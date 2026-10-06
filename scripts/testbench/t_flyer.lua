-- Prüfstand: Flieger-Tests T1, T9, T12 (Vertrag siehe runner.lua, Design 4.2 und 8).
-- T1 misst Tempo, Ankunft und Verbrauch der Flieger-Varianten über Sand, Fels, Wasser und Gebäude.
-- T9 zeigt Bild und Schatten einer getragenen Last und prüft, ob Render-Objekte beim
--    Oberflächenwechsel verschwinden (interaktiv).
-- T12 misst, was beim Drücken der Testtaste in Fahrzeug, Kartenansicht und Fernsteuerung ankommt (interaktiv).
-- Zustand nur in run.data: Zahlen, Texte, Positionen {x, y}, LuaEntity- und LuaRenderObject-Referenzen
-- (vor jeder Benutzung auf valid prüfen).

local FLYER_4 = "arrakis-test-flyer-4"
local FUEL_ITEM = "rocket-fuel"
local HOLD_NAME = "arrakis-test-hold"

-- Hilfen ------------------------------------------------------------------------------------

-- Ruft fn geschützt auf. Bei Fehler: Zeile mit level (Standard FEHLER) ins Protokoll.
local function guarded(run, tb, what, fn, level)
  local ok, result = pcall(fn)
  if not ok then
    tb.log(run, level or "FEHLER", what .. " ging nicht: " .. tostring(result))
  end
  return ok, result
end

-- Liest einen Wert; Fehler werden zu Text (für Messzeilen).
local function read(fn)
  local ok, value = pcall(fn)
  if ok then return value end
  return "Fehler: " .. tostring(value)
end

local function pos_text(tb, position)
  if not position then return "–" end
  return "(" .. tb.num(position.x) .. ", " .. tb.num(position.y) .. ")"
end

local function offset(origin, dx, dy)
  return {x = origin.x + dx, y = origin.y + dy}
end

-- Spieler zum Zuschauen hinbringen (merkt sich die Rückkehrposition, siehe tb.watch).
local function bring_player(run, tb, player, position)
  local ok, moved = guarded(run, tb, "Spieler zum Testbereich bringen", function()
    return tb.watch(run, player, position)
  end, "INFO")
  if ok and not moved then
    tb.log(run, "INFO", "Teleport zum Testbereich ging nicht; /arrakis-test zurück bringt dich zurück, falls nötig")
  end
end

-- Flieger erzeugen; nil bei Fehler (wird gemeldet).
local function create_flyer(run, tb, surface, name, position, force)
  local ok, flyer = guarded(run, tb, "Flieger " .. name .. " erzeugen", function()
    return surface.create_entity{name = name, position = position, force = force, create_build_effect_smoke = false}
  end)
  if ok and flyer and flyer.valid then return flyer end
  if ok then tb.log(run, "FEHLER", "Flieger " .. name .. " wurde nicht erzeugt (create_entity gab nil)") end
  return nil
end

-- Treibstoff einlegen; gibt die eingelegte Menge zurück.
local function add_fuel(run, tb, entity, count)
  local ok, inserted = guarded(run, tb, "Treibstoff einlegen", function()
    return tb.fuel(entity, FUEL_ITEM, count)
  end)
  if not ok then return 0 end
  inserted = inserted or 0
  if inserted < count then
    tb.log(run, "FEHLER", string.format("Treibstoff: nur %s von %s %s eingelegt", tostring(inserted), tostring(count), FUEL_ITEM))
  end
  return inserted
end

-- Gespeicherte Energie (J): Brennstoffinventar + Rest des brennenden Stücks + Wärmepuffer des Brenners.
local function fuel_energy(entity)
  if not (entity and entity.valid) then return nil end
  local ok, total = pcall(function()
    local burner = entity.burner
    if not burner then return nil end
    local sum = 0
    for _, item in pairs(burner.inventory.get_contents()) do
      local prototype = prototypes.item[item.name]
      sum = sum + (prototype and prototype.fuel_value or 0) * item.count
    end
    local ok_rest, rest = pcall(function() return burner.remaining_burning_fuel end)
    if ok_rest and type(rest) == "number" then sum = sum + rest end
    local ok_heat, heat = pcall(function() return burner.heat end)
    if ok_heat and type(heat) == "number" then sum = sum + heat end
    return sum
  end)
  if ok then return total end
  return nil
end

local function sticker_count(entity)
  if not (entity and entity.valid) then return nil end
  local ok, stickers = pcall(function() return entity.stickers end)
  if not ok then return nil end
  return stickers and #stickers or 0
end

-- T1 Flieger: Beine, Tempo, Gelände ---------------------------------------------------------

-- Bahnen laufen in +x. Alle x-Werte relativ zum Bereichsursprung.
local T1_START_X = 2
local T1_TARGET_X = 220
local T1_LANE_SPACING = 20
local T1_SAMPLE_TICKS = 30
local T1_REPORT_TICKS = 10 * 60
local T1_STALL_TICKS = 5 * 60
local T1_GIVE_UP_TICKS = 15 * 60
local T1_DEADLINE_TICKS = 110 * 60 -- Auswertung vor dem Zeitlimit (120 s) des Runners
local T1_GRACE_TICKS = 3 * 60 -- Nachlauf, wenn alle Bahnen fertig sind
local T1_ARRIVE_DISTANCE = 2
local T1_CRITERION = 5
local T1_CARRYALL = 6
-- Design (Zahlenregeln): 300 Kacheln in 60 s (Ornithopter, ≥ 5) bzw. 50 s (Carryall, ≥ 6).
local T1_TRIP = 300
local T1_TRIP_LIMIT = 60
local T1_TRIP_CARRYALL = 50

local T1_SECTIONS =
{
  {from = 0, to = 40, name = "Sand"},
  {from = 40, to = 70, name = "Fels"},
  {from = 70, to = 110, name = "Wasser"},
  {from = 110, to = 140, name = "Gebäude"},
  {from = 140, to = 220, name = "Sand (Ende)"}
}
-- Reisetempo: Durchschnitt über Fels, Wasser und Gebäude (ohne Anfahren und Abbremsen).
local T1_CRUISE_FIRST, T1_CRUISE_LAST = 2, 4

