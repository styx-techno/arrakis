-- Spice-Ernter (Phase 3b): Zustände, Abbau, Treibstoff, Tempo, Abbausperre, Andocken/Abdocken und Taste.
-- Bibliothek für __core__/lualib/event_handler (Plan 4.1). Daten nur in storage (Schema 3, siehe
-- scripts/migrate.lua), Schlüssel ist unit_number. Ereignisse kommen ungefiltert: Jeder Handler prüft
-- zuerst den Namen und kehrt sofort zurück. scripts/intake.lua ruft dock/undock; dieses Modul kennt
-- intake.lua nicht, liest aber storage.intakes/storage.nozzles als Daten (Proxy-Ziele setzen und löschen).
--
-- Datensatz storage.harvesters[un] (Plan 4.2, dazu un = eigener Schlüssel):
--   un, entity, state = "mobile"|"deploying"|"deployed"|"packing"|"docked"|"carried",
--   timer_start, timer_end, resources = {LuaEntity…}, res_index, progress, drain_rest, prod_rest,
--   last_tick, deploy_pos = {x, y}, deploy_surface, status = nil|"harvesting"|"trunk_full"|"field_empty"|"no_fuel",
--   renders = {ring, frame}, dock, undocked_from, still_since, fuel_key, last_toggle_tick, minable_pos,
--   carried_by = flyer_un|nil, lift_pos = {surface = surface_index, x, y}|nil (Phase 3c, docs/plan-3c.md 4.2)
--   Phase 3d1 (docs/plan-3d1.md 4.2): careful = false, careful_wait = true|nil, careful_pos = {surface, x, y}|nil,
--   careful_packing = true|nil (Vorsichtsmodus, scripts/vibration.lua), vib_weight, vib_key, vib_sand (Stand des letzten
--   60-Tick-Takts), alarm_unrest, alarm_hunt_eta, alarm_hunt_safe (set_alarm), status_written (zuletzt geschriebener
--   custom_status, Schlüssel wie "hunt:37").
--
-- Status am Ernter (docs/plan-3d1.md 1 „Status Ernter“): getragen immer „Wird getragen“; sonst Vorrang Wurmzeichen (rot,
-- sicher grün) vor „Vorsichtsmodus: wartet auf Ruhe“ (gelb) vor „Der Sand bebt“ (gelb) vor dem Zustand aus 3b/3c, auch im
-- Zustand mobil. Die Werte setzen scripts/vibration.lua und scripts/worms.lua über set_alarm und refresh_status; dieses
-- Modul kennt beide nicht.
--
-- Zustand carried (Phase 3c, docs/plan-3c.md 4.1 und 4.3): Der Ernter steht gesperrt auf der Ablage arrakis-hold,
-- am Ornithopter hängt sein Bild. Anheben (lift) und Absetzen (land) ruft scripts/flyer.lua; dieses Modul kennt
-- flyer.lua nicht. carried gilt als gesperrt (LOCKED: nicht abbaubar, kein Tempo-Deckel), hat aber keine Uhr (TIMED).
-- Wartet ein Ernter ohne Träger auf einen Landeplatz (storage.stranded, flyer.lua), ist carried_by nil.

local terrain = require("scripts.terrain")

-- Modultabelle (andere Module laden sie als harvester; hier lib, weil tools/check/api_names.py den
-- Namen harvester als LuaEntity deutet).
local lib = {}

local NAME = "spice-harvester"
local SPICE = "spice-sand"
local TOGGLE_INPUT = "arrakis-harvester-toggle"

-- Tempo-Deckel (Kacheln/s), läuft jeden Tick für gefahrene Ernter (Plan 1, 4.4).
lib.CAP = 1.5
-- Rücksetzwert beim Überschreiten des Deckels (Kacheln/s), das Vorzeichen bleibt.
lib.RESET = 1.45
-- Name des Ernter-Prototyps.
lib.NAME = NAME
-- Dauer Aufbauen (Ticks).
lib.DEPLOY_TICKS = 5 * 60
-- Dauer Einpacken (Ticks).
lib.PACK_TICKS = 10 * 60
-- Förderung in Spice-Sand je Sekunde, ohne Produktivität.
lib.RATE = 5
-- Feldabzug je gefördertem Spice-Sand (wie der Großbohrer).
lib.DRAIN = 0.5
-- Treibstoffverbrauch beim Ernten (Watt).
lib.POWER = 400000
-- Halbe Kantenlänge des Erntefelds (13×13 Kacheln um die Kachelmitte).
lib.FIELD_RADIUS = 6.5
-- Größtes Δt je Abbautakt (Sekunden), gegen Nachholen nach Pausen.
lib.MAX_DT = 2
-- Ab dieser Verschiebung (Kacheln) gilt ein aufgebauter Ernter als bewegt.
lib.MOVE_LIMIT = 0.25
-- Entprellen: zweite Taste für denselben Ernter innerhalb so vieler Ticks wird ignoriert.
lib.DEBOUNCE = 15
-- Unter diesem Tempo (Kacheln/Tick) steht ein Ernter.
lib.STILL_SPEED = 0.001

