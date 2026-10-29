-- Vibration (Phase 3d1, docs/plan-3d1.md 4.3, 4.4, 4.11, 4.12): Quellen und Gewichte, Wärme je Chunk mit Zerfall,
-- 3×3-Summen, Sektoren und Ruhe, Vorsichtsmodus, Unruhe (Status, Staub, Rumpeln) und Vibrationsanzeige.
-- Bibliothek für __core__/lualib/event_handler. Daten nur in storage (Schema 3, siehe scripts/migrate.lua). Die Takte
-- (tick, careful_tick, unrest_tick, overlay_tick) ruft nur scripts/worms.lua in fester Reihenfolge aus seinem
-- on_nth_tick(60) (Plan 4.4): event_handler sichert keine Reihenfolge zwischen Modulen zu. Die Modultabelle heißt lib
-- (tools/check/api_names.py); andere Dateien binden sie als vibration_lib.
--
-- Wärme gehört der Oberfläche, nicht der Force (Plan 4.14). Je Oberfläche s:
--   storage.vib.heat[s] = {tick, chunks = {[chunk_key] = h}, sum3 = {[chunk_key] = S}, prev3 = {[chunk_key] = S}}
--   H ← H · 0,98^Δs + ΣV · min(Δs, 2) im 60-Tick-Takt; S(c) = Wärme der 3×3 Chunks um c, prev3 die des Takts davor.
--   W am Ort einer Quelle = größtes S(d) über die 3×3 Chunks d um ihren Chunk (near_heat).
-- Quellen: Ernter über storage.harvesters (Gewicht aus dem Zustand), andere in storage.vib.sources[un] =
--   {un, entity, kind = "vehicle"|"fixed", base, sand, weight, key, surface} (Plan 4.2). weight und vib_weight sind das
--   Gewicht, mit dem die Quelle in diesem Takt beiträgt: 0 abseits vom Sand und auf der Prüfstand-Fläche für Forces,
--   die nicht eingeschaltet sind (Plan 4.3, 4.18).
-- Sand ist die natürliche Kachel ungleich arrakis-rock (scripts/terrain.lua); Ernter und Fahrzeuge an ihrer Mitte,
-- feste Quellen unter ihrer Box (beim Anmelden und bei Kachel-Ereignissen).

local terrain = require("scripts.terrain")
local harvester = require("scripts.harvester")

local lib = {}

local ROCK = "arrakis-rock"
local TESTBENCH_SURFACE = "arrakis-testbench"
local OVERLAY = "arrakis-vibration-overlay"
local DUST = "arrakis-sand-dust"
local RUMBLE = "arrakis-rumble"
local FLYER = "arrakis-ornithopter"

-- Zerfall je Sekunde (Faktor auf die Wärme).
lib.DECAY = 0.98
-- Größtes Δs je Takt beim Zufluss (Sekunden), Absicherung wie beim Ernter (Δs ist im 60-Tick-Takt immer 1).
lib.MAX_DT = 2
-- Unruhe ab dieser Wärme W.
lib.UNREST = 600
-- Wurmzeichen ab dieser 3×3-Summe (mit Unruhe im Takt davor, scripts/worms.lua).
lib.WORMSIGN = 1000
-- Vorsichtsmodus: wieder aufbauen unter dieser Wärme.
lib.CAREFUL_LOW = 300
-- Vorsichtsmodus: weiter als so viele Kacheln vom Wartepunkt gefahren beendet das Warten.
lib.CAREFUL_RANGE = 0.25
-- Ab diesem Tempo (Kacheln/Tick, Betrag) fährt ein Fahrzeug.
lib.MOVING = 0.001
-- Gewichte (Vibration je Sekunde, Plan 4.3). by_state: Spice-Ernter nach Zustand; by_name vor by_type; andere Typen
-- tragen nicht bei.
lib.WEIGHTS =
{
  by_state = {deployed = 30, packing = 30, careful_packing = 0, deploying = 0, moving = 10},
  by_name = {tank = 8, ["big-mining-drill"] = 8, pumpjack = 2},
  by_type = {car = 4, ["spider-vehicle"] = 6, locomotive = 6, ["mining-drill"] = 3, ["assembling-machine"] = 1, furnace = 1}
}
-- Höchstens so viele Quellen je Oberfläche und Takt zeigen Staub.
lib.DUST_MAX = 24
-- Rumpeln je Sektor höchstens alle so viele Ticks.
lib.RUMBLE_TICKS = 300
-- Vibrationsanzeige: Chunks um den Chunk der Spieleransicht (3 → 7×7).
lib.OVERLAY_RADIUS = 3

-- Schlüssel (Plan 4.2): chunk_key(cx, cy) = (cx + 65536) · 131072 + (cy + 65536), Sektor ebenso aus floor(c / 4).
local OFFSET = 65536
local SPAN = 131072
local CHUNK = 32
local SECTOR = 4