-- design = zählt für das Kriterium (die vier Bauformen mit Treibstoff, ohne Last).
-- sticker = Last-Sticker der Bahn. Zwei Sticker mit je einem Bremsfeld: welches Feld wirkt bei Spider-Vehicles,
-- ist nicht belegt (der Vanilla-Verlangsamungs-Sticker setzt nur target_movement_modifier).
local T1_LANES =
{
  {label = "-1", name = "arrakis-test-flyer-1", fuel = 5, design = true},
  {label = "-2", name = "arrakis-test-flyer-2", fuel = 5, design = true},
  {label = "-4", name = "arrakis-test-flyer-4", fuel = 5, design = true, reference = true},
  {label = "-4-fast", name = "arrakis-test-flyer-4-fast", fuel = 5, design = true},
  {label = "-4 leer", name = "arrakis-test-flyer-4", fuel = 0, no_fuel = true},
  {label = "-4 Last Fahrzeug", name = "arrakis-test-flyer-4", fuel = 5,
    sticker = "arrakis-test-load-sticker", sticker_field = "vehicle_speed_modifier 0.7"},
  {label = "-4 Last Bewegung", name = "arrakis-test-flyer-4", fuel = 5,
    sticker = "arrakis-test-load-sticker-move", sticker_field = "target_movement_modifier 0.7"}
}

local function t1_section_index(x)
  for index, section in ipairs(T1_SECTIONS) do
    if x < section.to then return index end
  end
  return #T1_SECTIONS
end

-- Ordnet die Strecke x1 → x2 (Dauer ticks) den Abschnitten zu, Zeit anteilig zur Strecke.
-- Ohne Fortschritt zählt die Zeit für den Abschnitt, in dem der Flieger steht.
local function t1_account(lane, x1, x2, ticks)
  if ticks <= 0 then return end
  local dx = x2 - x1
  if dx <= 0.001 then
    local index = t1_section_index(math.max(x1, 0))
    lane.sec_time[index] = lane.sec_time[index] + ticks
    return
  end
  for index, section in ipairs(T1_SECTIONS) do
    local a, b = math.max(x1, section.from), math.min(x2, section.to)
    if b > a then
      lane.sec_dist[index] = lane.sec_dist[index] + (b - a)
      lane.sec_time[index] = lane.sec_time[index] + ticks * (b - a) / dx
    end
  end
end

local function t1_arrive(run, tb, lane, tick, how)
  lane.arrived_tick = tick
  lane.arrived_x = lane.last_x
  lane.arrived_how = how
  lane.done = true
  tb.log(run, "MESSUNG", string.format("Bahn %s: angekommen nach %s s (%s)", lane.label,
    tb.num((tick - run.started) / 60), how))
end

-- Eine Messung je Bahn: Position, Fortschritt, Tempo, Abweichung, Ankunft, Stillstand.
local function t1_sample(run, tb, lane, tick)
  local data = run.data
  local entity = lane.entity
  if not (entity and entity.valid) then
    lane.done = true
    lane.lost = true
    tb.log(run, "FEHLER", "Bahn " .. lane.label .. ": Flieger ist verschwunden")
    return
  end
  local position = entity.position
  local x = position.x - data.x0
  t1_account(lane, lane.last_x, x, tick - lane.last_tick)
  lane.last_x, lane.last_tick = x, tick
  lane.last_position = {x = position.x, y = position.y}
  if x > lane.max_x then lane.max_x = x end
  local deviation = math.abs(position.y - lane.y)
  if deviation > lane.max_dev then lane.max_dev = deviation end
  local speed = tb.speed_tps(entity)
  if speed and speed > lane.max_speed then lane.max_speed = speed end

  if not lane.arrived_tick and tb.distance(position, lane.target) <= T1_ARRIVE_DISTANCE then
    t1_arrive(run, tb, lane, tick, "Abstand ≤ 2 Kacheln")
    return
  end

  if x - lane.progress_x >= 0.5 then
    if lane.stalled then
      lane.stalled = false
      tb.log(run, "MESSUNG", string.format("Bahn %s: fliegt wieder (x = %s)", lane.label, tb.num(x)))
    end
    lane.progress_x, lane.progress_tick = x, tick
  elseif tick - lane.progress_tick > T1_STALL_TICKS then
    if not lane.stalled then
      lane.stalled = true
      lane.stall_count = lane.stall_count + 1
      lane.first_stall_x = lane.first_stall_x or x
      tb.log(run, "MESSUNG", string.format("Bahn %s: Stillstand (über 5 s ohne 0.5 Kacheln Fortschritt) bei x = %s (%s)",
        lane.label, tb.num(x), T1_SECTIONS[t1_section_index(x)].name))
    end
    if tick - lane.progress_tick > T1_GIVE_UP_TICKS then
      lane.done = true
      lane.gave_up = true
    end
  end
end

-- Reisetempo (Kacheln/s) über die mittleren Abschnitte, nur wenn sie ganz gequert wurden.
local function t1_cruise(lane)
  if lane.max_x < T1_SECTIONS[T1_CRUISE_LAST].to then return nil end
  local dist, ticks = 0, 0
  for index = T1_CRUISE_FIRST, T1_CRUISE_LAST do
    dist = dist + lane.sec_dist[index]
    ticks = ticks + lane.sec_time[index]
  end
  if ticks <= 0 then return nil end
  return dist / (ticks / 60)
end

-- Durchschnittstempo vom Start bis zur Ankunft (oder bis zur letzten Messung).
local function t1_average(run, lane)
  local x, tick
  if lane.arrived_tick then
    x, tick = lane.arrived_x, lane.arrived_tick
  else
    x, tick = lane.last_x, lane.last_tick
  end
  local seconds = (tick - run.started) / 60
  if seconds <= 0 then return nil end
  return (x - T1_START_X) / seconds
end

-- Hochrechnung auf 300 Kacheln: Zeit bis zur Ankunft plus der Rest mit Reisetempo (s).
-- nil ohne Ankunft oder ohne Reisetempo.
local function t1_trip(run, lane)
  if not (lane.arrived_tick and lane.cruise and lane.cruise > 0) then return nil end
  local flown = (lane.arrived_x or lane.last_x) - T1_START_X
  if flown <= 0 then return nil end
  return (lane.arrived_tick - run.started) / 60 + math.max(T1_TRIP - flown, 0) / lane.cruise
end

