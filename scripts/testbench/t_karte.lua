-- Prüfstand: Kartengenerator-Test T14 „Karte echt“ (Vertrag siehe runner.lua).
-- T14 nimmt die Karte 2 (ab 0.5.4, reguläres Spice ab 0.5.5 aus arrakis_v3_spice_*) auf echten Kacheln
-- ab (T11-Empfehlung, Bauplan Schritt 6). Je Seed (der Seed dieses Spielstands und 8 feste wie in T11, mit
-- „/arrakis-test T14 lang“ 30) legt der Test eine Testoberfläche mit den Kartengenerator-Einstellungen des
-- Planeten Arrakis an, erzeugt die Chunks im Radius 12 um den Ursprung (800 × 800 Kacheln), liest
-- Felskacheln und Ressourcen und rechnet eine exakte euklidische Abstandstransformation auf Kacheln (Abstand
-- jeder Kachelmitte zur Mitte der nächsten Felskachel). Danach wird die Oberfläche gelöscht. Arrakis und der
-- Spieler bleiben unberührt.
-- FEHLER (je Seed):
--   reguläres Spice-Sand (mehr als 160 Kacheln vom Start) näher als 100 Kacheln am Fels;
--   kein Lehrfeld (Spice bis 160 Kacheln vom Start), eine Lehrfeld-Kachel nicht 40–60 Kacheln vom Fels
--   oder die Menge des Lehrfelds mehr als 5 % neben 100 000 Spice-Sand;
--   Spice auf Fels, Erz auf Sand, Tiefenwasser mit einer seiner 3 × 3 Kacheln auf Sand;
--   Ursprung nicht auf Fels, auf der Startinsel fehlt ein Erz von Arrakis oder ein Tiefenbrunnen;
--   Fels außer der Startinsel näher als 220 Kacheln am Start (Graben);
--   Chunks nicht erzeugt.
-- Spice-Kacheln nahe am Gebietsrand, deren Fels im Gebiet mindestens 100 weg ist, gelten als nicht
-- gewertet: Fels außerhalb des Gebiets kennt der Test nicht. Ein Seed ohne reguläres Spice im Gebiet ist
-- für den Abstand nicht prüfbar (INFO); auf allen Seeds ohne ist das ein FEHLER, sonst bestünde ein
-- kaputter Spice-Ausdruck die Prüfung.
-- FEHLER (nach allen Seeds, ab 0.5.5; Grund: T14 mit 0.5.4 fand im Mittel 0,9 reguläre Felder je Seed,
-- Median 134 Kacheln, siehe prototypes/noise.lua bei arrakis_v3_*). Nutzbar ist ein reguläres Feld
-- (zusammenhängendes Spice, 8er-Nachbarschaft wie unten) ab USABLE = 300 Kacheln, auch ein am Gebietsrand
-- angeschnittenes:
--   „Felder“: im Mittel weniger als 2 nutzbare Felder je Seed, oder mehr als ⌈n / 9⌉ der n Seeds ohne
--     nutzbares Feld (9 Seeds: höchstens 1, „lang“ mit 30: höchstens 4).
--   „Feldgröße“: Median der Größe aller nutzbaren Felder aller Seeds unter 500 Kacheln. Ohne nutzbares
--     Feld nicht prüfbar (INFO); das meldet schon „Felder“.
--   Die Schätzung für 0.5.5 liegt weit darüber (etwa 5,1 Felder je Seed, Median etwa 1150 Kacheln). Die
--   Simulation setzt Felder nur an günstige Kandidaten wie jetzt arrakis_v3_spot, bleibt aber eine
--   Schätzung (prototypes/noise.lua).
--   Ein Lauf, der vor 0.5.5 begann und nach einem Update weiterläuft, hat d.usable_check nicht (start); beide
--   sind dann nicht prüfbar (INFO), statt im Bericht an fehlenden Daten abzubrechen.
-- Nach allen Seeds zwei Durchgänge nur auf dem ersten Seed (d.pass):
--   „groesse0“: Spice-Regler auf Größe 0, Chunks im Radius 9. FEHLER, wenn das Lehrfeld dann fehlt
--     oder nicht 100 000 ± 5 % Spice-Sand hat (Festlegung 0.5.4: Es bleibt bei Größe 0), oder wenn
--     dann noch reguläres Spice liegt. Das Gebiet reicht bis 288 Kacheln je Achse, also in den Bereich
--     ab 215 Kacheln, in dem reguläres Spice liegen darf (Spicezone), und über die etwa 225 Kacheln hinaus,
--     ab denen die Fleckmitten liegen (arrakis_v3_spice_favorability, arrakis_v3_spot).
--   „alt“: dieselbe Fläche mit den Ausdrücken der Karte 0.4.0, nur zum Zeitvergleich.
-- MESSUNG: Zahl und Größe der regulären Felder, nutzbare Felder je Seed und ihre Größe im Median, Abstand
-- Start → nächstes reguläres Feld, Lehrfeld (Lage, größter dichter Block für den 13×13-Ernter), Startinsel,
-- Graben (nächster Fels außer der Startinsel), Dauer der Chunk-Erzeugung.
-- Die Rechenlast ist über Ticks verteilt: je Tick eine Chunkreihe erzeugen bzw. lesen, 100 Zeilen bzw.
-- Spalten der Abstandstransformation. Der Zustand liegt als reine Daten in run.data.
-- Die Dauer misst ein LuaProfiler. Er lässt sich nicht speichern und liegt deshalb nur in einer
-- Modulvariable (nur für die Ausgabe, nichts davon geht nach run.data); wird mitten im Test ein
-- Spielstand geladen, fehlt die Zeitangabe.

local CHUNK_RADIUS = 12                  -- Chunks −12 … 12 in x und y
local SIZE0_RADIUS = 9                   -- Durchgang „groesse0“: Chunks −9 … 9 (Kacheln −288 … 319)
local LEFT = -CHUNK_RADIUS * 32          -- erste Kachel in x und y (−384)
local N = (2 * CHUNK_RADIUS + 1) * 32    -- Kacheln je Zeile und Spalte (800)
local LINES_PER_TICK = 100               -- Zeilen bzw. Spalten der Abstandstransformation je Tick
local GENERATE_TRIES = 3                 -- Versuche je Chunkreihe
local TARGET = 100                       -- Mindestabstand reguläres Spice → Fels (Design 4.1)
local LEHR_MAX = 160                     -- Spice bis hier vom Start gehört zum Lehrfeld
-- Lehrfeld-Kacheln: Abstand zum Fels (Design 2.1). Gemessen von Kachelmitte zu Kachelmitte liegt eine
-- richtige Karte 0.5.4 bei 40,7 bis 60,0 (41–59 vom Inselrand, dazu Raster und Felskante, nachgerechnet):
-- Schon eine Kachel Verschiebung fällt auf. 41 als Untergrenze gäbe Fehlalarme.
local LEHR_ROCK_MIN, LEHR_ROCK_MAX = 40, 60
local LEHR_AMOUNT = 100000               -- Spice-Sand im Lehrfeld (erschöpfbar, Festlegung 0.5.4)
local LEHR_TOLERANCE = 0.05              -- nachgerechnet 99 910 bis 100 190 (prototypes/noise.lua)
-- Graben: kein Fels außer der Startinsel bis GRABEN vom Start (Festlegung 0.5.4). GRABEN_SLACK: die Felskante
-- (bis 0,4 Kacheln bei 1/150 je Kachel) und die Kachelmitte gegen den Punkt, an dem das Rauschen rechnet (0,7).
local GRABEN = 220
local GRABEN_SLACK = 1.5
local HARVEST_SIZE = 13                  -- Erntefeld des Ernters (Design 2.1)
local ISLAND_BOX = 250                   -- Startinsel: Suche bis hier vom Ursprung (je Achse)
local SPICE_LIMIT = 150000               -- höchstens so viele Spice-Kacheln je Seed auswerten
-- Nutzbare Felder (Prüfungen „Felder“ und „Feldgröße“ nach allen Seeds, ab 0.5.5).
local USABLE = 300                       -- ein reguläres Feld ab so vielen Kacheln ist nutzbar
local USABLE_MEAN = 2                    -- im Mittel mindestens so viele nutzbare Felder je Seed
local EMPTY_SHARE = 9                    -- höchstens ⌈n / 9⌉ der n Seeds ohne nutzbares Feld
local USABLE_MEDIAN = 500                -- Median der Größe aller nutzbaren Felder mindestens so viele Kacheln
local SURFACE_PREFIX = "arrakis-t14-"
local LOG_FILE = "arrakis-test.txt"      -- wie in runner.lua; Zeilen mit Zeitmessung schreibt T14 selbst
local ROCK = "arrakis-rock"
local SPICE = "spice-sand"
local DEEP_WATER = "arrakis-deep-water"
local SPICE_CONTROL = "arrakis_spice"    -- Autoplace-Regler für Spice (prototypes/noise.lua)
local V2_PREFIX = "arrakis_v2_"
-- Präfixe der Karte 2 (Spice ab 0.5.5 aus arrakis_v3_*); Durchgang „alt“ stellt beide auf arrakis_ zurück.
local MAP2_PREFIXES = {V2_PREFIX, "arrakis_v3_"}
local DEFAULT_ORES = {"iron-ore", "copper-ore", "stone", "coal"}
local DEFAULT_TILES = {"sand-1", "sand-2", "sand-3", ROCK}
local NAMES = {["iron-ore"] = "Eisen", ["copper-ore"] = "Kupfer", ["stone"] = "Stein", ["coal"] = "Kohle",
               [DEEP_WATER] = "Tiefenwasser", [SPICE] = "Spice"}
