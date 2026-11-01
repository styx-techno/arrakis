-- T35 Ernter Mk2 0.15.1 (docs/plan-3i.md 3, Max' Wahl 1b 2b 3b 4a): Prototypen (Laderaum 60, Leben ×1,5, Rezept mit
-- Prozessoren, Forschung 500 Einheiten), Förderung ×1,5 und Vibration ×0,8 neben einem Mk1, Beute schaltet nichts frei, Tragen mit dem Ornithopter (Lastbild getönt), Leitstelle gibt Mk2 zuerst aus und lagert ihn
-- ein, Biss „schwer beschädigt“ wie beim Mk1. Gemeinsame Helfer: scripts/testbench/gemeinsam_fleet.lua (T23-Fläche).

local common = require("scripts.testbench.gemeinsam_fleet")
local harvester = require("scripts.harvester")
local flyer_lib = require("scripts.flyer")
local fleet = require("scripts.fleet")
local worms_lib = require("scripts.worms")
local vibration_lib = require("scripts.vibration")
local sandworm_lib = require("scripts.sandworm")
local NAME = common.NAME
local MK2 = common.MK2
local SPICE = common.SPICE
local DEPOT = common.DEPOT
local valid = common.valid
local at = common.at
local t23_force = common.t23_force
local create = common.create
local tidy = common.tidy
local state_of = common.state_of
local new_harvester = common.new_harvester
local depot_record = common.depot_record
local depot_items = common.depot_items
local verdict = common.verdict
local fail = common.fail
local check = common.check
local wait_for = common.wait_for
local prepare = common.prepare
local run_steps = common.run_steps
local sweep = common.sweep

local TECH = "arrakis-harvester-mk2"
local FLYER = "arrakis-ornithopter"
local MEASURE_TICKS = 20 * 60

local function near(a, b, tolerance)
  return type(a) == "number" and math.abs(a - b) <= tolerance
end

local function trunk_count(car)
  local trunk = valid(car) and car.get_inventory(defines.inventory.car_trunk)
  return trunk and trunk.get_item_count(SPICE) or 0
end

local t35 = {}