local LOCKED = {deploying = true, deployed = true, packing = true, carried = true}
-- Zustände mit Aufbau-/Einpack-Uhr (timer_end); carried ist gesperrt, hat aber keine (docs/plan-3c.md 4.1).
local TIMED = {deploying = true, packing = true}
local ALERT = {trunk_full = true, field_empty = true, no_fuel = true}
local STATUS_KEY =
{
  harvesting = "status-harvesting",
  trunk_full = "status-trunk-full",
  field_empty = "status-field-empty",
  no_fuel = "status-no-fuel"
}
local STATUS_DIODE = {harvesting = "green", trunk_full = "yellow", field_empty = "yellow", no_fuel = "red"}
local RING_COLOR =
{
  deploying = {r = 1, g = 0.65, b = 0.2, a = 0.8},
  packing = {r = 0.35, g = 0.7, b = 1, a = 0.8}
}
local FRAME_COLOR = {r = 1, g = 0.75, b = 0.3, a = 0.6}

-- Hilfen ----------------------------------------------------------------------------------------

local function is_harvester(entity)
  return entity and entity.valid and entity.name == NAME
end

local function is_still(entity)
  local speed = entity.speed
  return speed < lib.STILL_SPEED and speed > -lib.STILL_SPEED
end

-- Erntefeld um die Kachelmitte unter position (genau 13×13 Ressourcenkacheln).
local function field_area(position)
  local cx = math.floor(position.x) + 0.5
  local cy = math.floor(position.y) + 0.5
  local r = lib.FIELD_RADIUS
  return {{cx - r, cy - r}, {cx + r, cy + r}}
end

local function log_error(text, entity)
  log("Arrakis FEHLER: " .. text .. " (" .. (entity.valid and (entity.name .. " " .. tostring(entity.unit_number)) or "ungültig") .. ")")
end

-- Sperren über disabled_by_script, zurücklesen (Plan 4.3); speed = 0 hält ihn sofort an.
local function lock(entity)
  entity.disabled_by_script = true
  entity.speed = 0
  if not entity.disabled_by_script then log_error("disabled_by_script = true wirkt nicht", entity) end
end

local function unlock(entity)
  if not entity.disabled_by_script then return end
  entity.disabled_by_script = false
  if entity.disabled_by_script then log_error("disabled_by_script = false wirkt nicht", entity) end
end

local function hint(player, entity, key)
  if not (player and player.valid) then return end
  player.create_local_flying_text{text = {"arrakis-message." .. key}, position = entity.position, surface = entity.surface}
end

local function stats(entity)
  return entity.force.get_item_production_statistics(entity.surface)
end

-- Anzeige: Ring, Feldrahmen, Status, Alarme ------------------------------------------------------

local function destroy_render(h, key)
  local object = h.renders[key]
  if object and object.valid then object.destroy() end
  h.renders[key] = nil
end

-- Fortschrittsring für Aufbauen/Einpacken: anlegen oder Winkel fortschreiben (nur die eigene Force sieht ihn).
local function draw_ring(h, tick)
  local entity = h.entity
  local total = math.max(1, h.timer_end - h.timer_start)
  local fraction = math.min(1, math.max(0, (tick - h.timer_start) / total))
  local angle = math.max(0.01, 2 * math.pi * fraction)
  local ring = h.renders.ring
  if ring and ring.valid then
    ring.angle = angle
    return
  end
  h.renders.ring = rendering.draw_arc{
    color = RING_COLOR[h.state] or RING_COLOR.deploying,
    max_radius = 2.6,
    min_radius = 2.2,
    start_angle = -math.pi / 2,
    angle = angle,
    target = entity,
    surface = entity.surface,
    forces = {entity.force}
  }
end

local function draw_frame(h, area)
  local entity = h.entity
  destroy_render(h, "frame")
  h.renders.frame = rendering.draw_rectangle{
    color = FRAME_COLOR,
    width = 2,
    filled = false,
    left_top = area[1],
    right_bottom = area[2],
    surface = entity.surface,
    forces = {entity.force},
    draw_on_ground = true
  }
end

-- custom_status nach Vorrang (Kopfkommentar), Zustand und Status. Geschrieben wird nur, wenn sich Text oder Sekunde
-- ändern (Schlüssel in h.status_written, docs/plan-3d1.md 4.1); aufrufen bei jedem Zustands-, Status- oder Alarmwechsel.
local function write_custom_status(h)
  local entity = h.entity
  if not entity.valid then return end
  local state = h.state
  local key, status
  if state == "carried" then
    key = "state:carried"
    status = {diode = defines.entity_status_diode.yellow, label = {"arrakis-message.state-carried"}}
  elseif h.alarm_hunt_eta then
    local left = math.max(0, math.ceil((h.alarm_hunt_eta - game.tick) / 60))
    if h.alarm_hunt_safe then
      key = "safe:" .. left
      status = {diode = defines.entity_status_diode.green, label = {"arrakis-message.status-wormsign-safe", left}}
    else
      key = "hunt:" .. left
      status = {diode = defines.entity_status_diode.red, label = {"arrakis-message.status-wormsign", left}}
    end
  elseif h.careful_wait then
    key = "careful"
    status = {diode = defines.entity_status_diode.yellow, label = {"arrakis-message.status-careful-wait"}}
  elseif h.alarm_unrest then
    key = "unrest"
    status = {diode = defines.entity_status_diode.yellow, label = {"arrakis-message.status-unrest"}}
  elseif state == "mobile" then
    key = "none"
  elseif state == "deployed" then
    local name = h.status or "harvesting"
    key = "deployed:" .. name
    status = {diode = defines.entity_status_diode[STATUS_DIODE[name]], label = {"arrakis-message." .. STATUS_KEY[name]}}
  else
    local diode = state == "docked" and "green" or "yellow"
    key = "state:" .. state
    status = {diode = defines.entity_status_diode[diode], label = {"arrakis-message.state-" .. state}}
  end
  if h.status_written == key then return end
  h.status_written = key
  if status then
    entity.custom_status = status
  elseif entity.custom_status then
    entity.custom_status = nil
  end
