-- Thumper (Phase 3h, docs/plan-3h.md 2.1): anmelden, Ablenkung beim Bauen, Ablauf und Forschung „Thumper“.
-- Bibliothek für __core__/lualib/event_handler; die Modultabelle heißt lib, andere Dateien binden sie als thumper_lib.
--
-- storage.thumpers[un] = {un, entity, surface, force_index, until_tick, sand, weight, key, diverted}
--   weight und key setzt scripts/vibration.lua in jedem Vibrationstakt (THUMPER_WEIGHT auf Sand, sonst 0); den Köder
--   (Wurmzeichen auf den Thumper) wählt scripts/worms.lua über sources_by_chunk wie jede andere Quelle.
-- Ein Thumper läuft TICKS lang. Gilt ihm dann noch eine Jagd, läuft er weiter, bis sie endet (meist mit dem Biss, der
-- ihn frisst); sonst zerfällt er mit Sandstaub.
-- Forschung „Thumper“ (Trigger scripted): erforscht, sobald die Force die erste Jagd überstanden hat
-- (stats.first_escape_tick, scripts/worms.lua), geprüft jede Sekunde, also auch für alte Spielstände.

local terrain = require("scripts.terrain")
local worms_lib = require("scripts.worms")

local lib = {}

lib.NAME = "arrakis-thumper"
lib.TECH = "arrakis-thumper"
-- Laufzeit (Ticks), Einstellung arrakis-thumper-seconds (scripts/config.lua).
lib.TICKS = 3600
-- Sandstaub alle so viele Ticks, solange er läuft.
lib.DUST_TICKS = 120

local DUST = "arrakis-sand-dust"

local function data()
  storage.thumpers = storage.thumpers or {}
  return storage.thumpers
end

-- Anmelden (Bauen, Skript); auf Arrakis gleich ablenken. Gibt den Datensatz zurück.
function lib.register(entity)
  if not (entity and entity.valid and entity.name == lib.NAME and entity.unit_number) then return nil end
  local list = data()
  local record = list[entity.unit_number]
  if record then return record end
  record =
  {
    un = entity.unit_number,
    entity = entity,
    surface = entity.surface.index,
    force_index = entity.force.index,
    until_tick = game.tick + lib.TICKS,
    sand = terrain.has_sand_under(entity),
    weight = 0,
    key = nil
  }
  list[record.un] = record
  if terrain.harvest_allowed(entity.surface) then
    local hunt = worms_lib.divert(entity)
    if hunt then record.diverted = hunt.id end
  end
  return record
end

-- Forschung „Thumper“ für Forces, die eine Jagd überstanden haben.
local function research_tick()
  for _, force in pairs(game.forces) do
    local tech = force.technologies[lib.TECH]
    if tech and not tech.researched then
      local stats = storage.worm_stats and storage.worm_stats[force.index]
      if stats and stats.first_escape_tick then
        force.script_trigger_research(lib.TECH)
        if not tech.researched then tech.researched = true end
      end
    end
  end
end

local function on_nth_tick_60(event)
  local tick = event.tick
  local list = storage.thumpers
  if list and next(list) ~= nil then
    local gone = {}
    for un, record in pairs(list) do
      local entity = record.entity
      if not entity.valid then
        gone[#gone + 1] = un
      elseif tick >= record.until_tick and not worms_lib.hunt_of(entity) then
        entity.surface.create_trivial_smoke{name = DUST, position = entity.position}
        entity.destroy()
        gone[#gone + 1] = un
      elseif record.sand and tick % lib.DUST_TICKS < 60 then
        entity.surface.create_trivial_smoke{name = DUST, position = entity.position}
      end
    end
    for _, un in ipairs(gone) do list[un] = nil end
  end
  research_tick()
end

local function on_built(event)
  lib.register(event.entity)
end

lib.events =
{
  [defines.events.on_built_entity] = on_built,
  [defines.events.on_robot_built_entity] = on_built,
  [defines.events.script_raised_built] = on_built,
  [defines.events.script_raised_revive] = on_built
}

lib.on_nth_tick =
{
  [60] = on_nth_tick_60
}

lib.on_init = function()
  data()
end

lib.on_configuration_changed = function()
  data()
end

return lib