-- 1) Prototypen: Laderaum 60, Leben ×1,5, Rezept mit Wurmzähnen und Prozessoren, Forschung 500 Einheiten hinter Thumper,
-- Faktoren im Skript.
function t35.s1(run, tb, d)
  local failed = {}
  local mk1, mk2 = prototypes.entity[NAME], prototypes.entity[MK2]
  check(failed, mk2 ~= nil and mk2.type == "car", "Fahrzeug " .. MK2 .. " fehlt")
  local size1 = mk1 and mk1.get_inventory_size(defines.inventory.car_trunk)
  local size2 = mk2 and mk2.get_inventory_size(defines.inventory.car_trunk)
  check(failed, size1 == 40 and size2 == 60, "Laderaum " .. tostring(size2) .. " (Mk1 " .. tostring(size1) .. ")")
  local hp1 = mk1 and mk1.get_max_health()
  local hp2 = mk2 and mk2.get_max_health()
  check(failed, hp1 ~= nil and hp2 ~= nil and near(hp2, hp1 * 1.5, 0.01), "Lebenspunkte " .. tostring(hp2) .. " (Mk1 "
    .. tostring(hp1) .. ")")
  local recipe = prototypes.recipe[MK2]
  local want = {[NAME] = 1, [worms_lib.TOOTH] = 4, ["melange"] = 10, ["processing-unit"] = 5}
  local got = {}
  for _, ing in ipairs(recipe and recipe.ingredients or {}) do
    got[#got + 1] = ing.name .. "×" .. ing.amount
    check(failed, want[ing.name] == ing.amount, "Zutat " .. ing.name .. " " .. ing.amount)
  end
  check(failed, #got == 4, "Rezept hat " .. #got .. " Zutaten")
  local tech = prototypes.technology[TECH]
  local units = tech and tech.research_unit_count
  local pre = tech and tech.prerequisites or {}
  check(failed, tech ~= nil and units == 500 and tech.research_trigger == nil and pre["arrakis-thumper"] ~= nil,
    "Forschung " .. TECH .. ": " .. tostring(units) .. " Einheiten, Voraussetzung Thumper " .. tostring(pre["arrakis-thumper"] ~= nil))
  check(failed, harvester.is_name(NAME) and harvester.is_name(MK2) and not harvester.is_name(FLYER), "harvester.is_name")
  check(failed, harvester.MK2_RATE == 1.5 and harvester.MK2_VIBRATION == 0.8, "Faktoren " .. tostring(harvester.MK2_RATE)
    .. "/" .. tostring(harvester.MK2_VIBRATION))
  return verdict(run, tb, 1, "Prototypen", failed, string.format("Laderaum %s, Leben %s, Rezept %s, Forschung %s Einheiten",
    tostring(size2), tostring(hp2), table.concat(got, " + "), tostring(units)))
end

-- 2) Förderung und Vibration: Mk1 und Mk2 nebeneinander auf gleichen Feldern, 20 s nach dem Aufbau.
function t35.s2_build(run, tb, d)
  local s = d.s2
  s.mk1 = new_harvester(run, tb, d, at(d.pos.rescue, 0, 0), {coal = 50})
  s.mk2 = new_harvester(run, tb, d, at(d.pos.rescue, 40, 0), {coal = 50, name = MK2})
  if not (s.mk1 and s.mk2) then return fail(run, tb, 2, "Ernter ließen sich nicht bauen") end
  s.deadline = game.tick + 30 * 60
  return 1
end

function t35.s2_deployed(run, tb, d)
  local s = d.s2
  local r = wait_for(s, function()
    if state_of(s.mk1) == "deployed" and state_of(s.mk2) == "deployed" then
      s.c1, s.c2, s.t0 = trunk_count(s.mk1), trunk_count(s.mk2), game.tick
      return true
    end
    return false
  end, function()
    return fail(run, tb, 2, "nicht aufgebaut: Mk1 " .. state_of(s.mk1) .. ", Mk2 " .. state_of(s.mk2))
  end)
  if r == 1 then return MEASURE_TICKS end
  return r
end

function t35.s2_check(run, tb, d)
  local s = d.s2
  local failed = {}
  local seconds = (game.tick - s.t0) / 60
  local n1, n2 = trunk_count(s.mk1) - s.c1, trunk_count(s.mk2) - s.c2
  local ratio = n1 > 0 and n2 / n1 or 0
  check(failed, n1 >= 0.85 * harvester.RATE * seconds and n1 <= 1.15 * harvester.RATE * seconds, "Mk1 " .. n1 .. " in "
    .. tb.num(seconds) .. " s")
  check(failed, ratio >= 1.4 and ratio <= 1.6, "Verhältnis " .. tb.num(ratio) .. " statt 1,5")
  local w1 = vibration_lib.weight_of(s.mk1)
  local w2 = vibration_lib.weight_of(s.mk2)
  local wr = w1 > 0 and w2 / w1 or 0
  check(failed, w1 > 0 and near(wr, 0.8, 0.005), "Vibration " .. tb.num(w2) .. " / " .. tb.num(w1))
  return verdict(run, tb, 2, "Förderung und Vibration", failed, string.format(
    "in %s s Mk1 %d, Mk2 %d Spice-Sand (×%s); Vibration aufgebaut Mk1 %s, Mk2 %s (×%s)", tb.num(seconds), n1, n2,
    tb.num(ratio), tb.num(w1), tb.num(w2), tb.num(wr)))
end

-- 3) Beute schaltet nichts frei (seit 0.15.1 normale Forschung): ein getöteter Wurm lässt Zähne fallen, die Forschung
-- bleibt offen.
local function teeth_clear(surface, position)
  for _, item in pairs(surface.find_entities_filtered{type = "item-entity", position = position, radius = 12}) do
    item.destroy()
  end
end

local function kill_worm(run, tb, position, force)
  local surface = tb.surface()
  local ok, unit = pcall(function()
    return surface.create_segmented_unit{name = sandworm_lib.NAME, position = position, direction = defines.direction.west,
      extended = true, force = worms_lib.ensure_force()}
  end)
  if not (ok and unit) then return nil, tostring(unit) end
  local head = unit.get_body_nodes()[1]
  local before = storage.hunts.teeth or 0
  unit.die(force)
  teeth_clear(surface, head)
  return (storage.hunts.teeth or 0) - before
end

function t35.s3(run, tb, d)
  local s = d.s3
  local failed = {}
  local force = t23_force()
  local tech = force.technologies[TECH]
  if not tech then return fail(run, tb, 3, "Forschung " .. TECH .. " fehlt") end
  s.was = tech.researched
  d.tech_was = s.was
  tech.researched = false
  local n, err = kill_worm(run, tb, at(d.pos.rescue, 40, 20), force)
  if not n then return fail(run, tb, 3, "Sandwurm ließ sich nicht erzeugen: " .. tostring(err)) end
  local after = tech.researched
  check(failed, n > 0 and not after, n .. " Zähne, erforscht " .. tostring(after))
  tech.researched = s.was
  d.tech_was = nil
  return verdict(run, tb, 3, "Beute schaltet nichts frei", failed, string.format("%d Zähne, erforscht %s", n, tostring(after)))
