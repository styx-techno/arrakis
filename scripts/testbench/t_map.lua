-- Prüfstand: Kartengenerator-Test T11, Seed-Vergleich der Fels-Varianten (Vertrag siehe runner.lua).
-- T11 erzeugt keine Chunks und lässt Arrakis und den Spieler in Ruhe. Für jeden Seed legt der Test
-- eine leere Testoberfläche mit den Kartengenerator-Einstellungen von Arrakis an, holt die Rauschwerte
-- auf einem Raster per calculate_tile_properties und löscht die Oberfläche wieder.
-- Je Variante (prototypes/testbench/noise.lua) und Seed:
--   Werteverteilung, Felsanteil, Inseln (zusammenhängender Fels im Raster), Felsabstand jedes
--   Sandpunkts (Chamfer-Abstandstransformation) und die Schwelle t100: Spice nur dort, wo
--   Wert − Felsschwelle < t100, liegt mindestens 100 Kacheln vom Fels entfernt. Dazu der Anteil der
--   Fläche, der dann für Spice übrig bleibt.
-- Kartenbilder (ein Zeichen je 16 × 16 Kacheln) stehen in script-output/arrakis-t11-karten.txt.
-- Die Rechenlast ist über Ticks verteilt (Phasen in run.data.phase); der Zustand liegt als reine
-- Daten in run.data.

local HALF = 800                    -- Gebiet −800 … 799 in x und y
local GRID = 8                      -- Rasterabstand in Kacheln
local N = 2 * HALF / GRID           -- Rasterpunkte je Zeile (200)
local BORDER = 16                   -- Rasterpunkte am Rand (128 Kacheln) ohne Abstandswertung
local TARGET = 100                  -- Mindestabstand Spicefeld → Fels (Design 4.1)
local PICTURE_STEP = 2              -- Kartenbild: jeder 2. Rasterpunkt
local BLOCK = 1000                  -- Positionen je calculate_tile_properties-Aufruf
local BLOCKS_PER_TICK = 8
local MAP_FILE = "arrakis-t11-karten.txt"
local SURFACE_PREFIX = "arrakis-t11-"
local FIXED_SEEDS = {1234, 98765, 424242, 1000003, 2718281, 3141592, 16180339, 27182818}
local SQRT2 = math.sqrt(2)
local INF = math.huge
local NONE = 1e9                    -- „kein Wert“ in gespeicherten Ergebnissen (statt math.huge)

-- Feste Schwellen für die Spicefläche (Wert − Felsschwelle < t): T_STEPS[m] = −0,05 · (m − 1), also 0 … −3.
local T_STEP = 0.05
local T_STEPS = {}
for index = 1, 61 do
  T_STEPS[index] = -T_STEP * (index - 1)
end

-- live: die Karte von 0.4.0 (mit Startinsel), roh: ihr Rauschen ohne Startinsel (nur Werteverteilung).
-- share: Felsschwelle je Seed so, dass dieser Anteil Fels ist; sonst feste Schwelle offset.
local VARIANTS =
{
  {key = "live", property = "arrakis_rock", offset = 0, title = "Karte 0.4.0 (mit Startinsel)"},
  {key = "roh", property = "arrakis_rock_noise", offset = 0, stats_only = true, title = "Rauschen 0.4.0 ohne Startinsel"},
  {key = "c1", property = "arrakis_t11_c1", share = 0.25, title = "3 Oktaven bis 300 Kacheln, 25 % Fels"},
  {key = "c2", property = "arrakis_t11_c2", share = 0.25, title = "3 Oktaven bis 500 Kacheln, 25 % Fels"},
  {key = "c3", property = "arrakis_t11_c3", offset = 0, title = "Voronoi-Inseln (Zellen 400, 65 % mit Insel)"}
}

local PROPERTY_NAMES = {}
for index, variant in ipairs(VARIANTS) do
  PROPERTY_NAMES[index] = variant.property
end

-- Helfer ---------------------------------------------------------------------------------------

local function fmt(value, digits)
  if value == nil then return "–" end
  if value >= NONE / 10 then return "∞" end
  if value <= -NONE / 10 then return "−∞" end
  return string.format("%." .. (digits or 2) .. "f", value)
