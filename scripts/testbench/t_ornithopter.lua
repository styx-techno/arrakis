-- Prüfstand: Ornithopter mit echtem Laufzeitcode (Phase 3c, docs/plan-3c.md 6; Vertrag siehe runner.lua).
--   T15: scripts/flyer.lua, scripts/hold.lua, scripts/harvester.lua, scripts/intake.lua und scripts/migrate.lua auf der
--        Prüfstand-Fläche (terrain.harvest_allowed erlaubt sie mit der Startup-Einstellung) und auf der echten Ablage
--        arrakis-hold. Siebzehn Schritte, je eine OK/FEHLER-Zeile mit Werten; Einzelwerte als MESSUNG nur in der Datei.
--   T16: Flugphysik des echten arrakis-ornithopter mit seinem echten Tempo-Sticker: parallele Bahnen wie T1, gemessen
--        zwischen 5 s und 15 s nach dem Start.
--   T17: Bedienung (interaktiv, nur mit Spieler): Taste, Verknüpfungen, Fenster, Fernbedienung, Fernfahren,
--        Solo-Rettung. Jeder Tastendruck und Verknüpfungsklick schreibt eine MESSUNG-Zeile.
-- Ornithopter und Ernter entstehen mit raise_built = true (script_raised_built trägt sie ein); Piloten und Fahrer sind
-- Puppen ohne Spieler (tb.dummy_driver). Ausnahme: die Vergleichsbahnen in T16, die bewusst nie eingetragen werden.
-- Taste, Verknüpfung und Fensterknopf rufen im Spiel flyer_lib.toggle_carry (Plan 4.5); T15 und T16 rufen dieselbe
-- Funktion ohne Spieler und meist mit ausdrücklichem Ziel-Ernter. Ob die Wege im Spiel ankommen, zeigt nur T17.
-- Zustand nur in run.data (Zahlen, Texte, Positionen, LuaEntity- und LuaRenderObject-Referenzen; vor jeder
-- Benutzung prüfen). Die Abläufe stehen als Funktionslisten in diesem Modul, run.data hält nur Schritt- und Phasennummern.
-- Die Modultabelle von scripts/flyer.lua heißt hier flyer_lib (tools/check/api_names.py hält flyer für LuaEntity).
--
-- Isolation von T15 und T16 (Plan 6): Beide heben echte Ernter auf die echte Ablage. Ohne Aufräumen setzte
-- return_cargo alte Lasten in eine eben vorbereitete Fläche (tb.prepare zerstört Flieger per destroy(),
-- on_object_destroyed kommt erst am Ende dieses oder des nächsten Ticks), und resolve_harvester fände sie dort.
-- Deshalb räumen start und cleanup gleich auf (sweep): zuerst jeder Ernter auf arrakis-hold, dessen Abhebepunkt in
-- der eigenen Fläche liegt (raise_destroy: flyer.lua leert den Träger und streicht die Warteliste), dann jeder
-- eingetragene Ornithopter der Fläche (jetzt leer); im cleanup dazu die eigenen Ernter und Ornithopter am Boden.
-- Erst danach tb.prepare, gebaut wird frühestens 2 Ticks später. Zahlen zur Ablage gelten immer relativ zum Stand vor
-- dem Schritt, nie absolut: Ein anderer Test oder der Spielstand kann selbst Lasten tragen.

local flyer_lib = require("scripts.flyer")
local harvester = require("scripts.harvester")
local hold = require("scripts.hold")
local intake = require("scripts.intake")
local migrate = require("scripts.migrate")
local terrain = require("scripts.terrain")

local FLYER = "arrakis-ornithopter"
local NAME = "spice-harvester"
local INTAKE = "arrakis-spice-intake"
local PROBE = "arrakis-harvester-probe"
local SPICE = "spice-sand"
local ROCK = "arrakis-rock"
local SAND = "sand-1"
local HOLD = "arrakis-hold"
local STICKER_EMPTY = "arrakis-ornithopter-empty"
local STICKER_LOADED = "arrakis-ornithopter-loaded"
local OWN_STICKER = {[STICKER_EMPTY] = true, [STICKER_LOADED] = true}
local IMAGE_SPRITE = "arrakis-harvester-carried-"
local SHADOW_SPRITE = "arrakis-harvester-carried-shadow-"
local CARRY_INPUT = "arrakis-carry-toggle"
local CARRY_SHORTCUT = "arrakis-carry"
local REMOTE_SHORTCUT = "arrakis-give-remote"
local REMOTE_ITEM = "spidertron-remote"
local HARVESTING_TECH = "arrakis-spice-harvesting"
local ORNITHOPTER_TECH = "arrakis-ornithopter"
-- Force für Forschung, Migration, fremde Force und „kein Landeplatz“ (einmal anlegen, wiederverwenden wie tb.worm_force).
local T15_FORCE = "arrakis-t15"
-- Force, die erst in Schritt 12 entsteht (Ablage für neue Forces versteckt) und am Ende in neutral aufgeht.
local T15_NEW_FORCE = "arrakis-t15n"

-- Sollwerte aus dem Plan (4.3 bis 4.11), bewusst nicht aus scripts/flyer.lua gelesen.
-- Kopplung 120 Ticks, geprüft im 10-Tick-Takt: Angehoben ist 120 bis 129 Ticks nach dem Aufruf, also sicher nach 130.
local COUPLE_WAIT = 130
-- Entprellen (Plan 4.3): ein zweiter Aufruf für denselben Flieger frühestens nach 15 Ticks.
local DEBOUNCE = 15
-- Pflege im 60-Tick-Takt (Plan 4.4); +1 Tick, weil die Reihenfolge zwischen den Handlern der Module und dem
-- Prüfstand-Tick nicht zugesichert ist (event_handler fasst sie mit pairs zusammen).
local CARE_WAIT = 61
-- Andocken nach dem Absetzen: Andock-Takt alle 60 Ticks, 120 Ticks Stillstand (scripts/intake.lua), also höchstens
-- 180 Ticks; +1 wie oben.
local DOCK_WAIT = 181
local CRASH_SHARE = 0.3       -- Absturzschaden als Anteil der Höchstgesundheit (Plan 4.10)
local LAND_RADIUS = 6         -- Landung höchstens so weit von Todesstelle bzw. Abhebepunkt (erste Suchstufe)
local SEAT_RANGE = 6          -- Insasse am Boden höchstens so weit vom Abhebepunkt (Plan 6, Schritt 3)
-- Stellplätze der Ablage (Plan 4.11): 16 × 16 im 10er-Raster, x, y ∈ {−60, −50, …, 90}.
local SLOT_FIRST, SLOT_LAST, SLOT_SPACING = -60, 90, 10
-- Farben wie T3 (scripts/testbench/t_harvester.lua): Auto beim Aufbau, Puppe vor dem Einsteigen.
local CAR_COLOR = {r = 0.2, g = 0.7, b = 1, a = 1}
local DRIVER_COLOR = {r = 0.6, g = 0.2, b = 0.8, a = 0.5}

-- Allgemeine Helfer ---------------------------------------------------------------------------

local function valid(object)
  return object ~= nil and object.valid
end

local function force_of(run, tb)
  local player = tb.player(run)
  return player and player.force or game.forces["player"]
end

local function copy_pos(position)
  return {x = position.x or position[1], y = position.y or position[2]}
end

local function at(origin, dx, dy)
  return {x = origin.x + dx, y = origin.y + dy}
end

local function pos_text(tb, position)
  if not position then return "–" end
  local p = copy_pos(position)
  return "(" .. tb.num(p.x) .. ", " .. tb.num(p.y) .. ")"
end

-- Liest einen Wert; Fehler werden zu nil.
local function read(fn)
  local ok, value = pcall(fn)
  if ok then return value end
  return nil
end

local function quality_exists(name)
  local ok, exists = pcall(function() return prototypes.quality[name] ~= nil end)
  return ok and exists
end

-- BoundingBox um center mit halben Kantenlängen half {x, y} (ganze Kacheln wie tb.prepare).
local function box_of(center, half)
  return
  {
    left_top = {x = math.floor(center.x - half.x), y = math.floor(center.y - half.y)},
    right_bottom = {x = math.ceil(center.x + half.x), y = math.ceil(center.y + half.y)}
  }
end

-- Liegt position (auch ein Ort {surface, x, y}) in einer der Flächen?
local function inside(boxes, position)
  local x, y = position.x or position[1], position.y or position[2]
  for _, box in pairs(boxes) do
    if x >= box.left_top.x and x <= box.right_bottom.x and y >= box.left_top.y and y <= box.right_bottom.y then
      return true
    end
  end
  return false
end

-- Name eines ItemIDAndQualityIDPair (gelesen: LuaItemPrototype/LuaQualityPrototype) als "name@qualität" (wie T3).
local function item_pair_name(pair)
  if not pair then return "–" end
  local name, quality = pair.name, pair.quality
  if name and type(name) ~= "string" then name = name.name end
  if quality and type(quality) ~= "string" then quality = quality.name end
  return tostring(name) .. "@" .. tostring(quality or "normal")
end

-- Inhalt eines Inventars als sortierter Text "name@qualität anzahl, …" (wie T3).
local function contents_text(inventory)
  if not (inventory and inventory.valid) then return "–" end
  local ok, contents = pcall(function() return inventory.get_contents() end)
  if not ok then return "Fehler: " .. tostring(contents) end
  local totals = {}
  for _, item in pairs(contents) do
    local name, quality = item.name, item.quality or "normal"
    if type(name) ~= "string" then name = name.name end
    if type(quality) ~= "string" then quality = quality.name end
    local key = name .. "@" .. quality
    totals[key] = (totals[key] or 0) + item.count
  end
  local parts = {}
  for key, count in pairs(totals) do table.insert(parts, key .. " " .. count) end
  if #parts == 0 then return "leer" end
  table.sort(parts)
  return table.concat(parts, ", ")
end

local function color_text(color)
  if type(color) ~= "table" then return color == nil and "–" or tostring(color) end
  local r, g, b, a = color.r or color[1], color.g or color[2], color.b or color[3], color.a or color[4] or 1
  return string.format("%.2f/%.2f/%.2f/%.2f", r or 0, g or 0, b or 0, a)
end

-- Gespeicherte Energie (J): Brennstoffinventar, Rest des brennenden Stücks, Wärmepuffer (wie T1). Qualität zählt mit
-- (fuel_value ist je Prototyp; ein legendärer Raketentreibstoff hat denselben Brennwert, A23 prototypes.d.ts).
local function fuel_energy(entity)
  if not valid(entity) then return nil end
  local ok, total = pcall(function()
    local burner = entity.burner
    if not burner then return nil end
    local sum = 0
    for _, item in pairs(burner.inventory.get_contents()) do
      local name = item.name
      if type(name) ~= "string" then name = name.name end
      local prototype = prototypes.item[name]
      sum = sum + (prototype and prototype.fuel_value or 0) * item.count
    end
    local rest = read(function() return burner.remaining_burning_fuel end)
    if type(rest) == "number" then sum = sum + rest end
    local heat = read(function() return burner.heat end)
    if type(heat) == "number" then sum = sum + heat end
    return sum
  end)
  if ok then return total end
  return nil
end

local function fuel_items(entity)
  local inventory = valid(entity) and entity.get_fuel_inventory()
  return inventory and inventory.get_item_count() or 0
end

local function trunk_count(car, item)
  local inventory = valid(car) and car.get_inventory(defines.inventory.car_trunk)
  return inventory and inventory.get_item_count(item or SPICE) or 0
end

-- Summe der Mengen und Zahl der Spice-Ressourcen in area.
local function spice_in(surface, area)
  local total, count = 0, 0
  for _, resource in pairs(surface.find_entities_filtered{area = area, name = SPICE}) do
    total = total + resource.amount
    count = count + 1
  end
  return total, count
end

-- Spice-Sand auf jeder Kachel x1..x2 × y1..y2 (Kachelnummern, beide Grenzen eingeschlossen; wie T13).
local function place_spice(surface, x1, y1, x2, y2, amount)
  local placed = 0
  for x = x1, x2 do
    for y = y1, y2 do
      if surface.create_entity{name = SPICE, position = {x + 0.5, y + 0.5}, amount = amount} then placed = placed + 1 end
    end
  end
  return placed
end

-- Gas geben oder loslassen: riding_state am Fahrzeug und am Dummy-Fahrer (wie T2, T13).
local function gas(car, driver, on)
  local state =
  {
    acceleration = on and defines.riding.acceleration.accelerating or defines.riding.acceleration.nothing,
    direction = defines.riding.direction.straight
  }
  pcall(function() car.riding_state = state end)
  if valid(driver) then pcall(function() driver.riding_state = state end) end
end

-- Steht position genau auf einem Stellplatz der Ablage?
local function at_slot(position)
  local function near(v)
    local k = math.floor((v - SLOT_FIRST) / SLOT_SPACING + 0.5)
    local slot = SLOT_FIRST + k * SLOT_SPACING
    return k >= 0 and slot <= SLOT_LAST and math.abs(v - slot) < 0.01
  end
  return near(position.x) and near(position.y)
end

local function free_slots()
  return hold.free_count()
end

-- Was auf einem Stellplatz steht (für FEHLER-Texte, wenn ein Platz nicht frei wird, z. B. Reste eines Ernters).
local function slot_contents(position)
  local surface = game.get_surface(HOLD)
  if not (surface and position) then return "–" end
  local names = {}
  local r = 4
  for _, entity in pairs(surface.find_entities_filtered{area = {{position.x - r, position.y - r}, {position.x + r, position.y + r}}}) do
    table.insert(names, entity.name)
  end
  if #names == 0 then return "nichts" end
  return table.concat(names, ", ")
end

-- Zustände und Merkmale ------------------------------------------------------------------------

-- Zustand des Fliegers nach Plan 4.3 (Datensatz in storage.flyers).
local function flyer_state(flyer)
  if not valid(flyer) then return "weg" end
  local record = flyer_lib.get(flyer)
  if not record then return "ohne Datensatz" end
  if record.cargo then return "beladen" end
  if record.coupling then return "koppelt" end
  return "leer"
end

-- Zustand des Ernters (storage.harvesters, scripts/harvester.lua).
local function car_state(car)
  if not valid(car) then return "weg" end
  local h = harvester.get(car)
  return h and h.state or "ohne Datensatz"
end

-- Eigene Sticker am Flieger (arrakis-ornithopter-empty/-loaded in flyer.stickers, A23 classes.d.ts:8564).
local function own_stickers(flyer)
  local list = {}
  if not valid(flyer) then return list end
  local stickers = read(function() return flyer.stickers end)
  for _, sticker in pairs(stickers or {}) do
    if sticker.valid and OWN_STICKER[sticker.name] then table.insert(list, sticker) end
  end
  return list
end

local function sticker_text(list)
  if #list == 0 then return "keiner" end
  local names = {}
  for _, sticker in ipairs(list) do
    table.insert(names, sticker.name == STICKER_LOADED and "beladen" or "leer")
  end
  return table.concat(names, " + ")
end

local function render_ok(object)
  local ok, is_valid = pcall(function() return object ~= nil and object.valid end)
  return ok and is_valid == true
end

local function flyer_text(tb, flyer)
  if not valid(flyer) then return "Ornithopter weg" end
  local record = flyer_lib.get(flyer)
  local renders = record and record.renders or {}
  return string.format("Ornithopter %s bei %s, minable_flag %s, Sticker %s, Bild %s, Schatten %s, Ring %s",
    flyer_state(flyer), pos_text(tb, flyer.position), tostring(flyer.minable_flag), sticker_text(own_stickers(flyer)),
    render_ok(renders.image) and "ja" or "nein", render_ok(renders.shadow) and "ja" or "nein",
    render_ok(renders.ring) and "ja" or "nein")
end

local function car_text(tb, car)
  if not valid(car) then return "Ernter weg" end
  local h = harvester.get(car)
  return string.format("Ernter %s auf %s %s, carried_by %s, disabled_by_script %s, minable_flag %s",
    car_state(car), car.surface.name, pos_text(tb, car.position), tostring(h and h.carried_by),
    tostring(read(function() return car.disabled_by_script end)), tostring(read(function() return car.minable_flag end)))
end

-- Sitz einer Puppe in einem Fahrzeug: "Pilot", "Beifahrer" oder nil.
local function seat_of(vehicle, who)
  if not (valid(vehicle) and valid(who)) then return nil end
  if vehicle.get_driver() == who then return "Pilot" end
  if vehicle.get_passenger() == who then return "Beifahrer" end
  return nil
end

-- Bewertung ---------------------------------------------------------------------------------------

local function check(failed, ok, label)
  if not ok then table.insert(failed, label) end
  return ok
end

