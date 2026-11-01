-- Prüfstand: Wurm-Tests T5, T6, T7 (Vertrag siehe runner.lua, Design 4.3 und 8).
-- T5 Wurm-KI: a) investigating zu einem Punkt 20 Kacheln hinter einem Ernter, b) attacking auf einen Ernter,
--    c) Drosselung per speed, d) Flieger 3 s über dem Kopf (Gesundheit, Sticker, Tempo danach).
-- T6 Fels-Ebene und Wächter: vier Bahnen mit Felsinsel (ohne Ebene, mit Ebene arrakis_rock, mit Mini-Wächter,
--    Angriff auf einen Ernter vor dem Felsrand; Ziel per investigating, attacking hält bei Fahrzeugen nicht, T5 b).
-- T7 Körperprüfung (jeder vierte Körperknoten auf Fels?) und, nur mit "/arrakis-test T7 ja", extended = false.
--    T7 hat kein confirm: Teil a läuft immer (auch bei „alle“), Teil b nur mit Argument "ja".
-- Zustand nur in run.data: Zahlen, Texte, Positionen {x, y}, LuaEntity- und LuaSegmentedUnit-Referenzen
-- (vor jeder Benutzung auf valid prüfen). Alle Würmer stehen in run.data.worms und werden am Ende zerstört.

local WORM = "arrakis-test-worm"
local HARVESTER = "arrakis-test-harvester"
local ROCK = "arrakis-rock"
-- Biss-Reichweite: Kopf näher als 3 Kacheln plus Zielradius (Design 4.3, BISS).
local REACH = 3
-- minimum_activity_mode aller Testwürmer. Laut API rechnet die Engine Würmer ohne möglichen Zuschauer sparsamer
-- (minimal: weniger Bewegung und Trigger-Effekte; im Zustand investigating nicht, siehe T5 a); full heißt „wie
-- beobachtet“. Mit Zuschauer blieben sie in 0.4.0 ohnehin full, so sind Läufe ohne Spieler (Serverkonsole, RCON)
-- vergleichbar. Die Würmer leben nur im Test.
local MIN_ACTIVITY = "full"

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

-- Für die Testdateien scripts/testbench/tests/ (eine je Test; aufgeteilt aus t_worm.lua, Verhalten unverändert).
return
{
  WORM = WORM,
  HARVESTER = HARVESTER,
  ROCK = ROCK,
  REACH = REACH,
  MIN_ACTIVITY = MIN_ACTIVITY,
  valid = valid,
  guarded = guarded,
  read = read,
  trace = trace,
  at = at,
  copy_position = copy_position,
  pos_text = pos_text,
  count_up = count_up,
  counts_text = counts_text,
  protect_and_watch = protect_and_watch,
  player_force = player_force,
  watch_death = watch_death,
  death_of = death_of,
  create_entity = create_entity,
  create_harvester = create_harvester,
  health_of = health_of,
  health_text = health_text,
  entity_radius = entity_radius,
  create_worm = create_worm,
  destroy_worm = destroy_worm,
  destroy_all_worms = destroy_all_worms,
  body_nodes = body_nodes,
  head_of = head_of,
  ai_state = ai_state,
  activity_mode = activity_mode,
  set_activity = set_activity,
  investigate = investigate,
  on_event = on_event,
  cleanup = cleanup,
}
