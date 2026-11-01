-- T37 Großer Wurm 0.16.0 (docs/plan-3j.md 3): Prototyp, Zufalls-Auswahl je Revierstufe (ruhig nie, normal 10 %, wild 30 %,
-- Einstellung aus, Lehrjagd immer klein), Jagd mit großem Wurm (Biss-Umkreis 6 statt 4), getöteter
-- großer Wurm (6–10 Zähne, Revier doppelt so lange frei). Gemeinsame Helfer: scripts/testbench/gemeinsam_fleet.lua.

local common = require("scripts.testbench.gemeinsam_fleet")
local worms_lib = require("scripts.worms")
local vibration_lib = require("scripts.vibration")
local sandworm_lib = require("scripts.sandworm")
local territory = require("scripts.territory")
local valid = common.valid
local at = common.at
local t23_force = common.t23_force
local create = common.create
local tidy = common.tidy
local verdict = common.verdict
local fail = common.fail
local check = common.check
local wait_for = common.wait_for
local prepare = common.prepare
local run_steps = common.run_steps
local sweep = common.sweep

local LARGE = "arrakis-sandworm-large"
local SMALL = "arrakis-sandworm-small"
local CHEST = "steel-chest"
local SEED = 4711
-- Countdown der Befehlsjagden (s) und Spawnhaken: Wurm 90 Kacheln westlich des Ziels, Blick nach Osten.
local SECONDS = 40
local HOOK_DX = -90

local t37 = {}

-- 1) Prototypen: großer Wurm 100 000 LP (klein 30 000), 12 Segmente, Werte im Skript.
function t37.s1(run, tb, d)
  local failed = {}
  local large, small = prototypes.entity[LARGE], prototypes.entity[SMALL]
  check(failed, large ~= nil and large.type == "segmented-unit", LARGE .. " fehlt")
  local hp_l = large and large.get_max_health()
  local hp_s = small and small.get_max_health()
  check(failed, hp_l == 100000 and hp_s == 30000, "Lebenspunkte groß " .. tostring(hp_l) .. ", klein " .. tostring(hp_s))
  local size = sandworm_lib.SIZES.large
  check(failed, size.name == LARGE and size.body_len == 30 and size.lookahead == 24 and size.turn == 9,
    "sandworm.SIZES.large")
  local L = worms_lib.LARGE
  check(failed, L.bite_radius == 6 and L.crush_radius == 4 and L.tooth_min == 6 and L.tooth_max == 10 and L.free_factor == 2,
    "worms.LARGE")
  return verdict(run, tb, 1, "Prototypen", failed, string.format("Lebenspunkte groß %s, klein %s; Biss %s, Zerdrücken %s, Zähne %s–%s",
    tostring(hp_l), tostring(hp_s), tostring(L.bite_radius), tostring(L.crush_radius), tostring(L.tooth_min), tostring(L.tooth_max)))
end

