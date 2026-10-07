-- Spice-Annahme und Tankstutzen (Phase 3b, Plan 4.8): Bauen, Felsprüfung, Andock-Takt, Zerstören.
-- Bibliothek für __core__/lualib/event_handler. Daten in storage.intakes und storage.nozzles (Schema 1,
-- siehe scripts/migrate.lua). Andocken und Abdocken selbst macht scripts/harvester.lua (dock/undock).
--
-- storage.intakes[un] = {entity, docked = harvester_un|nil, nozzles = {un…}, bad = false}
-- storage.nozzles[un] = {entity, intake = intake_un|nil}

local terrain = require("scripts.terrain")
local harvester = require("scripts.harvester")

local intake = {}

local INTAKE = "arrakis-spice-intake"
local NOZZLE = "arrakis-fuel-nozzle"
local KIND = {[INTAKE] = "intake", [NOZZLE] = "nozzle"}

-- Andockkreis: Mittelpunkt des Ernters höchstens so weit von der Annahme (Kacheln).
intake.DOCK_RADIUS = 4
-- Nach dem Abdocken erst wieder andocken, wenn der Ernter weiter als das weg war (Kacheln).
intake.RELEASE_RADIUS = 5
-- Ein Stutzen gehört zur nächsten Annahme in höchstens so vielen Kacheln.
intake.NOZZLE_RADIUS = 3
-- So lange muss ein Ernter stillstehen, bevor er andockt (Ticks).
intake.STILL_TICKS = 120
-- Halbe Kantenlänge der Felsfläche um die Annahme (wie die Bauregel im Prototyp).
intake.ROCK_RADIUS = 5

local function distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function same_place(a, b)
  return a.surface.index == b.surface.index
end

-- Hinweis als fliegender Text: an den bauenden Spieler, sonst an alle verbundenen Spieler der Force.
local function notify(entity, player_index, key)
  local players = {}
  local player = player_index and game.get_player(player_index)
  if player then
    players = {player}
  else
    players = entity.force.connected_players
  end
  for _, p in pairs(players) do
    p.create_local_flying_text{text = {"arrakis-message." .. key}, position = entity.position, surface = entity.surface}
  end
end

-- Nächste eingetragene Annahme in radius um position; exclude_bad überspringt Annahmen abseits vom Fels.
local function nearest_intake(surface, position, radius, exclude_bad)
  local best, best_distance
  for _, entity in pairs(surface.find_entities_filtered{name = INTAKE, position = position, radius = radius}) do
    local record = storage.intakes[entity.unit_number]
    if record and not (exclude_bad and record.bad) then
      local d = distance(entity.position, position)
      if not best or d < best_distance then
        best, best_distance = record, d
      end
    end
  end
  return best, best_distance
end

local function assign_nozzle(nozzle_record, intake_record)
  local nozzle_un = nozzle_record.entity.unit_number
  nozzle_record.intake = intake_record.entity.unit_number
  table.insert(intake_record.nozzles, nozzle_un)
  harvester.apply_targets(intake_record)
end

-- Stutzen ohne Annahme der nächsten Annahme in Reichweite zuordnen (falls es eine gibt).
local function find_intake_for(nozzle_record)
  local entity = nozzle_record.entity
  local intake_record = nearest_intake(entity.surface, entity.position, intake.NOZZLE_RADIUS, true)
  if intake_record then assign_nozzle(nozzle_record, intake_record) end
end

-- Eintragen ------------------------------------------------------------------------------------

local function register_intake(entity, player_index)
  local un = entity.unit_number
  local record = storage.intakes[un]
  if record then return record end
  record = {entity = entity, docked = nil, nozzles = {}, bad = false}
  storage.intakes[un] = record
  storage.reg[script.register_on_object_destroyed(entity)] = {kind = "intake", un = un}
  entity.proxy_target_entity = nil
  local p = entity.position
  local r = intake.ROCK_RADIUS
  if not terrain.is_rock_area(entity.surface, {{p.x - r, p.y - r}, {p.x + r, p.y + r}}) then
    record.bad = true
    entity.order_deconstruction(entity.force)
    notify(entity, player_index, "hint-intake-rock")
    return record
  end
  -- Freie Stutzen in Reichweite übernehmen (Annahme nach den Stutzen gebaut).
  for _, nozzle in pairs(entity.surface.find_entities_filtered{name = NOZZLE, position = p, radius = intake.NOZZLE_RADIUS}) do
    local nozzle_record = storage.nozzles[nozzle.unit_number]
    if nozzle_record and not nozzle_record.intake then assign_nozzle(nozzle_record, record) end
  end
  return record
