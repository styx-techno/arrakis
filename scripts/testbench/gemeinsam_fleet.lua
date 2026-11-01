-- Prüfstand: Leitstelle und Carryall-Automatik (Phase 3e, docs/plan-3e.md 7; Vertrag siehe runner.lua).
--   T23: scripts/fleet.lua mit dem echten Flieger-, Ernter-, Annahme- und Wurmcode auf der Prüfstand-Fläche
--        (terrain.harvest_allowed erlaubt sie mit der Startup-Einstellung). Force arrakis-t23, Jagden ohne Wurm
--        (worms_lib.set_worm_off): Der Biss fällt nach dem Countdown wie in 0.7.0. Zehn Schritte, je eine OK/FEHLER-Zeile.
--   T24: Dauerlauf, 60 min Spielzeit (Ziel aus docs/plan-3e.md: 60 min ohne Eingriff, kein Ernter verloren, keiner ohne
--        Treibstoff): eine Leitstelle, zwei Carryalls, vier Ernter, alle 75 s ein Wurmzeichen auf einen
--        aufgebauten Ernter; ein Ernter ist fast voll (Entladen), einer fast leer (Tanken).
--   T25: Ansicht (interaktiv, nur mit Spieler): Leitstelle, Carryall und Rettung vor Ort; FRAGE an Max.
--   T26: Flottenleitung (docs/plan-3f.md 4): Soll aus dem Fenster, Signal H, Rückruf Überzähliger ins Lager, Umsetzen,
--        Feldsuche (lauernder Wurm, Kartenmarkierung), Signal R; Statussignale in jedem Schritt. Sieben Schritte.
--   T27: Dauerlauf Flottenleitung, 60 min Spielzeit: 5 Ernter im Lager, H = 3, Felder werden leer, Wurmzeichen alle 75 s.
--   T28: Ansicht Flottenleitung (interaktiv): Fenster mit Soll und Rückruf-Knopf, Lampe am Draht; FRAGE an Max.
--   T29: 0.12.1 (docs/plan-3f.md 1.11 bis 1.13): Forschungen, Frühwarnung, Ernte-Dämpfung, Bereitschaftsflug.
-- Jeder Schritt baut seine Leitstelle neu (Abstand der Felder unter der Reichweite, siehe T23_PLACES) und räumt danach
-- alles ab (tidy, raise_destroy). Zustand nur in run.data (Zahlen, Texte, Positionen, LuaEntity-Referenzen, die Jagd
-- aus storage.hunts.list); Entities vor jeder Benutzung prüfen. Die Modultabelle von scripts/flyer.lua heißt flyer_lib
-- (tools/check/api_names.py hält flyer für LuaEntity).

local flyer_lib = require("scripts.flyer")
local fleet = require("scripts.fleet")
local fields = require("scripts.fleet-fields")
local harvester = require("scripts.harvester")
local worms_lib = require("scripts.worms")
local vibration_lib = require("scripts.vibration")

local CARRYALL = "arrakis-carryall"
local DEPOT = "arrakis-depot"
local NAME = "spice-harvester"
local MK2 = "spice-harvester-mk2"
local INTAKE = "arrakis-spice-intake"
local SPICE = "spice-sand"
local ROCK = "arrakis-rock"
local FLIGHT_FUEL = "rocket-fuel"
local T23_FORCE = "arrakis-t23"
-- Testfläche: Felsinsel mit Leitstelle und Annahme links, Felder auf Sand rechts davon (relativ zum Testbereich).
local T23_HALF = {x = 200, y = 45}
local T23_PLACES =
{
  depot = {x = -150, y = 0},
  island = {x1 = -165, y1 = -14, x2 = -125, y2 = 14},
  intake = {x = -135, y = -6},
  carryall = {x = -150, y = 8},
  carryall2 = {x = -146, y = 8},
  carryall3 = {x = -154, y = 8},
  rescue = {x = -50, y = 0},       -- 100 Kacheln: Rettung in 45 s gut machbar
  far = {x = 100, y = 0},          -- 250 Kacheln: in 10 s nicht erreichbar
  unload = {x = -80, y = -25},
  refuel = {x = -90, y = 25},
  manual = {x = -150, y = 32},     -- Ziel der „Fernbedienung“ in Schritt 7 (Sand)
  soak_d = {x = -20, y = 22},
  watch = {x = -125, y = 18}
}
local T23_GAP = 10
local T23_RESCUE_SECONDS = 45

