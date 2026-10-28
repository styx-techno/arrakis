-- storage-Aufbau, Schema und Migration (Phase 3b, Plan 4.2 und 4.10; Schema 3: docs/plan-3d1.md 4.16; Schema 4:
-- docs/plan-3d2.md 4.14).
-- Erste Bibliothek in control.lua: legt alle Tabellen in on_init und on_configuration_changed an, bevor die anderen
-- Module sie benutzen. on_load schreibt nie (diese Bibliothek hat kein on_load).
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
-- Schema 3 (0.7.0, Phase 3d1, docs/plan-3d1.md 4.2), dazu:
--   storage.rng             LuaRandomGenerator (Kartenseed), nur für die Ruhezeit der Sektoren
--   storage.grace[force_index]  Schonfrist je Force (scripts/worms.lua)
--   storage.vib             {sources, heat, rumble, overlay, testbench}: Quellen, Wärme, Rumpeln, Vibrationsanzeige,
--                           Prüfstand-Merker (scripts/vibration.lua)
--   storage.hunts           {next_id, list = {[id] = Jagd}, paused_until}: Jagden (scripts/worms.lua)
--   storage.sector_cooldown[surface_index][sector_key] = Ende der Ruhe
--   storage.worm_stats[force_index] = {bitten, escaped, gone, first_escape_tick}
--   storage.harvesters[un]  zusätzlich careful, careful_wait, careful_pos, careful_packing, vib_weight, vib_key,
--                           vib_sand, alarm_unrest, alarm_hunt_eta, alarm_hunt_safe, status_written
--   storage.migration       zusätzlich worms_pending (hier gesetzt, von worms.lua abgearbeitet), worm_notice
-- 0.6.x/0.5.x → 0.7.0: fehlende Ernter-Felder nachtragen, worms_pending setzen; Schonfrist, Quellen-Scan und Chatzeile
-- macht worms.lua in seinem on_configuration_changed (läuft danach). old < 2 läuft vor old < 3: Die Schonfrist sieht
-- die nachgeholte Forschung „Ornithopter“. worms_pending steht schon vor old < 2: researched = true löst
-- on_research_finished sofort aus [V2], und worms.lua nennt den Termin dann nicht ein zweites Mal. Herunterstufen auf
-- 0.6.x: vorher /arrakis-uninstall ja (Markierungen und die Sandwurm-Force blieben sonst im Spielstand).
--
-- Schema 4 (0.8.0, Phase 3d2, docs/plan-3d2.md 4.2), dazu:
--   storage.path_requests[request_id] = {hunt, kind = "plan"|"reroute", sent}: offene Pfad-Anfragen (scripts/sandworm.lua)
--   storage.worm_dives[i] = {unit, start, wave}: abtauchende Würmer (ab 0.8.4, scripts/sandworm.lua dive_takt)
--   storage.hunts           zusätzlich worm_off, spawn_dir (Prüfstand), log, log_next, ersatz (Protokoll)
--   storage.hunts.list[id]  zusätzlich r, phase, no_worm, dive, zone, plan_tick, spawn_tick, d, plan, path, worm,
--                           bite_tick, bite_dist, ersatz, last_worm, spawn_hook, spawn_dir
--   storage.worm_stats[force_index]  zusätzlich killed
-- 0.7.0 → 0.8.0: killed nachtragen. Laufende Jagden ohne phase oder r normalisiert worms.lua in jedem
-- on_configuration_changed, nicht nur bei old < 4: Nach 0.8.0 → 0.7.0 → 0.8.0 steht schema schon auf 4 (math.max).
-- Herunterstufen auf 0.7.0: vorher /arrakis-uninstall ja (sonst löscht die Engine die Würmer, Jagden beißen ohne Wurm).
--
-- Karte 2 (0.5.4) kommt nur auf eine neu angelegte Arrakis-Oberfläche. Behält ein Spielstand Karte 1,
-- meldet migrate das einmal (Merker storage.migration.old_map_notice): beim Mod-Update, wenn die
-- Oberfläche schon existiert, sonst beim Anlegen der Oberfläche. Ob ein vor 0.5.4 begonnener Spielstand
-- ohne Arrakis-Oberfläche beim Anlegen Karte 1 oder Karte 2 bekommt, ist ungeprüft: Der Planet hält eigene
-- Kartengenerator-Einstellungen, die vom Prototyp abweichen können (LuaPlanet::reset_map_gen_settings,
-- A23 classes.d.ts:15857-15860). Kommt Karte 1, meldet es on_surface_created.

local planet_map_gen = require("prototypes.planet.planet-map-gen")

local migrate = {}

