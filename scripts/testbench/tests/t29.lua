-- T29 Flottenleitung 0.12.1: Forschungen: Prüfstand-Test (aus t_fleet.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_fleet.lua.

local common = require("scripts.testbench.gemeinsam_fleet")
local fleet = require("scripts.fleet")
local fields = require("scripts.fleet-fields")
local harvester = require("scripts.harvester")
local worms_lib = require("scripts.worms")
local vibration_lib = require("scripts.vibration")
local T23_FORCE = common.T23_FORCE
local T23_RESCUE_SECONDS = common.T23_RESCUE_SECONDS
local valid = common.valid
local fleet_distance = common.fleet_distance
local t23_force = common.t23_force
local tidy = common.tidy
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
local FLEET_TECH = common.FLEET_TECH
local fleet_force = common.fleet_force
local sweep = common.sweep

-- T29 Flottenleitung 0.12.1 -------------------------------------------------------------------------------
-- Forschungen Frühwarnung, Ernte-Dämpfung und Bereitschaftsflug (docs/plan-3f.md 1.11 bis 1.13 und 6) mit dem echten
-- Code auf der T23-Fläche, Force arrakis-t23 ohne Wurm. Das Aufräumen setzt alle drei Forschungen zurück.

local T29_EARLY = "arrakis-early-warning"
local T29_DAMPING = "arrakis-harvest-damping"
local T29_ESCORT = "arrakis-escort-flight"

-- Erforschte Stufen setzen: 0 = keine, max = alle (dann researched). Gibt die gelesene Stufe zurück.
local function t29_levels(name, done)
  local tech = t23_force().technologies[name]
  if not tech then return -1 end
  local max = tech.prototype.max_level
  if done >= max then
    tech.level = max
    tech.researched = true
  else
    tech.researched = false
    tech.level = done + 1
  end
  return vibration_lib.tech_level(tech.force, name)
end

local function t29_escort(on)
  local tech = t23_force().technologies[T29_ESCORT]
  if tech then tech.researched = on end
end

local function t29_reset()
  t29_levels(T29_EARLY, 0)
  t29_levels(T29_DAMPING, 0)
  t29_escort(false)
end

local function escort_of(s, car)
  local un = valid(car) and car.unit_number
  for _, carryall in ipairs(s.carryalls or {}) do
    local record = record_of(carryall)
    if record and un and record.escort == un then return carryall, record end
  end
  return nil
end

local t29 = {}

-- 1) Prototypen: drei Forschungen hinter Flottenleitung, Stufen 1 / 6 / 10.
function t29.s1(run, tb, d)
  local failed = {}
  local values = {}
  for _, entry in ipairs({{T29_ESCORT, 1}, {T29_EARLY, 6}, {T29_DAMPING, 10}}) do
    local proto = prototypes.technology[entry[1]]
    check(failed, proto ~= nil, entry[1] .. " fehlt")
    if proto then
      check(failed, proto.prerequisites[FLEET_TECH] ~= nil, entry[1] .. " nicht hinter " .. FLEET_TECH)
      local max = proto.max_level
      if entry[2] > 1 then check(failed, max == entry[2], entry[1] .. " max_level " .. tostring(max) .. " statt " .. entry[2]) end
      table.insert(values, entry[1] .. " " .. tostring(max))
    end
  end
  return verdict(run, tb, 1, "Forschungen 0.12.1", failed, table.concat(values, ", "))
end

-- 2) Frühwarnung: Countdown 60 s + 5 s je Stufe (0, 3, 6 Stufen), echte Jagd mit 6 Stufen 90 s, Lehrjagd bleibt 90 s.
function t29.s2_build(run, tb, d)
  local s = d.s2
  s.car = new_harvester(run, tb, d, d.pos.rescue)
  if not s.car then return fail(run, tb, 2, "Ernter ließ sich nicht bauen") end
  return harvester.DEPLOY_TICKS + 10
end

