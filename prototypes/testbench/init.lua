-- Prüfstand (Phase 3a, docs/pruefstand.md): Test-Prototypen für /arrakis-test.
-- Nur mit der Startup-Einstellung "arrakis-testbench". Ohne sie bleibt das Spiel unberührt.
-- Alle Entities sind versteckt, heißen "arrakis-test-…" und haben weder Rezept noch Forschung.
if not settings.startup["arrakis-testbench"].value then return end

require("prototypes.testbench.flyers")
require("prototypes.testbench.harvester")
require("prototypes.testbench.proxies")
require("prototypes.testbench.worms")
require("prototypes.testbench.sprites")
require("prototypes.testbench.inputs")