-- 2) Zufalls-Auswahl je Revierstufe (Max „1c 3 zufall“): ruhig nie, normal 10 %, wild 30 %; Würfe mit storage.rng
-- (1000 je Stufe, Anteil ±5 Punkte), Einstellung aus, Lehrjagd immer klein, Befehlsjagd mit size groß.
function t37.s2(run, tb, d)
  local failed = {}
  local surface = tb.surface()
  local si = surface.index
  territory.test_real(surface, SEED)
  territory.test_reset(surface)
  d.territory_real = true
  local position = at(d.pos.rescue, 0, 0)
  local key = vibration_lib.key_of(position)
  local id = territory.of_key(si, key)
  local want = {calm = 0, normal = 0.1, wild = 0.3}
  local shares = {}
  for _, level in ipairs({"calm", "normal", "wild"}) do
    territory.test_level(surface, id, level)
    local chance = worms_lib.large_chance(si, key)
    local hits = 0
    for _ = 1, 1000 do
      if worms_lib.large_due(si, key) then hits = hits + 1 end
    end
    local share = hits / 1000
    shares[#shares + 1] = level .. " " .. tb.num(chance) .. "/" .. tb.num(share)
    check(failed, chance == want[level], level .. ": Chance " .. tostring(chance))
    check(failed, math.abs(share - want[level]) <= 0.05, level .. ": Anteil " .. tb.num(share))
    if level == "wild" then
      check(failed, worms_lib.large_due(si, key, 0.29) and not worms_lib.large_due(si, key, 0.3), "wild: Grenze bei 0,3")
    end
  end
  -- Einstellung aus (wild, Wurf 0).
  local was = worms_lib.LARGE_ENABLED
  worms_lib.LARGE_ENABLED = false
  local due_off = worms_lib.large_due(si, key, 0)
  worms_lib.LARGE_ENABLED = was
  check(failed, not due_off, "Einstellung aus: groß " .. tostring(due_off))
  territory.test_reset(surface)
  -- Lehrjagd bleibt klein, sonst gilt size.
  local force = t23_force()
  local a = create(run, tb, {name = CHEST, position = position, force = force}, "others")
  local b = create(run, tb, {name = CHEST, position = at(position, 10, 0), force = force}, "others")
  if not (a and b) then return fail(run, tb, 2, "Kisten ließen sich nicht bauen") end
  local h1 = worms_lib.start_hunt(a, {seconds = 2, debug = true, size = "large", teaching = true})
  local teach_size = h1 and h1.size
  if h1 then worms_lib.end_hunt(h1, nil, "abort") end
  local h2 = worms_lib.start_hunt(b, {seconds = 2, debug = true, size = "large"})
  local plain_size = h2 and h2.size
  if h2 then worms_lib.end_hunt(h2, nil, "abort") end
  check(failed, h1 ~= nil and teach_size == nil, "Lehrjagd: Größe " .. tostring(teach_size))
  check(failed, h2 ~= nil and plain_size == "large", "Befehlsjagd: Größe " .. tostring(plain_size))
  return verdict(run, tb, 2, "Zufalls-Auswahl", failed, string.format(
    "Chance/Anteil %s; Einstellung aus groß %s; Lehrjagd %s, Befehlsjagd %s", table.concat(shares, ", "), tostring(due_off),
    tostring(teach_size), tostring(plain_size)))
end

-- Jagd mit großem Wurm auf eine Kiste bei P, Spawnhaken 90 Kacheln westlich.
-- Die Force arrakis-t23 hat sonst keinen Wurm (gemeinsam_fleet.t23_force); hier für die Dauer des Starts an.
local function large_hunt(d, chest, debug)
  worms_lib.set_worm_off(t23_force(), false)
  local p = chest.position
  local hunt, reason = worms_lib.start_hunt(chest, {seconds = SECONDS, debug = debug, size = "large", bite = "total-loss",
    spawn = {position = {x = p.x + HOOK_DX, y = p.y}, direction = defines.direction.east}})
  t23_force()
  return hunt, reason
end

local function note_worm(s)
  local worm = s.hunt and s.hunt.worm
  local unit = worm and worm.unit
  if valid(unit) and not s.worm_name then
    s.worm_name = unit.name
    s.worm_hp = unit.max_health
  end
  return s.worm_name ~= nil
end

-- 3) Biss: Kiste als Ziel, ein Auto 6 Kacheln daneben (Box 5 weg: im Umkreis 6, nicht 4), eins 9 Kacheln daneben bleibt.
function t37.s3_build(run, tb, d)
  local s = d.s3
  local force = t23_force()
  local p = at(d.pos.far, 0, 0)
  s.chest = create(run, tb, {name = CHEST, position = p, force = force}, "others")
  s.near = create(run, tb, {name = "car", position = at(p, 0, 6), force = force}, "cars")
  s.far = create(run, tb, {name = "car", position = at(p, 0, -9), force = force}, "cars")
  if not (s.chest and s.near and s.far) then return fail(run, tb, 3, "Aufbau ging nicht") end
  local hunt, reason = large_hunt(d, s.chest, true)
  if not hunt then return fail(run, tb, 3, "start_hunt: " .. tostring(reason)) end
  s.hunt = hunt
  s.ring = hunt.renders.ring and hunt.renders.ring.valid and hunt.renders.ring.radius
  return 1
end

function t37.s3_check(run, tb, d)
  local s = d.s3
  local hunt = s.hunt
  note_worm(s)
  if game.tick < hunt.eta_tick + 30 and not hunt.outcome then return "poll" end
  local failed = {}
  check(failed, s.worm_name == LARGE, "Wurm " .. tostring(s.worm_name) .. " (Phase " .. tostring(hunt.phase) .. ", ohne "
    .. tostring(hunt.no_worm) .. ")")
  check(failed, s.ring == 6, "Ring " .. tostring(s.ring))
  check(failed, hunt.outcome == "bitten", "Ergebnis " .. tostring(hunt.outcome))
  check(failed, not valid(s.chest), "Kiste steht noch")
  check(failed, not valid(s.near), "Auto 6 Kacheln daneben steht noch")
  check(failed, valid(s.far), "Auto 9 Kacheln daneben gefressen")
  return verdict(run, tb, 3, "Biss des großen Wurms", failed, string.format(
    "Wurm %s (%s LP), Ring %s, Ergebnis %s, Kiste %s, Auto 6 %s, Auto 9 %s", tostring(s.worm_name), tostring(s.worm_hp),
    tostring(s.ring), tostring(hunt.outcome), valid(s.chest) and "steht" or "weg", valid(s.near) and "steht" or "weg",
    valid(s.far) and "steht" or "weg"))