function t29.s2_check(run, tb, d)
  local s = d.s2
  local failed = {}
  local force = t23_force()
  local got = {}
  for _, n in ipairs({0, 3, 6}) do
    local level = t29_levels(T29_EARLY, n)
    local ticks = worms_lib.warn_ticks(force)
    check(failed, level == n, "Stufe gelesen " .. level .. " statt " .. n)
    check(failed, ticks == 3600 + 300 * n, n .. " Stufen: " .. ticks .. " Ticks statt " .. (3600 + 300 * n))
    table.insert(got, n .. "→" .. tb.num(ticks / 60) .. " s")
  end
  local diff, teach = -1, -1
  local hunt, reason = worms_lib.start_hunt(s.car, {debug = true})
  if hunt then diff = hunt.eta_tick - hunt.warn_tick else table.insert(failed, "start_hunt: " .. tostring(reason)) end
  check(failed, diff >= 5400 and diff < 5410, "Jagd mit 6 Stufen: Countdown " .. diff .. " Ticks statt 5400")
  check(failed, worms_lib.TEACH_TICKS == 5400, "Lehrjagd " .. worms_lib.TEACH_TICKS .. " statt 5400")
  t29_levels(T29_EARLY, 0)
  return verdict(run, tb, 2, "Frühwarnung", failed, table.concat(got, ", ") .. string.format(", Jagd %s s, Lehrjagd %s s",
    tb.num(diff / 60), tb.num(worms_lib.TEACH_TICKS / 60)))
end

-- 3) Ernte-Dämpfung: Gewicht aufgebaut bei 0, 4 und 10 Stufen (1, 0,8, 0,5), einpackend bei 10 Stufen halb.
function t29.s3_build(run, tb, d)
  local s = d.s3
  s.car = new_harvester(run, tb, d, d.pos.rescue)
  if not s.car then return fail(run, tb, 3, "Ernter ließ sich nicht bauen") end
  return harvester.DEPLOY_TICKS + 10
end

function t29.s3_check(run, tb, d)
  local s = d.s3
  local failed = {}
  if state_of(s.car) ~= "deployed" then return fail(run, tb, 3, "Ernter baut nicht auf (" .. state_of(s.car) .. ")") end
  local W = vibration_lib.WEIGHTS.by_state
  local got = {}
  for _, n in ipairs({0, 4, 10}) do
    local level = t29_levels(T29_DAMPING, n)
    local w, sand = vibration_lib.weight_of(s.car)
    local want = W.deployed * (1 - 0.05 * n)
    check(failed, sand == true, "kein Sand unter dem Ernter")
    check(failed, level == n, "Stufe gelesen " .. level .. " statt " .. n)
    check(failed, math.abs(w - want) < 1e-6, n .. " Stufen: Gewicht " .. tb.num(w) .. " statt " .. tb.num(want))
    table.insert(got, n .. "→" .. tb.num(w))
  end
  local h = h_of(s.car)
  local packing = -1
  if h and harvester.pack(h) then
    local w = vibration_lib.weight_of(s.car)
    packing = w
    local want = (h.careful_packing and W.careful_packing or W.packing) * 0.5
    check(failed, h.state == "packing" and math.abs(w - want) < 1e-6, "einpackend: Gewicht " .. tb.num(w) .. " statt " .. tb.num(want))
  else
    table.insert(failed, "Ernter packt nicht ein")
  end
  t29_levels(T29_DAMPING, 0)
  return verdict(run, tb, 3, "Ernte-Dämpfung", failed, "aufgebaut " .. table.concat(got, ", ") .. ", einpackend (10) "
    .. tb.num(packing))
end

-- 4) Bereitschaftsflug mit zwei Carryalls: ohne Forschung kein Begleiter; mit Forschung schwebt einer über dem
-- Ernter 100 Kacheln weit, der zweite bleibt an der Leitstelle (auch bei einem zweiten Ernter). Wurmzeichen: Der
-- Begleiter übernimmt die Rettung und hebt den Ernter binnen 5 s an.
t29.s4_base = base_phase(4, {carryalls = 2, rocket = 60, coal = 300})
t29.s4_parked = parked_phase(4)

function t29.s4_build(run, tb, d)
  local s = d.s4
  s.car = new_harvester(run, tb, d, d.pos.rescue)
  if not s.car then return fail(run, tb, 4, "Ernter ließ sich nicht bauen") end
  return harvester.DEPLOY_TICKS + 4 * 60
end

function t29.s4_research(run, tb, d)
  local s = d.s4
  if state_of(s.car) ~= "deployed" then return fail(run, tb, 4, "Ernter baut nicht auf (" .. state_of(s.car) .. ")") end
  s.early_escort = escort_of(s, s.car) ~= nil
  t29_escort(true)
  s.research_tick = game.tick
  s.deadline = game.tick + 40 * 60
  return 1
end

function t29.s4_follow(run, tb, d)
  local s = d.s4
  return wait_for(s, function()
    local carryall = escort_of(s, s.car)
    if carryall and fleet_distance(carryall.position, s.car.position) <= fleet.ARRIVE then
      s.escort = carryall
      s.over_tick = game.tick
      return true
    end
    return false
  end, function()
    local carryall = escort_of(s, s.car)
    return fail(run, tb, 4, "kein Begleiter über dem Ernter nach 40 s (Begleiter " .. tostring(carryall ~= nil)
      .. (carryall and (", Abstand " .. tb.num(fleet_distance(carryall.position, s.car.position))) or "") .. ")")
  end)
