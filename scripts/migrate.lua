-- storage-Aufbau, Schema und Migration (Phase 3b, Plan 4.2 und 4.10). Erste Bibliothek in control.lua:
-- legt alle Tabellen in on_init und on_configuration_changed an, bevor die anderen Module sie benutzen.
-- on_load schreibt nie (diese Bibliothek hat kein on_load).
--
-- Schema 1:
--   storage.harvesters[un]  Ernter-Datensätze (scripts/harvester.lua)
--   storage.driven[un]      LuaEntity, Ernter mit Tempo-Deckel jeden Tick
--   storage.timers[un]      true, Ernter im Aufbauen/Einpacken
--   storage.intakes[un]     Annahmen, storage.nozzles[un] Tankstutzen (scripts/intake.lua)
--   storage.reg[nummer]     {kind = "harvester"|"intake"|"nozzle", un} für on_object_destroyed
--   storage.gui_open[player_index] = un (scripts/harvester-gui.lua)
--   storage.migration       {spice_drills = {LuaEntity…}}

local migrate = {}

local SCHEMA = 1
local SPICE = "spice-sand"

-- Schema-Version dieses Codes.
migrate.SCHEMA = SCHEMA

-- Legt fehlende storage-Tabellen an (nur aus on_init und on_configuration_changed aufrufen).
function migrate.init()
  storage.harvesters = storage.harvesters or {}
  storage.driven = storage.driven or {}
  storage.timers = storage.timers or {}
  storage.intakes = storage.intakes or {}
  storage.nozzles = storage.nozzles or {}
  storage.reg = storage.reg or {}
  storage.gui_open = storage.gui_open or {}
  storage.migration = storage.migration or {}
  storage.migration.spice_drills = storage.migration.spice_drills or {}
end

local function on_spice(surface, drill)
  local target = drill.mining_target
  if target and target.valid and target.name == SPICE then return true end
  return surface.count_entities_filtered{area = drill.mining_area, name = SPICE, limit = 1} > 0
end

-- Meldet Bohrer auf Spice-Sand (Markierung, Alarm, Sammelzeile je Force, kein Abriss); gibt die Liste zurück.
function migrate.report_drills(surface)
  local found = {}
  if not (surface and surface.valid) then return found end
  for _, drill in pairs(surface.find_entities_filtered{type = "mining-drill"}) do
    if drill.valid and on_spice(surface, drill) then table.insert(found, drill) end
  end
  local per_force = {}
  local icon = {type = "item", name = SPICE}
  for _, drill in pairs(found) do
    local force = drill.force
    force.add_chart_tag(surface, {position = drill.position, icon = icon})
    for _, player in pairs(force.connected_players) do
      player.add_custom_alert(drill, icon, {"arrakis-message.alert-drill-on-spice"}, true)
    end
    local entry = per_force[force.index]
    if entry then
      entry.count = entry.count + 1
    else
      per_force[force.index] = {force = force, count = 1, first = drill.position}
    end
  end
  for _, entry in pairs(per_force) do
    local gps = string.format("[gps=%d,%d,%s]", math.floor(entry.first.x), math.floor(entry.first.y), surface.name)
    entry.force.print({"arrakis-message.drills-on-spice", entry.count, gps})
  end
  return found
end

migrate.on_init = function()
  migrate.init()
  storage.schema = SCHEMA
end

migrate.on_configuration_changed = function()
  migrate.init()
  if (storage.schema or 0) < 1 then
    -- 0.3.0/0.4.x → 0.5.0: Spice gehört jetzt zur Kategorie arrakis-spice-harvest, Bohrer bauen es nicht mehr ab.
    local planet = game.planets["arrakis"]
    local surface = planet and planet.surface
    if surface then storage.migration.spice_drills = migrate.report_drills(surface) end
  end
  storage.schema = math.max(storage.schema or 0, SCHEMA)
end

return migrate
