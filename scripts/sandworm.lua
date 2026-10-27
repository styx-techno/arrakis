-- Sandwurm (Phase 3d2, docs/plan-3d2.md 4.1 bis 4.11, 4.14, 4.18): der Wurm als Fahrzeug. Spawnplanung in 16 Richtungen,
-- ROUTING per request_path samt on_script_path_request_finished, Erzeugen und Körperprüfung, Steuern, Fels-Wächter,
-- Tempo (Drosseln, Halten, Sprint), Abtauchen, Waisen und Prüfstand-Haken. Bibliothek für __core__/lualib/event_handler;
-- die Modultabelle heißt lib, andere Dateien binden sie als sandworm_lib.
--
-- scripts/worms.lua bleibt Herr der Jagd (Plan 1 „Module“) und ruft dieses Modul auf: begin beim Start, step im
-- 10-Tick-Takt (in fester Reihenfolge nach track, vor Zerdrücken und Biss-Fenster), dive beim Ende. sandworm entscheidet
-- nie, wer stirbt (kein die(), kein Biss, kein Zerdrücken), und nennt die Sandwurm-Force nie beim Namen: worms reicht
-- sie als LuaForce herein. Daten nur in den Wurm-Feldern der Jagd (Plan 4.2) und in storage.path_requests; Zufall nur
-- storage.rng (Startrichtung), sonst fest aus Tick, Knoten und Lage. Abhängigkeit ohne Kreis: worms → sandworm → terrain.
--
-- Phasen (hunt.phase, Plan 4.3): warten → routing → anfahrt ⇄ angriff → (Biss | suche) bzw. jederzeit ohne. Jeder
-- Wechsel auf ohne geht über to_none: danach gilt hunt.worm == nil, hunt.path == nil und kein Eintrag der Jagd in
-- storage.path_requests.
-- [Wn] markiert ungeprüftes Engine-Verhalten (Plan 4.17).

local terrain = require("scripts.terrain")

local lib = {}

-- Prototyp und Präfix aller eigenen Würmer (Testwürmer heißen arrakis-test-worm…).
lib.NAME = "arrakis-sandworm-small"
lib.PREFIX = "arrakis-sandworm-"
-- Tempo (Kacheln/s): Fahrt in allen Zuständen, Sprint.
lib.V = 3.5
lib.V_SPRINT = 6
-- Plan 1 „Sprint“, Max 27.10.: ja. Ist der Wurm zu spät, schreibt das Skript ein Tempo über V bis V_SPRINT, mit zwei
-- Ersatzstufen (move_forward, Knotenschub). false: nie mehr als V; ein fliehendes Ziel bekommt dann meist den Ersatzbiss
-- bei 0 + 3 s (Plan 4.9).
lib.SPRINT = true
-- Reichweite des Bisses über die Zielbox hinaus (Kacheln): R = BITE_REACH + r (worms.lua übernimmt den Wert).
lib.BITE_REACH = 3
-- Reserve vor dem Biss (s) und kürzester Countdown mit Wurm (s); D = min(D_MAX, V · (T − LEAD − 1)), 1 s Planung.
lib.LEAD = 3
lib.T_MIN = 27
-- Spawnabstand (Kacheln): höchstens, mindestens, kürzere Stufen (nur, wenn mindestens 10 Kacheln kürzer als D).
lib.D_MAX = 160
lib.D_MIN = 80
lib.D_STEPS = {120, 80}
lib.D_GAP = 10
-- Richtungen der Planung, Punktabstand der Sandlinie, Ende der Linie vor P (Kacheln).
lib.DIRECTIONS = 16
lib.LINE_STEP = 4
lib.LINE_END = 6
-- Körperlinie hinter dem Spawn: Länge, Schritt, Rand für Fahrzeuge und Figuren (Kacheln).
lib.BODY_LEN = 20
lib.BODY_STEP = 4
lib.BODY_CLEAR = 4
-- Höchstens so viele Kandidaten je Takt.
lib.CHECKS_PER_TICK = 8
-- Planung so viele Ticks vor dem Nennspawn; ohne Wurm bis eta − SPAWN_DEADLINE → ohne.
lib.PLAN_EARLY = 300
lib.SPAWN_DEADLINE = 1440
-- Höchstens so viele Erzeugungen je Jagd.
lib.SPAWN_MAX = 3
-- ROUTING (Plan 4.5): Anfragen der Planung, Wartezeit nach try_again_later, Versuche, Zeitablauf (Ticks), Zielradius,
-- Raster, Box (Kacheln, halbe Kantenlänge) und Rückgriff.
lib.PATH_MAX = 2
lib.PATH_RETRY = 60
lib.PATH_TRIES = 5
lib.PATH_TIMEOUT = 300
lib.PATH_RADIUS = 8
lib.PATH_RESOLUTION = -2
lib.PATH_BOX = 3.5
lib.PATH_BOX_MIN = 1.5
-- Wegpunkt erreicht (Kacheln), Zustand spätestens alle STATE_TICKS neu, bei Zielwechsel über GOAL_MOVE Kacheln sofort.
lib.WP_NEAR = 6
lib.STATE_TICKS = 30
lib.GOAL_MOVE = 2
-- Fels-Wächter (Plan 4.8): Vorausschau, Punktabstand, Seitenlinien, Wenderadius des Prototyps (turn_radius bleibt
-- Vanilla, Plan 2 „Tempo“) (Kacheln).
lib.LOOKAHEAD = 18
lib.LOOK_STEP = 2
lib.SIDE = 1.5
lib.TURN_RADIUS = 6
-- Umwege: Längen, Winkel (Grad), erreicht je Länge (Kacheln), längste Dauer (Ticks); höchstens REROUTE_MAX Neuplanungen,
-- dabei höchstens HOLD_MAX Ticks halten.
lib.DETOUR_RADII = {30, 15, 8}
lib.DETOUR_ANGLES = {30, -30, 60, -60, 90, -90}
lib.DETOUR_REACHED = {10, 6, 6}
lib.DETOUR_MAX = 900
lib.REROUTE_MAX = 1
lib.HOLD_MAX = 300
-- Stillstand: so viele Ticks ohne STALL_DIST Kacheln Bewegung → abtauchen.
lib.STALL_TICKS = 300
lib.STALL_DIST = 0.5
-- Angriff ab ATTACK_RANGE Kacheln, zurück in die Anfahrt über ATTACK_LEAVE; Fahrziel BEHIND bzw. BEHIND_MIN hinter P.
lib.ATTACK_RANGE = 40
lib.ATTACK_LEAVE = 50
lib.BEHIND = 20
lib.BEHIND_MIN = 6
-- Suche: abtauchen, sobald der Kopf so nah an P ist (Kacheln).
lib.SEARCH_REACHED = 8
-- Staubwolken je vierten Knoten beim Auf- und Abtauchen.
lib.DUST_PER_NODE = 2
-- Sprint-Ersatz (Plan 4.9): unter BOOST_MIN des geschriebenen Tempos in BOOST_TAKTS Sprint-Takten → nächste Stufe; Schub
-- höchstens PUSH_MAX Kacheln je Takt.
lib.BOOST_MIN = 0.9
lib.BOOST_TAKTS = 2
lib.PUSH_MAX = 0.4
-- tidy löscht Anfragen, die mindestens so alt sind (Ticks).
lib.TIDY_AGE = 600

