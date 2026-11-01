-- T7 Wurm: Körperprüfung und extended = false: Prüfstand-Test (aus t_worm.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_worm.lua.

local common = require("scripts.testbench.gemeinsam_worm")
local WORM = common.WORM
local ROCK = common.ROCK
local MIN_ACTIVITY = common.MIN_ACTIVITY
local valid = common.valid
local read = common.read
local at = common.at
local pos_text = common.pos_text
local protect_and_watch = common.protect_and_watch
local create_worm = common.create_worm
local destroy_worm = common.destroy_worm
local destroy_all_worms = common.destroy_all_worms
local body_nodes = common.body_nodes
local set_activity = common.set_activity
local investigate = common.investigate
local on_event = common.on_event
local cleanup = common.cleanup

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
    set_activity(run, tb, unit, MIN_ACTIVITY)
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