end

local function register_nozzle(entity)
  local un = entity.unit_number
  local record = storage.nozzles[un]
  if record then return record end
  record = {entity = entity, intake = nil}
  storage.nozzles[un] = record
  storage.reg[script.register_on_object_destroyed(entity)] = {kind = "nozzle", un = un}
  entity.proxy_target_entity = nil
  find_intake_for(record)
  return record
end

-- Annahme oder Stutzen eintragen (Bauen, Klon); gibt den Datensatz zurück. player_index nur für Hinweise.
function intake.register(entity, player_index)
  if not (entity and entity.valid) then return nil end
  local kind = KIND[entity.name]
  if kind == "intake" then return register_intake(entity, player_index) end
  if kind == "nozzle" then return register_nozzle(entity) end
  return nil
end

-- Datensatz einer Annahme oder eines Stutzens oder nil.
function intake.get(entity)
  if not (entity and entity.valid) then return nil end
  local kind = KIND[entity.name]
  if kind == "intake" then return storage.intakes[entity.unit_number] end
  if kind == "nozzle" then return storage.nozzles[entity.unit_number] end
  return nil
end

-- Entfernen ------------------------------------------------------------------------------------

-- Annahme austragen: angedockten Ernter abdocken, Stutzen freigeben und neu zuordnen.
local function remove_intake(un)
  local record = storage.intakes[un]
  if not record then return end
  local h = record.docked and storage.harvesters[record.docked]
  if h and h.state == "docked" and h.dock == un then
    harvester.undock(h)
  end
  record.docked = nil
  if record.entity.valid then record.entity.proxy_target_entity = nil end
  storage.intakes[un] = nil
  for _, nozzle_un in pairs(record.nozzles) do
    local nozzle_record = storage.nozzles[nozzle_un]
    if nozzle_record and nozzle_record.intake == un then
      nozzle_record.intake = nil
      if nozzle_record.entity.valid then
        nozzle_record.entity.proxy_target_entity = nil
        find_intake_for(nozzle_record)
      end
    end
  end
end

local function remove_nozzle(un)
  local record = storage.nozzles[un]
  if not record then return end
  storage.nozzles[un] = nil
  local intake_record = record.intake and storage.intakes[record.intake]
  if intake_record then
    for i = #intake_record.nozzles, 1, -1 do
      if intake_record.nozzles[i] == un then table.remove(intake_record.nozzles, i) end
    end
  end
  if record.entity.valid then record.entity.proxy_target_entity = nil end
end

-- Zentraler Entfernen-Weg für Annahme (kind "intake") und Stutzen (kind "nozzle").
function intake.remove(kind, un)
  if kind == "intake" then remove_intake(un) elseif kind == "nozzle" then remove_nozzle(un) end
end

-- Andock-Takt ----------------------------------------------------------------------------------

local function targets_entity(entity, h)
  local target = entity.proxy_target_entity
  return target and target.valid and target.unit_number == h.un
end

-- true, wenn die Annahme oder ein zugeordneter Stutzen nicht auf den Ernter zeigt (z. B. Ziel im
-- on_pre_mined gelöscht, das Abbauen aber nicht beendet).
local function targets_stale(record, h)
  if not targets_entity(record.entity, h) then return true end
  for _, nozzle_un in pairs(record.nozzles) do
    local nozzle = storage.nozzles[nozzle_un]
    if nozzle and nozzle.entity.valid and not targets_entity(nozzle.entity, h) then return true end
  end
  return false
end

-- Angedockte Ernter prüfen: Ernter gültig, angedockt und im Kreis, Annahme gültig; Ziele stimmen.
local function check_docked(un, record)
  if not record.entity.valid then
    remove_intake(un)
    return
  end
  if not record.docked then return end
  local h = storage.harvesters[record.docked]
  local ok = h and h.state == "docked" and h.dock == un and h.entity.valid
    and same_place(h.entity, record.entity)
    and distance(h.entity.position, record.entity.position) <= intake.DOCK_RADIUS
  if ok then
    if targets_stale(record, h) then harvester.apply_targets(record) end
  elseif h and h.state == "docked" and h.dock == un then
    harvester.undock(h)
  else
    record.docked = nil
    harvester.apply_targets(record)
  end
end

