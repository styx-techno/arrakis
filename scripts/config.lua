-- Mod-Einstellungen (Phase 3h, docs/plan-3h.md 2.3): überträgt die runtime-global-Einstellungen in die Konstanten der
-- Module. Läuft bei on_init, on_load, on_configuration_changed und on_runtime_mod_setting_changed. Das schreibt nur
-- Modultabellen, nichts in storage; alle Teilnehmer haben dieselben Einstellungen, also bleibt es deterministisch.
-- Standardwerte = Verhalten bis 0.13.0. Der Prüfstand setzt Konstanten selbst und stellt sie wieder her; eine geänderte
-- Einstellung während eines Prüfstand-Laufs überschreibt sie.

local worms_lib = require("scripts.worms")
local vibration_lib = require("scripts.vibration")
local territory_lib = require("scripts.territory")
local thumper_lib = require("scripts.thumper")

local lib = {}

-- Grundwerte, auf die sich die Prozent-Einstellungen beziehen.
lib.BASE =
{
  rest_min = 7200,
  rest_max = 14400,
  unrest_share = 0.6,
  careful_share = 0.3
}

local function value(name, default)
  local setting = settings.global[name]
  if setting == nil then return default end
  return setting.value
end

function lib.apply()
  worms_lib.ENABLED = value("arrakis-worms-enabled", true) == true
  worms_lib.WARN_TICKS = value("arrakis-warn-seconds", 60) * 60
  local threshold = value("arrakis-wormsign-threshold", 1000)
  vibration_lib.WORMSIGN = threshold
  vibration_lib.UNREST = threshold * lib.BASE.unrest_share
  vibration_lib.CAREFUL_LOW = threshold * lib.BASE.careful_share
  vibration_lib.SCALE = value("arrakis-vibration-percent", 100) / 100
  local rest = value("arrakis-rest-percent", 100) / 100
  worms_lib.REST_MIN = math.floor(lib.BASE.rest_min * rest + 0.5)
  worms_lib.REST_MAX = math.floor(lib.BASE.rest_max * rest + 0.5)
  worms_lib.MAX_HUNTS = value("arrakis-max-hunts", 3)
  territory_lib.FREE_TICKS = value("arrakis-free-minutes", 60) * 3600
  thumper_lib.TICKS = value("arrakis-thumper-seconds", 60) * 60
  worms_lib.TOOTH_FACTOR = value("arrakis-tooth-percent", 100) / 100
end

local function on_setting_changed(event)
  if event.setting_type == "runtime-global" and event.setting:sub(1, 8) == "arrakis-" then lib.apply() end
end

lib.events =
{
  [defines.events.on_runtime_mod_setting_changed] = on_setting_changed
}

lib.on_init = lib.apply
lib.on_load = lib.apply
lib.on_configuration_changed = lib.apply

return lib
