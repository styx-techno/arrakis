-- Prüfstand: Vibration und Würmer mit echtem Laufzeitcode (Phase 3d1, docs/plan-3d1.md 6; Vertrag siehe runner.lua).
--   T18: scripts/vibration.lua und scripts/worms.lua auf der Prüfstand-Fläche: Prototypen, Zeitlinie der Wärme bis zum
--        Wurmzeichen, Gewichte aller Quellen, feste Quellen, Zerfall, Nachbarschaft, Erstbefüllung, Vorsichtsmodus und
--        Prüfstand-Sperre. Elf Schritte laufen parallel ab Tick 2, jeder in eigenen Chunks mit 3 Chunks Abstand.
--   T19: Jagd und Biss: Lehrjagd mit Biss, „Schwer beschädigt“, Rettung per Ornithopter, feste Regeln, Grenzen,
--        Schonfrist, Flucht per Fahrt, Migration und Entfernen. Zehn Schritte nacheinander, Sektoren fest verteilt.
--   T20: Bedienung (interaktiv, nur mit Spieler): Schonfrist-Fenster, Unruhe, Vibrationsanzeige, Wurmzeichen, Rettung,
--        Biss, Vorsichtsmodus, Tipps, Fahrzeug ohne raise_built. Jede Verknüpfung und jedes Kontrollkästchen schreibt
--        eine MESSUNG-Zeile, jeder Zustandswechsel eine INFO-Zeile.
-- Gebaut wird mit raise_built = true (die Laufzeitmodule tragen ein), außer wo ein Schritt das Gegenteil prüft; Fahrer
-- sind Puppen ohne Spieler (tb.dummy_driver), gefahren wird über riding_state an Fahrzeug und Puppe jeden Tick (wie T2).
-- Die Tests zählen Ticks und lesen Takt-Werte in der Mitte zwischen zwei 60-Tick-Takten (tick % 60 == 30) oder erkennen
-- die Änderung jeden Tick: Die Reihenfolge zwischen den Takten der Module und dem Prüfstand-Tick ist nicht zugesichert.
-- Sollwerte stehen hier als Zahlen aus dem Plan (1, 4.3 bis 4.11), bewusst nicht aus den Modulen gelesen. Ausnahme sind
-- die Standardwahlen aus Plan 1, die Max noch ändern kann (Lehrjagd-Countdown, Untergrenze und Gewicht des
-- Vorsichtsmodus, Insassen beim Totalverlust, Wurmtempo für die Reichweite): Die liest der Test aus den Modulen, damit
-- ein Wechsel nur eine Stelle braucht.
-- Zustand nur in run.data (Zahlen, Texte, Positionen, LuaEntity-, LuaRenderObject- und LuaForce-Referenzen; vor jeder
-- Benutzung prüfen). Die Abläufe stehen als Funktionslisten in diesem Modul, run.data hält nur Schritt- und Phasennummern.
--
-- Isolation (Plan 4.18): Die Prüfstand-Fläche zählt nur für eingeschaltete Forces. T18 und T19 benutzen eigene Forces
-- (arrakis-t18, arrakis-t19; einmal anlegen, wiederverwenden), schalten sie in start ein und in cleanup aus, beenden dort
-- jede Jagd ihrer Force mit "abort", löschen Wärme und Ruhe ihrer Fläche und stellen Einstellung, Pause und Schonfrist
-- wieder her. T20 macht dasselbe mit der Force des Spielers und schreibt dazu deren Statistik zurück.
-- Jeder Schritt entfernt seine Quellen nach seiner letzten Messung (destroy{raise_destroy = true}) und setzt ihre Chunks
-- auf 0; sonst heizten sie weiter und nähmen einem späteren Schritt das Wurmzeichen.
-- Die Modultabellen heißen hier vibration_lib, worms_lib und flyer_lib (tools/check/api_names.py).

local harvester = require("scripts.harvester")
local intake = require("scripts.intake")
local flyer_lib = require("scripts.flyer")
local terrain = require("scripts.terrain")
local vibration_lib = require("scripts.vibration")
local worms_lib = require("scripts.worms")
local migrate = require("scripts.migrate")

local HARVESTER = "spice-harvester"
local FLYER = "arrakis-ornithopter"
local INTAKE = "arrakis-spice-intake"
local SPICE = "spice-sand"
local ROCK = "arrakis-rock"
local SAND = "sand-1"
local ERUPTION = "arrakis-worm-eruption"
local DUST = "arrakis-sand-dust"
local SIGNAL = "arrakis-wormsign"
local SOUNDS = {"arrakis-wormsign", "arrakis-rumble"}
local OVERLAY = "arrakis-vibration-overlay"
local TIPS = {"arrakis-briefing", "arrakis-wormsign-tip"}
local WORM_FORCE = "arrakis-sandworm"
local BITE_SETTING = "arrakis-worm-bite"
local ORNITHOPTER_TECH = "arrakis-ornithopter"
local T18_FORCE = "arrakis-t18"
local T19_FORCE = "arrakis-t19"
-- Force für den Force-Wechsel in T19 Schritt 5 e; geht im cleanup in arrakis-t19 auf.
local T19_OTHER_FORCE = "arrakis-t19b"

-- Sollwerte aus dem Plan --------------------------------------------------------------------------
local DECAY = 0.98
local HARVEST_WEIGHT = 30
local UNREST = 600
local WORMSIGN = 1000
local WARN_TICKS = 3600
-- Standardwahlen (Plan 1) aus den Modulen: 90 s Lehrjagd, Wiederaufbau unter 300, Einpacken mit Gewicht 0.
local TEACH_TICKS = worms_lib.TEACH_TICKS
local CAREFUL_LOW = vibration_lib.CAREFUL_LOW
local CAREFUL_PACKING = vibration_lib.WEIGHTS.by_state.careful_packing
local SEARCH_TICKS = 600
local REST_MIN, REST_MAX = 7200, 14400
local MAX_HUNTS = 3
local GRACE_ORNITHOPTER = 36000
local GRACE_LANDING = 108000
local PAUSE_TICKS = 36000
local HEAVY_SHARE = 0.1
local BITE_RADIUS = 4
-- Unruhe und Wurmzeichen ab kaltem Sand mit Gewicht 30: H_k = 1500 · (1 − 0,98^k), H_26 = 612,9, H_55 = 1006,2.
local UNREST_TAKE = 26
local WORMSIGN_TAKE = 55
local HEAT_TOLERANCE = 0.01
-- Wärme nach 3 Takten mit Gewicht w ab 0: w · (1 + 0,98 + 0,98²).
local THREE_TAKES = 1 + DECAY + DECAY * DECAY
-- Gewichte (Plan 4.3).
local WEIGHT =
{
  deployed = 30, deploying = 0, packing = 30, moving = 10, standing = 0, docked = 0,
  car = 4, tank = 8, spider = 6, locomotive = 6,
  big_drill = 8, drill = 3, pumpjack = 2, assembler = 1, furnace = 1
}
-- Tempo der Fahrzeuge in den Gewichtsmessungen (Kacheln/s): fährt sicher (≥ 0,06), bleibt in seinem Chunk.
local CRUISE = 1
local CAR_COLOR = {r = 0.2, g = 0.7, b = 1, a = 1}

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

local function check(failed, ok, label)
  if not ok then table.insert(failed, label) end
  return ok
end

local function near(value, target, tolerance)
  return type(value) == "number" and math.abs(value - target) <= tolerance
end

-- Flache Kopie (Schonfrist-Datensätze, Statistik).
local function copy(record)
  if record == nil then return nil end
  local out = {}
  for key, value in pairs(record) do out[key] = value end
  return out
end

-- Gleiche flache Tabellen (nil == nil)?
local function same(a, b)
  if a == nil or b == nil then return a == b end
  for key, value in pairs(a) do
    if b[key] ~= value then return false end
  end
  for key in pairs(b) do
    if a[key] == nil then return false end
  end
  return true
end

local function record_text(record)
  if record == nil then return "nil" end
  local keys = {}
  for key in pairs(record) do table.insert(keys, key) end
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do table.insert(parts, key .. "=" .. tostring(record[key])) end
  return "{" .. table.concat(parts, ", ") .. "}"
end

-- Ticks bis zur nächsten Takt-Mitte (tick % 60 == 30), mindestens min (Standard 1).
local function to_mid(min)
  min = min or 1
  local n = (30 - (game.tick + min) % 60) % 60
  return min + n
end

local function quality_exists(name)
  local ok, exists = pcall(function() return prototypes.quality[name] ~= nil end)
  return ok and exists
end

local function entity_exists(name)
  local ok, exists = pcall(function() return prototypes.entity[name] ~= nil end)
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

local function inside(box, position)
  local x, y = position.x or position[1], position.y or position[2]
  return x >= box.left_top.x and x <= box.right_bottom.x and y >= box.left_top.y and y <= box.right_bottom.y
end

local function overlaps(a, b)
  return a.left_top.x < b.right_bottom.x and b.left_top.x < a.right_bottom.x
    and a.left_top.y < b.right_bottom.y and b.left_top.y < a.right_bottom.y
end

