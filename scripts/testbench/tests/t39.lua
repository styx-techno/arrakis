-- T39 Wurm unter Beschuss 0.16.2 (Max im Spiel, T34 Schritte 3 und 4): Unter Beschuss bog der Wurm zu den Geschützen
-- an den Fels ab, blieb dort hängen und tauchte ab (sah aus wie Sterben, aber ohne Zähne), und bei 0 biss die Jagd doch
-- noch zu. Seit 0.16.2 setzt scripts/sandworm.lua wütende KI-Zustände (sandworm.ENRAGED) sofort auf investigating zurück
-- (Schadensereignis und Fahrtakt), und im Angriff drückt er nicht mehr gegen Fels hinter dem Ziel.
-- Aufbau: lange Felsleiste 6 Kacheln südlich der Fahrspur mit 45 Geschützen (Uranmunition) am Nordrand, Kiste östlich
-- ihres Endes, Befehlsjagd 40 s mit Spawnhaken 100 Kacheln westlich. Der Wurm fährt fast 100 Kacheln an der Reihe entlang
-- im Feuer. Erwartet: Er bleibt auf der Spur (biegt nicht zum Fels ab, nie wütend), taucht vor dem Biss nicht ab und nimmt
-- Schaden; stirbt er vor 0 (killed), 2 bis 4 Wurmzähne. Lauf a13f88e: 45 Geschütze schafften nur etwa 500 LP/s gegen
-- 30 000 LP (Panzerung, Heilung), der Wurm biss; ein Tod ist deshalb keine Bedingung. Lauf 79fb227 (alter Aufbau, Kiste vor einer kurzen Insel): Der Wurm kam pünktlich zum Biss erst
-- 1,5 s vorher in Reichweite und blieb ohne Schaden; enraged_at_target trat dort ohne Beschuss am Ziel auf (Engine-Angriff),
-- die Zustände stehen deshalb nur als Messung da.
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
local HOOK_DX = -100
-- Felsleiste relativ zu d.pos.far (Kiste bei 0, 0): x −96 bis −4, y 6 bis 15; Geschütze bei y 8, alle 2 Kacheln.
local STRIP = {x1 = -96, y1 = 6, x2 = -4, y2 = 15}
local TURRET_Y = 8
local TURRETS = 45
-- Weiter als so viele Kacheln von der Spur (y der Kiste) Richtung Fels gilt als abgebogen.
local SWERVE = 3

local STATE_NAMES = {}
for name, value in pairs(defines.segmented_unit_ai_state) do STATE_NAMES[value] = name end

local t39 = {}