end

-- Nur die eigenen Alarme (Symbol Spice-Sand, AlertFilter mit icon, A23 concepts.d.ts:130–138); sonst löschte
-- „Laderaum voll ist vorbei“ auch das Wurmzeichen (docs/plan-3d1.md 4.1).
local function remove_alerts(entity)
  for _, player in pairs(entity.force.connected_players) do
    player.remove_alert{entity = entity, type = defines.alert_type.custom, icon = {type = "item", name = SPICE}}
  end
end

local function add_alerts(entity, status)
  local message = {"arrakis-message.alert-" .. string.gsub(status, "_", "-")}
  for _, player in pairs(entity.force.connected_players) do
    player.add_custom_alert(entity, {type = "item", name = SPICE}, message, true)
  end
end

-- Status setzen; schreibt custom_status und Alarme nur bei einer Änderung (Plan 4.5 Schritt 8).
local function set_status(h, status)
  if h.status == status then return end
  local old = h.status
  h.status = status
  local entity = h.entity
  if not entity.valid then return end
  if old and ALERT[old] then remove_alerts(entity) end
  if status and ALERT[status] then add_alerts(entity, status) end
  if h.state == "deployed" then write_custom_status(h) end
end

-- Alarm am Ernter (docs/plan-3d1.md 4.1): kind "hunt" mit value = eta_tick oder nil und safe = true oder nil
-- (Wurmzeichen, scripts/worms.lua), kind "unrest" mit value = true oder nil (Der Sand bebt, scripts/vibration.lua).
-- Schreibt über write_custom_status, also nur bei einer Änderung von Text oder Sekunde.
function lib.set_alarm(h, kind, value, safe)
  if not h then return end
  if kind == "hunt" then
    h.alarm_hunt_eta = value
    h.alarm_hunt_safe = (value and safe) and true or nil
  elseif kind == "unrest" then
    h.alarm_unrest = value and true or nil
  end
  write_custom_status(h)
end

-- Status neu werten, z. B. nachdem der Vorsichtsmodus careful_wait geändert hat (scripts/vibration.lua).
function lib.refresh_status(h)
  if h then write_custom_status(h) end
end

-- Proxy-Ziele (Annahme und zugeordnete Stutzen) -----------------------------------------------------

local function clear_targets(intake_record)
  local intake = intake_record.entity
  if intake and intake.valid then intake.proxy_target_entity = nil end
  for _, nozzle_un in pairs(intake_record.nozzles) do
    local nozzle = storage.nozzles[nozzle_un]
    if nozzle and nozzle.entity.valid then nozzle.entity.proxy_target_entity = nil end
  end
end

local function set_targets(intake_record, entity)
  local intake = intake_record.entity
  if intake and intake.valid then
    intake.proxy_target_entity = entity
    intake.proxy_target_inventory = defines.inventory.car_trunk
  end
  for _, nozzle_un in pairs(intake_record.nozzles) do
    local nozzle = storage.nozzles[nozzle_un]
    if nozzle and nozzle.entity.valid then
      nozzle.entity.proxy_target_entity = entity
      nozzle.entity.proxy_target_inventory = defines.inventory.fuel
    end
  end
end

-- Setzt die Proxy-Ziele einer Annahme und ihrer Stutzen aus storage neu (angedockter Ernter oder keiner).
function lib.apply_targets(intake_record)
  local h = intake_record.docked and storage.harvesters[intake_record.docked]
  if h and h.state == "docked" and h.entity.valid then
    set_targets(intake_record, h.entity)
  else
    clear_targets(intake_record)
  end
end

-- Treibstoff ------------------------------------------------------------------------------------

-- Genau ein Item gleicher Sorte und Qualität aus dem Treibstoffinventar in den Brenner legen.
local function load_fuel(entity, burner)
  local inventory = burner.inventory
  for i = 1, #inventory do
    local stack = inventory[i]
    if stack.valid_for_read then
      local name, quality = stack.name, stack.quality.name
      local fuel_value = stack.prototype.fuel_value
      if fuel_value > 0 and inventory.remove{name = name, quality = quality, count = 1} == 1 then
        burner.currently_burning = {name = name, quality = quality}
        burner.remaining_burning_fuel = fuel_value
        stats(entity).on_flow({name = name, quality = quality}, -1)
        return true
      end
    end
  end
  return false
