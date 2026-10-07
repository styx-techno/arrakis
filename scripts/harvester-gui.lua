-- Relatives Fenster am Fahrzeugfenster des Spice-Ernters (Phase 3b, Plan 4.9): Zustand, Laderaum,
-- Treibstoff und ein Knopf für Aufbauen/Einpacken/Abdocken (gleichwertig zur Taste Umschalt+H).
-- Bibliothek für __core__/lualib/event_handler. Offene Fenster stehen in storage.gui_open[player_index] = un.

local harvester = require("scripts.harvester")

local gui = {}

local SPICE = "spice-sand"
local FRAME = "arrakis_harvester_frame"
local BUTTON = "arrakis_harvester_toggle"

-- Beschriftung des Knopfs je Zustand; im Einpacken gesperrt.
local BUTTON_CAPTION =
{
  mobile = "gui-deploy",
  deploying = "gui-abort",
  deployed = "gui-pack",
  packing = "gui-pack",
  docked = "gui-undock"
}

local function destroy(player)
  local frame = player.gui.relative[FRAME]
  if frame then frame.destroy() end
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
  local button = frame[BUTTON]
  button.caption = {"arrakis-message." .. (BUTTON_CAPTION[h.state] or "gui-deploy")}
  button.enabled = h.state ~= "packing"
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

-- Offene Fenster auffrischen; Fenster zu verschwundenen Erntern oder Spielern schließen.
local function on_nth_tick_30()
  local open = storage.gui_open
  if next(open) == nil then return end
  for player_index, un in pairs(open) do
    local player = game.get_player(player_index)
    local h = storage.harvesters[un]
    if not (player and player.connected and h and h.entity.valid and player.gui.relative[FRAME]) then
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
  [defines.events.on_gui_click] = on_gui_click
}

gui.on_nth_tick =
{
  [30] = on_nth_tick_30
}

return gui
