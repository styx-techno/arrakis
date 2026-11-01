-- T28 Flottenleitung: Ansicht: Prüfstand-Test (aus t_fleet.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_fleet.lua.

local common = require("scripts.testbench.gemeinsam_fleet")
local fields = require("scripts.fleet-fields")
local NAME = common.NAME
local at = common.at
local t23_force = common.t23_force
local create = common.create
local tidy = common.tidy
local build_base = common.build_base
local prepare = common.prepare
local T26_FIELDS = common.T26_FIELDS
local fleet_force = common.fleet_force
local place_fields = common.place_fields
local chart_area = common.chart_area
local chart_or_skip = common.chart_or_skip
local sweep = common.sweep

-- T28 Ansicht Flottenleitung (interaktiv) ------------------------------------------------------------------

local T28_END = 300 * 60

local function t28_start(run, tb)
  local player = tb.player(run)
  if not player then
    tb.log(run, "FEHLER", "T28 braucht einen Spieler")
    tb.finish(run, "abgebrochen (ohne Spieler)")
    return
  end
  prepare(run, tb)
  local d = run.data
  d.run_id = run.id
  d.s = {}
  local s = d.s
  fleet_force(true)
  fields.reset()
  if not build_base(run, tb, d, s, {carryalls = 2, rocket = 60, coal = 300}) then
    tb.finish(run, "abgebrochen (Aufbau)")
    return
  end
  s.depot.get_inventory(defines.inventory.chest).insert{name = NAME, count = 3}
  s.fields = place_fields(tb, d, {T26_FIELDS[1], T26_FIELDS[2], T26_FIELDS[3]})
  chart_area(tb, d)
  -- Lampe am roten Draht: leuchtet, sobald mindestens zwei Ernter aktiv sind (Strom aus einer Energieschnittstelle).
  pcall(function()
    local p = s.depot.position
    create(run, tb, {name = "electric-energy-interface", position = at(p, -6, -9), force = t23_force()}, "others")
    create(run, tb, {name = "small-electric-pole", position = at(p, -4, -9), force = t23_force()}, "others")
    s.lamp = create(run, tb, {name = "small-lamp", position = at(p, -3, -6), force = t23_force()}, "others")
    s.lamp.get_wire_connector(defines.wire_connector_id.circuit_red, true).connect_to(
      s.depot.get_wire_connector(defines.wire_connector_id.circuit_red, true), false)
    local behavior = s.lamp.get_or_create_control_behavior()
    behavior.circuit_enable_disable = true
    behavior.circuit_condition = {first_signal = {type = "virtual", name = "arrakis-signal-harvesters"}, comparator = "≥",
      constant = 2}
  end)
  s.viewer = player.index
  -- Leitstelle und Carryalls gehören der Prüfstand-Force (Flottenleitung erforscht, ohne Wurm). Damit du das Fenster
  -- öffnen kannst, spielst du während T28 in dieser Force; das Aufräumen setzt dich zurück (Max 29.10.: „gehören zu
  -- einer anderen Fraktion“).
  s.player_force = player.force.name
  player.force = t23_force()
  tb.watch(run, player, at(s.depot.position, 8, 4))
  tb.protect(run, player)
  s.start = game.tick
  tb.log(run, "INFO", "Leitstelle mit Flottenleitung, 3 Ernter im Lager, drei Spicefelder rechts. Öffne die Leitstelle: Stell die"
    .. " Soll-Zahl mit + auf 2; zwei Carryalls setzen gleichzeitig je einen Ernter ein, die Lampe links oben leuchtet ab zwei"
    .. " aktiven. Dann „Alle zurückrufen“ drücken (beide kommen an die Leitstelle) und noch einmal drücken (sie fliegen"
    .. " beide gleichzeitig zurück). 5 min Zeit.")
end

local function t28_tick(run, tb)
  local s = run.data.s
  if not (s and s.start) then return end
  chart_or_skip(run, tb, s)
  if game.tick >= s.start + T28_END then
    s.start = nil
    tb.log(run, "FRAGE", "Passen das Fenster der Leitstelle (Soll mit - und +, Rückruf-Knopf, Zeilen Aktiv/Reserve/Feldsuche) und"
      .. " der Ablauf (Einsatz aus dem Lager, Rückruf, Lampe am Draht)? Antwort bitte im Thread.")
    tb.finish(run, "Ansicht gezeigt")
  end
end

local function t28_cleanup(run, tb)
  local s = run.data and run.data.s
  local player = s and s.viewer and game.get_player(s.viewer)
  if player and player.valid and s.player_force and game.forces[s.player_force] then
    pcall(function() player.force = game.forces[s.player_force] end)
  end
  pcall(tidy, run)
  pcall(sweep, run, tb)
  pcall(fleet_force, false)
end

return
{
  T28 =
  {
    title = "Flottenleitung: Ansicht",
    timeout = T28_END + 60 * 60,
    interactive = true,
    answer_time = 120 * 60,
    confirm = nil,
    start = t28_start,
    tick = t28_tick,
    cleanup = t28_cleanup
  }
}
