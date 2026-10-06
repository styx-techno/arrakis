-- Prüfstand: Ernter-Tests T2, T3, T4 (Vertrag siehe runner.lua).
--   T2: Skriptfahrt, Höchsttempo je Brennstoff, Tempo-Deckel, Sperre (disabled_by_script), Status.
--   T3: Teleport zur Ablage-Oberfläche und zurück, Zustandsvergleich, Gegenprobe mit clone.
--   T4: Annahme und Tankstutzen (proxy-container) mit Greifarmen, Schaltung und Bauregel.
-- Zustand nur in run.data (Zahlen, Texte, Positionen, LuaEntity-Referenzen; vor jeder Benutzung prüfen).

local HARVESTER = "arrakis-test-harvester"
local INTAKE = "arrakis-test-intake"
local NOZZLE = "arrakis-test-nozzle"
local HOLD = "arrakis-test-hold"

-- Allgemeine Helfer ---------------------------------------------------------------------------

local function force_of(run, tb)
  local player = tb.player(run)
  return player and player.force or "player"
end

local function copy_pos(position)
  return {x = position.x or position[1], y = position.y or position[2]}
end

local function pos_text(tb, position)
  if not position then return "–" end
  local p = copy_pos(position)
  return "(" .. tb.num(p.x) .. ", " .. tb.num(p.y) .. ")"
end

local function count_text(value)
  if value == nil then return "–" end
  return tostring(value)
end

-- Rückgabe und Fehlermeldung eines pcall als Text.
local function result_text(ok, result)
  if ok then return "Rückgabe " .. tostring(result) .. ", Fehlermeldung –" end
  return "Rückgabe –, Fehlermeldung " .. tostring(result)
end

-- Name eines ItemIDAndQualityIDPair (gelesen: LuaItemPrototype/LuaQualityPrototype) als "name@qualität".
local function item_pair_name(pair)
  if not pair then return "–" end
  local name, quality = pair.name, pair.quality
  if name and type(name) ~= "string" then name = name.name end
  if quality and type(quality) ~= "string" then quality = quality.name end
  return tostring(name) .. "@" .. tostring(quality or "normal")
end

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

-- Anzahl eines Items in einem Inventar der Entity; nil, wenn nicht lesbar.
local function count_in(entity, inventory_index, item)
  if not (entity and entity.valid) then return nil end
  local ok, count = pcall(function()
    local inventory = entity.get_inventory(inventory_index)
    return inventory and inventory.get_item_count(item)
  end)
  if ok then return count end
  return nil
end

local function burner_text(tb, burner)
  if not burner then return "kein Brenner" end
  local ok, text = pcall(function()
    return "brennt " .. item_pair_name(burner.currently_burning)
      .. ", Rest " .. tb.num(burner.remaining_burning_fuel / 1000) .. " kJ"
      .. ", Puffer " .. tb.num(burner.heat / 1000) .. " kJ"
  end)
  if ok then return text end
  return "Brenner nicht lesbar: " .. tostring(text)
end

local function quality_exists(name)
  local ok, exists = pcall(function() return prototypes.quality[name] ~= nil end)
  return ok and exists
end

-- T2 Ernter-Fahrzeug ----------------------------------------------------------------------------
-- Ein Ernter mit Dummy-Fahrer fährt auf einer 300 Kacheln langen Sandbahn nach Osten. Je Durchgang:
-- Position, Tempo und Brenner zurücksetzen, Brennstoff einlegen, Gas geben (riding_state jeden Tick).

-- Deckel-Durchgang: mit Raketentreibstoff (schnellster Brennstoff, der Fall, für den der Deckel gedacht ist).
-- Der Deckel ist 1.5 Kacheln/s, wenn der Ernter ohne Deckel schneller als 1.6 fuhr; sonst 70 % seines
-- Höchsttempos, damit der Deckel wirklich greifen muss (siehe t2_cap).
local T2_PASSES =
{
  {key = "coal", label = "Kohle", fuel = "coal", count = 10, ticks = 15 * 60},
  {key = "solid", label = "Festbrennstoff", fuel = "solid-fuel", count = 10, ticks = 15 * 60},
  {key = "rocket", label = "Raketentreibstoff", fuel = "rocket-fuel", count = 5, ticks = 15 * 60},
  {key = "cap", label = "Raketentreibstoff mit Tempo-Deckel", fuel = "rocket-fuel", count = 5, ticks = 15 * 60, cap = true},
  {key = "disabled", label = "disabled_by_script", fuel = "coal", count = 10, ticks = 5 * 60, disabled = true}
}
local T2_SAMPLES = {[5 * 60] = "s5", [10 * 60] = "s10", [15 * 60] = "s15"}
local T2_PAUSE = 30            -- Ticks zwischen zwei Durchgängen
local T2_PROBE = 60            -- nach so vielen Ticks muss die Skriptfahrt etwas bewegt haben
local T2_CAP = 1.5             -- Tempo-Deckel (Kacheln/s), Design 4.1
local T2_CAP_MARGIN = 0.1      -- Kriterium: Höchsttempo ≤ Deckel + 0.1 (bei 1.5 also ≤ 1.6)
local T2_CAP_FACTOR = 0.7      -- Ersatzdeckel: 70 % des Höchsttempos ohne Deckel
local T2_MANUAL_LEAD = 5 * 60  -- Vorlauf, bis Max nach dem Umschalten W drückt
local T2_ORIENTATION = 0.25    -- Osten

-- Gas geben (oder nicht): riding_state am Fahrzeug und, falls vorhanden, am Dummy-Fahrer.
-- Laut API ist riding_state am Fahrer derselbe Zustand wie am Fahrzeug, in dem er sitzt.
local function t2_drive(run, tb, car, acceleration)
  local d = run.data
  local state = {acceleration = acceleration, direction = defines.riding.direction.straight}
  local on_car, car_err = pcall(function() car.riding_state = state end)
  local on_driver, driver_err = false, "kein Dummy-Fahrer"
  local driver = d.driver
  if driver and driver.valid then
    on_driver, driver_err = pcall(function() driver.riding_state = state end)
  end
  if not d.drive_logged then
    d.drive_logged = true
    tb.log(run, "INFO", "riding_state gesetzt: am Fahrzeug " .. (on_car and "ja" or ("nein (" .. tostring(car_err) .. ")"))
      .. ", am Dummy-Fahrer " .. (on_driver and "ja" or ("nein (" .. tostring(driver_err) .. ")")))
  end
  if not (on_car or on_driver) and not d.drive_error_logged then
    d.drive_error_logged = true
    tb.log(run, "FEHLER", "riding_state lässt sich weder am Fahrzeug noch am Fahrer setzen")
  end