end

local function pct(count, total)
  if not total or total <= 0 then return "–" end
  return string.format("%.1f %%", 100 * count / total)
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

local function write_map(text)
  helpers.write_file(MAP_FILE, text, true)
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

-- Analyse einer Variante für einen Seed ------------------------------------------------------------

-- Chamfer-Abstandstransformation (Gewichte 1 und √2) auf dem Raster: Abstand jedes Punkts zum
-- nächsten Felspunkt in Rasterschritten (INF, wenn es keinen Fels gibt).
local function distance_transform(rock)
  local dist = {}
  for k = 1, N * N do
    dist[k] = rock[k] and 0 or INF
  end
  for j = 0, N - 1 do
    for i = 0, N - 1 do
      local k = j * N + i + 1
      local best = dist[k]
      if best > 0 then
        if i > 0 and dist[k - 1] + 1 < best then best = dist[k - 1] + 1 end
        if j > 0 then
          local up = k - N
          if dist[up] + 1 < best then best = dist[up] + 1 end
          if i > 0 and dist[up - 1] + SQRT2 < best then best = dist[up - 1] + SQRT2 end
          if i < N - 1 and dist[up + 1] + SQRT2 < best then best = dist[up + 1] + SQRT2 end
        end
        dist[k] = best
      end
    end
  end
  for j = N - 1, 0, -1 do
    for i = N - 1, 0, -1 do
      local k = j * N + i + 1
      local best = dist[k]
      if best > 0 then
        if i < N - 1 and dist[k + 1] + 1 < best then best = dist[k + 1] + 1 end
        if j < N - 1 then
          local down = k + N
          if dist[down] + 1 < best then best = dist[down] + 1 end
          if i < N - 1 and dist[down + 1] + SQRT2 < best then best = dist[down + 1] + SQRT2 end
          if i > 0 and dist[down - 1] + SQRT2 < best then best = dist[down - 1] + SQRT2 end
        end
        dist[k] = best
      end
    end
  end
  return dist
end

-- Zusammenhängende Felsflächen (8er-Nachbarschaft). Rückgabe: Liste der Größen in Rasterpunkten.
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

