-- Prüfstand: Kartengenerator-Test T11 (Vertrag siehe runner.lua).
-- Läuft auf der echten Arrakis-Oberfläche (arrakis-surface.get_or_create) und liest dort nur;
-- verändert wird nichts außer der Chunk-Erzeugung. Der Spieler wird NICHT teleportiert.
--   1. Chunks im Radius 12 um 0,0 sofort erzeugen (vorher Hinweis im Chat, dann hängt das Spiel kurz).
--   2. Spicefelder: alle spice-sand im Gebiet, clustern (Gitter-Buckets + Union-Find, Nachbarschaft
--      ≤ 4 Kacheln), Gruppen < 20 ignorieren. Je Feld Mitte, Anzahl, Abstand vom Ursprung und
--      Felsabstand (Feldbox in 5er-Schritten vergrößern, count_tiles_filtered, bis 200).
--      Das Feld am nächsten am Ursprung ist der Lehrfeld-Kandidat (F1).
--   3. Schwellen-Kalibrierung: Raster alle 4 Kacheln, je Punkt Felsflag (Kachelname) und Wert von
--      arrakis_rock (calculate_tile_properties, in Blöcken), Felsabstand per Mehrquellen-BFS auf dem Raster.
--      Tabelle je Schwelle t (Spice nur bei arrakis_rock < t): kleinster Felsabstand und Flächenanteil.
-- Die Rechenlast ist über viele Ticks verteilt (Phasen in run.data.phase); der Zustand liegt als
-- reine Daten (Zahlen, Texte, Tabellen) in run.data.

local arrakis_surface = require("scripts.arrakis-surface")

local RADIUS_CHUNKS = 12
local SPICE = "spice-sand"
local ROCK_TILE = "arrakis-rock"
local ROCK_PROPERTY = "arrakis_rock"
local MIN_FIELD = 20                -- kleinere Gruppen sind keine Felder
local NEIGHBOUR_SQ = 4 * 4          -- Nachbarschaft ≤ 4 Kacheln (Abstand im Quadrat)
local BUCKET = 4                    -- Kantenlänge der Gitter-Buckets (= Nachbarschaft, also 3×3 Buckets prüfen)
local ROCK_STEP = 5                 -- Box-Suche: Schrittweite …
local ROCK_MAX = 200                -- … und größter Abstand
local GRID = 4                      -- Rasterabstand der Kalibrierung
local THRESHOLDS = {0, -0.1, -0.2, -0.25, -0.3, -0.35, -0.4, -0.5}
local TARGET = 100                  -- Mindestabstand Spicefeld → Fels (Design 4.1)
local WARN_TICKS = 30               -- Hinweis erst zeigen, dann Chunks erzeugen
local ENTITIES_PER_TICK = 2000
local POINTS_PER_TICK = 4000
local PROPERTY_BLOCK = 1000         -- Positionen je calculate_tile_properties-Aufruf
local ROCK_CALLS_PER_TICK = 10      -- count_tiles_filtered-Aufrufe je Tick
local BFS_PER_TICK = 4000
local MAX_FIELD_LINES = 40

local NEIGHBOURS = {{-1, -1}, {0, -1}, {1, -1}, {-1, 0}, {1, 0}, {-1, 1}, {0, 1}, {1, 1}}

-- Helfer ---------------------------------------------------------------------------------------

local function fmt_t(t)
  return string.format("%g", t)
end

-- Arrakis-Oberfläche aus run.data; fehlt sie, wird der Test beendet (Rückgabe nil).
local function get_surface(run, tb, d)
  local surface = d.surface_name and game.get_surface(d.surface_name)
  if surface and surface.valid then return surface end
  tb.log(run, "FEHLER", "Arrakis-Oberfläche ist nicht mehr da.")
  tb.finish(run, "abgebrochen (Oberfläche fehlt)")
  return nil
end

-- Union-Find über Entity-Nummern (Pfadhalbierung, Vereinigung nach Größe).
local function find(parent, i)
  while parent[i] ~= i do
    local grand = parent[parent[i]]
    parent[i] = grand
    i = grand
  end
  return i
end

