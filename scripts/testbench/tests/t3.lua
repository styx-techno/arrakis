-- T3 Ernter: Teleport zur Ablage: Prüfstand-Test (aus t_harvester.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_harvester.lua.

local common = require("scripts.testbench.gemeinsam_harvester")
local HARVESTER = common.HARVESTER
local force_of = common.force_of
local copy_pos = common.copy_pos
local pos_text = common.pos_text
local count_text = common.count_text
local result_text = common.result_text
local item_pair_name = common.item_pair_name

local HOLD = "arrakis-test-hold"

-- Inhalt eines Inventars als sortierter Text "name@qualität anzahl, …".
local function contents_text(inventory)
  if not (inventory and inventory.valid) then return "–" end
  local ok, contents = pcall(function() return inventory.get_contents() end)
  if not ok then return "Fehler: " .. tostring(contents) end
  local totals = {}
  for _, item in pairs(contents) do
    local name, quality = item.name, item.quality or "normal"
    if type(name) ~= "string" then name = name.name end
    if type(quality) ~= "string" then quality = quality.name end
    local key = name .. "@" .. quality
    totals[key] = (totals[key] or 0) + item.count
  end
  local parts = {}
  for key, count in pairs(totals) do table.insert(parts, key .. " " .. count) end
  if #parts == 0 then return "leer" end
  table.sort(parts)
  return table.concat(parts, ", ")
end

local function quality_exists(name)
  local ok, exists = pcall(function() return prototypes.quality[name] ~= nil end)
  return ok and exists
end

-- T3 Teleport zur Ablage -----------------------------------------------------------------------
-- Ein voll ausgestatteter Ernter wird mit und ohne Fahrer auf die versteckte Ablage-Oberfläche
-- teleportiert und zurück; der Zustand wird je Feld mit dem Vorher-Datensatz verglichen.
-- Vorher-Datensatz (d.before) ist der Zustand, nachdem der Dummy-Fahrer eingestiegen ist: Das Auto übernimmt
-- beim Einsteigen die Farbe des Fahrers und behält sie nach dem Aussteigen; solange er sitzt, wirkt car.color = …
-- nicht (0.5.3 mit 2.1.23). Das ist keine Folge des Teleports; der Zustand vom Aufbau steht in d.before_seat und
-- in der MESSUNG „Aufbau (noch ohne Fahrer)“.
-- Deshalb färbt der Test die Puppe vor dem Einsteigen mit T3_DRIVER_COLOR: Mit Standard-Orange als Vorher fiele ein
-- Teleport oder Klon, der die Farbe auf Standard zurückstellt, nicht auf. Ist die Vorher-Farbe trotzdem die
-- Standardfarbe (Puppe ließ sich nicht färben), heißen die Farbzeilen „nicht aussagekräftig (Standardfarbe)“.

local T3_STEP = 30
local T3_ORIENTATION = 0.375
-- Farbe des Autos beim Aufbau (ohne Fahrer).
local T3_COLOR = {r = 0.2, g = 0.7, b = 1, a = 1}
-- Testfarbe der Puppe: weder Standard-Orange noch T3_COLOR, damit die Herkunft der Autofarbe erkennbar bleibt.
local T3_DRIVER_COLOR = {r = 0.6, g = 0.2, b = 0.8, a = 0.5}
-- Standardfarbe einer Spielfigur ohne Spieler (gelesen in 0.4.0 bis 0.5.3), falls die Puppe sie nicht verrät.
local T3_DEFAULT_COLOR = "0.87/0.50/0.13/0.50"
local T3_COLOR_NOTE = "nicht aussagekräftig (Standardfarbe)"

-- Felder des Zustandsvergleichs. tolerance für Zahlen, kilo = Anzeige in kJ.
-- unsupported = Schlüssel in run.data: ist er gesetzt, kann das Auto das Feld nicht tragen (nur INFO, nicht gezählt).
-- note = Schlüssel in run.data: ist er gesetzt, sagt „gleich“ bei diesem Feld nichts (Text steht dahinter, wird gezählt).
local T3_FIELDS =
{
  {key = "trunk", label = "Kofferraum"},
  {key = "fuel", label = "Treibstoff"},
  {key = "remaining", label = "Restbrennwert", tolerance = 1, kilo = true},
  {key = "burning", label = "brennendes Item"},
  {key = "health", label = "Gesundheit", tolerance = 0.01},
  {key = "quality", label = "Qualität"},
  {key = "label", label = "Label", unsupported = "label_unsupported"},
  {key = "color", label = "Farbe", note = "color_note"},
  {key = "unit_number", label = "unit_number", integer = true},
  {key = "orientation", label = "Ausrichtung", tolerance = 0.001, digits = 3},
  {key = "minable_flag", label = "minable_flag"}
}

local function color_text(color)
  if type(color) ~= "table" then return color == nil and "–" or tostring(color) end
  local r, g, b, a = color.r or color[1], color.g or color[2], color.b or color[3], color.a or color[4] or 1
  return string.format("%.2f/%.2f/%.2f/%.2f", r or 0, g or 0, b or 0, a)
end

-- Liest einen Wert; Fehler werden zum Text (damit der Vergleich sie zeigt).
local function read(fn)
  local ok, value = pcall(fn)
  if ok then return value end
  return "Fehler: " .. tostring(value)
end

-- Zustand des Ernters als reine Daten.
local function t3_snapshot(car)
  local burner = car.burner
  return
  {
    surface = car.surface.name,
    position = copy_pos(car.position),
    trunk = contents_text(car.get_inventory(defines.inventory.car_trunk)),
    fuel = contents_text(car.get_fuel_inventory()),
    remaining = burner and read(function() return burner.remaining_burning_fuel end) or "kein Brenner",
    burning = burner and read(function() return item_pair_name(burner.currently_burning) end) or "kein Brenner",
    health = read(function() return car.health end),
    quality = read(function() return car.quality.name end),
    label = read(function() return car.entity_label end),
    color = color_text(read(function() return car.color end)),
    unit_number = car.unit_number,
    orientation = read(function() return car.orientation end),
    minable_flag = read(function() return car.minable_flag end)
  }
end

local function t3_value_text(tb, field, value)
  if value == nil then return "–" end
  if type(value) == "number" then
    if field.kilo then return tb.num(value / 1000) .. " kJ" end
    if field.integer then return string.format("%d", value) end
    return tb.num(value, field.digits or 1)
  end
  return tostring(value)
end

local function t3_same(field, a, b)
  if type(a) == "number" and type(b) == "number" then
    return math.abs(a - b) <= (field.tolerance or 0)
  end
  return a == b
end

local function t3_snapshot_text(tb, snap)
  local parts = {}
  for _, field in ipairs(T3_FIELDS) do
    table.insert(parts, field.label .. " " .. t3_value_text(tb, field, snap[field.key]))
  end
  return table.concat(parts, "; ")
end

local function t3_diff_labels(before, after)
  local labels = {}
  for _, field in ipairs(T3_FIELDS) do
    if not t3_same(field, before[field.key], after[field.key]) then table.insert(labels, field.label) end
  end
  return labels
end

-- Vergleich je Feld. per_field: jedes Feld eine Zeile (level_same/level_diff), sonst gleiche Felder gesammelt.
-- Gibt die Zahl gleicher Felder und die Zahl verglichener Felder zurück.
local function t3_compare(run, tb, prefix, before, after, level_same, level_diff, per_field)
  local same, compared, equal_labels, skipped, notes = 0, 0, {}, {}, {}
  for _, field in ipairs(T3_FIELDS) do
    local a, b = before[field.key], after[field.key]
    local note = field.note and run.data[field.note]
    if field.unsupported and run.data[field.unsupported] then
      table.insert(skipped, field.label)
    elseif t3_same(field, a, b) then
      compared = compared + 1
      same = same + 1
      if per_field then
        tb.log(run, level_same, prefix .. field.label .. " gleich: " .. t3_value_text(tb, field, b) .. (note and ("; " .. note) or ""))
      else
        table.insert(equal_labels, field.label)
        if note then table.insert(notes, field.label .. " " .. note) end
      end
    else
      compared = compared + 1
      tb.log(run, level_diff, prefix .. field.label .. " vorher " .. t3_value_text(tb, field, a)
        .. ", jetzt " .. t3_value_text(tb, field, b))
    end
  end
  if not per_field and #equal_labels > 0 then
    tb.log(run, level_same, prefix .. "gleich: " .. table.concat(equal_labels, ", ")
      .. (#notes > 0 and ("; " .. table.concat(notes, "; ")) or ""))
  end
  if #skipped > 0 then
    tb.log(run, "INFO", prefix .. "nicht verglichen (am Auto nicht unterstützt): " .. table.concat(skipped, ", "))
  end
  return same, compared
end

-- Ablage-Oberfläche (tb.hold_surface: Laborkacheln, 5×5 Chunks um 0,0, für alle Forces versteckt),
-- Stellplätze frei geräumt.
local function t3_hold_surface(run, tb)
  local surface = tb.hold_surface()
  local player = tb.player(run)
  local force = player and player.force or game.forces["player"]
  local ok_hidden, hidden = pcall(function() return force.get_surface_hidden(surface) end)
  if not (ok_hidden and hidden == true) then
    tb.log(run, "INFO", "Ablage für die Spieler-Force versteckt: " .. (ok_hidden and tostring(hidden) or ("nicht lesbar: " .. tostring(hidden))))
  end
  for _, entity in pairs(surface.find_entities_filtered{area = {{-64, -64}, {96, 96}}}) do
    if entity.valid and not (entity.type == "character" and entity.player) then
      entity.destroy()
    end
  end
  return surface
end

local function t3_driver_text(tb, car, driver)
  if not (driver and driver.valid) then return "ungültig (weg)" end
  local current = car and car.valid and car.get_driver()
  local inside = current and current.valid and current.object_name == "LuaEntity" and current.unit_number == driver.unit_number
  return (inside and "sitzt im Ernter" or "sitzt nicht im Ernter") .. ", auf " .. driver.surface.name .. " " .. pos_text(tb, driver.position)
end

-- Gültige Referenz auf den Ernter, notfalls per unit_number wiedergefunden.
local function t3_car(run, tb)
  local d = run.data
  if d.car and d.car.valid then return d.car end
  local number = d.before and d.before.unit_number
  local found = number and game.get_entity_by_unit_number(number)
  if found and found.valid then
    tb.log(run, "FEHLER", "Referenz auf den Ernter ungültig geworden; per unit_number wiedergefunden auf " .. found.surface.name)
    d.car = found
    return found
  end
  tb.log(run, "FEHLER", "Der Ernter ist verschwunden (auch per unit_number nicht zu finden)")
  return nil
end

local function t3_hold(run, tb)
  local hold = game.get_surface(HOLD)
  if not hold then tb.log(run, "FEHLER", "Ablage-Oberfläche " .. HOLD .. " fehlt") end
  return hold
end

local function t3_teleport(car, position, surface)
  return pcall(function() return car.teleport(position, surface) end)
end

local function t3_summary(run)
  local d = run.data
  return string.format("a) mit Fahrer: %s; b) Ablage %s/%s gleich, zurück %s/%s gleich; c) Klon %s/%s gleich%s",
    d.a_result or "–", count_text(d.b_hold_same), count_text(d.b_hold_total or #T3_FIELDS), count_text(d.b_back_same),
    count_text(d.b_back_total or #T3_FIELDS), count_text(d.c_same), count_text(d.c_total or #T3_FIELDS),
    d.color_note and ("; Farbe " .. d.color_note) or "")
end

local t3_steps = {}

-- a) Dummy-Fahrer (Puppe) erzeugen, mit T3_DRIVER_COLOR färben und erst dann einsteigen lassen (wie
-- tb.dummy_driver, nur mit dem Färben dazwischen). Teleport erst im nächsten Schritt: Der Vorher-Datensatz soll den
-- Zustand mit Fahrer zeigen, auch falls das Auto die Farbe des Fahrers erst im nächsten Tick übernimmt.
t3_steps[1] = function(run, tb)
  local d = run.data
  local car = t3_car(run, tb)
  if not car then return false end
  local surface = car.surface
  local position = surface.find_non_colliding_position("character", car.position, 10, 0.5) or car.position
  local driver = surface.create_entity{name = "character", position = position, force = car.force}
  if not driver then
    tb.log(run, "INFO", "a) Dummy-Fahrer ließ sich nicht erzeugen; a) läuft ohne Fahrer")
    return true
  end
  d.driver = driver
  local standard = read(function() return driver.color end)
  d.standard_color = type(standard) == "table" and color_text(standard) or nil
  local ok_color, err_color = pcall(function() driver.color = T3_DRIVER_COLOR end)
  local after = read(function() return driver.color end)
  local driver_color = color_text(after)
  local wanted = color_text(T3_DRIVER_COLOR)
  -- Gefärbt heißt: lesbar und gleich der Testfarbe oder wenigstens anders als die Standardfarbe (Rundung beim Speichern).
  if not ok_color then
    tb.log(run, "INFO", "a) Dummy-Fahrer färben ging nicht (" .. tostring(err_color) .. "); er steigt mit "
      .. (d.standard_color or "unbekannter Farbe") .. " ein")
  elseif type(after) ~= "table" then
    tb.log(run, "INFO", "a) Farbe des Dummy-Fahrers nicht lesbar (" .. driver_color .. "); ob das Färben wirkte, zeigt die Farbe des Autos mit Fahrer")
  elseif driver_color == wanted or (d.standard_color and driver_color ~= d.standard_color) then
    tb.log(run, "INFO", "a) Dummy-Fahrer vor dem Einsteigen gefärbt: " .. (d.standard_color or "–") .. " → " .. driver_color
      .. (driver_color == wanted and "" or (" (gesetzt " .. wanted .. ")")))
  else
    tb.log(run, "INFO", "a) Dummy-Fahrer färben ging nicht (Lesewert danach " .. driver_color .. "); er steigt mit "
      .. (d.standard_color or "unbekannter Farbe") .. " ein")
  end
  car.set_driver(driver)
  return true
end

-- a) Vorher-Datensatz mit Fahrer (Farbe vor und nach dem Einsteigen als INFO), dann Teleport mit Fahrer.
t3_steps[2] = function(run, tb)
  local d = run.data
  local car = t3_car(run, tb)
  if not car then return false end
  local hold = t3_hold(run, tb)
  if not hold then return false end
  local driver = d.driver
  local seated = driver and driver.valid and car.get_driver() ~= nil
  local seat = d.before_seat
  d.before = t3_snapshot(car)
  local seated_color = d.before.color
  local raw_driver_color = driver and driver.valid and read(function() return driver.color end)
  local driver_color = type(raw_driver_color) == "table" and color_text(raw_driver_color) or (raw_driver_color and "nicht lesbar" or "–")
  local origin
  if seated_color == seat.color then
    origin = " (gleich wie vor dem Einsteigen)"
  elseif seated_color == driver_color then
    origin = " (das Auto übernimmt die Farbe des Fahrers)"
  elseif type(raw_driver_color) ~= "table" then
    origin = " (anders als vor dem Einsteigen)"
  else
    origin = " (weder die Farbe vom Aufbau noch die des Fahrers)"
  end
  tb.log(run, "INFO", "a) Farbe vor dem Einsteigen " .. seat.color .. ", Dummy-Fahrer " .. driver_color .. ", Auto mit Dummy-Fahrer "
    .. seated_color .. origin .. "; „vorher“ heißt ab hier: Zustand mit Fahrer, vor dem Teleport")
  -- Standard-Orange als Vorher: ein Teleport oder Klon, der die Farbe auf Standard zurückstellt, fiele nicht auf.
  if seated_color == (d.standard_color or T3_DEFAULT_COLOR) then
    d.color_note = T3_COLOR_NOTE
    tb.log(run, "INFO", "a) Vorher-Farbe " .. seated_color .. " ist die Standardfarbe der Spielfigur; die Farbzeilen ab hier sind "
      .. T3_COLOR_NOTE)
  end
  local others = {}
  for _, field in ipairs(T3_FIELDS) do
    if field.key ~= "color" and not (field.unsupported and d[field.unsupported])
      and not t3_same(field, seat[field.key], d.before[field.key]) then
      table.insert(others, field.label .. " " .. t3_value_text(tb, field, seat[field.key]) .. " → "
        .. t3_value_text(tb, field, d.before[field.key]))
    end
  end
  if #others > 0 then
    tb.log(run, "INFO", "a) Mit Fahrer außerdem anders als beim Aufbau (vor dem Teleport, steckt damit im Vorher-Datensatz): "
      .. table.concat(others, ", "))
  end
  local ok, result = t3_teleport(car, {x = -5, y = -5}, hold)
  d.a_result = ok and tostring(result) or "Fehler"
  tb.log(run, "MESSUNG", "a) Teleport mit Dummy-Fahrer (" .. (seated and "sitzt" or "sitzt NICHT") .. ") zur Ablage (-5, -5): "
    .. result_text(ok, result))
  car = t3_car(run, tb)
  if not car then return false end
  tb.log(run, "MESSUNG", "a) Danach: Ernter auf " .. car.surface.name .. " " .. pos_text(tb, car.position)
    .. "; Fahrer " .. t3_driver_text(tb, car, driver))
  return true
end

-- a) 0,5 s später erneut ansehen, Fahrer entfernen, Ernter zurück auf die Testoberfläche.
t3_steps[3] = function(run, tb)
  local d = run.data
  local car = t3_car(run, tb)
  if not car then return false end
  tb.log(run, "MESSUNG", "a) Nach 0.5 s: Ernter auf " .. car.surface.name .. " " .. pos_text(tb, car.position)
    .. "; Fahrer " .. t3_driver_text(tb, car, d.driver))
  pcall(function() car.set_driver(nil) end)
  if d.driver and d.driver.valid then d.driver.destroy() end
  d.driver = nil
  local surface = tb.surface()
  if car.surface.name ~= surface.name then
    local ok, result = t3_teleport(car, d.home, surface)
    tb.log(run, "INFO", "a) Ernter ohne Fahrer zurück auf die Testoberfläche: " .. result_text(ok, result))
  end
  return true
end

-- b) Ohne Fahrer auf Stellplatz (5, 5) der Ablage.
t3_steps[4] = function(run, tb)
  local d = run.data
  local car = t3_car(run, tb)
  if not car then return false end
  pcall(function() car.set_driver(nil) end)
  local diffs = t3_diff_labels(d.before, t3_snapshot(car))
  if #diffs > 0 then
    tb.log(run, "INFO", "b) Schon vor dem Teleport anders als vorher (Folge von a): " .. table.concat(diffs, ", "))
  end
  local hold = t3_hold(run, tb)
  if not hold then return false end
  local ok, result = t3_teleport(car, {x = 5, y = 5}, hold)
  tb.log(run, "MESSUNG", "b) Teleport ohne Fahrer auf Stellplatz (5, 5) der Ablage: " .. result_text(ok, result))
  return true
end

-- b) Vergleich auf der Ablage, dann zurück.
t3_steps[5] = function(run, tb)
  local d = run.data
  local car = t3_car(run, tb)
  if not car then return false end
  local snap = t3_snapshot(car)
  tb.log(run, snap.surface == HOLD and "OK" or "FEHLER", "b) Ernter steht auf der Ablage: " .. snap.surface .. " " .. pos_text(tb, snap.position))
  d.b_hold_same, d.b_hold_total = t3_compare(run, tb, "b) Ablage: ", d.before, snap, "OK", "FEHLER", true)
  local surface = tb.surface()
  if snap.surface ~= surface.name then
    local ok, result = t3_teleport(car, d.home, surface)
    tb.log(run, "MESSUNG", "b) Teleport zurück auf die Testoberfläche: " .. result_text(ok, result))
  end
  return true
