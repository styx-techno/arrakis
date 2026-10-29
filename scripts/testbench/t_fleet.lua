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
-- Jeder Schritt baut seine Leitstelle neu (Abstand der Felder unter der Reichweite, siehe T23_PLACES) und räumt danach
-- alles ab (tidy, raise_destroy). Zustand nur in run.data (Zahlen, Texte, Positionen, LuaEntity-Referenzen, die Jagd
-- aus storage.hunts.list); Entities vor jeder Benutzung prüfen. Die Modultabelle von scripts/flyer.lua heißt flyer_lib
-- (tools/check/api_names.py hält flyer für LuaEntity).

local flyer_lib = require("scripts.flyer")
local fleet = require("scripts.fleet")
local fields = require("scripts.fleet-fields")
local harvester = require("scripts.harvester")
local intake = require("scripts.intake")
local worms_lib = require("scripts.worms")
local vibration_lib = require("scripts.vibration")
local speed = require("prototypes.ornithopter-speed")

local CARRYALL = "arrakis-carryall"
local DEPOT = "arrakis-depot"
local NAME = "spice-harvester"
local INTAKE = "arrakis-spice-intake"
local SPICE = "spice-sand"
local ROCK = "arrakis-rock"
local FLIGHT_FUEL = "rocket-fuel"
local T23_FORCE = "arrakis-t23"

-- Erwartetes Tempo leer mit Raketentreibstoff (Kacheln/s): Ornithopter 8,0 (T16) mal 1,125, ±10 %.
local T23_SPEED = 8 * 1.125
local T23_SPEED_TOL = 0.1
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
local T23_FAR_SECONDS = 10

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

-- Echter Ernter der Force arrakis-t23 auf einem Spicefeld 13×13; opts: coal (Standard 50), fill (Slots Spice-Sand).
local function new_harvester(run, tb, d, position, opts)
  opts = opts or {}
  local surface = tb.surface()
  place_spice(surface, position, 6, 100000)
  local car = create(run, tb, {name = NAME, position = {x = position.x + 0.5, y = position.y + 0.5}, force = t23_force(),
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

local function job_of(car)
  local h = h_of(car)
  return h and fleet.job_of_harvester(h.un)
end

local function hunt_alive(hunt)
  return hunt ~= nil and storage.hunts.list[hunt.id] == hunt
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

-- T23 Schritte ---------------------------------------------------------------------------------------

local t23 = {}

-- 1) Prototypen und storage (Laufzeit lesbar).
function t23.s1(run, tb, d)
  local failed = {}
  local car = prototypes.entity[CARRYALL]
  local depot = prototypes.entity[DEPOT]
  check(failed, car ~= nil and car.type == "spider-vehicle", "arrakis-carryall fehlt oder kein spider-vehicle")
  check(failed, depot ~= nil and depot.type == "container", "arrakis-depot fehlt oder kein container")
  local categories = car and car.burner_prototype and car.burner_prototype.fuel_categories or {}
  check(failed, categories[speed.FUEL_CATEGORY] == true and table_size(categories) == 1, "Brenner nicht nur Flugtreibstoff")
  check(failed, depot ~= nil and depot.get_inventory_size(defines.inventory.chest) == 48, "Leitstelle nicht 48 Slots")
  local stickers = 0
  for _, state in ipairs(speed.KIND_STATES.carryall) do
    for j = speed.MIN_J, speed.MAX_J do
      if prototypes.entity[speed.name(state, j)] then stickers = stickers + 1 end
    end
  end
  check(failed, stickers == 2 * speed.COUNT, stickers .. " Carryall-Sticker statt " .. 2 * speed.COUNT)
  check(failed, fleet.RANGE == settings.startup["arrakis-depot-range"].value, "fleet.RANGE passt nicht zur Einstellung")
  check(failed, storage.depots ~= nil and storage.jobs ~= nil and storage.jobs.list ~= nil and storage.job_of ~= nil
    and storage.jobs.refused ~= nil, "storage Schema 5 fehlt")
  check(failed, storage.schema >= 5, "storage.schema " .. tostring(storage.schema))
  return verdict(run, tb, 1, "Prototypen und storage", failed, string.format("Sticker %d, Reichweite %d, Schema %s",
    stickers, fleet.RANGE, tostring(storage.schema)))
end

-- 2) Ein neuer Carryall gehört zur Leitstelle, parkt und füllt Flugtreibstoff und Ernter-Treibstoff nach.
function t23.s2_check(run, tb, d)
  local s = d.s2
  local record = record_of(s.carryall)
  local failed = {}
  check(failed, record and record.kind == "carryall", "Datensatz kind ~= carryall")
  check(failed, burner_count(s.carryall, "coal") == 0, "Kohle im Brennstofffach")
  local trunk = trunk_of(s.carryall)
  local coal_stacks = 0
  for i = 1, #trunk do
    if trunk[i].valid_for_read and trunk[i].name == "coal" then coal_stacks = coal_stacks + 1 end
  end
  check(failed, coal_stacks <= fleet.TRUNK_STACKS, coal_stacks .. " Stapel Kohle statt höchstens " .. fleet.TRUNK_STACKS)
  return verdict(run, tb, 2, "Leitstelle übernimmt und füllt nach", failed, string.format(
    "geparkt nach %s s, Raketentreibstoff %d, Kohle im Kofferraum %d (%d Stapel), Leitstelle noch %d Raketentreibstoff",
    tb.num((s.parked_tick - s.base_tick) / 60), burner_count(s.carryall, FLIGHT_FUEL), item_count(trunk, "coal"),
    coal_stacks, item_count(s.depot.get_inventory(defines.inventory.chest), FLIGHT_FUEL)))
end

-- 3) Rettung: Wurmzeichen 45 s auf einen Ernter 100 Kacheln weit. Anheben vor dem Biss, zur Leitstelle bringen und dort
-- abstellen (0.11.0), nach dem Ende der Jagd zurückbringen und wieder aufbauen; Tempo leer zwischen 2 s und 4 s Flug.
-- Die Befehlsjagd hinterlässt keinen lauernden Wurm, deshalb geht der Rückflug gleich nach der Jagd los.
function t23.s3_build(run, tb, d)
  local s = d.s3
  s.car = new_harvester(run, tb, d, d.pos.rescue)
  if not s.car then return fail(run, tb, 3, "Ernter ließ sich nicht bauen") end
  s.origin = {x = s.car.position.x, y = s.car.position.y}
  return harvester.DEPLOY_TICKS + 10
end

function t23.s3_hunt(run, tb, d)
  local s = d.s3
  if state_of(s.car) ~= "deployed" then return fail(run, tb, 3, "Ernter baut nicht auf (" .. state_of(s.car) .. ")") end
  local hunt, reason = worms_lib.start_hunt(s.car, {seconds = T23_RESCUE_SECONDS, debug = true})
  if not hunt then return fail(run, tb, 3, "start_hunt: " .. tostring(reason)) end
  s.hunt = hunt
  s.eta = hunt.eta_tick
  s.start = game.tick
  s.deadline = s.eta + 90 * 60
  return 1
end

function t23.s3_watch(run, tb, d)
  local s = d.s3
  local tick = game.tick
  local record = record_of(s.carryall)
  local job = job_of(s.car)
  if job and not s.job_tick then
    s.job_tick = tick
    s.job_kind = job.kind
  end
  if record and record.job and not s.fly_tick and fleet_distance(s.carryall.position, s.depot.position) > 5 then
    s.fly_tick = tick + 60
  end
  if s.fly_tick and tick == s.fly_tick then s.p0 = {x = s.carryall.position.x, y = s.carryall.position.y} end
  if s.fly_tick and tick == s.fly_tick + 120 and s.p0 then
    s.speed = fleet_distance(s.carryall.position, s.p0) / 2
  end
  if state_of(s.car) == "carried" and not s.lift_tick then s.lift_tick = tick end
  if s.hunt and not s.outcome and s.hunt.outcome then s.outcome = s.hunt.outcome end
  if s.hunt and not hunt_alive(s.hunt) and not s.outcome then s.outcome = s.hunt.outcome or "?" end
  if s.hunt and not hunt_alive(s.hunt) and not s.end_tick then s.end_tick = tick end
  local h = h_of(s.car)
  if h and h.fleet_wait and not s.safe_tick then
    s.safe_tick = tick
    s.base_dist = fleet_distance(s.car.position, s.depot.position)
  end
  local back = s.safe_tick and h and (h.state == "deploying" or h.state == "deployed")
    and fleet_distance(s.car.position, s.origin) <= 6
  if back and not s.back_tick then s.back_tick = tick end
  if s.back_tick and parked(s) then
    s.home_tick = tick
    return 1
  end
  if tick >= s.deadline or not valid(s.car) then return 1 end
  return "poll"
end

function t23.s3_check(run, tb, d)
  local s = d.s3
  local failed = {}
  check(failed, s.job_kind == "rescue", "kein Rettungsauftrag (" .. tostring(s.job_kind) .. ")")
  check(failed, s.lift_tick ~= nil and s.lift_tick < s.eta, "nicht vor dem Biss angehoben")
  check(failed, s.outcome == "escaped", "Jagd endet " .. tostring(s.outcome) .. " statt escaped")
  check(failed, s.base_dist ~= nil and s.base_dist <= 15, "nicht an der Leitstelle abgestellt (Abstand "
    .. (s.base_dist and tb.num(s.base_dist) or "–") .. ")")
  check(failed, s.back_tick ~= nil, "Ernter nicht zurück am Feld aufgebaut (" .. state_of(s.car) .. ")")
  check(failed, s.back_tick == nil or (s.end_tick ~= nil and s.back_tick > s.end_tick), "zurück am Feld vor dem Ende der Jagd")
  check(failed, s.home_tick ~= nil, "Carryall nicht zurück an der Leitstelle")
  check(failed, s.speed ~= nil and math.abs(s.speed - T23_SPEED) <= T23_SPEED * T23_SPEED_TOL,
    "Tempo " .. tb.num(s.speed) .. " statt " .. tb.num(T23_SPEED) .. " ±10 %")
  tb.log(run, "MESSUNG", string.format("T23 Carryall leer mit Raketentreibstoff: %s Kacheln/s (Ornithopter 8,0)", tb.num(s.speed, 2)))
  local function since(t) return t and tb.num((t - s.start) / 60) or "–" end
  return verdict(run, tb, 3, "Rettung bei Wurmzeichen", failed, string.format(
    "Auftrag nach %s s, angehoben nach %s s (Biss bei %s s), an der Leitstelle nach %s s (%s Kacheln von ihrer Mitte), Jagd %s,"
    .. " zurück aufgebaut nach %s s, geparkt nach %s s, Tempo %s",
    since(s.job_tick), since(s.lift_tick), tb.num((s.eta - s.start) / 60), since(s.safe_tick), s.base_dist and tb.num(s.base_dist) or "–",
    tostring(s.outcome), since(s.back_tick), since(s.home_tick), tb.num(s.speed, 2)))