-- Kartenbild: # Fels, - Sand unter 100 Kacheln vom Fels, . Sand ab 100 Kacheln,
-- o Spicefläche (Wert − Felsschwelle < t100), S Ursprung (0, 0).
local function write_picture(variant, entry, values, offset, rock, dist, t100)
  local lines = {string.format("=== %s Seed %d (%s): %s, Felsschwelle %s, t100 %s ===",
    variant.key, entry.seed, entry.label, variant.title, fmt(offset, 3), fmt(t100, 3))}
  local origin_i, origin_j = N / 2, N / 2
  for j = 0, N - 1, PICTURE_STEP do
    local row = {}
    for i = 0, N - 1, PICTURE_STEP do
      local k = j * N + i + 1
      local char
      if i == origin_i and j == origin_j then
        char = "S"
      elseif rock[k] then
        char = "#"
      elseif values[k] - offset < t100 then
        char = "o"
      elseif dist[k] * GRID >= TARGET then
        char = "."
      else
        char = "-"
      end
      row[#row + 1] = char
    end
    lines[#lines + 1] = table.concat(row)
  end
  write_map(table.concat(lines, "\n") .. "\n\n")
end

-- Wertet eine Variante aus und gibt die Ergebniszeile (Tabelle aus Zahlen) zurück.
local function analyse(variant, entry, values)
  local n = N * N
  local sorted = {}
  for k = 1, n do sorted[k] = values[k] end
  table.sort(sorted)
  local result =
  {
    seed = entry.seed,
    q = {
      min = sorted[1], q01 = quantile(sorted, 0.01), q10 = quantile(sorted, 0.1), q25 = quantile(sorted, 0.25),
      q50 = quantile(sorted, 0.5), q75 = quantile(sorted, 0.75), q90 = quantile(sorted, 0.9),
      q99 = quantile(sorted, 0.99), max = sorted[n]
    }
  }
  if variant.stats_only then return result end

  local offset = variant.offset
  if variant.share then offset = quantile(sorted, 1 - variant.share) end
  result.offset = offset

  local rock, rock_count = {}, 0
  for k = 1, n do
    if values[k] - offset > 0 then
      rock[k] = true
      rock_count = rock_count + 1
    end
  end
  result.rock = rock_count / n

  local sizes = islands(rock)
  local big = 0
  for _, size in ipairs(sizes) do
    if size >= 4 then big = big + 1 end    -- ab 4 Rasterpunkten (256 Kacheln²) zählt eine Insel
  end
  result.islands = big
  result.island_max = sizes[#sizes] and sizes[#sizes] * GRID * GRID or 0
  result.island_median = sizes[1] and sizes[math.ceil(#sizes / 2)] * GRID * GRID or 0

  local dist = distance_transform(rock)

  -- Innenpunkte: Fels außerhalb des Gebiets liegt mindestens BORDER·GRID ≥ TARGET entfernt,
  -- die Einordnung „≥ 100 Kacheln“ ist dort also sicher.
  local interior, sand, deep, max_dist = 0, 0, 0, 0
  local violators = {}
  local t100 = INF
  -- hist[m]: Sandpunkte, deren Wert unter T_STEPS[1 … m] liegt (unter T_STEPS[m + 1] aber nicht).
  local hist = {}
  for m = 0, #T_STEPS do hist[m] = 0 end
  for j = BORDER, N - 1 - BORDER do
    for i = BORDER, N - 1 - BORDER do
      local k = j * N + i + 1
      interior = interior + 1
      if not rock[k] then
        sand = sand + 1
        local v = values[k] - offset
        local tiles = dist[k] * GRID
        if tiles >= TARGET then
          deep = deep + 1
        else
          violators[#violators + 1] = v
          if v < t100 then t100 = v end
        end
        if tiles ~= INF and tiles > max_dist then max_dist = tiles end
        -- v < T_STEPS[m] ⇔ m < 1 − v / T_STEP; größtes solches m, begrenzt auf 0 … #T_STEPS.
        local m = math.ceil(1 - v / T_STEP) - 1
        if m < 0 then m = 0 elseif m > #T_STEPS then m = #T_STEPS end
        hist[m] = hist[m] + 1
      end
    end
  end
  table.sort(violators)
  local t100_p1 = quantile(violators, 0.01) or INF
  -- below[index]: Sandpunkte mit Wert < T_STEPS[index].
  local below, running = {}, 0
  for index = #T_STEPS, 1, -1 do
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

  write_picture(variant, entry, values, offset, rock, dist, t100)

  result.interior, result.sand, result.deep, result.max_dist = interior, sand, deep, max_dist
  result.t100 = t100 == INF and NONE or t100
  result.t100_p1 = t100_p1 == INF and NONE or t100_p1
  result.eligible, result.eligible_p1 = eligible, eligible_p1
  result.below = below
  result.origin_rock = rock[(N / 2) * N + N / 2 + 1] == true
  return result
end

local function result_line(variant, entry, r)
  local q = r.q
  local spread = string.format("Werte min %s, 1 %% %s, 25 %% %s, Median %s, 75 %% %s, 99 %% %s, max %s",
    fmt(q.min), fmt(q.q01), fmt(q.q25), fmt(q.q50), fmt(q.q75), fmt(q.q99), fmt(q.max))
  if variant.stats_only then
    return string.format("%s Seed %d (%s): %s", variant.key, entry.seed, entry.label, spread)
  end
  return string.format("%s Seed %d (%s): Felsschwelle %s, Fels %s, %d Inseln (größte %d, Median %d Kacheln²), Ursprung %s; " ..
    "Sand ≥ %d vom Fels %s der Innenfläche, größter Abstand %s; t100 %s → Spicefläche %s; t100 (1 %% Ausreißer) %s → %s; %s",
    variant.key, entry.seed, entry.label, fmt(r.offset, 3), pct(r.rock, 1), r.islands, r.island_max, r.island_median,
    r.origin_rock and "Fels" or "Sand", TARGET, pct(r.deep, r.interior), fmt(r.max_dist, 0),
    fmt(r.t100, 3), pct(r.eligible, r.interior), fmt(r.t100_p1, 3), pct(r.eligible_p1, r.interior), spread)
end

-- Zusammenfassung einer Variante über alle Seeds. Rückgabe: Kurztext für das ENDE.
local function summarize(run, tb, variant, results)
  if #results == 0 then
    tb.log(run, "FEHLER", variant.key .. ": keine Werte")
    return variant.key .. " keine Werte"
  end
  local function stats(field)
    local low, high, sum = INF, -INF, 0
    for _, r in ipairs(results) do
      local v = r[field]
      if v < low then low = v end
      if v > high then high = v end
      sum = sum + v
    end
    return low, sum / #results, high
  end
  local function qstats(field)
    local low, high, sum = INF, -INF, 0
    for _, r in ipairs(results) do
      local v = r.q[field]
      if v < low then low = v end
      if v > high then high = v end
      sum = sum + v
    end
    return low, sum / #results, high
  end

  local qmin_low = qstats("min")
  local _, q50_mean = qstats("q50")
  local _, _, qmax_high = qstats("max")
  if variant.stats_only then
    tb.log(run, "MESSUNG", string.format("Σ %s (%s): Werte über alle Seeds min %s, Median im Mittel %s, max %s",
      variant.key, variant.title, fmt(qmin_low), fmt(q50_mean), fmt(qmax_high)))
    return nil
  end

  local rock_low, rock_mean, rock_high = stats("rock")
  local off_low, off_mean, off_high = stats("offset")
  local _, islands_mean = stats("islands")
  local deep_share_low, deep_share_sum = INF, 0
  local t_low, t_sum, t_count = INF, 0, 0
  for _, r in ipairs(results) do
    local share = r.deep / math.max(r.interior, 1)
    if share < deep_share_low then deep_share_low = share end
    deep_share_sum = deep_share_sum + share
    if r.t100 < t_low then t_low = r.t100 end
    if r.t100 < NONE then
      t_sum, t_count = t_sum + r.t100, t_count + 1
    end
  end
  -- Gemeinsame Schwelle: größter Rasterwert T_STEPS ≤ kleinstes t100 aller Seeds.
  local step
  for index, t in ipairs(T_STEPS) do
    if t <= t_low then
      step = index
      break
    end
  end
  local common = "keine (t100 unter " .. fmt(T_STEPS[#T_STEPS]) .. ")"
  if step then
    local low, high, sum = INF, -INF, 0
    for _, r in ipairs(results) do
      local share = r.below[step] / math.max(r.interior, 1)
      if share < low then low = share end
      if share > high then high = share end
      sum = sum + share
    end
    common = string.format("t = %s → Spicefläche min %s, Mittel %s, max %s", fmt(T_STEPS[step]),
      pct(low, 1), pct(sum / #results, 1), pct(high, 1))
  end
  tb.log(run, "MESSUNG", string.format("Σ %s (%s): Fels min %s, Mittel %s, max %s; Felsschwelle %s … %s (Mittel %s); " ..
    "Inseln im Mittel %.1f je 1,6 × 1,6 km; Sand ≥ %d vom Fels min %s, Mittel %s; t100 kleinstes %s, Mittel %s; gemeinsame Schwelle %s; " ..
    "Werte min %s, Median %s, max %s",
    variant.key, variant.title, pct(rock_low, 1), pct(rock_mean, 1), pct(rock_high, 1), fmt(off_low, 3), fmt(off_high, 3),
    fmt(off_mean, 3), islands_mean, TARGET, pct(deep_share_low, 1), pct(deep_share_sum / #results, 1),
    fmt(t_low, 3), t_count > 0 and fmt(t_sum / t_count, 3) or "–", common, fmt(qmin_low), fmt(q50_mean), fmt(qmax_high)))
  return string.format("%s Fels %s, Spice %s", variant.key, pct(rock_mean, 1), step and fmt(T_STEPS[step]) or "–")
end

-- Phasen ---------------------------------------------------------------------------------------

local phases = {}

local function surface_of(d)
  local surface = d.surface_name and game.get_surface(d.surface_name)
  if surface and surface.valid then return surface end
  return nil
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
  for _, variant in ipairs(VARIANTS) do
    d.values[variant.key] = {}
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
    for _, variant in ipairs(VARIANTS) do
      local list = result[variant.property]
      if not list then
        tb.log(run, "FEHLER", "calculate_tile_properties liefert keinen Wert für " .. variant.property ..
          " (Prüfstand-Einstellung aus oder Name falsch?)")
        tb.finish(run, "abgebrochen (Wert fehlt)")
        return
      end
      local target = d.values[variant.key]
      for index = 1, last - first + 1 do
        target[first + index - 1] = list[index]
      end
    end
    d.k = last + 1
  end
  if d.k > total then
    d.vi = 1
    d.phase = "auswerten"
  end
end

-- Eine Variante je Tick auswerten.
phases.auswerten = function(run, tb, d)
  local entry = d.seeds[d.si]
  local variant = VARIANTS[d.vi]
  local result = analyse(variant, entry, d.values[variant.key])
  table.insert(d.results[variant.key], result)
  tb.trace(run, result_line(variant, entry, result))
  d.values[variant.key] = nil
  d.vi = d.vi + 1
  if d.vi <= #VARIANTS then return end

  local surface = surface_of(d)
  if surface then pcall(function() game.delete_surface(surface) end) end
  d.surface_name = nil
  d.values = nil
  tb.log(run, "INFO", string.format("Seed %d von %d fertig (%d, %s)", d.si, #d.seeds, entry.seed, entry.label))
  d.si = d.si + 1
  d.phase = d.si <= #d.seeds and "anlegen" or "bericht"
end

phases.bericht = function(run, tb, d)
  local summary = {}
  for _, variant in ipairs(VARIANTS) do
    local text = summarize(run, tb, variant, d.results[variant.key])
    if text then summary[#summary + 1] = text end
  end
  tb.log(run, "INFO", "Kartenbilder: script-output/" .. MAP_FILE .. " (# Fels, - Sand unter " .. TARGET ..
    " Kacheln vom Fels, . Sand ab " .. TARGET .. ", o Spicefläche, S Ursprung; 1 Zeichen = 16 Kacheln). Bitte mitschicken.")
  d.phase = "fertig"
  tb.finish(run, table.concat(summary, "; "))
end

-- Vertrag ----------------------------------------------------------------------------------------

local function start(run, tb)
  local d = run.data
  d.seeds = seed_list()
  d.results = {}
  for _, variant in ipairs(VARIANTS) do
    d.results[variant.key] = {}
  end
  d.si = 1
  local names = {}
  for _, entry in ipairs(d.seeds) do names[#names + 1] = tostring(entry.seed) end
  tb.log(run, "INFO", string.format("T11 vergleicht %d Fels-Varianten auf %d Seeds (%s), je %d × %d Kacheln, ohne Karte zu erzeugen. " ..
    "Das Spiel ruckelt dabei einige Sekunden. Du bleibst, wo du bist.", #VARIANTS, #d.seeds, table.concat(names, ", "),
    2 * HALF, 2 * HALF))
  write_map(string.format("##### T11 Tick %d: %d Varianten, %d Seeds, Gebiet %d … %d, 1 Zeichen = %d Kacheln #####\n\n",
    game.tick, #VARIANTS, #d.seeds, -HALF, HALF - 1, GRID * PICTURE_STEP))
  d.phase = "anlegen"
end

local function tick(run, tb)
  local phase = phases[run.data.phase]
  if phase then phase(run, tb, run.data) end
end

-- Testoberfläche löschen und große Arbeitstabellen freigeben.
local function cleanup(run, tb)
  local d = run.data
  local surface = surface_of(d)
  if surface then pcall(function() game.delete_surface(surface) end) end
  d.surface_name = nil
  d.values = nil
end

return
{
  T11 =
  {
    title = "Kartengenerator: Fels-Varianten im Seed-Vergleich",
    timeout = 180 * 60,
    interactive = false,
    confirm = nil,
    hint = "schreibt zusätzlich script-output/arrakis-t11-karten.txt",
    start = start,
    tick = tick,
    cleanup = cleanup
  }
}
