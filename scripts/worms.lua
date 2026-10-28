-- Würmer (Phase 3d1, docs/plan-3d1.md 4.4 bis 4.10, 4.13, 4.14, 4.16): Takte, Schonfrist je Force, Wurmzeichen,
-- Jagden, Biss, Warnungen, Sandwurm-Force, Briefing-Chat, /arrakis-worm, Migration Schema 3 und 4 und Entfernen.
-- Bibliothek für __core__/lualib/event_handler. Daten nur in storage (Schema 4, siehe scripts/migrate.lua).
-- Die Modultabelle heißt lib; andere Dateien binden sie als worms_lib.
--
-- Nur dieses Modul hat die Wurm-Takte (Plan 4.4): on_nth_tick(60) ruft in fester Reihenfolge 1. vibration.tick,
-- 2. vibration.careful_tick, 3. Schonfrist, 4. vibration.unrest_tick, 5. Wurmzeichen, 6. Sekundenarbeit der Jagden,
-- 7. vibration.overlay_tick; on_nth_tick(10) führt die Jagden nach und beißt genau bei eta_tick.
--
-- Jagd storage.hunts.list[id] (Plan 4.2): Zustände warning → (biting) → searching → Ende. Entschieden wird erst am
-- Biss-Tick (Plan 4.7): weg, entkommen (getragen, andere Oberfläche, ganz auf Fels, außer Reichweite) oder Biss.
-- Befehlsjagden (debug) zählen nicht mit, sperren nichts und enden ohne Rücksetzen, Ruhe, Statistik und Lehrjagd-Merker.
-- [Vn] markiert ungeprüftes Engine-Verhalten (Plan 4.17).
--
-- Phase 3d2 (docs/plan-3d2.md 4.1, 4.3, 4.9 bis 4.14, 4.16, 4.18): Der Wurm selbst fährt in scripts/sandworm.lua; dieses
-- Modul bleibt Herr der Jagd. Der 10-Tick-Takt ruft je Jagd in fester Reihenfolge track, sandworm.step, Zerdrücken und
-- Biss-Fenster (Plan 4.3); der Biss kommt nie vor eta_tick und höchstens BITE_WINDOW Ticks danach (Ersatzbiss). Dazu
-- Tod und Verlust des Wurms, Grenze der Befehlsjagden, Migration Schema 4, Protokoll und Waisen beim Entfernen.
-- [Wn] markiert ungeprüftes Engine-Verhalten aus Plan 3d2 (4.17).

local terrain = require("scripts.terrain")
local harvester = require("scripts.harvester")
local vibration_lib = require("scripts.vibration")
local worms_gui = require("scripts.worms-gui")
local sandworm_lib = require("scripts.sandworm")

local lib = {}

-- Countdown (Ticks) einer Jagd.
lib.WARN_TICKS = 3600
-- Countdown der Lehrjagd (erste Jagd jeder Force auf einen Spice-Ernter).
lib.TEACH_TICKS = 5400
-- So lange sucht der Wurm nach einem Fehlschlag (Ticks), dann Ende.
lib.SEARCH_TICKS = 600
-- Bissradius (Kacheln, Abstand zur Box).
lib.BITE_RADIUS = 4
-- Tempo des Wurms (Kacheln/s) für die Reichweite: reach = WORM_SPEED · Countdown in Sekunden.
lib.WORM_SPEED = 3.5
-- Ruhe des Sektors nach einer Jagd (Ticks, Grenzen einschließlich).
lib.REST_MIN = 7200
lib.REST_MAX = 14400
-- Höchstens so viele Jagden zugleich (ohne Befehlsjagden), über alle Forces und Oberflächen.
lib.MAX_HUNTS = 3
-- Schonfrist: nach „Ornithopter“ bzw. nach der ersten Landung auf Arrakis (Ticks).
lib.GRACE_ORNITHOPTER = 36000
lib.GRACE_LANDING = 108000
-- Biss „Schwer beschädigt“: Anteil der Gesundheit, mit dem ein Spice-Ernter überlebt.
lib.HEAVY_HEALTH = 0.1
-- Nach /arrakis-uninstall so lange kein neues Wurmzeichen (Ticks).
lib.PAUSE_TICKS = 36000
-- /arrakis-worm: erlaubte Sekunden.
lib.DEBUG_MIN = 5
lib.DEBUG_MAX = 600
-- Force der Würmer (wie tb.worm_force, scripts/testbench/runner.lua).
lib.FORCE = "arrakis-sandworm"
-- Symbol für Alarm, Kartenmarkierung und Fenster.
lib.ICON = {type = "virtual", name = "arrakis-wormsign"}
-- Standardwahl (Plan 1, Max kann widersprechen): Fahrzeuge werden Ziel eines Wurmzeichens (sonst heizen sie nur).
lib.VEHICLE_TARGETS = true
-- Standardwahl (Plan 1 „Totalverlust“): Beim Totalverlust sterben die Insassen des Ernters mit.
lib.TOTAL_LOSS_OCCUPANTS = true

-- Phase 3d2 (docs/plan-3d2.md 4.1). Reichweite des Bisses über die Zielbox hinaus: R = BITE_REACH + r (Kacheln, wie
-- sandworm.lua); Biss-Fenster nach eta_tick (Ticks), danach Ersatzbiss.
lib.BITE_REACH = sandworm_lib.BITE_REACH
lib.BITE_WINDOW = 180
-- Zerdrücken (Plan 4.10): Radius um die Kopfmitte, Schutzzone um den Zielpunkt jeder laufenden Jagd (BITE_RADIUS + 1).
lib.CRUSH_RADIUS = 2.5
lib.ZONE_RADIUS = 5
-- Höchstens so viele Befehlsjagden mit Wurm zugleich (Plan 4.13); reguläre begrenzt MAX_HUNTS.
lib.MAX_DEBUG_WORMS = 3
-- Protokoll: die letzten so vielen beendeten Jagden (Plan 4.16).
lib.LOG_SIZE = 20
-- Plan 1 „Zerdrücken“, Max 27.10.: Auch Fahrzeuge (VEHICLE_TYPES, auch Spice-Ernter) und Figuren sterben im Weg, ohne
-- eigenen Alarm; ein Spice-Ernter nach der Einstellung arrakis-worm-bite wie beim Biss (devour), Insassen wie beim
-- Totalverlust. true: Das Zerdrücken schont Fahrzeuge und Figuren (die alte Standardwahl des Plans bis 27.10.).
-- Diesen Wert nennen auch die Texte arrakis-sandworm-small und arrakis-wormsign-tip (locale/*/arrakis.cfg) und
-- gui-careful-tooltip (locale/*/messages.cfg); T21 Schritt 8 liest ihn hier.
lib.CRUSH_SPARES_VEHICLES = false
-- Plan 1 „Wurm getötet“, Max 27.10.: ja. Ein Wurm, der vor 0 stirbt, beendet die Jagd als killed, das Ziel ist gerettet.
-- false: Die Jagd läuft ohne Wurm weiter (Phase ohne, "verloren") und beißt bei 0 wie 0.7.0; killed zählt trotzdem.
lib.KILL_RESCUES = true
-- Plan 1 „ROUTING“, Max 27.10.: ja. Ohne Sandlinie und ohne Weg (Phase ohne, "kein-weg") beißt es bei 0 wie 0.7.0.
-- false: Die Jagd entfällt still (Ende "quiet": Rücksetzen und Ruhe, keine Statistik, kein Biss).
lib.NO_ROUTE_BITE = true

local FORCE = lib.FORCE
local ICON = lib.ICON
local ERUPTION = "arrakis-worm-eruption"
local WORMSIGN_SOUND = "arrakis-wormsign"
local BITE_SETTING = "arrakis-worm-bite"
local FLYER = "arrakis-ornithopter"
local ARRAKIS = "arrakis"
local ORNITHOPTER_TECH = "arrakis-ornithopter"
local DISCOVERY_TECH = "planet-discovery-arrakis"
local HARVESTING_TECH = "arrakis-spice-harvesting"
local HARVESTER = harvester.NAME

-- Forces ohne Schonfrist und ohne Ziele (Plan 4.6).
local EXEMPT = {enemy = true, neutral = true, [FORCE] = true}
-- Fahrzeuge (Jagd-Art "vehicle", Insassen teilen ihr Los).
local VEHICLE_TYPES =
{
  car = true,
  ["spider-vehicle"] = true,
  locomotive = true,
  ["cargo-wagon"] = true,
  ["fluid-wagon"] = true,
  ["artillery-wagon"] = true
}
-- Nie Opfer eines Bisses (Plan 4.9 Schritt 3).
local NO_VICTIM =
{
  resource = true,
  corpse = true,
  ["character-corpse"] = true,
  ["entity-ghost"] = true,
  ["tile-ghost"] = true,
  cliff = true,
  ["spider-leg"] = true
}

