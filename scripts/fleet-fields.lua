-- Feldsuche der Flottenleitung (Phase 3f, docs/plan-3f.md 1.5 und 3.2): Spice-Sand je Chunk zählen (budgetiert),
-- Plätze für einen Ernter bewerten, Ziele reservieren. Kein eigenes Ereignis-Modul: scripts/fleet.lua ruft tick im
-- 60-Tick-Takt und leitet on_resource_depleted weiter. Daten nur in storage.fields (Schema 6, scripts/migrate.lua).
--
-- storage.fields.chunks[surface_index][chunk_key] = {tick, dirty = true|nil, spots = {{x, y, sum}…}}: bis zu
--   lib.SPOTS_PER_CHUNK beste Plätze mit der Mitte im Chunk (Spice im Erntekreis ≥ lib.MIN_AMOUNT, untereinander
--   mindestens lib.SPACING Kacheln Abstand), absteigend nach sum.
-- storage.fields.queue = {{s, cx, cy}…}, storage.fields.queued[s][chunk_key] = true: Chunks, die noch zu zählen sind.
-- storage.fields.refill[depot_un] = tick: frühester Tick für die nächste Füllung der Warteschlange je Leitstelle.
-- storage.fields.claims[job_id] = {s, x, y}: Ziele laufender Aufträge (Einsatz, Umsetzen).

local harvester = require("scripts.harvester")
local worms_lib = require("scripts.worms")
local vibration_lib = require("scripts.vibration")

local lib = {}

local SPICE = "spice-sand"
local CHUNK = 32

-- Mindestmenge Spice-Sand im Erntekreis eines Platzes (Plan 1.5).
lib.MIN_AMOUNT = 20000
-- Mindestabstand zu anderen Erntern und Zielen (Kacheln, Plan 1.5).
lib.SPACING = 14
-- Plätze bis so weit um eine Kartenmarkierung mit Spice-Sand-Symbol kommen zuerst dran (Kacheln, Plan 1.5).
lib.TAG_RADIUS = 64
-- Höchstens so viele Chunks je 60-Tick-Takt zählen (Plan 3.2).
lib.CHUNKS_PER_CYCLE = 4
-- Eine Chunk-Zählung veraltet nach so vielen Ticks (Plan 3.2).
lib.MAX_AGE = 10 * 60 * 60
-- Warteschlange je Leitstelle höchstens so oft neu füllen (Ticks).
lib.REFILL_TICKS = 10 * 60
-- So viele Plätze merkt sich ein Chunk.
lib.SPOTS_PER_CHUNK = 4
-- So viele Kandidaten prüft find_spot vor Ort nach (Menge im Erntekreis jetzt).
lib.VERIFY = 8

local function data()
  local f = storage.fields
  if not f then
    f = {}
    storage.fields = f
  end
  f.chunks = f.chunks or {}
  f.queue = f.queue or {}
  f.queued = f.queued or {}
  f.refill = f.refill or {}
  f.claims = f.claims or {}
  return f
end

local function distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

-- Spice-Sand im Erntekreis um position (genau wie scripts/harvester.lua field_area).
function lib.amount_at(surface, position)
  local sum = 0
  for _, e in pairs(surface.find_entities_filtered{area = harvester.field_area(position), name = SPICE}) do
    sum = sum + e.amount
  end
  return sum
end

-- Ruhig für einen neuen Platz: kein lauernder Wurm, keine Ruhe des Sektors, keine Jagd im Sektor (Plan 1.5).
function lib.quiet(s, position)
  if worms_lib.lurking_at(s, position) then return false end
  local sector = vibration_lib.sector_of_key((vibration_lib.key_of(position)))
  if vibration_lib.resting(s, sector) then return false end
  local hunts = storage.hunts and storage.hunts.list
  for _, hunt in pairs(hunts or {}) do
    if hunt.surface_index == s and hunt.sector_key == sector then return false end
  end
  return true
end

-- Zählen ------------------------------------------------------------------------------------------

