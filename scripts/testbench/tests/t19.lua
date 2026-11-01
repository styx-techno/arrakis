-- T19 Jagd: echter Code: Prüfstand-Test (aus t_jagd.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_jagd.lua.

local common = require("scripts.testbench.gemeinsam_jagd")
local harvester = require("scripts.harvester")
local intake = require("scripts.intake")
local terrain = require("scripts.terrain")
local vibration_lib = require("scripts.vibration")
local worms_lib = require("scripts.worms")
local INTAKE = common.INTAKE
local ROCK = common.ROCK
local SAND = common.SAND
local ERUPTION = common.ERUPTION
local WORM_FORCE = common.WORM_FORCE
local BITE_SETTING = common.BITE_SETTING
local WARN_TICKS = common.WARN_TICKS
local TEACH_TICKS = common.TEACH_TICKS
local REST_MIN = common.REST_MIN
local REST_MAX = common.REST_MAX
local MAX_HUNTS = common.MAX_HUNTS
local GRACE_ORNITHOPTER = common.GRACE_ORNITHOPTER
local valid = common.valid
local copy_pos = common.copy_pos
local pos_text = common.pos_text
local read = common.read
local check = common.check
local near = common.near
local copy = common.copy
local to_mid = common.to_mid
local box_of = common.box_of
local inside = common.inside
local tiles = common.tiles
local gas = common.gas
local render_ok = common.render_ok
local car_state = common.car_state
local status_name = common.status_name
local force_named = common.force_named
local heat_at = common.heat_at
local nine_zero = common.nine_zero
local hunt_list = common.hunt_list
local abort_hunts = common.abort_hunts
local foreign_regular = common.foreign_regular
local worm_hostile = common.worm_hostile
local hunt_text = common.hunt_text
local make = common.make
local new_harvester = common.new_harvester
local new_vehicle = common.new_vehicle
local new_flyer = common.new_flyer
local driver_of = common.driver_of
local keep_key = common.keep_key
local again = common.again
local verdict = common.verdict
local fail = common.fail
local lanes_init = common.lanes_init
local lane_step = common.lane_step
local summary = common.summary
local isolate_cleanup = common.isolate_cleanup
local timeline = common.timeline
local check_sign = common.check_sign
local isolate_start = common.isolate_start
local heat_chunk = common.heat_chunk
local deploy = common.deploy

local flyer_lib = require("scripts.flyer")
local ORNITHOPTER_TECH = "arrakis-ornithopter"
local T19_FORCE = "arrakis-t19"
-- Force für den Force-Wechsel in T19 Schritt 5 e; geht im cleanup in arrakis-t19 auf.
local T19_OTHER_FORCE = "arrakis-t19b"
local SEARCH_TICKS = 600
local GRACE_LANDING = 108000
local PAUSE_TICKS = 36000
local HEAVY_SHARE = 0.1
local BITE_RADIUS = 4

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

-- Grün (sichere Jagd, scripts/worms.lua): Grünanteil über dem Rotanteil.
local function is_green(object)
  if not render_ok(object) then return false end
  local color = read(function() return object.color end)
  if type(color) ~= "table" then return false end
  local r, g = color.r or color[1] or 0, color.g or color[2] or 0
  return g > r
end

local function fuel_items(entity)
  local inventory = valid(entity) and entity.get_fuel_inventory()
  return inventory and inventory.get_item_count() or 0
end

-- Eruptionen um position (Explosion, kurz sichtbar), für MESSUNG.
local function eruptions_at(surface, position, radius)
  return #surface.find_entities_filtered{name = ERUPTION, position = position, radius = radius or 2}
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
  -- Wrack des Ernters aus seinem Prototyp (ab 0.8.5 big-remnants statt tank-remnants).
  local proto = prototypes.entity[s.car.name]
  s.wreck = proto and proto.corpses and next(proto.corpses) or "big-remnants"
  s.remnants0 = surface.count_entities_filtered{name = s.wreck, area = s.box}
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
  local remnants = surface.count_entities_filtered{name = s.wreck, area = s.box}
  check(failed, remnants == s.remnants0 + 1, s.wreck .. " " .. s.remnants0 .. " → " .. remnants .. " statt eine mehr")
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
  s.flyer = new_flyer(run, tb, s, c, {force = d.force, pilot = true, rocket = 4})
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
  -- 0.11.0: Der Wurm lauert jetzt so lange, wie der Sektor ruht. Was das Lauern tut, prüft T23 Schritt 10; hier geht es
  -- wie bisher nur um die Wärme, deshalb vergisst der Test den lauernden Wurm vor dem Wiederaufbau.
  check(failed, worms_lib.lurking(surface.index, hunt.sector_key) == vibration_lib.resting(surface.index, hunt.sector_key),
    "Wurm lauert nicht so lange, wie der Sektor ruht")
  worms_lib.clear_lurk(surface.index)
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
  p.flyer = new_flyer(run, tb, s, c, {force = d.force, pilot = true, rocket = 4})
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
  -- Ohne Wurm wie 0.7.0 (docs/protokolle/plan-3d2.md 6): Biss genau bei 0; den Wurm prüft T21.
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

return
{
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
  }
}