-- „beladen“ (Plan 4.3, 4.6 Schritt 7): Datensatz trägt car, nicht abbaubar, genau ein eigener Sticker „beladen“,
-- Lastbild und Schatten gültig.
local function check_loaded(failed, label, flyer, car)
  local record = valid(flyer) and flyer_lib.get(flyer)
  if not check(failed, record ~= nil and record ~= false, label .. ": Ornithopter ohne Datensatz") then return false end
  local ok = check(failed, valid(car) and record.cargo == car.unit_number, label .. ": nicht beladen (" .. flyer_state(flyer) .. ")")
  ok = check(failed, flyer.minable_flag == false, label .. ": Ornithopter abbaubar") and ok
  local stickers = own_stickers(flyer)
  ok = check(failed, #stickers == 1 and stickers[1].name == STICKER_LOADED, label .. ": Sticker " .. sticker_text(stickers)) and ok
  ok = check(failed, render_ok(record.renders.image) and render_ok(record.renders.shadow), label .. ": Lastbild oder Schatten fehlt") and ok
  return ok
end

-- „leer“: Datensatz da, keine Last, keine Kopplung, abbaubar, genau ein eigener Sticker „leer“, kein Lastbild.
local function check_empty(failed, label, flyer)
  local record = valid(flyer) and flyer_lib.get(flyer)
  if not check(failed, record ~= nil and record ~= false, label .. ": Ornithopter ohne Datensatz (" .. flyer_state(flyer) .. ")") then return false end
  local ok = check(failed, record.cargo == nil and record.coupling == nil, label .. ": nicht leer (" .. flyer_state(flyer) .. ")")
  ok = check(failed, flyer.minable_flag == true, label .. ": Ornithopter nicht abbaubar") and ok
  local stickers = own_stickers(flyer)
  ok = check(failed, #stickers == 1 and stickers[1].name == STICKER_EMPTY, label .. ": Sticker " .. sticker_text(stickers)) and ok
  ok = check(failed, not render_ok(record.renders.image) and not render_ok(record.renders.shadow), label .. ": Lastbild noch da") and ok
  return ok
end

-- Ernter getragen (Plan 4.6 Schritte 4 und 5): carried, carried_by, auf der Ablage an einem Stellplatz, gesperrt.
local function check_carried(failed, label, car, flyer)
  local h = valid(car) and harvester.get(car)
  if not check(failed, h ~= nil and h ~= false, label .. ": Ernter weg oder ohne Datensatz") then return false end
  local ok = check(failed, h.state == "carried", label .. ": Ernter " .. tostring(h.state) .. " statt carried")
  if flyer ~= false then
    ok = check(failed, valid(flyer) and h.carried_by == flyer.unit_number, label .. ": carried_by " .. tostring(h.carried_by)) and ok
  end
  ok = check(failed, car.surface.name == HOLD and at_slot(car.position), label .. ": nicht auf einem Stellplatz der Ablage ("
    .. car.surface.name .. " " .. string.format("%.2f, %.2f", car.position.x, car.position.y) .. ")") and ok
  ok = check(failed, car.disabled_by_script == true and car.minable_flag == false, label .. ": nicht gesperrt (disabled_by_script "
    .. tostring(car.disabled_by_script) .. ", minable_flag " .. tostring(car.minable_flag) .. ")") and ok
  return ok
end

-- Ernter fahrbereit am Boden: mobile, auf der Prüfstand-Fläche, entsperrt.
local function check_mobile(failed, label, car, tb)
  if not check(failed, valid(car), label .. ": Ernter weg") then return false end
  local ok = check(failed, car_state(car) == "mobile", label .. ": Ernter " .. car_state(car) .. " statt mobile")
  ok = check(failed, car.surface.name == tb.surface().name, label .. ": Ernter auf " .. car.surface.name) and ok
  ok = check(failed, car.disabled_by_script == false, label .. ": Ernter noch gesperrt") and ok
  return ok
end

-- Entities und Aufräumen ----------------------------------------------------------------------------

-- Erzeugt eine Entity (Standard: Prüfstand-Fläche) und merkt sie für das Aufräumen (kind: cars, flyers, others);
-- nil, wenn es nicht ging (Grund in der Datei).
local function create(run, tb, params, surface, kind)
  local ok, entity = pcall(function() return (surface or tb.surface()).create_entity(params) end)
  if ok and entity then
    local made = run.data.made
    if made then table.insert(made[kind or "others"], entity) end
    return entity
  end
  tb.trace(run, params.name .. " bei " .. pos_text(tb, params.position) .. " ging nicht" .. (ok and "" or (": " .. tostring(entity))))
  return nil
end

-- Merkt eine anderswo entstandene Entity (Klon, Puppe) für das Aufräumen.
local function remember(run, entity, kind)
  local made = run.data.made
  if made and valid(entity) then table.insert(made[kind or "others"], entity) end
  return entity
end

-- Treibstoff ins Brennstoffinventar, auch mit Qualität; gibt die eingelegte Menge zurück.
local function add_fuel(entity, item, count, quality)
  local inventory = valid(entity) and entity.get_fuel_inventory()
  if not inventory then return 0 end
  local ok, inserted = pcall(function() return inventory.insert{name = item, count = count, quality = quality} end)
  return ok and inserted or 0
end

-- Echter Ernter, per script_raised_built eingetragen. opts: coal, orientation, force, quality, surface.
local function new_car(run, tb, position, opts)
  opts = opts or {}
  local car = create(run, tb, {name = NAME, position = position, force = opts.force or force_of(run, tb),
    orientation = opts.orientation or 0.25, quality = opts.quality, raise_built = true}, opts.surface, "cars")
  if car and opts.coal and opts.coal > 0 then tb.fuel(car, "coal", opts.coal) end
  return car
end

-- Spielfigur ohne Spieler neben near (Force von near oder force).
local function new_dummy(run, tb, near, force)
  local surface = near.surface
  local position = surface.find_non_colliding_position("character", near.position, 10, 0.5) or near.position
  return create(run, tb, {name = "character", position = position, force = force or near.force}, surface, "others")
end

-- Echter Ornithopter. opts: fuel (Item, Standard keins), count, fuel_quality, quality, pilot (Puppe als Pilot),
-- raw (ohne raise_built: nicht eingetragen), force, surface.
local function new_flyer(run, tb, position, opts)
  opts = opts or {}
  local force = opts.force or force_of(run, tb)
  local flyer = create(run, tb, {name = FLYER, position = position, force = force, quality = opts.quality,
    raise_built = not opts.raw, create_build_effect_smoke = false}, opts.surface, "flyers")
  if not flyer then return nil end
  if opts.fuel then add_fuel(flyer, opts.fuel, opts.count or 5, opts.fuel_quality) end
  if opts.pilot then
    local pilot = tb.dummy_driver(flyer, force)
    if pilot then remember(run, pilot, "others") end
  end
  return flyer
end

-- Paar für das Anheben: Ernter bei c (Kachelmitte), Ornithopter 1,5 Kacheln nördlich. Spinnen kollidieren mit nichts
-- (Vorgabe trigger_target, V23 core/lualib/collision-mask-defaults.lua:190), also auch nicht mit dem Ernter.
-- opts: fuel (Standard Kohle, false: keiner), pilot, force, coal (Ernter), orientation, quality (Ernter).
local function new_pair(run, tb, c, opts)
  opts = opts or {}
  local car = new_car(run, tb, {x = c.x + 0.5, y = c.y + 0.5}, {coal = opts.coal, force = opts.force,
    orientation = opts.orientation, quality = opts.quality})
  local fuel = opts.fuel
  if fuel == nil then fuel = "coal" end
  local flyer = new_flyer(run, tb, {x = c.x + 0.5, y = c.y - 1}, {fuel = fuel or nil, count = 5, pilot = opts.pilot,
    force = opts.force})
  return flyer, car
end

-- Kopplung starten (wie Taste, Shortcut und Knopf, Plan 4.5, nur ohne Spieler). Gibt ok, Grund zurück.
local function couple(flyer, car)
  if not valid(flyer) then return false, "no_flyer" end
  return flyer_lib.toggle_carry(flyer, car, nil)
end

-- Last absetzen bzw. Kopplung abbrechen (derselbe Aufruf).
local function toggle(flyer)
  if not valid(flyer) then return false, "no_flyer" end
  return flyer_lib.toggle_carry(flyer, nil, nil)
end

local function result_text(ok, reason)
  return tostring(ok) .. ", " .. tostring(reason)
end

-- Entfernt, was der Test gebaut hat: zuerst Ernter (raise_destroy, auch auf der Ablage: flyer.lua leert den Träger),
-- dann Ornithopter (raise_destroy, jetzt leer), zuletzt den Rest (Puppen, Mauern, Annahmen, Maschinen, Klippen).
local function tidy(run)
  local made = run.data.made
  if not made then return end
  for _, kind in ipairs({"cars", "flyers", "others"}) do
    for _, entity in pairs(made[kind]) do
      if valid(entity) then pcall(function() entity.destroy{raise_destroy = true} end) end
    end
    made[kind] = {}
  end
end

-- Isolation (Plan 6, siehe Kopf): getragene Ernter dieser Flächen von der Ablage, dann eingetragene Ornithopter der
-- Flächen; mit ground dazu alle Ernter und Ornithopter am Boden der Flächen (nur im cleanup).
local function sweep(run, tb, boxes, ground)
  local surface = tb.surface()
  local index = surface.index
  local counts = {hold = 0, flyers = 0, ground = 0}
  local hold_surface = game.get_surface(HOLD)
  if hold_surface and storage.harvesters then
    for _, car in pairs(hold_surface.find_entities_filtered{name = NAME}) do
      local h = car.valid and harvester.get(car)
      local lift = h and h.lift_pos
      if lift and lift.surface == index and inside(boxes, lift) then
        car.destroy{raise_destroy = true}
        counts.hold = counts.hold + 1
      end
    end
  end
  local flyers = {}
  for _, record in pairs(storage.flyers or {}) do
    local entity = record.entity
    if valid(entity) and entity.surface.index == index and inside(boxes, entity.position) then table.insert(flyers, entity) end
  end
  for _, entity in ipairs(flyers) do
    if entity.valid then
      entity.destroy{raise_destroy = true}
      counts.flyers = counts.flyers + 1
    end
  end
  if ground then
    for _, box in pairs(boxes) do
      for _, name in ipairs({NAME, FLYER}) do
        for _, entity in pairs(surface.find_entities_filtered{area = box, name = name}) do
          if entity.valid then
            entity.destroy{raise_destroy = true}
            counts.ground = counts.ground + 1
          end
        end
      end
    end
  end
  if counts.hold + counts.flyers + counts.ground > 0 then
    tb.trace(run, string.format("Aufräumen: %d Ernter von der Ablage, %d eingetragene Ornithopter, %d am Boden",
      counts.hold, counts.flyers, counts.ground))
  end
  return counts
end

local function t15_force()
  return game.forces[T15_FORCE] or game.create_force(T15_FORCE)
end

-- Ist storage des Laufzeitcodes da (scripts/migrate.lua init)?
local function storage_ready()
  return storage.flyers and storage.harvesters and storage.couplings and storage.stranded and storage.hold
    and storage.reg and storage.intakes
end

-- T15 Ornithopter: echter Code -------------------------------------------------------------------
-- Ablauf: siebzehn Schritte (Plan 6), je Schritt eine Liste von Phasen. Eine Phase gibt zurück:
--   "poll" = nächsten Tick dieselbe Phase, Zahl n = nächste Phase in n Ticks, "end" = Schritt fertig.
-- Jeder Schritt schreibt genau eine OK/FEHLER-Zeile (verdict oder fail); danach räumt tidy seine Entities ab.

local T15_HALF = {x = 160, y = 170}
local T15_CENTER = {x = 0, y = 10}
local T15_GAP = 10
-- Orte relativ zum Testbereich (ganze Zahlen). Reihen: y = −140 (Schritte 3–5), −105 (2, 6, 7), −90/−75 (8, 9),
-- −58 bis −34 (10–17). Der See aus Schritt 9 e liegt darunter (y −25 bis 175) und stört keine andere Reihe.
local T15_PLACES =
{
  s2 = {x = 130, y = -105},        -- Figur und Montagemaschine der Force arrakis-t15
  s3 = {x = -150, y = -140},       -- a, b und Gegenprobe im Abstand 20
  s4 = {x = -80, y = -140},        -- a bis e im Abstand 20
  s5 = {x = 30, y = -140},         -- aufbauend, aufgebaut, einpackend im Abstand 25
  s5_dock = {x = 120, y = -140},   -- Felsinsel 16×16 mit Annahme
  s6_a = {x = -140, y = -105},     -- Spice-Teppich A 15×15
  s6_b = {x = 10, y = -105},       -- Spice-Teppich B, 150 Kacheln weiter
  s7 = {x = 50, y = -105},         -- a, b, c im Abstand 20
  s8 = {x = -150, y = -75},        -- a und b im Abstand 60 (je 30 Kacheln Flug)
  s9_wall = {x = 0, y = -75},      -- Mauerfeld 13×13
  s9_water = {x = 40, y = -75},    -- Wasserfeld 15×15
  s9_cliff = {x = 80, y = -75},    -- Klippe
  s9_stage = {x = 0, y = -90},     -- Abhebestellen für a bis d
  s9_lake = {x = 0, y = 75},       -- See 200×200 mit Sandinsel 8×8
  s10 = {x = 0, y = -34},
  s11 = {x = 30, y = -34},
  s12 = {x = 0, y = -58},          -- drei Paare im Abstand 15
  s13 = {x = -150, y = -58},       -- Zustandstabelle: 10 Spalten (Abstand 14) × 3 Zeilen (Abstand 12)
  s14 = {x = 60, y = -34},
  s15 = {x = 60, y = -58},
  s16 = {x = 100, y = -34},        -- fremde Force; Unterflug bei +30
  s17 = {x = 90, y = -58},         -- drei Paare im Abstand 20
  watch = {x = 150, y = -20}       -- Zuschauerplatz (nur mit Spieler)
}

local function verdict(run, tb, number, title, failed, values)
  local level = #failed == 0 and "OK" or "FEHLER"
  local text = number .. ") " .. title .. ": " .. values
  if #failed > 0 then text = text .. " | nicht erfüllt: " .. table.concat(failed, "; ") end
  tb.log(run, level, text)
  run.data.results[number] = level
  return "end"
end

local function fail(run, tb, number, text)
  tb.log(run, "FEHLER", number .. ") " .. text)
  run.data.results[number] = "FEHLER"
  return "end"
end

-- Die Phasen der Schritte stehen in der Tabelle t15_steps statt als lokale Funktionen: Lua 5.2 erlaubt je Funktion
-- höchstens 200 lokale Variablen, auch im Hauptteil eines Moduls, und mit 64 Phasen wäre dieses Modul darüber.
local t15_steps = {}

-- Schritt 1: Prototypen (Plan 3, 6). Laufzeitlesbar ist fast alles; allow_remote_driving nicht.

function t15_steps.s1_check(run, tb, d)
  local failed, parts = {}, {}
  local p = prototypes.entity[FLYER]
  if not p then return fail(run, tb, 1, "Prototyp " .. FLYER .. " fehlt") end
  check(failed, p.type == "spider-vehicle", "Typ " .. tostring(p.type) .. " statt spider-vehicle")
  local legs = read(function() return #p.spider_engine.legs end)
  check(failed, legs == 4, "Beine " .. tostring(legs) .. " statt 4")
  local burner = p.burner_prototype
  local chemical = burner and read(function() return burner.fuel_categories["chemical"] end)
  check(failed, chemical == true, "Brenner ohne Kategorie chemical")
  local slots = burner and burner.fuel_inventory_size
  check(failed, slots == 2, "Brennstoff-Slots " .. tostring(slots) .. " statt 2")
  table.insert(parts, string.format("%s: %s, %s Beine, Brenner chemical %s, %s Slots", FLYER, tostring(p.type),
    tostring(legs), tostring(chemical == true), tostring(slots)))
  for _, name in ipairs({STICKER_EMPTY, STICKER_LOADED}) do
    local sticker = prototypes.entity[name]
    check(failed, sticker ~= nil and sticker.type == "sticker", "Sticker " .. name .. " fehlt")
  end
  local sprites, missing = 0, {}
  for i = 0, 15 do
    for _, prefix in ipairs({IMAGE_SPRITE, SHADOW_SPRITE}) do
      if helpers.is_valid_sprite_path(prefix .. i) then
        sprites = sprites + 1
      else
        table.insert(missing, prefix .. i)
      end
    end
  end
  check(failed, sprites == 32, "Lastbild-Sprites " .. sprites .. "/32, fehlen: " .. table.concat(missing, ", "))
  table.insert(parts, "Sticker leer und beladen, Lastbild " .. sprites .. "/32")
  check(failed, prototypes.entity[PROBE] ~= nil, "Probe " .. PROBE .. " fehlt")
  local key = prototypes.custom_input[CARRY_INPUT]
  if check(failed, key ~= nil, "Taste " .. CARRY_INPUT .. " fehlt") then
    table.insert(parts, string.format("Taste %s (%s, consuming %s)", CARRY_INPUT, tostring(key.key_sequence), tostring(key.consuming)))
  end
  local carry = prototypes.shortcut[CARRY_SHORTCUT]
  if check(failed, carry ~= nil, "Verknüpfung " .. CARRY_SHORTCUT .. " fehlt") then
    check(failed, carry.action == "lua", "Verknüpfung " .. CARRY_SHORTCUT .. ": action " .. tostring(carry.action) .. " statt lua")
    local tech = carry.technology_to_unlock
    check(failed, tech ~= nil and tech.name == ORNITHOPTER_TECH, "Verknüpfung " .. CARRY_SHORTCUT .. " hängt nicht an " .. ORNITHOPTER_TECH)
  end
  local remote_shortcut = prototypes.shortcut[REMOTE_SHORTCUT]
  if check(failed, remote_shortcut ~= nil, "Verknüpfung " .. REMOTE_SHORTCUT .. " fehlt") then
    local item = remote_shortcut.item_to_spawn
    check(failed, item ~= nil and item.name == REMOTE_ITEM, "Verknüpfung " .. REMOTE_SHORTCUT .. " gibt " .. tostring(item and item.name) .. " statt " .. REMOTE_ITEM)
    local tech = remote_shortcut.technology_to_unlock
    check(failed, tech ~= nil and tech.name == ORNITHOPTER_TECH, "Verknüpfung " .. REMOTE_SHORTCUT .. " hängt nicht an " .. ORNITHOPTER_TECH)
  end
  table.insert(parts, "Probe, Verknüpfungen " .. CARRY_SHORTCUT .. " und " .. REMOTE_SHORTCUT)
  tb.log(run, "INFO", "1) allow_remote_driving ist zur Laufzeit nicht lesbar (kein Feld in LuaEntityPrototype); geprüft in der"
    .. " Datenphase (tools/check/checks.lua, 3c) und mit dir in T17 Schritt 6")
  return verdict(run, tb, 1, "Prototypen", failed, table.concat(parts, "; "))
end

-- Schritt 2: Forschung [U11]. Die Force behält ihren Stand von Lauf zu Lauf, deshalb erst herstellen: „Spice-Ernte“
-- erforscht, „Ornithopter“ nicht, Herstellzähler 0, Rezept frei. Dann a) von Hand, b) Montagemaschine 3, c) MESSUNG.

-- Zutaten des Ernter-Rezepts (prototypes/harvester.lua:171–177).
local S2_INGREDIENTS =
{
  {name = "steel-plate", count = 40},
  {name = "engine-unit", count = 20},
  {name = "advanced-circuit", count = 10},
  {name = "stone-brick", count = 100},
  {name = "melange", count = 10}
}
local S2_HAND_ITEM = 660       -- 10 s von Hand (Tempo 1) plus 1 s
local S2_MACHINE_ITEM = 540    -- 10 s / 1,25 = 480 Ticks plus 1 s
local S2_RESEARCH = 60

-- Warum migrate.ornithopter_research für die Force true gäbe (vor dem Lauf schon ein Ernter da).
function t15_steps.s2_reason(force)
  for _, h in pairs(storage.harvesters) do
    if h.entity.valid and h.entity.force.index == force.index then return "Ernter-Datensatz der Force (Nr. " .. h.un .. ")" end
  end
  for _, surface in pairs(game.surfaces) do
    local count = read(function() return force.get_item_production_statistics(surface).get_input_count(NAME) end)
    if count and count > 0 then return string.format("Herstellzähler %s auf %s = %d", NAME, surface.name, count) end
  end
  return "unbekannt"
end

function t15_steps.s2_start(run, tb, d)
  local s = d.s2
  local force = t15_force()
  s.force = force
  local ornithopter = force.technologies[ORNITHOPTER_TECH]
  local harvesting = force.technologies[HARVESTING_TECH]
  if not (ornithopter and harvesting) then return fail(run, tb, 2, "Technologien " .. HARVESTING_TECH .. "/" .. ORNITHOPTER_TECH .. " fehlen") end
  harvesting.researched = true
  ornithopter.researched = false
  for _, surface in pairs(game.surfaces) do
    pcall(function() force.get_item_production_statistics(surface).set_input_count(NAME, 0) end)
  end
  force.recipes[NAME].enabled = true
  if migrate.ornithopter_research(force) then
    ornithopter.researched = false
    tb.log(run, "INFO", "2) nicht prüfbar: migrate.ornithopter_research gibt schon vor dem Herstellen true (" .. t15_steps.s2_reason(force)
      .. "); „Ornithopter“ wieder auf nicht erforscht gesetzt")
    run.data.results[2] = "INFO"
    return "end"
  end
  local c = d.pos.s2
  local character = create(run, tb, {name = "character", position = at(c, 0.5, 0.5), force = force})
  s.character = character
  if not character then return fail(run, tb, 2, "Figur der Force " .. T15_FORCE .. " ließ sich nicht erzeugen") end
  local inventory = character.get_inventory(defines.inventory.character_main)
  local missing = {}
  for _, ingredient in ipairs(S2_INGREDIENTS) do
    local n = inventory and inventory.insert{name = ingredient.name, count = ingredient.count} or 0
    if n < ingredient.count then table.insert(missing, ingredient.name .. " " .. n .. "/" .. ingredient.count) end
  end
  if #missing > 0 then return fail(run, tb, 2, "Zutaten passen nicht ins Inventar der Figur: " .. table.concat(missing, ", ")) end
  local ok, started = pcall(function() return character.begin_crafting{count = 1, recipe = NAME, silent = true} end)
  s.started = ok and started or 0
  s.craft_tick = game.tick
  tb.trace(run, "2) a) begin_crafting{recipe = " .. NAME .. ", count = 1}: " .. (ok and tostring(started) or ("Fehler " .. tostring(started))))
  if s.started == 0 then
    tb.log(run, "INFO", "2) a) begin_crafting startete nichts (" .. (ok and "Rückgabe 0" or tostring(started)) .. "); weiter mit der Montagemaschine")
    s.hand_skipped = true
  end
  return 1
end

-- a) Item im Inventar der Figur, dann Forschung.
function t15_steps.s2_hand(run, tb, d)
  local s = d.s2
  if s.hand_skipped then return 1 end
  local force = s.force
  local inventory = valid(s.character) and s.character.get_inventory(defines.inventory.character_main)
  local count = inventory and inventory.get_item_count(NAME) or 0
  local waited = game.tick - s.craft_tick
  if not s.item_tick then
    if count > 0 then
      s.item_tick = game.tick
      tb.trace(run, "2) a) Item von Hand nach " .. waited .. " Ticks")
    elseif waited > S2_HAND_ITEM then
      tb.log(run, "INFO", "2) a) kein Item bis Tick " .. S2_HAND_ITEM .. " nach begin_crafting (eine Figur ohne Spieler craftet womöglich nie); weiter mit der Montagemaschine")
      s.hand_skipped = true
      return 1
    end
    return "poll"
  end
  local researched = force.technologies[ORNITHOPTER_TECH].researched
  if researched then
    s.research_ticks = game.tick - s.item_tick
    s.done = "a"
    return 1
  end
  if game.tick - s.item_tick > S2_RESEARCH then
    s.done = "a"
    s.research_failed = true
    return 1
  end
  return "poll"
end

-- b) Montagemaschine 3 (Tempo 1,25) mit Strom wie scripts/testbench/t_harvester.lua:1145–1146, nur wenn a) kein Item gab.
function t15_steps.s2_machine_build(run, tb, d)
  local s = d.s2
  if s.done then return 1 end
  local force = s.force
  local c = at(d.pos.s2, 12, 0)
  s.machine = create(run, tb, {name = "assembling-machine-3", position = at(c, 0.5, 0.5), force = force})
  s.pole = create(run, tb, {name = "medium-electric-pole", position = at(c, 2.5, 0.5), force = force})
  s.power = create(run, tb, {name = "electric-energy-interface", position = at(c, 4, 1), force = force})
  if not (s.machine and s.pole and s.power) then return fail(run, tb, 2, "Montagemaschine, Mast oder Stromquelle ließ sich nicht bauen") end
  local ok_recipe, err_recipe = pcall(function() s.machine.set_recipe(NAME) end)
  if not ok_recipe then return fail(run, tb, 2, "set_recipe(" .. NAME .. ") ging nicht: " .. tostring(err_recipe)) end
  local input = s.machine.get_inventory(defines.inventory.crafter_input)
  local missing = {}
  for _, ingredient in ipairs(S2_INGREDIENTS) do
    local n = input and input.insert{name = ingredient.name, count = ingredient.count} or 0
    if n < ingredient.count then table.insert(missing, ingredient.name .. " " .. n .. "/" .. ingredient.count) end
  end
  if #missing > 0 then return fail(run, tb, 2, "Zutaten passen nicht in die Montagemaschine: " .. table.concat(missing, ", ")) end
  s.recipe_tick = game.tick
  s.item_tick = nil
  return 1
