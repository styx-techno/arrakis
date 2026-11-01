-- Wurm-Reviere (Phase 3g, docs/plan-3g.md): Zuschnitt, Stufe, Name und Zustand der Reviere.
-- Bibliothek für __core__/lualib/event_handler. Die Modultabelle heißt lib; andere Dateien binden sie als territory_lib.
--
-- Ein Revier ist reine Skriptbuchhaltung über den Sektoren (4×4 Chunks = 128×128 Kacheln, scripts/vibration.lua). Die
-- Engine-Territorien nutzen wir nicht (Design 2.5, Jagdwurm auf Abruf).
--
-- Zuschnitt auf Arrakis (Plan 1.1 a): Raster aus Zellen von CELL × CELL Kacheln. Jede Zelle hat einen Mittelpunkt, aus
-- dem Kartenseed um bis zu ±JITTER/2 Zellen verschoben. Jeder Sektor gehört zum nächsten Mittelpunkt (Abstand zur
-- Sektormitte, gleich weit: kleinere Zellnummer). Die Revier-ID ist chunk_key(gx, gy) der Zelle.
-- Auf allen anderen Oberflächen (auch der Prüfstand-Fläche) ist jeder Sektor sein eigenes Revier, Stufe normal, damit
-- alte Erwartungen gelten. Der Prüfstand kann eine Oberfläche mit lib.test_real(surface, seed) auf echten Zuschnitt
-- stellen und Stufen mit lib.test_level setzen.
--
-- storage.territory =
--   {seed = {[s] = n}, cache = {[s] = {[sector_key] = id}}, info = {[s] = {[id] = {level, x, y, gx, gy}}},
--    free = {[s] = {[id] = Ende-Tick}}, announced = {[s] = {[id] = true}}, real = {[s] = seed}, levels = {[s] = {[id] = level}}}

local vibration_lib = require("scripts.vibration")

local lib = {}

local ARRAKIS = "arrakis"
local SECTOR_TILES = 128
local MOD = 2147483647

-- Zellgröße (Kacheln) und Verschiebung der Mittelpunkte (Anteil der Zelle, gesamt).
lib.CELL = 256
lib.JITTER = 0.5
-- Forschung „Revierkunde“ (Plan 1.4 c): erst danach zeigen Anzeige und Leitstelle die Reviere.
lib.SURVEY_TECH = "arrakis-territory-survey"
-- Stufen (Plan 3). Mittelpunkt näher als START_RADIUS am Landeplatz (0, 0): ruhig. Das deckt das Lehrfeld (140 Kacheln
-- vom Start) sicher ab: Sektormitte ≤ 91, nächster Mittelpunkt ≤ 272 Kacheln weg, zusammen < 520. JITTER 0,5 statt 0,6: Mit 0,6 gab es Reviere aus nur einem Sektor (T30, Seed 4711).
lib.START_RADIUS = 520
lib.NEAR_RADIUS = 1100
-- Anteile {ruhig, normal} (Rest wild) zwischen START_RADIUS und NEAR_RADIUS bzw. darüber.
lib.SHARE_NEAR = {0.30, 0.85}
lib.SHARE_FAR = {0.10, 0.60}
-- Wirkung je Stufe: Faktor auf die Schwelle des Wurmzeichens, Countdown-Zuschlag (Ticks), Faktor auf die Ruhe.
lib.LEVELS =
{
  calm = {threshold = 1.4, warn = 900, rest = 1.5, rank = 1},
  normal = {threshold = 1, warn = 0, rest = 1, rank = 2},
  wild = {threshold = 0.7, warn = -600, rest = 0.5, rank = 3}
}
-- Countdown nie unter so vielen Ticks (Plan 2).
lib.MIN_WARN = 1800
-- Getöteter Wurm (Plan 1.3 b): Revier so lange frei; Ankündigung so viele Ticks vor dem Ende.
lib.FREE_TICKS = 216000
lib.ANNOUNCE_TICKS = 3600

-- Speicher ----------------------------------------------------------------------------------------

local function data()
  local t = storage.territory
  if not t then
    t = {}
    storage.territory = t
  end
  t.seed = t.seed or {}
  t.cache = t.cache or {}
  t.info = t.info or {}
  t.free = t.free or {}
  t.announced = t.announced or {}
  t.real = t.real or {}
  t.levels = t.levels or {}
  return t