function t39.s1_build(run, tb, d)
  local s = d.s1
  local force = t23_force()
  local base = d.pos.far
  local bx, by = math.floor(base.x), math.floor(base.y)
  tb.fill({{bx + STRIP.x1, by + STRIP.y1}, {bx + STRIP.x2 + 1, by + STRIP.y2 + 1}}, ROCK)
  s.lane_y = by + 0.5
  s.box = {{bx + STRIP.x1 - 2, by - 20}, {bx + 10, by + STRIP.y2 + 2}}
  s.turrets = 0
  for i = 0, TURRETS - 1 do
    local turret = create(run, tb, {name = "gun-turret", position = {x = bx + STRIP.x1 + 2 + 2 * i, y = by + TURRET_Y}, force = force},
      "others")
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
  s.teeth_before = storage.hunts.teeth or 0
  s.factor = worms_lib.TOOTH_FACTOR
  worms_lib.TOOTH_FACTOR = 1
  s.samples, s.angry, s.max_swerve = 0, 0, 0
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
    s.hp_max = s.hp_max or unit.max_health
    local ok, state = pcall(unit.get_ai_state)
    if ok and state then
      s.samples = s.samples + 1
      if sandworm_lib.ENRAGED[state.type] then s.angry = s.angry + 1 end
      local name = STATE_NAMES[state.type] or tostring(state.type)
      s.states = s.states or {}
      s.states[name] = (s.states[name] or 0) + 1
    end
    local head = sandworm_lib.head_of(hunt)
    -- Abbiegen zum Fels: Kopf südlich der Spur, solange er über der Leiste ist.
    if head and head.x < s.box[2][1] - 12 then
      local swerve = head.y - s.lane_y
      if swerve > s.max_swerve then s.max_swerve = swerve end
    end
    if game.tick % 120 == 0 then
      local aiming = 0
      for _, turret in pairs(tb.surface().find_entities_filtered{name = "gun-turret", area = s.box}) do
        if turret.shooting_target then aiming = aiming + 1 end
      end
      tb.log(run, "MESSUNG", string.format("Wurm: Phase %s, Lebenspunkte %s, Kopf bei %s, Geschütze mit Ziel %d", tostring(hunt.phase),
        tb.num(unit.health, 0), head and string.format("x %+.1f / y %+.1f", head.x - s.chest.position.x, head.y - s.lane_y) or "–", aiming))
    end
  end
  -- Abtauchen vor dem Ergebnis (nach dem Biss taucht er planmäßig ab, Grund „ende“).
  if hunt.dive and not s.dive and not hunt.outcome then s.dive = hunt.dive end
  if s.hp and (not s.hp_min or s.hp < s.hp_min) then s.hp_min = s.hp end
  if not s.killed_tick and hunt.outcome == "killed" then s.killed_tick = game.tick end
  if game.tick < hunt.eta_tick + 30 and not hunt.outcome then return "poll" end
  if s.killed_tick and game.tick < s.killed_tick + 30 then return "poll" end
  local failed = {}
  local calmed = (storage.hunts.calmed or 0) - s.calmed_before
  local teeth = (storage.hunts.teeth or 0) - s.teeth_before
  worms_lib.TOOTH_FACTOR = s.factor
  check(failed, s.seen == true, "kein Wurm erschienen (Phase " .. tostring(hunt.phase) .. ", ohne " .. tostring(hunt.no_worm) .. ")")
  local damage = s.hp_min and (s.hp_max - s.hp_min) or 0
  check(failed, hunt.outcome == "killed" or hunt.outcome == "bitten", "Ergebnis " .. tostring(hunt.outcome))
  check(failed, s.dive == nil, "vor dem Ergebnis abgetaucht: " .. tostring(s.dive))
  check(failed, s.angry <= 3, "wütend in " .. s.angry .. " von " .. s.samples .. " Takten")
  check(failed, s.max_swerve <= SWERVE, "zum Fels abgebogen: Kopf " .. tb.num(s.max_swerve) .. " Kacheln südlich der Spur")
  check(failed, damage >= 1000, "Geschütze trafen kaum: " .. tb.num(damage, 0) .. " Schaden")
  if hunt.outcome == "killed" then check(failed, teeth >= 2 and teeth <= 4, teeth .. " Wurmzähne") end
  local states = {}
  for name, n in pairs(s.states or {}) do states[#states + 1] = name .. " " .. n end
  table.sort(states)
  tb.log(run, "MESSUNG", "KI-Zustände (Takte): " .. table.concat(states, ", ") .. "; beruhigt " .. calmed .. " mal")
  for _, item in pairs(tb.surface().find_entities_filtered{type = "item-entity", area = s.box}) do item.destroy() end
  return verdict(run, tb, 1, "Wurm unter Beschuss", failed, string.format(
    "Ergebnis %s, vorher abgetaucht %s, Schaden %s (zuletzt %s LP), %d Zähne, Kopf höchstens %s Kacheln Richtung Fels, wütend %d von %d Takten, beruhigt %d mal",
    tostring(hunt.outcome), tostring(s.dive), tb.num(damage, 0), tb.num(s.hp or 0, 0), teeth, tb.num(s.max_swerve), s.angry, s.samples, calmed))
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
  tb.watch(run, nil, at(d.pos.far, -40, 0))
  tb.log(run, "INFO", "Ein Schritt 0.16.2 (Wurm unter Beschuss entlang einer Geschützreihe). Dauer etwa eine Minute Spielzeit.")
  d.step, d.phase, d.wait_until = 1, 1, game.tick + 30
end

local function t39_tick(run, tb)
  run_steps(run, tb, T39_STEPS)
end

local function t39_cleanup(run, tb)
  local s = run.data.s1
  if s and s.factor then worms_lib.TOOTH_FACTOR = s.factor end
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
