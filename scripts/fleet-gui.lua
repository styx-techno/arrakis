-- Relatives Fenster am Lagerfenster der Ornithopter-Leitstelle (Phase 3e, docs/plan-3e.md 6): Carryalls der
-- Leitstelle mit Zustand und Flugtreibstoff, Ernter in Reichweite, laufende Aufträge. Nur Anzeige. Bibliothek für
-- __core__/lualib/event_handler. Offene Fenster stehen in storage.depot_gui_open[player_index] = depot_un. Muster wie
-- scripts/flyer-gui.lua.

local fleet = require("scripts.fleet")

local gui = {}

local FRAME = "arrakis_depot_frame"
local DEPOT = "arrakis-depot"

local function destroy(player)
  local frame = player.gui.relative[FRAME]
  if frame then frame.destroy() end
end

-- Zustand eines Carryalls als Text: Handbetrieb, Auftrag, parkt oder unterwegs.
local function carryall_state(record, d)
  if record.fleet_mode == "manual" then return {"arrakis-message.gui-fleet-state-manual"} end
  local job = record.job and storage.jobs.list[record.job]
  if job then return {"arrakis-message.gui-fleet-job-" .. job.kind} end
  local entity = record.entity
  local dx, dy = entity.position.x - d.position.x, entity.position.y - d.position.y
  if dx * dx + dy * dy <= 9 then return {"arrakis-message.gui-fleet-state-parked"} end
  return {"arrakis-message.gui-fleet-state-flying"}
end

local function update(player, d)
  local frame = player.gui.relative[FRAME]
  if not frame then return end
  local list = frame.arrakis_depot_list
  list.clear()
  local free, busy, manual, count = 0, 0, 0, 0
  for _, record in pairs(storage.flyers) do
    if record.kind == "carryall" and record.depot == d.un and record.entity.valid then
      count = count + 1
      if record.fleet_mode == "manual" then manual = manual + 1
      elseif record.job then busy = busy + 1
      else free = free + 1 end
      list.add{type = "label", caption = {"arrakis-message.gui-depot-carryall", record.un, carryall_state(record, d),
        math.floor(fleet.onboard_energy(record.entity) / 1e6 + 0.5)}}
    end
  end
  frame.arrakis_depot_carryalls.caption = {"arrakis-message.gui-depot-carryalls", count, free, busy, manual}
  local harvesters = 0
  local entity = d.entity
  for _, h in pairs(storage.harvesters) do
    local e = h.entity
    if e and e.valid and e.surface.index == d.surface_index and e.force.index == d.force_index then
      local dx, dy = e.position.x - d.position.x, e.position.y - d.position.y
      if dx * dx + dy * dy <= fleet.RANGE * fleet.RANGE then harvesters = harvesters + 1 end
    end
  end
  frame.arrakis_depot_harvesters.caption = {"arrakis-message.gui-depot-harvesters", harvesters, fleet.RANGE}
  local jobs = 0
  for _, job in pairs(storage.jobs.list) do
    local record = job.carryall and storage.flyers[job.carryall]
    if record and record.depot == d.un then jobs = jobs + 1 end
  end
  frame.arrakis_depot_jobs.caption = {"arrakis-message.gui-depot-jobs", jobs}
  if count == 0 and entity.valid then
    list.add{type = "label", caption = {"arrakis-message.gui-depot-empty"}}
  end
end

-- Anker container_gui mit names (wie spider_vehicle_gui in scripts/flyer-gui.lua).
local function build(player, d)
  destroy(player)
  local frame = player.gui.relative.add{
    type = "frame",
    name = FRAME,
    caption = {"entity-name.arrakis-depot"},
    direction = "vertical",
    anchor =
    {
      gui = defines.relative_gui_type.container_gui,
      position = defines.relative_gui_position.right,
      names = {DEPOT}
    }
  }
  frame.add{type = "label", name = "arrakis_depot_carryalls"}
  frame.add{type = "flow", name = "arrakis_depot_list", direction = "vertical"}
  frame.add{type = "label", name = "arrakis_depot_harvesters"}
  frame.add{type = "label", name = "arrakis_depot_jobs"}
  update(player, d)
end

local function close(player_index)
  storage.depot_gui_open[player_index] = nil
  local player = game.get_player(player_index)
  if player then destroy(player) end
end

local function on_gui_opened(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.name == DEPOT) then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local d = fleet.depot_of(entity.unit_number) or fleet.register_depot(entity)
  storage.depot_gui_open[player.index] = d.un
  build(player, d)
end

local function on_gui_closed(event)
  if not storage.depot_gui_open[event.player_index] then return end
  local entity = event.entity
  if entity and entity.valid and entity.name ~= DEPOT then return end
  close(event.player_index)
end

-- Offene Fenster jede Sekunde auffrischen; Fenster zu verschwundenen Leitstellen oder Spielern schließen.
local function on_nth_tick_60()
  local open = storage.depot_gui_open
  if next(open) == nil then return end
  for player_index, un in pairs(open) do
    local player = game.get_player(player_index)
    local d = fleet.depot_of(un)
    if not (player and player.connected and d and player.gui.relative[FRAME]) then
      close(player_index)
    else
      update(player, d)
    end
  end
end

gui.events =
{
  [defines.events.on_gui_opened] = on_gui_opened,
  [defines.events.on_gui_closed] = on_gui_closed
}

gui.on_nth_tick =
{
  [60] = on_nth_tick_60
}

return gui