local VEHICLE = {car = true, ["spider-vehicle"] = true, locomotive = true}
local FIXED = {["mining-drill"] = true, ["assembling-machine"] = true, furnace = true}
local SCAN_TYPES = {"car", "spider-vehicle", "locomotive", "mining-drill", "assembling-machine", "furnace"}
local FIXED_TYPES = {"mining-drill", "assembling-machine", "furnace"}
-- Ernter stehen in storage.harvesters, der Ornithopter vibriert nicht (Plan 1 „Gewichte sonst“).
local EXCLUDED = {[harvester.NAME] = true, [FLYER] = true, ["arrakis-carryall"] = true}

local OVERLAY_COLOR =
{
  green = {r = 0.2, g = 0.8, b = 0.2, a = 0.25},
  yellow = {r = 0.9, g = 0.8, b = 0.1, a = 0.3},
  red = {r = 1, g = 0.15, b = 0.1, a = 0.35},
  rest = {r = 0.5, g = 0.5, b = 0.5, a = 0.3}
}
local OVERLAY_TEXT_COLOR = {r = 1, g = 1, b = 1, a = 0.9}

-- Hilfen ----------------------------------------------------------------------------------------

local function xy(position)
  return position.x or position[1], position.y or position[2]
end

local function distance(a, b)
  local ax, ay = xy(a)
  local bx, by = xy(b)
  return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- Oberflächen-Index aus LuaSurface oder Zahl.
local function index_of(surface)
  if type(surface) == "number" then return surface end
  if surface and surface.valid then return surface.index end
  return nil
end

-- Zeit m:ss aus Ticks (aufgerundet auf ganze Sekunden).
local function mmss(ticks)
  local s = math.max(0, math.ceil(ticks / 60))
  return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function moving(entity)
  local speed = entity.speed or 0
  return speed >= lib.MOVING or speed <= -lib.MOVING
end

-- Sand an der Mitte (Ernter, Fahrzeuge).
local function sand_at(surface, position)
  local x, y = xy(position)
  return terrain.natural_tile_name(surface, x, y) ~= ROCK
end

-- Zählt die Oberfläche für diese Force? Arrakis immer, die Prüfstand-Fläche nur für eingeschaltete Forces (Plan 4.18).
local function counted(surface, force_index)
  if not terrain.harvest_allowed(surface) then return false end
  if surface.name ~= TESTBENCH_SURFACE then return true end
  return storage.vib.testbench[force_index] == true
end

-- Schlüssel ---------------------------------------------------------------------------------------

function lib.chunk_key(cx, cy)
  return (cx + OFFSET) * SPAN + (cy + OFFSET)
end

-- Sektor aus Chunk-Koordinaten (4×4 Chunks).
function lib.sector_key(cx, cy)
  return lib.chunk_key(math.floor(cx / SECTOR), math.floor(cy / SECTOR))
end

-- Chunk-Koordinaten zu einem chunk_key.
local function chunk_of_key(key)
  return math.floor(key / SPAN) - OFFSET, key % SPAN - OFFSET
end

local function sector_of_key(key)
  local cx, cy = chunk_of_key(key)
  return lib.sector_key(cx, cy)
end

-- chunk_key, sector_key einer Position.
function lib.key_of(position)
  local x, y = xy(position)
  local cx, cy = math.floor(x / CHUNK), math.floor(y / CHUNK)
  return lib.chunk_key(cx, cy), lib.sector_key(cx, cy)
end

-- Chunk-Koordinaten zu einem chunk_key (für scripts/worms.lua und den Prüfstand).
lib.chunk_of_key = chunk_of_key
lib.sector_of_key = sector_of_key

-- Wärme -------------------------------------------------------------------------------------------

-- 3×3-Summen neu, gestreut: Jeder Eintrag h im Chunk c zählt für die 9 Chunks um c (Plan 4.4 Schritt 6).
local function scatter(chunks)
  local sum = {}
  for key, h in pairs(chunks) do
    if h > 0 then
      for dx = -1, 1 do
        local column = key + dx * SPAN
        for dy = -1, 1 do
          local d = column + dy
          sum[d] = (sum[d] or 0) + h
        end
      end
    end
  end
  return sum
end

-- Größtes S(d) über die 9 Chunks d um key; ohne Wärme-Datensatz 0.
local function near_key(e, key)
  if not (e and key) then return 0 end
  local sum = e.sum3
  local best = 0
  for dx = -1, 1 do
    local column = key + dx * SPAN
    for dy = -1, 1 do
      local v = sum[column + dy]
      if v and v > best then best = v end
    end
  end
  return best
end
lib.near_key = near_key

-- W an einer Position (Vorsichtsmodus, Unruhe, Fenster); surface als LuaSurface oder Index.
function lib.near_heat(surface, position)
  local s = index_of(surface)
  local e = s and storage.vib.heat[s]
  if not e then return 0 end
  return near_key(e, (lib.key_of(position)))
end

