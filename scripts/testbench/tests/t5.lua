-- T5 Wurm-KI: Zustände, Tempo, Flieger über dem Kopf: Prüfstand-Test (aus t_worm.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_worm.lua.

local common = require("scripts.testbench.gemeinsam_worm")
local WORM = common.WORM
local REACH = common.REACH
local MIN_ACTIVITY = common.MIN_ACTIVITY
local valid = common.valid
local guarded = common.guarded
local trace = common.trace
local at = common.at
local copy_position = common.copy_position
local pos_text = common.pos_text
local count_up = common.count_up
local counts_text = common.counts_text
local protect_and_watch = common.protect_and_watch
local player_force = common.player_force
local watch_death = common.watch_death
local death_of = common.death_of
local create_entity = common.create_entity
local create_harvester = common.create_harvester
local health_of = common.health_of
local health_text = common.health_text
local entity_radius = common.entity_radius
local create_worm = common.create_worm
local destroy_worm = common.destroy_worm
local destroy_all_worms = common.destroy_all_worms
local head_of = common.head_of
local ai_state = common.ai_state
local activity_mode = common.activity_mode
local set_activity = common.set_activity
local investigate = common.investigate
local on_event = common.on_event
local cleanup = common.cleanup

local FLYER_4 = "arrakis-test-flyer-4"
local FLYER_FUEL = "rocket-fuel"
local FLYER_FUEL_COUNT = 5
-- Ausnahme T5 a: Minimum minimal, wie es echte Würmer haben (Design 4.3). Den Modus minimal misst a damit nicht:
-- Im Zustand investigating hält die Engine den Wurm auch ohne Zuschauer auf full (0.5.3 mit 2.1.23: full bis zur
-- Ankunft, minimal erst etwa 4 s nach dem Wechsel zu patrolling). a zeigt also den ungedrosselten Anmarsch eines
-- echten Wurms und, nach der Ankunft, wann er auf minimal wechselt; nur MESSUNG, T5 hat kein OK/FEHLER.
local T5A_ACTIVITY = "minimal"

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
  set_activity(run, tb, p.unit, T5A_ACTIVITY)
  investigate(run, tb, p.unit, p.target, "Punkt hinter dem Ernter")
  local head = head_of(p.unit)
  p.last = head
  p.path = 0
  p.max_speed = 0
  p.min_dist = head and tb.distance(head, p.target) or nil
  p.states_before = {}
  p.states_after = {}
  p.modes = {}
  p.state_modes = {}
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
    p.state_modes[name] = p.state_modes[name] or {}
    count_up(p.state_modes[name], mode)
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
  -- Je Zustand getrennt: Das Minimum ist nur eine Untergrenze, den Modus wählt die Engine (investigating: full, siehe T5A_ACTIVITY).
  local states, per_state = {}, {}
  for state in pairs(p.state_modes) do table.insert(states, state) end
  table.sort(states)
  for _, state in ipairs(states) do table.insert(per_state, state .. " " .. counts_text(p.state_modes[state])) end
  tb.log(run, "MESSUNG", "a) activity_mode (Minimum " .. T5A_ACTIVITY .. " gesetzt, wie bei echten Würmern; welchen Modus der Wurm fährt, "
    .. "entscheidet die Engine): " .. counts_text(p.modes) .. "; je Zustand: " .. (#per_state > 0 and table.concat(per_state, "; ") or "–"))
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
  set_activity(run, tb, p.unit, MIN_ACTIVITY)
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
  tb.log(run, "MESSUNG", "b) activity_mode (Minimum " .. MIN_ACTIVITY .. " gesetzt): " .. counts_text(p.modes))
  return string.format("b Ziel %d/%d s, erreicht %s", p.held, p.samples, p.reached and "ja" or "nein")
end

-- c) Drosselung ------------------------------------------------------------------

function t5.c_start(run, tb, p)
  local o = run.data.o
  local y = T5_LANE.c
  p.unit = create_worm(run, tb, WORM, at(o, T5_START_X, y), defines.direction.east, true)
  if not p.unit then return false end
  set_activity(run, tb, p.unit, MIN_ACTIVITY)
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
  tb.log(run, "MESSUNG", string.format("c) danach frei (5 s): %s Kacheln/s (Weg %s Kacheln), speed im Mittel %s, am Ende %s Kacheln/s; activity_mode %s (Minimum %s)",
    tb.num(released), tb.num(p.dist[3]), tb.num(average(3)), tb.num(tb.speed_tps(p.unit)), activity_mode(tb, p.unit),
    MIN_ACTIVITY))
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
  set_activity(run, tb, p.unit, MIN_ACTIVITY)
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
  }
}
