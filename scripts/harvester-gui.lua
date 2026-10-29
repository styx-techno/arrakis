-- Relatives Fenster am Fahrzeugfenster des Spice-Ernters (Phase 3b, Plan 4.9): Zustand, Laderaum,
-- Treibstoff und ein Knopf für Aufbauen/Einpacken/Abdocken (gleichwertig zur Taste Umschalt+H).
-- Bibliothek für __core__/lualib/event_handler. Offene Fenster stehen in storage.gui_open[player_index] = un.
-- Getragen (Phase 3c, docs/plan-3c.md 4.1): Knopf „Wird getragen“ gesperrt; der 30-Tick-Takt schließt das Fenster.
-- Phase 3d1 (docs/plan-3d1.md 4.1, 4.11): Vibration und Wärme, Countdown eines Wurmzeichens, Kontrollkästchen
-- „Vorsichtsmodus“ (ruft vibration.set_careful) und dessen Warte-Zeile. Werte aus dem Datensatz (Stand des letzten
-- 60-Tick-Takts); ohne vib_key ist die Wärme 0.

local harvester = require("scripts.harvester")
local vibration_lib = require("scripts.vibration")

local gui = {}

local SPICE = "spice-sand"
local FRAME = "arrakis_harvester_frame"
local BUTTON = "arrakis_harvester_toggle"
local CAREFUL = "arrakis_careful"

-- Beschriftung des Knopfs je Zustand; im Einpacken und getragen gesperrt.
local BUTTON_CAPTION =
{
  mobile = "gui-deploy",
  deploying = "gui-abort",
  deployed = "gui-pack",
  packing = "gui-pack",
  docked = "gui-undock",
  carried = "gui-carried"
}
local BUTTON_LOCKED = {packing = true, carried = true}

local function destroy(player)
  local frame = player.gui.relative[FRAME]
  if frame then frame.destroy() end
end

-- Zeit m:ss aus Ticks (aufgerundet auf ganze Sekunden).
local function mmss(ticks)
  local s = math.max(0, math.ceil(ticks / 60))
  return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- Vibration, Wärme, Countdown und Vorsichtsmodus (docs/plan-3d1.md 4.1).
local function update_worms(frame, h)
  if not frame.arrakis_vibration then return end
  local tick = game.tick
  local entity = h.entity
  local s = entity.surface.index
  local key = h.vib_key
  local heat = key and vibration_lib.near_key(storage.vib.heat[s], key) or 0
  local resting = key and vibration_lib.resting(s, vibration_lib.sector_of_key(key))
  local lurk = storage.hunts.lurk and storage.hunts.lurk[s]
  local lurking = key and lurk and lurk[vibration_lib.sector_of_key(key)]
  local fw = h.fleet_wait
  if fw and (fw.reason == "reserve" or not fw.x) then
    -- Reserve der Flottenleitung (0.12.0): wartet an der Leitstelle auf einen freien Platz.
    frame.arrakis_vibration.caption = {"arrakis-message.gui-fleet-wait-reserve"}
  elseif fw and fw.reason == "recall" then
    frame.arrakis_vibration.caption = {"arrakis-message.gui-fleet-wait-recall"}
  elseif fw then
    -- Gerettet und an der Leitstelle abgestellt (0.11.0, scripts/fleet.lua): Wie lange lauert der Wurm am Feld noch?
    local field = storage.hunts.lurk and storage.hunts.lurk[fw.surface]
    local _, sector = vibration_lib.key_of({x = fw.x, y = fw.y})
    local until_tick = field and field[sector]
    if until_tick and until_tick > tick then
      frame.arrakis_vibration.caption = {"arrakis-message.gui-fleet-wait-lurk", mmss(until_tick - tick)}
    else
      frame.arrakis_vibration.caption = {"arrakis-message.gui-fleet-wait"}
    end
  elseif lurking and lurking > tick then
    frame.arrakis_vibration.caption = {"arrakis-message.gui-vibration-lurk", mmss(lurking - tick)}
  elseif resting then
    frame.arrakis_vibration.caption = {"arrakis-message.gui-vibration-rest", mmss(resting - tick)}
  else
    frame.arrakis_vibration.caption = {"arrakis-message.gui-vibration", h.vib_weight or 0, math.floor(heat + 0.5)}
  end
  local hunt = frame.arrakis_hunt
  if h.alarm_hunt_eta then
    local left = math.max(0, math.ceil((h.alarm_hunt_eta - tick) / 60))
    hunt.caption = {"arrakis-message." .. (h.alarm_hunt_safe and "status-wormsign-safe" or "gui-hunt"), left}
    hunt.visible = true
  else
    hunt.caption = ""
    hunt.visible = false
  end
  frame[CAREFUL].state = h.careful == true
  local wait = frame.arrakis_careful_wait
  if h.careful_wait then
    wait.caption = {"arrakis-message.gui-careful-wait", math.floor(heat + 0.5)}
    wait.visible = true
  else
    wait.caption = ""
    wait.visible = false
  end
end

