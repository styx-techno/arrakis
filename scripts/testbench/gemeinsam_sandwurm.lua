-- Prüfstand: Sandwurm mit echtem Laufzeitcode (Phase 3d2, docs/protokolle/plan-3d2.md 6; Vertrag siehe runner.lua).
--   T21: scripts/sandworm.lua und scripts/worms.lua mit dem echten Wurm auf der Prüfstand-Fläche, ohne Spieler: Prototypen und
--        storage, Zeitlinie einer regulären Jagd, Felsinsel, Sandtasche mit Knick (ROUTING), Ernter vor Fels, Ornithopter über
--        dem Kopf, Rettung, Zerdrücken, Ersatzbiss, Wurm getötet, Wurm verloren, Flucht per Fahrt, Grenzen, Migration und
--        Waisen, Entfernen. Fünfzehn Schritte in zwölf Feldern zu 400 × 400 Kacheln; die Schritte 2 bis 12 laufen in drei
--        Wellen (nie mehr als 3 Befehlsjagden mit Wurm, nie mehr als 6 Würmer), danach 13 bis 15 nacheinander in Feld 12.
--   T22: Optik und Laden (interaktiv, nur mit Spieler und seiner Force): Auftauchen, Halten, Biss und Abtauchen, Fels,
--        Zerdrücken, Ornithopter, Rettung, Tod des Wurms, Factoriopedia, Speichern und Laden. ALT+O (ab 0.8.3 auch
--        /arrakis-test weiter) schaltet weiter; jede FRAGE wartet auf Max.
-- Gebaut wird mit raise_built = true (die Laufzeitmodule tragen ein); Fahrer sind Puppen ohne Spieler (tb.dummy_driver),
-- gefahren wird über riding_state an Fahrzeug und Puppe jeden Tick (wie T13 und T19).
-- Die Tests zählen Ticks. Der Kopf wird je 10 Ticks in der Mitte zwischen zwei Takten gelesen (tick % 10 == 5) über
-- sandworm.head_of; Phasenwechsel erkennt der Test jeden Tick und rundet den Tick auf den Takt ab (Vielfaches von 10):
-- Die Reihenfolge zwischen dem 10-Tick-Takt von worms.lua und dem Prüfstand-Tick ist nicht zugesichert.
-- Knoten 1 springt im Kachelraster (W18, Prüfstand 2026-10-27): Er bleibt bis zu 1 Kachel hinter dem wahren Kopf, je 10 Ticks
-- kommt er 0, 1 oder 2 Kacheln weit. Ein Takt allein misst also kein Tempo; Tempo und Weg zählen nur über Fenster, deren Fehler
-- unter 1 Kachel bleibt (je Lauf ohne Unterbrechung), und die Texte nennen das Fenster.
-- Sollwerte stehen hier als Zahlen aus dem Plan (1, 4.4 bis 4.11, 6), bewusst nicht aus den Modulen gelesen. Ausnahme sind
-- die Standardwahlen aus Plan 1, die Max am 27.10. entschieden hat und die eine Konstante im Modul bleiben (Zerdrücken auch
-- von Fahrzeugen und Figuren: worms.CRUSH_SPARES_VEHICLES; Wurm getötet rettet: worms.KILL_RESCUES; Sprint:
-- sandworm.SPRINT): Die liest der Test aus den Modulen, damit ein Wechsel nur eine Stelle braucht.
-- Zustand nur in run.data (Zahlen, Texte, Positionen, LuaEntity-, LuaSegmentedUnit- und LuaForce-Referenzen; vor jeder
-- Benutzung prüfen). Abläufe und Messhaken stehen als Funktionslisten in diesem Modul, run.data hält nur Nummern.
--
-- Isolation (Plan 4.18): T21 benutzt die eigene Force arrakis-t21 (einmal anlegen, wiederverwenden), wach, mit
-- first_hunt_done, eingeschaltet für die Prüfstand-Fläche und mit der Startrichtung k0 = 2 (Nordost) für jede Jagd ohne
-- eigenen Haken. T22 benutzt Max' Force und schreibt Schonfrist, Pause und Statistik zurück (wie T20). cleanup beendet jede
-- Jagd der Force mit "abort" (die Würmer tauchen still ab), setzt set_worm_off und set_spawn_dir zurück, räumt Waisen auf der
-- Prüfstand-Fläche (sandworm.sweep) und Würmer, die der Test selbst erzeugt hat, und prüft, dass kein arrakis-sandworm-* im
-- Bereich bleibt. Jeder Schritt beendet seine Jagden, bevor er seine Entities entfernt: Kein Wurm überlebt einen Schritt.
-- Die Modultabellen heißen hier vibration_lib, worms_lib, sandworm_lib und flyer_lib (tools/check/api_names.py).

local harvester = require("scripts.harvester")
local terrain = require("scripts.terrain")
local vibration_lib = require("scripts.vibration")
local sandworm_lib = require("scripts.sandworm")
local worms_lib = require("scripts.worms")