local function valid(object)
  return object ~= nil and object.valid
end

local function fleet_distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function at(origin, dx, dy)
  return {x = origin.x + dx, y = origin.y + dy}
end

local function pos_text(tb, position)
  if not position then return "–" end
  return tb.num(position.x) .. ", " .. tb.num(position.y)
end

local function t23_force()
  local force = game.forces[T23_FORCE] or game.create_force(T23_FORCE)
  worms_lib.set_worm_off(force, true)
  return force
end

-- Entities --------------------------------------------------------------------------------------------

local function create(run, tb, params, kind)
  local ok, entity = pcall(function() return tb.surface().create_entity(params) end)
  if ok and entity then
    table.insert(run.data.made[kind or "others"], entity)
    return entity
  end
  tb.trace(run, params.name .. " bei " .. pos_text(tb, params.position) .. " ging nicht" .. (ok and "" or (": " .. tostring(entity))))
  return nil
end

-- Zuerst Ernter (auch auf der Ablage: flyer.lua leert den Träger), dann Flieger, dann der Rest.
local function tidy(run)
  local made = run.data.made
  if not made then return end
  for _, kind in ipairs({"cars", "flyers", "others"}) do
    for _, entity in pairs(made[kind]) do
      if valid(entity) then pcall(function() entity.destroy{raise_destroy = true} end) end
    end
    made[kind] = {}
  end
end

local function place_spice(surface, center, half, amount)
  local placed = 0
  for x = math.floor(center.x) - half, math.floor(center.x) + half do
    for y = math.floor(center.y) - half, math.floor(center.y) + half do
      if surface.create_entity{name = SPICE, position = {x + 0.5, y + 0.5}, amount = amount} then placed = placed + 1 end
    end
  end
  return placed
end

local function item_count(inventory, name)
  if not inventory then return 0 end
  return name and inventory.get_item_count(name) or inventory.get_item_count()
end

local function burner_count(entity, name)
  local burner = valid(entity) and entity.burner
  return burner and item_count(burner.inventory, name) or 0
end

local function trunk_of(carryall)
  return valid(carryall) and carryall.get_inventory(defines.inventory.spider_trunk)
end

local function fuel_items(car)
  local inventory = valid(car) and car.get_fuel_inventory()
  return inventory and inventory.get_item_count() or 0
end

local function record_of(carryall)
  return valid(carryall) and flyer_lib.get(carryall)
end

local function h_of(car)
  return valid(car) and harvester.get(car)
end

local function state_of(car)
  local h = h_of(car)
  return h and h.state or (valid(car) and "?" or "weg")
end

-- Leitstelle mit Vorrat und Carryall(s) mit 2 Raketentreibstoff; opts.carryalls (Standard 1), opts.rocket, opts.coal.
local function build_base(run, tb, d, s, opts)
  opts = opts or {}
  local force = t23_force()
  s.depot = create(run, tb, {name = DEPOT, position = d.pos.depot, force = force, raise_built = true}, "others")
  if not s.depot then return false end
  local inventory = s.depot.get_inventory(defines.inventory.chest)
  inventory.insert{name = FLIGHT_FUEL, count = opts.rocket or 20}
  inventory.insert{name = "coal", count = opts.coal or 300}
  s.carryalls = {}
  for i = 1, opts.carryalls or 1 do
    local place = ({d.pos.carryall, d.pos.carryall2, d.pos.carryall3})[i] or d.pos.carryall2
    local car = create(run, tb, {name = CARRYALL, position = place, force = force, raise_built = true,
      create_build_effect_smoke = false}, "flyers")
    if not car then return false end
    car.get_fuel_inventory().insert{name = FLIGHT_FUEL, count = 2}
    table.insert(s.carryalls, car)
  end
  s.carryall = s.carryalls[1]
  s.base_tick = game.tick
  return true
