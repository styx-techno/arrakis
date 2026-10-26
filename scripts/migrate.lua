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
--   storage.migration       {spice_drills = {LuaEntity…}, old_map_notice = true|nil}
--
-- Schema 2 (0.6.0, Phase 3c, docs/plan-3c.md 4.2), dazu:
--   storage.harvesters[un]  zusätzlich state "carried", carried_by = flyer_un|nil, lift_pos = {surface, x, y}|nil
--   storage.flyers[un]      Ornithopter-Datensätze (scripts/flyer.lua)
--   storage.couplings[un]   true, Ornithopter, die gerade ankoppeln (10-Tick-Takt)
--   storage.stranded[un]    {crash_pos, damage, reason}, getragene Ernter ohne Träger und ohne Landeplatz
--   storage.hold            {surface = LuaSurface|nil}, Ablage arrakis-hold (scripts/hold.lua)
--   storage.flyer_gui_open[player_index] = flyer_un (scripts/flyer-gui.lua)
--   storage.reg[nummer]     zusätzlich kind "flyer"
-- 0.5.x → 0.6.0: „Ornithopter“ (Trigger: ersten Spice-Ernter herstellen) feuert nicht rückwirkend [U12]; für
-- Forces mit erforschter „Spice-Ernte“ und Ernter holt migrate.ornithopter_research die Forschung nach.
-- 0.6.1: Dieselbe Prüfung läuft jede Sekunde für jede Force, bei der „Ornithopter“ noch aussteht, dazu
-- on_player_crafted_item [U11]: Im Prüfstand-Lauf vom 26.10.2026 (T15 Schritt 2) stellte eine Figur ohne Spieler einen
-- Ernter her, und der Auslöser der Engine feuerte nicht. Erforscht das Skript, bekommt die Force eine Chatzeile.
-- Herunterstufen auf 0.5.x mit getragenem Ernter ist nicht unterstützt (0.5.x kennt carried nicht): vorher absetzen.
--
-- Karte 2 (0.5.4) kommt nur auf eine neu angelegte Arrakis-Oberfläche. Behält ein Spielstand Karte 1,
-- meldet migrate das einmal (Merker storage.migration.old_map_notice): beim Mod-Update, wenn die
-- Oberfläche schon existiert, sonst beim Anlegen der Oberfläche. Ob ein vor 0.5.4 begonnener Spielstand
-- ohne Arrakis-Oberfläche beim Anlegen Karte 1 oder Karte 2 bekommt, ist ungeprüft: Der Planet hält eigene
-- Kartengenerator-Einstellungen, die vom Prototyp abweichen können (LuaPlanet::reset_map_gen_settings,
-- A23 classes.d.ts:15857-15860). Kommt Karte 1, meldet es on_surface_created.

local planet_map_gen = require("prototypes.planet.planet-map-gen")

local migrate = {}

local SCHEMA = 2
local SPICE = "spice-sand"
local ARRAKIS = "arrakis"
local HARVESTER = "spice-harvester"
local HARVESTING_TECH = "arrakis-spice-harvesting"
local ORNITHOPTER_TECH = "arrakis-ornithopter"

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
  -- Schema 2 (Phase 3c)
  storage.flyers = storage.flyers or {}
  storage.couplings = storage.couplings or {}
  storage.stranded = storage.stranded or {}
  storage.hold = storage.hold or {}
  storage.flyer_gui_open = storage.flyer_gui_open or {}
end

-- Hat die Force einen Spice-Ernter (Datensatz in storage.harvesters) oder je einen hergestellt
-- (Produktionsstatistik irgendeiner Oberfläche, A23 classes.d.ts:11187, :10737)?
local function has_harvester(force)
  for _, h in pairs(storage.harvesters or {}) do
    local entity = h.entity
    if entity.valid and entity.force.index == force.index then return true end
  end
  for _, surface in pairs(game.surfaces) do
    if force.get_item_production_statistics(surface).get_input_count(HARVESTER) > 0 then return true end
  end
  return false
end

-- Steht „Ornithopter“ für die Force aus? Vorhanden und nicht erforscht, „Spice-Ernte“ erforscht. Nur zwei Abfragen,
-- deshalb vor jeder teureren Prüfung (Datensätze, Statistik aller Oberflächen).
function migrate.ornithopter_pending(force)
  if not (force and force.valid) then return false end
  local technologies = force.technologies
  local ornithopter = technologies[ORNITHOPTER_TECH]
  if not ornithopter or ornithopter.researched then return false end
  local harvesting = technologies[HARVESTING_TECH]
  return harvesting ~= nil and harvesting.researched
end

