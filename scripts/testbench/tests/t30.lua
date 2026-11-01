-- T30 Wurm-Reviere 0.13.0 (docs/plan-3g.md 5): Zuschnitt, Startrevier, Stufenanteile, Schwelle und Countdown je Stufe,
-- Ruhe fürs ganze Revier, freies Revier mit Ankündigung, Revierkunde und Rang für die Leitstelle, Speicher.
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_fleet.lua (T23-Fläche, Force arrakis-t23 ohne Wurm).

local common = require("scripts.testbench.gemeinsam_fleet")
local harvester = require("scripts.harvester")
local worms_lib = require("scripts.worms")
local vibration_lib = require("scripts.vibration")
local territory = require("scripts.territory")
local migrate = require("scripts.migrate")
local T23_FORCE = common.T23_FORCE
local t23_force = common.t23_force
local tidy = common.tidy
local new_harvester = common.new_harvester
local verdict = common.verdict
local fail = common.fail
local check = common.check
local prepare = common.prepare
local run_steps = common.run_steps
local sweep = common.sweep

-- Feste Seeds für die Rechnung (Plan 5: „Testseed“); 4711 auch für die echten Reviere auf der Prüfstand-Fläche.
local SEEDS = {4711, 0, 123456789, 4294967295}
local SEED = 4711
local EARLY = "arrakis-early-warning"

local function surface_index()
  return game.get_surface("arrakis-testbench").index
end

-- Zellen in einem Quadrat von 2·R Sektoren um den Ursprung auf echten Revieren der Fläche (Seed seed).
local function census(seed, R)
  local s = surface_index()
  territory.test_real(s, seed)
  local sizes, order = {}, {}
  for sx = -R, R - 1 do
    for sy = -R, R - 1 do
      local id = territory.of_sector(s, vibration_lib.chunk_key(sx, sy))
      if not sizes[id] then
        sizes[id] = 0
        order[#order + 1] = id
      end
      sizes[id] = sizes[id] + 1
    end
  end
  return s, sizes, order
end

local function early_levels(done)
  local tech = t23_force().technologies[EARLY]
  if not tech then return end
  if done >= tech.prototype.max_level then
    tech.level = tech.prototype.max_level
    tech.researched = true
  else
    tech.researched = false
    tech.level = done + 1
  end
end

local function survey(on)
  local tech = t23_force().technologies[territory.SURVEY_TECH]
  if tech then tech.researched = on end
end

local t30 = {}

-- 1) Zuschnitt: zweimal gerechnet gleich, jeder Sektor gehört genau einem Revier (sectors_of enthält ihn), Größe
-- 2 bis 8 Sektoren für Reviere ganz im Quadrat.
function t30.s1(run, tb, d)
  local failed = {}
  local s, sizes, order = census(SEED, 24)
  local first = {}
  for sx = -24, 23 do
    for sy = -24, 23 do first[sx .. "/" .. sy] = territory.of_sector(s, vibration_lib.chunk_key(sx, sy)) end
  end
  territory.test_real(s, SEED)
  local same, mismatch = 0, 0
  for sx = -24, 23 do
    for sy = -24, 23 do
      if territory.of_sector(s, vibration_lib.chunk_key(sx, sy)) == first[sx .. "/" .. sy] then same = same + 1
      else mismatch = mismatch + 1 end
    end
  end
  check(failed, mismatch == 0, mismatch .. " Sektoren beim zweiten Rechnen anders")
  local mn, mx, inner, notlisted = 99, 0, 0, 0
  for _, id in ipairs(order) do
    local rec = territory.info(s, id)
    if math.abs(rec.gx) <= 9 and math.abs(rec.gy) <= 9 then
      inner = inner + 1
      mn = math.min(mn, sizes[id])
      mx = math.max(mx, sizes[id])
      local listed = 0
      for _, sector in ipairs(territory.sectors_of(s, id)) do
        if territory.of_sector(s, sector) == id then listed = listed + 1 end
      end
      if listed ~= sizes[id] then notlisted = notlisted + 1 end
    end
  end
  check(failed, mn >= 2 and mx <= 8, "Größe " .. mn .. " bis " .. mx .. " statt 2 bis 8 Sektoren")
  check(failed, notlisted == 0, notlisted .. " Reviere: sectors_of passt nicht zur Zählung")
  return verdict(run, tb, 1, "Zuschnitt", failed, string.format("%d Sektoren gleich, %d Reviere innen, %d bis %d Sektoren",
    same, inner, mn, mx))
end