end

-- Zieht joules vom Brenner ab und lädt dabei Items nach; gibt die tatsächlich abgezogene Energie zurück.
local function consume(entity, joules)
  local burner = entity.burner
  if not burner then return 0 end
  local need = joules
  for _ = 1, 1000 do
    local remaining = burner.currently_burning and burner.remaining_burning_fuel or 0
    if remaining >= need then
      burner.remaining_burning_fuel = remaining - need
      return joules
    end
    if remaining > 0 then
      need = need - remaining
      burner.remaining_burning_fuel = 0
    end
    if not load_fuel(entity, burner) then break end
  end
  return joules - need
end

local function has_fuel(entity)
  local burner = entity.burner
  if not burner then return false end
  if burner.currently_burning and burner.remaining_burning_fuel > 0 then return true end
  return not burner.inventory.is_empty()
end

-- Wirkt fuel_top_speed_multiplier bei Autos (ab 2.1.13)? Einmal je Lua-Sitzung aus script.active_mods gelesen,
-- nie in storage: Die base-Version ändert sich nur, wenn die Mods neu geladen werden.
local top_speed_acts

local function fuel_top_speed_acts()
  if top_speed_acts == nil then
    top_speed_acts = helpers.compare_versions(script.active_mods["base"], "2.1.13") >= 0
  end
  return top_speed_acts
end

-- Tempo-Ausgleich (Plan 4.6) nach currently_burning, schreibt nur bei Änderung. Modell aus T2/T2b: Endtempo
-- ∝ √(a · effectivity_modifier) · t mit a = Beschleunigung, t = Höchsttempo des Brennstoffs (je plus Qualitätsbonus).
-- t wirkt bei Autos erst ab 2.1.13 linear (vorher wie t = 1). Ausgleich min(1, 1/(a · t²)), vor 2.1.13 min(1, 1/a):
-- Kein Brennstoff fährt schneller als Kohle (a = t = 1, etwa 1.45 Kacheln/s); der Deckel bleibt nur die Sicherung.
function lib.apply_fuel_normalization(entity)
  if not (entity and entity.valid) then return nil end
  local burner = entity.burner
  local burning = burner and burner.currently_burning
  if not burning then return nil end
  local item, quality = burning.name, burning.quality
  local level = quality and quality.level or 0
  local a = item.fuel_acceleration_multiplier + level * item.fuel_acceleration_multiplier_quality_bonus
  local k = a
  if fuel_top_speed_acts() then
    local t = item.fuel_top_speed_multiplier + level * item.fuel_top_speed_multiplier_quality_bonus
    k = a * t * t
  end
  local target = k > 0 and math.min(1, 1 / k) or 1
  local harvesters = storage.harvesters
  local h = harvesters and harvesters[entity.unit_number]
  if h then h.fuel_key = item.name .. "/" .. (quality and quality.name or "normal") end
  if math.abs(entity.effectivity_modifier - target) > 1e-6 then entity.effectivity_modifier = target end
  return target
end

-- Abbausperre -----------------------------------------------------------------------------------

-- minable_flag neu werten (Plan 4.7): false im Auf-/Abbau und auf Sand einer Ernte-Oberfläche; gibt den Wert zurück.
function lib.refresh_minable(h)
  local entity = h.entity
  if not entity.valid then return nil end
  local position = entity.position
  h.minable_pos = {x = position.x, y = position.y}
  local locked = LOCKED[h.state] or (terrain.harvest_allowed(entity.surface) and terrain.has_sand_under(entity))
  local flag = not locked
  if entity.minable_flag ~= flag then entity.minable_flag = flag end
  return flag
end

-- Zustände --------------------------------------------------------------------------------------

-- Gemeinsamer Weg zurück nach mobile: Abbau und Anzeigen aus, entsperren, Sperre und Ausgleich neu werten.
local function set_mobile(h)
  local un = h.un
  storage.timers[un] = nil
  destroy_render(h, "ring")
  destroy_render(h, "frame")
  h.resources = {}
  h.res_index = 1
  h.timer_start = nil
  h.timer_end = nil
  h.deploy_pos = nil
  h.deploy_surface = nil
  h.still_since = nil
  h.careful_packing = nil
  h.last_tick = game.tick
  h.state = "mobile"
  set_status(h, nil)
  local entity = h.entity
  if not entity.valid then return end
  unlock(entity)
  write_custom_status(h)
  lib.refresh_minable(h)
  lib.apply_fuel_normalization(entity)
  if entity.get_driver() then storage.driven[un] = entity end
end

-- Datensatz zur Entity oder nil.
function lib.get(entity)
  if not (entity and entity.valid) then return nil end
  local harvesters = storage.harvesters
  return harvesters and harvesters[entity.unit_number]
end