-- Kacheln x1..x2 × y1..y2 (Kachelnummern, beide Grenzen eingeschlossen) mit einer Kachel belegen; raise wie
-- set_tiles(…, raise_event). Entities bleiben stehen.
local function tiles(surface, x1, y1, x2, y2, name, raise)
  local list = {}
  for x = x1, x2 do
    for y = y1, y2 do list[#list + 1] = {name = name, position = {x, y}} end
  end
  surface.set_tiles(list, true, false, true, raise == true)
  return #list
end

-- Spice-Sand auf jeder Kachel x1..x2 × y1..y2 (wie T13).
local function place_spice(surface, x1, y1, x2, y2, amount)
  local placed = 0
  for x = x1, x2 do
    for y = y1, y2 do
      if surface.create_entity{name = SPICE, position = {x + 0.5, y + 0.5}, amount = amount} then placed = placed + 1 end
    end
  end
  return placed
end

-- 13×13-Teppich um die Kachel unter position (das Erntefeld des Ernters).
local function carpet(surface, position, amount)
  local x, y = math.floor(position.x), math.floor(position.y)
  return place_spice(surface, x - 6, y - 6, x + 6, y + 6, amount or 1000)
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

-- Tempomat: Gas, solange das Fahrzeug langsamer als tps fährt.
local function cruise(car, driver, tps)
  if not valid(car) then return end
  gas(car, driver, math.abs(car.speed) * 60 < tps)
end

-- Spinne hin und her zwischen a und b; das Ziel wechselt, bevor sie ankommt (sie bleibt nie stehen).
local function patrol(spider, lane, tb)
  if not valid(spider) then return end
  local target = lane.leg == 2 and lane.b or lane.a
  if tb.distance(spider.position, target) < 5 then
    lane.leg = lane.leg == 2 and 1 or 2
    target = lane.leg == 2 and lane.b or lane.a
    pcall(function() spider.autopilot_destination = target end)
  elseif not read(function() return spider.autopilot_destination end) then
    pcall(function() spider.autopilot_destination = target end)
  end
end

local function render_ok(object)
  local ok, is_valid = pcall(function() return object ~= nil and object.valid end)
  return ok and is_valid == true
end

-- Grün (sichere Jagd, scripts/worms.lua): Grünanteil über dem Rotanteil.
local function is_green(object)
  if not render_ok(object) then return false end
  local color = read(function() return object.color end)
  if type(color) ~= "table" then return false end
  local r, g = color.r or color[1] or 0, color.g or color[2] or 0
  return g > r
end

local function trunk_count(car, item)
  local inventory = valid(car) and car.get_inventory(defines.inventory.car_trunk)
  return inventory and inventory.get_item_count(item) or 0
end

local function fuel_items(entity)
  local inventory = valid(entity) and entity.get_fuel_inventory()
  return inventory and inventory.get_item_count() or 0
end

local function car_state(car)
  if not valid(car) then return "weg" end
  local h = harvester.get(car)
  return h and h.state or "ohne Datensatz"
end

local function status_name(entity)
  if not valid(entity) then return "weg" end
  local status = read(function() return entity.status end)
  if status == nil then return "nil" end
  for name, value in pairs(defines.entity_status) do
    if value == status then return name end
  end
  return tostring(status)
end

-- Ist storage des Laufzeitcodes da (scripts/migrate.lua init, Schema 3)?
local function storage_ready()
  return storage.harvesters and storage.flyers and storage.intakes and storage.vib and storage.vib.heat
    and storage.vib.sources and storage.vib.testbench and storage.hunts and storage.hunts.list and storage.grace
    and storage.worm_stats and storage.sector_cooldown
end

local function force_named(name)
  return game.forces[name] or game.create_force(name)
end

-- Wärme -------------------------------------------------------------------------------------------

local function heat_at(surface, key)
  return vibration_lib.heat_entry(surface, key) or 0
end

-- Die 9 Chunks um key (vorhandene Einträge) auf 0.
local function zero_around(surface, key)
  local cx, cy = vibration_lib.chunk_of_key(key)
  for dx = -1, 1 do
    for dy = -1, 1 do
      if vibration_lib.heat_entry(surface, vibration_lib.chunk_key(cx + dx, cy + dy)) then
        vibration_lib.set_heat(surface, cx + dx, cy + dy, 0)
      end
    end
  end
end

-- Sind die 9 Chunks um key leer oder 0?
local function nine_zero(surface, key)
  local cx, cy = vibration_lib.chunk_of_key(key)
  for dx = -1, 1 do
    for dy = -1, 1 do
      local h = vibration_lib.heat_entry(surface, vibration_lib.chunk_key(cx + dx, cy + dy))
      if h and h > 1e-9 then return false end
    end
  end
  return true
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

-- Jagden nach id; filter(hunt) wählt aus (nil: alle).
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

-- Zahl der regulären Jagden (ohne Befehlsjagden) anderer Forces.
local function foreign_regular(own)
  local n = 0
  for _, hunt in pairs(storage.hunts.list) do
    if not hunt.debug and not own[hunt.force_index] then n = n + 1 end
  end
  return n
end

-- Ist die Sandwurm-Force da und feindlich zu force (beide Richtungen, ohne Waffenruhe)?
local function worm_hostile(force)
  local worm = game.forces[WORM_FORCE]
  if not (worm and force and force.valid) then return false end
  return not worm.get_friend(force) and not force.get_friend(worm)
    and not worm.get_cease_fire(force) and not force.get_cease_fire(worm)
end

local function hunt_text(tb, hunt)
  if not hunt then return "keine Jagd" end
  return string.format("Jagd %d %s%s%s, Zustand %s, Warnung %d, Biss %d (%d Ticks), Reichweite %s, safe %s%s",
    hunt.id, hunt.kind, hunt.debug and " (Befehl)" or "", hunt.teaching and " (Lehrjagd)" or "", hunt.state,
    hunt.warn_tick, hunt.eta_tick, hunt.eta_tick - hunt.warn_tick, tb.num(hunt.reach), tostring(hunt.safe),
    hunt.outcome and (", Ergebnis " .. hunt.outcome) or "")
end

-- Eruptionen um position (Explosion, kurz sichtbar), für MESSUNG.
local function eruptions_at(surface, position, radius)
  return #surface.find_entities_filtered{name = ERUPTION, position = position, radius = radius or 2}
end

-- Entities und Aufräumen ------------------------------------------------------------------------

local function new_made()
  return {cars = {}, flyers = {}, others = {}}
end

-- Erzeugt eine Entity (Standard: Prüfstand-Fläche) und merkt sie im Schritt s für das Aufräumen (kind: cars, flyers,
-- others); nil, wenn es nicht ging (Grund in der Datei).
local function make(run, tb, s, params, kind, surface)
  local ok, entity = pcall(function() return (surface or tb.surface()).create_entity(params) end)
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

-- Echter Ernter (Standard: eingetragen über raise_built). opts: force, orientation, coal, spice (Laderaum), driver
-- (Puppe als Fahrer), field (13×13-Spice-Teppich), raw (ohne raise_built).
local function new_harvester(run, tb, s, position, opts)
  opts = opts or {}
  local surface = tb.surface()
  if opts.field then carpet(surface, position, opts.field) end
  local car = make(run, tb, s, {name = HARVESTER, position = position, force = opts.force, orientation = opts.orientation or 0.25,
    raise_built = not opts.raw}, "cars")
  if not car then return nil end
  if opts.coal then tb.fuel(car, "coal", opts.coal) end
  if opts.spice then car.get_inventory(defines.inventory.car_trunk).insert{name = SPICE, count = opts.spice} end
  if opts.driver then
    local driver = tb.dummy_driver(car, opts.force)
    remember(s, driver)
    s.drivers = s.drivers or {}
    s.drivers[car.unit_number] = driver
  end
  return car
end

-- Fahrzeug aus Vanilla (car, tank, spidertron) mit Kohle und optional Puppe. opts: force, orientation, coal, driver, raw.
local function new_vehicle(run, tb, s, name, position, opts)
  opts = opts or {}
  local vehicle = make(run, tb, s, {name = name, position = position, force = opts.force, orientation = opts.orientation,
    raise_built = not opts.raw}, "others")
  if not vehicle then return nil end
  if opts.coal then tb.fuel(vehicle, "coal", opts.coal) end
  if opts.driver then
    local driver = tb.dummy_driver(vehicle, opts.force)
    remember(s, driver)
    s.drivers = s.drivers or {}
    s.drivers[vehicle.unit_number] = driver
  end
  pcall(function() vehicle.color = CAR_COLOR end)
  return vehicle
end

-- Echter Ornithopter mit Kohle; opts.pilot setzt eine Puppe als Pilot.
local function new_flyer(run, tb, s, position, opts)
  opts = opts or {}
  local flyer = make(run, tb, s, {name = FLYER, position = position, force = opts.force, raise_built = true,
    create_build_effect_smoke = false}, "flyers")
  if not flyer then return nil end
  tb.fuel(flyer, "coal", opts.coal or 10)
  if opts.pilot then remember(s, tb.dummy_driver(flyer, opts.force)) end
  return flyer
end

local function driver_of(s, vehicle)
  return valid(vehicle) and s.drivers and s.drivers[vehicle.unit_number] or nil
end

-- Strom für ein Gebäude mit Mitte p (Kachelmitte): Schnittstelle 2×2 und Mittelmast westlich (wie T4).
local function power(run, tb, s, p, force)
  local n, m = math.floor(p.x), math.floor(p.y)
  local eei = make(run, tb, s, {name = "electric-energy-interface", position = {x = n - 6, y = m + 1}, force = force})
  local pole = make(run, tb, s, {name = "medium-electric-pole", position = {x = n - 3.5, y = m + 0.5}, force = force})
  return eei ~= nil and pole ~= nil
end

-- Erz unter einem Bohrer (Kacheln um die Mitte, radius 2 = 5×5).
local function ore(surface, p, name, radius, amount)
  local n, m = math.floor(p.x), math.floor(p.y)
  local placed = 0
  for x = n - radius, n + radius do
    for y = m - radius, m + radius do
      if surface.create_entity{name = name, position = {x + 0.5, y + 0.5}, amount = amount or 10000} then placed = placed + 1 end
    end
  end
  return placed
end

-- Entfernt, was ein Schritt gebaut hat: zuerst Ernter (raise_destroy, auch auf der Ablage), dann Ornithopter, dann den
-- Rest; danach die Chunks seiner Quellen auf 0.
local function tidy(s)
  local made = s.made
  if made then
    for _, kind in ipairs({"cars", "flyers", "others"}) do
      for _, entity in pairs(made[kind]) do
        if valid(entity) then pcall(function() entity.destroy{raise_destroy = true} end) end
      end
      made[kind] = {}
    end
  end
  local surface = game.get_surface("arrakis-testbench")
  if surface and s.keys then
    for key in pairs(s.keys) do pcall(zero_around, surface, key) end
  end
end

-- Merkt den Chunk einer Quelle für das Aufräumen.
local function keep_key(s, position)
  s.keys = s.keys or {}
  local key = vibration_lib.key_of(position)
  s.keys[key] = true
  return key
end

-- Ablauf ----------------------------------------------------------------------------------------
-- Je Schritt eine Liste von Phasen (wie T15). Eine Phase gibt zurück: "poll" = nächsten Tick dieselbe Phase, Zahl n =
-- nächste Phase in n Ticks, again(n) = dieselbe Phase in n Ticks, "end" = Schritt fertig. Jeder Schritt schreibt genau eine OK/FEHLER-Zeile (verdict oder
-- fail; T19 Schritt 5 eine je Teil); danach räumt tidy seine Entities ab.

-- Dieselbe Phase in n Ticks wieder (Rückgabe einer Phase, wird nicht gespeichert).
local function again(n)
  return {again = n}
end

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

local function lanes_init(d, count, first_tick)
  d.lanes = {}
  d.results = {}
  for number = 1, count do
    d.lanes[number] = {phase = 1, wait_until = first_tick}
    d["s" .. number] = {made = new_made()}
  end
end

local function lane_done(run, tb, d, number)
  local lane = d.lanes[number]
  lane.done = true
  local ok, err = pcall(tidy, d["s" .. number])
  if not ok then tb.trace(run, "Aufräumen nach Schritt " .. number .. " ging nicht: " .. tostring(err)) end
end

-- Eine Phase des Schritts number, wenn er dran ist.
local function lane_step(run, tb, d, steps, number)
  local lane = d.lanes[number]
  if lane.done or game.tick < lane.wait_until then return end
  local phase = steps[number][lane.phase]
  if not phase then
    if not d.results[number] then fail(run, tb, number, "keine Ergebniszeile (Prüfstand-Fehler)") end
    lane_done(run, tb, d, number)
    return
  end
  local ok, result = pcall(phase, run, tb, d, d["s" .. number])
  if not ok then
    fail(run, tb, number, "Skriptfehler: " .. tostring(result))
    result = "end"
  end
  if result == "poll" then return end
  if type(result) == "table" then
    lane.wait_until = game.tick + (result.again or 1)
    return
  end
  if result == "end" then
    lane_done(run, tb, d, number)
  else
    lane.phase = lane.phase + 1
    lane.wait_until = game.tick + (type(result) == "number" and result or 1)
  end
end

local function summary(run, count, label)
  local ok, wrong, open = 0, {}, {}
  for number = 1, count do
    local result = run.data.results[number]
    if result == "OK" then
      ok = ok + 1
    elseif result == "INFO" or result == "MESSUNG" then
      table.insert(open, tostring(number))
    else
      table.insert(wrong, tostring(number))
    end
  end
  local text = string.format("%d/%d %s OK", ok, count, label or "Schritte")
  if #wrong > 0 then text = text .. ", FEHLER in " .. table.concat(wrong, ", ") end
  if #open > 0 then text = text .. ", von Hand prüfen: " .. table.concat(open, ", ") end
  return text
end

-- Entity-Tode (weitergeleitetes entity_died): je unit_number Tick, Name, Ort, Force, Täter, in Reihenfolge.
local function note_death(d, event)
  local entity = event.entity
  if not valid(entity) then return end
  d.deaths = d.deaths or {}
  d.death_list = d.death_list or {}
  local record =
  {
    tick = event.tick, name = entity.name, un = entity.unit_number, position = copy_pos(entity.position),
    force = event.force and event.force.valid and event.force.name or nil,
    cause = event.cause and (event.cause.valid and event.cause.name or "ungültig") or nil
  }
  if entity.unit_number then d.deaths[entity.unit_number] = record end
  table.insert(d.death_list, record)
end

local function died(d, entity_un)
  return d.deaths and entity_un and d.deaths[entity_un] or nil
end

-- Tode seit Index from (Namen in Reihenfolge), optional nur in box.
local function deaths_since(d, from, box)
  local names = {}
  for i = (from or 0) + 1, #(d.death_list or {}) do
    local record = d.death_list[i]
    if not box or inside(box, record.position) then table.insert(names, record.name) end
  end
  return names
end

-- Gemeinsames Aufräumen von T18 und T19 (Plan 4.18).
local function isolate_cleanup(run, tb, d, forces)
  local indices = {}
  for _, force in pairs(forces) do
    if valid(force) then indices[force.index] = true end
  end
  pcall(abort_hunts, indices)
  if d.lanes then
    for number in pairs(d.lanes) do pcall(tidy, d["s" .. number]) end
  end
  local surface = tb.surface()
  if d.box then pcall(clear_area, surface, d.box) end
  for _, force in pairs(forces) do
    if valid(force) then vibration_lib.testbench_disable(force) end
  end
  if d.saved then
    local force = forces[1]
    if valid(force) then worms_lib.grace_restore(force, d.saved.grace) end
    worms_lib.set_paused(d.saved.paused)
    if d.saved.bite_written then
      pcall(function() settings.global[BITE_SETTING] = {value = d.saved.bite} end)
    end
  end
  worms_lib.ensure_force()
end

-- T18 Wärme: echter Code ---------------------------------------------------------------------------
-- Fläche ±300 Kacheln um den Ursprung (x = 32 000 ist eine Sektor-Ecke). Zellen sind Chunks im Raster von 3 Chunks:
-- cx, cy ∈ Ursprung + {−8, −5, −2, 1, 4, 7}; eine Quelle in Zelle (i, j) beeinflusst nur die 3×3 Chunks um sich, und W an
-- der Nachbarzelle liest keinen davon. Reihen (j): 1 Ernter-Zustände (Schritt 3), 2 Fahrzeuge (3), 3 Lokomotive (3) und
-- feste Quellen (4), 4 feste Quellen (4), Zeitlinie (2, Zelle 4 allein im Sektor), Zerfall (5); 5 Nachbarschaft (6) und
-- Erstbefüllung (7); 6 Vorsichtsmodus (8 bis 10) und Prüfstand-Sperre (11).

local T18_HALF = 300
local T18_GRID = {-8, -5, -2, 1, 4, 7}

-- Zelle (i, j): Chunk, Mitte (ganze Kachel), chunk_key.
local function t18_cell(d, i, j)
  local cx, cy = d.bcx + T18_GRID[i], d.bcy + T18_GRID[j]
  return {cx = cx, cy = cy, x = cx * 32 + 16, y = cy * 32 + 16, key = vibration_lib.chunk_key(cx, cy)}
end

-- Kachelmitte in Zelle (i, j), dx, dy Kacheln von der Mitte.
local function t18_pos(d, i, j, dx, dy)
  local c = t18_cell(d, i, j)
  return {x = c.x + (dx or 0) + 0.5, y = c.y + (dy or 0) + 0.5}
end

local t18_steps = {}

-- Schritt 1: Prototypen, storage, Sandwurm-Force.
function t18_steps.s1_check(run, tb, d, s)
  local failed = {}
  local eruption = read(function() return prototypes.entity[ERUPTION] end)
  check(failed, eruption ~= nil and eruption.type == "explosion", "Eruption " .. ERUPTION .. " fehlt (oder keine explosion)")
  check(failed, read(function() return prototypes.trivial_smoke[DUST] end) ~= nil, "Staub " .. DUST .. " fehlt")
  check(failed, read(function() return prototypes.virtual_signal[SIGNAL] end) ~= nil, "Signal " .. SIGNAL .. " fehlt")
  for _, path in ipairs(SOUNDS) do
    check(failed, read(function() return helpers.is_valid_sound_path(path) end) == true, "Geräusch " .. path .. " fehlt")
  end
  local shortcut = read(function() return prototypes.shortcut[OVERLAY] end)
  check(failed, shortcut ~= nil, "Verknüpfung " .. OVERLAY .. " fehlt")
  if shortcut then check(failed, read(function() return shortcut.toggleable end) == true, "Verknüpfung " .. OVERLAY .. " nicht toggleable") end
  -- Tipps: LuaPrototypes hat keine Tabelle dafür; verbindlich prüft tools/check/checks.lua.
  for _, name in ipairs(TIPS) do
    local ok, history = pcall(prototypes.get_history, "tips-and-tricks-item", name)
    local text
    if not ok then
      text = "nicht lesbar (" .. tostring(history) .. ")"
    elseif history then
      text = "angelegt von " .. tostring(history.created)
    else
      text = "nil"
    end
    tb.log(run, "MESSUNG", "1) Tipp " .. name .. ": get_history " .. text)
  end
  local vib = storage.vib or {}
  local hunts = storage.hunts or {}
  local parts =
  {
    {"schema", storage.schema == migrate.SCHEMA}, {"rng", storage.rng ~= nil}, {"grace", type(storage.grace) == "table"},
    {"vib.sources", type(vib.sources) == "table"}, {"vib.heat", type(vib.heat) == "table"},
    {"vib.rumble", type(vib.rumble) == "table"}, {"vib.overlay", type(vib.overlay) == "table"},
    {"vib.testbench", type(vib.testbench) == "table"}, {"hunts.list", type(hunts.list) == "table"},
    {"hunts.next_id", type(hunts.next_id) == "number"}, {"sector_cooldown", type(storage.sector_cooldown) == "table"},
    {"worm_stats", type(storage.worm_stats) == "table"}, {"migration", type(storage.migration) == "table"}
  }
  for _, part in ipairs(parts) do check(failed, part[2], "storage." .. part[1] .. " fehlt") end
  check(failed, game.forces[WORM_FORCE] ~= nil, "Sandwurm-Force " .. WORM_FORCE .. " fehlt")
  check(failed, worm_hostile(d.force), "Sandwurm-Force nicht feindlich zu " .. T18_FORCE)
  check(failed, worm_hostile(game.forces.player), "Sandwurm-Force nicht feindlich zu player")
  return verdict(run, tb, 1, "Prototypen, storage, Sandwurm-Force", failed,
    "Eruption, Staub, Signal, 2 Geräusche, Verknüpfung, 13 storage-Tabellen, Force geprüft")
end

-- Schritt 2: Zeitlinie eines Ernters ab kaltem Sand bis zum Wurmzeichen.
function t18_steps.s2_build(run, tb, d, s)
  local position = t18_pos(d, 4, 4)
  s.car = new_harvester(run, tb, s, position, {force = d.force, coal = 20, field = 1000})
  if not s.car then return fail(run, tb, 2, "Aufbau ging nicht (Einzelheiten in der Datei)") end
  s.key = keep_key(s, position)
  local h = harvester.get(s.car)
  if not h then return fail(run, tb, 2, "Ernter nicht eingetragen (raise_built)") end
  local ok, reason = harvester.deploy(h)
  if not ok then return fail(run, tb, 2, "Aufbauen ging nicht: " .. tostring(reason)) end
  s.k, s.last, s.start, s.failed = 0, 0, game.tick, {}
  return 1
end

-- Jeden Tick: Wärme des Chunks; jede Änderung ist ein Takt mit Beitrag (Gewicht 30 ab kaltem Sand).
-- Gibt "poll" zurück oder true, wenn das Wurmzeichen da ist (oder ausbleibt).
local function timeline(s, car, label_failed)
  local h = harvester.get(car)
  if not s.td and h and h.state == "deployed" then s.td = game.tick end
  local value = heat_at(car.surface, s.key)
  if value ~= s.last then
    s.last = value
    s.k = s.k + 1
    local k = s.k
    if not s.td then check(label_failed, false, "Wärme vor dem Aufbau (Takt " .. k .. ")") end
    local expected = 1500 * (1 - DECAY ^ k)
    if not s.heat_bad and not near(value, expected, HEAT_TOLERANCE) then
      s.heat_bad = true
      check(label_failed, false, string.format("Wärme nach %d Takten %.4f statt %.4f ± %.2f", k, value, expected, HEAT_TOLERANCE))
    end
    local unrest = h ~= nil and h.alarm_unrest == true
    if unrest and not s.unrest_tick then s.unrest_tick, s.unrest_k = game.tick, k end
    if not s.unrest_bad and unrest ~= (k >= UNREST_TAKE) then
      s.unrest_bad = true
      check(label_failed, false, "Unruhe im Takt " .. k .. ": " .. tostring(unrest) .. " (erwartet ab Takt " .. UNREST_TAKE .. ")")
    end
    local hunt = worms_lib.hunt_of(car)
    if hunt then
      s.hunt, s.sign_tick, s.sign_k, s.sign_heat = hunt, game.tick, k, value
      return true
    end
    if k > WORMSIGN_TAKE + 5 then
      check(label_failed, false, "kein Wurmzeichen bis Takt " .. k)
      return true
    end
  elseif game.tick - (s.td or s.start) > 4500 then
    check(label_failed, false, "kein Wurmzeichen nach 75 s (Takt " .. s.k .. ", Wärme " .. string.format("%.1f", value) .. ")")
    return true
  end
  return "poll"
end

function t18_steps.s2_watch(run, tb, d, s)
  if not valid(s.car) then return fail(run, tb, 2, "Ernter weg") end
  if timeline(s, s.car, s.failed) == true then return 1 end
  return "poll"
end

-- Prüft die Zeitlinie und die Jagd im Takt des Wurmzeichens (gemeinsam mit T19 Schritt 4).
local function check_sign(failed, s, label, teaching)
  local td = s.td or s.start
  check(failed, s.unrest_k == UNREST_TAKE, label .. "Unruhe im Takt " .. tostring(s.unrest_k) .. " statt " .. UNREST_TAKE)
  if s.unrest_tick then
    check(failed, s.unrest_tick >= td + 1440 and s.unrest_tick <= td + 1620,
      label .. "Unruhe bei T_d + " .. (s.unrest_tick - td) .. " statt in [1440, 1620]")
  end
  check(failed, s.sign_k == WORMSIGN_TAKE, label .. "Wurmzeichen im Takt " .. tostring(s.sign_k) .. " statt " .. WORMSIGN_TAKE)
  if s.sign_tick then
    check(failed, s.sign_tick >= td + 3180 and s.sign_tick <= td + 3360,
      label .. "Wurmzeichen bei T_d + " .. (s.sign_tick - td) .. " statt in [3180, 3360]")
    check(failed, near(s.sign_heat, 1006.2, 0.5), label .. "Wärme beim Wurmzeichen " .. string.format("%.2f", s.sign_heat or -1) .. " statt 1006,2 ± 0,5")
  end
  local hunt = s.hunt
  if not hunt then return end
  local ticks = teaching and TEACH_TICKS or WARN_TICKS
  check(failed, hunt.teaching == (teaching == true), label .. "Lehrjagd " .. tostring(hunt.teaching))
  check(failed, hunt.eta_tick - hunt.warn_tick == ticks, label .. "Countdown " .. (hunt.eta_tick - hunt.warn_tick) .. " statt " .. ticks)
  check(failed, hunt.eta_tick % 10 == 0, label .. "eta_tick " .. hunt.eta_tick .. " kein Vielfaches von 10")
  check(failed, render_ok(hunt.renders.ring) and render_ok(hunt.renders.text), label .. "Ring oder Sekunden fehlen")
  local h = harvester.get(s.car)
  check(failed, h ~= nil and h.alarm_hunt_eta == hunt.eta_tick, label .. "alarm_hunt_eta " .. tostring(h and h.alarm_hunt_eta))
end

function t18_steps.s2_end(run, tb, d, s)
  local failed = s.failed
  local hunt = s.hunt
  local surface = tb.surface()
  check_sign(failed, s, "", true)
  local tag_text = "–"
  if hunt then
    local cx, cy = vibration_lib.chunk_of_key(hunt.origin_key)
    local charted = read(function() return d.force.is_chunk_charted(surface, {x = cx, y = cy}) end)
    if charted then
      tag_text = valid(hunt.tag) and "gültig" or "fehlt"
      check(failed, valid(hunt.tag), "Kartenmarkierung fehlt, obwohl der Chunk kartiert ist")
    else
      tag_text = "Chunk nicht kartiert"
      tb.log(run, "INFO", "2) Chunk des Wurmzeichens nicht kartiert (force.chart ohne Spieler): Markierung nicht prüfbar [V6]")
    end
    local ring, text, tag = hunt.renders.ring, hunt.renders.text, hunt.tag
    worms_lib.end_hunt(hunt, "escaped", "quiet")
    check(failed, storage.hunts.list[hunt.id] == nil, "Jagd nach end_hunt noch da")
    check(failed, nine_zero(surface, hunt.origin_key), "9 Chunks um den Ursprung nicht 0")
    local until_tick = vibration_lib.resting(surface.index, hunt.sector_key)
    local rest = until_tick and (until_tick - game.tick)
    check(failed, rest ~= nil and rest >= REST_MIN and rest <= REST_MAX, "Ruhe " .. tostring(rest) .. " Ticks statt 7200 bis 14400")
    local g = worms_lib.grace_snapshot(d.force)
    check(failed, g ~= nil and g.first_hunt_done == true, "first_hunt_done nicht gesetzt")
    check(failed, not render_ok(ring) and not render_ok(text), "Ring oder Sekunden nach dem Ende noch da")
    check(failed, not valid(tag), "Kartenmarkierung nach dem Ende noch da")
    s.rest = rest
  end
  tb.log(run, "MESSUNG", string.format("2) T_d = %s; Unruhe Tick %s (T_d + %s, Takt %s); Wurmzeichen Tick %s (T_d + %s, Takt %s, Wärme %s)",
    tostring(s.td), tostring(s.unrest_tick), s.unrest_tick and s.td and tostring(s.unrest_tick - s.td) or "–", tostring(s.unrest_k),
    tostring(s.sign_tick), s.sign_tick and s.td and tostring(s.sign_tick - s.td) or "–", tostring(s.sign_k),
    s.sign_heat and string.format("%.2f", s.sign_heat) or "–"))
  return verdict(run, tb, 2, "Zeitlinie bis zum Wurmzeichen", failed, string.format("Unruhe Takt %s, Wurmzeichen Takt %s, %s; Markierung %s, Ruhe %s Ticks",
    tostring(s.unrest_k), tostring(s.sign_k), hunt_text(tb, hunt), tag_text, tostring(s.rest)))
end

-- Schritt 3: Gewichte. Jede Quelle in ihrer Zelle; Messung über 3 Takte ab 0 in den 3×3 Chunks um die Quelle.
function t18_steps.s3_build(run, tb, d, s)
  local force = d.force
  local surface = tb.surface()
  s.src = {}
  local function add(label, entity, expect, extra)
    local entry = {label = label, entity = entity, expect = expect}
    for key, value in pairs(extra or {}) do entry[key] = value end
    table.insert(s.src, entry)
    if entity then keep_key(s, entity.position) end
    return entry
  end
  -- Reihe 1: Ernter-Zustände.
  add("Ernter aufgebaut", new_harvester(run, tb, s, t18_pos(d, 1, 1), {force = force, coal = 10, field = 1000}), WEIGHT.deployed,
    {state = "deployed", deploy = true})
  add("Ernter beim Aufbauen", new_harvester(run, tb, s, t18_pos(d, 2, 1), {force = force, coal = 10, field = 1000}), WEIGHT.deploying,
    {state = "deploying", late_deploy = true})
  add("Ernter beim Einpacken von Hand", new_harvester(run, tb, s, t18_pos(d, 3, 1), {force = force, coal = 10, field = 1000}),
    WEIGHT.packing, {state = "packing", deploy = true, pack = true})
  add("Ernter mobil fahrend", new_harvester(run, tb, s, t18_pos(d, 4, 1, -12, 0), {force = force, coal = 20, driver = true}),
    WEIGHT.moving, {state = "mobile", drive = true})
  add("Ernter mobil stehend", new_harvester(run, tb, s, t18_pos(d, 5, 1), {force = force, coal = 10}), WEIGHT.standing, {state = "mobile"})
  -- Angedockt: Annahme auf Fels (±6 Kacheln), Ernter 3,9 Kacheln östlich, seine Ostkante über Sand.
  local c = t18_cell(d, 6, 1)
  local p = {x = c.x - 4, y = c.y}
  tiles(surface, p.x - 6, p.y - 6, p.x + 4, p.y + 4, ROCK)
  local intake_entity = make(run, tb, s, {name = INTAKE, position = p, force = force, raise_built = true})
  local docked = new_harvester(run, tb, s, {x = p.x + 3.9, y = p.y}, {force = force, coal = 10})
  local docked_entry = add("Ernter angedockt (Ecke im Sand)", docked, WEIGHT.docked, {state = "docked"})
  local record = valid(intake_entity) and intake.get(intake_entity)
  local h = docked and harvester.get(docked)
  docked_entry.dock_ok = record and not record.bad and h and harvester.dock(h, record) or false
  docked_entry.corner = docked and terrain.has_sand_under(docked)
  -- Reihe 2: Fahrzeuge.
  add("Auto fahrend", new_vehicle(run, tb, s, "car", t18_pos(d, 1, 2, -12, 0), {force = force, coal = 10, driver = true, orientation = 0.25}),
    WEIGHT.car, {drive = true})
  add("Auto stehend", new_vehicle(run, tb, s, "car", t18_pos(d, 2, 2), {force = force, coal = 10, orientation = 0.25}), 0)
  add("Panzer fahrend", new_vehicle(run, tb, s, "tank", t18_pos(d, 3, 2, -12, 0), {force = force, coal = 10, driver = true, orientation = 0.25}),
    WEIGHT.tank, {drive = true})
  local sc = t18_cell(d, 4, 2)
  -- Spidertron zwischen x − 10 und x + 10: bleibt in seinem Chunk, die 3×3-Summe um ihn fasst jeden Beitrag.
  add("Spidertron mit Ziel", new_vehicle(run, tb, s, "spidertron", {x = sc.x - 10, y = sc.y}, {force = force}), WEIGHT.spider,
    {patrol = {a = {x = sc.x + 10, y = sc.y}, b = {x = sc.x - 10, y = sc.y}, leg = 1}})
  add("Spidertron stehend", new_vehicle(run, tb, s, "spidertron", t18_pos(d, 5, 2), {force = force}), 0)
  local fc = t18_cell(d, 6, 2)
  add("Ornithopter fliegend", new_flyer(run, tb, s, {x = fc.x - 10, y = fc.y}, {force = force, pilot = true}), 0,
    {patrol = {a = {x = fc.x + 10, y = fc.y}, b = {x = fc.x - 10, y = fc.y}, leg = 1}, flyer = true})
  -- Reihe 3, Zelle 1: Lokomotive auf Schienen (nur weight_of mit train.speed > 0).
  -- Aufbauen schon jetzt (5 s, fertig vor s3_run in 330 Ticks); eingepackt wird im ersten s3_run (10 s, reicht bis m1).
  for _, entry in ipairs(s.src) do
    local h = entry.deploy and valid(entry.entity) and harvester.get(entry.entity)
    if h then harvester.deploy(h) end
  end
  local lc = t18_cell(d, 1, 3)
  s.loco_text = "nicht gebaut"
  local rails = 0
  for x = lc.x - 15, lc.x + 15, 2 do
    if make(run, tb, s, {name = "straight-rail", position = {x = x, y = lc.y + 1}, direction = defines.direction.east, force = force}) then
      rails = rails + 1
    end
  end
  local loco = make(run, tb, s, {name = "locomotive", position = {x = lc.x, y = lc.y + 1}, orientation = 0.25, force = force, raise_built = true})
  if loco then
    tb.fuel(loco, "coal", 5)
    local ok, err = pcall(function()
      loco.train.manual_mode = true
      loco.train.speed = 0.05
    end)
    local speed = read(function() return loco.train.speed end)
    s.loco_weight = vibration_lib.weight_of(loco)
    s.loco_text = string.format("%d Schienen, train.speed %s, weight_of %s%s", rails, tb.num(speed, 3), tostring(s.loco_weight),
      ok and "" or (" (" .. tostring(err) .. ")"))
    s.loco_moving = type(speed) == "number" and speed > 0
    pcall(function() loco.train.speed = 0 end)
  end
  s.start = game.tick
  return 330
end

-- Jeden Tick: fahren; vor der Messung einpacken und das zweite Aufbauen beginnen; m0 Wärme 0, m1 nach 3 Takten lesen.
function t18_steps.s3_run(run, tb, d, s)
  local surface = tb.surface()
  if not s.m0 then
    for _, entry in ipairs(s.src) do
      local h = valid(entry.entity) and harvester.get(entry.entity)
      if h and entry.deploy and h.state == "mobile" then harvester.deploy(h) end
      if h and entry.pack then entry.pack_ok = harvester.toggle(entry.entity, nil) end
    end
    s.m0 = game.tick + to_mid(90)
    s.m1 = s.m0 + 180
  end
  local now = game.tick
  for _, entry in ipairs(s.src) do
    local entity = entry.entity
    if valid(entity) then
      if entry.drive then cruise(entity, driver_of(s, entity), CRUISE) end
      if entry.patrol then patrol(entity, entry.patrol, tb) end
      if entry.late_deploy and now == s.m0 - 20 then
        local h = harvester.get(entity)
        if h then entry.deploy_ok = harvester.deploy(h) end
      end
    end
  end
  if now == s.m0 then
    for _, entry in ipairs(s.src) do
      local entity = entry.entity
      if valid(entity) then
        entry.key = vibration_lib.key_of(entity.position)
        zero_around(surface, entry.key)
        entry.w0 = vibration_lib.weight_of(entity)
        entry.state0 = car_state(entity)
      end
    end
  elseif now >= s.m1 then
    local failed, parts = {}, {}
    for _, entry in ipairs(s.src) do
      local entity = entry.entity
      if not valid(entity) then
        check(failed, false, entry.label .. ": nicht gebaut oder weg")
      else
        local w1 = vibration_lib.weight_of(entity)
        local value = entry.key and vibration_lib.sum3(surface.index, entry.key) or -1
        local expected = entry.expect * THREE_TAKES
        check(failed, entry.w0 == entry.expect and w1 == entry.expect,
          entry.label .. ": weight_of " .. tostring(entry.w0) .. "/" .. tostring(w1) .. " statt " .. entry.expect)
        check(failed, near(value, expected, HEAT_TOLERANCE),
          entry.label .. string.format(": Wärme %.4f statt %.4f", value, expected))
        if entry.state then
          local state1 = car_state(entity)
          check(failed, entry.state0 == entry.state and state1 == entry.state,
            entry.label .. ": Zustand " .. tostring(entry.state0) .. "/" .. state1 .. " statt " .. entry.state)
        end
        if entry.flyer then check(failed, vibration_lib.source_of(entity) == nil, entry.label .. ": als Quelle eingetragen") end
        if entry.dock_ok ~= nil then
          check(failed, entry.dock_ok == true, entry.label .. ": Andocken ging nicht")
          check(failed, entry.corner == true, entry.label .. ": keine Ecke im Sand (Aufbau)")
        end
        table.insert(parts, string.format("%s %s/%.2f", entry.label, tostring(w1), value))
      end
    end
    if s.loco_moving then
      check(failed, s.loco_weight == WEIGHT.locomotive, "Lokomotive: weight_of " .. tostring(s.loco_weight) .. " statt " .. WEIGHT.locomotive)
    else
      tb.log(run, "INFO", "3) Lokomotive nicht prüfbar: " .. s.loco_text)
    end
    tb.trace(run, "3) Lokomotive: " .. s.loco_text)
    return verdict(run, tb, 3, "Gewichte", failed, table.concat(parts, ", ") .. "; Lokomotive " .. tostring(s.loco_weight))
  end
  if now > s.m1 + 60 then return fail(run, tb, 3, "Messung verpasst (Prüfstand-Fehler)") end
  return "poll"
end

-- Schritt 4: feste Quellen [V13]. Strom: Schnittstelle und Mast wie T4; Abnehmer: Kiste an drop_position, Lagertank.
function t18_steps.s4_build(run, tb, d, s)
  local force = d.force
  local surface = tb.surface()
  s.src = {}
  s.missing = {}
  local function add(label, entity, expect, extra)
    local entry = {label = label, entity = entity, expect = expect}
    for key, value in pairs(extra or {}) do entry[key] = value end
    table.insert(s.src, entry)
    if entity then keep_key(s, entity.position) else table.insert(s.missing, label) end
    return entry
  end
  local function drill(label, name, i, j, opts)
    local p = t18_pos(d, i, j)
    if opts.rock then tiles(surface, math.floor(p.x) - 2, math.floor(p.y) - 2, math.floor(p.x) + 2, math.floor(p.y) + 2, ROCK) end
    ore(surface, p, "iron-ore", opts.radius or 2)
    if opts.power then power(run, tb, s, p, force) end
    local entity = make(run, tb, s, {name = name, position = p, force = force, direction = defines.direction.north, raise_built = true})
    if entity then
      local drop = read(function() return entity.drop_position end)
      if drop then make(run, tb, s, {name = "wooden-chest", position = drop, force = force}) end
    end
    return add(label, entity, opts.expect, {rock = opts.rock, under = opts.under})
  end
  if entity_exists("big-mining-drill") then
    drill("Großbohrer", "big-mining-drill", 2, 3, {power = true, radius = 3, expect = WEIGHT.big_drill})
  else
    tb.log(run, "INFO", "4) big-mining-drill gibt es nicht (ohne Space Age): Großbohrer nicht prüfbar")
  end
  drill("Bohrer", "electric-mining-drill", 3, 3, {power = true, expect = WEIGHT.drill})
  -- Pumpe auf Rohöl, Ausgang nach Norden in einen Lagertank (Anschluss bei (1, −1), Tank 3 Kacheln nördlich).
  local pp = t18_pos(d, 4, 3)
  make(run, tb, s, {name = "crude-oil", position = pp, amount = 300000})
  power(run, tb, s, pp, force)
  local pump = make(run, tb, s, {name = "pumpjack", position = pp, force = force, direction = defines.direction.north, raise_built = true})
  make(run, tb, s, {name = "storage-tank", position = {x = pp.x, y = pp.y - 3}, force = force, direction = defines.direction.north})
  add("Pumpe", pump, WEIGHT.pumpjack)
  local ap = t18_pos(d, 5, 3)
  power(run, tb, s, ap, force)
  local assembler = make(run, tb, s, {name = "assembling-machine-1", position = ap, force = force, raise_built = true})
  if assembler then
    pcall(function() assembler.set_recipe("iron-gear-wheel") end)
    pcall(function() assembler.get_inventory(defines.inventory.crafter_input).insert{name = "iron-plate", count = 100} end)
  end
  add("Montagemaschine", assembler, WEIGHT.assembler)
  local fc = t18_cell(d, 6, 3)
  local furnace = make(run, tb, s, {name = "stone-furnace", position = {x = fc.x, y = fc.y}, force = force, raise_built = true})
  if furnace then
    tb.fuel(furnace, "coal", 10)
    pcall(function() furnace.get_inventory(defines.inventory.crafter_input).insert{name = "iron-ore", count = 50} end)
  end
  add("Steinofen", furnace, WEIGHT.furnace)
  drill("Bohrer ohne Strom", "electric-mining-drill", 1, 4, {expect = 0})
  drill("Bohrer auf Fels", "electric-mining-drill", 2, 4, {power = true, rock = true, expect = 0})
  drill("Bohrer, darunter Fels", "electric-mining-drill", 3, 4, {power = true, under = true, expect = WEIGHT.drill})
  if #s.missing > 0 then tb.log(run, "INFO", "4) nicht gebaut: " .. table.concat(s.missing, ", ") .. " (Einzelheiten in der Datei)") end
  return to_mid(120)
end

local function s4_read(run, tb, s, label)
  local parts = {}
  for _, entry in ipairs(s.src) do
    if valid(entry.entity) then
      entry.w_now = vibration_lib.weight_of(entry.entity)
      entry.st = status_name(entry.entity)
      entry.record = vibration_lib.source_of(entry.entity)
      table.insert(parts, entry.label .. " " .. entry.st)
    end
  end
  tb.log(run, "MESSUNG", "4) status " .. label .. ": " .. table.concat(parts, ", "))
end

function t18_steps.s4_first(run, tb, d, s)
  s.failed = {}
  s4_read(run, tb, s, "nach 120 Ticks Strom")
  for _, entry in ipairs(s.src) do
    if valid(entry.entity) then
      if entry.rock then
        check(s.failed, entry.record == nil, entry.label .. ": auf Fels eingetragen")
        check(s.failed, entry.w_now == 0, entry.label .. ": Gewicht " .. tostring(entry.w_now) .. " statt 0")
      else
        check(s.failed, entry.record ~= nil, entry.label .. ": nicht eingetragen")
        check(s.failed, entry.w_now == entry.expect, entry.label .. ": Gewicht " .. tostring(entry.w_now) .. " statt " .. entry.expect
          .. " (status " .. entry.st .. ")")
      end
    end
  end
  -- Kacheln wechseln (script_raised_set_tiles): Fels-Bohrer auf Sand, Sand-Bohrer auf Fels.
  local surface = tb.surface()
  for _, entry in ipairs(s.src) do
    if valid(entry.entity) and (entry.rock or entry.under) then
      local p = entry.entity.position
      local n, m = math.floor(p.x), math.floor(p.y)
      tiles(surface, n - 2, m - 2, n + 2, m + 2, entry.rock and SAND or ROCK, true)
    end
  end
  return 60
end

function t18_steps.s4_second(run, tb, d, s)
  local failed = s.failed
  s4_read(run, tb, s, "nach dem Kachelwechsel")
  local parts = {}
  for _, entry in ipairs(s.src) do
    if valid(entry.entity) then
      if entry.rock then
        check(failed, entry.record ~= nil, entry.label .. ": nach Kacheln zu Sand nicht eingetragen")
        check(failed, entry.w_now == WEIGHT.drill, entry.label .. ": nach Kacheln zu Sand Gewicht " .. tostring(entry.w_now) .. " statt 3")
      elseif entry.under then
        check(failed, entry.record ~= nil and entry.record.sand == false, entry.label .. ": sand nicht false")
        check(failed, entry.w_now == 0, entry.label .. ": Gewicht " .. tostring(entry.w_now) .. " statt 0")
      else
        check(failed, entry.w_now == entry.expect, entry.label .. ": Gewicht " .. tostring(entry.w_now) .. " statt " .. entry.expect)
      end
      table.insert(parts, entry.label .. " " .. tostring(entry.w_now))
    end
  end
  for _, label in ipairs(s.missing) do check(failed, false, label .. " nicht gebaut") end
  return verdict(run, tb, 4, "Feste Quellen [V13]", failed, table.concat(parts, ", "))
end

-- Schritt 5: Zerfall und Löschen.
function t18_steps.s5_wait(run, tb, d, s)
  return to_mid()
end

function t18_steps.s5_set(run, tb, d, s)
  local surface = tb.surface()
  s.a, s.b = t18_cell(d, 5, 4), t18_cell(d, 6, 4)
  s.keys = {[s.a.key] = true, [s.b.key] = true}
  vibration_lib.set_heat(surface, s.a.cx, s.a.cy, 1000)
  vibration_lib.set_heat(surface, s.b.cx, s.b.cy, 1.5)
  return 600
end

function t18_steps.s5_ten(run, tb, d, s)
  s.ten = vibration_lib.heat_entry(tb.surface(), s.a.key)
  return 600
end

function t18_steps.s5_twenty(run, tb, d, s)
  s.twenty = vibration_lib.heat_entry(tb.surface(), s.b.key)
  return 60
end

function t18_steps.s5_last(run, tb, d, s)
  local failed = {}
  local last = vibration_lib.heat_entry(tb.surface(), s.b.key)
  local expected = 1000 * DECAY ^ 10
  check(failed, near(s.ten, expected, 0.05), string.format("1000 nach 10 Takten %s statt %.2f ± 0,05", tb.num(s.ten, 3), expected))
  check(failed, s.twenty ~= nil, "1,5 nach 20 Takten schon gelöscht")
  check(failed, last == nil, "1,5 nach 21 Takten noch da (" .. tb.num(last, 4) .. ")")
  return verdict(run, tb, 5, "Zerfall und Löschen", failed, string.format("1000 → %s nach 10 Takten; 1,5 → %s nach 20, %s nach 21",
    tb.num(s.ten, 3), tb.num(s.twenty, 4), last == nil and "gelöscht" or tb.num(last, 4)))
end

-- Schritt 6: Nachbarschaft (sofort geprüft, danach wieder 0).
function t18_steps.s6_check(run, tb, d, s)
  local surface = tb.surface()
  local cy = d.bcy + T18_GRID[5]
  local failed, parts = {}, {}
  local function set(list, h)
    for _, cx in ipairs(list) do vibration_lib.set_heat(surface, cx, cy, h) end
  end
  local function sum(cx) return vibration_lib.sum3(surface.index, vibration_lib.chunk_key(cx, cy)) end
  local function nearby(cx) return vibration_lib.near_heat(surface, {x = cx * 32 + 16, y = cy * 32 + 16}) end
  local a = d.bcx - 8
  set({a, a + 1}, 500)
  check(failed, near(sum(a), 1000, 1e-6), "nebeneinander: sum3 am ersten " .. tb.num(sum(a)) .. " statt 1000")
  table.insert(parts, "nebeneinander " .. tb.num(sum(a)))
  set({a, a + 1}, 0)
  local b = d.bcx - 4
  set({b, b + 2}, 500)
  check(failed, near(sum(b + 1), 1000, 1e-6), "Abstand 2: sum3 in der Mitte " .. tb.num(sum(b + 1)) .. " statt 1000")
  check(failed, near(sum(b), 500, 1e-6) and near(sum(b + 2), 500, 1e-6),
    "Abstand 2: sum3 an den beiden " .. tb.num(sum(b)) .. "/" .. tb.num(sum(b + 2)) .. " statt 500")
  check(failed, near(nearby(b), 1000, 1e-6) and near(nearby(b + 2), 1000, 1e-6),
    "Abstand 2: near_heat " .. tb.num(nearby(b)) .. "/" .. tb.num(nearby(b + 2)) .. " statt 1000")
  table.insert(parts, string.format("Abstand 2: Mitte %s, Enden %s/%s, near_heat %s/%s", tb.num(sum(b + 1)), tb.num(sum(b)),
    tb.num(sum(b + 2)), tb.num(nearby(b)), tb.num(nearby(b + 2))))
  set({b, b + 2}, 0)
  local c = d.bcx + 1
  set({c, c + 3}, 500)
  local most = 0
  for cx = c - 1, c + 4 do most = math.max(most, sum(cx)) end
  check(failed, most <= 500 + 1e-6, "Abstand 3: sum3 bis " .. tb.num(most) .. " statt höchstens 500")
  table.insert(parts, "Abstand 3: höchstens " .. tb.num(most))
  set({c, c + 3}, 0)
  return verdict(run, tb, 6, "Nachbarschaft", failed, table.concat(parts, "; "))
end

-- Schritt 7: Erstbefüllung per scan (Auto und Montagemaschine ohne raise_built).
function t18_steps.s7_check(run, tb, d, s)
  local surface = tb.surface()
  local c = t18_cell(d, 6, 5)
  local car = make(run, tb, s, {name = "car", position = {x = c.x - 8, y = c.y + 0.5}, force = d.force, orientation = 0.25})
  local machine = make(run, tb, s, {name = "assembling-machine-1", position = {x = c.x + 6.5, y = c.y + 0.5}, force = d.force})
  if not (car and machine) then return fail(run, tb, 7, "Aufbau ging nicht (Einzelheiten in der Datei)") end
  keep_key(s, car.position)
  local failed = {}
  check(failed, vibration_lib.source_of(car) == nil, "Auto vor scan schon eingetragen")
  check(failed, vibration_lib.source_of(machine) == nil, "Montagemaschine vor scan schon eingetragen")
  local x0, y0 = c.cx * 32, c.cy * 32
  local n = vibration_lib.scan(surface, {{x0, y0}, {x0 + 32, y0 + 32}})
  check(failed, n >= 2, "scan meldet " .. tostring(n) .. " statt ≥ 2")
  check(failed, vibration_lib.source_of(car) ~= nil, "Auto nach scan nicht eingetragen")
  check(failed, vibration_lib.source_of(machine) ~= nil, "Montagemaschine nach scan nicht eingetragen")
  return verdict(run, tb, 7, "Erstbefüllung (scan)", failed, "scan: " .. tostring(n) .. " neu")
end

-- Schritte 8 und 9: Vorsichtsmodus. Lesen in jeder Takt-Mitte; Übergänge gegen W des Takts davor.
local function careful_new(run, tb, d, s, positions)
  s.cars = {}
  for _, position in ipairs(positions) do
    local car = new_harvester(run, tb, s, position, {force = d.force, coal = 30, field = 2000})
    if not car then return false end
    keep_key(s, position)
    local h = harvester.get(car)
    if not h then return false end
    vibration_lib.set_careful(h, true, nil)
    harvester.deploy(h)
    table.insert(s.cars, car)
  end
  s.reads, s.max_w, s.failed = 0, 0, {}
  return true
end

function t18_steps.s8_build(run, tb, d, s)
  if not careful_new(run, tb, d, s, {t18_pos(d, 1, 6)}) then return fail(run, tb, 8, "Aufbau ging nicht (Einzelheiten in der Datei)") end
  s.cycles, s.cycle = {}, {}
  return to_mid()
end

function t18_steps.s8_watch(run, tb, d, s)
  local car = s.cars[1]
  local failed = s.failed
  if not valid(car) then return fail(run, tb, 8, "Ernter weg") end
  local h = harvester.get(car)
  local W = vibration_lib.near_heat(car.surface, car.position)
  local state = h and h.state or "weg"
  local prev = s.prev
  local now = game.tick
  s.reads = s.reads + 1
  s.max_w = math.max(s.max_w, W)
  check(failed, W < WORMSIGN or s.over, "W " .. tb.num(W) .. " ≥ 1000")
  if W >= WORMSIGN then s.over = true end
  if worms_lib.hunt_of(car) and not s.sign then
    s.sign = true
    check(failed, false, "Wurmzeichen trotz Vorsichtsmodus")
  end
  if state == "deployed" then
    -- Ein Zyklus ist fertig, wenn nach Einpacken und Wiederaufbau wieder aufgebaut ist.
    local cycle = s.cycle
    if prev and prev.state == "deploying" then
      if cycle.deployed and cycle.pack and cycle.redeploy then
        local done = {harvest = cycle.pack - cycle.deployed, wait = cycle.redeploy - cycle.pack, deploy = now - cycle.redeploy}
        table.insert(s.cycles, done)
        local total = done.harvest + done.wait + done.deploy
        tb.log(run, "MESSUNG", string.format("8) Zyklus %d: Ernte %s s, Warten %s s, Aufbau %s s, Anteil %s %% (erwartet 16 / 36 / 5 s, 28 %%)",
          #s.cycles, tb.num(done.harvest / 60, 0), tb.num(done.wait / 60, 0), tb.num(done.deploy / 60, 0), tb.num(100 * done.harvest / total, 0)))
      end
      s.cycle = {deployed = now}
    end
    if W >= UNREST then check(failed, false, "aufgebaut mit W " .. tb.num(W) .. " ≥ 600 (kein Einpacken)") end
  elseif state == "packing" then
    if prev and prev.state == "deployed" then
      s.cycle.pack = now
      check(failed, W >= UNREST and prev.w < UNREST, string.format("Einpacken bei W %s (Takt davor %s) statt im ersten Takt mit W ≥ 600",
        tb.num(W), tb.num(prev.w)))
      check(failed, h.careful_packing == true, "Einpacken ohne careful_packing")
    end
    -- vib_weight gilt für den Takt davor: im Takt, der das Einpacken auslöst, trug der Ernter noch aufgebaut bei.
    local weight = vibration_lib.weight_of(car)
    local takes = prev and prev.state == "packing" and h.vib_weight or CAREFUL_PACKING
    if not s.pack_weight_bad and (weight ~= CAREFUL_PACKING or takes ~= CAREFUL_PACKING) then
      s.pack_weight_bad = true
      check(failed, false, "Gewicht beim Einpacken " .. tostring(weight) .. "/" .. tostring(h.vib_weight) .. " statt " .. CAREFUL_PACKING)
    end
  elseif state == "mobile" then
    if h.careful_wait and W < CAREFUL_LOW then check(failed, false, "wartet bei W " .. tb.num(W) .. " < 300") end
  elseif state == "deploying" and prev and prev.state == "mobile" then
    s.cycle.redeploy = now
    check(failed, W < CAREFUL_LOW and prev.w >= CAREFUL_LOW, string.format("Wiederaufbau bei W %s (Takt davor %s) statt im ersten Takt mit W < 300",
      tb.num(W), tb.num(prev.w)))
  end
  s.prev = {state = state, w = W}
  if #s.cycles >= 2 then
    return verdict(run, tb, 8, "Vorsichtsmodus, ein Ernter", failed, string.format("2 Zyklen, größtes W %s, kein Wurmzeichen", tb.num(s.max_w)))
  end
  if s.reads > 200 then
    check(failed, false, "nach " .. s.reads .. " Takten erst " .. #s.cycles .. " Zyklen")
    return verdict(run, tb, 8, "Vorsichtsmodus, ein Ernter", failed, "größtes W " .. tb.num(s.max_w))
  end
  return again(60)
end

function t18_steps.s9_build(run, tb, d, s)
  if not careful_new(run, tb, d, s, {t18_pos(d, 2, 6, 0, -4), t18_pos(d, 2, 6, 0, 4)}) then
    return fail(run, tb, 9, "Aufbau ging nicht (Einzelheiten in der Datei)")
  end
  return to_mid()
end

function t18_steps.s9_watch(run, tb, d, s)
  for _, car in ipairs(s.cars) do
    if not valid(car) then return fail(run, tb, 9, "Ernter weg") end
    s.max_w = math.max(s.max_w, vibration_lib.near_heat(car.surface, car.position))
    if worms_lib.hunt_of(car) then s.sign = true end
  end
  s.reads = s.reads + 1
  if s.reads < 120 then return again(60) end
  local failed = {}
  check(failed, s.max_w < WORMSIGN, "größtes W " .. tb.num(s.max_w) .. " ≥ 1000")
  check(failed, not s.sign, "Wurmzeichen trotz Vorsichtsmodus")
  tb.log(run, "MESSUNG", "9) größtes W mit zwei Erntern im selben Chunk: " .. tb.num(s.max_w) .. " (erwartet unter 660)")
  return verdict(run, tb, 9, "Vorsichtsmodus, zwei Ernter in einem Chunk", failed, "2 min, größtes W " .. tb.num(s.max_w))
end

-- Schritt 10: Abbruch beim Aufbauen; H10a wartet und baut wieder auf, H10b fährt weg und wartet nicht mehr.
function t18_steps.s10_build(run, tb, d, s)
  s.a = new_harvester(run, tb, s, t18_pos(d, 3, 6), {force = d.force, coal = 20, field = 1000})
  s.b = new_harvester(run, tb, s, t18_pos(d, 4, 6, -8, 0), {force = d.force, coal = 20, field = 1000, driver = true})
  if not (s.a and s.b) then return fail(run, tb, 10, "Aufbau ging nicht (Einzelheiten in der Datei)") end
  for _, car in ipairs({s.a, s.b}) do
    keep_key(s, car.position)
    vibration_lib.set_careful(harvester.get(car), true, nil)
  end
  return to_mid(30)
end

function t18_steps.s10_set(run, tb, d, s)
  local surface = tb.surface()
  s.failed = {}
  for _, car in ipairs({s.a, s.b}) do
    local cx, cy = vibration_lib.chunk_of_key(vibration_lib.key_of(car.position))
    vibration_lib.set_heat(surface, cx, cy, 700)
    check(s.failed, harvester.toggle(car, nil), "Aufbauen per toggle ging nicht")
  end
  s.set_tick = game.tick
  return 60
end

function t18_steps.s10_first(run, tb, d, s)
  for _, entry in ipairs({{"H10a", s.a}, {"H10b", s.b}}) do
    local label, car = entry[1], entry[2]
    local h = harvester.get(car)
    check(s.failed, h and h.state == "mobile" and h.careful_wait == true,
      label .. ": nach 60 Ticks " .. car_state(car) .. ", careful_wait " .. tostring(h and h.careful_wait))
  end
  s.b_start = copy_pos(s.b.position)
  return 1
end

function t18_steps.s10_run(run, tb, d, s)
  local failed = s.failed
  local now = game.tick
  if not (valid(s.a) and valid(s.b)) then return fail(run, tb, 10, "Ernter weg") end
  local ha, hb = harvester.get(s.a), harvester.get(s.b)
  -- H10b: 1 Kachel fahren.
  if not s.b_moved then
    local moved = tb.distance(s.b.position, s.b_start)
    gas(s.b, driver_of(s, s.b), moved < 1)
    if moved >= 1 then s.b_moved = now end
  elseif not s.b_cleared then
    gas(s.b, driver_of(s, s.b), false)
    if hb.careful_wait == nil then
      s.b_cleared = now
    elseif now > s.b_moved + 61 then
      s.b_cleared = now
      check(failed, false, "H10b: careful_wait nach 1 Kachel und 60 Ticks noch gesetzt")
    end
  end
  if now % 60 == 30 then
    local Wa = vibration_lib.near_heat(s.a.surface, s.a.position)
    local Wb = vibration_lib.near_heat(s.b.surface, s.b.position)
    if not s.a_done then
      if ha.state == "deploying" then
        s.a_done = true
        s.a_takes = math.floor((now - s.set_tick) / 60 + 0.5)
        check(failed, Wa < CAREFUL_LOW and (s.a_prev or 0) >= CAREFUL_LOW,
          string.format("H10a: Wiederaufbau bei W %s (Takt davor %s)", tb.num(Wa), tb.num(s.a_prev)))
        check(failed, ha.careful_wait == nil and ha.careful_pos == nil, "H10a: careful_wait oder careful_pos nach dem Wiederaufbau gesetzt")
        tb.log(run, "MESSUNG", "10) H10a baut " .. s.a_takes .. " Takte nach set_heat 700 wieder auf (erwartet etwa 42)")
      elseif ha.state ~= "mobile" or not ha.careful_wait then
        s.a_done = true
        check(failed, false, "H10a: " .. ha.state .. ", careful_wait " .. tostring(ha.careful_wait) .. " statt Warten")
      end
      s.a_prev = Wa
    end
    if not s.b_done then
      if not s.b_low and Wb < CAREFUL_LOW then s.b_low = now end
      if s.b_low and now >= s.b_low + 180 then
        s.b_done = true
        check(failed, hb.state == "mobile", "H10b: 3 Takte nach W < 300 " .. hb.state .. " statt mobil")
      end
    end
  end
  if s.a_done and s.b_done and s.b_cleared then
    return verdict(run, tb, 10, "Vorsichtsmodus: Abbruch und Weiterfahren", failed, string.format("H10a nach %s Takten wieder beim Aufbau, H10b fährt (careful_wait %s)",
      tostring(s.a_takes), tostring(hb.careful_wait)))
  end
  if now - s.set_tick > 70 * 60 then
    check(failed, false, "nach 70 s nicht fertig (H10a " .. tostring(s.a_done) .. ", H10b " .. tostring(s.b_done) .. ")")
    return verdict(run, tb, 10, "Vorsichtsmodus: Abbruch und Weiterfahren", failed, "abgebrochen")
  end
  return "poll"
end

-- Schritt 11: Prüfstand-Sperre (Force player ist nicht eingeschaltet).
function t18_steps.s11_build(run, tb, d, s)
  local player_force = game.forces.player
  if storage.vib.testbench[player_force.index] then
    tb.log(run, "INFO", "11) Force player ist für die Prüfstand-Fläche eingeschaltet (läuft T20?): Sperre nicht prüfbar")
    run.data.results[11] = "INFO"
    return "end"
  end
  s.car = new_harvester(run, tb, s, t18_pos(d, 5, 6), {force = player_force, coal = 10, field = 1000})
  if not s.car then return fail(run, tb, 11, "Aufbau ging nicht (Einzelheiten in der Datei)") end
  s.key = keep_key(s, s.car.position)
  harvester.deploy(harvester.get(s.car))
  s.start = game.tick
  return 1
end

function t18_steps.s11_wait(run, tb, d, s)
  if car_state(s.car) == "deployed" then return to_mid(180) end
  if game.tick - s.start > 600 then return fail(run, tb, 11, "Ernter baut nicht auf (" .. car_state(s.car) .. ")") end
  return "poll"
end

function t18_steps.s11_check(run, tb, d, s)
  local failed = {}
  local h = harvester.get(s.car)
  local entry = vibration_lib.heat_entry(tb.surface(), s.key)
  check(failed, entry == nil, "Wärme-Eintrag " .. tb.num(entry) .. " im Chunk")
  check(failed, h and h.vib_key == nil and h.vib_weight == 0, "vib_key " .. tostring(h and h.vib_key) .. ", vib_weight " .. tostring(h and h.vib_weight))
  return verdict(run, tb, 11, "Prüfstand-Sperre (Force player)", failed, "aufgebaut, nach 3 Takten kein Eintrag")
end

local T18_STEPS =
{
  {t18_steps.s1_check},
  {t18_steps.s2_build, t18_steps.s2_watch, t18_steps.s2_end},
  {t18_steps.s3_build, t18_steps.s3_run},
  {t18_steps.s4_build, t18_steps.s4_first, t18_steps.s4_second},
  {t18_steps.s5_wait, t18_steps.s5_set, t18_steps.s5_ten, t18_steps.s5_twenty, t18_steps.s5_last},
  {t18_steps.s6_check},
  {t18_steps.s7_check},
  {t18_steps.s8_build, t18_steps.s8_watch},
  {t18_steps.s9_build, t18_steps.s9_watch},
  {t18_steps.s10_build, t18_steps.s10_set, t18_steps.s10_first, t18_steps.s10_run},
  {t18_steps.s11_build, t18_steps.s11_wait, t18_steps.s11_check}
}

-- Gemeinsamer Start von T18 und T19: storage und Fläche prüfen, Force, Sicherungen, Fläche vorbereiten.
local function isolate_start(run, tb, force_name, half)
  local d = run.data
  local surface = tb.surface()
  if not storage_ready() then
    tb.log(run, "FEHLER", "storage des Laufzeitcodes fehlt (scripts/migrate.lua init, Schema 3)")
    tb.finish(run, "abgebrochen (kein storage)")
    return false
  end
  if not terrain.harvest_allowed(surface) then
    tb.log(run, "FEHLER", "terrain.harvest_allowed(" .. surface.name .. ") = false: der Laufzeitcode zählt hier nicht")
    tb.finish(run, "abgebrochen (Prüfstand-Fläche nicht erlaubt)")
    return false
  end
  d.origin = tb.area(run.id)
  d.box = box_of(d.origin, {x = half, y = half})
  d.bcx, d.bcy = math.floor(d.origin.x / 32), math.floor(d.origin.y / 32)
  local force = force_named(force_name)
  d.force = force
  d.saved = {grace = worms_lib.grace_snapshot(force), paused = storage.hunts.paused_until}
  abort_hunts({[force.index] = true})
  clear_area(surface, d.box)
  tb.prepare(d.origin, half)
  worms_lib.ensure_force()
  worms_lib.set_paused(nil)
  vibration_lib.testbench_enable(force)
  pcall(function() force.chart(surface, d.box) end)
  if tb.player(run) then tb.watch(run, nil, at(d.origin, 0, -20)) end
  return true
end

local function t18_start(run, tb)
  local d = run.data
  if not isolate_start(run, tb, T18_FORCE, T18_HALF) then return end
  worms_lib.set_grace(d.force, {awake = true, first_hunt_done = false}, {"first_hunt"})
  local others = foreign_regular({[d.force.index] = true})
  if others >= MAX_HUNTS then
    tb.log(run, "INFO", "Schon " .. others .. " reguläre Jagden anderer Forces (höchstens " .. MAX_HUNTS .. "): Schritt 2 bekommt kein Wurmzeichen")
  end
  lanes_init(d, #T18_STEPS, game.tick + 2)
  tb.log(run, "INFO", "Elf Schritte mit dem echten Vibrationscode (Force " .. T18_FORCE .. ", wach), parallel ab Tick 2, Dauer etwa 2 min"
    .. " Spielzeit. Je Schritt eine OK/FEHLER-Zeile, Einzelwerte in der Datei.")
end

local function t18_tick(run, tb)
  local d = run.data
  if not d.lanes or d.done_all then return end
  local open = false
  for number = 1, #T18_STEPS do
    lane_step(run, tb, d, T18_STEPS, number)
    if not d.lanes[number].done then open = true end
  end
  if not open then
    d.done_all = true
    tb.finish(run, summary(run, #T18_STEPS))
  end
end

local function t18_cleanup(run, tb)
  isolate_cleanup(run, tb, run.data, {run.data.force})
end

-- T19 Jagd: echter Code ----------------------------------------------------------------------------
-- Fläche ±300 Kacheln um x = 34 000 (keine Sektor-Ecke, Sektoren deshalb über vibration_lib.key_of). Ort (a, b, ci, cj):
-- Sektor a Spalten und b Zeilen neben dem Sektor des Ursprungs, darin Chunk (ci, cj). Belegung: 2 (−1, −1), 3 (−2, 0),
-- 4 (−1, 0), 5 elf Teile in elf Sektoren (Teil i in (−2, −1)), 6 Spalte 0, 7 (1, 1), 8 Felsstreifen bei Ursprung + 200
-- bis 240 (Spalten 1 und 2), 9 (−2, −1), 10 (−2, 1). Felsinseln bleiben nach einem Schritt liegen; spätere Schritte
-- meiden ihre Kacheln. Befehlsjagden setzen nichts zurück und lassen keinen Sektor ruhen, deshalb dürfen sich Teile von
-- Schritt 5 Sektoren mit späteren Schritten teilen.

local T19_HALF = 300
-- Countdown der Befehlsjagden in Schritt 5 (Sekunden); Teil f fliegt und hat 20 s.
local T19_SECONDS = 10
local T19_FLIGHT_SECONDS = 20

-- Kachelmitte im Ort (a, b, ci, cj); dx, dy vom Chunk-Anfang (Standard 16,5).
local function t19_place(d, a, b, ci, cj, dx, dy)
  return {x = (4 * (d.s0 + a) + ci) * 32 + (dx or 16.5), y = (4 * b + cj) * 32 + (dy or 16.5)}
end

-- Chunk einer Position und set_heat darauf.
local function heat_chunk(surface, position, h)
  local cx, cy = vibration_lib.chunk_of_key((vibration_lib.key_of(position)))
  vibration_lib.set_heat(surface, cx, cy, h)
end

-- Reguläre Jagden der eigenen Force.
local function own_regular(d)
  return hunt_list(function(hunt) return hunt.force_index == d.force.index and not hunt.debug end)
end

local function count_list(list)
  local n = 0
  for _ in pairs(list) do n = n + 1 end
  return n
end

-- Einstellung „Biss“ zurück, wenn der Test sie geschrieben hat (Schritt 3; sonst im cleanup).
local function restore_bite(d)
  local saved = d.saved
  if saved and saved.bite_written then
    pcall(function() settings.global[BITE_SETTING] = {value = saved.bite} end)
    saved.bite_written = nil
  end
end

-- Ernter der Force arrakis-t19, Chunk für das Aufräumen gemerkt.
local function t19_harvester(run, tb, d, s, position, opts)
  opts = opts or {}
  opts.force = opts.force or d.force
  local car = new_harvester(run, tb, s, position, opts)
  if car then keep_key(s, position) end
  return car
end

local function deploy(car)
  local h = valid(car) and harvester.get(car)
  if not h then return false, "kein Datensatz" end
  return harvester.deploy(h)
end

-- Phase: warten, bis alle Ernter in s.cars aufgebaut sind (höchstens 600 Ticks), dann bis zur Takt-Mitte.
local function wait_deployed(number)
  return function(run, tb, d, s)
    local states, all = {}, true
    for _, car in ipairs(s.cars) do
      local state = car_state(car)
      if state ~= "deployed" then all = false end
      table.insert(states, state)
    end
    if all then return to_mid() end
    s.deploy_wait = s.deploy_wait or game.tick
    if game.tick - s.deploy_wait > 600 then
      return fail(run, tb, number, "Ernter bauen nicht auf: " .. table.concat(states, ", "))
    end
    return "poll"
  end
end

-- Lebt die Entity des Eintrags und ist sie nicht gestorben?
local function alive(d, entity, un)
  return valid(entity) and not died(d, un)
end

local function result_text(ok, reason)
  return tostring(ok) .. "/" .. tostring(reason)
end

local t19_steps = {}

-- Schritt 1: Vorbedingung.
function t19_steps.s1_check(run, tb, d, s)
  local failed = {}
  d.foreign = foreign_regular({[d.force.index] = true})
  if d.foreign > 0 then
    tb.log(run, "INFO", "1) " .. d.foreign .. " reguläre Jagden anderer Forces laufen: Schritt 6 schreibt nur MESSUNG")
  end
  check(failed, worm_hostile(d.force), "Sandwurm-Force fehlt oder ist nicht feindlich zu " .. T19_FORCE)
  return verdict(run, tb, 1, "Vorbedingung", failed, d.foreign .. " reguläre Jagden anderer Forces, Sandwurm-Force feindlich")
end

-- Schritt 2: Lehrjagd mit Biss [V1, V14, V20]. Abstände zur Mitte C (Abstand zur Box wie beim Biss): Auto 2, Holzkiste
-- 2,65, Figur 3, Band 1,6, Eisenkiste (unzerstörbar) 2,3, Felskiste 3,75 (auf Fels), Steinmauer 4,7 (außerhalb).
function t19_steps.s2_build(run, tb, d, s)
  local surface = tb.surface()
  local force = d.force
  worms_lib.set_grace(force, {awake = true, first_hunt_done = false}, {"first_hunt"})
  local c = t19_place(d, -1, -1, 1, 1)
  s.c = c
  s.box = box_of(c, {x = 8, y = 8})
  s.car = t19_harvester(run, tb, d, s, c, {coal = 20, spice = 500, driver = true, field = 1000})
  if not s.car then return fail(run, tb, 2, "Aufbau ging nicht (Einzelheiten in der Datei)") end
  s.cars = {s.car}
  s.car_un = s.car.unit_number
  s.driver = driver_of(s, s.car)
  local n, m = math.floor(c.x), math.floor(c.y)
  -- Felsinsel 3×3 südwestlich der Mitte.
  tiles(surface, n - 4, m + 2, n - 2, m + 4, ROCK)
  s.dead, s.alive = {{label = "Ernter", entity = s.car, un = s.car_un}}, {}
  local function add(list, label, params)
    params.force = params.force or force
    local entity = make(run, tb, s, params)
    if entity then table.insert(list, {label = label, entity = entity, un = entity.unit_number}) end
    return entity
  end
  if valid(s.driver) then table.insert(s.dead, {label = "Fahrer", entity = s.driver, un = s.driver.unit_number, occupant = true}) end
  add(s.dead, "Auto", {name = "car", position = {x = c.x, y = c.y + 3}, orientation = 0})
  add(s.dead, "Holzkiste", {name = "wooden-chest", position = {x = c.x - 3, y = c.y}})
  add(s.dead, "Figur", {name = "character", position = {x = c.x + 3.2, y = c.y}})
  add(s.dead, "Band", {name = "transport-belt", position = {x = c.x, y = c.y - 2}, direction = defines.direction.east})
  local iron = add(s.alive, "Eisenkiste", {name = "iron-chest", position = {x = c.x + 2, y = c.y - 2}})
  if iron then iron.destructible = false end
  add(s.alive, "Mauer", {name = "stone-wall", position = {x = c.x, y = c.y - 5}})
  add(s.alive, "Felskiste", {name = "wooden-chest", position = {x = n - 2.5, y = m + 3.5}})
  local flyer = new_flyer(run, tb, s, c, {force = force, pilot = true})
  if flyer then
    table.insert(s.alive, {label = "Ornithopter", entity = flyer, un = flyer.unit_number})
    local pilot = read(function() return flyer.get_driver() end)
    if pilot and pilot.object_name == "LuaEntity" then table.insert(s.alive, {label = "Pilot", entity = pilot, un = pilot.unit_number}) end
  end
  if #s.dead < 6 or #s.alive < 5 then return fail(run, tb, 2, "Aufbau unvollständig (Einzelheiten in der Datei)") end
  s.health = {}
  for _, list in ipairs({s.dead, s.alive}) do
    for _, entry in ipairs(list) do s.health[entry.un] = entry.entity.health end
  end
  s.remnants0 = surface.count_entities_filtered{name = "tank-remnants", area = s.box}
  local ok, reason = deploy(s.car)
  if not ok then return fail(run, tb, 2, "Aufbauen ging nicht: " .. tostring(reason)) end
  return 1
end

function t19_steps.s2_set(run, tb, d, s)
  s.stats0 = copy(worms_lib.stats_of(d.force))
  s.mark = #(d.death_list or {})
  heat_chunk(tb.surface(), s.c, 999)
  s.set_tick = game.tick
  return 1
end

-- Wartet auf das Wurmzeichen nach set_heat 999 (im nächsten Takt); nil = weiter warten, false = keins gekommen.
local function sign_after_set(s, car)
  local hunt = worms_lib.hunt_of(car)
  if hunt then
    s.hunt = hunt
    return true
  end
  if game.tick > s.set_tick + 100 then return false end
  return nil
end

function t19_steps.s2_sign(run, tb, d, s)
  local found = sign_after_set(s, s.car)
  if found == nil then return "poll" end
  if not found then return fail(run, tb, 2, "kein Wurmzeichen nach set_heat 999 (" .. car_state(s.car) .. ")") end
  local hunt = s.hunt
  s.failed = {}
  check(s.failed, hunt.warn_tick == s.set_tick + 30, "Wurmzeichen bei Tick " .. hunt.warn_tick .. " statt im nächsten Takt " .. (s.set_tick + 30))
  check(s.failed, hunt.teaching == true and not hunt.debug, "keine Lehrjagd")
  check(s.failed, hunt.eta_tick - hunt.warn_tick == TEACH_TICKS, "Countdown " .. (hunt.eta_tick - hunt.warn_tick) .. " statt " .. TEACH_TICKS)
  s.ring, s.text = hunt.renders.ring, hunt.renders.text
  return math.max(1, hunt.eta_tick - 10 - game.tick)
end

-- Bei eta_tick − 10: nichts beschädigt, nichts gestorben; MESSUNG, ob die Suche den Fahrer im Ernter liefert.
function t19_steps.s2_before(run, tb, d, s)
  local failed = s.failed
  local surface = tb.surface()
  local changed = {}
  for _, list in ipairs({s.dead, s.alive}) do
    for _, entry in ipairs(list) do
      if not valid(entry.entity) then
        table.insert(changed, entry.label .. " weg")
      elseif entry.entity.health ~= s.health[entry.un] then
        table.insert(changed, entry.label .. " Gesundheit " .. tb.num(entry.entity.health))
      end
    end
  end
  check(failed, #changed == 0, "bis eta − 10: " .. table.concat(changed, ", "))
  local early = deaths_since(d, s.mark, s.box)
  check(failed, #early == 0, "vor dem Biss gestorben: " .. table.concat(early, ", "))
  local c = s.c
  local found = false
  for _, entity in pairs(surface.find_entities_filtered{area = {{c.x - BITE_RADIUS, c.y - BITE_RADIUS}, {c.x + BITE_RADIUS, c.y + BITE_RADIUS}},
      type = "character"}) do
    if valid(s.driver) and entity.unit_number == s.driver.unit_number then found = true end
  end
  tb.log(run, "MESSUNG", "2) find_entities_filtered (type character, Bissfläche) liefert den Fahrer im Ernter: " .. tostring(found) .. " [V14]")
  s.tag = s.hunt.tag
  s.mark = #(d.death_list or {})
  return 20
end

function t19_steps.s2_after(run, tb, d, s)
  local failed = s.failed
  local surface = tb.surface()
  local hunt = s.hunt
  local record = died(d, s.car_un)
  check(failed, record ~= nil, "Ernter nicht gestorben (" .. car_state(s.car) .. ")")
  if record then
    check(failed, record.tick == hunt.eta_tick, "Tod bei Tick " .. record.tick .. " statt " .. hunt.eta_tick)
    check(failed, record.force == WORM_FORCE, "entity_died mit Force " .. tostring(record.force) .. " statt " .. WORM_FORCE)
    check(failed, record.cause == nil, "entity_died mit cause " .. tostring(record.cause))
  end
  local dead, living = {}, {}
  for _, entry in ipairs(s.dead) do
    -- Der Fahrer stirbt nur mit, solange die Standardwahl „Insassen beim Totalverlust“ gilt (Plan 1).
    local expect = not entry.occupant or worms_lib.TOTAL_LOSS_OCCUPANTS
    local gone = died(d, entry.un) ~= nil
    check(failed, gone == expect, entry.label .. (expect and " lebt" or " gestorben"))
    if gone then table.insert(dead, entry.label) end
  end
  for _, entry in ipairs(s.alive) do
    local ok = alive(d, entry.entity, entry.un)
    check(failed, ok, entry.label .. " gestorben")
    if ok then table.insert(living, entry.label) end
  end
  local remnants = surface.count_entities_filtered{name = "tank-remnants", area = s.box}
  check(failed, remnants == s.remnants0 + 1, "tank-remnants " .. s.remnants0 .. " → " .. remnants .. " statt eine mehr")
  local items = surface.count_entities_filtered{type = "item-entity", position = s.c, radius = 6}
  check(failed, items == 0, items .. " Items am Boden im Radius 6")
  check(failed, nine_zero(surface, hunt.origin_key), "9 Chunks um den Ursprung nicht 0")
  local until_tick = vibration_lib.resting(surface.index, hunt.sector_key)
  local rest = until_tick and (until_tick - hunt.eta_tick)
  check(failed, rest ~= nil and rest >= REST_MIN and rest <= REST_MAX, "Ruhe " .. tostring(rest) .. " Ticks statt 7200 bis 14400")
  local stats = worms_lib.stats_of(d.force)
  check(failed, (stats.bitten or 0) == (s.stats0.bitten or 0) + 1, "bitten " .. tostring(s.stats0.bitten) .. " → " .. tostring(stats.bitten))
  local g = worms_lib.grace_snapshot(d.force) or {}
  check(failed, g.first_hunt_done == true and g.first_hunt == nil, "first_hunt_done " .. tostring(g.first_hunt_done) .. ", first_hunt " .. tostring(g.first_hunt))
  check(failed, storage.hunts.list[hunt.id] == nil, "Jagd nach dem Biss noch da")
  check(failed, not render_ok(s.ring) and not render_ok(s.text), "Ring oder Sekunden noch da")
  check(failed, not valid(s.tag), "Kartenmarkierung noch da")
  tb.log(run, "MESSUNG", "2) entity_died in Reihenfolge: " .. table.concat(deaths_since(d, s.mark), ", "))
  return verdict(run, tb, 2, "Lehrjagd mit Biss [V1, V14, V20]", failed, string.format("%s; gestorben: %s; am Leben: %s; Ruhe %s Ticks",
    hunt_text(tb, hunt), table.concat(dead, ", "), table.concat(living, ", "), tostring(rest)))
end

-- Schritt 3: Schwer beschädigt [V11, V19] (Befehlsjagd 2 s).
function t19_steps.s3_build(run, tb, d, s)
  local saved = d.saved
  if not saved.bite_written then saved.bite = read(function() return settings.global[BITE_SETTING].value end) end
  local ok = pcall(function() settings.global[BITE_SETTING] = {value = "heavy-damage"} end)
  if ok and read(function() return settings.global[BITE_SETTING].value end) == "heavy-damage" then
    saved.bite_written = true
    s.how = "Einstellung"
  else
    s.bite = "heavy-damage"
    s.how = "opts.bite"
    tb.log(run, "INFO", "3) Einstellung " .. BITE_SETTING .. " ließ sich nicht schreiben: Befehlsjagd mit opts.bite = \"heavy-damage\"")
  end
  local c = t19_place(d, -2, 0, 2, 1)
  s.c = c
  s.car = t19_harvester(run, tb, d, s, c, {coal = 10, spice = 500, driver = true, field = 1000})
  if not s.car then return fail(run, tb, 3, "Aufbau ging nicht (Einzelheiten in der Datei)") end
  s.cars = {s.car}
  s.car_un = s.car.unit_number
  s.driver = driver_of(s, s.car)
  local other = make(run, tb, s, {name = "car", position = {x = c.x, y = c.y + 2.5}, force = d.force, orientation = 0})
  if not other then return fail(run, tb, 3, "Auto ließ sich nicht bauen") end
  s.other_un = other.unit_number
  local deployed, reason = deploy(s.car)
  if not deployed then return fail(run, tb, 3, "Aufbauen ging nicht: " .. tostring(reason)) end
  return 1
end

function t19_steps.s3_start(run, tb, d, s)
  local surface = tb.surface()
  s.stats0 = copy(worms_lib.stats_of(d.force))
  local _, sector = vibration_lib.key_of(s.c)
  s.sector = sector
  s.rest0 = vibration_lib.resting(surface.index, sector)
  local hunt, reason = worms_lib.start_hunt(s.car, {seconds = 2, debug = true, bite = s.bite})
  if not hunt then return fail(run, tb, 3, "start_hunt: " .. tostring(reason)) end
  s.hunt = hunt
  return 1
end

function t19_steps.s3_watch(run, tb, d, s)
  local now = game.tick
  local hunt = s.hunt
  if now < hunt.eta_tick then
    s.fuel0 = fuel_items(s.car)
    return "poll"
  end
  if now < hunt.eta_tick + 10 then return "poll" end
  local failed = {}
  s.failed = failed
  local car = s.car
  if not alive(d, car, s.car_un) then
    check(failed, false, "H2 tot")
    restore_bite(d)
    return verdict(run, tb, 3, "Schwer beschädigt [V11, V19]", failed, hunt_text(tb, hunt))
  end
  local surface = tb.surface()
  local expected = math.max(1, HEAVY_SHARE * car.max_health)
  check(failed, near(car.health, expected, 0.5), "Gesundheit " .. tb.num(car.health) .. " statt " .. tb.num(expected) .. " ± 0,5")
  local trunk = car.get_inventory(defines.inventory.car_trunk)
  check(failed, trunk ~= nil and trunk.is_empty(), "Kofferraum nicht leer")
  -- Treibstoff gleich; zwischen der letzten Lesung und dem Biss kann der Brenner ein Stück nachgeladen haben.
  local fuel = fuel_items(car)
  check(failed, fuel > 0 and (fuel == s.fuel0 or fuel == s.fuel0 - 1), "Treibstoff " .. tostring(s.fuel0) .. " → " .. fuel)
  check(failed, car_state(car) == "mobile", "Zustand " .. car_state(car) .. " statt mobile")
  local driver = read(function() return car.get_driver() end)
  check(failed, valid(s.driver) and driver ~= nil and read(function() return driver.unit_number end) == s.driver.unit_number, "Fahrer sitzt nicht")
  check(failed, died(d, s.other_un) ~= nil, "Auto daneben lebt")
  check(failed, hunt.outcome == "bitten" and storage.hunts.list[hunt.id] == nil, "Ergebnis " .. tostring(hunt.outcome))
  check(failed, vibration_lib.resting(surface.index, s.sector) == s.rest0, "Ruhe geändert (Befehlsjagd)")
  check(failed, same(worms_lib.stats_of(d.force), s.stats0), "Statistik geändert (Befehlsjagd)")
  s.health = car.health
  s.from = copy_pos(car.position)
  s.drive_until = now + 60
  return 1
end

function t19_steps.s3_drive(run, tb, d, s)
  local car = s.car
  if not valid(car) then
    check(s.failed, false, "H2 beim Anfahren weg")
    restore_bite(d)
    return verdict(run, tb, 3, "Schwer beschädigt [V11, V19]", s.failed, "–")
  end
  if game.tick < s.drive_until then
    gas(car, s.driver, true)
    return "poll"
  end
  gas(car, s.driver, false)
  local moved = tb.distance(car.position, s.from)
  check(s.failed, moved >= 0.05, "fährt nicht an: " .. tb.num(moved, 3) .. " Kacheln in 1 s")
  restore_bite(d)
  return verdict(run, tb, 3, "Schwer beschädigt [V11, V19]", s.failed, string.format("über %s, Gesundheit %s, fährt %s Kacheln in 1 s",
    s.how, tb.num(s.health), tb.num(moved, 2)))
end

-- Schritt 4: Rettung per Ornithopter, danach Ruhe und ein neues Wurmzeichen wie in T18 Schritt 2.
function t19_steps.s4_build(run, tb, d, s)
  restore_bite(d)
  worms_lib.set_grace(d.force, {awake = true, first_hunt_done = true}, {"first_hunt"})
  local c = t19_place(d, -1, 0, 1, 1)
  s.c = c
  s.car = t19_harvester(run, tb, d, s, c, {coal = 40, field = 1000})
  if not s.car then return fail(run, tb, 4, "Aufbau ging nicht (Einzelheiten in der Datei)") end
  s.cars = {s.car}
  s.car_un = s.car.unit_number
  s.flyer = new_flyer(run, tb, s, c, {force = d.force, pilot = true, coal = 20})
  if not s.flyer then return fail(run, tb, 4, "Ornithopter ließ sich nicht bauen") end
  local ok, reason = deploy(s.car)
  if not ok then return fail(run, tb, 4, "Aufbauen ging nicht: " .. tostring(reason)) end
  return 1
end

function t19_steps.s4_set(run, tb, d, s)
  s.stats0 = copy(worms_lib.stats_of(d.force))
  s.failed = {}
  heat_chunk(tb.surface(), s.c, 999)
  s.set_tick = game.tick
  return 1
end

function t19_steps.s4_sign(run, tb, d, s)
  local found = sign_after_set(s, s.car)
  if found == nil then return "poll" end
  if not found then return fail(run, tb, 4, "kein Wurmzeichen nach set_heat 999 (" .. car_state(s.car) .. ")") end
  local hunt = s.hunt
  check(s.failed, hunt.warn_tick == s.set_tick + 30, "Wurmzeichen bei Tick " .. hunt.warn_tick .. " statt " .. (s.set_tick + 30))
  check(s.failed, not hunt.teaching and hunt.eta_tick - hunt.warn_tick == WARN_TICKS,
    "Countdown " .. (hunt.eta_tick - hunt.warn_tick) .. (hunt.teaching and " (Lehrjagd)" or "") .. " statt 3600")
  s.ring = hunt.renders.ring
  s.rescue = hunt
  return math.max(1, hunt.eta_tick - 720 - game.tick)
end

function t19_steps.s4_couple(run, tb, d, s)
  local ok, reason = flyer_lib.toggle_carry(s.flyer, s.car, nil)
  check(s.failed, ok == true and reason == "coupling", "toggle_carry bei eta − 720: " .. result_text(ok, reason))
  return math.max(1, s.rescue.eta_tick - 590 - game.tick)
end

function t19_steps.s4_carried(run, tb, d, s)
  local failed = s.failed
  local hunt = s.rescue
  check(failed, car_state(s.car) == "carried", "bei eta − 590 nicht getragen (" .. car_state(s.car) .. ")")
  check(failed, next(hunt.alerted) == nil, "Alarm-Merker nicht leer")
  check(failed, not render_ok(hunt.renders.ring) and not render_ok(s.ring), "Ring noch da")
  check(failed, hunt.hidden == true, "hidden nicht gesetzt")
  return math.max(1, hunt.eta_tick + 10 - game.tick)
end

function t19_steps.s4_zero(run, tb, d, s)
  local hunt = s.rescue
  check(s.failed, alive(d, s.car, s.car_un), "H3 gestorben")
  check(s.failed, hunt.outcome == "escaped" and hunt.state == "searching", "bei 0: " .. tostring(hunt.outcome) .. ", " .. tostring(hunt.state))
  tb.log(run, "MESSUNG", "4) Explosionen " .. ERUPTION .. " an last_pos " .. pos_text(tb, hunt.last_pos) .. ": "
    .. eruptions_at(tb.surface(), hunt.last_pos, 3))
  return math.max(1, hunt.eta_tick + SEARCH_TICKS + 10 - game.tick)
end

function t19_steps.s4_end(run, tb, d, s)
  local failed = s.failed
  local surface = tb.surface()
  local hunt = s.rescue
  check(failed, storage.hunts.list[hunt.id] == nil, "Jagd nach der Suche noch da")
  check(failed, nine_zero(surface, hunt.origin_key), "9 Chunks um den Ursprung nicht 0")
  check(failed, vibration_lib.resting(surface.index, hunt.sector_key) ~= nil, "Sektor ruht nicht")
  local stats = worms_lib.stats_of(d.force)
  check(failed, (stats.escaped or 0) == (s.stats0.escaped or 0) + 1, "escaped " .. tostring(s.stats0.escaped) .. " → " .. tostring(stats.escaped))
  check(failed, stats.first_escape_tick ~= nil, "first_escape_tick nicht gesetzt")
  local ok, reason = flyer_lib.toggle_carry(s.flyer, nil, nil)
  if not ok then
    check(failed, false, "Absetzen: " .. result_text(ok, reason))
    return verdict(run, tb, 4, "Rettung per Ornithopter", failed, hunt_text(tb, hunt))
  end
  s.drop_tick = game.tick
  return 10
end

function t19_steps.s4_redeploy(run, tb, d, s)
  local car = s.car
  if not valid(car) then return fail(run, tb, 4, "H3 nach dem Absetzen weg") end
  local h = harvester.get(car)
  if h and h.state == "mobile" then harvester.deploy(h) end
  if car_state(car) == "deployed" then
    check(s.failed, tb.distance(car.position, s.c) < 1.5, "abgesetzt bei " .. pos_text(tb, car.position) .. " statt an der alten Stelle")
    s.key = vibration_lib.key_of(car.position)
    s.quiet_reads = 0
    return to_mid()
  end
  if game.tick - s.drop_tick > 600 then return fail(run, tb, 4, "baut nach dem Absetzen nicht auf (" .. car_state(car) .. ")") end
  return "poll"
end

-- Fünf Takte Wärme 0 (Sektor ruht), dann rest(…, 60) und die Zeitlinie ab kaltem Sand.
function t19_steps.s4_quiet(run, tb, d, s)
  local surface = tb.surface()
  local value = heat_at(surface, s.key)
  s.quiet_reads = s.quiet_reads + 1
  check(s.failed, value == 0, "Wärme " .. tb.num(value) .. " im " .. s.quiet_reads .. ". Takt nach dem Aufbauen (Sektor ruht)")
  if s.quiet_reads < 5 then return again(60) end
  local _, sector = vibration_lib.key_of(s.car.position)
  vibration_lib.rest(surface.index, sector, 60)
  s.td, s.start, s.k, s.last = game.tick, game.tick, 0, value
  return 1
end

function t19_steps.s4_timeline(run, tb, d, s)
  if not valid(s.car) then return fail(run, tb, 4, "H3 weg") end
  s.hunt = nil
  if timeline(s, s.car, s.failed) ~= true then return "poll" end
  check_sign(s.failed, s, "nach der Ruhe: ", false)
  tb.trace(run, string.format("4) nach der Ruhe: Unruhe Takt %s (Tick %s), Wurmzeichen Takt %s (Tick %s, Wärme %s)", tostring(s.unrest_k),
    tostring(s.unrest_tick), tostring(s.sign_k), tostring(s.sign_tick), s.sign_heat and string.format("%.2f", s.sign_heat) or "–"))
  local hunt = s.hunt
  if hunt then worms_lib.end_hunt(hunt, nil, "quiet") end
  return verdict(run, tb, 4, "Rettung per Ornithopter", s.failed, string.format("%s; danach Unruhe Takt %s, Wurmzeichen Takt %s, %s",
    hunt_text(tb, s.rescue), tostring(s.unrest_k), tostring(s.sign_k), hunt_text(tb, hunt)))
end

-- Schritt 5: feste Regeln. Elf Teile, je in ihrem Sektor; alle Befehlsjagden beginnen im selben Tick T0 (s.t0). Je Teil
-- build (Aufbau), start (bei T0), tick (jeden Tick bis zur Prüfung) und check (Werte-Text, Fehler in p.failed,
-- p.level = "INFO" für eine Ausnahme). Jeder Teil schreibt eine Zeile 5a) bis 5k).
local T5_PARTS = {"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k"}
local T5_TITLES =
{
  a = "Fahrt auf eine Felsinsel", b = "auf Fels, eine Ecke im Sand", c = "Ziel weg (destroy)", d = "Teleport auf die Ablage",
  e = "Force-Wechsel", f = "angehoben und weiter abgesetzt", g = "10 Kacheln über Sand", h = "Montagemaschine mit Band",
  i = "angedockt [V15]", j = "Gründe und Spidertron [V22]", k = "Reichweite"
}
local t5_build, t5_start, t5_tick, t5_check = {}, {}, {}, {}

-- Befehlsjagd mit seconds (Standard 10 s) auf entity, gemerkt als p[key].
local function t5_hunt(p, key, entity, seconds)
  local hunt, reason = worms_lib.start_hunt(entity, {seconds = seconds or T19_SECONDS, debug = true})
  p[key] = hunt
  if not hunt then check(p.failed, false, key .. ": start_hunt " .. tostring(reason)) end
  return hunt
end

local function t5_outcome(p, hunt, expected, label)
  check(p.failed, hunt ~= nil and hunt.outcome == expected,
    (label or "Ziel") .. ": " .. tostring(hunt and hunt.outcome) .. " statt " .. expected)
end

local function t5_car(run, tb, d, s, position)
  local car = new_vehicle(run, tb, s, "car", position, {force = d.force, orientation = 0.25})
  if car then keep_key(s, position) end
  return car
end

-- a) Fährt vor 0 ganz auf eine Felsinsel 16 × 16 (4 Kacheln östlich): entkommen, safe "rock" binnen 10 Ticks, Ring grün.
function t5_build.a(run, tb, d, s, p)
  local c = t19_place(d, -1, -2, 1, 1)
  local n, m = math.floor(c.x), math.floor(c.y)
  tiles(tb.surface(), n + 4, m - 8, n + 19, m + 7, ROCK)
  p.car = t19_harvester(run, tb, d, s, c, {coal = 20, driver = true})
  p.box = box_of({x = c.x + 10, y = c.y}, {x = 16, y = 10})
  return p.car ~= nil
end

function t5_start.a(run, tb, d, s, p)
  t5_hunt(p, "hunt", p.car)
end

function t5_tick.a(run, tb, d, s, p, now)
  local car = p.car
  if not valid(car) then return end
  local driver = driver_of(s, car)
  if not p.rock_tick then
    if terrain.has_sand_under(car) then
      gas(car, driver, true)
    else
      p.rock_tick = now
      gas(car, driver, false)
    end
  else
    gas(car, driver, false)
    local hunt = p.hunt
    if hunt and not p.safe_tick and hunt.safe == "rock" then
      p.safe_tick = now
      p.green = is_green(hunt.renders.ring)
    end
  end
end

function t5_check.a(run, tb, d, s, p)
  local f, hunt = p.failed, p.hunt
  check(f, p.rock_tick ~= nil and p.rock_tick < hunt.eta_tick, "nicht vor 0 ganz auf Fels")
  check(f, p.rock_tick ~= nil and p.safe_tick ~= nil and p.safe_tick - p.rock_tick <= 10,
    "safe \"rock\" " .. (p.safe_tick and p.rock_tick and ((p.safe_tick - p.rock_tick) .. " Ticks nach dem Fels") or "nie"))
  check(f, p.green == true, "Ring nicht grün")
  t5_outcome(p, hunt, "escaped")
  local deaths = deaths_since(d, s.mark, p.box)
  check(f, #deaths == 0, "gestorben: " .. table.concat(deaths, ", "))
  return string.format("ganz auf Fels nach %s s, safe nach %s Ticks, Ergebnis %s",
    p.rock_tick and tb.num((p.rock_tick - s.t0) / 60) or "–", p.safe_tick and p.rock_tick and tostring(p.safe_tick - p.rock_tick) or "–",
    tostring(hunt.outcome))
end

-- b) Steht auf Fels, eine Ecke (Kachel südöstlich unter der Box) im Sand: gebissen.
function t5_build.b(run, tb, d, s, p)
  local surface = tb.surface()
  local c = t19_place(d, 0, -2, 1, 1)
  local n, m = math.floor(c.x), math.floor(c.y)
  tiles(surface, n - 4, m - 4, n + 4, m + 4, ROCK)
  tiles(surface, n + 1, m + 1, n + 1, m + 1, SAND)
  p.car = t19_harvester(run, tb, d, s, c, {coal = 5})
  if not p.car then return false end
  p.un = p.car.unit_number
  p.corner = terrain.has_sand_under(p.car)
  p.center_rock = tb.on_rock(surface, c)
  return true
end

function t5_start.b(run, tb, d, s, p)
  t5_hunt(p, "hunt", p.car)
end

function t5_check.b(run, tb, d, s, p)
  check(p.failed, p.corner == true and p.center_rock == true, "Aufbau: Ecke im Sand " .. tostring(p.corner) .. ", Mitte auf Fels " .. tostring(p.center_rock))
  t5_outcome(p, p.hunt, "bitten")
  check(p.failed, died(d, p.un) ~= nil, "Ernter lebt")
  return "Ecke im Sand, Ergebnis " .. tostring(p.hunt.outcome)
end

-- c) Ziel per destroy{raise_destroy = true} bei T0 + 60: lost, bei 0 gone; Kiste 2 Kacheln neben last_pos lebt.
function t5_build.c(run, tb, d, s, p)
  local c = t19_place(d, 1, -2, 1, 1)
  p.car = t19_harvester(run, tb, d, s, c, {coal = 5})
  p.chest = make(run, tb, s, {name = "wooden-chest", position = {x = c.x + 2, y = c.y}, force = d.force})
  return p.car ~= nil and p.chest ~= nil
end

function t5_start.c(run, tb, d, s, p)
  t5_hunt(p, "hunt", p.car)
end

function t5_tick.c(run, tb, d, s, p, now)
  if not p.destroyed and now >= s.t0 + 60 and valid(p.car) then
    p.car.destroy{raise_destroy = true}
    p.destroyed = now
    p.lost = p.hunt and p.hunt.lost
  end
end

function t5_check.c(run, tb, d, s, p)
  local hunt = p.hunt
  check(p.failed, p.lost == true, "nach destroy nicht lost")
  t5_outcome(p, hunt, "gone")
  check(p.failed, hunt.state == "searching", "Zustand " .. tostring(hunt.state) .. " statt searching")
  check(p.failed, valid(p.chest), "Kiste neben last_pos weg")
  local eruptions = eruptions_at(tb.surface(), hunt.last_pos, 3)
  tb.log(run, "MESSUNG", "5c) Explosionen an last_pos " .. pos_text(tb, hunt.last_pos) .. ": " .. eruptions)
  return "lost nach destroy, Ergebnis " .. tostring(hunt.outcome) .. ", Kiste lebt"
end

-- d) Auto 1 auf arrakis-test-hold (entkommen); Auto 2 hin und bei T0 + 300 zurück (gebissen).
function t5_build.d(run, tb, d, s, p)
  local c = t19_place(d, -1, -1, 1, 1)
  p.c2 = {x = c.x, y = c.y + 8}
  p.car1 = t5_car(run, tb, d, s, c)
  p.car2 = t5_car(run, tb, d, s, p.c2)
  if not (p.car1 and p.car2) then return false end
  p.un2 = p.car2.unit_number
  return true
end

function t5_start.d(run, tb, d, s, p)
  t5_hunt(p, "hunt1", p.car1)
  t5_hunt(p, "hunt2", p.car2)
end

function t5_tick.d(run, tb, d, s, p, now)
  if not p.away and now >= s.t0 + 60 then
    local hold = tb.hold_surface()
    p.away = {valid(p.car1) and p.car1.teleport({x = 60, y = 60}, hold), valid(p.car2) and p.car2.teleport({x = 60, y = 68}, hold)}
  elseif p.away and not p.back and now >= s.t0 + 300 then
    p.back = valid(p.car2) and p.car2.teleport(p.c2, tb.surface()) or false
  end
end

function t5_check.d(run, tb, d, s, p)
  check(p.failed, p.away ~= nil and p.away[1] == true and p.away[2] == true, "Teleport auf die Ablage ging nicht")
  check(p.failed, p.back == true, "Teleport zurück ging nicht")
  t5_outcome(p, p.hunt1, "escaped", "Auto 1 (Ablage)")
  t5_outcome(p, p.hunt2, "bitten", "Auto 2 (zurück)")
  check(p.failed, died(d, p.un2) ~= nil, "Auto 2 lebt")
  return "Auto 1 " .. tostring(p.hunt1.outcome) .. ", Auto 2 " .. tostring(p.hunt2.outcome)
end

-- e) Force des Ziels wechselt bei T0 + 60 auf arrakis-t19b: force_index neu, gebissen.
function t5_build.e(run, tb, d, s, p)
  p.other = force_named(T19_OTHER_FORCE)
  worms_lib.set_worm_off(p.other, true)
  worms_lib.ensure_force()
  p.car = t5_car(run, tb, d, s, t19_place(d, 0, -1, 1, 1))
  if not p.car then return false end
  p.un = p.car.unit_number
  return true
end

function t5_start.e(run, tb, d, s, p)
  t5_hunt(p, "hunt", p.car)
end

function t5_tick.e(run, tb, d, s, p, now)
  if not p.switched and now >= s.t0 + 60 and valid(p.car) then
    p.car.force = p.other
    p.switched = now
  elseif p.switched and not p.index_after and now >= p.switched + 20 then
    p.index_after = p.hunt and p.hunt.force_index
  end
end

function t5_check.e(run, tb, d, s, p)
  check(p.failed, valid(p.other) and p.index_after == p.other.index,
    "force_index nach dem Wechsel " .. tostring(p.index_after) .. " statt " .. tostring(valid(p.other) and p.other.index))
  t5_outcome(p, p.hunt, "bitten")
  check(p.failed, died(d, p.un) ~= nil, "Auto lebt")
  return "force_index " .. tostring(p.index_after) .. ", Ergebnis " .. tostring(p.hunt.outcome)
end

-- f) Angehoben (bei T0), per Autopilot 30 Kacheln weiter und auf Sand abgesetzt: gebissen dort, die Kiste an der alten
-- Stelle lebt. Eigene Befehlsjagd mit 20 s (reach 70); nicht vor 0 abgesetzt → INFO.
function t5_build.f(run, tb, d, s, p)
  local c = t19_place(d, 1, -1, 1, 1)
  p.c = c
  p.dest = {x = c.x + 30, y = c.y}
  keep_key(s, p.dest)
  p.car = t19_harvester(run, tb, d, s, c, {coal = 5})
  p.flyer = new_flyer(run, tb, s, c, {force = d.force, pilot = true, coal = 20})
  if not (p.car and p.flyer) then return false end
  p.un = p.car.unit_number
  return true
end

function t5_start.f(run, tb, d, s, p)
  t5_hunt(p, "hunt", p.car, T19_FLIGHT_SECONDS)
  p.couple = {flyer_lib.toggle_carry(p.flyer, p.car, nil)}
  if not p.couple[1] then check(p.failed, false, "toggle_carry " .. result_text(p.couple[1], p.couple[2])) end
end

function t5_tick.f(run, tb, d, s, p, now)
  local flyer = p.flyer
  if not valid(flyer) or p.dropped then return end
  if not p.lifted then
    if car_state(p.car) == "carried" then
      p.lifted = now
      p.chest = make(run, tb, s, {name = "wooden-chest", position = p.c, force = d.force})
      p.go = pcall(function() flyer.autopilot_destination = p.dest end)
    end
    return
  end
  local arrived = (d.arrived and d.arrived[flyer.unit_number] or 0) >= p.lifted or tb.distance(flyer.position, p.dest) < 1
  if arrived and (not p.retry or now >= p.retry) then
    local ok, reason = flyer_lib.toggle_carry(flyer, nil, nil)
    if ok then
      p.dropped = now
      p.drop_pos = valid(p.car) and copy_pos(p.car.position) or nil
    else
      p.drop_reason = reason
      p.retry = now + 30
    end
  end
end

function t5_check.f(run, tb, d, s, p)
  local hunt = p.hunt
  check(p.failed, p.go == true, "autopilot_destination ging nicht")
  if not p.dropped or p.dropped >= hunt.eta_tick then
    p.level = "INFO"
    return "nicht rechtzeitig abgesetzt (angehoben " .. (p.lifted and tb.num((p.lifted - s.t0) / 60) .. " s" or "nie")
      .. ", Absetzen " .. tostring(p.drop_reason or "–") .. "), Ergebnis " .. tostring(hunt.outcome)
  end
  t5_outcome(p, hunt, "bitten")
  local record = died(d, p.un)
  check(p.failed, record ~= nil, "Ernter lebt")
  local moved = record and tb.distance(record.position, p.c)
  check(p.failed, moved ~= nil and moved >= 25, "Biss " .. tb.num(moved) .. " Kacheln von der alten Stelle statt dort, wo er abgesetzt wurde")
  check(p.failed, valid(p.chest), "Kiste an der alten Stelle weg")
  return string.format("angehoben nach %s s, abgesetzt nach %s s bei %s, Biss %s Kacheln von der alten Stelle",
    tb.num((p.lifted - s.t0) / 60), tb.num((p.dropped - s.t0) / 60), pos_text(tb, p.drop_pos), tb.num(moved))
end

-- g) Fährt 10 Kacheln über Sand: gebissen an der neuen Stelle.
function t5_build.g(run, tb, d, s, p)
  local c = t19_place(d, -1, 0, 1, 1)
  keep_key(s, {x = c.x + 10, y = c.y})
  p.car = t19_harvester(run, tb, d, s, c, {coal = 20, driver = true})
  if not p.car then return false end
  p.un = p.car.unit_number
  return true
end

function t5_start.g(run, tb, d, s, p)
  t5_hunt(p, "hunt", p.car)
  p.from = copy_pos(p.car.position)
end

function t5_tick.g(run, tb, d, s, p, now)
  local car = p.car
  if not valid(car) then return end
  if p.stopped then
    gas(car, driver_of(s, car), false)
  elseif tb.distance(car.position, p.from) >= 10 then
    p.stopped = now
    gas(car, driver_of(s, car), false)
  else
    gas(car, driver_of(s, car), true)
  end
end

function t5_check.g(run, tb, d, s, p)
  t5_outcome(p, p.hunt, "bitten")
  local record = died(d, p.un)
  check(p.failed, record ~= nil, "Ernter lebt")
  local moved = record and tb.distance(record.position, p.hunt.warn_pos)
  check(p.failed, moved ~= nil and moved >= 5, "Biss " .. tb.num(moved) .. " Kacheln von warn_pos statt an der neuen Stelle")
  return "10 Kacheln nach " .. (p.stopped and tb.num((p.stopped - s.t0) / 60) .. " s" or "–") .. ", Biss " .. tb.num(moved) .. " Kacheln von warn_pos"
end

-- h) Montagemaschine mit Strom (Mast und Schnittstelle diagonal außerhalb des Bissradius), Band 2 Kacheln daneben.
function t5_build.h(run, tb, d, s, p)
  local c = t19_place(d, 0, 0, 1, 1)
  local n, m = math.floor(c.x), math.floor(c.y)
  make(run, tb, s, {name = "electric-energy-interface", position = {x = n - 6, y = m - 6}, force = d.force})
  make(run, tb, s, {name = "medium-electric-pole", position = {x = n - 3.5, y = m - 3.5}, force = d.force})
  p.machine = make(run, tb, s, {name = "assembling-machine-1", position = c, force = d.force, raise_built = true})
  p.belt = make(run, tb, s, {name = "transport-belt", position = {x = c.x + 2, y = c.y}, force = d.force, direction = defines.direction.north})
  if not (p.machine and p.belt) then return false end
  keep_key(s, c)
  pcall(function() p.machine.set_recipe("iron-gear-wheel") end)
  pcall(function() p.machine.get_inventory(defines.inventory.crafter_input).insert{name = "iron-plate", count = 100} end)
  p.un, p.belt_un = p.machine.unit_number, p.belt.unit_number
  return true
