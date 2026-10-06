-- Prüfstand: Wurm-Tests T5, T6, T7 (Vertrag siehe runner.lua, Design 4.3 und 8).
-- T5 Wurm-KI: a) investigating zu einem Punkt 20 Kacheln hinter einem Ernter, b) attacking auf einen Ernter,
--    c) Drosselung per speed, d) Flieger 3 s über dem Kopf (Gesundheit, Sticker, Tempo danach).
-- T6 Fels-Ebene und Wächter: vier Bahnen mit Felsinsel (ohne Ebene, mit Ebene arrakis_rock, mit Mini-Wächter,
--    Angriff auf einen Ernter vor dem Felsrand).
-- T7 Körperprüfung (jeder vierte Körperknoten auf Fels?) und, nur mit "/arrakis-test T7 ja", extended = false.
--    T7 hat kein confirm: Teil a läuft immer (auch bei „alle“), Teil b nur mit Argument "ja".
-- Zustand nur in run.data: Zahlen, Texte, Positionen {x, y}, LuaEntity- und LuaSegmentedUnit-Referenzen
-- (vor jeder Benutzung auf valid prüfen). Alle Würmer stehen in run.data.worms und werden am Ende zerstört.

local WORM = "arrakis-test-worm"
local WORM_ROCKMASK = "arrakis-test-worm-rockmask"
local HARVESTER = "arrakis-test-harvester"
local FLYER_4 = "arrakis-test-flyer-4"
local ROCK = "arrakis-rock"
local FLYER_FUEL = "rocket-fuel"
local FLYER_FUEL_COUNT = 5
local SAND = {["sand-1"] = true, ["sand-2"] = true, ["sand-3"] = true}
-- Biss-Reichweite: Kopf näher als 3 Kacheln plus Zielradius (Design 4.3, BISS).
local REACH = 3

-- Hilfen ------------------------------------------------------------------------------------

local function valid(object)
  return object ~= nil and object.valid
end

-- Ruft fn geschützt auf. Bei Fehler: Zeile mit level (Standard FEHLER) ins Protokoll.
local function guarded(run, tb, what, fn, level)
  local ok, result = pcall(fn)
  if not ok then
    tb.log(run, level or "FEHLER", what .. " ging nicht: " .. tostring(result))
  end
  return ok, result
end

-- Liest einen Wert; Fehler werden zu nil.
local function read(fn)
  local ok, value = pcall(fn)
  if ok then return value end
  return nil
end

-- Messzeile im Takt (jede Sekunde, Umwege): nur in die Datei, wenn der Runner tb.trace anbietet, sonst normal.
local function trace(run, tb, text)
  if tb.trace then
    tb.trace(run, text)
  else
    tb.log(run, "MESSUNG", text)
  end
end

local function at(origin, dx, dy)
  return {x = origin.x + dx, y = origin.y + dy}
end

local function copy_position(position)
  return {x = position.x, y = position.y}
end

local function pos_text(tb, position)
  if not position then return "–" end
  return "(" .. tb.num(position.x) .. ", " .. tb.num(position.y) .. ")"
end

local function count_up(counts, key)
  counts[key] = (counts[key] or 0) + 1
end

-- {investigating = 3, patrolling = 2} → "investigating 3×, patrolling 2×"
local function counts_text(counts)
  local keys = {}
  for key in pairs(counts or {}) do table.insert(keys, key) end
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do table.insert(parts, key .. " " .. counts[key] .. "×") end
  if #parts == 0 then return "–" end
  return table.concat(parts, ", ")
end

-- Spielfigur unverwundbar machen (tb.unprotect läuft bei jedem Testende) und zum Zuschauen hinbringen.
local function protect_and_watch(run, tb, position)
  local player = tb.player(run)
  if not player then
    tb.log(run, "INFO", "Kein Spieler gefunden; der Test läuft ohne Zuschauer")
    return
  end
  local ok, protected = guarded(run, tb, "Spielfigur schützen", function()
    return tb.protect(run, player)
  end)
  if ok and not protected then
    tb.log(run, "INFO", "Keine Spielfigur zum Schützen (z. B. Editor oder Fernansicht)")
  end
  local ok_watch, moved = guarded(run, tb, "Spieler zum Testbereich bringen", function()
    return tb.watch(run, player, position)
  end, "INFO")
  if ok_watch and not moved then
    tb.log(run, "INFO", "Teleport zum Testbereich ging nicht; /arrakis-test zurück bringt dich zurück, falls nötig")
  end
end

-- Entities ------------------------------------------------------------------------------------

local function player_force(run, tb)
  local player = tb.player(run)
  return player and player.force or "player"
end

-- Merkt eine Entity für on_entity_died vor (Meldung mit Bezeichnung).
local function watch_death(run, entity, label)
  local number = entity.unit_number
  if not number then return end
  run.data.watched = run.data.watched or {}
  run.data.watched[number] = label
end

local function death_of(run, number)
  return number and run.data.deaths and run.data.deaths[number] or nil
end

local function create_entity(run, tb, label, params)
  local ok, entity = guarded(run, tb, label .. " erzeugen", function()
    return tb.surface().create_entity(params)
  end)
  if ok and valid(entity) then return entity end
  if ok then tb.log(run, "FEHLER", label .. " wurde nicht erzeugt (create_entity gab nil)") end
  return nil
end

local function create_harvester(run, tb, position, label)
  local entity = create_entity(run, tb, label, {name = HARVESTER, position = position, force = player_force(run, tb),
    create_build_effect_smoke = false})
  if entity then watch_death(run, entity, label) end
  return entity
end

local function create_flyer(run, tb, position, label)
  local entity = create_entity(run, tb, label, {name = FLYER_4, position = position, force = player_force(run, tb),
    create_build_effect_smoke = false})
  if not entity then return nil end
  watch_death(run, entity, label)
  local ok, inserted = guarded(run, tb, label .. ": Treibstoff einlegen", function()
    return tb.fuel(entity, FLYER_FUEL, FLYER_FUEL_COUNT)
  end)
  if ok and (inserted or 0) < FLYER_FUEL_COUNT then
    tb.log(run, "FEHLER", string.format("%s: nur %s von %d %s eingelegt", label, tostring(inserted), FLYER_FUEL_COUNT,
      FLYER_FUEL))
  end
  return entity
end

local function health_of(entity)
  if not valid(entity) then return nil end
  local health = read(function() return entity.health end)
  if type(health) == "number" then return health end
  return nil
end

local function health_text(tb, entity)
  if not valid(entity) then return "zerstört" end
  return tb.num(health_of(entity))
end

-- Namen der Sticker an einer Entity (nil, wenn nicht lesbar).
local function sticker_names(entity)
  if not valid(entity) then return nil end
  local ok, stickers = pcall(function() return entity.stickers end)
  if not ok then return nil end
  local names = {}
  for _, sticker in pairs(stickers or {}) do
    if valid(sticker) then table.insert(names, sticker.name) end
  end
  return names
end

local function sticker_count(entity)
  local names = sticker_names(entity)
  return names and #names or nil
end

-- Radius aus der BoundingBox (für die Biss-Reichweite).
local function entity_radius(entity)
  local radius = read(function()
    local box, position = entity.bounding_box, entity.position
    return math.max(position.x - box.left_top.x, position.y - box.left_top.y,
      box.right_bottom.x - position.x, box.right_bottom.y - position.y)
  end)
  if type(radius) == "number" then return radius end
  return 1.5
end

-- Würmer --------------------------------------------------------------------------------------

-- Wurm erzeugen (Variante position-and-direction). Gibt die Einheit oder nil zurück (Fehler gemeldet).
local function create_worm(run, tb, name, position, direction, extended)
  local surface = tb.surface()
  local ok, unit = guarded(run, tb, "create_segmented_unit " .. name, function()
    return surface.create_segmented_unit{name = name, position = position, direction = direction,
      force = tb.worm_force(), extended = extended}
  end)
  if not ok then return nil end
  if not valid(unit) then
    tb.log(run, "FEHLER", "create_segmented_unit " .. name .. " gab nil zurück (Kopf " .. pos_text(tb, position) .. ")")
    return nil
  end
  run.data.worms = run.data.worms or {}
  table.insert(run.data.worms, unit)
  return unit
end

local function destroy_worm(unit)
  if valid(unit) then
    pcall(function() unit.destroy({raise_destroy = false}) end)
  end
end

local function destroy_all_worms(run)
  for _, unit in pairs(run.data.worms or {}) do
    destroy_worm(unit)
  end
  run.data.worms = {}
end

