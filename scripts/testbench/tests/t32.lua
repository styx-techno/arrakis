-- T32 Thumper 0.14.0 (docs/plan-3h.md 2.1, 4): Bauregel, Köder (Wurmzeichen nach etwa 20 s, zählt nicht zu MAX_HUNTS,
-- Ende ohne Ruhe, Rücksetzen und Lauern), Ablenkung einer Ernter-Jagd (160 ja, 200 nein), Laufzeit und Zerfall (auch
-- „pocht weiter, solange ihm eine Jagd gilt“), Forschung nach der ersten überstandenen Jagd.
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_fleet.lua (T23-Fläche, Force arrakis-t23 ohne Wurm).

local common = require("scripts.testbench.gemeinsam_fleet")
local harvester = require("scripts.harvester")
local worms_lib = require("scripts.worms")
local vibration_lib = require("scripts.vibration")
local thumper_lib = require("scripts.thumper")
local T23_FORCE = common.T23_FORCE
local t23_force = common.t23_force
local tidy = common.tidy
local create = common.create
local at = common.at
local valid = common.valid
local new_harvester = common.new_harvester
local verdict = common.verdict
local fail = common.fail
local check = common.check
local prepare = common.prepare
local run_steps = common.run_steps
local sweep = common.sweep

local THUMPER = thumper_lib.NAME

local function surface_index()
  return game.get_surface("arrakis-testbench").index
end

local function build(run, tb, position)
  return create(run, tb, {name = THUMPER, position = {x = position.x + 0.5, y = position.y + 0.5}, force = t23_force(),
    raise_built = true}, "others")
end

local function record_of(entity)
  return valid(entity) and storage.thumpers and storage.thumpers[entity.unit_number] or nil
end

local t32 = {}

-- 1) Bauregel: von Hand nur auf Sand (Fels der Insel nein, Sand ja).
function t32.s1(run, tb, d)
  local failed = {}
  local surface = tb.surface()
  local function can(position)
    local ok, result = pcall(function()
      return surface.can_place_entity{name = THUMPER, position = {x = position.x + 0.5, y = position.y + 0.5},
        force = t23_force(), build_check_type = defines.build_check_type.manual}
    end)
    return ok and result
  end
  local rock, sand = can(d.pos.depot), can(d.pos.rescue)
  check(failed, rock == false, "auf Fels baubar")
  check(failed, sand == true, "auf Sand nicht baubar")
  return verdict(run, tb, 1, "Bauregel", failed, "Fels " .. tostring(rock) .. ", Sand " .. tostring(sand))
end

-- 2) Köder: Thumper allein auf Sand, MAX_HUNTS = 0. Nach etwa 20 s Wurmzeichen auf den Thumper (lure); Ende ohne Ruhe,
-- ohne Lauern, Wärme bleibt, Statistik thumper + 1.
function t32.s2_build(run, tb, d)
  local s = d.s2
  local force = t23_force()
  vibration_lib.testbench_enable(force)
  worms_lib.set_grace(force, {awake = true, first_hunt_done = true}, {"first_hunt"})
  worms_lib.set_paused(nil)
  worms_lib.clear_lurk(surface_index())
  storage.sector_cooldown[surface_index()] = nil
  d.max_hunts = worms_lib.MAX_HUNTS
  worms_lib.MAX_HUNTS = 0
  s.thumper = build(run, tb, d.pos.far)
  if not s.thumper then return fail(run, tb, 2, "Thumper ließ sich nicht bauen") end
  s.built = game.tick
  s.stats = worms_lib.stats_of(force).thumper or 0
  s.deadline = game.tick + 45 * 60
  return 1
end

function t32.s2_wait(run, tb, d)
  local s = d.s2
  if not valid(s.thumper) then return fail(run, tb, 2, "Thumper verschwunden vor dem Wurmzeichen") end
  local hunt = worms_lib.hunt_of(s.thumper)
  if hunt then
    s.hunt = hunt
    return 1
  end
  if game.tick >= s.deadline then
    worms_lib.MAX_HUNTS = d.max_hunts
    local key = vibration_lib.key_of(s.thumper.position)
    return fail(run, tb, 2, "kein Wurmzeichen in 45 s, Wärme 3×3 " .. tb.num(vibration_lib.sum3(surface_index(), key) or 0))
  end
  return 30
end