-- S(c) für einen Chunk; 0 ohne Eintrag.
function lib.sum3(surface_index, key)
  local e = storage.vib.heat[index_of(surface_index) or 0]
  return e and e.sum3[key] or 0
end

-- Ruht der Sektor? Gibt den Ende-Tick zurück, sonst nil.
function lib.resting(surface_index, sector_key)
  local cool = storage.sector_cooldown[index_of(surface_index) or 0]
  local until_tick = cool and cool[sector_key]
  if until_tick and until_tick > game.tick then return until_tick end
  return nil
end

-- Sektor ruhen lassen (ersetzt eine laufende Ruhe; Plan 4.5).
function lib.rest(surface_index, sector_key, ticks)
  local s = index_of(surface_index)
  if not s then return end
  local cooldown = storage.sector_cooldown
  cooldown[s] = cooldown[s] or {}
  cooldown[s][sector_key] = game.tick + ticks
end

-- Die 9 Chunks um key auf 0 (auch über die Sektorgrenze) und die 3×3-Summen sofort neu, damit vor dem nächsten
-- Wurmzeichen wieder Unruhe kommt (Plan 4.5 „Ende einer Jagd“).
function lib.reset_around(surface_index, key)
  local e = storage.vib.heat[index_of(surface_index) or 0]
  if not (e and key) then return end
  local chunks = e.chunks
  for dx = -1, 1 do
    for dy = -1, 1 do
      local d = key + dx * SPAN + dy
      if chunks[d] then chunks[d] = 0 end
    end
  end
  e.sum3 = scatter(chunks)
end

-- Gewichte (Plan 4.3) -------------------------------------------------------------------------------

local function base_weight(entity)
  return lib.WEIGHTS.by_name[entity.name] or lib.WEIGHTS.by_type[entity.type] or 0
end

-- Gewicht eines Ernters aus seinem Zustand (ohne Sand).
local function harvester_weight(h, entity)
  local W = lib.WEIGHTS.by_state
  local state = h.state
  if state == "deployed" then return W.deployed end
  if state == "packing" then return h.careful_packing and W.careful_packing or W.packing end
  if state == "deploying" then return W.deploying end
  if state == "mobile" and moving(entity) then return W.moving end
  return 0
end

-- Gewicht und Sand einer Entity jetzt (für Fenster und Prüfstand): Ernter nach Zustand, Fahrzeuge nur fahrend, feste
-- Quellen nur bei status == working. Abseits vom Sand ist das Gewicht 0. Ohne Prüfstand-Regel (die wendet der Takt an).
function lib.weight_of(entity)
  if not (entity and entity.valid) then return 0, false end
  local surface = entity.surface
  if entity.name == harvester.NAME then
    local h = harvester.get(entity)
    if not h or h.state == "carried" then return 0, false end
    local sand = sand_at(surface, entity.position)
    return sand and harvester_weight(h, entity) or 0, sand
  end
  if EXCLUDED[entity.name] then return 0, false end
  local typ = entity.type
  if VEHICLE[typ] then
    local sand = sand_at(surface, entity.position)
    return (sand and moving(entity)) and base_weight(entity) or 0, sand
  end
  if FIXED[typ] then
    local record = entity.unit_number and storage.vib.sources[entity.unit_number]
    local sand
    if record then sand = record.sand == true else sand = terrain.has_sand_under(entity) end
    local working = entity.status == defines.entity_status.working
    return (sand and working) and base_weight(entity) or 0, sand
  end
  return 0, false
end

-- Quellen -------------------------------------------------------------------------------------------

-- Datensatz einer Quelle (nur storage.vib.sources; Ernter stehen in storage.harvesters) oder nil.
function lib.source_of(entity)
  if not (entity and entity.valid and entity.unit_number) then return nil end
  return storage.vib.sources[entity.unit_number]
end

-- Quelle anmelden (Plan 4.3): nur auf einer erlaubten Oberfläche, nur die Typen oben, eine je unit_number. Feste Quellen
-- nur auf Sand. Gibt den Datensatz zurück oder nil.
function lib.register(entity)
  local vib = storage.vib
  if not (vib and entity and entity.valid) then return nil end
  local typ = entity.type
  local kind = (VEHICLE[typ] and "vehicle") or (FIXED[typ] and "fixed") or nil
  if not kind or EXCLUDED[entity.name] then return nil end
  local un = entity.unit_number
  if not un then return nil end
  local surface = entity.surface
  if not terrain.harvest_allowed(surface) then return nil end
  local record = vib.sources[un]
  if record then return record end
  local sand = nil
  if kind == "fixed" then
    sand = terrain.has_sand_under(entity)
    if not sand then return nil end
  end
  record = {un = un, entity = entity, kind = kind, base = base_weight(entity), sand = sand, weight = 0, key = nil,
            surface = surface.index}
  vib.sources[un] = record
  return record
end