local function union(parent, size, a, b)
  local ra, rb = find(parent, a), find(parent, b)
  if ra == rb then return end
  if size[ra] < size[rb] then ra, rb = rb, ra end
  parent[rb] = ra
  size[ra] = size[ra] + size[rb]
end

-- Zahlenschlüssel eines Gitter-Buckets (bx, by liegen weit unter ±32768).
local function bucket_key(bx, by)
  return bx * 65536 + by
end

-- Rasterindex k (ab 1) → Spalte i, Zeile j (ab 0).
local function grid_ij(k, nx)
  local i = (k - 1) % nx
  return i, math.floor((k - 1 - i) / nx)
end

-- Kachel eines Rasterpunkts (Mitte seiner 4×4-Zelle).
local function grid_tile(d, i, j)
  return d.x1 + i * GRID + GRID / 2, d.y1 + j * GRID + GRID / 2
end

-- Kachelname (für pcall ohne neue Closure je Punkt).
local function tile_name(surface, x, y)
  return surface.get_tile(x, y).name
end

local function clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

-- Abstand einer Kachel zur ersten Kachel außerhalb des Gebiets. Ist der gemessene Felsabstand
-- größer, könnte außerhalb des Gebiets näherer Fels liegen: der Wert ist dann unsicher.
local function edge_distance(d, tx, ty)
  return math.min(tx - d.x1 + 1, d.x2 - tx, ty - d.y1 + 1, d.y2 - ty)
end

-- Box auf das untersuchte Gebiet beschränken.
local function clamp_area(d, area)
  return
  {
    left_top = {x = math.max(area.left_top.x, d.x1), y = math.max(area.left_top.y, d.y1)},
    right_bottom = {x = math.min(area.right_bottom.x, d.x2), y = math.min(area.right_bottom.y, d.y2)}
  }
end

-- Gibt es arrakis-rock in der Box? pcall-Ergebnis: ok, Anzahl (0 oder 1) bzw. Fehlermeldung.
local function count_rock(surface, area)
  return pcall(function()
    return surface.count_tiles_filtered{area = area, name = ROCK_TILE, limit = 1}
  end)
end

-- Felsabstand eines Felds aus der Box-Suche als Text. f.rock = erster Schritt mit Fels in der
-- vergrößerten Feldbox; der Abstand zur Box liegt also zwischen f.rock - 5 und f.rock.
local function rock_text(f)
  local text
  if f.rock_error then
    if f.rock_clear then
      text = "kein Fels bis " .. f.rock_clear .. " Kacheln um die Feldbox, danach Fehler bei count_tiles_filtered"
    else
      text = "Felsabstand nicht messbar (Fehler bei count_tiles_filtered)"
    end
  elseif f.rock == nil then
    text = "kein Fels bis " .. ROCK_MAX .. " Kacheln um die Feldbox"
  elseif f.rock == 0 then
    text = "Fels schon in der Feldbox"
  else
    text = string.format("Felsabstand %d–%d Kacheln (Box-Suche)", f.rock - ROCK_STEP, f.rock)
  end
  if f.rock_edge then
    text = text .. ", Suchbox ragte über das Gebiet (dort evtl. nicht erzeugt)"
  end
  return text
end

-- Phasen ---------------------------------------------------------------------------------------

local phases = {}

local function begin_raster(d)
  d.nx = math.floor((d.x2 - d.x1) / GRID)
  d.ny = math.floor((d.y2 - d.y1) / GRID)
  d.N = d.nx * d.ny
  d.gk = 1
  d.kind = {}        -- 1 = Fels, 0 = Sand, 2 = andere Kachel
  d.val = {}         -- arrakis_rock je Punkt (fehlt, wenn nicht berechenbar)
  d.dist = {}        -- Felsabstand in Rasterschritten (fehlt = unerreicht)
  d.src = {}         -- nächster Felspunkt (Rasterindex) für die BFS
  d.queue, d.qh, d.qt = {}, 1, 0
  d.tile_counts = {}
  d.phase = "raster"
end