-- Körperknoten (Kopie, vorne zuerst) oder nil.
local function body_nodes(unit)
  if not valid(unit) then return nil end
  local ok, nodes = pcall(function() return unit.get_body_nodes() end)
  if ok and type(nodes) == "table" and nodes[1] then return nodes end
  return nil
end

-- Kopfposition = erster Körperknoten; dazu alle Knoten.
local function head_of(unit)
  local nodes = body_nodes(unit)
  if not nodes then return nil, nil end
  return copy_position(nodes[1]), nodes
end

-- KI-Zustand als Name plus Rohdaten (nil, wenn nicht lesbar).
local function ai_state(tb, unit)
  if not valid(unit) then return "ungültig", nil end
  local ok, state = pcall(function() return unit.get_ai_state() end)
  if not ok then return "Fehler: " .. tostring(state), nil end
  if type(state) ~= "table" then return "–", nil end
  return tb.enum_name(defines.segmented_unit_ai_state, state.type), state
end

local function activity_mode(tb, unit)
  if not valid(unit) then return "ungültig" end
  local ok, mode = pcall(function() return unit.activity_mode end)
  if not ok then return "Fehler" end
  return tb.enum_name(defines.segmented_unit_activity_mode, mode)
end

local function set_activity(run, tb, unit, mode_name)
  return guarded(run, tb, "minimum_activity_mode = " .. mode_name, function()
    unit.minimum_activity_mode = defines.segmented_unit_activity_mode[mode_name]
  end)
end

local function investigate(run, tb, unit, destination, what)
  local ok = guarded(run, tb, "set_ai_state investigating (" .. what .. ")", function()
    unit.set_ai_state{type = defines.segmented_unit_ai_state.investigating, destination = destination}
  end)
  return ok
end

local function attack(run, tb, unit, target, what)
  local ok = guarded(run, tb, "set_ai_state attacking (" .. what .. ")", function()
    unit.set_ai_state{type = defines.segmented_unit_ai_state.attacking, target = target}
  end)
  return ok
end

-- Hält der Zustand die Entity als Angriffsziel?
local function holds_target(state, entity)
  if not (state and valid(entity)) then return false end
  if state.type ~= defines.segmented_unit_ai_state.attacking then return false end
  local target = state.target
  return valid(target) and target.unit_number == entity.unit_number
end

-- Halbe Kantenlänge der Kollisionsbox des Kopfes (kleiner Demolisher: 1,5).
local function head_half_size(unit)
  local half = read(function()
    local box = unit.prototype.collision_box
    return math.max(-box.left_top.x, -box.left_top.y, box.right_bottom.x, box.right_bottom.y)
  end)
  if type(half) == "number" and half > 0 then return half end
  return 1.5
end

-- Kacheln ---------------------------------------------------------------------------------------

local function rock_test(tb, surface, position)
  return tb.on_rock(surface, position)
end

local function not_sand_test(tb, surface, position)
  return not SAND[tb.tiles_name(surface, position)]
end

-- Trifft test auf der Strecke from → to zu? Prüfpunkte alle step Kacheln, ohne from, mit to.
local function line_hits(tb, surface, from, to, step, test)
  local dx, dy = to.x - from.x, to.y - from.y
  local count = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / step))
  for i = 1, count do
    local f = i / count
    if test(tb, surface, {x = from.x + dx * f, y = from.y + dy * f}) then return true end
  end
  return false
end

-- Berührt die Box (Mitte, halbe Kantenlänge) eine Felskachel?
local function touches_rock(surface, center, half)
  local count = read(function()
    return surface.count_tiles_filtered{area = {{center.x - half, center.y - half}, {center.x + half, center.y + half}},
      name = ROCK, limit = 1}
  end)
  return type(count) == "number" and count > 0
end

-- Ereignisse (alle drei Tests) ----------------------------------------------------------------

local function on_event(run, tb, name, event)
  if name ~= "entity_died" then return end
  local entity = event.entity
  if not valid(entity) then return end
  local number = entity.unit_number
  local label = number and run.data.watched and run.data.watched[number]
  if not label then return end
  local cause_name = valid(event.cause) and event.cause.name or "–"
  run.data.deaths = run.data.deaths or {}
  run.data.deaths[number] = {tick = event.tick, cause = cause_name}
  tb.log(run, "MESSUNG", string.format("%s zerstört nach %s s Testzeit (Ursache: %s)", label, tb.num(tb.elapsed(run)),
    cause_name))
end

local function cleanup(run, tb)
  destroy_all_worms(run)
end

-- T5 Wurm-KI ------------------------------------------------------------------------------------

-- Vier Bahnen in x-Richtung (Kopf startet bei x = -150 mit Blick nach Osten), y relativ zum Bereichsursprung.
-- Die Teile laufen nacheinander; jeder Wurm wird am Ende seines Teils zerstört.
local T5_HALF = {x = 200, y = 100}       -- Sandbereich 400 × 200
local T5_START_X = -150
local T5_LANE = {a = -75, b = -45, c = -15, d = 15}
local T5_WATCH = {x = -100, y = 45}      -- südlich aller Bahnen, außerhalb der Wurmwege
local T5_ORDER = {"a", "b", "c", "d"}
local T5_SAMPLE = 10                     -- Ticks je Messpunkt
local T5_LOG = 60                        -- Ticks je Protokollzeile (jede Sekunde)
local T5_A_DISTANCE = 120                -- Ziel: 20 Kacheln hinter dem Ernter
local T5_A_HARVESTER = 100
local T5_A_LIMIT = 40 * 60               -- Zeit bis zur Ankunft
local T5_A_AFTER = 5 * 60                -- Beobachtung nach der Ankunft
local T5_ARRIVE = 4                      -- Kacheln vom Ziel gelten als angekommen
local T5_B_HARVESTER = 60
local T5_B_LIMIT = 30 * 60
local T5_FAR_X = 180                     -- fernes Ziel für c und d (wird nicht erreicht)
local T5_C_FREE = 8 * 60                 -- Anfahrt ohne Eingriff
local T5_C_THROTTLE = 5 * 60
local T5_C_RELEASE = 5 * 60
local T5_C_SPEED = 1 / 60                -- 1 Kachel/s in Kacheln je Tick
local T5_D_WAIT = 5 * 60                 -- Wurm kommt in Fahrt
local T5_D_HOVER = 3 * 60
local T5_D_FLIGHT = 5 * 60
local T5_D_FLIGHT_DISTANCE = 50          -- Flugziel nach dem Schweben: 50 Kacheln nach Norden

local t5 = {}

-- Wurm verschwunden: Teil endet (Auswertung mit dem, was da ist).
local function t5_lost(run, tb, key, p)
  if not p.lost then
    p.lost = true
    tb.log(run, "FEHLER", key .. ") Wurm ist verschwunden (ungültig)")
  end
  return true
end

-- a) investigating ---------------------------------------------------------------

function t5.a_start(run, tb, p)
  local o = run.data.o
  local y = T5_LANE.a
  local harvester = create_harvester(run, tb, at(o, T5_START_X + T5_A_HARVESTER, y), "a) Ernter")
  p.harvester = harvester
  p.harvester_number = harvester and harvester.unit_number
  p.health0 = health_of(harvester)
  p.target = at(o, T5_START_X + T5_A_DISTANCE, y)
  p.unit = create_worm(run, tb, WORM, at(o, T5_START_X, y), defines.direction.east, true)
  if not p.unit then return false end
  set_activity(run, tb, p.unit, "minimal")
  investigate(run, tb, p.unit, p.target, "Punkt hinter dem Ernter")
  local head = head_of(p.unit)
  p.last = head
  p.path = 0
  p.max_speed = 0
  p.min_dist = head and tb.distance(head, p.target) or nil
  p.states_before = {}
  p.states_after = {}
  p.modes = {}
  tb.log(run, "MESSUNG", string.format("a) investigating: Kopf %s, Ziel %s (%s Kacheln, 20 hinter dem Ernter), Zustand %s, activity_mode %s",
    pos_text(tb, head), pos_text(tb, p.target), tb.num(p.min_dist), (ai_state(tb, p.unit)), activity_mode(tb, p.unit)))
  return true
end