-- 2) Startrevier: Landeplatz und Lehrfeld (140 Kacheln in jeder Richtung) liegen für vier Seeds in ruhigen Revieren.
function t30.s2(run, tb, d)
  local failed = {}
  local s = surface_index()
  local bad = 0
  for _, seed in ipairs(SEEDS) do
    territory.test_real(s, seed)
    if territory.level(s, territory.of_position(s, {x = 0, y = 0})) ~= "calm" then bad = bad + 1 end
    for a = 0, 355, 5 do
      local position = {x = 140 * math.cos(math.rad(a)), y = 140 * math.sin(math.rad(a))}
      if territory.level(s, territory.of_position(s, position)) ~= "calm" then bad = bad + 1 end
    end
  end
  check(failed, bad == 0, bad .. " Stellen nicht ruhig")
  return verdict(run, tb, 2, "Startrevier ruhig", failed, #SEEDS .. " Seeds, je 73 Stellen, nicht ruhig " .. bad)
end

-- 3) Stufenanteile (Plan 3): außerhalb 1100 Kacheln ruhig 5–16 %, wild 33–48 %; 520–1100 ruhig 12–45 %, wild ≤ 30 %.
function t30.s3(run, tb, d)
  local failed = {}
  local s, _, order = census(SEED, 40)
  local near, far = {calm = 0, normal = 0, wild = 0, n = 0}, {calm = 0, normal = 0, wild = 0, n = 0}
  for _, id in ipairs(order) do
    local rec = territory.info(s, id)
    if math.abs(rec.gx) <= 17 and math.abs(rec.gy) <= 17 then
      local dist = math.sqrt(rec.x * rec.x + rec.y * rec.y)
      local bucket = dist >= territory.NEAR_RADIUS and far or (dist >= territory.START_RADIUS and near or nil)
      if bucket then
        bucket[rec.level] = bucket[rec.level] + 1
        bucket.n = bucket.n + 1
      end
    end
  end
  local function share(b, level) return b.n > 0 and b[level] / b.n or 0 end
  check(failed, share(far, "calm") >= 0.05 and share(far, "calm") <= 0.16, "fern ruhig " .. tb.num(100 * share(far, "calm")) .. " %")
  check(failed, share(far, "wild") >= 0.33 and share(far, "wild") <= 0.48, "fern wild " .. tb.num(100 * share(far, "wild")) .. " %")
  check(failed, share(near, "calm") >= 0.12 and share(near, "calm") <= 0.45, "nah ruhig " .. tb.num(100 * share(near, "calm")) .. " %")
  check(failed, share(near, "wild") <= 0.30, "nah wild " .. tb.num(100 * share(near, "wild")) .. " %")
  return verdict(run, tb, 3, "Stufenanteile", failed, string.format(
    "nah %d (ruhig %s %%, wild %s %%), fern %d (ruhig %s %%, normal %s %%, wild %s %%)", near.n,
    tb.num(100 * share(near, "calm")), tb.num(100 * share(near, "wild")), far.n, tb.num(100 * share(far, "calm")),
    tb.num(100 * share(far, "normal")), tb.num(100 * share(far, "wild"))))
end

-- 4) Schwelle und Countdown je Stufe auf der Prüfstand-Fläche (Sektor = Revier, Stufe vorgegeben): Schwelle 1400 / 1000
-- / 700, Countdown einer Jagd 75 / 60 / 50 s, wild mit 6 Stufen Frühwarnung 80 s, ohne Vorgabe normal.
function t30.s4_build(run, tb, d)
  local s = d.s4
  territory.test_real(surface_index(), nil)
  s.car = new_harvester(run, tb, d, d.pos.rescue)
  if not s.car then return fail(run, tb, 4, "Ernter ließ sich nicht bauen") end
  return harvester.DEPLOY_TICKS + 10
end

function t30.s4_check(run, tb, d)
  local s = d.s4
  local failed = {}
  local si = surface_index()
  local key, sector = vibration_lib.key_of(s.car.position)
  local id = territory.of_sector(si, sector)
  check(failed, id == sector and not territory.real(si), "Prüfstand-Fläche nicht Sektor = Revier")
  check(failed, territory.level(si, id) == "normal", "ohne Vorgabe Stufe " .. territory.level(si, id))
  local got = {}
  local function countdown()
    local hunt, reason = worms_lib.start_hunt(s.car, {debug = true})
    if not hunt then
      table.insert(failed, "start_hunt: " .. tostring(reason))
      return -1
    end
    local ticks = hunt.eta_tick - hunt.warn_tick
    worms_lib.end_hunt(hunt, nil, "abort")
    return ticks
  end
  for _, entry in ipairs({{"calm", 1400, 4500}, {"normal", 1000, 3600}, {"wild", 700, 3000}}) do
    territory.test_level(si, id, entry[1])
    local threshold = territory.threshold(si, key)
    local ticks = countdown()
    check(failed, math.abs(threshold - entry[2]) < 1e-6, entry[1] .. ": Schwelle " .. tb.num(threshold))
    check(failed, ticks >= entry[3] and ticks < entry[3] + 10, entry[1] .. ": Countdown " .. ticks .. " Ticks")
    table.insert(got, entry[1] .. " " .. tb.num(threshold) .. "/" .. tb.num(ticks / 60) .. " s")
  end
  early_levels(6)
  local ticks = countdown()
  check(failed, ticks >= 4800 and ticks < 4810, "wild mit Frühwarnung 6: " .. ticks .. " Ticks statt 4800")
  early_levels(0)
  territory.test_reset(si)
  return verdict(run, tb, 4, "Schwelle und Countdown", failed, table.concat(got, ", ") .. ", wild + Frühwarnung "
    .. tb.num(ticks / 60) .. " s")
