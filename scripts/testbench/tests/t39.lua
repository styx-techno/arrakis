-- T39 Wurm unter Beschuss 0.16.2 (Max im Spiel, T34 Schritte 3 und 4): Beschuss machte den Wurm wütend
-- (enraged_at_target), die Engine lenkte ihn zum Schützen an den Fels, dort blieb er hängen und tauchte als festgefahren
-- ab (sah aus wie Sterben, aber ohne Zähne), und bei 0 biss die Jagd ohne Wurm doch noch zu. Seit 0.16.2 setzt
-- scripts/sandworm.lua jeden Zustand außer investigating sofort zurück (Schadensereignis und Fahrtakt).
-- Aufbau: Felsinsel mit 20 Geschützen (Uranmunition), Kiste 6 Kacheln davor auf Sand, Befehlsjagd 40 s mit Spawnhaken
-- 90 Kacheln westlich; der Wurm wartet gut 10 s vor der Kiste im Feuer. Erwartet: Wurm erscheint, taucht nicht ab,
-- Ergebnis killed (oder bitten, falls die Geschütze nicht reichen). Die Kiste steht wie der Thumper in T34 6 Kacheln vor
-- dem Fels: Der Angriffspunkt hinter ihr (BEHIND_MIN) läge im Fels; seit 0.16.2 nimmt der Wurm den weitesten freien Punkt
-- davor, statt gegen den Fels zu drücken und als festgefahren abzutauchen. Abstand Kopf–Fels nur als Messung.
-- Gemeinsame Helfer: scripts/testbench/gemeinsam_fleet.lua (T23-Fläche, Force arrakis-t23).

local common = require("scripts.testbench.gemeinsam_fleet")
local worms_lib = require("scripts.worms")
local sandworm_lib = require("scripts.sandworm")
local valid = common.valid
local at = common.at
local t23_force = common.t23_force
local create = common.create
local tidy = common.tidy
local verdict = common.verdict
local fail = common.fail
local check = common.check
local prepare = common.prepare
local run_steps = common.run_steps
local sweep = common.sweep

local ROCK = "arrakis-rock"
local CHEST = "steel-chest"
local SECONDS = 40
local HOOK_DX = -90
-- Felsinsel relativ zu d.pos.far: x 6 bis 25, y −15 bis 14; Kiste bei x 0.
local ISLAND = {x1 = 6, y1 = -15, x2 = 25, y2 = 14}
local TURRETS = 20

local STATE_NAMES = {}
for name, value in pairs(defines.segmented_unit_ai_state) do STATE_NAMES[value] = name end

local t39 = {}

function t39.s1_build(run, tb, d)
  local s = d.s1
  local force = t23_force()
  local base = d.pos.far
  local bx, by = math.floor(base.x), math.floor(base.y)
  tb.fill({{bx + ISLAND.x1, by + ISLAND.y1}, {bx + ISLAND.x2 + 1, by + ISLAND.y2 + 1}}, ROCK)
  s.rock_x = bx + ISLAND.x1
  s.box = {{bx - 10, by - 30}, {bx + ISLAND.x2 + 2, by + 30}}
  s.turrets = 0
  for i = 0, TURRETS - 1 do
    local column, row = math.floor(i / 10), i % 10
    local turret = create(run, tb, {name = "gun-turret", position = {x = bx + ISLAND.x1 + 2 + 2 * column, y = by - 9 + 2 * row},
      force = force}, "others")
    if turret then
      turret.insert{name = "uranium-rounds-magazine", count = 50}
      s.turrets = s.turrets + 1
    end
  end
  s.chest = create(run, tb, {name = CHEST, position = at(base, 0.5, 0.5), force = force}, "others")
  if not s.chest or s.turrets < TURRETS then return fail(run, tb, 1, "Aufbau ging nicht (" .. s.turrets .. " Geschütze)") end
  worms_lib.set_worm_off(force, false)
  local p = s.chest.position
  local hunt, reason = worms_lib.start_hunt(s.chest, {seconds = SECONDS, debug = true, bite = "total-loss",
    spawn = {position = {x = p.x + HOOK_DX, y = p.y}, direction = defines.direction.east}})
  t23_force()
  if not hunt then return fail(run, tb, 1, "start_hunt: " .. tostring(reason)) end
  s.hunt = hunt
  s.calmed_before = storage.hunts.calmed or 0
  s.samples, s.angry, s.min_gap = 0, 0, nil
  return 1
end

