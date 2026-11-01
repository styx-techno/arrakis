-- Prüfstand: Ernter-Tests T2, T3, T4 (Vertrag siehe runner.lua).
--   T2: Skriptfahrt, Höchsttempo je Brennstoff, Tempo-Deckel alle 10 Ticks (nur Messung), Sperre (disabled_by_script), Status.
--   T3: Teleport zur Ablage-Oberfläche und zurück, Zustandsvergleich, Gegenprobe mit clone.
--   T4: Annahme und Tankstutzen (proxy-container) mit Greifarmen, Schaltung und Bauregel.
-- Zustand nur in run.data (Zahlen, Texte, Positionen, LuaEntity-Referenzen; vor jeder Benutzung prüfen).

local HARVESTER = "arrakis-test-harvester"

-- Allgemeine Helfer ---------------------------------------------------------------------------

local function force_of(run, tb)
  local player = tb.player(run)
  return player and player.force or "player"
end

local function copy_pos(position)
  return {x = position.x or position[1], y = position.y or position[2]}
end

local function pos_text(tb, position)
  if not position then return "–" end
  local p = copy_pos(position)
  return "(" .. tb.num(p.x) .. ", " .. tb.num(p.y) .. ")"
end

local function count_text(value)
  if value == nil then return "–" end
  return tostring(value)
end

-- Rückgabe und Fehlermeldung eines pcall als Text.
local function result_text(ok, result)
  if ok then return "Rückgabe " .. tostring(result) .. ", Fehlermeldung –" end
  return "Rückgabe –, Fehlermeldung " .. tostring(result)
end

-- Name eines ItemIDAndQualityIDPair (gelesen: LuaItemPrototype/LuaQualityPrototype) als "name@qualität".
local function item_pair_name(pair)
  if not pair then return "–" end
  local name, quality = pair.name, pair.quality
  if name and type(name) ~= "string" then name = name.name end
  if quality and type(quality) ~= "string" then quality = quality.name end
  return tostring(name) .. "@" .. tostring(quality or "normal")
end

-- Für die Testdateien scripts/testbench/tests/ (eine je Test; aufgeteilt aus t_harvester.lua, Verhalten unverändert).
return
{
  HARVESTER = HARVESTER,
  force_of = force_of,
  copy_pos = copy_pos,
  pos_text = pos_text,
  count_text = count_text,
  result_text = result_text,
  item_pair_name = item_pair_name,
}