end

-- 5) Ruhe fürs ganze Revier: echte Reviere (Seed 4711) auf der Fläche, Revier des Ernters ruhig vorgegeben; eine reguläre
-- Jagd endet „escaped“: alle Sektoren des Reviers ruhen gleich lang, 3 bis 6 min (×1,5); ein Sektor eines anderen
-- Reviers ruht nicht; der Wurm lauert im Sektor der Jagd.
function t30.s5_build(run, tb, d)
  local s = d.s5
  s.car = new_harvester(run, tb, d, d.pos.far)
  if not s.car then return fail(run, tb, 5, "Ernter ließ sich nicht bauen") end
  return harvester.DEPLOY_TICKS + 10
end

function t30.s5_check(run, tb, d)
  local s = d.s5
  local failed = {}
  local si = surface_index()
  territory.test_real(si, SEED)
  local _, sector = vibration_lib.key_of(s.car.position)
  local id = territory.of_sector(si, sector)
  territory.test_level(si, id, "calm")
  local sectors = territory.sectors_of(si, id)
  d.rested = sectors
  local hunt, reason = worms_lib.start_hunt(s.car, {})
  if not hunt then return fail(run, tb, 5, "start_hunt: " .. tostring(reason)) end
  check(failed, hunt.revier == id, "Jagd ohne Revier")
  local tick = game.tick
  worms_lib.end_hunt(hunt, "escaped")
  local lo, hi, missing = math.huge, 0, 0
  for _, sec in ipairs(sectors) do
    local until_tick = vibration_lib.resting(si, sec)
    if until_tick then
      lo = math.min(lo, until_tick - tick)
      hi = math.max(hi, until_tick - tick)
    else
      missing = missing + 1
    end
  end
  check(failed, missing == 0, missing .. " Sektoren des Reviers ruhen nicht")
  check(failed, lo == hi, "Ruhe ungleich " .. lo .. " bis " .. hi)
  check(failed, hi >= 1.5 * worms_lib.REST_MIN and hi <= 1.5 * worms_lib.REST_MAX, "Ruhe " .. hi .. " Ticks statt 10800–21600")
  local sx, sy = vibration_lib.chunk_of_key(sector)
  local other
  for dx = -6, 6 do
    if not other then
      local cand = vibration_lib.chunk_key(sx + dx, sy)
      if territory.of_sector(si, cand) ~= id then other = cand end
    end
  end
  check(failed, other ~= nil and not vibration_lib.resting(si, other), "Sektor eines anderen Reviers ruht")
  check(failed, worms_lib.lurking(si, sector) ~= nil, "Wurm lauert nicht")
  return verdict(run, tb, 5, "Ruhe fürs Revier", failed, string.format("%d Sektoren, Ruhe %s min, lauert %s", #sectors,
    tb.num(hi / 3600), tostring(worms_lib.lurking(si, sector) ~= nil)))
end

-- 6) Freies Revier (Plan 1.3 b, im Test 15 s statt 60 min): frei und Rang 2 bei wild, Ankündigung im Takt, danach
-- wieder belegt; set_free ohne Dauer gibt 60 min.
function t30.s6_start(run, tb, d)
  local s = d.s6
  local si = surface_index()
  territory.test_real(si, SEED)
  local _, sector = vibration_lib.key_of(d.pos.rescue)
  s.revier = territory.of_sector(si, sector)
  territory.test_level(si, s.revier, "wild")
  s.rank_before = territory.rank(si, s.revier)
  territory.set_free(si, s.revier)
  s.full = (territory.free_until(si, s.revier) or 0) - game.tick
  territory.set_free(si, s.revier, 15 * 60)
  s.free = territory.free_until(si, s.revier) ~= nil
  s.rank_free = territory.rank(si, s.revier)
  return 2 * 60
end

function t30.s6_mid(run, tb, d)
  local s = d.s6
  local t = storage.territory
  s.announced = t.announced[surface_index()] ~= nil and t.announced[surface_index()][s.revier] == true
  return 15 * 60
end