-- Meldet an, was fehlt (Migration, Prüfstand); area nil = ganze Oberfläche. Gibt die Zahl neu angemeldeter Quellen zurück.
function lib.scan(surface, area)
  if not (surface and surface.valid and terrain.harvest_allowed(surface)) then return 0 end
  local filter = {type = SCAN_TYPES}
  if area then filter.area = area end
  local sources = storage.vib.sources
  local n = 0
  for _, entity in pairs(surface.find_entities_filtered(filter)) do
    local un = entity.unit_number
    if un and not sources[un] and lib.register(entity) then n = n + 1 end
  end
  return n
end

-- Feste Quellen im Bereich der Kacheln neu werten, uneingetragene auf Sand anmelden (Plan 4.3 „Kachel-Ereignisse“).
local function retile(surface, tiles)
  if not (surface and surface.valid and terrain.harvest_allowed(surface)) then return end
  if not tiles or #tiles == 0 then return end
  local x1, y1, x2, y2
  for _, tile in pairs(tiles) do
    local x, y = xy(tile.position)
    if not x1 then
      x1, y1, x2, y2 = x, y, x, y
    else
      x1, y1 = math.min(x1, x), math.min(y1, y)
      x2, y2 = math.max(x2, x), math.max(y2, y)
    end
  end
  local sources = storage.vib.sources
  for _, entity in pairs(surface.find_entities_filtered{type = FIXED_TYPES, area = {{x1, y1}, {x2 + 1, y2 + 1}}}) do
    local record = entity.unit_number and sources[entity.unit_number]
    if record then
      record.sand = terrain.has_sand_under(entity)
    else
      lib.register(entity)
    end
  end
end

-- Wärme-Takt (Plan 4.4) ---------------------------------------------------------------------------------

-- Beitrag w zum Chunk key auf Oberfläche s vormerken (Rohgewicht; min(Δs, 2) kommt in update_surface dazu).
local function feed(contrib, s, key, w)
  local list = contrib[s]
  if not list then
    list = {}
    contrib[s] = list
  end
  list[key] = (list[key] or 0) + w
end

local function is_resting(cool, sector, tick)
  local until_tick = cool and cool[sector]
  return until_tick ~= nil and until_tick > tick
end

-- Ein Ernter auf keiner gewerteten Oberfläche (getragen, andere Oberfläche, Prüfstand-Fläche mit ausgeschalteter Force):
-- Felder genullt, sonst wählte das Wurmzeichen ihn nach einem alten vib_key (Plan 4.4 Schritt 3).
local function harvester_off(h)
  h.vib_weight = 0
  h.vib_key = nil
  h.vib_sand = false
  local changed = h.careful_wait ~= nil or h.careful_pos ~= nil
  h.careful_wait = nil
  h.careful_pos = nil
  if h.alarm_unrest then
    harvester.set_alarm(h, "unrest", nil)
  elseif changed then
    harvester.refresh_status(h)
  end
end

-- Schritte 1, 2 und 4 bis 7 für eine Oberfläche; raw = {[chunk_key] = Rohgewicht} aus Schritt 3 oder nil.
local function update_surface(s, tick, raw)
  local heat = storage.vib.heat
  local cooldown = storage.sector_cooldown
  local e = heat[s]
  local cool = cooldown[s]
  if not e then
    if not raw and not cool then return end
    e = {tick = tick - 60, chunks = {}, sum3 = {}, prev3 = {}}
    heat[s] = e
  end
  -- Ein per Prüfstand (set_heat) angelegter Datensatz hat noch keinen Takt: Er beginnt wie jeder neue mit tick − 60.
  local ds = (tick - (e.tick or (tick - 60))) / 60
  if ds < 0 then ds = 0 end
  local f = lib.DECAY ^ ds
  local m = math.min(ds, lib.MAX_DT)
  local chunks = e.chunks
  -- 2. Zerfall
  for key, h in pairs(chunks) do chunks[key] = h * f end
  -- 3. Zufluss (ruhende Sektoren sind schon ausgenommen)
  local fed = {}
  if raw then
    for key, w in pairs(raw) do
      chunks[key] = (chunks[key] or 0) + w * m
      fed[key] = true
    end
  end
  -- 4. Ruhe: abgelaufene streichen, in den übrigen Sektoren jeder Eintrag 0
  if cool then
    for sector, until_tick in pairs(cool) do
      if until_tick <= tick then cool[sector] = nil end
    end
    if next(cool) == nil then
      cooldown[s] = nil
    else
      for key in pairs(chunks) do
        if cool[sector_of_key(key)] then chunks[key] = 0 end
      end
    end
  end
  -- 5. Einträge unter 1 ohne Zufluss löschen
  for key, h in pairs(chunks) do
    if h < 1 and not fed[key] then chunks[key] = nil end
  end
  -- 6. 3×3-Summen
  e.prev3 = e.sum3
  e.sum3 = scatter(chunks)
  -- 7. Takt merken; ohne Einträge fliegt der Datensatz raus (beginnt neu mit tick − 60)
  e.tick = tick
  if next(chunks) == nil then heat[s] = nil end