end

local function t2_stop(run, car)
  if not (car and car.valid) then return end
  if not run.data.manual then
    pcall(function()
      car.riding_state = {acceleration = defines.riding.acceleration.nothing, direction = defines.riding.direction.straight}
    end)
  end
  pcall(function() car.speed = 0 end)
end

-- Position, Tempo, Ausrichtung, Brennstoff und Brenner zurücksetzen. Gibt den Brennerzustand danach zurück.
local function t2_reset(run, tb, car)
  local d = run.data
  pcall(function() car.speed = 0 end)
  local ok, moved = pcall(function() return car.teleport(d.start) end)
  if not (ok and moved) then
    tb.log(run, "INFO", "Position zurücksetzen ging nicht: " .. result_text(ok, moved))
  end
  pcall(function() car.orientation = T2_ORIENTATION end)
  pcall(function() car.speed = 0 end)
  local inventory = car.get_fuel_inventory()
  if inventory then inventory.clear() end
  local burner = car.burner
  if not burner then return "kein Brenner" end
  local notes = {}
  local ok_burning, err_burning = pcall(function() burner.currently_burning = nil end)
  if not ok_burning then table.insert(notes, "currently_burning nicht schreibbar: " .. tostring(err_burning)) end
  local ok_heat, err_heat = pcall(function() burner.heat = 0 end)
  if not ok_heat then table.insert(notes, "heat nicht schreibbar: " .. tostring(err_heat)) end
  local text = burner_text(tb, burner)
  if #notes > 0 then text = text .. " (" .. table.concat(notes, "; ") .. ")" end
  return text
end

-- Deckel für den Deckel-Durchgang: 1.5, wenn der Ernter ohne Deckel schneller als 1.6 fuhr,
-- sonst 70 % des bisherigen Höchsttempos (auf 0.1 abgerundet, mindestens 0.2). Gibt Deckel und Grund zurück.
local function t2_cap(run)
  local natural = 0
  for _, key in ipairs({"coal", "solid", "rocket"}) do
    local earlier = run.data.results[key]
    if earlier and earlier.max > natural then natural = earlier.max end
  end
  if natural > T2_CAP + T2_CAP_MARGIN then
    return T2_CAP, "Höchsttempo ohne Deckel " .. string.format("%.2f", natural) .. " > 1.6"
  end
  local cap = math.max(0.2, math.floor(natural * T2_CAP_FACTOR * 10) / 10)
  return cap, "Ersatzdeckel: Höchsttempo ohne Deckel nur " .. string.format("%.2f", natural)
    .. " Kacheln/s, 1.5 würde nie greifen"
end

local function t2_begin_pass(run, tb)
  local d = run.data
  local pass = T2_PASSES[d.pass]
  local car = d.car
  local burner_after_reset = t2_reset(run, tb, car)
  local inserted = tb.fuel(car, pass.fuel, pass.count)
  local cap_text = ""
  if pass.cap then
    local reason
    d.cap, reason = t2_cap(run)
    cap_text = string.format(", Deckel %s Kacheln/s (%s)", tb.num(d.cap), reason)
  end
  tb.log(run, "INFO", string.format("Durchgang %d/%d: %s, %d %s eingelegt, %d s Gas%s%s. Brenner nach Reset: %s",
    d.pass, #T2_PASSES, pass.label, inserted, pass.fuel, math.floor(pass.ticks / 60),
    d.manual and " (manuell: W halten)" or "", cap_text, burner_after_reset))
  if inserted == 0 then
    tb.log(run, "FEHLER", pass.fuel .. " ließ sich nicht ins Brennstoffinventar legen (Brennstoffkategorie?)")
  end
  if pass.disabled then
    local ok, err = pcall(function() car.disabled_by_script = true end)
    d.disabled_set = true
    local ok_read, now = pcall(function() return car.disabled_by_script end)
    tb.log(run, ok and "MESSUNG" or "FEHLER", "disabled_by_script = true " .. (ok and "gesetzt" or ("ging nicht: " .. tostring(err)))
      .. ", Lesewert " .. (ok_read and tostring(now) or ("Fehler: " .. tostring(now))))
  end
  d.pass_pos = copy_pos(car.position)
  d.pass_start = game.tick
  d.cur = {max = 0, cap_resets = 0}
  d.phase = "pass"
  if not d.manual then
    t2_drive(run, tb, car, defines.riding.acceleration.accelerating)
  end
end

-- OK/FEHLER eines Durchgangs; "–" ohne Durchgang, "?" wenn nicht aussagekräftig.
local function t2_verdict(result)
  if not result then return "–" end
  if result.ok == nil then return "?" end
  return result.ok and "OK" or "FEHLER"
end

local function t2_summary(run, tb)
  local d = run.data
  local r = d.results
  local parts = {}
  if d.manual then
    table.insert(parts, "Skriptfahrt nein (manuell gemessen)")
  elseif d.probed then
    table.insert(parts, d.script_failed and "Skriptfahrt nein" or "Skriptfahrt ja")
  else
    table.insert(parts, "Skriptfahrt ungeprüft")
  end
  table.insert(parts, string.format("max Kohle %s / Festbrennstoff %s / Raketentreibstoff %s Kacheln/s",
    tb.num(r.coal and r.coal.max), tb.num(r.solid and r.solid.max), tb.num(r.rocket and r.rocket.max)))
  table.insert(parts, "Deckel " .. (r.cap and r.cap.cap and (tb.num(r.cap.cap) .. " ") or "") .. t2_verdict(r.cap))
  table.insert(parts, "Sperre " .. t2_verdict(r.disabled))
  table.insert(parts, "Status " .. (d.status_ok == nil and "–" or (d.status_ok and "OK" or "FEHLER")))
  return table.concat(parts, ", ")