end

-- 4) Ehrliche Absage: 250 Kacheln, 10 s Countdown. Kein Auftrag, Absage einmal vermerkt, Carryall bleibt stehen.
function t23.s4_build(run, tb, d)
  local s = d.s4
  s.car = new_harvester(run, tb, d, d.pos.far)
  if not s.car then return fail(run, tb, 4, "Ernter ließ sich nicht bauen") end
  return harvester.DEPLOY_TICKS + 10
end

function t23.s4_hunt(run, tb, d)
  local s = d.s4
  if state_of(s.car) ~= "deployed" then return fail(run, tb, 4, "Ernter baut nicht auf (" .. state_of(s.car) .. ")") end
  local hunt, reason = worms_lib.start_hunt(s.car, {seconds = T23_FAR_SECONDS, debug = true})
  if not hunt then return fail(run, tb, 4, "start_hunt: " .. tostring(reason)) end
  s.hunt = hunt
  s.un = h_of(s.car).un
  s.deadline = hunt.eta_tick + 3 * 60
  return 1
end

function t23.s4_watch(run, tb, d)
  local s = d.s4
  if storage.job_of[s.un] then s.job_seen = true end
  local record = record_of(s.carryall)
  if record and record.job then s.carryall_busy = true end
  if storage.jobs.refused[s.hunt.id] then s.refused = true end
  if s.hunt.outcome then s.outcome = s.hunt.outcome end
  if game.tick >= s.deadline then return 1 end
  return "poll"
end

function t23.s4_check(run, tb, d)
  local s = d.s4
  local failed = {}
  check(failed, s.refused == true, "Absage nicht vermerkt (storage.jobs.refused)")
  check(failed, not s.job_seen, "Auftrag blieb stehen (job_of gesetzt)")
  check(failed, not s.carryall_busy, "Carryall bekam einen Auftrag")
  check(failed, valid(s.carryall) and fleet_distance(s.carryall.position, s.depot.position) <= 3, "Carryall ist losgeflogen")
  check(failed, s.outcome == "bitten", "Jagd endet " .. tostring(s.outcome) .. " statt bitten")
  return verdict(run, tb, 4, "Ehrliche Absage", failed, string.format("Absage %s, Auftrag gesehen %s, Jagd %s",
    tostring(s.refused), tostring(s.job_seen == true), tostring(s.outcome)))
end

-- 5) Entladen: Ernter mit 37 von 40 Slots Spice-Sand. Zur Annahme tragen, andocken, (Greifarme simuliert: der Test
-- leert den Laderaum), zurück und wieder aufbauen.
function t23.s5_build(run, tb, d)
  local s = d.s5
  s.intake = create(run, tb, {name = INTAKE, position = d.pos.intake, force = t23_force(), raise_built = true}, "others")
  local record = s.intake and intake.get(s.intake)
  if not (record and not record.bad) then return fail(run, tb, 5, "Annahme auf der Felsinsel nicht richtig eingetragen") end
  s.car = new_harvester(run, tb, d, d.pos.unload, {fill = 37})
  if not s.car then return fail(run, tb, 5, "Ernter ließ sich nicht bauen") end
  s.origin = {x = s.car.position.x, y = s.car.position.y}
  s.start = game.tick
  s.deadline = game.tick + 120 * 60
  return 1
end

function t23.s5_watch(run, tb, d)
  local s = d.s5
  local tick = game.tick
  local job = job_of(s.car)
  if job and not s.job_tick then
    s.job_tick = tick
    s.job_kind = job.kind
  end
  local state = state_of(s.car)
  if state == "carried" and not s.lift_tick then s.lift_tick = tick end
  if state == "docked" and not s.dock_tick then
    s.dock_tick = tick
    s.dock_dist = fleet_distance(s.car.position, s.intake.position)
    local trunk = s.car.get_inventory(defines.inventory.car_trunk)
    s.unloaded = item_count(trunk, SPICE)
    trunk.clear()
  end
  local h = h_of(s.car)
  if s.dock_tick and h and (h.state == "deploying" or h.state == "deployed") and fleet_distance(s.car.position, s.origin) <= 6
      and not s.back_tick then
    s.back_tick = tick
  end
  if s.back_tick and parked(s) then
    s.home_tick = tick
    return 1
  end
  if tick >= s.deadline or not valid(s.car) then return 1 end
  return "poll"
end

function t23.s5_check(run, tb, d)
  local s = d.s5
  local failed = {}
  check(failed, s.job_kind == "unload", "kein Entladeauftrag (" .. tostring(s.job_kind) .. ")")
  check(failed, s.dock_tick ~= nil, "Ernter dockt nicht an der Annahme an (" .. state_of(s.car) .. ")")
  check(failed, s.back_tick ~= nil, "Ernter nicht zurück am Feld aufgebaut (" .. state_of(s.car) .. ")")
  check(failed, s.home_tick ~= nil, "Carryall nicht zurück an der Leitstelle")
  local function since(t) return t and tb.num((t - s.start) / 60) or "–" end
  return verdict(run, tb, 5, "Entladen an der Annahme", failed, string.format(
    "Auftrag nach %s s, angehoben nach %s s, angedockt nach %s s (Abstand %s, %s Spice-Sand), zurück nach %s s, geparkt nach %s s",
    since(s.job_tick), since(s.lift_tick), since(s.dock_tick), tb.num(s.dock_dist), tostring(s.unloaded), since(s.back_tick),
    since(s.home_tick)))
end

-- 6) Tanken: Ernter mit 2 Kohle; der Carryall bringt Kohle aus dem Kofferraum.
function t23.s6_build(run, tb, d)
  local s = d.s6
  s.car = new_harvester(run, tb, d, d.pos.refuel, {coal = 2})
  if not s.car then return fail(run, tb, 6, "Ernter ließ sich nicht bauen") end
  s.trunk_before = item_count(trunk_of(s.carryall), "coal")
  s.start = game.tick
  s.deadline = game.tick + 60 * 60
  return 1
end

function t23.s6_watch(run, tb, d)
  local s = d.s6
  local job = job_of(s.car)
  if job and not s.job_kind then s.job_kind = job.kind end
  if fuel_items(s.car) > 10 and not s.fuel_tick then
    s.fuel_tick = game.tick
    s.fuel = fuel_items(s.car)
  end
  if s.fuel_tick and parked(s) then
    s.home_tick = game.tick
    return 1
  end
  if game.tick >= s.deadline then return 1 end
  return "poll"
end

function t23.s6_check(run, tb, d)
  local s = d.s6
  local failed = {}
  check(failed, s.job_kind == "refuel", "kein Tankauftrag (" .. tostring(s.job_kind) .. ")")
  check(failed, s.fuel_tick ~= nil, "Ernter nicht betankt (" .. fuel_items(s.car) .. " Brennstoff)")
  check(failed, state_of(s.car) == "deployed", "Ernter nicht mehr aufgebaut (" .. state_of(s.car) .. ")")
  check(failed, s.home_tick ~= nil, "Carryall nicht zurück an der Leitstelle (oder ohne Nachschub)")
  local function since(t) return t and tb.num((t - s.start) / 60) or "–" end
  return verdict(run, tb, 6, "Tanken", failed, string.format("betankt nach %s s auf %s Kohle (Kofferraum vorher %d), geparkt nach %s s",
    since(s.fuel_tick), tostring(s.fuel), s.trunk_before, since(s.home_tick)))
end

-- 7) Handbetrieb: Ein fremdes Ziel (wie die Fernbedienung) schaltet auf Hand, ein Tankauftrag bleibt liegen; zurück an
-- der Leitstelle wieder Automatik, dann übernimmt er den Auftrag.
function t23.s7_go(run, tb, d)
  local s = d.s7
  s.carryall.autopilot_destination = d.pos.manual
  s.deadline = game.tick + 3 * 60
  return 1
end

function t23.s7_manual(run, tb, d)
  local s = d.s7
  return wait_for(s, function()
    local record = record_of(s.carryall)
    return record and record.fleet_mode == "manual"
  end, function()
    return fail(run, tb, 7, "fremdes Ziel schaltet nicht auf Handbetrieb")
  end)
end

function t23.s7_harvester(run, tb, d)
  local s = d.s7
  s.manual_ok = true
  s.car = new_harvester(run, tb, d, d.pos.refuel, {coal = 2})
  if not s.car then return fail(run, tb, 7, "Ernter ließ sich nicht bauen") end
  return 4 * 60
end

function t23.s7_still(run, tb, d)
  local s = d.s7
  local record = record_of(s.carryall)
  s.job_while_manual = record and record.job ~= nil
  local job = job_of(s.car)
  s.open_job = job ~= nil and job.state == "open"
  s.carryall.autopilot_destination = s.depot.position
  s.deadline = game.tick + 60 * 60
  return 1
end

function t23.s7_back(run, tb, d)
  local s = d.s7
  local record = record_of(s.carryall)
  if record and record.fleet_mode == "auto" and not s.auto_tick then s.auto_tick = game.tick end
  if fuel_items(s.car) > 10 and not s.fuel_tick then s.fuel_tick = game.tick end
  if s.fuel_tick then return 1 end
  if game.tick >= s.deadline then return 1 end
  return "poll"
end

