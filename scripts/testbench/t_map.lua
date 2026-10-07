-- Prüfstand: Kartengenerator-Test T11, Seed-Vergleich der Fels-Varianten (Vertrag siehe runner.lua).
-- T11 erzeugt keine Chunks und lässt Arrakis und den Spieler in Ruhe. Für jeden Seed legt der Test
-- eine leere Testoberfläche mit den Kartengenerator-Einstellungen von Arrakis an, holt die Rauschwerte
-- auf einem Raster (alle 8 Kacheln) per calculate_tile_properties und löscht die Oberfläche wieder.
-- Je Variante (Rauschen aus prototypes/testbench/noise.lua plus Felsschwelle) und Seed:
--   Felsanteil, Inseln (zusammenhängender Fels im Raster), euklidischer Felsabstand jedes Sandpunkts
--   und die Spice-Schwelle t100: Wo Wert − Felsschwelle < t100, liegt der nächste Fels-Rasterpunkt
--   mindestens 108 Kacheln weg (100 plus ein Rasterschritt, weil Fels zwischen den Punkten liegen
--   kann). Dazu der Flächenanteil, der dann für Spice übrig bleibt.
-- Zusätzlich die Werteverteilung jedes Rauschens (auch Hilfsgrößen wie die Verzerrung von 0.4.0).
-- Kartenbilder (ein Zeichen je 16 × 16 Kacheln) stehen in script-output/arrakis-t11-karten.txt;
-- tools/check/t11_bilder.py macht daraus PNGs.
-- Die Rechenlast ist über Ticks verteilt (Phasen in run.data.phase); der Zustand liegt als reine
-- Daten in run.data.

local HALF = 800                    -- Gebiet −800 … 799 in x und y
local GRID = 8                      -- Rasterabstand in Kacheln
local N = 2 * HALF / GRID           -- Rasterpunkte je Zeile (200)
local BORDER = 16                   -- Rasterpunkte am Rand (128 Kacheln) ohne Abstandswertung
local TARGET = 100                  -- Mindestabstand Spicefeld → Fels (Design 4.1)
local DEEP = TARGET + GRID          -- Abstand zum nächsten Fels-Rasterpunkt, ab dem TARGET sicher gilt
local PICTURE_STEP = 2              -- Kartenbild: jeder 2. Rasterpunkt
local BLOCK = 1000                  -- Positionen je calculate_tile_properties-Aufruf
local BLOCKS_PER_TICK = 6
local MAP_FILE = "arrakis-t11-karten.txt"
local SURFACE_PREFIX = "arrakis-t11-"
local FIXED_SEEDS = {1234, 98765, 424242, 1000003, 2718281, 3141592, 16180339, 27182818}
local INF = math.huge
local BIG = 1e10                    -- quadrierter Abstand „kein Fels“ in der Abstandstransformation
local NONE = 1e9                    -- „kein Wert“ in gespeicherten Ergebnissen (statt math.huge)

-- Feste Schwellen für die Spicefläche (Wert − Felsschwelle < t): T_STEPS[m] = −0,01 · (m − 1), also 0 … −4.
local T_STEP = 0.01
local T_COUNT = 401
local T_STEPS = {}
for index = 1, T_COUNT do
  T_STEPS[index] = -T_STEP * (index - 1)
end

-- Rauschen, die T11 je Seed holt.
local PROPERTIES =
{
  {name = "arrakis_rock", title = "Karte 0.4.0 mit Startinsel"},
  {name = "arrakis_rock_noise", title = "Rauschen 0.4.0 ohne Startinsel"},
  {name = "arrakis_wobble_x", title = "Verzerrung 0.4.0 (multioctave_noise, Maßstab 12)"},
  {name = "arrakis_t11_c1", title = "c1: 3 Oktaven bis 300 Kacheln"},
  {name = "arrakis_t11_c2", title = "c2: 3 Oktaven bis 500 Kacheln"},
  {name = "arrakis_t11_cone", title = "Voronoi-Kegel von c3"},
  {name = "arrakis_t11_c3", title = "c3: Voronoi-Inseln"},
  {name = "arrakis_t11_c4", title = "c4: Kegel-Inseln (spot_noise)"}
}
local PROPERTY_NAMES = {}
for index, property in ipairs(PROPERTIES) do
  PROPERTY_NAMES[index] = property.name