end

-- 60-Tick-Takt Schritt 1 (nur aus scripts/worms.lua): Gewichte und Sand aller Quellen, dann Wärme je Oberfläche.
function lib.tick(tick)
  local vib = storage.vib
  local cooldown = storage.sector_cooldown
  local contrib = {}
  local active = {}
  for _, h in pairs(storage.harvesters) do
    local entity = h.entity
    local done = false
    if entity.valid and h.state ~= "carried" then
      local surface = entity.surface
      if counted(surface, entity.force.index) then
        done = true
        local s = surface.index
        local position = entity.position
        local sand = sand_at(surface, position)
        local w = sand and harvester_weight(h, entity) or 0
        local key, sector = lib.key_of(position)
        h.vib_weight = w
        h.vib_key = key
        h.vib_sand = sand
        active[s] = true
        if w > 0 and not is_resting(cooldown[s], sector, tick) then feed(contrib, s, key, w) end
      end
    end
    if not done and (h.vib_key or h.vib_weight ~= 0 or h.vib_sand or h.careful_wait or h.careful_pos or h.alarm_unrest) then
      harvester_off(h)
    end
  end
  local sources = vib.sources
  for un, record in pairs(sources) do
    local entity = record.entity
    if not entity.valid then
      sources[un] = nil
    else
      local surface = entity.surface
      if not terrain.harvest_allowed(surface) then
        sources[un] = nil
      else
        local s = surface.index
        record.surface = s
        active[s] = true
        if counted(surface, entity.force.index) then
          local position = entity.position
          local key, sector = lib.key_of(position)
          local w = 0
          if record.kind == "vehicle" then
            local sand = sand_at(surface, position)
            record.sand = sand
            if sand and moving(entity) then w = record.base end
          elseif record.sand and entity.status == defines.entity_status.working then
            w = record.base
          end
          record.weight = w
          record.key = key
          if w > 0 and not is_resting(cooldown[s], sector, tick) then feed(contrib, s, key, w) end
        else
          record.weight = 0
          record.key = nil
        end
      end
    end
  end
  local surfaces = {}
  for s in pairs(active) do surfaces[s] = true end
  for s in pairs(vib.heat) do surfaces[s] = true end
  for s in pairs(cooldown) do surfaces[s] = true end
  for s in pairs(surfaces) do
    local surface = game.get_surface(s)
    if surface and terrain.harvest_allowed(surface) then update_surface(s, tick, contrib[s]) end
  end
end

-- Vorsichtsmodus (Plan 4.11) --------------------------------------------------------------------------

-- Schalter je Ernter; nur die eigene Force (sonst Hinweis). Aus: Warten und Einpacken mit Gewicht 0 enden.
function lib.set_careful(h, on, player)
  local entity = h and h.entity
  if not (entity and entity.valid) then return false end
  if player and player.force.index ~= entity.force.index then
    if player.valid then
      player.create_local_flying_text{text = {"arrakis-message.hint-foreign"}, position = entity.position, surface = entity.surface}
    end
    return false
  end
  h.careful = on == true
  if not h.careful then
    h.careful_wait = nil
    h.careful_packing = nil
    harvester.refresh_status(h)
  end
  return true
end

local function careful_one(h, heat)
  local entity = h.entity
  if not entity.valid then return end
  local state = h.state
  if state == "docked" or state == "carried" then
    if h.careful_wait or h.careful_pos or h.careful_packing then
      h.careful_wait = nil
      h.careful_pos = nil
      h.careful_packing = nil
      harvester.refresh_status(h)
    end
    return
  end
  -- Nur auf einer gewerteten Oberfläche (vib_key aus diesem Takt, Plan 4.4 Schritt 3).
  if not h.vib_key then return end
  local surface = entity.surface
  local W = near_key(heat[surface.index], h.vib_key)
  if state == "deployed" then
    if W >= lib.UNREST then
      local position = entity.position
      if harvester.pack(h) then
        h.careful_wait = true
        h.careful_pos = {surface = surface.index, x = position.x, y = position.y}
        h.careful_packing = true
        harvester.refresh_status(h)
      end
    end
  elseif state == "deploying" then
    if W >= lib.UNREST then
      local position = entity.position
      harvester.to_mobile(h)
      h.careful_wait = true
      h.careful_pos = {surface = surface.index, x = position.x, y = position.y}
      harvester.refresh_status(h)
    end
  elseif state == "mobile" and h.careful_wait then
    local pos = h.careful_pos
    if not pos or pos.surface ~= surface.index or distance(entity.position, pos) > lib.CAREFUL_RANGE then
      -- Der Spieler fährt: Warten endet.
      h.careful_wait = nil
      harvester.refresh_status(h)
    elseif not moving(entity) and W < lib.CAREFUL_LOW then
      -- Ruhe: wieder aufbauen; auch wenn es nicht geht (kein Spice, nicht erlaubt), endet das Warten.
      harvester.deploy(h)
      h.careful_wait = nil
      h.careful_pos = nil
      harvester.refresh_status(h)
    end
  end
