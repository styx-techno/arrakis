-- T34 Thumper im Spiel (interaktiv, 0.16.1; Plan docs/plan-3h.md 4): Thumper bauen und ansehen, Köder, eine Jagd
-- umlenken, einen Wurm vor Geschütze locken, Wurmzähne aufheben. Gerüst: scripts/testbench/gemeinsam_spielabend.lua.
-- Fläche ±250 aus Sand, Felsinsel mit 20 Geschützen (Uranmunition) 60 bis 90 Kacheln östlich des Ursprungs.

local common = require("scripts.testbench.gemeinsam_sandwurm")
local spiel = require("scripts.testbench.gemeinsam_spielabend")
local thumper_lib = require("scripts.thumper")
local worms_lib = common.worms_lib
local valid = common.valid
local at = common.at
local box_of = common.box_of

local ISLAND = {x1 = 60, y1 = -20, x2 = 90, y2 = 19}
local KILL_AFTER = 10 * 60

local enter, watch = {}, {}

-- Thumper der Force im Testbereich (unit_number → Eintrag).
local function thumpers(d)
  local list = {}
  for un, record in pairs(storage.thumpers or {}) do
    if record.entity.valid and record.force_index == d.force.index and common.inside(d.box, record.entity.position) then list[un] = record end
  end
  return list
end

-- Neue Thumper und Jagden auf Thumper als INFO (jeder Schritt).
local function log_news(run, tb, d)
  for un, record in pairs(thumpers(d)) do
    if not d.seen[un] then
      d.seen[un] = true
      tb.log(run, "INFO", string.format("%d) Thumper #%d gebaut bei %s, auf Sand %s%s", d.step, un, common.pos_text(tb, record.entity.position),
        tostring(record.sand), record.diverted and (", lenkt Jagd " .. record.diverted .. " um") or ""))
    end
  end
  for id, hunt in pairs(storage.hunts.list) do
    if hunt.force_index == d.force.index and hunt.thumper and not d.seen_hunts[id] then
      d.seen_hunts[id] = true
      tb.log(run, "INFO", string.format("%d) Jagd %d gilt einem Thumper (%s), Biss in %s s", d.step, id, hunt.diverted and "umgelenkt" or "Köder",
        tb.num((hunt.eta_tick - game.tick) / 60, 0)))
    end
  end
end

local function setup(run, tb, d)
  d.seen, d.seen_hunts = {}, {}
  local player = tb.player(run)
  spiel.give(run, tb, player, thumper_lib.NAME, 6)
  local built = spiel.turret_island(run, tb, d, d.origin, ISLAND.x1, ISLAND.y1, ISLAND.x2, ISLAND.y2, 20, "west")
  tb.log(run, "INFO", string.format("Felsinsel %d bis %d Kacheln östlich mit %d Geschützen (Uranmunition)", ISLAND.x1, ISLAND.x2, built))
end

enter[1] = function(run, tb, d)
  tb.log(run, "INFO", "1) Einen Thumper aus dem Inventar auf Sand neben dich stellen und zusehen. Nach etwa 20 s lockt er einen Wurm"
    .. " (Wurmzeichen auf den Thumper); bei 0 frisst der Wurm ihn.")
  spiel.ask(run, tb, d, "Pocht der Thumper sichtbar (Stempel auf und ab), staubt es um ihn, und hörst du ihn? Kommt nach etwa 20 s das"
    .. " Wurmzeichen auf den Thumper, und frisst ihn der Wurm bei 0?")
end
watch[1] = log_news

enter[2] = function(run, tb, d)
  local car = common.new_harvester(run, tb, d, d.made, at(d.origin, -100.5, 40.5), {force = d.force, coal = 20})
  if not car then return tb.log(run, "FEHLER", "2) Ernter ließ sich nicht bauen") end
  d.car2 = car
  local spot = at(d.origin, -70.5, 40.5)
  spiel.hunt(run, tb, d, car, {seconds = 90, debug = true}, "Ernter 100 Kacheln westlich, Wurmzeichen")
  tb.log(run, "INFO", "2) Lauf zur gelben Markierung " .. spiel.mark(tb, spot) .. " (30 Kacheln neben dem Ernter) und stell dort einen"
    .. " Thumper auf, solange der Countdown läuft.")
  spiel.ask(run, tb, d, "Springen Alarm und roter Ring vom Ernter auf den Thumper, und frisst der Wurm bei 0 den Thumper, während der"
    .. " Ernter heil bleibt?")