end

function t15_steps.s2_machine(run, tb, d)
  local s = d.s2
  if s.done then return 1 end
  local force = s.force
  local output = valid(s.machine) and s.machine.get_inventory(defines.inventory.crafter_output)
  local count = output and output.get_item_count(NAME) or 0
  if not s.item_tick then
    if count > 0 then
      s.item_tick = game.tick
      tb.trace(run, "2) b) Item aus der Montagemaschine nach " .. (game.tick - s.recipe_tick) .. " Ticks")
    elseif game.tick - s.recipe_tick > S2_MACHINE_ITEM then
      s.done = "c"
      return 1
    end
    return "poll"
  end
  if force.technologies[ORNITHOPTER_TECH].researched then
    s.research_ticks = game.tick - s.item_tick
    s.done = "b"
    return 1
  end
  if game.tick - s.item_tick > S2_RESEARCH then
    s.done = "b"
    s.research_failed = true
    return 1
  end
  return "poll"
end

function t15_steps.s2_check(run, tb, d)
  local s = d.s2
  if s.done == "c" then
    tb.log(run, "MESSUNG", "2) c) auch aus der Montagemaschine kein Item bis Tick " .. S2_MACHINE_ITEM
      .. " nach set_recipe; die Forschung prüfst du von Hand (Abnahme, docs/plan-3c.md 8)")
    run.data.results[2] = "MESSUNG"
    return "end"
  end
  local how = s.done == "a" and "a) von Hand" or "b) Montagemaschine 3"
  local item_ticks = s.done == "a" and (s.item_tick - s.craft_tick) or (s.item_tick - s.recipe_tick)
  local failed = {}
  check(failed, not s.research_failed, "Item da, „Ornithopter“ " .. S2_RESEARCH .. " Ticks später nicht erforscht")
  return verdict(run, tb, 2, "Forschung „Ornithopter“ beim ersten Ernter [U11]", failed, string.format(
    "%s: Item nach %d Ticks, erforscht %s", how, item_ticks,
    s.research_ticks and ("nach " .. s.research_ticks .. " Ticks") or "nicht"))
end

-- Schritt 3: Anheben mit Insassen [U14].

-- Gegenprobe zu Stufe 0 (Plan 4.7): flyer.lua gibt die Stufe nicht heraus (lift ist lokal, nur das Log nennt Stufe 1).
-- Deshalb dieselbe Lage von Hand: Ernter mit Puppe, Ornithopter 2 Kacheln daneben; set_driver(nil) stellt die Puppe
-- neben den Ernter, dann set_driver(Puppe) am Ornithopter und zurücklesen. Sitzt sie, griff beim echten Anheben
-- Stufe 0 (gleich gesetzt), sonst Stufe 1 (erst nach dem Teleport an den Ornithopter).
function t15_steps.s3_counter(run, tb, d)
  local s = d.s3
  local c = at(d.pos.s3, 40, 0)
  local car = new_car(run, tb, at(c, 0.5, 0.5), {})
  local flyer = new_flyer(run, tb, at(c, 0.5, -1.5), {})
  local dummy = car and new_dummy(run, tb, car)
  if not (car and flyer and dummy) then
    s.counter = "Gegenprobe nicht aufgebaut"
    return
  end
  car.set_driver(dummy)
  if car.get_driver() ~= dummy then
    s.counter = "Gegenprobe: Puppe ließ sich nicht in den Ernter setzen"
    return
  end
  car.set_driver(nil)
  local gap = tb.distance(dummy.position, flyer.position)
  local ok = pcall(function() flyer.set_driver(dummy) end)
  local seated = ok and flyer.get_driver() == dummy
  s.counter_stage = seated and 0 or 1
  s.counter = string.format("Gegenprobe: nach set_driver(nil) %s Kacheln vom Ornithopter, set_driver dort %s",
    tb.num(gap), seated and "greift (also Stufe 0, gleich gesetzt)" or "greift nicht (also Stufe 1, nach dem Teleport)")
end

function t15_steps.s3_build(run, tb, d)
  local s = d.s3
  local c = d.pos.s3
  t15_steps.s3_counter(run, tb, d)
  tb.trace(run, "3) " .. s.counter)
  local cells = {a = at(c, 0, 0), b = at(c, 20, 0)}
  for key, p in pairs(cells) do
    local cell = {}
    s[key] = cell
    cell.flyer = new_flyer(run, tb, at(p, 0.5, -1.5), {fuel = "coal", pilot = key == "a"})
    cell.car = new_car(run, tb, at(p, 0.5, 0.5), {coal = 2})
    if not (cell.flyer and cell.car) then return fail(run, tb, 3, "Aufbau " .. key .. ") ging nicht") end
    cell.pilot = cell.flyer.get_driver()
    if key == "a" and not valid(cell.pilot) then return fail(run, tb, 3, "a) Pilot-Puppe sitzt nicht im Ornithopter") end
    cell.driver = new_dummy(run, tb, cell.car)
    cell.passenger = new_dummy(run, tb, cell.car)
    if not (cell.driver and cell.passenger) then return fail(run, tb, 3, "Puppen für " .. key .. ") ließen sich nicht erzeugen") end
    cell.car.set_driver(cell.driver)
    cell.car.set_passenger(cell.passenger)
    if seat_of(cell.car, cell.driver) ~= "Pilot" or seat_of(cell.car, cell.passenger) ~= "Beifahrer" then
      return fail(run, tb, 3, key .. ") Fahrer und Beifahrer sitzen nicht im Ernter")
    end
    cell.lift = copy_pos(cell.car.position)
    cell.result = {couple(cell.flyer, cell.car)}
  end
  return COUPLE_WAIT
end

function t15_steps.s3_lifted(run, tb, d)
  local s = d.s3
  local failed, parts = {}, {}
  local stage = s.counter_stage == 0 and "Stufe 0" or (s.counter_stage == 1 and "Stufe 1" or "Stufe unbekannt")
  for _, key in ipairs({"a", "b"}) do
    local cell = s[key]
    local label = key .. ")"
    check(failed, cell.result[1] == true and cell.result[2] == "coupling", label .. " toggle_carry " .. result_text(cell.result[1], cell.result[2]))
    check_carried(failed, label, cell.car, cell.flyer)
    check_loaded(failed, label, cell.flyer, cell.car)
    check(failed, valid(cell.car) and cell.car.get_driver() == nil and cell.car.get_passenger() == nil, label .. " Ernter hat noch Insassen")
    local driver_seat = seat_of(cell.flyer, cell.driver)
    local passenger_seat = seat_of(cell.flyer, cell.passenger)
    if key == "a" then
      check(failed, seat_of(cell.flyer, cell.pilot) == "Pilot", "a) Pilot sitzt nicht mehr")
      check(failed, driver_seat == "Beifahrer", "a) Fahrer ist " .. tostring(driver_seat) .. " statt Beifahrer")
      local gap = valid(cell.passenger) and cell.passenger.surface.name == tb.surface().name and tb.distance(cell.passenger.position, cell.lift)
      check(failed, passenger_seat == nil and gap and gap <= SEAT_RANGE, "a) Beifahrer nicht am Boden ≤ " .. SEAT_RANGE .. " Kacheln (Abstand "
        .. tostring(gap and tb.num(gap)) .. ", Sitz " .. tostring(passenger_seat) .. ")")
      tb.trace(run, string.format("3) a) Fahrer → %s im Ornithopter (%s laut Gegenprobe); Beifahrer am Boden, %s Kacheln vom Abhebepunkt",
        tostring(driver_seat), stage, tostring(gap and tb.num(gap))))
      table.insert(parts, string.format("a) Pilot bleibt, Fahrer → %s, Beifahrer am Boden %s Kacheln", tostring(driver_seat), tostring(gap and tb.num(gap))))
    else
      check(failed, driver_seat == "Pilot", "b) Fahrer ist " .. tostring(driver_seat) .. " statt Pilot")
      check(failed, passenger_seat == "Beifahrer", "b) Beifahrer ist " .. tostring(passenger_seat) .. " statt Beifahrer")
      tb.trace(run, string.format("3) b) Fahrer → %s, Beifahrer → %s im Ornithopter (%s laut Gegenprobe)",
        tostring(driver_seat), tostring(passenger_seat), stage))
      table.insert(parts, string.format("b) Fahrer → %s, Beifahrer → %s", tostring(driver_seat), tostring(passenger_seat)))
    end
    if valid(cell.car) then table.insert(parts, label .. " Platz " .. pos_text(tb, cell.car.position)) end
    cell.seats = {seat_of(cell.flyer, cell.pilot), driver_seat, passenger_seat}
    tb.trace(run, "3) " .. label .. " angehoben: " .. car_text(tb, cell.car) .. "; " .. flyer_text(tb, cell.flyer))
  end
  -- Absetzen: Sitze bleiben (Plan 4.7).
  local drops = {}
  for _, key in ipairs({"a", "b"}) do
    local cell = s[key]
    local ok, reason = toggle(cell.flyer)
    table.insert(drops, key .. ") " .. result_text(ok, reason))
    check(failed, ok and reason == "dropped", key .. ") Absetzen " .. result_text(ok, reason))
    check_mobile(failed, key .. ") nach dem Absetzen", cell.car, tb)
    local seats = {seat_of(cell.flyer, cell.pilot), seat_of(cell.flyer, cell.driver), seat_of(cell.flyer, cell.passenger)}
    check(failed, seats[1] == cell.seats[1] and seats[2] == cell.seats[2] and seats[3] == cell.seats[3], key .. ") Sitze nach dem Absetzen anders")
    check(failed, valid(cell.car) and cell.car.get_driver() == nil, key .. ") nach dem Absetzen sitzt jemand im Ernter")
  end
  table.insert(parts, "Absetzen " .. table.concat(drops, ", ") .. ", Sitze gleich")
  table.insert(parts, s.counter)
  return verdict(run, tb, 3, "Anheben mit Insassen [U14]", failed, table.concat(parts, "; "))
end

-- Schritt 4: Ankoppeln a) Flieger fliegt weg, b) zweiter Aufruf, c) Entprellen, d) Ernter stirbt, e) zweiter Flieger.

function t15_steps.s4_build(run, tb, d)
  local s = d.s4
  local c = d.pos.s4
  for i, key in ipairs({"a", "b", "c", "d", "e"}) do
    local cell = {}
    s[key] = cell
    cell.flyer, cell.car = new_pair(run, tb, at(c, (i - 1) * 20, 0), {pilot = key == "a"})
    if not (cell.flyer and cell.car) then return fail(run, tb, 4, "Aufbau " .. key .. ") ging nicht") end
  end
  s.e.second = new_flyer(run, tb, at(c, 80.5, 2), {})
  if not s.e.second then return fail(run, tb, 4, "zweiter Ornithopter für e) ging nicht") end
  for _, key in ipairs({"a", "b", "c", "d", "e"}) do
    local cell = s[key]
    cell.result = {couple(cell.flyer, cell.car)}
    local record = flyer_lib.get(cell.flyer)
    cell.ring = record and record.renders.ring
    cell.ring_start = render_ok(cell.ring)
  end
  s.start = game.tick
  return 5
end

function t15_steps.s4_debounce(run, tb, d)
  local s = d.s4
  s.c.second = {toggle(s.c.flyer)}
  s.c.still = flyer_state(s.c.flyer)
  s.e.blocked = {couple(s.e.second, s.e.car)}
  return 25
end

function t15_steps.s4_inputs(run, tb, d)
  local s = d.s4
  local start = copy_pos(s.a.flyer.position)
  s.a.from = start
  local ok_go = pcall(function() s.a.flyer.autopilot_destination = {x = start.x + 10, y = start.y} end)
  s.a.go = ok_go
  s.b.second = {toggle(s.b.flyer)}
  s.b.after = flyer_state(s.b.flyer)
  s.b.ring_after = render_ok(s.b.ring)
  local ok_die, err_die = pcall(function() s.d.car.die() end)
  s.d.die = ok_die and "ok" or tostring(err_die)
  s.d.after = flyer_state(s.d.flyer)
  s.d.ring_after = render_ok(s.d.ring)
  return 100
end

function t15_steps.s4_check(run, tb, d)
  local s = d.s4
  local failed = {}
  for _, key in ipairs({"a", "b", "c", "d", "e"}) do
    local cell = s[key]
    check(failed, cell.result[1] == true and cell.result[2] == "coupling" and cell.ring_start,
      key .. ") Kopplung startet nicht (" .. result_text(cell.result[1], cell.result[2]) .. ", Ring " .. tostring(cell.ring_start) .. ")")
  end
  -- a) weggeflogen
  local a = s.a
  local a_record = flyer_lib.get(a.flyer)
  local a_gap = valid(a.flyer) and valid(a.car) and tb.distance(a.flyer.position, a.car.position)
  check(failed, a.go, "a) autopilot_destination ging nicht")
  check(failed, car_state(a.car) ~= "carried", "a) trotzdem angehoben")
  check(failed, a_record ~= nil and a_record.coupling == nil and not storage.couplings[a.flyer.unit_number], "a) Kopplung noch da")
  check(failed, not render_ok(a.ring), "a) Ring noch da")
  -- b) zweiter Aufruf
  local b = s.b
  check(failed, b.second[1] == true and b.second[2] == "aborted", "b) zweiter Aufruf " .. result_text(b.second[1], b.second[2]))
  check(failed, b.after == "leer" and not b.ring_after, "b) nach dem Abbruch " .. tostring(b.after) .. ", Ring " .. tostring(b.ring_after))
  check(failed, car_state(b.car) ~= "carried", "b) trotzdem angehoben")
  -- c) Entprellen
  local c = s.c
  check(failed, c.second[1] == false and c.second[2] == "debounce", "c) Aufruf nach 5 Ticks " .. result_text(c.second[1], c.second[2]))
  check(failed, c.still == "koppelt", "c) nach 5 Ticks " .. tostring(c.still) .. " statt koppelt")
  check(failed, car_state(c.car) == "carried" and flyer_state(c.flyer) == "beladen", "c) Kopplung lief nicht weiter (" .. car_state(c.car) .. ")")
  -- d) Ernter stirbt
  local dd = s.d
  check(failed, dd.die == "ok", "d) die() mit Skriptfehler: " .. tostring(dd.die))
  check(failed, dd.after == "leer" and not dd.ring_after, "d) nach dem Tod des Ernters " .. tostring(dd.after) .. ", Ring " .. tostring(dd.ring_after))
  check(failed, flyer_state(dd.flyer) == "leer", "d) später " .. flyer_state(dd.flyer))
  -- e) zweiter Flieger
  local e = s.e
  check(failed, e.blocked[1] == false and e.blocked[2] == "busy", "e) zweiter Ornithopter " .. result_text(e.blocked[1], e.blocked[2]))
  check(failed, flyer_state(e.second) == "leer", "e) zweiter Ornithopter " .. flyer_state(e.second))
  tb.trace(run, "4) a) Abstand Ornithopter–Ernter jetzt " .. tostring(a_gap and tb.num(a_gap)) .. "; " .. flyer_text(tb, a.flyer))
  return verdict(run, tb, 4, "Ankoppeln", failed, string.format(
    "a) weggeflogen: %s, Abstand %s; b) %s; c) %s, danach %s; d) Ernter tot: %s; e) %s",
    flyer_state(a.flyer), tostring(a_gap and tb.num(a_gap)), result_text(b.second[1], b.second[2]),
    result_text(c.second[1], c.second[2]), flyer_state(c.flyer), tostring(dd.after), result_text(e.blocked[1], e.blocked[2])))
end

-- Schritt 5: Notstart [U13] aus deploying, deployed, packing und docked; der angedockte dockt nach dem Absetzen wieder an.

local S5_CELLS = {"deploying", "deployed", "packing", "docked"}

function t15_steps.s5_build(run, tb, d)
  local s = d.s5
  local surface = tb.surface()
  local c = d.pos.s5
  s.cases = {}
  for i, key in ipairs({"deploying", "deployed", "packing"}) do
    local p = at(c, (i - 1) * 25, 0)
    place_spice(surface, p.x - 3, p.y - 3, p.x + 3, p.y + 3, 1000)
    local cell = {}
    s.cases[key] = cell
    cell.flyer, cell.car = new_pair(run, tb, p, {coal = 2})
    if not (cell.flyer and cell.car) then return fail(run, tb, 5, "Aufbau " .. key .. " ging nicht") end
  end
  -- Angedockt: Felsinsel, Annahme, Ernter 3,5 Kacheln nördlich (Andockkreis 4); der Ornithopter genau darüber, damit
  -- die Probe beim Absetzen dort passt (Kasten ±1,6 gegen Annahme ±0,9: 1 Kachel Luft) und der Ernter im Kreis bleibt.
  local o = d.pos.s5_dock
  tb.fill({{o.x - 8, o.y - 8}, {o.x + 8, o.y + 8}}, ROCK, surface)
  s.intake = create(run, tb, {name = INTAKE, position = o, force = force_of(run, tb), raise_built = true})
  local record = s.intake and intake.get(s.intake)
  if not (record and not record.bad) then return fail(run, tb, 5, "Annahme auf der Felsinsel nicht richtig eingetragen") end
  s.intake_record = record
  local cell = {}
  s.cases.docked = cell
  cell.car = new_car(run, tb, at(o, 0, -3.5), {})
  cell.flyer = new_flyer(run, tb, at(o, 0, -3.5), {fuel = "coal"})
  if not (cell.car and cell.flyer) then return fail(run, tb, 5, "Aufbau docked ging nicht") end
  for _, key in ipairs({"deployed", "packing"}) do
    s.cases[key].toggle = harvester.toggle(s.cases[key].car, nil)
  end
  return harvester.DEPLOY_TICKS + 10
end

function t15_steps.s5_couple(run, tb, d)
  local s = d.s5
  local cells = s.cases
  if car_state(cells.deployed.car) ~= "deployed" or car_state(cells.packing.car) ~= "deployed" then
    return fail(run, tb, 5, "Aufbauen nach 310 Ticks nicht fertig: " .. car_state(cells.deployed.car) .. ", " .. car_state(cells.packing.car))
  end
  if car_state(cells.docked.car) ~= "docked" then
    return fail(run, tb, 5, "Ernter an der Annahme dockt nicht an (" .. car_state(cells.docked.car) .. ")")
  end
  cells.packing.toggle = harvester.toggle(cells.packing.car, nil)
  cells.deploying.toggle = harvester.toggle(cells.deploying.car, nil)
  for _, key in ipairs(S5_CELLS) do
    local cell = cells[key]
    local h = harvester.get(cell.car)
    cell.before = h and h.state
    cell.ring = h and h.renders.ring
    cell.frame = h and h.renders.frame
    cell.had_render = render_ok(cell.ring) or render_ok(cell.frame)
    cell.result = {couple(cell.flyer, cell.car)}
  end
  s.targets_before = valid(s.intake) and s.intake.proxy_target_entity ~= nil
  return COUPLE_WAIT
end

function t15_steps.s5_lifted(run, tb, d)
  local s = d.s5
  local failed, parts = {}, {}
  s.table = {}
  for _, key in ipairs(S5_CELLS) do
    local cell = s.cases[key]
    local cell_failed = {}
    check(cell_failed, cell.before == key, key .. ": vorher " .. tostring(cell.before))
    check(cell_failed, cell.result[1] == true, key .. ": toggle_carry " .. result_text(cell.result[1], cell.result[2]))
    check_carried(cell_failed, key, cell.car, cell.flyer)
    check_loaded(cell_failed, key, cell.flyer, cell.car)
    local h = harvester.get(cell.car)
    local un = valid(cell.car) and cell.car.unit_number
    check(cell_failed, un and not storage.timers[un] and not storage.driven[un], key .. ": noch in storage.timers/driven")
    check(cell_failed, h ~= nil and not render_ok(h.renders.ring) and not render_ok(h.renders.frame)
      and not render_ok(cell.ring) and not render_ok(cell.frame), key .. ": Ring oder Feldrahmen noch da")
    if key == "docked" then
      check(cell_failed, s.targets_before, "docked: Annahme zeigte vorher nicht auf den Ernter")
      check(cell_failed, valid(s.intake) and s.intake.proxy_target_entity == nil, "docked: Annahme zeigt noch auf den Ernter")
      check(cell_failed, s.intake_record.docked == nil and h ~= nil and h.dock == nil, "docked: Andock-Eintrag noch da")
    end
    for _, label in ipairs(cell_failed) do table.insert(failed, label) end
    s.table[key] = #cell_failed == 0 and "OK" or table.concat(cell_failed, "; ")
    table.insert(parts, key .. " → " .. car_state(cell.car))
  end
  s.parts = parts
  s.failed = failed
  local cell = s.cases.docked
  local ok, reason = toggle(cell.flyer)
  s.drop = {ok, reason}
  s.drop_tick = game.tick
  if not (ok and reason == "dropped") then
    table.insert(failed, "docked: Absetzen über der Annahme " .. result_text(ok, reason))
    return verdict(run, tb, 5, "Notstart [U13]", failed, table.concat(parts, ", "))
  end
  s.drop_gap = tb.distance(cell.car.position, s.intake.position)
  return 1
