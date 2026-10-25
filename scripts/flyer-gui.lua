-- Relatives Fenster am Fahrzeugfenster des Ornithopters (Phase 3c, docs/plan-3c.md 4.13): Zustand, Hauptknopf
-- Anheben/Abbrechen/Absetzen (gleichwertig zur Taste Umschalt+C und zur Verknüpfung), Fernbedienung und
-- „In den Ernter steigen“. Bibliothek für __core__/lualib/event_handler. Offene Fenster stehen in
-- storage.flyer_gui_open[player_index] = flyer_un. Muster wie scripts/harvester-gui.lua.

local flyer_lib = require("scripts.flyer")

local gui = {}

local FRAME = "arrakis_flyer_frame"
local CARRY = "arrakis_carry_toggle"
local REMOTE = "arrakis_give_remote"
local BOARD = "arrakis_board_harvester"

local function destroy(player)
  local frame = player.gui.relative[FRAME]
  if frame then frame.destroy() end
end

-- Beschriftung des Hauptknopfs: beladen → Absetzen, koppelt → Abbrechen, leer → Anheben.
local function carry_caption(record)
  if record.cargo then return "gui-drop" end
  if record.coupling then return "gui-abort" end
  return "gui-lift"
end

-- Inhalt eines offenen Fensters auf den Stand des Datensatzes bringen.
local function update(player, record)
  local frame = player.gui.relative[FRAME]
  if not frame then return end
  frame.arrakis_flyer_state.caption = {"arrakis-message.gui-state", flyer_lib.state_text(record)}
  frame[CARRY].caption = {"arrakis-message." .. carry_caption(record)}
  frame[BOARD].visible = flyer_lib.board_target(record, player) ~= nil
end

-- Anker spider_vehicle_gui mit names (A23 defines.d.ts:2114) [U18].
local function build(player, record)
  destroy(player)
  local frame = player.gui.relative.add{
    type = "frame",
    name = FRAME,
    caption = {"arrakis-message.gui-flyer-title"},
    direction = "vertical",
    anchor =
    {
      gui = defines.relative_gui_type.spider_vehicle_gui,
      position = defines.relative_gui_position.right,
      names = {flyer_lib.NAME}
    }
  }
  frame.add{type = "label", name = "arrakis_flyer_state"}
  frame.add{type = "button", name = CARRY, tooltip = {"arrakis-message.gui-carry-tooltip"}}
  frame.add{type = "button", name = REMOTE, caption = {"arrakis-message.gui-remote"}}
  frame.add{type = "button", name = BOARD, caption = {"arrakis-message.gui-board-harvester"}}
  update(player, record)
end

local function close(player_index)
  storage.flyer_gui_open[player_index] = nil
  local player = game.get_player(player_index)
  if player then destroy(player) end
end

-- Datensatz des Fliegers, dessen Fenster der Spieler offen hat (storage.flyer_gui_open, sonst player.opened).
local function open_record(player)
  local record = storage.flyers[storage.flyer_gui_open[player.index] or 0]
  if record and record.entity.valid then return record end
  local opened = player.opened
  if opened and type(opened) ~= "number" and opened.object_name == "LuaEntity" and opened.name == flyer_lib.NAME then
    return flyer_lib.get(opened) or flyer_lib.register(opened)
  end
  return nil
end

local function on_gui_opened(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.name == flyer_lib.NAME) then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local record = flyer_lib.get(entity) or flyer_lib.register(entity)
  if not record then return end
  storage.flyer_gui_open[player.index] = record.un
  build(player, record)
end

local function on_gui_closed(event)
  if not storage.flyer_gui_open[event.player_index] then return end
  local entity = event.entity
  if entity and entity.valid and entity.name ~= flyer_lib.NAME then return end
  close(event.player_index)
end

-- Knöpfe: Flieger ist das offene Fenster, keine Suche (Plan 4.5).
local function on_gui_click(event)
  local element = event.element
  if not (element and element.valid) then return end
  local name = element.name
  if name ~= CARRY and name ~= REMOTE and name ~= BOARD then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local record = open_record(player)
  if not record then return end
  if name == CARRY then
    flyer_lib.toggle_carry(record.entity, nil, player)
  elseif name == REMOTE then
    flyer_lib.give_remote(record, player)
  else
    flyer_lib.board_harvester(record, player)
  end
  -- Der Datensatz kann inzwischen fehlen (z. B. Flieger entfernt); dann schließt der 30-Tick-Takt.
  if storage.flyers[record.un] and record.entity.valid then update(player, record) end
end

-- Offene Fenster auffrischen (Countdown, Laderaum); Fenster zu verschwundenen Fliegern oder Spielern schließen.
local function on_nth_tick_30()
  local open = storage.flyer_gui_open
  if next(open) == nil then return end
  for player_index, un in pairs(open) do
    local player = game.get_player(player_index)
    local record = storage.flyers[un]
    if not (player and player.connected and record and record.entity.valid and player.gui.relative[FRAME]) then
      close(player_index)
    else
      update(player, record)
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
