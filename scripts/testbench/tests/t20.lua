-- T20 Würmer: Bedienung: Prüfstand-Test (aus t_jagd.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_jagd.lua.

local common = require("scripts.testbench.gemeinsam_jagd")
local harvester = require("scripts.harvester")
local terrain = require("scripts.terrain")
local vibration_lib = require("scripts.vibration")
local worms_lib = require("scripts.worms")
local HARVESTER = common.HARVESTER
local FLYER = common.FLYER
local ROCK = common.ROCK
local SAND = common.SAND
local GRACE_ORNITHOPTER = common.GRACE_ORNITHOPTER
local valid = common.valid
local read = common.read
local copy = common.copy
local box_of = common.box_of
local tiles = common.tiles
local storage_ready = common.storage_ready
local clear_area = common.clear_area
local hunt_list = common.hunt_list
local abort_hunts = common.abort_hunts
local hunt_text = common.hunt_text
local new_made = common.new_made
local make = common.make
local new_harvester = common.new_harvester
local new_flyer = common.new_flyer
local heat_chunk = common.heat_chunk
local deploy = common.deploy

-- T20 Würmer: Bedienung (interaktiv) ----------------------------------------------------------------
-- Mit Max im Spiel und seiner Force. ALT+O (Prüfstand-Taste, ab 0.8.3 auch /arrakis-test weiter) schaltet zum nächsten
-- Schritt; Schritt 2 erst nach dem Erwachen, nach Schritt 9 endet der Test. Gebaut wird neben Max (auf der
-- Prüfstand-Fläche), der Ernter für den Vorsichtsmodus 120 Kacheln östlich des Ursprungs, damit die Ruhe nach der Jagd
-- aus Schritt 4 und 5 ihn nicht trifft.
-- Entities bleiben am Ende zum Ansehen stehen (wie T17); Wärme, Ruhe und Jagden der Force räumt cleanup.

local T20_HALF = 200
local T20_END_TICKS = 900 * 60
local T20_LAST = 9
local T20_NOT_REMOTE = {["arrakis-testbench"] = true, ["arrakis-test-hold"] = true, ["arrakis-hold"] = true}

-- Kachelmitte neben Max (dx, dy Kacheln), frei für name; ohne Max auf der Fläche: neben dem Ursprung.
local function t20_spot(run, tb, d, dx, dy, name)
  local surface = tb.surface()
  local player = tb.player(run)
  local base = d.origin
  if player and player.physical_surface.index == surface.index then base = player.physical_position end
  local want = {x = math.floor(base.x + dx) + 0.5, y = math.floor(base.y + dy) + 0.5}
  local spot = surface.find_non_colliding_position(name or HARVESTER, want, 12, 1, true) or want
  return {x = math.floor(spot.x) + 0.5, y = math.floor(spot.y) + 0.5}
end

local function gps_text(surface, position)
  return string.format("[gps=%d,%d,%s]", math.floor(position.x), math.floor(position.y), surface.name)
end

-- Ernter des Tests merken (Zustand und Vorsichtsmodus werden jeden Tick verglichen).
local function t20_remember(d, label, car)
  local h = harvester.get(car)
  table.insert(d.cars, {label = label, entity = car, un = car.unit_number, state = h and h.state, careful = h and h.careful == true})
  return car
end

local function t20_harvester(run, tb, d, label, position, opts)
  opts = opts or {}
  opts.force = d.force
  local car = new_harvester(run, tb, d.made, position, opts)
  if not car then
    tb.log(run, "FEHLER", label .. " ließ sich nicht bauen (Einzelheiten in der Datei)")
    return nil
  end
  return t20_remember(d, label, car)
end

local t20_enter = {}

-- 1) Schonfrist 1 min [V3, V18]. ornithopter_tick so, dass jede Neuberechnung (4.6) wieder Tick + 3600 ergibt.
t20_enter[1] = function(run, tb, d, player)
  local now = game.tick
  worms_lib.set_grace(d.force, {ornithopter_tick = now + 3600 - GRACE_ORNITHOPTER, active_from = now + 3600, awake = false,
    first_hunt_done = true}, {"announced", "first_hunt"})
  d.wake_tick = now + 3600
  -- Andere Oberfläche für die Fernsicht: nicht die Prüfstand-Fläche und keine der beiden Ablagen.
  local other = false
  for _, surface in pairs(game.surfaces) do
    if not T20_NOT_REMOTE[surface.name] then other = true end
  end
  tb.log(run, "FRAGE", "1) Steht oben links „Die Wüste regt sich in 1:00“ und zählt herunter? Kommt bei 0 im Chat „Die Wüste ist erwacht“? [V18]")
  if other then
    tb.log(run, "INFO", "1) Während der Minute: Karte öffnen (M) und eine andere Oberfläche wählen (Fernsicht) [V3]. Der Test schreibt jede"
      .. " Sekunde surface und physical_surface in die Datei.")
  else
    tb.log(run, "INFO", "1) Es gibt keine andere Oberfläche: Fernsicht [V3] hier nicht prüfbar")
  end