end

function lib.init()
  data()
end

-- Zufall aus Seed und Zelle ----------------------------------------------------------------------

-- (a · b) mod MOD für 0 ≤ a, b < MOD ohne Genauigkeitsverlust (alle Zwischenwerte < 2^48).
local function mulmod(a, b)
  local a1 = math.floor(a / 65536)
  local a0 = a % 65536
  return ((a1 * b % MOD) * 65536 + a0 * b) % MOD
end

-- Ganzzahl in [0, MOD), nur aus Seed, gx, gy und salt; quadratisches Mischen, damit Nachbarzellen unabhängig sind.
local function hash(seed, gx, gy, salt)
  local h = (seed % MOD + 1) % MOD
  for _, v in ipairs({gx, gy, salt, gx + gy}) do
    h = (h + (v % MOD) * 2654435 + 1013904) % MOD
    for _ = 1, 2 do h = (mulmod(h, h) + mulmod(h, 48271) + 12345) % MOD end
  end
  return h
end

local function unit(seed, gx, gy, salt)
  return hash(seed, gx, gy, salt) / MOD
end

-- Mittelpunkt (Kacheln) der Zelle gx, gy.
function lib.center(seed, gx, gy)
  local c = lib.CELL
  return (gx + 0.5) * c + (unit(seed, gx, gy, 1) - 0.5) * lib.JITTER * c,
    (gy + 0.5) * c + (unit(seed, gx, gy, 2) - 0.5) * lib.JITTER * c
end

-- Zelle des Sektors sx, sy (reine Rechnung, für den Prüfstand): gibt gx, gy zurück.
function lib.compute(seed, sx, sy)
  local px, py = (sx + 0.5) * SECTOR_TILES, (sy + 0.5) * SECTOR_TILES
  local hx, hy = math.floor(px / lib.CELL), math.floor(py / lib.CELL)
  local best_d, bx, by
  for gx = hx - 1, hx + 1 do
    for gy = hy - 1, hy + 1 do
      local x, y = lib.center(seed, gx, gy)
      local d = (x - px) ^ 2 + (y - py) ^ 2
      if not best_d or d < best_d or (d == best_d and (gx < bx or (gx == bx and gy < by))) then
        best_d, bx, by = d, gx, gy
      end
    end
  end
  return bx, by
end

-- Stufe der Zelle (reine Rechnung).
function lib.compute_level(seed, gx, gy)
  local x, y = lib.center(seed, gx, gy)
  local d = math.sqrt(x * x + y * y)
  if d < lib.START_RADIUS then return "calm" end
  local share = d < lib.NEAR_RADIUS and lib.SHARE_NEAR or lib.SHARE_FAR
  local u = unit(seed, gx, gy, 3)
  if u < share[1] then return "calm" end
  if u < share[2] then return "normal" end
  return "wild"
end

-- Oberflächen -------------------------------------------------------------------------------------

local function surface_of(s)
  if type(s) == "number" then return game.get_surface(s), s end
  if s and s.valid then return s, s.index end
  return nil, nil
end

-- Seed, wenn die Oberfläche echte Reviere hat, sonst nil (Sektor = Revier).
local function seed_of(s)
  local t = data()
  local real = t.real[s]
  if real then return real end
  local seed = t.seed[s]
  if seed then return seed ~= false and seed or nil end
  local surface = game.get_surface(s)
  if surface and surface.name == ARRAKIS then
    seed = surface.map_gen_settings.seed
  else
    seed = false
  end
  t.seed[s] = seed
  return seed or nil
end

function lib.real(s)
  local _, index = surface_of(s)
  return index ~= nil and seed_of(index) ~= nil
end

-- Abfragen ----------------------------------------------------------------------------------------

-- Revier eines Sektors.
function lib.of_sector(s, sector_key)
  local seed = seed_of(s)
  if not seed then return sector_key end
  local t = data()
  local cache = t.cache[s]
  if not cache then
    cache = {}
    t.cache[s] = cache
  end
  local id = cache[sector_key]
  if id then return id end
  local sx, sy = vibration_lib.chunk_of_key(sector_key)
  local gx, gy = lib.compute(seed, sx, sy)
  id = vibration_lib.chunk_key(gx, gy)
  cache[sector_key] = id
  return id
