-- T17 Ornithopter: Bedienung: Prüfstand-Test (aus t_ornithopter.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_ornithopter.lua.

local common = require("scripts.testbench.gemeinsam_ornithopter")
local flyer_lib = require("scripts.flyer")
local intake = require("scripts.intake")
local INTAKE = common.INTAKE
local SPICE = common.SPICE
local ROCK = common.ROCK
local FLIGHT_FUEL = common.FLIGHT_FUEL
local CARRY_SHORTCUT = common.CARRY_SHORTCUT
local REMOTE_SHORTCUT = common.REMOTE_SHORTCUT
local ORNITHOPTER_TECH = common.ORNITHOPTER_TECH
local valid = common.valid
local copy_pos = common.copy_pos
local at = common.at
local pos_text = common.pos_text
local read = common.read
local box_of = common.box_of
local flyer_state = common.flyer_state
local car_state = common.car_state
local create = common.create
local new_car = common.new_car
local new_flyer = common.new_flyer
local sweep = common.sweep
local storage_ready = common.storage_ready

-- T17 Ornithopter: Bedienung (interaktiv) -------------------------------------------------------------
-- Neben Max: ein Ornithopter mit Raketentreibstoff, ein Ernter mit 500 Spice-Sand, 30 Kacheln weiter eine Annahme auf Fels.
-- Jeder Druck auf die Taste (arrakis-carry-toggle) und jeder Klick auf eine der beiden Verknüpfungen schreibt eine
-- MESSUNG-Zeile (Weiterleitung carry_key und shortcut aus runner.lua, zusätzlich zu flyer.lua: event_handler fasst sie
-- zusammen, die Reihenfolge ist nicht zugesichert; der Zustand in der Zeile kann also vor oder nach dem Laufzeitcode
-- stehen). Jeder Zustandswechsel von Ornithopter oder Ernter schreibt eine INFO-Zeile. Nach dem zweiten Anheben
-- (Schritt 2; Schritt 1 ist Anheben und Absetzen, Plan 6) fliegt der Test den Ornithopter 20 s im Kreis (wie T9 C),
-- dann kommt die FRAGE zum Lastbild.

local T17_END_TICKS = 360 * 60 -- „endet nach 6 min Spielzeit“ (Zeitlimit des Runners 380 s)
local T17_CIRCLE_TICKS = 20 * 60
-- 0.16.1 (Max in T17 am 01.11.2026: „fliegt nicht immer mit gleichbleibender Geschwindigkeit“): Bis 0.16.0 setzte der
-- Test alle 3 s ein neues Ziel 45° weiter auf einem Kreis mit 8 Kacheln; der Ornithopter war nach knapp 1 s da und
-- stand dann 2 s (Stop-and-go). Jetzt bekommt er alle Wegpunkte von drei Runden auf einmal (add_autopilot_destination)
-- und fliegt sie ohne Halt ab.
local T17_CIRCLE_RADIUS = 16
local T17_CIRCLE_STEP = 30     -- Grad je Wegpunkt
local T17_CIRCLE_LAPS = 3

local function entity_text(entity)
  if not entity then return "nil" end
  if not entity.valid then return "ungültig" end
  return entity.name .. (entity.unit_number and (" #" .. entity.unit_number) or "")
end

-- Was beim Tastendruck oder Klick am Spieler steht (wie T12), dazu resolve_flyer (ohne Seiteneffekt).
local function t17_measure(run, tb, player, event)
  local parts = {}
  local function add(label, fn)
    local ok, value = pcall(fn)
    table.insert(parts, label .. " = " .. (ok and tostring(value) or ("Fehler " .. tostring(value))))
  end
  add("vehicle", function() return entity_text(player.vehicle) end)
  add("physical_vehicle", function() return entity_text(player.physical_vehicle) end)
  add("controller_type", function() return tb.enum_name(defines.controllers, player.controller_type) end)
  add("render_mode", function() return tb.enum_name(defines.render_mode, player.render_mode) end)
  add("spidertron_remote_selection", function()
    local list = player.spidertron_remote_selection
    if not list then return "nil" end
    if #list == 0 then return "leer" end
    local names = {}
    for _, entity in pairs(list) do table.insert(names, entity_text(entity)) end
    return table.concat(names, ", ")
  end)
  add("cursor_stack", function()
    local stack = player.cursor_stack
    if not stack then return "nil (kein Cursor)" end
    if not stack.valid_for_read then return "leer" end
    return stack.name .. " x" .. stack.count
  end)
  add("selected", function() return entity_text(player.selected) end)
  add("cursor_position", function() return event.cursor_position and pos_text(tb, event.cursor_position) or "–" end)
  add("resolve_flyer", function() return entity_text(flyer_lib.resolve_flyer(player, event.cursor_position)) end)
  return table.concat(parts, ", ")
end

local function t17_states(d)
  return flyer_state(d.flyer), car_state(d.car)
end

local function t17_start(run, tb)
  local d = run.data
  local player = tb.player(run)
  if not player then
    tb.log(run, "FEHLER", "Kein Spieler für den interaktiven Test")
    tb.finish(run, "abgebrochen (kein Spieler)")
    return
  end
  if not storage_ready() then
    tb.log(run, "FEHLER", "storage des Laufzeitcodes fehlt (scripts/migrate.lua init nicht gelaufen)")
    tb.finish(run, "abgebrochen (kein storage)")
    return
  end
  local origin = tb.area(run.id)
  d.boxes = {box_of(origin, {x = 60, y = 60})}
  d.made = {cars = {}, flyers = {}, others = {}}
  d.keys, d.shortcuts, d.changes = 0, 0, 0
  d.lifts = 0 -- Wechsel des Ornithopters nach „beladen“; der Kreisflug beginnt beim zweiten
  sweep(run, tb, d.boxes, true)
  tb.prepare(origin, 60)
  local surface = tb.surface()
  local force = player.force
  local tech = force.technologies[ORNITHOPTER_TECH]
  if tech and not tech.researched then
    tech.researched = true
    tb.log(run, "INFO", "„Ornithopter“ für deine Force erforscht (sonst gäbe es die Verknüpfungen nicht)")
  end
  tb.watch(run, player, origin)
  d.flyer = new_flyer(run, tb, at(origin, 4.5, 0.5), {fuel = FLIGHT_FUEL, count = 4, force = force})
  d.car = new_car(run, tb, at(origin, 12.5, 0.5), {coal = 10, force = force})
  local rock = at(origin, 42, 0)
  tb.fill({{rock.x - 8, rock.y - 8}, {rock.x + 8, rock.y + 8}}, ROCK, surface)
  d.intake = create(run, tb, {name = INTAKE, position = rock, force = force, raise_built = true})
  if not (d.flyer and d.car and d.intake) then
    tb.log(run, "FEHLER", "Aufbau ging nicht (Einzelheiten in der Datei)")
    tb.finish(run, "abgebrochen (Aufbau)")
    return
  end
  local spice = d.car.get_inventory(defines.inventory.car_trunk).insert{name = SPICE, count = 500}
  local record = intake.get(d.intake)
  tb.log(run, "INFO", string.format("Ornithopter %s mit Raketentreibstoff, Ernter %s mit %d Spice-Sand, Annahme %s auf Fels%s",
    pos_text(tb, d.flyer.position), pos_text(tb, d.car.position), spice, pos_text(tb, d.intake.position),
    (record and not record.bad) and "" or " (FEHLER: nicht richtig eingetragen)"))
  d.last_flyer, d.last_car = t17_states(d)
  local steps =
  {
    "1) In den Ornithopter einsteigen, über den Ernter fliegen, Umschalt+C: Ring um den Ernter, nach 2 s hängt er dran. Noch einmal Umschalt+C: abgesetzt.",
    "2) Wieder anheben. Dann fliegt der Test den Ornithopter 20 s im Kreis; danach kommt eine FRAGE.",
    "3) Die Verknüpfung „Ernter anheben oder absetzen“ in der Leiste klicken: absetzen, noch einmal: anheben.",
    "4) Das Fahrzeugfenster des Ornithopters öffnen; rechts daneben hängt das Ornithopter-Fenster. Dort „Absetzen“, dann „In den Ernter steigen“.",
    "5) Aussteigen, die Verknüpfung „Fernbedienung für Ornithopter“ klicken, mit der Fernbedienung den Ornithopter auswählen, Karte öffnen (M), "
      .. "Rechtsklick auf den Ernter. Nach der Ankunft in der Karte Umschalt+C, danach die Verknüpfung „Ernter anheben oder absetzen“.",
    "6) Den Ornithopter aus der Karte fernfahren (WASD) und Umschalt+C drücken.",
    "8) Solo-Rettung: in den Ernter steigen, den Ornithopter per Fernbedienung herholen, die Karte offen lassen, Umschalt+C. "
      .. "Erwartet: Du sitzt danach als Pilot im Ornithopter, der Ernter hängt dran. Über der Annahme absetzen: nach 2 s dockt er an."
  }
  for _, text in ipairs(steps) do tb.log(run, "INFO", text) end
  tb.log(run, "FRAGE", "7) Ist Umschalt+C unter Einstellungen → Steuerung doppelt belegt? [U1]")
  tb.log(run, "INFO", "Jeder Druck auf Umschalt+C und jeder Klick auf eine der beiden Verknüpfungen schreibt eine MESSUNG-Zeile, jeder"
    .. " Zustandswechsel eine INFO-Zeile. Ende nach 6 min Spielzeit oder mit /arrakis-test stop. Bitte mit /arrakis-test tempo 1.")
  if game.speed ~= 1 then
    tb.log(run, "INFO", "Zeitraffer an (game.speed " .. string.format("%g", game.speed) .. "): die 6 min vergehen schneller; zurück mit /arrakis-test tempo 1")
  end
end

local function t17_circle_point(circle, angle)
  local rad = math.rad(angle)
  return {x = circle.center.x + circle.radius * math.cos(rad), y = circle.center.y + circle.radius * math.sin(rad)}
end

local function t17_tick(run, tb)
  local d = run.data
  if not d.flyer then return end
  local now = game.tick
  local flyer_now, car_now = t17_states(d)
  if flyer_now ~= d.last_flyer or car_now ~= d.last_car then
    d.changes = d.changes + 1
    tb.log(run, "INFO", string.format("Zustand: Ornithopter %s → %s, Ernter %s → %s", d.last_flyer, flyer_now, d.last_car, car_now))
    if flyer_now == "beladen" and d.last_flyer ~= "beladen" then d.lifts = d.lifts + 1 end
    if flyer_now == "beladen" and d.lifts == 2 and not d.circle and valid(d.flyer) then
      d.circle = {center = copy_pos(d.flyer.position), radius = T17_CIRCLE_RADIUS, until_tick = now + T17_CIRCLE_TICKS, targets = 0}
      local circle = d.circle
      pcall(function() d.flyer.autopilot_destination = nil end)
      for k = 1, T17_CIRCLE_LAPS * 360 / T17_CIRCLE_STEP do
        if pcall(function() d.flyer.add_autopilot_destination(t17_circle_point(circle, k * T17_CIRCLE_STEP)) end) then
          circle.targets = circle.targets + 1
        end
      end
      tb.log(run, "INFO", "2) Kreisflug 20 s um " .. pos_text(tb, circle.center) .. " ohne Halt (" .. circle.targets .. " Wegpunkte)")
    end
    d.last_flyer, d.last_car = flyer_now, car_now
  end
  local circle = d.circle
  if circle and not circle.done and valid(d.flyer) then
    if now >= circle.until_tick then
      circle.done = true
      pcall(function() d.flyer.autopilot_destination = nil end)
      tb.log(run, "MESSUNG", string.format("2) Kreisflug fertig: %d Ziele, Ornithopter %s", circle.targets, flyer_state(d.flyer)))
      tb.log(run, "FRAGE", "2) Hängt der Ernter sichtbar unter dem Ornithopter, und liegt der Schatten passend am Boden? [U27] Bitte Screenshot.")
    end
  end
  if now - run.started >= T17_END_TICKS then
    if not (circle and circle.done) then
      tb.log(run, "FRAGE", "2) (ohne Kreisflug) Hängt der Ernter sichtbar unter dem Ornithopter, und liegt der Schatten passend am Boden? [U27]")
    end
    tb.finish(run, string.format("%d Tastendrücke, %d Verknüpfungsklicks, %d Zustandswechsel gemessen", d.keys, d.shortcuts, d.changes))
  end
end

local function t17_on_event(run, tb, name, event)
  local d = run.data
  if not d.flyer then return end
  local player = event.player_index and game.get_player(event.player_index)
  if not player then return end
  local who = player.index ~= run.player_index and (" (Spieler " .. player.name .. ")") or ""
  if name == "carry_key" then
    d.keys = d.keys + 1
    tb.log(run, "MESSUNG", string.format("Umschalt+C %d%s: %s; Ornithopter %s, Ernter %s", d.keys, who, t17_measure(run, tb, player, event),
      flyer_state(d.flyer), car_state(d.car)))
  elseif name == "shortcut" then
    if event.prototype_name ~= CARRY_SHORTCUT and event.prototype_name ~= REMOTE_SHORTCUT then return end
    d.shortcuts = d.shortcuts + 1
    tb.log(run, "MESSUNG", string.format("Verknüpfung %s %d%s: %s; Ornithopter %s, Ernter %s", event.prototype_name, d.shortcuts, who,
      t17_measure(run, tb, player, event), flyer_state(d.flyer), car_state(d.car)))
  elseif name == "driving_changed" then
    tb.log(run, "MESSUNG", string.format("Ein-/Ausstieg%s: vehicle = %s, controller_type = %s, Ereignis-Entity = %s", who,
      tostring(read(function() return entity_text(player.vehicle) end)),
      tostring(read(function() return tb.enum_name(defines.controllers, player.controller_type) end)),
      tostring(read(function() return entity_text(event.entity) end))))
  end
end

-- Kreisflug anhalten; eine Last absetzen (ohne Hinweis), damit kein Ernter des Tests auf der Ablage bleibt.
-- Ornithopter, Ernter und Annahme bleiben zum Ansehen stehen (wie T9).
local function t17_cleanup(run, tb)
  local d = run.data
  if valid(d.flyer) then
    pcall(function() d.flyer.autopilot_destination = nil end)
    local record = flyer_lib.get(d.flyer)
    if record and record.cargo then pcall(flyer_lib.drop, record, nil, true) end
  end
end

return
{
  T17 =
  {
    title = "Ornithopter: Bedienung",
    timeout = 380 * 60,
    interactive = true,
    confirm = nil,
    start = t17_start,
    tick = t17_tick,
    on_event = t17_on_event,
    cleanup = t17_cleanup
  }
}