function t39.s1_watch(run, tb, d)
  local s = d.s1
  local hunt = s.hunt
  local worm = hunt.worm
  local unit = worm and worm.unit
  if valid(unit) then
    s.seen = true
    s.hp = unit.health
    local ok, state = pcall(unit.get_ai_state)
    if ok and state then
      s.samples = s.samples + 1
      if sandworm_lib.ENRAGED[state.type] then s.angry = s.angry + 1 end
      local name = STATE_NAMES[state.type] or tostring(state.type)
      s.states = s.states or {}
      s.states[name] = (s.states[name] or 0) + 1
    end
    local head = sandworm_lib.head_of(hunt)
    if head then
      local gap = s.rock_x - head.x
      if not s.min_gap or gap < s.min_gap then s.min_gap = gap end
    end
    -- Alle 2 s: Lebenspunkte, Aktivität, Abstand zum Fels, wie viele Geschütze ein Ziel haben.
    if game.tick % 120 == 0 then
      local aiming = 0
      for _, turret in pairs(tb.surface().find_entities_filtered{name = "gun-turret", area = s.box}) do
        if turret.shooting_target then aiming = aiming + 1 end
      end
      tb.log(run, "MESSUNG", string.format("Wurm: Phase %s, Lebenspunkte %s, Aktivität %s, Kopf %s Kacheln vor dem Fels, Geschütze mit Ziel %d",
        tostring(hunt.phase), tb.num(unit.health, 0), tostring(unit.activity_mode), head and tb.num(s.rock_x - head.x) or "–", aiming))
    end
  end
  if hunt.dive and not s.dive then s.dive = hunt.dive end
  if game.tick < hunt.eta_tick + 30 and not hunt.outcome then return "poll" end
  local failed = {}
  local calmed = (storage.hunts.calmed or 0) - s.calmed_before
  check(failed, s.seen == true, "kein Wurm erschienen (Phase " .. tostring(hunt.phase) .. ", ohne " .. tostring(hunt.no_worm) .. ")")
  check(failed, hunt.outcome == "killed" or hunt.outcome == "bitten", "Ergebnis " .. tostring(hunt.outcome))
  check(failed, s.dive == nil or hunt.outcome == "bitten", "abgetaucht: " .. tostring(s.dive))
  check(failed, s.angry <= 3, "wütend in " .. s.angry .. " von " .. s.samples .. " Takten")
  if hunt.outcome == "bitten" then
    tb.log(run, "INFO", "Die Geschütze schafften den Wurm vor 0 nicht (Lebenspunkte zuletzt " .. tb.num(s.hp or 0, 0) .. ")")
  end
  for _, item in pairs(tb.surface().find_entities_filtered{type = "item-entity", position = at(d.pos.far, 0, 0), radius = 60}) do
    item.destroy()
  end
  local states = {}
  for name, n in pairs(s.states or {}) do states[#states + 1] = name .. " " .. n end
  table.sort(states)
  tb.log(run, "MESSUNG", "KI-Zustände (Takte): " .. table.concat(states, ", "))
  return verdict(run, tb, 1, "Wurm unter Beschuss", failed, string.format(
    "Ergebnis %s, abgetaucht %s, wütend %d von %d Takten, beruhigt %d mal, Kopf bis %s Kacheln an den Fels, Lebenspunkte zuletzt %s",
    tostring(hunt.outcome), tostring(s.dive), s.angry, s.samples, calmed, s.min_gap and tb.num(s.min_gap) or "–",
    tb.num(s.hp or 0, 0)))
end

local T39_STEPS =
{
  {t39.s1_build, t39.s1_watch}
}

local function t39_start(run, tb)
  prepare(run, tb)
  local d = run.data
  for number = 1, #T39_STEPS do d["s" .. number] = {} end
  d.after_step = "sweep"
  tb.watch(run, nil, at(d.pos.far, 0, 0))
  tb.log(run, "INFO", "Ein Schritt 0.16.2 (Wurm unter Beschuss vor einer Felsinsel). Dauer etwa eine Minute Spielzeit.")
  d.step, d.phase, d.wait_until = 1, 1, game.tick + 30
end

local function t39_tick(run, tb)
  run_steps(run, tb, T39_STEPS)
end

local function t39_cleanup(run, tb)
  pcall(tidy, run)
  pcall(sweep, run, tb)
  pcall(t23_force)
end

return
{
  T39 =
  {
    title = "Wurm unter Beschuss 0.16.2",
    timeout = 3 * 60 * 60,
    interactive = false,
    confirm = nil,
    start = t39_start,
    tick = t39_tick,
    cleanup = t39_cleanup
  }
}