function t32.s2_check(run, tb, d)
  local s = d.s2
  local failed = {}
  local hunt = s.hunt
  worms_lib.MAX_HUNTS = d.max_hunts
  local si = surface_index()
  local seconds = (hunt.warn_tick - s.built) / 60
  check(failed, hunt.lure == true and hunt.thumper == true, "Jagd nicht als Köder markiert")
  check(failed, seconds >= 15 and seconds <= 30, "Wurmzeichen nach " .. tb.num(seconds) .. " s statt 15–30")
  local key, sector = vibration_lib.key_of(s.thumper.position)
  worms_lib.end_hunt(hunt, "gone")
  local heat = vibration_lib.sum3(si, key) or 0
  local resting = vibration_lib.resting(si, sector)
  local lurking = worms_lib.lurking(si, sector)
  local stats = worms_lib.stats_of(t23_force()).thumper or 0
  if valid(s.thumper) then s.thumper.destroy() end
  vibration_lib.testbench_disable(t23_force())
  check(failed, heat >= vibration_lib.UNREST, "Wärme zurückgesetzt (" .. tb.num(heat) .. ")")
  check(failed, not resting, "Sektor ruht")
  check(failed, lurking == nil, "Wurm lauert")
  check(failed, stats == s.stats + 1, "Statistik thumper " .. s.stats .. " → " .. stats)
  return verdict(run, tb, 2, "Köder", failed, string.format("Wurmzeichen nach %s s trotz MAX_HUNTS 0, Wärme danach %s, Ruhe %s, lauert %s",
    tb.num(seconds), tb.num(heat), tostring(resting ~= nil and resting ~= false), tostring(lurking ~= nil)))
end

-- 3) Ablenkung: Jagd auf einen Ernter; Thumper 200 Kacheln weg lenkt nicht ab, 100 Kacheln weg schon.
function t32.s3_build(run, tb, d)
  local s = d.s3
  s.car = new_harvester(run, tb, d, d.pos.rescue)
  if not s.car then return fail(run, tb, 3, "Ernter ließ sich nicht bauen") end
  return harvester.DEPLOY_TICKS + 10
end

function t32.s3_check(run, tb, d)
  local s = d.s3
  local failed = {}
  local hunt, reason = worms_lib.start_hunt(s.car, {})
  if not hunt then return fail(run, tb, 3, "start_hunt: " .. tostring(reason)) end
  local eta = hunt.eta_tick
  local far = build(run, tb, at(d.pos.rescue, 200, 0))
  local far_kept = hunt.target == s.car and (record_of(far) or {}).diverted == nil
  local near_pos = at(d.pos.rescue, 100, 0)
  local near = build(run, tb, near_pos)
  if not (far and near) then
    worms_lib.end_hunt(hunt, nil, "abort")
    return fail(run, tb, 3, "Thumper ließ sich nicht bauen")
  end
  local h = harvester.get(s.car)
  check(failed, far_kept, "Thumper in 200 Kacheln hat abgelenkt")
  check(failed, hunt.target == near and hunt.target_un == near.unit_number, "Ziel nicht der nahe Thumper")
  check(failed, hunt.thumper == true and hunt.diverted == true and not hunt.lure, "Jagd nicht als umgelenkt markiert")
  check(failed, (record_of(near) or {}).diverted == hunt.id, "Thumper kennt die Jagd nicht")
  check(failed, hunt.eta_tick == eta, "Countdown verändert")
  check(failed, worms_lib.hunt_of(s.car) == nil, "Ernter noch Ziel")
  check(failed, h and not h.alarm_hunt_eta, "Alarm am Ernter bleibt")
  check(failed, math.abs(hunt.warn_pos.x - near.position.x) < 0.01 and math.abs(hunt.warn_pos.y - near.position.y) < 0.01,
    "warn_pos nicht am Thumper")
  local text = string.format("200 Kacheln: %s, 100 Kacheln: Ziel %s, Rest %s s", far_kept and "keine Ablenkung" or "abgelenkt",
    hunt.target == near and "Thumper" or "anders", tb.num((hunt.eta_tick - game.tick) / 60))
  worms_lib.end_hunt(hunt, nil, "abort")
  return verdict(run, tb, 3, "Ablenkung", failed, text)
end

-- 4) Laufzeit: TICKS = 120. Ohne Jagd zerfällt er, mit Jagd pocht er weiter, bis sie endet.
function t32.s4_build(run, tb, d)
  local s = d.s4
  d.ticks = thumper_lib.TICKS
  thumper_lib.TICKS = 120
  s.alone = build(run, tb, at(d.pos.rescue, 0, -20))
  s.hunted = build(run, tb, at(d.pos.rescue, 0, 20))
  thumper_lib.TICKS = d.ticks
  if not (s.alone and s.hunted) then return fail(run, tb, 4, "Thumper ließ sich nicht bauen") end
  s.un = s.alone.unit_number
  s.hunt = worms_lib.start_hunt(s.hunted, {debug = true})
  if not s.hunt then return fail(run, tb, 4, "Jagd auf den Thumper ging nicht") end
  return 240
