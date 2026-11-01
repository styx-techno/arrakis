-- T31 Wurm-Reviere im Spiel (interaktiv, 0.16.1; Plan docs/plan-3g.md 5): Reviergrenzen und Namen in der
-- Vibrationsanzeige und im Fenster der Ornithopter-Leitstelle, freies Revier, ohne Revierkunde nichts davon.
-- Gerüst: scripts/testbench/gemeinsam_spielabend.lua. Die Prüfstand-Fläche bekommt für die Dauer des Tests echte Reviere
-- (territory.test_real); drei Reviere um dich sind ruhig, normal und wild.

local common = require("scripts.testbench.gemeinsam_sandwurm")
local spiel = require("scripts.testbench.gemeinsam_spielabend")
local territory = require("scripts.territory")
local at = common.at

local SEED = 1909023499
local DEPOT = "arrakis-depot"
local LEVELS = {"calm", "normal", "wild"}
local LEVEL_TEXT = {calm = "ruhig", normal = "normal", wild = "wild"}

local enter = {}

local function surface_index(tb)
  return tb.surface().index
end

-- Reviere um den Ursprung, nach Abstand ihres Mittelpunkts (ohne doppelte).
local function nearby_reviere(tb, d)
  local s = surface_index(tb)
  local seen, list = {}, {}
  for dx = -320, 320, 64 do
    for dy = -320, 320, 64 do
      local id = territory.of_position(s, at(d.origin, dx, dy))
      if not seen[id] then
        seen[id] = true
        local info = territory.info(s, id)
        local cx, cy = info and info.x or d.origin.x, info and info.y or d.origin.y
        table.insert(list, {id = id, d2 = (cx - d.origin.x) ^ 2 + (cy - d.origin.y) ^ 2})
      end
    end
  end
  table.sort(list, function(a, b) return a.d2 < b.d2 end)
  return list
end

local function setup(run, tb, d)
  local surface = tb.surface()
  local s = surface.index
  d.survey_before = d.force.technologies[territory.SURVEY_TECH].researched
  spiel.research(run, tb, d.force, {territory.SURVEY_TECH})
  territory.test_real(s, SEED)
  local list = nearby_reviere(tb, d)
  d.levels = {}
  for i = 1, math.min(3, #list) do
    territory.test_level(s, list[i].id, LEVELS[i])
    d.levels[LEVELS[i]] = list[i].id
  end
  -- Leitstelle auf Fels am Ursprung, daneben ein aufgebauter Ernter (Wärme für die Anzeige).
  local n, m = math.floor(d.origin.x), math.floor(d.origin.y)
  common.tiles(surface, n - 6, m - 6, n + 5, m + 5, common.ROCK)
  d.depot = common.make(run, tb, d.made, {name = DEPOT, position = at(d.origin, 0, 0), force = d.force})
  if not d.depot then tb.log(run, "FEHLER", "Leitstelle ließ sich nicht bauen") end
  local car = common.new_harvester(run, tb, d, d.made, at(d.origin, 20.5, 0.5), {force = d.force, coal = 50, field = 1000})
  if car then common.deploy(car) end
  local names = {}
  for _, level in ipairs(LEVELS) do
    local id = d.levels[level]
    if id then table.insert(names, LEVEL_TEXT[level] .. " = Revier-ID " .. tostring(id)) end
  end
  tb.log(run, "MESSUNG", "Reviere um dich: " .. table.concat(names, ", "))
end

enter[1] = function(run, tb, d)
  tb.log(run, "INFO", "1) Die Verknüpfung „Vibrationsanzeige“ in der Leiste klicken und dich etwas umsehen (Karte ein Stück verschieben).")
  spiel.ask(run, tb, d, "Siehst du goldene Linien an den Reviergrenzen und in jedem Revier einen Namen mit Stufe (ruhig grün, normal gelb,"
    .. " wild rot)? Sind Namen und Linien gut lesbar und stören die Wärmezahlen nicht?")
end

enter[2] = function(run, tb, d)
  tb.log(run, "INFO", "2) Die Leitstelle neben dir anklicken (Fenster öffnen).")
  spiel.ask(run, tb, d, "Zeigt das Leitstellen-Fenster die Reviere in Reichweite mit ihrer Stufe verständlich an?")
end

enter[3] = function(run, tb, d)
  local id = d.levels.wild or d.levels.normal
  if not id then return tb.log(run, "FEHLER", "3) Kein Revier gefunden") end
  territory.set_free(surface_index(tb), id, 5 * 3600)
  tb.log(run, "INFO", "3) Der Test macht das wilde Revier für 5 min frei (als wäre dort ein Wurm getötet worden).")
  spiel.ask(run, tb, d, "Kommt im Chat die Meldung zum freien Revier, und steht in der Vibrationsanzeige und im Leitstellen-Fenster bei"
    .. " diesem Revier „frei“?")
end

enter[4] = function(run, tb, d)
  d.force.technologies[territory.SURVEY_TECH].researched = false
  tb.log(run, "INFO", "4) Der Test nimmt die Forschung „Revierkunde“ zurück (am Ende wieder wie vorher).")
  spiel.ask(run, tb, d, "Sind Grenzen und Namen in der Vibrationsanzeige weg (nur noch Wärme), und zeigt das Leitstellen-Fenster keine"
    .. " Reviere mehr?")
end

local function teardown(run, tb, d)
  local s = surface_index(tb)
  territory.test_reset(s)
  territory.test_real(s, nil)
  if d.survey_before ~= nil then d.force.technologies[territory.SURVEY_TECH].researched = d.survey_before end
end

return
{
  T31 = spiel.define{
    id = "T31",
    title = "Wurm-Reviere: Anzeige im Spiel",
    minutes = 15,
    half = 320,
    last = 4,
    intro = "T31 zeigt dir die Wurm-Reviere.",
    techs = {"planet-discovery-arrakis", "arrakis-spice-harvesting", "arrakis-ornithopter", "arrakis-ornithopter-depot"},
    max_at = {-5, 5},
    no_hunts = true,
    setup = setup,
    enter = enter,
    teardown = teardown
  }
}
