-- T12 Flieger: Rettung aus der Kartenansicht: Prüfstand-Test (aus t_flyer.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_flyer.lua.

local common = require("scripts.testbench.gemeinsam_flyer")
local FLYER_4 = common.FLYER_4
local FUEL_ITEM = common.FUEL_ITEM
local guarded = common.guarded
local read = common.read
local pos_text = common.pos_text
local offset = common.offset
local bring_player = common.bring_player
local create_flyer = common.create_flyer
local add_fuel = common.add_fuel

-- T12 Rettung aus der Kartenansicht ----------------------------------------------------------

local T12_END_TICKS = 180 * 60 -- „Ende nach 3 min“ (Zeitlimit des Runners 190 s)

local function t12_entity_text(entity)
  if not entity then return "nil" end
  if not entity.valid then return "ungültig" end
  return entity.name .. (entity.unit_number and (" #" .. entity.unit_number) or "")
end

local function t12_measure(run, tb, player, event)
  local vehicle = read(function() return t12_entity_text(player.vehicle) end)
  local physical = read(function() return t12_entity_text(player.physical_vehicle) end)
  local controller = read(function() return tb.enum_name(defines.controllers, player.controller_type) end)
  local render_mode = read(function() return tb.enum_name(defines.render_mode, player.render_mode) end)
  local selection = read(function()
    local list = player.spidertron_remote_selection
    if not list then return "nil" end
    if #list == 0 then return "leer" end
    local names = {}
    for _, entity in pairs(list) do table.insert(names, t12_entity_text(entity)) end
    return table.concat(names, ", ")
  end)
  local cursor = read(function()
    local stack = player.cursor_stack
    if not stack then return "nil (kein Cursor)" end
    if not stack.valid_for_read then return "leer" end
    return stack.name .. " x" .. stack.count
  end)
  local selected = read(function() return t12_entity_text(player.selected) end)
  local prototype = read(function()
    local sp = event.selected_prototype
    if not sp then return "nil" end
    return sp.base_type .. "/" .. sp.derived_type .. "/" .. sp.name .. (sp.quality and (" (" .. sp.quality .. ")") or "")
  end)
  return string.format("vehicle = %s, physical_vehicle = %s, controller_type = %s, render_mode = %s, " ..
    "spidertron_remote_selection = %s, cursor_stack = %s, selected = %s, selected_prototype = %s",
    tostring(vehicle), tostring(physical), tostring(controller), tostring(render_mode),
    tostring(selection), tostring(cursor), tostring(selected), tostring(prototype))
end

-- Spidertron-Fernbedienung in die Hand, nur in einen leeren Cursor. true, wenn sie jetzt dort liegt.
-- Die Verknüpfungsleiste gibt sie erst nach der Forschung „Spidertron“ (base shortcuts.lua:
-- unavailable_until_unlocked), im Testspielstand also meist nicht.
local function t12_give_remote(player)
  if not player.is_cursor_empty() then return false end
  local stack = player.cursor_stack
  if not stack then return false end
  return stack.set_stack({name = "spidertron-remote", count = 1}) == true
end

local function t12_start(run, tb)
  local data = run.data
  local player = tb.player(run)
  if not player then
    tb.log(run, "FEHLER", "Kein Spieler für den interaktiven Test")
    tb.finish(run, "abgebrochen (kein Spieler)")
    return
  end
  local origin = tb.area(run.id)
  tb.prepare(origin, 30)
  local surface = tb.surface()
  bring_player(run, tb, player, origin)
  data.presses = 0

  local flyer = create_flyer(run, tb, surface, FLYER_4, offset(origin, 5, 0), player.force)
  if not flyer then
    tb.finish(run, "FEHLER: kein Flieger")
    return
  end
  data.flyer = flyer
  add_fuel(run, tb, flyer, 5)

  -- Fernbedienung nur in einen leeren Cursor
  local has_remote = false
  local ok_empty, empty = guarded(run, tb, "Cursor prüfen", function() return player.is_cursor_empty() end)
  if ok_empty and empty then
    local ok, set = guarded(run, tb, "Spidertron-Fernbedienung in den Cursor legen", function()
      return t12_give_remote(player)
    end)
    has_remote = ok and set == true
    tb.log(run, "INFO", "Fernbedienung im Cursor: " .. (ok and tostring(set) or "Fehler"))
  elseif ok_empty then
    tb.log(run, "INFO", "Cursor nicht leer: keine Fernbedienung gegeben (Schritt 2: mit leerer Hand aussteigen, dann bekommst du sie)")
  end
  -- Ohne Fernbedienung in der Hand ist ein Fehler hier erwartbar, daher nur INFO.
  local ok_sel = guarded(run, tb, "spidertron_remote_selection setzen", function()
    player.spidertron_remote_selection = {flyer}
  end, has_remote and "FEHLER" or "INFO")
  local selection = read(function()
    local list = player.spidertron_remote_selection
    return list and #list or "nil"
  end)
  tb.log(run, "INFO", string.format("Flieger %s bei %s, Treibstoff %s; Auswahl gesetzt: %s (gelesen: %s Einträge)",
    t12_entity_text(flyer), pos_text(tb, flyer.position), FUEL_ITEM, ok_sel and "ja" or "nein", tostring(selection)))

  tb.log(run, "FRAGE", "1) Steig in den Flieger ein (Enter), öffne die Karte (M), steuere den Flieger aus der Karte heraus (WASD) und drück ALT+O.")
  tb.log(run, "FRAGE", "2) Steig aus, nimm die Spidertron-Fernbedienung in die Hand (ist sie weg: noch einmal ein- und mit leerer Hand " ..
    "aussteigen, dann legt der Test sie dir hinein), klick damit auf den Flieger (er muss ausgewählt sein), öffne die Karte (M) und drück ALT+O.")
  tb.log(run, "FRAGE", "3) Schließ die Karte und drück in der normalen Ansicht ALT+O.")
  tb.log(run, "INFO", "Jeder Druck auf ALT+O schreibt eine MESSUNG-Zeile. Bitte melden, ob bei jedem Schritt eine kam " ..
    "(Datei schicken reicht). Ende nach 3 min oder mit /arrakis-test stop.")
end

local function t12_tick(run, tb)
  if game.tick - run.started >= T12_END_TICKS then
    local presses = run.data.presses or 0
    if presses == 0 then
      tb.log(run, "MESSUNG", "Keine Testtaste angekommen")
    end
    tb.finish(run, string.format("%d Tastendrücke gemessen", presses))
  end
end

local function t12_on_event(run, tb, name, event)
  local data = run.data
  if name == "test_key" then
    local player = event.player_index and game.get_player(event.player_index)
    if not player then return end
    data.presses = (data.presses or 0) + 1
    local who = player.index ~= run.player_index and (" (Spieler " .. player.name .. ")") or ""
    tb.log(run, "MESSUNG", string.format("Taste %d%s: %s", data.presses, who, t12_measure(run, tb, player, event)))
  elseif name == "driving_changed" then
    if event.player_index ~= run.player_index then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    local vehicle = read(function() return t12_entity_text(player.vehicle) end)
    local controller = read(function() return tb.enum_name(defines.controllers, player.controller_type) end)
    tb.log(run, "MESSUNG", string.format("Ein-/Ausstieg: vehicle = %s, controller_type = %s, Ereignis-Entity = %s",
      tostring(vehicle), tostring(controller), read(function() return t12_entity_text(event.entity) end)))
    -- Beim Aussteigen (Schritt 2) den Flieger wieder auswählen; geht nur mit Fernbedienung in der Hand.
    -- Ist die Hand leer, kommt die Fernbedienung zurück (die Verknüpfungsleiste hilft ohne Forschung nicht).
    local flyer = data.flyer
    if not player.vehicle and flyer and flyer.valid then
      local ok_give, given = pcall(t12_give_remote, player)
      if ok_give and given then
        tb.log(run, "INFO", "Fernbedienung in die leere Hand gelegt")
      end
      local ok, err = pcall(function() player.spidertron_remote_selection = {flyer} end)
      local count = read(function()
        local list = player.spidertron_remote_selection
        return list and #list or "nil"
      end)
      tb.log(run, "INFO", "Flieger nach dem Aussteigen wieder ausgewählt: " .. (ok and "ja" or ("nein (" .. tostring(err) .. ")"))
        .. ", Auswahl jetzt " .. tostring(count) .. " Einträge" .. (ok and "" or "; mit der Fernbedienung auf den Flieger klicken"))
    end
  end
end

return
{
  T12 =
  {
    title = "Flieger: Rettung aus der Kartenansicht",
    timeout = 190 * 60,
    interactive = true,
    confirm = nil,
    start = t12_start,
    tick = t12_tick,
    on_event = t12_on_event
  }
}
