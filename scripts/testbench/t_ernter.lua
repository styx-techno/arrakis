-- Prüfstand: Spice-Ernter mit echtem Laufzeitcode (Phase 3b, Plan 6; Vertrag siehe runner.lua).
--   T13: scripts/harvester.lua, scripts/intake.lua und scripts/migrate.lua auf der Prüfstand-Fläche
--        (terrain.harvest_allowed erlaubt sie mit der Startup-Einstellung). Zwölf Schritte, je eine
--        OK/FEHLER-Zeile mit Werten; Einzelwerte als MESSUNG nur in der Datei.
--   T2b: Fahrphysik des echten spice-harvester: Brennstoffe mit Ausgleich, Raketentreibstoff ohne
--        Ausgleich und Deckel, Richtungen, negative Koordinaten, voller Laderaum.
-- Ernter entstehen mit raise_built = true (script_raised_built trägt sie ein). Ausnahme: der Vergleichsernter
-- in T2b, der bewusst nie eingetragen wird (kein Ausgleich, kein Deckel).
-- Zustand nur in run.data (Zahlen, Texte, Positionen, LuaEntity-Referenzen; vor jeder Benutzung prüfen).
-- Die Abläufe stehen als Funktionslisten in diesem Modul, run.data hält nur Schritt- und Phasennummern.

local harvester = require("scripts.harvester")
local intake = require("scripts.intake")
local migrate = require("scripts.migrate")
local terrain = require("scripts.terrain")

local NAME = "spice-harvester"
local INTAKE = "arrakis-spice-intake"
local NOZZLE = "arrakis-fuel-nozzle"
local SPICE = "spice-sand"
local ROCK = "arrakis-rock"

-- Sollwerte aus dem Plan (4.3 bis 4.5), bewusst nicht aus scripts/harvester.lua gelesen.
local RATE = 5                -- Spice-Sand je Sekunde ohne Produktivität
local DRAIN = 0.5             -- Feldabzug je Spice-Sand
local POWER = 400000          -- Treibstoff beim Ernten (W)
local DEPLOY_TICKS = 5 * 60
local PACK_TICKS = 10 * 60
local CAP = 1.5               -- Tempo-Deckel (Kacheln/s)
local RESET = 1.45            -- Rücksetzwert des Deckels (Kacheln/s)
local FIELD_TILES = 13 * 13

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

local function mj(joules)
  if type(joules) ~= "number" then return "–" end
  return string.format("%.2f MJ", joules / 1000000)
end

-- Zustand des Datensatzes in storage.harvesters (scripts/harvester.lua) oder "–".
local function state_of(car)
  local h = valid(car) and harvester.get(car)
  return h and h.state or "–"
end

local function flags_text(car)
  if not valid(car) then return "Ernter weg" end
  return string.format("Zustand %s, disabled_by_script %s, minable_flag %s", state_of(car),
    tostring(read(function() return car.disabled_by_script end)), tostring(read(function() return car.minable_flag end)))
end

local function trunk_count(car)
  local inventory = car.get_inventory(defines.inventory.car_trunk)
  return inventory and inventory.get_item_count(SPICE) or 0
end

local function fuel_count(car, item)
  local inventory = car.get_fuel_inventory()
  return inventory and inventory.get_item_count(item) or 0
end

-- Brennwert im Ernter (J): Rest des brennenden Items, Items im Treibstoffinventar, Puffer.
local function fuel_energy(car)
  local burner = car.burner
  if not burner then return 0 end
  local total = burner.heat
  if burner.currently_burning then total = total + burner.remaining_burning_fuel end
  local inventory = burner.inventory
  for i = 1, #inventory do
    local stack = inventory[i]
    if stack.valid_for_read then total = total + stack.count * stack.prototype.fuel_value end
  end
  return total
end

-- Spice-Sand auf jeder Kachel x1..x2 × y1..y2 (Kachelnummern, beide Grenzen eingeschlossen).
local function place_spice(surface, x1, y1, x2, y2, amount)
  local placed = 0
  for x = x1, x2 do
    for y = y1, y2 do
      if surface.create_entity{name = SPICE, position = {x + 0.5, y + 0.5}, amount = amount} then placed = placed + 1 end
    end
  end
  return placed
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

local function spice_input(force, surface)
  return force.get_item_production_statistics(surface).get_input_count(SPICE)
end

local function fuel_output(force, surface, item)
  return force.get_item_production_statistics(surface).get_output_count(item)
end

-- Ticks bis zur nächsten Mitte zwischen zwei Abbautakten (tick % 30 == 15), mindestens 1.
-- So hängt kein Ergebnis davon ab, ob on_nth_tick(30) vor oder nach dem Prüfstand-Tick läuft.
local function to_mid_cycle(extra)
  local tick = game.tick + (extra or 0)
  local n = (15 - tick % 30) % 30
  if n == 0 and not extra then n = 30 end
  return (extra or 0) + n
end

-- Gas geben oder loslassen: riding_state am Fahrzeug und am Dummy-Fahrer (wie T2).
local function gas(car, driver, on)
  local state =
  {
    acceleration = on and defines.riding.acceleration.accelerating or defines.riding.acceleration.nothing,
    direction = defines.riding.direction.straight
  }
  pcall(function() car.riding_state = state end)
  if valid(driver) then pcall(function() driver.riding_state = state end) end
end

local function quality_exists(name)
  local ok, exists = pcall(function() return prototypes.quality[name] ~= nil end)
  return ok and exists
end

-- Erzeugt eine Entity auf der Prüfstand-Fläche (oder surface); nil, wenn es nicht ging (Grund in der Datei).
local function create(run, tb, params, surface)
  local ok, entity = pcall(function() return (surface or tb.surface()).create_entity(params) end)
  if ok and entity then return entity end
  tb.trace(run, params.name .. " bei " .. pos_text(tb, params.position) .. " ging nicht" .. (ok and "" or (": " .. tostring(entity))))
  return nil
end

-- Greifarm von from nach to: die Richtung, bei der Aufnahme bei from und Ablage bei to liegt (wie T4).
local function inserter_between(run, tb, position, from, to)
  local directions = {defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west}
  for _, direction in ipairs(directions) do
    local inserter = create(run, tb, {name = "inserter", position = position, direction = direction, force = from.force})
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

-- T13 Ernter: echter Code ------------------------------------------------------------------------
-- Ablauf: zwölf Schritte (Plan 6), je Schritt eine Liste von Phasen. Eine Phase gibt zurück:
--   "poll" = nächsten Tick dieselbe Phase, Zahl n = nächste Phase in n Ticks, "end" = Schritt fertig.
-- Jeder Schritt schreibt genau eine OK/FEHLER-Zeile (verdict oder fail).

