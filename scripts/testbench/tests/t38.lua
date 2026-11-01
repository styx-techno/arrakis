-- T38 Großer Wurm im Spiel (interaktiv, 0.16.1; Plan docs/plan-3j.md 3): zwei Ernter, je ein großer Wurm. Ernter A mit
-- dem Ornithopter retten, Ernter B steht vor einer Felsinsel mit Geschützen. Ansehen: Größe, Staub, Ton, Meldung
-- „Großes Wurmzeichen“, größerer Ring, 6–10 Zähne. Gerüst: scripts/testbench/gemeinsam_spielabend.lua. Reguläre
-- Wurmzeichen sind aus (no_hunts); die beiden Jagden sind Befehlsjagden mit size „large“.

local common = require("scripts.testbench.gemeinsam_sandwurm")
local spiel = require("scripts.testbench.gemeinsam_spielabend")
local valid = common.valid
local at = common.at
local box_of = common.box_of

local ISLAND = {x1 = 30, y1 = 60, x2 = 60, y2 = 99}
local SECONDS = 120

local enter, watch = {}, {}

local function setup(run, tb, d)
  d.car_a = common.new_harvester(run, tb, d, d.made, at(d.origin, 0.5, -60.5), {force = d.force, coal = 20})
  d.car_b = common.new_harvester(run, tb, d, d.made, at(d.origin, ISLAND.x1 - 8.5, 80.5), {force = d.force, coal = 20})
  d.flyer = common.new_flyer(run, tb, d, d.made, at(d.origin, -10.5, -10.5), {force = d.force, rocket = 6})
  local built = spiel.turret_island(run, tb, d, d.origin, ISLAND.x1, ISLAND.y1, ISLAND.x2, ISLAND.y2, 24, "west")
  tb.log(run, "INFO", string.format("Ernter A %s, Ernter B %s vor der Felsinsel mit %d Geschützen (Uranmunition), Ornithopter neben dir",
    valid(d.car_a) and spiel.mark(tb, d.car_a.position, 3) or "fehlt", valid(d.car_b) and spiel.mark(tb, d.car_b.position, 3) or "fehlt",
    built))
end

-- Lebenspunkte des Wurms alle 5 s (MESSUNG).
local function log_worm(run, tb, d, hunt, label)
  local unit = hunt and hunt.worm and hunt.worm.unit
  if valid(unit) and game.tick % 300 == 0 then
    local head = common.sandworm_lib.head_of(hunt)
    tb.log(run, "MESSUNG", string.format("%d) %s: Wurm %s bei %s, Lebenspunkte %s, Biss in %s s", d.step, label, unit.prototype.name,
      head and common.pos_text(tb, head) or "–", tb.num(unit.health, 0), tb.num((hunt.eta_tick - game.tick) / 60, 0)))
  end
end

enter[1] = function(run, tb, d)
  if not valid(d.car_a) then return tb.log(run, "FEHLER", "1) Ernter A fehlt") end
  d.hunt_a = spiel.hunt(run, tb, d, d.car_a, {seconds = SECONDS, debug = true, size = "large"}, "Großer Wurm auf Ernter A")
  tb.log(run, "INFO", "1) Sieh dir das Wurmzeichen an und warte, bis der Wurm auftaucht. Dann in den Ornithopter, Ernter A vor 0 anheben"
    .. " (Umschalt+C) und bis nach dem Biss in der Luft bleiben.")
  spiel.ask(run, tb, d, "Steht „Großes Wurmzeichen“ im Chat und Alarm, und ist der rote Ring größer als beim kleinen Wurm? Ist der Wurm"
    .. " deutlich größer, mit mehr Staub und lauter? Beißt er bei 0 ins Leere, während Ernter A in der Luft hängt?")
end
watch[1] = function(run, tb, d)
  log_worm(run, tb, d, d.hunt_a, "Ernter A")
end

enter[2] = function(run, tb, d)
  if not valid(d.car_b) then return tb.log(run, "FEHLER", "2) Ernter B fehlt") end
  d.box2 = box_of(at(d.origin, ISLAND.x1, 80), {x = 50, y = 50})
  d.hunt_b = spiel.hunt(run, tb, d, d.car_b, {seconds = SECONDS, debug = true, size = "large"}, "Großer Wurm auf Ernter B vor den Geschützen")
  tb.log(run, "INFO", "2) Stell dich auf die Felsinsel hinter die Geschütze und sieh zu. Der Wurm hat 100 000 Lebenspunkte.")
  spiel.ask(run, tb, d, "Schaffen die Geschütze den großen Wurm vor dem Biss? Wenn ja: Stirbt er mit Sandstaub und liegen 6 bis 10"
    .. " Wurmzähne da (mit F aufheben)? Wenn nein: frisst er Ernter B mit dem großen Biss (Umkreis 6)?")
end
watch[2] = function(run, tb, d)
  local hunt = d.hunt_b
  log_worm(run, tb, d, hunt, "Ernter B")
  local unit = hunt and hunt.worm and hunt.worm.unit
  if valid(unit) then d.seen_b = true end
  if d.seen_b and not d.done_b and not valid(unit) then
    d.done_b = true
    d.teeth_at = game.tick + 60
  end
  if d.teeth_at and game.tick >= d.teeth_at then
    d.teeth_at = nil
    tb.log(run, "MESSUNG", string.format("2) Wurm weg; Ernter B %s, Wurmzähne am Boden %d", valid(d.car_b) and "lebt" or "gefressen",
      spiel.teeth_in(tb, d.box2)))
  end
end

return
{
  T38 = spiel.define{
    id = "T38",
    title = "Großer Wurm im Spiel",
    minutes = 20,
    half = 200,
    last = 2,
    intro = "T38 zeigt dir den großen Wurm.",
    techs = {"planet-discovery-arrakis", "arrakis-spice-harvesting", "arrakis-ornithopter"},
    max_at = {-15, -5},
    no_hunts = true,
    keep_hunts = true,
    setup = setup,
    enter = enter,
    watch = watch
  }
}