end

-- Ende: Fahrer raus, Ernter „aufgebaut“ (nicht abbaubar, Status) stehen lassen, FRAGE an Max.
local function t2_final(run, tb)
  local d = run.data
  d.phase = "done"
  local r = d.results
  if r.coal or r.solid or r.rocket then
    tb.log(run, "MESSUNG", string.format("Höchsttempo je Brennstoff: Kohle %s, Festbrennstoff %s, Raketentreibstoff %s Kacheln/s (Ziel mit Kohle etwa 1.5, Design höchstens 1.5)",
      tb.num(r.coal and r.coal.max), tb.num(r.solid and r.solid.max), tb.num(r.rocket and r.rocket.max)))
  end
  local car = d.car
  if not (car and car.valid) then
    tb.log(run, "FEHLER", "Der Ernter ist nicht mehr da, Status-Teil entfällt.")
    tb.finish(run, t2_summary(run, tb))
    return
  end
  t2_stop(run, car)
  pcall(function() car.set_driver(nil) end)
  if d.driver and d.driver.valid then d.driver.destroy() end
  d.driver = nil
  if d.manual then
    tb.log(run, "INFO", "W loslassen: Messung fertig, du bist ausgestiegen.")
  end

  local ok_flag, err_flag = pcall(function() car.minable_flag = false end)
  if ok_flag then
    local ok_read, text = pcall(function()
      return "minable_flag " .. tostring(car.minable_flag) .. ", minable " .. tostring(car.minable)
    end)
    tb.log(run, "MESSUNG", "minable_flag = false gesetzt; Lesewerte: " .. (ok_read and text or ("Fehler: " .. tostring(text))))
  else
    tb.log(run, "FEHLER", "minable_flag = false ging nicht: " .. tostring(err_flag))
  end

  local ok_status, err_status = pcall(function()
    car.custom_status = {diode = defines.entity_status_diode.yellow, label = "Prüfstand: aufgebaut"}
  end)
  d.status_ok = ok_status
  if ok_status then
    local ok_read, text = pcall(function()
      local status = car.custom_status
      if not status then return "Lesewert nil" end
      local label = type(status.label) == "string" and status.label or "(kein einfacher Text)"
      return "Diode " .. tb.enum_name(defines.entity_status_diode, status.diode) .. ", Text „" .. label .. "“"
    end)
    tb.log(run, "OK", "custom_status gesetzt: " .. (ok_read and text or ("Lesen ging nicht: " .. tostring(text))))
  else
    tb.log(run, "FEHLER", "custom_status setzen ging nicht: " .. tostring(err_status))
  end

  tb.log(run, "FRAGE", "Öffne den Ernter: Steht ‚Prüfstand: aufgebaut‘ im Fenster? Lässt er sich abbauen (sollte nicht)?"
    .. " Der Ernter steht bei " .. pos_text(tb, car.position) .. ".")
  tb.finish(run, t2_summary(run, tb))
end

-- Saß Max (manueller Modus) im Ernter? Ohne manuellen Modus immer true.
local function t2_player_inside(run, tb)
  local d = run.data
  if not d.manual then return true end
  local player = tb.player(run)
  local vehicle = player and player.vehicle
  return vehicle and vehicle.valid and d.car and d.car.valid and vehicle.unit_number == d.car.unit_number or false
end

local function t2_end_pass(run, tb)
  local d = run.data
  local pass = T2_PASSES[d.pass]
  local car = d.car
  local cur = d.cur
  local moved = tb.distance(car.position, d.pass_pos)
  local inside = t2_player_inside(run, tb)
  t2_stop(run, car)
  local result = {max = cur.max, s5 = cur.s5, s10 = cur.s10, s15 = cur.s15, distance = moved, cap_resets = cur.cap_resets}
  if pass.disabled then
    pcall(function() car.disabled_by_script = false end)
    d.disabled_set = false
    tb.log(run, "MESSUNG", "disabled_by_script, 5 s Gas: Verschiebung " .. tb.num(moved, 2) .. " Kacheln, Höchsttempo "
      .. tb.num(cur.max, 2) .. " Kacheln/s")
    -- Aussagekräftig nur, wenn der Ernter vorher fahren konnte und (manuell) Max am Steuer saß.
    local could_move = false
    for _, key in ipairs({"coal", "solid", "rocket", "cap"}) do
      local earlier = d.results[key]
      if earlier and earlier.max >= 0.05 then could_move = true end
    end
    if could_move and inside then
      result.ok = moved < 0.1
      tb.log(run, result.ok and "OK" or "FEHLER", "Sperre hält: Verschiebung " .. tb.num(moved, 2)
        .. (result.ok and " < 0.1" or " ≥ 0.1") .. " Kacheln")
    else
      tb.log(run, "INFO", "Sperre nicht aussagekräftig: " .. (inside and "der Ernter fuhr in keinem Durchgang" or "du saßt nicht im Ernter"))
    end
    local ok_read, now = pcall(function() return car.disabled_by_script end)
    tb.log(run, "INFO", "disabled_by_script wieder false (Lesewert " .. (ok_read and tostring(now) or ("Fehler: " .. tostring(now))) .. ")")
  else
    tb.log(run, "MESSUNG", string.format("%s: Höchsttempo %s Kacheln/s; bei 5/10/15 s: %s / %s / %s Kacheln/s; Strecke %s Kacheln",
      pass.label, tb.num(cur.max), tb.num(cur.s5), tb.num(cur.s10), tb.num(cur.s15), tb.num(moved)))
    if not inside then
      tb.log(run, "INFO", pass.label .. ": du saßt am Ende nicht im Ernter, Werte nur bedingt brauchbar")
    end
    if pass.cap then
      local cap = d.cap or T2_CAP
      local limit = cap + T2_CAP_MARGIN
      result.cap = cap
      -- Effektives Tempo nach dem Anfahren (5 bis 15 s): so schnell kommt der Ernter mit Deckel wirklich voran.
      local seconds = (pass.ticks - 5 * 60) / 60
      local effective = cur.pos5 and seconds > 0 and tb.distance(car.position, cur.pos5) / seconds or nil
      tb.log(run, "MESSUNG", string.format("Tempo-Deckel %s: effektiv (Strecke 5–15 s) %s Kacheln/s, Höchsttempo zwischen zwei Rücksetzungen %s Kacheln/s",
        tb.num(cap), tb.num(effective, 2), tb.num(cur.max, 2)))
      if cur.max < 0.05 then
        tb.log(run, "INFO", "Tempo-Deckel nicht aussagekräftig: der Ernter fuhr nicht")
      elseif cur.cap_resets == 0 then
        -- Nie über dem Deckel: das Zurücksetzen von speed wurde gar nicht gebraucht, also nicht geprüft.
        tb.log(run, "INFO", string.format("Tempo-Deckel %s nicht gefordert: Höchsttempo %s Kacheln/s, speed nie zurückgesetzt",
          tb.num(cap), tb.num(cur.max, 2)))
      else
        result.ok = cur.max <= limit
        tb.log(run, result.ok and "OK" or "FEHLER", string.format("Tempo-Deckel %s: Höchsttempo %s Kacheln/s %s %s (speed %d-mal zurückgesetzt)",
          tb.num(cap), tb.num(cur.max, 2), result.ok and "≤" or ">", tb.num(limit), cur.cap_resets))
      end
    end
  end
  d.results[pass.key] = result
  d.pass = d.pass + 1
  if d.pass > #T2_PASSES then
    t2_final(run, tb)
  else
    d.phase = "wait"
    d.next_tick = game.tick + T2_PAUSE
  end