function t5.a_tick(run, tb, p, elapsed)
  local unit = p.unit
  if elapsed % T5_SAMPLE == 0 then
    local head = head_of(unit)
    if not head then return t5_lost(run, tb, "a", p) end
    if p.last then p.path = p.path + tb.distance(p.last, head) end
    p.last = head
    local dist = tb.distance(head, p.target)
    p.min_dist = math.min(p.min_dist or dist, dist)
    p.max_speed = math.max(p.max_speed, tb.speed_tps(unit) or 0)
    if not p.arrived and dist <= T5_ARRIVE then
      p.arrived = elapsed
      p.arrive_path = p.path
      tb.log(run, "MESSUNG", string.format("a) angekommen nach %s s (Abstand %s Kacheln); beobachte noch 5 s",
        tb.num(elapsed / 60), tb.num(dist)))
    end
  end
  if elapsed % T5_LOG == 0 and p.last then
    local name = ai_state(tb, unit)
    local mode = activity_mode(tb, unit)
    count_up(p.arrived and p.states_after or p.states_before, name)
    count_up(p.modes, mode)
    trace(run, tb, string.format("a) %s s: Kopf %s, Abstand %s, Zustand %s, Tempo %s Kacheln/s, activity_mode %s",
      tb.num(elapsed / 60), pos_text(tb, p.last), tb.num(tb.distance(p.last, p.target)), name,
      tb.num(tb.speed_tps(unit)), mode))
  end
  if p.arrived then return elapsed - p.arrived >= T5_A_AFTER end
  return elapsed >= T5_A_LIMIT
end

function t5.a_done(run, tb, p)
  local summary
  if p.arrived then
    local t = p.arrived / 60
    tb.log(run, "MESSUNG", string.format("a) Ankunft (≤ %d Kacheln) nach %s s; Durchschnittstempo %s Kacheln/s (Weg %s Kacheln), Höchsttempo %s Kacheln/s",
      T5_ARRIVE, tb.num(t), tb.num(p.arrive_path / math.max(t, 1 / 60)), tb.num(p.arrive_path), tb.num(p.max_speed)))
    tb.log(run, "MESSUNG", string.format("a) Zustand nach der Ankunft (5 s beobachtet): %s; am Ende %s, Tempo %s Kacheln/s",
      counts_text(p.states_after), (ai_state(tb, p.unit)), tb.num(tb.speed_tps(p.unit))))
    summary = "a Ankunft " .. tb.num(t) .. " s"
  else
    local t = math.max((game.tick - p.tick0) / 60, 1 / 60)
    tb.log(run, "MESSUNG", string.format("a) keine Ankunft in %s s: kleinster Abstand %s Kacheln, Durchschnittstempo %s Kacheln/s (Weg %s Kacheln), Höchsttempo %s Kacheln/s",
      tb.num(t), tb.num(p.min_dist), tb.num(p.path / t), tb.num(p.path), tb.num(p.max_speed)))
    summary = "a keine Ankunft (min. " .. tb.num(p.min_dist) .. " Kacheln)"
  end
  tb.log(run, "MESSUNG", "a) Zustände bis zur Ankunft (vision_distance 0, Ernter im Weg): " .. counts_text(p.states_before))
  tb.log(run, "MESSUNG", "a) activity_mode (Minimum minimal gesetzt): " .. counts_text(p.modes))
  local death = death_of(run, p.harvester_number)
  if death then
    tb.log(run, "MESSUNG", string.format("a) Ernter im Weg: zerstört nach %s s (Ursache: %s)",
      tb.num((death.tick - p.tick0) / 60), death.cause))
  else
    tb.log(run, "MESSUNG", "a) Ernter im Weg: Gesundheit " .. tb.num(p.health0) .. " → " .. health_text(tb, p.harvester))
  end
  return summary
end

-- b) attacking -------------------------------------------------------------------

function t5.b_start(run, tb, p)
  local o = run.data.o
  local y = T5_LANE.b
  local harvester = create_harvester(run, tb, at(o, T5_START_X + T5_B_HARVESTER, y), "b) Ernter")
  if not harvester then return false end
  p.harvester = harvester
  p.harvester_number = harvester.unit_number
  p.health0 = health_of(harvester)
  p.reach = REACH + entity_radius(harvester)
  p.unit = create_worm(run, tb, WORM, at(o, T5_START_X, y), defines.direction.east, true)
  if not p.unit then return false end
  set_activity(run, tb, p.unit, "full")
  p.set_ok = attack(run, tb, p.unit, harvester, "Ernter")
  p.held = 0
  p.samples = 0
  p.states = {}
  p.modes = {}
  local head = head_of(p.unit)
  p.last = head
  p.min_dist = head and tb.distance(head, harvester.position) or nil
  local name, state = ai_state(tb, p.unit)
  tb.log(run, "MESSUNG", string.format("b) attacking: Kopf %s, Ernter %s (%s Kacheln), set_ai_state %s, Zustand jetzt %s (Ziel Ernter: %s), activity_mode %s",
    pos_text(tb, head), pos_text(tb, harvester.position), tb.num(p.min_dist), p.set_ok and "ok" or "Fehler",
    name, holds_target(state, harvester) and "ja" or "nein", activity_mode(tb, p.unit)))
  return true
end

function t5.b_tick(run, tb, p, elapsed)
  local unit = p.unit
  if elapsed % T5_SAMPLE == 0 then
    local head = head_of(unit)
    if not head then return t5_lost(run, tb, "b", p) end
    p.last = head
    if valid(p.harvester) then
      local dist = tb.distance(head, p.harvester.position)
      p.min_dist = math.min(p.min_dist or dist, dist)
      if not p.reached and dist <= p.reach then
        p.reached = elapsed
        tb.log(run, "MESSUNG", string.format("b) Kopf erreicht den Ernter nach %s s (Abstand %s Kacheln)",
          tb.num(elapsed / 60), tb.num(dist)))
      end
    end
  end
  if elapsed % T5_LOG == 0 and p.last then
    local name, state = ai_state(tb, unit)
    local holds = holds_target(state, p.harvester)
    -- Nur zählen, solange der Ernter steht (danach kann die KI kein Ziel mehr halten).
    if valid(p.harvester) then
      p.samples = p.samples + 1
      if holds then p.held = p.held + 1 end
    end
    count_up(p.states, name)
    local mode = activity_mode(tb, unit)
    count_up(p.modes, mode)
    local dist = valid(p.harvester) and tb.distance(p.last, p.harvester.position) or nil
    trace(run, tb, string.format("b) %s s: Abstand Kopf→Ernter %s, Ernter-Gesundheit %s, Zustand %s (Ziel Ernter: %s), Tempo %s Kacheln/s, activity_mode %s",
      tb.num(elapsed / 60), tb.num(dist), health_text(tb, p.harvester), name, holds and "ja" or "nein",
      tb.num(tb.speed_tps(unit)), mode))
  end
  return elapsed >= T5_B_LIMIT
end

function t5.b_done(run, tb, p)
  tb.log(run, "MESSUNG", string.format("b) Ernter als Ziel gehalten: %d von %d Sekunden, solange er stand (set_ai_state %s); Zustände über 30 s: %s",
    p.held, p.samples, p.set_ok and "ok" or "Fehler", counts_text(p.states)))
  if p.reached then
    tb.log(run, "MESSUNG", string.format("b) Ernter erreicht: ja, nach %s s (Reichweite %s Kacheln = 3 + Zielradius)",
      tb.num(p.reached / 60), tb.num(p.reach)))
  else
    tb.log(run, "MESSUNG", string.format("b) Ernter erreicht: nein, kleinster Abstand %s Kacheln (Reichweite %s)",
      tb.num(p.min_dist), tb.num(p.reach)))
  end
  local death = death_of(run, p.harvester_number)
  if death then
    tb.log(run, "MESSUNG", string.format("b) Schaden: Ernter zerstört nach %s s (Ursache: %s), vorher %s",
      tb.num((death.tick - p.tick0) / 60), death.cause, tb.num(p.health0)))
  else
    local health = health_of(p.harvester)
    tb.log(run, "MESSUNG", string.format("b) Schaden: Ernter-Gesundheit %s → %s (%s)", tb.num(p.health0),
      health_text(tb, p.harvester), (p.health0 and health) and ("−" .. tb.num(p.health0 - health)) or "–"))
  end
  tb.log(run, "MESSUNG", "b) activity_mode (Minimum full gesetzt): " .. counts_text(p.modes))
  return string.format("b Ziel %d/%d s, erreicht %s", p.held, p.samples, p.reached and "ja" or "nein")
end

-- c) Drosselung ------------------------------------------------------------------

