-- T6 Wurm: Fels-Ebene und Wächter: Prüfstand-Test (aus t_worm.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_worm.lua.

local common = require("scripts.testbench.gemeinsam_worm")
local WORM = common.WORM
local ROCK = common.ROCK
local REACH = common.REACH
local MIN_ACTIVITY = common.MIN_ACTIVITY
local valid = common.valid
local guarded = common.guarded
local read = common.read
local trace = common.trace
local at = common.at
local copy_position = common.copy_position
local pos_text = common.pos_text
local count_up = common.count_up
local counts_text = common.counts_text
local protect_and_watch = common.protect_and_watch
local death_of = common.death_of
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

local WORM_ROCKMASK = "arrakis-test-worm-rockmask"
local SAND = {["sand-1"] = true, ["sand-2"] = true, ["sand-3"] = true}

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
-- Angriff per investigating auf die Position des Ernters (Design 4.3), bei jedem Nachsetzen neu gelesen;
-- attacking hält bei Fahrzeugen kein Ziel (T5 b, 0.4.0: sofort patrolling).
local function t6_wanted(lane)
  local investigating = defines.segmented_unit_ai_state.investigating
  if lane.detour then return {type = investigating, destination = lane.detour} end
  if lane.attack then
    if not valid(lane.harvester) then return nil end
    return {type = investigating, destination = copy_position(lane.harvester.position)}
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
  set_activity(run, tb, lane.unit, MIN_ACTIVITY)
  if def.attack then
    lane.set_ok = investigate(run, tb, lane.unit, lane.harvester_pos, "Bahn D: Ernter")
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
    table.insert(parts, "Ziel per investigating zum Ernter " .. (lane.set_ok and "ok" or "Fehler"))
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
  table.insert(parts, "activity_mode " .. counts_text(lane.modes) .. " (Minimum " .. MIN_ACTIVITY .. ")")
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
  elseif c.rock == 0 and d.rock == 0 and not (c.arrived and d.bite) then
    -- Kein Fels, aber der Wurm kam gar nicht an der Insel vorbei bzw. nicht zum Ernter: kein Beleg für den Wächter.
    local missing = {}
    if not c.arrived then table.insert(missing, "Bahn C kam nicht ans Ziel") end
    if not d.bite then table.insert(missing, "Bahn D erreichte den Ernter nicht") end
    tb.log(run, "FEHLER", "Kopf war auf Bahn C und D nie auf Fels, aber " .. table.concat(missing, " und ")
      .. ": Wächter nicht bestätigt (siehe MESSUNG der Bahnen)")
    verdict = "Wächter nicht bestätigt"
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

return
{
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
  }
}
