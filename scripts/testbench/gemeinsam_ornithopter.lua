-- Prüfstand: Ornithopter mit echtem Laufzeitcode (Phase 3c, docs/protokolle/plan-3c.md 6; Vertrag siehe runner.lua).
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
local intake = require("scripts.intake")
local speed = require("prototypes.ornithopter-speed")

local FLYER = "arrakis-ornithopter"
local NAME = "spice-harvester"
local INTAKE = "arrakis-spice-intake"
local SPICE = "spice-sand"
local ROCK = "arrakis-rock"
local HOLD = "arrakis-hold"
-- Stufe ohne Brennstoff (t = 1) und für Raketentreibstoff (r = 1,15), Plan 4.9. Ab 0.9.0 fliegt der Ornithopter nur mit
-- Flugtreibstoff; die Prüflinge tanken Raketentreibstoff (100 MJ, bei 800 kW gut 2 min Flug je Stück).
local COAL_P, ROCKET_P = 100, 115
local FLIGHT_FUEL = "rocket-fuel"
local CARRY_SHORTCUT = "arrakis-carry"
local REMOTE_SHORTCUT = "arrakis-give-remote"
local ORNITHOPTER_TECH = "arrakis-ornithopter"
-- Stellplätze der Ablage (Plan 4.11): 16 × 16 im 10er-Raster, x, y ∈ {−60, −50, …, 90}.
local SLOT_FIRST, SLOT_LAST, SLOT_SPACING = -60, 90, 10

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

-- Steht position genau auf einem Stellplatz der Ablage?
local function at_slot(position)
  local function near(v)
    local k = math.floor((v - SLOT_FIRST) / SLOT_SPACING + 0.5)
    local slot = SLOT_FIRST + k * SLOT_SPACING
    return k >= 0 and slot <= SLOT_LAST and math.abs(v - slot) < 0.01
  end
  return near(position.x) and near(position.y)
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

-- Eigene Sticker am Flieger: die Familien arrakis-ornithopter-empty-<p> und -loaded-<p> in flyer.stickers (A23
-- classes.d.ts:8564), erkannt mit speed.parse (prototypes/ornithopter-speed.lua).
local function own_stickers(flyer)
  local list = {}
  if not valid(flyer) then return list end
  local stickers = read(function() return flyer.stickers end)
  for _, sticker in pairs(stickers or {}) do
    if sticker.valid and speed.parse(sticker.name) then table.insert(list, sticker) end
  end
  return list
end

-- Zustand und Stufe eines eigenen Stickers als Text, z. B. "beladen t1,00".
local function sticker_label(sticker)
  local state, j = speed.parse(sticker.name)
  if not state then return sticker.name end
  return (state == "loaded" and "beladen" or "leer") .. " t" .. speed.factor_text(j)
end

local function sticker_text(list)
  if #list == 0 then return "keiner" end
  local names = {}
  for _, sticker in ipairs(list) do table.insert(names, sticker_label(sticker)) end
  return table.concat(names, " + ")
end

-- p der Stufe eines Stickers oder nil.
local function sticker_p(sticker)
  local _, j = speed.parse(sticker.name)
  return j and speed.percent(j)
end

-- Was hat der Flieger im Brenner? "none" (nichts, auch kein Feuer), "rocket" (nur normaler Raketentreibstoff) oder
-- "other". Ohne Brennstoff behält er die Stufe seines Stickers, der erste bekommt t = 1 (p = 100); mit Raketentreibstoff
-- gilt p = 115 (Plan 4.9). Andere Brennstoffe prüft der Schritt selbst (15 f, T16).
local function fuel_kind(flyer)
  local burner = read(function() return flyer.burner end)
  if not burner then return "other" end
  local kind = "none"
  local function see(name, quality)
    if type(name) ~= "string" then name = name.name end
    if type(quality) == "table" then quality = quality.name end
    if name == FLIGHT_FUEL and (quality == nil or quality == "normal") then
      if kind == "none" then kind = "rocket" end
    else
      kind = "other"
    end
  end
  local burning = read(function() return burner.currently_burning end)
  if burning then see(burning.name, burning.quality) end
  local inventory = burner.inventory
  for i = 1, #inventory do
    local stack = inventory[i]
    if stack.valid_for_read then see(stack.name, stack.quality) end
  end
  return kind
end

-- Genau ein eigener Sticker im Zustand state ("empty", "loaded"); mit Raketentreibstoff in Stufe p = 115, ohne
-- Brennstoff in p = 100 oder 115.
local function sticker_ok(flyer, stickers, state)
  if #stickers ~= 1 then return false end
  local got = speed.parse(stickers[1].name)
  if got ~= state then return false end
  local p, kind = sticker_p(stickers[1]), fuel_kind(flyer)
  if kind == "rocket" then return p == ROCKET_P end
  if kind == "none" then return p == ROCKET_P or p == COAL_P end
  return true
end

local function render_ok(object)
  local ok, is_valid = pcall(function() return object ~= nil and object.valid end)
  return ok and is_valid == true
