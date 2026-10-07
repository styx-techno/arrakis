local handler = require("__core__.lualib.event_handler")

-- Reihenfolge (Plan 4.1): migrate legt storage an und kommt deshalb zuerst.
local libraries =
{
  require("scripts.migrate"),
  require("scripts.arrakis-surface"),
  require("scripts.harvester"),
  require("scripts.harvester-gui"),
  require("scripts.intake")
}

-- Prüfstand (/arrakis-test) nur mit Startup-Einstellung; sonst bleibt das Spiel unberührt. Immer zuletzt.
if settings.startup["arrakis-testbench"].value then
  local runner = require("scripts.testbench.runner")
  table.insert(libraries, runner)
end

handler.add_libraries(libraries)