-- Seeds wie in t_map.lua (T11), damit beide Tests dieselben Karten sehen.
local FIXED_SEEDS = {1234, 98765, 424242, 1000003, 2718281, 3141592, 16180339, 27182818}
local LONG_SEEDS = {7, 42, 99, 314, 1001, 2024, 4711, 8191, 12345, 31337, 65537, 99991, 131071, 271828,
                    524287, 777777, 1234567, 2147483, 3000017, 9999991, 123456789, 987654321}
local LONG_COUNT = 30
-- Durchgänge: erst alle Seeds, dann Spice-Größe 0 und der Zeitvergleich (beide auf dem ersten Seed).
local PASSES = {"karte", "groesse0", "alt"}
local SUFFIX = {karte = "", groesse0 = "-g0", alt = "-alt"}
local INF = math.huge
local BIG = 1e10                         -- quadrierter Abstand „kein Fels“ in der Abstandstransformation
local NONE = 1e9                         -- „kein Wert“ in gespeicherten Ergebnissen (statt math.huge)

-- Prüfungen in der Reihenfolge der Zusammenfassung.
local CHECKS =
{
  {key = "erzeugt", title = "Chunks erzeugt"},
  {key = "ursprung", title = "Ursprung auf Fels"},
  {key = "startinsel", title = "Startinsel mit allen Erzen und einem Tiefenbrunnen"},
  {key = "graben", title = "Graben: kein Fels außer der Startinsel bis " .. GRABEN .. " Kacheln vom Start"},
  {key = "lehrfeld", title = "Lehrfeld vorhanden"},
  {key = "lehrfeld_abstand", title = "Lehrfeld-Kacheln " .. LEHR_ROCK_MIN .. "–" .. LEHR_ROCK_MAX .. " Kacheln vom Fels"},
  {key = "lehrfeld_menge", title = "Lehrfeld 100 000 Spice-Sand ± " .. LEHR_TOLERANCE * 100 .. " %"},
  {key = "abstand", title = "Reguläres Spice mindestens " .. TARGET .. " Kacheln vom Fels",
   required = "auf keinem Seed reguläres Spice im Gebiet"},
  -- total: eine Prüfung über alle Seeds (total_checks); absent: Text, wenn sie nicht prüfbar ist.
  {key = "felder", title = string.format("Felder: im Mittel mindestens %d nutzbare Felder (reguläre Felder ab %d Kacheln) " ..
   "je Seed, höchstens 1/%d der Seeds (aufgerundet) ohne", USABLE_MEAN, USABLE, EMPTY_SHARE), total = true,
   absent = "keine Seeds ausgewertet"},
  {key = "feldgroesse", title = string.format("Feldgröße: nutzbare Felder im Median mindestens %d Kacheln", USABLE_MEDIAN),
   total = true, absent = "auf keinem Seed ein nutzbares Feld (siehe „Felder“)"},
  {key = "spice_fels", title = "Kein Spice auf Fels"},
  {key = "erz_sand", title = "Kein Erz und kein Tiefenwasser auf Sand (Tiefenwasser: alle 3 × 3 Kacheln)"},
  {key = "lehrfeld_groesse0", title = "Lehrfeld auch bei Spice-Größe 0 (100 000 Spice-Sand ± " .. LEHR_TOLERANCE * 100 .. " %)",
   once = true},
  {key = "groesse0_regulaer", title = "Kein reguläres Spice bei Spice-Größe 0", once = true}
}

-- Zeitmessung nur für die Ausgabe (LuaProfiler lässt sich nicht speichern). key ordnet sie dem Lauf zu.
-- incomplete: Summe ohne mindestens einen Seed. Liegt hier und nicht in run.data, weil es vom Profiler
-- abhängt, den ein später beigetretener Mitspieler nicht hat.
local timing = {key = nil, seed = nil, total_key = nil, total = nil, incomplete = false}

-- Helfer ---------------------------------------------------------------------------------------

local function fmt(value, digits)
  if value == nil then return "–" end
  if value >= NONE / 10 then return "∞" end
  if value <= -NONE / 10 then return "−∞" end
  return string.format("%." .. (digits or 1) .. "f", value)
end

local function pct(part, total)
  if not total or total <= 0 then return "–" end
  return string.format("%.1f %%", 100 * part / total)
end

-- Ganze Zahl mit Tausenderpunkten (100.000 → „100 000“).
local function amount_text(value)
  local text = string.format("%d", math.floor(value + 0.5))
  local result = text:reverse():gsub("(%d%d%d)", "%1 "):reverse()
  return (result:gsub("^ ", ""):gsub("^%- ", "-"))
end

local function name_of(name)
  return NAMES[name] or name
end