end

function t15_steps.s5_redock(run, tb, d)
  local s = d.s5
  local cell = s.cases.docked
  local waited = game.tick - s.drop_tick
  if car_state(cell.car) ~= "docked" then
    if waited > DOCK_WAIT then
      table.insert(s.failed, "docked: nach " .. waited .. " Ticks nicht wieder angedockt (" .. car_text(tb, cell.car) .. ")")
      return verdict(run, tb, 5, "Notstart [U13]", s.failed, table.concat(s.parts, ", "))
    end
    return "poll"
  end
  table.insert(s.parts, string.format("docked abgesetzt %s Kacheln von der Annahme, nach %d Ticks wieder angedockt", tb.num(s.drop_gap), waited))
  return verdict(run, tb, 5, "Notstart [U13]", s.failed, table.concat(s.parts, ", "))
end

-- Schritt 6: Voller Ernter von Feld A nach B [U13, U28] (Roadmap 3c, DOC 2.1 Schritt 11).

-- Felder des Vergleichs wie T3 (scripts/testbench/t_harvester.lua, T3_FIELDS) ohne Label und minable_flag.
local S6_FIELDS =
{
  {key = "trunk", label = "Kofferraum"},
  {key = "fuel", label = "Treibstoff"},
  {key = "remaining", label = "Restbrennwert", tolerance = 1},
  {key = "burning", label = "brennendes Item"},
  {key = "health", label = "Gesundheit", tolerance = 0.01},
  {key = "quality", label = "Qualität"},
  {key = "color", label = "Farbe"},
  {key = "unit_number", label = "unit_number"},
  {key = "orientation", label = "Ausrichtung", tolerance = 0.001}
}
local S6_FLIGHT = 40 * 60
local S6_ARRIVE = 1.5

function t15_steps.s6_snapshot(car)
  local burner = car.burner
  return
  {
    trunk = contents_text(car.get_inventory(defines.inventory.car_trunk)),
    fuel = contents_text(car.get_fuel_inventory()),
    remaining = burner and read(function() return burner.remaining_burning_fuel end),
    burning = burner and read(function() return item_pair_name(burner.currently_burning) end),
    health = read(function() return car.health end),
    quality = read(function() return car.quality.name end),
    color = color_text(read(function() return car.color end)),
    unit_number = car.unit_number,
    orientation = read(function() return car.orientation end)
  }
end

function t15_steps.s6_value(tb, value)
  if type(value) == "number" then return tb.num(value, 3) end
  return tostring(value)
end

function t15_steps.s6_build(run, tb, d)
  local s = d.s6
  local surface = tb.surface()
  local a, b = d.pos.s6_a, d.pos.s6_b
  s.area_a = {{a.x - 7, a.y - 7}, {a.x + 8, a.y + 8}}
  s.area_b = {{b.x - 7, b.y - 7}, {b.x + 8, b.y + 8}}
  place_spice(surface, a.x - 7, a.y - 7, a.x + 7, a.y + 7, 1000)
  place_spice(surface, b.x - 7, b.y - 7, b.x + 7, b.y + 7, 1000)
  s.quality = quality_exists("uncommon")
  local car = new_car(run, tb, at(a, 0.5, 0.5), {orientation = 0.375, quality = s.quality and "uncommon" or nil})
  s.car = car
  if not car then return fail(run, tb, 6, "Ernter ließ sich nicht erzeugen") end
  local notes = {}
  -- Treibstoff wie T3: 20 Kohle und ein laufender Brennvorgang mit krummem Restwert, Puffer voll.
  s.coal = tb.fuel(car, "coal", 20)
  local burner = car.burner
  if burner then
    local ok_burn = pcall(function()
      burner.currently_burning = "coal"
      burner.remaining_burning_fuel = 2500000
    end)
    if not ok_burn then table.insert(notes, "Brennvorgang setzen ging nicht") end
    if not pcall(function() burner.heat = burner.heat_capacity end) then table.insert(notes, "Puffer füllen ging nicht") end
  end
  if not pcall(function() car.health = car.max_health * 0.6 end) then table.insert(notes, "Gesundheit setzen ging nicht") end
  pcall(function() car.color = CAR_COLOR end)
  pcall(function() car.orientation = 0.375 end)
  -- Kofferraum voll: 40 Slots (prototypes/harvester.lua:62), Spice-Sand stapelt 50 (prototypes/resources.lua:53).
  -- Gefüllt wird vor dem Aufbauen: Ein aufgebauter Ernter mit Platz förderte sonst sofort, und 1900 Spice-Sand passten
  -- nicht mehr in 38 Slots. Der volle Kofferraum hält den Abbau an; bis zum Anheben ändert sich nichts.
  local trunk = car.get_inventory(defines.inventory.car_trunk)
  -- 38 Slots Spice-Sand, ein Slot 100 Eisenplatten (stapelt 100), ein letzter Slot Eisenplatten selten (Qualität im
  -- Kofferraum, wie T3) oder ohne Quality 50 normale. Auf B gibt die Entnahme der 100 Eisenplatten einen Slot frei.
  local wanted = {{SPICE, 1900}, {"iron-plate", 100}, {"iron-plate", 50}}
  if quality_exists("rare") then wanted[3] = {"iron-plate", 10, "rare"} end
  local filled = {}
  for _, item in ipairs(wanted) do
    local ok, n = pcall(function() return trunk.insert{name = item[1], count = item[2], quality = item[3]} end)
    n = ok and n or 0
    table.insert(filled, item[1] .. (item[3] and ("@" .. item[3]) or "") .. " " .. n)
    if n < item[2] then return fail(run, tb, 6, "Kofferraum füllen: " .. item[1] .. " nur " .. n .. "/" .. item[2]) end
  end
  check(notes, not trunk.can_insert{name = SPICE, count = 1}, "Kofferraum nicht voll")
  -- Puppe wie T3 vor dem Einsteigen färben (scripts/testbench/t_harvester.lua:737–771), dann einsteigen.
  local driver = new_dummy(run, tb, car)
  s.driver = driver
  if not driver then return fail(run, tb, 6, "Fahrer-Puppe ließ sich nicht erzeugen") end
  pcall(function() driver.color = DRIVER_COLOR end)
  car.set_driver(driver)
  if seat_of(car, driver) ~= "Pilot" then return fail(run, tb, 6, "Fahrer-Puppe sitzt nicht im Ernter") end
  s.deploy = harvester.toggle(car, nil)
  s.spice_a = spice_in(surface, s.area_a)
  s.spice_b = spice_in(surface, s.area_b)
  tb.trace(run, string.format("6) Teppiche A %s und B %s (je 15×15, Menge 1000), Ernter Nr. %d, Qualität %s, Kofferraum %s, %d Kohle%s",
    pos_text(tb, a), pos_text(tb, b), car.unit_number, tostring(read(function() return car.quality.name end)),
    table.concat(filled, ", "), s.coal, #notes > 0 and ("; " .. table.concat(notes, "; ")) or ""))
  if not s.deploy then return fail(run, tb, 6, "Aufbauen auf A: toggle gab false (" .. car_text(tb, car) .. ")") end
  return harvester.DEPLOY_TICKS + 10
end

function t15_steps.s6_lift(run, tb, d)
  local s = d.s6
  local car = s.car
  if car_state(car) ~= "deployed" then return fail(run, tb, 6, "Aufbauen auf A nicht fertig: " .. car_state(car)) end
  local flyer = new_flyer(run, tb, at(car.position, 0, -1.5), {fuel = "coal", count = 20, pilot = true})
  s.flyer = flyer
  if not flyer then return fail(run, tb, 6, "Ornithopter ließ sich nicht erzeugen") end
  s.pilot = flyer.get_driver()
  -- Vorher-Stand unmittelbar vor toggle_carry, mit sitzendem Fahrer.
  s.before = t15_steps.s6_snapshot(car)
  s.free_before = free_slots()
  s.result = {couple(flyer, car)}
  if not s.result[1] then return fail(run, tb, 6, "toggle_carry " .. result_text(s.result[1], s.result[2])) end
  return COUPLE_WAIT
end

function t15_steps.s6_fly(run, tb, d)
  local s = d.s6
  local failed = {}
  check_carried(failed, "Anheben", s.car, s.flyer)
  check_loaded(failed, "Anheben", s.flyer, s.car)
  if #failed > 0 then return fail(run, tb, 6, "Anheben aus deployed: " .. table.concat(failed, "; ")) end
  local b = d.pos.s6_b
  s.target = {x = b.x + 0.5, y = b.y + 0.5}
  s.from = copy_pos(s.flyer.position)
  s.energy_before = fuel_energy(s.flyer)
  local ok, err = pcall(function() s.flyer.autopilot_destination = s.target end)
  if not ok then return fail(run, tb, 6, "autopilot_destination ging nicht: " .. tostring(err)) end
  s.fly_tick = game.tick
  return 1
end

-- Ankunft per on_spider_command_completed (t15_on_event); höchstens 40 s [U28].
function t15_steps.s6_wait(run, tb, d)
  local s = d.s6
  if not valid(s.flyer) then return fail(run, tb, 6, "Ornithopter im Flug verschwunden") end
  if not s.arrived_tick then
    if game.tick - s.fly_tick > S6_FLIGHT then
      return fail(run, tb, 6, string.format("keine Ankunft in 40 s [U28]: Ornithopter bei %s, Ziel %s, %s", pos_text(tb, s.flyer.position),
        pos_text(tb, s.target), flyer_state(s.flyer)))
    end
    return "poll"
  end
  local failed, parts = {}, {}
  local flight = s.arrived_tick - s.fly_tick
  local distance = tb.distance(s.from, s.arrival)
  local energy = s.energy_before and fuel_energy(s.flyer)
  local ok, reason = toggle(s.flyer)
  check(failed, ok and reason == "dropped", "Absetzen über B " .. result_text(ok, reason))
  check_mobile(failed, "über B", s.car, tb)
  local after = valid(s.car) and t15_steps.s6_snapshot(s.car) or {}
  local same = 0
  for _, field in ipairs(S6_FIELDS) do
    local a, b = s.before[field.key], after[field.key]
    local equal = a == b or (type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (field.tolerance or 0))
    if equal then
      same = same + 1
    else
      table.insert(failed, field.label .. " vorher " .. t15_steps.s6_value(tb, a) .. ", jetzt " .. t15_steps.s6_value(tb, b))
    end
  end
  local gap = valid(s.car) and tb.distance(s.car.position, s.arrival)
  check(failed, gap and gap <= S6_ARRIVE, "Ernter " .. tostring(gap and tb.num(gap)) .. " Kacheln von der Ankunftsstelle")
  local seat = seat_of(s.flyer, s.driver)
  check(failed, seat ~= nil, "der Fahrer sitzt nicht mehr im Ornithopter")
  local free_after = free_slots()
  check(failed, free_after == s.free_before, "Ablage: frei vorher " .. s.free_before .. ", jetzt " .. free_after)
  tb.trace(run, string.format("6) Flug A → B: %d Ticks, %s Kacheln, %s Kacheln/s, Brennwert %s kJ verbraucht; Fahrer %s im Ornithopter",
    flight, tb.num(distance), tb.num(distance / math.max(1, flight) * 60, 2),
    (s.energy_before and energy) and tb.num((s.energy_before - energy) / 1000, 0) or "–", tostring(seat)))
  tb.trace(run, "6) T3-Felder vorher: " .. s.before.trunk .. " | Treibstoff " .. s.before.fuel .. " | Farbe " .. s.before.color)
  s.parts = parts
  table.insert(parts, string.format("Flug %s s, %s Kacheln/s; T3-Felder %d/%d gleich; Ernter %s Kacheln von der Ankunft; Fahrer %s; Ablage frei %d → %d",
    tb.num(flight / 60), tb.num(distance / math.max(1, flight) * 60, 2), same, #S6_FIELDS, tostring(gap and tb.num(gap)),
    tostring(seat), s.free_before, free_after))
  s.failed = failed
  if not valid(s.car) then return verdict(run, tb, 6, "Voller Ernter von A nach B [U13, U28]", failed, table.concat(parts, "; ")) end
  -- Dann auf B ernten: 100 Eisenplatten heraus (ein Slot frei), aufbauen.
  local trunk = s.car.get_inventory(defines.inventory.car_trunk)
  local removed = trunk.remove{name = "iron-plate", count = 100}
  check(failed, removed == 100, "Eisenplatten heraus: " .. removed .. "/100")
  s.trunk_b = trunk_count(s.car)
  s.spice_b_before = spice_in(tb.surface(), s.area_b)
  s.deploy_b = harvester.toggle(s.car, nil)
  if not s.deploy_b then
    table.insert(failed, "Aufbauen auf B: toggle gab false (" .. car_text(tb, s.car) .. ")")
    return verdict(run, tb, 6, "Voller Ernter von A nach B [U13, U28]", failed, table.concat(parts, "; "))
  end
  return harvester.DEPLOY_TICKS + 10
end

function t15_steps.s6_field(run, tb, d)
  local s = d.s6
  local failed = s.failed
  local h = harvester.get(s.car)
  if not check(failed, h ~= nil and h.state == "deployed", "auf B nach 310 Ticks " .. car_state(s.car) .. " statt deployed") then
    return verdict(run, tb, 6, "Voller Ernter von A nach B [U13, U28]", failed, table.concat(s.parts, "; "))
  end
  local area = harvester.field_area(s.car.position)
  local outside, at_a = 0, 0
  for _, resource in pairs(h.resources) do
    if resource.valid then
      if not inside({{left_top = {x = area[1][1], y = area[1][2]}, right_bottom = {x = area[2][1], y = area[2][2]}}}, resource.position) then
        outside = outside + 1
      end
      if inside({{left_top = {x = s.area_a[1][1], y = s.area_a[1][2]}, right_bottom = {x = s.area_a[2][1], y = s.area_a[2][2]}}}, resource.position) then
        at_a = at_a + 1
      end
    end
  end
  check(failed, #h.resources > 0 and outside == 0 and at_a == 0, string.format("Erntefeld: %d Ressourcen, %d außerhalb des Felds um die Absetzstelle, %d bei A",
    #h.resources, outside, at_a))
  s.field = #h.resources
  return 60
end

function t15_steps.s6_harvest(run, tb, d)
  local s = d.s6
  local failed = s.failed
  local trunk = trunk_count(s.car)
  local spice_b = spice_in(tb.surface(), s.area_b)
  check(failed, trunk > s.trunk_b, "nach 60 Ticks kein neuer Spice-Sand (" .. s.trunk_b .. " → " .. trunk .. ")")
  check(failed, spice_b < s.spice_b_before, "Spice auf B nicht weniger (" .. s.spice_b_before .. " → " .. spice_b .. ")")
  table.insert(s.parts, string.format("auf B %d Ressourcen im Feld, Kofferraum %d → %d, Spice auf B %d → %d",
    s.field or 0, s.trunk_b, trunk, s.spice_b_before, spice_b))
  return verdict(run, tb, 6, "Voller Ernter von A nach B [U13, U28]", failed, table.concat(s.parts, "; "))
end

-- Schritt 7: Absturz [U17, U23, U24]: a) volle Gesundheit, b) 20 %, c) mit Pilot.

function t15_steps.s7_build(run, tb, d)
  local s = d.s7
  local c = d.pos.s7
  s.cases = {}
  for i, key in ipairs({"a", "b", "c"}) do
    local cell = {}
    s.cases[key] = cell
    cell.flyer, cell.car = new_pair(run, tb, at(c, (i - 1) * 20, 0), {pilot = key == "c"})
    if not (cell.flyer and cell.car) then return fail(run, tb, 7, "Aufbau " .. key .. ") ging nicht") end
    if key == "b" then cell.car.health = cell.car.max_health * 0.2 end
    cell.result = {couple(cell.flyer, cell.car)}
  end
  return COUPLE_WAIT
end

function t15_steps.s7_crash(run, tb, d)
  local s = d.s7
  local failed = {}
  s.failed = failed
  for _, key in ipairs({"a", "b", "c"}) do
    local cell = s.cases[key]
    local label = key .. ")"
    if not (check_carried(failed, label .. " vorher", cell.car, cell.flyer) and check_loaded(failed, label .. " vorher", cell.flyer, cell.car)) then
      return verdict(run, tb, 7, "Absturz [U17, U23, U24]", failed, "Anheben ging nicht")
    end
    cell.health_before = cell.car.health
    cell.max = cell.car.max_health
    cell.pilot = cell.flyer.get_driver()
    cell.un = cell.flyer.unit_number
    cell.death = copy_pos(cell.flyer.position)
    local free_before = free_slots()
    local ok, err = pcall(function() cell.flyer.die() end)
    check(failed, ok, label .. " die() mit Skriptfehler: " .. tostring(err))
    -- im selben Tick
    check_mobile(failed, label, cell.car, tb)
    local gap = valid(cell.car) and tb.distance(cell.car.position, cell.death)
    check(failed, gap and gap <= LAND_RADIUS, label .. " Ernter " .. tostring(gap and tb.num(gap)) .. " Kacheln von der Todesstelle")
    local expected = math.max(1, cell.health_before - CRASH_SHARE * cell.max)
    local health = valid(cell.car) and cell.car.health
    check(failed, health and math.abs(health - expected) <= 0.5, label .. " Gesundheit " .. tostring(health and tb.num(health))
      .. " statt " .. tb.num(expected))
    check(failed, storage.flyers[cell.un] == nil, label .. " Flieger-Datensatz noch da")
    local free_after = free_slots()
    check(failed, free_after == free_before + 1, label .. " Ablage frei " .. free_before .. " → " .. free_after .. " statt +1")
    cell.gap, cell.health = gap, health
    cell.position = valid(cell.car) and copy_pos(cell.car.position)
    if key == "c" then
      local pilot_ok = valid(cell.pilot)
      check(failed, pilot_ok, "c) Pilot-Puppe nach dem Absturz ungültig")
      cell.pilot_gap = pilot_ok and valid(cell.car) and tb.distance(cell.pilot.position, cell.car.position)
      tb.trace(run, "7) c) Pilot nach dem Absturz " .. tostring(cell.pilot_gap and tb.num(cell.pilot_gap)) .. " Kacheln vom Ernter [U17]")
    end
    tb.trace(run, string.format("7) %s Absturz bei %s: %s, Gesundheit %s → %s (erwartet %s)", label, pos_text(tb, cell.death),
      car_text(tb, cell.car), tb.num(cell.health_before), tostring(health and tb.num(health)), tb.num(expected)))
  end
  return 2
end

function t15_steps.s7_after(run, tb, d)
  local s = d.s7
  local failed = s.failed
  for _, key in ipairs({"a", "b", "c"}) do
    local cell = s.cases[key]
    local moved = valid(cell.car) and cell.position and tb.distance(cell.car.position, cell.position)
    check(failed, moved and moved < 0.01 and math.abs(cell.car.health - cell.health) < 0.01,
      key .. ") 2 Ticks später verändert (Doppelbehandlung?)")
  end
  local a, b, c = s.cases.a, s.cases.b, s.cases.c
  return verdict(run, tb, 7, "Absturz [U17, U23, U24]", failed, string.format(
    "a) %s Kacheln, Gesundheit %s/%s; b) Gesundheit %s; c) Pilot %s Kacheln vom Ernter; nach 2 Ticks unverändert",
    tostring(a.gap and tb.num(a.gap)), tostring(a.health and tb.num(a.health)), tb.num(a.max), tostring(b.health and tb.num(b.health)),
    tostring(c.pilot_gap and tb.num(c.pilot_gap))))
end

-- Schritt 8: Anders entfernt: a) destroy() 30 Kacheln vom Abhebepunkt, b) destroy{raise_destroy = true}.