-- Beste Plätze mit der Mitte im Chunk (cx, cy): Summen der 13×13-Kacheln aus einer Summentabelle über den Chunk plus
-- Rand 6. Gibt die Platzliste zurück (leer ohne Spice).
local function count_chunk(surface, cx, cy)
  local x0, y0 = cx * CHUNK, cy * CHUNK
  if surface.count_entities_filtered{area = {{x0, y0}, {x0 + CHUNK, y0 + CHUNK}}, name = SPICE, limit = 1} == 0 then
    return {}
  end
  local bx, by = x0 - 6, y0 - 6
  local W = CHUNK + 12
  local grid = {}
  for _, e in pairs(surface.find_entities_filtered{area = {{bx, by}, {bx + W, by + W}}, name = SPICE}) do
    local p = e.position
    local i, j = math.floor(p.x) - bx, math.floor(p.y) - by
    if i >= 0 and i < W and j >= 0 and j < W then
      local k = i * W + j
      grid[k] = (grid[k] or 0) + e.amount
    end
  end
  -- P[(i)*(W+1)+j] = Summe über grid[0..i-1][0..j-1]
  local V = W + 1
  local P = {}
  for i = 0, W do P[i * V] = 0 end
  for j = 0, W do P[j] = 0 end
  for i = 1, W do
    local row = 0
    for j = 1, W do
      row = row + (grid[(i - 1) * W + (j - 1)] or 0)
      P[i * V + j] = P[(i - 1) * V + j] + row
    end
  end
  local sums = {}
  for a = 0, CHUNK - 1 do
    for b = 0, CHUNK - 1 do
      -- Kachel (x0 + a, y0 + b): Feld über grid[a..a+12][b..b+12]
      local i1, j1, i2, j2 = a, b, a + 13, b + 13
      sums[a * CHUNK + b] = P[i2 * V + j2] - P[i1 * V + j2] - P[i2 * V + j1] + P[i1 * V + j1]
    end
  end
  local spots = {}
  for _ = 1, lib.SPOTS_PER_CHUNK do
    local best, best_k = lib.MIN_AMOUNT - 1, nil
    for k, v in pairs(sums) do
      if v > best or (v == best and best_k and k < best_k) then best, best_k = v, k end
    end
    if not best_k then break end
    local a, b = math.floor(best_k / CHUNK), best_k % CHUNK
    local spot = {x = x0 + a + 0.5, y = y0 + b + 0.5, sum = best}
    table.insert(spots, spot)
    for k in pairs(sums) do
      local ka, kb = math.floor(k / CHUNK), k % CHUNK
      local dx, dy = ka - a, kb - b
      if dx * dx + dy * dy < lib.SPACING * lib.SPACING then sums[k] = nil end
    end
  end
  return spots
end

function lib.count(surface, cx, cy)
  local f = data()
  local s = surface.index
  f.chunks[s] = f.chunks[s] or {}
  local rec = {tick = game.tick, spots = count_chunk(surface, cx, cy)}
  f.chunks[s][vibration_lib.chunk_key(cx, cy)] = rec
  return rec
end

-- Chunks in Reichweite der Leitstelle d (kartiert von ihrer Force), die fehlen, veraltet oder markiert sind, in die
-- Warteschlange. range in Kacheln.
local function refill(d, range, tick)
  local f = data()
  if tick < (f.refill[d.un] or 0) then return end
  f.refill[d.un] = tick + lib.REFILL_TICKS
  local entity = d.entity
  local surface, force = entity.surface, entity.force
  local s = surface.index
  local chunks = f.chunks[s] or {}
  f.queued[s] = f.queued[s] or {}
  local queued = f.queued[s]
  local p = d.position
  local r = math.ceil(range / CHUNK) + 1
  local pcx, pcy = math.floor(p.x / CHUNK), math.floor(p.y / CHUNK)
  local reach = range + CHUNK * 0.75
  for cx = pcx - r, pcx + r do
    for cy = pcy - r, pcy + r do
      local mx, my = cx * CHUNK + CHUNK / 2, cy * CHUNK + CHUNK / 2
      local dx, dy = mx - p.x, my - p.y
      if dx * dx + dy * dy <= reach * reach then
        local key = vibration_lib.chunk_key(cx, cy)
        local rec = chunks[key]
        if not queued[key] and (not rec or rec.dirty or tick - rec.tick >= lib.MAX_AGE)
            and (f.skip_chart or force.is_chunk_charted(surface, {cx, cy})) then
          queued[key] = true
          table.insert(f.queue, {s = s, cx = cx, cy = cy})
        end
      end
    end
  end
end

-- 60-Tick-Takt: für jede Leitstelle mit Bedarf (depots: Liste von Datensätzen) nachfüllen, dann höchstens
-- CHUNKS_PER_CYCLE Chunks zählen.
function lib.tick(tick, depots, range)
  local f = data()
  for _, d in ipairs(depots) do refill(d, range, tick) end
  local n = 0
  while n < lib.CHUNKS_PER_CYCLE and #f.queue > 0 do
    local item = table.remove(f.queue, 1)
    local queued = f.queued[item.s]
    if queued then queued[vibration_lib.chunk_key(item.cx, item.cy)] = nil end
    local surface = game.get_surface(item.s)
    if surface then
      lib.count(surface, item.cx, item.cy)
      n = n + 1
    end
  end
  return n
end

-- Ein Spice-Feld wurde leer: Chunk neu zählen lassen.
function lib.on_resource_depleted(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.name == SPICE) then return end
  local f = data()
  local s = entity.surface.index
  local key = (vibration_lib.key_of(entity.position))
  local rec = f.chunks[s] and f.chunks[s][key]
  if rec then rec.dirty = true end
end

-- Reservierungen ----------------------------------------------------------------------------------

function lib.reserve(job_id, s, position)
  data().claims[job_id] = {s = s, x = position.x, y = position.y}
end

function lib.release(job_id)
  data().claims[job_id] = nil
end

