-- T24 Carryall-Automatik: Dauerlauf: Prüfstand-Test (aus t_fleet.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_fleet.lua.

local common = require("scripts.testbench.gemeinsam_fleet")
local fleet = require("scripts.fleet")
local worms_lib = require("scripts.worms")
local INTAKE = common.INTAKE
local valid = common.valid
local fleet_distance = common.fleet_distance
local pos_text = common.pos_text
local t23_force = common.t23_force
local create = common.create
local tidy = common.tidy
local fuel_items = common.fuel_items
local record_of = common.record_of
local h_of = common.h_of
local state_of = common.state_of
local build_base = common.build_base
local new_harvester = common.new_harvester
local check = common.check
local prepare = common.prepare

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

return
{
  T24 =
  {
    title = "Carryall-Automatik: Dauerlauf",
    timeout = T24_TICKS + T24_SETTLE + 60 * 60,
    interactive = false,
    confirm = nil,
    start = t24_start,
    tick = t24_tick,
    cleanup = t24_cleanup
  }
}
