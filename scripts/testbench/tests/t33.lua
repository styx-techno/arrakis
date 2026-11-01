-- T33 Beute und Einstellungen 0.14.0 (docs/plan-3h.md 2.2, 2.3, 4): Standardwerte der Einstellungen = Konstanten bis
-- 0.13.0, geänderte Einstellungen landen in den Konstanten (und zurück), Wurmzähne beim Tod eines Sandwurms (2–4, Faktor
-- 0 und 2). Gemeinsame Helfer: scripts/testbench/gemeinsam_fleet.lua (T23-Fläche).

local common = require("scripts.testbench.gemeinsam_fleet")
local worms_lib = require("scripts.worms")
local vibration_lib = require("scripts.vibration")
local territory = require("scripts.territory")
local thumper_lib = require("scripts.thumper")
local sandworm_lib = require("scripts.sandworm")
local config = require("scripts.config")
local tidy = common.tidy
local verdict = common.verdict
local fail = common.fail
local check = common.check
local prepare = common.prepare
local run_steps = common.run_steps
local sweep = common.sweep
local at = common.at

-- Name, Standard, Testwert.
local SETTINGS =
{
  {"arrakis-worms-enabled", true, false},
  {"arrakis-warn-seconds", 60, 90},
  {"arrakis-wormsign-threshold", 1000, 2000},
  {"arrakis-vibration-percent", 100, 200},
  {"arrakis-rest-percent", 100, 50},
  {"arrakis-max-hunts", 3, 5},
  {"arrakis-free-minutes", 60, 0},
  {"arrakis-thumper-seconds", 60, 30},
  {"arrakis-tooth-percent", 100, 0}
}

-- Konstanten nach config.apply für Standard (1) bzw. Testwerte (2).
local function constants()
  return
  {
    ENABLED = worms_lib.ENABLED,
    WARN_TICKS = worms_lib.WARN_TICKS,
    WORMSIGN = vibration_lib.WORMSIGN,
    UNREST = vibration_lib.UNREST,
    CAREFUL_LOW = vibration_lib.CAREFUL_LOW,
    SCALE = vibration_lib.SCALE,
    REST_MIN = worms_lib.REST_MIN,
    REST_MAX = worms_lib.REST_MAX,
    MAX_HUNTS = worms_lib.MAX_HUNTS,
    FREE_TICKS = territory.FREE_TICKS,
    TICKS = thumper_lib.TICKS,
    TOOTH_FACTOR = worms_lib.TOOTH_FACTOR
  }
end

local EXPECTED =
{
  {ENABLED = true, WARN_TICKS = 3600, WORMSIGN = 1000, UNREST = 600, CAREFUL_LOW = 300, SCALE = 1, REST_MIN = 7200,
   REST_MAX = 14400, MAX_HUNTS = 3, FREE_TICKS = 216000, TICKS = 3600, TOOTH_FACTOR = 1},
  {ENABLED = false, WARN_TICKS = 5400, WORMSIGN = 2000, UNREST = 1200, CAREFUL_LOW = 600, SCALE = 2, REST_MIN = 3600,
   REST_MAX = 7200, MAX_HUNTS = 5, FREE_TICKS = 0, TICKS = 1800, TOOTH_FACTOR = 0}
}