-- Belegte Punkte auf der Oberfläche s: Ernter (außer exclude_un und getragenen), Rückwege wartender und getragener
-- Ernter, reservierte Ziele.
local function occupied(s, exclude_un)
  local list = {}
  for un, h in pairs(storage.harvesters) do
    local e = h.entity
    if un ~= exclude_un and e and e.valid then
      if h.state ~= "carried" and e.surface.index == s then table.insert(list, e.position) end
      local fw = h.fleet_wait
      if fw and fw.x and fw.surface == s then table.insert(list, {x = fw.x, y = fw.y}) end
    end
  end
  for _, job in pairs(storage.jobs.list) do
    local pos = job.return_pos
    if job.harvester ~= exclude_un and pos and pos.surface == s then table.insert(list, {x = pos.x, y = pos.y}) end
  end
  for _, r in pairs(data().claims) do
    if r.s == s then table.insert(list, {x = r.x, y = r.y}) end
  end
  return list
end

-- Kartenmarkierungen mit Spice-Sand-Symbol im Umkreis der Leitstelle.
local function spice_tags(d, range)
  local p = d.position
  local entity = d.entity
  local list = {}
  local area = {{p.x - range - lib.TAG_RADIUS, p.y - range - lib.TAG_RADIUS},
    {p.x + range + lib.TAG_RADIUS, p.y + range + lib.TAG_RADIUS}}
  for _, tag in pairs(entity.force.find_chart_tags(entity.surface, area)) do
    local icon = tag.icon
    if icon and icon.name == SPICE and (icon.type == nil or icon.type == "item") then table.insert(list, tag.position) end
  end
  return list
end

local function nearest_intake_distance(s, force_index, position)
  local best
  for _, record in pairs(storage.intakes or {}) do
    local e = record.entity
    if e and e.valid and e.surface.index == s and e.force.index == force_index and not record.bad then
      local dist = distance(e.position, position)
      if not best or dist < best then best = dist end
    end
  end
  return best or 0
end

-- Bester freier Platz für die Leitstelle d (Plan 1.5) oder nil. exclude_un: der Ernter, der umgesetzt wird (sein
-- eigener Ort zählt nicht als belegt). Gibt {x, y, sum, tagged} zurück.
function lib.find_spot(d, range, exclude_un)
  local f = data()
  local entity = d.entity
  local surface = entity.surface
  local s = surface.index
  local chunks = f.chunks[s]
  if not chunks then return nil end
  local busy = occupied(s, exclude_un)
  local tags = spice_tags(d, range)
  local force_index = entity.force.index
  local candidates = {}
  for _, rec in pairs(chunks) do
    for _, spot in ipairs(rec.spots) do
      local dd = distance(spot, d.position)
      if dd <= range and spot.sum >= lib.MIN_AMOUNT then
        local free = true
        for _, p in ipairs(busy) do
          if distance(p, spot) < lib.SPACING then free = false break end
        end
        if free and lib.quiet(s, spot) then
          local tagged = false
          for _, t in ipairs(tags) do
            if distance(t, spot) <= lib.TAG_RADIUS then tagged = true break end
          end
          local score = spot.sum / (1 + dd / 100 + nearest_intake_distance(s, force_index, spot) / 100)
          table.insert(candidates, {spot = spot, score = score, tagged = tagged})
        end
      end
    end
  end
  table.sort(candidates, function(a, b)
    if a.tagged ~= b.tagged then return a.tagged end
    if a.score ~= b.score then return a.score > b.score end
    if a.spot.x ~= b.spot.x then return a.spot.x < b.spot.x end
    return a.spot.y < b.spot.y
  end)
  for i = 1, math.min(#candidates, lib.VERIFY) do
    local c = candidates[i]
    local now = lib.amount_at(surface, c.spot)
    c.spot.sum = now
    if now >= lib.MIN_AMOUNT then
      return {x = c.spot.x, y = c.spot.y, sum = now, tagged = c.tagged}
    end
  end
  return nil
end

-- Zahl bekannter Plätze in Reichweite der Leitstelle (Fenster).
function lib.known_spots(d, range)
  local chunks = data().chunks[d.surface_index]
  local n = 0
  for _, rec in pairs(chunks or {}) do
    for _, spot in ipairs(rec.spots) do
      if spot.sum >= lib.MIN_AMOUNT and distance(spot, d.position) <= range then n = n + 1 end
    end
  end
  return n
end

-- Noch zu zählende Chunks (Fenster, Prüfstand).
function lib.queue_length()
  return #data().queue
end

-- Prüfstand: alles vergessen.
function lib.reset()
  storage.fields = {chunks = {}, queue = {}, queued = {}, refill = {}, claims = {}}
end

-- Nur für den Prüfstand: Ohne Spieler kartiert force.chart auf dem Server nichts (V6, docs/plan-3d1.md); bis zum
-- nächsten reset() zählt die Feldsuche dann auch nicht kartierte Chunks.
function lib.skip_chart()
  data().skip_chart = true
  data().refill = {}
end

return lib