end

function t29.s4_second(run, tb, d)
  local s = d.s4
  s.car2 = new_harvester(run, tb, d, d.pos.refuel)
  if not s.car2 then return fail(run, tb, 4, "zweiter Ernter ließ sich nicht bauen") end
  return harvester.DEPLOY_TICKS + 5 * 60
end

function t29.s4_hunt(run, tb, d)
  local s = d.s4
  s.second_escort = escort_of(s, s.car2) ~= nil
  local other = s.escort == s.carryalls[1] and s.carryalls[2] or s.carryalls[1]
  s.other_parked = parked(s, other)
  s.still_over = valid(s.escort) and fleet_distance(s.escort.position, s.car.position) <= fleet.ARRIVE
  local hunt, reason = worms_lib.start_hunt(s.car, {seconds = T23_RESCUE_SECONDS, debug = true})
  if not hunt then return fail(run, tb, 4, "start_hunt: " .. tostring(reason)) end
  s.hunt = hunt
  s.hunt_tick = game.tick
  s.deadline = game.tick + 20 * 60
  return 1
end

function t29.s4_lift(run, tb, d)
  local s = d.s4
  local h = h_of(s.car)
  return wait_for(s, function()
    for _, carryall in ipairs(s.carryalls) do
      local record = record_of(carryall)
      if record and h and record.cargo == h.un then
        s.lifter = carryall
        s.lift_tick = game.tick
        return true
      end
    end
    return false
  end, function()
    s.lift_tick = nil
    return 1
  end)
end

function t29.s4_check(run, tb, d)
  local s = d.s4
  local failed = {}
  check(failed, not s.early_escort, "Begleiter ohne Forschung")
  check(failed, not s.second_escort, "zweiter Begleiter (Bereitschaft fehlt)")
  check(failed, s.other_parked, "zweiter Carryall nicht an der Leitstelle")
  check(failed, s.still_over, "Begleiter nicht mehr über dem Ernter")
  check(failed, s.lift_tick ~= nil, "Ernter nicht in 20 s angehoben")
  check(failed, s.lifter == nil or s.lifter == s.escort, "anderer Carryall als der Begleiter rettet")
  local lift = s.lift_tick and (s.lift_tick - s.hunt_tick) / 60
  check(failed, lift == nil or lift <= 5, "Anheben nach " .. tostring(lift and tb.num(lift)) .. " s statt höchstens 5 s")
  return verdict(run, tb, 4, "Bereitschaftsflug", failed, string.format(
    "Begleiter über dem Ernter %s s nach der Forschung, Anheben %s s nach dem Wurmzeichen",
    tb.num((s.over_tick - s.research_tick) / 60), lift and tb.num(lift) or "–"))
end

local T29_STEPS =
{
  {t29.s1},
  {t29.s2_build, t29.s2_check},
  {t29.s3_build, t29.s3_check},
  {t29.s4_base, t29.s4_parked, t29.s4_build, t29.s4_research, t29.s4_follow, t29.s4_second, t29.s4_hunt, t29.s4_lift,
    t29.s4_check}
}

local function t29_start(run, tb)
  prepare(run, tb)
  local d = run.data
  d.run_id = run.id
  for number = 1, #T29_STEPS do d["s" .. number] = {} end
  d.after_step = "sweep"
  fleet_force(true)
  t29_reset()
  fields.reset()
  tb.watch(run, nil, d.pos.watch)
  tb.log(run, "INFO", "Vier Schritte 0.12.1 mit dem echten Code (Forschungen, Frühwarnung, Ernte-Dämpfung, Bereitschaftsflug),"
    .. " Force " .. T23_FORCE .. " ohne Wurm. Dauer etwa 2 min Spielzeit.")
  d.step, d.phase, d.wait_until = 1, 1, game.tick + 30
end

local function t29_tick(run, tb)
  run_steps(run, tb, T29_STEPS)
end

local function t29_cleanup(run, tb)
  pcall(tidy, run)
  pcall(sweep, run, tb)
  pcall(t29_reset)
  pcall(fleet_force, false)
  storage.fleet_pause_until = nil
end

return
{
  T29 =
  {
    title = "Flottenleitung 0.12.1: Forschungen",
    timeout = 6 * 60 * 60,
    interactive = false,
    confirm = nil,
    start = t29_start,
    tick = t29_tick,
    cleanup = t29_cleanup
  }
}