end

-- 2) Unruhe [V17]: Ernter neben Max, aufgebaut, Wärme 620 in jeder Takt-Mitte bis zum Ende von Schritt 3.
t20_enter[2] = function(run, tb, d, player)
  local position = t20_spot(run, tb, d, 8, 0)
  d.main = t20_harvester(run, tb, d, "Ernter 1", position, {coal = 50, field = 1000})
  if not d.main then return end
  deploy(d.main)
  d.hold620 = true
  tb.log(run, "FRAGE", "2) Siehst du Sandstaub, hörst du ein Rumpeln, und zeigen Fahrzeugfenster und Ernterfenster „Der Sand bebt“ bzw. die Wärme? [V17]")
end

-- 3) Vibrationsanzeige.
t20_enter[3] = function(run, tb, d, player)
  tb.log(run, "FRAGE", "3) Verknüpfung „Vibrationsanzeige“ klicken: Siehst du farbige Chunks mit Zahlen, der um den Ernter gelb? Noch einmal klicken: weg?")
end

-- 4) Wurmzeichen [V5, V8]: set_heat 999, Jagd im nächsten Takt (60 s); der Ornithopter für Schritt 5 steht schon.
t20_enter[4] = function(run, tb, d, player)
  d.hold620 = false
  if not valid(d.main) then
    tb.log(run, "FEHLER", "4) Ernter 1 fehlt")
    return
  end
  heat_chunk(tb.surface(), d.main.position, 999)
  d.flyer = new_flyer(run, tb, d.made, t20_spot(run, tb, d, -6, 4, FLYER), {force = d.force, rocket = 4})
  tb.log(run, "FRAGE", "4) Je Zeichen ja/nein: Alarm unten rechts mit Wurmzeichen-Symbol, Kartenmarkierung, Warnton, roter Ring mit Sekunden,"
    .. " Zeile oben links, Status „Wurmzeichen! Biss in … s“? [V5, V8]")
  tb.log(run, "INFO", "4) Der Ornithopter für Schritt 5 steht neben dir. ALT+O oder /arrakis-test weiter für Schritt 5, solange der Countdown läuft.")
end

-- 5) Rettung [V16]; läuft keine Jagd mehr, startet der Test eine Befehlsjagd mit 60 s.
t20_enter[5] = function(run, tb, d, player)
  if valid(d.main) and not worms_lib.hunt_of(d.main) then
    local hunt = worms_lib.start_hunt(d.main, {seconds = 60, debug = true})
    tb.log(run, "INFO", "5) Die Jagd aus Schritt 4 ist vorbei: " .. (hunt and "Befehlsjagd mit 60 s auf Ernter 1" or "keine neue Jagd möglich"))
  end
  tb.log(run, "INFO", "5) In den Ornithopter steigen, über den Ernter fliegen, Umschalt+C.")
  tb.log(run, "FRAGE", "5) Verschwinden Alarm und Ring, steht oben links „wird getragen: erst nach … s auf Sand absetzen“, und kommt bei 0 eine"
    .. " Sandfontäne unter dir, ohne Schaden? [V16]")
end