-- Ernter eintragen (mobil, entsperrt) und für on_object_destroyed anmelden; gibt den Datensatz zurück.
function lib.register(entity)
  if not is_harvester(entity) then return nil end
  local un = entity.unit_number
  local h = storage.harvesters[un]
  if h then return h end
  h =
  {
    un = un,
    entity = entity,
    state = "mobile",
    resources = {},
    res_index = 1,
    progress = 0,
    drain_rest = 0,
    prod_rest = 0,
    last_tick = game.tick,
    renders = {},
    last_toggle_tick = 0,
    -- Phase 3d1 (docs/plan-3d1.md 4.2)
    careful = false,
    vib_weight = 0,
    vib_sand = false
  }
  storage.harvesters[un] = h
  storage.reg[script.register_on_object_destroyed(entity)] = {kind = "harvester", un = un}
  unlock(entity)
  if entity.custom_status then entity.custom_status = nil end
  lib.refresh_minable(h)
  lib.apply_fuel_normalization(entity)
  if entity.get_driver() or not is_still(entity) then storage.driven[un] = entity end
  return h
end

-- Aufbauen beginnen (5 s); gibt true oder false plus Grund "busy"|"moving"|"not-allowed"|"no-spice" zurück.
function lib.deploy(h)
  local entity = h and h.entity
  if not (entity and entity.valid) then return false, "busy" end
  if h.state ~= "mobile" then return false, "busy" end
  if not is_still(entity) then return false, "moving" end
  local surface = entity.surface
  if not terrain.harvest_allowed(surface) then return false, "not-allowed" end
  local position = entity.position
  if surface.count_entities_filtered{area = field_area(position), name = SPICE, limit = 1} == 0 then
    return false, "no-spice"
  end
  local tick = game.tick
  storage.driven[h.un] = nil
  h.state = "deploying"
  h.timer_start = tick
  h.timer_end = tick + lib.DEPLOY_TICKS
  h.deploy_pos = {x = position.x, y = position.y}
  h.deploy_surface = surface.index
  h.still_since = nil
  h.last_tick = tick
  lock(entity)
  lib.refresh_minable(h)
  storage.timers[h.un] = true
  draw_ring(h, tick)
  write_custom_status(h)
  return true
end

-- Ende des Aufbauens: Feld in den Cache, Rahmen zeichnen, Status „Erntet“.
local function finish_deploy(h)
  local entity = h.entity
  local position = entity.position
  local surface = entity.surface
  local area = field_area(position)
  storage.timers[h.un] = nil
  destroy_render(h, "ring")
  h.resources = surface.find_entities_filtered{area = area, name = SPICE}
  h.res_index = 1
  h.timer_start = nil
  h.timer_end = nil
  h.deploy_pos = {x = position.x, y = position.y}
  h.deploy_surface = surface.index
  h.last_tick = game.tick
  h.state = "deployed"
  draw_frame(h, area)
  h.status = nil
  set_status(h, "harvesting")
end

-- Einpacken beginnen (10 s): Abbau stoppt sofort, Rahmen weg, Ring an. Nur aus deployed.
function lib.pack(h)
  if not (h and h.state == "deployed" and h.entity.valid) then return false end
  local tick = game.tick
  h.state = "packing"
  set_status(h, nil)
  h.resources = {}
  h.res_index = 1
  destroy_render(h, "frame")
  h.timer_start = tick
  h.timer_end = tick + lib.PACK_TICKS
  h.last_tick = tick
  storage.timers[h.un] = true
  draw_ring(h, tick)
  write_custom_status(h)
  lib.refresh_minable(h)
  return true
end

-- Sofort nach mobile (Abbruch beim Aufbauen, Teleport, Klon); ohne Proxy-Ziele, dafür gibt es undock.
function lib.to_mobile(h)
  if h.state == "docked" then return lib.undock(h) end
  set_mobile(h)
  return true
end

-- Andocken an eine Annahme (Datensatz aus storage.intakes): sperren, dann Proxy-Ziele setzen.
function lib.dock(h, intake_record)
  local entity = h and h.entity
  local intake = intake_record and intake_record.entity
  if not (entity and entity.valid and intake and intake.valid) then return false end
  if h.state ~= "mobile" or intake_record.docked or intake_record.bad then return false end
  local intake_un = intake.unit_number
  storage.driven[h.un] = nil
  h.state = "docked"
  h.dock = intake_un
  h.undocked_from = nil
  h.still_since = nil
  h.careful_wait = nil
  h.careful_pos = nil
  h.careful_packing = nil
  h.last_tick = game.tick
  intake_record.docked = h.un
  lock(entity)
  set_targets(intake_record, entity)
  write_custom_status(h)
  lib.refresh_minable(h)
  return true
end

-- Abdocken: zuerst Proxy-Ziele löschen, dann entsperren; undocked_from verhindert sofortiges Wiederandocken.
function lib.undock(h)
  if not (h and h.state == "docked") then return false end
  local intake_un = h.dock
  local intake_record = intake_un and storage.intakes[intake_un]
  if intake_record then
    clear_targets(intake_record)
    if intake_record.docked == h.un then intake_record.docked = nil end
  end
  h.dock = nil
  h.undocked_from = intake_un
  set_mobile(h)
  return true
end

