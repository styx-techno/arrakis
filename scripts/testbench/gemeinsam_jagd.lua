-- Prüfstand: Vibration und Würmer mit echtem Laufzeitcode (Phase 3d1, docs/protokolle/plan-3d1.md 6; Vertrag siehe runner.lua).
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
local terrain = require("scripts.terrain")
local vibration_lib = require("scripts.vibration")
local worms_lib = require("scripts.worms")

local HARVESTER = "spice-harvester"
local FLYER = "arrakis-ornithopter"
local INTAKE = "arrakis-spice-intake"
local SPICE = "spice-sand"
local ROCK = "arrakis-rock"
local SAND = "sand-1"
local ERUPTION = "arrakis-worm-eruption"
local WORM_FORCE = "arrakis-sandworm"
local BITE_SETTING = "arrakis-worm-bite"

-- Sollwerte aus dem Plan --------------------------------------------------------------------------
local DECAY = 0.98
local HARVEST_WEIGHT = 30
local WARN_TICKS = 3600
-- Standardwahlen (Plan 1) aus den Modulen: 90 s Lehrjagd, Wiederaufbau unter 300, Einpacken mit Gewicht 0.
local TEACH_TICKS = worms_lib.TEACH_TICKS
local REST_MIN, REST_MAX = 7200, 14400
local MAX_HUNTS = 3
local GRACE_ORNITHOPTER = 36000
-- Unruhe und Wurmzeichen ab kaltem Sand mit Gewicht 30: H_k = 1500 · (1 − 0,98^k), H_26 = 612,9, H_55 = 1006,2.
local UNREST_TAKE = 26
local WORMSIGN_TAKE = 55
local HEAT_TOLERANCE = 0.01
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

local function render_ok(object)
  local ok, is_valid = pcall(function() return object ~= nil and object.valid end)
  return ok and is_valid == true
end

local function trunk_count(car, item)
  local inventory = valid(car) and car.get_inventory(defines.inventory.car_trunk)
  return inventory and inventory.get_item_count(item) or 0
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
  worms_lib.clear_lurk(s)
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

-- Echter Ornithopter mit Raketentreibstoff (ab 0.9.0 nur Flugtreibstoff, opts.rocket Stück); opts.pilot setzt eine
-- Puppe als Pilot.
local function new_flyer(run, tb, s, position, opts)
  opts = opts or {}
  local flyer = make(run, tb, s, {name = FLYER, position = position, force = opts.force, raise_built = true,
    create_build_effect_smoke = false}, "flyers")
  if not flyer then return nil end
  tb.fuel(flyer, "rocket-fuel", opts.rocket or 2)
  if opts.pilot then remember(s, tb.dummy_driver(flyer, opts.force)) end
  return flyer
end

local function driver_of(s, vehicle)
  return valid(vehicle) and s.drivers and s.drivers[vehicle.unit_number] or nil
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
  -- 0.11.0: Nach einer regulären Jagd lauert der Wurm im Sektor; der nächste Schritt baut dort neu.
  if surface then worms_lib.clear_lurk(surface.index) end
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

-- Chunk einer Position und set_heat darauf.
local function heat_chunk(surface, position, h)
  local cx, cy = vibration_lib.chunk_of_key((vibration_lib.key_of(position)))
  vibration_lib.set_heat(surface, cx, cy, h)
end

local function deploy(car)
  local h = valid(car) and harvester.get(car)
  if not h then return false, "kein Datensatz" end
  return harvester.deploy(h)
end

-- Für die Testdateien scripts/testbench/tests/ (eine je Test; aufgeteilt aus t_jagd.lua, Verhalten unverändert).
return
{
  harvester = harvester,
  intake = intake,
  terrain = terrain,
  vibration_lib = vibration_lib,
  worms_lib = worms_lib,
  HARVESTER = HARVESTER,
  FLYER = FLYER,
  INTAKE = INTAKE,
  SPICE = SPICE,
  ROCK = ROCK,
  SAND = SAND,
  ERUPTION = ERUPTION,
  WORM_FORCE = WORM_FORCE,
  BITE_SETTING = BITE_SETTING,
  DECAY = DECAY,
  HARVEST_WEIGHT = HARVEST_WEIGHT,
  WARN_TICKS = WARN_TICKS,
  TEACH_TICKS = TEACH_TICKS,
  REST_MIN = REST_MIN,
  REST_MAX = REST_MAX,
  MAX_HUNTS = MAX_HUNTS,
  GRACE_ORNITHOPTER = GRACE_ORNITHOPTER,
  UNREST_TAKE = UNREST_TAKE,
  WORMSIGN_TAKE = WORMSIGN_TAKE,
  HEAT_TOLERANCE = HEAT_TOLERANCE,
  CAR_COLOR = CAR_COLOR,
  valid = valid,
  copy_pos = copy_pos,
  at = at,
  pos_text = pos_text,
  read = read,
  check = check,
  near = near,
  copy = copy,
  to_mid = to_mid,
  quality_exists = quality_exists,
  box_of = box_of,
  inside = inside,
  overlaps = overlaps,
  tiles = tiles,
  place_spice = place_spice,
  carpet = carpet,
  gas = gas,
  render_ok = render_ok,
  trunk_count = trunk_count,
  car_state = car_state,
  status_name = status_name,
  storage_ready = storage_ready,
  force_named = force_named,
  heat_at = heat_at,
  zero_around = zero_around,
  nine_zero = nine_zero,
  clear_area = clear_area,
  hunt_list = hunt_list,
  abort_hunts = abort_hunts,
  foreign_regular = foreign_regular,
  worm_hostile = worm_hostile,
  hunt_text = hunt_text,
  new_made = new_made,
  make = make,
  remember = remember,
  new_harvester = new_harvester,
  new_vehicle = new_vehicle,
  new_flyer = new_flyer,
  driver_of = driver_of,
  tidy = tidy,
  keep_key = keep_key,
  again = again,
  verdict = verdict,
  fail = fail,
  lanes_init = lanes_init,
  lane_done = lane_done,
  lane_step = lane_step,
  summary = summary,
  isolate_cleanup = isolate_cleanup,
  timeline = timeline,
  check_sign = check_sign,
  isolate_start = isolate_start,
  heat_chunk = heat_chunk,
  deploy = deploy,
}
