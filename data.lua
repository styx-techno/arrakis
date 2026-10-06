local compat = require("prototypes.compat")
compat.start()

require("prototypes.surface-property")
require("prototypes.autoplace-controls")
require("prototypes.noise")
require("prototypes.collision-layers")
require("prototypes.tiles")
require("prototypes.resources")
require("prototypes.windtrap")
require("prototypes.spice")
require("prototypes.planet.planet")
require("prototypes.technology")

-- Prüfstand: nur mit Startup-Einstellung "arrakis-testbench".
require("prototypes.testbench.init")

compat.finish()