function t15_steps.s8_build(run, tb, d)
  local s = d.s8
  local c = d.pos.s8
  s.cases = {}
  for i, key in ipairs({"a", "b"}) do
    local cell = {}
    s.cases[key] = cell
    cell.flyer, cell.car = new_pair(run, tb, at(c, (i - 1) * 60, 0), {})
    if not (cell.flyer and cell.car) then return fail(run, tb, 8, "Aufbau " .. key .. ") ging nicht") end
    cell.lift = copy_pos(cell.car.position)
    cell.result = {couple(cell.flyer, cell.car)}
  end
  return COUPLE_WAIT
end

function t15_steps.s8_remove(run, tb, d)
  local s = d.s8
  local failed = {}
  s.failed = failed
  for _, key in ipairs({"a", "b"}) do
    local cell = s.cases[key]
    if not (check_carried(failed, key .. ") vorher", cell.car, cell.flyer) and check_loaded(failed, key .. ") vorher", cell.flyer, cell.car)) then
      return verdict(run, tb, 8, "Anders entfernt", failed, "Anheben ging nicht")
    end
    cell.flyer.teleport({x = cell.lift.x + 30, y = cell.lift.y})
    cell.health = cell.car.health
  end
  s.cases.a.flyer.destroy()
  s.cases.b.flyer.destroy{raise_destroy = true}
  s.removed_at = game.tick
  local b = s.cases.b
  check_mobile(failed, "b) sofort", b.car, tb)
  b.gap = valid(b.car) and tb.distance(b.car.position, b.lift)
  check(failed, b.gap and b.gap <= LAND_RADIUS, "b) Ernter " .. tostring(b.gap and tb.num(b.gap)) .. " Kacheln vom Abhebepunkt")
  check(failed, valid(b.car) and math.abs(b.car.health - b.health) < 0.01, "b) Gesundheit verändert")
  return 1
end

function t15_steps.s8_wait(run, tb, d)
  local s = d.s8
  local a = s.cases.a
  local waited = game.tick - s.removed_at
  if not (valid(a.car) and a.car.surface.name == tb.surface().name) then
    if waited >= 2 then
      table.insert(s.failed, "a) nach " .. waited .. " Ticks nicht zurück (" .. car_text(tb, a.car) .. ")")
      return verdict(run, tb, 8, "Anders entfernt", s.failed, "a) nicht zurück")
    end
    return "poll"
  end
  check_mobile(s.failed, "a)", a.car, tb)
  a.gap = tb.distance(a.car.position, a.lift)
  check(s.failed, a.gap <= LAND_RADIUS, "a) Ernter " .. tb.num(a.gap) .. " Kacheln vom Abhebepunkt")
  check(s.failed, math.abs(a.car.health - a.health) < 0.01, "a) Gesundheit verändert")
  local b = s.cases.b
  return verdict(run, tb, 8, "Anders entfernt", s.failed, string.format("a) destroy(): nach %d Ticks zurück, %s Kacheln vom Abhebepunkt; b) raise_destroy: sofort, %s Kacheln",
    waited, tb.num(a.gap), tostring(b.gap and tb.num(b.gap))))
end

-- Schritt 9: Kein Platz [U19]: a) Mauern, b) Wasser, c) Absturz über Mauern, d) Klippe, e) kein Landeplatz.

local S9_KEYS = {"a", "b", "c", "d", "e"}

function t15_steps.s9_build(run, tb, d)
  local s = d.s9
  local surface = tb.surface()
  local force = force_of(run, tb)
  local wall, water, cliff, lake = d.pos.s9_wall, d.pos.s9_water, d.pos.s9_cliff, d.pos.s9_lake
  -- a), c) Steinmauern auf jeder Kachel eines 13×13-Felds; Mitte ist die Kachelmitte von wall.
  local walls = 0
  for dx = -6, 6 do
    for dy = -6, 6 do
      if create(run, tb, {name = "stone-wall", position = at(wall, dx + 0.5, dy + 0.5), force = force}) then walls = walls + 1 end
    end
  end
  s.wall_center = at(wall, 0.5, 0.5)
  -- b) Wasser 15×15 um die Kachelmitte von water.
  tb.fill({{water.x - 7, water.y - 7}, {water.x + 8, water.y + 8}}, "water", surface)
  s.water_center = at(water, 0.5, 0.5)
  -- d) Klippe, wenn die Fläche eine erzeugen kann.
  s.cliff = create(run, tb, {name = "cliff", position = at(cliff, 0, 0), cliff_orientation = "west-to-east"})
  -- e) See 200×200 mit Sandinsel 8×8; Startpunkt der Force 20 Kacheln neben der Insel, also im See.
  tb.fill({{lake.x - 100, lake.y - 100}, {lake.x + 100, lake.y + 100}}, "water", surface)
  s.island = {{lake.x - 4, lake.y - 4}, {lake.x + 4, lake.y + 4}}
  tb.fill(s.island, SAND, surface)
  local t15 = t15_force()
  s.force = t15
  d.spawn_saved = {force = t15.name, surface = surface.index, position = copy_pos(t15.get_spawn_position(surface))}
  t15.set_spawn_position(at(lake, 20, 0), surface)
  -- Abhebestellen
  local stage = d.pos.s9_stage
  local places = {a = at(stage, -20, 0), b = at(stage, 40, 0), c = at(stage, 20, 0), d = at(stage, 80, 0), e = at(lake, 0, 0)}
  s.cases = {}
  for _, key in ipairs(S9_KEYS) do
    local cell = {}
    s.cases[key] = cell
    cell.flyer, cell.car = new_pair(run, tb, places[key], {force = key == "e" and t15 or nil})
    if not (cell.flyer and cell.car) then return fail(run, tb, 9, "Aufbau " .. key .. ") ging nicht") end
    cell.result = {couple(cell.flyer, cell.car)}
  end
  tb.trace(run, string.format("9) Mauerfeld 13×13 (%d Mauern) bei %s, Wasser 15×15 bei %s, Klippe %s, See 200×200 mit Insel 8×8 bei %s, Startpunkt %s",
    walls, pos_text(tb, s.wall_center), pos_text(tb, s.water_center), s.cliff and pos_text(tb, s.cliff.position) or "nicht erzeugt",
    pos_text(tb, lake), pos_text(tb, at(lake, 20, 0))))
  return COUPLE_WAIT
end

function t15_steps.s9_attempt(run, tb, d)
  local s = d.s9
  local failed, parts = {}, {}
  s.failed, s.parts = failed, parts
  for _, key in ipairs(S9_KEYS) do
    local cell = s.cases[key]
    if not (check_carried(failed, key .. ") vorher", cell.car, cell.flyer) and check_loaded(failed, key .. ") vorher", cell.flyer, cell.car)) then
      return verdict(run, tb, 9, "Kein Platz [U19]", failed, "Anheben ging nicht")
    end
  end
  local cells = s.cases
  -- a), b) über Mauern und Wasser: kein Platz, die Last bleibt.
  for _, key in ipairs({"a", "b"}) do
    local cell = cells[key]
    local center = key == "a" and s.wall_center or s.water_center
    cell.flyer.teleport(center)
    local ok, reason = toggle(cell.flyer)
    check(failed, ok == false and reason == "no_space", key .. ") Absetzen über " .. (key == "a" and "Mauern " or "Wasser ") .. result_text(ok, reason))
    check_loaded(failed, key .. ") danach", cell.flyer, cell.car)
    check_carried(failed, key .. ") danach", cell.car, cell.flyer)
    table.insert(parts, key .. ") " .. result_text(ok, reason))
  end
  -- c) Absturz über dem Mauerfeld: Landung im Radius 16.
  local c = cells.c
  c.flyer.teleport(s.wall_center)
  c.flyer.die()
  check_mobile(failed, "c)", c.car, tb)
  c.gap = valid(c.car) and tb.distance(c.car.position, s.wall_center)
  check(failed, c.gap and c.gap <= 16, "c) Ernter " .. tostring(c.gap and tb.num(c.gap)) .. " Kacheln von der Mitte statt ≤ 16")
  table.insert(parts, "c) Absturz über Mauern → " .. tostring(c.gap and tb.num(c.gap)) .. " Kacheln")
  -- d) Klippe
  local dd = cells.d
  if valid(s.cliff) then
    local force = dd.flyer.force
    local cp = copy_pos(s.cliff.position)
    local on = s.cliff.surface.can_place_entity{name = PROBE, position = cp, force = force, build_check_type = defines.build_check_type.manual}
    local beside = s.cliff.surface.can_place_entity{name = PROBE, position = at(cp, 0, 8), force = force, build_check_type = defines.build_check_type.manual}
    check(failed, on == false, "d) Probe passt auf die Klippe")
    check(failed, beside == true, "d) Probe passt 8 Kacheln neben der Klippe nicht")
    dd.flyer.teleport(cp)
    local ok, reason = toggle(dd.flyer)
    check(failed, ok and reason == "dropped", "d) Absetzen an der Klippe " .. result_text(ok, reason))
    dd.gap = valid(dd.car) and tb.distance(dd.car.position, cp)
    check(failed, dd.gap and dd.gap >= 1.6, "d) Ernter " .. tostring(dd.gap and tb.num(dd.gap)) .. " Kacheln von der Klippe")
    table.insert(parts, string.format("d) Probe auf der Klippe %s, daneben %s, abgesetzt %s Kacheln daneben", tostring(on), tostring(beside),
      tostring(dd.gap and tb.num(dd.gap))))
  else
    tb.log(run, "INFO", "9) d) keine Klippe erzeugt (die Fläche kann keine bilden); Probe an der Klippe nicht geprüft")
    table.insert(parts, "d) keine Klippe")
  end
  -- e) Kein Landeplatz: Insel zu Wasser, dann Absturz.
  local e = cells.e
  tb.fill(s.island, "water", tb.surface())
  e.un = e.flyer.unit_number
  e.death = copy_pos(e.flyer.position)
  e.health_before = e.car.health
  e.flyer.die()
  local h = harvester.get(e.car)
  local entry = storage.stranded[e.car.unit_number]
  check(failed, valid(e.car) and e.car.surface.name == HOLD and h and h.state == "carried" and h.carried_by == nil,
    "e) Ernter nicht wartend auf der Ablage (" .. car_text(tb, e.car) .. ")")
  check(failed, entry ~= nil and entry.damage == true, "e) kein Eintrag in storage.stranded mit damage")
  check(failed, storage.flyers[e.un] == nil, "e) Flieger-Datensatz noch da")
  e.health_wait = valid(e.car) and e.car.health
  return DEBOUNCE + 1
end

function t15_steps.s9_retry(run, tb, d)
  local s = d.s9
  local failed, parts = s.failed, s.parts
  for _, key in ipairs({"a", "b"}) do
    local cell = s.cases[key]
    local center = key == "a" and s.wall_center or s.water_center
    cell.flyer.teleport(at(center, 20, 0))
    local ok, reason = toggle(cell.flyer)
    check(failed, ok and reason == "dropped", key .. ") 20 Kacheln weiter " .. result_text(ok, reason))
    check_mobile(failed, key .. ") 20 Kacheln weiter", cell.car, tb)
  end
  table.insert(parts, "a), b) 20 Kacheln weiter abgesetzt")
  return CARE_WAIT - DEBOUNCE - 1
end

function t15_steps.s9_stranded(run, tb, d)
  local s = d.s9
  local e = s.cases.e
  local h = harvester.get(e.car)
  local entry = valid(e.car) and storage.stranded[e.car.unit_number]
  check(s.failed, valid(e.car) and e.car.surface.name == HOLD and h and h.state == "carried" and entry
    and math.abs(e.car.health - e.health_wait) < 0.01, "e) nach 60 Ticks verändert (" .. car_text(tb, e.car) .. ")")
  tb.fill(s.island, SAND, tb.surface())
  s.island_tick = game.tick
  return 1
end

function t15_steps.s9_land(run, tb, d)
  local s = d.s9
  local e = s.cases.e
  local failed = s.failed
  local waited = game.tick - s.island_tick
  if not (valid(e.car) and e.car.surface.name == tb.surface().name) then
    if waited > CARE_WAIT then
      table.insert(failed, "e) nach " .. waited .. " Ticks nicht gelandet (" .. car_text(tb, e.car) .. ")")
      return verdict(run, tb, 9, "Kein Platz [U19]", failed, table.concat(s.parts, "; "))
    end
    return "poll"
  end
  check_mobile(failed, "e) gelandet", e.car, tb)
  local gap = tb.distance(e.car.position, e.death)
  check(failed, gap <= LAND_RADIUS, "e) " .. tb.num(gap) .. " Kacheln von der Todesstelle")
  local expected = math.max(1, e.health_before - CRASH_SHARE * e.car.max_health)
  check(failed, math.abs(e.car.health - expected) <= 0.5, "e) Gesundheit " .. tb.num(e.car.health) .. " statt " .. tb.num(expected))
  check(failed, storage.stranded[e.car.unit_number] == nil, "e) Eintrag in storage.stranded noch da")
  table.insert(s.parts, string.format("e) wartet auf der Ablage, nach der Insel %d Ticks: gelandet %s Kacheln von der Todesstelle, Gesundheit %s",
    waited, tb.num(gap), tb.num(e.car.health)))
  return verdict(run, tb, 9, "Kein Platz [U19]", failed, table.concat(s.parts, "; "))
end

-- Schritt 10: Leerer Tank [U10]: Ziel 50 Kacheln, nach 3 s noch an der Stelle.

function t15_steps.s10_build(run, tb, d)
  local s = d.s10
  s.flyer, s.car = new_pair(run, tb, d.pos.s10, {fuel = false})
  if not (s.flyer and s.car) then return fail(run, tb, 10, "Aufbau ging nicht") end
  s.result = {couple(s.flyer, s.car)}
  return COUPLE_WAIT
end

function t15_steps.s10_go(run, tb, d)
  local s = d.s10
  local failed = {}
  if not (check_carried(failed, "vorher", s.car, s.flyer) and check_loaded(failed, "vorher", s.flyer, s.car)) then
    return verdict(run, tb, 10, "Leerer Tank [U10]", failed, "Anheben ging nicht")
  end
  s.from = copy_pos(s.flyer.position)
  s.go = pcall(function() s.flyer.autopilot_destination = {x = s.from.x + 50, y = s.from.y} end)
  return 3 * 60
end

function t15_steps.s10_check(run, tb, d)
  local s = d.s10
  local failed = {}
  check(failed, s.go, "autopilot_destination ging nicht")
  local moved = valid(s.flyer) and tb.distance(s.flyer.position, s.from)
  check(failed, moved and moved <= 0.1, "nach 3 s " .. tostring(moved and tb.num(moved, 2)) .. " Kacheln bewegt")
  check_loaded(failed, "nach 3 s", s.flyer, s.car)
  local ok, reason = toggle(s.flyer)
  check(failed, ok and reason == "dropped", "Absetzen " .. result_text(ok, reason))
  check_mobile(failed, "abgesetzt", s.car, tb)
  return verdict(run, tb, 10, "Leerer Tank [U10]", failed, string.format("nach 3 s %s Kacheln bewegt, beladen mit Bild, Absetzen %s",
    tostring(moved and tb.num(moved, 2)), result_text(ok, reason)))
end

-- Schritt 11: Abbausperre [U26].

function t15_steps.s11_build(run, tb, d)
  local s = d.s11
  s.flyer, s.car = new_pair(run, tb, d.pos.s11, {})
  if not (s.flyer and s.car) then return fail(run, tb, 11, "Aufbau ging nicht") end
  s.result = {couple(s.flyer, s.car)}
  return COUPLE_WAIT
end

function t15_steps.s11_mark(run, tb, d)
  local s = d.s11
  local failed = {}
  if not check_loaded(failed, "vorher", s.flyer, s.car) then return verdict(run, tb, 11, "Abbausperre [U26]", failed, "Anheben ging nicht") end
  s.minable_loaded = s.flyer.minable_flag
  local ok, marked = pcall(function() return s.flyer.order_deconstruction(s.flyer.force) end)
  s.order_text = ok and tostring(marked) or ("Fehler " .. tostring(marked))
  s.marked_now = s.flyer.to_be_deconstructed()
  return 1
end

function t15_steps.s11_check(run, tb, d)
  local s = d.s11
  local failed = {}
  local marked = valid(s.flyer) and s.flyer.to_be_deconstructed()
  check(failed, s.minable_loaded == false, "beladen minable_flag " .. tostring(s.minable_loaded))
  check(failed, marked == false, "beladen zum Abriss markiert")
  local ok, reason = toggle(s.flyer)
  check(failed, ok and reason == "dropped", "Absetzen " .. result_text(ok, reason))
  local minable_empty = valid(s.flyer) and s.flyer.minable_flag
  check(failed, minable_empty == true, "leer minable_flag " .. tostring(minable_empty))
  tb.trace(run, "11) order_deconstruction beladen: Rückgabe " .. s.order_text .. ", gleich danach markiert " .. tostring(s.marked_now)
    .. ", 1 Tick später " .. tostring(marked))
  return verdict(run, tb, 11, "Abbausperre [U26]", failed, string.format("beladen minable_flag %s, order_deconstruction %s, markiert %s; leer minable_flag %s",
    tostring(s.minable_loaded), s.order_text, tostring(marked), tostring(minable_empty)))
end

-- Schritt 12: Ablage [U25]: versteckt für alle Forces (auch eine neue), drei Plätze im selben Tick, Vergessen.

local function hidden_text(surface)
  local open = {}
  for _, force in pairs(game.forces) do
    local ok, hidden = pcall(function() return force.get_surface_hidden(surface) end)
    if not (ok and hidden == true) then table.insert(open, force.name) end
  end
  return open
end

function t15_steps.s12_build(run, tb, d)
  local s = d.s12
  local failed = {}
  s.failed = failed
  local surface = hold.surface()
  if not surface then
    tb.log(run, "INFO", "12) Ablage noch nicht angelegt; hold.ensure() legt sie an")
    surface = hold.ensure()
  end
  s.hold_index = surface.index
  if game.forces[T15_NEW_FORCE] then
    tb.log(run, "INFO", "12) Force " .. T15_NEW_FORCE .. " gibt es schon (Rest eines abgebrochenen Laufs); geprüft wird sie trotzdem")
  else
    game.create_force(T15_NEW_FORCE)
  end
  s.cases = {}
  for i = 1, 3 do
    local cell = {}
    s.cases[i] = cell
    cell.flyer, cell.car = new_pair(run, tb, at(d.pos.s12, (i - 1) * 15, 0), {})
    if not (cell.flyer and cell.car) then return fail(run, tb, 12, "Aufbau ging nicht") end
  end
  s.free_before = free_slots()
  for _, cell in ipairs(s.cases) do cell.result = {couple(cell.flyer, cell.car)} end
  return COUPLE_WAIT
end