end

-- 4) Tragen: Ornithopter koppelt den Mk2 an, hebt ihn (Lastbild getönt) und setzt ihn wieder ab.
function t35.s4_build(run, tb, d)
  local s = d.s4
  local force = t23_force()
  local spot = at(d.pos.refuel, 0, 0)
  s.car = create(run, tb, {name = MK2, position = spot, force = force, orientation = 0.25, raise_built = true}, "cars")
  s.flyer = create(run, tb, {name = FLYER, position = at(spot, 2, 0), force = force, raise_built = true,
    create_build_effect_smoke = false}, "flyers")
  if not (s.car and s.flyer) then return fail(run, tb, 4, "Mk2 oder Ornithopter ließ sich nicht bauen") end
  s.car.get_inventory(defines.inventory.car_trunk).insert{name = SPICE, count = 500}
  tb.fuel(s.car, "coal", 10)
  tb.fuel(s.flyer, "rocket-fuel", 2)
  s.record = flyer_lib.get(s.flyer) or flyer_lib.register(s.flyer)
  local ok, reason = flyer_lib.couple(s.record, s.car)
  if not ok then return fail(run, tb, 4, "Ankoppeln: " .. tostring(reason)) end
  s.un = s.car.unit_number
  s.deadline = game.tick + 10 * 60
  return 1
end

function t35.s4_lifted(run, tb, d)
  local s = d.s4
  return wait_for(s, function() return state_of(s.car) == "carried" end, function()
    return fail(run, tb, 4, "nicht angehoben in 10 s: Zustand " .. state_of(s.car))
  end)
end

function t35.s4_drop(run, tb, d)
  local s = d.s4
  local failed = {}
  s.failed = failed
  local record = flyer_lib.get(s.flyer)
  check(failed, record and record.cargo == s.un, "Ladung " .. tostring(record and record.cargo))
  local image = record and record.renders and record.renders.image
  local color = image and image.valid and image.color
  local tint = harvester.MK2_TINT
  s.color = color and string.format("%s/%s/%s", tb.num(color.r), tb.num(color.g), tb.num(color.b)) or "–"
  check(failed, color ~= nil and near(color.r, tint.r, 0.01) and near(color.g, tint.g, 0.01) and near(color.b, tint.b, 0.01),
    "Lastbild-Farbton " .. s.color)
  local ok, reason = flyer_lib.drop(record, nil, true)
  s.drop = tostring(ok) .. (reason and (" " .. tostring(reason)) or "")
  s.deadline = game.tick + 10 * 60
  return 1
end

function t35.s4_landed(run, tb, d)
  local s = d.s4
  local r = wait_for(s, function() return valid(s.car) and state_of(s.car) ~= "carried" end, function()
    check(s.failed, false, "nicht abgesetzt in 10 s (drop " .. s.drop .. ")")
    return 1
  end)
  if r ~= 1 then return r end
  local failed = s.failed
  check(failed, valid(s.car) and s.car.name == MK2 and s.car.unit_number == s.un, "nach dem Absetzen kein Mk2 mehr")
  check(failed, trunk_count(s.car) == 500, "Laderaum " .. trunk_count(s.car) .. " statt 500")
  check(failed, state_of(s.car) == "mobile", "Zustand " .. state_of(s.car))
  return verdict(run, tb, 4, "Tragen", failed, string.format("Farbton %s, Absetzen %s, danach %s mit %d Spice-Sand",
    s.color, s.drop, state_of(s.car), trunk_count(s.car)))
end

-- 5) Leitstelle: im Lager zuerst Mk1, dann Mk2; ausgegeben wird der Mk2, Einlagern legt ihn als Mk2 zurück.
function t35.s5(run, tb, d)
  local s = d.s5
  local failed = {}
  s.depot = create(run, tb, {name = DEPOT, position = d.pos.depot, force = t23_force(), raise_built = true}, "others")
  if not s.depot then return fail(run, tb, 5, "Leitstelle ließ sich nicht bauen") end
  local inventory = s.depot.get_inventory(defines.inventory.chest)
  inventory.insert{name = "coal", count = 100}
  inventory.insert{name = NAME, count = 1}
  inventory.insert{name = MK2, count = 1}
  local dr = depot_record(s)
  if not dr then return fail(run, tb, 5, "Leitstelle ohne Datensatz") end
  local h = fleet.spawn_reserve(dr, game.tick)
  local name = h and h.entity.valid and h.entity.name
  check(failed, name == MK2, "ausgegeben " .. tostring(name) .. " statt " .. MK2)
  local left1, left2 = depot_items(s, NAME), depot_items(s, MK2)
  check(failed, left1 == 1 and left2 == 0, "im Lager danach Mk1 " .. left1 .. ", Mk2 " .. left2)
  local stored = h and fleet.store_harvester(h, dr)
  local back1, back2 = depot_items(s, NAME), depot_items(s, MK2)
  check(failed, stored and back1 == 1 and back2 == 1, "eingelagert " .. tostring(stored) .. ": Mk1 " .. back1 .. ", Mk2 " .. back2)
  return verdict(run, tb, 5, "Leitstelle", failed, string.format("ausgegeben %s, Lager danach %d/%d, eingelagert %s, Lager %d/%d",
    tostring(name), left1, left2, tostring(stored), back1, back2))