-- 6) Biss ohne Rettung (Befehlsjagd 30 s, Kiste daneben) und Ernter am Rand einer Felsinsel (Befehlsjagd 60 s).
t20_enter[6] = function(run, tb, d, player)
  local surface = tb.surface()
  local position = t20_spot(run, tb, d, 8, 12)
  local car = t20_harvester(run, tb, d, "Ernter 2", position, {coal = 5})
  if car then
    make(run, tb, d.made, {name = "wooden-chest", position = {x = position.x, y = position.y + 2}, force = d.force})
    local hunt, reason = worms_lib.start_hunt(car, {seconds = 30, debug = true})
    if not hunt then tb.log(run, "FEHLER", "6) Befehlsjagd auf Ernter 2: " .. tostring(reason)) end
  end
  local corner = t20_spot(run, tb, d, 24, -4)
  local n, m = math.floor(corner.x), math.floor(corner.y)
  -- Felsinsel 11 × 10 Kacheln; unter der Box des Ernters (Kacheln n − 1 bis n + 1, m − 1 bis m + 1) ist nur die
  -- Nordwest-Ecke Sand.
  tiles(surface, n - 1, m - 1, n + 9, m + 8, ROCK, true)
  tiles(surface, n - 1, m - 1, n - 1, m - 1, SAND, true)
  local island = t20_harvester(run, tb, d, "Ernter 3", {x = n + 0.5, y = m + 0.5}, {coal = 20})
  if island then
    local hunt, reason = worms_lib.start_hunt(island, {seconds = 60, debug = true})
    if not hunt then tb.log(run, "FEHLER", "6) Befehlsjagd auf Ernter 3: " .. tostring(reason)) end
    tb.log(run, "MESSUNG", "6) Ernter 3 bei " .. gps_text(surface, island.position) .. ": Sand unter der Box " .. tostring(terrain.has_sand_under(island)))
  end
  tb.log(run, "FRAGE", "6) Kam die Eruption mit Ton genau bei 0, liegt das Wrack da, ist die Kiste weg?")
  tb.log(run, "INFO", "6) Ernter 3 steht am Rand der Felsinsel (Ecke im Sand): einsteigen und ganz auf den Fels fahren, dann zurück in den Sand.")
  tb.log(run, "FRAGE", "6) Wird der Ring grün und steht oben links „steht ganz auf Fels: sicher“, sobald er ganz auf Fels steht, und wieder rot,"
    .. " wenn du zurück in den Sand fährst?")
end

-- 7) Vorsichtsmodus: eigener Ernter 120 Kacheln östlich (anderer Sektor); sobald careful an ist, set_heat 580.
t20_enter[7] = function(run, tb, d, player)
  local position = {x = d.origin.x + 120.5, y = d.origin.y + 0.5}
  local car = t20_harvester(run, tb, d, "Ernter 4", position, {coal = 50, field = 1000})
  if not car then return end
  deploy(car)
  d.careful_car = car
  tb.watch(run, player, {x = position.x - 6, y = position.y + 3})
  tb.log(run, "INFO", "7) Der Test hat dich zu Ernter 4 gebracht " .. gps_text(tb.surface(), position) .. ". Fenster öffnen, Vorsichtsmodus"
    .. " einschalten; der Test setzt dann die Wärme auf 580.")
  tb.log(run, "FRAGE", "7) Packt der Ernter nach wenigen Sekunden selbst ein (im zweiten Takt), und baut er gut eine halbe Minute später"
    .. " (etwa 36 s nach dem Einpacken) wieder auf?")
end

-- 8) Tipps [V4].
t20_enter[8] = function(run, tb, d, player)
  tb.log(run, "FRAGE", "8) Stehen unter Tipps und Tricks (Space Age) die Einträge „Arrakis“ und „Wurmzeichen“? [V4]")
end

-- 9) Fahrzeug ohne raise_built [V12].
t20_enter[9] = function(run, tb, d, player)
  local position = t20_spot(run, tb, d, -5, 3, "car")
  d.raw_car = make(run, tb, d.made, {name = "car", position = position, force = d.force})
  if not d.raw_car then
    tb.log(run, "FEHLER", "9) Auto ließ sich nicht bauen")
    return
  end
  tb.fuel(d.raw_car, "coal", 10)
  tb.log(run, "MESSUNG", "9) Auto ohne raise_built: source_of " .. (vibration_lib.source_of(d.raw_car) and "eingetragen" or "nil"))
  tb.log(run, "INFO", "9) In das Auto neben dir steigen. Danach beendet ALT+O oder /arrakis-test weiter den Test.")
end

local function t20_next(run, tb, d)
  local player = tb.player(run)
  if d.step == 1 and not d.awake_tick then
    tb.log(run, "INFO", "1) Noch nicht erwacht (in " .. tb.num(math.max(0, (d.wake_tick or 0) - game.tick) / 60, 0) .. " s); ALT+O oder /arrakis-test weiter danach.")
    return
  end
  if d.step >= T20_LAST then
    d.done_all = true
    tb.finish(run, string.format("%d Schritte, %d Verknüpfungsklicks, %d Kontrollkästchen, %d Zustandswechsel", d.step, d.shortcuts, d.boxes, d.changes))
    return
  end
  d.step = d.step + 1
  tb.log(run, "INFO", "Schritt " .. d.step .. " von " .. T20_LAST)
  local ok, err = pcall(t20_enter[d.step], run, tb, d, player)
  if not ok then tb.log(run, "FEHLER", d.step .. ") Skriptfehler: " .. tostring(err)) end