function t23.s7_check(run, tb, d)
  local s = d.s7
  local failed = {}
  check(failed, s.manual_ok == true, "kein Handbetrieb")
  check(failed, not s.job_while_manual, "Auftrag trotz Handbetrieb")
  check(failed, s.open_job == true, "Tankauftrag wartet nicht offen")
  check(failed, s.auto_tick ~= nil, "zurück an der Leitstelle nicht wieder Automatik")
  check(failed, s.fuel_tick ~= nil, "Tankauftrag danach nicht erledigt")
  return verdict(run, tb, 7, "Handbetrieb", failed, string.format("Auftrag offen %s, Automatik wieder %s, betankt %s",
    tostring(s.open_job), tostring(s.auto_tick ~= nil), tostring(s.fuel_tick ~= nil)))
end

-- 8) Pause nach /arrakis-uninstall: fleet.uninstall hält die Automatik an; ohne Pause übernimmt sie wieder.
function t23.s8_pause(run, tb, d)
  local s = d.s8
  fleet.uninstall()
  s.paused = storage.fleet_pause_until ~= nil
  s.car = new_harvester(run, tb, d, d.pos.refuel, {coal = 2})
  if not s.car then return fail(run, tb, 8, "Ernter ließ sich nicht bauen") end
  return 4 * 60
end

function t23.s8_resume(run, tb, d)
  local s = d.s8
  s.job_paused = job_of(s.car) ~= nil
  storage.fleet_pause_until = nil
  s.deadline = game.tick + 4 * 60
  return 1
end

function t23.s8_job(run, tb, d)
  local s = d.s8
  return wait_for(s, function()
    s.job_after = job_of(s.car) ~= nil
    return s.job_after
  end, function() return 1 end)
end

function t23.s8_check(run, tb, d)
  local s = d.s8
  local failed = {}
  check(failed, s.paused, "storage.fleet_pause_until nicht gesetzt")
  check(failed, not s.job_paused, "Auftrag trotz Pause")
  check(failed, s.job_after == true, "nach der Pause kein Auftrag")
  return verdict(run, tb, 8, "Pause nach /arrakis-uninstall", failed, string.format("Pause %s, Auftrag in der Pause %s, danach %s",
    tostring(s.paused), tostring(s.job_paused), tostring(s.job_after)))
end

-- 9) Leitstelle abgerissen: Datensatz weg, Carryall ohne Leitstelle und ohne Ziel.
function t23.s9_remove(run, tb, d)
  local s = d.s9
  s.un = s.depot.unit_number
  s.depot.destroy{raise_destroy = true}
  return 60
end

function t23.s9_check(run, tb, d)
  local s = d.s9
  local record = record_of(s.carryall)
  local failed = {}
  check(failed, storage.depots[s.un] == nil, "Leitstelle noch in storage.depots")
  check(failed, record and record.depot == nil, "Carryall hält die Leitstelle noch")
  check(failed, valid(s.carryall) and s.carryall.autopilot_destination == nil, "Carryall fliegt los")
  return verdict(run, tb, 9, "Leitstelle abgerissen", failed, string.format("Datensatz %s, Carryall Leitstelle %s",
    tostring(storage.depots[s.un] ~= nil), tostring(record and record.depot)))
end

-- 10) Der Wurm lauert (0.11.0, Max 29.10.2026): reguläre Jagd 30 s auf einen Ernter. Der Carryall bringt ihn zur
-- Leitstelle; nach der Jagd lauert der Wurm im Sektor (2 bis 4 min), der Ernter wartet. Ein zweiter Ernter, der dort
-- aufbaut, bekommt nach fünf Sekunden ein Wurmzeichen (Jagd abgebrochen, Ernter weg). Dann endet das Lauern (vom
-- Test verkürzt), der Carryall bringt den ersten zurück. Zuletzt: Eine Jagd, die mit „Wurm getötet“ endet, hinterlässt
-- keinen lauernden Wurm. Die Force ist dafür wach und ihre Vibration zählt; danach wie vorher.
local function t23_s10_restore(d)
  local s = d.s10
  if not (s and s.force and s.force.valid) then return end
  if s.grace_saved then worms_lib.grace_restore(s.force, s.grace) end
  s.grace_saved = nil
  vibration_lib.testbench_disable(s.force)
  local own = {}
  for _, hunt in pairs(storage.hunts.list) do
    if hunt.force_index == s.force.index then table.insert(own, hunt) end
  end
  for _, hunt in ipairs(own) do pcall(worms_lib.end_hunt, hunt, nil, "abort") end
  if s.surface_index and s.sector then
    vibration_lib.rest(s.surface_index, s.sector, 0)
    worms_lib.clear_lurk(s.surface_index)
  end
end

function t23.s10_build(run, tb, d)
  local s = d.s10
  local force = t23_force()
  s.force = force
  s.grace = worms_lib.grace_snapshot(force)
  s.grace_saved = true
  worms_lib.set_grace(force, {awake = true, first_hunt_done = true}, {"first_hunt"})
  vibration_lib.testbench_enable(force)
  s.car = new_harvester(run, tb, d, d.pos.rescue)
  if not s.car then return fail(run, tb, 10, "Ernter ließ sich nicht bauen") end
  s.origin = {x = s.car.position.x, y = s.car.position.y}
  s.surface_index = s.car.surface.index
  return harvester.DEPLOY_TICKS + 10
end

function t23.s10_hunt(run, tb, d)
  local s = d.s10
  if state_of(s.car) ~= "deployed" then return fail(run, tb, 10, "Ernter baut nicht auf (" .. state_of(s.car) .. ")") end
  local hunt, reason = worms_lib.start_hunt(s.car, {seconds = 30})
  if not hunt then return fail(run, tb, 10, "start_hunt: " .. tostring(reason)) end
  s.hunt = hunt
  s.sector = hunt.sector_key
  s.start = game.tick
  s.deadline = hunt.eta_tick + 30 * 60
  return 1
end

function t23.s10_evac(run, tb, d)
  local s = d.s10
  return wait_for(s, function()
    local h = h_of(s.car)
    if not (h and h.fleet_wait and not hunt_alive(s.hunt)) then return false end
    s.outcome = s.hunt.outcome
    s.safe_tick = game.tick
    local until_tick = worms_lib.lurking(s.surface_index, s.sector)
    s.lurk_left = until_tick and (until_tick - game.tick)
    return true
  end, function()
    return fail(run, tb, 10, string.format("Ernter nach der Jagd nicht an der Leitstelle (Zustand %s, Jagd %s)",
      state_of(s.car), tostring(s.hunt.outcome)))
  end)
end

-- Sechs Sekunden: länger als LURK_DELAY und als ein Takt von scan_harvesters.
function t23.s10_second(run, tb, d)
  return 6 * 60
end

function t23.s10_lurking(run, tb, d)
  local s = d.s10
  local h = h_of(s.car)
  s.waits = h ~= nil and h.fleet_wait ~= nil
  s.job_while_lurking = job_of(s.car) ~= nil
  s.car2 = new_harvester(run, tb, d, s.origin)
  if not s.car2 then return fail(run, tb, 10, "zweiter Ernter ließ sich nicht bauen") end
  s.deadline = game.tick + 30 * 60
  return 1
end

function t23.s10_sign(run, tb, d)
  local s = d.s10
  if state_of(s.car2) == "deployed" and not s.deployed2 then s.deployed2 = game.tick end
  local hunt = worms_lib.hunt_of(s.car2)
  if hunt then
    s.sign_lurk = hunt.lurk == true
    s.sign_delay = s.deployed2 and (hunt.warn_tick - s.deployed2)
    worms_lib.end_hunt(hunt, nil, "abort")
    s.car2.destroy{raise_destroy = true}
    -- Lauern vom Test verkürzt: in einer Sekunde ist es am Feld ruhig.
    worms_lib.lurk(s.surface_index, s.sector, game.tick + 60)
    s.calm_tick = game.tick + 60
    s.deadline = game.tick + 90 * 60
    return 1
  end
  if game.tick >= s.deadline then
    s.deadline = game.tick + 90 * 60
    worms_lib.lurk(s.surface_index, s.sector, game.tick + 60)
    s.calm_tick = game.tick + 60
    return 1
  end
  return "poll"
end

function t23.s10_return(run, tb, d)
  local s = d.s10
  local h = h_of(s.car)
  if not s.back_tick and h and (h.state == "deploying" or h.state == "deployed") and fleet_distance(s.car.position, s.origin) <= 6 then
    s.back_tick = game.tick
  end
  if s.back_tick and parked(s) then return 1 end
  if game.tick >= s.deadline or not valid(s.car) then return 1 end
  return "poll"
end

function t23.s10_killed(run, tb, d)
  local s = d.s10
  vibration_lib.rest(s.surface_index, s.sector, 0)
  worms_lib.clear_lurk(s.surface_index)
  local target = valid(s.car) and s.car or nil
  local hunt = target and worms_lib.start_hunt(target, {seconds = 30})
  if hunt then
    worms_lib.end_hunt(hunt, "killed", "quiet")
    s.killed_rest = vibration_lib.resting(s.surface_index, hunt.sector_key) ~= nil
    s.killed_lurk = worms_lib.lurking(s.surface_index, hunt.sector_key)
    s.killed_done = true
  end
  return 1
end

function t23.s10_check(run, tb, d)
  local s = d.s10
  local failed = {}
  local min, max = worms_lib.REST_MIN, worms_lib.REST_MAX
  check(failed, s.outcome == "escaped", "Jagd endet " .. tostring(s.outcome) .. " statt escaped")
  check(failed, s.lurk_left ~= nil and s.lurk_left > min - 120 and s.lurk_left <= max,
    "Wurm lauert " .. tostring(s.lurk_left) .. " Ticks statt 7200 bis 14400")
  check(failed, s.waits == true, "Ernter wartet nicht an der Leitstelle")
  check(failed, not s.job_while_lurking, "Rückflug, obwohl der Wurm lauert")
  check(failed, s.sign_delay ~= nil and s.sign_delay >= worms_lib.LURK_DELAY and s.sign_delay <= worms_lib.LURK_DELAY + 120,
    "Wurmzeichen auf den zweiten Ernter nach " .. tostring(s.sign_delay) .. " Ticks statt 300 bis 420")
  check(failed, s.sign_lurk == true, "Wurmzeichen nicht als „Wurm lauert“ markiert")
  check(failed, s.back_tick ~= nil and s.back_tick > s.calm_tick, "nach dem Lauern nicht zurück am Feld aufgebaut ("
    .. state_of(s.car) .. ")")
  check(failed, s.killed_done == true and s.killed_rest == true and s.killed_lurk == nil,
    "getöteter Wurm: Ruhe " .. tostring(s.killed_rest) .. ", Lauern " .. tostring(s.killed_lurk))
  t23_s10_restore(d)
  local function since(t) return t and tb.num((t - s.start) / 60) or "–" end
  return verdict(run, tb, 10, "Wurm lauert", failed, string.format(
    "Jagd %s, an der Leitstelle nach %s s, Wurm lauert %s s, Rückflug während des Lauerns %s, Wurmzeichen auf Ernter 2"
    .. " %s s nach dem Aufbau (lauert %s), zurück aufgebaut %s s nach dem Ende des Lauerns, getötet: Ruhe %s, Lauern %s",
    tostring(s.outcome), since(s.safe_tick), s.lurk_left and tb.num(s.lurk_left / 60) or "–", tostring(s.job_while_lurking),
    s.sign_delay and tb.num(s.sign_delay / 60) or "–", tostring(s.sign_lurk), s.back_tick and tb.num((s.back_tick - s.calm_tick) / 60) or "–",
    tostring(s.killed_rest), tostring(s.killed_lurk ~= nil)))