function t5.c_start(run, tb, p)
  local o = run.data.o
  local y = T5_LANE.c
  p.unit = create_worm(run, tb, WORM, at(o, T5_START_X, y), defines.direction.east, true)
  if not p.unit then return false end
  set_activity(run, tb, p.unit, "minimal")
  p.target = at(o, T5_FAR_X, y)
  investigate(run, tb, p.unit, p.target, "fernes Ziel")
  p.last = head_of(p.unit)
  p.dist = {0, 0, 0}                     -- Weg je Abschnitt: frei, gedrosselt, wieder frei
  p.speed_sum = {0, 0, 0}
  p.speed_n = {0, 0, 0}
  p.throttle_errors = 0
  tb.log(run, "MESSUNG", "c) Drosselung: Wurm fährt 8 s frei an, dann 5 s lang alle 10 Ticks speed = 1 Kachel/s, dann 5 s frei")
  return true
end

function t5.c_tick(run, tb, p, elapsed)
  local unit = p.unit
  local throttle_end = T5_C_FREE + T5_C_THROTTLE
  if elapsed % T5_SAMPLE ~= 0 then return false end
  local head = head_of(unit)
  if not head then return t5_lost(run, tb, "c", p) end
  -- Abschnitt des Messintervalls (elapsed − 10, elapsed]
  local section = 3
  if elapsed <= T5_C_FREE then
    section = 1
  elseif elapsed <= throttle_end then
    section = 2
  end
  if p.last then p.dist[section] = p.dist[section] + tb.distance(p.last, head) end
  p.last = head
  -- Tempo vor dem Zurücksetzen: so weit hat die KI in 10 Ticks wieder beschleunigt.
  local speed = tb.speed_tps(unit) or 0
  p.speed_sum[section] = p.speed_sum[section] + speed
  p.speed_n[section] = p.speed_n[section] + 1
  if not p.speed_before and elapsed >= T5_C_FREE then p.speed_before = speed end
  if elapsed >= T5_C_FREE and elapsed < throttle_end then
    local ok, err = pcall(function() unit.speed = T5_C_SPEED end)
    if not ok then
      p.throttle_errors = p.throttle_errors + 1
      if p.throttle_errors == 1 then tb.log(run, "FEHLER", "c) speed setzen ging nicht: " .. tostring(err)) end
    end
  end
  return elapsed >= throttle_end + T5_C_RELEASE
end

function t5.c_done(run, tb, p)
  local function average(section)
    if p.speed_n[section] == 0 then return nil end
    return p.speed_sum[section] / p.speed_n[section]
  end
  local throttled = p.dist[2] / (T5_C_THROTTLE / 60)
  local released = p.dist[3] / (T5_C_RELEASE / 60)
  tb.log(run, "MESSUNG", string.format("c) vorher frei (8 s): Tempo am Ende %s Kacheln/s, Weg %s Kacheln",
    tb.num(p.speed_before), tb.num(p.dist[1])))
  tb.log(run, "MESSUNG", string.format("c) gedrosselt (5 s, alle 10 Ticks speed = 1 Kachel/s): tatsächlich %s Kacheln/s (Weg %s Kacheln), speed vor dem Zurücksetzen im Mittel %s Kacheln/s%s",
    tb.num(throttled), tb.num(p.dist[2]), tb.num(average(2)),
    p.throttle_errors > 0 and string.format(", %d Fehler beim Setzen", p.throttle_errors) or ""))
  tb.log(run, "MESSUNG", string.format("c) danach frei (5 s): %s Kacheln/s (Weg %s Kacheln), speed im Mittel %s, am Ende %s Kacheln/s; activity_mode %s (Minimum minimal)",
    tb.num(released), tb.num(p.dist[3]), tb.num(average(3)), tb.num(tb.speed_tps(p.unit)), activity_mode(tb, p.unit)))
  return "c gedrosselt " .. tb.num(throttled) .. ", frei " .. tb.num(released) .. " Kacheln/s"
end

-- d) Flieger über dem Kopf -------------------------------------------------------

-- Flieger losschicken: Ziel 50 Kacheln nördlich; Startpunkt für die Wegmessung merken.
local function t5_release(run, tb, flyer, label)
  if not valid(flyer) then return nil end
  local start = copy_position(flyer.position)
  guarded(run, tb, label .. ": autopilot_destination setzen", function()
    flyer.autopilot_destination = {x = start.x, y = start.y - T5_D_FLIGHT_DISTANCE}
  end)
  return start
end

function t5.d_start(run, tb, p)
  local o = run.data.o
  local y = T5_LANE.d
  p.unit = create_worm(run, tb, WORM, at(o, T5_START_X, y), defines.direction.east, true)
  if not p.unit then return false end
  set_activity(run, tb, p.unit, "minimal")
  investigate(run, tb, p.unit, at(o, T5_FAR_X, y), "fernes Ziel")
  p.flyer = create_flyer(run, tb, at(o, T5_START_X + 10, y + 12), "d) Flieger")
  if not p.flyer then return false end
  p.reference = create_flyer(run, tb, at(o, T5_START_X + 10, y - 20), "d) Vergleichsflieger")
  p.teleports = 0
  p.teleport_fails = 0
  p.max_stickers = 0
  p.flyer_max = 0
  p.reference_max = 0
  tb.log(run, "MESSUNG", "d) Flieger über dem Kopf: Wurm fährt 5 s an, dann 3 s lang Flieger -4 jeden Tick per teleport auf den Kopf; danach fliegen Flieger und Vergleichsflieger 5 s nach Norden")
  return true
end