end

-- Geparkt und aufgefüllt: Leitstelle zugeordnet, ≤ 3 Kacheln von ihrer Mitte, Raketentreibstoff ≥ 5, Kohle ≥ 50.
local function parked(s, carryall)
  carryall = carryall or s.carryall
  local record = record_of(carryall)
  if not (record and valid(s.depot)) then return false end
  return record.depot == s.depot.unit_number and record.fleet_mode == "auto" and not record.job
    and not record.cargo and fleet_distance(carryall.position, s.depot.position) <= 3
    and burner_count(carryall, FLIGHT_FUEL) >= 5 and item_count(trunk_of(carryall), "coal") >= 50
end

-- Echter Ernter der Force arrakis-t23 auf einem Spicefeld 13×13; opts: coal (Standard 50), fill (Slots Spice-Sand),
-- name (Standard Ernter; T35 baut den Mk2).
local function new_harvester(run, tb, d, position, opts)
  opts = opts or {}
  local surface = tb.surface()
  place_spice(surface, position, 6, 100000)
  local car = create(run, tb, {name = opts.name or NAME, position = {x = position.x + 0.5, y = position.y + 0.5}, force = t23_force(),
    orientation = 0.25, raise_built = true}, "cars")
  if not car then return nil end
  if (opts.coal or 50) > 0 then tb.fuel(car, "coal", opts.coal or 50) end
  if opts.fill then
    local stack = prototypes.item[SPICE].stack_size
    car.get_inventory(defines.inventory.car_trunk).insert{name = SPICE, count = opts.fill * stack}
  end
  local h = harvester.get(car) or harvester.register(car)
  if h then harvester.deploy(h) end
  return car
end

local function verdict(run, tb, number, title, failed, values)
  local level = #failed == 0 and "OK" or "FEHLER"
  local text = number .. ") " .. title .. ": " .. values
  if #failed > 0 then text = text .. " | nicht erfüllt: " .. table.concat(failed, "; ") end
  tb.log(run, level, text)
  run.data.results[number] = level
  return "end"
end

local function fail(run, tb, number, text)
  tb.log(run, "FEHLER", number .. ") " .. text)
  run.data.results[number] = "FEHLER"
  return "end"
end

local function check(failed, ok, label)
  if not ok then table.insert(failed, label) end
end

-- Warten auf eine Bedingung: "poll" bis cond() wahr (dann 1, nächste Phase) oder bis s.deadline (dann on_timeout()).
local function wait_for(s, cond, on_timeout)
  if cond() then
    s.deadline = nil
    return 1
  end
  if game.tick >= s.deadline then
    s.deadline = nil
    return on_timeout()
  end
  return "poll"
end

-- Gemeinsame Phasen: Grundaufbau und Warten aufs Parken.
local function base_phase(number, opts)
  return function(run, tb, d)
    local s = d["s" .. number]
    if not build_base(run, tb, d, s, opts) then return fail(run, tb, number, "Leitstelle oder Carryall ließ sich nicht bauen") end
    s.deadline = game.tick + 25 * 60
    return 1
  end
end

local function parked_phase(number)
  return function(run, tb, d)
    local s = d["s" .. number]
    return wait_for(s, function()
      for _, carryall in ipairs(s.carryalls) do
        if not parked(s, carryall) then return false end
      end
      s.parked_tick = game.tick
      return true
    end, function()
      local record = record_of(s.carryall)
      return fail(run, tb, number, string.format("Carryall parkt nicht in 25 s: Leitstelle %s, Abstand %s, Raketentreibstoff %d, Kohle im Kofferraum %d",
        tostring(record and record.depot), valid(s.carryall) and valid(s.depot) and tb.num(fleet_distance(s.carryall.position, s.depot.position)) or "–",
        burner_count(s.carryall, FLIGHT_FUEL), item_count(trunk_of(s.carryall), "coal")))
    end)
  end