end

-- 60-Tick-Takt Schritt 2 (nur aus scripts/worms.lua), direkt nach der Wärme.
function lib.careful_tick(tick)
  local heat = storage.vib.heat
  for _, h in pairs(storage.harvesters) do
    if h.careful == true then careful_one(h, heat) end
  end
end

-- Unruhe (Plan 4.12) ------------------------------------------------------------------------------------

-- Staubwolken an festen Stellen aus Tick und unit_number (verbraucht keine Zufallszahlen).
local function dust(surface, source, t)
  local n = math.min(3, 1 + math.floor((source.W - lib.UNREST) / 200))
  local x, y = source.position.x, source.position.y
  local un = source.un
  for k = 1, n do
    local angle = math.rad((un * 37 + t * 11 + k * 97) % 360)
    local d = 3 + (un * 13 + t * 7 + k * 29) % 8
    surface.create_trivial_smoke{name = DUST, position = {x = x + d * math.cos(angle), y = y + d * math.sin(angle)}}
  end
end

-- 60-Tick-Takt Schritt 4 (nur aus scripts/worms.lua): Status „Der Sand bebt“, Staub, Rumpeln.
function lib.unrest_tick(tick)
  local vib = storage.vib
  local heat = vib.heat
  local shaking = {}
  local function add(s, entry)
    local list = shaking[s]
    if not list then
      list = {}
      shaking[s] = list
    end
    list[#list + 1] = entry
  end
  for un, h in pairs(storage.harvesters) do
    local entity = h.entity
    if entity.valid and h.vib_key and h.state ~= "carried" then
      local s = entity.surface.index
      local W = near_key(heat[s], h.vib_key)
      local unrest = (h.vib_sand and W >= lib.UNREST) or nil
      if (h.alarm_unrest or nil) ~= unrest then harvester.set_alarm(h, "unrest", unrest) end
      if unrest and h.vib_weight > 0 then add(s, {un = un, W = W, key = h.vib_key, position = entity.position}) end
    elseif h.alarm_unrest then
      harvester.set_alarm(h, "unrest", nil)
    end
  end
  for un, record in pairs(vib.sources) do
    if record.weight > 0 and record.key and record.entity.valid then
      local W = near_key(heat[record.surface], record.key)
      if W >= lib.UNREST then add(record.surface, {un = un, W = W, key = record.key, position = record.entity.position}) end
    end
  end
  local t = math.floor(tick / 60)
  for s, list in pairs(shaking) do
    local surface = game.get_surface(s)
    if surface then
      table.sort(list, function(a, b)
        if a.W ~= b.W then return a.W > b.W end
        return a.un < b.un
      end)
      for i = 1, math.min(#list, lib.DUST_MAX) do dust(surface, list[i], t) end
      -- Rumpeln am Ort der heißesten Quelle je Sektor (die Liste ist nach W sortiert).
      local rumble = vib.rumble[s] or {}
      local seen = {}
      for _, entry in ipairs(list) do
        local sector = sector_of_key(entry.key)
        if not seen[sector] then
          seen[sector] = true
          local last = rumble[sector]
          if not last or last <= tick - lib.RUMBLE_TICKS then
            surface.play_sound{path = RUMBLE, position = entry.position}
            rumble[sector] = tick
          end
        end
      end
      if next(rumble) ~= nil then vib.rumble[s] = rumble end
    end
  end
  -- Alte Einträge sperren nichts mehr; sonst wüchse vib.rumble mit jedem Sektor, der je bebte.
  for s, rumble in pairs(vib.rumble) do
    for sector, last in pairs(rumble) do
      if last <= tick - lib.RUMBLE_TICKS then rumble[sector] = nil end
    end
    if next(rumble) == nil then vib.rumble[s] = nil end
  end
end

-- Vibrationsanzeige (Plan 4.12) -----------------------------------------------------------------------

local function destroy_cell(cell)
  if cell.rect and cell.rect.valid then cell.rect.destroy() end
  if cell.text and cell.text.valid then cell.text.destroy() end
end

local function clear_cells(entry)
  for key, cell in pairs(entry.cells) do
    destroy_cell(cell)
    entry.cells[key] = nil
  end
end

-- Verknüpfung setzen; pcall, falls die Engine den Zustand einer noch gesperrten Verknüpfung nicht annimmt.
local function set_toggled(player, on)
  pcall(player.set_shortcut_toggled, OVERLAY, on)
end
lib.set_toggled = set_toggled

-- Anzeige aus: alle Objekte weg, Eintrag weg (die Verknüpfung stellt der Aufrufer).
function lib.overlay_off(player_index)
  local overlay = storage.vib and storage.vib.overlay
  local entry = overlay and overlay[player_index]
  if not entry then return end
  clear_cells(entry)
  overlay[player_index] = nil
end

-- 7×7 Chunks um die Stelle, die der Spieler sieht; nur für ihn, nur in der Spielansicht (render_mode game).
local function draw_overlay(player, entry, tick)
  local surface = player.surface
  if entry.surface ~= surface.index then
    clear_cells(entry)
    entry.surface = surface.index
  end
  if not terrain.harvest_allowed(surface) then
    clear_cells(entry)
    return
  end
  local s = surface.index
  local e = storage.vib.heat[s]
  local cool = storage.sector_cooldown[s]
  -- Lauert dort ein Wurm (0.11.0, scripts/worms.lua lurk_tick)? Dann heißt die Ruhe „Wurm lauert“.
  local lurk = storage.hunts and storage.hunts.lurk and storage.hunts.lurk[s]
  local x, y = xy(player.position)
  local ccx, ccy = math.floor(x / CHUNK), math.floor(y / CHUNK)
  local R = lib.OVERLAY_RADIUS
  local cells = entry.cells
  local keep = {}
  for cx = ccx - R, ccx + R do
    for cy = ccy - R, ccy + R do
      local key = lib.chunk_key(cx, cy)
      local stage, text
      local until_tick = cool and cool[lib.sector_key(cx, cy)]
      if until_tick and until_tick > tick then
        stage = "rest"
        local lurk_until = lurk and lurk[lib.sector_key(cx, cy)]
        if lurk_until and lurk_until > tick then
          text = {"arrakis-message.overlay-lurk", mmss(lurk_until - tick)}
        else
          text = {"arrakis-message.overlay-rest", mmss(until_tick - tick)}
        end
      else
        local v = e and e.sum3[key] or 0
        if v >= lib.WORMSIGN then
          stage = "red"
        elseif v >= lib.UNREST then
          stage = "yellow"
        elseif v >= 1 then
          stage = "green"
        end
        text = tostring(math.floor(v + 0.5))
      end
      if stage then
        keep[key] = true
        local cell = cells[key]
        if cell and not (cell.rect and cell.rect.valid and cell.text and cell.text.valid) then
          destroy_cell(cell)
          cell = nil
        end
        if cell then
          if cell.stage ~= stage then
            cell.rect.color = OVERLAY_COLOR[stage]
            cell.stage = stage
          end
          cell.text.text = text
        else
          local x1, y1 = cx * CHUNK, cy * CHUNK
          cells[key] =
          {
            rect = rendering.draw_rectangle{
              color = OVERLAY_COLOR[stage],
              filled = true,
              left_top = {x1 + 0.5, y1 + 0.5},
              right_bottom = {x1 + CHUNK - 0.5, y1 + CHUNK - 0.5},
              surface = surface,
              players = {player},
              draw_on_ground = true
            },
            text = rendering.draw_text{
              text = text,
              target = {x1 + CHUNK / 2, y1 + CHUNK / 2},
              surface = surface,
              players = {player},
              color = OVERLAY_TEXT_COLOR,
              scale = 3,
              alignment = "center",
              vertical_alignment = "middle",
              draw_on_ground = true
            },
            stage = stage
          }
        end
      end
    end
  end
  for key, cell in pairs(cells) do
    if not keep[key] then
      destroy_cell(cell)
      cells[key] = nil
    end
  end
end

-- 60-Tick-Takt Schritt 7 (nur aus scripts/worms.lua): Anzeigen und Verknüpfungszustand je verbundenem Spieler. Der
-- Vergleich jede Sekunde ersetzt on_player_joined_game beim Laden im Einzelspieler (A23 events.d.ts:2721) [V9].
function lib.overlay_tick(tick)
  local overlay = storage.vib.overlay
  for _, player in pairs(game.connected_players) do
    local entry = overlay[player.index]
    local want = entry ~= nil
    if player.is_shortcut_toggled(OVERLAY) ~= want then set_toggled(player, want) end
    if entry then draw_overlay(player, entry, tick) end
  end
end

-- Oberfläche gelöscht, geleert oder nicht mehr erlaubt: Wärme, Ruhe, Rumpeln, Quellen und Anzeigen dort weg.
function lib.drop_surface(surface_index)
  local vib = storage.vib
  vib.heat[surface_index] = nil
  storage.sector_cooldown[surface_index] = nil
  vib.rumble[surface_index] = nil
  for un, record in pairs(vib.sources) do
    if record.surface == surface_index then vib.sources[un] = nil end
  end
  for _, entry in pairs(vib.overlay) do
    if entry.surface == surface_index then clear_cells(entry) end
  end
end

-- Prüfstand-Haken (Plan 4.18) ---------------------------------------------------------------------------

-- Prüfstand-Fläche zählt für diese Force (sonst Gewicht 0, Plan 4.3).
function lib.testbench_enable(force)
  storage.vib.testbench[force.index] = true
end

function lib.testbench_disable(force)
  storage.vib.testbench[force.index] = nil
end

-- Wärme-Eintrag eines Chunks oder nil.
function lib.heat_entry(surface, key)
  local e = storage.vib.heat[index_of(surface) or 0]
  return e and e.chunks[key] or nil
end

-- Schreibt den Eintrag und rechnet die 3×3-Summen sofort neu (prev3 = sum3). Ein neuer Datensatz bekommt seinen Takt
-- erst im nächsten 60-Tick-Takt (dann wie jeder neue mit tick − 60, also Δs = 1).
function lib.set_heat(surface, cx, cy, h)
  local s = index_of(surface)
  if not s then return end
  local heat = storage.vib.heat
  local e = heat[s]
  if not e then
    e = {chunks = {}, sum3 = {}, prev3 = {}}
    heat[s] = e
  end
  e.chunks[lib.chunk_key(cx, cy)] = h
  e.sum3 = scatter(e.chunks)
  e.prev3 = e.sum3
end

-- Ereignisse ---------------------------------------------------------------------------------------

local function on_built(event)
  lib.register(event.entity)
end

-- Klon: eigene Quelle (eine Jagd folgt nie dem Klon, scripts/worms.lua).
local function on_cloned(event)
  lib.register(event.destination)
end

-- Einsteigen: Fahrzeuge finden, die ohne raise_built entstanden [V12].
local function on_driving_changed(event)
  local entity = event.entity
  if entity and entity.valid and VEHICLE[entity.type] and not lib.source_of(entity) then lib.register(entity) end
end

-- Teleport: Oberfläche neu werten; verlässt die Quelle die erlaubten, wird sie ausgetragen.
local function on_teleported(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.unit_number) then return end
  local sources = storage.vib.sources
  local record = sources[entity.unit_number]
  if not record then
    lib.register(entity)
    return
  end
  local surface = entity.surface
  if not terrain.harvest_allowed(surface) then
    sources[record.un] = nil
    return
  end
  record.surface = surface.index
  if record.kind == "fixed" then record.sand = terrain.has_sand_under(entity) end
end

local function on_tiles(event)
  retile(game.get_surface(event.surface_index), event.tiles)
end

-- Klick: storage gilt, nicht der Zustand der Verknüpfung. Der kann bis zum nächsten overlay_tick abweichen (Laden im
-- Einzelspieler [V9], fremdes set_shortcut_toggled); sonst ersetzte ein Klick einen bestehenden Eintrag, und dessen
-- Render-Objekte blieben für immer liegen.
local function on_shortcut(event)
  if event.prototype_name ~= OVERLAY then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local on = storage.vib.overlay[player.index] == nil
  set_toggled(player, on)
  if on then
    local entry = {surface = player.surface.index, cells = {}}
    storage.vib.overlay[player.index] = entry
    draw_overlay(player, entry, game.tick)
  else
    lib.overlay_off(player.index)
  end
end

-- Oberflächenwechsel: nur die Zellen weg, der Eintrag bleibt (neu im nächsten Takt).
local function on_player_changed_surface(event)
  local entry = storage.vib.overlay[event.player_index]
  if entry then clear_cells(entry) end
end

local function on_player_joined_game(event)
  local player = game.get_player(event.player_index)
  if player then set_toggled(player, storage.vib.overlay[player.index] ~= nil) end
end

local function on_player_gone(event)
  lib.overlay_off(event.player_index)
end

-- Verschmelzen: Prüfstand-Merker der Quelle löschen (Indizes werden wiederverwendet, A23 classes.d.ts:11510).
local function on_forces_merging(event)
  local source = event.source
  if source and source.valid then storage.vib.testbench[source.index] = nil end
end

local function on_surface_gone(event)
  lib.drop_surface(event.surface_index)
end

lib.events =
{
  [defines.events.on_built_entity] = on_built,
  [defines.events.on_robot_built_entity] = on_built,
  [defines.events.script_raised_built] = on_built,
  [defines.events.script_raised_revive] = on_built,
  [defines.events.on_entity_cloned] = on_cloned,
  [defines.events.on_player_driving_changed_state] = on_driving_changed,
  [defines.events.script_raised_teleported] = on_teleported,
  [defines.events.on_player_built_tile] = on_tiles,
  [defines.events.on_robot_built_tile] = on_tiles,
  [defines.events.script_raised_set_tiles] = on_tiles,
  [defines.events.on_lua_shortcut] = on_shortcut,
  [defines.events.on_player_changed_surface] = on_player_changed_surface,
  [defines.events.on_player_joined_game] = on_player_joined_game,
  [defines.events.on_player_left_game] = on_player_gone,
  [defines.events.on_player_removed] = on_player_gone,
  [defines.events.on_forces_merging] = on_forces_merging,
  [defines.events.on_pre_surface_deleted] = on_surface_gone,
  [defines.events.on_surface_cleared] = on_surface_gone
}

return lib
