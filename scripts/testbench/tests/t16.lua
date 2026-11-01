-- T16 Ornithopter: Flugphysik: Prüfstand-Test (aus t_ornithopter.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_ornithopter.lua.

local common = require("scripts.testbench.gemeinsam_ornithopter")
local flyer_lib = require("scripts.flyer")
local speed = require("prototypes.ornithopter-speed")
local valid = common.valid
local copy_pos = common.copy_pos
local at = common.at
local pos_text = common.pos_text
local read = common.read
local quality_exists = common.quality_exists
local box_of = common.box_of
local fuel_energy = common.fuel_energy
local own_stickers = common.own_stickers
local sticker_text = common.sticker_text
local check_loaded = common.check_loaded
local check_carried = common.check_carried
local create = common.create
local new_car = common.new_car
local new_flyer = common.new_flyer
local couple = common.couple
local tidy = common.tidy
local sweep = common.sweep
local storage_ready = common.storage_ready

local function fuel_items(entity)
  local inventory = valid(entity) and entity.get_fuel_inventory()
  return inventory and inventory.get_item_count() or 0
end

-- T16 Ornithopter: Flugphysik -----------------------------------------------------------------------
-- Echte Ornithopter (eingetragen über script_raised_built, also mit echtem Sticker) mit Dummy-Pilot fliegen alle
-- zugleich los, Ziel 400 Kacheln voraus. Gemessen wird zwischen 5 s und 15 s nach dem Start: Weg, Brennwert.
-- Fläche A: Ost-Bahnen im Abstand 10, dazu West und Nordost; Fläche B (400 Kacheln östlich): Nord und Süd in eigenen
-- Spalten. Die Beine drehen nicht mit der Flugrichtung (docs/pruefstand.md, Bekannte Grenzen), deshalb N und S getrennt.
-- Vergleichsbahnen (raw): create_entity ohne raise_built; care sieht sie nie, und eine Puppe ohne Spieler löst kein
-- on_player_driving_changed_state aus. Bei einem eingetragenen Flieger hängte care binnen 60 Ticks den eigenen
-- Sticker wieder an, und im Messfenster wirkten beide.
-- Seit 0.6.1 wählt die Mod den Sticker je Brennstoff (prototypes/ornithopter-speed.lua): Jede Bahn nennt ihren Sticker
-- samt Stufe (z. B. „leer t1,15“). Die Bahn „effectivity_modifier 0,5“ (ohne Sticker, nur MESSUNG) zeigt, ob dieses
-- Feld bei einer Spinne wirkt; beim Ernter wirkt es (scripts/harvester.lua, apply_fuel_normalization).

local T16_HALF_A = {x = 140, y = 95}
local T16_B = {x = 400, y = 0}
local T16_HALF_B = {x = 45, y = 140}
local T16_GO = 140             -- Ticks nach dem Bau: Anheben fertig (120 bis 129), dann alle zugleich los
local T16_FROM, T16_TO = 5 * 60, 15 * 60
local T16_DISTANCE = 400
local T16_EMPTY = {7.0, 9.0}
local T16_LOADED = {5.0, 6.5}
local T16_RATIO = {0.65, 0.75}
local T16_FUEL_SPREAD = 1.10
local T16_QUALITY_SPREAD = 0.10
local T16_DIRS =
{
  O = {x = 1, y = 0},
  W = {x = -1, y = 0},
  N = {x = 0, y = -1},
  S = {x = 0, y = 1},
  NO = {x = math.sqrt(0.5), y = -math.sqrt(0.5)}
}
-- start relativ zur Fläche (A: Ursprung, B: Ursprung + T16_B). check: "empty" oder "loaded" (Tempo-Grenzen, geteilt
-- durch den Tempo-Faktor g des Brennstoffs); group = "fuel": Tempo je Treibstoff [U7]; pair: leere Bahn für das
-- Verhältnis beladen/leer; to: eigenes Ende des Messfensters (schnelle Bahnen verließen sonst die Fläche); reject:
-- Brennstoff, der ab 0.9.0 nicht in den Ornithopter passt (die Bahn fliegt nicht, gezählt wird das Einfüllen).
local T16_LANES =
{
  {key = "coal", label = "Kohle einfüllen", fuel = "coal", count = 10, start = {-125, -85}, reject = true},
  {key = "solid", label = "Festbrennstoff einfüllen", fuel = "solid-fuel", count = 5, start = {-115, -85}, reject = true},
  {key = "briquette", label = "Spice-Brikett einfüllen", fuel = "arrakis-spice-briquette", count = 5, start = {-105, -85}, reject = true},
  {key = "rocket", label = "leer, Raketentreibstoff, O", fuel = "rocket-fuel", count = 2, dir = "O", start = {-125, -60}, check = "empty", group = "fuel"},
  {key = "nuclear", label = "leer, Atomtreibstoff, O", fuel = "nuclear-fuel", count = 1, dir = "O", start = {-125, -50}, check = "empty", group = "fuel"},
  {key = "legendary_fuel", label = "leer, Raketentreibstoff legendär, O", fuel = "rocket-fuel", fuel_quality = "legendary", count = 2, dir = "O",
   start = {-125, -40}, check = "empty", group = "fuel", needs = "legendary", to = 10 * 60},
  {key = "legendary_nuclear", label = "leer, Atomtreibstoff legendär, O", fuel = "nuclear-fuel", fuel_quality = "legendary", count = 1, dir = "O",
   start = {-125, -30}, check = "empty", group = "fuel", needs = "legendary", to = 10 * 60},
  {key = "uncommon", label = "leer, Raketentreibstoff, O, Ornithopter ungewöhnlich", fuel = "rocket-fuel", count = 2, quality = "uncommon", dir = "O",
   start = {-125, 0}, check = "empty", needs = "uncommon", base = "rocket"},
  {key = "legendary", label = "leer, Raketentreibstoff, O, Ornithopter legendär", fuel = "rocket-fuel", count = 2, quality = "legendary", dir = "O",
   start = {-125, 10}, check = "empty", needs = "legendary", base = "rocket"},
  {key = "loaded_nuclear", label = "beladen, Atomtreibstoff, O", fuel = "nuclear-fuel", count = 1, dir = "O", start = {-125, 20}, check = "loaded",
   loaded = true, pair = "nuclear"},
  {key = "loaded_rocket", label = "beladen, Raketentreibstoff, O", fuel = "rocket-fuel", count = 2, dir = "O", start = {-125, 30}, check = "loaded",
   loaded = true, pair = "rocket"},
  {key = "raw", label = "ohne Sticker (Rohwert), Raketentreibstoff, O", fuel = "rocket-fuel", count = 2, dir = "O", start = {-125, 40}, raw = true},
  {key = "max_tick", label = "Test-Sticker vehicle_speed_max 8/60, Raketentreibstoff, O", fuel = "rocket-fuel", count = 2, dir = "O",
   start = {-125, 50}, raw = true, sticker = "arrakis-test-speed-max-tick"},
  {key = "max_second", label = "Test-Sticker vehicle_speed_max 8, Raketentreibstoff, O", fuel = "rocket-fuel", count = 2, dir = "O",
   start = {-125, 60}, raw = true, sticker = "arrakis-test-speed-max-second"},
  {key = "west", label = "leer, Raketentreibstoff, W", fuel = "rocket-fuel", count = 2, dir = "W", start = {125, 70}, check = "empty"},
  {key = "northeast", label = "leer, Raketentreibstoff, NO", fuel = "rocket-fuel", count = 2, dir = "NO", start = {-125, 85}, check = "empty"},
  {key = "hover", label = "Schweben beladen, Raketentreibstoff, ohne Ziel", fuel = "rocket-fuel", count = 2, loaded = true, hover = true, start = {100, 80}},
  {key = "north", label = "leer, Raketentreibstoff, N", fuel = "rocket-fuel", count = 2, dir = "N", region = "B", start = {-20, 125}, check = "empty"},
  {key = "loaded_rocket_north", label = "beladen, Raketentreibstoff, N", fuel = "rocket-fuel", count = 2, dir = "N", region = "B", start = {0, 125},
   check = "loaded", loaded = true, pair = "north"},
  {key = "south", label = "leer, Raketentreibstoff, S", fuel = "rocket-fuel", count = 2, dir = "S", region = "B", start = {35, -125}, check = "empty"},
  {key = "effectivity", label = "ohne Sticker, Raketentreibstoff, effectivity_modifier 0,5, O", fuel = "rocket-fuel", count = 2, dir = "O",
   start = {-125, -70}, raw = true, effectivity = 0.5}
}

-- Tempo-Faktor g eines Brennstoffs samt Qualität (prototypes/ornithopter-speed.lua): Raketentreibstoff normal 1.
local function t16_gain(fuel, quality)
  local item = prototypes.item[fuel]
  local level = quality and prototypes.quality[quality] and prototypes.quality[quality].level or 0
  return item and speed.gain(item.fuel_acceleration_multiplier + level * item.fuel_acceleration_multiplier_quality_bonus) or 1
end

local function t16_build(run, tb, d)
  d.lanes = {}
  local skipped = {}
  for _, spec in ipairs(T16_LANES) do
    if spec.needs and not quality_exists(spec.needs) then
      table.insert(skipped, spec.label)
    else
      local base = spec.region == "B" and at(d.origin, T16_B.x, T16_B.y) or d.origin
      local start = at(base, spec.start[1] + 0.5, spec.start[2] + 0.5)
      local lane = {spec = spec, start = start, gain = t16_gain(spec.fuel, spec.fuel_quality)}
      lane.flyer = new_flyer(run, tb, start, {fuel = spec.fuel, count = spec.count, fuel_quality = spec.fuel_quality,
        quality = spec.quality, raw = spec.raw, pilot = true})
      if lane.flyer and spec.reject then
        lane.fuel_in = fuel_items(lane.flyer)
        lane.lost = "fliegt nicht (Brennstoff-Probe)"
      elseif lane.flyer then
        lane.un = lane.flyer.unit_number
        lane.fuel_in = fuel_items(lane.flyer)
        lane.pilot = lane.flyer.get_driver() ~= nil
        if spec.sticker then
          lane.sticker = create(run, tb, {name = spec.sticker, position = lane.flyer.position, target = lane.flyer, force = lane.flyer.force})
        end
        if spec.effectivity then
          -- Ob das Feld bei einer Spinne schreibbar ist, sagt die API nicht („the car“); pcall, gelesen wird zurück.
          local ok, err = pcall(function() lane.flyer.effectivity_modifier = spec.effectivity end)
          lane.eff_probe = {ok = ok, err = not ok and tostring(err) or nil,
            value = read(function() return lane.flyer.effectivity_modifier end)}
        end
        if spec.loaded then
          lane.car = new_car(run, tb, at(start, 0, 1.5), {})
          lane.result = {couple(lane.flyer, lane.car)}
        end
      end
      table.insert(d.lanes, lane)
    end
  end
  if #skipped > 0 then tb.log(run, "INFO", "Ohne Quality entfallen: " .. table.concat(skipped, "; ")) end
  d.go_tick = game.tick + T16_GO
  d.phase = "go"
end

local function t16_go(run, tb, d)
  local failed = {}
  for _, lane in ipairs(d.lanes) do
    local spec = lane.spec
    if spec.reject then
      tb.trace(run, string.format("Bahn %s: %d von %d %s eingefüllt", spec.label, lane.fuel_in or 0, spec.count, spec.fuel))
    elseif not lane.flyer then
      lane.lost = "Ornithopter ließ sich nicht erzeugen"
    elseif spec.loaded and not (check_loaded(failed, spec.label, lane.flyer, lane.car) and check_carried(failed, spec.label, lane.car, lane.flyer)) then
      lane.lost = "Anheben ging nicht"
    elseif not spec.raw and not flyer_lib.get(lane.flyer) then
      lane.lost = "nicht eingetragen"
    end
    if lane.flyer and not lane.lost and not spec.hover then
      local dir = T16_DIRS[spec.dir]
      local ok = pcall(function()
        lane.flyer.autopilot_destination = {x = lane.start.x + dir.x * T16_DISTANCE, y = lane.start.y + dir.y * T16_DISTANCE}
      end)
      if not ok then lane.lost = "autopilot_destination ging nicht" end
    end
    if lane.lost and not spec.reject then tb.log(run, "FEHLER", "Bahn " .. spec.label .. ": " .. lane.lost) end
    if lane.flyer and not spec.reject then
      local effectivity = lane.eff_probe
      local extra = ""
      if effectivity then
        extra = ", effectivity_modifier " .. tb.num(spec.effectivity, 2) .. " " .. (effectivity.ok and "geschrieben" or ("nicht schreibbar ("
          .. tostring(effectivity.err) .. ")")) .. ", gelesen " .. tostring(effectivity.value and tb.num(effectivity.value, 3))
      end
      tb.trace(run, string.format("Bahn %s: Start %s, %d Brennstoffe, Pilot %s, Sticker %s%s%s", spec.label, pos_text(tb, lane.start),
        lane.fuel_in or 0, tostring(lane.pilot), sticker_text(own_stickers(lane.flyer)), spec.sticker and (" + " .. spec.sticker) or "", extra))
    end
  end
  if #failed > 0 then tb.trace(run, "Anheben: " .. table.concat(failed, "; ")) end
  d.t0 = game.tick
  d.phase = "sample"
end

local function t16_sample(lane, key)
  local flyer = lane.flyer
  if not valid(flyer) then return end
  lane[key] = {position = copy_pos(flyer.position), energy = fuel_energy(flyer), items = fuel_items(flyer),
    sticker = sticker_text(own_stickers(flyer))}
end

-- Tempo (Kacheln/s), kJ/Kachel und kW zwischen den beiden Messpunkten; nil, wenn nicht gemessen.
local function t16_values(lane)
  local a, b = lane.from, lane.to
  if not (a and b) then return nil end
  local seconds = ((lane.spec.to or T16_TO) - T16_FROM) / 60
  local distance = math.sqrt((b.position.x - a.position.x) ^ 2 + (b.position.y - a.position.y) ^ 2)
  local used = (a.energy and b.energy) and (a.energy - b.energy) or nil
  return
  {
    speed = distance / seconds,
    distance = distance,
    kj_tile = used and distance > 0 and used / distance / 1000 or nil,
    kw = used and used / seconds / 1000 or nil,
    used = used
  }
end

local function range_text(range)
  return string.format("%.2f–%.2f", range[1], range[2])
end

local function t16_evaluate(run, tb, d)
  local by_key, speeds = {}, {}
  for _, lane in ipairs(d.lanes) do
    by_key[lane.spec.key] = lane
    lane.values = t16_values(lane)
    local v = lane.values
    if v then
      speeds[lane.spec.key] = v.speed
      tb.trace(run, string.format("Bahn %s: %s Kacheln/s, %s Kacheln in 10 s, %s kJ/Kachel, %s kW, Brennstoffe %d → %d, Sticker %s → %s",
        lane.spec.label, tb.num(v.speed, 2), tb.num(v.distance), tb.num(v.kj_tile, 1), tb.num(v.kw, 0),
        lane.from.items or 0, lane.to.items or 0, lane.from.sticker or "–", lane.to.sticker or "–"))
    end
  end
  local criteria, ok_count = 0, 0
  local function rule(title, failed, values)
    criteria = criteria + 1
    if #failed == 0 then ok_count = ok_count + 1 end
    tb.log(run, #failed == 0 and "OK" or "FEHLER", title .. ": " .. values .. (#failed > 0 and (" | nicht erfüllt: " .. table.concat(failed, "; ")) or ""))
  end
  local function speed_of(key)
    return speeds[key]
  end
  -- 1. leer 7,0–9,0; 2. beladen 5,0–6,5, je geteilt durch den Tempo-Faktor g des Brennstoffs (ab 0.9.0)
  for _, kind in ipairs({"empty", "loaded"}) do
    local range = kind == "empty" and T16_EMPTY or T16_LOADED
    local failed, parts = {}, {}
    for _, lane in ipairs(d.lanes) do
      if lane.spec.check == kind then
        local v = speed_of(lane.spec.key)
        if not v then
          table.insert(failed, lane.spec.label .. " nicht gemessen")
        else
          local norm = v / lane.gain
          local text = lane.spec.label .. " " .. tb.num(v, 2) .. (lane.gain ~= 1 and (" (/ g " .. tb.num(lane.gain, 3) .. " = " .. tb.num(norm, 2) .. ")") or "")
          table.insert(parts, text)
          if norm < range[1] or norm > range[2] then table.insert(failed, text) end
        end
      end
    end
    rule((kind == "empty" and "Tempo leer " or "Tempo beladen ") .. range_text(range) .. " Kacheln/s · g [U6]", failed, table.concat(parts, ", "))
  end
  -- 3. beladen/leer, gleicher Brennstoff und gleiche Richtung
  do
    local failed, parts = {}, {}
    for _, lane in ipairs(d.lanes) do
      local pair = lane.spec.pair
      if pair then
        local loaded, empty = speed_of(lane.spec.key), speed_of(pair)
        if loaded and empty and empty > 0 then
          local ratio = loaded / empty
          table.insert(parts, lane.spec.label .. " / " .. by_key[pair].spec.label .. " = " .. tb.num(ratio, 3))
          if ratio < T16_RATIO[1] or ratio > T16_RATIO[2] then table.insert(failed, lane.spec.label .. " " .. tb.num(ratio, 3)) end
        else
          table.insert(failed, lane.spec.label .. ": Paar nicht gemessen")
        end
      end
    end
    local rn, ro = speed_of("loaded_rocket_north"), speed_of("rocket")
    if rn and ro and ro > 0 then
      tb.trace(run, "beladen, Raketentreibstoff, N / leer, Raketentreibstoff, O = " .. tb.num(rn / ro, 3) .. " (kein Paar gleicher Richtung)")
    end
    rule("Verhältnis beladen/leer " .. range_text(T16_RATIO), failed, table.concat(parts, ", "))
  end
  -- 4. Treibstoff [U7] (ab 0.9.0): Tempo je Treibstoff im Verhältnis zu Raketentreibstoff wie g (Atomtreibstoff 1,39,
  -- legendärer Raketentreibstoff 1,67, legendärer Atomtreibstoff 2,64), je höchstens T16_FUEL_SPREAD daneben.
  do
    local failed, parts = {}, {}
    local rocket = speed_of("rocket")
    for _, lane in ipairs(d.lanes) do
      if lane.spec.group == "fuel" and lane.spec.key ~= "rocket" then
        local v = speed_of(lane.spec.key)
        if v and rocket and rocket > 0 then
          local ratio = v / rocket
          local text = string.format("%s %s (%s statt %s)", lane.spec.label, tb.num(v, 2), tb.num(ratio, 3), tb.num(lane.gain, 3))
          table.insert(parts, text)
          if math.abs(ratio / lane.gain - 1) > T16_FUEL_SPREAD - 1 then table.insert(failed, text) end
        else
          table.insert(failed, lane.spec.label .. " nicht gemessen")
        end
      end
    end
    rule("Besserer Treibstoff fliegt schneller [U7], Verhältnis zu Raketentreibstoff = g ± " .. tb.num((T16_FUEL_SPREAD - 1) * 100, 0) .. " %",
      failed, "Raketentreibstoff " .. tostring(rocket and tb.num(rocket, 2)) .. "; " .. table.concat(parts, ", "))
  end
  -- 6. Nur Flugtreibstoff (0.9.0): Kohle, Festbrennstoff und Spice-Brikett gehen nicht hinein.
  do
    local failed, parts = {}, {}
    for _, lane in ipairs(d.lanes) do
      if lane.spec.reject then
        local n = lane.fuel_in
        table.insert(parts, lane.spec.label .. " " .. tostring(n))
        if n ~= 0 then table.insert(failed, lane.spec.label .. " " .. tostring(n) .. " statt 0") end
      end
    end
    rule("Nur Flugtreibstoff passt hinein", failed, table.concat(parts, ", "))
  end
  -- 5. Qualität [U8]
  do
    local failed, parts = {}, {}
    local rocket_v = speed_of("rocket")
    for _, lane in ipairs(d.lanes) do
      if lane.spec.base then
        local v = speed_of(lane.spec.key)
        if v and rocket_v and rocket_v > 0 then
          local change = math.abs(v - rocket_v) / rocket_v
          table.insert(parts, lane.spec.label .. " " .. tb.num(v, 2) .. " (" .. tb.num(change * 100, 1) .. " %)")
          if change > T16_QUALITY_SPREAD then table.insert(failed, lane.spec.label .. " " .. tb.num(change * 100, 1) .. " %") end
        else
          table.insert(failed, lane.spec.label .. " nicht gemessen")
        end
      end
    end
    if #parts == 0 and #failed == 0 then
      tb.log(run, "INFO", "Qualität [U8]: ohne Quality nicht prüfbar")
    else
      rule("Qualität ändert das Tempo um höchstens 10 % [U8]", failed, "Raketentreibstoff normal " .. tostring(rocket_v and tb.num(rocket_v, 2)) .. "; " .. table.concat(parts, ", "))
    end
  end
  -- Vergleichsbahnen [U22], effectivity_modifier und Schweben [U10]: nur MESSUNG/INFO.
  for _, key in ipairs({"raw", "max_tick", "max_second", "effectivity"}) do
    local lane = by_key[key]
    local v = lane and lane.values
    tb.trace(run, string.format("Vergleich %s: %s Kacheln/s", lane and lane.spec.label or key, tostring(v and tb.num(v.speed, 2))))
  end
  do
    local lane = by_key.effectivity
    local effectivity = lane and lane.eff_probe
    local raw = speed_of("raw")
    local v = speed_of("effectivity")
    if effectivity then
      tb.trace(run, string.format("effectivity_modifier bei der Spinne: %s, gelesen %s; Tempo %s statt %s Kacheln/s ohne (Verhältnis %s)",
        effectivity.ok and "geschrieben" or ("nicht schreibbar (" .. tostring(effectivity.err) .. ")"),
        tostring(effectivity.value and tb.num(effectivity.value, 3)), tostring(v and tb.num(v, 2)), tostring(raw and tb.num(raw, 2)),
        (v and raw and raw > 0) and tb.num(v / raw, 3) or "–"))
    end
  end
  local hover = by_key.hover
  local hv = hover and hover.values
  if hv then
    tb.trace(run, string.format("Schweben [U10]: Brennwert %s → %s kJ, Brennstoffe %d → %d, Verbrauch %s kW (%s kJ je 10 s), Weg %s Kacheln",
      tb.num(hover.from.energy and hover.from.energy / 1000, 0), tb.num(hover.to.energy and hover.to.energy / 1000, 0),
      hover.from.items or 0, hover.to.items or 0, tb.num(hv.kw, 1), tb.num(hv.used and hv.used / 1000, 0), tb.num(hv.distance, 2)))
    if hv.used and hv.used > 1000 then
      tb.log(run, "INFO", "U10 hält nicht: Schweben kostet " .. tb.num(hv.kw, 1) .. " kW (docs/protokolle/plan-3c.md 4.16 nimmt das hin)")
    end
  end
  -- Raketentreibstoff: r = t = 1,15, sein Sticker BASE / 1,15 ergibt BASE · Rohtempo bei t = 1 (prototypes/ornithopter-speed.lua).
  local empty, loaded = speed_of("rocket"), speed_of("loaded_rocket")
  tb.log(run, "INFO", string.format("Vorschlag aus den Ost-Bahnen mit Raketentreibstoff [U6]: BASE_EMPTY %s · 8 / %s = %s, BASE_LOADED %s · 5.6 / %s = %s"
    .. " (prototypes/ornithopter-speed.lua)",
    tb.num(speed.BASE_EMPTY, 3), tostring(empty and tb.num(empty, 2)), (empty and empty > 0) and tb.num(speed.BASE_EMPTY * 8 / empty, 3) or "–",
    tb.num(speed.BASE_LOADED, 3), tostring(loaded and tb.num(loaded, 2)), (loaded and loaded > 0) and tb.num(speed.BASE_LOADED * 5.6 / loaded, 3) or "–"))
  for _, lane in ipairs(d.lanes) do
    if valid(lane.flyer) then pcall(function() lane.flyer.autopilot_destination = nil end) end
  end
  local measured, flying = 0, 0
  for _, lane in ipairs(d.lanes) do
    if not lane.spec.reject then flying = flying + 1 end
    if lane.values then measured = measured + 1 end
  end
  local summary = string.format("%d/%d Bahnen gemessen, Kriterien %d/%d OK", measured, flying, ok_count, criteria)
  tb.finish(run, summary)
end

local function t16_start(run, tb)
  local d = run.data
  local origin = tb.area(run.id)
  d.origin = origin
  d.boxes = {box_of(origin, T16_HALF_A), box_of(at(origin, T16_B.x, T16_B.y), T16_HALF_B)}
  d.made = {cars = {}, flyers = {}, others = {}}
  if not storage_ready() then
    tb.log(run, "FEHLER", "storage des Laufzeitcodes fehlt (scripts/migrate.lua init nicht gelaufen)")
    tb.finish(run, "abgebrochen (kein storage)")
    return
  end
  sweep(run, tb, d.boxes, false)
  tb.prepare(origin, T16_HALF_A)
  tb.prepare(at(origin, T16_B.x, T16_B.y), T16_HALF_B)
  tb.watch(run, nil, at(origin, 0, 92))
  tb.log(run, "INFO", "Echte Ornithopter auf parallelen Bahnen, alle zugleich; gemessen zwischen 5 s und 15 s nach dem Start."
    .. " Grenzen: leer " .. range_text(T16_EMPTY) .. ", beladen " .. range_text(T16_LOADED) .. " Kacheln/s, beladen/leer "
    .. range_text(T16_RATIO) .. ". Einzelwerte in der Datei.")
  d.phase = "build"
  d.wait_until = game.tick + 30
end

local function t16_tick(run, tb)
  local d = run.data
  if d.phase == "build" then
    if game.tick >= d.wait_until then t16_build(run, tb, d) end
  elseif d.phase == "go" then
    if game.tick >= d.go_tick then t16_go(run, tb, d) end
  elseif d.phase == "sample" then
    local elapsed = game.tick - d.t0
    if elapsed == T16_FROM then
      for _, lane in ipairs(d.lanes) do if not lane.lost then t16_sample(lane, "from") end end
    end
    for _, lane in ipairs(d.lanes) do
      if not lane.lost and lane.from and not lane.to and elapsed >= (lane.spec.to or T16_TO) then t16_sample(lane, "to") end
    end
    if elapsed >= T16_TO then
      d.phase = "done"
      t16_evaluate(run, tb, d)
    end
  end
end

local function t16_cleanup(run, tb)
  local d = run.data
  pcall(tidy, run)
  if d.boxes then pcall(sweep, run, tb, d.boxes, true) end
end

return
{
  T16 =
  {
    title = "Ornithopter: Flugphysik",
    timeout = 90 * 60,
    interactive = false,
    confirm = nil,
    start = t16_start,
    tick = t16_tick,
    cleanup = t16_cleanup
  }
}