-- Holt „Ornithopter“ nach (docs/plan-3c.md 4.15): steht aus und die Force hat einen Ernter oder je einen hergestellt
-- → researched = true (A23 classes.d.ts:22293), Rückgabe true. Der Trigger feuert nicht für früher hergestellte Ernter
-- [U12]. Setzt nur, was fehlt, und meldet nichts; für T15 exportiert.
function migrate.ornithopter_research(force)
  if not migrate.ornithopter_pending(force) then return false end
  if not has_harvester(force) then return false end
  force.technologies[ORNITHOPTER_TECH].researched = true
  return true
end

-- Forschung „Ornithopter“ per Skript (0.6.1) [U11]: Steht sie aus und hat die Force einen Ernter (crafted: das
-- Ereignis on_player_crafted_item beweist ihn, die Statistik kann nachhinken), erforscht das Skript sie und meldet es der
-- Force. Hat die Engine sie schon erforscht, steht sie nicht mehr aus: keine Meldung. Rückgabe true, wenn erforscht.
local function research_by_script(force, crafted)
  if not migrate.ornithopter_pending(force) then return false end
  if crafted then
    force.technologies[ORNITHOPTER_TECH].researched = true
  elseif not migrate.ornithopter_research(force) then
    return false
  end
  force.print({"arrakis-message.msg-ornithopter-researched"})
  return true
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

-- Erzeugt diese Oberfläche Karte 1? Karte 2 erkennt man an einem ihrer Schlüssel (prototypes/planet/planet-map-gen.lua).
local function uses_old_map(surface)
  local names = surface.map_gen_settings.property_expression_names or {}
  return names[planet_map_gen.V2_KEY] ~= planet_map_gen.V2_NAME
end

-- Meldet einmal je Spielstand im Chat und im Log, dass Arrakis hier die alte Karte behält.
function migrate.notice_old_map(surface)
  local migration = storage.migration
  if not migration or migration.old_map_notice then return end
  if not (surface and surface.valid and surface.name == ARRAKIS) then return end
  if not uses_old_map(surface) then return end
  migration.old_map_notice = true
  game.print({"arrakis-message.old-map"})
  log({"arrakis-message.old-map"})
end

local function on_surface_created(event)
  migrate.notice_old_map(game.get_surface(event.surface_index))
end

-- Von Hand hergestellt (A23 events.d.ts:2346): ein Spice-Ernter → Forschung sofort, wenn sie aussteht.
local function on_player_crafted_item(event)
  local stack = event.item_stack
  local name = stack and stack.valid_for_read and stack.name
  if not name then
    local recipe = event.recipe
    name = recipe and recipe.valid and recipe.name
  end
  if name ~= HARVESTER then return end
  local player = game.get_player(event.player_index)
  if player then research_by_script(player.force, true) end
end

-- Jede Sekunde (Takt wie flyer.lua, event_handler fasst die Handler zusammen): je Force, bei der „Ornithopter“ aussteht,
-- dieselbe Prüfung wie die Migration. Forces ohne „Spice-Ernte“ oder mit erforschtem „Ornithopter“ kosten zwei
-- Abfragen; nur eine ausstehende Force liest Datensätze und Statistik.
local function on_nth_tick_60()
  for _, force in pairs(game.forces) do
    research_by_script(force, false)
  end
end

migrate.events =
{
  [defines.events.on_surface_created] = on_surface_created,
  [defines.events.on_player_crafted_item] = on_player_crafted_item
}

migrate.on_nth_tick =
{
  [60] = on_nth_tick_60
}

migrate.on_init = function()
  migrate.init()
  storage.schema = SCHEMA
end

migrate.on_configuration_changed = function()
  migrate.init()
  local old = storage.schema or 0
  if old < 1 then
    -- 0.3.0/0.4.x → 0.5.0: Spice gehört jetzt zur Kategorie arrakis-spice-harvest, Bohrer bauen es nicht mehr ab.
    local planet = game.planets["arrakis"]
    local surface = planet and planet.surface
    if surface then storage.migration.spice_drills = migrate.report_drills(surface) end
  end
  if old < 2 then
    -- 0.5.x → 0.6.0: Forschung „Ornithopter“ für Forces mit Ernter nachholen (siehe oben).
    for _, force in pairs(game.forces) do
      migrate.ornithopter_research(force)
    end
  end
  storage.schema = math.max(old, SCHEMA)
  -- 0.5.3 → 0.5.4: Hinweis auf die alte Karte (siehe oben).
  local planet = game.planets[ARRAKIS]
  migrate.notice_old_map(planet and planet.surface)
end

return migrate