local function compare(failed, label, want)
  local got = constants()
  local wrong = {}
  for name, value in pairs(want) do
    local v = got[name]
    if type(value) == "number" then
      if type(v) ~= "number" or math.abs(v - value) > 1e-9 then wrong[#wrong + 1] = name .. "=" .. tostring(v) end
    elseif v ~= value then
      wrong[#wrong + 1] = name .. "=" .. tostring(v)
    end
  end
  table.sort(wrong)
  check(failed, #wrong == 0, label .. ": " .. table.concat(wrong, ", "))
  return #wrong
end

local function write_settings(index)
  for _, entry in ipairs(SETTINGS) do
    settings.global[entry[1]] = {value = entry[index]}
  end
end

local t33 = {}

-- 1) Standardwerte: Einstellungen stehen auf Standard, die Konstanten sind die von 0.13.0.
function t33.s1(run, tb, d)
  local failed = {}
  local off = {}
  for _, entry in ipairs(SETTINGS) do
    if settings.global[entry[1]].value ~= entry[2] then off[#off + 1] = entry[1] end
  end
  check(failed, #off == 0, "nicht auf Standard: " .. table.concat(off, ", "))
  config.apply()
  local wrong = compare(failed, "Konstanten", EXPECTED[1])
  return verdict(run, tb, 1, "Standardwerte", failed, #SETTINGS .. " Einstellungen, " .. wrong .. " Konstanten abweichend")
end

-- 2) Einstellungen wirken: Testwerte schreiben (das Ereignis on_runtime_mod_setting_changed übernimmt sie), prüfen,
-- zurück auf Standard.
function t33.s2_write(run, tb, d)
  d.changed = true
  write_settings(3)
  return 2
end

function t33.s2_check(run, tb, d)
  local s = d.s2
  local failed = {}
  s.event = math.abs(worms_lib.WARN_TICKS - 5400) < 1e-9
  if not s.event then
    tb.log(run, "INFO", "2) Ereignis on_runtime_mod_setting_changed kam nicht; config.apply von Hand")
    config.apply()
  end
  local wrong = compare(failed, "Testwerte", EXPECTED[2])
  write_settings(2)
  config.apply()
  d.changed = nil
  local back = compare(failed, "zurück", EXPECTED[1])
  return verdict(run, tb, 2, "Einstellungen wirken", failed, string.format("Ereignis %s, abweichend %d, nach Rücksetzen %d",
    tostring(s.event), wrong, back))
end

-- 3) Beute: je ein Sandwurm stirbt mit TOOTH_FACTOR 1, 0 und 2; Zähne am Boden und im Zähler.
local TOOTH = worms_lib.TOOTH

local function teeth_near(surface, position)
  local n = 0
  for _, item in pairs(surface.find_entities_filtered{type = "item-entity", position = position, radius = 12}) do
    local stack = item.stack
    if stack and stack.valid_for_read and stack.name == TOOTH then n = n + stack.count end
  end
  return n
end

local function clear_teeth(surface, position)
  for _, item in pairs(surface.find_entities_filtered{type = "item-entity", position = position, radius = 12}) do
    item.destroy()
  end
end

function t33.s3(run, tb, d)
  local s = d.s3
  local failed = {}
  local surface = tb.surface()
  local worm_force = worms_lib.ensure_force()
  local results = {}
  d.factor = worms_lib.TOOTH_FACTOR
  for i, factor in ipairs({1, 0, 2}) do
    worms_lib.TOOTH_FACTOR = factor
    local position = at(d.pos.rescue, -40 + 40 * i, 0)
    local ok, unit = pcall(function()
      return surface.create_segmented_unit{name = sandworm_lib.NAME, position = position, direction = defines.direction.west,
        extended = true, force = worm_force}
    end)
    if not (ok and unit) then
      worms_lib.TOOTH_FACTOR = d.factor
      return fail(run, tb, 3, "Sandwurm ließ sich nicht erzeugen: " .. tostring(unit))
    end
    local head = unit.get_body_nodes()[1]
    local before = storage.hunts.teeth or 0
    unit.die()
    local counted = (storage.hunts.teeth or 0) - before
    local ground = teeth_near(surface, head)
    clear_teeth(surface, head)
    results[i] = factor .. "×: " .. ground .. " am Boden, Zähler " .. counted
    check(failed, ground == counted, "Faktor " .. factor .. ": Boden " .. ground .. " ≠ Zähler " .. counted)
    local lo, hi = math.floor(worms_lib.TOOTH_MIN * factor + 0.5), math.floor(worms_lib.TOOTH_MAX * factor + 0.5)
    check(failed, counted >= lo and counted <= hi, "Faktor " .. factor .. ": " .. counted .. " Zähne statt " .. lo .. "–" .. hi)
  end
  worms_lib.TOOTH_FACTOR = d.factor
  return verdict(run, tb, 3, "Beute", failed, table.concat(results, "; "))
end

local T33_STEPS =
{
  {t33.s1},
  {t33.s2_write, t33.s2_check},
  {t33.s3}
}

local function t33_start(run, tb)
  prepare(run, tb)
  local d = run.data
  for number = 1, #T33_STEPS do d["s" .. number] = {} end
  d.after_step = "sweep"
  tb.watch(run, nil, d.pos.watch)
  tb.log(run, "INFO", "Drei Schritte 0.14.0 (Einstellungen, Beute). Dauer wenige Sekunden Spielzeit.")
  d.step, d.phase, d.wait_until = 1, 1, game.tick + 30
end

local function t33_tick(run, tb)
  run_steps(run, tb, T33_STEPS)
end

local function t33_cleanup(run, tb)
  local d = run.data
  pcall(tidy, run)
  pcall(sweep, run, tb)
  if d.changed then pcall(write_settings, 2) end
  pcall(config.apply)
  if d.factor then worms_lib.TOOTH_FACTOR = d.factor end
end

return
{
  T33 =
  {
    title = "Beute und Einstellungen 0.14.0",
    timeout = 5 * 60 * 60,
    interactive = false,
    confirm = nil,
    start = t33_start,
    tick = t33_tick,
    cleanup = t33_cleanup
  }
}