end

-- Bewertung ---------------------------------------------------------------------------------------

local function check(failed, ok, label)
  if not ok then table.insert(failed, label) end
  return ok
end

-- „beladen“ (Plan 4.3, 4.6 Schritt 7): Datensatz trägt car, nicht abbaubar, genau ein eigener Sticker „beladen“ (mit
-- Raketentreibstoff t1,15), Lastbild und Schatten gültig.
local function check_loaded(failed, label, flyer, car)
  local record = valid(flyer) and flyer_lib.get(flyer)
  if not check(failed, record ~= nil and record ~= false, label .. ": Ornithopter ohne Datensatz") then return false end
  local ok = check(failed, valid(car) and record.cargo == car.unit_number, label .. ": nicht beladen (" .. flyer_state(flyer) .. ")")
  ok = check(failed, flyer.minable_flag == false, label .. ": Ornithopter abbaubar") and ok
  local stickers = own_stickers(flyer)
  ok = check(failed, sticker_ok(flyer, stickers, "loaded"), label .. ": Sticker " .. sticker_text(stickers)) and ok
  ok = check(failed, render_ok(record.renders.image) and render_ok(record.renders.shadow), label .. ": Lastbild oder Schatten fehlt") and ok
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

-- Echter Ornithopter. opts: fuel (Item, Standard keins), count, fuel_quality, quality, pilot (Puppe als Pilot),
-- raw (ohne raise_built: nicht eingetragen), force, surface.
local function new_flyer(run, tb, position, opts)
  opts = opts or {}
  local force = opts.force or force_of(run, tb)
  local flyer = create(run, tb, {name = FLYER, position = position, force = force, quality = opts.quality,
    raise_built = not opts.raw, create_build_effect_smoke = false}, opts.surface, "flyers")
  if not flyer then return nil end
  if opts.fuel then
    add_fuel(flyer, opts.fuel, opts.count or 5, opts.fuel_quality)
    -- Eingetragen wird beim Bau, also noch ohne Brennstoff (Sticker t1,00). Die Pflege des Taktes gleich hier, damit der
    -- Sticker schon zum Brennstoff passt (ab 0.9.0 hat Raketentreibstoff t1,15).
    local record = not opts.raw and flyer_lib.get(flyer)
    if record then flyer_lib.care(record) end
  end
  if opts.pilot then
    local pilot = tb.dummy_driver(flyer, force)
    if pilot then remember(run, pilot, "others") end
  end
  return flyer
end

-- Kopplung starten (wie Taste, Shortcut und Knopf, Plan 4.5, nur ohne Spieler). Gibt ok, Grund zurück.
local function couple(flyer, car)
  if not valid(flyer) then return false, "no_flyer" end
  return flyer_lib.toggle_carry(flyer, car, nil)
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

-- Ist storage des Laufzeitcodes da (scripts/migrate.lua init)?
local function storage_ready()
  return storage.flyers and storage.harvesters and storage.couplings and storage.stranded and storage.hold
    and storage.reg and storage.intakes
end

-- Für die Testdateien scripts/testbench/tests/ (eine je Test; aufgeteilt aus t_ornithopter.lua, Verhalten unverändert).
return
{
  flyer_lib = flyer_lib,
  harvester = harvester,
  intake = intake,
  speed = speed,
  FLYER = FLYER,
  NAME = NAME,
  INTAKE = INTAKE,
  SPICE = SPICE,
  ROCK = ROCK,
  HOLD = HOLD,
  COAL_P = COAL_P,
  ROCKET_P = ROCKET_P,
  FLIGHT_FUEL = FLIGHT_FUEL,
  CARRY_SHORTCUT = CARRY_SHORTCUT,
  REMOTE_SHORTCUT = REMOTE_SHORTCUT,
  ORNITHOPTER_TECH = ORNITHOPTER_TECH,
  SLOT_FIRST = SLOT_FIRST,
  SLOT_LAST = SLOT_LAST,
  SLOT_SPACING = SLOT_SPACING,
  valid = valid,
  force_of = force_of,
  copy_pos = copy_pos,
  at = at,
  pos_text = pos_text,
  read = read,
  quality_exists = quality_exists,
  box_of = box_of,
  inside = inside,
  fuel_energy = fuel_energy,
  at_slot = at_slot,
  flyer_state = flyer_state,
  car_state = car_state,
  own_stickers = own_stickers,
  sticker_label = sticker_label,
  sticker_text = sticker_text,
  sticker_p = sticker_p,
  fuel_kind = fuel_kind,
  sticker_ok = sticker_ok,
  render_ok = render_ok,
  check = check,
  check_loaded = check_loaded,
  check_carried = check_carried,
  create = create,
  remember = remember,
  add_fuel = add_fuel,
  new_car = new_car,
  new_flyer = new_flyer,
  couple = couple,
  tidy = tidy,
  sweep = sweep,
  storage_ready = storage_ready,
}