local T13_HALF = 130
local T13_GAP = 10
-- Orte relativ zum Testbereich (ganze Zahlen).
local T13_PLACES =
{
  s1 = {x = -60, y = -40},   -- Spice-Teppich 17×17, Ernter A (Schritte 1–4)
  s4 = {x = -60, y = -18},   -- Felsfleck 12×12 für Schritt 4
  s5 = {x = -20, y = -40},   -- drei kleine Ressourcen unter zwei Erntern
  s6 = {x = 20, y = -40},    -- Felsinsel 16×16 mit Annahme, Stutzen, Greifarmen und Kisten (Schritte 6, 7)
  s8 = {x = 60, y = -40},    -- Spice-Teppich 15×15 für Klon und Teleport
  s9 = {x = 100, y = -40},   -- Annahme auf Sand
  s10 = {x = -60, y = 10},   -- Bohrer auf Spice
  s11 = {x = -20, y = 10},   -- Förderbänder
  s12 = {x = -40, y = 40}    -- Zustandstabelle: 5 Spalten × 4 Zeilen, Abstand 20
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

local function check(failed, ok, label)
  if not ok then table.insert(failed, label) end
  return ok
end

-- Echter Ernter, per script_raised_built eingetragen; coal Kohle ins Treibstoffinventar.
local function new_harvester(run, tb, position, coal, orientation, surface)
  local car = create(run, tb, {name = NAME, position = position, force = force_of(run, tb),
    orientation = orientation or 0.25, raise_built = true}, surface)
  if car then
    table.insert(run.data.cars, car)
    if coal and coal > 0 then tb.fuel(car, "coal", coal) end
  end
  return car
end

-- Schritt 1: Aufbauen mit 3 Kohle, nie gefahren; 15 s Ernten.

local function s1_start(run, tb, d)
  local s = d.s1
  local c = d.pos.s1
  local surface = tb.surface()
  tb.watch(run, nil, at(c, 0, 12))
  s.carpet = {{c.x - 8, c.y - 8}, {c.x + 9, c.y + 9}}
  local placed = place_spice(surface, c.x - 8, c.y - 8, c.x + 8, c.y + 8, 1000)
  local car = new_harvester(run, tb, {x = c.x + 0.5, y = c.y + 0.5}, 3)
  s.car = car
  if not car then return fail(run, tb, 1, "Ernter ließ sich nicht erzeugen") end
  local h = harvester.get(car)
  if not h then return fail(run, tb, 1, "Ernter nach script_raised_built nicht eingetragen") end
  tb.trace(run, string.format("1) Spice-Teppich 17×17 (%d Ressourcen je 1000) bei %s, Ernter Nr. %d mit %d Kohle, nie gefahren: %s",
    placed, pos_text(tb, c), car.unit_number, fuel_count(car, "coal"), flags_text(car)))
  s.toggle_ok = harvester.toggle(car, nil)
  s.toggle_tick = game.tick
  if not s.toggle_ok then
    return fail(run, tb, 1, "toggle gab false zurück (" .. flags_text(car) .. ")")
  end
  return 1
end

local function s1_wait(run, tb, d)
  local s = d.s1
  local car = s.car
  if not valid(car) then return fail(run, tb, 1, "Ernter weg") end
  local h = harvester.get(car)
  local state = h and h.state or "–"
  local waited = game.tick - s.toggle_tick
  if state == "deploying" then
    if waited > DEPLOY_TICKS + 100 then
      return fail(run, tb, 1, "nach " .. waited .. " Ticks noch deploying (Soll 300)")
    end
    return "poll"
  end
  if state ~= "deployed" then
    return fail(run, tb, 1, "Zustand " .. state .. " statt deployed nach " .. waited .. " Ticks")
  end
  s.deploy_ticks = waited
  s.locked = car.disabled_by_script
  s.minable_flag = car.minable_flag
  s.minable_read = car.minable
  s.cache = #h.resources
  local force, surface = car.force, car.surface
  s.bonus = force.mining_drill_productivity_bonus
  s.trunk0 = trunk_count(car)
  s.field0 = spice_in(surface, s.carpet)
  s.energy0 = fuel_energy(car)
  s.coal0 = fuel_count(car, "coal")
  s.stat_spice0 = spice_input(force, surface)
  s.stat_coal0 = fuel_output(force, surface, "coal")
  s.last0 = h.last_tick
  tb.trace(run, string.format("1) deployed nach %d Ticks: %s, minable %s, Cache %d Ressourcen, Status %s, Produktivität +%d %%, Brennwert %s",
    waited, flags_text(car), tostring(s.minable_read), s.cache, tostring(h.status), math.floor(s.bonus * 100 + 0.5), mj(s.energy0)))
  -- 15 s ernten, Messung in der Mitte zwischen zwei Abbautakten.
  return to_mid_cycle(15 * 60)
end

local function s1_measure(run, tb, d)
  local s = d.s1
  local car = s.car
  if not valid(car) then return fail(run, tb, 1, "Ernter weg") end
  local h = harvester.get(car)
  if not h then return fail(run, tb, 1, "Datensatz weg (" .. flags_text(car) .. ")") end
  local force, surface = car.force, car.surface
  local factor = 1 + s.bonus
  local mined = (h.last_tick - s.last0) / 60
  local inserted = trunk_count(car) - s.trunk0
  local expected = RATE * factor * mined
  local drained = s.field0 - spice_in(surface, s.carpet)
  local expected_drain = DRAIN * inserted / factor
  local consumed = s.energy0 - fuel_energy(car)
  local expected_energy = POWER * mined
  local loaded = s.coal0 - fuel_count(car, "coal")
  local stat_coal = fuel_output(force, surface, "coal") - s.stat_coal0
  local stat_spice = spice_input(force, surface) - s.stat_spice0
  local deviation = expected_energy > 0 and (consumed - expected_energy) / expected_energy or 0
  tb.trace(run, string.format("1) nach 15 s: Erntezeit %.2f s, Ausbeute %d (Soll %.1f), Feldabzug %d (Soll %.1f), Brennwert −%s (Soll −%s), "
    .. "Kohle geladen %d, Statistik Kohle %d, Statistik Spice %d, Status %s, Brenner %s",
    mined, inserted, expected, drained, expected_drain, mj(consumed), mj(expected_energy), loaded, stat_coal, stat_spice,
    tostring(h.status), car.burner and car.burner.currently_burning and car.burner.currently_burning.name.name or "–"))
  local failed = {}
  check(failed, s.deploy_ticks >= DEPLOY_TICKS and s.deploy_ticks <= DEPLOY_TICKS + 20, "Aufbau in 5 s")
  check(failed, s.locked == true, "gesperrt")
  check(failed, s.minable_flag == false, "nicht abbaubar")
  check(failed, s.cache == FIELD_TILES, "Feld 13×13")
  check(failed, mined >= 14.5 and mined <= 15.5, "Erntezeit 15 s")
  check(failed, math.abs(inserted - expected) <= 2, "Ausbeute ≈ 5/s")
  check(failed, math.abs(drained - expected_drain) <= 1, "Feldabzug = 0,5 × Ausbeute ± 1")
  check(failed, math.abs(deviation) <= 0.05, "Brennwert ± 5 %")
  check(failed, loaded >= 1 and loaded == stat_coal, "Kohle-Itemzahl = Statistik")
  check(failed, inserted == stat_spice, "Spice = Statistik")
  check(failed, h.status == "harvesting", "Status Erntet")
  return verdict(run, tb, 1, "Aufbauen und Ernten", failed, string.format(
    "deployed nach %.1f s, disabled_by_script %s, minable_flag %s, Feld %d; %.1f s geerntet: %d Spice (%.2f/s, Soll %.1f), "
    .. "Feldabzug %d (Soll %.1f), Brennwert −%s (Soll −%s, %+.1f %%), Kohle −%d = Statistik %d, Spice +%d = Statistik %d",
    s.deploy_ticks / 60, tostring(s.locked), tostring(s.minable_flag), s.cache, mined, inserted,
    mined > 0 and inserted / mined or 0, expected, drained, expected_drain, mj(consumed), mj(expected_energy),
    deviation * 100, loaded, stat_coal, inserted, stat_spice))
end

-- Schritt 2: Dummy-Fahrer gibt Gas, während aufgebaut; dann order_deconstruction.

local S2_TICKS = 5 * 60

local function s2_start(run, tb, d)
  local s = d.s2
  local car = d.s1.car
  if not (valid(car) and state_of(car) == "deployed") then
    return fail(run, tb, 2, "nicht prüfbar: Ernter aus Schritt 1 nicht aufgebaut (" .. flags_text(car) .. ")")
  end
  local driver = tb.dummy_driver(car)
  if driver then table.insert(d.drivers, driver) end
  s.driver = driver
  local seated = car.get_driver()
  s.seated = seated ~= nil
  s.pos0 = copy_pos(car.position)
  s.max = 0
  s.start = game.tick
  s.energy0 = fuel_energy(car)
  s.last0 = harvester.get(car).last_tick
  gas(car, driver, true)
  return 1
end

local function s2_drive(run, tb, d)
  local s = d.s2
  local car = d.s1.car
  if not valid(car) then return fail(run, tb, 2, "Ernter weg") end
  local speed = tb.speed_tps(car) or 0
  if speed > s.max then s.max = speed end
  if game.tick - s.start < S2_TICKS then
    gas(car, s.driver, true)
    return "poll"
  end
  gas(car, s.driver, false)
  local h = harvester.get(car)
  s.moved = tb.distance(car.position, s.pos0)
  s.state = h and h.state or "–"
  s.locked = car.disabled_by_script
  local mined = h and (h.last_tick - s.last0) / 60 or 0
  s.consumed = s.energy0 - fuel_energy(car)
  s.expected_energy = POWER * mined
  pcall(function() car.set_driver(nil) end)
  if valid(s.driver) then s.driver.destroy() end
  s.driver = nil
  local ok, result = pcall(function() return car.order_deconstruction(car.force) end)
  s.order_result = ok and tostring(result) or ("Fehler: " .. tostring(result))
  s.marked_now = car.to_be_deconstructed()
  tb.trace(run, string.format("2) 5 s Gas (Fahrer %s): Weg %.3f, Höchsttempo %.3f Kacheln/s, %s; Brennwert −%s (Ernten %s); "
    .. "order_deconstruction → %s, sofort markiert %s",
    s.seated and "sitzt" or "sitzt nicht", s.moved, s.max, flags_text(car), mj(s.consumed), mj(s.expected_energy),
    s.order_result, tostring(s.marked_now)))
  return 1
end

local function s2_check(run, tb, d)
  local s = d.s2
  local car = d.s1.car
  if not valid(car) then return fail(run, tb, 2, "Ernter weg") end
  local marked = car.to_be_deconstructed()
  -- Ohne Fahrer bewegt riding_state ein Auto nicht: „Weg 0“ hieße dann nichts.
  if not s.seated then
    return fail(run, tb, 2, string.format("nicht prüfbar: Dummy-Fahrer saß nicht im Ernter (Weg %.3f, Zustand %s, danach markiert %s)",
      s.moved, s.state, tostring(marked)))
  end
  local failed = {}
  check(failed, s.moved < 0.01, "Weg 0")
  check(failed, s.state == "deployed" and s.locked == true, "bleibt aufgebaut und gesperrt")
  check(failed, not marked, "nicht zum Abriss markiert")
  return verdict(run, tb, 2, "Gas im aufgebauten Ernter, Abriss-Markierung", failed, string.format(
    "Weg %.3f Kacheln, Höchsttempo %.2f Kacheln/s, Zustand %s; Brennwert −%s (Ernten %s); order_deconstruction → %s, danach markiert %s",
    s.moved, s.max, s.state, mj(s.consumed), mj(s.expected_energy), s.order_result, tostring(marked)))
end

-- Schritt 3: Laderaum voll, 600 Ticks Pause, leeren, ein Takt: kein Nachholen.

local S3_PAUSE = 600

local function s3_fill(run, tb, d)
  local s = d.s3
  local car = d.s1.car
  if not (valid(car) and state_of(car) == "deployed") then
    return fail(run, tb, 3, "nicht prüfbar: Ernter aus Schritt 1 nicht aufgebaut (" .. flags_text(car) .. ")")
  end
  local trunk = car.get_inventory(defines.inventory.car_trunk)
  local capacity = #trunk * prototypes.item[SPICE].stack_size
  s.filled = trunk.insert{name = SPICE, count = capacity}
  s.room = trunk.can_insert{name = SPICE, count = 1}
  s.energy0 = fuel_energy(car)
  s.field0 = spice_in(car.surface, d.s1.carpet)
  tb.trace(run, string.format("3) Laderaum gefüllt: +%d Spice, jetzt %d von %d, Platz frei %s", s.filled, trunk_count(car), capacity, tostring(s.room)))
  return S3_PAUSE
end

local function s3_pause(run, tb, d)
  local s = d.s3
  local car = d.s1.car
  if not valid(car) then return fail(run, tb, 3, "Ernter weg") end
  local h = harvester.get(car)
  s.status_pause = h and h.status or "–"
  s.energy_pause = s.energy0 - fuel_energy(car)
  s.drain_pause = s.field0 - spice_in(car.surface, d.s1.carpet)
  return to_mid_cycle()
end

local function s3_clear(run, tb, d)
  local s = d.s3
  local car = d.s1.car
  if not valid(car) then return fail(run, tb, 3, "Ernter weg") end
  local h = harvester.get(car)
  car.get_inventory(defines.inventory.car_trunk).clear()
  s.last_before = h and h.last_tick or game.tick
  s.energy1 = fuel_energy(car)
  s.field1 = spice_in(car.surface, d.s1.carpet)
  s.stat0 = spice_input(car.force, car.surface)
  return 30
end

local function s3_check(run, tb, d)
  local s = d.s3
  local car = d.s1.car
  if not valid(car) then return fail(run, tb, 3, "Ernter weg") end
  local h = harvester.get(car)
  local inserted = trunk_count(car)
  local cycle = h and (h.last_tick - s.last_before) / 60 or 0
  local drained = s.field1 - spice_in(car.surface, d.s1.carpet)
  local consumed = s.energy1 - fuel_energy(car)
  local stat = spice_input(car.force, car.surface) - s.stat0
  local status = h and h.status or "–"
  local failed = {}
  check(failed, s.status_pause == "trunk_full", "Status Laderaum voll")
  check(failed, math.abs(s.energy_pause) < 1 and s.drain_pause == 0, "Pause ohne Verbrauch und Feldabzug")
  check(failed, inserted <= RATE + 1, "höchstens 5 + 1 eingefügt")
  check(failed, drained <= DRAIN * inserted + 1, "Feldabzug ≤ 0,5 × eingefügt + 1")
  check(failed, consumed <= POWER * 0.5 * 1.05, "Brennwert ≤ 400 kW × 0,5 s")
  check(failed, stat == inserted, "Statistik = eingefügt")
  check(failed, status == "harvesting", "Status wieder Erntet")
  return verdict(run, tb, 3, "Laderaum voll, Pause, ein Takt", failed, string.format(
    "Status in der Pause %s, Verbrauch in 600 Ticks %s, Feldabzug %d; nach dem Leeren ein Takt (%.2f s): %d eingefügt, "
    .. "Feldabzug %d, Brennwert −%s, Statistik %d, Status %s",
    s.status_pause, mj(s.energy_pause), s.drain_pause, cycle, inserted, drained, mj(consumed), stat, status))
end

-- Schritt 4: Einpacken auf Sand, dann auf Fels teleportiert abbaubar.

local function s4_pack(run, tb, d)
  local s = d.s4
  local car = d.s1.car
  if not (valid(car) and state_of(car) == "deployed") then
    return fail(run, tb, 4, "nicht prüfbar: Ernter aus Schritt 1 nicht aufgebaut (" .. flags_text(car) .. ")")
  end
  s.toggle_ok = harvester.toggle(car, nil)
  s.after = state_of(car)
  s.start = game.tick
  if not (s.toggle_ok and s.after == "packing") then
    return fail(run, tb, 4, "toggle gab " .. tostring(s.toggle_ok) .. " zurück, " .. flags_text(car))
  end
  return 1
end

local function s4_wait(run, tb, d)
  local s = d.s4
  local car = d.s1.car
  if not valid(car) then return fail(run, tb, 4, "Ernter weg") end
  local state = state_of(car)
  local waited = game.tick - s.start
  if state == "packing" then
    if waited > PACK_TICKS + 100 then return fail(run, tb, 4, "nach " .. waited .. " Ticks noch packing (Soll 600)") end
    return "poll"
  end
  if state ~= "mobile" then return fail(run, tb, 4, "Zustand " .. state .. " statt mobile nach " .. waited .. " Ticks") end
  s.pack_ticks = waited
  s.locked = car.disabled_by_script
  s.flag_sand = car.minable_flag
  s.tile_sand = tb.tiles_name(car.surface, car.position)
  -- Teleport ohne Ereignis: die Abbausperre wertet der 60-Tick-Takt neu (ruhend, Position geändert).
  local target = {x = d.pos.s4.x + 0.5, y = d.pos.s4.y + 0.5}
  s.teleported = car.teleport(target)
  s.tile_rock = tb.tiles_name(car.surface, car.position)
  return 70
end

local function s4_check(run, tb, d)
  local s = d.s4
  local car = d.s1.car
  if not valid(car) then return fail(run, tb, 4, "Ernter weg") end
  local flag_rock = car.minable_flag
  local failed = {}
  check(failed, s.pack_ticks >= PACK_TICKS and s.pack_ticks <= PACK_TICKS + 20, "mobile nach 10 s")
  check(failed, s.locked == false, "entsperrt")
  check(failed, s.flag_sand == false, "auf Sand nicht abbaubar")
  check(failed, s.teleported == true, "Teleport auf Fels")
  check(failed, flag_rock == true, "auf Fels abbaubar")
  return verdict(run, tb, 4, "Einpacken, Abbausperre", failed, string.format(
    "mobile nach %.1f s, disabled_by_script %s, auf %s minable_flag %s; Teleport auf %s %s, nach 70 Ticks minable_flag %s",
    s.pack_ticks / 60, tostring(s.locked), s.tile_sand, tostring(s.flag_sand), s.tile_rock, tostring(s.teleported), tostring(flag_rock)))
end

-- Schritt 5: Erschöpfung: drei Ressourcen (Menge 1, 2, 3) unter zwei überlappenden Erntern.

local S5_TIMEOUT = 25 * 60

local function s5_start(run, tb, d)
  local s = d.s5
  local c = d.pos.s5
  local surface = tb.surface()
  tb.watch(run, nil, at(c, 0, 10))
  s.resources = {}
  for i, amount in ipairs({1, 2, 3}) do
    local resource = surface.create_entity{name = SPICE, position = {c.x + 0.5, c.y - 1.5 + 2 * (i - 1)}, amount = amount}
    if resource then table.insert(s.resources, resource) end
  end
  s.cars = {new_harvester(run, tb, {x = c.x - 2.5, y = c.y + 0.5}, 3, 0), new_harvester(run, tb, {x = c.x + 3.5, y = c.y + 0.5}, 3, 0)}
  if #s.resources ~= 3 or not (valid(s.cars[1]) and valid(s.cars[2])) then
    return fail(run, tb, 5, string.format("Aufbau ging nicht: %d von 3 Ressourcen, Ernter %s/%s", #s.resources,
      tostring(valid(s.cars[1])), tostring(valid(s.cars[2]))))
  end
  s.toggled = {}
  for i, car in ipairs(s.cars) do s.toggled[i] = harvester.toggle(car, nil) end
  s.start = game.tick
  tb.trace(run, "5) Ressourcen 1, 2, 3 bei " .. pos_text(tb, c) .. ", zwei Ernter im Abstand 6, toggle → "
    .. tostring(s.toggled[1]) .. "/" .. tostring(s.toggled[2]))
  return 1
end

local function s5_wait(run, tb, d)
  local s = d.s5
  local done = true
  for _, car in ipairs(s.cars) do
    local h = valid(car) and harvester.get(car)
    if not (h and h.state == "deployed" and h.status == "field_empty") then done = false end
  end
  local waited = game.tick - s.start
  if not done and waited < S5_TIMEOUT then return "poll" end
  local left, parts, harvested = 0, {}, 0
  for _, resource in ipairs(s.resources) do
    if resource.valid then left = left + 1 end
  end
  for i, car in ipairs(s.cars) do
    local h = valid(car) and harvester.get(car)
    local count = valid(car) and trunk_count(car) or 0
    harvested = harvested + count
    table.insert(parts, string.format("Ernter %d: %s/%s, %d Spice", i, h and h.state or "–", h and tostring(h.status) or "–", count))
  end
  local failed = {}
  check(failed, done, "beide Feld erschöpft")
  check(failed, left == 0, "alle drei Ressourcen weg")
  tb.trace(run, string.format("5) nach %.1f s: %s; Ressourcen übrig %d; geerntet %d, Feldabzug 6, 0,5 × geerntet = %.1f",
    waited / 60, table.concat(parts, "; "), left, harvested, DRAIN * harvested))
  verdict(run, tb, 5, "Erschöpfung unter zwei Erntern", failed, string.format(
    "kein Skriptfehler (Takte liefen durch), nach %.1f s %s; Ressourcen übrig %d von 3; geerntet %d (0,5 × %d = %.1f, Feldabzug 6)",
    waited / 60, table.concat(parts, "; "), left, harvested, harvested, DRAIN * harvested))
  -- Ernter mit Ereignis entfernen: Alarme weg, storage leer.
  for _, car in ipairs(s.cars) do
    if valid(car) then
      local un = car.unit_number
      car.destroy{raise_destroy = true}
      tb.trace(run, "5) Ernter Nr. " .. un .. " entfernt, Datensatz " .. (storage.harvesters[un] and "noch da" or "weg"))
    end
  end
  return "end"
end

-- Schritte 6 und 7: Felsinsel mit Annahme (Mitte o), Stutzen o+(-0.5, 2.5), Greifarm Annahme → Kiste
-- o+(1.5, -0.5) → o+(2.5, -0.5), Kohlekiste o+(-0.5, 4.5) → Greifarm o+(-0.5, 3.5) → Stutzen,
-- Mast o+(0.5, 1.5), Energie-Schnittstelle o+(3, 3), Ernter D bei o+(0, -3.5) mit 100 Spice-Sand.

local S6_HARVESTER = {x = 0, y = -3.5}
local S6_AWAY = {x = 0, y = -9.5}
local S6_DOCK_LIMIT = 190

local function targets_text(s, car)
  local function one(entity)
    if not valid(entity) then return "weg" end
    local target = entity.proxy_target_entity
    if not target then return "nil" end
    local mark = valid(car) and target.unit_number == car.unit_number and "Ernter" or target.name
    return mark .. "/" .. tostring(entity.proxy_target_inventory)
  end
  return "Annahme → " .. one(s.intake) .. ", Stutzen → " .. one(s.nozzle)
end

local function targets_on(s, car)
  local function on(entity, inventory)
    local target = valid(entity) and entity.proxy_target_entity
    return target and valid(car) and target.unit_number == car.unit_number and entity.proxy_target_inventory == inventory or false
  end
  return on(s.intake, defines.inventory.car_trunk) and on(s.nozzle, defines.inventory.fuel)
end

local function targets_off(s)
  local function off(entity)
    return not valid(entity) or entity.proxy_target_entity == nil
  end
  return off(s.intake) and off(s.nozzle)
end

local function s6_build(run, tb, d)
  local s = d.s6
  local o = d.pos.s6
  local force = force_of(run, tb)
  tb.watch(run, nil, at(o, -6, 6))
  s.power = create(run, tb, {name = "electric-energy-interface", position = at(o, 3, 3), force = force})
  s.pole = create(run, tb, {name = "medium-electric-pole", position = at(o, 0.5, 1.5), force = force})
  s.intake = create(run, tb, {name = INTAKE, position = o, force = force, raise_built = true})
  s.nozzle = create(run, tb, {name = NOZZLE, position = at(o, -0.5, 2.5), force = force, raise_built = true})
  s.chest = create(run, tb, {name = "wooden-chest", position = at(o, 2.5, -0.5), force = force})
  s.coal_chest = create(run, tb, {name = "wooden-chest", position = at(o, -0.5, 4.5), force = force})
  if not (s.power and s.pole and s.intake and s.nozzle and s.chest and s.coal_chest) then
    return fail(run, tb, 6, "Aufbau ging nicht (Einzelheiten in der Datei)")
  end
  s.inserter_out = inserter_between(run, tb, at(o, 1.5, -0.5), s.intake, s.chest)
  s.inserter_fuel = inserter_between(run, tb, at(o, -0.5, 3.5), s.coal_chest, s.nozzle)
  if not (s.inserter_out and s.inserter_fuel) then
    return fail(run, tb, 6, "Greifarm ließ sich in keiner Richtung passend setzen")
  end
  s.coal_chest.get_inventory(defines.inventory.chest).insert{name = "coal", count = 50}
  local record = intake.get(s.intake)
  local nozzle_record = intake.get(s.nozzle)
  s.intake_un = s.intake.unit_number
  if not (record and not record.bad and nozzle_record and nozzle_record.intake == s.intake_un) then
    return fail(run, tb, 6, string.format("Annahme/Stutzen nicht richtig eingetragen: Annahme %s (bad %s), Stutzen gehört zu %s",
      record and "eingetragen" or "fehlt", record and tostring(record.bad) or "–", nozzle_record and tostring(nozzle_record.intake) or "–"))
  end
  local car = new_harvester(run, tb, at(o, S6_HARVESTER.x, S6_HARVESTER.y), 0)
  s.car = car
  if not car then return fail(run, tb, 6, "Ernter ließ sich nicht erzeugen") end
  s.spice = car.get_inventory(defines.inventory.car_trunk).insert{name = SPICE, count = 100}
  s.start = game.tick
  tb.trace(run, string.format("6) Felsinsel bei %s: Annahme Nr. %d, Stutzen zugeordnet, Ernter Nr. %d im Kreis (Abstand %.1f), %d Spice-Sand, Treibstoff leer",
    pos_text(tb, o), s.intake_un, car.unit_number, tb.distance(car.position, o), s.spice))
  return 1
end

local function s6_wait_dock(run, tb, d)
  local s = d.s6
  local car = s.car
  if not valid(car) then return fail(run, tb, 6, "Ernter weg") end
  local waited = game.tick - s.start
  if state_of(car) ~= "docked" then
    if waited > 300 then return fail(run, tb, 6, "dockt nicht an: nach " .. waited .. " Ticks " .. flags_text(car)) end
    return "poll"
  end
  s.dock_ticks = waited
  s.dock_disabled = car.disabled_by_script
  s.dock_targets = targets_on(s, car)
  s.dock_text = targets_text(s, car)
  tb.trace(run, "6) angedockt nach " .. waited .. " Ticks: " .. flags_text(car) .. "; " .. s.dock_text)
  return 10 * 60
end

local function s6_flow(run, tb, d)
  local s = d.s6
  local car = s.car
  if not valid(car) then return fail(run, tb, 6, "Ernter weg") end
  s.chest_spice = s.chest.get_inventory(defines.inventory.chest).get_item_count(SPICE)
  s.fuel_coal = fuel_count(car, "coal")
  s.flow_state = state_of(car)
  tb.trace(run, string.format("6) nach 10 s angedockt: Kiste %d Spice-Sand, Ernter-Treibstoff %d Kohle, Laderaum %d", s.chest_spice, s.fuel_coal, trunk_count(car)))
  s.undock_ok = harvester.toggle(car, nil)
  s.undock_state = state_of(car)
  s.undock_disabled = car.disabled_by_script
  s.undock_targets = targets_off(s)
  local h = harvester.get(car)
  s.undocked_from = h and h.undocked_from
  tb.trace(run, "6) toggle → " .. tostring(s.undock_ok) .. ": " .. flags_text(car) .. "; " .. targets_text(s, car)
    .. "; undocked_from " .. tostring(s.undocked_from))
  return 3 * 60 + 5
end

local function s6_stay(run, tb, d)
  local s = d.s6
  local car = s.car
  if not valid(car) then return fail(run, tb, 6, "Ernter weg") end
  s.stay_state = state_of(car)
  s.stay_disabled = car.disabled_by_script
  s.away_ok = car.teleport(at(d.pos.s6, S6_AWAY.x, S6_AWAY.y))
  return 70
end

local function s6_away(run, tb, d)
  local s = d.s6
  local car = s.car
  if not valid(car) then return fail(run, tb, 6, "Ernter weg") end
  local h = harvester.get(car)
  s.away_released = h and h.undocked_from == nil
  s.away_state = state_of(car)
  s.back_ok = car.teleport(at(d.pos.s6, S6_HARVESTER.x, S6_HARVESTER.y))
  s.back_tick = game.tick
  tb.trace(run, string.format("6) 6 Kacheln weg (Teleport %s): %s, undocked_from gelöscht %s; zurück (Teleport %s)",
    tostring(s.away_ok), flags_text(car), tostring(s.away_released), tostring(s.back_ok)))
  return 1
end

local function s6_redock(run, tb, d)
  local s = d.s6
  local car = s.car
  if not valid(car) then return fail(run, tb, 6, "Ernter weg") end
  local waited = game.tick - s.back_tick
  local docked = state_of(car) == "docked"
  if not docked and waited <= 250 then return "poll" end
  s.redock_ticks = docked and waited or nil
  local failed = {}
  check(failed, s.dock_ticks <= S6_DOCK_LIMIT, "dockt in 3 s")
  check(failed, s.dock_disabled == true and s.dock_targets, "gesperrt, Ziele gesetzt")
  check(failed, s.chest_spice > 0, "Kiste hat Spice")
  check(failed, s.fuel_coal > 0, "Treibstoff hat Kohle")
  check(failed, s.undock_ok and s.undock_state == "mobile" and s.undock_disabled == false and s.undock_targets, "Abdocken per toggle")
  check(failed, s.stay_state == "mobile" and s.stay_disabled == false, "bleibt 3 × 60 Ticks mobile")
  check(failed, s.away_ok and s.back_ok and docked, "dockt nach Weg und zurück wieder")
  return verdict(run, tb, 6, "Andocken, Greifarme, Abdocken", failed, string.format(
    "docked nach %.1f s (%s); 10 s Greifarme: Kiste %d Spice, Treibstoff %d Kohle; toggle → %s, %s; nach 185 Ticks %s; "
    .. "6 Kacheln weg (undocked_from gelöscht %s) und zurück: %s",
    s.dock_ticks / 60, s.dock_text, s.chest_spice, s.fuel_coal, tostring(s.undock_ok),
    s.undock_targets and "Ziele nil" or "Ziele noch gesetzt", s.stay_state, tostring(s.away_released),
    docked and string.format("docked nach %.1f s", waited / 60) or ("nicht angedockt (" .. flags_text(car) .. ")")))
end

-- Schritt 7: Annahme zerstören (destroy ohne Ereignis, nur on_object_destroyed), Ernter die() angedockt.

local function s7_destroy(run, tb, d)
  local s = d.s7
  local s6 = d.s6
  local car = s6.car
  if not (valid(car) and state_of(car) == "docked" and valid(s6.intake)) then
    return fail(run, tb, 7, "nicht prüfbar: Ernter aus Schritt 6 nicht angedockt (" .. flags_text(car) .. ")")
  end
  s.intake_un = s6.intake.unit_number
  s.nozzle_un = valid(s6.nozzle) and s6.nozzle.unit_number
  s6.intake.destroy()
  s.destroy_tick = game.tick
  return 2
end

local function s7_after(run, tb, d)
  local s = d.s7
  local s6 = d.s6
  local car = s6.car
  if not valid(car) then return fail(run, tb, 7, "Ernter weg") end
  s.a_state = state_of(car)
  s.a_disabled = car.disabled_by_script
  s.a_record_gone = storage.intakes[s.intake_un] == nil
  local nozzle_record = s.nozzle_un and storage.nozzles[s.nozzle_un]
  s.a_nozzle_free = valid(s6.nozzle) and s6.nozzle.proxy_target_entity == nil and nozzle_record and nozzle_record.intake == nil or false
  tb.trace(run, string.format("7) 2 Ticks nach destroy(): %s; Annahme-Eintrag weg %s, Stutzen frei %s",
    flags_text(car), tostring(s.a_record_gone), tostring(s.a_nozzle_free)))
  -- Neue Annahme an derselben Stelle: übernimmt den freien Stutzen, der Ernter dockt wieder an.
  s6.intake = create(run, tb, {name = INTAKE, position = d.pos.s6, force = force_of(run, tb), raise_built = true})
  if not s6.intake then return fail(run, tb, 7, "neue Annahme ließ sich nicht erzeugen") end
  local record = nozzle_record and storage.nozzles[s.nozzle_un]
  s.adopted = record and record.intake == s6.intake.unit_number or false
  s.rebuild_tick = game.tick
  return 1
end

local function s7_wait_dock(run, tb, d)
  local s = d.s7
  local s6 = d.s6
  local car = s6.car
  if not valid(car) then return fail(run, tb, 7, "Ernter weg") end
  local waited = game.tick - s.rebuild_tick
  if state_of(car) ~= "docked" then
    if waited > 300 then
      return fail(run, tb, 7, string.format("Annahme zerstört: %s; neue Annahme: Ernter dockt nicht an (%s), Teil die() nicht prüfbar",
        s.a_state, flags_text(car)))
    end
    return "poll"
  end
  s.redock_ticks = waited
  s.car_un = car.unit_number
  s.died = car.die()
  local intake_record = intake.get(s6.intake)
  s.b_targets_off = targets_off(s6)
  s.b_record_free = intake_record and intake_record.docked == nil or false
  s.b_storage_empty = storage.harvesters[s.car_un] == nil and storage.driven[s.car_un] == nil and storage.timers[s.car_un] == nil
  tb.trace(run, string.format("7) neue Annahme nach %d Ticks angedockt, Stutzen übernommen %s; die() → %s: %s, Annahme frei %s, storage leer %s",
    waited, tostring(s.adopted), tostring(s.died), targets_text(s6, nil), tostring(s.b_record_free), tostring(s.b_storage_empty)))
  return 2
end

local function s7_check(run, tb, d)
  local s = d.s7
  local reg_left = 0
  for _, entry in pairs(storage.reg) do
    if entry.kind == "harvester" and entry.un == s.car_un then reg_left = reg_left + 1 end
  end
  local failed = {}
  check(failed, s.a_state == "mobile" and s.a_disabled == false, "nach 2 Ticks entsperrt")
  check(failed, s.a_record_gone and s.a_nozzle_free, "Annahme ausgetragen, Stutzen frei")
  check(failed, s.died == true, "die() ging")
  check(failed, s.b_targets_off and s.b_record_free, "Ziele nil")
  check(failed, s.b_storage_empty and reg_left == 0, "storage leer")
  return verdict(run, tb, 7, "Annahme zerstört, Ernter tot", failed, string.format(
    "Annahme destroy() ohne Ereignis: nach 2 Ticks Zustand %s, disabled_by_script %s, Eintrag weg %s, Stutzen frei %s; "
    .. "neue Annahme, angedockt nach %.1f s; die() angedockt: Ziele nil %s, Annahme frei %s, storage leer %s, on_object_destroyed-Einträge übrig %d",
    s.a_state, tostring(s.a_disabled), tostring(s.a_record_gone), tostring(s.a_nozzle_free), (s.redock_ticks or 0) / 60,
    tostring(s.b_targets_off), tostring(s.b_record_free), tostring(s.b_storage_empty), reg_left))
end

-- Schritt 8: Klon eines aufgebauten Ernters; Teleport eines aufgebauten Ernters ohne Ereignis.

local function s8_start(run, tb, d)
  local s = d.s8
  local c = d.pos.s8
  local surface = tb.surface()
  tb.watch(run, nil, at(c, -12, 8))
  s.carpet = {{c.x - 7, c.y - 7}, {c.x + 8, c.y + 8}}
  place_spice(surface, c.x - 7, c.y - 7, c.x + 7, c.y + 7, 1000)
  -- Fels unter dem Klon (c + (0.5, 12.5)): der Klon muss die Abbausperre neu werten (Quelle: false auf Sand).
  tb.fill({{c.x - 3, c.y + 10}, {c.x + 4, c.y + 15}}, ROCK, surface)
  local car = new_harvester(run, tb, {x = c.x + 0.5, y = c.y + 0.5}, 3)
  s.car = car
  if not car then return fail(run, tb, 8, "Ernter ließ sich nicht erzeugen") end
  s.toggle_ok = harvester.toggle(car, nil)
  s.start = game.tick
  if not s.toggle_ok then return fail(run, tb, 8, "toggle gab false zurück (" .. flags_text(car) .. ")") end
  return 1
end

local function s8_clone(run, tb, d)
  local s = d.s8
  local car = s.car
  if not valid(car) then return fail(run, tb, 8, "Ernter weg") end
  local state = state_of(car)
  if state == "deploying" then
    if game.tick - s.start > DEPLOY_TICKS + 100 then return fail(run, tb, 8, "Ernter wird nicht fertig: " .. flags_text(car)) end
    return "poll"
  end
  if state ~= "deployed" then return fail(run, tb, 8, "Ernter nicht aufgebaut: " .. flags_text(car)) end
  local c = d.pos.s8
  local ok, clone = pcall(function() return car.clone{position = {x = c.x + 0.5, y = c.y + 12.5}} end)
  if ok and clone then
    s.clone_state = state_of(clone)
    s.clone_disabled = clone.disabled_by_script
    s.clone_flag = clone.minable_flag
    s.clone_text = flags_text(clone) .. " auf " .. tb.tiles_name(clone.surface, clone.position)
    clone.destroy{raise_destroy = true}
  else
    s.clone_text = "clone ging nicht: " .. (ok and "nil" or tostring(clone))
  end
  s.original_state = state_of(car)
  tb.trace(run, "8) Klon des aufgebauten Ernters: " .. s.clone_text .. "; Original " .. flags_text(car))
  return to_mid_cycle()
end

local function s8_teleport(run, tb, d)
  local s = d.s8
  local car = s.car
  if not valid(car) then return fail(run, tb, 8, "Ernter weg") end
  local c = d.pos.s8
  s.field0 = spice_in(car.surface, s.carpet)
  s.before = state_of(car)
  s.teleported = car.teleport({x = c.x + 0.5, y = c.y + 20.5})
  return 30
end

local function s8_check(run, tb, d)
  local s = d.s8
  local car = s.car
  if not valid(car) then return fail(run, tb, 8, "Ernter weg") end
  local state = state_of(car)
  local disabled = car.disabled_by_script
  local drained = s.field0 - spice_in(car.surface, s.carpet)
  local failed = {}
  check(failed, s.clone_state == "mobile" and s.clone_disabled == false, "Klon mobile und entsperrt")
  check(failed, s.clone_flag == true, "Klon auf Fels abbaubar")
  check(failed, s.original_state == "deployed", "Original bleibt aufgebaut")
  check(failed, s.before == "deployed" and s.teleported == true, "Teleport ging")
  check(failed, state == "mobile" and disabled == false, "nach einem Takt mobile")
  check(failed, drained == 0, "altes Feld unverändert")
  return verdict(run, tb, 8, "Klon und Teleport", failed, string.format(
    "Klon: %s; Original %s; Teleport 20 Kacheln ohne Ereignis %s, nach einem Takt Zustand %s, disabled_by_script %s, Abzug am alten Feld %d",
    s.clone_text or "–", tostring(s.original_state), tostring(s.teleported), state, tostring(disabled), drained))
end

-- Schritt 9: Annahme auf Sand per create_entity{raise_built = true}.

local function s9_start(run, tb, d)
  local s = d.s9
  local c = d.pos.s9
  tb.watch(run, nil, at(c, 0, 8))
  s.car = new_harvester(run, tb, at(c, S6_HARVESTER.x, S6_HARVESTER.y), 0)
  s.intake = create(run, tb, {name = INTAKE, position = c, force = force_of(run, tb), raise_built = true})
  if not (s.car and s.intake) then return fail(run, tb, 9, "Ernter oder Annahme ließ sich nicht erzeugen") end
  local record = intake.get(s.intake)
  s.bad = record and record.bad
  s.marked_now = s.intake.to_be_deconstructed()
  return 4 * 60
end

local function s9_check(run, tb, d)
  local s = d.s9
  if not (valid(s.car) and valid(s.intake)) then return fail(run, tb, 9, "Ernter oder Annahme weg") end
  local marked = s.intake.to_be_deconstructed()
  local state = state_of(s.car)
  local target = s.intake.proxy_target_entity
  local failed = {}
  check(failed, s.bad == true, "als bad eingetragen")
  check(failed, marked, "zum Abriss markiert")
  check(failed, state == "mobile" and target == nil, "dockt nicht")
  return verdict(run, tb, 9, "Annahme auf Sand", failed, string.format(
    "Kachel %s, bad %s, markiert sofort %s, nach 4 s %s; Ernter im Kreis (Abstand %.1f): Zustand %s, Ziel %s",
    tb.tiles_name(s.intake.surface, s.intake.position), tostring(s.bad), tostring(s.marked_now), tostring(marked),
    tb.distance(s.car.position, s.intake.position), state, target and target.name or "nil"))
end

-- Schritt 10: Bohrer auf Spice (migrate.report_drills), Gegenprobe mit Bohrer ohne Spice.

local function s10_run(run, tb, d)
  local c = d.pos.s10
  local surface = tb.surface()
  local force = force_of(run, tb)
  local placed = place_spice(surface, c.x - 2, c.y - 2, c.x + 2, c.y + 2, 500)
  local drill = create(run, tb, {name = "electric-mining-drill", position = {c.x + 0.5, c.y + 0.5}, force = force,
    direction = defines.direction.north})
  local control = create(run, tb, {name = "electric-mining-drill", position = {c.x + 15.5, c.y + 0.5}, force = force,
    direction = defines.direction.north})
  if not (drill and control) then return fail(run, tb, 10, "Bohrer ließ sich nicht erzeugen") end
  local found = migrate.report_drills(surface)
  local hit, control_hit = false, false
  for _, entity in pairs(found) do
    if entity.valid and entity.unit_number == drill.unit_number then hit = true end
    if entity.valid and entity.unit_number == control.unit_number then control_hit = true end
  end
  -- Kartenmarkierungen der Meldung im Testbereich wieder entfernen.
  local tags = 0
  local ok_tags = pcall(function()
    for _, tag in pairs(force.find_chart_tags(surface, {{c.x - 30, c.y - 30}, {c.x + 30, c.y + 30}})) do
      tag.destroy()
      tags = tags + 1
    end
  end)
  local failed = {}
  check(failed, hit, "Bohrer auf Spice gemeldet")
  check(failed, not control_hit, "Bohrer ohne Spice nicht gemeldet")
  return verdict(run, tb, 10, "Bohrer auf Spice", failed, string.format(
    "%d Spice-Kacheln, Bohrer mining_target %s; report_drills meldet %d Bohrer auf der Fläche, darunter der Testbohrer %s, die Gegenprobe %s; "
    .. "Kartenmarkierungen entfernt %s",
    placed, read(function() return drill.mining_target and drill.mining_target.name end) or "nil", #found, tostring(hit),
    tostring(control_hit), ok_tags and tostring(tags) or "Fehler"))
end

-- Schritt 11: Ernter auf laufendem Band, Gegenprobe mit einem Vanilla-Auto.

local S11_TICKS = 5 * 60
local S11_BELTS = 2 * 12

local function s11_start(run, tb, d)
  local s = d.s11
  local c = d.pos.s11
  local force = force_of(run, tb)
  tb.watch(run, nil, at(c, 0, 14))
  local belts = 0
  for _, row in ipairs({0, 6}) do
    for x = c.x - 6, c.x + 5 do
      if create(run, tb, {name = "transport-belt", position = {x + 0.5, c.y + row + 0.5}, direction = defines.direction.east, force = force}) then
        belts = belts + 1
      end
    end
  end
  s.car = new_harvester(run, tb, {x = c.x + 0.5, y = c.y + 0.5}, 0)
  s.control = create(run, tb, {name = "car", position = {x = c.x + 0.5, y = c.y + 6.5}, force = force, orientation = 0.25})
  if s.control then table.insert(d.cars, s.control) end
  if not (s.car and s.control) then return fail(run, tb, 11, "Ernter oder Gegenprobe-Auto ließ sich nicht erzeugen") end
  s.belts = belts
  s.pos_car = copy_pos(s.car.position)
  s.pos_control = copy_pos(s.control.position)
  return S11_TICKS
end

local function s11_check(run, tb, d)
  local s = d.s11
  if not (valid(s.car) and valid(s.control)) then return fail(run, tb, 11, "Ernter oder Auto weg") end
  local moved = tb.distance(s.car.position, s.pos_car)
  local control = tb.distance(s.control.position, s.pos_control)
  local immunity = read(function() return s.car.prototype.has_belt_immunity end)
  -- Laufen die Bänder nicht oder nimmt das Band das Vanilla-Auto nicht mit, hieße „Weg 0“ nichts.
  if control < 0.5 or s.belts < S11_BELTS then
    return fail(run, tb, 11, string.format("nicht prüfbar: Gegenprobe-Auto %.2f Kacheln, %d von %d Bändern (Ernter Weg %.3f, has_belt_immunity %s)",
      control, s.belts, S11_BELTS, moved, tostring(immunity)))
  end
  local failed = {}
  check(failed, moved < 0.01, "Weg 0")
  return verdict(run, tb, 11, "Ernter auf laufendem Band", failed, string.format(
    "%d Bänder, 5 s: Ernter Weg %.3f Kacheln (%s, has_belt_immunity %s); Gegenprobe Vanilla-Auto %.2f Kacheln",
    s.belts, moved, flags_text(s.car), tostring(immunity), control))
end

-- Schritt 12: Zustandstabelle (Plan 4.3): jede Eingabe in jedem Zustand, je Feld ein eigener Ernter.
-- Zellen mit Annahme (Spalte docked, Zeile Andock-Takt) liegen auf Fels ±7, ebenso deploying×Taste ohne
-- Annahme (der Abbruch muss minable_flag auf true werten). In der Zeile Teleport/Klon steht der Ernter auf
-- Sand, Teleportziel (Mitte + (3, -3.5)) und Klon (Mitte + (0, 4.5)) auf Fels. So ändert sich minable_flag
-- durch die Eingabe; gelesen wird direkt danach, bevor ein 60-Tick-Takt nachwerten kann. Die übrigen Zellen
-- liegen auf Sand. Dazu drei Fälle mobile×Taste, die nur einen Hinweis geben dürfen (kein Spice im Feld,
-- in Fahrt, nicht auf Arrakis), je mit eigenem Ernter (Spalte 6 und die Ablage-Oberfläche).
-- Zeitplan ab Schrittbeginn: deployed- und packing-Zellen bauen sofort auf (packing packt ein, sobald
-- aufgebaut), docked-Zellen docken in 3 s an, deploying-Zellen entstehen bei 450, Eingaben bei 500 (T),
-- mobile×Andock-Takt entsteht bei T; Prüfung bei T + 2, die Zeile Andock-Takt bei T + 200.

local T12_STATES = {"mobile", "deploying", "deployed", "packing", "docked"}
local T12_INPUTS =
{
  {key = "toggle", label = "Taste"},
  {key = "dock", label = "Andock-Takt"},
  {key = "death", label = "Tod"},
  {key = "teleport", label = "Teleport/Klon"}
}
local T12_EXPECT =
{
  toggle = {mobile = "deploying", deploying = "mobile", deployed = "packing", packing = "packing", docked = "mobile"},
  dock = {mobile = "docked", deploying = "deploying", deployed = "deployed", packing = "packing", docked = "docked"},
  death = {mobile = "weg", deploying = "weg", deployed = "weg", packing = "weg", docked = "weg"},
  teleport = {mobile = "mobile", deploying = "mobile", deployed = "mobile", packing = "mobile", docked = "mobile"}
}
local T12_TOGGLE_RETURN = {mobile = true, deploying = true, deployed = true, packing = false, docked = true}
local T12_SPACING = 20
local T12_LATE_DEPLOY = 450
local T12_INPUT = 500
local T12_DOCK_CHECK = 200
-- mobile×Taste, nur Hinweis: key = erwarteter Grund aus harvester.deploy.
local T12_HINTS =
{
  {key = "no-spice", label = "ohne Spice im Feld"},
  {key = "moving", label = "in Fahrt"},
  {key = "not-allowed", label = "nicht auf Arrakis"}
}
local T12_HINT_SPEED = 0.02               -- Kacheln je Tick, im selben Tick vor der Taste gesetzt
local T12_HOLD_SLOT = {x = 40, y = -30}   -- Ablage-Oberfläche, abseits der Stellplätze aus T3 und T9

local function t12_spawn(run, tb, cell)
  local car = new_harvester(run, tb, at(cell.center, 0, -3.5), 3)
  cell.car = car
  if not car then
    cell.error = "Ernter ließ sich nicht erzeugen"
    return
  end
  cell.un = car.unit_number
  if cell.state == "deploying" or cell.state == "deployed" or cell.state == "packing" then
    cell.deploy_ok = harvester.toggle(car, nil)
  end
end

-- packing-Zellen: einpacken, sobald aufgebaut.
local function t12_pack_ready(s)
  for _, cell in ipairs(s.table_cells) do
    if cell.state == "packing" and not cell.packed and valid(cell.car) and state_of(cell.car) == "deployed" then
      cell.packed = true
      cell.pack_ok = harvester.toggle(cell.car, nil)
    end
  end
end

local function t12_evaluate(cell)
  local want = T12_EXPECT[cell.input][cell.state]
  local problems = {}
  if cell.error then table.insert(problems, cell.error) end
  if cell.pre ~= cell.state then table.insert(problems, "Ausgangszustand " .. tostring(cell.pre)) end
  local minable_pre = (cell.state == "mobile" or cell.state == "docked") and cell.rock_before
  if cell.flag_pre ~= nil and cell.flag_pre ~= minable_pre then
    table.insert(problems, "minable_flag vorher " .. tostring(cell.flag_pre))
  end
  if cell.input == "toggle" then
    if cell.ret ~= T12_TOGGLE_RETURN[cell.state] then table.insert(problems, "toggle gab " .. tostring(cell.ret) .. " zurück") end
    if cell.state == "mobile" and cell.ret2 ~= false then table.insert(problems, "zweite Taste nicht entprellt") end
  elseif cell.input == "teleport" then
    if not (cell.clone_state == "mobile" and cell.clone_disabled == false) then
      table.insert(problems, "Klon " .. tostring(cell.clone_state) .. "/disabled " .. tostring(cell.clone_disabled))
    end
    if cell.clone_state and cell.clone_flag ~= true then
      table.insert(problems, "Klon auf Fels minable_flag " .. tostring(cell.clone_flag))
    end
    if cell.teleported ~= true then table.insert(problems, "Teleport ging nicht") end
  end
  local car = cell.car
  local target = valid(cell.intake) and cell.intake.proxy_target_entity
  local nozzle_target = valid(cell.nozzle) and cell.nozzle.proxy_target_entity
  if want == "weg" then
    if valid(car) then table.insert(problems, "Ernter noch da") end
    if cell.un and (storage.harvesters[cell.un] or storage.driven[cell.un] or storage.timers[cell.un]) then
      table.insert(problems, "storage nicht leer")
    end
    if target or nozzle_target then table.insert(problems, "Ziele nicht gelöscht") end
    local record = valid(cell.intake) and intake.get(cell.intake)
    if record and record.docked then table.insert(problems, "Annahme noch belegt") end
  elseif not valid(car) then
    table.insert(problems, "Ernter weg")
  else
    local state = state_of(car)
    if state ~= want then table.insert(problems, "Zustand " .. state .. " statt " .. want) end
    local locked = want ~= "mobile"
    if car.disabled_by_script ~= locked then table.insert(problems, "disabled_by_script " .. tostring(car.disabled_by_script)) end
    local minable = (want == "mobile" or want == "docked") and cell.rock_after
    if car.minable_flag ~= minable then table.insert(problems, "minable_flag " .. tostring(car.minable_flag)) end
    if cell.flag_now ~= nil and cell.flag_now ~= minable then
      table.insert(problems, "minable_flag direkt nach der Eingabe " .. tostring(cell.flag_now))
    end
    if valid(cell.intake) then
      local function on(entity)
        return entity and entity.unit_number == car.unit_number
      end
      if want == "docked" then
        if not (on(target) and on(nozzle_target)) then table.insert(problems, "Ziele nicht gesetzt") end
      elseif target or nozzle_target then
        table.insert(problems, "Ziele noch gesetzt")
      end
    end
  end
  cell.ok = #problems == 0
  cell.after = valid(car) and state_of(car) or "weg"
  cell.problems = table.concat(problems, ", ")
end

-- mobile×Taste mit nur Hinweis: false, bleibt mobile und entsperrt, keine Uhr, richtiger Grund.
local function t12_evaluate_hint(cell)
  local problems = {}
  if cell.error then table.insert(problems, cell.error) end
  if cell.ret ~= false then table.insert(problems, "toggle gab " .. tostring(cell.ret) .. " zurück") end
  if cell.state_after ~= "mobile" then table.insert(problems, "Zustand " .. tostring(cell.state_after)) end
  if cell.disabled_after ~= false then table.insert(problems, "disabled_by_script " .. tostring(cell.disabled_after)) end
  if cell.timer ~= false then table.insert(problems, "Uhr läuft " .. tostring(cell.timer)) end
  if cell.reason ~= cell.key then table.insert(problems, "Grund " .. tostring(cell.reason) .. " statt " .. cell.key) end
  cell.ok = #problems == 0
  cell.problems = table.concat(problems, ", ")
end

-- Ernter für die Hinweis-Fälle; not-allowed steht auf der Ablage-Oberfläche (harvest_allowed = false).
local function t12_hint_setup(run, tb, s, base)
  local surface = tb.surface()
  s.hint_cells = {}
  for i, hint in ipairs(T12_HINTS) do
    local cell = {key = hint.key, label = "mobile×Taste " .. hint.label}
    local where, center = surface, at(base, 5 * T12_SPACING, (i - 1) * T12_SPACING)
    if hint.key == "not-allowed" then
      local ok, hold = pcall(tb.hold_surface)
      where = ok and hold or nil
      center = T12_HOLD_SLOT
      if where then
        s.hold_name = where.name
        s.hold_area = {{center.x - 8, center.y - 8}, {center.x + 8, center.y + 8}}
        for _, entity in pairs(where.find_entities_filtered{area = s.hold_area}) do
          if entity.valid and entity.type ~= "character" then entity.destroy() end
        end
      end
    end
    if where then
      if hint.key ~= "no-spice" then place_spice(where, center.x - 1, center.y - 5, center.x + 1, center.y - 3, 5000) end
      cell.car = new_harvester(run, tb, at(center, 0, -3.5), 3, nil, where)
    end
    if valid(cell.car) then
      cell.where = cell.car.surface.name .. " " .. pos_text(tb, cell.car.position)
    else
      cell.error = where and "Ernter ließ sich nicht erzeugen" or "Ablage-Oberfläche fehlt"
    end
    table.insert(s.hint_cells, cell)
  end
end

-- Taste an den Hinweis-Ernter, Grund über harvester.deploy (ohne Entprellen, gleicher Zustand), dann entfernen.
-- Den Spice auf der Ablage-Oberfläche räumt der Schritt wieder ab.
local function t12_hint_input(s)
  for _, cell in ipairs(s.hint_cells) do
    local car = cell.car
    if valid(car) then
      if cell.key == "moving" then car.speed = T12_HINT_SPEED end
      cell.speed = math.abs(car.speed) * 60
      cell.ret = harvester.toggle(car, nil)
      local h = harvester.get(car)
      if h then
        local ok, reason = harvester.deploy(h)
        cell.reason = ok and "aufgebaut" or reason
      end
      if cell.key == "moving" then car.speed = 0 end
      cell.state_after = state_of(car)
      cell.disabled_after = car.disabled_by_script
      cell.timer = storage.timers[car.unit_number] ~= nil
      car.destroy{raise_destroy = true}
    end
    t12_evaluate_hint(cell)
  end
  local hold = s.hold_name and game.get_surface(s.hold_name)
  if hold then
    for _, resource in pairs(hold.find_entities_filtered{area = s.hold_area, name = SPICE}) do resource.destroy() end
  end
end

local function s12_setup(run, tb, d)
  local s = d.s12
  local base = d.pos.s12
  local surface = tb.surface()
  local force = force_of(run, tb)
  tb.watch(run, nil, at(base, 40, -12))
  s.table_cells = {}
  s.start = game.tick
  for row, input in ipairs(T12_INPUTS) do
    for col, state in ipairs(T12_STATES) do
      local center = at(base, (col - 1) * T12_SPACING, (row - 1) * T12_SPACING)
      local cell = {state = state, input = input.key, label = state .. "×" .. input.label, center = center}
      cell.rock = state == "docked" or input.key == "dock"
      local rock_only = state == "deploying" and input.key == "toggle"
      if cell.rock or rock_only then
        tb.fill({{center.x - 7, center.y - 7}, {center.x + 7, center.y + 7}}, ROCK, surface)
      end
      if input.key == "teleport" then
        tb.fill({{center.x + 1, center.y - 6}, {center.x + 6, center.y - 1}}, ROCK, surface)
        tb.fill({{center.x - 3, center.y + 2}, {center.x + 3, center.y + 7}}, ROCK, surface)
      end
      -- Fels unter dem Ernter vor und nach der Eingabe (Sollwert für minable_flag).
      cell.rock_before = cell.rock or rock_only
      cell.rock_after = cell.rock_before or input.key == "teleport"
      if cell.rock then
        cell.intake = create(run, tb, {name = INTAKE, position = center, force = force, raise_built = true})
        cell.nozzle = create(run, tb, {name = NOZZLE, position = at(center, 1.5, 1.5), force = force, raise_built = true})
        if not (cell.intake and cell.nozzle) then cell.error = "Annahme oder Stutzen fehlt" end
      end
      if state == "deploying" or state == "deployed" or state == "packing" or (state == "mobile" and input.key == "toggle") then
        place_spice(surface, center.x - 1, center.y - 5, center.x + 1, center.y - 3, 5000)
      end
      if state == "deploying" then
        cell.late = "deploy"
      elseif state == "mobile" and input.key == "dock" then
        cell.late = "input"
      else
        t12_spawn(run, tb, cell)
      end
      table.insert(s.table_cells, cell)
    end
  end
  t12_hint_setup(run, tb, s, base)
  tb.trace(run, "12) " .. #s.table_cells .. " Zellen aufgebaut bei " .. pos_text(tb, base) .. " (5 Zustände × 4 Eingaben, Abstand 20), dazu "
    .. #s.hint_cells .. " Hinweis-Fälle")
  return 1
end

local function s12_prepare(run, tb, d)
  local s = d.s12
  t12_pack_ready(s)
  if game.tick - s.start < T12_LATE_DEPLOY then return "poll" end
  for _, cell in ipairs(s.table_cells) do
    if cell.late == "deploy" then t12_spawn(run, tb, cell) end
  end
  return 1
end

local function s12_input(run, tb, d)
  local s = d.s12
  t12_pack_ready(s)
  if game.tick - s.start < T12_INPUT then return "poll" end
  for _, cell in ipairs(s.table_cells) do
    if cell.late == "input" then t12_spawn(run, tb, cell) end
    cell.pre = state_of(cell.car)
    cell.flag_pre = read(function() return cell.car.minable_flag end)
  end
  for _, cell in ipairs(s.table_cells) do
    local car = cell.car
    if valid(car) then
      if cell.input == "toggle" then
        cell.ret = harvester.toggle(car, nil)
        if cell.state == "mobile" then cell.ret2 = harvester.toggle(car, nil) end
        cell.flag_now = read(function() return car.minable_flag end)
      elseif cell.input == "death" then
        cell.died = car.die()
      elseif cell.input == "teleport" then
        local ok, clone = pcall(function() return car.clone{position = at(cell.center, 0, 4.5)} end)
        if ok and clone then
          cell.clone_state = state_of(clone)
          cell.clone_disabled = clone.disabled_by_script
          cell.clone_flag = clone.minable_flag
          clone.destroy{raise_destroy = true}
        end
        cell.teleported = car.teleport(at(cell.center, 3, -3.5), nil, true)
        -- Direkt lesen: der 60-Tick-Takt würde eine fehlende Neuwertung sonst nachholen.
        cell.flag_now = read(function() return car.minable_flag end)
      end
    end
  end
  t12_hint_input(s)
  return 2
end

local function s12_check_now(run, tb, d)
  for _, cell in ipairs(d.s12.table_cells) do
    if cell.input ~= "dock" then t12_evaluate(cell) end
  end
  return T12_DOCK_CHECK - 2
end

local function s12_check_dock(run, tb, d)
  local s = d.s12
  local per_input, total, wrong = {}, 0, {}
  for _, cell in ipairs(s.table_cells) do
    if cell.input == "dock" then t12_evaluate(cell) end
    per_input[cell.input] = (per_input[cell.input] or 0) + (cell.ok and 1 or 0)
    if cell.ok then total = total + 1 else table.insert(wrong, cell.label .. " (" .. cell.problems .. ")") end
    tb.trace(run, string.format("12) %s: vorher %s (minable_flag %s), nachher %s (direkt %s), erwartet %s → %s%s", cell.label,
      tostring(cell.pre), tostring(cell.flag_pre), cell.after, tostring(cell.flag_now), T12_EXPECT[cell.input][cell.state],
      cell.ok and "OK" or "FEHLER", cell.ok and "" or (": " .. cell.problems)))
  end
  local hints_ok = 0
  for _, cell in ipairs(s.hint_cells) do
    if cell.ok then hints_ok = hints_ok + 1 else table.insert(wrong, cell.label .. " (" .. cell.problems .. ")") end
    tb.trace(run, string.format("12) %s auf %s, Tempo %s Kacheln/s: toggle %s, Grund %s, Zustand %s → %s%s", cell.label,
      cell.where or "–", tb.num(cell.speed, 2), tostring(cell.ret), tostring(cell.reason), tostring(cell.state_after),
      cell.ok and "OK" or "FEHLER", cell.ok and "" or (": " .. cell.problems)))
  end
  local parts = {}
  for _, input in ipairs(T12_INPUTS) do
    table.insert(parts, string.format("%s %d/%d", input.label, per_input[input.key] or 0, #T12_STATES))
  end
  local debounce = "–"
  for _, cell in ipairs(s.table_cells) do
    if cell.input == "toggle" and cell.state == "mobile" then debounce = cell.ret2 == false and "ja" or "nein" end
  end
  return verdict(run, tb, 12, "Zustandstabelle", wrong, string.format("%d/%d Felder stimmen (%s); Entprellen %s; "
    .. "Taste nur mit Hinweis (kein Spice, in Fahrt, nicht auf Arrakis) %d/%d",
    total, #s.table_cells, table.concat(parts, ", "), debounce, hints_ok, #s.hint_cells))
end

local T13_STEPS =
{
  {s1_start, s1_wait, s1_measure},
  {s2_start, s2_drive, s2_check},
  {s3_fill, s3_pause, s3_clear, s3_check},
  {s4_pack, s4_wait, s4_check},
  {s5_start, s5_wait},
  {s6_build, s6_wait_dock, s6_flow, s6_stay, s6_away, s6_redock},
  {s7_destroy, s7_after, s7_wait_dock, s7_check},
  {s8_start, s8_clone, s8_teleport, s8_check},
  {s9_start, s9_check},
  {s10_run},
  {s11_start, s11_check},
  {s12_setup, s12_prepare, s12_input, s12_check_now, s12_check_dock}
}

local function t13_summary(run)
  local ok, wrong = 0, {}
  for number = 1, #T13_STEPS do
    local result = run.data.results[number]
    if result == "OK" then ok = ok + 1 else table.insert(wrong, tostring(number)) end
  end
  local text = string.format("%d/%d Schritte OK", ok, #T13_STEPS)
  if #wrong > 0 then text = text .. ", FEHLER in " .. table.concat(wrong, ", ") end
  return text
end

local function t13_start(run, tb)
  local d = run.data
  local origin = tb.area(run.id)
  tb.prepare(origin, T13_HALF)
  local surface = tb.surface()
  d.pos = {}
  for key, offset in pairs(T13_PLACES) do d.pos[key] = at(origin, offset.x, offset.y) end
  tb.fill({{d.pos.s4.x - 6, d.pos.s4.y - 6}, {d.pos.s4.x + 6, d.pos.s4.y + 6}}, ROCK, surface)
  tb.fill({{d.pos.s6.x - 8, d.pos.s6.y - 8}, {d.pos.s6.x + 8, d.pos.s6.y + 8}}, ROCK, surface)
  d.cars, d.drivers, d.results = {}, {}, {}
  for number = 1, #T13_STEPS do d["s" .. number] = {} end
  if not (storage.harvesters and storage.intakes and storage.reg) then
    tb.log(run, "FEHLER", "storage des Laufzeitcodes fehlt (scripts/migrate.lua init nicht gelaufen)")
    tb.finish(run, "abgebrochen (kein storage)")
    return
  end
  if not terrain.harvest_allowed(surface) then
    tb.log(run, "FEHLER", "terrain.harvest_allowed(" .. surface.name .. ") = false: der Laufzeitcode erntet hier nicht")
    tb.finish(run, "abgebrochen (Prüfstand-Fläche nicht erlaubt)")
    return
  end
  tb.log(run, "INFO", "Zwölf Schritte mit dem echten Laufzeitcode (Ernter, Annahme, Stutzen, Migration), Dauer etwa 2 min."
    .. " Je Schritt eine OK/FEHLER-Zeile, Einzelwerte in der Datei.")
  tb.log(run, "INFO", "Nicht automatisch prüfbar (Abnahme durch Max, Plan 8): Fenster und Knopf, Taste Umschalt+H,"
    .. " Abbauen von Hand und per Roboter, Speichern/Laden, Mehrspieler, Upgrade eines 0.4.x-Spielstands.")
  d.step, d.phase, d.wait_until = 1, 1, game.tick + 30
end

local function t13_tick(run, tb)
  local d = run.data
  if not d.step or game.tick < d.wait_until then return end
  local step = T13_STEPS[d.step]
  if not step then
    d.step = nil
    tb.finish(run, t13_summary(run))
    return
  end
  local phase = step[d.phase]
  if not phase then
    if not d.results[d.step] then fail(run, tb, d.step, "keine Ergebniszeile (Prüfstand-Fehler)") end
    d.step, d.phase, d.entered = d.step + 1, 1, nil
    return
  end
  d.entered = d.entered or game.tick
  local ok, result = pcall(phase, run, tb, d)
  if not ok then
    fail(run, tb, d.step, "Skriptfehler: " .. tostring(result))
    result = "end"
  end
  if result == "poll" then return end
  d.entered = nil
  if result == "end" then
    d.step, d.phase = d.step + 1, 1
    d.wait_until = game.tick + T13_GAP
  else
    d.phase = d.phase + 1
    d.wait_until = game.tick + (type(result) == "number" and result or 1)
  end
end

-- Aufräumen: Dummy-Fahrer weg, Ernter mit Ereignis entfernen (Alarme weg, storage leer). Der Rest bleibt stehen.
local function t13_cleanup(run, tb)
  local d = run.data
  for _, driver in pairs(d.drivers or {}) do
    if valid(driver) then driver.destroy() end
  end
  for _, car in pairs(d.cars or {}) do
    if valid(car) then car.destroy{raise_destroy = true} end
  end
end

-- T2b Ernter: Fahrphysik --------------------------------------------------------------------------
-- Ein eingetragener spice-harvester mit Dummy-Fahrer fährt nacheinander die Läufe aus T2B_RUNS. Der Fahrer
-- sitzt schon beim Eintragen (script_raised_built), deshalb steht der Ernter wie nach dem Einsteigen sofort
-- in storage.driven (Tempo-Deckel jeden Tick, Ausgleich alle 10 Ticks). Der Vergleichsernter entsteht ohne
-- Ereignis und wird nie eingetragen: kein Ausgleich, kein Deckel.
-- Messung je Tick im Prüfstand-Tick: speed (nach dem Deckel des Laufzeitcodes, der als Bibliothek vor dem
-- Prüfstand läuft), Schritt am Boden (Positionsänderung, 1/256-Raster), ab 5 s Mittelwert und Bodentempo.
-- Weil speed nach dem Deckel gelesen wird, zählt jeder Eingriff des Deckels (speed genau 1.45): Er heißt, das
-- Tempo war davor über 1.5. In der ersten Sekunde ist er erlaubt (neuer Brennstoff, Ausgleich folgt im
-- 10-Tick-Takt), danach ist er ein FEHLER.

local T2B_BACK = 30
local T2B_PAUSE = 30
local T2B_WINDOW = 5 * 60
local T2B_NEGATIVE = {x = -1000, y = -1000}
local T2B_DIRS =
{
  O = {orientation = 0.25, x = 1, y = 0},
  W = {orientation = 0.75, x = -1, y = 0},
  N = {orientation = 0, x = 0, y = -1},
  S = {orientation = 0.5, x = 0, y = 1},
  NO = {orientation = 0.125, x = math.sqrt(0.5), y = -math.sqrt(0.5)},
  SW = {orientation = 0.625, x = -math.sqrt(0.5), y = math.sqrt(0.5)}
}
local T2B_RUNS =
{
  {key = "coal", label = "Kohle", fuel = "coal", count = 10, dir = "O", ticks = 15 * 60},
  {key = "solid", label = "Festbrennstoff", fuel = "solid-fuel", count = 10, dir = "O", ticks = 15 * 60},
  {key = "rocket", label = "Raketentreibstoff", fuel = "rocket-fuel", count = 3, dir = "O", ticks = 15 * 60},
  {key = "nuclear", label = "Atomtreibstoff", fuel = "nuclear-fuel", count = 1, dir = "O", ticks = 15 * 60},
  {key = "legendary", label = "Raketentreibstoff legendär", fuel = "rocket-fuel", quality = "legendary", count = 3, dir = "O", ticks = 15 * 60},
  {key = "plain", label = "Raketentreibstoff ohne Ausgleich und Deckel", fuel = "rocket-fuel", count = 3, dir = "O", ticks = 15 * 60, raw = true},
  {key = "west", label = "Raketentreibstoff nach W", fuel = "rocket-fuel", count = 3, dir = "W", ticks = 10 * 60},
  {key = "north", label = "Raketentreibstoff nach N", fuel = "rocket-fuel", count = 3, dir = "N", ticks = 10 * 60},
  {key = "south", label = "Raketentreibstoff nach S", fuel = "rocket-fuel", count = 3, dir = "S", ticks = 10 * 60},
  {key = "northeast", label = "Raketentreibstoff schräg nach NO", fuel = "rocket-fuel", count = 3, dir = "NO", ticks = 10 * 60},
  {key = "southwest", label = "Raketentreibstoff schräg nach SW", fuel = "rocket-fuel", count = 3, dir = "SW", ticks = 10 * 60},
  {key = "neg_east", label = "negative Koordinaten nach O", fuel = "rocket-fuel", count = 3, dir = "O", ticks = 10 * 60, negative = true},
  {key = "neg_west", label = "negative Koordinaten nach W", fuel = "rocket-fuel", count = 3, dir = "W", ticks = 10 * 60, negative = true},
  {key = "full", label = "voller Laderaum", fuel = "rocket-fuel", count = 3, dir = "O", ticks = 15 * 60, full = true}
}

-- Ausgleich laut Plan 4.6: min(1, 1/a), a = Beschleunigung des Brennstoffs plus Qualitätsbonus.
local function expected_modifier(fuel, quality)
  local item = prototypes.item[fuel]
  local level = quality and prototypes.quality[quality] and prototypes.quality[quality].level or 0
  local a = item.fuel_acceleration_multiplier + level * item.fuel_acceleration_multiplier_quality_bonus
  if a <= 0 then return 1, a end
  return math.min(1, 1 / a), a
end

local function t2b_park(d, which)
  return which == "raw" and at(d.track_center, -40, 50) or at(d.track_center, 40, 50)
end

local function t2b_cars(d, spec)
  if spec.raw then return d.raw, d.raw_driver, d.car end
  return d.car, d.driver, d.raw
end

local function t2b_summary(run)
  local d = run.data
  local ok, wrong, peak, ground = 0, 0, 0, 0
  for _, spec in ipairs(T2B_RUNS) do
    local r = d.results[spec.key]
    if r and not spec.raw and r.ok ~= nil then
      if r.ok then ok = ok + 1 else wrong = wrong + 1 end
      if r.max > peak then peak = r.max end
      if r.ground and r.ground > ground then ground = r.ground end
    end
  end
  local raw_result = d.results.plain
  return string.format("%d Läufe OK, %d FEHLER; mit Ausgleich höchstens speed %.2f, Bodentempo %.2f Kacheln/s; ohne Ausgleich und Deckel %s",
    ok, wrong, peak, ground, raw_result and raw_result.max and string.format("speed %.2f, Bodentempo %.2f", raw_result.max, raw_result.ground or 0) or "–")
end

local function t2b_finish(run, tb)
  local d = run.data
  d.phase = "done"
  local cars = {d.car, d.raw}
  for i = 1, 2 do
    local car = cars[i]
    if valid(car) then
      gas(car, nil, false)
      pcall(function() car.speed = 0 end)
    end
  end
  local hits, late = 0, 0
  for _, r in pairs(d.results) do
    hits = hits + (r.cap_hits or 0)
    late = late + (r.cap_late or 0)
  end
  tb.log(run, "INFO", "Deckel-Rücksetzwert 1.45 im Prüfstand-Tick gesehen: " .. hits .. "×, davon ab 1 s " .. late .. "×"
    .. (hits > 0 and " (speed wird also nach dem Deckel gelesen; ab 1 s ist jeder Eingriff im Lauf mit Ausgleich ein FEHLER)"
      or " (der Deckel griff nicht ein oder speed wird vor ihm gelesen; dann ist die Spitze das Tempo vor dem Deckel)"))
  tb.finish(run, t2b_summary(run))
end

local function t2b_next(run, tb)
  local d = run.data
  d.run_index = d.run_index + 1
  if d.run_index > #T2B_RUNS then
    t2b_finish(run, tb)
    return
  end
  d.phase = "wait"
  d.next_tick = game.tick + T2B_PAUSE
end

-- Ernter für einen Lauf herrichten: anhalten, an den Start, Brennstoff und Brenner neu, Laderaum leer oder voll.
local function t2b_reset(car, start, orientation, spec)
  pcall(function() car.speed = 0 end)
  local moved = car.teleport(start)
  pcall(function() car.orientation = orientation end)
  pcall(function() car.speed = 0 end)
  local inventory = car.get_fuel_inventory()
  if inventory then inventory.clear() end
  local burner = car.burner
  if burner then
    -- Rest zuerst auf 0: falls currently_burning = nil nicht geht, lädt der Brenner trotzdem den neuen Brennstoff.
    pcall(function() burner.remaining_burning_fuel = 0 end)
    pcall(function() burner.currently_burning = nil end)
    pcall(function() burner.heat = 0 end)
  end
  local trunk = car.get_inventory(defines.inventory.car_trunk)
  trunk.clear()
  if spec.full then trunk.insert{name = SPICE, count = #trunk * prototypes.item[SPICE].stack_size} end
  local inserted = 0
  if inventory then
    inserted = inventory.insert{name = spec.fuel, count = spec.count, quality = spec.quality or "normal"}
  end
  return moved, inserted
end

local function t2b_begin(run, tb)
  local d = run.data
  local spec = T2B_RUNS[d.run_index]
  if spec.quality and not quality_exists(spec.quality) then
    tb.log(run, "INFO", spec.label .. ": Qualität " .. spec.quality .. " gibt es nicht, Lauf entfällt")
    return t2b_next(run, tb)
  end
  local car, _, other = t2b_cars(d, spec)
  if not (valid(car) and valid(other)) then
    tb.log(run, "FEHLER", "Ernter für den Lauf fehlt")
    return t2b_finish(run, tb)
  end
  local center = spec.negative and T2B_NEGATIVE or d.track_center
  if (spec.negative and not d.watching_negative) or (not spec.negative and d.watching_negative) then
    d.watching_negative = spec.negative or nil
    tb.watch(run, nil, at(center, 12, 12))
  end
  other.teleport(t2b_park(d, spec.raw and "main" or "raw"))
  local dir = T2B_DIRS[spec.dir]
  local start = {x = center.x - dir.x * T2B_BACK, y = center.y - dir.y * T2B_BACK}
  local moved, inserted = t2b_reset(car, start, dir.orientation, spec)
  if not moved or inserted == 0 then
    tb.log(run, "FEHLER", string.format("%s: Start ging nicht (Teleport %s, %d %s eingelegt)", spec.label, tostring(moved), inserted, spec.fuel))
    return t2b_next(run, tb)
  end
  d.cur =
  {
    start = game.tick,
    start_pos = copy_pos(car.position),
    last = copy_pos(car.position),
    max = 0,
    max_late = 0,
    max_step = 0,
    cap_hits = 0,
    cap_late = 0,
    sum = 0,
    n = 0
  }
  d.phase = "run"
  tb.trace(run, string.format("T2b %s: Start %s, Richtung %s, %d %s%s, Laderaum %d Spice, effectivity_modifier vorher %.3f",
    spec.label, pos_text(tb, car.position), spec.dir, inserted, spec.fuel, spec.quality and (" " .. spec.quality) or "",
    trunk_count(car), car.effectivity_modifier))
  gas(car, spec.raw and d.raw_driver or d.driver, true)
end

local function t2b_end(run, tb)
  local d = run.data
  local spec = T2B_RUNS[d.run_index]
  local car, driver = t2b_cars(d, spec)
  local cur = d.cur
  gas(car, driver, false)
  local window = (spec.ticks - T2B_WINDOW) / 60
  local ground = cur.pos5 and tb.distance(car.position, cur.pos5) / window or nil
  local mean = cur.n > 0 and cur.sum / cur.n or nil
  local distance = tb.distance(car.position, cur.start_pos)
  local modifier = car.effectivity_modifier
  local expected, a = 1, nil
  if not spec.raw then expected, a = expected_modifier(spec.fuel, spec.quality) end
  local burning = read(function()
    local pair = car.burner.currently_burning
    return pair and (pair.name.name .. "@" .. pair.quality.name)
  end) or "–"
  pcall(function() car.speed = 0 end)
  local result = {max = cur.max, ground = ground, mean = mean, cap_hits = cur.cap_hits, cap_late = cur.cap_late}
  local values = string.format("speed %s (Mittel ab 5 s), Spitze %.3f (ab 1 s %.3f), Bodentempo %s (Strecke ab 5 s), "
    .. "Schritt je Tick bis %d/256 (%.2f), Weg %.1f in %d s, Deckel %d× (ab 1 s %d×), brennt %s, effectivity_modifier %.3f",
    tb.num(mean, 3), cur.max, cur.max_late, tb.num(ground, 3), cur.max_step, cur.max_step * 60 / 256, distance,
    spec.ticks / 60, cur.cap_hits, cur.cap_late, burning, modifier)
  if spec.raw then
    local registered = harvester.get(car) ~= nil
    tb.log(run, "MESSUNG", spec.label .. " (nur gemessen, Ernter nicht eingetragen" .. (registered and ": DOCH EINGETRAGEN" or "")
      .. "): " .. values)
  else
    local failed = {}
    check(failed, cur.max_late <= CAP + 1e-6, "Spitze ab 1 s ≤ 1.5")
    check(failed, cur.cap_late == 0, "Deckel griff ab 1 s nie (Tempo vor dem Deckel ≤ 1.5)")
    check(failed, ground ~= nil and ground <= CAP, "Bodentempo ≤ 1.5")
    check(failed, math.abs(modifier - expected) <= 1e-3, "Ausgleich " .. string.format("%.3f", expected))
    result.ok = #failed == 0
    local text = spec.label .. " (" .. spec.dir .. (spec.negative and ", negative Koordinaten" or "") .. "): " .. values
      .. string.format(" (erwartet %.3f, a = %s)", expected, tb.num(a, 2))
    if #failed > 0 then text = text .. " | nicht erfüllt: " .. table.concat(failed, "; ") end
    tb.log(run, result.ok and "OK" or "FEHLER", text)
    if mean and (mean < 1.40 or mean > CAP) then
      tb.log(run, "INFO", spec.label .. ": speed im Mittel " .. tb.num(mean, 3) .. " statt etwa 1.45")
    end
  end
  d.results[spec.key] = result
  t2b_next(run, tb)
end

local function t2b_start(run, tb)
  local d = run.data
  local origin = tb.area(run.id)
  tb.prepare(origin, 70)
  tb.prepare(T2B_NEGATIVE, 45)
  d.track_center = copy_pos(origin)
  d.results = {}
  local surface = tb.surface()
  local force = force_of(run, tb)
  -- Ernter mit Ausgleich: erst der Fahrer, dann script_raised_built (wie Einsteigen: sofort im Tempo-Deckel).
  local car = surface.create_entity{name = NAME, position = t2b_park(d, "main"), force = force, orientation = 0.25}
  local raw = surface.create_entity{name = NAME, position = t2b_park(d, "raw"), force = force, orientation = 0.25}
  if not (car and raw) then
    tb.log(run, "FEHLER", "spice-harvester ließ sich nicht erzeugen")
    tb.finish(run, "abgebrochen (kein Ernter)")
    return
  end
  d.car, d.raw = car, raw
  d.driver = tb.dummy_driver(car)
  d.raw_driver = tb.dummy_driver(raw)
  script.raise_script_built{entity = car}
  local h = harvester.get(car)
  local driven = storage.driven and storage.driven[car.unit_number] ~= nil
  local seated = car.get_driver() ~= nil and raw.get_driver() ~= nil
  tb.log(run, (h and seated) and "INFO" or "FEHLER", string.format("Ernter Nr. %d eingetragen %s, im Tempo-Deckel %s; Vergleichsernter Nr. %d eingetragen %s; Dummy-Fahrer sitzen %s",
    car.unit_number, tostring(h ~= nil), tostring(driven), raw.unit_number, tostring(harvester.get(raw) ~= nil), tostring(seated)))
  tb.log(run, "INFO", #T2B_RUNS .. " Läufe je 10–15 s, Dauer etwa 3 min. Kriterium mit Ausgleich: ab 1 s Spitze ≤ 1.5 Kacheln/s"
    .. " und kein Eingriff des Tempo-Deckels, Bodentempo ≤ 1.5 Kacheln/s, effectivity_modifier = min(1, 1/a)."
    .. " speed wird nach dem Deckel des Laufzeitcodes gelesen; ein Eingriff heißt, das Tempo war davor über 1.5.")
  tb.watch(run, nil, at(d.track_center, 12, 12))
  d.run_index = 1
  d.phase = "wait"
  d.next_tick = game.tick + T2B_PAUSE
end

local function t2b_tick(run, tb)
  local d = run.data
  if d.phase == "done" then return end
  if d.phase == "wait" then
    if game.tick >= d.next_tick then t2b_begin(run, tb) end
    return
  end
  local spec = T2B_RUNS[d.run_index]
  local car, driver = t2b_cars(d, spec)
  if not valid(car) then
    tb.log(run, "FEHLER", "Der Ernter ist nicht mehr da.")
    return t2b_finish(run, tb)
  end
  local cur = d.cur
  local elapsed = game.tick - cur.start
  local speed = tb.speed_tps(car) or 0
  local position = copy_pos(car.position)
  local step = tb.distance(position, cur.last)
  cur.last = position
  if speed > cur.max then cur.max = speed end
  if elapsed > 60 and speed > cur.max_late then cur.max_late = speed end
  local units = math.floor(step * 256 + 0.5)
  if units > cur.max_step then cur.max_step = units end
  -- Genau der Rücksetzwert (als float gespeichert: Abweichung etwa 4e-8 Kacheln/s); natürliche Fahrt trifft ihn kaum.
  if math.abs(speed - RESET) < 2e-7 then
    cur.cap_hits = cur.cap_hits + 1
    if elapsed > 60 then cur.cap_late = cur.cap_late + 1 end
  end
  if elapsed == T2B_WINDOW then cur.pos5 = position end
  if elapsed > T2B_WINDOW then
    cur.sum = cur.sum + speed
    cur.n = cur.n + 1
  end
  if elapsed % 60 == 0 then
    tb.trace(run, string.format("T2b %s %d s: speed %.3f, Weg %.2f, Schritt %d/256", spec.label, elapsed / 60, speed,
      tb.distance(position, cur.start_pos), units))
  end
  if not d.probed and elapsed >= 60 then
    d.probed = true
    local moved = tb.distance(position, cur.start_pos)
    if moved < 0.05 and speed < 0.01 then
      tb.log(run, "FEHLER", "Skriptfahrt geht nicht: nach 1 s " .. tb.num(moved, 2) .. " Kacheln, Tempo " .. tb.num(speed, 2)
        .. " Kacheln/s; " .. flags_text(car))
      return t2b_finish(run, tb)
    end
  end
  if elapsed >= spec.ticks then
    return t2b_end(run, tb)
  end
  gas(car, driver, true)
end

local function t2b_cleanup(run, tb)
  local d = run.data
  local drivers, cars = {d.driver, d.raw_driver}, {d.car, d.raw}
  for i = 1, 2 do
    local driver, car = drivers[i], cars[i]
    if valid(driver) then driver.destroy() end
    if valid(car) then car.destroy{raise_destroy = true} end
  end
end

return
{
  T13 =
  {
    title = "Ernter: echter Code",
    timeout = 5 * 60 * 60,
    interactive = false,
    confirm = nil,
    start = t13_start,
    tick = t13_tick,
    cleanup = t13_cleanup
  },
  T2b =
  {
    title = "Ernter: Fahrphysik",
    timeout = 6 * 60 * 60,
    interactive = false,
    confirm = nil,
    start = t2b_start,
    tick = t2b_tick,
    cleanup = t2b_cleanup
  }
}