end

function t5_start.h(run, tb, d, s, p)
  p.state0 = status_name(p.machine)
  t5_hunt(p, "hunt", p.machine)
end

function t5_check.h(run, tb, d, s, p)
  t5_outcome(p, p.hunt, "bitten")
  check(p.failed, died(d, p.un) ~= nil, "Montagemaschine lebt")
  check(p.failed, died(d, p.belt_un) ~= nil, "Band lebt")
  return "status bei T0 " .. p.state0 .. ", Ergebnis " .. tostring(p.hunt.outcome)
end

-- i) Zwei angedockte Ernter (wie T18 Schritt 3): Ecke im Sand → gebissen; auf Fels 31 × 31 → entkommen.
local function t5_docked(run, tb, d, s, c, rock_half)
  local surface = tb.surface()
  local p0 = {x = c.x - 4, y = c.y}
  if rock_half then
    tiles(surface, p0.x - rock_half, p0.y - rock_half, p0.x + rock_half, p0.y + rock_half, ROCK)
  else
    tiles(surface, p0.x - 6, p0.y - 6, p0.x + 4, p0.y + 4, ROCK)
  end
  local intake_entity = make(run, tb, s, {name = INTAKE, position = p0, force = d.force, raise_built = true})
  local car = t19_harvester(run, tb, d, s, {x = p0.x + 3.9, y = p0.y}, {coal = 5})
  local record = valid(intake_entity) and intake.get(intake_entity)
  local h = car and harvester.get(car)
  local docked = record and not record.bad and h and harvester.dock(h, record) or false
  return car, docked == true, car and terrain.has_sand_under(car)