local ROCK = "arrakis-rock"
local DUST = "arrakis-sand-dust"
local DIVE = "arrakis-worm-dive"
local RUMBLE = "arrakis-rumble"
local CHUNK = 32
-- Halbe Diagonale, wenn das Ziel fehlt (Spice-Ernter, Plan 4.14).
local DEFAULT_R = 1.58
local EPS = 1e-9
-- Fahrzeuge und Figuren am Spawn (Plan 4.4 Schritt 4 a; eine Figur im Fahrzeug findet die Suche nicht, das Fahrzeug schon).
local BLOCKER_TYPES = {"character", "car", "spider-vehicle", "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon"}
-- Phasen, in denen eine Jagd einen Wurm hat oder bekommt (Grenze, Plan 4.13).
local ACTIVE = {warten = true, routing = true, anfahrt = true, angriff = true}

-- Hilfen ----------------------------------------------------------------------------------------

local function distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

-- Einheitsvektor (dx, dy) oder nil bei Länge 0.
local function unit_vector(dx, dy)
  local len = math.sqrt(dx * dx + dy * dy)
  if len < EPS then return nil end
  return dx / len, dy / len
end

-- Richtung k (defines.direction: north = 0, im Uhrzeigersinn, east = 4) als Einheitsvektor.
local function dir_vector(k)
  local angle = k * math.pi * 2 / lib.DIRECTIONS
  return math.sin(angle), -math.cos(angle)
end

-- Vektor → nächste der 16 Richtungen.
local function round_dir(dx, dy)
  local angle = math.atan2(dx, -dy)
  return math.floor(angle / (math.pi * 2 / lib.DIRECTIONS) + 0.5) % lib.DIRECTIONS
end

-- Vektor um a Grad gedreht (positiv: im Uhrzeigersinn auf dem Bildschirm).
local function rotate(x, y, a)
  local r = math.rad(a)
  local c, s = math.cos(r), math.sin(r)
  return x * c - y * s, x * s + y * c
end

-- Vorlauf des Spawns vor eta (Ticks) für Weglänge L: ceil((L / V + LEAD) · 6) · 10 (Plan 1 „Spawn“).
local function spawn_lead(L)
  return math.ceil((L / lib.V + lib.LEAD) * 6 - EPS) * 10
end

-- Passt ein Weg der Länge L noch in die Restzeit (L / V + 1 ≤ (eta − tick) / 60, Plan 4.5)? deadline statt eta_tick
-- für die Neuplanung (reroute_deadline).
local function fits(hunt, L, tick, deadline)
  return L / lib.V + 1 <= ((deadline or hunt.eta_tick) - tick) / 60
end

-- Frist der Neuplanung vom Kopf: eta, in der Suche end_tick. Abweichung von Plan 4.5 und 4.8 Schritt 5 (Gegenprüfung
-- 0.8.0): Gemessen an eta passte in der Suche nie ein Weg; der Wurm hielt bis zur Antwort und tauchte mit "kein-weg" ab.
local function reroute_deadline(hunt)
  if hunt.state == "searching" and hunt.end_tick then return hunt.end_tick end
  return hunt.eta_tick
end

-- Sand (Plan 4.4 Schritt 4): Chunk erzeugt und natürliche Kachel kein Fels. Ungenerierte Chunks zählen als Fels.
-- probe = {surface, chunks} merkt sich die Chunks einer Prüfung.
local function new_probe(surface)
  return {surface = surface, chunks = {}}
end

local function sand(probe, x, y)
  local cx, cy = math.floor(x / CHUNK), math.floor(y / CHUNK)
  local key = cx .. "," .. cy
  local generated = probe.chunks[key]
  if generated == nil then
    generated = probe.surface.is_chunk_generated{cx, cy}
    probe.chunks[key] = generated
  end
  if not generated then return false end
  return terrain.natural_tile_name(probe.surface, x, y) ~= ROCK
end

-- Strecke (ax, ay) → (bx, by): Punkte alle step Kacheln ohne den Startpunkt, mit dem Endpunkt, auf Sand; side > 0 prüft
-- dazu zwei Parallelen im Abstand ±side (Plan 4.8 Schritt 3). Erst die Mittellinie, dann die Parallelen.
local function line_clear(probe, ax, ay, bx, by, step, side)
  local ux, uy = unit_vector(bx - ax, by - ay)
  if not ux then return true end
  local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
  local offsets = (side and side > 0) and {0, side, -side} or {0}
  for _, o in ipairs(offsets) do
    local ox, oy = -uy * o, ux * o
    local s = step
    while true do
      local t = math.min(s, len)
      if not sand(probe, ax + ux * t + ox, ay + uy * t + oy) then return false end
      if t >= len then break end
      s = s + step
    end
  end
  return true
end

-- Liegt im Quadrat ±half um (x, y) eine natürliche Felskachel?
local function rock_near(surface, x, y, half)
  for tx = math.floor(x - half), math.ceil(x + half) - 1 do
    for ty = math.floor(y - half), math.ceil(y + half) - 1 do
      if terrain.natural_tile_name(surface, tx, ty) == ROCK then return true end
    end
  end
  return false
end

-- Liste von Wegpunkten als {x, y}.
local function copy_points(points)
  local out = {}
  for i, p in ipairs(points) do out[i] = {x = p.x, y = p.y} end
  return out
end

-- Staub an jedem vierten Knoten (feste Versätze aus Tick und Knotennummer, Muster scripts/vibration.lua), Effekt und
-- Rumpeln am Kopf (Plan 4.6 Schritt 4).
local function surface_effects(surface, nodes, tick)
  for i = 1, #nodes, lib.BODY_STEP do
    local node = nodes[i]
    for j = 1, lib.DUST_PER_NODE do
      local angle = math.rad((tick * 11 + i * 37 + j * 97) % 360)
      local d = 1 + (tick * 7 + i * 13 + j * 29) % 3
      surface.create_trivial_smoke{name = DUST, position = {x = node.x + d * math.cos(angle), y = node.y + d * math.sin(angle)}}
    end
  end
  local head = nodes[1]
  surface.create_entity{name = DIVE, position = head}
  surface.play_sound{path = RUMBLE, position = head}
end

-- Anfragen -----------------------------------------------------------------------------------------