local function sorted_keys(map)
  local keys = {}
  for key in pairs(map or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

local function spread(list)
  local low, high, sum = INF, -INF, 0
  for _, v in ipairs(list) do
    if v < low then low = v end
    if v > high then high = v end
    sum = sum + v
  end
  return low, sum / math.max(#list, 1), high
end

-- digits: Nachkommastellen; as_amount: Ganzzahl mit Tausenderabständen (amount_text).
local function spread_text(list, digits, as_amount)
  if #list == 0 then return "–" end
  local low, mean, high = spread(list)
  local function f(value) return as_amount and amount_text(value) or fmt(value, digits or 0) end
  return string.format("min %s, Mittel %s, max %s", f(low), f(mean), f(high))
end

-- Kachel (x, y) ↔ Index im Gebiet (ab 1, zeilenweise).
local function index_of(x, y)
  return (y - LEFT) * N + (x - LEFT) + 1
end

local function tile_of(k)
  local i = (k - 1) % N
  local j = (k - 1 - i) / N
  return LEFT + i, LEFT + j
end

local function inside(x, y)
  return x >= LEFT and x < LEFT + N and y >= LEFT and y < LEFT + N
end

-- Abstand der Kachelmitte zum Ursprung (Startpunkt 0,0).
local function from_start(x, y)
  return math.sqrt((x + 0.5) ^ 2 + (y + 0.5) ^ 2)
end

-- Abstand der Kachelmitte zur nächsten Kachelmitte außerhalb des Gebiets.
local function border_distance(x, y)
  local i, j = x - LEFT, y - LEFT
  return math.min(i + 1, N - i, j + 1, N - j)
end

-- Seeds: der Seed dieses Spielstands (Arrakis, sonst Nauvis) und die festen Seeds, mit long bis 30 (wie T11).
local function seed_list(long)
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
  local lists = long and {FIXED_SEEDS, LONG_SEEDS} or {FIXED_SEEDS}
  for _, list in ipairs(lists) do
    for _, seed in ipairs(list) do
      if long and #seeds >= LONG_COUNT then break end
      if not (seeds[1] and seeds[1].seed == seed) then
        seeds[#seeds + 1] = {seed = seed, label = "fest"}
      end
    end
  end
  return seeds
end

-- Gibt es den Rauschausdruck? (nil, wenn die Liste nicht lesbar ist)
local function expression_exists(name)
  local ok, known = pcall(function() return prototypes.named_noise_expression end)
  if not ok or not known then return nil end
  return (pcall(function() return known[name].name end))
end

-- Rest des Namens hinter einem Präfix der Karte 2 (MAP2_PREFIXES), sonst nil.
local function map2_rest(value)
  if type(value) ~= "string" then return nil end
  for _, prefix in ipairs(MAP2_PREFIXES) do
    if string.sub(value, 1, #prefix) == prefix then return string.sub(value, #prefix + 1) end
  end
  return nil
end

-- Kartengenerator-Einstellungen von Arrakis für seed. pass (PASSES): „karte“ wie der Planet;
-- „groesse0“ mit dem Spice-Regler auf Größe 0; „alt“ Karte 0.4.0 zum Zeitvergleich, also jeder
-- Schlüssel mit einem arrakis_v2_…- oder arrakis_v3_…-Ausdruck (Spice ab 0.5.5) auf den gleichnamigen
-- alten Ausdruck (arrakis_…) gestellt oder, wenn es den nicht gibt, gestrichen (dann gilt die
-- Autoplace-Regel des Prototyps wie bis 0.5.3).
local function settings_for(seed, pass)
  local map_gen = game.planets["arrakis"].prototype.map_gen_settings
  map_gen.seed = seed
  -- Ohne Startpunkt gäbe es weder Startinsel noch Lehrfeld (distance, starting_spot_at_angle).
  if type(map_gen.starting_points) ~= "table" or #map_gen.starting_points == 0 then
    map_gen.starting_points = {{x = 0, y = 0}}
  end
  if pass == "alt" then
    local names = map_gen.property_expression_names or {}
    for key, value in pairs(names) do
      local rest = map2_rest(value)
      if rest then
        local previous = "arrakis_" .. rest
        names[key] = expression_exists(previous) and previous or nil
      end
    end
    map_gen.property_expression_names = names
  elseif pass == "groesse0" then
    local controls = map_gen.autoplace_controls or {}
    local spice = controls[SPICE_CONTROL] or {}
    spice.size = 0
    controls[SPICE_CONTROL] = spice
    map_gen.autoplace_controls = controls
  end
  return map_gen
end

-- Exakte quadratische Abstandstransformation in 1D (Felzenszwalb/Huttenlocher) über f[0 … n − 1]
-- (wie in t_map.lua).
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

-- Abstand der Kachel k zum nächsten Fels in Kacheln (INF ohne Fels im Gebiet).
local function rock_distance(grid, k)
  local value = grid[k]
  if value >= BIG / 10 then return INF end
  return math.sqrt(value)
end

-- Zählt einen Fund (count) und merkt sich den ersten Ort und je Name die Zahl.
local function note(found, x, y, name)
  found.count = found.count + 1
  if not found.x then found.x, found.y = x, y end
  if name then found.by[name] = (found.by[name] or 0) + 1 end
end

local function new_found()
  return {count = 0, by = {}}
end

local function by_text(by)
  local parts = {}
  for _, name in ipairs(sorted_keys(by)) do parts[#parts + 1] = name_of(name) .. " " .. by[name] end
  return table.concat(parts, ", ")
end

-- Oberflächen ----------------------------------------------------------------------------------

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

-- Testoberflächen früherer, abgebrochener Läufe entfernen.
local function delete_leftovers()
  local names = {}
  for _, surface in pairs(game.surfaces) do
    if surface.valid and string.sub(surface.name, 1, #SURFACE_PREFIX) == SURFACE_PREFIX then
      names[#names + 1] = surface.name
    end
  end
  for _, name in ipairs(names) do
    pcall(function() game.delete_surface(name) end)
  end
  return #names
end

-- Zeitmessung ---------------------------------------------------------------------------------

local function timer_key(run, d)
  return run.started .. "/" .. d.si .. "/" .. d.pass
end

-- Profiler der laufenden Chunk-Erzeugung; beim ersten Versuch der ersten Reihe neu. nil, wenn er fehlt.
local function seed_timer(run, d)
  local key = timer_key(run, d)
  if d.cy == -d.radius and d.tries == 0 then
    local ok, profiler = pcall(function() return helpers.create_profiler(true) end)
    timing.key, timing.seed = key, ok and profiler or nil
  end
  if timing.key ~= key then return nil end
  return timing.seed
end

-- MESSUNG-Zeile mit Zeitangabe direkt in die Datei (tb.trace nimmt nur Text, der Profiler ist ein LuaObject).
local function write_timing(run, tb, text, profiler)
  if not profiler then
    tb.trace(run, text .. "nicht messbar (Spielstand mitten im Test geladen?)")
    return
  end
  local line = string.format("[%s] MESSUNG +%.1fs: %s", run.id, (game.tick - run.started) / 60, text)
  pcall(function() helpers.write_file(LOG_FILE, {"", line, profiler, "\n"}, true) end)
end

-- Prüfungen ------------------------------------------------------------------------------------

-- Ergebnis einer Prüfung für den laufenden Seed. ok: true, false oder nil (nicht prüfbar).
local function verdict(run, tb, d, key, ok, text)
  if ok == nil then return end
  local entry = d.seeds[d.si]
  d.checked[key] = (d.checked[key] or 0) + 1
  if not ok then
    table.insert(d.failed[key], tostring(entry.seed))
    tb.log(run, "FEHLER", string.format("Seed %d (%s): %s", entry.seed, entry.label, text))
  end
end

-- Phasen ---------------------------------------------------------------------------------------

local phases = {}

local function abort(run, tb, text, summary)
  tb.log(run, "FEHLER", text)
  tb.finish(run, "abgebrochen (" .. summary .. ")")
end

-- Nächster Durchgang (PASSES) auf dem ersten Seed, nach dem letzten der Bericht.
local function next_pass(d)
  delete_surface(d)
  for index, pass in ipairs(PASSES) do
    if pass == d.pass and PASSES[index + 1] then
      d.pass, d.si, d.phase = PASSES[index + 1], 1, "anlegen"
      return
    end
  end
  d.phase = "bericht"
end

-- Störung: bei den Seeds der Karte Abbruch mit FEHLER; bei den Zusatzdurchgängen nur INFO,
-- dann der nächste Durchgang (ein FEHLER-Ergebnis bleibt dort aus, „groesse0“ gilt als nicht prüfbar).
local function trouble(run, tb, d, text, summary)
  if d.pass == "karte" then
    abort(run, tb, text, summary)
    return
  end
  tb.log(run, "INFO", string.format("Durchgang %s übersprungen: %s", d.pass, text))
  next_pass(d)
end

-- Testoberfläche für den nächsten Seed bzw. Durchgang anlegen.
phases.anlegen = function(run, tb, d)
  local entry = d.seeds[d.si]
  local ok, settings = pcall(settings_for, entry.seed, d.pass)
  if not ok or type(settings) ~= "table" then
    trouble(run, tb, d, "Kartengenerator-Einstellungen von Arrakis nicht lesbar: " .. tostring(settings), "keine Einstellungen")
    return
  end
  local name = SURFACE_PREFIX .. run.started .. "-" .. d.si .. SUFFIX[d.pass]
  local ok_surface, surface = pcall(function()
    if game.get_surface(name) then error("Oberfläche gibt es schon") end
    return game.create_surface(name, settings)
  end)
  if not ok_surface or not surface then
    trouble(run, tb, d, "Testoberfläche " .. name .. " nicht angelegt: " .. tostring(surface), "keine Testoberfläche")
    return
  end
  d.surface_name = name
  for _, force in pairs(game.forces) do
    pcall(function() force.set_surface_hidden(surface, true) end)
  end
  d.radius = d.pass == "groesse0" and SIZE0_RADIUS or CHUNK_RADIUS
  d.cy, d.tries, d.missing = -d.radius, 0, 0
  d.phase = "erzeugen"
end

-- Eine Chunkreihe je Tick erzeugen (sofort, damit das Spiel nur kurz steht).
phases.erzeugen = function(run, tb, d)
  local surface = surface_of(d)
  if not surface then
    trouble(run, tb, d, "Testoberfläche verschwunden", "Testoberfläche fehlt")
    return
  end
  local radius = d.radius
  local timer = seed_timer(run, d)
  for cx = -radius, radius do
    surface.request_to_generate_chunks({x = cx * 32 + 16, y = d.cy * 32 + 16}, 0)
  end
  if timer then timer.restart() end
  surface.force_generate_chunk_requests()
  if timer then timer.stop() end
  local missing = 0
  for cx = -radius, radius do
    if not surface.is_chunk_generated({x = cx, y = d.cy}) then missing = missing + 1 end
  end
  if missing > 0 then
    d.tries = d.tries + 1
    if d.tries < GENERATE_TRIES then return end
    d.missing = d.missing + missing
  end
  d.tries = 0
  d.cy = d.cy + 1
  if d.cy <= radius then return end

  local entry = d.seeds[d.si]
  local chunks = (2 * radius + 1) ^ 2
  if d.pass == "alt" then
    write_timing(run, tb, string.format("Seed %d (%s), Karte 0.4.0 (Ausdrücke ohne %s) zum Vergleich: Chunk-Erzeugung " ..
      "%d Chunks: ", entry.seed, entry.label, table.concat(MAP2_PREFIXES, "/"), chunks), timer)
    next_pass(d)
    return
  end
  if d.pass == "groesse0" then
    write_timing(run, tb, string.format("Seed %d (%s), Spice-Größe 0: Chunk-Erzeugung %d Chunks: ",
      entry.seed, entry.label, chunks), timer)
    d.phase = "groesse0"
    return
  end
  write_timing(run, tb, string.format("Seed %d (%s): Chunk-Erzeugung %d Chunks (%d × %d Kacheln): ",
    entry.seed, entry.label, chunks, N, N), timer)
  if timer and timing.total and timing.total_key == run.started then
    timing.total.add(timer)
  else
    timing.incomplete = true
  end
  d.current = {missing = d.missing}
  d.grid = {}
  d.rock_tiles, d.foreign = 0, 0
  d.spice_n, d.spice_k, d.spice_amount, d.spice_extra = 0, {}, {}, 0
  d.spice_on_rock, d.ore_on_sand = new_found(), new_found()
  d.resources, d.wells = {}, {}
  d.cy = -CHUNK_RADIUS
  d.phase = "lesen"
end

-- Eine Chunkreihe je Tick lesen: Fels in d.grid (0 Fels, BIG sonst), Ressourcen nach Art.
phases.lesen = function(run, tb, d)
  local surface = surface_of(d)
  if not surface then
    abort(run, tb, "Testoberfläche verschwunden", "Testoberfläche fehlt")
    return
  end
  local grid = d.grid
  local y0 = d.cy * 32
  local j0 = y0 - LEFT
  for k = j0 * N + 1, (j0 + 32) * N do grid[k] = BIG end
  local area = {left_top = {x = LEFT, y = y0}, right_bottom = {x = LEFT + N, y = y0 + 32}}
  for _, tile in ipairs(surface.find_tiles_filtered{area = area, name = ROCK}) do
    local p = tile.position
    if inside(p.x, p.y) and p.y >= y0 and p.y < y0 + 32 then
      grid[index_of(p.x, p.y)] = 0
      d.rock_tiles = d.rock_tiles + 1
    end
  end
  d.foreign = d.foreign + surface.count_tiles_filtered{area = area, name = d.tile_names, invert = true}
  for _, entity in ipairs(surface.find_entities_filtered{area = area, type = "resource"}) do
    if entity.valid then
      local p = entity.position
      local x, y = math.floor(p.x), math.floor(p.y)
      if inside(x, y) and y >= y0 and y < y0 + 32 then
        local k = index_of(x, y)
        local on_rock = grid[k] == 0
        local name = entity.name
        if name == SPICE then
          if on_rock then note(d.spice_on_rock, x, y) end
          if d.spice_n < SPICE_LIMIT then
            local n = d.spice_n + 1
            d.spice_n = n
            d.spice_k[n] = k
            d.spice_amount[n] = entity.amount
          else
            d.spice_extra = d.spice_extra + 1
          end
        else
          local resource = d.resources[name] or {count = 0, amount = 0}
          d.resources[name] = resource
          resource.count = resource.count + 1
          resource.amount = resource.amount + entity.amount
          -- Tiefenwasser belegt 3 × 3 Kacheln; die Nachbarreihe ist hier noch nicht gelesen (Prüfung in „insel“).
          if name == DEEP_WATER then
            d.wells[#d.wells + 1] = k
          elseif not on_rock then
            note(d.ore_on_sand, x, y, name)
          end
        end
      end
    end
  end
  d.cy = d.cy + 1
  if d.cy > CHUNK_RADIUS then
    d.line = 0
    d.phase = "zeilen"
  end
end

-- Abstandstransformation, erst zeilenweise, dann spaltenweise; LINES_PER_TICK je Tick, in d.grid.
local function transform_lines(d, by_column)
  local grid = d.grid
  local f, out, v, z = {}, {}, {}, {}
  local last = math.min(N - 1, d.line + LINES_PER_TICK - 1)
  for line = d.line, last do
    if by_column then
      for j = 0, N - 1 do f[j] = grid[j * N + line + 1] end
      edt_1d(f, N, out, v, z)
      for j = 0, N - 1 do grid[j * N + line + 1] = out[j] end
    else
      local base = line * N + 1
      for i = 0, N - 1 do f[i] = grid[base + i] end
      edt_1d(f, N, out, v, z)
      for i = 0, N - 1 do grid[base + i] = out[i] end
    end
  end
  d.line = last + 1
  return d.line >= N
end

phases.zeilen = function(run, tb, d)
  if transform_lines(d, false) then
    d.line = 0
    d.phase = "spalten"
  end
end

phases.spalten = function(run, tb, d)
  if transform_lines(d, true) then d.phase = "insel" end
end

-- Ursprung und Startinsel (zusammenhängender Fels um den Ursprung, 4er-Nachbarschaft) samt ihren Ressourcen.
phases.insel = function(run, tb, d)
  local grid = d.grid
  local current = d.current
  local origin = {}
  for _, t in ipairs({{0, 0}, {-1, 0}, {0, -1}, {-1, -1}}) do
    if grid[index_of(t[1], t[2])] ~= 0 then origin[#origin + 1] = string.format("(%d, %d)", t[1], t[2]) end
  end
  current.origin_sand = origin

  -- Anfang der Suche: Kachel (0, 0), sonst die nächste Felskachel bis ISLAND_BOX.
  local first = grid[index_of(0, 0)] == 0 and index_of(0, 0) or nil
  if not first then
    local best = INF
    for y = -ISLAND_BOX, ISLAND_BOX do
      for x = -ISLAND_BOX, ISLAND_BOX do
        local k = index_of(x, y)
        if grid[k] == 0 then
          local r = from_start(x, y)
          if r < best then best, first = r, k end
        end
      end
    end
  end
  local island = {tiles = 0, r_min = NONE, r_max = 0, at_limit = false, found = first ~= nil, by = {}}
  current.island = island
  local member = {}
  if first then
    local stack, top = {first}, 1
    member[first] = true
    local x1, y1, x2, y2 = INF, INF, -INF, -INF
    while top > 0 do
      local k = stack[top]
      top = top - 1
      island.tiles = island.tiles + 1
      local x, y = tile_of(k)
      if x < x1 then x1 = x end
      if y < y1 then y1 = y end
      if x > x2 then x2 = x end
      if y > y2 then y2 = y end
      local edge = false
      for _, step in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
        local nx, ny = x + step[1], y + step[2]
        if math.abs(nx) > ISLAND_BOX or math.abs(ny) > ISLAND_BOX or not inside(nx, ny) then
          island.at_limit = true
        else
          local nk = index_of(nx, ny)
          if grid[nk] ~= 0 then
            edge = true
          elseif not member[nk] then
            member[nk] = true
            top = top + 1
            stack[top] = nk
          end
        end
      end
      if edge then
        local r = from_start(x, y)
        if r < island.r_min then island.r_min = r end
        if r > island.r_max then island.r_max = r end
      end
    end
    local surface = surface_of(d)
    if surface then
      local area = {left_top = {x = x1, y = y1}, right_bottom = {x = x2 + 1, y = y2 + 1}}
      for _, entity in ipairs(surface.find_entities_filtered{area = area, type = "resource"}) do
        if entity.valid then
          local p = entity.position
          local x, y = math.floor(p.x), math.floor(p.y)
          if inside(x, y) and member[index_of(x, y)] then
            island.by[entity.name] = (island.by[entity.name] or 0) + 1
          end
        end
      end
    end
  end

  -- Graben: nächster Fels außer der Startinsel (Fels hat nach der Abstandstransformation den Wert 0).
  local graben = {closest = NONE, inside = 0}
  current.graben = graben
  for k = 1, N * N do
    if grid[k] == 0 and not member[k] then
      local x, y = tile_of(k)
      local r = from_start(x, y)
      if r < graben.closest then graben.closest, graben.x, graben.y = r, x, y end
      if r < GRABEN - GRABEN_SLACK then graben.inside = graben.inside + 1 end
    end
  end

  -- Tiefenwasser: alle 3 × 3 Kacheln unter Brunnen und Pumpe müssen Fels sein.
  for _, k in ipairs(d.wells) do
    local x, y = tile_of(k)
    local sand = false
    for dy = -1, 1 do
      for dx = -1, 1 do
        if inside(x + dx, y + dy) and grid[index_of(x + dx, y + dy)] ~= 0 then sand = true end
      end
    end
    if sand then note(d.ore_on_sand, x, y, DEEP_WATER) end
  end
  d.phase = "felder"
end

-- Größtes Quadrat (Kantenlänge), das ganz aus Kacheln der Menge set besteht; set: Index → true.
local function largest_square(set, x1, y1, x2, y2)
  local best, previous = 0, {}
  for y = y1, y2 do
    local row = {}
    for x = x1, x2 do
      local value = 0
      if set[index_of(x, y)] then
        local left, up, diag = row[x - 1] or 0, previous[x] or 0, previous[x - 1] or 0
        value = math.min(left, up, diag) + 1
        if value > best then best = value end
      end
      row[x] = value
    end
    previous = row
  end
  return best
end

-- Spice auswerten: Lehrfeld, reguläre Felder (8er-Nachbarschaft), Prüfungen und Messwerte des Seeds.
phases.felder = function(run, tb, d)
  local entry = d.seeds[d.si]
  local grid = d.grid
  local current = d.current
  local lehr = {tiles = 0, amount = 0, rock_min = INF, rock_max = 0, bad = new_found(), sx = 0, sy = 0}
  local lehr_set = {}
  local lx1, ly1, lx2, ly2 = INF, INF, -INF, -INF
  local regular = {tiles = 0, amount = 0, near = new_found(), unrated = 0, closest = INF, start_min = INF, box = 0}
  local regular_set = {}
  local worst_x, worst_y
  local box_low, box_high = -SIZE0_RADIUS * 32, (SIZE0_RADIUS + 1) * 32
  for n = 1, d.spice_n do
    local k = d.spice_k[n]
    local x, y = tile_of(k)
    local r = from_start(x, y)
    local rock = rock_distance(grid, k)
    local amount = d.spice_amount[n]
    if r <= LEHR_MAX then
      lehr.tiles = lehr.tiles + 1
      lehr.amount = lehr.amount + amount
      lehr.sx, lehr.sy = lehr.sx + x + 0.5, lehr.sy + y + 0.5
      if rock < lehr.rock_min then lehr.rock_min = rock end
      if rock > lehr.rock_max then lehr.rock_max = rock end
      if rock < LEHR_ROCK_MIN or rock > LEHR_ROCK_MAX then note(lehr.bad, x, y) end
      lehr_set[k] = true
      if x < lx1 then lx1 = x end
      if y < ly1 then ly1 = y end
      if x > lx2 then lx2 = x end
      if y > ly2 then ly2 = y end
    else
      regular.tiles = regular.tiles + 1
      regular.amount = regular.amount + amount
      regular_set[k] = n
      if x >= box_low and x < box_high and y >= box_low and y < box_high then regular.box = regular.box + 1 end
      if r < regular.start_min then regular.start_min = r end
      if rock < regular.closest then regular.closest, worst_x, worst_y = rock, x, y end
      if rock < TARGET then
        note(regular.near, x, y)
      elseif border_distance(x, y) < TARGET then
        regular.unrated = regular.unrated + 1
      end
    end
  end

  -- Reguläre Felder: zusammenhängendes Spice (8er-Nachbarschaft), in der Lesereihenfolge.
  local fields, seen = {}, {}
  for index = 1, d.spice_n do
    local start_k = d.spice_k[index]
    if regular_set[start_k] and not seen[start_k] then
      local field = {tiles = 0, amount = 0, start_min = INF, closest = INF, border = false}
      local stack, top = {start_k}, 1
      seen[start_k] = true
      while top > 0 do
        local k = stack[top]
        top = top - 1
        local n = regular_set[k]
        local x, y = tile_of(k)
        field.tiles = field.tiles + 1
        field.amount = field.amount + d.spice_amount[n]
        local r = from_start(x, y)
        if r < field.start_min then field.start_min = r end
        local rock = rock_distance(grid, k)
        if rock < field.closest then field.closest = rock end
        if border_distance(x, y) <= 1 then field.border = true end
        for dy = -1, 1 do
          for dx = -1, 1 do
            local nx, ny = x + dx, y + dy
            if (dx ~= 0 or dy ~= 0) and inside(nx, ny) then
              local nk = index_of(nx, ny)
              if regular_set[nk] and not seen[nk] then
                seen[nk] = true
                top = top + 1
                stack[top] = nk
              end
            end
          end
        end
      end
      fields[#fields + 1] = field
    end
  end
  table.sort(fields, function(a, b)
    if a.start_min ~= b.start_min then return a.start_min < b.start_min end
    return a.tiles > b.tiles
  end)
  -- usable: Größen der nutzbaren Felder (ab USABLE Kacheln, auch am Gebietsrand) für „Felder“ und „Feldgröße“.
  local sizes, usable, near_fields, border_fields = {}, {}, 0, 0
  for index, field in ipairs(fields) do
    sizes[index] = field.tiles
    if field.tiles >= USABLE then usable[#usable + 1] = field.tiles end
    if field.closest < TARGET then near_fields = near_fields + 1 end
    if field.border then border_fields = border_fields + 1 end
  end
  table.sort(sizes)
  local square = lehr.tiles > 0 and largest_square(lehr_set, lx1, ly1, lx2, ly2) or 0

  -- Prüfungen.
  verdict(run, tb, d, "erzeugt", current.missing == 0,
    string.format("%d Chunks nicht erzeugt (nach %d Versuchen je Reihe)", current.missing, GENERATE_TRIES))
  verdict(run, tb, d, "ursprung", #current.origin_sand == 0,
    "Ursprung nicht auf Fels, Sand an " .. table.concat(current.origin_sand, ", "))
  local island = current.island
  local lacking = {}
  for _, name in ipairs(d.ores) do
    if (island.by[name] or 0) == 0 then lacking[#lacking + 1] = name_of(name) end
  end
  if (island.by[DEEP_WATER] or 0) == 0 then lacking[#lacking + 1] = "Tiefenbrunnen" end
  verdict(run, tb, d, "startinsel", island.found and #lacking == 0,
    island.found and ("auf der Startinsel fehlt " .. table.concat(lacking, ", ")) or "keine Startinsel (kein Fels bis "
      .. ISLAND_BOX .. " Kacheln vom Ursprung)")
  local graben = current.graben
  verdict(run, tb, d, "graben", graben.inside == 0,
    string.format("%d Felskacheln außer der Startinsel näher als %s Kacheln am Start (Graben %d), nächste %s Kacheln " ..
      "vom Start bei (%s, %s)", graben.inside, fmt(GRABEN - GRABEN_SLACK), GRABEN, fmt(graben.closest),
      tostring(graben.x), tostring(graben.y)))
  verdict(run, tb, d, "lehrfeld", lehr.tiles > 0, "kein Lehrfeld (kein Spice bis " .. LEHR_MAX .. " Kacheln vom Start)")
  if lehr.tiles > 0 then
    verdict(run, tb, d, "lehrfeld_abstand", lehr.bad.count == 0,
      string.format("%d von %d Lehrfeld-Kacheln nicht %d–%d Kacheln vom Fels (Abstand %s … %s), z. B. bei (%s, %s)",
        lehr.bad.count, lehr.tiles, LEHR_ROCK_MIN, LEHR_ROCK_MAX, fmt(lehr.rock_min), fmt(lehr.rock_max),
        tostring(lehr.bad.x), tostring(lehr.bad.y)))
    verdict(run, tb, d, "lehrfeld_menge", math.abs(lehr.amount - LEHR_AMOUNT) <= LEHR_TOLERANCE * LEHR_AMOUNT,
      string.format("Lehrfeld hat %s Spice-Sand, Soll %s ± %d %%", amount_text(lehr.amount), amount_text(LEHR_AMOUNT),
        LEHR_TOLERANCE * 100))
  end
  local complete = d.spice_extra == 0
  if regular.tiles == 0 and complete then
    tb.log(run, "INFO", string.format("Seed %d (%s): kein reguläres Spice im Gebiet, Abstand zum Fels hier nicht prüfbar",
      entry.seed, entry.label))
  else
    verdict(run, tb, d, "abstand", regular.near.count == 0 and complete,
      complete and string.format("%d reguläre Spice-Kacheln in %d Feldern näher als %d Kacheln am Fels, kleinster Abstand " ..
        "%s bei (%s, %s)", regular.near.count, near_fields, TARGET, fmt(regular.closest), tostring(worst_x), tostring(worst_y))
        or string.format("mehr als %d Spice-Kacheln (%d weitere nicht ausgewertet), Spicefläche viel zu groß",
          SPICE_LIMIT, d.spice_extra))
  end
  verdict(run, tb, d, "spice_fels", d.spice_on_rock.count == 0,
    string.format("%d Spice-Kacheln auf Fels, z. B. bei (%s, %s)", d.spice_on_rock.count,
      tostring(d.spice_on_rock.x), tostring(d.spice_on_rock.y)))
  verdict(run, tb, d, "erz_sand", d.ore_on_sand.count == 0,
    string.format("%d Erz- bzw. Tiefenwasserfelder auf Sand (%s; bei Tiefenwasser zählt jede der 3 × 3 Kacheln), " ..
      "z. B. bei (%s, %s)", d.ore_on_sand.count, by_text(d.ore_on_sand.by), tostring(d.ore_on_sand.x),
      tostring(d.ore_on_sand.y)))

  -- Messwerte in die Datei.
  local cells = N * N
  local resources = {}
  for _, name in ipairs(sorted_keys(d.resources)) do
    local resource = d.resources[name]
    resources[#resources + 1] = string.format("%s %d (%s)", name_of(name), resource.count, amount_text(resource.amount))
  end
  tb.trace(run, string.format("Seed %d (%s): Fels %s, fremde Kacheln %d, Ressourcen außer Spice: %s",
    entry.seed, entry.label, pct(d.rock_tiles, cells), d.foreign, #resources > 0 and table.concat(resources, ", ") or "keine"))
  tb.trace(run, string.format("Seed %d (%s): Startinsel %d Kacheln, Rand %s … %s Kacheln vom Start%s; darauf %s",
    entry.seed, entry.label, island.tiles, fmt(island.r_min), fmt(island.r_max),
    island.at_limit and string.format(" (reicht bis %d, Suche dort beendet)", ISLAND_BOX) or "",
    next(island.by) and by_text(island.by) or "nichts"))
  tb.trace(run, string.format("Seed %d (%s): Graben: nächster Fels außer der Startinsel %s Kacheln vom Start%s",
    entry.seed, entry.label, fmt(graben.closest), graben.x and string.format(" bei (%d, %d)", graben.x, graben.y) or ""))
  local lehr_center = "–"
  if lehr.tiles > 0 then
    local cx, cy = lehr.sx / lehr.tiles, lehr.sy / lehr.tiles
    lehr_center = string.format("(%s, %s), %s Kacheln vom Start", fmt(cx), fmt(cy), fmt(math.sqrt(cx * cx + cy * cy)))
  end
  tb.trace(run, string.format("Seed %d (%s): Lehrfeld %d Kacheln, %s Spice-Sand, Mitte %s, Abstand zum Fels %s … %s, " ..
    "größter dichter Block %d × %d (Ernter %d × %d)", entry.seed, entry.label, lehr.tiles, amount_text(lehr.amount),
    lehr_center, fmt(lehr.tiles > 0 and lehr.rock_min or nil), fmt(lehr.tiles > 0 and lehr.rock_max or nil),
    square, square, HARVEST_SIZE, HARVEST_SIZE))
  local field_parts = {}
  for index, field in ipairs(fields) do
    if index > 12 then
      field_parts[#field_parts + 1] = "…"
      break
    end
    field_parts[#field_parts + 1] = string.format("%d Kacheln/%s bei %s vom Start, Fels %s%s", field.tiles,
      amount_text(field.amount), fmt(field.start_min, 0), fmt(field.closest, 0), field.border and ", am Rand" or "")
  end
  tb.trace(run, string.format("Seed %d (%s): %d reguläre Felder (%d nutzbar ab %d Kacheln, %d am Gebietsrand angeschnitten), " ..
    "%d Kacheln, %s Spice-Sand, kleinster Abstand zum Fels %s, nicht gewertet (Gebietsrand) %d Kacheln; nächstes Feld %s " ..
    "Kacheln vom Start; Felder: %s", entry.seed, entry.label, #fields, #usable, USABLE, border_fields, regular.tiles,
    amount_text(regular.amount), fmt(regular.closest), regular.unrated, fmt(regular.start_min, 0),
    #field_parts > 0 and table.concat(field_parts, "; ") or "keine"))

  local median = sizes[1] and sizes[math.ceil(#sizes / 2)] or 0
  table.insert(d.summary, {
    seed = entry.seed, fields = #fields, size_min = sizes[1] or 0, size_median = median, size_max = sizes[#sizes] or 0,
    usable = #usable, usable_sizes = usable,
    nearest = regular.start_min == INF and NONE or regular.start_min, closest = regular.closest == INF and NONE or regular.closest,
    lehr_tiles = lehr.tiles, lehr_amount = lehr.amount, square = square,
    island_tiles = island.tiles, island_min = island.r_min, island_max = island.r_max, rock = d.rock_tiles / cells,
    graben = graben.closest, regular_box = regular.box
  })
  tb.log(run, "INFO", string.format("Seed %d von %d fertig (%d, %s): %d reguläre Felder (%d nutzbar), nächstes %s Kacheln " ..
    "vom Start, Lehrfeld %d Kacheln mit %s Spice-Sand", d.si, #d.seeds, entry.seed, entry.label, #fields, #usable,
    fmt(regular.start_min, 0), lehr.tiles, amount_text(lehr.amount)))

  -- Aufräumen, nächster Seed bzw. nach dem letzten die Zusatzdurchgänge auf dem ersten Seed.
  d.grid, d.spice_k, d.spice_amount, d.resources, d.current, d.wells = nil, nil, nil, nil, nil, nil
  d.si = d.si + 1
  if d.si <= #d.seeds then
    delete_surface(d)
    d.phase = "anlegen"
  else
    next_pass(d)
  end
end

-- Durchgang „groesse0“: Lehrfeld (Spice bis LEHR_MAX vom Start) bei Spice-Größe 0 lesen und prüfen.
phases.groesse0 = function(run, tb, d)
  local surface = surface_of(d)
  if not surface then
    trouble(run, tb, d, "Testoberfläche verschwunden", "Testoberfläche fehlt")
    return
  end
  local entry = d.seeds[d.si]
  local low, high = -d.radius * 32, (d.radius + 1) * 32
  local tiles, amount, outside = 0, 0, 0
  for _, entity in ipairs(surface.find_entities_filtered{area = {left_top = {x = low, y = low}, right_bottom = {x = high, y = high}},
                                                         name = SPICE}) do
    if entity.valid then
      local p = entity.position
      local x, y = math.floor(p.x), math.floor(p.y)
      if x >= low and x < high and y >= low and y < high then
        if from_start(x, y) <= LEHR_MAX then
          tiles = tiles + 1
          amount = amount + entity.amount
        else
          outside = outside + 1
        end
      end
    end
  end
  local normal = d.summary[1]
  tb.trace(run, string.format("Seed %d (%s), Spice-Größe 0: Lehrfeld %d Kacheln, %s Spice-Sand (Größe 1: %s Kacheln, %s); " ..
    "reguläres Spice (weiter als %d Kacheln vom Start) bis %d Kacheln je Achse: %d Kacheln (Größe 1: %s)", entry.seed,
    entry.label, tiles, amount_text(amount), normal and tostring(normal.lehr_tiles) or "–",
    normal and amount_text(normal.lehr_amount) or "–", LEHR_MAX, high, outside,
    normal and tostring(normal.regular_box) or "–"))
  if d.missing > 0 then
    tb.log(run, "INFO", string.format("Spice-Größe 0: %d Chunks nicht erzeugt, Lehrfeld nicht prüfbar", d.missing))
    next_pass(d)
    return
  end
  -- (size > 0) in arrakis_v3_spice_richness schaltet die regulären Felder bei Größe 0 ab.
  verdict(run, tb, d, "groesse0_regulaer", outside == 0, string.format("bei Spice-Größe 0 noch %d reguläre Spice-Kacheln " ..
    "(weiter als %d Kacheln vom Start, Größe 1: %s); schaltet (size > 0) die Felder nicht ab?", outside, LEHR_MAX,
    normal and tostring(normal.regular_box) or "–"))
  if tiles == 0 then
    verdict(run, tb, d, "lehrfeld_groesse0", false, string.format("bei Spice-Größe 0 kein Lehrfeld (kein Spice bis %d Kacheln " ..
      "vom Start); setzt die Engine das Autoplace von %s bei Größe 0 ganz aus?", LEHR_MAX, SPICE))
  else
    verdict(run, tb, d, "lehrfeld_groesse0", math.abs(amount - LEHR_AMOUNT) <= LEHR_TOLERANCE * LEHR_AMOUNT,
      string.format("Lehrfeld bei Spice-Größe 0 hat %s Spice-Sand in %d Kacheln, Soll %s ± %d %%", amount_text(amount), tiles,
        amount_text(LEHR_AMOUNT), LEHR_TOLERANCE * 100))
  end
  next_pass(d)
end

-- Nutzbare Felder aller Seeds (aus d.summary): Zahl je Seed, alle Größen sortiert, Seeds ohne, Median (nil ohne Feld).
local function usable_fields(d)
  local counts, sizes, empty = {}, {}, 0
  for index, s in ipairs(d.summary) do
    counts[index] = s.usable
    if s.usable == 0 then empty = empty + 1 end
    for _, size in ipairs(s.usable_sizes) do sizes[#sizes + 1] = size end
  end
  table.sort(sizes)
  -- Median wie je Seed in „felder“: bei gerader Zahl der kleinere der beiden mittleren Werte.
  local median = sizes[1] and sizes[math.ceil(#sizes / 2)] or nil
  return {counts = counts, sizes = sizes, empty = empty, median = median}
end

-- Prüfungen über alle Seeds (CHECKS mit total): „Felder“ und „Feldgröße“. Wie verdict, aber einmal für alle
-- Seeds: zählt in d.checked und d.failed und schreibt den FEHLER sofort. ok nil heißt nicht prüfbar.
-- Rückgabe: je Prüfung der Text für die OK-Zeile.
local function total_checks(run, tb, d, usable)
  local seeds = #usable.counts
  local notes = {}
  local function total(key, ok, text)
    if ok == nil then return end
    d.checked[key] = seeds
    if not ok then
      table.insert(d.failed[key], "alle")
      tb.log(run, "FEHLER", text)
    end
  end
  if seeds > 0 then
    local _, mean = spread(usable.counts)
    local allowed = math.ceil(seeds / EMPTY_SHARE)
    local problems = {}
    if mean < USABLE_MEAN then
      problems[#problems + 1] = string.format("im Mittel %s nutzbare Felder je Seed, Soll mindestens %d", fmt(mean, 1), USABLE_MEAN)
    end
    if usable.empty > allowed then
      problems[#problems + 1] = string.format("%d von %d Seeds ohne nutzbares Feld, erlaubt höchstens %d", usable.empty, seeds,
        allowed)
    end
    notes.felder = string.format("%d Seeds, im Mittel %s nutzbare Felder je Seed, %d Seeds ohne (erlaubt höchstens %d)",
      seeds, fmt(mean, 1), usable.empty, allowed)
    total("felder", #problems == 0, string.format("Felder: %s (nutzbar: reguläres Feld ab %d Kacheln, %d Seeds)",
      table.concat(problems, "; "), USABLE, seeds))
  end
  -- Ohne nutzbares Feld nicht prüfbar: Das meldet schon „Felder“ (Mittel 0), ein zweiter FEHLER sagte nichts Neues.
  if usable.median then
    notes.feldgroesse = string.format("Median %d Kacheln über %d nutzbare Felder", usable.median, #usable.sizes)
    total("feldgroesse", usable.median >= USABLE_MEDIAN, string.format("Feldgröße: nutzbare Felder im Median %d Kacheln, " ..
      "Soll mindestens %d (%d nutzbare Felder auf %d Seeds)", usable.median, USABLE_MEDIAN, #usable.sizes, seeds))
  end
  return notes
end

phases.bericht = function(run, tb, d)
  local n = #d.seeds
  local failures = 0
  -- Ein Lauf aus 0.5.4 (gespeichert, mit 0.5.5 weitergeladen) hat weder d.usable_check noch usable je Seed
  -- noch d.failed.felder/feldgroesse: „Felder“ und „Feldgröße“ sind dann nicht prüfbar.
  local usable = d.usable_check and usable_fields(d) or nil
  local notes = usable and total_checks(run, tb, d, usable) or {}
  for _, check in ipairs(CHECKS) do
    local failed = d.failed[check.key] or {}
    local checked = d.checked[check.key] or 0
    failures = failures + #failed
    if checked == 0 and check.required then
      -- Sonst bestünde ein kaputter Ausdruck (etwa nie reguläres Spice) die Prüfung ohne Befund.
      failures = failures + 1
      tb.log(run, "FEHLER", string.format("%s: nicht prüfbar, %s (von %d Seeds)", check.title, check.required, n))
    elseif checked == 0 and check.total then
      tb.log(run, "INFO", string.format("%s: nicht prüfbar, %s", check.title, usable and check.absent or "Lauf vor 0.5.5 begonnen"))
    elseif checked == 0 then
      tb.log(run, "INFO", check.title .. ": auf keinem Seed prüfbar")
    elseif #failed == 0 and check.once then
      tb.log(run, "OK", string.format("%s: Seed %d", check.title, d.seeds[1].seed))
    elseif #failed == 0 and check.total then
      tb.log(run, "OK", string.format("%s: %s", check.title, notes[check.key]))
    elseif check.total then
      tb.log(run, "INFO", string.format("%s: verletzt über alle %d Seeds, FEHLER oben", check.title, checked))
    elseif #failed == 0 then
      tb.log(run, "OK", string.format("%s: alle %d Seeds%s", check.title, checked,
        checked < n and string.format(" (von %d prüfbar)", n) or ""))
    else
      tb.log(run, "INFO", string.format("%s: verletzt auf %d von %d Seeds (%s), FEHLER oben", check.title, #failed, checked,
        table.concat(failed, ", ")))
    end
  end
  local fields, sizes, largest, nearest, lehr, squares, island, rims, graben = {}, {}, {}, {}, {}, {}, {}, {}, {}
  for index, s in ipairs(d.summary) do
    fields[index] = s.fields
    sizes[index] = s.size_median
    largest[index] = s.size_max
    if s.nearest < NONE then nearest[#nearest + 1] = s.nearest end
    lehr[index] = s.lehr_amount
    squares[index] = s.square
    island[index] = s.island_tiles
    if s.island_min < NONE then rims[#rims + 1] = s.island_min end
    if s.island_max > 0 then rims[#rims + 1] = s.island_max end
    if s.graben < NONE then graben[#graben + 1] = s.graben end
  end
  tb.log(run, "MESSUNG", string.format("Reguläre Felder je Seed %s; Feldgröße (Median je Seed) %s, größtes Feld %s Kacheln; " ..
    "nächstes Feld vom Start %s Kacheln (%d Seeds ohne Feld)", spread_text(fields, 1), spread_text(sizes), spread_text(largest),
    spread_text(nearest), n - #nearest))
  if usable then
    tb.log(run, "MESSUNG", string.format("Nutzbare Felder (ab %d Kacheln) je Seed %s (%d Seeds ohne); Größe der nutzbaren " ..
      "Felder im Median %s Kacheln (%d Felder, alle Seeds)", USABLE, spread_text(usable.counts, 1), usable.empty,
      usable.median and tostring(usable.median) or "–", #usable.sizes))
  end
  local rim_low, _, rim_high = spread(rims)
  tb.log(run, "MESSUNG", string.format("Lehrfeld Spice-Sand %s, größter dichter Block %s (Ernter %d × %d); Startinsel %s Kacheln, " ..
    "Rand %s … %s Kacheln vom Start", spread_text(lehr, 0, true), spread_text(squares), HARVEST_SIZE, HARVEST_SIZE, spread_text(island),
    fmt(#rims > 0 and rim_low or nil), fmt(#rims > 0 and rim_high or nil)))
  tb.log(run, "MESSUNG", string.format("Graben: nächster Fels außer der Startinsel %s Kacheln vom Start (Soll ab %d; " ..
    "%d Seeds ohne solchen Fels im Gebiet)", spread_text(graben, 1), GRABEN, n - #graben))
  local total = timing.total_key == run.started and not timing.incomplete and timing.total or nil
  write_timing(run, tb, string.format("Chunk-Erzeugung aller %d Seeds zusammen (%d Chunks): ", n,
    n * (2 * CHUNK_RADIUS + 1) ^ 2), total)
  tb.log(run, "INFO", "Dauer der Chunk-Erzeugung je Seed (auch Spice-Größe 0 und Karte 0.4.0 zum Vergleich) steht in arrakis-test.txt.")
  d.phase = "fertig"
  tb.finish(run, failures == 0 and string.format("%d Seeds, alle Prüfungen bestanden", n)
    or string.format("%d Seeds, %d Verstöße; Einzelwerte in arrakis-test.txt", n, failures))
end

-- Vertrag ----------------------------------------------------------------------------------------

local function start(run, tb)
  local d = run.data
  local ok, settings = pcall(settings_for, 0, "karte")
  if not ok or type(settings) ~= "table" then
    abort(run, tb, "Kartengenerator-Einstellungen von Arrakis nicht lesbar: " .. tostring(settings), "keine Einstellungen")
    return
  end
  -- Erze von Arrakis = Ressourcen der Planeten-Einstellungen außer Spice und Tiefenwasser; Kacheln ebenso.
  local autoplace = settings.autoplace_settings or {}
  local entity_settings = (autoplace["entity"] or {}).settings
  local tile_settings = (autoplace["tile"] or {}).settings
  d.ores = {}
  for _, name in ipairs(sorted_keys(entity_settings)) do
    if name ~= SPICE and name ~= DEEP_WATER then d.ores[#d.ores + 1] = name end
  end
  if #d.ores == 0 then d.ores = DEFAULT_ORES end
  d.tile_names = sorted_keys(tile_settings)
  if #d.tile_names == 0 then d.tile_names = DEFAULT_TILES end
  local names, v2 = {}, false
  for _, key in ipairs(sorted_keys(settings.property_expression_names)) do
    local value = settings.property_expression_names[key]
    names[#names + 1] = key .. " = " .. tostring(value)
    if type(value) == "string" and string.sub(value, 1, #V2_PREFIX) == V2_PREFIX then v2 = true end
  end
  tb.trace(run, "Planet Arrakis, property_expression_names: " .. (#names > 0 and table.concat(names, ", ") or "keine"))
  if not v2 then
    tb.log(run, "INFO", "Die Planeten-Einstellungen nutzen keinen " .. V2_PREFIX .. "…-Ausdruck: T14 prüft also nicht die Karte 2 " ..
      "(ab 0.5.4).")
  end

  d.long = string.lower(run.args[1] or "") == "lang"
  d.seeds = seed_list(d.long)
  d.failed, d.checked, d.summary = {}, {}, {}
  for _, check in ipairs(CHECKS) do d.failed[check.key] = {} end
  d.usable_check = true                  -- ab 0.5.5: je Seed usable in d.summary, „Felder“ und „Feldgröße“ (bericht)
  local leftovers = delete_leftovers()
  if leftovers > 0 then tb.log(run, "INFO", leftovers .. " alte T14-Testoberflächen gelöscht") end
  local ok_timer, profiler = pcall(function() return helpers.create_profiler(true) end)
  timing.total_key, timing.total, timing.incomplete = run.started, ok_timer and profiler or nil, false
  d.si, d.pass = 1, "karte"
  local own = d.seeds[1].label ~= "fest" and string.format("eigener Seed %d (%s) und ", d.seeds[1].seed, d.seeds[1].label) or ""
  tb.log(run, "INFO", string.format("T14 erzeugt die Karte von Arrakis auf %d Seeds (%s%d feste) je %d × %d Kacheln " ..
    "(Chunks im Radius %d) auf eigenen Testoberflächen und prüft sie auf Kacheln: Spice-Abstand zum Fels, Lehrfeld, " ..
    "Startinsel, Graben, Zahl und Größe der regulären Felder; danach auf dem ersten Seed das Spice bei Spice-Größe 0. " ..
    "Das Spiel läuft dabei langsam, je Seed etwa 70 Ticks. Du bleibst, wo du bist.", #d.seeds, own,
    #d.seeds - (own ~= "" and 1 or 0), N, N, CHUNK_RADIUS))
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
  d.grid, d.spice_k, d.spice_amount, d.resources, d.current, d.wells = nil, nil, nil, nil, nil, nil
  if timing.total_key == run.started then
    timing.total_key, timing.total = nil, nil
  end
  timing.key, timing.seed = nil, nil
end

return
{
  T14 =
  {
    title = "Kartengenerator: Karte echt (Kacheln)",
    timeout = 300 * 60,
    interactive = false,
    confirm = nil,
    hint = "legt kurz Testoberflächen arrakis-t14-… an; mit „lang“ 30 Seeds",
    start = start,
    tick = tick,
    cleanup = cleanup
  }
}