end

function t5_build.i(run, tb, d, s, p)
  p.car1, p.dock1, p.sand1 = t5_docked(run, tb, d, s, t19_place(d, -2, -1, 2, 0, 16, 16), nil)
  p.car2, p.dock2, p.sand2 = t5_docked(run, tb, d, s, t19_place(d, -2, -1, 3, 2, 16, 16), 15)
  if not (p.car1 and p.car2) then return false end
  p.un1 = p.car1.unit_number
  return true
end

function t5_start.i(run, tb, d, s, p)
  t5_hunt(p, "hunt1", p.car1)
  t5_hunt(p, "hunt2", p.car2)
end

function t5_check.i(run, tb, d, s, p)
  check(p.failed, p.dock1 and p.dock2, "Andocken ging nicht (" .. tostring(p.dock1) .. "/" .. tostring(p.dock2) .. ")")
  check(p.failed, p.sand1 == true and p.sand2 == false, "Aufbau: Sand unter " .. tostring(p.sand1) .. "/" .. tostring(p.sand2))
  t5_outcome(p, p.hunt1, "bitten", "Ecke im Sand")
  check(p.failed, died(d, p.un1) ~= nil, "Ernter mit Ecke im Sand lebt")
  t5_outcome(p, p.hunt2, "escaped", "auf Fels")
  return "Ecke im Sand " .. tostring(p.hunt1.outcome) .. ", auf Fels " .. tostring(p.hunt2.outcome)
