local handler = require("__core__.lualib.event_handler")

-- Prüfstand (/arrakis-test) nur mit Startup-Einstellung; sonst bleibt das Spiel unberührt.
local libraries = {require("scripts.arrakis-surface")}
if settings.startup["arrakis-testbench"].value then
  local runner = require("scripts.testbench.runner")
  table.insert(libraries, runner)
end

handler.add_libraries(libraries)
