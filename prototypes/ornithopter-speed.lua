-- Tempo des Ornithopters je Brennstoff (0.6.1, docs/plan-3c.md 4.9) [U6, U7]. Reines Lua ohne data, game und storage:
-- Die Datenstufe legt damit die Sticker an (prototypes/ornithopter.lua) und prüft sie (tools/check/checks.lua), die
-- Laufzeit wählt damit den Sticker (scripts/flyer.lua) und der Prüfstand liest die Namen (T15, T16). Vorbild:
-- scripts/migrate.lua lädt prototypes.planet.planet-map-gen auch zur Laufzeit.
--
-- Gemessen im Prüfstand-Lauf vom 26.10.2026 (0.6.0, T16): Das Tempo ist proportional zum Höchsttempo-Faktor t des
-- Brennstoffs (Kohle und Spice-Brikett 1, Festbrennstoff 1,05, Raketen- und Atomtreibstoff 1,15, je plus
-- Qualitätsbonus; legendärer Raketentreibstoff 1,375, gemessen 1,385) und etwa proportional zu vehicle_speed_modifier.
-- Die Qualität des Ornithopters selbst wirkt nicht. Kohle, Osten: 0,52 → 6,90 Kacheln/s leer, 0,364 → 4,77 beladen.
-- Daraus die Basis für t = 1 (Vorschlag aus T16): leer 0,52 · 8 / 6,90 = 0,603 → 8,0 Kacheln/s, beladen
-- 0,364 · 5,6 / 4,77 = 0,427 → 5,6 Kacheln/s.
--
-- Stufen: t_j = 1,02^j für j = −35 … 70 (t ≈ 0,50 … 3,99), je Zustand ein Sticker
-- "arrakis-ornithopter-empty-<p>" bzw. "arrakis-ornithopter-loaded-<p>" mit p = floor(100 · t_j + 0,5) (Kohle p = 100,
-- Raketentreibstoff p = 115) und vehicle_speed_modifier = BASE / t_j. Die Stufe zu einem Brennstoff ist die nächste im
-- logarithmischen Abstand, der Tempo-Fehler also höchstens ±1 %. Brennstoffe außerhalb des Rasters (Fäulnis hat 0,5)
-- bekommen die Randstufe.

local speed = {}

-- Basis-Modifier für t = 1 (T16 vom 26.10.2026, siehe oben).
speed.BASE_EMPTY = 0.603
speed.BASE_LOADED = 0.427
-- Raster der Stufen.
speed.STEP = 1.02
speed.MIN_J = -35
speed.MAX_J = 70
-- Zustände in fester Reihenfolge; Namensanfang je Zustand.
speed.STATES = {"empty", "loaded"}
speed.PREFIX = {empty = "arrakis-ornithopter-empty-", loaded = "arrakis-ornithopter-loaded-"}

local BASE = {empty = speed.BASE_EMPTY, loaded = speed.BASE_LOADED}
local LOG_STEP = math.log(speed.STEP)

local factors = {}   -- j → t_j
local percents = {}  -- j → p
local names = {empty = {}, loaded = {}}  -- Zustand → j → Name
local parsed = {}    -- Name → {Zustand, j}

do
  local seen = {}
  for j = speed.MIN_J, speed.MAX_J do
    local t = speed.STEP ^ j
    local p = math.floor(100 * t + 0.5)
    assert(not seen[p], "ornithopter-speed: p = " .. p .. " doppelt (j = " .. tostring(seen[p]) .. " und " .. j .. ")")
    seen[p] = j
    factors[j] = t
    percents[j] = p
    for _, state in ipairs(speed.STATES) do
      local name = speed.PREFIX[state] .. p
      names[state][j] = name
      parsed[name] = {state, j}
    end
  end
end

-- Zahl der Stufen je Zustand (106).
speed.COUNT = speed.MAX_J - speed.MIN_J + 1

-- Faktor t_j der Stufe j.
function speed.factor(j)
  return factors[j]
end

-- p der Stufe j (Kohle 100).
function speed.percent(j)
  return percents[j]
end

-- Nächste Stufe zum Höchsttempo-Faktor t (im logarithmischen Abstand, auf das Raster begrenzt); t ≤ 0 oder nil zählt
-- wie 1.
function speed.bucket(t)
  if type(t) ~= "number" or t <= 0 then t = 1 end
  local j = math.floor(math.log(t) / LOG_STEP + 0.5)
  if j < speed.MIN_J then return speed.MIN_J end
  if j > speed.MAX_J then return speed.MAX_J end
  return j
end

-- Stickername zu Zustand ("empty", "loaded") und Stufe.
function speed.name(state, j)
  local list = names[state]
  return list and list[j]
end

-- vehicle_speed_modifier des Stickers: BASE des Zustands / t_j.
function speed.modifier(state, j)
  return BASE[state] / factors[j]
end

-- Zustand und Stufe zu einem Stickernamen; nil für jeden anderen Namen.
function speed.parse(name)
  local entry = parsed[name]
  if not entry then return nil end
  return entry[1], entry[2]
end

-- t_j als Text mit Komma und zwei Stellen, z. B. "1,15" (Prüfstand).
function speed.factor_text(j)
  local p = percents[j]
  if not p then return "?" end
  return string.format("%d,%02d", math.floor(p / 100), p % 100)
end

return speed
