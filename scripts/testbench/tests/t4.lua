-- T4 Annahme und Tankstutzen: Prüfstand-Test (aus t_harvester.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_harvester.lua.

local common = require("scripts.testbench.gemeinsam_harvester")
local HARVESTER = common.HARVESTER
local force_of = common.force_of
local pos_text = common.pos_text
local count_text = common.count_text

local INTAKE = "arrakis-test-intake"
local NOZZLE = "arrakis-test-nozzle"

-- Anzahl eines Items in einem Inventar der Entity; nil, wenn nicht lesbar.
local function count_in(entity, inventory_index, item)
  if not (entity and entity.valid) then return nil end
  local ok, count = pcall(function()
    local inventory = entity.get_inventory(inventory_index)
    return inventory and inventory.get_item_count(item)
  end)
  if ok then return count end
  return nil
end

-- T4 Annahme und Tankstutzen -------------------------------------------------------------------
-- Felsquadrat 24×24 in Sand. Bauregel der Annahme prüfen, dann Aufbau (Koordinaten relativ zur Mitte o):
--   Annahme 2×2 bei o, Greifarm 1 bei o+(1.5, -0.5) → Kiste bei o+(2.5, -0.5)
--   Kohlekiste o+(-1.5, 3.5) → Greifarm 2 o+(-0.5, 3.5) → Tankstutzen o+(0.5, 3.5)
--   Mast o+(0.5, 1.5) (Versorgung ±3.5), Energie-Schnittstelle o+(3, 3), Rechenkombinator o+(-2.5, 0),
--   Ernter o+(0, -6).

local T4_ROCK_HALF = 12
local T4_RUN = 60 * 60
local T4_AFTER = 10 * 60

-- Greifarm von from nach to: die Richtung wählen, bei der Aufnahme bei from und Ablage bei to liegt.
local function t4_inserter(surface, force, position, from, to, tb)
  local directions = {defines.direction.east, defines.direction.west, defines.direction.north, defines.direction.south}
  for _, direction in ipairs(directions) do
    local inserter = surface.create_entity{name = "inserter", position = position, direction = direction, force = force}
    if inserter then
      local drop, pickup = inserter.drop_position, inserter.pickup_position
      if tb.distance(drop, to.position) < tb.distance(drop, from.position)
        and tb.distance(pickup, from.position) < tb.distance(pickup, to.position) then
        return inserter
      end
      inserter.destroy()
    end
  end
  return nil
end

local function t4_inserter_text(tb, inserter)
  local ok, text = pcall(function()
    local pickup, drop = inserter.pickup_target, inserter.drop_target
    return "nimmt bei " .. pos_text(tb, inserter.pickup_position) .. " (" .. (pickup and pickup.name or "–") .. "), legt bei "
      .. pos_text(tb, inserter.drop_position) .. " (" .. (drop and drop.name or "–") .. ")"
  end)
  return ok and text or ("nicht lesbar: " .. tostring(text))
end

local function t4_signal(d)
  local combinator = d.combinator
  if not (combinator and combinator.valid) then return nil, "Kombinator fehlt" end
  local ok, value = pcall(function()
    return combinator.get_signal({type = "item", name = "spice-sand"}, defines.wire_connector_id.combinator_input_red)
  end)
  if ok then return value end
  return nil, tostring(value)
end

local function held_count(inserter, item)
  if not (inserter and inserter.valid) then return 0 end
  local ok, count = pcall(function()
    local stack = inserter.held_stack
    if stack and stack.valid_for_read and stack.name == item then return stack.count end
    return 0
  end)
  return ok and count or 0
end

-- Bauregel: can_place_entity mit build_check_type manual an drei Stellen.
local function t4_checks(run, tb)
  local d = run.data
  local surface = tb.surface()
  local ox, oy = d.origin.x, d.origin.y
  local force = force_of(run, tb)
  local cases =
  {
    {label = "Felsmitte", position = {x = ox, y = oy}, expected = true},
    {label = "3 Kacheln vom Felsrand (Ring enthält Sand)", position = {x = ox + T4_ROCK_HALF - 3, y = oy}, expected = false},
    {label = "auf Sand", position = {x = ox + 30, y = oy}, expected = false}
  }
  d.rule_ok = 0
  local script_results = {}
  for _, case in ipairs(cases) do
    local ok, result = pcall(function()
      return surface.can_place_entity{name = INTAKE, position = case.position, force = force,
        build_check_type = defines.build_check_type.manual}
    end)
    if not ok then
      tb.log(run, "FEHLER", "Bauregel " .. case.label .. ": can_place_entity ging nicht: " .. tostring(result))
    else
      local good = result == case.expected
      if good then d.rule_ok = d.rule_ok + 1 end
      tb.log(run, good and "OK" or "FEHLER", "Bauregel " .. case.label .. " " .. pos_text(tb, case.position)
        .. ": can_place_entity = " .. tostring(result) .. " (erwartet " .. tostring(case.expected) .. ")")
    end
    -- Zum Vergleich dieselbe Stelle mit build_check_type script (nur INFO).
    local ok_script, result_script = pcall(function()
      return surface.can_place_entity{name = INTAKE, position = case.position, force = force,
        build_check_type = defines.build_check_type.script}
    end)
    table.insert(script_results, case.label .. " " .. (ok_script and tostring(result_script) or "Fehler"))
  end
  tb.log(run, "INFO", "Zum Vergleich mit build_check_type script: " .. table.concat(script_results, "; "))
  -- Gegenprobe: Tankstutzen ohne Bauregel auf Sand muss gehen, sonst sagen die false-Werte nichts.
  local ok, result = pcall(function()
    return surface.can_place_entity{name = NOZZLE, position = {x = ox + 30.5, y = oy + 4.5}, force = force,
      build_check_type = defines.build_check_type.manual}
  end)
  tb.log(run, "MESSUNG", "Gegenprobe Tankstutzen (ohne Bauregel) auf Sand: can_place_entity = "
    .. (ok and tostring(result) or ("Fehler: " .. tostring(result))))
  if not (ok and result == true) then
    tb.log(run, "INFO", "Gegenprobe nicht true: die false-Ergebnisse der Bauregel sind nicht aussagekräftig")
  end
end

-- Aufbau. Gibt false zurück, wenn etwas Wesentliches fehlt.
local function t4_build(run, tb)
  local d = run.data
  local surface = tb.surface()
  local ox, oy = d.origin.x, d.origin.y
  local force = force_of(run, tb)
  local missing = {}
  local function make(params)
    params.force = force
    local ok, entity = pcall(function() return surface.create_entity(params) end)
    if ok and entity then return entity end
    table.insert(missing, params.name)
    tb.log(run, "FEHLER", "Aufbau: " .. params.name .. " bei " .. pos_text(tb, params.position) .. " ging nicht"
      .. (ok and "" or (": " .. tostring(entity))))
    return nil
  end

  d.power = make{name = "electric-energy-interface", position = {x = ox + 3, y = oy + 3}}
  d.pole = make{name = "medium-electric-pole", position = {x = ox + 0.5, y = oy + 1.5}}
  d.intake = make{name = INTAKE, position = {x = ox, y = oy}}
  d.chest = make{name = "wooden-chest", position = {x = ox + 2.5, y = oy - 0.5}}
  d.coal_chest = make{name = "wooden-chest", position = {x = ox - 1.5, y = oy + 3.5}}
  d.nozzle = make{name = NOZZLE, position = {x = ox + 0.5, y = oy + 3.5}}
  d.combinator = make{name = "arithmetic-combinator", position = {x = ox - 2.5, y = oy}, direction = defines.direction.north}
  d.harvester = make{name = HARVESTER, position = {x = ox, y = oy - 6}, orientation = 0.25}
  if #missing > 0 then return false end

  d.inserter_out = t4_inserter(surface, force, {x = ox + 1.5, y = oy - 0.5}, d.intake, d.chest, tb)
  d.inserter_fuel = t4_inserter(surface, force, {x = ox - 0.5, y = oy + 3.5}, d.coal_chest, d.nozzle, tb)
  if not (d.inserter_out and d.inserter_fuel) then
    tb.log(run, "FEHLER", "Aufbau: Greifarm ließ sich in keiner Richtung passend setzen")
    return false
  end
  tb.log(run, "MESSUNG", "Greifarm 1 (Annahme → Kiste) " .. t4_inserter_text(tb, d.inserter_out))
  tb.log(run, "MESSUNG", "Greifarm 2 (Kohlekiste → Tankstutzen) " .. t4_inserter_text(tb, d.inserter_fuel))

  local coal = d.coal_chest.get_inventory(defines.inventory.chest).insert{name = "coal", count = 100}
  local spice = d.harvester.get_inventory(defines.inventory.car_trunk).insert{name = "spice-sand", count = 400}
  tb.log(run, "INFO", "Kohlekiste " .. coal .. " Kohle, Ernter-Kofferraum " .. spice .. " Spice-Sand, Ernter-Treibstoff leer")

  -- Ziele per Skript: Annahme → Kofferraum, Tankstutzen → Treibstoff.
  local targets =
  {
    {entity = d.intake, label = "Annahme", inventory = defines.inventory.car_trunk, inventory_name = "car_trunk"},
    {entity = d.nozzle, label = "Tankstutzen", inventory = defines.inventory.fuel, inventory_name = "fuel"}
  }
  for _, target in ipairs(targets) do
    local ok, err = pcall(function()
      target.entity.proxy_target_entity = d.harvester
      target.entity.proxy_target_inventory = target.inventory
    end)
    if ok then
      -- Inventar als Zahl: defines.inventory hat mehrere Namen je Wert, Rückübersetzen wäre mehrdeutig.
      local ok_read, text = pcall(function()
        local now = target.entity.proxy_target_entity
        local index = target.entity.proxy_target_inventory
        return "Ziel " .. (now and (now.name .. " Nr. " .. tostring(now.unit_number)) or "nil") .. ", Inventar "
          .. tostring(index) .. (index == target.inventory and " (passt)" or (" (erwartet " .. tostring(target.inventory) .. ")"))
      end)
      tb.log(run, "MESSUNG", target.label .. " → Ernter (" .. target.inventory_name .. "): " .. (ok_read and text or ("Lesen ging nicht: " .. tostring(text))))
    else
      tb.log(run, "FEHLER", target.label .. ": Ziel setzen ging nicht: " .. tostring(err))
    end
  end

  -- Inhalt der Annahme an die Schaltung melden (Standard laut API: true).
  local ok_cb, cb_text = pcall(function()
    local behavior = d.intake.get_or_create_control_behavior()
    if not behavior then return "keine Steuerung" end
    local before = behavior.read_contents
    if before == false then behavior.read_contents = true end
    return "read_contents " .. tostring(before) .. (before == false and " → true gesetzt" or "")
  end)
  tb.log(run, "INFO", "Annahme Schaltung: " .. (ok_cb and cb_text or ("nicht lesbar: " .. tostring(cb_text))))

  -- Roter Draht Annahme → Kombinator-Eingang, per Skript (unsichtbar, falls wire_origin.script existiert).
  local ok_wire, connected, origin_name = pcall(function()
    local from = d.intake.get_wire_connector(defines.wire_connector_id.circuit_red, true)
    local to = d.combinator.get_wire_connector(defines.wire_connector_id.combinator_input_red, true)
    local script_origin = defines.wire_origin and defines.wire_origin.script
    if script_origin then
      return from.connect_to(to, false, script_origin), "script"
    end
    return from.connect_to(to, false), "Standard"
  end)
  if ok_wire then
    d.wire_origin = origin_name
    tb.log(run, connected and "MESSUNG" or "FEHLER", "Roter Draht Annahme → Kombinator-Eingang (Ursprung " .. tostring(origin_name)
      .. "): verbunden " .. tostring(connected))
  else
    tb.log(run, "FEHLER", "Roter Draht ging nicht: " .. tostring(connected))
  end
  return true
end

local function t4_measure(run, tb)
  local d = run.data
  local chest = count_in(d.chest, defines.inventory.chest, "spice-sand")
  local fuel = count_in(d.harvester, defines.inventory.fuel, "coal")
  local trunk = count_in(d.harvester, defines.inventory.car_trunk, "spice-sand")
  local coal_left = count_in(d.coal_chest, defines.inventory.chest, "coal")
  local signal, signal_err = t4_signal(d)
  local ok_power, power = pcall(function()
    return tostring(d.inserter_out.is_connected_to_electric_network()) .. "/" .. tostring(d.inserter_fuel.is_connected_to_electric_network())
  end)
  tb.log(run, "MESSUNG", string.format("Nach 60 s: Spice-Sand in der Kiste %s, Kohle im Ernter-Brennstoff %s, Signal spice-sand am Kombinator-Eingang %s"
    .. " (Kofferraum noch %s, Kohlekiste noch %s, Greifarme mit Strom %s)",
    count_text(chest), count_text(fuel), signal and tostring(signal) or ("– " .. tostring(signal_err)),
    count_text(trunk), count_text(coal_left), ok_power and power or "?"))
  d.chest_ok = (chest or 0) > 0
  d.fuel_ok = (fuel or 0) > 0
  d.signal_ok = (signal or 0) > 0
  tb.log(run, d.chest_ok and "OK" or "FEHLER", "Greifarm holt über die Annahme aus dem Kofferraum: Kiste " .. count_text(chest))
  tb.log(run, d.fuel_ok and "OK" or "FEHLER", "Greifarm füllt über den Tankstutzen den Ernter-Treibstoff: " .. count_text(fuel) .. " Kohle")
  tb.log(run, d.signal_ok and "OK" or "FEHLER", "Schaltungssignal spice-sand vorhanden: " .. (signal and tostring(signal) or ("– " .. tostring(signal_err))))
  if signal and trunk then
    tb.log(run, "INFO", "Signal " .. (signal == trunk and "=" or "≠") .. " Kofferraum (" .. signal .. " / " .. trunk .. ")")
  end
  d.measured = {chest = chest, fuel = fuel, signal = signal}

  -- Ziele lösen.
  local parts = {}
  for _, entry in ipairs({{d.intake, "Annahme"}, {d.nozzle, "Tankstutzen"}}) do
    local entity, label = entry[1], entry[2]
    local ok, err = pcall(function() entity.proxy_target_entity = nil end)
    local ok_read, now = pcall(function() return entity.proxy_target_entity end)
    if ok then
      table.insert(parts, label .. " Lesewert " .. (ok_read and (now and now.name or "nil") or ("Fehler: " .. tostring(now))))
    else
      tb.log(run, "FEHLER", label .. ": proxy_target_entity = nil ging nicht: " .. tostring(err))
    end
  end
  tb.log(run, "MESSUNG", "proxy_target_entity = nil gesetzt: " .. table.concat(parts, ", "))
  d.detach = {chest = chest or 0, hand = held_count(d.inserter_out, "spice-sand"), fuel = fuel or 0}
end

local function t4_after(run, tb)
  local d = run.data
  local chest = count_in(d.chest, defines.inventory.chest, "spice-sand")
  local fuel = count_in(d.harvester, defines.inventory.fuel, "coal")
  local signal, signal_err = t4_signal(d)
  local detach = d.detach
  tb.log(run, "MESSUNG", string.format("10 s nach dem Lösen: Kiste %s (beim Lösen %d, dazu %d in der Greifarm-Hand), Ernter-Brennstoff %s (beim Lösen %d), Signal %s",
    count_text(chest), detach.chest, detach.hand, count_text(fuel), detach.fuel,
    signal and tostring(signal) or ("– " .. tostring(signal_err))))
  if chest == detach.chest then
    d.after_ok = true
    tb.log(run, "OK", "Kistenstand unverändert (" .. chest .. ")")
  elseif chest and chest <= detach.chest + detach.hand then
    d.after_ok = true
    tb.log(run, "OK", "Kistenstand unverändert bis auf " .. (chest - detach.chest) .. " Stück aus der Greifarm-Hand (" .. chest .. ")")
  else
    d.after_ok = false
    tb.log(run, "FEHLER", "Kistenstand nach dem Lösen verändert: " .. detach.chest .. " → " .. count_text(chest))
  end
  tb.log(run, "FRAGE", "Siehst du den roten Draht zwischen Annahme und Kombinator? Kannst du ihn entfernen?"
    .. " (Annahme = orange 2×2-Kiste in der Felsmitte, Kombinator links daneben; Draht per Skript, Ursprung "
    .. tostring(d.wire_origin or "–") .. ")")
  local m = d.measured or {}
  tb.finish(run, string.format("Bauregel %d/3 wie erwartet; Kiste %s %s, Brennstoff %s %s, Signal %s %s; nach dem Lösen %s",
    d.rule_ok or 0, count_text(m.chest), d.chest_ok and "OK" or "FEHLER", count_text(m.fuel), d.fuel_ok and "OK" or "FEHLER",
    count_text(m.signal), d.signal_ok and "OK" or "FEHLER", d.after_ok and "OK" or "FEHLER"))
end

local function t4_start(run, tb)
  local d = run.data
  local origin = tb.area(run.id)
  local ox, oy = origin.x, origin.y
  tb.prepare(origin, 40)
  local tiles = tb.fill({{ox - T4_ROCK_HALF, oy - T4_ROCK_HALF}, {ox + T4_ROCK_HALF, oy + T4_ROCK_HALF}}, "arrakis-rock", tb.surface())
  d.origin = {x = ox, y = oy}
  tb.watch(run, nil, {x = ox, y = oy + 9})
  tb.log(run, "INFO", "Felsquadrat 24×24 (" .. tiles .. " Kacheln arrakis-rock) in Sand bei " .. pos_text(tb, d.origin)
    .. "; Bauregel-Prüfung und Aufbau in 0.5 s, dann 60 s Betrieb")
  d.step = "check"
  d.next_tick = game.tick + 30
end

local function t4_tick(run, tb)
  local d = run.data
  if not d.step or game.tick < d.next_tick then return end
  if d.step == "check" then
    t4_checks(run, tb)
    if not t4_build(run, tb) then
      tb.finish(run, "abgebrochen (Aufbau fehlgeschlagen); Bauregel " .. (d.rule_ok or 0) .. "/3 wie erwartet")
      return
    end
    tb.log(run, "INFO", "Aufbau fertig, läuft 60 s")
    d.step = "measure"
    d.next_tick = game.tick + T4_RUN
  elseif d.step == "measure" then
    t4_measure(run, tb)
    d.step = "after"
    d.next_tick = game.tick + T4_AFTER
  elseif d.step == "after" then
    d.step = nil
    t4_after(run, tb)
  end
end

return
{
  T4 =
  {
    title = "Annahme und Tankstutzen",
    timeout = 100 * 60,
    interactive = false,
    confirm = nil,
    answer_time = 30 * 60, -- bei „alle“: Zeit, den Draht anzusehen (FRAGE am Ende)
    start = t4_start,
    tick = t4_tick
  }
}