local SCHEMA = 4
local SPICE = "spice-sand"
local ARRAKIS = "arrakis"
local HARVESTER = "spice-harvester"
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
  -- Schema 3 (Phase 3d1)
  storage.rng = storage.rng or game.create_random_generator()
  storage.grace = storage.grace or {}
  storage.vib = storage.vib or {}
  local vib = storage.vib
  vib.sources = vib.sources or {}
  vib.heat = vib.heat or {}
  vib.rumble = vib.rumble or {}
  vib.overlay = vib.overlay or {}
  vib.testbench = vib.testbench or {}
  storage.hunts = storage.hunts or {next_id = 1, list = {}}
  storage.hunts.next_id = storage.hunts.next_id or 1
  storage.hunts.list = storage.hunts.list or {}
  storage.sector_cooldown = storage.sector_cooldown or {}
  storage.worm_stats = storage.worm_stats or {}
  -- Schema 4 (Phase 3d2)
  storage.path_requests = storage.path_requests or {}
  -- 0.8.4: abtauchende Würmer (scripts/sandworm.lua dive_takt)
  storage.worm_dives = storage.worm_dives or {}
  local hunts = storage.hunts
  hunts.worm_off = hunts.worm_off or {}
  hunts.spawn_dir = hunts.spawn_dir or {}
  hunts.log = hunts.log or {}
  hunts.log_next = hunts.log_next or 1
  hunts.ersatz = hunts.ersatz or 0
end

-- Hat die Force einen Spice-Ernter (Datensatz in storage.harvesters) oder je einen hergestellt
-- (Produktionsstatistik irgendeiner Oberfläche, A23 classes.d.ts:11187, :10737)? Die Statistik zählt je Qualität, ein
-- Name allein fragt nur „normal“ ab (A23 concepts.d.ts:4599–4611); deshalb jede Qualität außer quality-unknown
-- (prototypes.quality, A23 classes.d.ts:17058), sonst bliebe ein Ernter aus einer Maschine mit Qualitätsmodulen ungezählt.
local function has_harvester(force)
  for _, h in pairs(storage.harvesters or {}) do
    local entity = h.entity
    if entity.valid and entity.force.index == force.index then return true end
  end
  for _, surface in pairs(game.surfaces) do
    local stats = force.get_item_production_statistics(surface)
    for quality in pairs(prototypes.quality) do
      if quality ~= "quality-unknown" and stats.get_input_count({name = HARVESTER, quality = quality}) > 0 then return true end
    end
  end
  return false
end

-- Steht „Ornithopter“ für die Force aus? Vorhanden, freigegeben und nicht erforscht, jede Voraussetzung erforscht (also
-- „Spice-Ernte“; enabled und prerequisites, A23 classes.d.ts:22238, :22267): Mehr als der Auslöser der Engine darf das
-- Skript nicht, auch wenn eine andere Mod Voraussetzungen ergänzt oder ein Szenario die Technologie sperrt. Nur wenige
-- Abfragen, deshalb vor jeder teureren Prüfung (Datensätze, Statistik aller Oberflächen).
function migrate.ornithopter_pending(force)
  if not (force and force.valid) then return false end
  local ornithopter = force.technologies[ORNITHOPTER_TECH]
  if not ornithopter or ornithopter.researched or not ornithopter.enabled then return false end
  for _, prerequisite in pairs(ornithopter.prerequisites) do
    if not prerequisite.researched then return false end
  end
  return true
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
-- dieselbe Prüfung wie die Migration. Forces ohne „Spice-Ernte“ oder mit erforschtem „Ornithopter“ kosten nur die
-- Abfragen der Technologie und ihrer Voraussetzungen; nur eine ausstehende Force liest Datensätze und Statistik.
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
  -- 0.6.x/0.5.x → 0.7.0: vor old < 2 merken (siehe oben); die Ernter-Felder folgen unten.
  if old < 3 then storage.migration.worms_pending = true end
  if old < 2 then
    -- 0.5.x → 0.6.0: Forschung „Ornithopter“ für Forces mit Ernter nachholen (siehe oben).
    for _, force in pairs(game.forces) do
      migrate.ornithopter_research(force)
    end
  end
  if old < 3 then
    -- 0.6.x/0.5.x → 0.7.0: Felder für Vorsichtsmodus und Vibration; der Rest folgt in worms.lua (siehe oben).
    for _, h in pairs(storage.harvesters) do
      if h.careful == nil then h.careful = false end
      if h.vib_weight == nil then h.vib_weight = 0 end
      if h.vib_sand == nil then h.vib_sand = false end
    end
  end
  if old < 4 then
    -- 0.7.0 → 0.8.0: Statistik getöteter Würmer; Jagden normalisiert worms.lua (siehe oben).
    for _, record in pairs(storage.worm_stats) do record.killed = record.killed or 0 end
  end
  storage.schema = math.max(old, SCHEMA)
  -- 0.5.3 → 0.5.4: Hinweis auf die alte Karte (siehe oben).
  local planet = game.planets[ARRAKIS]
  migrate.notice_old_map(planet and planet.surface)
end

return migrate