end

-- j) Gründe: Ornithopter → "flyer", Baum → "no-target", zweite Jagd → "busy"; Spidertron auf Sand gebissen.
function t5_build.j(run, tb, d, s, p)
  local c = t19_place(d, -1, 1, 1, 1)
  p.spider = new_vehicle(run, tb, s, "spidertron", c, {force = d.force})
  p.flyer = new_flyer(run, tb, s, {x = c.x + 8, y = c.y}, {force = d.force})
  p.tree = make(run, tb, s, {name = "tree-01", position = {x = c.x - 8, y = c.y}})
  if not (p.spider and p.flyer and p.tree) then return false end
  keep_key(s, c)
  p.un = p.spider.unit_number
  return true
end

-- Gründe aus start_hunt; eine unerwartet gestartete Jagd endet sofort ("abort").
local function t5_reason(entity)
  local hunt, reason = worms_lib.start_hunt(entity, {seconds = T19_SECONDS, debug = true})
  if hunt then
    worms_lib.end_hunt(hunt, nil, "abort")
    return {"Jagd"}
  end
  return {reason}
end

function t5_start.j(run, tb, d, s, p)
  p.r_flyer = t5_reason(p.flyer)
  p.r_tree = t5_reason(p.tree)
  t5_hunt(p, "hunt", p.spider)
  local again_hunt, reason = worms_lib.start_hunt(p.spider, {seconds = T19_SECONDS, debug = true})
  p.r_busy = {again_hunt and "Jagd" or reason}
  if again_hunt then worms_lib.end_hunt(again_hunt, nil, "abort") end
  p.sand = terrain.has_sand_under(p.spider)
  tb.log(run, "MESSUNG", "5j) has_sand_under(Spidertron) " .. tostring(p.sand) .. " [V22]")