function t15_steps.s12_lifted(run, tb, d)
  local s = d.s12
  local failed = s.failed
  -- Versteckt erst hier geprüft, 130 Ticks nach create_force: Ob on_force_created noch im Aufruf kommt, sagt die API
  -- nicht (A23 events.d.ts:957); so gilt das Ergebnis in beiden Fällen.
  local open = hidden_text(game.get_surface(HOLD))
  check(failed, #open == 0, "Ablage sichtbar für " .. table.concat(open, ", "))
  -- game.forces ist ein LuaCustomTable: Länge mit # (table_size zählt dort nicht richtig, A23 global.d.ts:65).
  s.forces = #game.forces
  local slots, seen = {}, {}
  for i, cell in ipairs(s.cases) do
    check_carried(failed, i .. ".", cell.car, cell.flyer)
    if valid(cell.car) then
      local key = string.format("%d,%d", math.floor(cell.car.position.x + 0.5), math.floor(cell.car.position.y + 0.5))
      check(failed, not seen[key], "Platz " .. key .. " doppelt")
      seen[key] = true
      table.insert(slots, "(" .. key .. ")")
    end
  end
  local free_lifted = free_slots()
  check(failed, free_lifted == s.free_before - 3, "frei " .. s.free_before .. " → " .. free_lifted .. " statt −3")
  for i, cell in ipairs(s.cases) do
    local ok, reason = toggle(cell.flyer)
    check(failed, ok and reason == "dropped", i .. ". Absetzen " .. result_text(ok, reason))
  end
  local free_dropped = free_slots()
  check(failed, free_dropped == s.free_before, "nach dem Absetzen frei " .. free_dropped .. " statt " .. s.free_before)
  s.values = string.format("drei Plätze %s, frei %d → %d → %d", table.concat(slots, " "), s.free_before, free_lifted, free_dropped)
  return DEBOUNCE
end

function t15_steps.s12_forget(run, tb, d)
  local s = d.s12
  hold.forget()
  local cell = s.cases[1]
  cell.again = {couple(cell.flyer, cell.car)}
  check(s.failed, cell.again[1] == true, "nach hold.forget() toggle_carry " .. result_text(cell.again[1], cell.again[2]))
  return COUPLE_WAIT
end

function t15_steps.s12_relift(run, tb, d)
  local s = d.s12
  local failed = s.failed
  local cell = s.cases[1]
  check_carried(failed, "nach hold.forget()", cell.car, cell.flyer)
  local surface = hold.surface()
  check(failed, surface ~= nil and surface.index == s.hold_index and surface == game.get_surface(HOLD),
    "storage.hold.surface ist nicht wieder die Ablage")
  local open = surface and hidden_text(surface) or {"?"}
  check(failed, #open == 0, "nach hold.forget() sichtbar für " .. table.concat(open, ", "))
  if game.forces[T15_NEW_FORCE] then game.merge_forces(T15_NEW_FORCE, "neutral") end
  return verdict(run, tb, 12, "Ablage [U25]", failed, s.values .. string.format("; versteckt für alle %d Forces (auch %s); nach hold.forget() wieder eingetragen und versteckt",
    s.forces, T15_NEW_FORCE))
end

-- Schritt 13: Zustandstabellen (Plan 4.3), jede Eingabe in jedem Zustand von Ornithopter und getragenem Ernter.
-- Nicht doppelt: Zellen „wie 3b“ (mobile bis docked × Taste, Tod, Teleport, Klon) prüft T13 Schritt 12; „Kopplung fertig“
-- aus deploying, deployed, packing und docked steht in Schritt 5 (Notstart), „kein Platz“ in Schritt 9.
-- Zeitplan: alle Zellen bauen; nach 2 Ticks die Aufrufe (leer) und Kopplungen; nach 30 Ticks die Eingaben während der
-- Kopplung; nach 130 Ticks die Eingaben im Zustand „beladen“ und „getragen“, eine je Tick (damit die Zahl freier
-- Plätze je Zelle genau stimmt); 61 Ticks danach die Pflege-Fälle.

local T13_CELLS =
{
  {id = "L1", kind = "L", car = true, label = "leer × Taste mit Ernter → koppelt"},
  {id = "L1b", kind = "L", label = "leer × Taste ohne Ernter → Hinweis"},
  {id = "L2", kind = "L", label = "leer × Tod → ausgetragen"},
  {id = "L3", kind = "L", label = "leer × anders entfernt → ausgetragen"},
  {id = "L4", kind = "L", no_fuel = true, label = "leer × Tank leer → bleibt leer"},
  {id = "L5", kind = "L", label = "leer × Teleport → bleibt leer"},
  {id = "L6", kind = "L", label = "leer × Klon → Klon leer"},
  {id = "K1", kind = "K", label = "koppelt × Taste → leer (Abbruch)"},
  {id = "K2", kind = "K", label = "koppelt × Takt, Ernter > 4 Kacheln → leer"},
  {id = "K3", kind = "K", label = "koppelt × Takt, Zeit um → beladen (mobile → carried)"},
  {id = "K4", kind = "K", label = "koppelt × Tod → Ring weg, ausgetragen"},
  {id = "K5", kind = "K", label = "koppelt × anders entfernt → Ring weg, ausgetragen"},
  {id = "K6", kind = "K", no_fuel = true, label = "koppelt × Tank leer → koppelt weiter"},
  {id = "K7a", kind = "K", label = "koppelt × Teleport ≤ 4 Kacheln → koppelt weiter"},
  {id = "K7b", kind = "K", label = "koppelt × Teleport auf andere Oberfläche → Abbruch"},
  {id = "K7c", kind = "K", label = "koppelt × Teleport > 4 Kacheln → Abbruch"},
  {id = "K8", kind = "K", label = "koppelt × Klon → Klon leer, Original koppelt weiter"},
  {id = "B1", kind = "B", label = "beladen × Taste → abgesetzt, leer"},
  {id = "B2", kind = "B", label = "beladen × Tod → Absturz"},
  {id = "B3", kind = "B", label = "beladen × anders entfernt → Ernter zum Abhebepunkt"},
  {id = "B4", kind = "B", no_fuel = true, label = "beladen × Tank leer → schwebt, bleibt beladen"},
  {id = "B5", kind = "B", label = "beladen × Teleport → Bilder gültig"},
  {id = "B6", kind = "B", label = "beladen × Klon → Klon leer, Original beladen"},
  {id = "C1", kind = "C", label = "getragen × Umschalt+H → Hinweis, bleibt getragen"},
  {id = "C3", kind = "C", label = "getragen × Tod → Ornithopter leer"},
  {id = "C4", kind = "C", label = "getragen × destroy() ohne Ereignis → Ornithopter leer (Pflege a)"},
  {id = "C5", kind = "C", label = "getragen × Teleport auf der Ablage → bleibt getragen"},
  {id = "C6", kind = "C", label = "getragen × Teleport weg, raise_teleported → mobil"},
  {id = "C7", kind = "C", label = "getragen × Teleport weg, ohne Ereignis → mobil (Pflege b)"},
  {id = "C8", kind = "C", label = "getragen × Klon → Klon mobil, Original getragen"}
}

function t15_steps.s13_build(run, tb, d)
  local s = d.s13
  s.cases = {}
  for i, spec in ipairs(T13_CELLS) do
    local c = at(d.pos.s13, ((i - 1) % 10) * 14, math.floor((i - 1) / 10) * 12)
    local cell = {spec = spec, failed = {}, notes = {}}
    s.cases[spec.id] = cell
    if spec.kind == "L" and not spec.car then
      cell.flyer = new_flyer(run, tb, at(c, 0.5, -1), {fuel = not spec.no_fuel and "coal" or nil})
    else
      cell.flyer, cell.car = new_pair(run, tb, c, {fuel = not spec.no_fuel and "coal" or false})
    end
    if not cell.flyer or (spec.kind ~= "L" or spec.car) and not cell.car then return fail(run, tb, 13, "Aufbau " .. spec.id .. " ging nicht") end
    cell.lift = cell.car and copy_pos(cell.car.position)
    cell.un = cell.flyer.unit_number
  end
  return 2
end

-- Eingaben im Zustand leer; Kopplungen für K, B und C.
function t15_steps.s13_empty(run, tb, d)
  local s = d.s13
  local cells = s.cases
  local function cell_check(cell, ok, label)
    return check(cell.failed, ok, label)
  end
  local c = cells.L1
  local ok, reason = toggle(c.flyer)
  cell_check(c, ok and reason == "coupling" and flyer_state(c.flyer) == "koppelt", "Taste " .. result_text(ok, reason) .. ", " .. flyer_state(c.flyer))
  c = cells.L1b
  ok, reason = toggle(c.flyer)
  cell_check(c, ok == false and reason == "no_harvester" and flyer_state(c.flyer) == "leer", "Taste " .. result_text(ok, reason))
  c = cells.L2
  c.flyer.die()
  cell_check(c, storage.flyers[c.un] == nil, "Datensatz nach dem Tod noch da")
  c = cells.L3
  c.flyer.destroy{raise_destroy = true}
  cell_check(c, storage.flyers[c.un] == nil, "Datensatz nach destroy{raise_destroy} noch da")
  c = cells.L5
  c.flyer.teleport(at(c.flyer.position, 3, 0), nil, true)
  check_empty(c.failed, "nach dem Teleport", c.flyer)
  c = cells.L6
  local clone = c.flyer.clone{position = at(c.flyer.position, 3, 0)}
  remember(run, clone, "flyers")
  check_empty(c.failed, "Klon", clone)
  check_empty(c.failed, "Original", c.flyer)
  for _, spec in ipairs(T13_CELLS) do
    if spec.kind ~= "L" then
      local cell = cells[spec.id]
      cell.result = {couple(cell.flyer, cell.car)}
      local record = flyer_lib.get(cell.flyer)
      cell.ring = record and record.renders.ring
      cell_check(cell, cell.result[1] == true and render_ok(cell.ring), "Kopplung startet nicht (" .. result_text(cell.result[1], cell.result[2]) .. ")")
    end
  end
  return 30
end

-- Eingaben während der Kopplung.
function t15_steps.s13_coupling(run, tb, d)
  local s = d.s13
  local cells = s.cases
  local c = cells.K1
  local ok, reason = toggle(c.flyer)
  check(c.failed, ok and reason == "aborted" and flyer_state(c.flyer) == "leer" and not render_ok(c.ring), "Taste " .. result_text(ok, reason)
    .. ", " .. flyer_state(c.flyer))
  c = cells.K2
  c.car.teleport(at(c.car.position, 6, 0))
  c = cells.K4
  c.flyer.die()
  check(c.failed, storage.flyers[c.un] == nil and not storage.couplings[c.un] and not render_ok(c.ring), "nach dem Tod: Datensatz, Kopplung oder Ring noch da")
  c = cells.K5
  c.flyer.destroy{raise_destroy = true}
  check(c.failed, storage.flyers[c.un] == nil and not storage.couplings[c.un] and not render_ok(c.ring), "nach destroy{raise_destroy}: Datensatz, Kopplung oder Ring noch da")
  c = cells.K7a
  c.flyer.teleport(at(c.flyer.position, 1, 0), nil, true)
  check(c.failed, flyer_state(c.flyer) == "koppelt", "nach dem Teleport um 1 Kachel " .. flyer_state(c.flyer))
  c = cells.K7b
  local home = copy_pos(c.flyer.position)
  c.flyer.teleport({x = 40, y = -40}, tb.hold_surface(), true)
  check(c.failed, flyer_state(c.flyer) == "leer" and not storage.couplings[c.un] and not render_ok(c.ring),
    "nach dem Teleport auf " .. c.flyer.surface.name .. " " .. flyer_state(c.flyer))
  c.flyer.teleport(home, tb.surface(), true)
  c = cells.K7c
  c.flyer.teleport(at(c.flyer.position, 8, 0), nil, true)
  check(c.failed, flyer_state(c.flyer) == "leer" and not render_ok(c.ring), "nach dem Teleport um 8 Kacheln " .. flyer_state(c.flyer))
  c = cells.K8
  local clone = c.flyer.clone{position = at(c.flyer.position, 3, 0)}
  remember(run, clone, "flyers")
  c.clone = clone
  check_empty(c.failed, "Klon", clone)
  check(c.failed, flyer_state(c.flyer) == "koppelt", "Original " .. flyer_state(c.flyer))
  return COUPLE_WAIT - 30
end

-- Auswertung der Kopplungen; Vorbereitung der Eingaben „beladen“/„getragen“ (eine je Tick).
function t15_steps.s13_loaded(run, tb, d)
  local s = d.s13
  local cells = s.cases
  local c = cells.K2
  check(c.failed, flyer_state(c.flyer) == "leer" and car_state(c.car) ~= "carried" and not render_ok(c.ring),
    "Ernter 6 Kacheln weg: " .. flyer_state(c.flyer) .. ", Ernter " .. car_state(c.car))
  for _, id in ipairs({"K3", "K6", "K7a", "K8"}) do
    c = cells[id]
    check_loaded(c.failed, "nach 130 Ticks", c.flyer, c.car)
    check_carried(c.failed, "nach 130 Ticks", c.car, c.flyer)
  end
  check_empty(cells.K8.failed, "Klon später", cells.K8.clone)
  c = cells.L4
  check_empty(c.failed, "nach 130 Ticks ohne Treibstoff", c.flyer)
  s.queue = {}
  for _, spec in ipairs(T13_CELLS) do
    if spec.kind == "B" or spec.kind == "C" then
      local cell = cells[spec.id]
      if check_loaded(cell.failed, "vorher", cell.flyer, cell.car) and check_carried(cell.failed, "vorher", cell.car, cell.flyer) then
        table.insert(s.queue, spec.id)
      end
    end
  end
  s.next_cell = 1
  return 1
end

-- Eingaben „beladen“ und „getragen“; jede Zelle in ihrem Tick, freie Plätze davor und danach.
local S13_INPUT = {}

S13_INPUT.B1 = function(run, tb, cell)
  local ok, reason = toggle(cell.flyer)
  check(cell.failed, ok and reason == "dropped", "Taste " .. result_text(ok, reason))
  check_mobile(cell.failed, "Ernter", cell.car, tb)
  check_empty(cell.failed, "Ornithopter", cell.flyer)
  return 1
end

S13_INPUT.B2 = function(run, tb, cell)
  local death = copy_pos(cell.flyer.position)
  local health, max = cell.car.health, cell.car.max_health
  cell.flyer.die()
  check_mobile(cell.failed, "Ernter", cell.car, tb)
  local gap = valid(cell.car) and tb.distance(cell.car.position, death)
  check(cell.failed, gap and gap <= LAND_RADIUS and math.abs(cell.car.health - math.max(1, health - CRASH_SHARE * max)) <= 0.5,
    "Landung " .. tostring(gap and tb.num(gap)) .. " Kacheln, Gesundheit " .. tostring(valid(cell.car) and tb.num(cell.car.health)))
  check(cell.failed, storage.flyers[cell.un] == nil, "Datensatz noch da")
  return 1
end

S13_INPUT.B3 = function(run, tb, cell)
  local health = cell.car.health
  cell.flyer.destroy{raise_destroy = true}
  check_mobile(cell.failed, "Ernter", cell.car, tb)
  local gap = valid(cell.car) and tb.distance(cell.car.position, cell.lift)
  check(cell.failed, gap and gap <= LAND_RADIUS and math.abs(cell.car.health - health) < 0.01,
    "Ernter " .. tostring(gap and tb.num(gap)) .. " Kacheln vom Abhebepunkt")
  check(cell.failed, storage.flyers[cell.un] == nil, "Datensatz noch da")
  return 1
end

S13_INPUT.B4 = function(run, tb, cell)
  cell.position = copy_pos(cell.flyer.position)
  cell.flyer.autopilot_destination = at(cell.position, 20, 0)
  cell.delayed = true
  return 0
end

S13_INPUT.B5 = function(run, tb, cell)
  cell.flyer.teleport(at(cell.flyer.position, 5, 0), nil, true)
  check_loaded(cell.failed, "nach dem Teleport", cell.flyer, cell.car)
  check_carried(cell.failed, "nach dem Teleport", cell.car, cell.flyer)
  return 0
end

S13_INPUT.B6 = function(run, tb, cell)
  local clone = cell.flyer.clone{position = at(cell.flyer.position, 3, 0)}
  remember(run, clone, "flyers")
  check_empty(cell.failed, "Klon", clone)
  check_loaded(cell.failed, "Original", cell.flyer, cell.car)
  check_carried(cell.failed, "Original", cell.car, cell.flyer)
  return 0
end

S13_INPUT.C1 = function(run, tb, cell)
  local ok = harvester.toggle(cell.car, nil)
  check(cell.failed, ok == false and car_state(cell.car) == "carried", "toggle " .. tostring(ok) .. ", " .. car_state(cell.car))
  return 0
end

S13_INPUT.C3 = function(run, tb, cell)
  cell.slot = copy_pos(cell.car.position)
  cell.car.die()
  check(cell.failed, flyer_state(cell.flyer) == "leer", "Ornithopter nach dem Tod " .. flyer_state(cell.flyer))
  check_empty(cell.failed, "Ornithopter", cell.flyer)
  return 1
end

S13_INPUT.C4 = function(run, tb, cell)
  cell.slot = copy_pos(cell.car.position)
  cell.car.destroy()
  cell.delayed = true
  return 1
end

S13_INPUT.C5 = function(run, tb, cell)
  cell.car.teleport(at(cell.car.position, 1, 1), cell.car.surface, true)
  check(cell.failed, car_state(cell.car) == "carried" and cell.car.surface.name == HOLD, "nach dem Teleport auf der Ablage " .. car_text(tb, cell.car))
  check_loaded(cell.failed, "Ornithopter", cell.flyer, cell.car)
  return 0
end

S13_INPUT.C6 = function(run, tb, cell)
  cell.car.teleport(cell.lift, tb.surface(), true)
  check_mobile(cell.failed, "im selben Tick", cell.car, tb)
  check(cell.failed, harvester.get(cell.car) ~= nil, "Datensatz weg")
  check_empty(cell.failed, "Ornithopter", cell.flyer)
  return 1
end

S13_INPUT.C7 = function(run, tb, cell)
  cell.car.teleport(cell.lift, tb.surface())
  cell.delayed = true
  return 1
end

S13_INPUT.C8 = function(run, tb, cell)
  local clone = cell.car.clone{position = cell.lift, surface = tb.surface()}
  remember(run, clone, "cars")
  check_mobile(cell.failed, "Klon", clone, tb)
  check(cell.failed, car_state(cell.car) == "carried", "Original " .. car_state(cell.car))
  check_loaded(cell.failed, "Ornithopter", cell.flyer, cell.car)
  return 0
end

function t15_steps.s13_inputs(run, tb, d)
  local s = d.s13
  local id = s.queue[s.next_cell]
  if not id then return CARE_WAIT end
  s.next_cell = s.next_cell + 1
  local cell = s.cases[id]
  local before = free_slots()
  local ok, delta = pcall(S13_INPUT[id], run, tb, cell)
  if not ok then
    check(cell.failed, false, "Skriptfehler: " .. tostring(delta))
  else
    local after = free_slots()
    if not check(cell.failed, after == before + delta, string.format("Ablage frei %d → %d statt %+d", before, after, delta)) and cell.slot then
      table.insert(cell.failed, "auf dem Platz steht " .. slot_contents(cell.slot))
    end
  end
  if s.queue[s.next_cell] then return "poll" end
  return CARE_WAIT
end

-- Pflege-Fälle (60-Tick-Takt) und Tabelle.
function t15_steps.s13_check(run, tb, d)
  local s = d.s13
  local cells = s.cases
  local c = cells.B4
  if c.delayed then
    local moved = valid(c.flyer) and tb.distance(c.flyer.position, c.position)
    check(c.failed, moved and moved <= 0.1, "ohne Treibstoff " .. tostring(moved and tb.num(moved, 2)) .. " Kacheln bewegt")
    check_loaded(c.failed, "nach 61 Ticks", c.flyer, c.car)
  end
  c = cells.C4
  if c.delayed then check_empty(c.failed, "nach 61 Ticks (Pflege a)", c.flyer) end
  c = cells.C7
  if c.delayed then
    check_mobile(c.failed, "nach 61 Ticks (Pflege b)", c.car, tb)
    check_empty(c.failed, "Ornithopter nach 61 Ticks", c.flyer)
  end
  local failed, ok_count = {}, 0
  for _, spec in ipairs(T13_CELLS) do
    local cell = cells[spec.id]
    if #cell.failed == 0 then
      ok_count = ok_count + 1
      tb.trace(run, "13) " .. spec.id .. " " .. spec.label .. ": OK")
    else
      table.insert(failed, spec.id .. " (" .. table.concat(cell.failed, "; ") .. ")")
      tb.trace(run, "13) " .. spec.id .. " " .. spec.label .. ": FEHLER " .. table.concat(cell.failed, "; "))
    end
  end
  local s5 = d.s5.table or {}
  local notstart = {}
  for _, key in ipairs(S5_CELLS) do table.insert(notstart, key .. " " .. (s5[key] == "OK" and "OK" or (s5[key] and "FEHLER" or "–"))) end
  tb.log(run, "INFO", "13) Zellen „wie 3b“ (mobile bis docked × Taste, Tod, Teleport, Klon) prüft T13 Schritt 12; „Kopplung fertig“ aus "
    .. "deploying, deployed, packing, docked steht in Schritt 5 (" .. table.concat(notstart, ", ") .. "), „kein Platz“ in Schritt 9")
  return verdict(run, tb, 13, "Zustandstabellen", failed, string.format("%d/%d Zellen OK (Ornithopter leer, koppelt, beladen; Ernter getragen)",
    ok_count, #T13_CELLS))
end

-- Schritt 14: Migration (Plan 4.15) mit einem Ernter der Force arrakis-t15.

function t15_steps.s14_run(run, tb, d)
  local s = d.s14
  local force = t15_force()
  local failed = {}
  local ornithopter = force.technologies[ORNITHOPTER_TECH]
  local harvesting = force.technologies[HARVESTING_TECH]
  if not (ornithopter and harvesting) then return fail(run, tb, 14, "Technologien fehlen") end
  local before = {harvesting = harvesting.researched, ornithopter = ornithopter.researched}
  -- Nur der Ernter-Datensatz soll zählen: Herstellzähler (Schritt 2) auf 0.
  for _, surface in pairs(game.surfaces) do
    pcall(function() force.get_item_production_statistics(surface).set_input_count(NAME, 0) end)
  end
  local car = new_car(run, tb, {x = d.pos.s14.x + 0.5, y = d.pos.s14.y + 0.5}, {force = force})
  if not (car and harvester.get(car)) then return fail(run, tb, 14, "Ernter der Force " .. T15_FORCE .. " nicht eingetragen") end
  harvesting.researched = true
  ornithopter.researched = false
  local r1 = migrate.ornithopter_research(force)
  local after1 = ornithopter.researched
  local r2 = migrate.ornithopter_research(force)
  harvesting.researched = false
  ornithopter.researched = false
  local r3 = migrate.ornithopter_research(force)
  local after3 = ornithopter.researched
  harvesting.researched = before.harvesting
  ornithopter.researched = before.ornithopter
  check(failed, r1 == true and after1 == true, "mit Ernter: " .. tostring(r1) .. ", erforscht " .. tostring(after1))
  check(failed, r2 == false, "zweiter Aufruf " .. tostring(r2))
  check(failed, r3 == false and after3 == false, "ohne „Spice-Ernte“: " .. tostring(r3) .. ", erforscht " .. tostring(after3))
  check(failed, harvesting.researched == before.harvesting and ornithopter.researched == before.ornithopter, "Forschungen nicht wie vorher")
  return verdict(run, tb, 14, "Migration", failed, string.format("mit Ernter %s (erforscht %s), zweiter Aufruf %s, ohne „Spice-Ernte“ %s; danach wie vorher (%s, %s)",
    tostring(r1), tostring(after1), tostring(r2), tostring(r3), tostring(before.harvesting), tostring(before.ornithopter)))
end

-- Schritt 15: Pflege [U9, U16]: Sticker weg, zweiter Sticker, Bild weg, Teleport auf arrakis-test-hold und zurück.

local S15_PARTS = {"a", "b", "c", "d"}
local S15_LABEL =
{
  a = "Sticker zerstört",
  b = "zweiter eigener Sticker",
  c = "Bild zerstört",
  d = "Teleport auf die Prüfstand-Ablage und zurück"
}

function t15_steps.s15_build(run, tb, d)
  local s = d.s15
  s.flyer, s.car = new_pair(run, tb, d.pos.s15, {})
  if not (s.flyer and s.car) then return fail(run, tb, 15, "Aufbau ging nicht") end
  s.result = {couple(s.flyer, s.car)}
  s.failed, s.parts, s.part = {}, {}, 0
  return COUPLE_WAIT
end

-- Pflege-Zustand gut? Genau ein eigener Sticker „beladen“ (b: der gemerkte), am Flieger, Bild und Schatten gültig.
function t15_steps.s15_good(s)
  local record = flyer_lib.get(s.flyer)
  if not record then return false end
  local stickers = own_stickers(s.flyer)
  if #stickers ~= 1 or stickers[1].name ~= STICKER_LOADED then return false end
  if read(function() return stickers[1].sticked_to == s.flyer end) ~= true then return false end
  if s.remembered and stickers[1] ~= s.remembered then return false end
  return render_ok(record.renders.image) and render_ok(record.renders.shadow)
end

function t15_steps.s15_poke(run, tb, d)
  local s = d.s15
  if s.part == 0 and not (check_loaded(s.failed, "vorher", s.flyer, s.car)) then
    return verdict(run, tb, 15, "Pflege [U9, U16]", s.failed, "Anheben ging nicht")
  end
  s.part = s.part + 1
  local key = S15_PARTS[s.part]
  if not key then
    return verdict(run, tb, 15, "Pflege [U9, U16]", s.failed, table.concat(s.parts, "; "))
  end
  local record = flyer_lib.get(s.flyer)
  s.remembered = nil
  if key == "a" then
    local sticker = record and record.sticker
    if valid(sticker) then sticker.destroy() end
  elseif key == "b" then
    s.remembered = record and record.sticker
    remember(run, s.flyer.surface.create_entity{name = STICKER_LOADED, position = s.flyer.position, target = s.flyer, force = s.flyer.force})
  elseif key == "c" then
    local image = record and record.renders.image
    if render_ok(image) then image.destroy() end
  else
    s.home = copy_pos(s.flyer.position)
    s.flyer.teleport({x = -40, y = 40}, tb.hold_surface())
    s.away = true
  end
  s.count_after_poke = #own_stickers(s.flyer)
  s.poke_tick = game.tick
  return 1
end

function t15_steps.s15_wait(run, tb, d)
  local s = d.s15
  local key = S15_PARTS[s.part]
  if s.away then
    -- d) im nächsten Tick zurück auf die Prüfstand-Fläche (ohne raise_teleported: die Pflege muss es finden).
    s.away = nil
    s.flyer.teleport(s.home, tb.surface())
    s.poke_tick = game.tick
    return "poll"
  end
  local waited = game.tick - s.poke_tick
  if t15_steps.s15_good(s) then
    tb.trace(run, string.format("15) %s) %s: nach %d Ticks wieder gut, eigene Sticker gleich danach %d, jetzt %d",
      key, S15_LABEL[key], waited, s.count_after_poke, #own_stickers(s.flyer)))
    table.insert(s.parts, string.format("%s) %s: %d Ticks", key, S15_LABEL[key], waited))
    s.phase_back = true
    return 1
  end
  if waited > CARE_WAIT then
    table.insert(s.failed, string.format("%s) %s: nach %d Ticks nicht wieder gut (%s)", key, S15_LABEL[key], waited, flyer_text(tb, s.flyer)))
    table.insert(s.parts, key .. ") nicht gut")
    s.phase_back = true
    return 1
  end
  return "poll"
end

-- Springt zurück zu s15_poke, bis alle Teile durch sind (Phasenliste: poke, wait, loop).
function t15_steps.s15_loop(run, tb, d)
  local s = d.s15
  if s.phase_back and S15_PARTS[s.part + 1] then
    s.phase_back = nil
    d.phase = 1  -- t15_tick zählt danach auf 2 (s15_poke) weiter
    return 1
  end
  return verdict(run, tb, 15, "Pflege [U9, U16]", s.failed, table.concat(s.parts, "; ") .. "; eigene Sticker am Ende "
    .. #own_stickers(s.flyer))
end

-- Schritt 16: Fremde Force und Unterflug [U21].

function t15_steps.s16_build(run, tb, d)
  local s = d.s16
  local failed = {}
  s.failed = failed
  local c = d.pos.s16
  s.flyer = new_flyer(run, tb, at(c, 0.5, -1), {})
  s.foreign = new_car(run, tb, at(c, 0.5, 0.5), {force = t15_force()})
  if not (s.flyer and s.foreign) then return fail(run, tb, 16, "Aufbau a) ging nicht") end
  s.result = {couple(s.flyer, s.foreign)}
  check(failed, s.result[1] == false and s.result[2] == "foreign", "fremder Ernter: toggle_carry " .. result_text(s.result[1], s.result[2]))
  check(failed, flyer_state(s.flyer) == "leer", "Ornithopter " .. flyer_state(s.flyer))
  -- b) Unterflug: Ernter mit Dummy-Fahrer fährt 3 s nach Osten unter einem stehenden Ornithopter durch.
  local u = at(c, 30, 0)
  s.over = new_flyer(run, tb, at(u, 0.5, 0.5), {})
  s.car = new_car(run, tb, at(u, -2.5, 0.5), {coal = 5, orientation = 0.25})
  if not (s.over and s.car) then return fail(run, tb, 16, "Aufbau b) ging nicht") end
  s.driver = tb.dummy_driver(s.car)
  remember(run, s.driver)
  s.health = {flyer = s.over.health, car = s.car.health}
  s.start_x = s.car.position.x
  s.max_x = s.start_x
  s.start = game.tick
  return 1
end

function t15_steps.s16_drive(run, tb, d)
  local s = d.s16
  if valid(s.car) then
    gas(s.car, s.driver, game.tick - s.start < 3 * 60)
    s.max_x = math.max(s.max_x, s.car.position.x)
  end
  if game.tick - s.start < 3 * 60 + 30 then return "poll" end
  local flyer_health = valid(s.over) and s.over.health
  local car_health = valid(s.car) and s.car.health
  local passed = s.max_x > s.over.position.x
  tb.trace(run, string.format("16) b) Unterflug [U21]: Ernter von x %s bis %s (Ornithopter bei %s, %s), Gesundheit Ornithopter %s → %s, Ernter %s → %s",
    tb.num(s.start_x), tb.num(s.max_x), tb.num(s.over.position.x), passed and "durch" or "nicht durch",
    tb.num(s.health.flyer), tostring(flyer_health and tb.num(flyer_health)), tb.num(s.health.car), tostring(car_health and tb.num(car_health))))
  return verdict(run, tb, 16, "Fremde Force und Unterflug [U21]", s.failed, string.format(
    "a) fremder Ernter %s; b) Unterflug %s, Gesundheit Ornithopter %s → %s, Ernter %s → %s",
    result_text(s.result[1], s.result[2]), passed and "durch" or "nicht durch", tb.num(s.health.flyer),
    tostring(flyer_health and tb.num(flyer_health)), tb.num(s.health.car), tostring(car_health and tb.num(car_health))))
end

-- Schritt 17: Entfernen (immer zuletzt): /arrakis-uninstall ja mit zwei Lasten und einer Waise.

function t15_steps.s17_build(run, tb, d)
  local s = d.s17
  s.cases = {}
  for i = 1, 3 do
    local cell = {}
    s.cases[i] = cell
    cell.flyer, cell.car = new_pair(run, tb, at(d.pos.s17, (i - 1) * 20, 0), {})
    if not (cell.flyer and cell.car) then return fail(run, tb, 17, "Aufbau ging nicht") end
    cell.result = {couple(cell.flyer, cell.car)}
  end
  return COUPLE_WAIT
end

function t15_steps.s17_run(run, tb, d)
  local s = d.s17
  local failed = {}
  s.failed = failed
  for i, cell in ipairs(s.cases) do
    if not (check_carried(failed, i .. ". vorher", cell.car, cell.flyer) and check_loaded(failed, i .. ". vorher", cell.flyer, cell.car)) then
      return verdict(run, tb, 17, "Entfernen (/arrakis-uninstall)", failed, "Anheben ging nicht")
    end
  end
  -- Waise: Datensatz des dritten Fliegers streichen (wie T13 storage direkt liest, Plan 4.17), dann destroy().
  local orphan = s.cases[3]
  local h = harvester.get(orphan.car)
  orphan.lift = h and h.lift_pos and {x = h.lift_pos.x, y = h.lift_pos.y}
  storage.flyers[orphan.flyer.unit_number] = nil
  orphan.flyer.destroy()
  for i = 1, 2 do s.cases[i].home = copy_pos(s.cases[i].flyer.position) end
  local ok, n, rest = pcall(flyer_lib.uninstall)
  if not ok then return fail(run, tb, 17, "uninstall mit Skriptfehler: " .. tostring(n)) end
  s.n, s.rest = n, rest
  check(failed, n >= 3, "abgesetzt " .. tostring(n) .. " statt ≥ 3")
  check(failed, rest == 0, "übrig " .. tostring(rest))
  for i = 1, 2 do
    local cell = s.cases[i]
    check_mobile(failed, i .. ".", cell.car, tb)
    local gap = valid(cell.car) and tb.distance(cell.car.position, cell.home)
    check(failed, gap and gap <= LAND_RADIUS, i .. ". Ernter " .. tostring(gap and tb.num(gap)) .. " Kacheln vom Ornithopter")
    check(failed, flyer_state(cell.flyer) == "leer", i .. ". Ornithopter " .. flyer_state(cell.flyer))
    cell.gap = gap
  end
  check_mobile(failed, "Waise", orphan.car, tb)
  orphan.gap = valid(orphan.car) and orphan.lift and tb.distance(orphan.car.position, orphan.lift)
  check(failed, orphan.gap and orphan.gap <= LAND_RADIUS, "Waise " .. tostring(orphan.gap and tb.num(orphan.gap)) .. " Kacheln vom Abhebepunkt")
  return 1
end

function t15_steps.s17_after(run, tb, d)
  local s = d.s17
  check(s.failed, game.get_surface(HOLD) == nil, HOLD .. " gibt es nach 1 Tick noch")
  check(s.failed, hold.surface() == nil, "storage.hold zeigt noch auf eine Ablage")
  local c1, c2, c3 = s.cases[1], s.cases[2], s.cases[3]
  return verdict(run, tb, 17, "Entfernen (/arrakis-uninstall)", s.failed, string.format(
    "n = %s, rest = %s; Lasten %s und %s Kacheln vom Ornithopter, Waise %s Kacheln vom Abhebepunkt; Ablage gelöscht",
    tostring(s.n), tostring(s.rest), tostring(c1.gap and tb.num(c1.gap)), tostring(c2.gap and tb.num(c2.gap)), tostring(c3.gap and tb.num(c3.gap))))
end

local T15_STEPS =
{
  {t15_steps.s1_check},
  {t15_steps.s2_start, t15_steps.s2_hand, t15_steps.s2_machine_build, t15_steps.s2_machine, t15_steps.s2_check},
  {t15_steps.s3_build, t15_steps.s3_lifted},
  {t15_steps.s4_build, t15_steps.s4_debounce, t15_steps.s4_inputs, t15_steps.s4_check},
  {t15_steps.s5_build, t15_steps.s5_couple, t15_steps.s5_lifted, t15_steps.s5_redock},
  {t15_steps.s6_build, t15_steps.s6_lift, t15_steps.s6_fly, t15_steps.s6_wait, t15_steps.s6_field, t15_steps.s6_harvest},
  {t15_steps.s7_build, t15_steps.s7_crash, t15_steps.s7_after},
  {t15_steps.s8_build, t15_steps.s8_remove, t15_steps.s8_wait},
  {t15_steps.s9_build, t15_steps.s9_attempt, t15_steps.s9_retry, t15_steps.s9_stranded, t15_steps.s9_land},
  {t15_steps.s10_build, t15_steps.s10_go, t15_steps.s10_check},
  {t15_steps.s11_build, t15_steps.s11_mark, t15_steps.s11_check},
  {t15_steps.s12_build, t15_steps.s12_lifted, t15_steps.s12_forget, t15_steps.s12_relift},
  {t15_steps.s13_build, t15_steps.s13_empty, t15_steps.s13_coupling, t15_steps.s13_loaded, t15_steps.s13_inputs, t15_steps.s13_check},
  {t15_steps.s14_run},
  {t15_steps.s15_build, t15_steps.s15_poke, t15_steps.s15_wait, t15_steps.s15_loop},
  {t15_steps.s16_build, t15_steps.s16_drive},
  {t15_steps.s17_build, t15_steps.s17_run, t15_steps.s17_after}
}

local function t15_summary(run)
  local ok, wrong, open = 0, {}, {}
  for number = 1, #T15_STEPS do
    local result = run.data.results[number]
    if result == "OK" then
      ok = ok + 1
    elseif result == "INFO" or result == "MESSUNG" then
      table.insert(open, tostring(number))
    else
      table.insert(wrong, tostring(number))
    end
  end
  local text = string.format("%d/%d Schritte OK", ok, #T15_STEPS)
  if #wrong > 0 then text = text .. ", FEHLER in " .. table.concat(wrong, ", ") end
  if #open > 0 then text = text .. ", von Hand prüfen: " .. table.concat(open, ", ") end
  return text
end

local function t15_start(run, tb)
  local d = run.data
  local origin = tb.area(run.id)
  local surface = tb.surface()
  d.boxes = {box_of(at(origin, T15_CENTER.x, T15_CENTER.y), T15_HALF)}
  d.made = {cars = {}, flyers = {}, others = {}}
  d.results = {}
  if not storage_ready() then
    tb.log(run, "FEHLER", "storage des Laufzeitcodes fehlt (scripts/migrate.lua init nicht gelaufen)")
    tb.finish(run, "abgebrochen (kein storage)")
    return
  end
  if not terrain.harvest_allowed(surface) then
    tb.log(run, "FEHLER", "terrain.harvest_allowed(" .. surface.name .. ") = false: der Laufzeitcode erntet hier nicht")
    tb.finish(run, "abgebrochen (Prüfstand-Fläche nicht erlaubt)")
    return
  end
  sweep(run, tb, d.boxes, false)
  tb.prepare(at(origin, T15_CENTER.x, T15_CENTER.y), T15_HALF)
  d.pos = {}
  for key, offset in pairs(T15_PLACES) do d.pos[key] = at(origin, offset.x, offset.y) end
  for number = 1, #T15_STEPS do d["s" .. number] = {} end
  tb.watch(run, nil, d.pos.watch)
  tb.log(run, "INFO", "Siebzehn Schritte mit dem echten Ornithopter-Code (Anheben, Tragen, Absetzen, Absturz, Ablage, Migration),"
    .. " Dauer etwa 2 bis 3 min Spielzeit. Je Schritt eine OK/FEHLER-Zeile, Einzelwerte in der Datei.")
  tb.log(run, "INFO", "T15 benutzt die echte Ablage " .. HOLD .. " und setzt in Schritt 17 alle getragenen Ernter ab (wie /arrakis-uninstall ja);"
    .. " Zahlen zur Ablage gelten relativ zum Stand vor dem Schritt.")
  d.step, d.phase, d.wait_until = 1, 1, game.tick + 30
end

-- Schritt fertig: aufräumen, nächster Schritt nach T15_GAP Ticks.
local function t15_next(run, tb, d)
  local ok, err = pcall(tidy, run)
  if not ok then tb.trace(run, "Aufräumen nach Schritt " .. d.step .. " ging nicht: " .. tostring(err)) end
  d.step, d.phase = d.step + 1, 1
  d.wait_until = game.tick + T15_GAP
end

local function t15_tick(run, tb)
  local d = run.data
  if not d.step or game.tick < d.wait_until then return end
  local step = T15_STEPS[d.step]
  if not step then
    d.step = nil
    tb.finish(run, t15_summary(run))
    return
  end
  local phase = step[d.phase]
  if not phase then
    if not d.results[d.step] then fail(run, tb, d.step, "keine Ergebniszeile (Prüfstand-Fehler)") end
    t15_next(run, tb, d)
    return
  end
  local ok, result = pcall(phase, run, tb, d)
  if not ok then
    fail(run, tb, d.step, "Skriptfehler: " .. tostring(result))
    result = "end"
  end
  if result == "poll" then return end
  if result == "end" then
    t15_next(run, tb, d)
  else
    d.phase = d.phase + 1
    d.wait_until = game.tick + (type(result) == "number" and result or 1)
  end
end

local function t15_on_event(run, tb, name, event)
  if name ~= "spider_command_completed" then return end
  local s = run.data.s6
  local vehicle = event.vehicle
  if not (s and s.fly_tick and not s.arrived_tick and valid(s.flyer) and vehicle and vehicle.valid) then return end
  if vehicle.unit_number ~= s.flyer.unit_number then return end
  s.arrived_tick = event.tick
  s.arrival = copy_pos(vehicle.position)
end

-- Aufräumen: eigene Entities, Isolation mit den Ernter und Ornithoptern am Boden, Startpunkt von arrakis-t15 wie
-- vorher (Schritt 9 e), arrakis-t15n in neutral (Schritt 12).
local function t15_cleanup(run, tb)
  local d = run.data
  pcall(tidy, run)
  if d.boxes then pcall(sweep, run, tb, d.boxes, true) end
  local saved = d.spawn_saved
  if saved then
    local force = game.forces[saved.force]
    local surface = game.get_surface(saved.surface)
    if force and surface then pcall(function() force.set_spawn_position(saved.position, surface) end) end
    d.spawn_saved = nil
  end
  if game.forces[T15_NEW_FORCE] then pcall(function() game.merge_forces(T15_NEW_FORCE, "neutral") end) end
end

-- T16 Ornithopter: Flugphysik -----------------------------------------------------------------------
-- Echte Ornithopter (eingetragen über script_raised_built, also mit echtem Sticker) mit Dummy-Pilot fliegen alle
-- zugleich los, Ziel 400 Kacheln voraus. Gemessen wird zwischen 5 s und 15 s nach dem Start: Weg, Brennwert.
-- Fläche A: Ost-Bahnen im Abstand 10, dazu West und Nordost; Fläche B (400 Kacheln östlich): Nord und Süd in eigenen
-- Spalten. Die Beine drehen nicht mit der Flugrichtung (docs/pruefstand.md, Bekannte Grenzen), deshalb N und S getrennt.
-- Vergleichsbahnen (raw): create_entity ohne raise_built; care sieht sie nie, und eine Puppe ohne Spieler löst kein
-- on_player_driving_changed_state aus. Bei einem eingetragenen Flieger hängte care binnen 60 Ticks den eigenen
-- Sticker wieder an, und im Messfenster wirkten beide.

local T16_HALF_A = {x = 140, y = 95}
local T16_B = {x = 400, y = 0}
local T16_HALF_B = {x = 45, y = 140}
local T16_GO = 140             -- Ticks nach dem Bau: Anheben fertig (120 bis 129), dann alle zugleich los
local T16_FROM, T16_TO = 5 * 60, 15 * 60
local T16_DISTANCE = 400
local T16_EMPTY = {7.0, 9.0}
local T16_LOADED = {5.0, 6.5}
local T16_RATIO = {0.65, 0.75}
local T16_FUEL_SPREAD = 1.10
local T16_QUALITY_SPREAD = 0.10
local T16_DIRS =
{
  O = {x = 1, y = 0},
  W = {x = -1, y = 0},
  N = {x = 0, y = -1},
  S = {x = 0, y = 1},
  NO = {x = math.sqrt(0.5), y = -math.sqrt(0.5)}
}
-- start relativ zur Fläche (A: Ursprung, B: Ursprung + T16_B). check: "empty" oder "loaded" (Tempo-Grenzen);
-- group = "fuel": Brennstoff-Vergleich [U7]; pair: leere Bahn für das Verhältnis beladen/leer.
local T16_LANES =
{
  {key = "coal", label = "leer, Kohle, O", fuel = "coal", count = 10, dir = "O", start = {-125, -60}, check = "empty", group = "fuel"},
  {key = "solid", label = "leer, Festbrennstoff, O", fuel = "solid-fuel", count = 5, dir = "O", start = {-125, -50}, check = "empty", group = "fuel"},
  {key = "rocket", label = "leer, Raketentreibstoff, O", fuel = "rocket-fuel", count = 2, dir = "O", start = {-125, -40}, check = "empty", group = "fuel"},
  {key = "nuclear", label = "leer, Atomtreibstoff, O", fuel = "nuclear-fuel", count = 1, dir = "O", start = {-125, -30}, check = "empty", group = "fuel"},
  {key = "briquette", label = "leer, Spice-Brikett, O", fuel = "arrakis-spice-briquette", count = 5, dir = "O", start = {-125, -20}, check = "empty", group = "fuel"},
  {key = "legendary_fuel", label = "leer, Raketentreibstoff legendär, O", fuel = "rocket-fuel", fuel_quality = "legendary", count = 2, dir = "O",
   start = {-125, -10}, check = "empty", group = "fuel", needs = "legendary"},
  {key = "uncommon", label = "leer, Kohle, O, Ornithopter ungewöhnlich", fuel = "coal", count = 10, quality = "uncommon", dir = "O",
   start = {-125, 0}, check = "empty", needs = "uncommon", base = "coal"},
  {key = "legendary", label = "leer, Kohle, O, Ornithopter legendär", fuel = "coal", count = 10, quality = "legendary", dir = "O",
   start = {-125, 10}, check = "empty", needs = "legendary", base = "coal"},
  {key = "loaded_coal", label = "beladen, Kohle, O", fuel = "coal", count = 10, dir = "O", start = {-125, 20}, check = "loaded", loaded = true, pair = "coal"},
  {key = "loaded_rocket", label = "beladen, Raketentreibstoff, O", fuel = "rocket-fuel", count = 2, dir = "O", start = {-125, 30}, check = "loaded",
   loaded = true, pair = "rocket"},
  {key = "raw", label = "ohne Sticker (Rohwert), Raketentreibstoff, O", fuel = "rocket-fuel", count = 2, dir = "O", start = {-125, 40}, raw = true},
  {key = "max_tick", label = "Test-Sticker vehicle_speed_max 8/60, Raketentreibstoff, O", fuel = "rocket-fuel", count = 2, dir = "O",
   start = {-125, 50}, raw = true, sticker = "arrakis-test-speed-max-tick"},
  {key = "max_second", label = "Test-Sticker vehicle_speed_max 8, Raketentreibstoff, O", fuel = "rocket-fuel", count = 2, dir = "O",
   start = {-125, 60}, raw = true, sticker = "arrakis-test-speed-max-second"},
  {key = "west", label = "leer, Kohle, W", fuel = "coal", count = 10, dir = "W", start = {125, 70}, check = "empty"},
  {key = "northeast", label = "leer, Kohle, NO", fuel = "coal", count = 10, dir = "NO", start = {-125, 85}, check = "empty"},
  {key = "hover", label = "Schweben beladen, Kohle, ohne Ziel", fuel = "coal", count = 10, loaded = true, hover = true, start = {100, 80}},
  {key = "north", label = "leer, Kohle, N", fuel = "coal", count = 10, dir = "N", region = "B", start = {-20, 125}, check = "empty"},
  {key = "loaded_coal_north", label = "beladen, Kohle, N", fuel = "coal", count = 10, dir = "N", region = "B", start = {0, 125}, check = "loaded",
   loaded = true, pair = "north"},
  {key = "loaded_rocket_north", label = "beladen, Raketentreibstoff, N", fuel = "rocket-fuel", count = 2, dir = "N", region = "B", start = {20, 125},
   check = "loaded", loaded = true},
  {key = "south", label = "leer, Kohle, S", fuel = "coal", count = 10, dir = "S", region = "B", start = {35, -125}, check = "empty"}
}

local function t16_build(run, tb, d)
  d.lanes = {}
  local skipped = {}
  for _, spec in ipairs(T16_LANES) do
    if spec.needs and not quality_exists(spec.needs) then
      table.insert(skipped, spec.label)
    else
      local base = spec.region == "B" and at(d.origin, T16_B.x, T16_B.y) or d.origin
      local start = at(base, spec.start[1] + 0.5, spec.start[2] + 0.5)
      local lane = {spec = spec, start = start}
      lane.flyer = new_flyer(run, tb, start, {fuel = spec.fuel, count = spec.count, fuel_quality = spec.fuel_quality,
        quality = spec.quality, raw = spec.raw, pilot = true})
      if lane.flyer then
        lane.un = lane.flyer.unit_number
        lane.fuel_in = fuel_items(lane.flyer)
        lane.pilot = lane.flyer.get_driver() ~= nil
        if spec.sticker then
          lane.sticker = create(run, tb, {name = spec.sticker, position = lane.flyer.position, target = lane.flyer, force = lane.flyer.force})
        end
        if spec.loaded then
          lane.car = new_car(run, tb, at(start, 0, 1.5), {})
          lane.result = {couple(lane.flyer, lane.car)}
        end
      end
      table.insert(d.lanes, lane)
    end
  end
  if #skipped > 0 then tb.log(run, "INFO", "Ohne Quality entfallen: " .. table.concat(skipped, "; ")) end
  d.go_tick = game.tick + T16_GO
  d.phase = "go"
end

local function t16_go(run, tb, d)
  local failed = {}
  for _, lane in ipairs(d.lanes) do
    local spec = lane.spec
    if not lane.flyer then
      lane.lost = "Ornithopter ließ sich nicht erzeugen"
    elseif spec.loaded and not (check_loaded(failed, spec.label, lane.flyer, lane.car) and check_carried(failed, spec.label, lane.car, lane.flyer)) then
      lane.lost = "Anheben ging nicht"
    elseif not spec.raw and not flyer_lib.get(lane.flyer) then
      lane.lost = "nicht eingetragen"
    end
    if lane.flyer and not lane.lost and not spec.hover then
      local dir = T16_DIRS[spec.dir]
      local ok = pcall(function()
        lane.flyer.autopilot_destination = {x = lane.start.x + dir.x * T16_DISTANCE, y = lane.start.y + dir.y * T16_DISTANCE}
      end)
      if not ok then lane.lost = "autopilot_destination ging nicht" end
    end
    if lane.lost then tb.log(run, "FEHLER", "Bahn " .. spec.label .. ": " .. lane.lost) end
    if lane.flyer then
      tb.trace(run, string.format("Bahn %s: Start %s, %d Brennstoffe, Pilot %s, Sticker %s%s", spec.label, pos_text(tb, lane.start),
        lane.fuel_in or 0, tostring(lane.pilot), sticker_text(own_stickers(lane.flyer)), spec.sticker and (" + " .. spec.sticker) or ""))
    end
  end
  if #failed > 0 then tb.trace(run, "Anheben: " .. table.concat(failed, "; ")) end
  d.t0 = game.tick
  d.phase = "sample"
end

local function t16_sample(lane, key)
  local flyer = lane.flyer
  if not valid(flyer) then return end
  lane[key] = {position = copy_pos(flyer.position), energy = fuel_energy(flyer), items = fuel_items(flyer)}
end

-- Tempo (Kacheln/s), kJ/Kachel und kW zwischen den beiden Messpunkten; nil, wenn nicht gemessen.
local function t16_values(lane)
  local a, b = lane.from, lane.to
  if not (a and b) then return nil end
  local seconds = (T16_TO - T16_FROM) / 60
  local distance = math.sqrt((b.position.x - a.position.x) ^ 2 + (b.position.y - a.position.y) ^ 2)
  local used = (a.energy and b.energy) and (a.energy - b.energy) or nil
  return
  {
    speed = distance / seconds,
    distance = distance,
    kj_tile = used and distance > 0 and used / distance / 1000 or nil,
    kw = used and used / seconds / 1000 or nil,
    used = used
  }
end

local function range_text(range)
  return string.format("%.2f–%.2f", range[1], range[2])
end

local function t16_evaluate(run, tb, d)
  local by_key, speeds = {}, {}
  for _, lane in ipairs(d.lanes) do
    by_key[lane.spec.key] = lane
    lane.values = t16_values(lane)
    local v = lane.values
    if v then
      speeds[lane.spec.key] = v.speed
      tb.trace(run, string.format("Bahn %s: %s Kacheln/s, %s Kacheln in 10 s, %s kJ/Kachel, %s kW, Brennstoffe %d → %d",
        lane.spec.label, tb.num(v.speed, 2), tb.num(v.distance), tb.num(v.kj_tile, 1), tb.num(v.kw, 0),
        lane.from.items or 0, lane.to.items or 0))
    end
  end
  local criteria, ok_count = 0, 0
  local function rule(title, failed, values)
    criteria = criteria + 1
    if #failed == 0 then ok_count = ok_count + 1 end
    tb.log(run, #failed == 0 and "OK" or "FEHLER", title .. ": " .. values .. (#failed > 0 and (" | nicht erfüllt: " .. table.concat(failed, "; ")) or ""))
  end
  local function speed_of(key)
    return speeds[key]
  end
  -- 1. leer 7,0–9,0; 2. beladen 5,0–6,5
  for _, kind in ipairs({"empty", "loaded"}) do
    local range = kind == "empty" and T16_EMPTY or T16_LOADED
    local failed, parts = {}, {}
    for _, lane in ipairs(d.lanes) do
      if lane.spec.check == kind then
        local v = speed_of(lane.spec.key)
        if not v then
          table.insert(failed, lane.spec.label .. " nicht gemessen")
        else
          table.insert(parts, lane.spec.label .. " " .. tb.num(v, 2))
          if v < range[1] or v > range[2] then table.insert(failed, lane.spec.label .. " " .. tb.num(v, 2)) end
        end
      end
    end
    rule((kind == "empty" and "Tempo leer " or "Tempo beladen ") .. range_text(range) .. " Kacheln/s [U6]", failed, table.concat(parts, ", "))
  end
  -- 3. beladen/leer, gleicher Brennstoff und gleiche Richtung
  do
    local failed, parts = {}, {}
    for _, lane in ipairs(d.lanes) do
      local pair = lane.spec.pair
      if pair then
        local loaded, empty = speed_of(lane.spec.key), speed_of(pair)
        if loaded and empty and empty > 0 then
          local ratio = loaded / empty
          table.insert(parts, lane.spec.label .. " / " .. by_key[pair].spec.label .. " = " .. tb.num(ratio, 3))
          if ratio < T16_RATIO[1] or ratio > T16_RATIO[2] then table.insert(failed, lane.spec.label .. " " .. tb.num(ratio, 3)) end
        else
          table.insert(failed, lane.spec.label .. ": Paar nicht gemessen")
        end
      end
    end
    local rn, ro = speed_of("loaded_rocket_north"), speed_of("rocket")
    if rn and ro and ro > 0 then
      tb.trace(run, "beladen, Raketentreibstoff, N / leer, Raketentreibstoff, O = " .. tb.num(rn / ro, 3) .. " (kein Paar gleicher Richtung)")
    end
    rule("Verhältnis beladen/leer " .. range_text(T16_RATIO), failed, table.concat(parts, ", "))
  end
  -- 4. Brennstoff [U7]: größtes/kleinstes Tempo der leeren Brennstoff-Bahnen
  do
    local failed = {}
    local low, high, low_label, high_label = nil, nil, "–", "–"
    for _, lane in ipairs(d.lanes) do
      local v = lane.spec.group == "fuel" and speed_of(lane.spec.key)
      if v then
        if not low or v < low then low, low_label = v, lane.spec.label end
        if not high or v > high then high, high_label = v, lane.spec.label end
      end
    end
    local spread = low and low > 0 and high / low
    check(failed, spread and spread <= T16_FUEL_SPREAD, "max/min " .. tostring(spread and tb.num(spread, 3)))
    rule("Brennstoff ändert das Tempo nicht [U7], max/min ≤ " .. tb.num(T16_FUEL_SPREAD, 2), failed, string.format("max %s (%s), min %s (%s), max/min %s",
      tostring(high and tb.num(high, 2)), high_label, tostring(low and tb.num(low, 2)), low_label, tostring(spread and tb.num(spread, 3))))
  end
  -- 5. Qualität [U8]
  do
    local failed, parts = {}, {}
    local coal = speed_of("coal")
    for _, lane in ipairs(d.lanes) do
      if lane.spec.base then
        local v = speed_of(lane.spec.key)
        if v and coal and coal > 0 then
          local change = math.abs(v - coal) / coal
          table.insert(parts, lane.spec.label .. " " .. tb.num(v, 2) .. " (" .. tb.num(change * 100, 1) .. " %)")
          if change > T16_QUALITY_SPREAD then table.insert(failed, lane.spec.label .. " " .. tb.num(change * 100, 1) .. " %") end
        else
          table.insert(failed, lane.spec.label .. " nicht gemessen")
        end
      end
    end
    if #parts == 0 and #failed == 0 then
      tb.log(run, "INFO", "Qualität [U8]: ohne Quality nicht prüfbar")
    else
      rule("Qualität ändert das Tempo um höchstens 10 % [U8]", failed, "Kohle normal " .. tostring(coal and tb.num(coal, 2)) .. "; " .. table.concat(parts, ", "))
    end
  end
  -- Vergleichsbahnen [U22] und Schweben [U10]: nur MESSUNG/INFO.
  for _, key in ipairs({"raw", "max_tick", "max_second"}) do
    local lane = by_key[key]
    local v = lane and lane.values
    tb.trace(run, string.format("Vergleich %s: %s Kacheln/s", lane and lane.spec.label or key, tostring(v and tb.num(v.speed, 2))))
  end
  local hover = by_key.hover
  local hv = hover and hover.values
  if hv then
    tb.trace(run, string.format("Schweben [U10]: Brennwert %s → %s kJ, Brennstoffe %d → %d, Verbrauch %s kW (%s kJ je 10 s), Weg %s Kacheln",
      tb.num(hover.from.energy and hover.from.energy / 1000, 0), tb.num(hover.to.energy and hover.to.energy / 1000, 0),
      hover.from.items or 0, hover.to.items or 0, tb.num(hv.kw, 1), tb.num(hv.used and hv.used / 1000, 0), tb.num(hv.distance, 2)))
    if hv.used and hv.used > 1000 then
      tb.log(run, "INFO", "U10 hält nicht: Schweben kostet " .. tb.num(hv.kw, 1) .. " kW (docs/plan-3c.md 4.16 nimmt das hin)")
    end
  end
  local empty, loaded = speed_of("coal"), speed_of("loaded_coal")
  tb.log(run, "INFO", string.format("Vorschlag aus den Ost-Bahnen mit Kohle [U6]: vehicle_speed_modifier leer 0,52 · 8 / %s = %s, beladen 0,364 · 5,6 / %s = %s",
    tostring(empty and tb.num(empty, 2)), (empty and empty > 0) and tb.num(0.52 * 8 / empty, 3) or "–",
    tostring(loaded and tb.num(loaded, 2)), (loaded and loaded > 0) and tb.num(0.364 * 5.6 / loaded, 3) or "–"))
  for _, lane in ipairs(d.lanes) do
    if valid(lane.flyer) then pcall(function() lane.flyer.autopilot_destination = nil end) end
  end
  local measured = 0
  for _, lane in ipairs(d.lanes) do if lane.values then measured = measured + 1 end end
  local summary = string.format("%d/%d Bahnen gemessen, Kriterien %d/%d OK", measured, #d.lanes, ok_count, criteria)
  tb.finish(run, summary)
end

local function t16_start(run, tb)
  local d = run.data
  local origin = tb.area(run.id)
  d.origin = origin
  d.boxes = {box_of(origin, T16_HALF_A), box_of(at(origin, T16_B.x, T16_B.y), T16_HALF_B)}
  d.made = {cars = {}, flyers = {}, others = {}}
  if not storage_ready() then
    tb.log(run, "FEHLER", "storage des Laufzeitcodes fehlt (scripts/migrate.lua init nicht gelaufen)")
    tb.finish(run, "abgebrochen (kein storage)")
    return
  end
  sweep(run, tb, d.boxes, false)
  tb.prepare(origin, T16_HALF_A)
  tb.prepare(at(origin, T16_B.x, T16_B.y), T16_HALF_B)
  tb.watch(run, nil, at(origin, 0, 92))
  tb.log(run, "INFO", "Echte Ornithopter auf parallelen Bahnen, alle zugleich; gemessen zwischen 5 s und 15 s nach dem Start."
    .. " Grenzen: leer " .. range_text(T16_EMPTY) .. ", beladen " .. range_text(T16_LOADED) .. " Kacheln/s, beladen/leer "
    .. range_text(T16_RATIO) .. ". Einzelwerte in der Datei.")
  d.phase = "build"
  d.wait_until = game.tick + 30
end

local function t16_tick(run, tb)
  local d = run.data
  if d.phase == "build" then
    if game.tick >= d.wait_until then t16_build(run, tb, d) end
  elseif d.phase == "go" then
    if game.tick >= d.go_tick then t16_go(run, tb, d) end
  elseif d.phase == "sample" then
    local elapsed = game.tick - d.t0
    if elapsed == T16_FROM then
      for _, lane in ipairs(d.lanes) do if not lane.lost then t16_sample(lane, "from") end end
    elseif elapsed >= T16_TO then
      for _, lane in ipairs(d.lanes) do if not lane.lost and lane.from then t16_sample(lane, "to") end end
      d.phase = "done"
      t16_evaluate(run, tb, d)
    end
  end
end

local function t16_cleanup(run, tb)
  local d = run.data
  pcall(tidy, run)
  if d.boxes then pcall(sweep, run, tb, d.boxes, true) end
end

-- T17 Ornithopter: Bedienung (interaktiv) -------------------------------------------------------------
-- Neben Max: ein Ornithopter mit Kohle, ein Ernter mit 500 Spice-Sand, 30 Kacheln weiter eine Annahme auf Fels.
-- Jeder Druck auf die Taste (arrakis-carry-toggle) und jeder Klick auf eine der beiden Verknüpfungen schreibt eine
-- MESSUNG-Zeile (Weiterleitung carry_key und shortcut aus runner.lua, zusätzlich zu flyer.lua: event_handler fasst sie
-- zusammen, die Reihenfolge ist nicht zugesichert; der Zustand in der Zeile kann also vor oder nach dem Laufzeitcode
-- stehen). Jeder Zustandswechsel von Ornithopter oder Ernter schreibt eine INFO-Zeile. Nach dem zweiten Anheben
-- (Schritt 2; Schritt 1 ist Anheben und Absetzen, Plan 6) fliegt der Test den Ornithopter 20 s im Kreis (wie T9 C),
-- dann kommt die FRAGE zum Lastbild.

local T17_END_TICKS = 360 * 60 -- „endet nach 6 min Spielzeit“ (Zeitlimit des Runners 380 s)
local T17_CIRCLE_TICKS = 20 * 60
local T17_CIRCLE_RADIUS = 8
local T17_CIRCLE_STEP = 45     -- Grad je neuem Ziel (wie T9)
local T17_CIRCLE_EVERY = 3 * 60

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
  d.flyer = new_flyer(run, tb, at(origin, 4.5, 0.5), {fuel = "coal", count = 20, force = force})
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
  tb.log(run, "INFO", string.format("Ornithopter %s mit Kohle, Ernter %s mit %d Spice-Sand, Annahme %s auf Fels%s",
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
      d.circle = {center = copy_pos(d.flyer.position), radius = T17_CIRCLE_RADIUS, angle = 0, next_tick = now, until_tick = now + T17_CIRCLE_TICKS, targets = 0}
      tb.log(run, "INFO", "2) Kreisflug 20 s um " .. pos_text(tb, d.circle.center) .. " (wie T9 C)")
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
    elseif now >= circle.next_tick then
      circle.next_tick = now + T17_CIRCLE_EVERY
      circle.angle = (circle.angle + T17_CIRCLE_STEP) % 360
      if pcall(function() d.flyer.autopilot_destination = t17_circle_point(circle, circle.angle) end) then
        circle.targets = circle.targets + 1
      end
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
  T15 =
  {
    title = "Ornithopter: echter Code",
    timeout = 240 * 60,
    interactive = false,
    confirm = nil,
    start = t15_start,
    tick = t15_tick,
    on_event = t15_on_event,
    cleanup = t15_cleanup
  },
  T16 =
  {
    title = "Ornithopter: Flugphysik",
    timeout = 90 * 60,
    interactive = false,
    confirm = nil,
    start = t16_start,
    tick = t16_tick,
    cleanup = t16_cleanup
  },
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