end
watch[2] = function(run, tb, d)
  log_news(run, tb, d)
  if d.car2 and not d.car2_logged and not valid(d.car2) then
    d.car2_logged = true
    tb.log(run, "MESSUNG", "2) Der Ernter ist weg (gefressen?)")
  end
end

enter[3] = function(run, tb, d)
  local spot = at(d.origin, ISLAND.x1 - 6.5, 0.5)
  d.box3 = box_of(at(d.origin, ISLAND.x1, 0), {x = 40, y = 40})
  d.teeth_before = spiel.teeth_in(tb, d.box3)
  tb.log(run, "INFO", "3) Stell einen Thumper auf Sand direkt vor die Felsinsel mit den Geschützen, an die gelbe Markierung "
    .. spiel.mark(tb, spot) .. ". Er lockt nach etwa 20 s einen Wurm. Du stehst am besten auf der Insel.")
  spiel.ask(run, tb, d, "Kommt der Wurm zum Thumper, und schießen die Geschütze ihn vor dem Biss tot? Stirbt er mit Sandstaub?")
end
watch[3] = function(run, tb, d)
  log_news(run, tb, d)
  for id, hunt in pairs(storage.hunts.list) do
    local unit = hunt.worm and hunt.worm.unit
    if hunt.force_index == d.force.index and hunt.thumper and valid(unit) and game.tick % 300 == 0 then
      local head = common.sandworm_lib.head_of(hunt)
      tb.log(run, "MESSUNG", string.format("3) Jagd %d: Wurm bei %s, Lebenspunkte %s, Biss in %s s", id, head and common.pos_text(tb, head) or "–",
        tb.num(unit.health, 0), tb.num((hunt.eta_tick - game.tick) / 60, 0)))
    end
  end
end

-- 4) Zähne: Liegen keine aus Schritt 3, lockt der Test einen Wurm an eine Kiste vor der Insel und tötet ihn 10 s nach dem
-- Auftauchen (wie T22 Schritt 7), damit es welche gibt.
enter[4] = function(run, tb, d)
  local box = d.box3 or box_of(at(d.origin, ISLAND.x1, 0), {x = 40, y = 40})
  local teeth = spiel.teeth_in(tb, box)
  tb.log(run, "MESSUNG", "4) Wurmzähne am Boden vor der Insel: " .. teeth)
  if teeth > 0 then
    spiel.ask(run, tb, d, "Liegen dort 2 bis 4 Wurmzähne mit eigenem Symbol, und kannst du sie mit F aufheben?")
    return
  end
  local chest = common.make(run, tb, d.made, {name = common.CHEST, position = at(d.origin, ISLAND.x1 - 8.5, 10.5), force = d.force})
  if not chest then return tb.log(run, "FEHLER", "4) Kiste ließ sich nicht bauen") end
  d.kill4 = spiel.hunt(run, tb, d, chest, {seconds = 60, debug = true}, "Kein Zahn da: Wurm zur Kiste vor der Insel, der Test tötet ihn 10 s"
    .. " nach dem Auftauchen")
  spiel.ask(run, tb, d, "Liegen nach dem Tod 2 bis 4 Wurmzähne mit eigenem Symbol neben der Insel, und kannst du sie mit F aufheben?")
end
watch[4] = function(run, tb, d)
  local hunt = d.kill4
  if not hunt then return end
  local unit = hunt.worm and hunt.worm.unit
  if valid(unit) and not d.spawn4 then d.spawn4 = game.tick end
  if d.spawn4 and not d.killed4 and game.tick >= d.spawn4 + KILL_AFTER then
    d.killed4 = true
    if valid(unit) then
      local ok, err = pcall(function() unit.die(d.force) end)
      if not ok then tb.log(run, "FEHLER", "4) die: " .. tostring(err)) end
    end
  end
  if d.killed4 and not d.counted4 and game.tick >= d.spawn4 + KILL_AFTER + 60 then
    d.counted4 = true
    tb.log(run, "MESSUNG", "4) Wurmzähne nach dem Tod: " .. spiel.teeth_in(tb, d.box3 or box_of(at(d.origin, ISLAND.x1, 0), {x = 40, y = 40})))
  end
end

return
{
  T34 = spiel.define{
    id = "T34",
    title = "Thumper im Spiel",
    minutes = 25,
    half = 250,
    last = 4,
    intro = "T34 zeigt dir den Thumper.",
    techs = {"planet-discovery-arrakis", "arrakis-spice-harvesting", thumper_lib.TECH},
    max_at = {-5, 5},
    setup = setup,
    enter = enter,
    watch = watch,
    keep_hunts = true
  }
}
