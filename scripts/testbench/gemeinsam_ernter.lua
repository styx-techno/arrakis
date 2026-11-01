-- Prüfstand: Spice-Ernter mit echtem Laufzeitcode (Phase 3b, Plan 6; Vertrag siehe runner.lua).
--   T13: scripts/harvester.lua, scripts/intake.lua und scripts/migrate.lua auf der Prüfstand-Fläche
--        (terrain.harvest_allowed erlaubt sie mit der Startup-Einstellung). Zwölf Schritte, je eine
--        OK/FEHLER-Zeile mit Werten; Einzelwerte als MESSUNG nur in der Datei.
--   T2b: Fahrphysik des echten spice-harvester: Brennstoffe mit Ausgleich, Raketentreibstoff ohne
--        Ausgleich und Deckel, Richtungen, negative Koordinaten, voller Laderaum. Dazu Läufe ohne Deckel:
--        drei mit dem alten Ausgleich 1/a (sie messen, wie stark das Höchsttempo t wirkt, 2.1.13) und ab
--        2.1.13 drei mit dem neuen Ausgleich 1/(a · t²) (sie zeigen das Tempo, das der Deckel sonst verdeckt).
-- Ernter entstehen mit raise_built = true (script_raised_built trägt sie ein). Ausnahme: der Vergleichsernter
-- in T2b, der bewusst nie eingetragen wird (kein Deckel; den Ausgleich setzt der Test).
-- Zustand nur in run.data (Zahlen, Texte, Positionen, LuaEntity-Referenzen; vor jeder Benutzung prüfen).
-- Die Abläufe stehen als Funktionslisten in diesem Modul, run.data hält nur Schritt- und Phasennummern.

local harvester = require("scripts.harvester")

local NAME = "spice-harvester"
local SPICE = "spice-sand"

-- Allgemeine Helfer ---------------------------------------------------------------------------

local function valid(object)
  return object ~= nil and object.valid
end

local function force_of(run, tb)
  local player = tb.player(run)
  return player and player.force or game.forces["player"]
end

local function copy_pos(position)
  return {x = position.x or position[1], y = position.y or position[2]}
end

local function at(origin, dx, dy)
  return {x = origin.x + dx, y = origin.y + dy}
end

local function pos_text(tb, position)
  if not position then return "–" end
  local p = copy_pos(position)
  return "(" .. tb.num(p.x) .. ", " .. tb.num(p.y) .. ")"
end

-- Liest einen Wert; Fehler werden zu nil.
local function read(fn)
  local ok, value = pcall(fn)
  if ok then return value end
  return nil
end

-- Zustand des Datensatzes in storage.harvesters (scripts/harvester.lua) oder "–".
local function state_of(car)
  local h = valid(car) and harvester.get(car)
  return h and h.state or "–"
end

local function flags_text(car)
  if not valid(car) then return "Ernter weg" end
  return string.format("Zustand %s, disabled_by_script %s, minable_flag %s", state_of(car),
    tostring(read(function() return car.disabled_by_script end)), tostring(read(function() return car.minable_flag end)))
end

local function trunk_count(car)
  local inventory = car.get_inventory(defines.inventory.car_trunk)
  return inventory and inventory.get_item_count(SPICE) or 0
end

-- Gas geben oder loslassen: riding_state am Fahrzeug und am Dummy-Fahrer (wie T2).
local function gas(car, driver, on)
  local state =
  {
    acceleration = on and defines.riding.acceleration.accelerating or defines.riding.acceleration.nothing,
    direction = defines.riding.direction.straight
  }
  pcall(function() car.riding_state = state end)
  if valid(driver) then pcall(function() driver.riding_state = state end) end
end

local function verdict(run, tb, number, title, failed, values)
  local level = #failed == 0 and "OK" or "FEHLER"
  local text = number .. ") " .. title .. ": " .. values
  if #failed > 0 then text = text .. " | nicht erfüllt: " .. table.concat(failed, "; ") end
  tb.log(run, level, text)
  run.data.results[number] = level
  return "end"
end

local function check(failed, ok, label)
  if not ok then table.insert(failed, label) end
  return ok
end

-- Für die Testdateien scripts/testbench/tests/ (eine je Test; aufgeteilt aus t_ernter.lua, Verhalten unverändert).
return
{
  harvester = harvester,
  NAME = NAME,
  SPICE = SPICE,
  valid = valid,
  force_of = force_of,
  copy_pos = copy_pos,
  at = at,
  pos_text = pos_text,
  read = read,
  state_of = state_of,
  flags_text = flags_text,
  trunk_count = trunk_count,
  gas = gas,
  verdict = verdict,
  check = check,
}