end

-- 4) Getötet: reguläre Jagd mit echten Revieren; Zähne 6–10, Revier 2 × FREE_TICKS frei.
function t37.s4_build(run, tb, d)
  local s = d.s4
  local surface = tb.surface()
  territory.test_real(surface, SEED)
  territory.test_reset(surface)
  d.territory_real = true
  d.factor = worms_lib.TOOTH_FACTOR
  worms_lib.TOOTH_FACTOR = 1
  s.chest = create(run, tb, {name = CHEST, position = at(d.pos.far, 0, 30), force = t23_force()}, "others")
  if not s.chest then return fail(run, tb, 4, "Kiste ließ sich nicht bauen") end
  local hunt, reason = large_hunt(d, s.chest, false)
  if not hunt then return fail(run, tb, 4, "start_hunt: " .. tostring(reason)) end
  s.hunt = hunt
  s.deadline = hunt.eta_tick - 120
  return 1
end

function t37.s4_kill(run, tb, d)
  local s = d.s4
  local r = wait_for(s, function() return note_worm(s) end, function()
    return fail(run, tb, 4, "kein Wurm erschienen (Phase " .. tostring(s.hunt.phase) .. ", ohne " .. tostring(s.hunt.no_worm) .. ")")
  end)
  if r ~= 1 then return r end
  local unit = s.hunt.worm.unit
  local surface = tb.surface()
  s.revier = s.hunt.revier
  s.si = surface.index
  s.before = storage.hunts.teeth or 0
  s.killed_at = game.tick
  unit.die(t23_force())
  return 1
end

function t37.s4_check(run, tb, d)
  local s = d.s4
  local failed = {}
  local n = (storage.hunts.teeth or 0) - s.before
  local free = (territory.free_until(s.si, s.revier) or 0) - s.killed_at
  local want = territory.FREE_TICKS * worms_lib.LARGE.free_factor
  check(failed, s.worm_name == LARGE, "Wurm " .. tostring(s.worm_name))
  check(failed, n >= 6 and n <= 10, n .. " Zähne")
  check(failed, math.abs(free - want) <= 2, "Revier frei " .. free .. " Ticks statt " .. want)
  check(failed, s.hunt.outcome == "killed", "Ergebnis " .. tostring(s.hunt.outcome))
  for _, item in pairs(tb.surface().find_entities_filtered{type = "item-entity", position = s.chest.valid and s.chest.position
      or at(d.pos.far, 0, 30), radius = 120}) do
    item.destroy()
  end
  return verdict(run, tb, 4, "Großer Wurm getötet", failed, string.format("%d Zähne, Revier frei %s min, Ergebnis %s", n,
    tb.num(free / 3600), tostring(s.hunt.outcome)))
end

local T37_STEPS =
{
  {t37.s1},
  {t37.s2},
  {t37.s3_build, t37.s3_check},
  {t37.s4_build, t37.s4_kill, t37.s4_check}
}

local function restore(d, tb)
  t23_force()
  if d.factor then worms_lib.TOOTH_FACTOR = d.factor end
  if d.territory_real then
    local surface = tb.surface()
    territory.test_reset(surface)
    territory.test_real(surface, nil)
  end
end

local function t37_start(run, tb)
  prepare(run, tb)
  local d = run.data
  for number = 1, #T37_STEPS do d["s" .. number] = {} end
  d.after_step = "sweep"
  tb.watch(run, nil, d.pos.watch)
  tb.log(run, "INFO", "Vier Schritte 0.16.0 (großer Wurm). Dauer etwa zwei Minuten Spielzeit.")
  d.step, d.phase, d.wait_until = 1, 1, game.tick + 30
end

local function t37_tick(run, tb)
  run_steps(run, tb, T37_STEPS)
end

local function t37_cleanup(run, tb)
  local d = run.data
  pcall(tidy, run)
  pcall(sweep, run, tb)
  pcall(restore, d, tb)
end

return
{
  T37 =
  {
    title = "Großer Wurm 0.16.0",
    timeout = 5 * 60 * 60,
    interactive = false,
    confirm = nil,
    start = t37_start,
    tick = t37_tick,
    cleanup = t37_cleanup
  }
}