-- Taste oder Knopf (Plan 4.3). player darf nil sein (Prüfstand). Gibt true zurück, wenn sich der Zustand ändert.
function lib.toggle(entity, player)
  if not is_harvester(entity) then return false end
  if player and player.force.index ~= entity.force.index then
    hint(player, entity, "hint-foreign")
    return false
  end
  local h = lib.get(entity) or lib.register(entity)
  local tick = game.tick
  if h.last_toggle_tick ~= 0 and tick - h.last_toggle_tick < lib.DEBOUNCE then return false end
  h.last_toggle_tick = tick
  -- Der Spieler übernimmt: Ein wartender Vorsichtsmodus baut nicht mehr selbst auf (docs/plan-3d1.md 4.11).
  if h.careful_wait then
    h.careful_wait = nil
    write_custom_status(h)
  end
  local state = h.state
  if state == "mobile" then
    local ok, reason = lib.deploy(h)
    if not ok then hint(player, entity, "hint-" .. reason) end
    return ok
  elseif state == "deploying" then
    set_mobile(h)
    return true
  elseif state == "deployed" then
    return lib.pack(h)
  elseif state == "packing" then
    hint(player, entity, "hint-packing")
    return false
  elseif state == "docked" then
    return lib.undock(h)
  elseif state == "carried" then
    hint(player, entity, "hint-carried")
    return false
  end
  return false
end

-- Anheben (docs/plan-3c.md 4.1, 4.6 Schritt 4): Notstart nach mobile (angedockt → abdocken), dann carried und
-- gesperrt. carrier_un ist der Flieger (nil: wartet ohne Träger), lift_pos der Abhebepunkt
-- {surface = surface_index, x, y} (nil: unbekannt, dann gilt bei der Landesuche nur der Startpunkt der Force).
-- speed = 0 setzt lock(): Ein angekoppelt fahrender Ernter rollte nach dem Absetzen sonst weiter.
function lib.lift(h, carrier_un, lift_pos)
  local entity = h and h.entity
  if not (entity and entity.valid) then return false end
  if h.state ~= "carried" then lib.to_mobile(h) end
  local un = h.un
  h.state = "carried"
  h.carried_by = carrier_un
  h.lift_pos = lift_pos
  h.undocked_from = nil
  h.still_since = nil
  h.careful_wait = nil
  h.careful_pos = nil
  h.careful_packing = nil
  storage.driven[un] = nil
  storage.timers[un] = nil
  lock(entity)
  write_custom_status(h)
  lib.refresh_minable(h)
  return true
end

-- Absetzen (docs/plan-3c.md 4.1, 4.8 Schritt 3): Träger und Abhebepunkt vergessen, dann wie jeder Weg nach
-- mobile (entsperrt, Abbausperre und Tempo-Ausgleich am neuen Ort, last_tick). undocked_from = nil: Steht er an
-- einer freien Annahme, dockt er nach 2 s Stillstand an (scripts/intake.lua, dock_check).
function lib.land(h)
  if not h then return false end
  h.carried_by = nil
  h.lift_pos = nil
  h.undocked_from = nil
  set_mobile(h)
  return true
end

-- Zustand und Status als LocalisedString (Fenster, Prüfstand).
function lib.state_text(h)
  local state = h.state
  if state == "deploying" or state == "packing" then
    local left = math.max(0, math.ceil(((h.timer_end or game.tick) - game.tick) / 60))
    return {"arrakis-message.state-" .. state .. "-time", left}
  elseif state == "deployed" then
    return {"arrakis-message.state-deployed", {"arrakis-message." .. STATUS_KEY[h.status or "harvesting"]}}
  end
  return {"arrakis-message.state-" .. state}
end

-- Zentraler Entfernen-Weg (Tod, Abbau, Zerstören, on_object_destroyed): Proxy-Ziele zuerst löschen.
function lib.remove(un)
  local h = storage.harvesters[un]
  if not h then return end
  local intake_record = h.dock and storage.intakes[h.dock]
  if intake_record then
    clear_targets(intake_record)
    if intake_record.docked == un then intake_record.docked = nil end
  end
  destroy_render(h, "ring")
  destroy_render(h, "frame")
  if h.entity.valid and h.status and ALERT[h.status] then remove_alerts(h.entity) end
  storage.driven[un] = nil
  storage.timers[un] = nil
  storage.harvesters[un] = nil
end

-- Abbau (Plan 4.5) ----------------------------------------------------------------------------------

-- Gültige Ressource am Zeiger; ungültige fliegen aus dem Cache. Ist er leer und refill gesetzt, einmal neu suchen.
local function current_resource(h, refill)
  local list = h.resources
  while #list > 0 do
    if h.res_index > #list or h.res_index < 1 then h.res_index = 1 end
    local resource = list[h.res_index]
    if resource.valid then return resource end
    table.remove(list, h.res_index)
  end
  if refill and h.deploy_pos then
    local surface = h.entity.surface
    h.resources = surface.find_entities_filtered{area = field_area(h.deploy_pos), name = SPICE}
    h.res_index = 1
    return current_resource(h, false)
  end
  return nil
end