end

local function t20_start(run, tb)
  local d = run.data
  local player = tb.player(run)
  if not player then
    tb.log(run, "FEHLER", "T20 braucht einen Spieler im Spiel")
    tb.finish(run, "abgebrochen (kein Spieler)")
    return
  end
  if not storage_ready() then
    tb.log(run, "FEHLER", "storage des Laufzeitcodes fehlt (scripts/migrate.lua init, Schema 3)")
    tb.finish(run, "abgebrochen (kein storage)")
    return
  end
  local surface = tb.surface()
  if not terrain.harvest_allowed(surface) then
    tb.log(run, "FEHLER", "terrain.harvest_allowed(" .. surface.name .. ") = false: der Laufzeitcode zählt hier nicht")
    tb.finish(run, "abgebrochen (Prüfstand-Fläche nicht erlaubt)")
    return
  end
  local force = player.force
  d.force = force
  d.origin = tb.area(run.id)
  d.box = box_of(d.origin, {x = T20_HALF, y = T20_HALF})
  d.saved = {grace = worms_lib.grace_snapshot(force), paused = storage.hunts.paused_until}
  d.stats = copy(worms_lib.stats_of(force))
  d.made = {made = new_made()}
  d.cars, d.hunts = {}, {}
  d.step, d.shortcuts, d.boxes, d.changes = 0, 0, 0, 0
  clear_area(surface, d.box)
  tb.prepare(d.origin, T20_HALF)
  worms_lib.ensure_force()
  worms_lib.set_paused(nil)
  -- Ohne Wurm wie 0.7.0 (docs/protokolle/plan-3d2.md 6).
  worms_lib.set_worm_off(force, true)
  tb.log(run, "INFO", "T20 prüft die Warnungen ohne Wurm; den Wurm zeigt T22.")
  vibration_lib.testbench_enable(force)
  tb.protect(run, player)
  tb.watch(run, player, d.origin)
  tb.log(run, "INFO", "Während T20 vibrieren auch deine übrigen Bauten auf der Prüfstand-Fläche (Force " .. force.name .. ").")
  tb.log(run, "INFO", "Neun Schritte; ALT+O oder /arrakis-test weiter schaltet zum nächsten (Schritt 2 erst nach dem Erwachen, nach Schritt 9 endet der Test)."
    .. " Jeder Klick auf eine Verknüpfung und jedes Kontrollkästchen schreibt eine MESSUNG-Zeile, jeder Zustandswechsel eine INFO-Zeile."
    .. " Ende nach 15 min Spielzeit oder mit /arrakis-test stop. Bitte mit /arrakis-test tempo 1.")
  if game.speed ~= 1 then
    tb.log(run, "INFO", "Zeitraffer an (game.speed " .. string.format("%g", game.speed) .. "): die 15 min vergehen schneller; zurück mit /arrakis-test tempo 1")
  end
  d.step = 1
  tb.log(run, "INFO", "Schritt 1 von " .. T20_LAST)
  t20_enter[1](run, tb, d, player)
end

-- Zustandswechsel der Ernter und Jagden (INFO), Kontrollkästchen (MESSUNG).
local function t20_watch(run, tb, d)
  for _, entry in ipairs(d.cars) do
    local h = valid(entry.entity) and harvester.get(entry.entity)
    local state = h and h.state or "weg"
    if state ~= entry.state then
      d.changes = d.changes + 1
      tb.log(run, "INFO", string.format("Zustand: %s %s → %s", entry.label, tostring(entry.state), state))
      entry.state = state
    end
    local careful = h and h.careful == true or false
    if careful ~= entry.careful then
      d.boxes = d.boxes + 1
      entry.careful = careful
      tb.log(run, "MESSUNG", string.format("Kontrollkästchen Vorsichtsmodus an %s: %s (Zustand %s, W %s)", entry.label, careful and "an" or "aus",
        state, valid(entry.entity) and tb.num(vibration_lib.near_heat(entry.entity.surface, entry.entity.position)) or "–"))
      if careful and valid(d.careful_car) and entry.un == d.careful_car.unit_number and not d.careful_set then
        d.careful_set = game.tick
        heat_chunk(entry.entity.surface, entry.entity.position, 580)
        tb.log(run, "INFO", "7) Vorsichtsmodus an: Wärme auf 580 gesetzt")
      end
    end
  end
  local seen = {}
  for _, hunt in ipairs(hunt_list(function(hunt) return hunt.force_index == d.force.index end)) do
    seen[hunt.id] = true
    local key = hunt.state .. (hunt.safe and ("/" .. tostring(hunt.safe)) or "") .. (hunt.hidden and "/getragen" or "")
    if d.hunts[hunt.id] ~= key then
      d.changes = d.changes + 1
      tb.log(run, "INFO", (d.hunts[hunt.id] and "Jagd: " or "Jagd neu: ") .. hunt_text(tb, hunt) .. (hunt.hidden and ", getragen" or ""))
      d.hunts[hunt.id] = key
    end
  end
  for id in pairs(d.hunts) do
    if not seen[id] then
      d.changes = d.changes + 1
      tb.log(run, "INFO", "Jagd " .. id .. " zu Ende")
      d.hunts[id] = nil
    end
  end