local function t1_sections_text(tb, lane)
  local parts = {}
  for index, section in ipairs(T1_SECTIONS) do
    local dist, ticks = lane.sec_dist[index], lane.sec_time[index]
    local text
    if dist <= 0 or ticks <= 0 then
      text = ticks > 0 and "0.0" or "–"
    else
      text = tb.num(dist / (ticks / 60))
      local length = section.to - section.from
      if index == 1 then length = length - T1_START_X end
      if dist < length - 2.5 then text = text .. " (teilw.)" end
    end
    table.insert(parts, section.name .. " " .. text)
  end
  return table.concat(parts, " | ") .. " Kacheln/s"
end

local function t1_evaluate(run, tb)
  local data = run.data
  if data.evaluated then return end
  data.evaluated = true
  local end_x = T1_SECTIONS[#T1_SECTIONS].to - T1_ARRIVE_DISTANCE
  local obstacles_end = T1_SECTIONS[T1_CRUISE_LAST].to
  local reference, empty
  local loaded = {}
  local events_yes, events_no = {}, {}

  for _, lane in ipairs(data.lanes) do
    -- Gequert: hinter den Gebäuden und angekommen (Abstand oder Ereignis) bzw. bis kurz vors Bahnende.
    lane.crossed = lane.max_x >= obstacles_end and (lane.arrived_tick ~= nil or lane.max_x >= end_x)
    lane.cruise = t1_cruise(lane)
    lane.average = t1_average(run, lane)
    lane.trip = t1_trip(run, lane)
    if lane.reference then reference = lane end
    if lane.sticker then table.insert(loaded, lane) end
    if lane.no_fuel then empty = lane end

    -- Zeile 1: Ankunft, Tempo, Ereignis, Abweichung, Stillstand
    local arrival
    if lane.arrived_tick then
      arrival = string.format("angekommen nach %s s (%s, x = %s)", tb.num((lane.arrived_tick - run.started) / 60),
        lane.arrived_how, tb.num(lane.arrived_x))
    else
      local why = lane.lost and "Flieger verschwunden" or (lane.gave_up and "15 s ohne Fortschritt" or "Messende")
      arrival = string.format("nicht angekommen, x = %s von %d (%s)", tb.num(lane.last_x), T1_TARGET_X, why)
    end
    local event
    if lane.event_tick then
      event = string.format("ja (nach %s s, Abstand zum Ziel %s)", tb.num((lane.event_tick - run.started) / 60), tb.num(lane.event_dist))
      table.insert(events_yes, lane.label)
    else
      event = "nein"
      table.insert(events_no, lane.label)
    end
    tb.log(run, "MESSUNG", string.format(
      "Bahn %s (%s): %s, Ø %s Kacheln/s, Reisetempo (x 40–140) %s Kacheln/s, Höchsttempo %s Kacheln/s, " ..
      "300 Kacheln hochgerechnet %s s, on_spider_command_completed: %s, seitliche Abweichung max. %s, Stillstände %d%s",
      lane.label, lane.name, arrival, tb.num(lane.average), tb.num(lane.cruise), tb.num(lane.max_speed),
      tb.num(lane.trip), event, tb.num(lane.max_dev), lane.stall_count,
      lane.first_stall_x and (" (erster bei x = " .. tb.num(lane.first_stall_x) .. ")") or ""))

    -- Zeile 2: Tempo je Abschnitt
    tb.log(run, "MESSUNG", "Bahn " .. lane.label .. " Abschnitte: " .. t1_sections_text(tb, lane))

    -- Zeile 3: Treibstoff
    lane.energy_after = fuel_energy(lane.entity)
    local used = lane.energy_before and lane.energy_after and (lane.energy_before - lane.energy_after)
    local flown = lane.max_x - T1_START_X
    local per_tile = used and flown > 1 and (used / flown / 1000) or nil
    tb.log(run, "MESSUNG", string.format("Bahn %s Treibstoff: vorher %s MJ, nachher %s MJ, verbraucht %s MJ (%s kJ/Kachel)",
      lane.label, tb.num(lane.energy_before and lane.energy_before / 1e6), tb.num(lane.energy_after and lane.energy_after / 1e6),
      tb.num(used and used / 1e6), tb.num(per_tile)))
  end

  tb.log(run, "MESSUNG", "on_spider_command_completed bei Skriptziel: kam bei " ..
    (#events_yes > 0 and table.concat(events_yes, ", ") or "keiner Bahn") ..
    (#events_no > 0 and ("; nicht bei " .. table.concat(events_no, ", ")) or ""))

  -- Ohne Treibstoff
  if empty then
    local flown = empty.max_x - T1_START_X
    if flown < 1 then
      tb.log(run, "MESSUNG", string.format("Ohne Treibstoff: fliegt nicht (Strecke %s Kacheln)", tb.num(flown)))
    else
      tb.log(run, "MESSUNG", string.format("Ohne Treibstoff: fliegt %s Kacheln, Ø %s Kacheln/s, angekommen %s",
        tb.num(flown), tb.num(empty.average), empty.arrived_tick and "ja" or "nein"))
    end
  end

  -- Last-Sticker: Tempoverhältnis zur -4-Bahn (Reisetempo, sonst Durchschnitt), je Sticker-Feld
  for _, lane in ipairs(loaded) do
    local sticker_end = sticker_count(lane.entity)
    local ratio_text
    if lane.cruise and reference and reference.cruise and reference.cruise > 0 then
      ratio_text = string.format("%s %% (Reisetempo %s / %s Kacheln/s)", tb.num(100 * lane.cruise / reference.cruise),
        tb.num(lane.cruise), tb.num(reference.cruise))
    elseif lane.average and reference and reference.average and reference.average > 0 then
      ratio_text = string.format("%s %% (Ø %s / %s Kacheln/s)", tb.num(100 * lane.average / reference.average),
        tb.num(lane.average), tb.num(reference.average))
    else
      ratio_text = "nicht messbar"
    end
    tb.log(run, "MESSUNG", string.format("Last-Sticker %s (nur %s): Tempo im Verhältnis zur -4-Bahn %s; Sticker am Flieger: Start %s, Ende %s",
      lane.sticker, lane.sticker_field, ratio_text, tostring(lane.stickers_start or "–"), tostring(sticker_end or "–")))
  end
  if #loaded > 0 then
    tb.log(run, "INFO", "Last-Sticker: etwa 70 % heißt, dieses Feld bremst Spider-Vehicles; etwa 100 %: es wirkt nicht.")
  end

  -- Kriterium 1: beste Bauform mit Treibstoff quert alle Abschnitte mit Reisetempo ≥ 5
  local best
  for _, lane in ipairs(data.lanes) do
    if lane.design and lane.crossed and lane.cruise and (not best or lane.cruise > best.cruise) then
      best = lane
    end
  end
  -- Kriterium 2 (Design): 300 Kacheln (hochgerechnet) in höchstens 60 s
  local fastest
  for _, lane in ipairs(data.lanes) do
    if lane.design and lane.crossed and lane.trip and (not fastest or lane.trip < fastest.trip) then
      fastest = lane
    end
  end
  local carryall = {}
  for _, lane in ipairs(data.lanes) do
    if lane.design and lane.crossed and lane.cruise and lane.cruise >= T1_CARRYALL then
      table.insert(carryall, lane.label .. " " .. tb.num(lane.cruise) .. " Kacheln/s, 300 Kacheln in " .. tb.num(lane.trip) .. " s")
    end
  end
  tb.log(run, "MESSUNG", "Carryall-Kriterium (Reisetempo ≥ 6 Kacheln/s, 300 Kacheln in ≤ 50 s, alle Abschnitte): " ..
    (#carryall > 0 and ("Reisetempo erfüllt von " .. table.concat(carryall, "; ")) or "Reisetempo von keiner Variante erfüllt"))

  local parts = {}
  if best and best.cruise >= T1_CRITERION then
    tb.log(run, "OK", string.format("Beste Variante %s: Reisetempo (x 40–140) %s Kacheln/s (≥ 5), alle Abschnitte gequert (Ø %s Kacheln/s)",
      best.label, tb.num(best.cruise), tb.num(best.average)))
    table.insert(parts, string.format("OK: beste Variante %s mit Reisetempo %s Kacheln/s", best.label, tb.num(best.cruise)))
  elseif best then
    tb.log(run, "FEHLER", string.format("Beste Variante %s quert alle Abschnitte, aber nur mit Reisetempo %s Kacheln/s (< 5)",
      best.label, tb.num(best.cruise)))
    table.insert(parts, string.format("FEHLER: beste Variante %s nur Reisetempo %s Kacheln/s", best.label, tb.num(best.cruise)))
  else
    tb.log(run, "FEHLER", "Keine Variante mit Treibstoff hat alle Abschnitte gequert")
    table.insert(parts, "FEHLER: keine Variante kam ans Bahnende")
  end
  if fastest then
    local good = fastest.trip <= T1_TRIP_LIMIT
    tb.log(run, good and "OK" or "FEHLER", string.format("Hochrechnung %s: 300 Kacheln in %s s (%s 60 s, Ø %s Kacheln/s; Carryall-Ziel ≤ %d s: %s)",
      fastest.label, tb.num(fastest.trip), good and "≤" or ">", tb.num(T1_TRIP / fastest.trip), T1_TRIP_CARRYALL,
      fastest.trip <= T1_TRIP_CARRYALL and "ja" or "nein"))
    table.insert(parts, string.format("300 Kacheln in %s s (%s)", tb.num(fastest.trip), good and "OK" or "FEHLER"))
  end
  tb.finish(run, table.concat(parts, "; "))
end

local function t1_start(run, tb)
  local data = run.data
  local origin = tb.area(run.id)
  local x0, y0 = origin.x, origin.y
  data.x0, data.y0 = x0, y0
  local half_height = (#T1_LANES / 2) * T1_LANE_SPACING + 10
  tb.prepare({x = x0 + T1_TARGET_X / 2, y = y0}, {x = T1_TARGET_X / 2 + 20, y = half_height}, "sand-1")
  local surface = tb.surface()
  local player = tb.player(run)
  local force = player and player.force or "player"

  -- Gelände quer über alle Bahnen. Der Steg (Sand durchs Wasser, keine Gebäude) ist der Zuschauerplatz.
  -- Er liegt zwischen zwei Bahnen: bei gerader Bahnzahl auf y = 0, bei ungerader 10 Kacheln daneben.
  local path_y = y0 + ((#T1_LANES % 2 == 1) and T1_LANE_SPACING / 2 or 0)
  local top, bottom = y0 - half_height + 10, y0 + half_height - 10
  local function band(from_x, to_x, tile, y1, y2)
    tb.fill({left_top = {x = x0 + from_x, y = y1 or top}, right_bottom = {x = x0 + to_x, y = y2 or bottom}}, tile, surface)
  end
  band(40, 70, "arrakis-rock")
  band(70, 110, "water")
  band(80, 100, "deepwater")
  band(70, 110, "sand-1", path_y - 2, path_y + 2)

  -- Gebäude: Raster aus Steinöfen (2×2) und Steinmauern im Abstand 4 auf Sand, x 110–140.
  local walls, furnaces = 0, 0
  local ok_build = guarded(run, tb, "Gebäuderaster bauen", function()
    for gx = 0, 6 do
      local x = x0 + 112 + 4 * gx
      for y = top + 2, bottom - 6, 4 do
        if y + 2 <= path_y - 4 or y >= path_y + 4 then
          local furnace = (gx + math.floor((y - top) / 4)) % 2 == 0
          local built = surface.create_entity{
            name = furnace and "stone-furnace" or "stone-wall",
            position = furnace and {x = x + 1, y = y + 1} or {x = x + 0.5, y = y + 0.5},
            force = force,
            create_build_effect_smoke = false
          }
          if built then
            if furnace then furnaces = furnaces + 1 else walls = walls + 1 end
          end
        end
      end
    end
  end)
  tb.log(run, "INFO", string.format("Aufbau: %d Bahnen im Abstand %d, Länge %d; Sand 0–40, Fels 40–70, Wasser 70–110 (Mitte tief), " ..
    "Gebäude 110–140 (%d Öfen, %d Mauern%s), Sand 140–220", #T1_LANES, T1_LANE_SPACING, T1_TARGET_X, furnaces, walls,
    ok_build and "" or ", unvollständig"))
  tb.log(run, "INFO", "Die Beine drehen nicht mit (Rumpfbild hat nur eine Richtung): Beinanordnungen liegen fest zur Karte. " ..
    "Alle Bahnen fliegen nach Osten; Werte für -1 und -2 gelten nur für Ost-West-Flug.")

  -- Flieger je Bahn
  data.lanes = {}
  for index, spec in ipairs(T1_LANES) do
    local lane_y = y0 + (index - (#T1_LANES + 1) / 2) * T1_LANE_SPACING
    local flyer = create_flyer(run, tb, surface, spec.name, {x = x0 + T1_START_X, y = lane_y}, force)
    if flyer then
      local lane =
      {
        label = spec.label,
        name = spec.name,
        design = spec.design,
        reference = spec.reference,
        no_fuel = spec.no_fuel,
        sticker = spec.sticker,
        sticker_field = spec.sticker_field,
        y = lane_y,
        target = {x = x0 + T1_TARGET_X, y = lane_y},
        entity = flyer,
        unit = flyer.unit_number,
        last_x = T1_START_X,
        last_tick = game.tick,
        max_x = T1_START_X,
        max_dev = 0,
        max_speed = 0,
        progress_x = T1_START_X,
        progress_tick = game.tick,
        stall_count = 0,
        sec_dist = {},
        sec_time = {}
      }
      for i = 1, #T1_SECTIONS do
        lane.sec_dist[i] = 0
        lane.sec_time[i] = 0
      end
      if spec.fuel > 0 then add_fuel(run, tb, flyer, spec.fuel) end
      lane.energy_before = fuel_energy(flyer)
      if spec.sticker then
        local ok, sticker = guarded(run, tb, "Last-Sticker " .. spec.sticker .. " erzeugen", function()
          return surface.create_entity{name = spec.sticker, position = flyer.position, target = flyer, force = flyer.force}
        end)
        lane.stickers_start = sticker_count(flyer)
        tb.log(run, "MESSUNG", string.format("Bahn %s: Last-Sticker %s, create_entity %s, Sticker am Flieger: %s",
          spec.label, spec.sticker, ok and (sticker and "lieferte Entity" or "lieferte nil") or "Fehler",
          tostring(lane.stickers_start or "–")))
      end
      table.insert(data.lanes, lane)
    end
  end
  if #data.lanes == 0 then
    tb.log(run, "FEHLER", "Kein Flieger erzeugt")
    tb.finish(run, "FEHLER: kein Flieger erzeugt")
    return
  end

  if player then
    bring_player(run, tb, player, {x = x0 + T1_TARGET_X / 2, y = path_y})
  end

  -- Start: alle gleichzeitig zum Bahnende
  for _, lane in ipairs(data.lanes) do
    local ok = guarded(run, tb, "Bahn " .. lane.label .. ": autopilot_destination setzen", function()
      lane.entity.autopilot_destination = lane.target
    end)
    if not ok then
      lane.done = true
    end
  end
  data.next_sample = game.tick + T1_SAMPLE_TICKS
  data.next_trace = game.tick + 60
  data.next_report = game.tick + T1_REPORT_TICKS
  data.deadline = run.started + T1_DEADLINE_TICKS
  tb.log(run, "INFO", "Alle Flieger fliegen zum Bahnende (x = " .. T1_TARGET_X .. "). Auswertung, wenn alle angekommen sind " ..
    "oder 15 s stillstehen, spätestens nach 110 s.")
  tb.log(run, "FRAGE", "Sieht der Flug glatt aus, sind Beine unsichtbar? Bitte Screenshot während des Flugs.")
end

local function t1_tick(run, tb)
  local data = run.data
  if not data.lanes or data.evaluated then return end
  local now = game.tick
  if now >= data.next_sample then
    data.next_sample = now + T1_SAMPLE_TICKS
    for _, lane in ipairs(data.lanes) do
      if not lane.done then t1_sample(run, tb, lane, now) end
    end
  end
  -- Rohdaten jede Sekunde nur in die Datei: x und Tempo je Bahn.
  if data.next_trace and now >= data.next_trace then
    data.next_trace = now + 60
    local parts = {}
    for _, lane in ipairs(data.lanes) do
      local entity = lane.entity
      local speed = entity and entity.valid and tb.speed_tps(entity) or nil
      table.insert(parts, string.format("%s x %s v %s", lane.label, tb.num(lane.last_x), tb.num(speed)))
    end
    tb.trace(run, "Messpunkt: " .. table.concat(parts, " | "))
  end
  if now >= data.next_report then
    data.next_report = now + T1_REPORT_TICKS
    local parts = {}
    for _, lane in ipairs(data.lanes) do
      table.insert(parts, lane.label .. " " .. (lane.arrived_tick and "am Ziel" or ("x " .. tb.num(lane.last_x))))
    end
    tb.log(run, "MESSUNG", "Stand " .. tb.num(tb.elapsed(run), 0) .. " s: " .. table.concat(parts, " | "))
  end
  -- Sind alle Bahnen fertig, noch kurz warten: Ankunft per Abstand kommt vor dem Ereignis,
  -- und on_spider_command_completed soll noch mitgezählt werden.
  if not data.grace_until then
    local all_done = true
    for _, lane in ipairs(data.lanes) do
      if not lane.done then
        all_done = false
        break
      end
    end
    if all_done then data.grace_until = now + T1_GRACE_TICKS end
  end
  if (data.grace_until and now >= data.grace_until) or now >= data.deadline then
    t1_evaluate(run, tb)
  end
end

local function t1_on_event(run, tb, name, event)
  if name ~= "spider_command_completed" then return end
  local data = run.data
  local vehicle = event.vehicle
  if not (data.lanes and vehicle and vehicle.valid) then return end
  local unit = vehicle.unit_number
  for _, lane in ipairs(data.lanes) do
    if lane.unit == unit then
      if not lane.event_tick then
        lane.event_tick = event.tick
        lane.event_dist = tb.distance(vehicle.position, lane.target)
      end
      if not lane.done then
        t1_sample(run, tb, lane, event.tick)
        if not lane.arrived_tick and not lane.done then
          t1_arrive(run, tb, lane, event.tick, "Ereignis, Abstand " .. tb.num(lane.event_dist))
        end
      end
      return
    end
  end
end

-- Flieger bleiben stehen; nur die Autopiloten anhalten.
local function t1_cleanup(run, tb)
  for _, lane in ipairs(run.data.lanes or {}) do
    if lane.entity and lane.entity.valid then
      pcall(function() lane.entity.autopilot_destination = nil end)
    end
  end
end

-- T9 Schatten der Last ------------------------------------------------------------------------

local T9_CARRIED = "arrakis-test-carried"
local T9_SHADOW = "arrakis-test-carried-shadow"
local T9_CARRIED_OFFSET = {0, 0.5}
local T9_SHADOW_OFFSET = {1, 1} -- leicht nach rechts unten versetzt
local T9_SCALE = 1.5
local T9_CIRCLE_RADIUS = 8
local T9_CIRCLE_STEP = 45 -- Grad je neuem Ziel
local T9_CIRCLE_TICKS = 3 * 60
local T9_CHECK_DELAY = 60
local T9_HOLD_SLOT = {x = -25, y = -25} -- abseits vom Stellplatz {5, 5} aus T3
local T9_END_TICKS = 57 * 60 -- vor dem Zeitlimit (60 s) selbst beenden

local function t9_draw(run, tb, what, kind, params)
  local ok, object = guarded(run, tb, what, function()
    if kind == "text" then return rendering.draw_text(params) end
    return rendering.draw_sprite(params)
  end)
  if ok then return object end
  return nil
end

-- Bild der Last (unter dem Flieger) und Schatten nach Art: "sprite" (draw_as_shadow), "tint" (Ersatz) oder nil.
local function t9_decorate(run, tb, flyer, label, shadow_kind)
  local objects = {}
  local surface = flyer.surface
  local function keep(object)
    if object then table.insert(objects, object) end
  end
  if shadow_kind == "sprite" then
    keep(t9_draw(run, tb, label .. ": Schatten-Sprite zeichnen", "sprite", {
      sprite = T9_SHADOW, target = {entity = flyer, offset = T9_SHADOW_OFFSET}, surface = surface,
      x_scale = T9_SCALE, y_scale = T9_SCALE, render_layer = "floor"}))
  elseif shadow_kind == "tint" then
    keep(t9_draw(run, tb, label .. ": Ersatzschatten zeichnen", "sprite", {
      sprite = T9_CARRIED, target = {entity = flyer, offset = T9_SHADOW_OFFSET}, surface = surface,
      x_scale = T9_SCALE, y_scale = T9_SCALE, render_layer = "floor", tint = {r = 0, g = 0, b = 0, a = 0.5}}))
  end
  keep(t9_draw(run, tb, label .. ": Bild der Last zeichnen", "sprite", {
    sprite = T9_CARRIED, target = {entity = flyer, offset = T9_CARRIED_OFFSET}, surface = surface,
    x_scale = T9_SCALE, y_scale = T9_SCALE, render_layer = "smoke"}))
  keep(t9_draw(run, tb, label .. ": Beschriftung", "text", {
    text = label, target = {entity = flyer, offset = {0, 2.5}}, surface = surface,
    color = {r = 1, g = 1, b = 1}, scale = 1.5, alignment = "center"}))
  return objects
end

local function t9_circle_point(circle, angle)
  local rad = math.rad(angle)
  return {x = circle.center.x + circle.radius * math.cos(rad), y = circle.center.y + circle.radius * math.sin(rad)}
end

local function t9_valid_count(objects)
  local valid = 0
  for _, object in pairs(objects or {}) do
    local ok, is_valid = pcall(function() return object.valid end)
    if ok and is_valid then valid = valid + 1 end
  end
  return valid
end

local function t9_start(run, tb)
  local data = run.data
  local player = tb.player(run)
  if not player then
    tb.log(run, "FEHLER", "Kein Spieler für den interaktiven Test")
    tb.finish(run, "abgebrochen (kein Spieler)")
    return
  end
  local origin = tb.area(run.id)
  tb.prepare(origin, 40)
  local surface = tb.surface()
  bring_player(run, tb, player, origin)
  local force = player.force

  for _, sprite in ipairs({T9_CARRIED, T9_SHADOW}) do
    local ok, valid = pcall(function() return helpers.is_valid_sprite_path(sprite) end)
    if not (ok and valid) then
      tb.log(run, "FEHLER", "Sprite " .. sprite .. " ist kein gültiger SpritePath (" .. tostring(valid) .. ")")
    end
  end

  -- A: Schatten-Sprite mit draw_as_shadow; B: Ersatzschatten; C: Kreisflug; D: Teleport-Test.
  data.flyers = {}
  local layout =
  {
    {key = "A", position = offset(origin, -6, -5), label = "A: Schatten-Sprite (draw_as_shadow)", shadow = "sprite"},
    {key = "B", position = offset(origin, 6, -5), label = "B: Ersatzschatten (schwarz, halbtransparent)", shadow = "tint"},
    {key = "C", position = offset(origin, T9_CIRCLE_RADIUS, 14), label = "C: Kreisflug mit Bild"},
    {key = "D", position = offset(origin, 0, -16), label = "D: Teleport-Test", shadow = "sprite"}
  }
  data.objects = {}
  for _, entry in ipairs(layout) do
    local flyer = create_flyer(run, tb, surface, FLYER_4, entry.position, force)
    if flyer then
      add_fuel(run, tb, flyer, 3)
      data.flyers[entry.key] = flyer
      data.objects[entry.key] = t9_decorate(run, tb, flyer, entry.label, entry.shadow)
    end
  end

  -- C fliegt im Kreis: alle 3 s ein neues autopilot_destination, nie Wegpunkte anhängen.
  data.circle = {center = offset(origin, 0, 14), radius = T9_CIRCLE_RADIUS, angle = 0, next_tick = game.tick, targets = 0}
  data.check = {state = "wait", tick = game.tick + T9_CHECK_DELAY}

  tb.log(run, "INFO", "A, B und C stehen neben dir, D verschwindet nach 1 s auf die Ablage. Die Flieger bleiben nach Testende stehen.")
  tb.log(run, "FRAGE", "Welcher Schatten sieht richtig aus: A (Schatten-Sprite mit draw_as_shadow) oder B (schwarz getöntes, " ..
    "halbtransparentes Bild)? Liegt das Panzerbild unter dem Rumpf, und folgt es bei C dem Flug ohne Ruckeln? " ..
    "Bitte Screenshot von A, B und C und Antwort melden.")
end

-- Automatische Prüfung: D samt Render-Objekten per teleport auf die Ablage-Oberfläche.
local function t9_check(run, tb)
  local data = run.data
  local check = data.check
  local objects = data.objects.D or {}
  if check.state == "wait" then
    local flyer = data.flyers.D
    if not (flyer and flyer.valid) then
      tb.log(run, "FEHLER", "Teleport-Test: Flieger D fehlt")
      check.state = "done"
      return
    end
    check.before = t9_valid_count(objects)
    check.total = #objects
    -- Ablage-Oberfläche wie in T3 (tb.hold_surface: Laborkacheln, 5×5 Chunks, für alle Forces versteckt).
    local ok_hold, hold = guarded(run, tb, "Ablage-Oberfläche " .. HOLD_NAME .. " anlegen", function()
      return tb.hold_surface()
    end)
    if not (ok_hold and hold) then
      check.state = "done"
      return
    end
    -- Reste eines früheren Laufs vom Stellplatz räumen
    pcall(function()
      for _, old in pairs(hold.find_entities_filtered{position = T9_HOLD_SLOT, radius = 6, name = FLYER_4}) do
        old.destroy()
      end
    end)
    local ok, result = guarded(run, tb, "Teleport von D auf die Ablage", function()
      return flyer.teleport(T9_HOLD_SLOT, hold)
    end)
    check.now = t9_valid_count(objects)
    local where = read(function() return flyer.valid and (flyer.surface.name .. " " .. pos_text(tb, flyer.position)) or "ungültig" end)
    tb.log(run, "MESSUNG", string.format("Teleport-Test: teleport() = %s, D danach auf %s; Render-Objekte gültig vorher %d von %d, direkt danach %d",
      ok and tostring(result) or "Fehler", tostring(where), check.before, check.total, check.now))
    if not (ok and result) then
      tb.log(run, "FEHLER", "Teleport auf die Ablage fehlgeschlagen, Render-Prüfung nicht möglich")
      check.state = "done"
      return
    end
    check.state = "teleported"
    check.tick = game.tick + 1
  elseif check.state == "teleported" or check.state == "late" then
    -- Einen Tick nach dem Teleport prüfen; sind noch Objekte gültig, nach 1 s ein zweites Mal.
    local after = t9_valid_count(objects)
    check.after = after
    if check.total == 0 then
      tb.log(run, "FEHLER", "Teleport-Test: D hatte keine Render-Objekte")
      check.state = "done"
    elseif after == 0 then
      tb.log(run, "OK", string.format("Render-Objekte am Flieger verschwinden beim Oberflächenwechsel (render_object.valid = false bei %d von %d%s)",
        check.total, check.total, check.state == "late" and ", erst nach 1 s" or ""))
      check.state = "done"
    elseif check.state == "teleported" then
      tb.log(run, "MESSUNG", string.format("Einen Tick nach dem Teleport noch %d von %d Render-Objekten gültig, prüfe nach 1 s erneut",
        after, check.total))
      check.state = "late"
      check.tick = game.tick + 60
    else
      local where = "?"
      for _, object in pairs(objects) do
        local ok, name = pcall(function() return object.valid and object.surface.name end)
        if ok and name then
          where = name
          break
        end
      end
      tb.log(run, "FEHLER", string.format("Nach dem Oberflächenwechsel sind nach 1 s noch %d von %d Render-Objekten gültig (Oberfläche %s)",
        after, check.total, where))
      check.state = "done"
    end
  end
end

local function t9_tick(run, tb)
  local data = run.data
  if not data.circle then return end
  local now = game.tick

  local circle = data.circle
  local flyer = data.flyers.C
  if now >= circle.next_tick and flyer and flyer.valid then
    circle.next_tick = now + T9_CIRCLE_TICKS
    circle.angle = (circle.angle + T9_CIRCLE_STEP) % 360
    local ok = guarded(run, tb, "C: autopilot_destination setzen", function()
      flyer.autopilot_destination = t9_circle_point(circle, circle.angle)
    end)
    if ok then circle.targets = circle.targets + 1 end
  end

  if data.check.state ~= "done" and now >= data.check.tick then
    t9_check(run, tb)
  end

  if now - run.started >= T9_END_TICKS then
    if flyer and flyer.valid then
      local queue = read(function() return #flyer.autopilot_destinations end)
      tb.log(run, "MESSUNG", string.format("C: %d Ziele gesetzt, Warteschlange jetzt %s (erwartet ≤ 1), Tempo %s Kacheln/s",
        circle.targets, tostring(queue), tb.num(tb.speed_tps(flyer))))
    end
    local check = data.check
    local result
    if check.after == 0 and (check.total or 0) > 0 then
      result = "Render-Objekte verschwinden: OK"
    elseif check.after then
      result = "Render-Objekte bleiben: FEHLER"
    else
      result = "Render-Prüfung nicht gelaufen"
    end
    tb.finish(run, result .. "; Schatten: Antwort von Max")
  end
end

-- C hält an; D (auf der versteckten Ablage) wird entfernt. A, B, C bleiben samt Bildern stehen.
local function t9_cleanup(run, tb)
  local flyers = run.data.flyers or {}
  if flyers.C and flyers.C.valid then
    pcall(function() flyers.C.autopilot_destination = nil end)
  end
  if flyers.D and flyers.D.valid then
    pcall(function() flyers.D.destroy() end)
  end
end

-- T12 Rettung aus der Kartenansicht ----------------------------------------------------------

local T12_END_TICKS = 180 * 60 -- „Ende nach 3 min“ (Zeitlimit des Runners 190 s)

local function t12_entity_text(entity)
  if not entity then return "nil" end
  if not entity.valid then return "ungültig" end
  return entity.name .. (entity.unit_number and (" #" .. entity.unit_number) or "")
end

local function t12_measure(run, tb, player, event)
  local vehicle = read(function() return t12_entity_text(player.vehicle) end)
  local physical = read(function() return t12_entity_text(player.physical_vehicle) end)
  local controller = read(function() return tb.enum_name(defines.controllers, player.controller_type) end)
  local render_mode = read(function() return tb.enum_name(defines.render_mode, player.render_mode) end)
  local selection = read(function()
    local list = player.spidertron_remote_selection
    if not list then return "nil" end
    if #list == 0 then return "leer" end
    local names = {}
    for _, entity in pairs(list) do table.insert(names, t12_entity_text(entity)) end
    return table.concat(names, ", ")
  end)
  local cursor = read(function()
    local stack = player.cursor_stack
    if not stack then return "nil (kein Cursor)" end
    if not stack.valid_for_read then return "leer" end
    return stack.name .. " x" .. stack.count
  end)
  local selected = read(function() return t12_entity_text(player.selected) end)
  local prototype = read(function()
    local sp = event.selected_prototype
    if not sp then return "nil" end
    return sp.base_type .. "/" .. sp.derived_type .. "/" .. sp.name .. (sp.quality and (" (" .. sp.quality .. ")") or "")
  end)
  return string.format("vehicle = %s, physical_vehicle = %s, controller_type = %s, render_mode = %s, " ..
    "spidertron_remote_selection = %s, cursor_stack = %s, selected = %s, selected_prototype = %s",
    tostring(vehicle), tostring(physical), tostring(controller), tostring(render_mode),
    tostring(selection), tostring(cursor), tostring(selected), tostring(prototype))
end

local function t12_start(run, tb)
  local data = run.data
  local player = tb.player(run)
  if not player then
    tb.log(run, "FEHLER", "Kein Spieler für den interaktiven Test")
    tb.finish(run, "abgebrochen (kein Spieler)")
    return
  end
  local origin = tb.area(run.id)
  tb.prepare(origin, 30)
  local surface = tb.surface()
  bring_player(run, tb, player, origin)
  data.presses = 0

  local flyer = create_flyer(run, tb, surface, FLYER_4, offset(origin, 5, 0), player.force)
  if not flyer then
    tb.finish(run, "FEHLER: kein Flieger")
    return
  end
  data.flyer = flyer
  add_fuel(run, tb, flyer, 5)

  -- Fernbedienung nur in einen leeren Cursor
  local remote = false
  local ok_empty, empty = guarded(run, tb, "Cursor prüfen", function() return player.is_cursor_empty() end)
  if ok_empty and empty then
    local ok, set = guarded(run, tb, "Spidertron-Fernbedienung in den Cursor legen", function()
      local stack = player.cursor_stack
      if not stack then return false end
      return stack.set_stack({name = "spidertron-remote", count = 1})
    end)
    remote = ok and set == true
    tb.log(run, "INFO", "Fernbedienung im Cursor: " .. (ok and tostring(set) or "Fehler"))
  elseif ok_empty then
    tb.log(run, "INFO", "Cursor nicht leer: keine Fernbedienung gegeben (für Schritt 2 selbst nehmen: Verknüpfungsleiste)")
  end
  -- Ohne Fernbedienung in der Hand ist ein Fehler hier erwartbar, daher nur INFO.
  local ok_sel = guarded(run, tb, "spidertron_remote_selection setzen", function()
    player.spidertron_remote_selection = {flyer}
  end, remote and "FEHLER" or "INFO")
  local selection = read(function()
    local list = player.spidertron_remote_selection
    return list and #list or "nil"
  end)
  tb.log(run, "INFO", string.format("Flieger %s bei %s, Treibstoff %s; Auswahl gesetzt: %s (gelesen: %s Einträge)",
    t12_entity_text(flyer), pos_text(tb, flyer.position), FUEL_ITEM, ok_sel and "ja" or "nein", tostring(selection)))

  tb.log(run, "FRAGE", "1) Steig in den Flieger ein (Enter), öffne die Karte (M), steuere den Flieger aus der Karte heraus (WASD) und drück ALT+O.")
  tb.log(run, "FRAGE", "2) Steig aus, nimm die Spidertron-Fernbedienung in die Hand (ist sie weg: Verknüpfungsleiste unten rechts), " ..
    "klick damit auf den Flieger (er muss ausgewählt sein), öffne die Karte (M) und drück ALT+O.")
  tb.log(run, "FRAGE", "3) Schließ die Karte und drück in der normalen Ansicht ALT+O.")
  tb.log(run, "INFO", "Jeder Druck auf ALT+O schreibt eine MESSUNG-Zeile. Bitte melden, ob bei jedem Schritt eine kam " ..
    "(Datei schicken reicht). Ende nach 3 min oder mit /arrakis-test stop.")
end

local function t12_tick(run, tb)
  if game.tick - run.started >= T12_END_TICKS then
    local presses = run.data.presses or 0
    if presses == 0 then
      tb.log(run, "MESSUNG", "Keine Testtaste angekommen")
    end
    tb.finish(run, string.format("%d Tastendrücke gemessen", presses))
  end
end

local function t12_on_event(run, tb, name, event)
  local data = run.data
  if name == "test_key" then
    local player = event.player_index and game.get_player(event.player_index)
    if not player then return end
    data.presses = (data.presses or 0) + 1
    local who = player.index ~= run.player_index and (" (Spieler " .. player.name .. ")") or ""
    tb.log(run, "MESSUNG", string.format("Taste %d%s: %s", data.presses, who, t12_measure(run, tb, player, event)))
  elseif name == "driving_changed" then
    if event.player_index ~= run.player_index then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    local vehicle = read(function() return t12_entity_text(player.vehicle) end)
    local controller = read(function() return tb.enum_name(defines.controllers, player.controller_type) end)
    tb.log(run, "MESSUNG", string.format("Ein-/Ausstieg: vehicle = %s, controller_type = %s, Ereignis-Entity = %s",
      tostring(vehicle), tostring(controller), read(function() return t12_entity_text(event.entity) end)))
    -- Beim Aussteigen (Schritt 2) den Flieger wieder auswählen; geht nur mit Fernbedienung in der Hand.
    local flyer = data.flyer
    if not player.vehicle and flyer and flyer.valid then
      local ok, err = pcall(function() player.spidertron_remote_selection = {flyer} end)
      local count = read(function()
        local list = player.spidertron_remote_selection
        return list and #list or "nil"
      end)
      tb.log(run, "INFO", "Flieger nach dem Aussteigen wieder ausgewählt: " .. (ok and "ja" or ("nein (" .. tostring(err) .. ")"))
        .. ", Auswahl jetzt " .. tostring(count) .. " Einträge" .. (ok and "" or "; mit der Fernbedienung auf den Flieger klicken"))
    end
  end
end

return
{
  T1 =
  {
    title = "Flieger: Beine, Tempo, Gelände",
    timeout = 120 * 60,
    interactive = false,
    confirm = nil,
    start = t1_start,
    tick = t1_tick,
    on_event = t1_on_event,
    cleanup = t1_cleanup
  },
  T9 =
  {
    title = "Flieger: Schatten der Last",
    timeout = 60 * 60,
    interactive = true,
    confirm = nil,
    start = t9_start,
    tick = t9_tick,
    cleanup = t9_cleanup
  },
  T12 =
  {
    title = "Flieger: Rettung aus der Kartenansicht",
    timeout = 190 * 60,
    interactive = true,
    confirm = nil,
    start = t12_start,
    tick = t12_tick,
    on_event = t12_on_event
  }
}
