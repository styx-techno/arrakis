-- T22 Sandwurm: Optik und Laden: Prüfstand-Test (aus t_sandwurm.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_sandwurm.lua.

local common = require("scripts.testbench.gemeinsam_sandwurm")
local terrain = require("scripts.terrain")
local vibration_lib = require("scripts.vibration")
local sandworm_lib = require("scripts.sandworm")
local worms_lib = require("scripts.worms")
local FLYER = common.FLYER
local ROCK = common.ROCK
local CHEST = common.CHEST
local KILL_AFTER = common.KILL_AFTER
local valid = common.valid
local at = common.at
local read = common.read
local copy = common.copy
local dist = common.dist
local box_of = common.box_of
local sand_at = common.sand_at
local storage_ready = common.storage_ready
local tiles = common.tiles
local clear_area = common.clear_area
local abort_hunts = common.abort_hunts
local end_if_running = common.end_if_running
local sandworms_in = common.sandworms_in
local new_made = common.new_made
local make = common.make
local new_harvester = common.new_harvester
local new_car = common.new_car
local new_flyer = common.new_flyer
local deploy = common.deploy

-- T22 Sandwurm: Optik und Laden (interaktiv) ----------------------------------------------------------
-- Mit Max im Spiel und seiner Force auf der Fläche ±250 mit einer Felsinsel (40 × 40, Mitte 60 östlich des Ursprungs).
-- ALT+O (ab 0.8.3 auch /arrakis-test weiter) schaltet zum nächsten Schritt; ein Schritt beendet beim Weiterschalten seine
-- laufenden Jagden ("abort"), damit kein Wurm überlebt. Die FRAGEn kommen, sobald es etwas zu sehen gab (Auftauchen,
-- Ende der Jagd). Entities bleiben am Ende zum Ansehen stehen (wie T20); Jagden, Wärme, Ruhe, Schonfrist, Pause und
-- Statistik räumt cleanup.

local T22_HALF = 250
local T22_LAST = 9
-- 0.8.4: 45 statt 20 min Spielzeit (am 28.10.2026 lief T22 mit Erklärungen in Schritt 8 ab).
local T22_END_TICKS = 45 * 60 * 60 - 60
local T22_ISLAND = {dx1 = 40, dx2 = 79, dy1 = -20, dy2 = 19}

local t22_enter = {}
local t22_watch = {}

local function t22_hunt(run, tb, d, entity, opts, label)
  local hunt, reason = worms_lib.start_hunt(entity, opts)
  if not hunt then
    tb.log(run, "FEHLER", d.step .. ") " .. label .. ": Befehlsjagd ging nicht (" .. tostring(reason) .. ")")
    return nil
  end
  table.insert(d.hunts, hunt)
  d.cur = {hunt = hunt, label = label, start = game.tick}
  tb.log(run, "INFO", string.format("%d) %s: Jagd %d, Biss bei 0 in %s s", d.step, label, hunt.id, tb.num((hunt.eta_tick - game.tick) / 60, 0)))
  return hunt
end

local function t22_make(run, tb, d, params)
  return make(run, tb, d.made, params)
end

local function t22_base(d)
  return d.max_pos or d.origin
end

local function t22_ask(run, tb, d, text)
  tb.log(run, "FRAGE", d.step .. ") " .. text)
end

t22_enter[1] = function(run, tb, d)
  local base = t22_base(d)
  local chest = t22_make(run, tb, d, {name = CHEST, position = at(base, 0, -20), force = d.force})
  if not chest then return tb.log(run, "FEHLER", "1) Kiste ließ sich nicht bauen") end
  local tick = math.ceil((game.tick + 120) / 10) * 10
  t22_hunt(run, tb, d, chest, {seconds = 60, debug = true, spawn = {position = at(base, 60, 0), direction = defines.direction.west, tick = tick}},
    "Auftauchen 60 Kacheln östlich von dir in 2 s")
end

t22_watch[1] = function(run, tb, d)
  local hunt = d.cur and d.cur.hunt
  if not hunt then return end
  if hunt.worm and not d.cur.asked then
    d.cur.asked = true
    t22_ask(run, tb, d, "Hörst du gut 3 s vorher ein Rumpeln, und siehst du den Wurm mit Brüllen und Staub auftauchen? Ist er sandfarben, ohne Ascheschwaden, ohne dunkle Rauchspur, ohne orange Partikel?")
  end
  if storage.hunts.list[hunt.id] ~= hunt and not d.cur.done then
    d.cur.done = true
    d.step = 2
    tb.log(run, "INFO", "Schritt 2 von " .. T22_LAST)
    t22_ask(run, tb, d, "Wartet der Wurm vor der Kiste fast still bis 0? Kam der Biss genau bei 0 mit Sandfontäne, und tauchte er danach in 1 s vom Kopf bis zum Schwanz im Staub ab, statt auf einmal zu verschwinden?")
  end
end

t22_enter[2] = function(run, tb, d)
  tb.log(run, "INFO", "2) Warte auf den Biss der Jagd aus Schritt 1; die FRAGE kommt danach.")
end
t22_watch[2] = t22_watch[1]

t22_enter[3] = function(run, tb, d)
  local o = d.origin
  local chest = t22_make(run, tb, d, {name = CHEST, position = at(o, 110, 0), force = d.force})
  if not chest then return tb.log(run, "FEHLER", "3) Kiste ließ sich nicht bauen") end
  d.cur3 = "a"
  t22_hunt(run, tb, d, chest, {seconds = 60, debug = true, spawn = {position = at(o, -50, 0), direction = defines.direction.east}},
    "Felsinsel zwischen Wurm und Kiste (Insel östlich des Ursprungs)")
end

t22_watch[3] = function(run, tb, d)
  local hunt = d.cur and d.cur.hunt
  if not hunt or storage.hunts.list[hunt.id] == hunt or d.cur.done then return end
  d.cur.done = true
  if d.cur3 == "a" then
    t22_ask(run, tb, d, "Biegt er glatt vor der Insel ab, ohne den Fels zu berühren?")
    local o = d.origin
    local car = new_harvester(run, tb, d, d.made, at(o, T22_ISLAND.dx1 - 10, 0), {force = d.force, coal = 20})
    if not car then return tb.log(run, "FEHLER", "3) Ernter ließ sich nicht bauen") end
    d.cur3 = "b"
    t22_hunt(run, tb, d, car, {seconds = 60, debug = true, spawn = {position = at(o, T22_ISLAND.dx1 - 170, 0), direction = defines.direction.east}},
      "Ernter 10 Kacheln vor dem Inselrand, Wurm frontal auf den Fels dahinter")
  else
    t22_ask(run, tb, d, "Wird der Ernter trotzdem gebissen, und bleibt der Wurm dabei auf dem Sand?")
  end
end

t22_enter[4] = function(run, tb, d)
  local o = d.origin
  local y = -120
  local surface = tb.surface()
  for i = -2, 2 do
    t22_make(run, tb, d, {name = "transport-belt", position = at(o, -20, y + i), direction = defines.direction.north, force = d.force})
  end
  t22_make(run, tb, d, {name = CHEST, position = at(o, 0, y), force = d.force})
  t22_make(run, tb, d, {name = CHEST, position = at(o, 10, y), force = d.force})
  new_car(run, tb, d, d.made, at(o, 30, y), {force = d.force})
  new_car(run, tb, d, d.made, at(o, 30, y - 6), {force = d.force})
  -- Felskiste im Zerdrückradius, nur durch die Sandregel geschützt; 16 Kacheln vor dem Ziel, also im Angriff (wie T21
  -- Schritt 8, Gegenprüfung 0.8.0).
  local n, m = math.floor(o.x), math.floor(o.y) + y
  tiles(surface, n + 84, m + 2, n + 85, m + 3, ROCK)
  t22_make(run, tb, d, {name = CHEST, position = {x = n + 84 + 0.5, y = m + 2 + 0.5}, force = d.force})
  local chest = t22_make(run, tb, d, {name = CHEST, position = at(o, 100, y), force = d.force})
  if not chest then return tb.log(run, "FEHLER", "4) Kiste ließ sich nicht bauen") end
  t22_hunt(run, tb, d, chest, {seconds = 60, debug = true, spawn = {position = at(o, -60, y), direction = defines.direction.east}},
    "Zerdrücken: Band, Kisten und ein Auto auf der Linie, ein Auto 6 Kacheln daneben, eine Kiste auf Fels")
  -- 0.8.4: Max fragte am 28.10.2026, ob der Wurm dem Felsfleck auswich; das muss er hier nicht.
  tb.log(run, "INFO", "4) Der kleine Felsfleck liegt 2 Kacheln neben der Spur: Ausweichen muss der Wurm nicht. Die Kiste darauf liegt im"
    .. " Zerdrückradius und bleibt nur heil, weil der Wurm auf Fels nichts zerstört. Das Ausweichen zeigt Schritt 3.")
end

t22_watch[4] = function(run, tb, d)
  local hunt = d.cur and d.cur.hunt
  if not hunt or storage.hunts.list[hunt.id] == hunt or d.cur.done then return end
  d.cur.done = true
  if worms_lib.CRUSH_SPARES_VEHICLES then
    t22_ask(run, tb, d, "Verschwinden Band und Kisten am Kopf (Wracks), bleiben die Autos und die Kiste auf dem Fels heil, und fährt der Wurm am Auto vorbei oder hindurch, ohne hängen zu bleiben?")
  else
    t22_ask(run, tb, d, "Verschwinden Band, Kisten und das Auto auf der Linie am Kopf (Wracks), bleiben das Auto neben der Spur und die Kiste auf dem Fels heil, und fährt der Wurm durch, ohne hängen zu bleiben?")
  end
end

t22_enter[5] = function(run, tb, d)
  local o = d.origin
  local base = t22_base(d)
  d.flyer = valid(d.flyer) and d.flyer or new_flyer(run, tb, d, d.made, at(base, 4, 0), {force = d.force, rocket = 10})
  local chest = t22_make(run, tb, d, {name = CHEST, position = at(o, 100, 120), force = d.force})
  if not chest then return tb.log(run, "FEHLER", "5) Kiste ließ sich nicht bauen") end
  -- 0.8.4 (T22 am 28.10.2026): Aufgabe klarer, 90 statt 60 s; die Kiste ist nur Köder.
  tb.log(run, "INFO", "5) Die Kiste ist nur der Köder, sie wird gebissen. Getestet wird der Ornithopter neben dir: Steig sofort ein"
    .. " und flieg zum Wurm (er taucht 160 Kacheln westlich der Kiste auf und fährt nach Osten), schwebe über dem fahrenden"
    .. " Kopf, halt an, dann flieg voll nach Westen über den Körper weg. Du hast 90 s bis zum Biss.")
  t22_hunt(run, tb, d, chest, {seconds = 90, debug = true, spawn = {position = at(o, -60, 120), direction = defines.direction.east}},
    "Ornithopter über dem Kopf [W12]")
end

t22_watch[5] = function(run, tb, d)
  local hunt = d.cur and d.cur.hunt
  if not hunt then return end
  local player = tb.player(run)
  if game.tick % 60 == 0 and storage.hunts.list[hunt.id] == hunt then
    local vehicle = player and player.vehicle
    local head = sandworm_lib.head_of(hunt)
    if valid(vehicle) and vehicle.name == FLYER then
      -- Abstand zum Kopf (Knoten 1, bis 1 Kachel hinter dem wahren Kopf, W18) und zum nächsten Körperknoten
      local near
      local unit = hunt.worm and hunt.worm.unit
      if valid(unit) then
        for _, node in ipairs(unit.get_body_nodes()) do
          local gap = dist(vehicle.position, node)
          if not near or gap < near then near = gap end
        end
      end
      tb.trace(run, string.format("5) Ornithopter Tempo %s Kacheln/s, Gesundheit %s, Abstand zum Kopf %s, zum nächsten Körperknoten %s",
        tb.num(tb.speed_tps(vehicle), 2), tb.num(vehicle.health, 0), head and tb.num(dist(vehicle.position, head)) or "–", tb.num(near)))
    end
  end
  if storage.hunts.list[hunt.id] ~= hunt and not d.cur.done then
    d.cur.done = true
    t22_ask(run, tb, d, "Merkst du ein Bremsen, Ruckeln oder Schaden?")
  end
end

t22_enter[6] = function(run, tb, d)
  local base = t22_base(d)
  local player = tb.player(run)
  if player and player.physical_surface.index == tb.surface().index then base = player.physical_position end
  -- Platz für Ernter und Spice-Teppich (13 × 13) ganz auf Sand nahe base (0.8.4: am 28.10.2026 lag er neben der
  -- Felsinsel auf Fels).
  local surface = tb.surface()
  local spot
  for _, offset in ipairs({{10, 0}, {-10, 0}, {0, 10}, {0, -10}, {20, 0}, {-20, 0}, {0, 20}, {0, -20}, {30, 0}, {-30, 0}}) do
    local c = at(base, offset[1], offset[2])
    local ok = true
    for dx = -8, 8, 2 do
      for dy = -8, 8, 2 do
        if ok and not sand_at(surface, c.x + dx, c.y + dy) then ok = false end
      end
    end
    if ok then
      spot = c
      break
    end
  end
  if not spot then return tb.log(run, "FEHLER", "6) Kein freier Sand neben dir für den Ernter; geh ein Stück weg von der Felsinsel") end
  local car = new_harvester(run, tb, d, d.made, spot, {force = d.force, coal = 20, field = 1000})
  if not car then return tb.log(run, "FEHLER", "6) Ernter ließ sich nicht bauen") end
  deploy(car)
  tb.log(run, "INFO", "6) Heb den Ernter neben dir vor 0 mit dem Ornithopter an und schwebe über der Stelle.")
  t22_hunt(run, tb, d, car, {seconds = 60, debug = true}, "Rettung")
end

t22_watch[6] = function(run, tb, d)
  local hunt = d.cur and d.cur.hunt
  if not hunt or d.cur.done then return end
  if hunt.state == "searching" or storage.hunts.list[hunt.id] ~= hunt then
    d.cur.done = true
    t22_ask(run, tb, d, "Hält der Wurm neben dir, beißt ins Leere und taucht ab?")
  end
end

t22_enter[7] = function(run, tb, d)
  local o = d.origin
  local chest = t22_make(run, tb, d, {name = CHEST, position = at(o, 100, 200), force = d.force})
  if not chest then return tb.log(run, "FEHLER", "7) Kiste ließ sich nicht bauen") end
  t22_hunt(run, tb, d, chest, {seconds = 60, debug = true, spawn = {position = at(o, -60, 200), direction = defines.direction.east}},
    "Wurm getötet (10 s nach dem Auftauchen)")
end

t22_watch[7] = function(run, tb, d)
  local cur = d.cur
  local hunt = cur and cur.hunt
  if not hunt then return end
  if hunt.worm and not cur.spawn then cur.spawn = game.tick end
  if cur.spawn and not cur.killed and game.tick >= cur.spawn + KILL_AFTER then
    cur.killed = game.tick
    local unit = hunt.worm and hunt.worm.unit
    local player = tb.player(run)
    if valid(unit) then
      local ok, err = pcall(function() unit.die(player and player.force or d.force) end)
      if not ok then tb.log(run, "FEHLER", "7) die: " .. tostring(err)) end
    end
  end
  if cur.killed and not cur.done and game.tick >= cur.killed + 60 then
    cur.done = true
    t22_ask(run, tb, d, "Stirbt der Wurm mit Sandstaub, ohne Leiche und ohne Wolfram, steht im Chat „… ist gerettet“, und verschwindet die Jagd oben links?")
  end
end

t22_enter[8] = function(run, tb, d)
  t22_ask(run, tb, d, "Steht der Sandwurm in der Factoriopedia unter Gegner mit sandfarbenem Symbol, Name und Beschreibung?")
end

t22_enter[9] = function(run, tb, d)
  local base = t22_base(d)
  local chest = t22_make(run, tb, d, {name = CHEST, position = at(base, -20, -30), force = d.force})
  if not chest then return tb.log(run, "FEHLER", "9) Kiste ließ sich nicht bauen") end
  local hunt = t22_hunt(run, tb, d, chest, {teaching = true, debug = true}, "Speichern und Laden (Lehrjagd 90 s)")
  if not hunt then return end
  d.cur.w5 = false
  tb.log(run, "INFO", "9) Planung (routing) nur von 36,2 s bis 41,2 s nach dem Wurmzeichen, davor warten. Speichere zwischen 37 und 40 s und lade;"
    .. " nach dem Auftauchen (41,2 s) noch einmal speichern und laden.")
end

t22_watch[9] = function(run, tb, d)
  local cur = d.cur
  local hunt = cur and cur.hunt
  if not hunt or cur.done then return end
  local running = storage.hunts.list[hunt.id] == hunt
  local t = game.tick - hunt.warn_tick
  if running and t >= 30 * 60 and t % 60 == 0 then
    local worm = hunt.worm
    local open = hunt.path ~= nil and hunt.path.id ~= nil
    if hunt.phase == "routing" and open then cur.w5 = true end
    tb.log(run, "MESSUNG", string.format("9) %s s: Phase %s, Kandidat %s, spawn_tick %s, Anfrage offen %s, Wurm gültig %s", tb.num(t / 60, 0),
      tostring(hunt.phase), hunt.plan and hunt.plan.chosen and "gewählt" or "–", tostring(hunt.spawn_tick), open and "ja" or "nein",
      worm and tostring(valid(worm.unit)) or "–"))
  end
  if not running then
    cur.done = true
    if not cur.w5 then tb.log(run, "INFO", "9) W5 offen: beim Speichern war keine Anfrage offen (Zeitablauf deckt beide Fälle, Plan 4.5)") end
    t22_ask(run, tb, d, "Taucht der Wurm auf, fährt er nach dem Laden weiter und beißt bei 0?")
  end
end

local function t22_next(run, tb, d)
  if d.step >= T22_LAST then
    d.done_all = true
    tb.finish(run, string.format("%d Schritte, %d Jagden", d.step, #d.hunts))
    return
  end
  -- Kein Wurm überlebt einen Schritt (Schritt 2 setzt die Jagd aus Schritt 1 fort).
  if d.step ~= 1 then
    for _, hunt in ipairs(d.hunts) do end_if_running(hunt) end
  end
  d.step = d.step + 1
  tb.log(run, "INFO", "Schritt " .. d.step .. " von " .. T22_LAST)
  local ok, err = pcall(t22_enter[d.step], run, tb, d)
  if not ok then tb.log(run, "FEHLER", d.step .. ") Skriptfehler: " .. tostring(err)) end
end

local function t22_start(run, tb)
  local d = run.data
  local player = tb.player(run)
  if not player then
    tb.log(run, "FEHLER", "T22 braucht einen Spieler im Spiel")
    tb.finish(run, "abgebrochen (kein Spieler)")
    return
  end
  if not storage_ready() then
    tb.log(run, "FEHLER", "storage des Laufzeitcodes fehlt (scripts/migrate.lua init, Schema 4)")
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
  d.box = box_of(d.origin, {x = T22_HALF, y = T22_HALF})
  d.saved = {grace = worms_lib.grace_snapshot(force), paused = storage.hunts.paused_until}
  d.stats = copy(worms_lib.stats_of(force))
  d.made = {made = new_made()}
  d.hunts, d.units = {}, {}
  d.step = 0
  clear_area(surface, d.box)
  tb.prepare(d.origin, T22_HALF)
  local n, m = math.floor(d.origin.x), math.floor(d.origin.y)
  tiles(surface, n + T22_ISLAND.dx1, m + T22_ISLAND.dy1, n + T22_ISLAND.dx2, m + T22_ISLAND.dy2, ROCK)
  worms_lib.ensure_force()
  worms_lib.set_paused(nil)
  worms_lib.set_worm_off(force, false)
  vibration_lib.testbench_enable(force)
  worms_lib.set_grace(force, {awake = true})
  tb.protect(run, player)
  d.max_pos = at(d.origin, -60, 60)
  tb.watch(run, player, d.max_pos)
  tb.log(run, "INFO", "Neun Schritte mit dem echten Sandwurm und deiner Force (" .. force.name .. ", wach); ALT+O oder /arrakis-test weiter schaltet zum nächsten,"
    .. " nach Schritt 9 endet der Test. Jede FRAGE wartet auf deine Antwort. Ende nach " .. (T22_END_TICKS + 60) / 3600 .. " min Spielzeit oder mit /arrakis-test stop."
    .. " Bitte vorher /arrakis-test tempo 1.")
  if game.speed ~= 1 then
    tb.log(run, "INFO", "Zeitraffer an (game.speed " .. string.format("%g", game.speed) .. "): zurück mit /arrakis-test tempo 1")
  end
  d.step = 1
  tb.log(run, "INFO", "Schritt 1 von " .. T22_LAST)
  t22_enter[1](run, tb, d)
end

local function t22_tick(run, tb)
  local d = run.data
  if not d.made or d.done_all then return end
  local fn = t22_watch[d.step]
  if fn then
    local ok, err = pcall(fn, run, tb, d)
    if not ok then tb.log(run, "FEHLER", d.step .. ") Skriptfehler: " .. tostring(err)) end
  end
  if game.tick - run.started >= T22_END_TICKS then
    d.done_all = true
    tb.finish(run, string.format("%d min um: Schritt %d, %d Jagden", (T22_END_TICKS + 60) / 3600, d.step, #d.hunts))
  end
end

local function t22_on_event(run, tb, name, event)
  local d = run.data
  if not d.made or d.done_all then return end
  if (name == "test_key" or name == "test_next") and event.player_index == run.player_index then t22_next(run, tb, d) end
end

local function t22_cleanup(run, tb)
  local d = run.data
  local force = d.force
  if not valid(force) then return end
  pcall(abort_hunts, {[force.index] = true})
  local surface = tb.surface()
  pcall(sandworm_lib.sweep, {surface})
  if d.box then
    local left = read(function() return sandworms_in(surface, d.box) end) or 0
    if left > 0 then tb.log(run, "FEHLER", left .. " arrakis-sandworm-* nach dem Aufräumen im Bereich von T22") end
    pcall(clear_area, surface, d.box)
  end
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
  T22 =
  {
    title = "Sandwurm: Optik und Laden",
    timeout = T22_END_TICKS + 60,
    interactive = true,
    steps = true,
    confirm = nil,
    start = t22_start,
    tick = t22_tick,
    on_event = t22_on_event,
    cleanup = t22_cleanup
  }
}