-- Feldabzug reihum je 1 Einheit; erschöpfte Ressourcen erst aus dem Cache nehmen, dann deplete().
local function drain(h, amount)
  h.drain_rest = h.drain_rest + amount
  while h.drain_rest >= 1 do
    local resource = current_resource(h, false)
    if not resource then
      h.drain_rest = h.drain_rest - math.floor(h.drain_rest)
      return
    end
    h.drain_rest = h.drain_rest - 1
    if resource.amount <= 1 then
      table.remove(h.resources, h.res_index)
      resource.deplete()
    else
      resource.amount = resource.amount - 1
      h.res_index = h.res_index + 1
    end
  end
end

local function moved(h)
  local entity = h.entity
  local pos = h.deploy_pos
  if not pos then return false end
  if entity.surface.index ~= h.deploy_surface then return true end
  local position = entity.position
  local dx, dy = position.x - pos.x, position.y - pos.y
  return dx * dx + dy * dy > lib.MOVE_LIMIT * lib.MOVE_LIMIT
end

-- Ein Abbautakt für einen aufgebauten Ernter. Gibt die eingefügte Menge Spice-Sand zurück.
local function mine(h, tick)
  local entity = h.entity
  if moved(h) then
    set_mobile(h)
    return 0
  end
  local dt = math.min((tick - (h.last_tick or tick)) / 60, lib.MAX_DT)
  h.last_tick = tick
  if dt <= 0 then return 0 end
  local trunk = entity.get_inventory(defines.inventory.car_trunk)
  if not (trunk and trunk.can_insert{name = SPICE, count = 1}) then
    set_status(h, "trunk_full")
    return 0
  end
  if not current_resource(h, true) then
    set_status(h, "field_empty")
    return 0
  end
  if not has_fuel(entity) then
    set_status(h, "no_fuel")
    return 0
  end
  h.progress = h.progress + lib.RATE * dt
  local n = math.floor(h.progress)
  h.progress = h.progress - n
  local bonus = entity.force.mining_drill_productivity_bonus
  local total = n * (1 + bonus) + h.prod_rest
  local k = math.floor(total)
  h.prod_rest = total - k
  local inserted = 0
  if k > 0 then inserted = trunk.insert{name = SPICE, count = k} end
  if inserted > 0 then
    stats(entity).on_flow(SPICE, inserted)
    drain(h, lib.DRAIN * inserted / (1 + bonus))
  end
  consume(entity, lib.POWER * dt)
  lib.apply_fuel_normalization(entity)
  set_status(h, "harvesting")
  return inserted
end

-- Ein Abbautakt jetzt (game.tick) für einen Datensatz im Zustand deployed; gibt die eingefügte Menge zurück.
function lib.mine_once(h)
  if not (h and h.state == "deployed" and h.entity.valid) then return 0 end
  return mine(h, game.tick)
end

-- Zieht joules vom Brenner der Entity ab (wie beim Ernten, lädt Items nach); gibt die abgezogene Energie zurück.
function lib.consume(entity, joules)
  if not is_harvester(entity) then return 0 end
  return consume(entity, joules)
end

-- Erntefeld als {{x1, y1}, {x2, y2}} um eine Position.
lib.field_area = field_area

-- Aufbau-/Einpack-Uhr eines Datensatzes nachführen und bei Ablauf abschließen (wie der 10-Tick-Takt).
local function update_timer(h, tick)
  if not TIMED[h.state] then
    storage.timers[h.un] = nil
    return
  end
  if moved(h) then
    set_mobile(h)
  elseif tick >= h.timer_end then
    if h.state == "deploying" then finish_deploy(h) else set_mobile(h) end
  else
    draw_ring(h, tick)
  end
end

-- Uhr eines Datensatzes jetzt prüfen (game.tick); für den Prüfstand.
function lib.update_timer(h)
  if h and h.entity.valid then update_timer(h, game.tick) end
end

-- Takte ------------------------------------------------------------------------------------------

-- Tempo-Deckel jeden Tick, nur für storage.driven; leere Liste kostet einen Vergleich.
local function on_tick(event)
  local driven = storage.driven
  if not driven or next(driven) == nil then return end
  local cap = lib.CAP / 60
  local reset = lib.RESET / 60
  local check = event.tick % 10 == 0
  local harvesters = storage.harvesters
  for un, entity in pairs(driven) do
    if not entity.valid then
      driven[un] = nil
    else
      local speed = entity.speed
      if speed > cap then
        entity.speed = reset
      elseif speed < -cap then
        entity.speed = -reset
      end
      if check then
        local h = harvesters[un]
        if not h or h.state ~= "mobile" or (not entity.get_driver() and is_still(entity)) then
          driven[un] = nil
        else
          lib.apply_fuel_normalization(entity)
        end
      end
    end
  end
end

local function on_nth_tick_10(event)
  local timers = storage.timers
  if next(timers) == nil then return end
  local harvesters = storage.harvesters
  for un in pairs(timers) do
    local h = harvesters[un]
    if not h then
      timers[un] = nil
    elseif not h.entity.valid then
      lib.remove(un)
    else
      update_timer(h, event.tick)
    end
  end
end

-- Abbau für alle aufgebauten Ernter; fahrende mobile Ernter für den Tempo-Deckel eintragen.
local function on_nth_tick_30(event)
  local tick = event.tick
  local driven = storage.driven
  for un, h in pairs(storage.harvesters) do
    local entity = h.entity
    if not entity.valid then
      lib.remove(un)
    elseif h.state == "deployed" then
      mine(h, tick)
    elseif h.state == "mobile" and not driven[un] and not is_still(entity) then
      driven[un] = entity
    end
  end