-- Nie zerdrückt (Plan 4.10 Schritt 2), dazu alles, was victim_ok ausnimmt; Fahrzeuge und Figuren nur mit
-- CRUSH_SPARES_VEHICLES = true. Rampen und Stützen gehören zur Hochbahn: Ohne sie hätte ein Zug, der über der Spur
-- verschont bleibt, nichts mehr, worauf er fährt.
local NO_CRUSH =
{
  ["elevated-straight-rail"] = true,
  ["elevated-half-diagonal-rail"] = true,
  ["elevated-curved-rail-a"] = true,
  ["elevated-curved-rail-b"] = true,
  ["rail-ramp"] = true,
  ["rail-support"] = true,
  segment = true,
  ["segmented-unit"] = true
}
-- Schienenfahrzeuge: Über dem Boden (draw_data.height > 0, auf Hochschiene oder Rampe) zerdrückt der Wurm sie nicht,
-- wie die Hochschiene darunter (Gegenprüfung 0.8.0; draw_data gibt es nur für diese Typen, A23 classes.d.ts:7849).
local ROLLING_STOCK =
{
  locomotive = true,
  ["cargo-wagon"] = true,
  ["fluid-wagon"] = true,
  ["artillery-wagon"] = true
}
-- Halbe Diagonale, wenn das Ziel fehlt (Spice-Ernter, Plan 4.14).
local DEFAULT_R = 1.58
-- Phasen, in denen sandworm.step läuft (Plan 4.3 Schritt 2 b); suche nur mit Wurm.
local STEP_PHASES = {warten = true, routing = true, anfahrt = true, angriff = true}

local RING_RED = {r = 1, g = 0.15, b = 0.1, a = 0.9}
local TEXT_RED = {r = 1, g = 0.3, b = 0.2}
local GREEN = {r = 0.2, g = 0.8, b = 0.2, a = 0.9}

-- Hilfen ----------------------------------------------------------------------------------------

local function distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function gps(surface, position)
  return string.format("[gps=%d,%d,%s]", math.floor(position.x), math.floor(position.y), surface.name)
end

-- Ort auf der Oberfläche der Jagd als GPS-Text; fehlt die Oberfläche, nur die Koordinaten.
local function gps_of(surface_index, position)
  local surface = game.get_surface(surface_index)
  if surface then return gps(surface, position) end
  return string.format("%d, %d", math.floor(position.x), math.floor(position.y))
end

-- Zeit m:ss aus Ticks (aufgerundet auf ganze Sekunden).
local function mmss(ticks)
  local s = math.max(0, math.ceil(ticks / 60))
  return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function seconds_left(eta, tick)
  return math.max(0, math.ceil((eta - tick) / 60))
end

local function force_of(index)
  local force = index and game.forces[index]
  if force and force.valid then return force end
  return nil
end

local function copy(record)
  if not record then return nil end
  local out = {}
  for key, value in pairs(record) do out[key] = value end
  return out
end

-- Antwort an den Spieler; ohne Spieler (Serverkonsole, RCON) an RCON und ins Log (wie /arrakis-uninstall).
local function reply(player, message)
  if player then
    player.print(message)
  else
    rcon.print(message)
    log(message)
  end
end

-- Abstand von (cx, cy) zum nächsten Punkt der Box (gedreht: umschließendes Rechteck wie terrain.has_sand_under).
local function box_distance(entity, cx, cy)
  local box = entity.bounding_box
  local left_top, right_bottom = box.left_top, box.right_bottom
  local x1, y1, x2, y2 = left_top.x, left_top.y, right_bottom.x, right_bottom.y
  local orientation = box.orientation
  if orientation and orientation ~= 0 then
    local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
    local hw, hh = (x2 - x1) / 2, (y2 - y1) / 2
    local angle = orientation * 2 * math.pi
    local c, s = math.abs(math.cos(angle)), math.abs(math.sin(angle))
    local ex, ey = hw * c + hh * s, hw * s + hh * c
    x1, y1, x2, y2 = mx - ex, my - ey, mx + ex, my + ey
  end
  local dx = math.max(x1 - cx, 0, cx - x2)
  local dy = math.max(y1 - cy, 0, cy - y2)
  return math.sqrt(dx * dx + dy * dy)
end

local function kind_of(entity)
  if entity.name == HARVESTER then return "harvest" end
  if VEHICLE_TYPES[entity.type] then return "vehicle" end
  return "building"
end

-- Sandwurm-Force --------------------------------------------------------------------------------

-- Feindschaft in beide Richtungen, ohne Waffenruhe (wie tb.worm_force).
local function set_hostile(worm, other)
  if other.index == worm.index or other.name == "neutral" then return end
  worm.set_friend(other, false)
  other.set_friend(worm, false)
  worm.set_cease_fire(other, false)
  other.set_cease_fire(worm, false)
end

-- Legt die Sandwurm-Force bei Bedarf an (pcall: höchstens 64 Forces) und macht sie zu allen feindlich; nil, wenn es
-- keinen Platz gibt.
function lib.ensure_force()
  local worm = game.forces[FORCE]
  if not worm then
    local ok = pcall(game.create_force, FORCE)
    worm = game.forces[FORCE]
    if not (ok and worm) then
      log("Arrakis: Sandwurm-Force " .. FORCE .. " ließ sich nicht anlegen")
      return nil
    end
  end
  for _, other in pairs(game.forces) do set_hostile(worm, other) end
  return worm
end

-- Schonfrist (Plan 4.6) ---------------------------------------------------------------------------

-- Datensatz der Force, bei Bedarf angelegt; nil für enemy, neutral und die Sandwurm-Force.
function lib.grace_of(force)
  if not (force and force.valid) or EXEMPT[force.name] then return nil end
  local grace = storage.grace
  local g = grace[force.index]
  if not g then
    g = {awake = false, first_hunt_done = false}
    grace[force.index] = g
  end
  return g
end

-- active_from = Minimum aus ornithopter_tick + 36000 und landed_tick + 108000; nil ohne beide.
local function compute_active(g)
  local active
  if g.ornithopter_tick then active = g.ornithopter_tick + lib.GRACE_ORNITHOPTER end
  if g.landed_tick then
    local landing = g.landed_tick + lib.GRACE_LANDING
    if not active or landing < active then active = landing end
  end
  return active
end

-- Chatzeile, wenn der Termin neu ist oder früher als zuletzt genannt. Ein schon erreichter Termin wird nur gemerkt:
-- Im selben Takt kommt „Die Wüste ist erwacht“.
local function announce(force, g, tick)
  if g.awake or not g.active_from then return end
  if g.announced and g.active_from >= g.announced then return end
  g.announced = g.active_from
  if g.active_from > tick then force.print({"arrakis-message.msg-grace-start", mmss(g.active_from - tick)}) end
end

local function reschedule(force, g, tick)
  if g.awake then return end
  g.active_from = compute_active(g)
  announce(force, g, tick)
end

-- Ein verbundener Spieler der Force steht wirklich auf Arrakis (physical_surface, nicht die Fernsicht) [V3].
local function landed(force)
  for _, player in pairs(force.connected_players) do
    local surface = player.physical_surface
    if surface and surface.valid and surface.name == ARRAKIS then return true end
  end
  return false
end

-- 60-Tick-Takt Schritt 3: Forschung und Landung nachholen [V2, V3], Erwachen.
local function grace_tick(tick)
  for _, force in pairs(game.forces) do
    local g = lib.grace_of(force)
    if g and not g.awake then
      local changed = false
      if not g.ornithopter_tick then
        local tech = force.technologies[ORNITHOPTER_TECH]
        if tech and tech.researched then
          g.ornithopter_tick = tick
          changed = true
        end
      end
      if not g.landed_tick and landed(force) then
        g.landed_tick = tick
        changed = true
      end
      if changed then reschedule(force, g, tick) end
      if g.active_from and tick >= g.active_from then
        g.awake = true
        force.print({"arrakis-message.msg-grace-awake"})
        worms_gui.refresh_force(force)
      end
    end
  end
end

-- Läuft die Lehrjagd dieser Force noch? Dann sind ihre Quellen nicht berechtigt (Plan 4.6 „Lehrjagd-Merker“).
local function teaching_running(g)
  return g.first_hunt ~= nil and storage.hunts.list[g.first_hunt] ~= nil
end

-- Statistik --------------------------------------------------------------------------------------

local function stats_for(force_index)
  local stats = storage.worm_stats
  local record = stats[force_index]
  if not record then
    record = {bitten = 0, escaped = 0, gone = 0, killed = 0}
    stats[force_index] = record
  end
  return record
end

-- Warnungen (Plan 4.10) ---------------------------------------------------------------------------

local function destroy_marks(hunt)
  local renders = hunt.renders
  for name, object in pairs(renders) do
    if object.valid then object.destroy() end
    renders[name] = nil
  end
end

local function mark_colors(hunt)
  if hunt.safe then return GREEN, GREEN end
  return RING_RED, TEXT_RED
end

-- Roter (sicher: grüner) Ring mit Radius 4 und Sekunden über dem Ziel, nur für die Force der Jagd.
local function draw_marks(hunt, force)
  local target = hunt.target
  if not (target and target.valid and force) then return end
  destroy_marks(hunt)
  local ring_color, text_color = mark_colors(hunt)
  local surface = target.surface
  hunt.renders.ring = rendering.draw_circle{
    color = ring_color,
    radius = lib.BITE_RADIUS,
    width = 3,
    filled = false,
    target = target,
    surface = surface,
    forces = {force},
    draw_on_ground = true
  }
  hunt.renders.text = rendering.draw_text{
    text = tostring(hunt.second),
    target = {entity = target, offset = {0, -3}},
    surface = surface,
    forces = {force},
    color = text_color,
    scale = 2.5,
    alignment = "center",
    vertical_alignment = "middle"
  }
end

-- Eigener Alarm je Spieler [V5], gemerkt in alerted.
local function alert_player(hunt, player)
  player.add_custom_alert(hunt.target, ICON, {"arrakis-message.alert-wormsign", hunt.target_name}, true)
  hunt.alerted[player.index] = true
end