local function begin_evaluation(d)
  d.acc = {}
  for index = 1, #THRESHOLDS do
    d.acc[index] = {count = 0, unsure = 0}
  end
  d.stats = {rock = 0, sand = 0, other = 0, rock_vn = 0, rock_vsum = 0, sand_vn = 0, sand_vsum = 0}
  d.gk = 1
  d.phase = "auswerten"
end

-- 1. Nach dem Hinweis (start) Chunks erzeugen und das Gebiet festlegen.
phases.warten = function(run, tb, d)
  if game.tick < d.wait_until then return end
  local existed = false
  pcall(function() existed = game.planets["arrakis"].surface ~= nil end)
  local ok, surface = pcall(arrakis_surface.get_or_create, RADIUS_CHUNKS)
  if not ok or not (surface and surface.valid) then
    tb.log(run, "FEHLER", "Arrakis-Oberfläche nicht verfügbar: " .. tostring(surface))
    tb.finish(run, "abgebrochen (keine Arrakis-Oberfläche)")
    return
  end
  d.surface_name = surface.name
  -- Gebiet = alle Chunks -12…12 in x und y (Kacheln x1…x2-1).
  d.x1 = -RADIUS_CHUNKS * 32
  d.y1 = -RADIUS_CHUNKS * 32
  d.x2 = (RADIUS_CHUNKS + 1) * 32
  d.y2 = (RADIUS_CHUNKS + 1) * 32
  local generated, total = 0, 0
  for cx = -RADIUS_CHUNKS, RADIUS_CHUNKS do
    for cy = -RADIUS_CHUNKS, RADIUS_CHUNKS do
      total = total + 1
      if surface.is_chunk_generated({x = cx, y = cy}) then generated = generated + 1 end
    end
  end
  tb.log(run, "INFO", "Oberfläche " .. surface.name .. (existed and " (gab es schon; schon abgebautes Spice fehlt in der Zählung)" or " (neu angelegt)"))
  tb.log(run, "MESSUNG", string.format("Chunks erzeugt: %d von %d; Gebiet x %d…%d, y %d…%d (%d×%d Kacheln)",
    generated, total, d.x1, d.x2 - 1, d.y1, d.y2 - 1, d.x2 - d.x1, d.y2 - d.y1))
  if generated < total then
    tb.log(run, "FEHLER", "Nicht alle Chunks erzeugt; Ergebnisse sind unvollständig.")
  end
  d.sx, d.sy, d.n = {}, {}, 0
  d.chunk = 0        -- laufende Chunknummer 0 … 624 (zeilenweise)
  d.phase = "suchen"
end

-- 2a. spice-sand chunkweise einsammeln (als Kachelkoordinaten), je Tick Chunks bis etwa
-- ENTITIES_PER_TICK Funde (ein Chunk hat höchstens 1024).
phases.suchen = function(run, tb, d)
  local surface = get_surface(run, tb, d)
  if not surface then return end
  local side = 2 * RADIUS_CHUNKS + 1
  local sx, sy, n = d.sx, d.sy, d.n
  local taken = 0
  while taken < ENTITIES_PER_TICK and d.chunk < side * side do
    local left = (d.chunk % side - RADIUS_CHUNKS) * 32
    local top = (math.floor(d.chunk / side) - RADIUS_CHUNKS) * 32
    d.chunk = d.chunk + 1
    local ok, found = pcall(function()
      return surface.find_entities_filtered{
        area = {left_top = {x = left, y = top}, right_bottom = {x = left + 32, y = top + 32}},
        name = SPICE
      }
    end)
    if not ok then
      if not d.find_error then
        d.find_error = true
        tb.log(run, "FEHLER", "find_entities_filtered: " .. tostring(found))
      end
      found = {}
    end
    for _, entity in ipairs(found) do
      local position = entity.position
      local tx, ty = math.floor(position.x), math.floor(position.y)
      -- Nur Entities, deren Kachel in diesem Chunk liegt: keine Doppelten an den Chunkgrenzen.
      if tx >= left and tx < left + 32 and ty >= top and ty < top + 32 then
        n = n + 1
        sx[n], sy[n] = tx, ty
      end
    end
    taken = taken + #found
  end
  d.n = n
  if d.chunk >= side * side then
    d.parent, d.size, d.buckets, d.ci = {}, {}, {}, 1
    d.phase = "clustern"
  end