end

local function t20_tick(run, tb)
  local d = run.data
  if not d.cars or d.done_all then return end
  local now = game.tick
  local player = tb.player(run)
  local g = worms_lib.grace_snapshot(d.force) or {}
  if d.step == 1 and not d.awake_tick then
    if now % 60 == 0 and player then
      tb.trace(run, "1) surface " .. tostring(read(function() return player.surface.name end)) .. ", physical_surface "
        .. tostring(read(function() return player.physical_surface.name end)))
    end
    if g.awake then
      d.awake_tick = now
      tb.log(run, "INFO", "1) Erwacht bei Tick " .. now .. " (Termin " .. tostring(d.wake_tick) .. "). Weiter mit ALT+O oder /arrakis-test weiter.")
    end
  end
  if d.hold620 and valid(d.main) and now % 60 == 30 then heat_chunk(d.main.surface, d.main.position, 620) end
  if d.car_check and now >= d.car_check then
    d.car_check = nil
    tb.log(run, "MESSUNG", "9) Nach dem Einsteigen: source_of " .. (valid(d.raw_car) and vibration_lib.source_of(d.raw_car) and "eingetragen (V12 hält)"
      or "nil (V12 hält nicht)"))
  end
  t20_watch(run, tb, d)
  if now - run.started >= T20_END_TICKS then
    d.done_all = true
    tb.finish(run, string.format("15 min um: Schritt %d, %d Verknüpfungsklicks, %d Kontrollkästchen, %d Zustandswechsel", d.step, d.shortcuts,
      d.boxes, d.changes))
  end
end

local function t20_on_event(run, tb, name, event)
  local d = run.data
  if not d.cars or d.done_all then return end
  if name == "test_key" or name == "test_next" then
    if event.player_index == run.player_index then t20_next(run, tb, d) end
  elseif name == "shortcut" then
    local player = event.player_index and game.get_player(event.player_index)
    if not player then return end
    d.shortcuts = d.shortcuts + 1
    local toggled = read(function() return player.is_shortcut_toggled(event.prototype_name) end)
    tb.log(run, "MESSUNG", string.format("Verknüpfung %s (%s): toggled %s, Vibrationsanzeige %s", tostring(event.prototype_name), player.name,
      tostring(toggled), storage.vib.overlay[player.index] and "an" or "aus"))
  elseif name == "driving_changed" then
    -- Erst im nächsten Tick lesen: Die Reihenfolge der Handler (Runner, scripts/vibration.lua) ist nicht zugesichert.
    if valid(d.raw_car) and valid(event.entity) and event.entity.unit_number == d.raw_car.unit_number then d.car_check = game.tick + 1 end
  end
end

-- Jagden der Force abbrechen, Wärme und Ruhe der Fläche löschen, Prüfstand-Merker, Schonfrist, Pause und Statistik
-- zurück (die Jagden aus Schritt 4 und 5 zählten sonst in Max' Force).
local function t20_cleanup(run, tb)
  local d = run.data
  local force = d.force
  if not valid(force) then return end
  pcall(abort_hunts, {[force.index] = true})
  if d.box then pcall(clear_area, tb.surface(), d.box) end
  worms_lib.set_worm_off(force, false)
  vibration_lib.testbench_disable(force)
  if d.saved then
    worms_lib.grace_restore(force, d.saved.grace)
    worms_lib.set_paused(d.saved.paused)
  end
  local stats = worms_lib.stats_of(force)
  for key in pairs(stats) do stats[key] = nil end
  for key, value in pairs(d.stats or {}) do stats[key] = value end
  worms_lib.ensure_force()
end

return
{
  T20 =
  {
    title = "Würmer: Bedienung",
    timeout = 920 * 60,
    interactive = true,
    steps = true,
    confirm = nil,
    start = t20_start,
    tick = t20_tick,
    on_event = t20_on_event,
    cleanup = t20_cleanup
  }
}