end

function t32.s4_mid(run, tb, d)
  local s = d.s4
  s.alone_gone = not valid(s.alone) and storage.thumpers[s.un] == nil
  s.hunted_alive = valid(s.hunted)
  worms_lib.end_hunt(s.hunt, nil, "abort")
  return 120
end

function t32.s4_check(run, tb, d)
  local s = d.s4
  local failed = {}
  check(failed, s.alone_gone, "ohne Jagd nicht zerfallen")
  check(failed, s.hunted_alive, "mit Jagd zerfallen")
  check(failed, not valid(s.hunted), "nach Jagdende nicht zerfallen")
  return verdict(run, tb, 4, "Laufzeit", failed, string.format("allein weg %s, mit Jagd da %s, danach weg %s",
    tostring(s.alone_gone), tostring(s.hunted_alive), tostring(not valid(s.hunted))))
end

-- 5) Forschung „Thumper“: ohne überstandene Jagd nicht, mit first_escape_tick binnen 2 s erforscht.
function t32.s5_start(run, tb, d)
  local s = d.s5
  local force = t23_force()
  local stats = worms_lib.stats_of(force)
  d.escape = stats.first_escape_tick
  d.researched = force.technologies[thumper_lib.TECH].researched
  stats.first_escape_tick = nil
  force.technologies[thumper_lib.TECH].researched = false
  return 120
end

function t32.s5_mid(run, tb, d)
  local s = d.s5
  local force = t23_force()
  s.before = force.technologies[thumper_lib.TECH].researched
  worms_lib.stats_of(force).first_escape_tick = game.tick
  return 120
end

function t32.s5_check(run, tb, d)
  local s = d.s5
  local failed = {}
  local force = t23_force()
  local after = force.technologies[thumper_lib.TECH].researched
  local unlocked = force.recipes[THUMPER].enabled
  check(failed, s.before == false, "ohne Jagd erforscht")
  check(failed, after == true, "nach überstandener Jagd nicht erforscht")
  check(failed, unlocked == true, "Rezept nicht frei")
  return verdict(run, tb, 5, "Forschung", failed, "vorher " .. tostring(s.before) .. ", nachher " .. tostring(after)
    .. ", Rezept " .. tostring(unlocked))
end

local T32_STEPS =
{
  {t32.s1},
  {t32.s2_build, t32.s2_wait, t32.s2_check},
  {t32.s3_build, t32.s3_check},
  {t32.s4_build, t32.s4_mid, t32.s4_check},
  {t32.s5_start, t32.s5_mid, t32.s5_check}
}

local function t32_start(run, tb)
  prepare(run, tb)
  local d = run.data
  for number = 1, #T32_STEPS do d["s" .. number] = {} end
  d.after_step = "sweep"
  d.grace = worms_lib.grace_snapshot(t23_force())
  tb.watch(run, nil, d.pos.watch)
  tb.log(run, "INFO", "Fünf Schritte 0.14.0 (Thumper) mit dem echten Code, Force " .. T23_FORCE
    .. " ohne Wurm. Dauer etwa 45 s Spielzeit.")
  d.step, d.phase, d.wait_until = 1, 1, game.tick + 30
end

local function t32_tick(run, tb)
  run_steps(run, tb, T32_STEPS)
end

local function t32_cleanup(run, tb)
  local d = run.data
  pcall(tidy, run)
  pcall(sweep, run, tb)
  if d.max_hunts then worms_lib.MAX_HUNTS = d.max_hunts end
  if d.ticks then thumper_lib.TICKS = d.ticks end
  pcall(function()
    local force = t23_force()
    vibration_lib.testbench_disable(force)
    if d.grace then worms_lib.grace_restore(force, d.grace) end
    if d.researched ~= nil then
      worms_lib.stats_of(force).first_escape_tick = d.escape
      force.technologies[thumper_lib.TECH].researched = d.researched
    end
    worms_lib.clear_lurk(surface_index())
    storage.sector_cooldown[surface_index()] = nil
    for un, record in pairs(storage.thumpers or {}) do
      if not record.entity.valid then storage.thumpers[un] = nil end
    end
  end)
  storage.fleet_pause_until = nil
end

return
{
  T32 =
  {
    title = "Thumper 0.14.0",
    timeout = 10 * 60 * 60,
    interactive = false,
    confirm = nil,
    start = t32_start,
    tick = t32_tick,
    cleanup = t32_cleanup
  }
}