end

-- Skriptfahrt geht nicht: Max fährt selbst (gleiche Durchgänge, gleiche Messung).
local function t2_go_manual(run, tb, moved, speed)
  local d = run.data
  local car = d.car
  d.script_failed = true
  -- Brennt schon Treibstoff, kam das Gas an und nur die Physik bremst; sonst wirkt riding_state nicht.
  tb.log(run, "FEHLER", "Skriptfahrt geht nicht: nach 1 s " .. tb.num(moved, 2) .. " Kacheln, Tempo " .. tb.num(speed, 2)
    .. " Kacheln/s; Brenner: " .. burner_text(tb, car.burner))
  t2_stop(run, car)
  pcall(function() car.set_driver(nil) end)
  if d.driver and d.driver.valid then d.driver.destroy() end
  d.driver = nil
  local player = tb.player(run)
  local ok, err = false, "kein Spieler"
  if player and player.character then
    ok, err = pcall(function() car.set_driver(player) end)
  elseif player then
    err = "Spieler hat keine Spielfigur"
  end
  local seated = ok and car.get_driver() ~= nil
  if not seated then
    tb.log(run, "FEHLER", "Spieler als Fahrer setzen ging nicht: " .. (ok and "kein Fahrer danach" or tostring(err)))
    t2_final(run, tb)
    return
  end
  d.manual = true
  d.pass = 1
  d.phase = "wait"
  d.next_tick = game.tick + T2_MANUAL_LEAD
  tb.log(run, "FRAGE", "W gedrückt halten bis zur Meldung „W loslassen“. Du sitzt jetzt im Ernter; die Messung startet in "
    .. math.floor(T2_MANUAL_LEAD / 60) .. " s (manueller Modus, gleiche Messung).")
end