-- Inhalt eines offenen Fensters auf den Stand des Datensatzes bringen.
local function update(player, h)
  local frame = player.gui.relative[FRAME]
  if not frame then return end
  local entity = h.entity
  frame.arrakis_state.caption = {"arrakis-message.gui-state", harvester.state_text(h)}
  local trunk = entity.get_inventory(defines.inventory.car_trunk)
  local count = trunk and trunk.get_item_count(SPICE) or 0
  local capacity = trunk and #trunk * prototypes.item[SPICE].stack_size or 0
  frame.arrakis_trunk.caption = {"arrakis-message.gui-trunk", count, capacity}
  frame.arrakis_trunk_bar.value = capacity > 0 and math.min(1, count / capacity) or 0
  local burner = entity.burner
  local items, rest = 0, 0
  if burner then
    items = burner.inventory.get_item_count()
    if burner.currently_burning then rest = burner.remaining_burning_fuel end
  end
  frame.arrakis_fuel.caption = {"arrakis-message.gui-fuel", items, string.format("%.1f", rest / 1000000)}
  update_worms(frame, h)
  local button = frame[BUTTON]
  button.caption = {"arrakis-message." .. (BUTTON_CAPTION[h.state] or "gui-deploy")}
  button.enabled = not BUTTON_LOCKED[h.state]
end

local function build(player, h)
  destroy(player)
  local frame = player.gui.relative.add{
    type = "frame",
    name = FRAME,
    caption = {"arrakis-message.gui-title"},
    direction = "vertical",
    anchor =
    {
      gui = defines.relative_gui_type.car_gui,
      position = defines.relative_gui_position.right,
      names = {harvester.NAME}
    }
  }
  frame.add{type = "label", name = "arrakis_state"}
  frame.add{type = "label", name = "arrakis_trunk"}
  frame.add{type = "progressbar", name = "arrakis_trunk_bar"}
  frame.add{type = "label", name = "arrakis_fuel"}
  frame.add{type = "label", name = "arrakis_vibration"}
  frame.add{type = "label", name = "arrakis_hunt"}
  frame.add{type = "checkbox", name = CAREFUL, caption = {"arrakis-message.gui-careful"},
    tooltip = {"arrakis-message.gui-careful-tooltip"}, state = h.careful == true}
  frame.add{type = "label", name = "arrakis_careful_wait"}
  frame.add{type = "button", name = BUTTON, tooltip = {"arrakis-message.gui-button-tooltip"}}
  update(player, h)
end

local function close(player_index)
  storage.gui_open[player_index] = nil
  local player = game.get_player(player_index)
  if player then destroy(player) end
end

-- Datensatz des Ernters, dessen Fenster der Spieler offen hat (storage.gui_open, sonst player.opened).
local function open_record(player)
  local h = storage.harvesters[storage.gui_open[player.index] or 0]
  if h and h.entity.valid then return h end
  local opened = player.opened
  if opened and type(opened) ~= "number" and opened.object_name == "LuaEntity" and opened.name == harvester.NAME then
    return harvester.get(opened) or harvester.register(opened)
  end
  return nil
end

local function on_gui_opened(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.name == harvester.NAME) then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local h = harvester.get(entity) or harvester.register(entity)
  if not h then return end
  storage.gui_open[player.index] = h.un
  build(player, h)
end

local function on_gui_closed(event)
  if not storage.gui_open[event.player_index] then return end
  local entity = event.entity
  if entity and entity.valid and entity.name ~= harvester.NAME then return end
  close(event.player_index)
end

local function on_gui_click(event)
  local element = event.element
  if not (element and element.valid and element.name == BUTTON) then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local h = open_record(player)
  if not h then return end
  harvester.toggle(h.entity, player)
  update(player, h)
end

-- Kontrollkästchen „Vorsichtsmodus“: Schalter am Ernter; abgelehnt (fremde Force) zeigt es wieder den alten Stand.
local function on_gui_checked_state_changed(event)
  local element = event.element
  if not (element and element.valid and element.name == CAREFUL) then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local h = open_record(player)
  if not h then return end
  vibration_lib.set_careful(h, element.state, player)
  update(player, h)
end

-- Offene Fenster auffrischen; Fenster zu verschwundenen, getragenen Erntern oder Spielern schließen.
local function on_nth_tick_30()
  local open = storage.gui_open
  if next(open) == nil then return end
  for player_index, un in pairs(open) do
    local player = game.get_player(player_index)
    local h = storage.harvesters[un]
    if not (player and player.connected and h and h.entity.valid and h.state ~= "carried"
        and player.gui.relative[FRAME]) then
      close(player_index)
    else
      update(player, h)
    end
  end
end

gui.events =
{
  [defines.events.on_gui_opened] = on_gui_opened,
  [defines.events.on_gui_closed] = on_gui_closed,
  [defines.events.on_gui_click] = on_gui_click,
  [defines.events.on_gui_checked_state_changed] = on_gui_checked_state_changed
}

gui.on_nth_tick =
{
  [30] = on_nth_tick_30
}

-- Nach Mod-Änderungen alle offenen Ernterfenster schließen: Ein alt gespeichertes Fenster hat die Elemente aus 3d1
-- nicht (docs/plan-3d1.md 4.1); beim nächsten Öffnen baut build es vollständig.
gui.on_configuration_changed = function()
  for player_index in pairs(storage.gui_open) do close(player_index) end
end

return gui