end

-- 2b. Clustern: jede Entity mit allen früheren in den 3×3 Nachbar-Buckets vergleichen.
phases.clustern = function(run, tb, d)
  local sx, sy, parent, size, buckets = d.sx, d.sy, d.parent, d.size, d.buckets
  local last = math.min(d.n, d.ci + ENTITIES_PER_TICK - 1)
  for i = d.ci, last do
    local tx, ty = sx[i], sy[i]
    parent[i], size[i] = i, 1
    local bx, by = math.floor(tx / BUCKET), math.floor(ty / BUCKET)
    for ox = -1, 1 do
      for oy = -1, 1 do
        local list = buckets[bucket_key(bx + ox, by + oy)]
        if list then
          for _, j in ipairs(list) do
            local dx, dy = sx[j] - tx, sy[j] - ty
            if dx * dx + dy * dy <= NEIGHBOUR_SQ then union(parent, size, i, j) end
          end
        end
      end
    end
    local key = bucket_key(bx, by)
    local own = buckets[key]
    if not own then
      own = {}
      buckets[key] = own
    end
    own[#own + 1] = i
  end
  d.ci = last + 1
  if d.ci > d.n then
    d.buckets = nil
    d.groups = {}
    d.ci = 1
    d.phase = "sammeln"
  end
end

-- 2c. Gruppen zusammenfassen, Felder (≥ 20) nach Abstand vom Ursprung sortieren.
phases.sammeln = function(run, tb, d)
  local sx, sy, parent, groups = d.sx, d.sy, d.parent, d.groups
  local last = math.min(d.n, d.ci + ENTITIES_PER_TICK - 1)
  for i = d.ci, last do
    local root = find(parent, i)
    local x, y = sx[i], sy[i]
    local g = groups[root]
    if not g then
      g = {count = 0, sum_x = 0, sum_y = 0, min_x = x, max_x = x, min_y = y, max_y = y}
      groups[root] = g
    end
    g.count = g.count + 1
    g.sum_x, g.sum_y = g.sum_x + x, g.sum_y + y
    if x < g.min_x then g.min_x = x end
    if x > g.max_x then g.max_x = x end
    if y < g.min_y then g.min_y = y end
    if y > g.max_y then g.max_y = y end
  end
  d.ci = last + 1
  if d.ci <= d.n then return end

  local fields, group_count, small_groups, small_entities = {}, 0, 0, 0
  for root, g in pairs(groups) do
    group_count = group_count + 1
    if g.count >= MIN_FIELD then
      -- Mitte als Kartenposition (Kachelmitte).
      local cx, cy = g.sum_x / g.count + 0.5, g.sum_y / g.count + 0.5
      fields[#fields + 1] =
      {
        root = root, count = g.count, cx = cx, cy = cy, origin = math.sqrt(cx * cx + cy * cy),
        min_x = g.min_x, max_x = g.max_x, min_y = g.min_y, max_y = g.max_y
      }
    else
      small_groups = small_groups + 1
      small_entities = small_entities + g.count
    end
  end
  table.sort(fields, function(a, b)
    if a.origin ~= b.origin then return a.origin < b.origin end
    return a.root < b.root
  end)
  d.field_of_root = {}
  for index, f in ipairs(fields) do
    d.field_of_root[f.root] = index
  end
  d.fields = fields
  d.groups = nil
  tb.log(run, "MESSUNG", string.format("Spice-Sand im Gebiet: %d Entities in %d Gruppen; Felder (≥ %d): %d; ignoriert: %d Gruppen mit %d Entities",
    d.n, group_count, MIN_FIELD, #fields, small_groups, small_entities))
  if #fields > 0 then
    tb.log(run, "INFO", "Felder nach Abstand vom Ursprung (F1 = Lehrfeld-Kandidat). Felsabstand per Box-Suche: Feldbox in "
      .. ROCK_STEP .. "er-Schritten vergrößert, gemessen in x/y-Richtung, diagonal also bis ×1.4 zu klein. Euklidisch: Rasterabstand weiter unten.")
  end
  d.rf, d.rk = 1, 0
  d.phase = "fels"
end

-- 2d. Felsabstand je Feld: Feldbox schrittweise um 5 Kacheln vergrößern, bis Fels darin liegt.
-- Das ist der Abstand zur Box (Chebyshev), also eine untere Schranke für den Abstand zum Feld.
phases.fels = function(run, tb, d)
  local fields = d.fields
  if d.rf <= #fields then
    local surface = get_surface(run, tb, d)
    if not surface then return end
    local calls = 0
    while calls < ROCK_CALLS_PER_TICK and d.rf <= #fields do
      local f = fields[d.rf]
      local step = d.rk * ROCK_STEP
      local area =
      {
        left_top = {x = f.min_x - step, y = f.min_y - step},
        right_bottom = {x = f.max_x + 1 + step, y = f.max_y + 1 + step}
      }
      local ok, count = count_rock(surface, d.count_clamped and clamp_area(d, area) or area)
      if not ok and not d.count_clamped then
        -- Vielleicht mag count_tiles_filtered keine Box über das erzeugte Gebiet hinaus:
        -- ab jetzt nur noch im Gebiet suchen (Felder am Rand sind dann markiert).
        d.count_clamped = true
        tb.log(run, "FEHLER", "count_tiles_filtered (F" .. d.rf .. ", Box +" .. step .. "): " .. tostring(count)
          .. "; suche ab jetzt nur im Gebiet")
        ok, count = count_rock(surface, clamp_area(d, area))
      end
      calls = calls + 1
      local done = true
      f.rock_edge = area.left_top.x < d.x1 or area.left_top.y < d.y1
        or area.right_bottom.x > d.x2 or area.right_bottom.y > d.y2
      if not ok then
        f.rock_error = true
        if step > 0 then f.rock_clear = step - ROCK_STEP end
        if not d.count_error then
          d.count_error = true
          tb.log(run, "FEHLER", "count_tiles_filtered (F" .. d.rf .. ", Box +" .. step .. "): " .. tostring(count))
        end
      elseif count > 0 then
        f.rock = step
      elseif step < ROCK_MAX then
        done = false
      end
      if done then
        if d.rf <= MAX_FIELD_LINES then
          tb.log(run, "MESSUNG", string.format("F%d%s: Mitte (%s, %s), %d Spice-Sand, Box %d×%d, %s Kacheln vom Ursprung, %s",
            d.rf, d.rf == 1 and " (Lehrfeld-Kandidat)" or "", tb.num(f.cx), tb.num(f.cy), f.count,
            f.max_x - f.min_x + 1, f.max_y - f.min_y + 1, tb.num(f.origin), rock_text(f)))
        end
        d.rf, d.rk = d.rf + 1, 0
      else
        d.rk = d.rk + 1
      end
    end
    if d.rf <= #fields then return end
  end

  if #fields > MAX_FIELD_LINES then
    tb.log(run, "INFO", string.format("Weitere %d Felder nicht einzeln ausgegeben.", #fields - MAX_FIELD_LINES))
  end
  if #fields == 0 then
    tb.log(run, "MESSUNG", "Keine Spicefelder (≥ " .. MIN_FIELD .. " Entities) im Gebiet, also auch kein Lehrfeld-Kandidat.")
  else
    tb.log(run, "MESSUNG", "Lehrfeld-Kandidat F1: " .. rock_text(fields[1]) .. " (Ziel 40–80 Kacheln)")
    local near, others = 0, 0
    for index = 2, #fields do
      local f = fields[index]
      others = others + 1
      if f.rock and f.rock <= TARGET then near = near + 1 end
    end
    tb.log(run, "MESSUNG", string.format("Übrige Felder mit Fels in Feldbox + %d Kacheln: %d von %d (Ziel: keins)", TARGET, near, others))
  end
  begin_raster(d)
end

-- 3a. Raster: Felsflag je Punkt (Kachelname), arrakis_rock-Wert in Blöcken. Felspunkte sind die
-- Quellen der BFS.
phases.raster = function(run, tb, d)
  local surface = get_surface(run, tb, d)
  if not surface then return end
  local kind, dist, src, queue, counts = d.kind, d.dist, d.src, d.queue, d.tile_counts
  local last = math.min(d.N, d.gk + POINTS_PER_TICK - 1)
  local positions, keys = {}, {}
  for k = d.gk, last do
    local i, j = grid_ij(k, d.nx)
    local tx, ty = grid_tile(d, i, j)
    local ok, name = pcall(tile_name, surface, tx, ty)
    if not ok then
      if not d.tile_error then
        d.tile_error = true
        tb.log(run, "FEHLER", string.format("get_tile(%d, %d): %s", tx, ty, tostring(name)))
      end
      name = "(Fehler)"
    end
    counts[name] = (counts[name] or 0) + 1
    if name == ROCK_TILE then
      kind[k] = 1
      dist[k], src[k] = 0, k
      d.qt = d.qt + 1
      queue[d.qt] = k
    elseif string.sub(name, 1, 5) == "sand-" then
      kind[k] = 0
    else
      kind[k] = 2
    end
    positions[#positions + 1] = {x = tx, y = ty}
    keys[#keys + 1] = k
  end

  if not d.no_values then
    local val = d.val
    for first = 1, #positions, PROPERTY_BLOCK do
      local block = {}
      for b = first, math.min(#positions, first + PROPERTY_BLOCK - 1) do
        block[#block + 1] = positions[b]
      end
      local ok, result = pcall(function()
        return surface.calculate_tile_properties({ROCK_PROPERTY}, block)
      end)
      local values = ok and type(result) == "table" and result[ROCK_PROPERTY]
      if not values then
        d.no_values = true
        if ok then
          tb.log(run, "FEHLER", "calculate_tile_properties liefert keinen Wert für " .. ROCK_PROPERTY .. " (Eigenschaft unbekannt?)")
        else
          tb.log(run, "FEHLER", "calculate_tile_properties: " .. tostring(result))
        end
        break
      end
      for b = 1, #block do
        val[keys[first + b - 1]] = values[b]
      end
    end
  end

  d.gk = last + 1
  if d.gk <= d.N then return end

  local names = {}
  for name in pairs(counts) do names[#names + 1] = name end
  table.sort(names)
  local parts = {}
  for _, name in ipairs(names) do
    parts[#parts + 1] = string.format("%s %d (%s %%)", name, counts[name], tb.num(100 * counts[name] / d.N))
  end
  tb.log(run, "MESSUNG", string.format("Raster alle %d Kacheln: %d Punkte; Kacheln: %s", GRID, d.N, table.concat(parts, ", ")))
  if d.qt == 0 then
    tb.log(run, "FEHLER", "Kein Fels im Raster: Felsabstände nicht messbar.")
  end
  d.phase = "bfs"
end

-- 3b. Mehrquellen-BFS über 8 Nachbarn. Jeder Punkt erbt den nächsten Felspunkt seines Vorgängers;
-- der Abstand ist euklidisch zu diesem Felspunkt (in Rasterschritten). Wird ein Punkt später
-- über einen näheren Felspunkt erreicht, kommt er erneut in die Schlange.
phases.bfs = function(run, tb, d)
  local queue, dist, src = d.queue, d.dist, d.src
  local nx, ny = d.nx, d.ny
  local qh, qt = d.qh, d.qt
  local budget = BFS_PER_TICK
  while budget > 0 and qh <= qt do
    local c = queue[qh]
    queue[qh] = nil
    qh = qh + 1
    budget = budget - 1
    local ci, cj = grid_ij(c, nx)
    local s = src[c]
    local si, sj = grid_ij(s, nx)
    for _, offset in ipairs(NEIGHBOURS) do
      local ni, nj = ci + offset[1], cj + offset[2]
      if ni >= 0 and ni < nx and nj >= 0 and nj < ny then
        local nk = nj * nx + ni + 1
        local di, dj = ni - si, nj - sj
        local candidate = math.sqrt(di * di + dj * dj)
        local old = dist[nk]
        if old == nil or candidate < old - 1e-9 then
          dist[nk], src[nk] = candidate, s
          qt = qt + 1
          queue[qt] = nk
        end
      end
    end
  end
  d.qh, d.qt = qh, qt
  if qh <= qt then return end
  d.queue = nil
  d.src = nil
  d.ci = 1
  d.phase = "abgleich"
end

-- 3c. Gegenprobe je Feld: kleinster Rasterabstand zum Fels über alle Entities des Felds.
phases.abgleich = function(run, tb, d)
  local fields = d.fields or {}
  if #fields > 0 and d.n > 0 then
    local sx, sy, parent, dist, field_of_root = d.sx, d.sy, d.parent, d.dist, d.field_of_root
    local last = math.min(d.n, d.ci + ENTITIES_PER_TICK - 1)
    for e = d.ci, last do
      local index = field_of_root[find(parent, e)]
      if index then
        local f = fields[index]
        local i = clamp(math.floor((sx[e] - d.x1) / GRID), 0, d.nx - 1)
        local j = clamp(math.floor((sy[e] - d.y1) / GRID), 0, d.ny - 1)
        local steps = dist[j * d.nx + i + 1]
        if steps then
          local tiles = steps * GRID
          if f.grid == nil or tiles < f.grid then
            local gx, gy = grid_tile(d, i, j)
            f.grid = tiles
            f.grid_sure = tiles <= edge_distance(d, gx, gy)
          end
        end
      end
    end
    d.ci = last + 1
    if d.ci <= d.n then return end
    local parts = {}
    for index = 1, math.min(#fields, MAX_FIELD_LINES) do
      local f = fields[index]
      parts[#parts + 1] = "F" .. index .. " " .. tb.num(f.grid) .. ((f.grid and not f.grid_sure) and "?" or "")
    end
    tb.log(run, "MESSUNG", "Rasterabstand Feld → Fels in Kacheln (≈ euklidisch, ±" .. GRID .. "; ? = am Gebietsrand, unsicher): "
      .. table.concat(parts, ", "))
  end
  d.sx, d.sy, d.parent, d.size, d.field_of_root = nil, nil, nil, nil, nil
  begin_evaluation(d)
end

-- Tabelle, Ergebnis und Zusammenfassung.
local function report(run, tb, d)
  local st, total = d.stats, d.N
  if st.rock_vn + st.sand_vn > 0 then
    -- Wo die Kachelgrenze Fels/Sand im Noise-Wert liegt.
    tb.log(run, "MESSUNG", string.format("arrakis_rock an Felspunkten: kleinster %s, Mittel %s; an Sandpunkten: größter %s, Mittel %s",
      tb.num(st.rock_vmin, 2), tb.num(st.rock_vn > 0 and st.rock_vsum / st.rock_vn, 2),
      tb.num(st.sand_vmax, 2), tb.num(st.sand_vn > 0 and st.sand_vsum / st.sand_vn, 2)))
  end

  local fields = d.fields or {}
  local summary = {#fields .. " Spicefelder"}
  if fields[1] then
    table.insert(summary, "Lehrfeld-Kandidat F1: " .. rock_text(fields[1]))
  end

  if d.no_values then
    tb.log(run, "FEHLER", "Schwellen-Kalibrierung entfällt: keine Werte für " .. ROCK_PROPERTY .. ".")
    table.insert(summary, "keine Noise-Werte")
    return table.concat(summary, "; ")
  end

  tb.log(run, "MESSUNG", string.format("Schwellen (Sandpunkte mit %s < t; Felsabstand im Raster %d Kacheln, ≈ euklidisch, ±%d; %d Punkte, davon %d Sand, %d Fels):",
    ROCK_PROPERTY, GRID, GRID, total, st.sand, st.rock))
  local best
  for index, t in ipairs(THRESHOLDS) do
    local a = d.acc[index]
    local text
    if a.count == 0 then
      text = "keine Sandpunkte"
    else
      local where = a.min and string.format("%s Kacheln bei (%d, %d)", tb.num(a.min), a.min_x, a.min_y) or "unbekannt"
      text = string.format("%d Punkte = %s %% der Fläche (%s %% des Sands), kleinster Felsabstand %s",
        a.count, tb.num(100 * a.count / total), tb.num(100 * a.count / math.max(st.sand, 1)), where)
      if a.unsure > 0 then
        text = text .. string.format(" (%d Randpunkte ausgelassen: Fels außerhalb des Gebiets könnte näher sein)", a.unsure)
      end
    end
    tb.log(run, "MESSUNG", "t = " .. fmt_t(t) .. ": " .. text)
    if not best and a.min and a.min >= TARGET then best = index end
  end

  if best then
    local a = d.acc[best]
    tb.log(run, "OK", string.format("Kleinste Schwelle mit Felsabstand ≥ %d: %s < %s (Abstand %s Kacheln, %s %% der Fläche)",
      TARGET, ROCK_PROPERTY, fmt_t(THRESHOLDS[best]), tb.num(a.min), tb.num(100 * a.count / total)))
    table.insert(summary, "Schwelle " .. fmt_t(THRESHOLDS[best]) .. " (Abstand " .. tb.num(a.min) .. ")")
  else
    tb.log(run, "FEHLER", "keine Schwelle erreicht " .. TARGET)
    table.insert(summary, "keine Schwelle erreicht " .. TARGET)
  end
  return table.concat(summary, "; ")
end

-- 3d. Auswertung je Schwelle: kleinster sicherer Felsabstand der Sandpunkte mit Wert < t.
phases.auswerten = function(run, tb, d)
  local kind, val, dist, acc, st = d.kind, d.val, d.dist, d.acc, d.stats
  local last = math.min(d.N, d.gk + POINTS_PER_TICK - 1)
  for k = d.gk, last do
    local v = val[k]
    if kind[k] == 1 then
      st.rock = st.rock + 1
      if v then
        st.rock_vn, st.rock_vsum = st.rock_vn + 1, st.rock_vsum + v
        if not st.rock_vmin or v < st.rock_vmin then st.rock_vmin = v end
      end
    elseif kind[k] == 0 then
      st.sand = st.sand + 1
      if v then
        st.sand_vn, st.sand_vsum = st.sand_vn + 1, st.sand_vsum + v
        if not st.sand_vmax or v > st.sand_vmax then st.sand_vmax = v end
        local i, j = grid_ij(k, d.nx)
        local tx, ty = grid_tile(d, i, j)
        local tiles = dist[k] and dist[k] * GRID
        local sure = tiles ~= nil and tiles <= edge_distance(d, tx, ty)
        for index, t in ipairs(THRESHOLDS) do
          if v < t then
            local a = acc[index]
            a.count = a.count + 1
            if not sure then
              a.unsure = a.unsure + 1
            elseif not a.min or tiles < a.min then
              a.min, a.min_x, a.min_y = tiles, tx, ty
            end
          end
        end
      end
    else
      st.other = st.other + 1
    end
  end
  d.gk = last + 1
  if d.gk <= d.N then return end
  d.phase = "fertig"
  tb.finish(run, report(run, tb, d))
end

-- Vertrag ----------------------------------------------------------------------------------------

local function start(run, tb)
  local d = run.data
  tb.log(run, "INFO", "T11 erzeugt Karte, das Spiel hängt kurz (Arrakis, Chunks im Radius " .. RADIUS_CHUNKS
    .. " um (0, 0)). Du bleibst, wo du bist.")
  d.wait_until = game.tick + WARN_TICKS
  d.phase = "warten"
end

local function tick(run, tb)
  local phase = phases[run.data.phase]
  if phase then phase(run, tb, run.data) end
end

-- Große Arbeitstabellen freigeben; auf der Oberfläche ist nichts zurückzusetzen.
local function cleanup(run, tb)
  local d = run.data
  for _, key in ipairs({"sx", "sy", "parent", "size", "buckets", "groups", "field_of_root",
                        "kind", "val", "dist", "src", "queue", "tile_counts", "acc"}) do
    d[key] = nil
  end
end

return
{
  T11 =
  {
    title = "Kartengenerator: Spicefelder und Fels",
    timeout = 300 * 60,
    interactive = false,
    confirm = nil,
    start = start,
    tick = tick,
    cleanup = cleanup
  }
}