end

-- Revier eines Chunks (chunk_key) bzw. einer Position.
function lib.of_key(s, key)
  return lib.of_sector(s, vibration_lib.sector_of_key(key))
end

function lib.of_position(s, position)
  local _, sector = vibration_lib.key_of(position)
  return lib.of_sector(s, sector)
end

-- Angaben zum Revier: {level, x, y, gx, gy}; x, y ist der Mittelpunkt (Kacheln).
function lib.info(s, id)
  local t = data()
  local list = t.info[s]
  if not list then
    list = {}
    t.info[s] = list
  end
  local rec = list[id]
  if rec then return rec end
  local gx, gy = vibration_lib.chunk_of_key(id)
  local seed = seed_of(s)
  if seed then
    local x, y = lib.center(seed, gx, gy)
    rec = {level = lib.compute_level(seed, gx, gy), x = x, y = y, gx = gx, gy = gy}
  else
    -- Sektor = Revier: gx, gy sind Sektor-Koordinaten.
    rec = {level = "normal", x = (gx + 0.5) * SECTOR_TILES, y = (gy + 0.5) * SECTOR_TILES, gx = gx, gy = gy, sector = true}
  end
  list[id] = rec
  return rec
end

-- Stufe (Prüfstand-Vorgabe vor der Rechnung).
function lib.level(s, id)
  local over = data().levels[s]
  if over and over[id] then return over[id] end
  return lib.info(s, id).level
end

local function params(s, id)
  return lib.LEVELS[lib.level(s, id)] or lib.LEVELS.normal
end

-- Schwelle des Wurmzeichens für den Chunk key.
function lib.threshold(s, key)
  return vibration_lib.WORMSIGN * params(s, lib.of_key(s, key)).threshold
end

-- Countdown (Ticks) einer regulären Jagd im Revier, aus dem Grundwert base (mit Frühwarnung).
function lib.warn_ticks(s, id, base)
  return math.max(lib.MIN_WARN, base + params(s, id).warn)
end

function lib.rest_factor(s, id)
  return params(s, id).rest
end

-- Rang für die Leitstelle (1 ruhig, 2 normal oder frei, 3 wild).
function lib.rank(s, id)
  local rank = params(s, id).rank
  if rank > 2 and lib.free_until(s, id) then rank = 2 end
  return rank
end

