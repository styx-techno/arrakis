local compat = require("prototypes.compat")
compat.start()

require("prototypes.surface-property")
require("prototypes.autoplace-controls")
require("prototypes.noise")
require("prototypes.collision-layers")
require("prototypes.tiles")
-- Vor resources.lua: dort bekommt Spice-Sand die Ressourcenkategorie aus harvester.lua.
require("prototypes.harvester")
-- Direkt nach harvester.lua: Die Absetz-Probe übernimmt die Kollisionsmaske des Ernters (docs/plan-3c.md 2).
require("prototypes.ornithopter")
require("prototypes.resources")
require("prototypes.windtrap")
require("prototypes.spice")
require("prototypes.planet.planet")
require("prototypes.technology")
-- Phase 3d1 (docs/plan-3d1.md 3): Eruption, Sandstaub, Signal, Geräusche, Vibrationsanzeige, Tipps.
require("prototypes.worms")
-- Phase 3d2 (docs/plan-3d2.md 3): Sandwurm, Bohrstaub, Auf- und Abtauchen. Direkt nach worms.lua: arrakis-worm-dive kopiert
-- die Eruption.
require("prototypes.sandworm")

-- Prüfstand: nur mit Startup-Einstellung "arrakis-testbench".
require("prototypes.testbench.init")

compat.finish()