end

function t5_check.j(run, tb, d, s, p)
  check(p.failed, p.r_flyer[1] == "flyer", "Ornithopter: " .. tostring(p.r_flyer[1]) .. " statt flyer")
  check(p.failed, p.r_tree[1] == "no-target", "Baum: " .. tostring(p.r_tree[1]) .. " statt no-target")
  check(p.failed, p.r_busy[1] == "busy", "zweite Jagd: " .. tostring(p.r_busy[1]) .. " statt busy")
  t5_outcome(p, p.hunt, "bitten", "Spidertron")
  check(p.failed, died(d, p.un) ~= nil, "Spidertron lebt")
  return string.format("Gründe %s/%s/%s, Spidertron %s", tostring(p.r_flyer[1]), tostring(p.r_tree[1]), tostring(p.r_busy[1]), tostring(p.hunt.outcome))
end

-- k) Reichweite: reach = Wurmtempo · (eta_tick − warn_tick) / 60, bei 10 s also 35 (bis 35,5, weil eta_tick auf ein
-- Vielfaches von 10 aufgerundet ist). Auto 1 per teleport reach + 15 weiter (entkommen, Eruption an
-- warn_pos, safe "far" binnen 10 Ticks, Ring grün), Auto 2 reach − 5 weiter (gebissen dort).
function t5_build.k(run, tb, d, s, p)
  local c = t19_place(d, 0, 1, 0, 1)
  p.c1, p.c2 = c, {x = c.x, y = c.y + 8}
  p.car1 = t5_car(run, tb, d, s, p.c1)
  p.car2 = t5_car(run, tb, d, s, p.c2)
  if not (p.car1 and p.car2) then return false end
  p.un2 = p.car2.unit_number
  return true
end

function t5_start.k(run, tb, d, s, p)
  t5_hunt(p, "hunt1", p.car1)
  t5_hunt(p, "hunt2", p.car2)
  p.reach = p.hunt1 and p.hunt1.reach
end

function t5_tick.k(run, tb, d, s, p, now)
  if not p.moved and now >= s.t0 + 60 and p.reach then
    p.far = {x = p.c1.x + p.reach + 15, y = p.c1.y}
    p.near = {x = p.c2.x + p.reach - 5, y = p.c2.y}
    keep_key(s, p.far)
    keep_key(s, p.near)
    p.ok1 = valid(p.car1) and p.car1.teleport(p.far)
    p.ok2 = valid(p.car2) and p.car2.teleport(p.near)
    p.moved = now
  elseif p.moved and not p.far_tick and p.hunt1 and p.hunt1.safe == "far" then
    p.far_tick = now
    p.green = is_green(p.hunt1.renders.ring)
  end
end

function t5_check.k(run, tb, d, s, p)
  local hunt = p.hunt1
  local expected = hunt and worms_lib.WORM_SPEED * (hunt.eta_tick - hunt.warn_tick) / 60 or -1
  check(p.failed, near(p.reach, expected, 1e-6), "reach " .. tb.num(p.reach, 2) .. " statt " .. tb.num(expected, 2))
  local least = worms_lib.WORM_SPEED * T19_SECONDS
  check(p.failed, type(p.reach) == "number" and p.reach >= least - 1e-6 and p.reach < least + worms_lib.WORM_SPEED * 10 / 60,
    "reach " .. tb.num(p.reach, 2) .. " nicht in [" .. tb.num(least, 1) .. ", " .. tb.num(least + worms_lib.WORM_SPEED / 6, 2) .. ")")
  check(p.failed, p.ok1 == true and p.ok2 == true, "Teleport ging nicht")
  check(p.failed, p.far_tick ~= nil and p.far_tick - p.moved <= 10,
    "safe \"far\" " .. (p.far_tick and ((p.far_tick - p.moved) .. " Ticks nach dem Teleport") or "nie"))
  check(p.failed, p.green == true, "Ring nicht grün")
  t5_outcome(p, p.hunt1, "escaped", "Auto 1")
  local eruptions = eruptions_at(tb.surface(), p.hunt1.warn_pos, 3)
  tb.log(run, "MESSUNG", "5k) Explosionen an warn_pos " .. pos_text(tb, p.hunt1.warn_pos) .. ": " .. eruptions)
  t5_outcome(p, p.hunt2, "bitten", "Auto 2")
  local record = died(d, p.un2)
  check(p.failed, record ~= nil and p.near ~= nil and tb.distance(record.position, p.near) < 1, "Auto 2 nicht an der neuen Stelle gebissen")
  return string.format("reach %s, Auto 1 %s (safe nach %s Ticks), Auto 2 %s", tb.num(p.reach, 2), tostring(p.hunt1.outcome),
    p.far_tick and tostring(p.far_tick - p.moved) or "–", tostring(p.hunt2.outcome))
end

-- Prüfung und Zeile eines Teils.
local function t5_log(run, tb, d, s, p)
  p.logged = true
  local level, text
  if p.broken then
    level, text = "FEHLER", p.broken
  else
    local ok, values = pcall(t5_check[p.letter], run, tb, d, s, p)
    if not ok then
      level, text = "FEHLER", "Skriptfehler in der Prüfung: " .. tostring(values)
    elseif #p.failed > 0 then
      level, text = "FEHLER", values .. " | nicht erfüllt: " .. table.concat(p.failed, "; ")
    else
      level, text = p.level or "OK", values
    end
  end
  p.result = level
  tb.log(run, level, "5" .. p.letter .. ") " .. T5_TITLES[p.letter] .. ": " .. text)
end

function t19_steps.s5_build(run, tb, d, s)
  worms_lib.ensure_force()
  s.parts = {}
  s.mark = #(d.death_list or {})
  for _, letter in ipairs(T5_PARTS) do
    local p = {letter = letter, failed = {}}
    s.parts[letter] = p
    local ok, built = pcall(t5_build[letter], run, tb, d, s, p)
    if not ok then
      p.broken = "Skriptfehler im Aufbau: " .. tostring(built)
    elseif not built then
      p.broken = "Aufbau ging nicht (Einzelheiten in der Datei)"
    end
  end
  -- 150 Ticks für Strom (h) und Andocken (i).
  return 150
end

function t19_steps.s5_start(run, tb, d, s)
  s.t0 = game.tick
  s.mark = #(d.death_list or {})
  for _, letter in ipairs(T5_PARTS) do
    local p = s.parts[letter]
    if not p.broken then
      local ok, err = pcall(t5_start[letter], run, tb, d, s, p)
      if not ok then p.broken = "Skriptfehler beim Start: " .. tostring(err) end
    end
  end
  s.eta = math.ceil((s.t0 + 60 * T19_SECONDS) / 10) * 10
  s.eta_f = math.ceil((s.t0 + 60 * T19_FLIGHT_SECONDS) / 10) * 10
  return 1
end

function t19_steps.s5_run(run, tb, d, s)
  local now = game.tick
  for _, letter in ipairs(T5_PARTS) do
    local p = s.parts[letter]
    if not (p.broken or p.logged) and t5_tick[letter] then
      local ok, err = pcall(t5_tick[letter], run, tb, d, s, p, now)
      if not ok then p.broken = "Skriptfehler: " .. tostring(err) end
    end
  end
  for _, letter in ipairs(T5_PARTS) do
    local p = s.parts[letter]
    local due = (letter == "f" and s.eta_f or s.eta) + 10
    if not p.logged and (p.broken or now >= due) then t5_log(run, tb, d, s, p) end
  end
  -- Ende, wenn die letzte Suche vorbei ist; Reste mit "abort".
  if now < s.eta_f + SEARCH_TICKS + 10 then return "poll" end
  abort_hunts({[d.force.index] = true, [force_named(T19_OTHER_FORCE).index] = true})
  local level = "OK"
  for _, letter in ipairs(T5_PARTS) do
    local result = s.parts[letter].result
    if result == "FEHLER" then
      level = "FEHLER"
    elseif result ~= "OK" and level == "OK" then
      level = "INFO"
    end
  end
  d.results[5] = level
  return "end"
end

-- Schritt 6: Grenzen. L1 bis L4 in vier Sektoren der Spalte 0, L5 im Sektor von L1 (3 Chunks weiter).
local T6_PLACES = {{"L1", 0, -2, 0, 1}, {"L2", 0, -1, 1, 1}, {"L3", 0, 0, 1, 1}, {"L4", 0, 1, 1, 1}, {"L5", 0, -2, 3, 1}}

function t19_steps.s6_build(run, tb, d, s)
  worms_lib.set_grace(d.force, {awake = true, first_hunt_done = true}, {"first_hunt"})
  d.foreign = math.max(d.foreign or 0, foreign_regular({[d.force.index] = true}))
  s.cars, s.labels = {}, {}
  for i, place in ipairs(T6_PLACES) do
    local car = t19_harvester(run, tb, d, s, t19_place(d, place[2], place[3], place[4], place[5]), {coal = 20, field = 1000})
    if not car then return fail(run, tb, 6, place[1] .. " ließ sich nicht bauen") end
    s.cars[i], s.labels[i] = car, place[1]
    deploy(car)
  end
  local sectors = {}
  for i = 1, 5 do
    local _, sector = vibration_lib.key_of(s.cars[i].position)
    sectors[i] = sector
  end
  local distinct = sectors[1] ~= sectors[2] and sectors[1] ~= sectors[3] and sectors[1] ~= sectors[4] and sectors[2] ~= sectors[3]
    and sectors[2] ~= sectors[4] and sectors[3] ~= sectors[4]
  if not (distinct and sectors[5] == sectors[1]) then return fail(run, tb, 6, "Aufbau: Sektoren der Ernter nicht wie geplant") end
  return 1
end

function t19_steps.s6_set(run, tb, d, s)
  for _, car in ipairs(s.cars) do heat_chunk(tb.surface(), car.position, 999) end
  s.reads, s.counts, s.failed = 0, {}, {}
  return 60
end