local HARVESTER = "spice-harvester"
local FLYER = "arrakis-ornithopter"
local SPICE = "spice-sand"
local ROCK = "arrakis-rock"
local CHEST = "wooden-chest"
local PREFIX = "arrakis-sandworm-"
local KILL_AFTER = 600

-- Allgemeine Helfer ---------------------------------------------------------------------------

local function valid(object)
  return object ~= nil and object.valid
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

local function copy(record)
  if record == nil then return nil end
  local out = {}
  for key, value in pairs(record) do out[key] = value end
  return out
end

local function dist(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function box_of(center, half)
  return
  {
    left_top = {x = math.floor(center.x - half.x), y = math.floor(center.y - half.y)},
    right_bottom = {x = math.ceil(center.x + half.x), y = math.ceil(center.y + half.y)}
  }
end

local function inside(box, position)
  local x, y = position.x or position[1], position.y or position[2]
  return x >= box.left_top.x and x <= box.right_bottom.x and y >= box.left_top.y and y <= box.right_bottom.y
end

local function overlaps(a, b)
  return a.left_top.x < b.right_bottom.x and b.left_top.x < a.right_bottom.x
    and a.left_top.y < b.right_bottom.y and b.left_top.y < a.right_bottom.y
end

-- Natürlicher Sand an (x, y): erzeugter Chunk und natürliche Kachel kein Fels (wie scripts/sandworm.lua).
local function sand_at(surface, x, y)
  if not surface.is_chunk_generated{math.floor(x / 32), math.floor(y / 32)} then return false end
  return terrain.natural_tile_name(surface, x, y) ~= ROCK
end

local function storage_ready()
  return storage.harvesters and storage.flyers and storage.vib and storage.vib.heat and storage.hunts and storage.hunts.list
    and storage.grace and storage.worm_stats and storage.sector_cooldown and storage.path_requests
end

-- Kacheln x1..x2 × y1..y2 (Kachelnummern, beide eingeschlossen) mit einer Kachel belegen. Entities bleiben stehen.
local function tiles(surface, x1, y1, x2, y2, name)
  local list = {}
  for x = x1, x2 do
    for y = y1, y2 do list[#list + 1] = {name = name, position = {x, y}} end
  end
  surface.set_tiles(list, true, false, true, false)
  return #list
end

-- 13×13-Spice-Teppich um die Kachel unter position (das Erntefeld des Ernters, wie T19).
local function carpet(surface, position, amount)
  local x, y = math.floor(position.x), math.floor(position.y)
  local placed = 0
  for i = x - 6, x + 6 do
    for j = y - 6, y + 6 do
      if surface.create_entity{name = SPICE, position = {i + 0.5, j + 0.5}, amount = amount or 1000} then placed = placed + 1 end
    end
  end
  return placed
end

-- Wärme und Ruhe auf der Fläche box löschen (Chunks mit Mitte in box, Sektoren, die box berühren).
local function clear_area(surface, box)
  local s = surface.index
  local e = storage.vib.heat[s]
  if e then
    local keys = {}
    for key in pairs(e.chunks) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do
      local cx, cy = vibration_lib.chunk_of_key(key)
      if inside(box, {x = cx * 32 + 16, y = cy * 32 + 16}) then vibration_lib.set_heat(surface, cx, cy, 0) end
    end
  end
  local cool = storage.sector_cooldown[s]
  if cool then
    local sectors = {}
    for sector in pairs(cool) do sectors[#sectors + 1] = sector end
    for _, sector in ipairs(sectors) do
      local sx, sy = vibration_lib.chunk_of_key(sector)
      local area = {left_top = {x = sx * 128, y = sy * 128}, right_bottom = {x = sx * 128 + 128, y = sy * 128 + 128}}
      if overlaps(box, area) then vibration_lib.rest(s, sector, 0) end
    end
  end
end

-- Jagden ----------------------------------------------------------------------------------------

local function hunt_list(filter)
  local ids = {}
  for id, hunt in pairs(storage.hunts.list) do
    if not filter or filter(hunt) then ids[#ids + 1] = id end
  end
  table.sort(ids)
  local list = {}
  for _, id in ipairs(ids) do list[#list + 1] = storage.hunts.list[id] end
  return list
end

-- Jede Jagd der Forces (Indizes als Schlüssel) mit "abort" beenden; gibt die Zahl zurück.
local function abort_hunts(force_indices)
  local n = 0
  for _, hunt in ipairs(hunt_list(function(h) return force_indices[h.force_index] end)) do
    worms_lib.end_hunt(hunt, nil, "abort")
    n = n + 1
  end
  return n
end

local function end_if_running(hunt)
  if hunt and storage.hunts.list[hunt.id] == hunt then worms_lib.end_hunt(hunt, nil, "abort") end
end

-- Würmer unseres Prototyps (arrakis-sandworm-*) mit einem Knoten in box; abtauchende (ab 0.8.4, noch höchstens
-- sandworm.DIVE_TICKS sichtbar) zählen nicht.
local function sandworms_in(surface, box)
  local n = 0
  for _, unit in pairs(surface.get_segmented_units()) do
    if unit.valid and unit.prototype.name:sub(1, #PREFIX) == PREFIX and not sandworm_lib.diving(unit) then
      for _, node in pairs(unit.get_body_nodes()) do
        if inside(box, node) then
          n = n + 1
          break
        end
      end
    end
  end
  return n
end

-- Entities und Aufräumen ------------------------------------------------------------------------

local function new_made()
  return {cars = {}, flyers = {}, others = {}}
end

-- Erzeugt eine Entity auf der Prüfstand-Fläche mit raise_built und merkt sie im Schritt s für das Aufräumen (kind: cars,
-- flyers, others); nil, wenn es nicht ging (Grund in der Datei).
local function make(run, tb, s, params, kind)
  if params.raise_built == nil then params.raise_built = true end
  local ok, entity = pcall(function() return tb.surface().create_entity(params) end)
  if ok and entity then
    table.insert(s.made[kind or "others"], entity)
    return entity
  end
  tb.trace(run, params.name .. " bei " .. pos_text(tb, params.position) .. " ging nicht" .. (ok and "" or (": " .. tostring(entity))))
  return nil
end

local function remember(s, entity, kind)
  if valid(entity) then table.insert(s.made[kind or "others"], entity) end
  return entity
end

-- Echter Ernter (eingetragen über raise_built). opts: orientation, coal, spice (Laderaum), driver, field (Teppich).
local function new_harvester(run, tb, d, s, position, opts)
  opts = opts or {}
  local surface = tb.surface()
  local force = opts.force or d.force
  if opts.field then carpet(surface, position, opts.field) end
  local car = make(run, tb, s, {name = HARVESTER, position = position, force = force, orientation = opts.orientation or 0.25}, "cars")
  if not car then return nil end
  if opts.coal then tb.fuel(car, "coal", opts.coal) end
  if opts.spice then car.get_inventory(defines.inventory.car_trunk).insert{name = SPICE, count = opts.spice} end
  if opts.driver then
    local driver = tb.dummy_driver(car, force)
    remember(s, driver)
    s.drivers = s.drivers or {}
    s.drivers[car.unit_number] = driver
  end
  s.keys = s.keys or {}
  s.keys[vibration_lib.key_of(position)] = true
  return car
end

-- Auto mit Kohle und optional Puppe als Fahrer.
local function new_car(run, tb, d, s, position, opts)
  opts = opts or {}
  local car = make(run, tb, s, {name = "car", position = position, force = opts.force or d.force, orientation = opts.orientation or 0})
  if not car then return nil end
  tb.fuel(car, "coal", 5)
  if opts.driver then
    local driver = tb.dummy_driver(car, opts.force or d.force)
    remember(s, driver)
    s.drivers = s.drivers or {}
    s.drivers[car.unit_number] = driver
  end
  return car
end

-- Echter Ornithopter mit Raketentreibstoff (ab 0.9.0 nur Flugtreibstoff, opts.rocket Stück); opts.pilot setzt eine
-- Puppe als Pilot.
local function new_flyer(run, tb, d, s, position, opts)
  opts = opts or {}
  local flyer = make(run, tb, s, {name = FLYER, position = position, force = opts.force or d.force, create_build_effect_smoke = false}, "flyers")
  if not flyer then return nil end
  tb.fuel(flyer, "rocket-fuel", opts.rocket or 2)
  if opts.pilot then remember(s, tb.dummy_driver(flyer, opts.force or d.force)) end
  return flyer
end

local function deploy(car)
  local h = valid(car) and harvester.get(car)
  if not h then return false, "kein Datensatz" end
  return harvester.deploy(h)
end

-- Für die Testdateien scripts/testbench/tests/ (eine je Test; aufgeteilt aus t_sandwurm.lua, Verhalten unverändert).
return
{
  harvester = harvester,
  terrain = terrain,
  vibration_lib = vibration_lib,
  sandworm_lib = sandworm_lib,
  worms_lib = worms_lib,
  HARVESTER = HARVESTER,
  FLYER = FLYER,
  SPICE = SPICE,
  ROCK = ROCK,
  CHEST = CHEST,
  PREFIX = PREFIX,
  KILL_AFTER = KILL_AFTER,
  valid = valid,
  copy_pos = copy_pos,
  at = at,
  pos_text = pos_text,
  read = read,
  copy = copy,
  dist = dist,
  box_of = box_of,
  inside = inside,
  overlaps = overlaps,
  sand_at = sand_at,
  storage_ready = storage_ready,
  tiles = tiles,
  carpet = carpet,
  clear_area = clear_area,
  hunt_list = hunt_list,
  abort_hunts = abort_hunts,
  end_if_running = end_if_running,
  sandworms_in = sandworms_in,
  new_made = new_made,
  make = make,
  remember = remember,
  new_harvester = new_harvester,
  new_car = new_car,
  new_flyer = new_flyer,
  deploy = deploy,
}
