local handler = require("__core__.lualib.event_handler")

-- Reihenfolge (Plan 4.1, docs/plan-3c.md 4.1): migrate legt storage an und kommt deshalb zuerst. on_init und
-- on_configuration_changed laufen in dieser Reihenfolge; für ein Ereignis, das mehrere Module behandeln, ist die
-- Reihenfolge zwischen den Modulen nicht zugesichert (event_handler fasst die Handler mit pairs zusammen).
local libraries =
{
  require("scripts.migrate"),
  require("scripts.arrakis-surface"),
  require("scripts.harvester"),
  require("scripts.harvester-gui"),
  require("scripts.intake"),
  require("scripts.hold"),
  require("scripts.flyer"),
  require("scripts.flyer-gui"),
  -- Phase 3d1 (docs/plan-3d1.md 4.1): Vibration, Würmer (einzige Wurm-Takte), Fenster oben links.
  require("scripts.vibration"),
  -- Phase 3d2 (docs/plan-3d2.md 4.1): der Sandwurm als Fahrzeug, direkt vor worms (worms ruft ihn auf).
  require("scripts.sandworm"),
  require("scripts.worms"),
  require("scripts.worms-gui")
}

-- Prüfstand (/arrakis-test) nur mit Startup-Einstellung; sonst bleibt das Spiel unberührt. Immer zuletzt.
if settings.startup["arrakis-testbench"].value then
  local runner = require("scripts.testbench.runner")
  table.insert(libraries, runner)
end

handler.add_libraries(libraries)