function t5.d_tick(run, tb, p, elapsed)
  local hover_end = T5_D_WAIT + T5_D_HOVER
  if not p.hover_started and elapsed >= T5_D_WAIT then
    p.hover_started = true
    p.health0 = health_of(p.flyer)
    p.stickers0 = sticker_count(p.flyer)
    p.speed_worm = tb.speed_tps(p.unit)
    p.mode = activity_mode(tb, p.unit)
  end
  if p.hover_started and not p.released then
    local head = head_of(p.unit)
    if not head then return t5_lost(run, tb, "d", p) end
    if valid(p.flyer) then
      local ok, moved = pcall(function() return p.flyer.teleport(head) end)
      p.teleports = p.teleports + 1
      if not (ok and moved) then
        p.teleport_fails = p.teleport_fails + 1
        if p.teleport_fails == 1 then
          tb.log(run, "INFO", "d) teleport auf den Kopf ging nicht" .. (ok and " (false)" or (": " .. tostring(moved))))
        end
      end
      if elapsed % T5_SAMPLE == 0 then
        p.max_stickers = math.max(p.max_stickers, sticker_count(p.flyer) or 0)
      end
    end
  end
  if not p.released and elapsed >= hover_end then
    p.released = elapsed
    p.health1 = health_of(p.flyer)
    p.flyer_alive = valid(p.flyer)
    p.stickers1 = sticker_names(p.flyer)
    p.max_stickers = math.max(p.max_stickers, p.stickers1 and #p.stickers1 or 0)
    p.flyer_start = t5_release(run, tb, p.flyer, "d) Flieger")
    p.reference_start = t5_release(run, tb, p.reference, "d) Vergleichsflieger")
    return false
  end
  if p.released and elapsed % T5_SAMPLE == 0 then
    p.flyer_max = math.max(p.flyer_max, tb.speed_tps(p.flyer) or 0)
    p.reference_max = math.max(p.reference_max, tb.speed_tps(p.reference) or 0)
  end
  return p.released ~= nil and elapsed - p.released >= T5_D_FLIGHT
end

function t5.d_done(run, tb, p)
  local health_after = p.flyer_alive == false and "zerstört" or tb.num(p.health1)
  local names = p.stickers1 and (#p.stickers1 > 0 and (" (" .. table.concat(p.stickers1, ", ") .. ")") or "") or ""
  tb.log(run, "MESSUNG", string.format("d) Flieger 3 s über dem Kopf (Wurm %s Kacheln/s, activity_mode %s): teleport %d×, davon %d fehlgeschlagen; Gesundheit vorher %s, nachher %s",
    tb.num(p.speed_worm), p.mode or "–", p.teleports, p.teleport_fails, tb.num(p.health0), health_after))
  tb.log(run, "MESSUNG", string.format("d) Sticker am Flieger: vorher %s, höchstens %d während, danach %s%s (erwartet 0, Asche ist entfernt)",
    p.stickers0 and tostring(p.stickers0) or "–", p.max_stickers, p.stickers1 and tostring(#p.stickers1) or "–", names))
  local function flown(entity, start)
    if not (valid(entity) and start) then return nil end
    return tb.distance(start, entity.position)
  end
  local ratio = p.reference_max > 0 and (100 * p.flyer_max / p.reference_max) or nil
  tb.log(run, "MESSUNG", string.format("d) Tempo danach (5 s Richtung Norden): Flieger höchstens %s Kacheln/s (Weg %s), Vergleichsflieger %s Kacheln/s (Weg %s), Verhältnis %s %%",
    tb.num(p.flyer_max), tb.num(flown(p.flyer, p.flyer_start)), tb.num(p.reference_max),
    tb.num(flown(p.reference, p.reference_start)), tb.num(ratio, 0)))
  return string.format("d Sticker %d, Tempo %s %%", p.max_stickers, tb.num(ratio, 0))
end

-- Ablauf T5 ------------------------------------------------------------------------

local function t5_finish(run, tb)
  destroy_all_worms(run)
  tb.finish(run, table.concat(run.data.summary, "; "))
end

-- Wertet den laufenden Teil aus, räumt seinen Wurm weg und startet den nächsten.
local function t5_next(run, tb)
  local data = run.data
  local key = T5_ORDER[data.phase]
  if key then
    local p = data[key]
    local ok, summary = guarded(run, tb, key .. ") Auswertung", function()
      return t5[key .. "_done"](run, tb, p)
    end)
    table.insert(data.summary, ok and summary or (key .. " Auswertung fehlgeschlagen"))
    destroy_worm(p.unit)
  end
  while true do
    data.phase = data.phase + 1
    key = T5_ORDER[data.phase]
    if not key then
      t5_finish(run, tb)
      return
    end
    local p = {tick0 = game.tick}
    data[key] = p
    if t5[key .. "_start"](run, tb, p) then return end
    destroy_worm(p.unit)
    table.insert(data.summary, key .. " übersprungen")
    tb.log(run, "FEHLER", key .. ") übersprungen: Aufbau ging nicht")
  end
end

local function t5_start(run, tb)
  local data = run.data
  local origin = tb.area(run.id)
  data.o = {x = origin.x, y = origin.y}
  data.summary = {}
  data.worms = {}
  tb.prepare(data.o, T5_HALF)
  protect_and_watch(run, tb, at(data.o, T5_WATCH.x, T5_WATCH.y))
  tb.log(run, "INFO", "Vier Teile nacheinander auf Bahnen von Nord nach Süd (du stehst südlich davon): a) investigating, b) attacking, c) Drosselung, d) Flieger über dem Kopf. Dauer etwa 110 s.")
  tb.log(run, "FRAGE", "Bitte zuschauen (herauszoomen): Ziehen die Würmer Ascheschwaden oder dunkle Spuren hinter sich her (sollten fehlen)? Sind sie sandfarben? Melde es, gern mit Screenshot.")
  data.phase = 0
  t5_next(run, tb)
end

local function t5_tick(run, tb)
  local data = run.data
  local key = T5_ORDER[data.phase]
  if not key then return end
  local p = data[key]
  local done = p.lost or t5[key .. "_tick"](run, tb, p, game.tick - p.tick0)
  if done then t5_next(run, tb) end
end

-- T6 Fels-Ebene und Wächter --------------------------------------------------------------------

-- Bahnen in x-Richtung von x = 0 (Start) nach x = 200 (Ziel), y relativ zum Bereichsursprung, 80 Kacheln Abstand.
-- Jede Bahn hat eine Felsinsel 40 × 40 in der Mitte (x 80…120). Alle Bahnen laufen gleichzeitig.
local T6_LANES =
{
  {key = "A", y = -120, worm = WORM, guard = false, text = "ohne Wächter"},
  {key = "B", y = -40, worm = WORM_ROCKMASK, guard = false, text = "Felsmaske, ohne Wächter"},
  {key = "C", y = 40, worm = WORM, guard = true, text = "mit Wächter"},
  {key = "D", y = 120, worm = WORM, guard = true, attack = true, text = "Angriff auf Ernter vor dem Fels, mit Wächter"}
}
local T6_START_X = 0
local T6_TARGET_X = 200
local T6_ISLAND_X1, T6_ISLAND_X2 = 80, 120
local T6_ISLAND_HALF_Y = 20
local T6_HARVESTER_X = 70                -- 10 Kacheln vor dem Felsrand (Sandseite)
local T6_CENTER = {x = 100, y = 0}
local T6_HALF = {x = 160, y = 170}
local T6_WATCH = {x = 100, y = 0}        -- zwischen Bahn B und C, je 20 Kacheln neben den Inseln
local T6_SAMPLE = 10                     -- Messpunkt und Wächter alle 10 Ticks
local T6_STATE_TICKS = 30                -- Zustand nachführen wie im Design (alle 30 Ticks)
local T6_LOOKAHEAD = 18                  -- 2 × Wenderadius (6) + 6
local T6_LOOK_STEP = 2
local T6_DETOUR = 30
local T6_DETOUR_STEP = 4                 -- Sandlinie zum Wegpunkt: get_tile alle 4 Kacheln
local T6_DETOUR_ANGLES = {30, -30, 60, -60, 90, -90}
local T6_DETOUR_REACHED = 10             -- danach wieder Richtung Ziel
local T6_DETOUR_MAX = 15 * 60
local T6_ARRIVE = 4
local T6_STALL_TICKS = 5 * 60            -- Stillstand: > 5 s ohne 0,5 Kacheln Bewegung
local T6_STALL_DISTANCE = 0.5
local T6_D_AFTER_REACH = 10 * 60         -- Bahn D: so lange nach dem Erreichen weiter beobachten
local T6_D_AFTER_DEATH = 5 * 60
local T6_DEADLINE = 110 * 60             -- Auswertung vor dem Zeitlimit (120 s) des Runners

local function rotate(v, degrees)
  local a = math.rad(degrees)
  local c, s = math.cos(a), math.sin(a)
  return {x = v.x * c - v.y * s, y = v.x * s + v.y * c}
end

-- Kopfrichtung aus Knoten 1 und 3 (Design 4.3, Fels-Wächter); nil, wenn zu wenig Knoten.
local function heading(nodes)
  local front, back = nodes[1], nodes[3] or nodes[2]
  if not (front and back) then return nil end
  local dx, dy = front.x - back.x, front.y - back.y
  local length = math.sqrt(dx * dx + dy * dy)
  if length < 0.01 then return nil end
  return {x = dx / length, y = dy / length}
end

-- Soll-Zustand der Bahn: Umweg-Wegpunkt, Angriff auf den Ernter oder Ziel. nil: nichts mehr zu tun.
local function t6_wanted(lane)
  local investigating = defines.segmented_unit_ai_state.investigating
  if lane.detour then return {type = investigating, destination = lane.detour} end
  if lane.attack then
    if not valid(lane.harvester) then return nil end
    if lane.attack_ok then
      return {type = defines.segmented_unit_ai_state.attacking, target = lane.harvester}
    end
    return {type = investigating, destination = lane.harvester_pos}
  end
  return {type = investigating, destination = lane.target}
end

-- set_ai_state für eine Bahn; nur der erste Fehler je Bahn wird gemeldet.
local function t6_set(run, tb, lane, state)
  local ok, err = pcall(function() lane.unit.set_ai_state(state) end)
  if not ok then
    lane.state_errors = lane.state_errors + 1
    if lane.state_errors == 1 then
      tb.log(run, "FEHLER", "Bahn " .. lane.key .. ": set_ai_state ging nicht: " .. tostring(err))
    end
  end
  return ok
end

-- Alle 30 Ticks: hat die KI den Zustand verlassen, wird er neu gesetzt (gezählt).
local function t6_reassert(run, tb, lane)
  local wanted = t6_wanted(lane)
  if not wanted then return end
  local _, state = ai_state(tb, lane.unit)
  if state and state.type == wanted.type then return end
  lane.reasserts = lane.reasserts + 1
  t6_set(run, tb, lane, wanted)
end

local function t6_lane_start(run, tb, def)
  local o = run.data.o
  local lane =
  {
    key = def.key, text = def.text, guard = def.guard, attack = def.attack,
    y = o.y + def.y, target = at(o, T6_TARGET_X, def.y),
    samples = 0, rock = 0, touch = 0, after = {samples = 0, rock = 0, touch = 0}, max_dev = 0, stalls = 0, stall_ticks = 0,
    detours = 0, no_detour = 0, reasserts = 0, state_errors = 0, guard_errors = 0, modes = {}
  }
  if def.attack then
    local harvester = create_harvester(run, tb, at(o, T6_HARVESTER_X, def.y), "Bahn D: Ernter")
    if not harvester then
      lane.done = true
      return lane
    end
    lane.harvester = harvester
    lane.harvester_number = harvester.unit_number
    lane.harvester_pos = copy_position(harvester.position)
    lane.health0 = health_of(harvester)
    lane.reach = REACH + entity_radius(harvester)
  end
  lane.unit = create_worm(run, tb, def.worm, at(o, T6_START_X, def.y), defines.direction.east, true)
  if not lane.unit then
    lane.done = true
    return lane
  end
  lane.half = head_half_size(lane.unit)
  set_activity(run, tb, lane.unit, def.attack and "full" or "minimal")
  if def.attack then
    lane.attack_ok = attack(run, tb, lane.unit, lane.harvester, "Bahn D")
    if not lane.attack_ok then
      tb.log(run, "INFO", "Bahn D: Ersatz investigating zum Ernter")
      investigate(run, tb, lane.unit, lane.harvester_pos, "Bahn D")
    end
  else
    investigate(run, tb, lane.unit, lane.target, "Bahn " .. def.key)
  end
  local head = head_of(lane.unit)
  lane.move_pos = head or at(o, T6_START_X, def.y)
  lane.move_tick = game.tick
  return lane
end

-- Neuen Wegpunkt suchen: ±30°, ±60°, ±90° gedreht, 30 Kacheln weit, gerade Linie auf Sand.
local function t6_find_detour(tb, surface, head, dir)
  for _, degrees in ipairs(T6_DETOUR_ANGLES) do
    local d = rotate(dir, degrees)
    local point = {x = head.x + d.x * T6_DETOUR, y = head.y + d.y * T6_DETOUR}
    if not line_hits(tb, surface, head, point, T6_DETOUR_STEP, not_sand_test) then
      return point, degrees
    end
  end
  return nil, nil
end

-- Mini-Wächter (alle 10 Ticks). Anfahrt: Vorausschau 18 Kacheln in Kopfrichtung (Kopfrichtung aus Knoten 1 und 3).
-- Angriff: nur die Strecke Kopf → Ziel, nie darüber hinaus. Liegt dort Fels: Umweg, danach wieder zum Ziel.
-- Während eines Umwegs wird nur die Strecke Kopf → Wegpunkt geprüft (der Kopf dreht noch).
local function t6_guard(run, tb, lane, head, nodes, tick)
  local surface = tb.surface()
  if lane.detour then
    if tb.distance(head, lane.detour) <= T6_DETOUR_REACHED or tick - lane.detour_tick >= T6_DETOUR_MAX then
      lane.detour = nil
      local wanted = t6_wanted(lane)
      if wanted then t6_set(run, tb, lane, wanted) end
    elseif not line_hits(tb, surface, head, lane.detour, T6_LOOK_STEP, rock_test) then
      return
    end
  end
  local dir = heading(nodes)
  if not dir then return end
  local blocked = lane.detour ~= nil
  if not blocked then
    if lane.attack then
      if not valid(lane.harvester) then return end
      blocked = line_hits(tb, surface, head, lane.harvester.position, T6_LOOK_STEP, rock_test)
    else
      local ahead = {x = head.x + dir.x * T6_LOOKAHEAD, y = head.y + dir.y * T6_LOOKAHEAD}
      blocked = line_hits(tb, surface, head, ahead, T6_LOOK_STEP, rock_test)
    end
  end
  if not blocked then return end
  local point, degrees = t6_find_detour(tb, surface, head, dir)
  if not point then
    lane.no_detour = lane.no_detour + 1
    return
  end
  lane.detour = point
  lane.detour_tick = tick
  lane.detours = lane.detours + 1
  t6_set(run, tb, lane, {type = defines.segmented_unit_ai_state.investigating, destination = point})
  trace(run, tb, string.format("Bahn %s: Umweg %+d° nach %s (Kopf %s, %s s)", lane.key, degrees, pos_text(tb, point),
    pos_text(tb, head), tb.num((tick - run.data.t0) / 60)))
end

-- Ein Messpunkt: Fels unter dem Kopf, Abweichung, Stillstand, Ankunft. Gibt Kopf und Knoten zurück.
local function t6_sample(run, tb, lane, tick)
  local surface = tb.surface()
  local head, nodes = head_of(lane.unit)
  if not head then
    lane.done = true
    lane.lost = true
    tb.log(run, "FEHLER", "Bahn " .. lane.key .. ": Wurm ist verschwunden")
    return nil, nil
  end
  local t = (tick - run.data.t0) / 60
  -- Bahn D: nach dem Biss (Kopf in Reichweite oder Ernter weg) taucht der Wurm im Spiel ab;
  -- was er danach im Test noch tut, wird getrennt gezählt und zählt nicht fürs Kriterium.
  local count = lane.bite and lane.after or lane
  count.samples = count.samples + 1
  if tb.on_rock(surface, head) then
    count.rock = count.rock + 1
    if not count.first_rock then
      count.first_rock = {x = head.x, y = head.y, t = t}
      trace(run, tb, string.format("Bahn %s: Kopf erstmals auf Fels bei %s nach %s s%s", lane.key, pos_text(tb, head),
        tb.num(t), lane.bite and " (nach dem Biss)" or ""))
    end
  end
  if touches_rock(surface, head, lane.half) then count.touch = count.touch + 1 end
  lane.max_dev = math.max(lane.max_dev, math.abs(head.y - lane.y))
  if tb.distance(head, lane.move_pos) >= T6_STALL_DISTANCE then
    lane.move_pos = head
    lane.move_tick = tick
    lane.stalled = false
  elseif tick - lane.move_tick > T6_STALL_TICKS then
    if not lane.stalled then
      lane.stalled = true
      lane.stalls = lane.stalls + 1
      lane.stall_first = lane.stall_first or {x = head.x, y = head.y, t = t}
      tb.log(run, "MESSUNG", string.format("Bahn %s: Stillstand (5 s ohne 0.5 Kacheln Bewegung) bei %s nach %s s",
        lane.key, pos_text(tb, head), tb.num(t)))
    end
    lane.stall_ticks = lane.stall_ticks + T6_SAMPLE
  end
  if lane.attack then
    if valid(lane.harvester) then
      local dist = tb.distance(head, lane.harvester.position)
      lane.min_dist = math.min(lane.min_dist or dist, dist)
      if not lane.reached and dist <= lane.reach then
        lane.reached = t
        lane.bite = lane.bite or t
        lane.end_tick = tick + T6_D_AFTER_REACH
        tb.log(run, "MESSUNG", string.format("Bahn D: Kopf erreicht den Ernter nach %s s (Abstand %s Kacheln)",
          tb.num(t), tb.num(dist)))
      end
    elseif not lane.harvester_gone then
      lane.harvester_gone = t
      lane.bite = lane.bite or t
      local limit = tick + T6_D_AFTER_DEATH
      lane.end_tick = lane.end_tick and math.min(lane.end_tick, limit) or limit
    end
    if lane.end_tick and tick >= lane.end_tick then lane.done = true end
  else
    local dist = tb.distance(head, lane.target)
    lane.min_dist = math.min(lane.min_dist or dist, dist)
    if dist <= T6_ARRIVE then
      lane.arrived = t
      lane.done = true
      tb.log(run, "MESSUNG", string.format("Bahn %s: angekommen nach %s s", lane.key, tb.num(t)))
    end
  end
  if lane.done then destroy_worm(lane.unit) end
  return head, nodes
end

local function t6_report(run, tb, lane)
  local name = "Bahn " .. lane.key .. " (" .. lane.text .. ")"
  if lane.samples == 0 and lane.after.samples == 0 then
    tb.log(run, "MESSUNG", name .. ": keine Messung (Aufbau ging nicht)")
    return lane.key .. " –"
  end
  local rock = string.format("Kopf auf Fels %d von %d Messpunkten (Kopfbox berührt Fels %d)", lane.rock, lane.samples, lane.touch)
  if lane.first_rock then
    rock = rock .. string.format(", zuerst bei %s nach %s s", pos_text(tb, lane.first_rock), tb.num(lane.first_rock.t))
  end
  if lane.attack then
    rock = "bis zum Biss " .. rock
    local after = lane.after
    if after.samples > 0 then
      rock = rock .. string.format("; nach dem Biss (im Spiel taucht der Wurm dann ab) Kopf auf Fels %d von %d (Kopfbox berührt Fels %d)",
        after.rock, after.samples, after.touch)
      if after.first_rock then
        rock = rock .. string.format(", zuerst bei %s nach %s s", pos_text(tb, after.first_rock), tb.num(after.first_rock.t))
      end
    end
  end
  tb.log(run, "MESSUNG", name .. ": " .. rock .. "; seitliche Abweichung höchstens " .. tb.num(lane.max_dev) .. " Kacheln")
  local parts = {}
  if lane.attack then
    table.insert(parts, string.format("kleinster Abstand Kopf→Ernter %s Kacheln (Reichweite %s), erreicht %s",
      tb.num(lane.min_dist), tb.num(lane.reach), lane.reached and ("ja nach " .. tb.num(lane.reached) .. " s") or "nein"))
    local death = death_of(run, lane.harvester_number)
    if death then
      table.insert(parts, string.format("Ernter zerstört nach %s s (Ursache: %s)", tb.num((death.tick - run.data.t0) / 60), death.cause))
    else
      table.insert(parts, "Ernter-Gesundheit " .. tb.num(lane.health0) .. " → " .. health_text(tb, lane.harvester))
    end
    table.insert(parts, "set_ai_state attacking " .. (lane.attack_ok and "ok" or "Fehler (Ersatz investigating)"))
  else
    table.insert(parts, lane.arrived and ("Ankunft ja nach " .. tb.num(lane.arrived) .. " s")
      or ("Ankunft nein (kleinster Abstand " .. tb.num(lane.min_dist) .. " Kacheln)"))
  end
  if lane.stalls > 0 then
    table.insert(parts, string.format("Stillstand ja (%d×, zusammen %s s, zuerst bei %s nach %s s)", lane.stalls,
      tb.num(lane.stall_ticks / 60), pos_text(tb, lane.stall_first), tb.num(lane.stall_first.t)))
  else
    table.insert(parts, "Stillstand nein")
  end
  if lane.guard then
    table.insert(parts, string.format("Umwege %d, kein Umweg gefunden %d×", lane.detours, lane.no_detour))
  end
  table.insert(parts, "Zustand nachgeführt " .. lane.reasserts .. "×")
  table.insert(parts, "activity_mode " .. counts_text(lane.modes))
  tb.log(run, "MESSUNG", name .. ": " .. table.concat(parts, "; "))
  local short = lane.key .. " Fels " .. lane.rock .. "×"
  if lane.stalls > 0 then short = short .. " Stillstand" end
  if not lane.attack then short = short .. (lane.arrived and " angekommen" or " nicht angekommen") end
  return short
end

local function t6_finish(run, tb)
  local data = run.data
  local parts = {}
  local by_key = {}
  for _, lane in ipairs(data.lanes) do
    by_key[lane.key] = lane
    local ok, short = guarded(run, tb, "Bahn " .. lane.key .. ": Auswertung", function()
      return t6_report(run, tb, lane)
    end)
    table.insert(parts, ok and short or (lane.key .. " ?"))
  end
  local c, d = by_key.C, by_key.D
  local verdict
  if not (c and d) or c.samples == 0 or d.samples == 0 then
    tb.log(run, "FEHLER", "Kriterium nicht prüfbar: Bahn C oder D ohne Messung")
    verdict = "Wächter nicht prüfbar"
  elseif c.rock == 0 and d.rock == 0 then
    tb.log(run, "OK", string.format("Kopf war auf Bahn C und D bis zum Biss nie auf Fels (Kopfbox berührte Fels: C %d×, D %d×)", c.touch, d.touch))
    verdict = "Wächter OK"
  else
    tb.log(run, "FEHLER", string.format("Kopf auf Fels: Bahn C %d×, Bahn D bis zum Biss %d× (Messpunkte alle 10 Ticks)", c.rock, d.rock))
    verdict = "Wächter FEHLER"
  end
  -- Bahn D nach dem Biss zählt nicht fürs Kriterium (im Spiel taucht der Wurm dann ab), soll aber sichtbar sein.
  if d and d.after.rock > 0 then
    tb.log(run, "INFO", string.format("Bahn D: nach dem Biss Kopf auf Fels %d von %d Messpunkten (nicht bewertet: im Spiel taucht der Wurm beim Biss ab)",
      d.after.rock, d.after.samples))
    verdict = verdict .. " (D nach dem Biss auf Fels)"
  end
  destroy_all_worms(run)
  tb.finish(run, table.concat(parts, ", ") .. "; " .. verdict)
end

local function t6_start(run, tb)
  local data = run.data
  local origin = tb.area(run.id)
  local o = {x = origin.x, y = origin.y}
  data.o = o
  data.worms = {}
  tb.prepare(at(o, T6_CENTER.x, T6_CENTER.y), T6_HALF)
  for _, def in ipairs(T6_LANES) do
    tb.fill({left_top = at(o, T6_ISLAND_X1, def.y - T6_ISLAND_HALF_Y), right_bottom = at(o, T6_ISLAND_X2, def.y + T6_ISLAND_HALF_Y)}, ROCK)
  end
  protect_and_watch(run, tb, at(o, T6_WATCH.x, T6_WATCH.y))
  tb.log(run, "INFO", "Vier Bahnen von Nord nach Süd, jede mit Felsinsel: A ohne Wächter, B mit Felsmaske, C mit Wächter, D Angriff auf einen Ernter vor dem Fels. Du stehst zwischen B und C.")
  tb.log(run, "FRAGE", "Schau auf Bahn B (nördlich von dir): Was macht der Wurm mit Felsmaske an der Felsinsel – hält er an, weicht er aus, flackert er oder fährt er durch? Und wirkt das Ausweichen auf Bahn C (südlich) glatt? Bitte melden, gern mit Screenshot.")
  data.t0 = game.tick
  data.lanes = {}
  for _, def in ipairs(T6_LANES) do
    table.insert(data.lanes, t6_lane_start(run, tb, def))
  end
end

local function t6_tick(run, tb)
  local data = run.data
  local tick = game.tick
  local elapsed = tick - data.t0
  if elapsed % T6_SAMPLE == 0 then
    for _, lane in ipairs(data.lanes) do
      if not lane.done then
        local head, nodes = t6_sample(run, tb, lane, tick)
        if head and lane.guard and not lane.done then
          local ok, err = pcall(t6_guard, run, tb, lane, head, nodes, tick)
          if not ok then
            lane.guard_errors = lane.guard_errors + 1
            if lane.guard_errors == 1 then
              tb.log(run, "FEHLER", "Bahn " .. lane.key .. ": Wächter ging nicht: " .. tostring(err))
            end
          end
        end
      end
    end
  end
  if elapsed % T6_STATE_TICKS == 0 then
    for _, lane in ipairs(data.lanes) do
      if not lane.done then t6_reassert(run, tb, lane) end
    end
  end
  if elapsed % 60 == 0 then
    for _, lane in ipairs(data.lanes) do
      if not lane.done then count_up(lane.modes, activity_mode(tb, lane.unit)) end
    end
  end
  local all_done = true
  for _, lane in ipairs(data.lanes) do
    if not lane.done then all_done = false end
  end
  if all_done or elapsed >= T6_DEADLINE then t6_finish(run, tb) end
end

-- T7 Körperprüfung und extended = false -------------------------------------------------------

local T7_HALF = {x = 100, y = 70}
local T7_HEAD_ROCK = {x = 0, y = -35}    -- Kopf auf Sand, 5 Kacheln vor dem Fels, Blick nach Osten (weg vom Fels)
local T7_ROCK_GAP = 5
local T7_ROCK_DEPTH = 70                 -- Fels westlich des Kopfes, länger als der Körper
local T7_ROCK_HALF_Y = 12
local T7_HEAD_SAND = {x = 0, y = 5}      -- Gegenprobe ganz auf Sand
local T7_HEAD_FREE = {x = -60, y = 45}   -- Teil b
local T7_FREE_TARGET = {x = 60, y = 45}
local T7_WATCH = {x = -20, y = 62}
local T7_CHECK_STEP = 4                  -- jeder vierte Knoten
local T7_WARN_DELAY = 2 * 60             -- Warnung steht in Chat und Datei, bevor es knallen kann
local T7_DRIVE = 10 * 60

-- Körperprüfung wie beim Spawn (Design 4.3): jeder vierte Knoten aus get_body_nodes() auf Fels?
local function t7_body_check(tb, surface, nodes)
  local result = {nodes = #nodes, checked = 0, hits = 0, all = 0}
  for i = 1, #nodes, T7_CHECK_STEP do
    result.checked = result.checked + 1
    if tb.on_rock(surface, nodes[i]) then
      result.hits = result.hits + 1
      result.first = result.first or i
    end
  end
  for _, node in ipairs(nodes) do
    if tb.on_rock(surface, node) then result.all = result.all + 1 end
  end
  return result
end

local function t7_check_text(tb, nodes, result)
  local text = string.format("jeder 4. Knoten: %d geprüft, %d auf Fels", result.checked, result.hits)
  if result.first then
    text = text .. string.format(" (erster Treffer Knoten %d, %s Kacheln hinter dem Kopf)", result.first,
      tb.num(tb.distance(nodes[1], nodes[result.first])))
  end
  return text .. string.format("; alle Knoten auf Fels: %d von %d", result.all, result.nodes)
end

-- Wurm mit extended = true erzeugen und sofort (im selben Tick) prüfen.
local function t7_spawn_check(run, tb, label, head_position, expect_rock)
  local surface = tb.surface()
  local check = {label = label, expect_rock = expect_rock}
  check.unit = create_worm(run, tb, WORM, head_position, defines.direction.east, true)
  if not check.unit then
    tb.log(run, "FEHLER", "a) " .. label .. ": kein Wurm, Prüfung nicht möglich")
    return check
  end
  local nodes = body_nodes(check.unit)
  if not nodes then
    tb.log(run, "FEHLER", "a) " .. label .. ": get_body_nodes ging nicht")
    return check
  end
  local result = t7_body_check(tb, surface, nodes)
  check.result = result
  local max_nodes = read(function() return check.unit.max_body_nodes end)
  tb.log(run, "MESSUNG", string.format("a) %s: %d Knoten (max_body_nodes %s), Körperlänge %s Kacheln, Kopf auf %s; %s",
    label, result.nodes, tostring(max_nodes), tb.num(tb.distance(nodes[1], nodes[#nodes])),
    tb.tiles_name(surface, nodes[1]), t7_check_text(tb, nodes, result)))
  if expect_rock then
    if result.hits > 0 then
      tb.log(run, "OK", "a) Körperprüfung erkennt den Fels hinter dem Kopf")
    else
      tb.log(run, "FEHLER", "a) Körperprüfung erkennt den Fels hinter dem Kopf nicht")
    end
  else
    if result.hits == 0 then
      tb.log(run, "OK", "a) Gegenprobe auf Sand: kein Fels erkannt")
    else
      tb.log(run, "FEHLER", "a) Gegenprobe auf Sand meldet Fels")
    end
  end
  return check
end

-- Einen Tick später noch einmal prüfen (falls der Körper erst nach dem Erzeugen liegt), dann zerstören.
local function t7_recheck(run, tb)
  local surface = tb.surface()
  for _, check in ipairs(run.data.checks) do
    local nodes = body_nodes(check.unit)
    if nodes then
      tb.log(run, "MESSUNG", "a) " .. check.label .. " nach 1 Tick: " .. t7_check_text(tb, nodes, t7_body_check(tb, surface, nodes)))
    end
    destroy_worm(check.unit)
  end
end

local function t7_unit_text(tb, unit)
  local nodes = body_nodes(unit)
  local max_nodes = read(function() return unit.max_body_nodes end)
  local ok, total, with_entity = pcall(function()
    local count, existing = 0, 0
    for _, segment in pairs(unit.segments) do
      count = count + 1
      if segment.entity then existing = existing + 1 end
    end
    return count, existing
  end)
  local segments = ok and string.format("Segmente %s, davon mit Entity %s", tostring(total), tostring(with_entity))
    or ("Segmente nicht lesbar: " .. tostring(total))
  return string.format("Knoten %s (max_body_nodes %s), %s, Kopf %s, Tempo %s Kacheln/s",
    nodes and tostring(#nodes) or "–", tostring(max_nodes), segments, pos_text(tb, nodes and nodes[1]),
    tb.num(tb.speed_tps(unit)))
end

local function t7_summary(run, tb)
  local data = run.data
  local parts = {}
  for _, check in ipairs(data.checks) do
    local result = check.result
    local good
    if result then
      if check.expect_rock then good = result.hits > 0 else good = result.hits == 0 end
    end
    table.insert(parts, check.label .. " " .. (result and (good and "ok" or "falsch") or "–"))
  end
  if data.part_b then
    table.insert(parts, "b Knoten " .. tostring(data.b_nodes0 or "–") .. " → " .. tostring(data.b_nodes1 or "–"))
  else
    table.insert(parts, "b nicht gestartet")
  end
  return table.concat(parts, ", ")
end

local function t7_start(run, tb)
  local data = run.data
  local origin = tb.area(run.id)
  local o = {x = origin.x, y = origin.y}
  data.o = o
  data.worms = {}
  data.part_b = type(run.args[1]) == "string" and string.lower(run.args[1]) == "ja"
  tb.prepare(o, T7_HALF)
  local head_rock = at(o, T7_HEAD_ROCK.x, T7_HEAD_ROCK.y)
  tb.fill({left_top = {x = head_rock.x - T7_ROCK_GAP - T7_ROCK_DEPTH, y = head_rock.y - T7_ROCK_HALF_Y},
    right_bottom = {x = head_rock.x - T7_ROCK_GAP, y = head_rock.y + T7_ROCK_HALF_Y}}, ROCK)
  protect_and_watch(run, tb, at(o, T7_WATCH.x, T7_WATCH.y))
  data.checks =
  {
    t7_spawn_check(run, tb, "Felsprobe", head_rock, true),
    t7_spawn_check(run, tb, "Gegenprobe Sand", at(o, T7_HEAD_SAND.x, T7_HEAD_SAND.y), false)
  }
  data.t0 = game.tick
  data.step = "recheck"
end

local function t7_tick(run, tb)
  local data = run.data
  local tick = game.tick
  if data.step == "recheck" then
    if tick <= data.t0 then return end
    t7_recheck(run, tb)
    if not data.part_b then
      tb.log(run, "INFO", "Teil b (extended = false) startet nur mit /arrakis-test T7 ja – nur in einem Wegwerf-Spielstand.")
      destroy_all_worms(run)
      tb.finish(run, t7_summary(run, tb))
      return
    end
    tb.log(run, "FRAGE", "Starte extended = false in 2 s; falls das Spiel abstürzt, bitte melden (diese Zeile steht dann als letzte in arrakis-test.txt).")
    data.warn_tick = tick
    data.step = "spawn"
  elseif data.step == "spawn" then
    if tick < data.warn_tick + T7_WARN_DELAY then return end
    local o = data.o
    local unit = create_worm(run, tb, WORM, at(o, T7_HEAD_FREE.x, T7_HEAD_FREE.y), defines.direction.east, false)
    data.b_unit = unit
    data.b_tick = tick
    data.step = "drive"
    if not unit then
      tb.log(run, "FEHLER", "b) extended = false: kein Wurm erzeugt")
      destroy_all_worms(run)
      tb.finish(run, t7_summary(run, tb))
      return
    end
    local nodes = body_nodes(unit)
    data.b_nodes0 = nodes and #nodes or nil
    tb.log(run, "MESSUNG", "b) extended = false, sofort: " .. t7_unit_text(tb, unit))
    set_activity(run, tb, unit, "full")
    investigate(run, tb, unit, at(o, T7_FREE_TARGET.x, T7_FREE_TARGET.y), "Teil b")
  elseif data.step == "drive" then
    if tick < data.b_tick + T7_DRIVE then return end
    local unit = data.b_unit
    if valid(unit) then
      local nodes = body_nodes(unit)
      data.b_nodes1 = nodes and #nodes or nil
      tb.log(run, "MESSUNG", "b) nach 10 s Fahrt: " .. t7_unit_text(tb, unit))
    else
      tb.log(run, "FEHLER", "b) Wurm ist nach 10 s verschwunden")
    end
    destroy_all_worms(run)
    tb.finish(run, t7_summary(run, tb))
  end
end

return
{
  T5 =
  {
    title = "Wurm-KI: Zustände, Tempo, Flieger über dem Kopf",
    timeout = 150 * 60,
    interactive = false,
    confirm = nil,
    start = t5_start,
    tick = t5_tick,
    on_event = on_event,
    cleanup = cleanup
  },
  T6 =
  {
    title = "Wurm: Fels-Ebene und Wächter",
    timeout = 120 * 60,
    interactive = false,
    confirm = nil,
    start = t6_start,
    tick = t6_tick,
    on_event = on_event,
    cleanup = cleanup
  },
  T7 =
  {
    title = "Wurm: Körperprüfung und extended = false",
    timeout = 40 * 60,
    interactive = false,
    confirm = nil,
    hint = "Teil b (extended = false) nur mit /arrakis-test T7 ja, nur im Wegwerf-Spielstand",
    start = t7_start,
    tick = t7_tick,
    on_event = on_event,
    cleanup = cleanup
  }
}
