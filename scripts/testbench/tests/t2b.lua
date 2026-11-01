-- T2b Ernter: Fahrphysik: Prüfstand-Test (aus t_ernter.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_ernter.lua.

local common = require("scripts.testbench.gemeinsam_ernter")
local harvester = require("scripts.harvester")
local NAME = common.NAME
local SPICE = common.SPICE
local valid = common.valid
local force_of = common.force_of
local copy_pos = common.copy_pos
local at = common.at
local pos_text = common.pos_text
local read = common.read
local flags_text = common.flags_text
local trunk_count = common.trunk_count
local gas = common.gas
local verdict = common.verdict
local check = common.check

local CAP = 1.5               -- Tempo-Deckel (Kacheln/s)
local RESET = 1.45            -- Rücksetzwert des Deckels (Kacheln/s)

local function quality_exists(name)
  local ok, exists = pcall(function() return prototypes.quality[name] ~= nil end)
  return ok and exists
end

-- T2b Ernter: Fahrphysik --------------------------------------------------------------------------
-- Ein eingetragener spice-harvester mit Dummy-Fahrer fährt nacheinander die Läufe aus T2B_RUNS. Der Fahrer
-- sitzt schon beim Eintragen (script_raised_built), deshalb steht der Ernter wie nach dem Einsteigen sofort
-- in storage.driven (Tempo-Deckel jeden Tick, Ausgleich alle 10 Ticks). Der Vergleichsernter entsteht ohne
-- Ereignis und wird nie eingetragen: kein Deckel; den Ausgleich setzt der Test selbst (Läufe mit norm, sonst 1).
-- Messung je Tick im Prüfstand-Tick: speed (nach dem Deckel des Laufzeitcodes, der als Bibliothek vor dem
-- Prüfstand läuft), Schritt am Boden (Positionsänderung, 1/256-Raster), ab 5 s Mittelwert und Bodentempo.
-- Weil speed nach dem Deckel gelesen wird, zählt jeder Eingriff des Deckels (speed genau 1.45): Er heißt, das
-- Tempo war davor über 1.5. In der ersten Sekunde ist er erlaubt (neuer Brennstoff, Ausgleich folgt im
-- 10-Tick-Takt), danach ist er ein FEHLER.
-- Ab 2.1.13 wirkt auch fuel_top_speed_multiplier (t) bei Autos, und zwar linear: T2 und T2b unter 2.1.23 (0.5.2)
-- passen zu Endtempo ∝ √(a · Ausgleich) · t. Der Ausgleich ist deshalb ab 2.1.13 min(1, 1/(a · t²)), davor
-- min(1, 1/a) (Plan 4.6, scripts/harvester.lua); die eingetragenen Läufe erwarten die Formel der laufenden Version.
-- Die Läufe ohne Deckel (Vergleichsernter, nur MESSUNG) halten beides auseinander:
--   norm = "old": alter Ausgleich min(1, 1/a), wie bis 0.5.2. Sie messen t weiter als Zahl: Faktor = Tempo /
--     (Tempo mit Kohle · √(a · Ausgleich)), das 2.0-Modell ohne t. Faktor 1.000 heißt keine Wirkung, Faktor ≈ t
--     heißt linear; Exponent p = ln(Faktor) / ln(t), also p = 1 linear, p = 0 keine Wirkung.
--   norm = "new" (nur ab 2.1.13; davor gleich "old"): neuer Ausgleich. Tempo / Kohle soll 1.000 sein, dann bleibt der
--     Deckel frei. Weicht es ab, zeigt p (dieselbe Rechnung), um wie viel: passend wäre dann 1/(a · t^(2p)).

-- Ab dieser base-Version wirkt t bei Autos (Changelog 2.1.13: „Improved fuel top speed modifies with cars/tanks“).
local T2B_TOP_SPEED_FROM = "2.1.13"

local T2B_BACK = 30
local T2B_PAUSE = 30
-- Zu viel ausgeglichen? Eingetragene Läufe mit anderem Brennstoff und gleicher Dauer wie Kohle: Mittel ab 5 s
-- mindestens 97 % des Mittels mit Kohle, sonst FEHLER (bei der neuen Formel hieße das: t wirkt schwächer als linear).
local T2B_SLOWER = 0.97
local T2B_WINDOW = 5 * 60
local T2B_NEGATIVE = {x = -1000, y = -1000}
local T2B_DIRS =
{
  O = {orientation = 0.25, x = 1, y = 0},
  W = {orientation = 0.75, x = -1, y = 0},
  N = {orientation = 0, x = 0, y = -1},
  S = {orientation = 0.5, x = 0, y = 1},
  NO = {orientation = 0.125, x = math.sqrt(0.5), y = -math.sqrt(0.5)},
  SW = {orientation = 0.625, x = -math.sqrt(0.5), y = math.sqrt(0.5)}
}
local T2B_RUNS =
{
  {key = "coal", label = "Kohle", fuel = "coal", count = 10, dir = "O", ticks = 15 * 60},
  {key = "solid", label = "Festbrennstoff", fuel = "solid-fuel", count = 10, dir = "O", ticks = 15 * 60},
  {key = "rocket", label = "Raketentreibstoff", fuel = "rocket-fuel", count = 3, dir = "O", ticks = 15 * 60},
  {key = "nuclear", label = "Atomtreibstoff", fuel = "nuclear-fuel", count = 1, dir = "O", ticks = 15 * 60},
  {key = "legendary", label = "Raketentreibstoff legendär", fuel = "rocket-fuel", quality = "legendary", count = 3, dir = "O", ticks = 15 * 60},
  {key = "plain", label = "Raketentreibstoff ohne Ausgleich und Deckel", fuel = "rocket-fuel", count = 3, dir = "O", ticks = 15 * 60, raw = true},
  {key = "norm_solid", label = "Festbrennstoff mit altem Ausgleich 1/a, ohne Deckel", fuel = "solid-fuel", count = 10, raw = true, norm = "old", dir = "O", ticks = 15 * 60},
  {key = "norm_rocket", label = "Raketentreibstoff mit altem Ausgleich 1/a, ohne Deckel", fuel = "rocket-fuel", count = 3, raw = true, norm = "old", dir = "O", ticks = 15 * 60},
  {key = "norm_legendary", label = "Raketentreibstoff legendär mit altem Ausgleich 1/a, ohne Deckel", fuel = "rocket-fuel", quality = "legendary", count = 3, raw = true, norm = "old", dir = "O", ticks = 15 * 60},
  {key = "new_solid", label = "Festbrennstoff mit neuem Ausgleich 1/(a · t²), ohne Deckel", short = "Festbrennstoff", fuel = "solid-fuel", count = 10, raw = true, norm = "new", dir = "O", ticks = 15 * 60},
  {key = "new_rocket", label = "Raketentreibstoff mit neuem Ausgleich 1/(a · t²), ohne Deckel", short = "Raketentreibstoff", fuel = "rocket-fuel", count = 3, raw = true, norm = "new", dir = "O", ticks = 15 * 60},
  {key = "new_legendary", label = "Raketentreibstoff legendär mit neuem Ausgleich 1/(a · t²), ohne Deckel", short = "Raketentreibstoff legendär", fuel = "rocket-fuel", quality = "legendary", count = 3, raw = true, norm = "new", dir = "O", ticks = 15 * 60},
  {key = "west", label = "Raketentreibstoff nach W", fuel = "rocket-fuel", count = 3, dir = "W", ticks = 10 * 60},
  {key = "north", label = "Raketentreibstoff nach N", fuel = "rocket-fuel", count = 3, dir = "N", ticks = 10 * 60},
  {key = "south", label = "Raketentreibstoff nach S", fuel = "rocket-fuel", count = 3, dir = "S", ticks = 10 * 60},
  {key = "northeast", label = "Raketentreibstoff schräg nach NO", fuel = "rocket-fuel", count = 3, dir = "NO", ticks = 10 * 60},
  {key = "southwest", label = "Raketentreibstoff schräg nach SW", fuel = "rocket-fuel", count = 3, dir = "SW", ticks = 10 * 60},
  {key = "neg_east", label = "negative Koordinaten nach O", fuel = "rocket-fuel", count = 3, dir = "O", ticks = 10 * 60, negative = true},
  {key = "neg_west", label = "negative Koordinaten nach W", fuel = "rocket-fuel", count = 3, dir = "W", ticks = 10 * 60, negative = true},
  {key = "full", label = "voller Laderaum", fuel = "rocket-fuel", count = 3, dir = "O", ticks = 15 * 60, full = true}
}

-- Wirkt t in der laufenden Version (base ≥ 2.1.13)? Selbst gelesen, nicht aus scripts/harvester.lua.
local function top_speed_acts()
  return helpers.compare_versions(script.active_mods["base"], T2B_TOP_SPEED_FROM) >= 0
end

-- Formel des Ausgleichs als Text; old: der alte Ausgleich (bis 0.5.2, vor 2.1.13 auch der aktuelle).
local function formula_text(old)
  if old or not top_speed_acts() then return "min(1, 1/a)" end
  return "min(1, 1/(a · t²))"
end

-- Ausgleich laut Plan 4.6: min(1, 1/(a · t²)) ab 2.1.13, davor min(1, 1/a); old: immer min(1, 1/a).
-- a = Beschleunigung, t = Höchsttempo des Brennstoffs, je plus Qualitätsbonus. Gibt Ausgleich, a, t zurück.
local function expected_modifier(fuel, quality, old)
  local item = prototypes.item[fuel]
  local level = quality and prototypes.quality[quality] and prototypes.quality[quality].level or 0
  local a = item.fuel_acceleration_multiplier + level * item.fuel_acceleration_multiplier_quality_bonus
  local t = item.fuel_top_speed_multiplier + level * item.fuel_top_speed_multiplier_quality_bonus
  local k = a
  if not old and top_speed_acts() then k = a * t * t end
  if k <= 0 then return 1, a, t end
  return math.min(1, 1 / k), a, t
end

-- Läuft spec in dieser Version? Die Läufe mit neuem Ausgleich entfallen vor 2.1.13 (dort gleich dem alten).
local function t2b_planned(spec)
  return not (spec.norm == "new" and not top_speed_acts())
end

-- Gilt das 97-%-Kriterium (T2B_SLOWER) für spec? Eingetragene Läufe mit anderem Brennstoff und gleicher Dauer wie
-- Kohle (coal_ticks). Start-INFO und Auswertung nehmen beide diese Regel.
local function t2b_slower_checked(spec, coal_ticks)
  return not spec.raw and spec.fuel ~= "coal" and coal_ticks ~= nil and spec.ticks == coal_ticks
end

local function t2b_park(d, which)
  return which == "raw" and at(d.track_center, -40, 50) or at(d.track_center, 40, 50)
end

local function t2b_cars(d, spec)
  if spec.raw then return d.raw, d.raw_driver, d.car end
  return d.car, d.driver, d.raw
end

local function t2b_summary(run)
  local d = run.data
  local ok, wrong, peak, ground = 0, 0, 0, 0
  for _, spec in ipairs(T2B_RUNS) do
    local r = d.results[spec.key]
    if r and not spec.raw and r.ok ~= nil then
      if r.ok then ok = ok + 1 else wrong = wrong + 1 end
      if r.max > peak then peak = r.max end
      if r.ground and r.ground > ground then ground = r.ground end
    end
  end
  -- Exponent p aller Läufe ohne Deckel (Bereich) und die Läufe mit neuem Ausgleich (Spitze ab 1 s, Tempo/Kohle).
  local p_low, p_high, new_peak, new_ratio
  for _, spec in ipairs(T2B_RUNS) do
    local r = d.results[spec.key]
    if r and spec.raw then
      if r.p then
        p_low = math.min(p_low or r.p, r.p)
        p_high = math.max(p_high or r.p, r.p)
      end
      if spec.norm == "new" then
        new_peak = math.max(new_peak or 0, r.max_late or 0)
        if r.ratio then new_ratio = math.max(new_ratio or 0, r.ratio) end
      end
    end
  end
  local raw_result = d.results.plain
  local p_text = p_low and (string.format("%.2f", p_low) .. (p_high - p_low >= 0.005 and string.format("–%.2f", p_high) or "")) or "–"
  local new_text = new_peak and string.format("ab 1 s bis speed %.2f, Tempo/Kohle bis %s", new_peak,
    new_ratio and string.format("%.3f", new_ratio) or "–")
    or (top_speed_acts() and "–" or "entfällt (vor 2.1.13)")
  return string.format("%d Läufe OK, %d FEHLER; mit Ausgleich höchstens speed %.2f, Bodentempo %.2f Kacheln/s; ohne Ausgleich und Deckel %s; "
    .. "Höchsttempo t wirkt mit p %s (1 linear, 0 nicht); neuer Ausgleich ohne Deckel %s",
    ok, wrong, peak, ground, raw_result and raw_result.max and string.format("speed %.2f, Bodentempo %.2f", raw_result.max, raw_result.ground or 0) or "–",
    p_text, new_text)
end

local function t2b_finish(run, tb)
  local d = run.data
  d.phase = "done"
  local cars = {d.car, d.raw}
  for i = 1, 2 do
    local car = cars[i]
    if valid(car) then
      gas(car, nil, false)
      pcall(function() car.speed = 0 end)
    end
  end
  local hits, late = 0, 0
  for _, r in pairs(d.results) do
    hits = hits + (r.cap_hits or 0)
    late = late + (r.cap_late or 0)
  end
  tb.log(run, "INFO", "Deckel-Rücksetzwert 1.45 im Prüfstand-Tick gesehen: " .. hits .. "×, davon ab 1 s " .. late .. "×"
    .. (hits > 0 and " (speed wird also nach dem Deckel gelesen; ab 1 s ist jeder Eingriff im Lauf mit Ausgleich ein FEHLER)"
      or " (der Deckel griff nicht ein oder speed wird vor ihm gelesen; dann ist die Spitze das Tempo vor dem Deckel)"))
  -- Ohne Ausgleich und mit altem Ausgleich 1/a: Wirkt t, und wie (Faktor, Exponent p)?
  local factors = {}
  -- Mit neuem Ausgleich 1/(a · t²): Bleibt das Tempo ohne Deckel unter 1.5?
  local news, holds, p_sum, p_n, worst = {}, true, 0, 0, nil
  for _, spec in ipairs(T2B_RUNS) do
    local r = d.results[spec.key]
    if spec.raw and r and spec.norm ~= "new" and r.factor then
      table.insert(factors, string.format("%s: t = %s, Faktor %s, p = %s", spec.label, tb.num(r.t, 3), tb.num(r.factor, 3), tb.num(r.p, 2)))
    elseif spec.raw and r and spec.norm == "new" then
      table.insert(news, string.format("%s: Tempo/Kohle %s, Spitze ab 1 s %s, p = %s", spec.short or spec.label, tb.num(r.ratio, 3),
        tb.num(r.max_late, 3), tb.num(r.p, 2)))
      if not (r.max_late and r.max_late <= CAP + 1e-6) then holds = false end
      if r.ratio and (not worst or math.abs(r.ratio - 1) > math.abs(worst - 1)) then worst = r.ratio end
      if r.p then
        p_sum = p_sum + r.p
        p_n = p_n + 1
      end
    end
  end
  if #factors > 0 then
    tb.log(run, "INFO", "Höchsttempo t der Brennstoffe (2.1.13), Faktor gegenüber dem 2.0-Modell √(a · Ausgleich) mit Ausgleich 1"
      .. " oder altem Ausgleich 1/a: " .. table.concat(factors, "; ")
      .. ". Faktor 1.000 (p = 0) heißt keine Wirkung, Faktor ≈ t (p = 1) heißt linear, wie der neue Ausgleich annimmt.")
  end
  local coal = d.results.coal and d.results.coal.mean
  if d.results.coal and (d.results.coal.cap_late or 0) > 0 then
    tb.log(run, "INFO", "Bezug Kohle: Der Deckel griff auch dort ein, Tempo/Kohle, Faktor und p der Läufe ohne Deckel sind deshalb zu hoch.")
  end
  if #news > 0 then
    local verdict = holds and "hält ohne Deckel (Spitze ab 1 s ≤ 1.5)" or "hält NICHT ohne Deckel"
    -- Ab 1 % Abweichung (auch nach unten) die Formel nennen, die zu den Messungen passt.
    if p_n > 0 and (not holds or (worst and math.abs(worst - 1) > 0.01)) then
      verdict = verdict .. string.format("; passend wäre min(1, 1/(a · t^(2p))) mit p = %.2f", p_sum / p_n)
    end
    tb.log(run, "INFO", "Neuer Ausgleich min(1, 1/(a · t²)) ohne Deckel: " .. table.concat(news, "; ")
      .. ". Soll Tempo/Kohle 1.000; der Deckel bleibt frei bis " .. tb.num(coal and coal > 0 and CAP / coal or nil, 3)
      .. " (1.5 / Tempo mit Kohle). Größte Abweichung "
      .. (worst and (math.abs(worst - 1) < 0.0005 and "0.0 %" or string.format("%+.1f %%", (worst - 1) * 100)) or "–")
      .. ", Ergebnis: " .. verdict .. ".")
  elseif not top_speed_acts() then
    tb.log(run, "INFO", "Neuer Ausgleich: base " .. tostring(script.active_mods["base"]) .. " ist älter als "
      .. T2B_TOP_SPEED_FROM .. ", dort ist er gleich dem alten min(1, 1/a); die Läufe mit neuem Ausgleich entfielen.")
  end
  tb.finish(run, t2b_summary(run))
end

local function t2b_next(run, tb)
  local d = run.data
  d.run_index = d.run_index + 1
  if d.run_index > #T2B_RUNS then
    t2b_finish(run, tb)
    return
  end
  d.phase = "wait"
  d.next_tick = game.tick + T2B_PAUSE
end

-- Ernter für einen Lauf herrichten: anhalten, an den Start, Brennstoff und Brenner neu, Laderaum leer oder voll.
-- Der Vergleichsernter bekommt den Ausgleich vom Test: norm = "old" der alte 1/a, "new" wie im Mod, sonst 1.
local function t2b_reset(car, start, orientation, spec)
  if spec.raw then
    local modifier = 1
    if spec.norm then modifier = expected_modifier(spec.fuel, spec.quality, spec.norm == "old") end
    pcall(function() car.effectivity_modifier = modifier end)
  end
  pcall(function() car.speed = 0 end)
  local moved = car.teleport(start)
  pcall(function() car.orientation = orientation end)
  pcall(function() car.speed = 0 end)
  local inventory = car.get_fuel_inventory()
  if inventory then inventory.clear() end
  local burner = car.burner
  if burner then
    -- Rest zuerst auf 0: falls currently_burning = nil nicht geht, lädt der Brenner trotzdem den neuen Brennstoff.
    pcall(function() burner.remaining_burning_fuel = 0 end)
    pcall(function() burner.currently_burning = nil end)
    pcall(function() burner.heat = 0 end)
  end
  local trunk = car.get_inventory(defines.inventory.car_trunk)
  trunk.clear()
  if spec.full then trunk.insert{name = SPICE, count = #trunk * prototypes.item[SPICE].stack_size} end
  local inserted = 0
  if inventory then
    inserted = inventory.insert{name = spec.fuel, count = spec.count, quality = spec.quality or "normal"}
  end
  return moved, inserted
end

local function t2b_begin(run, tb)
  local d = run.data
  local spec = T2B_RUNS[d.run_index]
  -- Vor 2.1.13 entfallen die Läufe mit neuem Ausgleich ohne eigene Zeile (die Start-INFO nennt es).
  if not t2b_planned(spec) then return t2b_next(run, tb) end
  if spec.quality and not quality_exists(spec.quality) then
    tb.log(run, "INFO", spec.label .. ": Qualität " .. spec.quality .. " gibt es nicht, Lauf entfällt")
    return t2b_next(run, tb)
  end
  local car, _, other = t2b_cars(d, spec)
  if not (valid(car) and valid(other)) then
    tb.log(run, "FEHLER", "Ernter für den Lauf fehlt")
    return t2b_finish(run, tb)
  end
  local center = spec.negative and T2B_NEGATIVE or d.track_center
  if (spec.negative and not d.watching_negative) or (not spec.negative and d.watching_negative) then
    d.watching_negative = spec.negative or nil
    tb.watch(run, nil, at(center, 12, 12))
  end
  other.teleport(t2b_park(d, spec.raw and "main" or "raw"))
  local dir = T2B_DIRS[spec.dir]
  local start = {x = center.x - dir.x * T2B_BACK, y = center.y - dir.y * T2B_BACK}
  local moved, inserted = t2b_reset(car, start, dir.orientation, spec)
  if not moved or inserted == 0 then
    tb.log(run, "FEHLER", string.format("%s: Start ging nicht (Teleport %s, %d %s eingelegt)", spec.label, tostring(moved), inserted, spec.fuel))
    return t2b_next(run, tb)
  end
  d.cur =
  {
    start = game.tick,
    start_pos = copy_pos(car.position),
    last = copy_pos(car.position),
    max = 0,
    max_late = 0,
    max_step = 0,
    cap_hits = 0,
    cap_late = 0,
    sum = 0,
    n = 0
  }
  d.phase = "run"
  tb.trace(run, string.format("T2b %s: Start %s, Richtung %s, %d %s%s, Laderaum %d Spice, effectivity_modifier vorher %.3f",
    spec.label, pos_text(tb, car.position), spec.dir, inserted, spec.fuel, spec.quality and (" " .. spec.quality) or "",
    trunk_count(car), car.effectivity_modifier))
  gas(car, spec.raw and d.raw_driver or d.driver, true)
end

local function t2b_end(run, tb)
  local d = run.data
  local spec = T2B_RUNS[d.run_index]
  local car, driver = t2b_cars(d, spec)
  local cur = d.cur
  gas(car, driver, false)
  local window = (spec.ticks - T2B_WINDOW) / 60
  local ground = cur.pos5 and tb.distance(car.position, cur.pos5) / window or nil
  local mean = cur.n > 0 and cur.sum / cur.n or nil
  local distance = tb.distance(car.position, cur.start_pos)
  local modifier = car.effectivity_modifier
  local old = spec.norm == "old"
  local expected, a, t = expected_modifier(spec.fuel, spec.quality, old)
  if spec.raw and not spec.norm then expected = 1 end
  local burning = read(function()
    local pair = car.burner.currently_burning
    return pair and (pair.name.name .. "@" .. pair.quality.name)
  end) or "–"
  pcall(function() car.speed = 0 end)
  local result = {max = cur.max, ground = ground, mean = mean, cap_hits = cur.cap_hits, cap_late = cur.cap_late,
    ticks = spec.ticks}
  local values = string.format("speed %s (Mittel ab 5 s), Spitze %.3f (ab 1 s %.3f), Bodentempo %s (Strecke ab 5 s), "
    .. "Schritt je Tick bis %d/256 (%.2f), Weg %.1f in %d s, Deckel %d× (ab 1 s %d×), brennt %s, effectivity_modifier %.3f",
    tb.num(mean, 3), cur.max, cur.max_late, tb.num(ground, 3), cur.max_step, cur.max_step * 60 / 256, distance,
    spec.ticks / 60, cur.cap_hits, cur.cap_late, burning, modifier)
  if spec.raw then
    local registered = harvester.get(car) ~= nil
    -- Faktor gegenüber dem 2.0-Modell ohne t: Tempo / (Tempo mit Kohle · √(a · Ausgleich)); Faktor = t^p.
    -- Mit neuem Ausgleich ist √(a · Ausgleich) = 1/t, dort heißt Tempo/Kohle 1.000 genau p = 1.
    local coal = d.results.coal and d.results.coal.mean
    result.t = t
    result.ratio = mean and coal and coal > 0 and mean / coal or nil
    result.max_late = cur.max_late
    local model = a and a > 0 and math.sqrt(a * modifier) or nil
    result.factor = result.ratio and model and model > 0 and result.ratio / model or nil
    result.p = result.factor and result.factor > 0 and math.abs(t - 1) > 1e-3 and math.log(result.factor) / math.log(t) or nil
    -- Faktor knapp unter 1 (2.0: t wirkt nicht) ergäbe sonst „p = -0.00“.
    if result.p and math.abs(result.p) < 0.005 then result.p = 0 end
    local formula = spec.norm and formula_text(old) or "keiner"
    local goal = spec.norm == "new" and string.format("; Soll Tempo/Kohle 1.000, Deckel frei bis %s", tb.num(coal and coal > 0 and CAP / coal or nil, 3)) or ""
    tb.log(run, "MESSUNG", spec.label .. " (nur gemessen, Ernter nicht eingetragen" .. (registered and ": DOCH EINGETRAGEN" or "")
      .. "): " .. values .. string.format(", Ausgleich gesetzt %.3f (%s), a = %s, t = %s; Tempo/Kohle %s, 2.0-Modell ohne t erwartet %s, "
      .. "Faktor %s, p = %s%s", expected, formula, tb.num(a, 2), tb.num(t, 3), tb.num(result.ratio, 3), tb.num(model, 3),
      tb.num(result.factor, 3), tb.num(result.p, 2), goal))
  else
    local failed = {}
    check(failed, cur.max_late <= CAP + 1e-6, "Spitze ab 1 s ≤ 1.5")
    check(failed, cur.cap_late == 0, "Deckel griff ab 1 s nie (Tempo vor dem Deckel ≤ 1.5)")
    check(failed, ground ~= nil and ground <= CAP, "Bodentempo ≤ 1.5")
    check(failed, math.abs(modifier - expected) <= 1e-3, "Ausgleich " .. string.format("%.3f", expected))
    local coal = d.results.coal
    if coal and coal.mean and coal.mean > 0 and t2b_slower_checked(spec, coal.ticks) then
      check(failed, mean ~= nil and mean >= T2B_SLOWER * coal.mean, string.format("Mittel ≥ %d %% von Kohle (%s), nicht zu viel ausgeglichen",
        math.floor(T2B_SLOWER * 100 + 0.5), tb.num(T2B_SLOWER * coal.mean, 3)))
    end
    result.ok = #failed == 0
    local text = spec.label .. " (" .. spec.dir .. (spec.negative and ", negative Koordinaten" or "") .. "): " .. values
      .. string.format(" (erwartet %.3f = %s, a = %s, t = %s)", expected, formula_text(false), tb.num(a, 2), tb.num(t, 3))
    if #failed > 0 then text = text .. " | nicht erfüllt: " .. table.concat(failed, "; ") end
    tb.log(run, result.ok and "OK" or "FEHLER", text)
    if mean and (mean < 1.40 or mean > CAP) then
      tb.log(run, "INFO", spec.label .. ": speed im Mittel " .. tb.num(mean, 3) .. " statt etwa 1.45")
    end
  end
  d.results[spec.key] = result
  t2b_next(run, tb)
end

local function t2b_start(run, tb)
  local d = run.data
  local origin = tb.area(run.id)
  tb.prepare(origin, 70)
  tb.prepare(T2B_NEGATIVE, 45)
  d.track_center = copy_pos(origin)
  d.results = {}
  local surface = tb.surface()
  local force = force_of(run, tb)
  -- Ernter mit Ausgleich: erst der Fahrer, dann script_raised_built (wie Einsteigen: sofort im Tempo-Deckel).
  local car = surface.create_entity{name = NAME, position = t2b_park(d, "main"), force = force, orientation = 0.25}
  local raw = surface.create_entity{name = NAME, position = t2b_park(d, "raw"), force = force, orientation = 0.25}
  if not (car and raw) then
    tb.log(run, "FEHLER", "spice-harvester ließ sich nicht erzeugen")
    tb.finish(run, "abgebrochen (kein Ernter)")
    return
  end
  d.car, d.raw = car, raw
  d.driver = tb.dummy_driver(car)
  d.raw_driver = tb.dummy_driver(raw)
  script.raise_script_built{entity = car}
  local h = harvester.get(car)
  local driven = storage.driven and storage.driven[car.unit_number] ~= nil
  local seated = car.get_driver() ~= nil and raw.get_driver() ~= nil
  tb.log(run, (h and seated) and "INFO" or "FEHLER", string.format("Ernter Nr. %d eingetragen %s, im Tempo-Deckel %s; Vergleichsernter Nr. %d eingetragen %s; Dummy-Fahrer sitzen %s",
    car.unit_number, tostring(h ~= nil), tostring(driven), raw.unit_number, tostring(harvester.get(raw) ~= nil), tostring(seated)))
  -- Welche Läufe das 97-%-Kriterium prüft, steht in der Start-INFO (OK-Zeilen nennen nur verfehlte Kriterien).
  local planned, ticks, slower, other_duration, coal_ticks = 0, 0, {}, 0, nil
  for _, spec in ipairs(T2B_RUNS) do
    if spec.key == "coal" then coal_ticks = spec.ticks end
  end
  for _, spec in ipairs(T2B_RUNS) do
    if t2b_planned(spec) and not (spec.quality and not quality_exists(spec.quality)) then
      planned = planned + 1
      ticks = ticks + spec.ticks + T2B_PAUSE
      if t2b_slower_checked(spec, coal_ticks) then
        table.insert(slower, spec.label)
      elseif not spec.raw and spec.fuel ~= "coal" then
        other_duration = other_duration + 1
      end
    end
  end
  local acts = top_speed_acts()
  tb.log(run, "INFO", string.format("%d Läufe je 10–15 s, Dauer etwa %.1f min. Kriterium mit Ausgleich: ab 1 s Spitze ≤ 1.5 Kacheln/s"
    .. " und kein Eingriff des Tempo-Deckels, Bodentempo ≤ 1.5 Kacheln/s, effectivity_modifier = %s (base %s, Höchsttempo t wirkt %s %s)."
    .. " Dazu Mittel ≥ %d %% von Kohle (nicht zu viel ausgeglichen) in allen eingetragenen Läufen mit anderem Brennstoff und gleicher"
    .. " Dauer wie Kohle (%d s): %s; nicht in den %d eingetragenen Läufen mit anderer Dauer und nicht in den Läufen „ohne Deckel“."
    .. " speed wird nach dem Deckel des Laufzeitcodes gelesen; ein Eingriff heißt, das Tempo war davor über 1.5."
    .. " Die Läufe „ohne Deckel“ fährt der Vergleichsernter; sie werden nur gemessen: ohne Ausgleich und mit altem Ausgleich 1/a"
    .. " zeigen sie, wie t wirkt, mit neuem Ausgleich das Tempo, das sonst der Deckel verdeckt.%s",
    planned, ticks / 3600, formula_text(false), tostring(script.active_mods["base"]), acts and "ab" or "erst ab", T2B_TOP_SPEED_FROM,
    math.floor(T2B_SLOWER * 100 + 0.5), math.floor((coal_ticks or 0) / 60), #slower > 0 and table.concat(slower, ", ") or "–",
    other_duration, acts and "" or (" Die Läufe mit neuem Ausgleich entfallen (vor " .. T2B_TOP_SPEED_FROM .. " gleich dem alten).")))
  tb.watch(run, nil, at(d.track_center, 12, 12))
  d.run_index = 1
  d.phase = "wait"
  d.next_tick = game.tick + T2B_PAUSE
end

local function t2b_tick(run, tb)
  local d = run.data
  if d.phase == "done" then return end
  if d.phase == "wait" then
    if game.tick >= d.next_tick then t2b_begin(run, tb) end
    return
  end
  local spec = T2B_RUNS[d.run_index]
  local car, driver = t2b_cars(d, spec)
  if not valid(car) then
    tb.log(run, "FEHLER", "Der Ernter ist nicht mehr da.")
    return t2b_finish(run, tb)
  end
  local cur = d.cur
  local elapsed = game.tick - cur.start
  local speed = tb.speed_tps(car) or 0
  local position = copy_pos(car.position)
  local step = tb.distance(position, cur.last)
  cur.last = position
  if speed > cur.max then cur.max = speed end
  if elapsed > 60 and speed > cur.max_late then cur.max_late = speed end
  local units = math.floor(step * 256 + 0.5)
  if units > cur.max_step then cur.max_step = units end
  -- Genau der Rücksetzwert (als float gespeichert: Abweichung etwa 4e-8 Kacheln/s); natürliche Fahrt trifft ihn kaum.
  if math.abs(speed - RESET) < 2e-7 then
    cur.cap_hits = cur.cap_hits + 1
    if elapsed > 60 then cur.cap_late = cur.cap_late + 1 end
  end
  if elapsed == T2B_WINDOW then cur.pos5 = position end
  if elapsed > T2B_WINDOW then
    cur.sum = cur.sum + speed
    cur.n = cur.n + 1
  end
  if elapsed % 60 == 0 then
    tb.trace(run, string.format("T2b %s %d s: speed %.3f, Weg %.2f, Schritt %d/256", spec.label, elapsed / 60, speed,
      tb.distance(position, cur.start_pos), units))
  end
  if not d.probed and elapsed >= 60 then
    d.probed = true
    local moved = tb.distance(position, cur.start_pos)
    if moved < 0.05 and speed < 0.01 then
      tb.log(run, "FEHLER", "Skriptfahrt geht nicht: nach 1 s " .. tb.num(moved, 2) .. " Kacheln, Tempo " .. tb.num(speed, 2)
        .. " Kacheln/s; " .. flags_text(car))
      return t2b_finish(run, tb)
    end
  end
  if elapsed >= spec.ticks then
    return t2b_end(run, tb)
  end
  gas(car, driver, true)
end

local function t2b_cleanup(run, tb)
  local d = run.data
  local drivers, cars = {d.driver, d.raw_driver}, {d.car, d.raw}
  for i = 1, 2 do
    local driver, car = drivers[i], cars[i]
    if valid(driver) then driver.destroy() end
    if valid(car) then car.destroy{raise_destroy = true} end
  end
end

return
{
  T2b =
  {
    title = "Ernter: Fahrphysik",
    timeout = 8 * 60 * 60,
    interactive = false,
    confirm = nil,
    start = t2b_start,
    tick = t2b_tick,
    cleanup = t2b_cleanup
  }
}