end

-- b) Vergleich zurück auf der Testoberfläche.
t3_steps[6] = function(run, tb)
  local d = run.data
  local car = t3_car(run, tb)
  if not car then return false end
  local snap = t3_snapshot(car)
  local surface = tb.surface()
  tb.log(run, snap.surface == surface.name and "OK" or "FEHLER", "b) Ernter wieder auf der Testoberfläche: " .. snap.surface
    .. " " .. pos_text(tb, snap.position))
  d.b_back_same, d.b_back_total = t3_compare(run, tb, "b) zurück: ", d.before, snap, "OK", "FEHLER", true)
  return true
end

-- c) Gegenprobe mit clone statt Teleport (nur INFO), Klon danach zerstören.
t3_steps[7] = function(run, tb)
  local d = run.data
  local car = t3_car(run, tb)
  if not car then return false end
  local hold = t3_hold(run, tb)
  if not hold then return false end
  local ok, clone = pcall(function() return car.clone{position = {x = 10, y = 10}, surface = hold} end)
  if not (ok and clone) then
    tb.log(run, "INFO", "c) clone auf die Ablage ging nicht: " .. (ok and "Rückgabe nil" or tostring(clone)))
    return true
  end
  d.clone = clone
  local snap = t3_snapshot(clone)
  tb.log(run, "INFO", "c) Klon auf " .. snap.surface .. " " .. pos_text(tb, snap.position) .. " (Original bleibt auf " .. car.surface.name .. ")")
  d.c_same, d.c_total = t3_compare(run, tb, "c) Klon: ", d.before, snap, "INFO", "INFO", false)
  clone.destroy()
  d.clone = nil
  return true
