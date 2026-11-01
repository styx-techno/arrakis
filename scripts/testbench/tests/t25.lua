-- T25 Carryall und Leitstelle: Ansicht: Prüfstand-Test (aus t_fleet.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_fleet.lua.

local common = require("scripts.testbench.gemeinsam_fleet")
local flyer_lib = require("scripts.flyer")
local worms_lib = require("scripts.worms")
local DEPOT = common.DEPOT
local T23_HALF = common.T23_HALF
local at = common.at
local t23_force = common.t23_force
local tidy = common.tidy
local record_of = common.record_of
local state_of = common.state_of
local build_base = common.build_base
local new_harvester = common.new_harvester
local prepare = common.prepare

-- T25 Ansicht (interaktiv) ---------------------------------------------------------------------------
-- Anders als T23 und T24 mit sichtbarem Wurm (Max 29.10.2026: „es war kein Wurm zu sehen“): set_worm_off aus,
-- Startrichtung Ost (k0 = 4, weg von der Felsinsel). Dazu bekommt der Spieler eine Leitstelle ins Inventar, damit er die
-- Frage nach dem Reichweitenkreis beim Bauen beantworten kann; Aufräumen nimmt sie wieder weg.

local T25_HUNT_AFTER = 15 * 60
local T25_HUNT_SECONDS = 60
local T25_END = 150 * 60
local T25_SPAWN_DIR = 4

local function t25_start(run, tb)
  local player = tb.player(run)
  if not player then
    tb.log(run, "FEHLER", "T25 braucht einen Spieler")
    tb.finish(run, "abgebrochen (ohne Spieler)")
    return
  end
  prepare(run, tb)
  local d = run.data
  d.s = {}
  local s = d.s
  if not build_base(run, tb, d, s) then
    tb.finish(run, "abgebrochen (Aufbau)")
    return
  end
  s.car = new_harvester(run, tb, d, at(d.pos.depot, 45, 0))
  -- Erst nach new_harvester: t23_force() schaltet den Wurm bei jedem Aufruf wieder aus.
  local force = t23_force()
  worms_lib.ensure_force()
  worms_lib.set_worm_off(force, false)
  worms_lib.set_spawn_dir(force, T25_SPAWN_DIR)
  s.force = force
  s.viewer = player.index
  s.given = player.insert{name = DEPOT, count = 1}
  tb.watch(run, player, at(d.pos.depot, 22, 6))
  tb.protect(run, player)
  s.start = game.tick
  tb.log(run, "INFO", "Leitstelle links auf Fels, Carryall parkt dort, Ernter 45 Kacheln rechts. In 15 s kommt ein Wurmzeichen,"
    .. " der Wurm taucht von Osten auf: Der Carryall holt den Ernter, bringt ihn zur Leitstelle und nach der Jagd zurück aufs Feld."
    .. (s.given > 0 and " Eine Leitstelle liegt in deinem Inventar: Nimm sie in die Hand und zeig auf die Felsinsel, dann siehst du"
      .. " den Reichweitenkreis (setzen darfst du sie auch)." or " Eine Leitstelle ließ sich nicht ins Inventar legen."))
end

local function t25_tick(run, tb)
  local s = run.data.s
  if not (s and s.start) then return end
  local tick = game.tick
  if not s.hunt and tick >= s.start + T25_HUNT_AFTER and state_of(s.car) == "deployed" then
    s.hunt = worms_lib.start_hunt(s.car, {seconds = T25_HUNT_SECONDS, debug = true})
    if not s.hunt then tb.log(run, "FEHLER", "Wurmzeichen ließ sich nicht starten") end
  end
  if tick >= s.start + T25_END then
    s.start = nil
    tb.log(run, "FRAGE", "Passt der Ablauf wie im Film (Ernter zur Leitstelle, nach der Jagd zurück aufs Feld)? Antwort bitte im"
      .. " Thread.")
    tb.finish(run, "Ansicht gezeigt")
  end
end

local function t25_cleanup(run, tb)
  local s = run.data.s
  local record = s and record_of(s.carryall)
  if record and record.cargo then pcall(flyer_lib.drop, record, nil, true) end
  if s and s.force and s.force.valid then
    local own = {}
    for _, hunt in pairs(storage.hunts.list) do
      if hunt.force_index == s.force.index then table.insert(own, hunt) end
    end
    for _, hunt in ipairs(own) do pcall(worms_lib.end_hunt, hunt, nil, "abort") end
    worms_lib.set_spawn_dir(s.force, nil)
    worms_lib.set_worm_off(s.force, true)
  end
  pcall(tidy, run)
  -- Vom Spieler gesetzte Leitstellen im Testbereich und die geschenkte im Inventar wieder weg.
  local origin = tb.area(run.id)
  local surface = tb.surface()
  pcall(function()
    for _, entity in pairs(surface.find_entities_filtered{name = DEPOT, area = {{origin.x - T23_HALF.x, origin.y - T23_HALF.y},
        {origin.x + T23_HALF.x, origin.y + T23_HALF.y}}}) do
      entity.destroy{raise_destroy = true}
    end
  end)
  local player = s and s.viewer and game.get_player(s.viewer)
  if player and s.given and s.given > 0 then pcall(function() player.remove_item{name = DEPOT, count = s.given} end) end
end

return
{
  T25 =
  {
    title = "Carryall und Leitstelle: Ansicht",
    timeout = T25_END + 60 * 60,
    interactive = true,
    answer_time = 120 * 60,
    confirm = nil,
    start = t25_start,
    tick = t25_tick,
    cleanup = t25_cleanup
  }
}