end

local T23_STEPS =
{
  {t23.s1},
  {base_phase(2), parked_phase(2), t23.s2_check},
  {base_phase(3), parked_phase(3), t23.s3_build, t23.s3_hunt, t23.s3_watch, t23.s3_check},
  {base_phase(4), parked_phase(4), t23.s4_build, t23.s4_hunt, t23.s4_watch, t23.s4_check},
  {base_phase(5), parked_phase(5), t23.s5_build, t23.s5_watch, t23.s5_check},
  {base_phase(6), parked_phase(6), t23.s6_build, t23.s6_watch, t23.s6_check},
  {base_phase(7), parked_phase(7), t23.s7_go, t23.s7_manual, t23.s7_harvester, t23.s7_still, t23.s7_back, t23.s7_check},
  {base_phase(8), parked_phase(8), t23.s8_pause, t23.s8_resume, t23.s8_job, t23.s8_check},
  {base_phase(9), parked_phase(9), t23.s9_remove, t23.s9_check},
  {base_phase(10), parked_phase(10), t23.s10_build, t23.s10_hunt, t23.s10_evac, t23.s10_second, t23.s10_lurking,
    t23.s10_sign, t23.s10_return, t23.s10_killed, t23.s10_check}
}

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

local function t23_start(run, tb)
  prepare(run, tb)
  local d = run.data
  for number = 1, #T23_STEPS do d["s" .. number] = {} end
  tb.watch(run, nil, d.pos.watch)
  tb.log(run, "INFO", "Zehn Schritte mit der echten Carryall-Automatik (Übernahme, Rettung zur Leitstelle, Absage, Entladen,"
    .. " Tanken, Handbetrieb, Pause, Abriss, Wurm lauert), Force " .. T23_FORCE .. " ohne Wurm. Dauer etwa 6 min Spielzeit.")
  d.step, d.phase, d.wait_until = 1, 1, game.tick + 30
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

local function t23_tick(run, tb)
  run_steps(run, tb, T23_STEPS)
end

local function t23_cleanup(run, tb)
  pcall(t23_s10_restore, run.data)
  pcall(tidy, run)
  storage.fleet_pause_until = nil
end

-- T24 Dauerlauf --------------------------------------------------------------------------------------

local T24_TICKS = 60 * 60 * 60
-- Längste erlaubte Zeit eines aufgebauten Ernters ohne Brennstoff (Ticks): Tankflug plus Reserve.
local T24_NO_FUEL_LIMIT = 120 * 60
local T24_HUNT_EVERY = 75 * 60
local T24_SETTLE = 240 * 60
local T24_JOB_LIMIT = 240 * 60

local function t24_start(run, tb)
  prepare(run, tb)
  local d = run.data
  d.s = {}
  local s = d.s
  if not build_base(run, tb, d, s, {carryalls = 2, rocket = 60, coal = 2000}) then
    tb.log(run, "FEHLER", "Leitstelle oder Carryalls ließen sich nicht bauen")
    tb.finish(run, "abgebrochen (Aufbau)")
    return
  end
  s.intake = create(run, tb, {name = INTAKE, position = d.pos.intake, force = t23_force(), raise_built = true}, "others")
  s.cars = {
    new_harvester(run, tb, d, d.pos.rescue),
    new_harvester(run, tb, d, d.pos.refuel, {coal = 3}),
    new_harvester(run, tb, d, d.pos.unload, {fill = 37}),
    new_harvester(run, tb, d, d.pos.soak_d)
  }
  for i, car in ipairs(s.cars) do
    if not car then
      tb.log(run, "FEHLER", "Ernter " .. i .. " ließ sich nicht bauen")
      tb.finish(run, "abgebrochen (Aufbau)")
      return
    end
  end
  s.start = game.tick
  s.next_hunt = game.tick + 30 * 60
  s.target = 0
  s.hunts = {}
  s.jobs = {}
  s.kinds = {}
  s.docked = 0
  s.fuel_before = fuel_items(s.cars[2])
  s.max_job = 0
  s.no_fuel_since = {}
  s.max_no_fuel = 0
  tb.watch(run, nil, d.pos.watch)
  tb.log(run, "INFO", "Dauerlauf 60 min Spielzeit: 2 Carryalls, 4 Ernter, alle 75 s ein Wurmzeichen (60 s). Erwartet: kein Biss,"
    .. " mindestens ein Entladen und ein Tanken, kein Auftrag hängt länger als 4 min, kein Ernter länger als 2 min ohne Brennstoff.")
end