end

local function summary(run, steps)
  local ok, wrong = 0, {}
  for number = 1, #steps do
    if run.data.results[number] == "OK" then ok = ok + 1 else table.insert(wrong, tostring(number)) end
  end
  local text = string.format("%d/%d Schritte OK", ok, #steps)
  if #wrong > 0 then text = text .. ", FEHLER in " .. table.concat(wrong, ", ") end
  return text
end

-- Fläche vorbereiten: Sand, Felsinsel mit Leitstellen- und Annahmeplatz; Orte relativ zum Testbereich.
local function prepare(run, tb)
  local d = run.data
  local origin = tb.area(run.id)
  d.made = {cars = {}, flyers = {}, others = {}}
  d.results = {}
  d.pos = {}
  for key, offset in pairs(T23_PLACES) do
    if offset.x then d.pos[key] = at(origin, offset.x, offset.y) end
  end
  local i = T23_PLACES.island
  tb.prepare(origin, T23_HALF)
  tb.fill({{origin.x + i.x1, origin.y + i.y1}, {origin.x + i.x2, origin.y + i.y2}}, ROCK)
  t23_force()
  storage.fleet_pause_until = nil
end

-- Aufräumen nach jedem Schritt, über den Namen in d.after_step (run.data liegt in storage, Funktionen lassen sich
-- nicht speichern: PC-Lauf 6fe82de brach beim Autosave mit „Cannot serialise lua functions“ ab).
local AFTER_STEP = {}

local function run_steps(run, tb, steps)
  local d = run.data
  if not d.step or game.tick < d.wait_until then return end
  local step = steps[d.step]
  if not step then
    d.step = nil
    tb.finish(run, summary(run, steps))
    return
  end
  local phase = step[d.phase]
  local result
  if not phase then
    if not d.results[d.step] then fail(run, tb, d.step, "keine Ergebniszeile (Prüfstand-Fehler)") end
    result = "end"
  else
    local ok, value = pcall(phase, run, tb, d)
    if not ok then
      fail(run, tb, d.step, "Skriptfehler: " .. tostring(value))
      value = "end"
    end
    result = value
  end
  if result == "poll" then return end
  if result == "keep" then
    -- Nächster Schritt auf demselben Aufbau (T26 Schritte 2 bis 5): nichts abräumen.
    d.step, d.phase = d.step + 1, 1
    d.wait_until = game.tick + T23_GAP
    return
  end
  if result == "end" then
    local ok, err = pcall(tidy, run)
    if not ok then tb.trace(run, "Aufräumen nach Schritt " .. d.step .. " ging nicht: " .. tostring(err)) end
    if d.after_step then
      ok, err = pcall(AFTER_STEP[d.after_step], run, tb)
      if not ok then tb.trace(run, "Aufräumen nach Schritt " .. d.step .. " ging nicht: " .. tostring(err)) end
    end
    d.step, d.phase = d.step + 1, 1
    d.wait_until = game.tick + T23_GAP
  else
    d.phase = d.phase + 1
    d.wait_until = game.tick + (type(result) == "number" and result or 1)
  end
end

-- T26 Flottenleitung -----------------------------------------------------------------------------------
-- Gleiche Fläche wie T23 (Felsinsel links, Sand rechts). Die Force arrakis-t23 bekommt für T26 bis T28 die Forschung
-- „Flottenleitung“; das Aufräumen nimmt sie wieder weg. Ernter, die die Leitstelle aus dem Lager einsetzt, stehen nicht in
-- run.data.made: sweep räumt nach jedem Schritt alle Ernter, Spice-Sand und Kartenmarkierungen im Testbereich ab.

local FLEET_TECH = "arrakis-fleet-control"
local SIGNAL_SLOTS = {H = 1, R = 2}
-- Spicefelder 13×13 mit je 2000 Spice-Sand je Kachel (338 000 im Erntekreis), relativ zum Testbereich.
local T26_FIELDS = {{x = -90, y = -22}, {x = -40, y = 22}, {x = 10, y = -22}, {x = 60, y = 22}, {x = 110, y = -22},
  {x = -100, y = 32}}
local T26_AMOUNT = 2000

local function fleet_force(on)
  local force = t23_force()
  local tech = force.technologies[FLEET_TECH]
  if tech then tech.researched = on end
  return force
end

local function depot_record(s)
  return valid(s.depot) and fleet.depot_of(s.depot.unit_number)
end

local function depot_items(s, name)
  return valid(s.depot) and item_count(s.depot.get_inventory(defines.inventory.chest), name) or 0
end

-- Ernter der Leitstelle (fleet_owner) und alle Ernter im Testbereich, nach Zustand gezählt.
local function owned(s, state)
  local list = {}
  local un = valid(s.depot) and s.depot.unit_number
  for _, h in pairs(storage.harvesters) do
    if h.fleet_owner == un and h.entity.valid and (not state or h.state == state) then table.insert(list, h) end
  end
  table.sort(list, function(a, b) return a.un < b.un end)
  return list
end

local function depot_jobs(s)
  local n = 0
  local un = valid(s.depot) and s.depot.unit_number
  for _, job in pairs(storage.jobs.list) do
    if job.depot == un then n = n + 1 end
  end
  return n
end

-- Signal H oder R über ein Konstant-Schaltungsgebäude neben der Leitstelle (grüner Draht); 0 löscht.
local function set_wire_signal(run, tb, s, letter, value)
  if not valid(s.box) then
    s.box = create(run, tb, {name = "constant-combinator", position = at(s.depot.position, 3, -4), force = t23_force()},
      "others")
    if not s.box then return false end
    s.box.get_wire_connector(defines.wire_connector_id.circuit_green, true).connect_to(
      s.depot.get_wire_connector(defines.wire_connector_id.circuit_green, true), false)
  end
  local behavior = s.box.get_or_create_control_behavior()
  local section = behavior.get_section(1) or behavior.add_section()
  local slot = SIGNAL_SLOTS[letter]
  if value > 0 then
    section.set_slot(slot, {value = {type = "virtual", name = "signal-" .. letter, quality = "normal"}, min = value})
  else
    section.clear_slot(slot)
  end
  return true
end

local function place_fields(tb, d, list)
  local surface = tb.surface()
  local origin = tb.area(d.run_id)
  local placed = {}
  for _, offset in ipairs(list) do
    local p = at(origin, offset.x, offset.y)
    place_spice(surface, p, 6, T26_AMOUNT)
    table.insert(placed, {x = math.floor(p.x) + 0.5, y = math.floor(p.y) + 0.5})
  end
  return placed
end

local function chart_area(tb, d)
  local origin = tb.area(d.run_id)
  t23_force().chart(tb.surface(), {{origin.x - T23_HALF.x, origin.y - T23_HALF.y}, {origin.x + T23_HALF.x, origin.y + T23_HALF.y}})
end

local function charted(tb, points)
  local force = t23_force()
  for _, p in ipairs(points) do
    if not force.is_chunk_charted(tb.surface(), {math.floor(p.x / 32), math.floor(p.y / 32)}) then return false end
  end
  return true
end

-- Ohne Spieler kartiert force.chart auf dem Server nichts (V6, wie T18 Schritt 2, PC-Lauf 0.12.0): Die Feldsuche zählt
-- dann im Test auch nicht kartierte Chunks (fields.skip_chart bis zum nächsten fields.reset).
local function skip_chart(run, tb, label)
  fields.skip_chart()
  tb.log(run, "INFO", label .. "Chunks nach 10 s nicht kartiert (ohne Spieler, V6): Feldsuche im Test ohne Kartierungsprüfung")
end

-- T27, T28: 10 s nach dem Start einmal prüfen.
local function chart_or_skip(run, tb, s)
  if s.chart_checked or game.tick < s.start + 600 then return end
  s.chart_checked = true
  if not charted(tb, s.fields) then skip_chart(run, tb, "") end
end

-- Alles im Testbereich weg: Ernter (auch getragene der Leitstelle), Spice-Sand, Kartenmarkierungen, lauernde Würmer.
local function sweep(run, tb)
  local surface = tb.surface()
  local origin = tb.area(run.id)
  local area = {{origin.x - T23_HALF.x - 10, origin.y - T23_HALF.y - 10}, {origin.x + T23_HALF.x + 10, origin.y + T23_HALF.y + 10}}
  local force = game.forces[T23_FORCE]
  for un, h in pairs(storage.harvesters) do
    local e = h.entity
    if e and e.valid and e.force == force and (h.state == "carried" or h.fleet_owner) then
      pcall(function() e.destroy{raise_destroy = true} end)
    end
  end
  for _, name in ipairs({NAME, MK2, SPICE, "constant-combinator"}) do
    for _, e in pairs(surface.find_entities_filtered{name = name, area = area}) do
      if e.valid then pcall(function() e.destroy{raise_destroy = true} end) end
    end
  end
  if force then
    for _, tag in pairs(force.find_chart_tags(surface, area)) do tag.destroy() end
  end
  worms_lib.clear_lurk(surface.index)
  fields.reset()
end

AFTER_STEP.sweep = sweep

-- Feld leeren: Spice-Sand bis 10 Kacheln um die Stelle (mehr als der Erntekreis, damit kein Rest daneben bleibt).
local function empty_field(tb, position)
  local area = {{position.x - 10, position.y - 10}, {position.x + 10, position.y + 10}}
  for _, e in pairs(tb.surface().find_entities_filtered{name = SPICE, area = area}) do e.destroy() end
end

-- Für die Testdateien scripts/testbench/tests/ (eine je Test; aufgeteilt aus t_fleet.lua, Verhalten unverändert).
return
{
  flyer_lib = flyer_lib,
  fleet = fleet,
  fields = fields,
  harvester = harvester,
  worms_lib = worms_lib,
  vibration_lib = vibration_lib,
  CARRYALL = CARRYALL,
  DEPOT = DEPOT,
  NAME = NAME,
  MK2 = MK2,
  INTAKE = INTAKE,
  SPICE = SPICE,
  ROCK = ROCK,
  FLIGHT_FUEL = FLIGHT_FUEL,
  T23_FORCE = T23_FORCE,
  T23_HALF = T23_HALF,
  T23_PLACES = T23_PLACES,
  T23_GAP = T23_GAP,
  T23_RESCUE_SECONDS = T23_RESCUE_SECONDS,
  valid = valid,
  fleet_distance = fleet_distance,
  at = at,
  pos_text = pos_text,
  t23_force = t23_force,
  create = create,
  tidy = tidy,
  place_spice = place_spice,
  item_count = item_count,
  burner_count = burner_count,
  trunk_of = trunk_of,
  fuel_items = fuel_items,
  record_of = record_of,
  h_of = h_of,
  state_of = state_of,
  build_base = build_base,
  parked = parked,
  new_harvester = new_harvester,
  verdict = verdict,
  fail = fail,
  check = check,
  wait_for = wait_for,
  base_phase = base_phase,
  parked_phase = parked_phase,
  summary = summary,
  prepare = prepare,
  AFTER_STEP = AFTER_STEP,
  run_steps = run_steps,
  FLEET_TECH = FLEET_TECH,
  SIGNAL_SLOTS = SIGNAL_SLOTS,
  T26_FIELDS = T26_FIELDS,
  T26_AMOUNT = T26_AMOUNT,
  fleet_force = fleet_force,
  depot_record = depot_record,
  depot_items = depot_items,
  owned = owned,
  depot_jobs = depot_jobs,
  set_wire_signal = set_wire_signal,
  place_fields = place_fields,
  chart_area = chart_area,
  charted = charted,
  skip_chart = skip_chart,
  chart_or_skip = chart_or_skip,
  sweep = sweep,
  empty_field = empty_field,
}
