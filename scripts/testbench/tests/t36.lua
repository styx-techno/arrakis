-- T36 Ernter Mk2 im Spiel (interaktiv, 0.16.1; Plan docs/plan-3i.md 3): Mk2 von Hand herstellen, neben dem Mk1 ansehen
-- (Grafik, Ernterfenster), mit dem Ornithopter tragen (eigenes Lastbild seit 0.16.1). Ohne Wurm-Jagden.
-- Gerüst: scripts/testbench/gemeinsam_spielabend.lua.

local common = require("scripts.testbench.gemeinsam_sandwurm")
local spiel = require("scripts.testbench.gemeinsam_spielabend")
local flyer_lib = require("scripts.flyer")
local harvester_lib = require("scripts.harvester")
local valid = common.valid
local at = common.at

local MK2 = "spice-harvester-mk2"
local TECH = "arrakis-harvester-mk2"
local INGREDIENTS = {{"spice-harvester", 1}, {"arrakis-worm-tooth", 4}, {"melange", 10}, {"processing-unit", 5}}

local enter, watch = {}, {}

-- Mk2 im Testbereich (erster gefundener).
local function find_mk2(tb, d)
  local list = tb.surface().find_entities_filtered{area = d.box, name = MK2, force = d.force}
  return list[1]
end

-- Zustand des Ornithopters und Name seiner Last als INFO bei jeder Änderung.
local function log_flyer(run, tb, d)
  local record = valid(d.flyer) and flyer_lib.get(d.flyer)
  local h = record and record.cargo and storage.harvesters[record.cargo]
  local text = (h and h.entity.valid) and h.entity.name or "leer"
  local image = record and record.renders and record.renders.image
  local sprite = image and image.valid and image.sprite or "–"
  local key = text .. "/" .. sprite
  if key ~= d.cargo_key then
    d.cargo_key = key
    tb.log(run, "INFO", string.format("%d) Ornithopter: Last %s, Lastbild %s", d.step, text, sprite))
  end
end

local function setup(run, tb, d)
  local player = tb.player(run)
  for _, entry in ipairs(INGREDIENTS) do spiel.give(run, tb, player, entry[1], entry[2]) end
  d.mk1 = common.new_harvester(run, tb, d, d.made, at(d.origin, 12.5, 0.5), {force = d.force, coal = 20, field = 1000})
  if d.mk1 then common.deploy(d.mk1) end
  common.carpet(tb.surface(), at(d.origin, 12.5, 16.5), 1000)
  d.spot = at(d.origin, 12.5, 16.5)
  d.flyer = common.new_flyer(run, tb, d, d.made, at(d.origin, -6.5, 8.5), {force = d.force, rocket = 6})
end

enter[1] = function(run, tb, d)
  tb.log(run, "INFO", "1) Im Handwerksmenü „Spice-Ernter Mk2“ herstellen (die Zutaten liegen in deinem Inventar, 20 s).")
  spiel.ask(run, tb, d, "Hat der Mk2 ein eigenes Symbol (Klingen, helle Platten), und stehen im Rezept 1 Spice-Ernter, 4 Wurmzähne,"
    .. " 10 Melange und 5 Prozessoren?")
end

enter[2] = function(run, tb, d)
  local player = tb.player(run)
  local have = player and player.get_item_count(MK2) or 0
  if have == 0 and not find_mk2(tb, d) then
    spiel.give(run, tb, player, MK2, 1)
    tb.log(run, "INFO", "2) Kein Mk2 im Inventar: der Test hat dir einen gegeben.")
  end
  tb.log(run, "INFO", "2) Den Mk2 auf das Spice-Feld an der gelben Markierung " .. spiel.mark(tb, d.spot, 3) .. " stellen, einsteigen und"
    .. " mit Umschalt+H aufbauen. Der Mk1 steht 16 Kacheln nördlich davon.")
  spiel.ask(run, tb, d, "Sieht der Mk2 anders aus als der Mk1 (Wurmzahn-Klingen am Maul, hellere Panzerplatten, drei Schlote), laufen"
    .. " seine Raupen beim Fahren mit, und zeigt das Ernterfenster Laderaum …/60?")
end
watch[2] = function(run, tb, d)
  local mk2 = find_mk2(tb, d)
  if mk2 and not d.mk2_logged then
    d.mk2_logged = true
    local h = harvester_lib.get(mk2)
    local trunk = mk2.get_inventory(defines.inventory.car_trunk)
    tb.log(run, "MESSUNG", string.format("2) Mk2 gebaut bei %s, eingetragen %s, Laderaum %d Plätze", common.pos_text(tb, mk2.position),
      h and "ja" or "nein", trunk and #trunk or 0))
  end
end

enter[3] = function(run, tb, d)
  if not valid(d.flyer) then d.flyer = common.new_flyer(run, tb, d, d.made, at(d.origin, -6.5, 8.5), {force = d.force, rocket = 6}) end
  tb.log(run, "INFO", "3) In den Ornithopter neben dir steigen, über den Mk2 fliegen, Umschalt+C (anheben), eine Runde fliegen und wieder"
    .. " absetzen (Umschalt+C). Zum Vergleich auch den Mk1 anheben.")
  spiel.ask(run, tb, d, "Hängt der Mk2 mit seinem eigenen Bild (Klingen, drei Schlote, Raupen, deine Farbe) unter dem Ornithopter, der Mk1"
    .. " mit seinem? Ist nach dem Absetzen derselbe Ernter wieder da?")
end
watch[3] = log_flyer

return
{
  T36 = spiel.define{
    id = "T36",
    title = "Ernter Mk2 im Spiel",
    minutes = 20,
    half = 120,
    last = 3,
    intro = "T36 zeigt dir den Ernter Mk2.",
    techs = {"planet-discovery-arrakis", "arrakis-spice-harvesting", "arrakis-ornithopter", "arrakis-thumper", TECH},
    max_at = {-5, 5},
    no_hunts = true,
    setup = setup,
    enter = enter,
    watch = watch
  }
}