-- Alle Einträge der Jagd aus storage.path_requests und hunt.path weg.
function lib.drop_requests(hunt)
  local requests = storage.path_requests
  local gone = {}
  for id, entry in pairs(requests) do
    if entry.hunt == hunt.id then gone[#gone + 1] = id end
  end
  for _, id in ipairs(gone) do requests[id] = nil end
  hunt.path = nil
end

-- Zähler des Wurms fürs Protokoll (Plan 4.16), bevor hunt.worm gelöscht wird.
local function keep_counters(hunt, worm)
  hunt.last_worm =
  {
    un = worm.un, spawned = worm.spawned, reroutes = worm.reroutes, detours = worm.detours, samples = worm.samples,
    rock_box = worm.rock_box, vmax = worm.vmax, crushed = worm.crushed, sprint = worm.sprint, boost = worm.boost
  }
end

-- Wurm und Anfragen vergessen, ohne zu zerstören (getötet, fremd zerstört).
function lib.forget(hunt)
  local worm = hunt.worm
  if worm then keep_counters(hunt, worm) end
  hunt.worm = nil
  lib.drop_requests(hunt)
end

-- Abtauchen (Plan 4.11): hunt.worm weg, Anfragen weg; eine gültige Einheit zeigt ohne quiet Staub, Effekt und Rumpeln und
-- verschwindet mit raise_destroy (keine Leiche, keine Beute, kein on_segmented_unit_died [W7]). hunt.dive bleibt stehen.
-- Gibt true zurück, wenn eine gültige Einheit zerstört wurde.
function lib.dive(hunt, why, quiet)
  local worm = hunt.worm
  lib.drop_requests(hunt)
  if not worm then return false end
  keep_counters(hunt, worm)
  hunt.worm = nil
  hunt.dive = why
  local unit = worm.unit
  if not (unit and unit.valid) then return false end
  if not quiet then surface_effects(unit.surface, unit.get_body_nodes(), game.tick) end
  unit.destroy{raise_destroy = true}
  return true
end

-- Jeder Wechsel auf ohne (Plan 4.3): ein vorhandener Wurm taucht ab (Grund dive_why oder why), Anfragen weg, Phase ohne,
-- no_worm = why. In der Suche bleibt die Phase suche.
function lib.to_none(hunt, why, dive_why)
  if hunt.worm then lib.dive(hunt, dive_why or why) end
  lib.drop_requests(hunt)
  if hunt.phase ~= "suche" then hunt.phase = "ohne" end
  hunt.no_worm = why
end

-- Abtauchen aus dem Wächter: vor dem Biss Phase ohne ("abgetaucht"), in der Suche bleibt suche.
local function abort_worm(hunt, why)
  lib.to_none(hunt, "abgetaucht", why)
end

-- Anfrage senden (Plan 4.5) in pcall: Ein Fehler schreibt eine Logzeile und zählt wie eine Antwort ohne Weg. Gibt false
-- zurück, wenn die Anfrage nicht lief (die Jagd ist dann schon weitergeschaltet).
local failed

local function send(hunt, tick, force)
  local path = hunt.path
  local surface = game.get_surface(hunt.surface_index)
  local start, goal, b = path.start, hunt.zone, path.box
  local ok, id = pcall(function()
    return surface.request_path{
      bounding_box = {{-b, -b}, {b, b}},
      collision_mask = {layers = {arrakis_rock = true}},
      start = {x = start.x, y = start.y},
      goal = {x = goal.x, y = goal.y},
      force = force,
      radius = lib.PATH_RADIUS,
      path_resolution_modifier = lib.PATH_RESOLUTION,
      pathfind_flags = {prefer_straight_paths = true, cache = false}
    }
  end)
  path.tries = (path.tries or 0) + 1
  path.retry_tick = nil
  if not (ok and id) then
    log("Arrakis: request_path für Jagd " .. hunt.id .. " fehlgeschlagen: " .. tostring(id))
    path.id = nil
    if path.box == lib.PATH_BOX then
      -- wie path == nil mit ±3,5: einmal mit ±1,5 (im nächsten Takt)
      path.box = lib.PATH_BOX_MIN
      path.tries = 0
      path.retry_tick = tick
      return false
    end
    failed(hunt, tick)
    return false
  end
  storage.path_requests[id] = {hunt = hunt.id, kind = path.kind, sent = tick}
  path.id = id
  path.sent = tick
  return true
end

-- Wegkandidaten der Planung (Plan 4.5): kürzester Abstand zuerst, darin wie die Liste; höchstens PATH_MAX Anfragen.
-- force nil (aus dem Ereignis): Die Anfrage geht im nächsten Takt.
local function next_route(hunt, tick, force)
  local plan = hunt.plan
  local index = plan.route_cands and table.remove(plan.route_cands, 1)
  if not index or plan.paths >= lib.PATH_MAX then return lib.to_none(hunt, "kein-weg") end
  local cand = plan.list[index]
  local surface = game.get_surface(hunt.surface_index)
  local box = rock_near(surface, cand.x, cand.y, lib.PATH_BOX) and lib.PATH_BOX_MIN or lib.PATH_BOX
  plan.paths = plan.paths + 1
  hunt.path = {cand = index, tries = 0, kind = "plan", box = box, start = {x = cand.x, y = cand.y}, sent = tick}
  if force then
    send(hunt, tick, force)
  else
    hunt.path.retry_tick = tick
  end
end

-- Fehlschlag einer Anfrage: Planung → nächster Wegkandidat, sonst ohne ("kein-weg"); Neuplanung → abtauchen.
failed = function(hunt, tick, force)
  local path = hunt.path
  lib.drop_requests(hunt)
  if path and path.kind == "reroute" then
    if hunt.worm then hunt.worm.hold_since = nil end
    return abort_worm(hunt, "kein-weg")
  end
  return next_route(hunt, tick, force)
end

-- Spawnplanung (Plan 4.4) ----------------------------------------------------------------------------

-- Wurm oder nicht, Zeiten, Haken (Schritte 1 und 2). opts = {spawn, spawn_dir, max_debug}. Gibt phase, no_worm zurück.
function lib.begin(hunt, opts)
  opts = opts or {}
  local hunts = storage.hunts
  local T = (hunt.eta_tick - hunt.warn_tick) / 60
  local why
  if hunts.worm_off and hunts.worm_off[hunt.force_index] then
    why = "aus"
  elseif T < lib.T_MIN then
    why = "kurz"
  elseif hunt.debug and lib.counted(true) >= (opts.max_debug or math.huge) then
    why = "grenze"
  end
  if why then
    hunt.phase = "ohne"
    hunt.no_worm = why
    return hunt.phase, why
  end
  local D = math.min(lib.D_MAX, lib.V * (T - lib.LEAD - 1))
  local first = math.ceil((hunt.warn_tick + 10) / 10) * 10
  hunt.d = D
  hunt.plan_tick = math.max(first, hunt.eta_tick - spawn_lead(D) - lib.PLAN_EARLY)
  hunt.phase = "warten"
  hunt.no_worm = nil
  hunt.plan = {spawns = 0, paths = 0, checked = 0}
  local k = opts.spawn_dir or (hunts.spawn_dir and hunts.spawn_dir[hunt.force_index])
  if k then hunt.spawn_dir = k % lib.DIRECTIONS end
  local spawn = opts.spawn
  if spawn and spawn.position then
    local px = spawn.position.x or spawn.position[1]
    local py = spawn.position.y or spawn.position[2]
    hunt.spawn_hook = {position = {x = px, y = py}, direction = spawn.direction or 0, tick = spawn.tick}
    -- Ohne Planung: gleich im ersten Takt nach dem Start bereit (der Haken kann früh spawnen).
    hunt.plan_tick = first
  end
  return hunt.phase, nil
end

-- Startrichtung k0 (Plan 4.4 Schritt 3): Haken, sonst Fahrtrichtung des Ziels (der Wurm kommt von vorn), sonst Zufall.
local function start_dir(hunt)
  if hunt.spawn_dir then return hunt.spawn_dir end
  local target = hunt.target
  local v = target and target.valid and target.speed
  if v ~= nil and v ~= false and math.abs(v) >= 0.001 then
    local o = target.orientation
    if v < 0 then o = o + 0.5 end
    return math.floor(o * lib.DIRECTIONS + 0.5) % lib.DIRECTIONS
  end
  return storage.rng(0, lib.DIRECTIONS - 1)
end

-- Kandidatenliste: Abstände D, 120, 80 (soweit 10 kürzer), je 16 Richtungen k0, k0 + 1, k0 − 1, …, k0 + 8.
local function build(hunt, tick)
  local plan = hunt.plan
  plan.list = {}
  plan.next = 1
  plan.route_cands = {}
  local hook = hunt.spawn_hook
  if hook then
    plan.hook = true
    local L = distance(hook.position, hunt.zone)
    local at = hook.tick
    plan.chosen = {position = {x = hook.position.x, y = hook.position.y}, direction = hook.direction, route = {}, length = L}
    hunt.spawn_tick = at or math.max(tick + 10, hunt.eta_tick - spawn_lead(L))
    return
  end
  local k0 = start_dir(hunt)
  plan.k0 = k0
  local distances = {hunt.d}
  for _, d in ipairs(lib.D_STEPS) do
    if d <= hunt.d - lib.D_GAP then distances[#distances + 1] = d end
  end
  local n = lib.DIRECTIONS
  for _, d in ipairs(distances) do
    plan.list[#plan.list + 1] = {k = k0, d = d}
    for j = 1, n / 2 - 1 do
      plan.list[#plan.list + 1] = {k = (k0 + j) % n, d = d}
      plan.list[#plan.list + 1] = {k = (k0 - j) % n, d = d}
    end
    plan.list[#plan.list + 1] = {k = (k0 + n / 2) % n, d = d}
  end
end

-- Spawnpunkt und Körperlinie (Plan 4.4 Schritt 4 a): c und die Punkte alle 4 Kacheln bis 20 hinter c (Richtung bx, by)
-- auf Sand, dort bis 4 Kacheln kein Fahrzeug und keine Figur.
local function body_ok(probe, cx, cy, bx, by)
  if not sand(probe, cx, cy) then return false end
  local ex, ey = cx + bx * lib.BODY_LEN, cy + by * lib.BODY_LEN
  if not line_clear(probe, cx, cy, ex, ey, lib.BODY_STEP, 0) then return false end
  local m = lib.BODY_CLEAR
  local area = {{math.min(cx, ex) - m, math.min(cy, ey) - m}, {math.max(cx, ex) + m, math.max(cy, ey) + m}}
  return probe.surface.count_entities_filtered{area = area, type = BLOCKER_TYPES, limit = 1} == 0
end

-- Gewählt (Plan 4.4 Schritt 5): Spawn so, dass L mit 3 s Reserve bis eta reicht. Liegt der Nennspawn schon vor dem
-- nächsten Takt, nur wenn L / V + 1 in die Restzeit passt. Gibt true zurück, wenn gewählt.
local function choose(hunt, tick, chosen)
  local L = chosen.length
  local nominal = hunt.eta_tick - spawn_lead(L)
  if nominal < tick + 10 and not fits(hunt, L, tick) then return false end
  hunt.plan.chosen = chosen
  hunt.spawn_tick = math.max(tick + 10, nominal)
  return true
end

-- Höchstens CHECKS_PER_TICK Kandidaten prüfen (Plan 4.4 Schritt 4). Gibt true zurück, wenn einer gewählt ist.
local function check_candidates(hunt, tick)
  local plan = hunt.plan
  local surface = game.get_surface(hunt.surface_index)
  local probe = new_probe(surface)
  local P = hunt.zone
  local n = 0
  while plan.next <= #plan.list and n < lib.CHECKS_PER_TICK do
    local cand = plan.list[plan.next]
    local index = plan.next
    plan.next = plan.next + 1
    plan.checked = plan.checked + 1
    n = n + 1
    local bx, by = dir_vector(cand.k)
    local cx, cy = P.x + cand.d * bx, P.y + cand.d * by
    cand.x, cand.y = cx, cy
    if body_ok(probe, cx, cy, bx, by) then
      local len = cand.d - lib.LINE_END
      if line_clear(probe, cx, cy, cx - bx * len, cy - by * len, lib.LINE_STEP, 0) then
        local chosen = {position = {x = cx, y = cy}, direction = (cand.k + lib.DIRECTIONS / 2) % lib.DIRECTIONS,
                        route = {}, length = cand.d, k = cand.k}
        if choose(hunt, tick, chosen) then return true end
      else
        plan.route_cands[#plan.route_cands + 1] = index
      end
    end
  end
  return false
end

-- Wegkandidaten nach Abstand ordnen (stabil nach Listenplatz).
local function sort_route_cands(plan)
  table.sort(plan.route_cands, function(a, b)
    local da, db = plan.list[a].d, plan.list[b].d
    if da ~= db then return da < db end
    return a < b
  end)
end

-- Weg aus der Antwort (Plan 4.5 „Weg da“): Strecken auf Sand, nach Sichtlinie ausdünnen, Länge. Gibt route, L oder nil.
local function take_route(hunt, start, waypoints)
  local surface = game.get_surface(hunt.surface_index)
  if not surface then return nil end
  local probe = new_probe(surface)
  local points = {}
  for _, waypoint in ipairs(waypoints) do
    local p = waypoint.position
    points[#points + 1] = {x = p.x or p[1], y = p.y or p[2]}
  end
  if #points == 0 then return nil end
  -- Jede Strecke alle 2 Kacheln auf Sand: gepflasterter Fels hat die Ebene arrakis_rock nicht.
  local ax, ay = start.x, start.y
  for _, p in ipairs(points) do
    if not line_clear(probe, ax, ay, p.x, p.y, lib.LOOK_STEP, 0) then return nil end
    ax, ay = p.x, p.y
  end
  -- Ausdünnen: Ein Wegpunkt fällt weg, wenn die Strecke vom letzten behaltenen zum folgenden Sand ist (Mitte und ±1,5).
  local route = {}
  local anchor = start
  for i = 1, #points - 1 do
    local nxt = points[i + 1]
    if not line_clear(probe, anchor.x, anchor.y, nxt.x, nxt.y, lib.LOOK_STEP, lib.SIDE) then
      route[#route + 1] = points[i]
      anchor = points[i]
    end
  end
  route[#route + 1] = points[#points]
  local L = 0
  ax, ay = start.x, start.y
  for _, p in ipairs(route) do
    L = L + math.sqrt((p.x - ax) ^ 2 + (p.y - ay) ^ 2)
    ax, ay = p.x, p.y
  end
  L = L + math.sqrt((hunt.zone.x - ax) ^ 2 + (hunt.zone.y - ay) ^ 2)
  return route, L
end

-- Antwort auf eine Anfrage (on_script_path_request_finished, Plan 4.5) [W4].
local function on_path(event)
  local requests = storage.path_requests
  if not requests then return end
  local entry = requests[event.id]
  if not entry then return end
  requests[event.id] = nil
  local hunt = storage.hunts.list[entry.hunt]
  local path = hunt and hunt.path
  if not (path and path.id == event.id) then return end
  path.id = nil
  local tick = event.tick
  if event.try_again_later then
    if path.tries >= lib.PATH_TRIES then return failed(hunt, tick) end
    path.retry_tick = tick + lib.PATH_RETRY
    return
  end
  if not event.path then
    if path.box == lib.PATH_BOX then
      path.box = lib.PATH_BOX_MIN
      path.tries = 0
      path.retry_tick = tick
      return
    end
    return failed(hunt, tick)
  end
  local route, L = take_route(hunt, path.start, event.path)
  local deadline = path.kind == "reroute" and reroute_deadline(hunt) or nil
  if not route or not fits(hunt, L, tick, deadline) then return failed(hunt, tick) end
  if path.kind == "reroute" then
    local worm = hunt.worm
    if not worm then return lib.drop_requests(hunt) end
    hunt.path = nil
    worm.route = route
    worm.wp = 1
    worm.passing = nil
    worm.detour = nil
    worm.hold_since = nil
    worm.set_dest = nil
    if hunt.phase == "angriff" then hunt.phase = "anfahrt" end
    return
  end
  -- Planung: Blickrichtung auf den ersten Wegpunkt; zeigt sie nicht auf P, die Körperlinie neu prüfen.
  local plan = hunt.plan
  local cand = plan.list[path.cand]
  local start = path.start
  local first = route[1]
  if distance(first, start) < 1 and route[2] then first = route[2] end
  local k = round_dir(first.x - start.x, first.y - start.y)
  if k ~= (cand.k + lib.DIRECTIONS / 2) % lib.DIRECTIONS then
    local fx, fy = dir_vector(k)
    if not body_ok(new_probe(game.get_surface(hunt.surface_index)), start.x, start.y, -fx, -fy) then return failed(hunt, tick) end
  end
  hunt.path = nil
  local chosen = {position = {x = start.x, y = start.y}, direction = k, route = route, length = L, box = path.box, k = cand.k}
  if not choose(hunt, tick, chosen) then return failed(hunt, tick) end
end

-- Offene Anfrage im Takt: geplante Wiederholung senden, Zeitablauf (auch nach Speichern und Laden [W5]).
local function path_takt(hunt, tick, force)
  local path = hunt.path
  if path.retry_tick then
    if tick >= path.retry_tick then send(hunt, tick, force) end
    return
  end
  if path.id and path.sent + lib.PATH_TIMEOUT <= tick then
    local requests = storage.path_requests
    local entry = requests[path.id]
    -- nur den eigenen Eintrag: Nach dem Laden kann die Engine eine Kennung neu vergeben haben.
    if entry and entry.hunt == hunt.id then requests[path.id] = nil end
    path.id = nil
    if path.kind == "reroute" or path.tries >= lib.PATH_TRIES then return failed(hunt, tick, force) end
    send(hunt, tick, force)
  end
end

-- Erzeugen, Körperprüfung, Auftauchen (Plan 4.6) ------------------------------------------------------

local function spawn(hunt, tick, force)
  local plan = hunt.plan
  local chosen = plan.chosen
  local surface = game.get_surface(hunt.surface_index)
  plan.spawns = plan.spawns + 1
  local ok, unit = pcall(function()
    return surface.create_segmented_unit{name = lib.NAME, position = chosen.position, direction = chosen.direction,
                                         extended = true, force = force}
  end)
  if not ok then
    log("Arrakis: Sandwurm für Jagd " .. hunt.id .. " ließ sich nicht erzeugen: " .. tostring(unit))
    unit = nil
  end
  local nodes
  if unit then
    -- Körperprüfung: jeder vierte Knoten auf Sand in erzeugtem Chunk [W6].
    nodes = unit.get_body_nodes()
    local probe = new_probe(surface)
    for i = 1, #nodes, lib.BODY_STEP do
      if not sand(probe, nodes[i].x, nodes[i].y) then
        unit.destroy{}
        unit = nil
        break
      end
    end
  end
  if not unit then
    -- Nächster Kandidat (Planung läuft im nächsten Takt weiter); der Haken hat keinen.
    plan.chosen = nil
    if plan.hook or plan.spawns >= lib.SPAWN_MAX then return lib.to_none(hunt, "kein-weg") end
    return
  end
  local head = nodes[1]
  local dest = chosen.route[1] or hunt.zone
  hunt.worm =
  {
    unit = unit, un = unit.unit_number, spawned = tick, route = copy_points(chosen.route), wp = 1, passing = nil,
    dest = {x = dest.x, y = dest.y}, set_tick = tick, set_dest = {x = dest.x, y = dest.y},
    mode = defines.segmented_unit_activity_mode.minimal, detour = nil, reroutes = 0, hold_since = nil,
    head = {x = head.x, y = head.y}, moved = {x = head.x, y = head.y, tick = tick}, detours = 0, samples = 0,
    rock_box = 0, vmax = 0, crushed = 0, sprint = 0, boost = 0, slow = 0
  }
  hunt.spawn_tick = tick
  unit.minimum_activity_mode = defines.segmented_unit_activity_mode.minimal
  unit.speed = lib.V / 60
  unit.set_ai_state{type = defines.segmented_unit_ai_state.investigating, destination = {x = dest.x, y = dest.y}}
  hunt.phase = "anfahrt"
  surface_effects(surface, nodes, tick)
end

local function routing(hunt, tick, force)
  local plan = hunt.plan
  if not plan.list then build(hunt, tick) end
  if plan.chosen then
    if tick >= hunt.spawn_tick then spawn(hunt, tick, force) end
    return
  end
  -- Frist: ohne gewählten Kandidaten bis eta − 1440 → ohne (auch mit offener Anfrage; eine späte Antwort findet nichts).
  if tick >= hunt.eta_tick - lib.SPAWN_DEADLINE then return lib.to_none(hunt, "kein-weg") end
  if hunt.path then return path_takt(hunt, tick, force) end
  if plan.next <= #plan.list then
    if check_candidates(hunt, tick) then return end
    if plan.next <= #plan.list then return end
  end
  -- Auch nach einem gescheiterten Spawn des letzten Listenkandidaten (dann kam der Takt nicht durch die Prüfung oben).
  sort_route_cands(plan)
  next_route(hunt, tick, force)
end

-- Steuern, Wächter, Tempo (Plan 4.7 bis 4.9) ----------------------------------------------------------

-- Restweg Kopf → (Umweg) → offene Wegpunkte → P (Kacheln).
local function rest_path(worm, hx, hy, P)
  local L = 0
  local ax, ay = hx, hy
  local function go(p)
    L = L + math.sqrt((p.x - ax) ^ 2 + (p.y - ay) ^ 2)
    ax, ay = p.x, p.y
  end
  if worm.detour then go(worm.detour) end
  for i = worm.wp, #worm.route do go(worm.route[i]) end
  go(P)
  return L
end

-- Umweg (Plan 4.8 Schritt 4): Längen 30, 15, 8, Winkel ±30, ±60, ±90 um die Kopfrichtung; erste freie Strecke.
local function find_detour(probe, hx, hy, h_x, h_y, tick)
  for i, len in ipairs(lib.DETOUR_RADII) do
    for _, a in ipairs(lib.DETOUR_ANGLES) do
      local rx, ry = rotate(h_x, h_y, a)
      local px, py = hx + len * rx, hy + len * ry
      if line_clear(probe, hx, hy, px, py, lib.LOOK_STEP, lib.SIDE) then
        return {x = px, y = py, tick = tick, reached = lib.DETOUR_REACHED[i]}
      end
    end
  end
  return nil
end

-- Neuplanung vom Kopf (Plan 4.8 Schritt 5): Art reroute, währenddessen halten.
local function start_reroute(hunt, tick, force, hx, hy)
  local worm = hunt.worm
  local surface = game.get_surface(hunt.surface_index)
  worm.reroutes = worm.reroutes + 1
  worm.hold_since = tick
  local box = rock_near(surface, hx, hy, lib.PATH_BOX) and lib.PATH_BOX_MIN or lib.PATH_BOX
  hunt.path = {tries = 0, kind = "reroute", box = box, start = {x = hx, y = hy}, sent = tick}
  send(hunt, tick, force)
end

-- Knotenschub (Ersatz 2): neuer Kopf delta voraus Richtung (dx, dy), die übrigen Knoten im Abstand 1 längs der alten
-- Spur, der letzte fällt weg. In pcall; ein Fehler schreibt eine Logzeile, der Takt schiebt dann nicht.
local function push_nodes(hunt, unit, nodes, dx, dy, delta)
  local hx, hy = nodes[1].x + dx * delta, nodes[1].y + dy * delta
  local trace = {{x = hx, y = hy}}
  for i = 1, #nodes do trace[#trace + 1] = nodes[i] end
  local out = {{x = hx, y = hy}}
  local seg, pos = 1, 0          -- Strecke trace[seg] → trace[seg + 1], Lage darauf
  for _ = 2, #nodes do
    local need = 1
    while seg < #trace do
      local a, b = trace[seg], trace[seg + 1]
      local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
      if len - pos >= need then
        pos = pos + need
        local f = len > EPS and pos / len or 0
        out[#out + 1] = {x = a.x + (b.x - a.x) * f, y = a.y + (b.y - a.y) * f}
        break
      end
      need = need - (len - pos)
      seg = seg + 1
      pos = 0
    end
    if seg >= #trace then break end
  end
  local ok, err = pcall(function() unit.set_body_nodes(out) end)
  if not ok then
    log("Arrakis: set_body_nodes für Jagd " .. hunt.id .. " fehlgeschlagen: " .. tostring(err))
    return nil
  end
  return hx, hy
end

-- Ein Takt mit Wurm (Phasen anfahrt, angriff, suche).
local function drive(hunt, tick, force)
  local worm = hunt.worm
  local unit = worm.unit
  if not (unit and unit.valid) then
    lib.forget(hunt)
    return lib.to_none(hunt, "verloren")
  end
  local surface = unit.surface
  local nodes = unit.get_body_nodes()
  local head = nodes[1]
  local hx, hy = head.x, head.y
  local back = nodes[3] or nodes[#nodes]
  local h_x, h_y = unit_vector(hx - back.x, hy - back.y)
  if not h_x then h_x, h_y = unit_vector(worm.dest.x - hx, worm.dest.y - hy) end
  if not h_x then h_x, h_y = 0, -1 end
  -- Tempo aus dem Kopfweg seit dem letzten Takt (Kacheln/s, Plan 4.9 „Sprint-Ersatz“).
  local measured = math.sqrt((hx - worm.head.x) ^ 2 + (hy - worm.head.y) ^ 2) * 6
  worm.head = {x = hx, y = hy}
  local probe = new_probe(surface)

  -- 1. Sicherheitsnetz: Kopf auf Fels oder in ungeneriertem Chunk → sofort abtauchen.
  if not sand(probe, hx, hy) then return abort_worm(hunt, "fels") end

  -- Messung (Plan 4.8 Schritt 7): Kopfbox ±1,5 (Ecken und Mitte) auf Fels, größtes Tempo.
  worm.samples = worm.samples + 1
  local half = 1.5
  if not (sand(probe, hx - half, hy - half) and sand(probe, hx + half, hy - half) and sand(probe, hx - half, hy + half)
      and sand(probe, hx + half, hy + half)) then
    worm.rock_box = worm.rock_box + 1
  end
  local v_now = unit.speed * 60
  if v_now > worm.vmax then worm.vmax = v_now end

  local P = hunt.zone
  local R = lib.BITE_REACH + (hunt.r or DEFAULT_R)
  local d = math.sqrt((P.x - hx) ^ 2 + (P.y - hy) ^ 2)
  local phase = hunt.phase

  -- Suche: nah genug an P → abtauchen (die Jagd bleibt bis end_tick in der Suche).
  if phase == "suche" and d <= lib.SEARCH_REACHED then
    lib.dive(hunt, "suche")
    return
  end

  -- Offene Neuplanung: Wiederholung, Zeitablauf, höchstens HOLD_MAX halten; passt kein Weg mehr in die Frist (unter 1 s
  -- Rest), endet sie gleich als Fehlschlag (Gegenprüfung 0.8.0, wie reroute_deadline).
  if hunt.path then
    path_takt(hunt, tick, force)
    if hunt.worm ~= worm then return end
    if hunt.path and worm.hold_since
        and (tick - worm.hold_since >= lib.HOLD_MAX or not fits(hunt, 0, tick, reroute_deadline(hunt))) then
      return failed(hunt, tick, force)
    end
  end
  local rerouting = hunt.path ~= nil

  -- Umweg erreicht oder abgelaufen.
  local detour = worm.detour
  if detour and (math.sqrt((detour.x - hx) ^ 2 + (detour.y - hy) ^ 2) <= detour.reached or tick - detour.tick >= lib.DETOUR_MAX) then
    worm.detour = nil
    detour = nil
  end
  -- Wegpunkt: weiter, sobald die Strecke zum folgenden frei ist (nach dem letzten: zum Reichweitenpunkt vor P, wie die
  -- Vorausschau mit Haltepunkt R). Abweichung von Plan 4.7 (Trockenlauf 0.8.0, Tasche mit Knick): 6 Kacheln vor dem
  -- Wegpunkt wechselt er nicht blind, denn dann schnitte die Strecke zum folgenden die innere Felsecke, und die Umwege um die
  -- Kopfrichtung führten ihn aus dem Gang. Er fährt geradeaus weiter (Fahrziel 18 Kacheln voraus, die Engine patrouilliert
  -- nicht), bis die Strecke frei ist; erst 6 Kacheln hinter dem Wegpunkt wechselt er doch, dann greift der Wächter.
  local route = worm.route
  local straight = false
  if worm.wp <= #route then
    local current = route[worm.wp]
    local following = route[worm.wp + 1]
    local fx, fy
    if following then
      fx, fy = following.x, following.y
    else
      local f = d > R and (d - R) / d or 0
      fx, fy = hx + (P.x - hx) * f, hy + (P.y - hy) * f
    end
    if line_clear(probe, hx, hy, fx, fy, lib.LOOK_STEP, lib.SIDE) then
      worm.wp = worm.wp + 1
      worm.passing = nil
    elseif math.sqrt((current.x - hx) ^ 2 + (current.y - hy) ^ 2) <= lib.WP_NEAR then
      worm.passing = true
      straight = true
    elseif worm.passing then
      worm.wp = worm.wp + 1
      worm.passing = nil
    end
  end
  local open = worm.wp <= #route

  -- Richtung Kopf → P und Reichweitenpunkt P − R · u.
  local u_x, u_y = unit_vector(P.x - hx, P.y - hy)
  if not u_x then u_x, u_y = h_x, h_y end
  local reach_len = math.max(0, d - R)

  -- Anfahrt ⇄ Angriff (Plan 4.3, 4.9).
  if phase == "anfahrt" and not open and not detour and not rerouting and d <= lib.ATTACK_RANGE
      and line_clear(probe, hx, hy, hx + u_x * reach_len, hy + u_y * reach_len, lib.LOOK_STEP, 0) then
    phase = "angriff"
  elseif phase == "angriff" and (d > lib.ATTACK_LEAVE or open) then
    phase = "anfahrt"
  end

  -- Fahrziel und Halteabstand (Plan 4.7, 4.8 Schritt 2).
  local dest, hold
  if detour then
    dest, hold = detour, detour.reached
  elseif open then
    dest, hold = route[worm.wp], lib.WP_NEAR
    if straight then dest = {x = hx + h_x * lib.LOOKAHEAD, y = hy + h_y * lib.LOOKAHEAD} end
  elseif phase == "angriff" then
    local far_x, far_y = P.x + u_x * lib.BEHIND, P.y + u_y * lib.BEHIND
    if line_clear(probe, P.x, P.y, far_x, far_y, lib.LOOK_STEP, 0) and sand(probe, P.x, P.y) then
      dest = {x = far_x, y = far_y}
    else
      dest = {x = P.x + u_x * lib.BEHIND_MIN, y = P.y + u_y * lib.BEHIND_MIN}
    end
    hold = nil
  elseif phase == "suche" then
    dest, hold = P, lib.SEARCH_REACHED
  else
    dest, hold = P, R
  end

  -- Vorausschau (Plan 4.8 Schritte 3 bis 5); während einer Neuplanung hält er und schaut nicht.
  local force_state = false
  if not rerouting then
    local blocked = false
    if phase == "angriff" and not detour then
      local L = math.min(lib.LOOKAHEAD, reach_len)
      if L > 0 then blocked = not line_clear(probe, hx, hy, hx + u_x * L, hy + u_y * L, lib.LOOK_STEP, 0) end
    else
      local to_dest = math.sqrt((dest.x - hx) ^ 2 + (dest.y - hy) ^ 2)
      local L = math.min(lib.LOOKAHEAD, to_dest - hold)
      if L > 0 then
        local g_x, g_y = unit_vector(dest.x - hx, dest.y - hy)
        blocked = not line_clear(probe, hx, hy, hx + g_x * L, hy + g_y * L, lib.LOOK_STEP, lib.SIDE)
        if not blocked and not detour then
          -- Kopfrichtung nur so weit, wie der Bogen bis zur Drehung auf dest lang ist (Wenderadius · Winkel). Abweichung von
          -- Plan 4.8 Schritt 3 (Trockenlauf 0.8.0): Nach dem Wechsel an einer Gangbiegung sähe die volle Länge die Wand
          -- gegenüber, die er nie erreicht, und der Umweg um die Kopfrichtung führte aus dem Gang.
          local a = math.acos(math.max(-1, math.min(1, h_x * g_x + h_y * g_y)))
          local L_h = math.min(L, lib.TURN_RADIUS * a)
          blocked = not line_clear(probe, hx, hy, hx + h_x * L_h, hy + h_y * L_h, lib.LOOK_STEP, lib.SIDE)
        end
      end
    end
    if blocked then
      local found = find_detour(probe, hx, hy, h_x, h_y, tick)
      if found then
        worm.detour = found
        worm.detours = worm.detours + 1
        detour = found
        dest, hold = found, found.reached
        force_state = true
        if phase == "angriff" then phase = "anfahrt" end
      elseif worm.reroutes < lib.REROUTE_MAX and fits(hunt, 0, tick, reroute_deadline(hunt)) then
        -- Nur, solange überhaupt ein Weg in die Frist passen kann (Gegenprüfung 0.8.0): Ab 1 s vor eta (in der Suche vor
        -- end_tick) hielte er sonst für eine Antwort, die nie gilt. So taucht er gleich ab ("kein-weg"), und ohne Wurm beißt
        -- es bei 0 wie 0.7.0, nach 0 im selben Takt (Biss-Fenster).
        hunt.phase = phase
        start_reroute(hunt, tick, force, hx, hy)
        if hunt.worm ~= worm then return end
        rerouting = hunt.path ~= nil
        if phase == "angriff" then phase = "anfahrt" end
      else
        return abort_worm(hunt, "kein-weg")
      end
    end
  end
  hunt.phase = phase

  -- Zustand (Plan 4.7): bei Zielwechsel über 2 Kacheln sofort, sonst alle 30 Ticks, immer investigating [W9].
  local set = worm.set_dest
  if force_state or not set or math.sqrt((dest.x - set.x) ^ 2 + (dest.y - set.y) ^ 2) > lib.GOAL_MOVE
      or tick - worm.set_tick >= lib.STATE_TICKS then
    unit.set_ai_state{type = defines.segmented_unit_ai_state.investigating, destination = {x = dest.x, y = dest.y}}
    worm.set_tick = tick
    worm.set_dest = {x = dest.x, y = dest.y}
  end
  worm.dest = {x = dest.x, y = dest.y}

  -- Aktivität: full im Angriff, sonst minimal; nur bei Wechsel schreiben [W13, W16].
  local mode = phase == "angriff" and defines.segmented_unit_activity_mode.full or defines.segmented_unit_activity_mode.minimal
  if worm.mode ~= mode then
    unit.minimum_activity_mode = mode
    worm.mode = mode
  end

  -- Stillstand (Plan 4.8 Schritt 6): nicht haltend und 300 Ticks weniger als 0,5 Kacheln Bewegung.
  local moved = worm.moved
  if worm.hold_since or math.sqrt((moved.x - hx) ^ 2 + (moved.y - hy) ^ 2) > lib.STALL_DIST then
    worm.moved = {x = hx, y = hy, tick = tick}
  elseif tick - moved.tick >= lib.STALL_TICKS then
    return abort_worm(hunt, "stillstand")
  end

  -- Tempo (Plan 4.9): v in Kacheln/s, nil = nichts schreiben (die Engine fährt V).
  local vmax = lib.SPRINT and lib.V_SPRINT or lib.V
  local t = (hunt.eta_tick - tick) / 60
  local S = rest_path(worm, hx, hy, P) - R
  local v
  local holding = false
  if rerouting then
    v, holding = 0, true
  elseif phase == "angriff" then
    if t > 0 then
      if S <= 0 then
        v, holding = 0, true
      else
        v = math.min(vmax, S / t)
      end
    else
      v = vmax
    end
  elseif phase == "anfahrt" then
    if S / lib.V > t - 1 then v = math.min(vmax, math.max(0, S) / math.max(t - 1, 1 / 6)) end
  end
  if rerouting then
    worm.hold_since = worm.hold_since or tick
  elseif holding then
    worm.hold_since = worm.hold_since or tick
  else
    worm.hold_since = nil
  end

  -- Sprint-Ersatz [W3]: Nach einem Sprint-Takt zählt slow, wenn der Kopf unter 0,9 des geschriebenen Tempos blieb.
  -- Steht der Kopf (in STALL_TICKS käme er nicht STALL_DIST weit), hält ihn etwas auf [W10]: Das ist kein Sprintversagen,
  -- sondern Sache des Stillstands (Plan 4.8 Schritt 6, 4.10 Schritt 4). Abweichung von Plan 4.9 (Trockenlauf 0.8.0): Sonst
  -- schöbe die Ersatzstufe einen festgefahrenen Wurm in der Anfahrt weiter, und der Stillstand griffe nie.
  local last = worm.last_v
  if last and last > lib.V then
    local standing = measured * lib.STALL_TICKS / 60 < lib.STALL_DIST
    if measured < lib.BOOST_MIN * last and not standing then worm.slow = worm.slow + 1 else worm.slow = 0 end
    if worm.slow >= lib.BOOST_TAKTS and worm.boost < 2 then
      worm.boost = worm.boost + 1
      worm.slow = 0
      log(string.format("Arrakis: Sandwurm der Jagd %d sprintet nicht (%.2f statt %.2f Kacheln/s), Ersatzstufe %d",
        hunt.id, measured, last, worm.boost))
    end
  else
    worm.slow = 0
  end
  -- Der fehlende Weg zählt gegen das Tempo der Engine allein: Der Kopfweg des letzten Takts enthält den Schub von damals,
  -- sonst wechselten volle und fast leere Schübe ab (im Mittel etwa 4,7 statt 6 Kacheln/s).
  local engine = measured - (worm.push or 0) * 6
  local pushed = 0
  if v then
    unit.speed = v / 60
    if v > lib.V then
      worm.sprint = worm.sprint + 1
      local delta = math.min(lib.PUSH_MAX, (v - engine) * 10 / 60)
      if delta > 0 and worm.boost == 1 then
        unit.move_forward(delta)
        pushed = delta
      elseif delta > 0 and worm.boost >= 2 then
        local g_x, g_y = unit_vector(dest.x - hx, dest.y - hy)
        if g_x then
          local nx, ny = push_nodes(hunt, unit, nodes, g_x, g_y, delta)
          if nx then pushed = delta end
          -- Der Wächter prüft den neuen Kopf im selben Takt.
          if nx and not sand(probe, nx, ny) then return abort_worm(hunt, "fels") end
        end
      end
    else
      worm.slow = 0
    end
  end
  worm.push = pushed
  worm.last_v = v
end

-- Ein Takt der Jagd (Plan 4.3 Schritt 2 b), nur aus worms.lua mit der LuaForce der Würmer.
function lib.step(hunt, tick, worm_force)
  local phase = hunt.phase
  if phase == "warten" then
    if tick < hunt.plan_tick then return end
    hunt.phase = "routing"
    phase = "routing"
  end
  if phase == "routing" then return routing(hunt, tick, worm_force) end
  if hunt.worm then return drive(hunt, tick, worm_force) end
  if phase == "anfahrt" or phase == "angriff" then return lib.to_none(hunt, "verloren") end
end

-- Abfragen, Waisen, Aufräumen (Plan 4.13, 4.14, 4.5) -------------------------------------------------

-- Kopf des Wurms der Jagd und alle Knoten (vorne zuerst, Kopie), oder nil.
function lib.head_of(hunt)
  local worm = hunt and hunt.worm
  local unit = worm and worm.unit
  if not (unit and unit.valid) then return nil, nil end
  local nodes = unit.get_body_nodes()
  return nodes[1], nodes
end

-- Zahl der Jagden mit Wurm oder Wurm in Planung (warten bis angriff, suche mit Wurm); debug true: nur Befehlsjagden,
-- sonst nur reguläre.
function lib.counted(debug)
  local n = 0
  local want = debug == true
  for _, hunt in pairs(storage.hunts.list) do
    if (hunt.debug == true) == want and (ACTIVE[hunt.phase] or (hunt.phase == "suche" and hunt.worm)) then n = n + 1 end
  end
  return n
end

-- Waisen (Plan 4.14): Würmer unseres Prototyps ohne Jagd auf den Oberflächen (nil: alle) → raise_destroy. Testwürmer
-- bleiben. Gibt die Zahl zurück.
function lib.sweep(surfaces)
  local owned = {}
  for _, hunt in pairs(storage.hunts.list) do
    if hunt.worm and hunt.worm.un then owned[hunt.worm.un] = true end
  end
  local n = 0
  for _, surface in pairs(surfaces or game.surfaces) do
    if surface and surface.valid then
      for _, unit in pairs(surface.get_segmented_units()) do
        if unit.valid and not owned[unit.unit_number] and unit.prototype.name:sub(1, #lib.PREFIX) == lib.PREFIX then
          unit.destroy{raise_destroy = true}
          n = n + 1
        end
      end
    end
  end
  return n
end

-- Alte Anfragen räumen (Plan 4.5 „Aufräumen“): Jagd fehlt, hunt.path zeigt nicht mehr auf sie oder älter als TIDY_AGE.
function lib.tidy(tick)
  local requests = storage.path_requests
  if not requests then return end
  local list = storage.hunts.list
  local gone = {}
  for id, entry in pairs(requests) do
    local hunt = list[entry.hunt]
    if not (hunt and hunt.path and hunt.path.id == id) or tick - (entry.sent or 0) >= lib.TIDY_AGE then gone[#gone + 1] = id end
  end
  for _, id in ipairs(gone) do requests[id] = nil end
end

lib.events =
{
  [defines.events.on_script_path_request_finished] = on_path
}

return lib