end

-- 6) Biss „schwer beschädigt“ (Befehlsjagd, 2 s): Ernter-Jagd, Mk2 überlebt mobil, Laderaum leer.
function t35.s6_build(run, tb, d)
  local s = d.s6
  s.car = new_harvester(run, tb, d, at(d.pos.rescue, 80, 0), {coal = 50, name = MK2, fill = 2})
  if not s.car then return fail(run, tb, 6, "Mk2 ließ sich nicht bauen") end
  s.un = s.car.unit_number
  s.deadline = game.tick + 30 * 60
  return 1
end

function t35.s6_hunt(run, tb, d)
  local s = d.s6
  local r = wait_for(s, function() return state_of(s.car) == "deployed" end, function()
    return fail(run, tb, 6, "nicht aufgebaut: " .. state_of(s.car))
  end)
  if r ~= 1 then return r end
  local hunt, reason = worms_lib.start_hunt(s.car, {seconds = 2, debug = true, bite = "heavy-damage"})
  if not hunt then return fail(run, tb, 6, "start_hunt: " .. tostring(reason)) end
  s.hunt = hunt
  s.kind = hunt.kind
  return 1
end

function t35.s6_check(run, tb, d)
  local s = d.s6
  local hunt = s.hunt
  if game.tick < hunt.eta_tick + 10 then return "poll" end
  local failed = {}
  check(failed, s.kind == "harvest", "Jagdart " .. tostring(s.kind))
  local alive = valid(s.car) and s.car.unit_number == s.un
  check(failed, alive, "Mk2 tot")
  if alive then
    local trunk = s.car.get_inventory(defines.inventory.car_trunk)
    check(failed, trunk and trunk.is_empty(), "Laderaum nicht leer")
    check(failed, state_of(s.car) == "mobile", "Zustand " .. state_of(s.car))
  end
  check(failed, hunt.outcome == "bitten", "Ergebnis " .. tostring(hunt.outcome))
  return verdict(run, tb, 6, "Biss", failed, string.format("Jagdart %s, Ergebnis %s, Zustand %s, Laderaum %d",
    tostring(s.kind), tostring(hunt.outcome), state_of(s.car), trunk_count(s.car)))
end

local T35_STEPS =
{
  {t35.s1},
  {t35.s2_build, t35.s2_deployed, t35.s2_check},
  {t35.s3},
  {t35.s4_build, t35.s4_lifted, t35.s4_drop, t35.s4_landed},
  {t35.s5},
  {t35.s6_build, t35.s6_hunt, t35.s6_check}
}

local function restore(d)
  if d.factor then worms_lib.TOOTH_FACTOR = d.factor end
  local force = game.forces[common.T23_FORCE]
  local tech = force and force.technologies[TECH]
  if tech and d.tech_was ~= nil then tech.researched = d.tech_was end
end

local function t35_start(run, tb)
  prepare(run, tb)
  local d = run.data
  for number = 1, #T35_STEPS do d["s" .. number] = {} end
  d.after_step = "sweep"
  tb.watch(run, nil, d.pos.watch)
  tb.log(run, "INFO", "Sechs Schritte 0.15.1 (Ernter Mk2). Dauer etwa eine Minute Spielzeit.")
  d.step, d.phase, d.wait_until = 1, 1, game.tick + 30
end

local function t35_tick(run, tb)
  run_steps(run, tb, T35_STEPS)
end

local function t35_cleanup(run, tb)
  local d = run.data
  pcall(tidy, run)
  pcall(sweep, run, tb)
  pcall(restore, d)
end

return
{
  T35 =
  {
    title = "Ernter Mk2 0.15.1",
    timeout = 5 * 60 * 60,
    interactive = false,
    confirm = nil,
    start = t35_start,
    tick = t35_tick,
    cleanup = t35_cleanup
  }
}