end

-- Varianten = Rauschen + Felsschwelle. share: Schwelle je Seed so, dass dieser Anteil Fels ist;
-- sonst feste Schwelle offset. picture: Kartenbild schreiben. family: Zeile in der Kurzfassung.
local VARIANTS =
{
  {key = "live", family = "live", property = "arrakis_rock", offset = 0, picture = true,
   title = "Karte 0.4.0 (mit Startinsel)"}
}
for _, family in ipairs({{key = "c1", property = "arrakis_t11_c1"}, {key = "c2", property = "arrakis_t11_c2"}}) do
  for _, percent in ipairs({15, 20, 25, 30}) do
    VARIANTS[#VARIANTS + 1] = {key = family.key .. "-" .. percent, family = family.key, property = family.property,
      share = percent / 100, picture = percent == 20, title = percent .. " % Fels je Seed", label = percent .. " %"}
  end
end
for _, offset in ipairs({-0.05, 0, 0.05}) do
  VARIANTS[#VARIANTS + 1] = {key = "c3" .. string.format("%+.2f", offset), family = "c3", property = "arrakis_t11_c3",
    offset = offset, picture = offset == 0, title = "Felsschwelle " .. offset, label = string.format("%+.2f", offset)}
end
for _, offset in ipairs({-0.2, 0, 0.2}) do
  VARIANTS[#VARIANTS + 1] = {key = "c4" .. string.format("%+.1f", offset), family = "c4", property = "arrakis_t11_c4",
    offset = offset, picture = offset == 0, title = "Felsschwelle " .. offset, label = string.format("%+.1f", offset)}
end
local FAMILIES = {"live", "c1", "c2", "c3", "c4"}

-- Letzte Variante je Rauschen: danach werden seine Werte freigegeben.
local LAST_USE = {}
for index, variant in ipairs(VARIANTS) do
  LAST_USE[variant.property] = index
end

-- Helfer ---------------------------------------------------------------------------------------

local function fmt(value, digits)
  if value == nil then return "–" end
  if value >= NONE / 10 then return "∞" end
  if value <= -NONE / 10 then return "−∞" end
  return string.format("%." .. (digits or 2) .. "f", value)
end

local function pct(part, total)
  if not total or total <= 0 then return "–" end
  return string.format("%.1f %%", 100 * part / total)
end

-- Kartenposition des Rasterpunkts k (ab 1): Mitte seiner 8×8-Zelle.
local function grid_position(k)
  local i = (k - 1) % N
  local j = (k - 1 - i) / N
  return {x = -HALF + i * GRID + GRID / 2, y = -HALF + j * GRID + GRID / 2}
end

-- Quantil p (0…1) einer sortierten Liste.
local function quantile(sorted, p)
  local n = #sorted
  if n == 0 then return nil end
  local index = math.ceil(p * n)
  if index < 1 then index = 1 end
  if index > n then index = n end
  return sorted[index]
end

-- Anteil der Werte über x, aus einer Quantiltabelle qtab[1 … 99] (qtab[p] = p-%-Quantil) mit
-- Minimum low und Maximum high, linear interpoliert.
local function share_above(qtab, low, high, x)
  if x < low then return 1 end
  if x >= high then return 0 end
  local prev_value, prev_p = low, 0
  for p = 1, 100 do
    local value = p == 100 and high or qtab[p]
    if x < value then
      local span = value - prev_value
      local frac = span > 0 and (x - prev_value) / span or 0
      return 1 - (prev_p + frac * (p - prev_p)) / 100
    end
    prev_value, prev_p = value, p
  end
  return 0