end

-- Abbausperre für ruhende mobile Ernter, deren Position sich seit der letzten Wertung geändert hat.
local function on_nth_tick_60()
  for un, h in pairs(storage.harvesters) do
    if h.state == "mobile" then
      local entity = h.entity
      if not entity.valid then
        lib.remove(un)
      elseif is_still(entity) then
        local position, last = entity.position, h.minable_pos
        if not last or math.abs(position.x - last.x) > 0.01 or math.abs(position.y - last.y) > 0.01 then
          lib.refresh_minable(h)
        end
      end
    end
  end
end

-- Ereignisse ---------------------------------------------------------------------------------------

local function on_built(event)
  local entity = event.entity
  if is_harvester(entity) then lib.register(entity) end
end

-- Klon: startet immer mobil und entsperrt, egal in welchem Zustand die Quelle war.
local function on_cloned(event)
  local entity = event.destination
  if is_harvester(entity) then lib.register(entity) end
end

local function on_teleported(event)
  local entity = event.entity
  if not is_harvester(entity) then return end
  local h = lib.get(entity)
  if not h then
    lib.register(entity)
  elseif h.state == "carried" then
    -- Getragen: nichts tun, sonst risse to_mobile ihn los. Landet ein fremdes Skript ihn außerhalb der Ablage,
    -- holt scripts/flyer.lua ihn herunter (docs/plan-3c.md 4.4, care Fall b).
    return
  elseif h.state == "mobile" then
    lib.refresh_minable(h)
    lib.apply_fuel_normalization(entity)
  else
    lib.to_mobile(h)
  end
end

local function on_removed(event)
  local entity = event.entity
  if is_harvester(entity) then lib.remove(entity.unit_number) end
end

local function on_object_destroyed(event)
  local reg = storage.reg[event.registration_number]
  if not (reg and reg.kind == "harvester") then return end
  storage.reg[event.registration_number] = nil
  lib.remove(reg.un)
end

local function on_driving_changed(event)
  local entity = event.entity
  if not is_harvester(entity) then return end
  local h = lib.get(entity) or lib.register(entity)
  local player = game.get_player(event.player_index)
  if player and player.vehicle == entity then
    if h.state == "mobile" then storage.driven[h.un] = entity end
    lib.apply_fuel_normalization(entity)
  else
    lib.refresh_minable(h)
  end
end

-- Gesperrte Ernter (minable_flag false) dürfen nicht zum Abriss markiert bleiben (Flucht per Roboter).
local function on_marked_for_deconstruction(event)
  local entity = event.entity
  if not is_harvester(entity) then return end
  local h = lib.get(entity)
  if h then lib.refresh_minable(h) end
  if entity.minable_flag then return end
  local player = event.player_index and game.get_player(event.player_index)
  if player then
    entity.cancel_deconstruction(player.force, player)
  else
    entity.cancel_deconstruction(entity.force)
  end
end

-- Taste: zuerst das Fahrzeug, in dem der Spieler sitzt, sonst die Auswahl (auch aus der Kartenansicht).
local function on_toggle_key(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  local entity = player.vehicle
  if not is_harvester(entity) then
    entity = player.selected
    if not is_harvester(entity) then return end
  end
  if entity.force.index ~= player.force.index then return end
  lib.toggle(entity, player)
end

lib.events =
{
  [defines.events.on_tick] = on_tick,
  [defines.events.on_built_entity] = on_built,
  [defines.events.on_robot_built_entity] = on_built,
  [defines.events.on_space_platform_built_entity] = on_built,
  [defines.events.script_raised_built] = on_built,
  [defines.events.script_raised_revive] = on_built,
  [defines.events.on_entity_cloned] = on_cloned,
  [defines.events.script_raised_teleported] = on_teleported,
  [defines.events.on_entity_died] = on_removed,
  [defines.events.on_player_mined_entity] = on_removed,
  [defines.events.on_robot_mined_entity] = on_removed,
  [defines.events.on_space_platform_mined_entity] = on_removed,
  [defines.events.script_raised_destroy] = on_removed,
  [defines.events.on_object_destroyed] = on_object_destroyed,
  [defines.events.on_player_driving_changed_state] = on_driving_changed,
  [defines.events.on_marked_for_deconstruction] = on_marked_for_deconstruction,
  [TOGGLE_INPUT] = on_toggle_key
}

lib.on_nth_tick =
{
  [10] = on_nth_tick_10,
  [30] = on_nth_tick_30,
  [60] = on_nth_tick_60
}

-- Nach Mod-Änderungen: Datensätze ohne gültige Entity aufräumen (migrate.lua hat storage schon angelegt).
lib.on_configuration_changed = function()
  for un, h in pairs(storage.harvesters) do
    if not h.entity.valid then lib.remove(un) end
  end
  for un, entity in pairs(storage.driven) do
    if not entity.valid then storage.driven[un] = nil end
  end
end

return lib
