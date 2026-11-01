-- T23 Carryall-Automatik: echter Code: Prüfstand-Test (aus t_fleet.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_fleet.lua.

local common = require("scripts.testbench.gemeinsam_fleet")
local fleet = require("scripts.fleet")
local harvester = require("scripts.harvester")
local worms_lib = require("scripts.worms")
local vibration_lib = require("scripts.vibration")
local CARRYALL = common.CARRYALL
local DEPOT = common.DEPOT
local INTAKE = common.INTAKE
local SPICE = common.SPICE
local FLIGHT_FUEL = common.FLIGHT_FUEL
local T23_FORCE = common.T23_FORCE
local T23_RESCUE_SECONDS = common.T23_RESCUE_SECONDS
local valid = common.valid
local fleet_distance = common.fleet_distance
local t23_force = common.t23_force
local create = common.create
local tidy = common.tidy
local item_count = common.item_count
local burner_count = common.burner_count
local trunk_of = common.trunk_of
local fuel_items = common.fuel_items
local record_of = common.record_of
local h_of = common.h_of
local state_of = common.state_of
local parked = common.parked
local new_harvester = common.new_harvester
local verdict = common.verdict
local fail = common.fail
local check = common.check
local wait_for = common.wait_for
local base_phase = common.base_phase
local parked_phase = common.parked_phase
local prepare = common.prepare
local run_steps = common.run_steps

local intake = require("scripts.intake")
local speed = require("prototypes.ornithopter-speed")

-- Erwartetes Tempo leer mit Raketentreibstoff (Kacheln/s): Ornithopter 8,0 (T16) mal 1,125, ±10 %.
local T23_SPEED = 8 * 1.125
local T23_SPEED_TOL = 0.1
local T23_FAR_SECONDS = 10

local function job_of(car)
  local h = h_of(car)
  return h and fleet.job_of_harvester(h.un)
end

local function hunt_alive(hunt)
  return hunt ~= nil and storage.hunts.list[hunt.id] == hunt
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

local function t23_start(run, tb)
  prepare(run, tb)
  local d = run.data
  for number = 1, #T23_STEPS do d["s" .. number] = {} end
  tb.watch(run, nil, d.pos.watch)
  tb.log(run, "INFO", "Zehn Schritte mit der echten Carryall-Automatik (Übernahme, Rettung zur Leitstelle, Absage, Entladen,"
    .. " Tanken, Handbetrieb, Pause, Abriss, Wurm lauert), Force " .. T23_FORCE .. " ohne Wurm. Dauer etwa 6 min Spielzeit.")
  d.step, d.phase, d.wait_until = 1, 1, game.tick + 30
end

local function t23_tick(run, tb)
  run_steps(run, tb, T23_STEPS)
end

local function t23_cleanup(run, tb)
  pcall(t23_s10_restore, run.data)
  pcall(tidy, run)
  storage.fleet_pause_until = nil
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
  }
}