-- Andock-Takt für einen mobilen Ernter (Plan 4.8, Stillstand, Kreis, Hysterese); true, wenn er angedockt hat.
function intake.dock_check(h, tick)
  if not (h and h.state == "mobile") then return false end
  local entity = h.entity
  if not entity.valid then return false end
  if h.undocked_from then
    local from = storage.intakes[h.undocked_from]
    if not (from and from.entity.valid and same_place(from.entity, entity)
        and distance(from.entity.position, entity.position) <= intake.RELEASE_RADIUS) then
      h.undocked_from = nil
    end
  end
  if not terrain.harvest_allowed(entity.surface) then
    h.still_since = nil
    return false
  end
  if math.abs(entity.speed) >= harvester.STILL_SPEED then
    h.still_since = nil
    return false
  end
  h.still_since = h.still_since or tick
  if tick - h.still_since < intake.STILL_TICKS then return false end
  local record = nearest_intake(entity.surface, entity.position, intake.DOCK_RADIUS, false)
  if not record or record.bad or record.docked then return false end
  if record.entity.unit_number == h.undocked_from then return false end
  return harvester.dock(h, record)
end

-- Ganzer Andock-Takt (alle 60 Ticks): erst angedockte prüfen, dann mobile Ernter andocken.
function intake.dock_pass(tick)
  for un, record in pairs(storage.intakes) do
    check_docked(un, record)
  end
  for _, h in pairs(storage.harvesters) do
    if h.state == "mobile" then intake.dock_check(h, tick) end
  end
end

-- Ereignisse ---------------------------------------------------------------------------------------

local function on_built(event)
  local entity = event.entity
  if entity and entity.valid and KIND[entity.name] then intake.register(entity, event.player_index) end
end

-- Klon: neuer Eintrag ohne Proxy-Ziel (register löscht es), Felsprüfung am neuen Ort.
local function on_cloned(event)
  local entity = event.destination
  if entity and entity.valid and KIND[entity.name] then intake.register(entity) end
end

local function on_removed(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  local kind = KIND[entity.name]
  if kind then intake.remove(kind, entity.unit_number) end
end

-- Vor dem Abbauen das Proxy-Ziel lösen, damit Laderaum und Tank nicht ins Inventar des Abbauenden wandern.
local function on_pre_mined(event)
  local entity = event.entity
  if entity and entity.valid and KIND[entity.name] then entity.proxy_target_entity = nil end
end

local function on_object_destroyed(event)
  local reg = storage.reg[event.registration_number]
  if not (reg and (reg.kind == "intake" or reg.kind == "nozzle")) then return end
  storage.reg[event.registration_number] = nil
  intake.remove(reg.kind, reg.un)
end

-- Einstellungen einfügen: Ziele aus storage neu setzen (nie ein kopiertes Ziel übernehmen).
local function on_settings_pasted(event)
  local entity = event.destination
  if not (entity and entity.valid) then return end
  local kind = KIND[entity.name]
  if kind == "intake" then
    local record = storage.intakes[entity.unit_number]
    if record then harvester.apply_targets(record) else entity.proxy_target_entity = nil end
  elseif kind == "nozzle" then
    local record = storage.nozzles[entity.unit_number]
    local intake_record = record and record.intake and storage.intakes[record.intake]
    if intake_record then harvester.apply_targets(intake_record) else entity.proxy_target_entity = nil end
  end
end

intake.events =
{
  [defines.events.on_built_entity] = on_built,
  [defines.events.on_robot_built_entity] = on_built,
  [defines.events.on_space_platform_built_entity] = on_built,
  [defines.events.script_raised_built] = on_built,
  [defines.events.script_raised_revive] = on_built,
  [defines.events.on_entity_cloned] = on_cloned,
  [defines.events.on_entity_died] = on_removed,
  [defines.events.on_player_mined_entity] = on_removed,
  [defines.events.on_robot_mined_entity] = on_removed,
  [defines.events.on_space_platform_mined_entity] = on_removed,
  [defines.events.script_raised_destroy] = on_removed,
  [defines.events.on_pre_player_mined_item] = on_pre_mined,
  [defines.events.on_robot_pre_mined] = on_pre_mined,
  [defines.events.on_space_platform_pre_mined] = on_pre_mined,
  [defines.events.on_object_destroyed] = on_object_destroyed,
  [defines.events.on_entity_settings_pasted] = on_settings_pasted
}

intake.on_nth_tick =
{
  [60] = function(event) intake.dock_pass(event.tick) end
}

return intake