-- In jeder Takt-Mitte: Zahl der Jagden; nach 5 Takten eine Jagd (nicht die von L1) "quiet" beenden.
function t19_steps.s6_watch(run, tb, d, s)
  local failed = s.failed
  s.reads = s.reads + 1
  local hunts = {}
  for i, car in ipairs(s.cars) do hunts[i] = worms_lib.hunt_of(car) end
  local own = own_regular(d)
  s.counts[s.reads] = #own
  local sectors = {}
  for _, hunt in ipairs(own) do
    if sectors[hunt.sector_key] and not s.double then
      s.double = true
      check(failed, false, "zwei Jagden im selben Sektor nach " .. s.reads .. " Takten")
    end
    sectors[hunt.sector_key] = true
  end
  if hunts[5] and not s.l5 then
    s.l5 = true
    check(failed, false, "L5 bekommt eine Jagd, obwohl in seinem Sektor eine läuft")
  end
  if s.reads <= 3 then
    check(failed, #own == s.reads, "nach " .. s.reads .. " Takten " .. #own .. " Jagden statt " .. s.reads)
  elseif s.reads == 5 then
    check(failed, #own == MAX_HUNTS, "nach 5 Takten " .. #own .. " Jagden statt 3")
    for i = 1, 4 do
      if not hunts[i] then s.free = s.free and -1 or i end
    end
    check(failed, s.free ~= nil and s.free > 0, "nach 5 Takten nicht genau ein Ernter ohne Jagd")
    for i = 2, 4 do
      if hunts[i] and not s.ended then
        s.ended = i
        worms_lib.end_hunt(hunts[i], nil, "quiet")
      end
    end
  elseif s.reads > 5 and s.free and s.free > 0 and hunts[s.free] and not s.free_take then
    s.free_take = s.reads - 5
  end
  if s.reads < 7 then return again(60) end
  check(failed, s.free_take ~= nil, "nach end_hunt bekommt " .. tostring(s.free and s.labels[s.free]) .. " binnen 2 Takten keine Jagd")
  local text = string.format("Jagden nach 1 bis 7 Takten: %s; beendet %s, dann %s nach %s Takten", table.concat(s.counts, ", "),
    tostring(s.ended and s.labels[s.ended]), tostring(s.free and s.free > 0 and s.labels[s.free]), tostring(s.free_take))
  abort_hunts({[d.force.index] = true})
  if d.foreign > 0 then
    tb.log(run, "MESSUNG", "6) Grenzen (andere Forces jagen mit, nur Messung): " .. text
      .. (#failed > 0 and (" | abweichend: " .. table.concat(failed, "; ")) or ""))
    d.results[6] = "MESSUNG"
    return "end"
  end
  return verdict(run, tb, 6, "Grenzen", failed, text)
end

-- Schritt 7: Schonfrist [V2].
function t19_steps.s7_build(run, tb, d, s)
  s.c = t19_place(d, 1, 1, 1, 1)
  s.car = t19_harvester(run, tb, d, s, s.c, {coal = 30, field = 1000})
  if not s.car then return fail(run, tb, 7, "Aufbau ging nicht (Einzelheiten in der Datei)") end
  s.cars = {s.car}
  deploy(s.car)
  return 1
end

function t19_steps.s7_research(run, tb, d, s)
  local force = d.force
  local tech = force.technologies[ORNITHOPTER_TECH]
  if not tech then return fail(run, tb, 7, "Forschung " .. ORNITHOPTER_TECH .. " fehlt") end
  s.failed = {}
  worms_lib.set_grace(force, {awake = false, first_hunt_done = false}, {"landed_tick", "ornithopter_tick", "active_from", "first_hunt"})
  d.research_event = nil
  tech.researched = false
  tech.researched = true
  s.research_tick = game.tick
  return 1
end

function t19_steps.s7_ornithopter(run, tb, d, s)
  local now = game.tick
  local g = worms_lib.grace_snapshot(d.force) or {}
  if not g.ornithopter_tick then
    if now - s.research_tick <= 60 then return "poll" end
    check(s.failed, false, "ornithopter_tick nach 60 Ticks nicht gesetzt")
    return verdict(run, tb, 7, "Schonfrist [V2]", s.failed, record_text(g))
  end
  local event = d.research_event
  local delay = g.ornithopter_tick - s.research_tick
  tb.log(run, "MESSUNG", "7) ornithopter_tick " .. (delay == 0 and "im selben Tick (Ereignis)" or (delay .. " Ticks später (Takt)"))
    .. "; on_research_finished " .. (event and ("bei Tick " .. event.tick .. ", by_script " .. tostring(event.by_script)) or "nicht gekommen") .. " [V2]")
  check(s.failed, delay <= 60, "ornithopter_tick " .. delay .. " Ticks nach der Forschung")
  check(s.failed, g.active_from == g.ornithopter_tick + GRACE_ORNITHOPTER,
    "active_from " .. tostring(g.active_from) .. " statt ornithopter_tick + 36000")
  local landed = now - 100000
  local g2 = worms_lib.set_grace(d.force, {landed_tick = landed}) or {}
  check(s.failed, g2.active_from == landed + GRACE_LANDING, "mit landed_tick: active_from " .. tostring(g2.active_from) .. " statt landed_tick + 108000")
  return to_mid()
end

function t19_steps.s7_heat(run, tb, d, s)
  heat_chunk(tb.surface(), s.c, 999)
  return 180
end

function t19_steps.s7_none(run, tb, d, s)
  check(s.failed, worms_lib.hunt_of(s.car) == nil, "Jagd vor dem Erwachen")
  local now = game.tick
  local g = worms_lib.set_grace(d.force, {landed_tick = now - GRACE_LANDING + 120}) or {}
  check(s.failed, g.active_from == now + 120, "active_from " .. tostring(g.active_from) .. " statt Tick + 120")
  s.wake_set = now
  return 1
end

function t19_steps.s7_awake(run, tb, d, s)
  local now = game.tick
  local g = worms_lib.grace_snapshot(d.force) or {}
  if g.awake and not s.awake_tick then
    s.awake_tick = now
    s.awake_take = now - now % 60
  end
  local hunt = worms_lib.hunt_of(s.car)
  if not hunt and now <= s.wake_set + 240 then return "poll" end
  local failed = s.failed
  check(failed, s.awake_take ~= nil and s.awake_take <= s.wake_set + 180, "nicht binnen 3 Takten wach (" .. tostring(s.awake_take) .. ")")
  check(failed, hunt ~= nil, "keine Jagd nach dem Erwachen")
  if hunt then
    check(failed, hunt.warn_tick == s.awake_take, "Lehrjagd bei Tick " .. hunt.warn_tick .. " statt im Takt des Erwachens " .. tostring(s.awake_take))
    check(failed, hunt.teaching == true and hunt.eta_tick - hunt.warn_tick == TEACH_TICKS,
      "Lehrjagd " .. tostring(hunt.teaching) .. ", Countdown " .. (hunt.eta_tick - hunt.warn_tick))
    worms_lib.end_hunt(hunt, nil, "quiet")
  end
  return verdict(run, tb, 7, "Schonfrist [V2]", failed, string.format("wach im Takt %s (%s Ticks nach dem Setzen), %s", tostring(s.awake_take),
    s.awake_take and tostring(s.awake_take - s.wake_set) or "–", hunt_text(tb, hunt)))
end

-- Schritt 8: Flucht per Fahrt auf einen Felsstreifen 40 × 300. E1 59, E2 und E3 100 Kacheln vor seinem Rand.
local T8_CARS = {{"E1", 140.5, -59.5}, {"E2", 100.5, 60.5}, {"E3", 100.5, -130.5}}

function t19_steps.s8_build(run, tb, d, s)
  local surface = tb.surface()
  worms_lib.set_grace(d.force, {awake = true, first_hunt_done = true}, {"first_hunt"})
  s.rock_x = d.origin.x + 200
  tiles(surface, s.rock_x, -150, s.rock_x + 39, 149, ROCK)
  s.cars, s.un = {}, {}
  for i, spec in ipairs(T8_CARS) do
    local car = t19_harvester(run, tb, d, s, {x = d.origin.x + spec[2], y = spec[3]}, {coal = 50, driver = true, field = 1000})
    if not car then return fail(run, tb, 8, spec[1] .. " ließ sich nicht bauen") end
    s.cars[i], s.un[i] = car, car.unit_number
    deploy(car)
  end
  local k1, sector1 = vibration_lib.key_of(s.cars[1].position)
  local k2, sector2 = vibration_lib.key_of(s.cars[2].position)
  local x1, y1 = vibration_lib.chunk_of_key(k1)
  local x2, y2 = vibration_lib.chunk_of_key(k2)
  if sector1 == sector2 or math.max(math.abs(x1 - x2), math.abs(y1 - y2)) < 3 then
    return fail(run, tb, 8, "Aufbau: E1 und E2 im selben Sektor oder weniger als 3 Chunks auseinander")
  end
  return 1
end

function t19_steps.s8_set(run, tb, d, s)
  local surface = tb.surface()
  heat_chunk(surface, s.cars[1].position, 999)
  heat_chunk(surface, s.cars[2].position, 999)
  s.set_tick = game.tick
  s.hunts, s.sign, s.packed, s.rock, s.failed = {}, {}, {}, {}, {}
  local hunt, reason = worms_lib.start_hunt(s.cars[3], {seconds = 90, debug = true})
  if not hunt then return fail(run, tb, 8, "Befehlsjagd auf E3: " .. tostring(reason)) end
  s.hunts[3], s.sign[3] = hunt, game.tick
  s.packed[3] = harvester.toggle(s.cars[3], nil)
  return 1
end

function t19_steps.s8_run(run, tb, d, s)
  local now = game.tick
  for i = 1, 3 do
    local car = s.cars[i]
    if valid(car) then
      local driver = driver_of(s, car)
      if not s.hunts[i] then
        local hunt = worms_lib.hunt_of(car)
        if hunt then
          s.hunts[i], s.sign[i] = hunt, now
          s.packed[i] = harvester.toggle(car, nil)
        end
      end
      if s.hunts[i] and not s.rock[i] then
        if car_state(car) == "mobile" then
          if terrain.has_sand_under(car) then
            gas(car, driver, true)
          else
            s.rock[i] = now
            gas(car, driver, false)
          end
        end
      elseif s.rock[i] then
        gas(car, driver, false)
      end
      if now % 60 == 0 then keep_key(s, car.position) end
      if i == 2 then s.e2_x = car.position.x end
    end
  end
  if not (s.hunts[1] and s.hunts[2]) and now > s.set_tick + 200 then
    return fail(run, tb, 8, "kein Wurmzeichen für E1 oder E2 (" .. tostring(s.hunts[1] ~= nil) .. "/" .. tostring(s.hunts[2] ~= nil) .. ")")
  end
  if now < s.hunts[3].eta_tick + 10 then return "poll" end
  local failed = s.failed
  local h1, h2, h3 = s.hunts[1], s.hunts[2], s.hunts[3]
  check(failed, s.packed[1] and s.packed[2], "Einpacken per toggle ging nicht (" .. tostring(s.packed[1]) .. "/" .. tostring(s.packed[2]) .. ")")
  check(failed, math.abs(h1.warn_tick - h2.warn_tick) == 60, "Wurmzeichen von E1 und E2 nicht in aufeinanderfolgenden Takten ("
    .. h1.warn_tick .. ", " .. h2.warn_tick .. ")")
  check(failed, h1.outcome == "escaped" and s.rock[1] ~= nil and s.rock[1] < h1.eta_tick, "E1: " .. tostring(h1.outcome) .. " statt entkommen")
  check(failed, h2.outcome == "bitten" and died(d, s.un[2]) ~= nil, "E2: " .. tostring(h2.outcome) .. " statt gebissen")
  local arrival = s.rock[1] and (s.rock[1] - s.sign[1]) / 60
  local left = s.e2_x and (s.rock_x - (s.e2_x + 1.3))
  tb.log(run, "MESSUNG", string.format("8) E1 ganz auf Fels %s s nach dem Wurmzeichen (erwartet etwa 53 s); E2 bei 0 noch %s Kacheln vor dem Fels (erwartet etwa 30)",
    tb.num(arrival), tb.num(left)))
  if h3.outcome == "escaped" and s.rock[3] and s.rock[3] < h3.eta_tick then
    tb.log(run, "INFO", "8) Lehrjagd-Ausnahme: E3 entkommt von 100 Kacheln (ganz auf Fels nach " .. tb.num((s.rock[3] - s.sign[3]) / 60) .. " s)")
  else
    tb.log(run, "INFO", "8) E3 entkommt nicht von 100 Kacheln in 90 s: " .. tostring(h3.outcome))
  end
  abort_hunts({[d.force.index] = true})
  return verdict(run, tb, 8, "Flucht per Fahrt", failed, string.format("E1 %s nach %s s, E2 %s, E3 %s", tostring(h1.outcome), tb.num(arrival),
    tostring(h2.outcome), tostring(h3.outcome)))
end

-- Schritt 9: Migration (nur was fehlt).
local function others_grace(d)
  local list = {}
  for _, force in pairs(game.forces) do
    if force.index ~= d.force.index then list[force.index] = {g = worms_lib.grace_snapshot(force)} end
  end
  return list
end

local function others_changed(before, after)
  local names = {}
  for index, entry in pairs(before) do
    if not (after[index] and same(entry.g, after[index].g)) then table.insert(names, tostring(index)) end
  end
  return names
end

function t19_steps.s9_check(run, tb, d, s)
  local force = d.force
  local surface = tb.surface()
  local failed = {}
  s.failed = failed
  local tech = force.technologies[ORNITHOPTER_TECH]
  if not tech then return fail(run, tb, 9, "Forschung " .. ORNITHOPTER_TECH .. " fehlt") end
  if not tech.researched then tech.researched = true end
  local c = t19_place(d, -2, -1, 2, 1)
  s.car = make(run, tb, s, {name = "car", position = c, force = force, orientation = 0.25})
  s.drill = make(run, tb, s, {name = "electric-mining-drill", position = {x = c.x + 8, y = c.y}, force = force})
  if not (s.car and s.drill) then return fail(run, tb, 9, "Aufbau ging nicht (Einzelheiten in der Datei)") end
  keep_key(s, c)
  check(failed, vibration_lib.source_of(s.car) == nil and vibration_lib.source_of(s.drill) == nil, "vor der Migration schon eingetragen")
  worms_lib.grace_restore(force, nil)
  local before = others_grace(d)
  local now = game.tick
  worms_lib.migrate_schema3{surfaces = {surface}, forces = {force}}
  local g = worms_lib.grace_snapshot(force) or {}
  check(failed, g.ornithopter_tick == now, "ornithopter_tick " .. tostring(g.ornithopter_tick) .. " statt " .. now)
  check(failed, g.active_from == now + GRACE_ORNITHOPTER, "active_from " .. tostring(g.active_from) .. " statt Tick + 36000")
  check(failed, vibration_lib.source_of(s.car) ~= nil, "Auto nicht eingetragen")
  check(failed, vibration_lib.source_of(s.drill) ~= nil, "Bohrer nicht eingetragen")
  local changed = others_changed(before, others_grace(d))
  check(failed, #changed == 0, "Schonfrist anderer Forces geändert: " .. table.concat(changed, ", "))
  s.g = g
  return 1
end

function t19_steps.s9_again(run, tb, d, s)
  local failed = s.failed
  local g0 = worms_lib.grace_snapshot(d.force)
  local sources = count_list(storage.vib.sources)
  local before = others_grace(d)
  worms_lib.migrate_schema3{surfaces = {tb.surface()}, forces = {d.force}}
  check(failed, same(worms_lib.grace_snapshot(d.force), g0), "zweiter Aufruf ändert die Schonfrist")
  check(failed, count_list(storage.vib.sources) == sources, "zweiter Aufruf trägt Quellen ein")
  local changed = others_changed(before, others_grace(d))
  check(failed, #changed == 0, "zweiter Aufruf ändert die Schonfrist anderer Forces: " .. table.concat(changed, ", "))
  return verdict(run, tb, 9, "Migration", failed, "Schonfrist " .. record_text(s.g) .. ", Auto und Bohrer eingetragen")
end

-- Schritt 10: Entfernen [V21] (immer zuletzt).
function t19_steps.s10_build(run, tb, d, s)
  worms_lib.set_grace(d.force, {awake = true, first_hunt_done = true}, {"first_hunt"})
  s.c = t19_place(d, -2, 1, 2, 1)
  s.car = t19_harvester(run, tb, d, s, s.c, {coal = 20, field = 1000})
  s.other = t5_car(run, tb, d, s, t19_place(d, -2, 1, 3, 2))
  if not (s.car and s.other) then return fail(run, tb, 10, "Aufbau ging nicht (Einzelheiten in der Datei)") end
  s.cars = {s.car}
  deploy(s.car)
  return 1
end

function t19_steps.s10_set(run, tb, d, s)
  heat_chunk(tb.surface(), s.c, 999)
  s.set_tick = game.tick
  return 1
end

function t19_steps.s10_sign(run, tb, d, s)
  local found = sign_after_set(s, s.car)
  if found == nil then return "poll" end
  if not found then return fail(run, tb, 10, "kein Wurmzeichen nach set_heat 999 (" .. car_state(s.car) .. ")") end
  local hunt, reason = worms_lib.start_hunt(s.other, {seconds = 60, debug = true})
  if not hunt then return fail(run, tb, 10, "Befehlsjagd: " .. tostring(reason)) end
  s.debug = hunt
  return to_mid(30)
end

function t19_steps.s10_uninstall(run, tb, d, s)
  local failed = {}
  s.failed = failed
  local before = count_list(storage.hunts.list)
  local marks = {}
  for _, hunt in ipairs({s.hunt, s.debug}) do
    table.insert(marks, hunt.renders.ring)
    table.insert(marks, hunt.renders.text)
  end
  local tags = {s.hunt.tag, s.debug.tag}
  local now = game.tick
  local n = worms_lib.uninstall()
  s.n = n
  if before ~= 2 then tb.log(run, "INFO", "10) " .. (before - 2) .. " weitere Jagden liefen mit (andere Forces)") end
  check(failed, n == before, "uninstall gibt " .. tostring(n) .. " statt " .. before)
  check(failed, next(storage.hunts.list) == nil, "Jagden nach uninstall noch da")
  for _, object in pairs(marks) do
    if render_ok(object) and not s.marks_bad then
      s.marks_bad = true
      check(failed, false, "Ring oder Sekunden nach uninstall noch gültig")
    end
  end
  for _, tag in pairs(tags) do
    if valid(tag) and not s.tags_bad then
      s.tags_bad = true
      check(failed, false, "Kartenmarkierung nach uninstall noch gültig")
    end
  end
  check(failed, storage.hunts.paused_until == now + PAUSE_TICKS, "paused_until " .. tostring(storage.hunts.paused_until) .. " statt Tick + 36000")
  heat_chunk(tb.surface(), s.c, 999)
  return 1
end

function t19_steps.s10_force(run, tb, d, s)
  check(s.failed, game.forces[WORM_FORCE] == nil, "Sandwurm-Force nach 1 Tick noch da")
  worms_lib.ensure_force()
  check(s.failed, worm_hostile(d.force) and worm_hostile(game.forces.player), "ensure_force: Sandwurm-Force fehlt oder nicht feindlich")
  return 180
end

function t19_steps.s10_none(run, tb, d, s)
  check(s.failed, next(storage.hunts.list) == nil, "Jagd trotz Pause (" .. count_list(storage.hunts.list) .. ")")
  return verdict(run, tb, 10, "Entfernen [V21]", s.failed, "uninstall " .. tostring(s.n) .. " Jagden, 3 Takte keine neue, Sandwurm-Force neu angelegt")
end

local T19_STEPS =
{
  {t19_steps.s1_check},
  {t19_steps.s2_build, wait_deployed(2), t19_steps.s2_set, t19_steps.s2_sign, t19_steps.s2_before, t19_steps.s2_after},
  {t19_steps.s3_build, wait_deployed(3), t19_steps.s3_start, t19_steps.s3_watch, t19_steps.s3_drive},
  {t19_steps.s4_build, wait_deployed(4), t19_steps.s4_set, t19_steps.s4_sign, t19_steps.s4_couple, t19_steps.s4_carried, t19_steps.s4_zero,
    t19_steps.s4_end, t19_steps.s4_redeploy, t19_steps.s4_quiet, t19_steps.s4_timeline},
  {t19_steps.s5_build, t19_steps.s5_start, t19_steps.s5_run},
  {t19_steps.s6_build, wait_deployed(6), t19_steps.s6_set, t19_steps.s6_watch},
  {t19_steps.s7_build, wait_deployed(7), t19_steps.s7_research, t19_steps.s7_ornithopter, t19_steps.s7_heat, t19_steps.s7_none, t19_steps.s7_awake},
  {t19_steps.s8_build, wait_deployed(8), t19_steps.s8_set, t19_steps.s8_run},
  {t19_steps.s9_check, t19_steps.s9_again},
  {t19_steps.s10_build, wait_deployed(10), t19_steps.s10_set, t19_steps.s10_sign, t19_steps.s10_uninstall, t19_steps.s10_force, t19_steps.s10_none}
}

local function t19_start(run, tb)
  local d = run.data
  if not isolate_start(run, tb, T19_FORCE, T19_HALF) then return end
  d.s0 = math.floor(math.floor(d.origin.x / 32) / 4)
  -- Statistik der Test-Force von vorn, damit first_escape_tick in Schritt 4 aus diesem Lauf stammt.
  local stats = worms_lib.stats_of(d.force)
  for key in pairs(stats) do stats[key] = nil end
  stats.bitten, stats.escaped, stats.gone, stats.killed = 0, 0, 0, 0
  -- Ohne Wurm wie 0.7.0 (docs/plan-3d2.md 6): Biss genau bei 0; den Wurm prüft T21.
  worms_lib.set_worm_off(d.force, true)
  worms_lib.set_grace(d.force, {awake = true, first_hunt_done = false}, {"first_hunt"})
  lanes_init(d, #T19_STEPS, game.tick + 2)
  d.step = 1
  tb.log(run, "INFO", "Zehn Schritte mit dem echten Wurmcode (Force " .. T19_FORCE .. ", wach) nacheinander, Dauer etwa 7 min Spielzeit."
    .. " Je Schritt eine OK/FEHLER-Zeile (Schritt 5 eine je Teil), Einzelwerte in der Datei.")
end

local function t19_tick(run, tb)
  local d = run.data
  if not d.lanes or d.done_all then return end
  local number = d.step
  lane_step(run, tb, d, T19_STEPS, number)
  if not d.lanes[number].done then return end
  if number >= #T19_STEPS then
    d.done_all = true
    tb.finish(run, summary(run, #T19_STEPS))
  else
    -- Was ein abgebrochener Schritt laufen ließ, stört den nächsten nicht (Lehrjagd-Merker, MAX_HUNTS).
    abort_hunts({[d.force.index] = true, [force_named(T19_OTHER_FORCE).index] = true})
    d.step = number + 1
    d.lanes[d.step].wait_until = game.tick + 10
  end
end

local function t19_on_event(run, tb, name, event)
  local d = run.data
  if not d.lanes then return end
  if name == "entity_died" then
    note_death(d, event)
  elseif name == "research_finished" then
    local research = event.research
    if valid(research) and research.name == ORNITHOPTER_TECH and valid(d.force) and research.force.index == d.force.index then
      d.research_event = {tick = event.tick, by_script = event.by_script == true}
    end
  elseif name == "spider_command_completed" then
    local vehicle = event.vehicle
    if valid(vehicle) and vehicle.unit_number then
      d.arrived = d.arrived or {}
      d.arrived[vehicle.unit_number] = event.tick
    end
  end
end

-- Aufräumen wie T18; dazu arrakis-t19b in arrakis-t19 verschmelzen (Schritt 5 e).
local function t19_cleanup(run, tb)
  local d = run.data
  local other = game.forces[T19_OTHER_FORCE]
  isolate_cleanup(run, tb, d, {d.force, other})
  if valid(d.force) then worms_lib.set_worm_off(d.force, false) end
  if other and other.valid then worms_lib.set_worm_off(other, false) end
  if other and valid(d.force) then pcall(game.merge_forces, other, d.force) end
end

-- T20 Würmer: Bedienung (interaktiv) ----------------------------------------------------------------
-- Mit Max im Spiel und seiner Force. ALT+O (Prüfstand-Taste) schaltet zum nächsten Schritt; Schritt 2 erst nach dem
-- Erwachen, nach Schritt 9 endet der Test. Gebaut wird neben Max (auf der Prüfstand-Fläche), der Ernter für den
-- Vorsichtsmodus 120 Kacheln östlich des Ursprungs, damit die Ruhe nach der Jagd aus Schritt 4 und 5 ihn nicht trifft.
-- Entities bleiben am Ende zum Ansehen stehen (wie T17); Wärme, Ruhe und Jagden der Force räumt cleanup.

local T20_HALF = 200
local T20_END_TICKS = 900 * 60
local T20_LAST = 9
local T20_NOT_REMOTE = {["arrakis-testbench"] = true, ["arrakis-test-hold"] = true, ["arrakis-hold"] = true}

-- Kachelmitte neben Max (dx, dy Kacheln), frei für name; ohne Max auf der Fläche: neben dem Ursprung.
local function t20_spot(run, tb, d, dx, dy, name)
  local surface = tb.surface()
  local player = tb.player(run)
  local base = d.origin
  if player and player.physical_surface.index == surface.index then base = player.physical_position end
  local want = {x = math.floor(base.x + dx) + 0.5, y = math.floor(base.y + dy) + 0.5}
  local spot = surface.find_non_colliding_position(name or HARVESTER, want, 12, 1, true) or want
  return {x = math.floor(spot.x) + 0.5, y = math.floor(spot.y) + 0.5}
end

local function gps_text(surface, position)
  return string.format("[gps=%d,%d,%s]", math.floor(position.x), math.floor(position.y), surface.name)
end

-- Ernter des Tests merken (Zustand und Vorsichtsmodus werden jeden Tick verglichen).
local function t20_remember(d, label, car)
  local h = harvester.get(car)
  table.insert(d.cars, {label = label, entity = car, un = car.unit_number, state = h and h.state, careful = h and h.careful == true})
  return car
end

local function t20_harvester(run, tb, d, label, position, opts)
  opts = opts or {}
  opts.force = d.force
  local car = new_harvester(run, tb, d.made, position, opts)
  if not car then
    tb.log(run, "FEHLER", label .. " ließ sich nicht bauen (Einzelheiten in der Datei)")
    return nil
  end
  return t20_remember(d, label, car)
end

local t20_enter = {}

-- 1) Schonfrist 1 min [V3, V18]. ornithopter_tick so, dass jede Neuberechnung (4.6) wieder Tick + 3600 ergibt.
t20_enter[1] = function(run, tb, d, player)
  local now = game.tick
  worms_lib.set_grace(d.force, {ornithopter_tick = now + 3600 - GRACE_ORNITHOPTER, active_from = now + 3600, awake = false,
    first_hunt_done = true}, {"announced", "first_hunt"})
  d.wake_tick = now + 3600
  -- Andere Oberfläche für die Fernsicht: nicht die Prüfstand-Fläche und keine der beiden Ablagen.
  local other = false
  for _, surface in pairs(game.surfaces) do
    if not T20_NOT_REMOTE[surface.name] then other = true end
  end
  tb.log(run, "FRAGE", "1) Steht oben links „Die Wüste regt sich in 1:00“ und zählt herunter? Kommt bei 0 im Chat „Die Wüste ist erwacht“? [V18]")
  if other then
    tb.log(run, "INFO", "1) Während der Minute: Karte öffnen (M) und eine andere Oberfläche wählen (Fernsicht) [V3]. Der Test schreibt jede"
      .. " Sekunde surface und physical_surface in die Datei.")
  else
    tb.log(run, "INFO", "1) Es gibt keine andere Oberfläche: Fernsicht [V3] hier nicht prüfbar")
  end
end

-- 2) Unruhe [V17]: Ernter neben Max, aufgebaut, Wärme 620 in jeder Takt-Mitte bis zum Ende von Schritt 3.
t20_enter[2] = function(run, tb, d, player)
  local position = t20_spot(run, tb, d, 8, 0)
  d.main = t20_harvester(run, tb, d, "Ernter 1", position, {coal = 50, field = 1000})
  if not d.main then return end
  deploy(d.main)
  d.hold620 = true
  tb.log(run, "FRAGE", "2) Siehst du Sandstaub, hörst du ein Rumpeln, und zeigen Fahrzeugfenster und Ernterfenster „Der Sand bebt“ bzw. die Wärme? [V17]")
end

-- 3) Vibrationsanzeige.
t20_enter[3] = function(run, tb, d, player)
  tb.log(run, "FRAGE", "3) Verknüpfung „Vibrationsanzeige“ klicken: Siehst du farbige Chunks mit Zahlen, der um den Ernter gelb? Noch einmal klicken: weg?")
end

-- 4) Wurmzeichen [V5, V8]: set_heat 999, Jagd im nächsten Takt (60 s); der Ornithopter für Schritt 5 steht schon.
t20_enter[4] = function(run, tb, d, player)
  d.hold620 = false
  if not valid(d.main) then
    tb.log(run, "FEHLER", "4) Ernter 1 fehlt")
    return
  end
  heat_chunk(tb.surface(), d.main.position, 999)
  d.flyer = new_flyer(run, tb, d.made, t20_spot(run, tb, d, -6, 4, FLYER), {force = d.force, coal = 20})
  tb.log(run, "FRAGE", "4) Je Zeichen ja/nein: Alarm unten rechts mit Wurmzeichen-Symbol, Kartenmarkierung, Warnton, roter Ring mit Sekunden,"
    .. " Zeile oben links, Status „Wurmzeichen! Biss in … s“? [V5, V8]")
  tb.log(run, "INFO", "4) Der Ornithopter für Schritt 5 steht neben dir. ALT+O für Schritt 5, solange der Countdown läuft.")
end

-- 5) Rettung [V16]; läuft keine Jagd mehr, startet der Test eine Befehlsjagd mit 60 s.
t20_enter[5] = function(run, tb, d, player)
  if valid(d.main) and not worms_lib.hunt_of(d.main) then
    local hunt = worms_lib.start_hunt(d.main, {seconds = 60, debug = true})
    tb.log(run, "INFO", "5) Die Jagd aus Schritt 4 ist vorbei: " .. (hunt and "Befehlsjagd mit 60 s auf Ernter 1" or "keine neue Jagd möglich"))
  end
  tb.log(run, "INFO", "5) In den Ornithopter steigen, über den Ernter fliegen, Umschalt+C.")
  tb.log(run, "FRAGE", "5) Verschwinden Alarm und Ring, steht oben links „wird getragen: erst nach … s auf Sand absetzen“, und kommt bei 0 eine"
    .. " Sandfontäne unter dir, ohne Schaden? [V16]")
end

-- 6) Biss ohne Rettung (Befehlsjagd 30 s, Kiste daneben) und Ernter am Rand einer Felsinsel (Befehlsjagd 60 s).
t20_enter[6] = function(run, tb, d, player)
  local surface = tb.surface()
  local position = t20_spot(run, tb, d, 8, 12)
  local car = t20_harvester(run, tb, d, "Ernter 2", position, {coal = 5})
  if car then
    make(run, tb, d.made, {name = "wooden-chest", position = {x = position.x, y = position.y + 2}, force = d.force})
    local hunt, reason = worms_lib.start_hunt(car, {seconds = 30, debug = true})
    if not hunt then tb.log(run, "FEHLER", "6) Befehlsjagd auf Ernter 2: " .. tostring(reason)) end
  end
  local corner = t20_spot(run, tb, d, 24, -4)
  local n, m = math.floor(corner.x), math.floor(corner.y)
  -- Felsinsel 11 × 10 Kacheln; unter der Box des Ernters (Kacheln n − 1 bis n + 1, m − 1 bis m + 1) ist nur die
  -- Nordwest-Ecke Sand.
  tiles(surface, n - 1, m - 1, n + 9, m + 8, ROCK, true)
  tiles(surface, n - 1, m - 1, n - 1, m - 1, SAND, true)
  local island = t20_harvester(run, tb, d, "Ernter 3", {x = n + 0.5, y = m + 0.5}, {coal = 20})
  if island then
    local hunt, reason = worms_lib.start_hunt(island, {seconds = 60, debug = true})
    if not hunt then tb.log(run, "FEHLER", "6) Befehlsjagd auf Ernter 3: " .. tostring(reason)) end
    tb.log(run, "MESSUNG", "6) Ernter 3 bei " .. gps_text(surface, island.position) .. ": Sand unter der Box " .. tostring(terrain.has_sand_under(island)))
  end
  tb.log(run, "FRAGE", "6) Kam die Eruption mit Ton genau bei 0, liegt das Wrack da, ist die Kiste weg?")
  tb.log(run, "INFO", "6) Ernter 3 steht am Rand der Felsinsel (Ecke im Sand): einsteigen und ganz auf den Fels fahren, dann zurück in den Sand.")
  tb.log(run, "FRAGE", "6) Wird der Ring grün und steht oben links „steht ganz auf Fels: sicher“, sobald er ganz auf Fels steht, und wieder rot,"
    .. " wenn du zurück in den Sand fährst?")
end

-- 7) Vorsichtsmodus: eigener Ernter 120 Kacheln östlich (anderer Sektor); sobald careful an ist, set_heat 580.
t20_enter[7] = function(run, tb, d, player)
  local position = {x = d.origin.x + 120.5, y = d.origin.y + 0.5}
  local car = t20_harvester(run, tb, d, "Ernter 4", position, {coal = 50, field = 1000})
  if not car then return end
  deploy(car)
  d.careful_car = car
  tb.watch(run, player, {x = position.x - 6, y = position.y + 3})
  tb.log(run, "INFO", "7) Der Test hat dich zu Ernter 4 gebracht " .. gps_text(tb.surface(), position) .. ". Fenster öffnen, Vorsichtsmodus"
    .. " einschalten; der Test setzt dann die Wärme auf 580.")
  tb.log(run, "FRAGE", "7) Packt der Ernter nach wenigen Sekunden selbst ein (im zweiten Takt), und baut er gut eine halbe Minute später"
    .. " (etwa 36 s nach dem Einpacken) wieder auf?")
end

-- 8) Tipps [V4].
t20_enter[8] = function(run, tb, d, player)
  tb.log(run, "FRAGE", "8) Stehen unter Tipps und Tricks (Space Age) die Einträge „Arrakis“ und „Wurmzeichen“? [V4]")
end

-- 9) Fahrzeug ohne raise_built [V12].
t20_enter[9] = function(run, tb, d, player)
  local position = t20_spot(run, tb, d, -5, 3, "car")
  d.raw_car = make(run, tb, d.made, {name = "car", position = position, force = d.force})
  if not d.raw_car then
    tb.log(run, "FEHLER", "9) Auto ließ sich nicht bauen")
    return
  end
  tb.fuel(d.raw_car, "coal", 10)
  tb.log(run, "MESSUNG", "9) Auto ohne raise_built: source_of " .. (vibration_lib.source_of(d.raw_car) and "eingetragen" or "nil"))
  tb.log(run, "INFO", "9) In das Auto neben dir steigen. Danach ALT+O beendet den Test.")