end

-- Seeds: der Seed dieses Spielstands (Arrakis, sonst Nauvis) und die festen Seeds.
local function seed_list()
  local seeds, label = {}, nil
  local ok, own = pcall(function()
    local arrakis = game.get_surface("arrakis")
    if arrakis then
      label = "Spielstand (Arrakis)"
      return arrakis.map_gen_settings.seed
    end
    local nauvis = game.get_surface("nauvis")
    if nauvis then
      label = "Spielstand (Nauvis)"
      return nauvis.map_gen_settings.seed
    end
  end)
  if ok and type(own) == "number" then
    seeds[1] = {seed = own, label = label}
  end
  for _, seed in ipairs(FIXED_SEEDS) do
    if not (seeds[1] and seeds[1].seed == seed) then
      seeds[#seeds + 1] = {seed = seed, label = "fest"}
    end
  end
  return seeds
end

-- Abstandstransformation ---------------------------------------------------------------------------

-- Exakte quadratische Abstandstransformation in 1D (Felzenszwalb/Huttenlocher) über f[0 … n − 1].
local function edt_1d(f, n, out, v, z)
  local k = 0
  v[0] = 0
  z[0] = -INF
  z[1] = INF
  for q = 1, n - 1 do
    local fq = f[q] + q * q
    local p = v[k]
    local s = (fq - (f[p] + p * p)) / (2 * (q - p))
    while s <= z[k] do
      k = k - 1
      p = v[k]
      s = (fq - (f[p] + p * p)) / (2 * (q - p))
    end
    k = k + 1
    v[k] = q
    z[k] = s
    z[k + 1] = INF
  end
  k = 0
  for q = 0, n - 1 do
    while z[k + 1] < q do k = k + 1 end
    local d = q - v[k]
    out[q] = d * d + f[v[k]]
  end
end

-- Euklidischer Abstand jedes Rasterpunkts zum nächsten Felspunkt in Rasterschritten (INF ohne Fels).
local function distance_transform(rock)
  local d2, f, out, v, z = {}, {}, {}, {}, {}
  for j = 0, N - 1 do
    local base = j * N + 1
    for i = 0, N - 1 do f[i] = rock[base + i] and 0 or BIG end
    edt_1d(f, N, out, v, z)
    for i = 0, N - 1 do d2[base + i] = out[i] end
  end
  for i = 0, N - 1 do
    for j = 0, N - 1 do f[j] = d2[j * N + i + 1] end
    edt_1d(f, N, out, v, z)
    for j = 0, N - 1 do d2[j * N + i + 1] = out[j] end
  end
  local dist = {}
  for k = 1, N * N do
    local value = d2[k]
    dist[k] = value >= BIG / 10 and INF or math.sqrt(value)
  end
  return dist
end

-- Zusammenhängende Felsflächen (8er-Nachbarschaft). Rückgabe: sortierte Liste der Größen in Rasterpunkten.
local function islands(rock)
  local seen, sizes, stack = {}, {}, {}
  for start = 1, N * N do
    if rock[start] and not seen[start] then
      local size, top = 0, 1
      stack[1] = start
      seen[start] = true
      while top > 0 do
        local k = stack[top]
        top = top - 1
        size = size + 1
        local i = (k - 1) % N
        local j = (k - 1 - i) / N
        for dj = -1, 1 do
          local nj = j + dj
          if nj >= 0 and nj < N then
            for di = -1, 1 do
              local ni = i + di
              if ni >= 0 and ni < N then
                local nk = nj * N + ni + 1
                if rock[nk] and not seen[nk] then
                  seen[nk] = true
                  top = top + 1
                  stack[top] = nk
                end
              end
            end
          end
        end
      end
      sizes[#sizes + 1] = size
    end
  end
  table.sort(sizes)
  return sizes
end

local function interior(i, j)
  return i >= BORDER and i < N - BORDER and j >= BORDER and j < N - BORDER
end

-- Kartenbild: # Fels, - Sand unter 100 Kacheln vom Fels, . Sand ab 100 Kacheln,
-- o Spicefläche (Wert − Felsschwelle < t100 dieses Seeds, nur im ausgewerteten Inneren), S Ursprung.
local function write_picture(variant, entry, values, offset, rock, dist, t100)
  local lines = {string.format("=== %s Seed %d (%s): %s, Felsschwelle %s, t100 %s ===",
    variant.key, entry.seed, entry.label, variant.title, fmt(offset, 3), fmt(t100, 3))}
  local origin = N / 2
  for j = 0, N - 1, PICTURE_STEP do
    local row = {}
    for i = 0, N - 1, PICTURE_STEP do
      local k = j * N + i + 1
      local char
      if i == origin and j == origin then
        char = "S"
      elseif rock[k] then
        char = "#"
      elseif interior(i, j) and values[k] - offset < t100 then
        char = "o"
      elseif dist[k] * GRID >= DEEP then
        char = "."
      else
        char = "-"
      end
      row[#row + 1] = char
    end
    lines[#lines + 1] = table.concat(row)
  end
  helpers.write_file(MAP_FILE, table.concat(lines, "\n") .. "\n\n", true)
end

-- Werteverteilung einer sortierten Liste: Kennzahlen samt Quantiltabelle.
local function distribution(sorted)
  local qtab = {}
  for p = 1, 99 do qtab[p] = quantile(sorted, p / 100) end
  return {min = sorted[1], max = sorted[#sorted], q01 = qtab[1], q10 = qtab[10], q25 = qtab[25], q50 = qtab[50],
          q75 = qtab[75], q90 = qtab[90], q99 = qtab[99], qtab = qtab}
end

local function distribution_text(q)
  return string.format("min %s, 1 %% %s, 10 %% %s, 25 %% %s, Median %s, 75 %% %s, 90 %% %s, 99 %% %s, max %s",
    fmt(q.min), fmt(q.q01), fmt(q.q10), fmt(q.q25), fmt(q.q50), fmt(q.q75), fmt(q.q90), fmt(q.q99), fmt(q.max))
end

-- Analyse einer Variante für einen Seed. Rückgabe: Ergebnis (nur Zahlen).
local function analyse(variant, entry, values, offset)
  local n = N * N
  local rock, rock_count = {}, 0
  for k = 1, n do
    if values[k] - offset > 0 then
      rock[k] = true
      rock_count = rock_count + 1
    end
  end
  local result = {seed = entry.seed, offset = offset, rock = rock_count / n}

  local sizes = islands(rock)
  local big = 0
  for _, size in ipairs(sizes) do
    if size >= 4 then big = big + 1 end    -- ab 4 Rasterpunkten (256 Kacheln²) zählt eine Insel
  end
  result.islands = big
  result.island_max = sizes[#sizes] and sizes[#sizes] * GRID * GRID or 0
  result.island_median = sizes[1] and sizes[math.ceil(#sizes / 2)] * GRID * GRID or 0

  local dist = distance_transform(rock)

  -- Innenpunkte: Fels außerhalb des Gebiets liegt mindestens BORDER · GRID = 128 ≥ DEEP Kacheln
  -- entfernt, die Einordnung „tief“ ist dort also sicher.
  local inner, sand, deep, max_dist = 0, 0, 0, 0
  local violators = {}
  local t100 = INF
  -- hist[m]: Sandpunkte mit Wert unter T_STEPS[1 … m], aber nicht unter T_STEPS[m + 1].
  local hist = {}
  for m = 0, T_COUNT do hist[m] = 0 end
  for j = BORDER, N - 1 - BORDER do
    for i = BORDER, N - 1 - BORDER do
      local k = j * N + i + 1
      inner = inner + 1
      if not rock[k] then
        sand = sand + 1
        local v = values[k] - offset
        local tiles = dist[k] * GRID
        if tiles >= DEEP then
          deep = deep + 1
        else
          violators[#violators + 1] = v
          if v < t100 then t100 = v end
        end
        if tiles ~= INF and tiles > max_dist then max_dist = tiles end
        -- v < T_STEPS[m] ⇔ m < 1 − v / T_STEP; größtes solches m, begrenzt auf 0 … T_COUNT.
        local m = math.ceil(1 - v / T_STEP) - 1
        if m < 0 then m = 0 elseif m > T_COUNT then m = T_COUNT end
        hist[m] = hist[m] + 1
      end
    end
  end
  table.sort(violators)
  local t100_p1 = quantile(violators, 0.01) or INF
  -- below[index]: Sandpunkte mit Wert < T_STEPS[index].
  local below, running = {}, 0
  for index = T_COUNT, 1, -1 do
    running = running + hist[index]
    below[index] = running
  end

  local eligible, eligible_p1 = 0, 0
  for j = BORDER, N - 1 - BORDER do
    for i = BORDER, N - 1 - BORDER do
      local k = j * N + i + 1
      if not rock[k] then
        local v = values[k] - offset
        if v < t100 then eligible = eligible + 1 end
        if v < t100_p1 then eligible_p1 = eligible_p1 + 1 end
      end
    end
  end

  if variant.picture then
    write_picture(variant, entry, values, offset, rock, dist, t100)
  end

  result.inner, result.sand, result.deep, result.max_dist = inner, sand, deep, max_dist
  result.t100 = t100 == INF and NONE or t100
  result.t100_p1 = t100_p1 == INF and NONE or t100_p1
  result.eligible, result.eligible_p1 = eligible, eligible_p1
  result.below = below
  result.origin_rock = rock[(N / 2) * N + N / 2 + 1] == true
  return result
end

local function result_line(variant, entry, r)
  return string.format("%s Seed %d (%s): Felsschwelle %s, Fels %s, %d Inseln (größte %d, Median %d Kacheln²), Ursprung %s; " ..
    "Sand ≥ %d vom Fels %s der Innenfläche, größter Abstand %s; t100 %s → Spicefläche %s; t100 (1 %% Ausreißer) %s → %s",
    variant.key, entry.seed, entry.label, fmt(r.offset, 3), pct(r.rock, 1), r.islands, r.island_max, r.island_median,
    r.origin_rock and "Fels" or "Sand", TARGET, pct(r.deep, r.inner), fmt(r.max_dist, 0),
    fmt(r.t100, 3), pct(r.eligible, r.inner), fmt(r.t100_p1, 3), pct(r.eligible_p1, r.inner))
end

-- Zusammenfassung ------------------------------------------------------------------------------------

local function spread(list)
  local low, high, sum = INF, -INF, 0
  for _, v in ipairs(list) do
    if v < low then low = v end
    if v > high then high = v end
    sum = sum + v
  end
  return low, sum / math.max(#list, 1), high
end

-- Σ-Zeile einer Variante (nur Datei). Rückgabe: Kurzwerte für die Chat-Zusammenfassung.
local function summarize(run, tb, d, variant)
  local results = d.results[variant.key]
  if #results == 0 then
    tb.trace(run, "Σ " .. variant.key .. ": keine Werte")
    return nil
  end
  local rocks, offsets, isl, deeps, finite_t = {}, {}, {}, {}, {}
  local t_low = INF
  for index, r in ipairs(results) do
    rocks[index] = r.rock
    offsets[index] = r.offset
    isl[index] = r.islands
    deeps[index] = r.deep / math.max(r.inner, 1)
    if r.t100 < t_low then t_low = r.t100 end
    if r.t100 < NONE then finite_t[#finite_t + 1] = r.t100 end
  end
  local rock_low, rock_mean, rock_high = spread(rocks)
  local off_low, off_mean, off_high = spread(offsets)
  local _, isl_mean = spread(isl)
  local deep_low, deep_mean = spread(deeps)
  local _, t_mean = spread(finite_t)

  -- Gemeinsame Spice-Schwelle: größter Rasterwert T_STEPS ≤ kleinstes t100 aller Seeds.
  local step
  for index, t in ipairs(T_STEPS) do
    if t <= t_low then
      step = index
      break
    end
  end
  local spice_mean
  local common = "keine (t100 unter " .. fmt(T_STEPS[T_COUNT]) .. ")"
  if step then
    local shares = {}
    for index, r in ipairs(results) do shares[index] = r.below[step] / math.max(r.inner, 1) end
    local spice_low, mean, spice_high = spread(shares)
    spice_mean = mean
    common = string.format("t = %s → Spicefläche min %s, Mittel %s, max %s", fmt(T_STEPS[step]),
      pct(spice_low, 1), pct(spice_mean, 1), pct(spice_high, 1))
  end

  -- Bei Schwelle je Seed: Felsanteil, den die feste mittlere Schwelle auf jedem Seed ergäbe.
  local fixed = ""
  if variant.share then
    local shares = {}
    for index, q in ipairs(d.distributions[variant.property]) do
      shares[index] = share_above(q.qtab, q.min, q.max, off_mean)
    end
    local low, mean, high = spread(shares)
    fixed = string.format("; mit fester Schwelle %s: Fels min %s, Mittel %s, max %s", fmt(off_mean, 3),
      pct(low, 1), pct(mean, 1), pct(high, 1))
  end

  tb.trace(run, string.format("Σ %s (%s): Fels min %s, Mittel %s, max %s; Felsschwelle %s … %s (Mittel %s)%s; " ..
    "Inseln im Mittel %.1f je 1,6 × 1,6 km; Sand ≥ %d vom Fels min %s, Mittel %s; t100 kleinstes %s, Mittel %s; " ..
    "gemeinsame Schwelle %s",
    variant.key, variant.title, pct(rock_low, 1), pct(rock_mean, 1), pct(rock_high, 1), fmt(off_low, 3), fmt(off_high, 3),
    fmt(off_mean, 3), fixed, isl_mean, TARGET, pct(deep_low, 1), pct(deep_mean, 1), fmt(t_low, 3),
    #finite_t > 0 and fmt(t_mean, 3) or "–", common))
  return {rock = rock_mean, islands = isl_mean, deep = deep_mean, spice = spice_mean, t = step and T_STEPS[step]}
end

-- Phasen ---------------------------------------------------------------------------------------

local phases = {}

local function surface_of(d)
  local surface = d.surface_name and game.get_surface(d.surface_name)
  if surface and surface.valid then return surface end
  return nil
end

local function delete_surface(d)
  local surface = surface_of(d)
  if surface then pcall(function() game.delete_surface(surface) end) end
  d.surface_name = nil
end

-- Testoberfläche für den nächsten Seed anlegen (oder eine alte gleichen Namens umstellen).
phases.anlegen = function(run, tb, d)
  local entry = d.seeds[d.si]
  local ok, settings = pcall(function() return game.planets["arrakis"].prototype.map_gen_settings end)
  if not ok or type(settings) ~= "table" then
    tb.log(run, "FEHLER", "Kartengenerator-Einstellungen von Arrakis nicht lesbar: " .. tostring(settings))
    tb.finish(run, "abgebrochen (keine Einstellungen)")
    return
  end
  settings.seed = entry.seed
  local name = SURFACE_PREFIX .. d.si
  local ok_surface, surface = pcall(function()
    local existing = game.get_surface(name)
    if existing then
      existing.map_gen_settings = settings
      return existing
    end
    return game.create_surface(name, settings)
  end)
  if not ok_surface or not surface then
    tb.log(run, "FEHLER", "Testoberfläche " .. name .. " nicht angelegt: " .. tostring(surface))
    tb.finish(run, "abgebrochen (keine Testoberfläche)")
    return
  end
  d.surface_name = name
  d.values = {}
  for _, property in ipairs(PROPERTY_NAMES) do
    d.values[property] = {}
  end
  d.k = 1
  d.phase = "werte"
end

-- Rauschwerte blockweise holen.
phases.werte = function(run, tb, d)
  local surface = surface_of(d)
  if not surface then
    tb.log(run, "FEHLER", "Testoberfläche verschwunden")
    tb.finish(run, "abgebrochen (Testoberfläche fehlt)")
    return
  end
  local total = N * N
  for _ = 1, BLOCKS_PER_TICK do
    if d.k > total then break end
    local first = d.k
    local last = math.min(total, first + BLOCK - 1)
    local positions = {}
    for k = first, last do
      positions[k - first + 1] = grid_position(k)
    end
    local ok, result = pcall(function() return surface.calculate_tile_properties(PROPERTY_NAMES, positions) end)
    if not ok then
      tb.log(run, "FEHLER", "calculate_tile_properties: " .. tostring(result))
      tb.finish(run, "abgebrochen (calculate_tile_properties)")
      return
    end
    for _, property in ipairs(PROPERTY_NAMES) do
      local list = result[property]
      if not list then
        tb.log(run, "FEHLER", "calculate_tile_properties liefert keinen Wert für " .. property ..
          " (Prüfstand-Einstellung aus oder Name falsch?)")
        tb.finish(run, "abgebrochen (Wert fehlt)")
        return
      end
      local target = d.values[property]
      for index = 1, last - first + 1 do
        target[first + index - 1] = list[index]
      end
    end
    d.k = last + 1
  end
  if d.k > total then
    -- Die Oberfläche wird nicht mehr gebraucht.
    delete_surface(d)
    d.pi = 1
    d.phase = "verteilung"
  end
end

-- Ein Rauschen je Tick: Werteverteilung und die Felsschwellen der Varianten mit festem Felsanteil.
phases.verteilung = function(run, tb, d)
  local entry = d.seeds[d.si]
  local property = PROPERTIES[d.pi]
  local values = d.values[property.name]
  local sorted = {}
  for k = 1, #values do sorted[k] = values[k] end
  table.sort(sorted)
  local q = distribution(sorted)
  table.insert(d.distributions[property.name], q)
  for _, variant in ipairs(VARIANTS) do
    if variant.property == property.name and variant.share then
      d.offsets[variant.key] = quantile(sorted, 1 - variant.share)
    end
  end
  tb.trace(run, string.format("Werte %s Seed %d (%s): %s", property.title, entry.seed, entry.label, distribution_text(q)))
  if not LAST_USE[property.name] then d.values[property.name] = nil end
  d.pi = d.pi + 1
  if d.pi > #PROPERTIES then
    d.vi = 1
    d.phase = "auswerten"
  end
end

-- Eine Variante je Tick auswerten.
phases.auswerten = function(run, tb, d)
  local entry = d.seeds[d.si]
  local variant = VARIANTS[d.vi]
  local offset = variant.share and d.offsets[variant.key] or variant.offset
  local result = analyse(variant, entry, d.values[variant.property], offset)
  table.insert(d.results[variant.key], result)
  tb.trace(run, result_line(variant, entry, result))
  if LAST_USE[variant.property] == d.vi then d.values[variant.property] = nil end
  d.vi = d.vi + 1
  if d.vi <= #VARIANTS then return end

  d.values = nil
  d.offsets = {}
  tb.log(run, "INFO", string.format("Seed %d von %d fertig (%d, %s)", d.si, #d.seeds, entry.seed, entry.label))
  d.si = d.si + 1
  d.phase = d.si <= #d.seeds and "anlegen" or "bericht"
end

phases.bericht = function(run, tb, d)
  for _, property in ipairs(PROPERTIES) do
    local mins, medians, maxs = {}, {}, {}
    for index, q in ipairs(d.distributions[property.name]) do
      mins[index], medians[index], maxs[index] = q.min, q.q50, q.max
    end
    local low = spread(mins)
    local med_low, med_mean, med_high = spread(medians)
    local _, _, high = spread(maxs)
    tb.trace(run, string.format("Σ Werte %s: min %s, Median %s … %s (Mittel %s), max %s",
      property.title, fmt(low), fmt(med_low), fmt(med_high), fmt(med_mean), fmt(high)))
  end

  local by_family = {}
  for _, variant in ipairs(VARIANTS) do
    local short = summarize(run, tb, d, variant)
    if short then
      by_family[variant.family] = by_family[variant.family] or {}
      table.insert(by_family[variant.family], string.format("%s: Fels %s, %.1f Inseln, Sand ≥ %d vom Fels %s, Spice %s bei t = %s",
        variant.label or "Karte", pct(short.rock, 1), short.islands, TARGET, pct(short.deep, 1),
        short.spice and pct(short.spice, 1) or "–", short.t and fmt(short.t) or "–"))
    end
  end
  for _, family in ipairs(FAMILIES) do
    if by_family[family] then
      tb.log(run, "MESSUNG", family .. " – " .. table.concat(by_family[family], " | "))
    end
  end
  tb.log(run, "INFO", "Kartenbilder: script-output/" .. MAP_FILE .. ". Bitte diese Datei zusammen mit arrakis-test.txt schicken.")
  d.phase = "fertig"
  tb.finish(run, string.format("%d Seeds, %d Varianten; Einzelwerte in arrakis-test.txt", #d.seeds, #VARIANTS))
end

-- Vertrag ----------------------------------------------------------------------------------------

local function start(run, tb)
  local d = run.data
  d.seeds = seed_list()
  d.results, d.distributions, d.offsets = {}, {}, {}
  for _, variant in ipairs(VARIANTS) do
    d.results[variant.key] = {}
  end
  for _, property in ipairs(PROPERTY_NAMES) do
    d.distributions[property] = {}
  end
  d.si = 1
  local own = d.seeds[1].label ~= "fest" and string.format("eigener Seed %d (%s) und ", d.seeds[1].seed, d.seeds[1].label) or ""
  tb.log(run, "INFO", string.format("T11 vergleicht %d Fels-Varianten auf %d Seeds (%s%d feste), je %d × %d Kacheln, " ..
    "ohne Karte zu erzeugen. Das Spiel ruckelt dabei etwa eine halbe Minute. Du bleibst, wo du bist.",
    #VARIANTS, #d.seeds, own, #d.seeds - (own ~= "" and 1 or 0), 2 * HALF, 2 * HALF))
  -- Die Bilddatei gilt nur für diesen Lauf (überschreiben statt anhängen).
  helpers.write_file(MAP_FILE, string.format("##### T11 Tick %d: %d Varianten, %d Seeds, Gebiet %d … %d, 1 Zeichen = %d Kacheln #####\n\n",
    game.tick, #VARIANTS, #d.seeds, -HALF, HALF - 1, GRID * PICTURE_STEP), false)
  d.phase = "anlegen"
end

local function tick(run, tb)
  local phase = phases[run.data.phase]
  if phase then phase(run, tb, run.data) end
end

-- Testoberfläche löschen und große Arbeitstabellen freigeben.
local function cleanup(run, tb)
  local d = run.data
  delete_surface(d)
  d.values = nil
  d.offsets = nil
end

return
{
  T11 =
  {
    title = "Kartengenerator: Fels-Varianten im Seed-Vergleich",
    timeout = 300 * 60,
    interactive = false,
    confirm = nil,
    hint = "schreibt zusätzlich script-output/arrakis-t11-karten.txt",
    start = start,
    tick = tick,
    cleanup = cleanup
  }
}