end

local function t3_start(run, tb)
  local d = run.data
  local origin = tb.area(run.id)
  tb.prepare(origin, 30)
  local surface = tb.surface()
  local ok_hold, hold = pcall(t3_hold_surface, run, tb)
  if not ok_hold then
    tb.log(run, "FEHLER", "Ablage-Oberfläche " .. HOLD .. " ging nicht: " .. tostring(hold))
    tb.finish(run, "abgebrochen (keine Ablage)")
    return
  end
  tb.log(run, "INFO", "Ablage-Oberfläche " .. hold.name .. " bereit (5×5 Chunks, versteckt)")
  d.home = {x = origin.x, y = origin.y}
  local force = force_of(run, tb)

  -- Ernter in Qualität uncommon, falls es sie gibt.
  local quality = quality_exists("uncommon") and "uncommon" or "normal"
  local car
  local ok, result = pcall(function()
    return surface.create_entity{name = HARVESTER, position = d.home, force = force, quality = quality, orientation = T3_ORIENTATION}
  end)
  if ok and result then
    car = result
  else
    tb.log(run, "INFO", "Ernter in Qualität " .. quality .. " ging nicht (" .. (ok and "nil" or tostring(result)) .. "), nehme normal")
    car = surface.create_entity{name = HARVESTER, position = d.home, force = force, orientation = T3_ORIENTATION}
  end
  if not car then
    tb.log(run, "FEHLER", "Ernter " .. HARVESTER .. " ließ sich nicht erzeugen")
    tb.finish(run, "abgebrochen (kein Ernter)")
    return
  end
  d.car = car

  -- Kofferraum: 500 Spice-Sand, 100 Eisenplatten, 10 Eisenplatten rare (falls es rare gibt).
  local trunk = car.get_inventory(defines.inventory.car_trunk)
  local n_spice = trunk and trunk.insert{name = "spice-sand", count = 500} or 0
  local n_iron = trunk and trunk.insert{name = "iron-plate", count = 100} or 0
  local n_rare = 0
  if trunk and quality_exists("rare") then
    local ok_rare, inserted = pcall(function() return trunk.insert{name = "iron-plate", count = 10, quality = "rare"} end)
    if ok_rare then n_rare = inserted else tb.log(run, "INFO", "Eisenplatten rare gingen nicht: " .. tostring(inserted)) end
  end

  -- Treibstoff 20 Kohle und ein laufender Brennvorgang mit krummem Restwert.
  local n_coal = tb.fuel(car, "coal", 20)
  local burner = car.burner
  if burner then
    local ok_burn, err_burn = pcall(function()
      burner.currently_burning = "coal"
      burner.remaining_burning_fuel = 2500000
    end)
    if not ok_burn then tb.log(run, "INFO", "Brennvorgang setzen ging nicht: " .. tostring(err_burn)) end
    -- Puffer voll: sonst füllt der Brenner ihn im nächsten Tick aus dem Restbrennwert auf,
    -- und der Vergleich meldet einen Verlust, den nicht der Teleport verursacht hat.
    local ok_heat, err_heat = pcall(function() burner.heat = burner.heat_capacity end)
    if not ok_heat then tb.log(run, "INFO", "Brenner-Puffer füllen ging nicht: " .. tostring(err_heat)) end
  else
    tb.log(run, "INFO", "Ernter hat keinen Brenner (burner = nil)")
  end

  -- Gesundheit 60 %, Label, Farbe, gedrehte Ausrichtung.
  local ok_health, err_health = pcall(function() car.health = car.max_health * 0.6 end)
  if not ok_health then tb.log(run, "INFO", "Gesundheit setzen ging nicht: " .. tostring(err_health)) end
  local ok_label, err_label = pcall(function() car.entity_label = "Test-Ernter" end)
  local label_now = read(function() return car.entity_label end)
  if not ok_label or label_now ~= "Test-Ernter" then
    d.label_unsupported = true
    tb.log(run, "INFO", "entity_label am Auto: " .. (ok_label and ("Lesewert " .. tostring(label_now)) or tostring(err_label))
      .. " (API: nur für Spinnenfahrzeuge dokumentiert); das Feld Label wird nicht verglichen")
  end
  local ok_color, err_color = pcall(function() car.color = T3_COLOR end)
  if not ok_color then tb.log(run, "INFO", "Farbe setzen ging nicht: " .. tostring(err_color)) end
  pcall(function() car.orientation = T3_ORIENTATION end)

  -- Zustand vom Aufbau; Vergleichsgrundlage wird erst der Zustand mit Fahrer (t3_steps[2]).
  d.before_seat = t3_snapshot(car)
  d.before = d.before_seat
  tb.log(run, "INFO", string.format("Aufbau: Qualität %s, Kofferraum %d Spice-Sand, %d Eisenplatten, %d Eisenplatten rare; %d Kohle",
    d.before_seat.quality, n_spice, n_iron, n_rare, n_coal))
  tb.log(run, "MESSUNG", "Aufbau (noch ohne Fahrer): " .. t3_snapshot_text(tb, d.before_seat))
  tb.watch(run, nil, {x = d.home.x, y = d.home.y + 8})
  d.step = 1
  d.next_tick = game.tick + T3_STEP
end

local function t3_tick(run, tb)
  local d = run.data
  if not d.step or game.tick < d.next_tick then return end
  local step = t3_steps[d.step]
  if not step then
    tb.finish(run, t3_summary(run))
    return
  end
  d.step = d.step + 1
  d.next_tick = game.tick + T3_STEP
  if not step(run, tb) then
    tb.finish(run, "abgebrochen (siehe FEHLER); " .. t3_summary(run))
  end
end

local function t3_cleanup(run, tb)
  local d = run.data
  if d.clone and d.clone.valid then d.clone.destroy() end
  d.clone = nil
  if d.driver and d.driver.valid then d.driver.destroy() end
  d.driver = nil
end

return
{
  T3 =
  {
    title = "Ernter: Teleport zur Ablage",
    timeout = 30 * 60,
    interactive = false,
    confirm = nil,
    start = t3_start,
    tick = t3_tick,
    cleanup = t3_cleanup
  }
}