-- Alarme weg für jeden Spieler in alerted (Ziel oder Spieler können die Force gewechselt haben). Ungültiges Ziel: über
-- den Oberflächen-Filter; der trifft auch Alarme anderer Jagden dort, deren Merker für diesen Spieler deshalb mit gehen
-- (die Sekundenarbeit setzt sie binnen 60 Ticks neu).
local function clear_alerts(hunt)
  local target = hunt.target
  local valid = target and target.valid
  for player_index in pairs(hunt.alerted) do
    local player = game.get_player(player_index)
    if player and player.valid then
      if valid then
        player.remove_alert{entity = target, type = defines.alert_type.custom, icon = ICON}
      else
        player.remove_alert{type = defines.alert_type.custom, icon = ICON, surface = hunt.surface_index}
        for _, other in pairs(storage.hunts.list) do
          if other ~= hunt and other.surface_index == hunt.surface_index then other.alerted[player_index] = nil end
        end
      end
    end
  end
  hunt.alerted = {}
end

-- Kartenmarkierung an warn_pos (nur Symbol). Gibt die Engine nil zurück (Chunk nicht kartiert), versucht es die
-- Sekundenarbeit weiter und loggt einmal [V6]. Eine vom Spieler gelöschte Markierung kommt nicht wieder.
local function place_tag(hunt, force)
  if hunt.tag or not force then return end
  local surface = game.get_surface(hunt.surface_index)
  if not surface then return end
  local tag = force.add_chart_tag(surface, {position = hunt.warn_pos, icon = ICON})
  if tag then
    hunt.tag = tag
  elseif not hunt.tag_logged then
    hunt.tag_logged = true
    log("Arrakis: Wurmzeichen-Markierung bei " .. gps(surface, hunt.warn_pos) .. " noch nicht möglich (Chunk nicht kartiert)")
  end
end

local function drop_tag(hunt)
  local tag = hunt.tag
  if tag and tag.valid then tag.destroy() end
  hunt.tag = nil
  hunt.tag_logged = nil
end

-- Status am Ernter (Vorrang Wurmzeichen, scripts/harvester.lua).
local function harvester_alarm(hunt, eta, safe)
  local h = storage.harvesters[hunt.target_un]
  if h then harvester.set_alarm(h, "hunt", eta, safe) end
end

local function refresh_forces(...)
  for _, force in pairs({...}) do
    if force and force.valid then worms_gui.refresh_force(force) end
  end
end

-- Jagden ------------------------------------------------------------------------------------------

-- Jagd auf diese Entity (jeder Zustand) oder nil.
function lib.hunt_of(entity)
  if not (entity and entity.valid) then return nil end
  local un = entity.unit_number
  if not un then return nil end
  for _, hunt in pairs(storage.hunts.list) do
    if hunt.target_un == un then return hunt end
  end
  return nil
end

-- Halbe Diagonale der Box (Kacheln): R = BITE_REACH + r (docs/plan-3d2.md 1 „Biss“).
local function half_diagonal(entity)
  local box = entity.bounding_box
  local w = box.right_bottom.x - box.left_top.x
  local h = box.right_bottom.y - box.left_top.y
  return math.sqrt(w * w + h * h) / 2
end

-- Jagd starten (Plan 4.8). opts = {seconds, teaching, debug, bite}, dazu nur Prüfstand (docs/plan-3d2.md 4.18)
-- spawn = {position, direction, tick|nil} und spawn_dir = k. Gibt die Jagd zurück oder nil plus Grund
-- "no-target"|"not-allowed"|"flyer"|"busy". Der Biss fällt im 10-Tick-Takt, deshalb ist eta_tick ein Vielfaches von 10
-- (aus dem 60-Tick-Takt ohnehin). Am Ende entscheidet sandworm.begin, ob ein Wurm kommt (Phase, docs/plan-3d2.md 4.4).
function lib.start_hunt(entity, opts)
  opts = opts or {}
  if not (entity and entity.valid and entity.is_entity_with_health and entity.unit_number) then return nil, "no-target" end
  local surface = entity.surface
  if not terrain.harvest_allowed(surface) then return nil, "not-allowed" end
  if entity.name == FLYER then return nil, "flyer" end
  if lib.hunt_of(entity) then return nil, "busy" end
  local tick = game.tick
  local seconds = opts.seconds or (opts.teaching and lib.TEACH_TICKS / 60) or (lib.WARN_TICKS / 60)
  local eta = math.ceil((tick + 60 * seconds) / 10) * 10
  local position = entity.position
  local key, sector = vibration_lib.key_of(position)
  local force = entity.force
  local hunts = storage.hunts
  local id = hunts.next_id
  hunts.next_id = id + 1
  local hunt =
  {
    id = id,
    kind = kind_of(entity),
    debug = opts.debug == true,
    teaching = opts.teaching == true,
    bite = opts.bite,
    target = entity,
    target_un = entity.unit_number,
    force_index = force.index,
    surface_index = surface.index,
    target_name = entity.localised_name,
    origin_key = key,
    sector_key = sector,
    state = "warning",
    warn_tick = tick,
    eta_tick = eta,
    warn_pos = {x = position.x, y = position.y},
    last_pos = {x = position.x, y = position.y},
    reach = lib.WORM_SPEED * (eta - tick) / 60,
    r = half_diagonal(entity),
    safe = false,
    lost = false,
    renders = {},
    second = seconds_left(eta, tick),
    hidden = false,
    alerted = {}
  }
  hunts.list[id] = hunt
  if hunt.teaching and not hunt.debug and hunt.kind == "harvest" then
    local g = lib.grace_of(force)
    if g then g.first_hunt = id end
  end
  -- Warnungen: Alarm und Ton je verbundenem Spieler [V8], Markierung, Ring und Sekunden, Chat, Fenster, Status.
  for _, player in pairs(force.connected_players) do
    alert_player(hunt, player)
    player.play_sound{path = WORMSIGN_SOUND}
  end
  place_tag(hunt, force)
  draw_marks(hunt, force)
  force.print({"arrakis-message.msg-wormsign", gps(surface, position), hunt.target_name, hunt.second})
  harvester_alarm(hunt, eta, nil)
  worms_gui.refresh_force(force)
  -- Wurm oder nicht (docs/plan-3d2.md 4.4 Schritt 1): Phase warten oder ohne mit Grund.
  sandworm_lib.begin(hunt, {spawn = opts.spawn, spawn_dir = opts.spawn_dir, max_debug = lib.MAX_DEBUG_WORMS})
  return hunt
end