-- Alle Sektoren des Reviers (für die Ruhe des ganzen Reviers).
function lib.sectors_of(s, id)
  local seed = seed_of(s)
  if not seed then return {id} end
  local rec = lib.info(s, id)
  local per = lib.CELL / SECTOR_TILES
  local list = {}
  for sx = (rec.gx - 1) * per, (rec.gx + 2) * per - 1 do
    for sy = (rec.gy - 1) * per, (rec.gy + 2) * per - 1 do
      local sector = vibration_lib.chunk_key(sx, sy)
      if lib.of_sector(s, sector) == id then list[#list + 1] = sector end
    end
  end
  return list
end

-- Ganzes Revier ruhen lassen (ersetzt eine kürzere Ruhe nicht durch eine längere: jede Ruhe gilt wie bisher neu).
function lib.rest(s, id, ticks)
  for _, sector in ipairs(lib.sectors_of(s, id)) do
    vibration_lib.rest(s, sector, ticks)
  end
end

-- Name als LocalisedString, z. B. „Revier N3-O2“ (Richtung und Zellen vom Landeplatz).
function lib.name(s, id)
  local rec = lib.info(s, id)
  if rec.sector then return {"arrakis-message.territory-name-sector", rec.gx, rec.gy} end
  local ns = rec.gy < 0 and "n" or "s"
  local ew = rec.gx < 0 and "w" or "e"
  local nn = rec.gy < 0 and -rec.gy or rec.gy + 1
  local en = rec.gx < 0 and -rec.gx or rec.gx + 1
  return {"arrakis-message.territory-name", {"", {"arrakis-message.dir-" .. ns}, tostring(nn)},
    {"", {"arrakis-message.dir-" .. ew}, tostring(en)}}
end

function lib.level_name(s, id)
  return {"arrakis-message.territory-level-" .. lib.level(s, id)}
end

-- Kennt die Force die Reviere (Revierkunde erforscht)?
function lib.known(force)
  local tech = force and force.valid and force.technologies[lib.SURVEY_TECH]
  return tech ~= nil and tech.researched
end

-- Freies Revier (Plan 1.3) ---------------------------------------------------------------------------

function lib.free_until(s, id)
  local list = data().free[s]
  local until_tick = list and list[id]
  if until_tick and until_tick > game.tick then return until_tick end
  return nil
end

local function print_all(message)
  for _, force in pairs(game.forces) do
    if storage.grace and storage.grace[force.index] then force.print(message) end
  end
end

local function gps(s, id)
  local rec = lib.info(s, id)
  local surface = game.get_surface(s)
  return string.format("[gps=%d,%d,%s]", math.floor(rec.x), math.floor(rec.y), surface and surface.name or "")
end

-- Wurm des Reviers getötet: frei bis tick + ticks (Standard FREE_TICKS).
function lib.set_free(s, id, ticks)
  local t = data()
  t.free[s] = t.free[s] or {}
  t.free[s][id] = game.tick + (ticks or lib.FREE_TICKS)
  if t.announced[s] then t.announced[s][id] = nil end
  print_all({"arrakis-message.msg-territory-free", lib.name(s, id), gps(s, id), math.floor((ticks or lib.FREE_TICKS) / 3600)})
end

-- 60-Tick-Takt (aus scripts/worms.lua): Ankündigung vor dem Ende, abgelaufene Einträge weg.
function lib.tick(tick)
  local t = storage.territory
  if not (t and t.free and next(t.free)) then return end
  for s, list in pairs(t.free) do
    for id, until_tick in pairs(list) do
      if until_tick <= tick then
        list[id] = nil
        if t.announced[s] then t.announced[s][id] = nil end
      elseif until_tick - tick <= lib.ANNOUNCE_TICKS then
        t.announced[s] = t.announced[s] or {}
        if not t.announced[s][id] then
          t.announced[s][id] = true
          print_all({"arrakis-message.msg-territory-return", lib.name(s, id), gps(s, id),
            math.ceil((until_tick - tick) / 60)})
        end
      end
    end
    if next(list) == nil then t.free[s] = nil end
  end
end

-- Oberfläche weg: alles dazu vergessen.
function lib.drop_surface(s)
  local t = storage.territory
  if not t then return end
  for _, name in ipairs({"seed", "cache", "info", "free", "announced", "real", "levels"}) do
    if t[name] then t[name][s] = nil end
  end
end

-- Prüfstand-Haken ---------------------------------------------------------------------------------

-- Echte Reviere auf einer Oberfläche (seed) oder zurück auf Sektor = Revier (nil).
function lib.test_real(surface, seed)
  local _, s = surface_of(surface)
  local t = data()
  t.real[s] = seed
  t.cache[s] = nil
  t.info[s] = nil
  t.seed[s] = nil
end

function lib.test_level(surface, id, level)
  local _, s = surface_of(surface)
  local t = data()
  t.levels[s] = t.levels[s] or {}
  t.levels[s][id] = level
end

-- Alles auf der Oberfläche zurücksetzen (Stufen, frei, Ankündigungen).
function lib.test_reset(surface)
  local _, s = surface_of(surface)
  local t = data()
  t.levels[s] = nil
  t.free[s] = nil
  t.announced[s] = nil
end

-- Ereignisse --------------------------------------------------------------------------------------

lib.on_init = lib.init
lib.on_configuration_changed = lib.init

lib.events =
{
  [defines.events.on_pre_surface_deleted] = function(event) lib.drop_surface(event.surface_index) end,
  [defines.events.on_surface_cleared] = function(event)
    local t = storage.territory
    if t then
      if t.free then t.free[event.surface_index] = nil end
      if t.announced then t.announced[event.surface_index] = nil end
    end
  end
}

-- Für die Vibrationsanzeige (scripts/vibration.lua darf territory nicht laden: Ring beim require).
vibration_lib.territory = lib

return lib
