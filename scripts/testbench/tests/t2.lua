-- T2 Ernter: Skriptfahrt, Tempo, Sperre, Status: Prüfstand-Test (aus t_harvester.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_harvester.lua.

local common = require("scripts.testbench.gemeinsam_harvester")
local HARVESTER = common.HARVESTER
local force_of = common.force_of
local copy_pos = common.copy_pos
local pos_text = common.pos_text
local result_text = common.result_text
local item_pair_name = common.item_pair_name

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

-- T2 Ernter-Fahrzeug ----------------------------------------------------------------------------
-- Ein Ernter mit Dummy-Fahrer fährt auf einer 300 Kacheln langen Sandbahn nach Osten. Je Durchgang:
-- Position, Tempo und Brenner zurücksetzen, Brennstoff einlegen, Gas geben (riding_state jeden Tick).

-- Deckel-Durchgang: mit Raketentreibstoff (schnellster Brennstoff, der Fall, für den der Deckel gedacht ist).
-- Der Deckel ist 1.5 Kacheln/s, wenn der Ernter ohne Deckel schneller als 1.6 fuhr; sonst 70 % seines
-- Höchsttempos, damit der Deckel wirklich greifen muss (siehe t2_cap).
-- Die Frage aus 3a (reicht Rücksetzen alle 10 Ticks?) ist seit 0.4.0 beantwortet: nein. Der echte Ernter
-- deckelt jeden Tick (T2b zählt seine Eingriffe). Der Durchgang wird deshalb nur noch gemessen, ohne OK/FEHLER.
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
local T2_CAP_MARGIN = 0.1      -- Vergleichswert der Messung: Deckel + 0.1 (bei 1.5 also 1.6); auch Grenze für den Ersatzdeckel
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

-- Deckel-Durchgang für die Kurzfassung (nur Messung, siehe T2_PASSES).
local function t2_cap_text(tb, result)
  if not result then return "Deckel –" end
  local cap = result.cap and (tb.num(result.cap) .. " ") or ""
  if result.max < 0.05 then return "Deckel " .. cap .. "nicht aussagekräftig" end
  if result.cap_resets == 0 then return "Deckel " .. cap .. "nicht gefordert" end
  return "Deckel " .. cap .. "alle 10 Ticks: Spitze " .. tb.num(result.max, 2) .. " (Messung)"
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
  table.insert(parts, t2_cap_text(tb, r.cap))
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
        -- Nur Messung (siehe T2_PASSES): result.ok bleibt nil, der Durchgang zählt weder OK noch FEHLER.
        tb.log(run, "MESSUNG", string.format("Tempo-Deckel %s, Rücksetzen alle 10 Ticks: Höchsttempo %s Kacheln/s %s %s (speed %d-mal zurückgesetzt)",
          tb.num(cap), tb.num(cur.max, 2), cur.max <= limit and "≤" or ">", tb.num(limit), cur.cap_resets))
        tb.log(run, "INFO", "Tempo-Deckel alle 10 Ticks: seit 0.4.0 bekannt, dass das nicht reicht (2.0.77: Spitze 1.82 > 1.6 mit Raketentreibstoff)"
          .. (cur.max <= limit and "; diesmal blieb die Spitze darunter." or ", diesmal wieder darüber.")
          .. " Der echte Ernter deckelt deshalb jeden Tick; T2b zählt seine Eingriffe. Hier nur Messung, kein FEHLER.")
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
  -- Start ohne Spieler (Serverkonsole, RCON): keine Handfahrt möglich, gleich auswerten.
  if not player then
    tb.log(run, "FEHLER", "Manuelle Messung entfällt: kein Spieler im Spiel (Start ohne Spieler)")
    t2_final(run, tb)
    return
  end
  local ok, err = false, "Spieler hat keine Spielfigur"
  if player.character then
    ok, err = pcall(function() car.set_driver(player) end)
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
  }
}