-- Protokoll (docs/plan-3d2.md 4.16): Eintrag im Ring storage.hunts.log (nur Zahlen, Texte und Wahrheitswerte), je
-- Jagd mit Wurm eine Logzeile.
local function write_log(hunt)
  local hunts = storage.hunts
  if not hunts.log then return end
  local plan = hunt.plan or {}
  local chosen = plan.chosen or {}
  local worm = hunt.last_worm or {}
  local entry =
  {
    id = hunt.id, kind = hunt.kind, debug = hunt.debug, force_index = hunt.force_index, outcome = hunt.outcome,
    phase = hunt.phase, no_worm = hunt.no_worm, warn_tick = hunt.warn_tick, eta_tick = hunt.eta_tick,
    plan_tick = hunt.plan_tick, spawn_tick = hunt.spawn_tick, bite_tick = hunt.bite_tick, bite_dist = hunt.bite_dist,
    ersatz = hunt.ersatz == true, k = chosen.k, d = hunt.d, length = chosen.length, paths = plan.paths, box = chosen.box,
    spawns = plan.spawns, reroutes = worm.reroutes, detours = worm.detours, samples = worm.samples,
    rock_box = worm.rock_box, vmax = worm.vmax, sprint = worm.sprint, boost = worm.boost, crushed = worm.crushed,
    dive = hunt.dive
  }
  local i = hunts.log_next or 1
  hunts.log[i] = entry
  hunts.log_next = i % lib.LOG_SIZE + 1
  if not worm.un then return end
  local parts = {}
  for _, key in ipairs({"id", "kind", "debug", "outcome", "phase", "no_worm", "warn_tick", "eta_tick", "plan_tick",
                        "spawn_tick", "bite_tick", "bite_dist", "ersatz", "k", "d", "length", "paths", "box", "spawns",
                        "reroutes", "detours", "samples", "rock_box", "vmax", "sprint", "boost", "crushed", "dive"}) do
    local value = entry[key]
    if type(value) == "number" and value ~= math.floor(value) then value = string.format("%.2f", value) end
    parts[#parts + 1] = key .. "=" .. tostring(value)
  end
  log("Arrakis: Jagd " .. table.concat(parts, " "))
end

-- Ende einer Jagd (Plan 4.7 „Ende“). mode nil (normal), "quiet" (ohne Statistik, Prüfstand) oder "abort" (ohne
-- Rücksetzen, Ruhe und Statistik; Lehrjagd-Merker nur first_hunt = nil). Befehlsjagden: nur Aufräumen.
-- 3d2: Vor dem Austragen taucht der Wurm ab (bei "abort" still), Anfragen weg, Protokoll; gibt das Ergebnis von
-- sandworm.dive zurück (true: eine gültige Einheit wurde zerstört).
function lib.end_hunt(hunt, outcome, mode)
  local list = storage.hunts.list
  if not (hunt and list[hunt.id] == hunt) then return false end
  if outcome then hunt.outcome = outcome end
  local dived = sandworm_lib.dive(hunt, "ende", mode == "abort")
  drop_tag(hunt)
  destroy_marks(hunt)
  clear_alerts(hunt)
  local h = storage.harvesters[hunt.target_un]
  if h and (h.alarm_hunt_eta or h.alarm_hunt_safe) then harvester.set_alarm(h, "hunt", nil) end
  list[hunt.id] = nil
  if not hunt.debug then
    if mode ~= "abort" then
      vibration_lib.reset_around(hunt.surface_index, hunt.origin_key)
      vibration_lib.rest(hunt.surface_index, hunt.sector_key, storage.rng(lib.REST_MIN, lib.REST_MAX))
    end
    -- Lehrjagd-Merker: jeder Datensatz, der auf diese Jagd zeigt (nach einem Force-Wechsel der der alten Force).
    for _, g in pairs(storage.grace) do
      if g.first_hunt == hunt.id then
        g.first_hunt = nil
        if mode ~= "abort" then g.first_hunt_done = true end
      end
    end
    local result = hunt.outcome
    if mode == nil and result then
      local stats = stats_for(hunt.force_index)
      stats[result] = (stats[result] or 0) + 1
      -- killed (docs/plan-3d2.md 4.11): Die Jagd ist überstanden wie bei escaped.
      if (result == "escaped" or result == "killed") and not stats.first_escape_tick then stats.first_escape_tick = game.tick end
    end
  end
  write_log(hunt)
  refresh_forces(force_of(hunt.force_index))
  return dived
end

-- Ziel verloren (Ereignis oder ungültig ohne Ereignis): Countdown läuft weiter, Warnungen weg.
local function lose(hunt)
  if hunt.lost then return end
  hunt.lost = true
  clear_alerts(hunt)
  destroy_marks(hunt)
  local h = storage.harvesters[hunt.target_un]
  if h and (h.alarm_hunt_eta or h.alarm_hunt_safe) then harvester.set_alarm(h, "hunt", nil) end
  refresh_forces(force_of(hunt.force_index))
end

-- Ziel getragen oder auf einer anderen Oberfläche: Alarme, Ring und Sekunden weg, das Fenster sagt „wird getragen“.
local function hide(hunt)
  hunt.hidden = true
  clear_alerts(hunt)
  destroy_marks(hunt)
  refresh_forces(force_of(hunt.force_index))
end

-- Force des Ziels gewechselt (kein Ereignis, Plan 1 „Force-Wechsel“): Warnungen wechseln zur neuen Force.
local function change_force(hunt, new_force)
  local old_force = force_of(hunt.force_index)
  clear_alerts(hunt)
  drop_tag(hunt)
  hunt.force_index = new_force.index
  hunt.redraw = nil
  destroy_marks(hunt)
  if not (hunt.hidden or hunt.lost) then draw_marks(hunt, new_force) end
  place_tag(hunt, new_force)
  refresh_forces(new_force, old_force)
end

-- Nach on_forces_merging (force_index ist schon die Ziel-Force): Ring, Text und Markierung neu für sie.
local function redraw(hunt)
  hunt.redraw = nil
  local force = force_of(hunt.force_index)
  if not force then return end
  destroy_marks(hunt)
  local target = hunt.target
  if hunt.state == "warning" and not (hunt.hidden or hunt.lost) and target and target.valid then draw_marks(hunt, force) end
  drop_tag(hunt)
  place_tag(hunt, force)
  refresh_forces(force)
end

-- Nachführen im 10-Tick-Takt (Plan 4.7): verloren, Force-Wechsel, getragen, Sand, safe, Sekunden.
local function track(hunt, tick)
  local target = hunt.target
  if not hunt.lost and not (target and target.valid) then lose(hunt) end
  if hunt.lost then
    if hunt.redraw then redraw(hunt) end
    return
  end
  if target.force_index ~= hunt.force_index then
    change_force(hunt, target.force)
  elseif hunt.redraw then
    redraw(hunt)
  end
  local force = force_of(hunt.force_index)
  local h = hunt.kind == "harvest" and harvester.get(target) or nil
  if (h and h.state == "carried") or target.surface.index ~= hunt.surface_index then
    if not hunt.hidden then hide(hunt) end
    return
  end
  if hunt.hidden then
    hunt.hidden = false
    draw_marks(hunt, force)
    refresh_forces(force)
  end
  local position = target.position
  local sand = terrain.has_sand_under(target)
  if sand then hunt.last_pos = {x = position.x, y = position.y} end
  local safe = false
  if not sand then
    safe = "rock"
  elseif distance(position, hunt.warn_pos) > hunt.reach then
    safe = "far"
  end
  local changed = safe ~= hunt.safe
  hunt.safe = safe
  local second = seconds_left(hunt.eta_tick, tick)
  local renders = hunt.renders
  if not (renders.ring and renders.ring.valid and renders.text and renders.text.valid) then
    hunt.second = second
    draw_marks(hunt, force)
  else
    if changed then
      local ring_color, text_color = mark_colors(hunt)
      renders.ring.color = ring_color
      renders.text.color = text_color
    end
    if second ~= hunt.second then
      hunt.second = second
      renders.text.text = tostring(second)
    end
  end
  if h then harvester.set_alarm(h, "hunt", hunt.eta_tick, safe and true or nil) end
  if changed then refresh_forces(force) end
end

-- Kein Biss (weg oder entkommen): harmlose Eruption, Chat, Warnungen weg (die Markierung bleibt bis zum Ende), suchen.
local function miss(hunt, outcome, position)
  local surface = game.get_surface(hunt.surface_index)
  if surface then surface.create_entity{name = ERUPTION, position = position} end
  hunt.outcome = outcome
  hunt.state = "searching"
  hunt.end_tick = hunt.eta_tick + lib.SEARCH_TICKS
  clear_alerts(hunt)
  destroy_marks(hunt)
  local h = storage.harvesters[hunt.target_un]
  if h and (h.alarm_hunt_eta or h.alarm_hunt_safe) then harvester.set_alarm(h, "hunt", nil) end
  local force = force_of(hunt.force_index)
  if force then
    local key = outcome == "gone" and "msg-gone" or "msg-escaped"
    force.print({"arrakis-message." .. key, gps_of(hunt.surface_index, position)})
  end
  refresh_forces(force)
end

-- Darf die Entity Opfer sein (Plan 4.9 Schritt 3, ohne Abstand und Sand)?
local function victim_ok(entity)
  if not (entity and entity.valid and entity.is_entity_with_health) then return false end
  if entity.destructible == false then return false end
  if NO_VICTIM[entity.type] or entity.name == FLYER then return false end
  if entity.force.name == FORCE then return false end
  return true
end

-- Insassen eines Fahrzeugs als Figuren: Fahrer und (nur car, spider-vehicle) Beifahrer, Figur oder player.character.
local function occupants(vehicle)
  local out = {}
  local function take(occupant)
    if not occupant then return end
    local character = occupant
    if occupant.object_name == "LuaPlayer" then
      character = occupant.character
      local seat = character and character.valid and character.vehicle
      if not (seat and seat.unit_number == vehicle.unit_number) then return end
    end
    if character and character.valid and character.type == "character" then out[#out + 1] = character end
  end
  take(vehicle.get_driver())
  local typ = vehicle.type
  if typ == "car" or typ == "spider-vehicle" then take(vehicle.get_passenger()) end
  return out
end

-- Opferliste (Plan 4.9 Schritt 3): Figuren, Fahrzeuge, Rest; seen verhindert Doppelte (unit_number).
local function new_victims(seen)
  return {seen = seen or {}, characters = {}, vehicles = {}, others = {}}
end

local function add_victim(victims, list, entity)
  local un = entity.unit_number
  if un then
    if victims.seen[un] then return end
    victims.seen[un] = true
  end
  list[#list + 1] = entity
end

-- In die passende Liste. Figuren im Fahrzeug teilen dessen Los (in devour über get_driver/get_passenger).
local function sort_victim(victims, entity)
  local typ = entity.type
  if typ == "character" then
    if not entity.vehicle then add_victim(victims, victims.characters, entity) end
  elseif VEHICLE_TYPES[typ] then
    add_victim(victims, victims.vehicles, entity)
  else
    add_victim(victims, victims.others, entity)
  end
end

-- Gemeinsamer Kern von Biss und Zerdrücken (docs/plan-3d2.md 4.1, P3D1 4.9 Schritte 3 bis 5): Fahrzeuge regeln (Ernter
-- nach mode, sonst Insassen auf die Liste), dann töten in fester Reihenfolge ohne cause, weil die() Ereignisse sofort
-- auslöst [V1]. target nil beim Zerdrücken. Gibt damaged (das Ziel überlebt schwer beschädigt) und die Zahl der
-- Getöteten zurück.
local function devour(victims, target, mode, worm_force)
  local function add_occupants(vehicle)
    for _, character in pairs(occupants(vehicle)) do
      if victim_ok(character) then add_victim(victims, victims.characters, character) end
    end
  end
  -- Gibt true zurück, wenn das Fahrzeug stirbt.
  local function settle(vehicle)
    if vehicle.name == HARVESTER then
      local h = harvester.get(vehicle)
      local trunk = vehicle.get_inventory(defines.inventory.car_trunk)
      if mode == "heavy-damage" then
        -- Überlebt mobil (angedockt: abgedockt), Laderaum leer, Treibstoff und Insassen bleiben [V19].
        if h then harvester.to_mobile(h) end
        if trunk then trunk.clear() end
        vehicle.health = math.max(1, lib.HEAVY_HEALTH * vehicle.max_health)
        return false
      end
      if trunk then trunk.clear() end
      local fuel = vehicle.get_fuel_inventory()
      if fuel then fuel.clear() end
      if lib.TOTAL_LOSS_OCCUPANTS then add_occupants(vehicle) end
      return true
    end
    add_occupants(vehicle)
    return true
  end
  local doomed = {}
  for _, vehicle in ipairs(victims.vehicles) do
    if settle(vehicle) then doomed[#doomed + 1] = vehicle end
  end
  local damaged = false
  local target_dies = target ~= nil
  if target and VEHICLE_TYPES[target.type] then
    target_dies = settle(target)
    damaged = not target_dies
  end
  -- Töten: erst Figuren (noch im Sitz) [V14], dann Fahrzeuge, dann der Rest, zuletzt das Ziel; ohne cause. Jedes Opfer
  -- erst auf valid prüfen: die() eines anderen kann es schon mitgenommen haben [W15].
  local n = 0
  local function kill(entity)
    if entity.valid then
      entity.die(worm_force)
      n = n + 1
    end
  end
  for _, entity in ipairs(victims.characters) do kill(entity) end
  for _, entity in ipairs(doomed) do kill(entity) end
  for _, entity in ipairs(victims.others) do kill(entity) end
  if target_dies then kill(target) end
  return damaged, n
end

-- Biss (Plan 4.9) an der Zielmitte: Eruption, devour, Ende. Der Wurm taucht im Ende ab (docs/plan-3d2.md 4.11).
local function bite(hunt)
  hunt.state = "biting"
  hunt.bite_tick = game.tick
  local target = hunt.target
  local center = target.position
  local surface = target.surface
  local mode = hunt.bite or settings.global[BITE_SETTING].value
  surface.create_entity{name = ERUPTION, position = center}
  local cx, cy = center.x, center.y
  local R = lib.BITE_RADIUS
  local victims = new_victims({[target.unit_number] = true})
  for _, entity in pairs(surface.find_entities_filtered{area = {{cx - R, cy - R}, {cx + R, cy + R}}}) do
    if victim_ok(entity) and box_distance(entity, cx, cy) <= R and terrain.has_sand_under(entity) then
      sort_victim(victims, entity)
    end
  end
  local damaged = devour(victims, target, mode, lib.ensure_force())
  local force = force_of(hunt.force_index)
  lib.end_hunt(hunt, "bitten")
  if force then
    local key = damaged and "msg-bitten-damaged" or "msg-bitten"
    force.print({"arrakis-message." .. key, gps(surface, center), hunt.target_name})
  end
end

-- Entscheidung ohne Wirkung (Plan 4.7 Schritte 1 bis 4, in dieser Reihenfolge): nil (beißbar) oder Ergebnis und Ort der
-- Eruption ohne Wurm.
local function judge(hunt)
  local target = hunt.target
  if hunt.lost or not (target and target.valid) then return "gone", hunt.last_pos end
  local h = hunt.kind == "harvest" and harvester.get(target) or nil
  if (h and h.state == "carried") or target.surface.index ~= hunt.surface_index then return "escaped", hunt.last_pos end
  if not terrain.has_sand_under(target) then return "escaped", hunt.last_pos end
  if distance(target.position, hunt.warn_pos) > hunt.reach then return "escaped", hunt.warn_pos end
  return nil
end

-- Entscheidung am Biss-Tick ohne Wurm (wie 0.7.0).
local function decide(hunt)
  local outcome, position = judge(hunt)
  if outcome then return miss(hunt, outcome, position) end
  bite(hunt)
end

-- Biss-Fenster (docs/plan-3d2.md 4.9), jeder Takt mit state warning und tick ≥ eta_tick. Mit Wurm: nicht beißbar →
-- Fehlbiss am Kopf und Suche; in Reichweite R → Biss; bis eta + BITE_WINDOW warten; dann Ersatzbiss. Ohne Wurm: decide.
local function bite_window(hunt, tick)
  local worm = hunt.worm
  if not worm then
    -- Noch in der Planung (nur mit Prüfstand-Haken möglich): auf ohne, dann wie 0.7.0.
    if hunt.phase ~= "ohne" and hunt.phase ~= "suche" then sandworm_lib.to_none(hunt, "kein-weg") end
    return decide(hunt)
  end
  local outcome = judge(hunt)
  if outcome then
    miss(hunt, outcome, worm.head)
    hunt.phase = "suche"
    return
  end
  local center = hunt.target.position
  local dist = distance(worm.head, center)
  hunt.bite_dist = dist
  if dist <= lib.BITE_REACH + (hunt.r or DEFAULT_R) then return bite(hunt) end
  if tick < hunt.eta_tick + lib.BITE_WINDOW then return end
  hunt.ersatz = true
  storage.hunts.ersatz = (storage.hunts.ersatz or 0) + 1
  log(string.format("Arrakis: Ersatzbiss Jagd %d, Abstand %.1f, Phase %s", hunt.id, dist, tostring(hunt.phase)))
  bite(hunt)
end

-- Zielpunkt P (docs/plan-3d2.md 1 „Zielpunkt“): Zielmitte, wenn das Ziel gültig, auf der Oberfläche der Jagd, nicht
-- getragen und mit Sand darunter ist (nur im Zustand warning), sonst last_pos; am Reichweitenkreis um warn_pos geklemmt.
local function aim_point(hunt)
  local p = hunt.last_pos
  local target = hunt.target
  if hunt.state == "warning" and not hunt.lost and target and target.valid and target.surface.index == hunt.surface_index then
    local h = hunt.kind == "harvest" and harvester.get(target) or nil
    if not (h and h.state == "carried") and terrain.has_sand_under(target) then p = target.position end
  end
  local w = hunt.warn_pos
  local dx, dy = p.x - w.x, p.y - w.y
  local len = math.sqrt(dx * dx + dy * dy)
  if len > hunt.reach and len > 0 then
    local f = hunt.reach / len
    return {x = w.x + dx * f, y = w.y + dy * f}
  end
  return {x = p.x, y = p.y}
end

-- Darf der Wurm die Entity am Punkt (hx, hy) zerdrücken (docs/plan-3d2.md 4.10 Schritt 2)? ctx = {zones, targets}.
local function crushable(entity, hx, hy, surface_index, ctx)
  if not victim_ok(entity) then return false end
  local typ = entity.type
  if NO_CRUSH[typ] then return false end
  if lib.CRUSH_SPARES_VEHICLES and (typ == "character" or VEHICLE_TYPES[typ]) then return false end
  if ROLLING_STOCK[typ] and entity.draw_data.height > 0 then return false end
  local g = storage.grace[entity.force.index]
  if g and not g.awake then return false end
  if box_distance(entity, hx, hy) > lib.CRUSH_RADIUS then return false end
  if not terrain.has_sand_under(entity) then return false end
  local un = entity.unit_number
  if un and ctx.targets[un] then return false end
  for _, zone in ipairs(ctx.zones) do
    if zone.surface_index == surface_index and box_distance(entity, zone.x, zone.y) <= lib.ZONE_RADIUS then return false end
  end
  return true
end

-- Zerdrücken (docs/plan-3d2.md 4.10): am Kopf dieses Takts (Knoten 1, bis zu 1 Kachel hinter dem wahren Kopf, W18; steht
-- er an etwas, auch an der Front worm.front), im Spawn-Takt an jedem vierten Knoten. Keine Eruption, kein Chat, kein Alarm;
-- worm.crushed zählt mit (Getötete; ein schwer beschädigter Ernter zählt nicht).
local function crush(hunt, tick, ctx, worm_force)
  local worm = hunt.worm
  local unit = worm.unit
  if not (unit and unit.valid) then return end
  local surface = unit.surface
  local points = {worm.head, worm.front}
  if worm.spawned == tick then
    local _, nodes = sandworm_lib.head_of(hunt)
    points = {}
    for i = 1, #(nodes or {}), sandworm_lib.BODY_STEP do points[#points + 1] = nodes[i] end
  end
  local victims = new_victims()
  local r = lib.CRUSH_RADIUS
  for _, p in ipairs(points) do
    local hx, hy = p.x, p.y
    for _, entity in pairs(surface.find_entities_filtered{area = {{hx - r, hy - r}, {hx + r, hy + r}}}) do
      if crushable(entity, hx, hy, hunt.surface_index, ctx) then sort_victim(victims, entity) end
    end
  end
  if #victims.characters + #victims.vehicles + #victims.others == 0 then return end
  -- Ein Spice-Ernter im Weg wie beim Biss dieser Jagd: Einstellung arrakis-worm-bite (Prüfstand: hunt.bite).
  local mode = hunt.bite or settings.global[BITE_SETTING].value
  local _, n = devour(victims, nil, mode, worm_force)
  -- devour kann über Ereignisse anderer Mods den Wurm schon beendet haben.
  if hunt.worm == worm then worm.crushed = worm.crushed + n end
end

-- Jagden in fester Reihenfolge (nach id), weil Aufrufe die Liste ändern.
local function sorted_ids()
  local ids = {}
  for id in pairs(storage.hunts.list) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

-- 10-Tick-Takt (docs/plan-3d2.md 4.3): 1. Zielpunkte und Ziele aller Jagden vor dem ersten Zerdrücken; 2. je Jagd nach
-- id a. nachführen, b. sandworm.step, c. Zerdrücken, d. Biss-Fenster, e. Suche beenden. Die Sandwurm-Force holt der
-- Takt einmal vor dem ersten step (docs/plan-3d2.md 1 „Force“).
local function on_nth_tick_10(event)
  -- Abtauchen läuft auch nach dem Ende der Jagd weiter (0.8.4).
  sandworm_lib.dive_takt(event.tick)
  local list = storage.hunts.list
  if next(list) == nil then return end
  local tick = event.tick
  local ids = sorted_ids()
  local ctx = {zones = {}, targets = {}}
  for _, id in ipairs(ids) do
    local hunt = list[id]
    local zone = aim_point(hunt)
    hunt.zone = zone
    ctx.zones[#ctx.zones + 1] = {x = zone.x, y = zone.y, surface_index = hunt.surface_index}
    ctx.targets[hunt.target_un] = true
  end
  local worm_force
  local function get_force()
    if worm_force == nil then worm_force = game.forces[FORCE] or lib.ensure_force() or false end
    return worm_force or nil
  end
  for _, id in ipairs(ids) do
    local hunt = list[id]
    if hunt then
      if hunt.state == "warning" then track(hunt, tick) end
      if list[id] == hunt and hunt.state == "searching" and hunt.redraw then redraw(hunt) end
      if list[id] == hunt and (STEP_PHASES[hunt.phase] or (hunt.phase == "suche" and hunt.worm)) then
        local force = get_force()
        if force then
          sandworm_lib.step(hunt, tick, force)
        else
          sandworm_lib.to_none(hunt, "keine-force")
        end
      end
      if not lib.NO_ROUTE_BITE and list[id] == hunt and hunt.state == "warning" and hunt.phase == "ohne"
          and hunt.no_worm == "kein-weg" then
        lib.end_hunt(hunt, nil, "quiet")
      end
      if list[id] == hunt and hunt.worm then crush(hunt, tick, ctx, get_force()) end
      if list[id] == hunt and hunt.state == "warning" and tick >= hunt.eta_tick then bite_window(hunt, tick) end
      if list[id] == hunt and hunt.state == "searching" and tick >= hunt.end_tick then lib.end_hunt(hunt) end
    end
  end
end

-- Wurmzeichen (Plan 4.8) --------------------------------------------------------------------------

-- Quellen je Chunk auf Oberfläche s aus diesem Takt (Ernter über vib_key, sonst key).
local function sources_by_chunk(s)
  local index = {}
  local function put(key, entry)
    local list = index[key]
    if not list then
      list = {}
      index[key] = list
    end
    list[#list + 1] = entry
  end
  for un, h in pairs(storage.harvesters) do
    local entity = h.entity
    if h.vib_key and h.vib_weight > 0 and entity.valid and h.state ~= "carried" and entity.surface.index == s then
      put(h.vib_key, {un = un, entity = entity, weight = h.vib_weight, key = h.vib_key, harvester = true})
    end
  end
  for un, record in pairs(storage.vib.sources) do
    if record.key and record.weight > 0 and record.surface == s and record.entity.valid
        and (lib.VEHICLE_TARGETS or record.kind ~= "vehicle") then
      put(record.key, {un = un, entity = record.entity, weight = record.weight, key = record.key, harvester = false})
    end
  end
  return index
end

-- Ist die Quelle berechtigt (Plan 1 „Berechtigt“)? Gewicht > 0 (also auf Sand, nicht getragen) steht schon fest.
local function eligible(entry, s, busy_sectors)
  local entity = entry.entity
  local g = storage.grace[entity.force.index]
  if not (g and g.awake) or teaching_running(g) then return false end
  if lib.hunt_of(entity) then return false end
  local sector = vibration_lib.sector_of_key(entry.key)
  if busy_sectors[sector] then return false end
  if vibration_lib.resting(s, sector) then return false end
  return true
end

-- Stärkste berechtigte Quelle in den 9 Chunks um d; gleich stark: Ernter vor anderen, dann kleinste unit_number.
local function best_target(index, d, s, busy_sectors)
  local best
  local cx, cy = vibration_lib.chunk_of_key(d)
  for dx = -1, 1 do
    for dy = -1, 1 do
      local list = index[vibration_lib.chunk_key(cx + dx, cy + dy)]
      if list then
        for _, entry in ipairs(list) do
          if not best or entry.weight > best.weight
              or (entry.weight == best.weight and ((entry.harvester and not best.harvester)
                or (entry.harvester == best.harvester and entry.un < best.un))) then
            if eligible(entry, s, busy_sectors) then best = entry end
          end
        end
      end
    end
  end
  return best
end

-- 60-Tick-Takt Schritt 5: je erlaubter Oberfläche höchstens ein neues Wurmzeichen, höchstens MAX_HUNTS zugleich.
local function wormsign_tick(tick)
  local hunts = storage.hunts
  if hunts.paused_until and hunts.paused_until > tick then return end
  local count = 0
  local busy = {}
  local origins = {}
  for _, hunt in pairs(hunts.list) do
    if not hunt.debug then
      count = count + 1
      local s = hunt.surface_index
      busy[s] = busy[s] or {}
      busy[s][hunt.sector_key] = true
      origins[s] = origins[s] or {}
      table.insert(origins[s], hunt.origin_key)
    end
  end
  if count >= lib.MAX_HUNTS then return end
  local heat = storage.vib.heat
  local surfaces = {}
  for s in pairs(heat) do surfaces[#surfaces + 1] = s end
  table.sort(surfaces)
  for _, s in ipairs(surfaces) do
    if count >= lib.MAX_HUNTS then return end
    local e = heat[s]
    local surface = game.get_surface(s)
    if e and surface and terrain.harvest_allowed(surface) then
      local sum3, prev3 = e.sum3, e.prev3
      local candidates = {}
      for key, v in pairs(sum3) do
        if v >= vibration_lib.WORMSIGN and (prev3[key] or 0) >= vibration_lib.UNREST then
          candidates[#candidates + 1] = key
        end
      end
      if #candidates > 0 then
        table.sort(candidates, function(a, b)
          if sum3[a] ~= sum3[b] then return sum3[a] > sum3[b] end
          return a < b
        end)
        local index = sources_by_chunk(s)
        local busy_sectors = busy[s] or {}
        for _, d in ipairs(candidates) do
          -- Die Wärme um den Ursprung einer laufenden Jagd gehört zu ihr.
          local near = false
          local dcx, dcy = vibration_lib.chunk_of_key(d)
          for _, origin in ipairs(origins[s] or {}) do
            local ocx, ocy = vibration_lib.chunk_of_key(origin)
            if math.abs(ocx - dcx) <= 1 and math.abs(ocy - dcy) <= 1 then
              near = true
              break
            end
          end
          if not near then
            local entry = best_target(index, d, s, busy_sectors)
            if entry then
              local entity = entry.entity
              local g = storage.grace[entity.force.index]
              local teaching = entry.harvester and not g.first_hunt_done
              if lib.start_hunt(entity, {teaching = teaching}) then count = count + 1 end
              break
            end
          end
        end
      end
    end
  end
end

-- 60-Tick-Takt Schritt 6: Alarme für Spieler, die ihn noch nicht haben, und Markierung nachholen [V6].
local function hunts_second(tick)
  -- Alte Pfad-Anfragen räumen, auch ohne laufende Jagd (docs/plan-3d2.md 4.5 „Aufräumen“).
  local requests = storage.path_requests
  if requests and next(requests) ~= nil then sandworm_lib.tidy(tick) end
  local list = storage.hunts.list
  if next(list) == nil then return end
  for _, id in ipairs(sorted_ids()) do
    local hunt = list[id]
    local force = force_of(hunt.force_index)
    if force then
      local target = hunt.target
      if hunt.state == "warning" and not (hunt.hidden or hunt.lost) and target and target.valid then
        for _, player in pairs(force.connected_players) do
          if not hunt.alerted[player.index] then alert_player(hunt, player) end
        end
      end
      place_tag(hunt, force)
    end
  end
end

-- 60-Tick-Takt in fester Reihenfolge (Plan 4.4).
local function on_nth_tick_60(event)
  local tick = event.tick
  vibration_lib.tick(tick)
  vibration_lib.careful_tick(tick)
  grace_tick(tick)
  vibration_lib.unrest_tick(tick)
  wormsign_tick(tick)
  hunts_second(tick)
  vibration_lib.overlay_tick(tick)
end

-- Befehl /arrakis-worm (Plan 1 „Befehlsjagd“) -------------------------------------------------------

local CMD_REASON =
{
  ["no-target"] = "worm-cmd-no-target",
  ["not-allowed"] = "worm-cmd-not-allowed",
  flyer = "worm-cmd-flyer",
  busy = "worm-cmd-busy"
}

-- Nur Admins (ohne Spieler: Serverkonsole oder RCON, die haben keine Auswahl). Ohne Argument 60 s, „lehr“ 90 s.
local function worm_command(command)
  local player = command.player_index and game.get_player(command.player_index)
  if command.player_index and not player then return end
  if player and not player.admin then
    reply(player, {"arrakis-message.worm-cmd-admin"})
    return
  end
  local word = string.lower(string.match(command.parameter or "", "^%s*(.-)%s*$"))
  local seconds = lib.WARN_TICKS / 60
  local teaching = false
  if word == "lehr" or word == "teach" then
    seconds = lib.TEACH_TICKS / 60
    teaching = true
  elseif word ~= "" then
    local n = tonumber(word)
    if not (n and n == math.floor(n) and n >= lib.DEBUG_MIN and n <= lib.DEBUG_MAX) then
      reply(player, {"arrakis-message.worm-cmd-bad"})
      return
    end
    seconds = n
  end
  local entity = player and player.selected
  local hunt, reason = lib.start_hunt(entity, {seconds = seconds, teaching = teaching, debug = true})
  if not hunt then
    reply(player, {"arrakis-message." .. (CMD_REASON[reason] or "worm-cmd-no-target")})
    return
  end
  reply(player, {"arrakis-message.worm-cmd-started", hunt.target_name, hunt.second})
end

-- Migration und Entfernen (Plan 4.16) --------------------------------------------------------------

-- Schema 3 nachholen, nur was fehlt: Schonfrist je Force („Ornithopter“ erforscht → jetzt; Arrakis da und Spieler →
-- Landung jetzt), Quellen auf Arrakis anmelden, Chatzeile einmal. Prüfstand: opts = {surfaces = {…}, forces = {…}}
-- begrenzt Scan und Forces, dann ohne Chat und ohne worm_notice.
function lib.migrate_schema3(opts)
  local tick = game.tick
  local arrakis = game.get_surface(ARRAKIS)
  local forces = opts and opts.forces or game.forces
  for _, force in pairs(forces) do
    local g = lib.grace_of(force)
    if g and not g.awake then
      local changed = false
      if not g.ornithopter_tick then
        local tech = force.technologies[ORNITHOPTER_TECH]
        if tech and tech.researched then
          g.ornithopter_tick = tick
          changed = true
        end
      end
      if not g.landed_tick and arrakis and #force.players > 0 then
        g.landed_tick = tick
        changed = true
      end
      -- Den Termin nennt die Chatzeile der Migration (msg-worms-migrated), deshalb nur merken.
      if changed then
        g.active_from = compute_active(g)
        g.announced = g.active_from
      end
    end
  end
  local surfaces = opts and opts.surfaces or {arrakis}
  for _, surface in pairs(surfaces) do vibration_lib.scan(surface) end
  if opts or storage.migration.worm_notice then return end
  storage.migration.worm_notice = true
  for _, force in pairs(game.forces) do
    local g = #force.players > 0 and lib.grace_of(force)
    if g then
      if g.awake then
        -- schon wach (sollte es bei einer Migration nicht geben): kein Termin
      elseif g.active_from then
        force.print({"arrakis-message.msg-worms-migrated", mmss(g.active_from - tick)})
      else
        force.print({"arrakis-message.msg-worms-migrated-later"})
      end
    end
  end
end

-- Schema 4 nachholen (docs/plan-3d2.md 4.14), bei jedem on_configuration_changed: Jede Jagd ohne phase oder ohne r (aus
-- 0.7.0, auch nach 0.8.0 → 0.7.0 → 0.8.0) bekommt Phase ohne ("migration") und r aus dem Ziel (ungültig: 1,58).
-- Prüfstand: opts = {hunts = {…}} nur diese Jagden.
function lib.migrate_schema4(opts)
  local hunts = opts and opts.hunts or storage.hunts.list
  for _, hunt in pairs(hunts) do
    if hunt.phase == nil or hunt.r == nil then
      sandworm_lib.to_none(hunt, "migration")
      if hunt.r == nil then
        local target = hunt.target
        hunt.r = (target and target.valid) and half_diagonal(target) or DEFAULT_R
      end
    end
  end
end

-- /arrakis-uninstall ja (scripts/flyer.lua): alle Jagden ohne Biss beenden (Würmer tauchen still ab), Waisen auf allen
-- Oberflächen, Alarme, Fenster und Anzeigen weg, Verknüpfungen aus, Ernter-Status zurück, 10 min Pause, Sandwurm-Force
-- mit enemy verschmelzen [V21]. Gibt die Zahl der beendeten Jagden und die Zahl aller entfernten Sandwürmer zurück
-- (docs/plan-3d2.md 4.14).
function lib.uninstall()
  local n, m = 0, 0
  local list = storage.hunts.list
  for _, id in ipairs(sorted_ids()) do
    local hunt = list[id]
    if hunt then
      if lib.end_hunt(hunt, nil, "abort") then m = m + 1 end
      n = n + 1
    end
  end
  -- Vor dem Verschmelzen der Force: Waisen unseres Prototyps.
  m = m + sandworm_lib.sweep()
  storage.path_requests = {}
  storage.hunts.paused_until = game.tick + lib.PAUSE_TICKS
  for _, player in pairs(game.players) do
    player.remove_alert{type = defines.alert_type.custom, icon = ICON}
    worms_gui.destroy(player)
    vibration_lib.overlay_off(player.index)
    vibration_lib.set_toggled(player, false)
  end
  for _, h in pairs(storage.harvesters) do
    if h.alarm_hunt_eta or h.alarm_hunt_safe then harvester.set_alarm(h, "hunt", nil) end
    if h.alarm_unrest then harvester.set_alarm(h, "unrest", nil) end
  end
  if game.forces[FORCE] then
    local ok, err = pcall(game.merge_forces, FORCE, "enemy")
    if not ok then log("Arrakis: Sandwurm-Force nicht verschmolzen: " .. tostring(err)) end
  end
  return n, m
end

-- Prüfstand-Haken (Plan 4.18) ---------------------------------------------------------------------------

-- Schreibt die Felder aus fields (auch awake) und setzt jedes Feld aus der Liste clear auf nil. Ohne active_from in
-- fields wird active_from danach neu berechnet (4.6). Gibt den Datensatz zurück.
function lib.set_grace(force, fields, clear)
  local g = lib.grace_of(force)
  if not g then return nil end
  for key, value in pairs(fields or {}) do g[key] = value end
  for _, key in pairs(clear or {}) do g[key] = nil end
  if not (fields and fields.active_from ~= nil) then g.active_from = compute_active(g) end
  announce(force, g, game.tick)
  return g
end

-- Kopie des Schonfrist-Datensatzes oder nil.
function lib.grace_snapshot(force)
  return copy(storage.grace[force.index])
end

-- Ersetzt den ganzen Datensatz (nil löscht ihn).
function lib.grace_restore(force, snapshot)
  storage.grace[force.index] = copy(snapshot)
end

-- Statistik der Force (bei Bedarf angelegt).
function lib.stats_of(force)
  return stats_for(force.index)
end

-- Pause neuer Wurmzeichen bis zu diesem Tick (nil: keine).
function lib.set_paused(until_tick)
  storage.hunts.paused_until = until_tick
end

-- Kein Wurm für Jagden der Force, die danach starten (docs/plan-3d2.md 4.18); on false oder nil schaltet zurück.
function lib.set_worm_off(force, on)
  storage.hunts.worm_off[force.index] = on and true or nil
end

-- Startrichtung k0 (0 bis 15) für jede danach startende Jagd der Force, auch reguläre; nil löscht.
function lib.set_spawn_dir(force, k)
  storage.hunts.spawn_dir[force.index] = k
end

-- Protokoll der letzten LOG_SIZE beendeten Jagden (Ring, log_next zeigt auf den nächsten Platz).
function lib.hunt_log()
  return storage.hunts.log
end

-- Ereignisse ---------------------------------------------------------------------------------------

-- Ziel gestorben oder abgebaut: im Zustand warning „Ziel verloren“; beim Biss (biting) ist es die eigene Tötung.
local function on_target_removed(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  local un = entity.unit_number
  if not un then return end
  for _, hunt in pairs(storage.hunts.list) do
    if hunt.target_un == un and hunt.state == "warning" then lose(hunt) end
  end
end

local function on_player_changed_surface(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  local surface = player.physical_surface
  if not (surface and surface.valid and surface.name == ARRAKIS) then return end
  local force = player.force
  local g = lib.grace_of(force)
  if g and not g.awake and not g.landed_tick then
    g.landed_tick = game.tick
    reschedule(force, g, game.tick)
  end
end

-- Beitritt und Force-Wechsel: alle Wurmzeichen-Alarme des Spielers weg (auch alte aus beendeten Jagden), Merker
-- streichen; die Sekundenarbeit setzt die laufender Jagden seiner Force neu.
local function reset_player_alerts(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  player.remove_alert{type = defines.alert_type.custom, icon = ICON}
  for _, hunt in pairs(storage.hunts.list) do hunt.alerted[player.index] = nil end
end

local function on_player_gone(event)
  for _, hunt in pairs(storage.hunts.list) do hunt.alerted[event.player_index] = nil end
end

-- Forschung: Termin der Schonfrist (Ornithopter) und Briefing-Chat (Plan 4.13), auch per Skript erforscht [V2].
local function on_research_finished(event)
  local research = event.research
  if not (research and research.valid) then return end
  local force = research.force
  local name = research.name
  if name == ORNITHOPTER_TECH then
    local g = lib.grace_of(force)
    if g and not g.awake and not g.ornithopter_tick then
      g.ornithopter_tick = game.tick
      if storage.migration.worms_pending then
        -- Mitten in der Migration (migrate.lua holt die Forschung nach): nur merken, den Termin nennt msg-worms-migrated.
        g.active_from = compute_active(g)
        g.announced = g.active_from
      else
        reschedule(force, g, game.tick)
      end
    end
  elseif name == DISCOVERY_TECH then
    force.print({"arrakis-message.msg-briefing"})
  elseif name == HARVESTING_TECH then
    force.print({"arrakis-message.msg-wormsign-tip"})
  end
end

-- Neue Force: feindlich zur Sandwurm-Force; Indizes werden wiederverwendet (A23 classes.d.ts:11510), deshalb alte
-- Datensätze unter diesem Index verwerfen.
local function on_force_created(event)
  local force = event.force
  if not (force and force.valid) or force.name == FORCE then return end
  local worm = game.forces[FORCE]
  if worm then set_hostile(worm, force) end
  storage.grace[force.index] = nil
  storage.worm_stats[force.index] = nil
  -- Prüfstand-Merker (docs/plan-3d2.md 4.1); nil-sicher, falls eine andere Mod vor unserer Migration Forces anlegt.
  local hunts = storage.hunts
  if hunts.worm_off then hunts.worm_off[force.index] = nil end
  if hunts.spawn_dir then hunts.spawn_dir[force.index] = nil end
end

-- Verschmelzen (Plan 4.14): Jagden zur Ziel-Force (redraw im 10-Tick-Takt), Statistik addieren, Datensätze der Quelle weg.
local function on_forces_merging(event)
  local source, destination = event.source, event.destination
  if not (source and source.valid and destination and destination.valid) then return end
  for _, hunt in pairs(storage.hunts.list) do
    if hunt.force_index == source.index then
      hunt.force_index = destination.index
      hunt.redraw = true
    end
  end
  local stats = storage.worm_stats
  local from = stats[source.index]
  if from and not EXEMPT[destination.name] then
    local into = stats_for(destination.index)
    into.bitten = (into.bitten or 0) + (from.bitten or 0)
    into.escaped = (into.escaped or 0) + (from.escaped or 0)
    into.gone = (into.gone or 0) + (from.gone or 0)
    into.killed = (into.killed or 0) + (from.killed or 0)
    local a, b = into.first_escape_tick, from.first_escape_tick
    if b and (not a or b < a) then into.first_escape_tick = b end
  end
  stats[source.index] = nil
  storage.grace[source.index] = nil
  local hunts = storage.hunts
  if hunts.worm_off then hunts.worm_off[source.index] = nil end
  if hunts.spawn_dir then hunts.spawn_dir[source.index] = nil end
end

-- Oberfläche wird gelöscht: Jagden dort ohne Biss beenden (der Wurm taucht still ab).
local function on_pre_surface_deleted(event)
  local list = storage.hunts.list
  for _, id in ipairs(sorted_ids()) do
    local hunt = list[id]
    if hunt and hunt.surface_index == event.surface_index then lib.end_hunt(hunt, nil, "abort") end
  end
end

-- Oberfläche wird geleert (docs/plan-3d2.md 4.1): Ziel und Wurm verschwänden ohne Ereignis; deshalb jetzt Ende "abort",
-- solange beide noch da sind (der Wurm taucht still ab).
local on_pre_surface_cleared = on_pre_surface_deleted

-- Jagd, zu deren Wurm diese Einheit gehört, oder nil.
local function hunt_of_worm(unit)
  if not (unit and unit.valid) then return nil end
  local un = unit.unit_number
  for _, hunt in pairs(storage.hunts.list) do
    local worm = hunt.worm
    if worm and worm.un == un then return hunt end
  end
  return nil
end

local function count_killed(hunt)
  if hunt.debug then return end
  local stats = stats_for(hunt.force_index)
  stats.killed = (stats.killed or 0) + 1
end

-- Wurm getötet (docs/plan-3d2.md 4.11) [W8]: Wurm und Anfragen vergessen, Chat mit Ort; vor 0 Ende killed (das Ziel ist
-- gerettet, KILL_RESCUES), in der Suche Ende mit dem schon gesetzten Ergebnis und killed + 1 dazu.
local function on_segmented_unit_died(event)
  local hunt = hunt_of_worm(event.segmented_unit)
  if not hunt then return end
  local where = hunt.worm.head
  sandworm_lib.forget(hunt)
  local target = hunt.target
  local warning = hunt.state == "warning"
  local rescued = lib.KILL_RESCUES and warning and not hunt.lost and target and target.valid
  local force = force_of(hunt.force_index)
  if force then
    local place = gps_of(hunt.surface_index, where)
    if rescued then
      force.print({"arrakis-message.msg-worm-killed", place, hunt.target_name})
    else
      force.print({"arrakis-message.msg-worm-killed-plain", place})
    end
  end
  if warning and lib.KILL_RESCUES then
    lib.end_hunt(hunt, "killed")
  elseif warning then
    count_killed(hunt)
    sandworm_lib.to_none(hunt, "verloren")
  else
    count_killed(hunt)
    lib.end_hunt(hunt)
  end
end

-- Wurm fremd zerstört (anderer Mod): Phase ohne ("verloren"), Biss bei 0 wie 0.7.0. Unser eigenes Abtauchen leert
-- hunt.worm vorher und kommt hier nie an.
local function on_worm_destroyed(event)
  local hunt = hunt_of_worm(event.segmented_unit)
  if not hunt then return end
  sandworm_lib.forget(hunt)
  sandworm_lib.to_none(hunt, "verloren")
end

lib.events =
{
  [defines.events.on_entity_died] = on_target_removed,
  [defines.events.on_player_mined_entity] = on_target_removed,
  [defines.events.on_robot_mined_entity] = on_target_removed,
  [defines.events.script_raised_destroy] = on_target_removed,
  [defines.events.on_player_changed_surface] = on_player_changed_surface,
  [defines.events.on_player_joined_game] = reset_player_alerts,
  [defines.events.on_player_changed_force] = reset_player_alerts,
  [defines.events.on_player_left_game] = on_player_gone,
  [defines.events.on_player_removed] = on_player_gone,
  [defines.events.on_research_finished] = on_research_finished,
  [defines.events.on_force_created] = on_force_created,
  [defines.events.on_forces_merging] = on_forces_merging,
  [defines.events.on_pre_surface_deleted] = on_pre_surface_deleted,
  [defines.events.on_pre_surface_cleared] = on_pre_surface_cleared,
  [defines.events.on_segmented_unit_died] = on_segmented_unit_died,
  [defines.events.script_raised_destroy_segmented_unit] = on_worm_destroyed
}

lib.on_nth_tick =
{
  [60] = on_nth_tick_60,
  [10] = on_nth_tick_10
}

lib.on_init = function()
  lib.ensure_force()
  for _, force in pairs(game.forces) do lib.grace_of(force) end
end

-- Nach migrate (Schema 4): Force, Migration aus 0.6.x/0.5.x, Verknüpfungen angleichen [V9], Oberflächen, die es nicht
-- mehr gibt oder die nicht mehr erlaubt sind, räumen (samt ihren Jagden), Fenster neu. Ring und Text prüft der
-- 10-Tick-Takt (valid) und zeichnet sie neu. 3d2 (docs/plan-3d2.md 4.14), immer, unabhängig vom alten Schema: Tabellen
-- anlegen, migrate_schema4, ungültige Würmer → verloren, Anfragen ohne Jagd weg, am Ende Waisen räumen.
lib.on_configuration_changed = function()
  lib.ensure_force()
  local hunts = storage.hunts
  storage.path_requests = storage.path_requests or {}
  hunts.worm_off = hunts.worm_off or {}
  hunts.spawn_dir = hunts.spawn_dir or {}
  hunts.log = hunts.log or {}
  hunts.log_next = hunts.log_next or 1
  hunts.ersatz = hunts.ersatz or 0
  lib.migrate_schema4()
  for _, id in ipairs(sorted_ids()) do
    local hunt = hunts.list[id]
    local worm = hunt.worm
    if worm and not (worm.unit and worm.unit.valid) then
      sandworm_lib.forget(hunt)
      sandworm_lib.to_none(hunt, "verloren")
    end
  end
  local requests = storage.path_requests
  local orphans = {}
  for request_id, entry in pairs(requests) do
    if not hunts.list[entry.hunt] then orphans[#orphans + 1] = request_id end
  end
  for _, request_id in ipairs(orphans) do requests[request_id] = nil end
  local migration = storage.migration
  if migration.worms_pending then
    lib.migrate_schema3()
    migration.worms_pending = nil
  end
  for _, force in pairs(game.forces) do lib.grace_of(force) end
  local overlay = storage.vib.overlay
  for _, player in pairs(game.players) do vibration_lib.set_toggled(player, overlay[player.index] ~= nil) end
  local gone = {}
  local function check(s)
    local surface = game.get_surface(s)
    if not (surface and terrain.harvest_allowed(surface)) then gone[s] = true end
  end
  for s in pairs(storage.vib.heat) do check(s) end
  for s in pairs(storage.sector_cooldown) do check(s) end
  for s in pairs(storage.vib.rumble) do check(s) end
  for _, record in pairs(storage.vib.sources) do check(record.surface) end
  for _, hunt in pairs(storage.hunts.list) do check(hunt.surface_index) end
  local list = storage.hunts.list
  for _, id in ipairs(sorted_ids()) do
    local hunt = list[id]
    if hunt and gone[hunt.surface_index] then lib.end_hunt(hunt, nil, "abort") end
  end
  for s in pairs(gone) do vibration_lib.drop_surface(s) end
  -- Würmer unseres Prototyps ohne Jagd auf allen Oberflächen (docs/plan-3d2.md 4.14).
  local swept = sandworm_lib.sweep()
  if swept > 0 then log("Arrakis: " .. swept .. " Sandwürmer ohne Jagd entfernt") end
  for _, player in pairs(game.connected_players) do
    worms_gui.destroy(player)
    worms_gui.refresh(player)
  end
end

lib.add_commands = function()
  commands.add_command("arrakis-worm", {"arrakis-message.worm-cmd-help"}, worm_command)
end

return lib