end

local function t20_next(run, tb, d)
  local player = tb.player(run)
  if d.step == 1 and not d.awake_tick then
    tb.log(run, "INFO", "1) Noch nicht erwacht (in " .. tb.num(math.max(0, (d.wake_tick or 0) - game.tick) / 60, 0) .. " s); ALT+O danach.")
    return
  end
  if d.step >= T20_LAST then
    d.done_all = true
    tb.finish(run, string.format("%d Schritte, %d Verknüpfungsklicks, %d Kontrollkästchen, %d Zustandswechsel", d.step, d.shortcuts, d.boxes, d.changes))
    return
  end
  d.step = d.step + 1
  tb.log(run, "INFO", "Schritt " .. d.step .. " von " .. T20_LAST)
  local ok, err = pcall(t20_enter[d.step], run, tb, d, player)
  if not ok then tb.log(run, "FEHLER", d.step .. ") Skriptfehler: " .. tostring(err)) end
end

local function t20_start(run, tb)
  local d = run.data
  local player = tb.player(run)
  if not player then
    tb.log(run, "FEHLER", "T20 braucht einen Spieler im Spiel")
    tb.finish(run, "abgebrochen (kein Spieler)")
    return
  end
  if not storage_ready() then
    tb.log(run, "FEHLER", "storage des Laufzeitcodes fehlt (scripts/migrate.lua init, Schema 3)")
    tb.finish(run, "abgebrochen (kein storage)")
    return
  end
  local surface = tb.surface()
  if not terrain.harvest_allowed(surface) then
    tb.log(run, "FEHLER", "terrain.harvest_allowed(" .. surface.name .. ") = false: der Laufzeitcode zählt hier nicht")
    tb.finish(run, "abgebrochen (Prüfstand-Fläche nicht erlaubt)")
    return
  end
  local force = player.force
  d.force = force
  d.origin = tb.area(run.id)
  d.box = box_of(d.origin, {x = T20_HALF, y = T20_HALF})
  d.saved = {grace = worms_lib.grace_snapshot(force), paused = storage.hunts.paused_until}
  d.stats = copy(worms_lib.stats_of(force))
  d.made = {made = new_made()}
  d.cars, d.hunts = {}, {}
  d.step, d.shortcuts, d.boxes, d.changes = 0, 0, 0, 0
  clear_area(surface, d.box)
  tb.prepare(d.origin, T20_HALF)
  worms_lib.ensure_force()
  worms_lib.set_paused(nil)
  -- Ohne Wurm wie 0.7.0 (docs/plan-3d2.md 6).
  worms_lib.set_worm_off(force, true)
  tb.log(run, "INFO", "T20 prüft die Warnungen ohne Wurm; den Wurm zeigt T22.")
  vibration_lib.testbench_enable(force)
  tb.protect(run, player)
  tb.watch(run, player, d.origin)
  tb.log(run, "INFO", "Während T20 vibrieren auch deine übrigen Bauten auf der Prüfstand-Fläche (Force " .. force.name .. ").")
  tb.log(run, "INFO", "Neun Schritte; ALT+O schaltet zum nächsten (Schritt 2 erst nach dem Erwachen, nach Schritt 9 endet der Test)."
    .. " Jeder Klick auf eine Verknüpfung und jedes Kontrollkästchen schreibt eine MESSUNG-Zeile, jeder Zustandswechsel eine INFO-Zeile."
    .. " Ende nach 15 min Spielzeit oder mit /arrakis-test stop. Bitte mit /arrakis-test tempo 1.")
  if game.speed ~= 1 then
    tb.log(run, "INFO", "Zeitraffer an (game.speed " .. string.format("%g", game.speed) .. "): die 15 min vergehen schneller; zurück mit /arrakis-test tempo 1")
  end
  d.step = 1
  tb.log(run, "INFO", "Schritt 1 von " .. T20_LAST)
  t20_enter[1](run, tb, d, player)
end

-- Zustandswechsel der Ernter und Jagden (INFO), Kontrollkästchen (MESSUNG).
local function t20_watch(run, tb, d)
  for _, entry in ipairs(d.cars) do
    local h = valid(entry.entity) and harvester.get(entry.entity)
    local state = h and h.state or "weg"
    if state ~= entry.state then
      d.changes = d.changes + 1
      tb.log(run, "INFO", string.format("Zustand: %s %s → %s", entry.label, tostring(entry.state), state))
      entry.state = state
    end
    local careful = h and h.careful == true or false
    if careful ~= entry.careful then
      d.boxes = d.boxes + 1
      entry.careful = careful
      tb.log(run, "MESSUNG", string.format("Kontrollkästchen Vorsichtsmodus an %s: %s (Zustand %s, W %s)", entry.label, careful and "an" or "aus",
        state, valid(entry.entity) and tb.num(vibration_lib.near_heat(entry.entity.surface, entry.entity.position)) or "–"))
      if careful and valid(d.careful_car) and entry.un == d.careful_car.unit_number and not d.careful_set then
        d.careful_set = game.tick
        heat_chunk(entry.entity.surface, entry.entity.position, 580)
        tb.log(run, "INFO", "7) Vorsichtsmodus an: Wärme auf 580 gesetzt")
      end
    end
  end
  local seen = {}
  for _, hunt in ipairs(hunt_list(function(hunt) return hunt.force_index == d.force.index end)) do
    seen[hunt.id] = true
    local key = hunt.state .. (hunt.safe and ("/" .. tostring(hunt.safe)) or "") .. (hunt.hidden and "/getragen" or "")
    if d.hunts[hunt.id] ~= key then
      d.changes = d.changes + 1
      tb.log(run, "INFO", (d.hunts[hunt.id] and "Jagd: " or "Jagd neu: ") .. hunt_text(tb, hunt) .. (hunt.hidden and ", getragen" or ""))
      d.hunts[hunt.id] = key
    end
  end
  for id in pairs(d.hunts) do
    if not seen[id] then
      d.changes = d.changes + 1
      tb.log(run, "INFO", "Jagd " .. id .. " zu Ende")
      d.hunts[id] = nil
    end
  end
end

local function t20_tick(run, tb)
  local d = run.data
  if not d.cars or d.done_all then return end
  local now = game.tick
  local player = tb.player(run)
  local g = worms_lib.grace_snapshot(d.force) or {}
  if d.step == 1 and not d.awake_tick then
    if now % 60 == 0 and player then
      tb.trace(run, "1) surface " .. tostring(read(function() return player.surface.name end)) .. ", physical_surface "
        .. tostring(read(function() return player.physical_surface.name end)))
    end
    if g.awake then
      d.awake_tick = now
      tb.log(run, "INFO", "1) Erwacht bei Tick " .. now .. " (Termin " .. tostring(d.wake_tick) .. "). Weiter mit ALT+O.")
    end
  end
  if d.hold620 and valid(d.main) and now % 60 == 30 then heat_chunk(d.main.surface, d.main.position, 620) end
  if d.car_check and now >= d.car_check then
    d.car_check = nil
    tb.log(run, "MESSUNG", "9) Nach dem Einsteigen: source_of " .. (valid(d.raw_car) and vibration_lib.source_of(d.raw_car) and "eingetragen (V12 hält)"
      or "nil (V12 hält nicht)"))
  end
  t20_watch(run, tb, d)
  if now - run.started >= T20_END_TICKS then
    d.done_all = true
    tb.finish(run, string.format("15 min um: Schritt %d, %d Verknüpfungsklicks, %d Kontrollkästchen, %d Zustandswechsel", d.step, d.shortcuts,
      d.boxes, d.changes))
  end
end

local function t20_on_event(run, tb, name, event)
  local d = run.data
  if not d.cars or d.done_all then return end
  if name == "test_key" then
    if event.player_index == run.player_index then t20_next(run, tb, d) end
  elseif name == "shortcut" then
    local player = event.player_index and game.get_player(event.player_index)
    if not player then return end
    d.shortcuts = d.shortcuts + 1
    local toggled = read(function() return player.is_shortcut_toggled(event.prototype_name) end)
    tb.log(run, "MESSUNG", string.format("Verknüpfung %s (%s): toggled %s, Vibrationsanzeige %s", tostring(event.prototype_name), player.name,
      tostring(toggled), storage.vib.overlay[player.index] and "an" or "aus"))
  elseif name == "driving_changed" then
    -- Erst im nächsten Tick lesen: Die Reihenfolge der Handler (Runner, scripts/vibration.lua) ist nicht zugesichert.
    if valid(d.raw_car) and valid(event.entity) and event.entity.unit_number == d.raw_car.unit_number then d.car_check = game.tick + 1 end
  end
end

-- Jagden der Force abbrechen, Wärme und Ruhe der Fläche löschen, Prüfstand-Merker, Schonfrist, Pause und Statistik
-- zurück (die Jagden aus Schritt 4 und 5 zählten sonst in Max' Force).
local function t20_cleanup(run, tb)
  local d = run.data
  local force = d.force
  if not valid(force) then return end
  pcall(abort_hunts, {[force.index] = true})
  if d.box then pcall(clear_area, tb.surface(), d.box) end
  worms_lib.set_worm_off(force, false)
  vibration_lib.testbench_disable(force)
  if d.saved then
    worms_lib.grace_restore(force, d.saved.grace)
    worms_lib.set_paused(d.saved.paused)
  end
  local stats = worms_lib.stats_of(force)
  for key in pairs(stats) do stats[key] = nil end
  for key, value in pairs(d.stats or {}) do stats[key] = value end
  worms_lib.ensure_force()
end

return
{
  T18 =
  {
    title = "Wärme: echter Code",
    timeout = 240 * 60,
    interactive = false,
    confirm = nil,
    start = t18_start,
    tick = t18_tick,
    cleanup = t18_cleanup
  },
  T19 =
  {
    title = "Jagd: echter Code",
    timeout = 540 * 60,
    interactive = false,
    confirm = nil,
    start = t19_start,
    tick = t19_tick,
    on_event = t19_on_event,
    cleanup = t19_cleanup
  },
  T20 =
  {
    title = "Würmer: Bedienung",
    timeout = 920 * 60,
    interactive = true,
    confirm = nil,
    start = t20_start,
    tick = t20_tick,
    on_event = t20_on_event,
    cleanup = t20_cleanup
  }
}