function t30.s6_check(run, tb, d)
  local s = d.s6
  local failed = {}
  local si = surface_index()
  check(failed, s.full == territory.FREE_TICKS, "Standarddauer " .. tostring(s.full) .. " statt " .. territory.FREE_TICKS)
  check(failed, s.free, "nicht frei")
  check(failed, s.rank_before == 3 and s.rank_free == 2, "Rang wild " .. s.rank_before .. ", frei " .. s.rank_free)
  check(failed, s.announced, "keine Ankündigung")
  check(failed, territory.free_until(si, s.revier) == nil, "nach Ablauf noch frei")
  territory.test_reset(si)
  return verdict(run, tb, 6, "Freies Revier", failed, string.format("Standard %s min, Rang %d → %d, Ankündigung %s",
    tb.num(s.full / 3600), s.rank_before, s.rank_free, tostring(s.announced)))
end

-- 7) Revierkunde: Forschung hinter der Leitstelle; known nur nach der Forschung; Rang ruhig 1, normal 2, wild 3.
function t30.s7(run, tb, d)
  local failed = {}
  local proto = prototypes.technology[territory.SURVEY_TECH]
  check(failed, proto ~= nil and proto.prerequisites["arrakis-ornithopter-depot"] ~= nil, "Revierkunde fehlt oder Voraussetzung falsch")
  survey(false)
  local before = territory.known(t23_force())
  survey(true)
  local after = territory.known(t23_force())
  survey(false)
  check(failed, not before and after, "known vorher " .. tostring(before) .. ", nachher " .. tostring(after))
  local si = surface_index()
  territory.test_real(si, nil)
  local _, sector = vibration_lib.key_of(d.pos.rescue)
  local ranks = {}
  for _, level in ipairs({"calm", "normal", "wild"}) do
    territory.test_level(si, sector, level)
    table.insert(ranks, territory.rank(si, sector))
  end
  territory.test_reset(si)
  check(failed, ranks[1] == 1 and ranks[2] == 2 and ranks[3] == 3, "Ränge " .. table.concat(ranks, "/"))
  return verdict(run, tb, 7, "Revierkunde", failed, "known " .. tostring(before) .. " → " .. tostring(after)
    .. ", Ränge " .. table.concat(ranks, "/"))
end

-- 8) Speicher: Schema 7, storage.territory mit allen Untertabellen.
function t30.s8(run, tb, d)
  local failed = {}
  local t = storage.territory
  check(failed, migrate.SCHEMA == 7 and storage.schema == 7, "Schema " .. tostring(storage.schema))
  for _, name in ipairs({"seed", "cache", "info", "free", "announced", "real", "levels"}) do
    check(failed, t and type(t[name]) == "table", "storage.territory." .. name .. " fehlt")
  end
  return verdict(run, tb, 8, "Speicher", failed, "Schema " .. tostring(storage.schema))
end

local T30_STEPS =
{
  {t30.s1},
  {t30.s2},
  {t30.s3},
  {t30.s4_build, t30.s4_check},
  {t30.s5_build, t30.s5_check},
  {t30.s6_start, t30.s6_mid, t30.s6_check},
  {t30.s7},
  {t30.s8}
}

local function reset_surface()
  local si = surface_index()
  territory.test_real(si, nil)
  territory.test_reset(si)
end

local function t30_start(run, tb)
  prepare(run, tb)
  local d = run.data
  d.run_id = run.id
  for number = 1, #T30_STEPS do d["s" .. number] = {} end
  d.after_step = "sweep"
  reset_surface()
  early_levels(0)
  survey(false)
  tb.watch(run, nil, d.pos.watch)
  tb.log(run, "INFO", "Acht Schritte 0.13.0 (Wurm-Reviere) mit dem echten Code, Force " .. T23_FORCE
    .. " ohne Wurm. Dauer etwa 30 s Spielzeit.")
  d.step, d.phase, d.wait_until = 1, 1, game.tick + 30
end

local function t30_tick(run, tb)
  run_steps(run, tb, T30_STEPS)
end

local function t30_cleanup(run, tb)
  pcall(tidy, run)
  pcall(sweep, run, tb)
  pcall(reset_surface)
  pcall(early_levels, 0)
  pcall(survey, false)
  pcall(function()
    local si = surface_index()
    local cool = storage.sector_cooldown[si]
    for _, sector in ipairs(run.data.rested or {}) do
      if cool then cool[sector] = nil end
    end
    worms_lib.clear_lurk(si)
  end)
  storage.fleet_pause_until = nil
end

return
{
  T30 =
  {
    title = "Wurm-Reviere 0.13.0",
    timeout = 10 * 60 * 60,
    interactive = false,
    confirm = nil,
    start = t30_start,
    tick = t30_tick,
    cleanup = t30_cleanup
  }
}