local function t2_start(run, tb)
  local d = run.data
  local origin = tb.area(run.id)
  tb.prepare(origin, {x = 170, y = 24})
  local surface = tb.surface()
  local start = {x = origin.x - 150, y = origin.y}
  local car = surface.create_entity{name = HARVESTER, position = start, force = force_of(run, tb), orientation = T2_ORIENTATION}
  if not car then
    tb.log(run, "FEHLER", "Ernter " .. HARVESTER .. " ließ sich nicht erzeugen")
    tb.finish(run, "abgebrochen (kein Ernter)")
    return
  end
  d.car = car
  d.start = copy_pos(car.position)
  d.results = {}
  local driver = tb.dummy_driver(car)
  d.driver = driver
  if not (driver and driver.valid and car.get_driver()) then
    tb.log(run, "INFO", "Dummy-Fahrer fehlt; riding_state wird nur am Fahrzeug gesetzt")
  end
  tb.watch(run, nil, {x = start.x + 10, y = start.y + 8})
  tb.log(run, "INFO", "Ernter bei " .. pos_text(tb, d.start) .. ", fährt nach Osten auf Sand (Bahn 300 Kacheln). "
    .. #T2_PASSES .. " Durchgänge, Dauer etwa 70 s.")
  d.pass = 1
  d.phase = "wait"
  d.next_tick = game.tick + T2_PAUSE
end

local function t2_tick(run, tb)
  local d = run.data
  if d.phase == "done" then return end
  local car = d.car
  if not (car and car.valid) then
    tb.log(run, "FEHLER", "Der Ernter ist nicht mehr da.")
    tb.finish(run, "abgebrochen (Ernter weg)")
    return
  end
  if d.phase == "wait" then
    if game.tick >= d.next_tick then t2_begin_pass(run, tb) end
    return
  end

  local pass = T2_PASSES[d.pass]
  local cur = d.cur
  local elapsed = game.tick - d.pass_start
  local speed = tb.speed_tps(car) or 0
  if speed > cur.max then cur.max = speed end
  local sample = T2_SAMPLES[elapsed]
  if sample then cur[sample] = speed end
  if sample == "s5" then cur.pos5 = copy_pos(car.position) end

  -- Deckel: alle 10 Ticks zurück auf den Deckel (Kacheln/s), wenn darüber.
  local cap = d.cap
  if pass.cap and cap and elapsed % 10 == 0 and speed > cap then
    local raw = car.speed or 0
    local ok = pcall(function() car.speed = (raw < 0 and -1 or 1) * cap / 60 end)
    if ok then cur.cap_resets = cur.cap_resets + 1 end
  end

  if not d.manual and not d.probed and elapsed >= T2_PROBE then
    d.probed = true
    local moved = tb.distance(car.position, d.pass_pos)
    if moved < 0.05 and speed < 0.01 then
      t2_go_manual(run, tb, moved, speed)
      return
    end
    tb.log(run, "OK", "Skriptfahrt geht: nach 1 s " .. tb.num(moved, 2) .. " Kacheln, Tempo " .. tb.num(speed, 2) .. " Kacheln/s")
  end

  if elapsed >= pass.ticks then
    t2_end_pass(run, tb)
    return
  end
  if not d.manual then
    t2_drive(run, tb, car, defines.riding.acceleration.accelerating)
  end
end

local function t2_on_event(run, tb, name, event)
  local d = run.data
  if name ~= "driving_changed" or not d.manual or d.phase == "done" then return end
  if event.player_index ~= run.player_index then return end
  local player = tb.player(run)
  local car = d.car
  local vehicle = player and player.vehicle
  local inside = car and car.valid and vehicle and vehicle.valid and vehicle.unit_number == car.unit_number
  if inside then
    tb.log(run, "INFO", "Wieder im Ernter.")
  else
    tb.log(run, "INFO", "Du bist ausgestiegen – bitte wieder in den Ernter (Enter) und W halten.")
  end
end

local function t2_cleanup(run, tb)
  local d = run.data
  local car = d.car
  if not (car and car.valid) then return end
  if d.disabled_set then
    pcall(function() car.disabled_by_script = false end)
    d.disabled_set = false
  end
  if d.phase ~= "done" then t2_stop(run, car) end
end

-- T3 Teleport zur Ablage -----------------------------------------------------------------------
-- Ein voll ausgestatteter Ernter wird mit und ohne Fahrer auf die versteckte Ablage-Oberfläche
-- teleportiert und zurück; der Zustand wird je Feld mit dem Vorher-Datensatz verglichen.

local T3_STEP = 30
local T3_ORIENTATION = 0.375

-- Felder des Zustandsvergleichs. tolerance für Zahlen, kilo = Anzeige in kJ.
-- unsupported = Schlüssel in run.data: ist er gesetzt, kann das Auto das Feld nicht tragen (nur INFO, nicht gezählt).
local T3_FIELDS =
{
  {key = "trunk", label = "Kofferraum"},
  {key = "fuel", label = "Treibstoff"},
  {key = "remaining", label = "Restbrennwert", tolerance = 1, kilo = true},
  {key = "burning", label = "brennendes Item"},
  {key = "health", label = "Gesundheit", tolerance = 0.01},
  {key = "quality", label = "Qualität"},
  {key = "label", label = "Label", unsupported = "label_unsupported"},
  {key = "color", label = "Farbe"},
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
  local same, compared, equal_labels, skipped = 0, 0, {}, {}
  for _, field in ipairs(T3_FIELDS) do
    local a, b = before[field.key], after[field.key]
    if field.unsupported and run.data[field.unsupported] then
      table.insert(skipped, field.label)
    elseif t3_same(field, a, b) then
      compared = compared + 1
      same = same + 1
      if per_field then
        tb.log(run, level_same, prefix .. field.label .. " gleich: " .. t3_value_text(tb, field, b))
      else
        table.insert(equal_labels, field.label)
      end
    else
      compared = compared + 1
      tb.log(run, level_diff, prefix .. field.label .. " vorher " .. t3_value_text(tb, field, a)
        .. ", jetzt " .. t3_value_text(tb, field, b))
    end
  end
  if not per_field and #equal_labels > 0 then
    tb.log(run, level_same, prefix .. "gleich: " .. table.concat(equal_labels, ", "))
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
  return string.format("a) mit Fahrer: %s; b) Ablage %s/%s gleich, zurück %s/%s gleich; c) Klon %s/%s gleich",
    d.a_result or "–", count_text(d.b_hold_same), count_text(d.b_hold_total or #T3_FIELDS), count_text(d.b_back_same),
    count_text(d.b_back_total or #T3_FIELDS), count_text(d.c_same), count_text(d.c_total or #T3_FIELDS))
end

local t3_steps = {}

-- a) Teleport mit Dummy-Fahrer.
t3_steps[1] = function(run, tb)
  local d = run.data
  local car = t3_car(run, tb)
  if not car then return false end
  local hold = t3_hold(run, tb)
  if not hold then return false end
  local driver = tb.dummy_driver(car)
  d.driver = driver
  local seated = driver and driver.valid and car.get_driver() ~= nil
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
t3_steps[2] = function(run, tb)
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
t3_steps[3] = function(run, tb)
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
t3_steps[4] = function(run, tb)
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
t3_steps[5] = function(run, tb)
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
t3_steps[6] = function(run, tb)
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
  local ok_color, err_color = pcall(function() car.color = {r = 0.2, g = 0.7, b = 1, a = 1} end)
  if not ok_color then tb.log(run, "INFO", "Farbe setzen ging nicht: " .. tostring(err_color)) end
  pcall(function() car.orientation = T3_ORIENTATION end)

  d.before = t3_snapshot(car)
  tb.log(run, "INFO", string.format("Aufbau: Qualität %s, Kofferraum %d Spice-Sand, %d Eisenplatten, %d Eisenplatten rare; %d Kohle",
    d.before.quality, n_spice, n_iron, n_rare, n_coal))
  tb.log(run, "MESSUNG", "Vorher: " .. t3_snapshot_text(tb, d.before))
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

-- T4 Annahme und Tankstutzen -------------------------------------------------------------------
-- Felsquadrat 24×24 in Sand. Bauregel der Annahme prüfen, dann Aufbau (Koordinaten relativ zur Mitte o):
--   Annahme 2×2 bei o, Greifarm 1 bei o+(1.5, -0.5) → Kiste bei o+(2.5, -0.5)
--   Kohlekiste o+(-1.5, 3.5) → Greifarm 2 o+(-0.5, 3.5) → Tankstutzen o+(0.5, 3.5)
--   Mast o+(0.5, 1.5) (Versorgung ±3.5), Energie-Schnittstelle o+(3, 3), Rechenkombinator o+(-2.5, 0),
--   Ernter o+(0, -6).

local T4_ROCK_HALF = 12
local T4_RUN = 60 * 60
local T4_AFTER = 10 * 60

-- Greifarm von from nach to: die Richtung wählen, bei der Aufnahme bei from und Ablage bei to liegt.
local function t4_inserter(surface, force, position, from, to, tb)
  local directions = {defines.direction.east, defines.direction.west, defines.direction.north, defines.direction.south}
  for _, direction in ipairs(directions) do
    local inserter = surface.create_entity{name = "inserter", position = position, direction = direction, force = force}
    if inserter then
      local drop, pickup = inserter.drop_position, inserter.pickup_position
      if tb.distance(drop, to.position) < tb.distance(drop, from.position)
        and tb.distance(pickup, from.position) < tb.distance(pickup, to.position) then
        return inserter
      end
      inserter.destroy()
    end
  end
  return nil
end

local function t4_inserter_text(tb, inserter)
  local ok, text = pcall(function()
    local pickup, drop = inserter.pickup_target, inserter.drop_target
    return "nimmt bei " .. pos_text(tb, inserter.pickup_position) .. " (" .. (pickup and pickup.name or "–") .. "), legt bei "
      .. pos_text(tb, inserter.drop_position) .. " (" .. (drop and drop.name or "–") .. ")"
  end)
  return ok and text or ("nicht lesbar: " .. tostring(text))
end

local function t4_signal(d)
  local combinator = d.combinator
  if not (combinator and combinator.valid) then return nil, "Kombinator fehlt" end
  local ok, value = pcall(function()
    return combinator.get_signal({type = "item", name = "spice-sand"}, defines.wire_connector_id.combinator_input_red)
  end)
  if ok then return value end
  return nil, tostring(value)
end

local function held_count(inserter, item)
  if not (inserter and inserter.valid) then return 0 end
  local ok, count = pcall(function()
    local stack = inserter.held_stack
    if stack and stack.valid_for_read and stack.name == item then return stack.count end
    return 0
  end)
  return ok and count or 0
end

-- Bauregel: can_place_entity mit build_check_type manual an drei Stellen.
local function t4_checks(run, tb)
  local d = run.data
  local surface = tb.surface()
  local ox, oy = d.origin.x, d.origin.y
  local force = force_of(run, tb)
  local cases =
  {
    {label = "Felsmitte", position = {x = ox, y = oy}, expected = true},
    {label = "3 Kacheln vom Felsrand (Ring enthält Sand)", position = {x = ox + T4_ROCK_HALF - 3, y = oy}, expected = false},
    {label = "auf Sand", position = {x = ox + 30, y = oy}, expected = false}
  }
  d.rule_ok = 0
  local script_results = {}
  for _, case in ipairs(cases) do
    local ok, result = pcall(function()
      return surface.can_place_entity{name = INTAKE, position = case.position, force = force,
        build_check_type = defines.build_check_type.manual}
    end)
    if not ok then
      tb.log(run, "FEHLER", "Bauregel " .. case.label .. ": can_place_entity ging nicht: " .. tostring(result))
    else
      local good = result == case.expected
      if good then d.rule_ok = d.rule_ok + 1 end
      tb.log(run, good and "OK" or "FEHLER", "Bauregel " .. case.label .. " " .. pos_text(tb, case.position)
        .. ": can_place_entity = " .. tostring(result) .. " (erwartet " .. tostring(case.expected) .. ")")
    end
    -- Zum Vergleich dieselbe Stelle mit build_check_type script (nur INFO).
    local ok_script, result_script = pcall(function()
      return surface.can_place_entity{name = INTAKE, position = case.position, force = force,
        build_check_type = defines.build_check_type.script}
    end)
    table.insert(script_results, case.label .. " " .. (ok_script and tostring(result_script) or "Fehler"))
  end
  tb.log(run, "INFO", "Zum Vergleich mit build_check_type script: " .. table.concat(script_results, "; "))
  -- Gegenprobe: Tankstutzen ohne Bauregel auf Sand muss gehen, sonst sagen die false-Werte nichts.
  local ok, result = pcall(function()
    return surface.can_place_entity{name = NOZZLE, position = {x = ox + 30.5, y = oy + 4.5}, force = force,
      build_check_type = defines.build_check_type.manual}
  end)
  tb.log(run, "MESSUNG", "Gegenprobe Tankstutzen (ohne Bauregel) auf Sand: can_place_entity = "
    .. (ok and tostring(result) or ("Fehler: " .. tostring(result))))
  if not (ok and result == true) then
    tb.log(run, "INFO", "Gegenprobe nicht true: die false-Ergebnisse der Bauregel sind nicht aussagekräftig")
  end
end

-- Aufbau. Gibt false zurück, wenn etwas Wesentliches fehlt.
local function t4_build(run, tb)
  local d = run.data
  local surface = tb.surface()
  local ox, oy = d.origin.x, d.origin.y
  local force = force_of(run, tb)
  local missing = {}
  local function make(params)
    params.force = force
    local ok, entity = pcall(function() return surface.create_entity(params) end)
    if ok and entity then return entity end
    table.insert(missing, params.name)
    tb.log(run, "FEHLER", "Aufbau: " .. params.name .. " bei " .. pos_text(tb, params.position) .. " ging nicht"
      .. (ok and "" or (": " .. tostring(entity))))
    return nil
  end

  d.power = make{name = "electric-energy-interface", position = {x = ox + 3, y = oy + 3}}
  d.pole = make{name = "medium-electric-pole", position = {x = ox + 0.5, y = oy + 1.5}}
  d.intake = make{name = INTAKE, position = {x = ox, y = oy}}
  d.chest = make{name = "wooden-chest", position = {x = ox + 2.5, y = oy - 0.5}}
  d.coal_chest = make{name = "wooden-chest", position = {x = ox - 1.5, y = oy + 3.5}}
  d.nozzle = make{name = NOZZLE, position = {x = ox + 0.5, y = oy + 3.5}}
  d.combinator = make{name = "arithmetic-combinator", position = {x = ox - 2.5, y = oy}, direction = defines.direction.north}
  d.harvester = make{name = HARVESTER, position = {x = ox, y = oy - 6}, orientation = 0.25}
  if #missing > 0 then return false end

  d.inserter_out = t4_inserter(surface, force, {x = ox + 1.5, y = oy - 0.5}, d.intake, d.chest, tb)
  d.inserter_fuel = t4_inserter(surface, force, {x = ox - 0.5, y = oy + 3.5}, d.coal_chest, d.nozzle, tb)
  if not (d.inserter_out and d.inserter_fuel) then
    tb.log(run, "FEHLER", "Aufbau: Greifarm ließ sich in keiner Richtung passend setzen")
    return false
  end
  tb.log(run, "MESSUNG", "Greifarm 1 (Annahme → Kiste) " .. t4_inserter_text(tb, d.inserter_out))
  tb.log(run, "MESSUNG", "Greifarm 2 (Kohlekiste → Tankstutzen) " .. t4_inserter_text(tb, d.inserter_fuel))

  local coal = d.coal_chest.get_inventory(defines.inventory.chest).insert{name = "coal", count = 100}
  local spice = d.harvester.get_inventory(defines.inventory.car_trunk).insert{name = "spice-sand", count = 400}
  tb.log(run, "INFO", "Kohlekiste " .. coal .. " Kohle, Ernter-Kofferraum " .. spice .. " Spice-Sand, Ernter-Treibstoff leer")

  -- Ziele per Skript: Annahme → Kofferraum, Tankstutzen → Treibstoff.
  local targets =
  {
    {entity = d.intake, label = "Annahme", inventory = defines.inventory.car_trunk, inventory_name = "car_trunk"},
    {entity = d.nozzle, label = "Tankstutzen", inventory = defines.inventory.fuel, inventory_name = "fuel"}
  }
  for _, target in ipairs(targets) do
    local ok, err = pcall(function()
      target.entity.proxy_target_entity = d.harvester
      target.entity.proxy_target_inventory = target.inventory
    end)
    if ok then
      -- Inventar als Zahl: defines.inventory hat mehrere Namen je Wert, Rückübersetzen wäre mehrdeutig.
      local ok_read, text = pcall(function()
        local now = target.entity.proxy_target_entity
        local index = target.entity.proxy_target_inventory
        return "Ziel " .. (now and (now.name .. " Nr. " .. tostring(now.unit_number)) or "nil") .. ", Inventar "
          .. tostring(index) .. (index == target.inventory and " (passt)" or (" (erwartet " .. tostring(target.inventory) .. ")"))
      end)
      tb.log(run, "MESSUNG", target.label .. " → Ernter (" .. target.inventory_name .. "): " .. (ok_read and text or ("Lesen ging nicht: " .. tostring(text))))
    else
      tb.log(run, "FEHLER", target.label .. ": Ziel setzen ging nicht: " .. tostring(err))
    end
  end

  -- Inhalt der Annahme an die Schaltung melden (Standard laut API: true).
  local ok_cb, cb_text = pcall(function()
    local behavior = d.intake.get_or_create_control_behavior()
    if not behavior then return "keine Steuerung" end
    local before = behavior.read_contents
    if before == false then behavior.read_contents = true end
    return "read_contents " .. tostring(before) .. (before == false and " → true gesetzt" or "")
  end)
  tb.log(run, "INFO", "Annahme Schaltung: " .. (ok_cb and cb_text or ("nicht lesbar: " .. tostring(cb_text))))

  -- Roter Draht Annahme → Kombinator-Eingang, per Skript (unsichtbar, falls wire_origin.script existiert).
  local ok_wire, connected, origin_name = pcall(function()
    local from = d.intake.get_wire_connector(defines.wire_connector_id.circuit_red, true)
    local to = d.combinator.get_wire_connector(defines.wire_connector_id.combinator_input_red, true)
    local script_origin = defines.wire_origin and defines.wire_origin.script
    if script_origin then
      return from.connect_to(to, false, script_origin), "script"
    end
    return from.connect_to(to, false), "Standard"
  end)
  if ok_wire then
    d.wire_origin = origin_name
    tb.log(run, connected and "MESSUNG" or "FEHLER", "Roter Draht Annahme → Kombinator-Eingang (Ursprung " .. tostring(origin_name)
      .. "): verbunden " .. tostring(connected))
  else
    tb.log(run, "FEHLER", "Roter Draht ging nicht: " .. tostring(connected))
  end
  return true
end

local function t4_measure(run, tb)
  local d = run.data
  local chest = count_in(d.chest, defines.inventory.chest, "spice-sand")
  local fuel = count_in(d.harvester, defines.inventory.fuel, "coal")
  local trunk = count_in(d.harvester, defines.inventory.car_trunk, "spice-sand")
  local coal_left = count_in(d.coal_chest, defines.inventory.chest, "coal")
  local signal, signal_err = t4_signal(d)
  local ok_power, power = pcall(function()
    return tostring(d.inserter_out.is_connected_to_electric_network()) .. "/" .. tostring(d.inserter_fuel.is_connected_to_electric_network())
  end)
  tb.log(run, "MESSUNG", string.format("Nach 60 s: Spice-Sand in der Kiste %s, Kohle im Ernter-Brennstoff %s, Signal spice-sand am Kombinator-Eingang %s"
    .. " (Kofferraum noch %s, Kohlekiste noch %s, Greifarme mit Strom %s)",
    count_text(chest), count_text(fuel), signal and tostring(signal) or ("– " .. tostring(signal_err)),
    count_text(trunk), count_text(coal_left), ok_power and power or "?"))
  d.chest_ok = (chest or 0) > 0
  d.fuel_ok = (fuel or 0) > 0
  d.signal_ok = (signal or 0) > 0
  tb.log(run, d.chest_ok and "OK" or "FEHLER", "Greifarm holt über die Annahme aus dem Kofferraum: Kiste " .. count_text(chest))
  tb.log(run, d.fuel_ok and "OK" or "FEHLER", "Greifarm füllt über den Tankstutzen den Ernter-Treibstoff: " .. count_text(fuel) .. " Kohle")
  tb.log(run, d.signal_ok and "OK" or "FEHLER", "Schaltungssignal spice-sand vorhanden: " .. (signal and tostring(signal) or ("– " .. tostring(signal_err))))
  if signal and trunk then
    tb.log(run, "INFO", "Signal " .. (signal == trunk and "=" or "≠") .. " Kofferraum (" .. signal .. " / " .. trunk .. ")")
  end
  d.measured = {chest = chest, fuel = fuel, signal = signal}

  -- Ziele lösen.
  local parts = {}
  for _, entry in ipairs({{d.intake, "Annahme"}, {d.nozzle, "Tankstutzen"}}) do
    local entity, label = entry[1], entry[2]
    local ok, err = pcall(function() entity.proxy_target_entity = nil end)
    local ok_read, now = pcall(function() return entity.proxy_target_entity end)
    if ok then
      table.insert(parts, label .. " Lesewert " .. (ok_read and (now and now.name or "nil") or ("Fehler: " .. tostring(now))))
    else
      tb.log(run, "FEHLER", label .. ": proxy_target_entity = nil ging nicht: " .. tostring(err))
    end
  end
  tb.log(run, "MESSUNG", "proxy_target_entity = nil gesetzt: " .. table.concat(parts, ", "))
  d.detach = {chest = chest or 0, hand = held_count(d.inserter_out, "spice-sand"), fuel = fuel or 0}
end

local function t4_after(run, tb)
  local d = run.data
  local chest = count_in(d.chest, defines.inventory.chest, "spice-sand")
  local fuel = count_in(d.harvester, defines.inventory.fuel, "coal")
  local signal, signal_err = t4_signal(d)
  local detach = d.detach
  tb.log(run, "MESSUNG", string.format("10 s nach dem Lösen: Kiste %s (beim Lösen %d, dazu %d in der Greifarm-Hand), Ernter-Brennstoff %s (beim Lösen %d), Signal %s",
    count_text(chest), detach.chest, detach.hand, count_text(fuel), detach.fuel,
    signal and tostring(signal) or ("– " .. tostring(signal_err))))
  if chest == detach.chest then
    d.after_ok = true
    tb.log(run, "OK", "Kistenstand unverändert (" .. chest .. ")")
  elseif chest and chest <= detach.chest + detach.hand then
    d.after_ok = true
    tb.log(run, "OK", "Kistenstand unverändert bis auf " .. (chest - detach.chest) .. " Stück aus der Greifarm-Hand (" .. chest .. ")")
  else
    d.after_ok = false
    tb.log(run, "FEHLER", "Kistenstand nach dem Lösen verändert: " .. detach.chest .. " → " .. count_text(chest))
  end
  tb.log(run, "FRAGE", "Siehst du den roten Draht zwischen Annahme und Kombinator? Kannst du ihn entfernen?"
    .. " (Annahme = orange 2×2-Kiste in der Felsmitte, Kombinator links daneben; Draht per Skript, Ursprung "
    .. tostring(d.wire_origin or "–") .. ")")
  local m = d.measured or {}
  tb.finish(run, string.format("Bauregel %d/3 wie erwartet; Kiste %s %s, Brennstoff %s %s, Signal %s %s; nach dem Lösen %s",
    d.rule_ok or 0, count_text(m.chest), d.chest_ok and "OK" or "FEHLER", count_text(m.fuel), d.fuel_ok and "OK" or "FEHLER",
    count_text(m.signal), d.signal_ok and "OK" or "FEHLER", d.after_ok and "OK" or "FEHLER"))
end

local function t4_start(run, tb)
  local d = run.data
  local origin = tb.area(run.id)
  local ox, oy = origin.x, origin.y
  tb.prepare(origin, 40)
  local tiles = tb.fill({{ox - T4_ROCK_HALF, oy - T4_ROCK_HALF}, {ox + T4_ROCK_HALF, oy + T4_ROCK_HALF}}, "arrakis-rock", tb.surface())
  d.origin = {x = ox, y = oy}
  tb.watch(run, nil, {x = ox, y = oy + 9})
  tb.log(run, "INFO", "Felsquadrat 24×24 (" .. tiles .. " Kacheln arrakis-rock) in Sand bei " .. pos_text(tb, d.origin)
    .. "; Bauregel-Prüfung und Aufbau in 0.5 s, dann 60 s Betrieb")
  d.step = "check"
  d.next_tick = game.tick + 30
end

local function t4_tick(run, tb)
  local d = run.data
  if not d.step or game.tick < d.next_tick then return end
  if d.step == "check" then
    t4_checks(run, tb)
    if not t4_build(run, tb) then
      tb.finish(run, "abgebrochen (Aufbau fehlgeschlagen); Bauregel " .. (d.rule_ok or 0) .. "/3 wie erwartet")
      return
    end
    tb.log(run, "INFO", "Aufbau fertig, läuft 60 s")
    d.step = "measure"
    d.next_tick = game.tick + T4_RUN
  elseif d.step == "measure" then
    t4_measure(run, tb)
    d.step = "after"
    d.next_tick = game.tick + T4_AFTER
  elseif d.step == "after" then
    d.step = nil
    t4_after(run, tb)
  end
end

return
{
  T2 =
  {
    title = "Ernter: Skriptfahrt, Tempo, Sperre, Status",
    timeout = 120 * 60,
    interactive = false,
    confirm = nil,
    answer_time = 30 * 60, -- bei „alle“: Zeit, den Ernter zu öffnen (FRAGE am Ende)
    start = t2_start,
    tick = t2_tick,
    on_event = t2_on_event,
    cleanup = t2_cleanup
  },
  T3 =
  {
    title = "Ernter: Teleport zur Ablage",
    timeout = 30 * 60,
    interactive = false,
    confirm = nil,
    start = t3_start,
    tick = t3_tick,
    cleanup = t3_cleanup
  },
  T4 =
  {
    title = "Annahme und Tankstutzen",
    timeout = 100 * 60,
    interactive = false,
    confirm = nil,
    answer_time = 30 * 60, -- bei „alle“: Zeit, den Draht anzusehen (FRAGE am Ende)
    start = t4_start,
    tick = t4_tick
  }
}