local function t24_tick(run, tb)
  local d = run.data
  local s = d.s
  if not (s and s.start) then return end
  local tick = game.tick
  -- Aufträge beobachten.
  for id, job in pairs(storage.jobs.list) do
    if not s.jobs[id] then
      s.jobs[id] = {kind = job.kind, created = job.created}
      s.kinds[job.kind] = (s.kinds[job.kind] or 0) + 1
    end
    local age = tick - job.created
    if age > s.max_job then s.max_job = age end
  end
  -- Alle 30 s ein Stand in die Datei: Carryalls (Auftrag, Zustand, Last, Ort) und Ernter (Zustand, Füllstand, Brennstoff).
  if (tick - s.start) % 1800 == 0 then
    local parts = {}
    for i, carryall in ipairs(s.carryalls) do
      local record = record_of(carryall)
      local job = record and record.job and storage.jobs.list[record.job]
      table.insert(parts, string.format("C%d %s/%s Last %s bei %s", i, job and job.kind or "-", job and job.state or "-",
        tostring(record and record.cargo), valid(carryall) and pos_text(tb, carryall.position) or "weg"))
    end
    for i, car in ipairs(s.cars) do
      table.insert(parts, string.format("E%d %s %.2f %d", i, state_of(car), valid(car) and fleet.fill_of(car) or 0, fuel_items(car)))
    end
    tb.trace(run, "Stand: " .. table.concat(parts, "; "))
  end
  -- Ohne Brennstoff: längste Strecke je Ernter (Status no_fuel, scripts/harvester.lua).
  for i, car in ipairs(s.cars) do
    local h = h_of(car)
    if h and h.state == "deployed" and h.status == "no_fuel" then
      s.no_fuel_since[i] = s.no_fuel_since[i] or tick
      s.max_no_fuel = math.max(s.max_no_fuel, tick - s.no_fuel_since[i])
    else
      s.no_fuel_since[i] = nil
    end
  end
  -- Annahme: Greifarme simuliert, angedockte Ernter werden geleert.
  if tick % 60 == 0 then
    for _, car in ipairs(s.cars) do
      if state_of(car) == "docked" then
        local trunk = car.get_inventory(defines.inventory.car_trunk)
        if not trunk.is_empty() then
          trunk.clear()
          s.docked = s.docked + 1
        end
      end
    end
  end
  -- Wurmzeichen.
  if tick >= s.next_hunt and tick < s.start + T24_TICKS then
    s.next_hunt = tick + T24_HUNT_EVERY
    local started = false
    for _ = 1, #s.cars do
      s.target = s.target % #s.cars + 1
      local car = s.cars[s.target]
      if state_of(car) == "deployed" then
        local hunt = worms_lib.start_hunt(car, {seconds = 60, debug = true})
        if hunt then
          table.insert(s.hunts, hunt)
          tb.trace(run, "Wurmzeichen auf Ernter " .. s.target .. ", Jagd " .. hunt.id)
          started = true
        end
        break
      end
    end
    -- Seit 0.11.0 stehen gerettete Ernter länger an der Leitstelle; ist keiner aufgebaut, fällt das Wurmzeichen aus.
    if not started then s.skipped = (s.skipped or 0) + 1 end
  end
  if tick < s.start + T24_TICKS + T24_SETTLE then return end
  -- Auswertung.
  local failed = {}
  local escaped, bitten, open = 0, 0, 0
  for _, hunt in ipairs(s.hunts) do
    if hunt.outcome == "escaped" then escaped = escaped + 1
    elseif hunt.outcome == "bitten" then bitten = bitten + 1
    else open = open + 1 end
  end
  -- 48 Termine; bis 0.10.x gut 40 Wurmzeichen, seit 0.11.0 (Ernter warten an der Leitstelle) am 29.10.2026 36.
  check(failed, #s.hunts >= 30, #s.hunts .. " Wurmzeichen statt mindestens 30")
  check(failed, bitten == 0 and open == 0, bitten .. " gebissen, " .. open .. " ohne Ende")
  local lost, waiting, stuck = 0, 0, 0
  for _, car in ipairs(s.cars) do
    local state = state_of(car)
    if not valid(car) or state == "carried" then lost = lost + 1 end
    local h = h_of(car)
    if h and h.fleet_wait then waiting = waiting + 1 end
    if state == "docked" then stuck = stuck + 1 end
  end
  check(failed, stuck == 0, stuck .. " Ernter hängen noch an der Annahme")
  check(failed, lost == 0, lost .. " Ernter weg oder noch in der Luft")
  check(failed, waiting == 0, waiting .. " Ernter warten noch an der Leitstelle")
  check(failed, s.docked >= 1, "kein Entladen an der Annahme")
  check(failed, fuel_items(s.cars[2]) > s.fuel_before, "Ernter 2 nicht betankt")
  check(failed, s.max_job <= T24_JOB_LIMIT, "Auftrag " .. tb.num(s.max_job / 60) .. " s alt")
  check(failed, s.max_no_fuel <= T24_NO_FUEL_LIMIT, "Ernter " .. tb.num(s.max_no_fuel / 60) .. " s ohne Brennstoff")
  local home = 0
  for _, carryall in ipairs(s.carryalls) do
    if valid(carryall) and fleet_distance(carryall.position, s.depot.position) <= 3 then home = home + 1 end
  end
  check(failed, home == #s.carryalls, home .. " von " .. #s.carryalls .. " Carryalls an der Leitstelle")
  local kinds = {}
  for _, kind in ipairs({"rescue", "unload", "refuel", "return"}) do table.insert(kinds, kind .. " " .. (s.kinds[kind] or 0)) end
  local values = string.format("Wurmzeichen %d (entkommen %d), Aufträge %s, entladen %d, längster Auftrag %s s, längste Zeit ohne Brennstoff %s s, Carryalls daheim %d, Ernter an der Leitstelle %d, Wurmzeichen ausgefallen (kein Ernter aufgebaut) %d",
    #s.hunts, escaped, table.concat(kinds, ", "), s.docked, tb.num(s.max_job / 60), tb.num(s.max_no_fuel / 60), home, waiting, s.skipped or 0)
  tb.log(run, #failed == 0 and "OK" or "FEHLER", "Dauerlauf: " .. values
    .. (#failed > 0 and (" | nicht erfüllt: " .. table.concat(failed, "; ")) or ""))
  s.start = nil
  tb.finish(run, #failed == 0 and "Dauerlauf OK" or "Dauerlauf FEHLER")
end

local function t24_cleanup(run, tb)
  pcall(tidy, run)
end

-- T25 Ansicht (interaktiv) ---------------------------------------------------------------------------
-- Anders als T23 und T24 mit sichtbarem Wurm (Max 29.10.2026: „es war kein Wurm zu sehen“): set_worm_off aus,
-- Startrichtung Ost (k0 = 4, weg von der Felsinsel). Dazu bekommt der Spieler eine Leitstelle ins Inventar, damit er die
-- Frage nach dem Reichweitenkreis beim Bauen beantworten kann; Aufräumen nimmt sie wieder weg.

local T25_HUNT_AFTER = 15 * 60
local T25_HUNT_SECONDS = 60
local T25_END = 150 * 60
local T25_SPAWN_DIR = 4

local function t25_start(run, tb)
  local player = tb.player(run)
  if not player then
    tb.log(run, "FEHLER", "T25 braucht einen Spieler")
    tb.finish(run, "abgebrochen (ohne Spieler)")
    return
  end
  prepare(run, tb)
  local d = run.data
  d.s = {}
  local s = d.s
  if not build_base(run, tb, d, s) then
    tb.finish(run, "abgebrochen (Aufbau)")
    return
  end
  s.car = new_harvester(run, tb, d, at(d.pos.depot, 45, 0))
  -- Erst nach new_harvester: t23_force() schaltet den Wurm bei jedem Aufruf wieder aus.
  local force = t23_force()
  worms_lib.ensure_force()
  worms_lib.set_worm_off(force, false)
  worms_lib.set_spawn_dir(force, T25_SPAWN_DIR)
  s.force = force
  s.viewer = player.index
  s.given = player.insert{name = DEPOT, count = 1}
  tb.watch(run, player, at(d.pos.depot, 22, 6))
  tb.protect(run, player)
  s.start = game.tick
  tb.log(run, "INFO", "Leitstelle links auf Fels, Carryall parkt dort, Ernter 45 Kacheln rechts. In 15 s kommt ein Wurmzeichen,"
    .. " der Wurm taucht von Osten auf: Der Carryall holt den Ernter, bringt ihn zur Leitstelle und nach der Jagd zurück aufs Feld."
    .. (s.given > 0 and " Eine Leitstelle liegt in deinem Inventar: Nimm sie in die Hand und zeig auf die Felsinsel, dann siehst du"
      .. " den Reichweitenkreis (setzen darfst du sie auch)." or " Eine Leitstelle ließ sich nicht ins Inventar legen."))
end

local function t25_tick(run, tb)
  local s = run.data.s
  if not (s and s.start) then return end
  local tick = game.tick
  if not s.hunt and tick >= s.start + T25_HUNT_AFTER and state_of(s.car) == "deployed" then
    s.hunt = worms_lib.start_hunt(s.car, {seconds = T25_HUNT_SECONDS, debug = true})
    if not s.hunt then tb.log(run, "FEHLER", "Wurmzeichen ließ sich nicht starten") end
  end
  if tick >= s.start + T25_END then
    s.start = nil
    tb.log(run, "FRAGE", "Passt der Ablauf wie im Film (Ernter zur Leitstelle, nach der Jagd zurück aufs Feld)? Antwort bitte im"
      .. " Thread.")
    tb.finish(run, "Ansicht gezeigt")
  end
end

local function t25_cleanup(run, tb)
  local s = run.data.s
  local record = s and record_of(s.carryall)
  if record and record.cargo then pcall(flyer_lib.drop, record, nil, true) end
  if s and s.force and s.force.valid then
    local own = {}
    for _, hunt in pairs(storage.hunts.list) do
      if hunt.force_index == s.force.index then table.insert(own, hunt) end
    end
    for _, hunt in ipairs(own) do pcall(worms_lib.end_hunt, hunt, nil, "abort") end
    worms_lib.set_spawn_dir(s.force, nil)
    worms_lib.set_worm_off(s.force, true)
  end
  pcall(tidy, run)
  -- Vom Spieler gesetzte Leitstellen im Testbereich und die geschenkte im Inventar wieder weg.
  local origin = tb.area(run.id)
  local surface = tb.surface()
  pcall(function()
    for _, entity in pairs(surface.find_entities_filtered{name = DEPOT, area = {{origin.x - T23_HALF.x, origin.y - T23_HALF.y},
        {origin.x + T23_HALF.x, origin.y + T23_HALF.y}}}) do
      entity.destroy{raise_destroy = true}
    end
  end)
  local player = s and s.viewer and game.get_player(s.viewer)
  if player and s.given and s.given > 0 then pcall(function() player.remove_item{name = DEPOT, count = s.given} end) end
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
local T26_SETTLE = 130

local function fleet_force(on)
  local force = t23_force()
  local tech = force.technologies[FLEET_TECH]
  if tech then tech.researched = on end
  return force
end

local function red_signal(entity, name)
  if not valid(entity) then return 0 end
  return entity.get_signal({type = "virtual", name = name}, defines.wire_connector_id.circuit_red)
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
  for _, name in ipairs({NAME, SPICE, "constant-combinator"}) do
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

local t26 = {}

-- 1) Prototypen, storage (Schema 6) und das versteckte Schaltungsgebäude an einer neuen Leitstelle.
function t26.s1(run, tb, d)
  local s = d.s1
  local failed = {}
  fleet_force(true)
  check(failed, prototypes.technology[FLEET_TECH] ~= nil, "Forschung " .. FLEET_TECH .. " fehlt")
  for _, name in ipairs(fleet.STATUS_SIGNALS) do
    check(failed, prototypes.virtual_signal[name] ~= nil, "Signal " .. name .. " fehlt")
  end
  check(failed, prototypes.entity["arrakis-depot-signals"] ~= nil, "arrakis-depot-signals fehlt")
  check(failed, storage.schema >= 6 and storage.fields ~= nil and storage.fields.chunks ~= nil, "storage Schema 6 fehlt")
  s.depot = create(run, tb, {name = DEPOT, position = d.pos.depot, force = t23_force(), raise_built = true}, "others")
  local dr = s.depot and fleet.depot_of(s.depot.unit_number)
  local cc = dr and dr.signal_entity
  check(failed, valid(cc) and cc.name == "arrakis-depot-signals", "kein Schaltungsgebäude an der Leitstelle")
  local wired = 0
  if valid(cc) then
    for _, id in ipairs({defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green}) do
      local connector = cc.get_wire_connector(id, false)
      if connector and connector.connection_count >= 1 then wired = wired + 1 end
    end
  end
  check(failed, wired == 2, wired .. " von 2 Drähten am Schaltungsgebäude")
  check(failed, dr and dr.target == 0 and dr.recall_button == false, "Soll nicht aus oder Rückruf an")
  return verdict(run, tb, 1, "Prototypen, Schema 6, Schaltungsgebäude", failed, string.format(
    "Schema %s, Schaltungsgebäude %s, Drähte %d", tostring(storage.schema), valid(cc) and "da" or "fehlt", wired))
end

-- 2) Soll 2 aus dem Fenster: zwei Ernter aus dem Lager (3 Items) auf zwei Felder, Reserve 1.
function t26.s2_build(run, tb, d)
  local s = d.s2
  fleet_force(true)
  if not build_base(run, tb, d, s, {carryalls = 3, rocket = 60, coal = 300}) then return fail(run, tb, 2, "Leitstelle oder Carryalls ließen sich nicht bauen") end
  s.depot.get_inventory(defines.inventory.chest).insert{name = NAME, count = 3}
  s.fields = place_fields(tb, d, T26_FIELDS)
  chart_area(tb, d)
  s.deadline = game.tick + 10 * 60
  return 1
end

function t26.s2_chart(run, tb, d)
  local s = d.s2
  local r = wait_for(s, function() return charted(tb, s.fields) end,
    function() skip_chart(run, tb, "2) ") return 1 end)
  if r == 1 then
    fleet.set_target(depot_record(s), 2)
    s.start = game.tick
    s.deadline = game.tick + 240 * 60
  end
  return r
end

function t26.s2_wait(run, tb, d)
  local s = d.s2
  local r = wait_for(s, function()
    return #owned(s, "deployed") == 2 and depot_jobs(s) == 0
  end, function()
    return fail(run, tb, 2, string.format("nach 240 s %d eigene Ernter aufgebaut, %d im Lager, Aufträge %d, Feldsuche offen %d",
      #owned(s, "deployed"), depot_items(s, NAME), depot_jobs(s), fields.queue_length()))
  end)
  if r == 1 then return T26_SETTLE end
  return r
end

-- Feld leeren: Spice-Sand bis 10 Kacheln um die Stelle (mehr als der Erntekreis, damit kein Rest daneben bleibt).
local function empty_field(tb, position)
  local area = {{position.x - 10, position.y - 10}, {position.x + 10, position.y + 10}}
  for _, e in pairs(tb.surface().find_entities_filtered{name = SPICE, area = area}) do e.destroy() end
end

local function on_field(h)
  return h.entity.valid and fields.amount_at(h.entity.surface, h.entity.position) >= fields.MIN_AMOUNT
end

function t26.s2_check(run, tb, d)
  local s = d.s2
  local failed = {}
  local list = owned(s, "deployed")
  check(failed, depot_items(s, NAME) == 1, depot_items(s, NAME) .. " Ernter im Lager statt 1")
  local gap = #list == 2 and fleet_distance(list[1].entity.position, list[2].entity.position) or 0
  check(failed, gap >= fields.SPACING, "Abstand der beiden " .. tb.num(gap))
  for i, h in ipairs(list) do check(failed, on_field(h), "Ernter " .. i .. " nicht auf Spice") end
  local active, reserve = red_signal(s.depot, "arrakis-signal-harvesters"), red_signal(s.depot, "arrakis-signal-reserve")
  check(failed, active == 2 and reserve == 1, "Statussignale aktiv " .. active .. ", Reserve " .. reserve)
  s.ok = #failed == 0
  local result = verdict(run, tb, 2, "Soll 2 aus dem Fenster", failed, string.format(
    "zwei eingesetzt nach %s s, Abstand %s, Signale aktiv %d / Reserve %d / freie Carryalls %d",
    tb.num((game.tick - s.start) / 60), tb.num(gap), active, reserve, red_signal(s.depot, "arrakis-signal-carryalls")))
  d.s3, d.s4, d.s5 = s, s, s
  return s.ok and "keep" or result
end

-- 3) Signal H = 3 (Vorrang vor dem Fenster): der dritte Ernter aus dem Lager.
function t26.s3_set(run, tb, d)
  local s = d.s3
  if not (s and s.ok) then return fail(run, tb, 3, "folgt aus Schritt 2 (nicht erfüllt)") end
  if not set_wire_signal(run, tb, s, "H", 3) then return fail(run, tb, 3, "Konstant-Schaltungsgebäude ließ sich nicht bauen") end
  s.start = game.tick
  s.deadline = game.tick + 240 * 60
  return 1
end

function t26.s3_wait(run, tb, d)
  local s = d.s3
  local r = wait_for(s, function()
    return #owned(s, "deployed") == 3 and depot_jobs(s) == 0
  end, function()
    local dr = depot_record(s)
    return fail(run, tb, 3, string.format("nach 240 s %d eigene Ernter aufgebaut, Soll %s, gelesenes H %s",
      #owned(s, "deployed"), tostring(dr and dr.soll), tostring(dr and dr.last_h)))
  end)
  if r == 1 then return T26_SETTLE end
  return r
end

function t26.s3_check(run, tb, d)
  local s = d.s3
  local failed = {}
  local dr = depot_record(s)
  check(failed, dr and dr.soll == 3 and dr.last_h == 3, "Soll " .. tostring(dr and dr.soll) .. " statt 3")
  check(failed, depot_items(s, NAME) == 0, depot_items(s, NAME) .. " Ernter im Lager statt 0")
  local active, reserve = red_signal(s.depot, "arrakis-signal-harvesters"), red_signal(s.depot, "arrakis-signal-reserve")
  check(failed, active == 3 and reserve == 0, "Statussignale aktiv " .. active .. ", Reserve " .. reserve)
  s.ok = #failed == 0
  local result = verdict(run, tb, 3, "Signal H = 3", failed, string.format("dritter nach %s s, Signale aktiv %d / Reserve %d",
    tb.num((game.tick - s.start) / 60), active, reserve))
  return s.ok and "keep" or result
end

-- 4) H = 1: die zwei zuletzt eingesetzten zurück ins Lager (Ladung im Lager, kein Umweg ohne Annahme).
function t26.s4_set(run, tb, d)
  local s = d.s4
  if not (s and s.ok) then return fail(run, tb, 4, "folgt aus Schritt 3 (nicht erfüllt)") end
  set_wire_signal(run, tb, s, "H", 1)
  s.start = game.tick
  s.deadline = game.tick + 400 * 60
  return 1
end

function t26.s4_wait(run, tb, d)
  local s = d.s4
  local r = wait_for(s, function()
    return #owned(s) == 1 and depot_items(s, NAME) == 2 and depot_jobs(s) == 0
  end, function()
    return fail(run, tb, 4, string.format("nach 400 s %d eigene Ernter draußen, %d im Lager, Aufträge %d",
      #owned(s), depot_items(s, NAME), depot_jobs(s)))
  end)
  if r == 1 then return T26_SETTLE end
  return r
end

function t26.s4_check(run, tb, d)
  local s = d.s4
  local failed = {}
  local list = owned(s, "deployed")
  check(failed, #list == 1, #list .. " aufgebaut statt 1")
  local active, reserve = red_signal(s.depot, "arrakis-signal-harvesters"), red_signal(s.depot, "arrakis-signal-reserve")
  check(failed, active == 1 and reserve == 2, "Statussignale aktiv " .. active .. ", Reserve " .. reserve)
  s.ok = #failed == 0
  local result = verdict(run, tb, 4, "Signal H = 1 holt zwei ins Lager", failed, string.format(
    "nach %s s, im Lager %d Ernter und %d Spice-Sand, Signale aktiv %d / Reserve %d", tb.num((game.tick - s.start) / 60),
    depot_items(s, NAME), depot_items(s, SPICE), active, reserve))
  return s.ok and "keep" or result
end

-- 5) Umsetzen: Das Feld des letzten wird leer (Spice-Sand entfernt), die Leitstelle setzt ihn auf ein freies Feld.
function t26.s5_empty(run, tb, d)
  local s = d.s5
  if not (s and s.ok) then return fail(run, tb, 5, "folgt aus Schritt 4 (nicht erfüllt)") end
  local h = owned(s, "deployed")[1]
  if not h then return fail(run, tb, 5, "kein aufgebauter Ernter") end
  s.mover = h.entity
  s.from = {x = h.entity.position.x, y = h.entity.position.y}
  empty_field(tb, s.from)
  s.start = game.tick
  s.deadline = game.tick + 240 * 60
  return 1
end

function t26.s5_wait(run, tb, d)
  local s = d.s5
  local r = wait_for(s, function()
    local h = h_of(s.mover)
    if h and h.status == "field_empty" then s.seen_empty = true end
    return h and h.state == "deployed" and h.status ~= "field_empty" and fleet_distance(s.mover.position, s.from) >= fields.SPACING
      and depot_jobs(s) == 0
  end, function()
    return fail(run, tb, 5, string.format("nach 240 s Ernter %s bei %s (vorher %s), Status %s", state_of(s.mover),
      valid(s.mover) and pos_text(tb, s.mover.position) or "–", pos_text(tb, s.from), tostring((h_of(s.mover) or {}).status)))
  end)
  if r == 1 then return T26_SETTLE end
  return r
end

function t26.s5_check(run, tb, d)
  local s = d.s5
  local failed = {}
  local h = h_of(s.mover)
  check(failed, s.seen_empty, "Status „Feld leer“ nie gesehen")
  check(failed, h and on_field(h), "nicht auf Spice")
  check(failed, red_signal(s.depot, "arrakis-signal-harvesters") == 1, "Signal aktiv " .. red_signal(s.depot, "arrakis-signal-harvesters"))
  check(failed, depot_items(s, NAME) == 2, depot_items(s, NAME) .. " im Lager statt 2")
  return verdict(run, tb, 5, "Umsetzen bei leerem Feld", failed, string.format("umgesetzt nach %s s, %s Kacheln weiter",
    tb.num((game.tick - s.start) / 60), tb.num(valid(s.mover) and fleet_distance(s.mover.position, s.from) or 0)))
end

-- 6) Feldsuche ohne Flug: nähere Felder gewinnen, eine Kartenmarkierung mit Spice-Sand-Symbol geht vor, ein lauernder
-- Wurm sperrt seinen Sektor.
function t26.s6_build(run, tb, d)
  local s = d.s6
  fleet_force(true)
  s.depot = create(run, tb, {name = DEPOT, position = d.pos.depot, force = t23_force(), raise_built = true}, "others")
  if not s.depot then return fail(run, tb, 6, "Leitstelle ließ sich nicht bauen") end
  -- P1 110 Kacheln von der Leitstelle, P2 250 Kacheln: mehr als ein Sektor (128) auseinander. y = 20: weg von der
  -- Sektorgrenze bei y = 0 (Sektoren 128 Kacheln, ab 0 gezählt), sonst hätte jedes Feld Plätze in zwei Sektoren.
  s.fields = place_fields(tb, d, {{x = -40, y = 20}, {x = 100, y = 20}})
  chart_area(tb, d)
  s.deadline = game.tick + 10 * 60
  return 1
end

function t26.s6_chart(run, tb, d)
  local s = d.s6
  return wait_for(s, function() return charted(tb, s.fields) end,
    function()
      skip_chart(run, tb, "6) ")
      s.uncharted = true
      return 1
    end)
end

function t26.s6_check(run, tb, d)
  local s = d.s6
  local failed = {}
  local surface = tb.surface()
  for _, p in ipairs(s.fields) do
    local cx, cy = math.floor(p.x / 32), math.floor(p.y / 32)
    for dx = -1, 1 do for dy = -1, 1 do fields.count(surface, cx + dx, cy + dy) end end
  end
  local dr = depot_record(s)
  local function near(spot, p) return spot and fleet_distance(spot, p) <= 3 end
  local a = fields.find_spot(dr, fleet.RANGE)
  check(failed, near(a, s.fields[1]), "ohne Markierung nicht das nähere Feld: " .. pos_text(tb, a))
  -- Kartenmarkierungen gehen nur auf kartierten Chunks.
  local tag
  if s.uncharted then
    tb.log(run, "INFO", "6) Vorrang der Kartenmarkierung nicht prüfbar (Chunks nicht kartiert, V6)")
  else
    tag = t23_force().add_chart_tag(surface, {position = s.fields[2], icon = {type = "item", name = SPICE}})
    check(failed, tag ~= nil, "Kartenmarkierung ließ sich nicht setzen")
  end
  local b = fields.find_spot(dr, fleet.RANGE)
  if not s.uncharted then
    check(failed, near(b, s.fields[2]), "mit Markierung nicht das markierte Feld: " .. pos_text(tb, b))
  end
  local _, sector = vibration_lib.key_of(s.fields[2])
  worms_lib.lurk(surface.index, sector, game.tick + 60 * 60)
  local c = fields.find_spot(dr, fleet.RANGE)
  check(failed, near(c, s.fields[1]), "lauernder Wurm am markierten Feld nicht gemieden: " .. pos_text(tb, c))
  local _, sector1 = vibration_lib.key_of(s.fields[1])
  check(failed, sector1 ~= sector, "beide Felder im selben Sektor")
  worms_lib.lurk(surface.index, sector1, game.tick + 60 * 60)
  local e = fields.find_spot(dr, fleet.RANGE)
  check(failed, e == nil, "beide Sektoren gesperrt, trotzdem Platz " .. pos_text(tb, e))
  worms_lib.clear_lurk(surface.index)
  if tag and tag.valid then tag.destroy() end
  return verdict(run, tb, 6, "Feldsuche: Abstand, Markierung, lauernder Wurm", failed, string.format(
    "ohne Markierung %s, mit Markierung %s, Wurm am markierten %s, beide gesperrt %s; Plätze bekannt %d",
    pos_text(tb, a), pos_text(tb, b), pos_text(tb, c), pos_text(tb, e), fields.known_spots(dr, fleet.RANGE)))
end

-- 7) Signal R: beide Ernter (einer selbst gesetzt, einer eigener mit Ladung) an die Leitstelle; solange R gilt, keiner
-- zurück; R = 0 bringt beide auf ihre Felder.
local T26_R_FIELDS = {{x = -60, y = 20}, {x = -10, y = -20}}

function t26.s7_build(run, tb, d)
  local s = d.s7
  fleet_force(true)
  if not build_base(run, tb, d, s, {carryalls = 3, rocket = 60, coal = 300}) then return fail(run, tb, 7, "Leitstelle oder Carryalls ließen sich nicht bauen") end
  local origin = tb.area(run.id)
  s.cars = {
    new_harvester(run, tb, d, at(origin, T26_R_FIELDS[1].x, T26_R_FIELDS[1].y)),
    new_harvester(run, tb, d, at(origin, T26_R_FIELDS[2].x, T26_R_FIELDS[2].y), {fill = 1})
  }
  if not (s.cars[1] and s.cars[2]) then return fail(run, tb, 7, "Ernter ließen sich nicht bauen") end
  h_of(s.cars[2]).fleet_owner = s.depot.unit_number
  s.origins = {}
  for i, car in ipairs(s.cars) do s.origins[i] = {x = car.position.x, y = car.position.y} end
  fleet.set_target(depot_record(s), 2)
  return harvester.DEPLOY_TICKS + 30
end

function t26.s7_recall(run, tb, d)
  local s = d.s7
  for i, car in ipairs(s.cars) do
    if state_of(car) ~= "deployed" then return fail(run, tb, 7, "Ernter " .. i .. " baut nicht auf (" .. state_of(car) .. ")") end
  end
  if not set_wire_signal(run, tb, s, "R", 1) then return fail(run, tb, 7, "Konstant-Schaltungsgebäude ließ sich nicht bauen") end
  s.start = game.tick
  s.deadline = game.tick + 240 * 60
  return 1
end

local function both_recalled(s)
  for _, car in ipairs(s.cars) do
    local h = h_of(car)
    if not (h and h.state == "mobile" and h.fleet_wait and h.fleet_wait.reason == "recall") then return false end
  end
  return true
end

function t26.s7_home(run, tb, d)
  local s = d.s7
  local r = wait_for(s, function()
    if not both_recalled(s) then return false end
    s.home_tick = game.tick
    return true
  end, function()
    return fail(run, tb, 7, string.format("nach 240 s nicht beide an der Leitstelle: %s / %s", state_of(s.cars[1]), state_of(s.cars[2])))
  end)
  if r == 1 then return 15 * 60 end
  return r
end

function t26.s7_hold(run, tb, d)
  local s = d.s7
  -- 15 s später: noch immer beide an der Leitstelle (R gilt), kein Auftrag.
  s.held = both_recalled(s) and depot_jobs(s) == 0
  s.dist_home = valid(s.cars[1]) and fleet_distance(s.cars[1].position, s.depot.position) or -1
  set_wire_signal(run, tb, s, "R", 0)
  s.release = game.tick
  s.deadline = game.tick + 240 * 60
  return 1
end

function t26.s7_back(run, tb, d)
  local s = d.s7
  return wait_for(s, function()
    for i, car in ipairs(s.cars) do
      if not (state_of(car) == "deployed" and fleet_distance(car.position, s.origins[i]) <= 4) then return false end
    end
    return true
  end, function()
    return fail(run, tb, 7, string.format("nach 240 s nicht beide zurück: %s / %s", state_of(s.cars[1]), state_of(s.cars[2])))
  end)
end

function t26.s7_check(run, tb, d)
  local s = d.s7
  local failed = {}
  check(failed, s.held, "während R nicht beide wartend an der Leitstelle")
  check(failed, s.dist_home <= 18, "Ernter 1 " .. tb.num(s.dist_home) .. " Kacheln von der Leitstelle")
  return verdict(run, tb, 7, "Signal R holt alle, R = 0 bringt sie zurück", failed, string.format(
    "an der Leitstelle nach %s s, zurück nach %s s", tb.num((s.home_tick - s.start) / 60), tb.num((game.tick - s.release) / 60)))
end

local T26_STEPS =
{
  {t26.s1},
  {t26.s2_build, t26.s2_chart, t26.s2_wait, t26.s2_check},
  {t26.s3_set, t26.s3_wait, t26.s3_check},
  {t26.s4_set, t26.s4_wait, t26.s4_check},
  {t26.s5_empty, t26.s5_wait, t26.s5_check},
  {t26.s6_build, t26.s6_chart, t26.s6_check},
  {t26.s7_build, t26.s7_recall, t26.s7_home, t26.s7_hold, t26.s7_back, t26.s7_check}
}

local function t26_start(run, tb)
  prepare(run, tb)
  local d = run.data
  d.run_id = run.id
  for number = 1, #T26_STEPS do d["s" .. number] = d["s" .. number] or {} end
  d.after_step = "sweep"
  fleet_force(true)
  fields.reset()
  tb.watch(run, nil, d.pos.watch)
  tb.log(run, "INFO", "Sieben Schritte Flottenleitung mit der echten Automatik (Soll, H, Rückruf ins Lager, Umsetzen,"
    .. " Feldsuche, R), Force " .. T23_FORCE .. " ohne Wurm. Dauer etwa 12 min Spielzeit.")
  d.step, d.phase, d.wait_until = 1, 1, game.tick + 30
end

local function t26_tick(run, tb)
  run_steps(run, tb, T26_STEPS)
end

local function t26_cleanup(run, tb)
  pcall(tidy, run)
  pcall(sweep, run, tb)
  pcall(fleet_force, false)
  storage.fleet_pause_until = nil
end

-- T27 Dauerlauf Flottenleitung ---------------------------------------------------------------------------

local T27_TICKS = 60 * 60 * 60
local T27_SETTLE = 300 * 60
local T27_HUNT_EVERY = 75 * 60
-- Nach so vielen Minuten wird je ein Feld leer (das Feld eines aufgebauten Ernters).
local T27_EMPTY_AT = {8, 23, 38}
-- Nach einem leeren Feld spätestens so lange, bis wieder drei laufen (Ticks).
local T27_RECOVER = 240 * 60

local function open_transfer(s)
  local un = valid(s.depot) and s.depot.unit_number
  for _, job in pairs(storage.jobs.list) do
    if job.depot == un and (job.kind == "move" or job.kind == "deploy") then return true end
  end
  return false
end

local function t27_start(run, tb)
  prepare(run, tb)
  local d = run.data
  d.run_id = run.id
  d.s = {}
  local s = d.s
  fleet_force(true)
  fields.reset()
  if not build_base(run, tb, d, s, {carryalls = 3, rocket = 100, coal = 1500}) then
    tb.log(run, "FEHLER", "Leitstelle oder Carryalls ließen sich nicht bauen")
    tb.finish(run, "abgebrochen (Aufbau)")
    return
  end
  -- 48 Plätze: 30 Kohle, 5 Raketentreibstoff, 5 Ernter (Stapel 1).
  local inserted = s.depot.get_inventory(defines.inventory.chest).insert{name = NAME, count = 5}
  if inserted ~= 5 then
    tb.log(run, "FEHLER", "nur " .. inserted .. " von 5 Erntern passen ins Lager der Leitstelle")
    tb.finish(run, "abgebrochen (Aufbau)")
    return
  end
  s.intake = create(run, tb, {name = INTAKE, position = d.pos.intake, force = t23_force(), raise_built = true}, "others")
  s.fields = place_fields(tb, d, T26_FIELDS)
  chart_area(tb, d)
  if not set_wire_signal(run, tb, s, "H", 3) then
    tb.finish(run, "abgebrochen (Aufbau)")
    return
  end
  s.start = game.tick
  s.next_hunt = game.tick + 90 * 60
  s.target = 0
  s.hunts = {}
  s.kinds = {}
  s.jobs = {}
  s.max_active = 0
  s.empties = {}
  s.recover = {}
  s.docked = 0
  tb.watch(run, nil, d.pos.watch)
  tb.log(run, "INFO", "Dauerlauf 60 min Spielzeit: 5 Ernter im Lager, Signal H = 3, sechs Felder, nach 8, 23 und 38 min wird je"
    .. " ein Feld leer, alle 75 s ein Wurmzeichen. Erwartet: nie mehr als 3 aktiv, nach jedem leeren Feld binnen 4 min wieder 3"
    .. " aufgebaut, kein Biss, kein Ernter verloren.")
end

local function t27_tick(run, tb)
  local d = run.data
  local s = d.s
  if not (s and s.start) then return end
  local tick = game.tick
  chart_or_skip(run, tb, s)
  local dr = depot_record(s)
  local c = dr and dr.census
  if c and c.active > s.max_active then s.max_active = c.active end
  for id, job in pairs(storage.jobs.list) do
    if not s.jobs[id] then
      s.jobs[id] = true
      s.kinds[job.kind] = (s.kinds[job.kind] or 0) + 1
    end
  end
  local deployed = owned(s, "deployed")
  -- Annahme wie in T24: angedockte Ernter werden geleert.
  if tick % 60 == 0 then
    for _, h in ipairs(owned(s, "docked")) do
      local trunk = h.entity.get_inventory(defines.inventory.car_trunk)
      if not trunk.is_empty() then
        trunk.clear()
        s.docked = s.docked + 1
      end
    end
  end
  -- Felder leeren.
  local minute = (tick - s.start) / 3600
  for i, at_min in ipairs(T27_EMPTY_AT) do
    if not s.empties[i] and minute >= at_min and #deployed > 0 then
      local h = deployed[(i % #deployed) + 1]
      empty_field(tb, h.entity.position)
      s.empties[i] = tick
      s.moves_before = s.moves_before or {}
      s.moves_before[i] = s.kinds.move or 0
      tb.trace(run, "Feld leer bei " .. pos_text(tb, h.entity.position))
    end
    -- Wieder drei: seit dem leeren Feld ein Umsetzen begonnen, drei aktiv (aufgebaut oder nach einer Rettung wartend)
    -- und kein Einsatz oder Umsetzen offen. (PC-Lauf 325d24b zählte ohne die erste Bedingung 2 s, bevor der Ernter
    -- „Feld leer“ meldete.)
    if s.empties[i] and not s.recover[i] and (s.kinds.move or 0) > s.moves_before[i] and c and c.active == 3
        and not open_transfer(s) then
      s.recover[i] = tick - s.empties[i]
    end
  end
  -- Wurmzeichen.
  if tick >= s.next_hunt and tick < s.start + T27_TICKS then
    s.next_hunt = tick + T27_HUNT_EVERY
    if #deployed > 0 then
      s.target = s.target % #deployed + 1
      local hunt = worms_lib.start_hunt(deployed[s.target].entity, {seconds = 60, debug = true})
      if hunt then table.insert(s.hunts, hunt) end
    else
      s.skipped = (s.skipped or 0) + 1
    end
  end
  if (tick - s.start) % 1800 == 0 then
    tb.trace(run, string.format("Stand: aufgebaut %d, aktiv %s, Reserve %s, Aufträge %d", #deployed, tostring(c and c.active),
      tostring(c and c.reserve), depot_jobs(s)))
  end
  if tick < s.start + T27_TICKS + T27_SETTLE then return end
  local failed = {}
  local escaped, bitten, open = 0, 0, 0
  for _, hunt in ipairs(s.hunts) do
    if hunt.outcome == "escaped" then escaped = escaped + 1
    elseif hunt.outcome == "bitten" then bitten = bitten + 1
    else open = open + 1 end
  end
  check(failed, #s.hunts >= 25, #s.hunts .. " Wurmzeichen statt mindestens 25")
  check(failed, bitten == 0 and open == 0, bitten .. " gebissen, " .. open .. " ohne Ende")
  check(failed, s.max_active <= 3, "bis zu " .. s.max_active .. " aktiv")
  -- Aktiv statt aufgebaut: Auch nach den Wurmzeichen sind oft ein oder zwei gerade zum Entladen an der Annahme
  -- (PC-Lauf fa36b5f: aufgebaut 1 bis 3, aktiv immer 3).
  check(failed, c ~= nil and c.active == 3, tostring(c and c.active) .. " aktiv am Ende statt 3")
  local total = #owned(s) + depot_items(s, NAME)
  check(failed, total == 5, total .. " Ernter statt 5 (draußen und im Lager)")
  local recover = {}
  for i = 1, #T27_EMPTY_AT do
    local r = s.recover[i]
    table.insert(recover, r and tb.num(r / 60) or "nie")
    check(failed, r ~= nil and r <= T27_RECOVER, "nach leerem Feld " .. i .. " nicht binnen 4 min wieder 3")
  end
  check(failed, (s.kinds.move or 0) >= #T27_EMPTY_AT, (s.kinds.move or 0) .. " Umsetzen statt mindestens " .. #T27_EMPTY_AT)
  local kinds = {}
  for _, kind in ipairs({"deploy", "move", "recall", "rescue", "return", "unload", "refuel"}) do
    table.insert(kinds, kind .. " " .. (s.kinds[kind] or 0))
  end
  tb.log(run, #failed == 0 and "OK" or "FEHLER", string.format(
    "Dauerlauf Flottenleitung: Wurmzeichen %d (entkommen %d), höchstens %d aktiv, wieder 3 nach %s s, Aufträge %s, entladen %d"
    .. ", ausgefallen %d", #s.hunts, escaped, s.max_active, table.concat(recover, "/"), table.concat(kinds, ", "), s.docked,
    s.skipped or 0) .. (#failed > 0 and (" | nicht erfüllt: " .. table.concat(failed, "; ")) or ""))
  s.start = nil
  tb.finish(run, #failed == 0 and "Dauerlauf OK" or "Dauerlauf FEHLER")
end

local function t27_cleanup(run, tb)
  pcall(tidy, run)
  pcall(sweep, run, tb)
  pcall(fleet_force, false)
end

-- T28 Ansicht Flottenleitung (interaktiv) ------------------------------------------------------------------

local T28_END = 300 * 60

local function t28_start(run, tb)
  local player = tb.player(run)
  if not player then
    tb.log(run, "FEHLER", "T28 braucht einen Spieler")
    tb.finish(run, "abgebrochen (ohne Spieler)")
    return
  end
  prepare(run, tb)
  local d = run.data
  d.run_id = run.id
  d.s = {}
  local s = d.s
  fleet_force(true)
  fields.reset()
  if not build_base(run, tb, d, s, {carryalls = 2, rocket = 60, coal = 300}) then
    tb.finish(run, "abgebrochen (Aufbau)")
    return
  end
  s.depot.get_inventory(defines.inventory.chest).insert{name = NAME, count = 3}
  s.fields = place_fields(tb, d, {T26_FIELDS[1], T26_FIELDS[2], T26_FIELDS[3]})
  chart_area(tb, d)
  -- Lampe am roten Draht: leuchtet, sobald mindestens zwei Ernter aktiv sind (Strom aus einer Energieschnittstelle).
  pcall(function()
    local p = s.depot.position
    create(run, tb, {name = "electric-energy-interface", position = at(p, -6, -9), force = t23_force()}, "others")
    create(run, tb, {name = "small-electric-pole", position = at(p, -4, -9), force = t23_force()}, "others")
    s.lamp = create(run, tb, {name = "small-lamp", position = at(p, -3, -6), force = t23_force()}, "others")
    s.lamp.get_wire_connector(defines.wire_connector_id.circuit_red, true).connect_to(
      s.depot.get_wire_connector(defines.wire_connector_id.circuit_red, true), false)
    local behavior = s.lamp.get_or_create_control_behavior()
    behavior.circuit_enable_disable = true
    behavior.circuit_condition = {first_signal = {type = "virtual", name = "arrakis-signal-harvesters"}, comparator = "≥",
      constant = 2}
  end)
  s.viewer = player.index
  tb.watch(run, player, at(s.depot.position, 8, 4))
  tb.protect(run, player)
  s.start = game.tick
  tb.log(run, "INFO", "Leitstelle mit Flottenleitung, 3 Ernter im Lager, drei Spicefelder rechts. Öffne die Leitstelle: Stell die"
    .. " Soll-Zahl mit + auf 2; zwei Carryalls setzen nacheinander je einen Ernter ein, die Lampe links oben leuchtet ab zwei"
    .. " aktiven. Dann „Alle zurückrufen“ drücken (beide kommen an die Leitstelle) und noch einmal drücken (sie fliegen"
    .. " zurück). 5 min Zeit.")
end

local function t28_tick(run, tb)
  local s = run.data.s
  if not (s and s.start) then return end
  chart_or_skip(run, tb, s)
  if game.tick >= s.start + T28_END then
    s.start = nil
    tb.log(run, "FRAGE", "Passen das Fenster der Leitstelle (Soll mit - und +, Rückruf-Knopf, Zeilen Aktiv/Reserve/Feldsuche) und"
      .. " der Ablauf (Einsatz aus dem Lager, Rückruf, Lampe am Draht)? Antwort bitte im Thread.")
    tb.finish(run, "Ansicht gezeigt")
  end
end

local function t28_cleanup(run, tb)
  pcall(tidy, run)
  pcall(sweep, run, tb)
  pcall(fleet_force, false)
end

return
{
  T23 =
  {
    title = "Carryall-Automatik: echter Code",
    timeout = 8 * 60 * 60,
    interactive = false,
    confirm = nil,
    start = t23_start,
    tick = t23_tick,
    cleanup = t23_cleanup
  },
  T24 =
  {
    title = "Carryall-Automatik: Dauerlauf",
    timeout = T24_TICKS + T24_SETTLE + 60 * 60,
    interactive = false,
    confirm = nil,
    start = t24_start,
    tick = t24_tick,
    cleanup = t24_cleanup
  },
  T25 =
  {
    title = "Carryall und Leitstelle: Ansicht",
    timeout = T25_END + 60 * 60,
    interactive = true,
    answer_time = 120 * 60,
    confirm = nil,
    start = t25_start,
    tick = t25_tick,
    cleanup = t25_cleanup
  },
  T26 =
  {
    title = "Flottenleitung: echter Code",
    timeout = 20 * 60 * 60,
    interactive = false,
    confirm = nil,
    start = t26_start,
    tick = t26_tick,
    cleanup = t26_cleanup
  },
  T27 =
  {
    title = "Flottenleitung: Dauerlauf",
    timeout = T27_TICKS + T27_SETTLE + 60 * 60,
    interactive = false,
    confirm = nil,
    start = t27_start,
    tick = t27_tick,
    cleanup = t27_cleanup
  },
  T28 =
  {
    title = "Flottenleitung: Ansicht",
    timeout = T28_END + 60 * 60,
    interactive = true,
    answer_time = 120 * 60,
    confirm = nil,
    start = t28_start,
    tick = t28_tick,
    cleanup = t28_cleanup
  }
}
