-- Fenster oben links (Phase 3d1, docs/plan-3d1.md 4.6 und 4.10): Schonfrist und Jagden der eigenen Force.
-- Bibliothek für __core__/lualib/event_handler. Liest nur storage (storage.grace, storage.hunts), schreibt nichts
-- dorthin. scripts/worms.lua ruft refresh_force bei Start, Entscheidung und Ende einer Jagd; sonst frischt der
-- 30-Tick-Takt auf. Leer → Rahmen weg. Solange storage.hunts.paused_until in der Zukunft liegt (nach
-- /arrakis-uninstall), zeigt das Fenster nichts, auch keine Schonfrist.
-- Rahmen arrakis_worm_frame im Fluss von mod_gui.get_frame_flow (V23 core/lualib/mod-gui.lua:36–40) [V18]; den Fluss
-- selbst legt dieses Modul nur an, wenn es eine Zeile gibt, und lässt ihn stehen (andere Mods nutzen ihn auch).

local mod_gui = require("mod-gui")

local gui = {}

local FRAME = "arrakis_worm_frame"
-- Name des Flusses aus mod_gui.get_frame_flow (V23 core/lualib/mod-gui.lua:38).
local FLOW = "mod_gui_frame_flow"

-- Zeit m:ss aus Ticks (aufgerundet auf ganze Sekunden).
local function mmss(ticks)
  local s = math.max(0, math.ceil(ticks / 60))
  return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function seconds_left(eta, tick)
  return math.max(0, math.ceil((eta - tick) / 60))
end

-- Zeilen für die Force des Spielers: Schonfrist, dann Jagden nach eta_tick (bei Gleichstand nach id).
local function lines_for(player, tick)
  local lines = {}
  local hunts = storage.hunts
  if not (hunts and storage.grace) then return lines end
  if hunts.paused_until and hunts.paused_until > tick then return lines end
  local force_index = player.force.index
  local g = storage.grace[force_index]
  if g and g.active_from and not g.awake then
    lines[#lines + 1] = {"arrakis-message.worm-gui-grace", mmss(g.active_from - tick)}
  end
  local own = {}
  for _, hunt in pairs(hunts.list) do
    if hunt.force_index == force_index then own[#own + 1] = hunt end
  end
  table.sort(own, function(a, b)
    if a.eta_tick ~= b.eta_tick then return a.eta_tick < b.eta_tick end
    return a.id < b.id
  end)
  for _, hunt in ipairs(own) do
    local left = seconds_left(hunt.eta_tick, tick)
    local name = hunt.target_name
    if hunt.state == "searching" then
      lines[#lines + 1] = {"arrakis-message.worm-gui-hunt-searching", seconds_left(hunt.end_tick or tick, tick)}
    elseif hunt.state == "warning" then
      if hunt.lost then
        lines[#lines + 1] = {"arrakis-message.worm-gui-hunt-lost", left}
      elseif hunt.hidden then
        lines[#lines + 1] = {"arrakis-message.worm-gui-hunt-carried", name, left}
      elseif hunt.safe == "rock" then
        lines[#lines + 1] = {"arrakis-message.worm-gui-hunt-safe", name, left}
      elseif hunt.safe == "far" then
        lines[#lines + 1] = {"arrakis-message.worm-gui-hunt-far", name, left}
      else
        lines[#lines + 1] = {"arrakis-message.worm-gui-hunt", name, left}
      end
      if hunt.teaching then lines[#lines + 1] = {"arrakis-message.worm-gui-teaching"} end
    end
  end
  return lines
end

-- Rahmen weg (der Fluss bleibt).
function gui.destroy(player)
  if not (player and player.valid) then return end
  local flow = player.gui.left[FLOW]
  local frame = flow and flow[FRAME]
  if frame then frame.destroy() end
end

-- Fenster auf den Stand von storage bringen; Labels werden wiederverwendet.
function gui.refresh(player)
  if not (player and player.valid) then return end
  local lines = player.connected and lines_for(player, game.tick) or {}
  if #lines == 0 then
    gui.destroy(player)
    return
  end
  local flow = mod_gui.get_frame_flow(player)
  local frame = flow[FRAME]
  if not frame then
    frame = flow.add{type = "frame", name = FRAME, caption = {"arrakis-message.worm-gui-title"}, direction = "vertical",
      style = mod_gui.frame_style}
  end
  local children = frame.children
  for i, line in ipairs(lines) do
    local label = children[i]
    if label then
      label.caption = line
    else
      frame.add{type = "label", caption = line}
    end
  end
  for i = #children, #lines + 1, -1 do children[i].destroy() end
end

-- Alle verbundenen Spieler der Force.
function gui.refresh_force(force)
  if not (force and force.valid) then return end
  for _, player in pairs(force.connected_players) do gui.refresh(player) end
end

local function on_player_event(event)
  gui.refresh(game.get_player(event.player_index))
end

local function on_player_left_game(event)
  gui.destroy(game.get_player(event.player_index))
end

local function on_nth_tick_30()
  for _, player in pairs(game.connected_players) do gui.refresh(player) end
end

gui.events =
{
  [defines.events.on_player_joined_game] = on_player_event,
  [defines.events.on_player_changed_force] = on_player_event,
  [defines.events.on_player_left_game] = on_player_left_game
}

gui.on_nth_tick =
{
  [30] = on_nth_tick_30
}

return gui
