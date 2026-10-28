-- Prüfstand: Sandwurm mit echtem Laufzeitcode (Phase 3d2, docs/plan-3d2.md 6; Vertrag siehe runner.lua).
--   T21: scripts/sandworm.lua und scripts/worms.lua mit dem echten Wurm auf der Prüfstand-Fläche, ohne Spieler: Prototypen und
--        storage, Zeitlinie einer regulären Jagd, Felsinsel, Sandtasche mit Knick (ROUTING), Ernter vor Fels, Ornithopter über
--        dem Kopf, Rettung, Zerdrücken, Ersatzbiss, Wurm getötet, Wurm verloren, Flucht per Fahrt, Grenzen, Migration und
--        Waisen, Entfernen. Fünfzehn Schritte in zwölf Feldern zu 400 × 400 Kacheln; die Schritte 2 bis 12 laufen in drei
--        Wellen (nie mehr als 3 Befehlsjagden mit Wurm, nie mehr als 6 Würmer), danach 13 bis 15 nacheinander in Feld 12.
--   T22: Optik und Laden (interaktiv, nur mit Spieler und seiner Force): Auftauchen, Halten, Biss und Abtauchen, Fels,
--        Zerdrücken, Ornithopter, Rettung, Tod des Wurms, Factoriopedia, Speichern und Laden. ALT+O (ab 0.8.3 auch
--        /arrakis-test weiter) schaltet weiter; jede FRAGE wartet auf Max.
-- Gebaut wird mit raise_built = true (die Laufzeitmodule tragen ein); Fahrer sind Puppen ohne Spieler (tb.dummy_driver),
-- gefahren wird über riding_state an Fahrzeug und Puppe jeden Tick (wie T13 und T19).
-- Die Tests zählen Ticks. Der Kopf wird je 10 Ticks in der Mitte zwischen zwei Takten gelesen (tick % 10 == 5) über
-- sandworm.head_of; Phasenwechsel erkennt der Test jeden Tick und rundet den Tick auf den Takt ab (Vielfaches von 10):
-- Die Reihenfolge zwischen dem 10-Tick-Takt von worms.lua und dem Prüfstand-Tick ist nicht zugesichert.
-- Knoten 1 springt im Kachelraster (W18, Prüfstand 2026-10-27): Er bleibt bis zu 1 Kachel hinter dem wahren Kopf, je 10 Ticks
-- kommt er 0, 1 oder 2 Kacheln weit. Ein Takt allein misst also kein Tempo; Tempo und Weg zählen nur über Fenster, deren Fehler
-- unter 1 Kachel bleibt (je Lauf ohne Unterbrechung), und die Texte nennen das Fenster.
-- Sollwerte stehen hier als Zahlen aus dem Plan (1, 4.4 bis 4.11, 6), bewusst nicht aus den Modulen gelesen. Ausnahme sind
-- die Standardwahlen aus Plan 1, die Max am 27.10. entschieden hat und die eine Konstante im Modul bleiben (Zerdrücken auch
-- von Fahrzeugen und Figuren: worms.CRUSH_SPARES_VEHICLES; Wurm getötet rettet: worms.KILL_RESCUES; Sprint:
-- sandworm.SPRINT): Die liest der Test aus den Modulen, damit ein Wechsel nur eine Stelle braucht.
-- Zustand nur in run.data (Zahlen, Texte, Positionen, LuaEntity-, LuaSegmentedUnit- und LuaForce-Referenzen; vor jeder
-- Benutzung prüfen). Abläufe und Messhaken stehen als Funktionslisten in diesem Modul, run.data hält nur Nummern.
--
-- Isolation (Plan 4.18): T21 benutzt die eigene Force arrakis-t21 (einmal anlegen, wiederverwenden), wach, mit
-- first_hunt_done, eingeschaltet für die Prüfstand-Fläche und mit der Startrichtung k0 = 2 (Nordost) für jede Jagd ohne
-- eigenen Haken. T22 benutzt Max' Force und schreibt Schonfrist, Pause und Statistik zurück (wie T20). cleanup beendet jede
-- Jagd der Force mit "abort" (die Würmer tauchen still ab), setzt set_worm_off und set_spawn_dir zurück, räumt Waisen auf der
-- Prüfstand-Fläche (sandworm.sweep) und Würmer, die der Test selbst erzeugt hat, und prüft, dass kein arrakis-sandworm-* im
-- Bereich bleibt. Jeder Schritt beendet seine Jagden, bevor er seine Entities entfernt: Kein Wurm überlebt einen Schritt.
-- Die Modultabellen heißen hier vibration_lib, worms_lib, sandworm_lib und flyer_lib (tools/check/api_names.py).

local harvester = require("scripts.harvester")
local flyer_lib = require("scripts.flyer")
local terrain = require("scripts.terrain")
local vibration_lib = require("scripts.vibration")
local sandworm_lib = require("scripts.sandworm")
local worms_lib = require("scripts.worms")
local speed = require("prototypes.ornithopter-speed")

local HARVESTER = "spice-harvester"
local FLYER = "arrakis-ornithopter"
local SPICE = "spice-sand"
local ROCK = "arrakis-rock"
local CHEST = "wooden-chest"
local ERUPTION = "arrakis-worm-eruption"
local DIVE = "arrakis-worm-dive"
local WORM = "arrakis-sandworm-small"
local PREFIX = "arrakis-sandworm-"
local TEST_WORM = "arrakis-test-worm"
local WORM_FORCE = "arrakis-sandworm"
local SMOKES = {"arrakis-sandworm-smoke-front", "arrakis-sandworm-smoke-small-top", "arrakis-sandworm-smoke-small-bottom",
                "arrakis-sandworm-smoke-big"}
local T21_FORCE = "arrakis-t21"

-- Sollwerte aus dem Plan --------------------------------------------------------------------------
local WARN_TICKS = 3600
-- 60 s auf freiem Sand (Plan 4.4 Schritt 2): routing bei eta − 3230, Wurm bei eta − 2930 (D = 160).
local PLAN_LEAD = 3230
local SPAWN_LEAD = 2930
local CANDIDATES = 48
local NODES = 22
local BODY_STEP = 4
-- Letzter Knoten mindestens so viel weiter vom Ziel als der Kopf (Körper auf der abgewandten Seite).
local BODY_AWAY = 18
-- W1: Tempo 1 s nach dem Spawn (Kacheln/s).
local V_W1 = 3.3
local ATTACK_RANGE = 40
local BITE_WINDOW = 180
-- R = 3 + r, Ernter r = 1,58 (Plan 1 „Biss“).
local BITE_REACH = 3
local R_HARVESTER = 4.58
local R_TOLERANCE = 0.01
-- Zerdrücken: Kopf höchstens 2,5 + 0,6 Kacheln von der Box (ein Takt Fahrt).
local CRUSH_REACH = 2.5 + 0.6
local ROCK_BOX_INFO = 0.05
-- W2: Weg beim Halten höchstens 0,5 Kacheln plus 0,1 je Sekunde.
local HOLD_BASE, HOLD_PER_S = 0.5, 0.1
-- Schritt 3: erster Umweg mindestens 2 Kacheln vor dem Inselrand, binnen 180 Ticks ≥ 20° Drehung.
local DETOUR_EDGE = 2
local TURN_MIN = 20
local TURN_WINDOW = 180
-- W3 hält ab diesem mittleren Sprinttempo (Kacheln/s), bei 6 geschriebenen also ab diesem Anteil des geschriebenen Wegs.
local SPRINT_W3 = 5.5
local SPRINT_SHARE = SPRINT_W3 / 6
-- Raster der Körperknoten (W18): Fehler eines Wegs je Lauf; Tempo im Text über 6 Proben (1 s).
local NODE_STEP = 1
local SPEED_SAMPLES = 6
-- Schritt 6: Mitflug, Ruhe, Flug nach Westen über den Körper.
local ESCORT_START = 600
local ESCORT_TICKS = 300
local ESCORT_LEAD = 6
local ESCORT_SIDE = 60
local FLIGHT = 80
local ESCORT_DIST = 0.5
local ESCORT_SPEED = 0.98
local FLIGHT_MAX = 900
-- Ruhe vor dem Flug: beide unter REST_SPEED Kacheln/s für REST_CALM Ticks, höchstens REST_MAX Ticks.
local REST_SPEED = 0.05
local REST_CALM = 10
local REST_MAX = 240
-- Über dem Körper: höchstens OVER_NEAR Kacheln von einem Körperknoten, mindestens OVER_MIN Ticks des Flugs. Grenze für das
-- Bremsen dort (0.8.2): O6 mindestens BRAKE.min des mittleren Tempos der beiden Vergleichsflieger in denselben Ticks, Flugzeit
-- höchstens BRAKE.flight × deren Mittel. Der Lauf vom 27.10.2026 (0.8.1) maß 89 % für 115 Ticks (1,6 Kacheln Rückstand, Flugzeit
-- 102,2 %); die Ursache ist offen, darum der zweite Vergleichsflieger O6c südlich und die MESSUNGen (Seitenabweichung,
-- Wegpunkte des Autopiloten, Tempo je 20 Ticks). Spürbares Bremsen (ein Fünftel und mehr) bleibt FEHLER.
local OVER_NEAR = 3
local OVER_MIN = 60
-- (Eine Tabelle statt vier Konstanten: Die Datei liegt an der Grenze von 200 lokalen Namen je Funktion.)
local BRAKE = {min = 0.8, flight = 1.05, profile_step = 20, profile_ticks = 160}
-- Schritt 7: Rettung wie T19 Schritt 4.
local RESCUE_COUPLE = 720
local RESCUE_CARRIED = 590
local RESCUE_NEAR = 8
local DIVE_AFTER = 30
local SEARCH_TICKS = 600
-- Schritt 9: Spawn bei eta − 840.
local ERSATZ_SPAWN = 840
-- Schritt 10: Schaden und Tod.
local KILL_DAMAGE_AFTER = 300
local KILL_DAMAGE = 1000
local KILL_AFTER = 600
local KILL_STATE_MAX = 40
local REST_MIN = 7200
-- Schritt 11: Verlust 300 Ticks nach dem Spawn.
local LOST_AFTER = 300
-- Schritt 13 bis 15.
local LIMIT_WINDOW = 300
local SHORT_SECONDS = 20
local UNINSTALL_SECONDS = 27
local UNINSTALL_SPAWN = 60
local UNINSTALL_SLACK = 9
-- Fläche (Plan 6): zwölf Felder zu 400 × 400 um den Ursprung.
local FIELD_HALF = 200
local COLS = {-400, 0, 400}
local ROWS = {-600, -200, 200, 600}
local AREA_HALF = {x = 600, y = 800}
-- Wellen (Plan 6): A ab Tick 13 mit 2, 10, 12 (regulär) und 3, 4, 5; B mit 6, 7, 8 und C mit 9, 11, sobald keine
-- Befehlsjagd mehr einen Wurm hat; dann 13, 14, 15 nacheinander.
local WAVE = {[1] = "A", [2] = "A", [3] = "A", [4] = "A", [5] = "A", [10] = "A", [12] = "A", [6] = "B", [7] = "B", [8] = "B",
              [9] = "C", [11] = "C", [13] = "T13", [14] = "T14", [15] = "T15"}
local WAVE_DEBUG = {A = {3, 4, 5}, B = {6, 7, 8}}
local REGULAR_ORDER = {2, 10, 12}
local STEP_COUNT = 15

-- Allgemeine Helfer ---------------------------------------------------------------------------

local function valid(object)
  return object ~= nil and object.valid
end

local function copy_pos(position)
  return {x = position.x or position[1], y = position.y or position[2]}
end

local function at(origin, dx, dy)
  return {x = origin.x + dx, y = origin.y + dy}
end

local function pos_text(tb, position)
  if not position then return "–" end
  local p = copy_pos(position)
  return "(" .. tb.num(p.x) .. ", " .. tb.num(p.y) .. ")"
end

-- Liest einen Wert; Fehler werden zu nil.
local function read(fn)
  local ok, value = pcall(fn)
  if ok then return value end
  return nil
end

local function check(failed, ok, label)
  if not ok then table.insert(failed, label) end
  return ok
end

local function copy(record)
  if record == nil then return nil end
  local out = {}
  for key, value in pairs(record) do out[key] = value end
  return out
end

local function dist(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

-- Tick auf den Takt abgerundet (Vielfaches von 10).
local function takt(tick)
  return math.floor(tick / 10) * 10
end

-- Tick relativ zu eta als Text („eta − 2930“, „eta + 0“).
local function rel(tick, eta)
  if not tick or not eta then return "–" end
  local delta = tick - eta
  return delta < 0 and ("eta − " .. -delta) or ("eta + " .. delta)
end

local function count_list(list)
  local n = 0
  for _ in pairs(list or {}) do n = n + 1 end
  return n
end

-- Ticks bis zur nächsten Takt-Mitte des 60-Tick-Takts (tick % 60 == 30), mindestens min (Standard 1).
local function to_mid(min)
  min = min or 1
  local n = (30 - (game.tick + min) % 60) % 60
  return min + n
end

-- Ticks bis zum nächsten Tick ≥ target mit tick % 10 == 5 (Takt-Mitte des 10-Tick-Takts), mindestens 1.
local function to_sample(target)
  local t = math.max(target, game.tick + 1)
  local n = (5 - t % 10) % 10
  return t + n - game.tick
end

local function box_of(center, half)
  return
  {
    left_top = {x = math.floor(center.x - half.x), y = math.floor(center.y - half.y)},
    right_bottom = {x = math.ceil(center.x + half.x), y = math.ceil(center.y + half.y)}
  }
end

local function inside(box, position)
  local x, y = position.x or position[1], position.y or position[2]
  return x >= box.left_top.x and x <= box.right_bottom.x and y >= box.left_top.y and y <= box.right_bottom.y
end

local function overlaps(a, b)
  return a.left_top.x < b.right_bottom.x and b.left_top.x < a.right_bottom.x
    and a.left_top.y < b.right_bottom.y and b.left_top.y < a.right_bottom.y
end

-- Abstand von (x, y) zur Box (gedreht: umschließendes Rechteck, wie scripts/worms.lua).
local function box_distance(box, x, y)
  if not box then return nil end
  local x1, y1, x2, y2 = box.left_top.x, box.left_top.y, box.right_bottom.x, box.right_bottom.y
  local orientation = box.orientation
  if orientation and orientation ~= 0 then
    local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
    local hw, hh = (x2 - x1) / 2, (y2 - y1) / 2
    local angle = orientation * 2 * math.pi
    local c, s = math.abs(math.cos(angle)), math.abs(math.sin(angle))
    local ex, ey = hw * c + hh * s, hw * s + hh * c
    x1, y1, x2, y2 = mx - ex, my - ey, mx + ex, my + ey
  end
  local dx = math.max(x1 - x, 0, x - x2)
  local dy = math.max(y1 - y, 0, y - y2)
  return math.sqrt(dx * dx + dy * dy)
end

local function box_copy(box)
  if not box then return nil end
  return {left_top = copy_pos(box.left_top), right_bottom = copy_pos(box.right_bottom), orientation = box.orientation}
end

-- Abstand eines Punkts zu einem Kachelrechteck x1..x2 × y1..y2 (Kachelnummern, beide eingeschlossen).
local function rect_distance(rect, p)
  local dx = math.max(rect.x1 - p.x, 0, p.x - (rect.x2 + 1))
  local dy = math.max(rect.y1 - p.y, 0, p.y - (rect.y2 + 1))
  return math.sqrt(dx * dx + dy * dy)
end

-- Winkel zwischen zwei Richtungen (Grad, 0 bis 180).
local function angle_between(a, b)
  if not (a and b) then return 0 end
  local dot = a.x * b.x + a.y * b.y
  return math.deg(math.acos(math.max(-1, math.min(1, dot))))
end

local function unit_vector(dx, dy)
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1e-9 then return nil end
  return {x = dx / len, y = dy / len}
end

-- Natürlicher Sand an (x, y): erzeugter Chunk und natürliche Kachel kein Fels (wie scripts/sandworm.lua).
local function sand_at(surface, x, y)
  if not surface.is_chunk_generated{math.floor(x / 32), math.floor(y / 32)} then return false end
  return terrain.natural_tile_name(surface, x, y) ~= ROCK
end

-- Strecke a → b alle step Kacheln (ohne a, mit b) auf Sand, Mittellinie und Parallelen ±side.
local function line_sand(surface, a, b, step, side)
  local u = unit_vector(b.x - a.x, b.y - a.y)
  if not u then return true end
  local len = dist(a, b)
  for _, o in ipairs(side and {0, side, -side} or {0}) do
    local ox, oy = -u.y * o, u.x * o
    local s = step
    while true do
      local t = math.min(s, len)
      if not sand_at(surface, a.x + u.x * t + ox, a.y + u.y * t + oy) then return false end
      if t >= len then break end
      s = s + step
    end
  end
  return true
end

local function storage_ready()
  return storage.harvesters and storage.flyers and storage.vib and storage.vib.heat and storage.hunts and storage.hunts.list
    and storage.grace and storage.worm_stats and storage.sector_cooldown and storage.path_requests
end

local function force_named(name)
  return game.forces[name] or game.create_force(name)
end

local function worm_force()
  return game.forces[WORM_FORCE] or worms_lib.ensure_force()
end

-- Kacheln x1..x2 × y1..y2 (Kachelnummern, beide eingeschlossen) mit einer Kachel belegen. Entities bleiben stehen.
local function tiles(surface, x1, y1, x2, y2, name)
  local list = {}
  for x = x1, x2 do
    for y = y1, y2 do list[#list + 1] = {name = name, position = {x, y}} end
  end
  surface.set_tiles(list, true, false, true, false)
  return #list
end

-- 13×13-Spice-Teppich um die Kachel unter position (das Erntefeld des Ernters, wie T19).
local function carpet(surface, position, amount)
  local x, y = math.floor(position.x), math.floor(position.y)
  local placed = 0
  for i = x - 6, x + 6 do
    for j = y - 6, y + 6 do
      if surface.create_entity{name = SPICE, position = {i + 0.5, j + 0.5}, amount = amount or 1000} then placed = placed + 1 end
    end
  end
  return placed
end

-- Gas geben oder loslassen: riding_state am Fahrzeug und am Dummy-Fahrer (wie T2, T13).
local function gas(car, driver, on)
  local state =
  {
    acceleration = on and defines.riding.acceleration.accelerating or defines.riding.acceleration.nothing,
    direction = defines.riding.direction.straight
  }
  pcall(function() car.riding_state = state end)
  if valid(driver) then pcall(function() driver.riding_state = state end) end
end

local function car_state(car)
  if not valid(car) then return "weg" end
  local h = harvester.get(car)
  return h and h.state or "ohne Datensatz"
end

-- Wärme -------------------------------------------------------------------------------------------

local function heat_chunk(surface, position, h)
  local cx, cy = vibration_lib.chunk_of_key((vibration_lib.key_of(position)))
  vibration_lib.set_heat(surface, cx, cy, h)
end

-- Die 9 Chunks um key (vorhandene Einträge) auf 0.
local function zero_around(surface, key)
  local cx, cy = vibration_lib.chunk_of_key(key)
  for dx = -1, 1 do
    for dy = -1, 1 do
      if vibration_lib.heat_entry(surface, vibration_lib.chunk_key(cx + dx, cy + dy)) then
        vibration_lib.set_heat(surface, cx + dx, cy + dy, 0)
      end
    end
  end
end

-- Sind die 9 Chunks um key leer oder 0?
local function nine_zero(surface, key)
  local cx, cy = vibration_lib.chunk_of_key(key)
  for dx = -1, 1 do
    for dy = -1, 1 do
      local h = vibration_lib.heat_entry(surface, vibration_lib.chunk_key(cx + dx, cy + dy))
      if h and h > 1e-9 then return false end
    end
  end
  return true
end

-- Wärme und Ruhe auf der Fläche box löschen (Chunks mit Mitte in box, Sektoren, die box berühren).
local function clear_area(surface, box)
  local s = surface.index
  local e = storage.vib.heat[s]
  if e then
    local keys = {}
    for key in pairs(e.chunks) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do
      local cx, cy = vibration_lib.chunk_of_key(key)
      if inside(box, {x = cx * 32 + 16, y = cy * 32 + 16}) then vibration_lib.set_heat(surface, cx, cy, 0) end
    end
  end
  local cool = storage.sector_cooldown[s]
  if cool then
    local sectors = {}
    for sector in pairs(cool) do sectors[#sectors + 1] = sector end
    for _, sector in ipairs(sectors) do
      local sx, sy = vibration_lib.chunk_of_key(sector)
      local area = {left_top = {x = sx * 128, y = sy * 128}, right_bottom = {x = sx * 128 + 128, y = sy * 128 + 128}}
      if overlaps(box, area) then vibration_lib.rest(s, sector, 0) end
    end
  end
end

-- Jagden ----------------------------------------------------------------------------------------

local function hunt_list(filter)
  local ids = {}
  for id, hunt in pairs(storage.hunts.list) do
    if not filter or filter(hunt) then ids[#ids + 1] = id end
  end
  table.sort(ids)
  local list = {}
  for _, id in ipairs(ids) do list[#list + 1] = storage.hunts.list[id] end
  return list
end

-- Jede Jagd der Forces (Indizes als Schlüssel) mit "abort" beenden; gibt die Zahl zurück.
local function abort_hunts(force_indices)
  local n = 0
  for _, hunt in ipairs(hunt_list(function(h) return force_indices[h.force_index] end)) do
    worms_lib.end_hunt(hunt, nil, "abort")
    n = n + 1
  end
  return n
end

local function end_if_running(hunt)
  if hunt and storage.hunts.list[hunt.id] == hunt then worms_lib.end_hunt(hunt, nil, "abort") end
end

-- Zahl der regulären Jagden (ohne Befehlsjagden), optional nur anderer Forces.
local function regular_count(own)
  local n = 0
  for _, hunt in pairs(storage.hunts.list) do
    if not hunt.debug and not (own and own[hunt.force_index]) then n = n + 1 end
  end
  return n
end

-- Jagden anderer Forces (jede Art).
local function foreign_count(own)
  local n = 0
  for _, hunt in pairs(storage.hunts.list) do
    if not own[hunt.force_index] then n = n + 1 end
  end
  return n
end

-- Protokolleintrag einer Jagd aus storage.hunts.log (Plan 4.16) oder nil.
local function log_entry(id)
  for _, entry in pairs(worms_lib.hunt_log() or {}) do
    if entry.id == id then return entry end
  end
  return nil
end

-- Abtauchen ab tick (seit 0.8.4 als Welle über sandworm.DIVE_TICKS): ein segmented_unit_destroyed von tick bis
-- tick + DIVE_TICKS + 10, oder die Einheit taucht noch ab.
local function dived_after(ev, un, tick)
  if #ev.destroyed == 1 then
    return tick ~= nil and ev.destroyed[1] >= tick and ev.destroyed[1] <= tick + sandworm_lib.DIVE_TICKS + 10
  end
  if #ev.destroyed > 1 then return false end
  for _, entry in ipairs(storage.worm_dives or {}) do
    if entry.unit and entry.unit.valid and entry.unit.unit_number == un then return true end
  end
  return false
end

-- Würmer unseres Prototyps (arrakis-sandworm-*) mit einem Knoten in box; abtauchende (ab 0.8.4, noch höchstens
-- sandworm.DIVE_TICKS sichtbar) zählen nicht.
local function sandworms_in(surface, box)
  local n = 0
  for _, unit in pairs(surface.get_segmented_units()) do
    if unit.valid and unit.prototype.name:sub(1, #PREFIX) == PREFIX and not sandworm_lib.diving(unit) then
      for _, node in pairs(unit.get_body_nodes()) do
        if inside(box, node) then
          n = n + 1
          break
        end
      end
    end
  end
  return n
end

-- Würmer unseres Prototyps auf der Oberfläche, ohne abtauchende.
local function sandworms_on(surface)
  local n = 0
  for _, unit in pairs(surface.get_segmented_units()) do
    if unit.valid and unit.prototype.name:sub(1, #PREFIX) == PREFIX and not sandworm_lib.diving(unit) then n = n + 1 end
  end
  return n
end

-- Erzeugt einen Wurm (Probe, Waise, Testwurm) in pcall; ein Fehler schreibt eine Logzeile. Der Test merkt ihn für
-- das Aufräumen.
local function spawn_unit(run, tb, d, name, position, direction, force)
  local surface = tb.surface()
  local ok, unit = pcall(function()
    return surface.create_segmented_unit{name = name, position = position, direction = direction, extended = true, force = force}
  end)
  if not ok then
    log("Arrakis-Prüfstand: create_segmented_unit " .. name .. " fehlgeschlagen: " .. tostring(unit))
    tb.trace(run, "create_segmented_unit " .. name .. " bei " .. pos_text(tb, position) .. ": " .. tostring(unit))
    return nil
  end
  if not valid(unit) then return nil end
  d.units[#d.units + 1] = unit
  return unit
end

-- Entities und Aufräumen ------------------------------------------------------------------------

local function new_made()
  return {cars = {}, flyers = {}, others = {}}
end

-- Erzeugt eine Entity auf der Prüfstand-Fläche mit raise_built und merkt sie im Schritt s für das Aufräumen (kind: cars,
-- flyers, others); nil, wenn es nicht ging (Grund in der Datei).
local function make(run, tb, s, params, kind)
  if params.raise_built == nil then params.raise_built = true end
  local ok, entity = pcall(function() return tb.surface().create_entity(params) end)
  if ok and entity then
    table.insert(s.made[kind or "others"], entity)
    return entity
  end
  tb.trace(run, params.name .. " bei " .. pos_text(tb, params.position) .. " ging nicht" .. (ok and "" or (": " .. tostring(entity))))
  return nil
end

local function remember(s, entity, kind)
  if valid(entity) then table.insert(s.made[kind or "others"], entity) end
  return entity
end

-- Echter Ernter (eingetragen über raise_built). opts: orientation, coal, spice (Laderaum), driver, field (Teppich).
local function new_harvester(run, tb, d, s, position, opts)
  opts = opts or {}
  local surface = tb.surface()
  local force = opts.force or d.force
  if opts.field then carpet(surface, position, opts.field) end
  local car = make(run, tb, s, {name = HARVESTER, position = position, force = force, orientation = opts.orientation or 0.25}, "cars")
  if not car then return nil end
  if opts.coal then tb.fuel(car, "coal", opts.coal) end
  if opts.spice then car.get_inventory(defines.inventory.car_trunk).insert{name = SPICE, count = opts.spice} end
  if opts.driver then
    local driver = tb.dummy_driver(car, force)
    remember(s, driver)
    s.drivers = s.drivers or {}
    s.drivers[car.unit_number] = driver
  end
  s.keys = s.keys or {}
  s.keys[vibration_lib.key_of(position)] = true
  return car
end

-- Auto mit Kohle und optional Puppe als Fahrer.
local function new_car(run, tb, d, s, position, opts)
  opts = opts or {}
  local car = make(run, tb, s, {name = "car", position = position, force = opts.force or d.force, orientation = opts.orientation or 0})
  if not car then return nil end
  tb.fuel(car, "coal", 5)
  if opts.driver then
    local driver = tb.dummy_driver(car, opts.force or d.force)
    remember(s, driver)
    s.drivers = s.drivers or {}
    s.drivers[car.unit_number] = driver
  end
  return car
end

-- Echter Ornithopter mit Kohle; opts.pilot setzt eine Puppe als Pilot.
local function new_flyer(run, tb, d, s, position, opts)
  opts = opts or {}
  local flyer = make(run, tb, s, {name = FLYER, position = position, force = opts.force or d.force, create_build_effect_smoke = false}, "flyers")
  if not flyer then return nil end
  tb.fuel(flyer, "coal", opts.coal or 10)
  if opts.pilot then remember(s, tb.dummy_driver(flyer, opts.force or d.force)) end
  return flyer
end

local function driver_of(s, vehicle)
  return valid(vehicle) and s.drivers and s.drivers[vehicle.unit_number] or nil
end

local function pilot_of(flyer)
  local pilot = valid(flyer) and read(function() return flyer.get_driver() end)
  if pilot and pilot.object_name == "LuaEntity" then return pilot end
  return nil
end

local function deploy(car)
  local h = valid(car) and harvester.get(car)
  if not h then return false, "kein Datensatz" end
  return harvester.deploy(h)
end

-- Entfernt, was ein Schritt gebaut hat: zuerst seine Jagden ("abort", der Wurm taucht still ab), dann Ernter
-- (raise_destroy), Ornithopter und den Rest; danach die Chunks seiner Quellen auf 0.
local function tidy(s)
  for _, key in ipairs({"hunt", "hunt2"}) do
    local w = s[key]
    if w then end_if_running(w) end
  end
  for _, hunt in ipairs(s.hunts or {}) do end_if_running(hunt) end
  local made = s.made
  if made then
    for _, kind in ipairs({"cars", "flyers", "others"}) do
      for _, entity in pairs(made[kind]) do
        if valid(entity) then pcall(function() entity.destroy{raise_destroy = true} end) end
      end
      made[kind] = {}
    end
  end
  local surface = game.get_surface("arrakis-testbench")
  if surface and s.keys then
    for key in pairs(s.keys) do pcall(zero_around, surface, key) end
  end
end

-- Ablauf ----------------------------------------------------------------------------------------
-- Je Schritt eine Liste von Phasen (wie T15 und T19). Eine Phase gibt zurück: "poll" = nächsten Tick dieselbe Phase,
-- Zahl n = nächste Phase in n Ticks, again(n) = dieselbe Phase in n Ticks, "end" = Schritt fertig. Jeder Schritt schreibt
-- genau eine OK/FEHLER-Zeile (verdict oder fail; Schritt 13 bei fremden Jagden eine INFO-Zeile); danach räumt tidy ab.

local function again(n)
  return {again = n}
end

local function verdict(run, tb, number, title, failed, values)
  local level = #failed == 0 and "OK" or "FEHLER"
  local text = number .. ") " .. title .. ": " .. values
  if #failed > 0 then text = text .. " | nicht erfüllt: " .. table.concat(failed, "; ") end
  tb.log(run, level, text)
  run.data.results[number] = level
  return "end"
end

local function fail(run, tb, number, text)
  tb.log(run, "FEHLER", number .. ") " .. text)
  run.data.results[number] = "FEHLER"
  return "end"
end

local function lanes_init(d)
  d.lanes = {}
  d.results = {}
  for number = 1, STEP_COUNT do
    d.lanes[number] = {phase = 1, wait_until = 0}
    d["s" .. number] = {made = new_made(), failed = {}, number = number}
  end
end

local function lane_done(run, tb, d, number)
  d.lanes[number].done = true
  local ok, err = pcall(tidy, d["s" .. number])
  if not ok then tb.trace(run, "Aufräumen nach Schritt " .. number .. " ging nicht: " .. tostring(err)) end
end

local function lane_step(run, tb, d, steps, number)
  local lane = d.lanes[number]
  if lane.done or game.tick < lane.wait_until then return end
  local phase = steps[number][lane.phase]
  if not phase then
    if not d.results[number] then fail(run, tb, number, "keine Ergebniszeile (Prüfstand-Fehler)") end
    lane_done(run, tb, d, number)
    return
  end
  local ok, result = pcall(phase, run, tb, d, d["s" .. number])
  if not ok then
    fail(run, tb, number, "Skriptfehler: " .. tostring(result))
    result = "end"
  end
  if result == "poll" then return end
  if type(result) == "table" then
    lane.wait_until = game.tick + (result.again or 1)
    return
  end
  if result == "end" then
    lane_done(run, tb, d, number)
  else
    lane.phase = lane.phase + 1
    lane.wait_until = game.tick + (type(result) == "number" and math.max(1, result) or 1)
  end
end

local function summary(run, count)
  local ok, wrong, open = 0, {}, {}
  for number = 1, count do
    local result = run.data.results[number]
    if result == "OK" then
      ok = ok + 1
    elseif result == "INFO" or result == "MESSUNG" then
      table.insert(open, tostring(number))
    else
      table.insert(wrong, tostring(number))
    end
  end
  local text = string.format("%d/%d Schritte OK", ok, count)
  if #wrong > 0 then text = text .. ", FEHLER in " .. table.concat(wrong, ", ") end
  if #open > 0 then text = text .. ", von Hand prüfen: " .. table.concat(open, ", ") end
  return text
end

-- Ereignisse: Tode, Würmer, Wege ---------------------------------------------------------------------

-- Entity-Tod (weitergeleitetes entity_died): je unit_number Tick, Name, Ort, Box, Force, Täter, Eruptionen am Ort und, wenn
-- ein beobachteter Wurm im Feld fährt, der Abstand seines Kopfes zur Box (im Takt des Zerdrückens gelesen).
local function note_death(d, event)
  local entity = event.entity
  if not valid(entity) then return end
  d.deaths = d.deaths or {}
  d.death_list = d.death_list or {}
  local position = copy_pos(entity.position)
  local record =
  {
    tick = event.tick, name = entity.name, un = entity.unit_number, position = position, box = box_copy(entity.bounding_box),
    force = event.force and event.force.valid and event.force.name or nil,
    cause = event.cause and (event.cause.valid and event.cause.name or "ungültig") or nil,
    eruptions = #entity.surface.find_entities_filtered{name = ERUPTION, position = position, radius = 2}
  }
  for number, s in pairs(d.active or {}) do
    local w = d["s" .. number] and d["s" .. number].watch
    if w and not w.ended and inside(w.box, position) then
      local head = sandworm_lib.head_of(w.hunt)
      if head then record.head_dist = box_distance(record.box, head.x, head.y) end
    end
  end
  if entity.unit_number then d.deaths[entity.unit_number] = record end
  table.insert(d.death_list, record)
end

local function died(d, un)
  return d.deaths and un and d.deaths[un] or nil
end

-- Tode in box vor dem Tick (Namen).
local function deaths_before(d, box, tick)
  local names = {}
  for _, record in ipairs(d.death_list or {}) do
    if inside(box, record.position) and record.tick < tick then table.insert(names, record.name) end
  end
  return names
end

local function note_unit(d, kind, event)
  local unit = event.segmented_unit
  if not valid(unit) then return end
  local un = unit.unit_number
  d.unit_events = d.unit_events or {}
  local e = d.unit_events[un] or {died = {}, destroyed = {}}
  d.unit_events[un] = e
  table.insert(e[kind], event.tick)
end

local function unit_events(d, un)
  return (d.unit_events and un and d.unit_events[un]) or {died = {}, destroyed = {}}
end

-- Beobachtung einer Jagd ------------------------------------------------------------------------------
-- Je Tick: Phasen, Grund ohne Wurm, Abtauchen, Anfragen, neuer Wurm, Umwege, Wechsel in den Angriff und in die Suche.
-- Je Takt-Mitte (tick % 10 == 5) mit Wurm: Kopf, Richtung, Fels, Aktivität, Zustand, Tempo, Halten, Sprint, Ankunft; dazu
-- der Messhaken des Schritts (SAMPLE).

local SAMPLE = {}

-- Feld je Schritt (Plan 6): Schritt n in Feld n, Schritt 1 (Probewurm) und 13 bis 15 in Feld 12, Schritt 2 in Feld 1, Schritt 12 in Feld 2.
local FIELD_OF = {[1] = 12, [2] = 1, [12] = 2, [13] = 12, [14] = 12, [15] = 12}

local function watch_new(d, number, hunt)
  local field = d.fields[FIELD_OF[number] or number]
  return
  {
    hunt = hunt, id = hunt.id, number = number, eta = hunt.eta_tick, warn = hunt.warn_tick, box = field and field.box,
    R = BITE_REACH + (hunt.r or 1.58), first_phase = hunt.phase, phase = hunt.phase, phase_at = {[hunt.phase] = takt(game.tick)},
    phases = {}, requests = {}, dives = {}, detours = {}, rock = 0, samples = 0, modes = {}, states = {}, steps = {},
    sprint = {n = 0, walked = 0, want = 0, runs = 0}, hold = {ticks = 0, path = 0, runs = 0}, detour_n = 0, sprint_n = 0
  }
end

-- P der Jagd (hunt.zone: Zielmitte, solange sie zählt, sonst last_pos, Plan 4.12), ersatzweise Zielmitte oder last_pos. Ein
-- getragener Ernter steht anderswo (Schritt 7, Prüfstand 2026-10-27: Abstand 37680); P bleibt, wo der Wurm hinfährt.
local function target_point(hunt)
  if hunt.zone then return copy_pos(hunt.zone) end
  local target = hunt.target
  if valid(target) then return copy_pos(target.position) end
  return copy_pos(hunt.last_pos)
end

-- Weg von Knoten 1 über die letzten n Proben (Kacheln) und deren Zahl.
local function recent_path(w, n)
  local list = w.steps
  local k = math.min(n, #list)
  local sum = 0
  for i = #list - k + 1, #list do sum = sum + list[i] end
  return sum, k
end

local function heading_of(nodes)
  local back = nodes[3] or nodes[#nodes]
  return unit_vector(nodes[1].x - back.x, nodes[1].y - back.y)
end

local function sample(run, tb, d, w, hunt, worm)
  local unit = worm.unit
  local nodes = unit.get_body_nodes()
  local head = nodes[1]
  local tick = game.tick
  local surface = unit.surface
  local phase = hunt.phase
  w.samples = w.samples + 1
  local rec = {tick = tick, head = {x = head.x, y = head.y}, heading = heading_of(nodes), phase = phase}
  if terrain.natural_tile_name(surface, head.x, head.y) == ROCK then
    w.rock = w.rock + 1
    w.rock_first = w.rock_first or {tick = tick, position = rec.head}
  end
  local mode = tb.enum_name(defines.segmented_unit_activity_mode, read(function() return unit.activity_mode end))
  local key = tostring(phase) .. "/" .. mode
  w.modes[key] = (w.modes[key] or 0) + 1
  if mode == "minimal" then w.minimal = (w.minimal or 0) + 1 end
  local ai = read(function() return unit.get_ai_state() end)
  local state = ai and tb.enum_name(defines.segmented_unit_ai_state, ai.type) or "?"
  rec.state = state
  w.states[state] = (w.states[state] or 0) + 1
  local P = target_point(hunt)
  rec.d = dist(head, P)
  -- Tempo nur über SPEED_SAMPLES Proben (1 s, Fehler unter 1 Kachel/s); kleinstes im Angriff über volle Fenster.
  local v
  local holding = worm.hold_since ~= nil
  if w.last_head then
    local step = dist(head, w.last_head)
    rec.step = step
    table.insert(w.steps, step)
    if #w.steps > SPEED_SAMPLES then table.remove(w.steps, 1) end
    local sum, k = recent_path(w, SPEED_SAMPLES)
    v = sum * 6 / k
    rec.v = v
    if phase == "angriff" and k == SPEED_SAMPLES and (not w.v_attack_min or v < w.v_attack_min) then w.v_attack_min = v end
    -- Sprint [W3]: Weg von Knoten 1 gegen den geschriebenen Weg; je Lauf ohne Unterbrechung höchstens 1 Kachel Rasterfehler.
    local sp = w.sprint
    if w.sprint_pending then
      if not sp.open then sp.runs = sp.runs + 1 end
      sp.open = true
      sp.n = sp.n + 1
      sp.walked = sp.walked + step
      sp.want = sp.want + w.sprint_pending / 6
    else
      sp.open = false
    end
    -- Halten [W2]: Weg von Knoten 1 vom ersten bis zum letzten Takt jedes Haltens (Fehler je Halten unter 1 Kachel).
    if holding and w.was_holding then
      w.hold.ticks = w.hold.ticks + 10
      w.hold.last = rec.head
    end
  end
  if holding and not w.was_holding then
    w.hold.runs = w.hold.runs + 1
    w.hold.start, w.hold.last = rec.head, rec.head
  elseif not holding and w.was_holding and w.hold.start then
    w.hold.path = w.hold.path + dist(w.hold.start, w.hold.last)
    w.hold.start = nil
  end
  w.was_holding = holding
  -- Tempo, das der Sprint-Takt seit der letzten Probe geschrieben hat (Kacheln/s), sonst false.
  w.sprint_pending = worm.sprint > w.sprint_n and (worm.last_v or 0)
  w.sprint_n = worm.sprint
  if not w.v1 and w.spawn_tick and tick >= w.spawn_tick + 60 then w.v1 = read(function() return unit.speed end) end
  if w.v1 and not w.v1_tps then w.v1_tps = w.v1 * 60 end
  -- W1 aus Schritt 2 gleich bei der Messung merken: Schritt 3 (Befehlsjagd, früheres eta) wertet vor Schritt 2 aus und
  -- fände d.w1 sonst nie gesetzt (Nachprüfung 0.8.0).
  if w.number == 2 and w.v1_tps and d.w1 == nil then d.w1 = w.v1_tps >= V_W1 end
  -- Ankunft von Knoten 1 in Reichweite (bis 1 Kachel nach dem wahren Kopf, W18).
  if not w.arrived and rec.d <= w.R then w.arrived = tick end
  if tick % 60 == 5 then
    tb.trace(run, string.format("%d) %s: %s, Phase %s, Kopf %s, Abstand %s, Tempo 1 s %s (Spur %s), Ziel %s", w.number, rel(tick, w.eta), state,
      tostring(phase), pos_text(tb, head), tb.num(rec.d), tb.num(v), tb.num(worm.v_head), pos_text(tb, ai and ai.destination)))
  end
  w.last_head = rec.head
  w.last_heading = rec.heading
  local hook = SAMPLE[w.number]
  if hook then hook(run, tb, d, d["s" .. w.number], w, hunt, worm, rec) end
end

local function watch_tick(run, tb, d, w)
  if w.ended then return end
  local hunt = w.hunt
  local tick = game.tick
  if storage.hunts.list[w.id] ~= hunt then
    w.ended = tick
    w.entry = log_entry(w.id)
    if w.un and not w.worm_gone then w.worm_gone = tick end
    return
  end
  local phase = hunt.phase
  if phase ~= w.phase then
    w.phase = phase
    if not w.phase_at[phase] then w.phase_at[phase] = takt(tick) end
    table.insert(w.phases, tostring(phase) .. " " .. rel(takt(tick), w.eta))
    if phase == "angriff" and not w.attack then
      local head = sandworm_lib.head_of(hunt)
      local worm = hunt.worm
      w.attack = {tick = takt(tick), d = head and dist(head, target_point(hunt)) or nil,
                  open = worm and worm.wp <= #worm.route or false}
    end
  end
  if hunt.no_worm ~= w.no_worm then
    w.no_worm = hunt.no_worm
    if hunt.no_worm == "abgetaucht" and not w.abgetaucht then w.abgetaucht = tick end
  end
  if hunt.dive ~= w.dive then
    w.dive = hunt.dive
    if hunt.dive then table.insert(w.dives, {why = hunt.dive, tick = tick}) end
  end
  if hunt.state == "searching" and not w.searching then
    w.searching = tick
    local head = hunt.worm and hunt.worm.head or w.last_head
    if head then
      w.miss_head = copy_pos(head)
      w.miss_eruptions = #game.get_surface(hunt.surface_index).find_entities_filtered{name = ERUPTION, position = head, radius = 3}
    end
  end
  local path = hunt.path
  if path and path.id and not w.requests[path.id] then
    w.requests[path.id] = {sent = path.sent, box = path.box, kind = path.kind}
  end
  local worm = hunt.worm
  if worm and worm.un ~= w.un then
    w.un = worm.un
    w.unit = worm.unit
    w.spawn_seen = tick
    w.spawn_tick = hunt.spawn_tick
    w.worms = (w.worms or 0) + 1
    w.nodes0 = valid(worm.unit) and worm.unit.get_body_nodes() or nil
    w.route0 = #(worm.route or {})
  end
  if w.un and not worm and not w.worm_gone then w.worm_gone = tick end
  if worm and worm.detours > w.detour_n then
    w.detour_n = worm.detours
    local nodes = valid(worm.unit) and worm.unit.get_body_nodes()
    local head = nodes and nodes[1]
    local detour = worm.detour
    table.insert(w.detours, {tick = tick, head = head and copy_pos(head), heading = nodes and heading_of(nodes),
                             d = head and dist(head, target_point(hunt)), point = detour and copy_pos(detour),
                             length = detour and head and dist(head, detour), reached = detour and detour.reached})
  end
  if tick % 10 == 5 and worm and valid(worm.unit) then sample(run, tb, d, w, hunt, worm) end
end

-- Weg beim Halten samt einem offenen Halten (Kacheln).
local function hold_path(w)
  local hold = w.hold
  local path = hold.path
  if hold.start and hold.last then path = path + dist(hold.start, hold.last) end
  return path
end

-- Allgemeine Prüfungen je Schritt mit Wurm (Plan 6): Fels, Abtauchen, Kopfbox, Erzeugungen, Aktivität, Halten, Feld leer.
-- opts.dives: erlaubte Gründe des Abtauchens vor dem Biss. Schreibt MESSUNG- und INFO-Zeilen, FEHLER in s.failed.
local function general(run, tb, d, s, w, opts)
  opts = opts or {}
  local failed = s.failed
  local n = w.number
  local e = w.entry
  if w.rock > 0 then
    check(failed, false, string.format("Kopfmitte %d× auf Fels (zuerst %s bei %s)", w.rock, rel(w.rock_first.tick, w.eta),
      pos_text(tb, w.rock_first.position)))
  end
  local allowed = opts.dives or {}
  local reasons = {}
  for _, rec in ipairs(w.dives) do table.insert(reasons, rec.why .. " " .. rel(rec.tick, w.eta)) end
  if e and e.dive then table.insert(reasons, "Protokoll " .. e.dive) end
  for _, rec in ipairs(w.dives) do
    if rec.why == "fels" then
      check(failed, false, "abgetaucht wegen Fels " .. rel(rec.tick, w.eta))
    elseif (rec.why == "stillstand" or rec.why == "kein-weg") and not allowed[rec.why] then
      check(failed, false, "abgetaucht (" .. rec.why .. ") " .. rel(rec.tick, w.eta))
    end
  end
  if e and (e.dive == "fels" or ((e.dive == "stillstand" or e.dive == "kein-weg") and not allowed[e.dive])) and #w.dives == 0 then
    check(failed, false, "Protokoll: abgetaucht (" .. e.dive .. ")")
  end
  if (w.abgetaucht and w.abgetaucht < w.eta) or (e and e.no_worm == "abgetaucht" and not w.abgetaucht) then
    check(failed, false, "no_worm abgetaucht vor eta")
  end
  if e then
    local share = (e.samples or 0) > 0 and (e.rock_box or 0) / e.samples or 0
    tb.log(run, "MESSUNG", string.format("%d) Kopfbox auf Fels %s von %s Takten (%s %%), Abtauchen: %s", n, tostring(e.rock_box),
      tostring(e.samples), tb.num(100 * share), #reasons > 0 and table.concat(reasons, ", ") or "–"))
    if share > ROCK_BOX_INFO then tb.log(run, "INFO", n .. ") Kopfbox berührt in über 5 % der Takte Fels") end
    if w.un and e.spawns ~= 1 then tb.log(run, "INFO", n .. ") " .. tostring(e.spawns) .. " Erzeugungen statt 1 [W14]") end
  else
    check(failed, false, "kein Protokolleintrag der Jagd " .. w.id)
  end
  if w.un then
    local modes = {}
    for key, count in pairs(w.modes) do table.insert(modes, key .. " " .. count) end
    table.sort(modes)
    local states = {}
    for key, count in pairs(w.states) do table.insert(states, key .. " " .. count) end
    table.sort(states)
    tb.log(run, "MESSUNG", n .. ") activity_mode je Phase: " .. (#modes > 0 and table.concat(modes, ", ") or "–") .. "; Zustände: "
      .. (#states > 0 and table.concat(states, ", ") or "–"))
    if (w.minimal or 0) > 0 then tb.log(run, "INFO", n .. ") activity_mode minimal in " .. w.minimal .. " Takten [W13]") end
    if w.hold.ticks > 0 then
      local hold = w.hold
      local path = hold_path(w)
      local limit = HOLD_BASE + HOLD_PER_S * hold.ticks / 60
      tb.log(run, "MESSUNG", string.format("%d) Halten %s s in %d Läufen, Weg von Knoten 1 dabei %s Kacheln (Raster ±%d, Grenze %s)", n,
        tb.num(hold.ticks / 60), hold.runs, tb.num(path, 2), hold.runs * NODE_STEP, tb.num(limit, 2)))
      -- Kriechen nur, wenn es auch mit dem Rasterfehler über der Grenze liegt (ein Sprung beim Anhalten ist keiner).
      if path - hold.runs * NODE_STEP > limit then tb.log(run, "INFO", n .. ") Kopf kriecht beim Halten [W2]") end
    end
  end
  if w.box then
    local left = sandworms_in(tb.surface(), w.box)
    check(failed, left == 0, left .. " arrakis-sandworm-* nach dem Ende im Feld")
  end
end

-- Bissverzug, Ersatzbiss, Abstand (Plan 6 „Bissverzug“ = bite_tick − eta_tick).
local function bite_checks(run, tb, s, w, opts)
  opts = opts or {}
  local failed = s.failed
  local e = w.entry or {}
  local delay = e.bite_tick and (e.bite_tick - e.eta_tick) or nil
  check(failed, e.outcome == "bitten", "Ergebnis " .. tostring(e.outcome) .. " statt bitten")
  check(failed, delay and delay >= 0 and delay <= BITE_WINDOW, "Bissverzug " .. tostring(delay) .. " statt 0 bis 180")
  if delay and delay > 0 then tb.log(run, "INFO", w.number .. ") Bissverzug " .. delay .. " Ticks") end
  if not opts.ersatz_ok then check(failed, e.ersatz ~= true, "Ersatzbiss") end
  -- Ein erlaubter Ersatzbiss kommt per Definition außer Reichweite (Plan 4.9 Biss-Fenster Fall 4); sonst würde Schritt 3
  -- daraus doch FEHLER statt INFO (Nachprüfung 0.8.0).
  if opts.reach and not (opts.ersatz_ok and e.ersatz) then
    check(failed, e.bite_dist and e.bite_dist <= opts.reach + R_TOLERANCE,
      "Abstand beim Biss " .. tb.num(e.bite_dist, 2) .. " statt ≤ " .. tb.num(opts.reach, 2))
  end
  return delay
end

-- Sprint [W3] über alle Sprint-Proben: Weg von Knoten 1 gegen den geschriebenen Weg. Gibt den Anteil und seine Grenzen
-- (je Lauf höchstens NODE_STEP Rasterfehler) zurück, ohne Sprint nil.
local function sprint_share(w)
  local sp = w.sprint
  if sp.n == 0 or sp.want <= 0 then return nil end
  local err = sp.runs * NODE_STEP
  return sp.walked / sp.want, math.max(0, sp.walked - err) / sp.want, (sp.walked + err) / sp.want
end

-- Mittleres Sprinttempo (Kacheln/s, Weg von Knoten 1 über alle Sprint-Proben) oder nil.
local function sprint_mean(w)
  local sp = w.sprint
  if sp.n == 0 then return nil end
  return sp.walked * 6 / sp.n
end

-- W3 hält (true), hält nicht (false) oder ist im Raster nicht zu entscheiden (nil).
local function sprint_holds(w)
  local _, lo, hi = sprint_share(w)
  if not lo then return nil end
  if lo >= SPRINT_SHARE then return true end
  if hi < SPRINT_SHARE then return false end
  return nil
end

local function sprint_text(tb, w)
  local e = w.entry or {}
  local share, lo, hi = sprint_share(w)
  local sp = w.sprint
  return string.format("Sprint-Takte %s, mittleres Sprinttempo %s über %d Proben in %d Läufen, Weg %s %% des geschriebenen (Raster %s bis %s %%), Ersatzstufe %s",
    tostring(e.sprint), tb.num(sprint_mean(w), 2), sp.n, sp.runs, tb.num(share and 100 * share, 1), tb.num(lo and 100 * lo, 1),
    tb.num(hi and 100 * hi, 1), tostring(e.boost))
end

local function no_corpse(run, tb, s, w)
  local surface = tb.surface()
  local rocks = surface.count_entities_filtered{area = w.box, type = "simple-entity"}
  local tungsten = 0
  for _, item in pairs(surface.find_entities_filtered{area = w.box, name = "item-on-ground"}) do
    local stack = read(function() return item.stack end)
    if stack and read(function() return stack.valid_for_read and stack.name end) == "tungsten-ore" then tungsten = tungsten + 1 end
  end
  check(s.failed, rocks == 0, rocks .. " simple-entity im Feld")
  check(s.failed, tungsten == 0, tungsten .. " Bodenstapel mit Wolframerz im Feld")
end

-- Reguläre Jagden der Schritte 2, 10, 12 (Plan 6): Wurmzeichen in aufeinanderfolgenden 60-Tick-Takten, je Schritt
-- set_heat 999 einen Takt nach dem vorigen, nur solange höchstens 2 reguläre Jagden laufen.
local function regular_turn(run, tb, d, number)
  local reg = d.reg
  if reg.queue[1] ~= number then return false end
  if game.tick % 60 ~= 30 then return false end
  if reg.last and game.tick < reg.last + 60 then return false end
  local busy = regular_count()
  if busy >= 3 then
    if not reg.blocked then
      reg.blocked = true
      tb.log(run, "INFO", number .. ") Schon " .. busy .. " reguläre Jagden: Schritt " .. number .. " wartet, bis eine frei wird")
    end
    return false
  end
  table.remove(reg.queue, 1)
  reg.last = game.tick
  return true
end

local function set_phase(number)
  return function(run, tb, d, s)
    if not regular_turn(run, tb, d, number) then return "poll" end
    heat_chunk(tb.surface(), s.c, 999)
    s.set_tick = game.tick
    return 1
  end
end

-- Wurmzeichen nach set_heat 999 (im nächsten Takt); legt die Beobachtung an.
local function sign_phase(number, title)
  return function(run, tb, d, s)
    local hunt = worms_lib.hunt_of(s.car)
    if not hunt then
      if game.tick > s.set_tick + 100 then return fail(run, tb, number, title .. ": kein Wurmzeichen nach set_heat 999 (" .. car_state(s.car) .. ")") end
      return "poll"
    end
    s.hunt = hunt
    s.watch = watch_new(d, number, hunt)
    d.active[number] = true
    check(s.failed, hunt.warn_tick == s.set_tick + 30, "Wurmzeichen bei Tick " .. hunt.warn_tick .. " statt " .. (s.set_tick + 30))
    check(s.failed, not hunt.debug and not hunt.teaching and hunt.eta_tick - hunt.warn_tick == WARN_TICKS,
      "Countdown " .. (hunt.eta_tick - hunt.warn_tick) .. (hunt.teaching and " (Lehrjagd)" or "") .. " statt 3600")
    return 1
  end
end

-- Phase: warten, bis alle Ernter in s.cars aufgebaut sind (höchstens 600 Ticks), dann bis zur Takt-Mitte.
local function wait_deployed(number)
  return function(run, tb, d, s)
    local states, all = {}, true
    for _, car in ipairs(s.cars) do
      local state = car_state(car)
      if state ~= "deployed" then all = false end
      table.insert(states, state)
    end
    if all then return to_mid() end
    s.deploy_wait = s.deploy_wait or game.tick
    if game.tick - s.deploy_wait > 600 then return fail(run, tb, number, "Ernter bauen nicht auf: " .. table.concat(states, ", ")) end
    return "poll"
  end
end

-- Phase: bis die Jagd vorbei ist (und 2 Ticks danach, damit Ereignisse und Protokoll da sind).
local function wait_end(run, tb, d, s)
  local w = s.watch
  if not w.ended then return "poll" end
  if game.tick < w.ended + 2 then return "poll" end
  return 1
end

-- Befehlsjagd auf entity mit Haken; legt die Beobachtung an.
local function debug_hunt(run, tb, d, s, number, entity, opts)
  local hunt, reason = worms_lib.start_hunt(entity, opts)
  if not hunt then return nil, reason end
  s.hunt = hunt
  s.watch = watch_new(d, number, hunt)
  d.active[number] = true
  return hunt
end

-- T21 ------------------------------------------------------------------------------------------------

local steps = {}

local function field(d, number)
  return d.fields[number].center
end

-- Schritt 1: Prototypen und storage.
function steps.s1_check(run, tb, d, s)
  local failed = s.failed
  local head = read(function() return prototypes.entity[WORM] end)
  check(failed, head ~= nil and head.type == "segmented-unit", WORM .. " fehlt oder Typ " .. tostring(head and head.type))
  local missing = {}
  for _, name in ipairs(SMOKES) do
    if not read(function() return prototypes.trivial_smoke[name] end) then table.insert(missing, name) end
  end
  check(failed, #missing == 0, "Rauch fehlt: " .. table.concat(missing, ", "))
  check(failed, read(function() return prototypes.entity[DIVE] end) ~= nil, DIVE .. " fehlt")
  local probe = spawn_unit(run, tb, d, WORM, at(field(d, 12), 0, -100), 0, worm_force())
  local max_nodes, nodes
  if probe then
    max_nodes = read(function() return probe.max_body_nodes end)
    nodes = #probe.get_body_nodes()
    probe.destroy{}
  end
  check(failed, max_nodes == NODES, "Probewurm: max_body_nodes " .. tostring(max_nodes) .. " statt 22")
  check(failed, storage.schema == 4, "storage.schema " .. tostring(storage.schema) .. " statt 4")
  check(failed, type(storage.path_requests) == "table", "storage.path_requests fehlt")
  check(failed, type(storage.hunts.log) == "table", "storage.hunts.log fehlt")
  check(failed, type(storage.hunts.worm_off) == "table", "storage.hunts.worm_off fehlt")
  check(failed, type(storage.hunts.spawn_dir) == "table", "storage.hunts.spawn_dir fehlt")
  local stats = worms_lib.stats_of(d.force)
  check(failed, stats.killed == 0, "stats_of(" .. T21_FORCE .. ").killed " .. tostring(stats.killed) .. " statt 0")
  return verdict(run, tb, 1, "Prototypen und storage", failed, string.format("%s %s, Rauch %d/4, Probewurm %s/%s Knoten, Schema %s, killed %s",
    WORM, tostring(head and head.type), 4 - #missing, tostring(nodes), tostring(max_nodes), tostring(storage.schema), tostring(stats.killed)))
end

-- Schritt 2: Zeitlinie 60 s, regulär (Feld 1) [W1, W2, W6, W7, W9, W13].
function steps.s2_build(run, tb, d, s)
  local c = field(d, 1)
  s.c = c
  s.car = new_harvester(run, tb, d, s, c, {coal = 20, field = 1000})
  if not s.car then return fail(run, tb, 2, "Aufbau ging nicht (Einzelheiten in der Datei)") end
  s.car_un = s.car.unit_number
  s.cars = {s.car}
  s.chests = {}
  for _, offset in ipairs({{0, -3}, {3, 0}, {0, 3}, {-3, 0}}) do
    local chest = make(run, tb, s, {name = CHEST, position = at(c, offset[1], offset[2]), force = d.force})
    if chest then table.insert(s.chests, {entity = chest, un = chest.unit_number}) end
  end
  if #s.chests < 4 then return fail(run, tb, 2, "Kisten ließen sich nicht bauen") end
  local ok, reason = deploy(s.car)
  if not ok then return fail(run, tb, 2, "Aufbauen ging nicht: " .. tostring(reason)) end
  return 1
end

-- Raster der Körperknoten [W18] und segments[1] [W19], nur MESSUNG: Weg von Knoten 1 je Probe nach ganzen Kacheln gezählt;
-- Lage von segments[1].position gegen Knoten 1 längs der Kopfrichtung und ob sie sich stetig bewegt (dann wäre sie der wahre
-- Kopf, den die Laufzeit noch nicht benutzt).
SAMPLE[2] = function(run, tb, d, s, w, hunt, worm, rec)
  local r = s.raster or {n = 0, counts = {}, off = 0}
  s.raster = r
  if rec.step then
    r.n = r.n + 1
    local k = math.floor(rec.step + 0.5)
    if math.abs(rec.step - k) > 0.1 then
      r.off = r.off + 1
    else
      r.counts[k] = (r.counts[k] or 0) + 1
    end
  end
  local g = s.segment or {n = 0, ahead = 0, side = 0, steps = 0, off = 0, missing = 0}
  s.segment = g
  local seg = read(function()
    local first = worm.unit.segments[1]
    return first and first.position and copy_pos(first.position)
  end)
  if not (seg and rec.heading) then
    g.missing = g.missing + 1
    return
  end
  local dx, dy = seg.x - rec.head.x, seg.y - rec.head.y
  local ahead = dx * rec.heading.x + dy * rec.heading.y
  g.n = g.n + 1
  g.ahead = g.ahead + ahead
  g.side = math.max(g.side, math.abs(dy * rec.heading.x - dx * rec.heading.y))
  g.min = math.min(g.min or ahead, ahead)
  g.max = math.max(g.max or ahead, ahead)
  if g.last then
    local step = dist(seg, g.last)
    g.steps = g.steps + 1
    if math.abs(step - math.floor(step + 0.5)) > 0.1 then g.off = g.off + 1 end
  end
  g.last = seg
end

local function raster_text(run, tb, s)
  local r = s.raster
  if r and r.n > 0 then
    local keys, parts = {}, {}
    for k in pairs(r.counts) do table.insert(keys, k) end
    table.sort(keys)
    for _, k in ipairs(keys) do table.insert(parts, k .. " × " .. r.counts[k]) end
    tb.log(run, "MESSUNG", string.format("2) Raster [W18]: Weg von Knoten 1 je 10 Ticks in ganzen Kacheln %s, nicht ganzzahlig %d von %d Proben",
      #parts > 0 and table.concat(parts, ", ") or "–", r.off, r.n))
    if r.off > 0 then tb.log(run, "INFO", "2) Knoten 1 springt nicht nur um ganze Kacheln [W18]") end
  end
  local g = s.segment
  if g and g.n > 0 then
    tb.log(run, "MESSUNG", string.format("2) segments[1] [W19]: vor Knoten 1 längs der Kopfrichtung im Mittel %s (%s bis %s), seitlich höchstens %s Kacheln; "
      .. "Weg je 10 Ticks nicht ganzzahlig in %d von %d Proben, ohne Lage %d", tb.num(g.ahead / g.n, 2), tb.num(g.min, 2), tb.num(g.max, 2),
      tb.num(g.side, 2), g.off, g.steps, g.missing))
  elseif g then
    tb.log(run, "MESSUNG", "2) segments[1] [W19]: keine Lage in " .. g.missing .. " Proben")
  end
end

function steps.s2_eval(run, tb, d, s)
  local w = s.watch
  local failed = s.failed
  local e = w.entry or {}
  local hunt = s.hunt
  local plan = hunt.plan or {}
  local chosen = plan.chosen or {}
  check(failed, w.first_phase == "warten", "erste Phase " .. tostring(w.first_phase) .. " statt warten")
  check(failed, w.phase_at.routing == w.eta - PLAN_LEAD, "routing " .. rel(w.phase_at.routing, w.eta) .. " statt eta − 3230")
  check(failed, w.spawn_tick == w.eta - SPAWN_LEAD and w.spawn_seen and takt(w.spawn_seen) == w.eta - SPAWN_LEAD,
    "Wurm " .. rel(w.spawn_tick, w.eta) .. " statt eta − 2930")
  check(failed, plan.paths == 0 and #(chosen.route or {}) == 0, "Weg statt gerader Linie (paths " .. tostring(plan.paths) .. ")")
  check(failed, e.k == 2, "Richtung k " .. tostring(e.k) .. " statt 2")
  local nodes = w.nodes0 or {}
  check(failed, #nodes == NODES, #nodes .. " Knoten statt 22")
  local surface = tb.surface()
  local bad = 0
  for i = 1, #nodes, BODY_STEP do
    if not sand_at(surface, nodes[i].x, nodes[i].y) then bad = bad + 1 end
  end
  check(failed, bad == 0, bad .. " Prüfknoten nicht auf Sand")
  local away = #nodes > 0 and (dist(nodes[#nodes], s.c) - dist(nodes[1], s.c)) or nil
  check(failed, away and away >= BODY_AWAY, "Körper: letzter Knoten " .. tb.num(away) .. " Kacheln weiter weg als der Kopf statt ≥ 18")
  check(failed, w.v1_tps and w.v1_tps >= V_W1, "Tempo 1 s nach dem Spawn " .. tb.num(w.v1_tps, 2) .. " statt ≥ 3,3 [W1]")
  d.w1 = w.v1_tps and w.v1_tps >= V_W1
  check(failed, w.attack and w.attack.d and w.attack.d <= ATTACK_RANGE, "Angriff bei Abstand " .. tb.num(w.attack and w.attack.d) .. " statt ≤ 40")
  local early = deaths_before(d, w.box, w.eta)
  check(failed, #early == 0, "vor eta gestorben: " .. table.concat(early, ", "))
  local delay = bite_checks(run, tb, s, w, {reach = R_HARVESTER})
  local bite_tick = e.bite_tick
  local dead = 0
  local car_death = died(d, s.car_un)
  if car_death and car_death.tick == bite_tick then dead = dead + 1 end
  for _, chest in ipairs(s.chests) do
    local record = died(d, chest.un)
    if record and record.tick == bite_tick then dead = dead + 1 end
  end
  check(failed, dead == 5, "im Biss-Takt " .. dead .. " von 5 tot (H1 und vier Kisten)")
  local ev = unit_events(d, w.un)
  check(failed, #ev.died == 0, #ev.died .. " segmented_unit_died")
  check(failed, dived_after(ev, w.un, bite_tick), #ev.destroyed .. " segmented_unit_destroyed (" ..
    tostring(ev.destroyed[1] and rel(ev.destroyed[1], w.eta)) .. ") statt eines vom Biss-Takt bis zum Ende des Abtauchens")
  check(failed, w.worm_gone and takt(w.worm_gone) == bite_tick, "Wurm nicht im Biss-Takt weg (" .. rel(w.worm_gone, w.eta) .. ")")
  no_corpse(run, tb, s, w)
  check(failed, e.phase == "angriff" and e.outcome == "bitten", "Protokoll: Phase " .. tostring(e.phase) .. ", Ergebnis " .. tostring(e.outcome))
  general(run, tb, d, s, w)
  tb.log(run, "MESSUNG", string.format("2) Ankunft von Knoten 1 in Reichweite %s, kleinstes Tempo im Angriff %s (Weg je 1 s, Raster ±1), Phasen: %s",
    rel(w.arrived, w.eta), tb.num(w.v_attack_min, 2), table.concat(w.phases, ", ")))
  raster_text(run, tb, s)
  return verdict(run, tb, 2, "Zeitlinie 60 s, regulär", failed, string.format("routing %s, Wurm %s, Tempo nach 1 s %s, Angriff bei %s, Biss %s (%s), Abstand %s",
    rel(w.phase_at.routing, w.eta), rel(w.spawn_tick, w.eta), tb.num(w.v1_tps, 2), tb.num(w.attack and w.attack.d), rel(bite_tick, w.eta),
    tostring(delay), tb.num(e.bite_dist, 2)))
end

-- Schritt 3: Felsinsel (Feld 3) [W3].
function steps.s3_build(run, tb, d, s)
  local c = field(d, 3)
  s.c = c
  local surface = tb.surface()
  local n, m = math.floor(c.x), math.floor(c.y)
  s.island = {x1 = n - 100, x2 = n - 61, y1 = m - 20, y2 = m + 19}
  tiles(surface, s.island.x1, s.island.y1, s.island.x2, s.island.y2, ROCK)
  local chest = make(run, tb, s, {name = CHEST, position = c, force = d.force})
  if not chest then return fail(run, tb, 3, "Kiste K3 ließ sich nicht bauen") end
  s.chest = chest
  local hunt, reason = debug_hunt(run, tb, d, s, 3, chest, {seconds = 60, debug = true,
    spawn = {position = at(c, -160, 0), direction = defines.direction.east}})
  if not hunt then return fail(run, tb, 3, "Befehlsjagd ging nicht: " .. tostring(reason)) end
  return 1
end

SAMPLE[3] = function(run, tb, d, s, w, hunt, worm, rec)
  local first = w.detours[1]
  if first and rec.tick <= first.tick + TURN_WINDOW and rec.heading and first.heading then
    local a = angle_between(rec.heading, first.heading)
    if not w.turn_max or a > w.turn_max then w.turn_max = a end
  end
end

function steps.s3_eval(run, tb, d, s)
  local w = s.watch
  local failed = s.failed
  local e = w.entry or {}
  local first = w.detours[1]
  local edge = first and first.head and rect_distance(s.island, first.head)
  check(failed, first ~= nil, "kein Umweg vor der Insel")
  check(failed, edge and edge >= DETOUR_EDGE, "erster Umweg " .. tb.num(edge) .. " Kacheln vor dem Inselrand statt ≥ 2")
  check(failed, w.turn_max and w.turn_max >= TURN_MIN, "Richtungsänderung " .. tb.num(w.turn_max) .. "° binnen 180 Ticks statt ≥ 20°")
  bite_checks(run, tb, s, w, {ersatz_ok = true, reach = w.R})
  local w3 = sprint_holds(w)
  if e.ersatz then
    if d.w1 and w3 then
      check(failed, false, "Ersatzbiss, obwohl W1 und W3 halten")
    else
      tb.log(run, "INFO", "3) Ersatzbiss (W1 " .. tostring(d.w1) .. ", W3 " .. (w3 == nil and "im Raster offen" or tostring(w3))
        .. "): Umweg und Start ohne Schwung zusammen über 7,4 s Luft")
    end
  end
  general(run, tb, d, s, w)
  local straight = (160 - w.R) / 3.5 * 60
  local loss = w.arrived and w.spawn_tick and (w.arrived - w.spawn_tick - straight) or nil
  local angles = {}
  for _, detour in ipairs(w.detours) do
    table.insert(angles, tb.num(detour.length) .. " Kacheln bei Abstand " .. tb.num(detour.d))
  end
  tb.log(run, "MESSUNG", string.format("3) Umwege %d (%s), größte Drehung %s°, Zeitverlust gegen die gerade Linie %s Ticks (Ankunft von Knoten 1 "
    .. "in Reichweite, bis 1 Kachel Fahrt nach dem wahren Kopf), %s",
    #w.detours, table.concat(angles, "; "), tb.num(w.turn_max), tb.num(loss, 0), sprint_text(tb, w)))
  return verdict(run, tb, 3, "Felsinsel [W3]", failed, string.format("erster Umweg %s Kacheln vor dem Rand, Drehung %s°, Biss %s, Ersatzbiss %s",
    tb.num(edge), tb.num(w.turn_max), rel(e.bite_tick, w.eta), tostring(e.ersatz)))
end

-- Schritt 4: Sandtasche mit Knick (Feld 4) [W4, W17]. Fels 140 × 140, Tasche 30 × 30, Gang 16 breit 30 nach Osten, dann
-- nach Norden bis zum Rand.
function steps.s4_build(run, tb, d, s)
  local c = field(d, 4)
  s.c = c
  local surface = tb.surface()
  local n, m = math.floor(c.x), math.floor(c.y)
  tiles(surface, n - 70, m - 70, n + 69, m + 69, ROCK)
  tiles(surface, n - 15, m - 15, n + 14, m + 14, "sand-1")
  tiles(surface, n + 15, m - 8, n + 44, m + 7, "sand-1")
  tiles(surface, n + 29, m - 70, n + 44, m - 8, "sand-1")
  s.car = new_harvester(run, tb, d, s, c, {coal = 10})
  if not s.car then return fail(run, tb, 4, "Ernter H4 ließ sich nicht bauen") end
  s.car_un = s.car.unit_number
  local hunt, reason = debug_hunt(run, tb, d, s, 4, s.car, {seconds = 60, debug = true, spawn_dir = 0})
  if not hunt then return fail(run, tb, 4, "Befehlsjagd ging nicht: " .. tostring(reason)) end
  return 1
end

function steps.s4_eval(run, tb, d, s)
  local w = s.watch
  local failed = s.failed
  local e = w.entry or {}
  local hunt = s.hunt
  local plan = hunt.plan or {}
  local chosen = plan.chosen or {}
  local route = chosen.route or {}
  check(failed, (plan.checked or 0) == CANDIDATES and #(plan.list or {}) == CANDIDATES,
    "Kandidaten geprüft " .. tostring(plan.checked) .. " von " .. #(plan.list or {}) .. " statt 48")
  check(failed, plan.paths == 1 or plan.paths == 2, "Anfragen " .. tostring(plan.paths) .. " statt 1 oder 2")
  check(failed, #route > 0 and chosen.box == 3.5, "Weg mit " .. #route .. " Wegpunkten, Box " .. tostring(chosen.box) .. " statt Weg mit Box ±3,5")
  local surface = tb.surface()
  local cut = 0
  local a = chosen.position
  for _, p in ipairs(route) do
    if a and not line_sand(surface, a, p, 2, 1.5) then cut = cut + 1 end
    a = p
  end
  check(failed, cut == 0, cut .. " Sehnen der Route schneiden Fels")
  check(failed, w.attack and not w.attack.open, "Angriff vor dem letzten Wegpunkt")
  bite_checks(run, tb, s, w, {reach = R_HARVESTER})
  general(run, tb, d, s, w)
  local waits, later, before = {}, 0, {}
  for id, req in pairs(w.requests) do
    local answer = d.path_events[id]
    if answer then
      table.insert(waits, tostring(answer.tick - req.sent))
      if answer.later then later = later + 1 end
      if answer.n then table.insert(before, tostring(answer.n)) end
    end
  end
  local detours = {}
  for _, detour in ipairs(w.detours) do table.insert(detours, tb.num(detour.length)) end
  tb.log(run, "MESSUNG", string.format("4) Wartezeit der Antworten %s Ticks, try_again_later %d, Box %s, Weglänge %s, Wegpunkte %s → %d, Umwege %d (%s), "
    .. "Kopfbox auf Fels %s, Spawn %s", #waits > 0 and table.concat(waits, ", ") or "–", later, tostring(chosen.box), tb.num(chosen.length),
    #before > 0 and table.concat(before, "/") or "–", #route, #w.detours, table.concat(detours, ", "), tostring(e.rock_box), rel(e.spawn_tick, w.eta)))
  return verdict(run, tb, 4, "Sandtasche mit Knick [W4, W17]", failed, string.format("%s Kandidaten, %s Anfragen, %d Wegpunkte, Box %s, Biss %s, Abstand %s",
    tostring(plan.checked), tostring(plan.paths), #route, tostring(chosen.box), rel(e.bite_tick, w.eta), tb.num(e.bite_dist, 2)))
end

-- Schritt 5: Ernter 10 Kacheln vor Fels (Feld 5) [W2].
function steps.s5_build(run, tb, d, s)
  local c = field(d, 5)
  s.c = c
  local surface = tb.surface()
  local n, m = math.floor(c.x), math.floor(c.y)
  s.rock_x = n + 10
  tiles(surface, n + 10, m - FIELD_HALF, n + FIELD_HALF - 1, m + FIELD_HALF - 1, ROCK)
  s.car = new_harvester(run, tb, d, s, c, {coal = 20, field = 1000})
  if not s.car then return fail(run, tb, 5, "Ernter H5 ließ sich nicht bauen") end
  s.car_un = s.car.unit_number
  s.cars = {s.car}
  local ok, reason = deploy(s.car)
  if not ok then return fail(run, tb, 5, "Aufbauen ging nicht: " .. tostring(reason)) end
  return 1
end

function steps.s5_start(run, tb, d, s)
  local hunt, reason = debug_hunt(run, tb, d, s, 5, s.car, {seconds = 60, debug = true,
    spawn = {position = at(s.c, -160, 0), direction = defines.direction.east}})
  if not hunt then return fail(run, tb, 5, "Befehlsjagd ging nicht: " .. tostring(reason)) end
  s.dest_bad, s.dest_n = 0, 0
  return 1
end

SAMPLE[5] = function(run, tb, d, s, w, hunt, worm, rec)
  local gap = s.rock_x - rec.head.x
  if not s.rock_min or gap < s.rock_min then s.rock_min = gap end
  if rec.phase == "angriff" then
    local P = target_point(hunt)
    local u = unit_vector(P.x - rec.head.x, P.y - rec.head.y)
    if u then
      s.dest_n = s.dest_n + 1
      local want = {x = P.x + 6 * u.x, y = P.y + 6 * u.y}
      local off = dist(worm.dest, want)
      if off > 1.5 then
        s.dest_bad = s.dest_bad + 1
        s.dest_first = s.dest_first or (pos_text(tb, worm.dest) .. " statt " .. pos_text(tb, want))
      end
    end
  end
end

function steps.s5_eval(run, tb, d, s)
  local w = s.watch
  local failed = s.failed
  local e = w.entry or {}
  check(failed, (s.dest_n or 0) > 0 and s.dest_bad == 0, "Fahrziel im Angriff nicht P + 6 · u (" .. tostring(s.dest_bad) .. " von "
    .. tostring(s.dest_n) .. " Takten, zuerst " .. tostring(s.dest_first) .. ")")
  check(failed, (w.states.patrolling or 0) == 0, "patrolling vor dem Biss in " .. tostring(w.states.patrolling) .. " Takten")
  local late = 0
  for _, detour in ipairs(w.detours) do
    if detour.d and detour.d <= ATTACK_RANGE then late = late + 1 end
  end
  check(failed, late == 0, late .. " Umwege in den letzten 40 Kacheln")
  bite_checks(run, tb, s, w, {reach = R_HARVESTER})
  check(failed, w.worm_gone and w.entry and w.worm_gone <= (e.bite_tick or 0) + 10, "Wurm nach dem Biss nicht weg")
  general(run, tb, d, s, w)
  tb.log(run, "MESSUNG", string.format("5) kleinster Abstand Kopf–Fels %s Kacheln, Weg von Knoten 1 beim Halten %s in %s s (Raster ±%d)",
    tb.num(s.rock_min, 2), tb.num(hold_path(w), 2), tb.num(w.hold.ticks / 60), w.hold.runs * NODE_STEP))
  return verdict(run, tb, 5, "Ernter 10 Kacheln vor Fels [W2]", failed, string.format("Fahrziel P + 6 · u in %s Takten, patrolling %d, Biss %s, Abstand %s",
    tostring(s.dest_n), w.states.patrolling or 0, rel(e.bite_tick, w.eta), tb.num(e.bite_dist, 2)))
end

-- Schritt 6: Ornithopter über dem Kopf (Feld 6) [W12]. Mitflug 300 Ticks über dem Kopf (O6), 60 Kacheln nördlich (O6b) und
-- 60 südlich (O6c, seit 0.8.2), dann kommen alle drei an ihren Punkten zur Ruhe, dann fliegen alle drei 80 Kacheln nach Westen:
-- O6 über den Körper (der Wurm fährt nach Osten), O6b und O6c auf den Parallelen. Abänderung 0.8.1 (Prüfstand 2026-10-27): Das Tempo im Mitflug folgt Zielpunkten, die mit
-- Knoten 1 im Raster springen (W18), und ist nur noch MESSUNG; der Flug nach Norden blieb kaum über dem Körper und begann mit
-- ungleichem Schwung. Gegenprüfung 0.8.1: Über dem Körper ist O6 nur etwa 140 der 600 Flugticks, die Flugzeit allein ließ 5 %
-- Bremsen dort durch; dafür zählte der Weg bis zum letzten Tick über dem Körper, und Sticker liest der Test in Ruhe und Flug je Tick.
-- Abänderung 0.8.2: Grenze BRAKE statt Weg (siehe oben bei den Konstanten).
function steps.s6_build(run, tb, d, s)
  local c = field(d, 6)
  s.c = c
  local chest = make(run, tb, s, {name = CHEST, position = c, force = d.force})
  if not chest then return fail(run, tb, 6, "Kiste K6 ließ sich nicht bauen") end
  local hunt, reason = debug_hunt(run, tb, d, s, 6, chest, {seconds = 60, debug = true,
    spawn = {position = at(c, -160, 0), direction = defines.direction.east}})
  if not hunt then return fail(run, tb, 6, "Befehlsjagd ging nicht: " .. tostring(reason)) end
  return 1
end

function steps.s6_wait(run, tb, d, s)
  local w = s.watch
  if w.ended then return fail(run, tb, 6, "Jagd vor dem Mitflug vorbei") end
  if not w.spawn_tick then return "poll" end
  return math.max(1, w.spawn_tick + ESCORT_START - game.tick)
end

-- Sticker außer den Tempo-Stickern des Ornithopters (prototypes/ornithopter-speed.lua).
local function foreign_stickers(entity)
  local names = {}
  for _, sticker in pairs(read(function() return entity.stickers end) or {}) do
    if valid(sticker) and not speed.parse(sticker.name) then table.insert(names, sticker.name) end
  end
  return names
end

-- Zielpunkte im Mitflug: O6 über dem Kopf, O6b 60 Kacheln nördlich, O6c 60 Kacheln südlich (beide fern vom Wurm).
local function escort_points(head, heading)
  local h = heading or {x = 1, y = 0}
  local p = {x = head.x + ESCORT_LEAD * h.x, y = head.y + ESCORT_LEAD * h.y}
  return p, {x = p.x, y = p.y - ESCORT_SIDE}, {x = p.x, y = p.y + ESCORT_SIDE}
end

function steps.s6_escort_start(run, tb, d, s)
  local nodes = s.hunt.worm and valid(s.hunt.worm.unit) and s.hunt.worm.unit.get_body_nodes()
  if not nodes then return fail(run, tb, 6, "kein Wurm 600 Ticks nach dem Spawn") end
  local head = nodes[1]
  s.o6 = new_flyer(run, tb, d, s, head, {pilot = true, coal = 20})
  s.o6b = new_flyer(run, tb, d, s, at(head, 0, -ESCORT_SIDE), {pilot = true, coal = 20})
  s.o6c = new_flyer(run, tb, d, s, at(head, 0, ESCORT_SIDE), {pilot = true, coal = 20})
  if not (s.o6 and s.o6b and s.o6c) then return fail(run, tb, 6, "Ornithopter ließen sich nicht bauen") end
  s.pilot6, s.pilot6b = pilot_of(s.o6), pilot_of(s.o6b)
  s.health = {o6 = s.o6.health, o6b = s.o6b.health, p6 = s.pilot6 and s.pilot6.health, p6b = s.pilot6b and s.pilot6b.health}
  s.escort = {start = game.tick, n = 0, d6 = 0, db = 0, dc = 0, v6 = 0, vb = 0, vc = 0, head = 0, extra = {}}
  return 1
end

function steps.s6_escort(run, tb, d, s)
  local e = s.escort
  local now = game.tick
  if not (valid(s.o6) and valid(s.o6b) and valid(s.o6c)) then return fail(run, tb, 6, "Ornithopter im Mitflug weg") end
  local head = sandworm_lib.head_of(s.hunt)
  if (now - e.start) % 10 == 0 then
    if head then
      local nodes = s.hunt.worm.unit.get_body_nodes()
      e.p6, e.pb, e.pc = escort_points(head, heading_of(nodes))
      pcall(function() s.o6.autopilot_destination = e.p6 end)
      pcall(function() s.o6b.autopilot_destination = e.pb end)
      pcall(function() s.o6c.autopilot_destination = e.pc end)
    end
    for _, name in ipairs(foreign_stickers(s.o6)) do e.extra[name] = true end
  end
  if e.p6 then
    e.n = e.n + 1
    e.d6 = e.d6 + dist(s.o6.position, e.p6)
    e.db = e.db + dist(s.o6b.position, e.pb)
    e.dc = e.dc + dist(s.o6c.position, e.pc)
    e.v6 = e.v6 + (tb.speed_tps(s.o6) or 0)
    e.vb = e.vb + (tb.speed_tps(s.o6b) or 0)
    e.vc = e.vc + (tb.speed_tps(s.o6c) or 0)
    if head then e.head = e.head + dist(s.o6.position, head) end
  end
  if now - e.start < ESCORT_TICKS then return "poll" end
  -- Ruhe: Die Zielpunkte bleiben, wo sie zuletzt waren; der Wurm fährt weiter unter O6 hindurch.
  if e.p6 then
    pcall(function() s.o6.autopilot_destination = e.p6 end)
    pcall(function() s.o6b.autopilot_destination = e.pb end)
    pcall(function() s.o6c.autopilot_destination = e.pc end)
  end
  s.rest = {start = now, calm = 0}
  return 1
end

-- Beide unter REST_SPEED für REST_CALM Ticks oder REST_MAX Ticks vorbei, dann der Flug nach Westen aus der Ruhe. Sticker je
-- Tick: Hier fährt der Kopf unter O6 hindurch, und ein kurzer Sticker wäre bis s6_eval abgelaufen.
function steps.s6_rest(run, tb, d, s)
  local r = s.rest
  local now = game.tick
  if not (valid(s.o6) and valid(s.o6b) and valid(s.o6c)) then return fail(run, tb, 6, "Ornithopter vor dem Flug weg") end
  for _, name in ipairs(foreign_stickers(s.o6)) do s.escort.extra[name] = true end
  local v6, vb, vc = tb.speed_tps(s.o6) or 0, tb.speed_tps(s.o6b) or 0, tb.speed_tps(s.o6c) or 0
  if v6 < REST_SPEED and vb < REST_SPEED and vc < REST_SPEED then r.calm = r.calm + 1 else r.calm = 0 end
  if r.calm < REST_CALM and now - r.start < REST_MAX then return "poll" end
  r.ticks, r.calm_ok, r.v6, r.vb, r.vc = now - r.start, r.calm >= REST_CALM, v6, vb, vc
  s.flight = {start = now, p6 = at(s.o6.position, -FLIGHT, 0), pb = at(s.o6b.position, -FLIGHT, 0), pc = at(s.o6c.position, -FLIGHT, 0),
    over = 0, v6 = 0, vb = 0, vc = 0, near = nil, s6 = at(s.o6.position, 0, 0), sb = at(s.o6b.position, 0, 0), sc = at(s.o6c.position, 0, 0),
    side = {0, 0, 0}, profile = {{}, {}, {}}, waypoints = nil}
  pcall(function() s.o6.autopilot_destination = s.flight.p6 end)
  pcall(function() s.o6b.autopilot_destination = s.flight.pb end)
  pcall(function() s.o6c.autopilot_destination = s.flight.pc end)
  return 1
end

-- Flug: je Tick der kleinste Abstand von O6 zu einem Körperknoten; über dem Körper (≤ OVER_NEAR) zählen Ticks und die Tempi
-- beider Flieger im selben Tick, und w6, wb halten den Weg beider seit dem Start (der letzte solche Tick bleibt stehen). Beide
-- starten im selben Tick aus der Ruhe zu festen Zielen: Der Weg hängt nicht am Raster der Knoten, und ein Bremsen über dem
-- Körper fehlt O6 dort ganz (die Flugzeit verdünnt es mit dem Rest der 80 Kacheln). Sticker an O6 je Tick wie in s6_rest.
-- Fertig, wenn alle drei angekommen sind (on_spider_command_completed) oder nach FLIGHT_MAX.
function steps.s6_flight(run, tb, d, s)
  local f = s.flight
  local arrived = d.arrived or {}
  local a6 = valid(s.o6) and arrived[s.o6.unit_number]
  local ab = valid(s.o6b) and arrived[s.o6b.unit_number]
  local ac = valid(s.o6c) and arrived[s.o6c.unit_number]
  if a6 and a6 < f.start then a6 = nil end
  if ab and ab < f.start then ab = nil end
  if ac and ac < f.start then ac = nil end
  local unit = s.hunt.worm and s.hunt.worm.unit
  if valid(s.o6) then
    for _, name in ipairs(foreign_stickers(s.o6)) do s.escort.extra[name] = true end
  end
  -- MESSUNG: Wegpunkte des Autopiloten im ersten Tick (setzt die Engine eigene Zwischenpunkte, etwa um den Wurm herum?),
  -- größte Abweichung quer zur Flugrichtung und das Tempo je BRAKE.profile_step Ticks in den ersten BRAKE.profile_ticks.
  local age = game.tick - f.start
  if not f.waypoints and valid(s.o6) then
    f.waypoints = {}
    for i, flyer in ipairs({s.o6, s.o6b, s.o6c}) do
      local list = valid(flyer) and read(function() return flyer.autopilot_destinations end)
      f.waypoints[i] = list and #list or -1
    end
  end
  for i, pair in ipairs({{s.o6, f.s6}, {s.o6b, f.sb}, {s.o6c, f.sc}}) do
    local flyer, start = pair[1], pair[2]
    if valid(flyer) then
      local side = math.abs(flyer.position.y - start.y)
      if side > f.side[i] then f.side[i] = side end
      if age > 0 and age <= BRAKE.profile_ticks and age % BRAKE.profile_step == 0 then table.insert(f.profile[i], tb.speed_tps(flyer) or 0) end
    end
  end
  if not a6 and valid(s.o6) and valid(unit) then
    local near
    for _, node in ipairs(unit.get_body_nodes()) do
      local gap = dist(s.o6.position, node)
      if not near or gap < near then near = gap end
    end
    if near and (not f.near or near < f.near) then f.near = near end
    if near and near <= OVER_NEAR then
      f.over = f.over + 1
      f.v6 = f.v6 + (tb.speed_tps(s.o6) or 0)
      f.vb = f.vb + (valid(s.o6b) and tb.speed_tps(s.o6b) or 0)
      f.vc = f.vc + (valid(s.o6c) and tb.speed_tps(s.o6c) or 0)
      f.w6 = dist(s.o6.position, f.s6)
      f.wb = valid(s.o6b) and dist(s.o6b.position, f.sb) or nil
      f.wc = valid(s.o6c) and dist(s.o6c.position, f.sc) or nil
    end
  end
  if a6 and ab and ac then
    f.t6, f.tb, f.tc = a6 - f.start, ab - f.start, ac - f.start
    return 1
  end
  if game.tick - f.start > FLIGHT_MAX then
    f.t6, f.tb, f.tc = a6 and (a6 - f.start), ab and (ab - f.start), ac and (ac - f.start)
    return 1
  end
  return "poll"
end

function steps.s6_eval(run, tb, d, s)
  local w = s.watch
  local failed = s.failed
  local e = s.escort
  local f = s.flight
  for _, name in ipairs(foreign_stickers(s.o6)) do e.extra[name] = true end
  local extra = {}
  for name in pairs(e.extra) do table.insert(extra, name) end
  table.sort(extra)
  local same = valid(s.o6) and valid(s.o6b) and s.o6.health == s.health.o6 and s.o6b.health == s.health.o6b
    and valid(s.pilot6) and s.pilot6.health == s.health.p6 and valid(s.pilot6b) and s.pilot6b.health == s.health.p6b
  check(failed, same, "Gesundheit von O6, O6b oder Pilot verändert")
  check(failed, #extra == 0, "fremde Sticker an O6: " .. table.concat(extra, ", "))
  local n = math.max(1, e.n)
  local d6, db, dc, v6, vb, vc = e.d6 / n, e.db / n, e.dc / n, e.v6 / n, e.vb / n, e.vc / n
  local dref = (db + dc) / 2
  check(failed, e.n > 0 and d6 <= dref + ESCORT_DIST, "mittlerer Abstand zum Zielpunkt O6 " .. tb.num(d6, 2) .. " statt ≤ O6b/O6c "
    .. tb.num(dref, 2) .. " + 0,5")
  check(failed, f.over >= OVER_MIN, "O6 nur " .. f.over .. " Ticks des Flugs höchstens 3 Kacheln von einem Körperknoten statt ≥ 60")
  -- Tempo über dem Körper und Flugzeit vergleichen nur Flüge aus der Ruhe; sonst ist der Vergleich nicht aussagekräftig, und der
  -- Schritt sagt das als eigenen FEHLER statt als Bremsen.
  local r = s.rest or {}
  local over = math.max(1, f.over)
  local o6, oref = f.v6 / over, (f.vb + f.vc) / (2 * over)
  local tref = f.tb and f.tc and (f.tb + f.tc) / 2
  if r.calm_ok then
    check(failed, f.over > 0 and o6 >= BRAKE.min * oref, "Tempo O6 über dem Körper " .. tb.num(o6, 2) .. " statt ≥ 80 % von O6b/O6c "
      .. tb.num(oref, 2))
    check(failed, f.t6 and tref and f.t6 <= BRAKE.flight * tref, "Flugzeit O6 " .. tostring(f.t6) .. " statt ≤ 1,05 × " .. tb.num(tref, 1))
  else
    check(failed, false, string.format("nach %s Ticks nicht in Ruhe (O6 %s, O6b %s, O6c %s Kacheln/s), Flugvergleich nicht aussagekräftig",
      tostring(r.ticks), tb.num(r.v6, 2), tb.num(r.vb, 2), tb.num(r.vc, 2)))
  end
  -- Das Tempo im Mitflug ist MESSUNG: Die Zielpunkte springen mit Knoten 1 (W18), O6 folgt ihnen anders als O6b.
  if e.n > 0 and v6 < ESCORT_SPEED * (vb + vc) / 2 then
    tb.log(run, "INFO", "6) mittleres Tempo O6 im Mitflug " .. tb.num(v6, 2) .. " unter 98 % von O6b/O6c " .. tb.num((vb + vc) / 2, 2) .. " (nur MESSUNG)")
  end
  bite_checks(run, tb, s, w, {reach = w.R})
  general(run, tb, d, s, w)
  local function profile(list)
    local parts = {}
    for _, v in ipairs(list or {}) do table.insert(parts, tb.num(v, 1)) end
    return table.concat(parts, " ")
  end
  local wp = f.waypoints or {}
  tb.log(run, "MESSUNG", string.format("6) Mitflug %d Ticks: Abstand O6–Kopf %s, zum Zielpunkt O6 %s / O6b %s / O6c %s, Tempo O6 %s / O6b %s / O6c %s; "
    .. "Ruhe nach %s Ticks; Flug 80 Kacheln nach Westen O6 %s / O6b %s / O6c %s Ticks, über dem Körper %d Ticks (kleinster Abstand %s), "
    .. "Tempo dort O6 %s / O6b %s / O6c %s (%s %%), Weg bis zum letzten Tick dort O6 %s / O6b %s / O6c %s",
    e.n, tb.num(e.head / n, 2), tb.num(d6, 2), tb.num(db, 2), tb.num(dc, 2), tb.num(v6, 2), tb.num(vb, 2), tb.num(vc, 2),
    tostring(r.ticks), tostring(f.t6), tostring(f.tb), tostring(f.tc), f.over, tb.num(f.near, 2),
    tb.num(f.over > 0 and o6 or nil, 2), tb.num(f.over > 0 and f.vb / over or nil, 2), tb.num(f.over > 0 and f.vc / over or nil, 2),
    tb.num(oref > 0 and 100 * o6 / oref or nil, 0), tb.num(f.w6, 2), tb.num(f.wb, 2), tb.num(f.wc, 2)))
  tb.log(run, "MESSUNG", string.format("6) Ursache [W12]: Wegpunkte des Autopiloten im ersten Flugtick O6 %s / O6b %s / O6c %s; größte Abweichung quer "
    .. "O6 %s / O6b %s / O6c %s Kacheln; Tempo je %d Ticks O6 %s | O6b %s | O6c %s",
    tostring(wp[1]), tostring(wp[2]), tostring(wp[3]), tb.num(f.side[1], 2), tb.num(f.side[2], 2), tb.num(f.side[3], 2), BRAKE.profile_step,
    profile(f.profile[1]), profile(f.profile[2]), profile(f.profile[3])))
  return verdict(run, tb, 6, "Ornithopter über dem Kopf [W12]", failed, string.format("Tempo über dem Körper %s %%, Flugzeit %s %%, über dem Körper %d Ticks, "
    .. "Abstand +%s, Sticker %d, Biss %s",
    tb.num(oref > 0 and 100 * o6 / oref or nil, 0), tb.num(f.t6 and tref and tref > 0 and 100 * f.t6 / tref or nil, 1), f.over,
    tb.num(d6 - dref, 2), #extra, rel((w.entry or {}).bite_tick, w.eta)))
end

-- Schritt 7: Rettung (Feld 7).
function steps.s7_build(run, tb, d, s)
  local c = field(d, 7)
  s.c = c
  s.car = new_harvester(run, tb, d, s, c, {coal = 40, field = 1000, driver = true})
  if not s.car then return fail(run, tb, 7, "Ernter H7 ließ sich nicht bauen") end
  s.car_un = s.car.unit_number
  s.driver = driver_of(s, s.car)
  s.cars = {s.car}
  s.flyer = new_flyer(run, tb, d, s, c, {pilot = true, coal = 20})
  if not s.flyer then return fail(run, tb, 7, "Ornithopter O7 ließ sich nicht bauen") end
  s.pilot = pilot_of(s.flyer)
  local ok, reason = deploy(s.car)
  if not ok then return fail(run, tb, 7, "Aufbauen ging nicht: " .. tostring(reason)) end
  return 1
end

function steps.s7_start(run, tb, d, s)
  local hunt, reason = debug_hunt(run, tb, d, s, 7, s.car, {seconds = 60, debug = true})
  if not hunt then return fail(run, tb, 7, "Befehlsjagd ging nicht: " .. tostring(reason)) end
  s.health = {flyer = s.flyer.health, pilot = s.pilot and s.pilot.health}
  s.mark = #(d.death_list or {})
  return math.max(1, hunt.eta_tick - RESCUE_COUPLE - game.tick)
end

function steps.s7_couple(run, tb, d, s)
  local ok, reason = flyer_lib.toggle_carry(s.flyer, s.car, nil)
  check(s.failed, ok == true and reason == "coupling", "toggle_carry bei eta − 720: " .. tostring(ok) .. "/" .. tostring(reason))
  return math.max(1, s.hunt.eta_tick - RESCUE_CARRIED - game.tick)
end

function steps.s7_carried(run, tb, d, s)
  check(s.failed, car_state(s.car) == "carried", "bei eta − 590 nicht getragen (" .. car_state(s.car) .. ")")
  return to_sample(s.hunt.eta_tick - 10)
end

function steps.s7_before(run, tb, d, s)
  local head = sandworm_lib.head_of(s.hunt)
  s.before = head and dist(head, s.hunt.last_pos) or nil
  check(s.failed, s.before and s.before <= s.watch.R + RESCUE_NEAR, "vor 0 Kopf " .. tb.num(s.before) .. " Kacheln von last_pos statt ≤ R + 8")
  return 1
end

function steps.s7_end(run, tb, d, s)
  local w = s.watch
  if not w.ended or game.tick < w.ended + 2 then return "poll" end
  local failed = s.failed
  local e = w.entry or {}
  check(failed, e.outcome == "escaped", "Ergebnis " .. tostring(e.outcome) .. " statt escaped")
  check(failed, w.searching and takt(w.searching) == w.eta, "Fehlbiss " .. rel(w.searching, w.eta) .. " statt bei eta")
  check(failed, (w.miss_eruptions or 0) >= 1, "keine Eruption am Kopf bei eta")
  check(failed, w.worm_gone and w.worm_gone <= w.eta + DIVE_AFTER, "Wurm " .. rel(w.worm_gone, w.eta) .. " abgetaucht statt spätestens eta + 30")
  check(failed, takt(w.ended) == w.eta + SEARCH_TICKS, "Ende " .. rel(w.ended, w.eta) .. " statt eta + 600")
  local gone = {}
  for i = s.mark + 1, #(d.death_list or {}) do
    local record = d.death_list[i]
    if inside(w.box, record.position) then table.insert(gone, record.name) end
  end
  check(failed, #gone == 0, "gestorben: " .. table.concat(gone, ", "))
  check(failed, valid(s.flyer) and s.flyer.health == s.health.flyer and valid(s.pilot) and s.pilot.health == s.health.pilot,
    "O7 oder Pilot verändert")
  general(run, tb, d, s, w)
  local ok = flyer_lib.toggle_carry(s.flyer, nil, nil)
  s.drop_tick = game.tick
  if not ok then check(failed, false, "Absetzen ging nicht") end
  return 1
end

function steps.s7_drop(run, tb, d, s)
  local w = s.watch
  local state = car_state(s.car)
  if state == "carried" and game.tick - s.drop_tick < 600 then return "poll" end
  return verdict(run, tb, 7, "Rettung", s.failed, string.format("vor 0 %s Kacheln von last_pos, Fehlbiss %s mit %s Eruptionen am Kopf, Wurm weg %s, Ende %s, H7 danach %s",
    tb.num(s.before), rel(w.searching, w.eta), tostring(w.miss_eruptions), rel(w.worm_gone, w.eta), rel(w.ended, w.eta), state))
end

-- Schritt 8: Zerdrücken (Feld 8) [W10, W15]. Linie westlich von K8. Max 27.10.: Auto samt Fahrer und Figur auf der
-- Linie sterben mit (worms.CRUSH_SPARES_VEHICLES = false); ein Auto 6 Kacheln neben der Spur und der Ernter H8 6 Kacheln
-- daneben (Plan: 3; die Box ±1,1 läge dann in der Spur) bleiben. Die Felskiste steht im Zerdrückradius (Gegenprüfung
-- 0.8.0: bei −30 und 4 Kacheln neben der Linie lag sie außerhalb, und nichts prüfte die Sandregel): Felsfleck 2 × 2 mit
-- dem Rand 1,5 Kacheln neben der Linie bei −14, also erst im Angriff (Kopf höchstens 40 vor K8), in dem die Vorausschau
-- nur die Mittellinie prüft; die Vorausschau der Anfahrt reicht höchstens bis −22.
function steps.s8_build(run, tb, d, s)
  local c = field(d, 8)
  s.c = c
  local surface = tb.surface()
  local force = d.force
  local n, m = math.floor(c.x), math.floor(c.y)
  local spares = worms_lib.CRUSH_SPARES_VEHICLES
  s.crush, s.keep, s.cross = {}, {}, {}
  local function add(list, label, entity, extra)
    if not entity then return nil end
    local entry = {label = label, entity = entity, un = entity.unit_number, health = entity.health, x = entity.position.x}
    for key, value in pairs(extra or {}) do entry[key] = value end
    table.insert(list, entry)
    return entity
  end
  for i = -2, 2 do
    add(s.crush, "Band " .. (i + 3), make(run, tb, s, {name = "transport-belt", position = at(c, -100, i), direction = defines.direction.north, force = force}))
  end
  add(s.crush, "Holzkiste", make(run, tb, s, {name = CHEST, position = at(c, -90, 0), force = force}))
  add(s.crush, "Schiene", make(run, tb, s, {name = "straight-rail", position = at(c, -80, 0), direction = defines.direction.north, force = force}))
  local car = new_car(run, tb, d, s, at(c, -70, 0), {driver = true})
  local car_driver = driver_of(s, car)
  local character = make(run, tb, s, {name = "character", position = at(c, -60, 0), force = force})
  add(spares and s.keep or s.crush, "Auto auf der Linie", car)
  add(spares and s.keep or s.crush, "Fahrer des Autos", car_driver)
  add(spares and s.keep or s.crush, "Figur zu Fuß", character)
  s.cross.car, s.cross.character = car and car.position.x, character and character.position.x
  local elevated = make(run, tb, s, {name = "elevated-straight-rail", position = at(c, -50, 0), direction = defines.direction.north, force = force})
  add(s.keep, "Hochschiene", elevated)
  s.cross.elevated = elevated and elevated.position.x
  local iron = make(run, tb, s, {name = "iron-chest", position = at(c, -40, 0), force = force})
  if iron then iron.destructible = false end
  add(s.keep, "Eisenkiste (unzerstörbar)", iron)
  s.cross.iron = iron and iron.position.x
  tiles(surface, n - 14, m + 2, n - 13, m + 3, ROCK)
  local rock_chest = make(run, tb, s, {name = CHEST, position = {x = n - 14 + 0.5, y = m + 2 + 0.5}, force = force})
  add(s.keep, "Felskiste", rock_chest)
  s.rock_box = rock_chest and box_copy(rock_chest.bounding_box)
  -- Nur die Sandregel darf sie schützen: Box höchstens CRUSH_RADIUS von der Linie und ganz auf Fels.
  local rock_gap = rock_chest and box_distance(s.rock_box, rock_chest.position.x, c.y)
  if rock_chest and (rock_gap >= worms_lib.CRUSH_RADIUS or terrain.has_sand_under(rock_chest)) then
    return fail(run, tb, 8, "Felskiste nicht ganz auf Fels im Zerdrückradius der Linie (Abstand " .. tb.num(rock_gap, 2) .. ")")
  end
  local flyer = new_flyer(run, tb, d, s, at(c, -25, 0), {pilot = true})
  add(s.keep, "Ornithopter", flyer)
  add(s.keep, "Pilot", pilot_of(flyer))
  local h8 = new_harvester(run, tb, d, s, at(c, -20, 6), {coal = 10, spice = 100, driver = true})
  if h8 then
    local h = harvester.get(h8)
    if h then vibration_lib.set_careful(h, true, nil) end
  end
  add(s.keep, "Ernter H8", h8, {trunk = 100})
  add(s.keep, "Fahrer von H8", driver_of(s, h8))
  local side = new_car(run, tb, d, s, at(c, -70, -6), {driver = true})
  add(s.keep, "Auto neben der Spur", side)
  add(s.keep, "Fahrer neben der Spur", driver_of(s, side))
  s.z = make(run, tb, s, {name = CHEST, position = at(c, -3, 0), force = force})
  s.z_un = s.z and s.z.unit_number
  local chest = make(run, tb, s, {name = CHEST, position = c, force = force})
  if not (chest and s.z) or #s.crush < (spares and 7 or 10) or #s.keep < (spares and 12 or 9) then
    return fail(run, tb, 8, "Aufbau unvollständig (Einzelheiten in der Datei)")
  end
  s.travel = {}
  local hunt, reason = debug_hunt(run, tb, d, s, 8, chest, {seconds = 60, debug = true,
    spawn = {position = at(c, -160, 0), direction = defines.direction.east}})
  if not hunt then return fail(run, tb, 8, "Befehlsjagd ging nicht: " .. tostring(reason)) end
  return 1
end

-- MESSUNG: Weg von Knoten 1 in 60 Ticks vor und nach der x-Lage von Eisenkiste, Hochschiene, Auto und Figur (Raster [W18]: bei
-- 3,5 Kacheln/s 3 oder 4, bei 2,4 Kacheln/s 2 oder 3; Stehen hieße 0 bis 1).
SAMPLE[8] = function(run, tb, d, s, w, hunt, worm, rec)
  s.track = s.track or {}
  table.insert(s.track, {tick = rec.tick, x = rec.head.x, y = rec.head.y})
  for key, x in pairs(s.cross) do
    if x and not s.travel[key] and rec.head.x >= x then s.travel[key] = {tick = rec.tick} end
  end
end

local function travel_text(tb, s)
  local parts = {}
  for _, key in ipairs({"car", "character", "elevated", "iron"}) do
    local t = s.travel[key]
    if t then
      local before, after
      for _, p in ipairs(s.track or {}) do
        if p.tick == t.tick - 60 then before = p end
        if p.tick == t.tick + 60 then after = p end
      end
      local here
      for _, p in ipairs(s.track or {}) do if p.tick == t.tick then here = p end end
      local b = before and here and dist(before, here)
      local a = after and here and dist(here, after)
      table.insert(parts, key .. " " .. tb.num(b) .. "/" .. tb.num(a))
    else
      table.insert(parts, key .. " nicht erreicht")
    end
  end
  return table.concat(parts, ", ")
end

function steps.s8_eval(run, tb, d, s)
  local w = s.watch
  local failed = s.failed
  local e = w.entry or {}
  local wrong = {}
  for _, entry in ipairs(s.crush) do
    local record = died(d, entry.un)
    if not record then
      table.insert(wrong, entry.label .. " lebt")
    elseif not (record.tick < w.eta and record.force == WORM_FORCE and record.head_dist and record.head_dist <= CRUSH_REACH) then
      table.insert(wrong, string.format("%s %s, Force %s, Kopf %s", entry.label, rel(record.tick, w.eta), tostring(record.force), tb.num(record.head_dist, 2)))
    end
  end
  check(failed, #wrong == 0, "nicht wie verlangt zerdrückt: " .. table.concat(wrong, ", "))
  local hurt = {}
  for _, entry in ipairs(s.keep) do
    local ok = valid(entry.entity) and not died(d, entry.un) and entry.entity.health == entry.health
    if ok and entry.trunk then
      local trunk = entry.entity.get_inventory(defines.inventory.car_trunk)
      ok = trunk and trunk.get_item_count(SPICE) == entry.trunk
    end
    if not ok then table.insert(hurt, entry.label) end
  end
  check(failed, #hurt == 0, "nicht heil: " .. table.concat(hurt, ", "))
  -- Sonst sagt „Felskiste heil“ nichts über die Sandregel.
  local closest
  for _, p in ipairs(s.track or {}) do
    local gap = box_distance(s.rock_box, p.x, p.y)
    if gap and (not closest or gap < closest) then closest = gap end
  end
  check(failed, closest and closest <= worms_lib.CRUSH_RADIUS, "Kopf nie im Zerdrückradius der Felskiste (kleinster Abstand "
    .. tb.num(closest, 2) .. "): Sandregel ungeprüft")
  local z = died(d, s.z_un)
  check(failed, z and z.tick == e.bite_tick, "Kiste Z " .. (z and rel(z.tick, w.eta) or "lebt") .. " statt im Biss-Takt")
  check(failed, e.dive ~= "stillstand", "abgetaucht wegen Stillstand")
  bite_checks(run, tb, s, w, {reach = w.R})
  general(run, tb, d, s, w)
  local where = {}
  for _, entry in ipairs(s.keep) do
    if valid(entry.entity) and (entry.label == "Auto neben der Spur" or entry.label == "Ernter H8" or entry.label == "Auto auf der Linie"
        or entry.label == "Figur zu Fuß") then
      table.insert(where, entry.label .. " " .. pos_text(tb, entry.entity.position))
    end
  end
  tb.log(run, "MESSUNG", "8) Weg von Knoten 1 je 60 Ticks vor/nach (Raster ±1, Stehen hieße 0 bis 1): " .. travel_text(tb, s) .. "; Lage danach: " .. (#where > 0 and table.concat(where, ", ") or "–")
    .. "; zerdrückt laut Protokoll " .. tostring(e.crushed) .. "; Kopf bis " .. tb.num(closest, 2) .. " an der Felskiste")
  return verdict(run, tb, 8, "Zerdrücken [W10, W15]", failed, string.format("%d zerdrückt (Fahrzeuge und Figuren %s), %d heil, Z %s, Biss %s",
    #s.crush, worms_lib.CRUSH_SPARES_VEHICLES and "verschont" or "mit", #s.keep, z and rel(z.tick, w.eta) or "lebt", rel(e.bite_tick, w.eta)))
end

-- Schritt 9: Ersatzbiss (Feld 9) [W3].
function steps.s9_build(run, tb, d, s)
  local c = field(d, 9)
  s.c = c
  local chest = make(run, tb, s, {name = CHEST, position = c, force = d.force})
  if not chest then return fail(run, tb, 9, "Kiste K9 ließ sich nicht bauen") end
  s.chest_un = chest.unit_number
  s.ersatz0 = storage.hunts.ersatz or 0
  local eta = math.ceil((game.tick + WARN_TICKS) / 10) * 10
  local hunt, reason = debug_hunt(run, tb, d, s, 9, chest, {seconds = 60, debug = true,
    spawn = {position = at(c, -160, 0), direction = defines.direction.east, tick = eta - ERSATZ_SPAWN}})
  if not hunt then return fail(run, tb, 9, "Befehlsjagd ging nicht: " .. tostring(reason)) end
  return 1
end

function steps.s9_eval(run, tb, d, s)
  local w = s.watch
  local failed = s.failed
  local e = w.entry or {}
  local record = died(d, s.chest_un)
  check(failed, record and record.tick == w.eta + BITE_WINDOW, "K9 " .. (record and rel(record.tick, w.eta) or "lebt") .. " statt eta + 180")
  check(failed, e.ersatz == true, "kein Ersatzbiss im Protokoll")
  check(failed, (storage.hunts.ersatz or 0) == s.ersatz0 + 1, "storage.hunts.ersatz " .. s.ersatz0 .. " → " .. tostring(storage.hunts.ersatz))
  check(failed, e.bite_dist and e.bite_dist > w.R, "Abstand beim Ersatzbiss " .. tb.num(e.bite_dist, 2) .. " nicht > R")
  local ev = unit_events(d, w.un)
  check(failed, dived_after(ev, w.un, e.bite_tick), "Wurm nicht ab dem Biss-Takt abgetaucht")
  check(failed, w.spawn_tick == w.eta - ERSATZ_SPAWN, "Spawn " .. rel(w.spawn_tick, w.eta) .. " statt eta − 840")
  general(run, tb, d, s, w)
  tb.log(run, "MESSUNG", string.format("9) %s, Abstand beim Ersatzbiss %s Kacheln", sprint_text(tb, w), tb.num(e.bite_dist, 2)))
  return verdict(run, tb, 9, "Ersatzbiss [W3]", failed, string.format("Spawn %s, Biss %s, ersatz %s, Abstand %s", rel(w.spawn_tick, w.eta),
    rel(e.bite_tick, w.eta), tostring(e.ersatz), tb.num(e.bite_dist, 2)))
end

-- Schritt 10: Wurm getötet (Feld 10) [W8, W9].
function steps.s10_build(run, tb, d, s)
  local c = field(d, 10)
  s.c = c
  s.car = new_harvester(run, tb, d, s, c, {coal = 40, field = 1000})
  if not s.car then return fail(run, tb, 10, "Ernter H10 ließ sich nicht bauen") end
  s.car_un = s.car.unit_number
  s.cars = {s.car}
  local ok, reason = deploy(s.car)
  if not ok then return fail(run, tb, 10, "Aufbauen ging nicht: " .. tostring(reason)) end
  return 1
end

function steps.s10_wait(run, tb, d, s)
  local w = s.watch
  if not s.stats0 then s.stats0 = copy(worms_lib.stats_of(d.force)) end
  if w.ended then return fail(run, tb, 10, "Jagd vor dem Schaden vorbei") end
  if not w.spawn_tick then return "poll" end
  return math.max(1, w.spawn_tick + KILL_DAMAGE_AFTER - game.tick)
end

function steps.s10_damage(run, tb, d, s)
  local unit = s.hunt.worm and s.hunt.worm.unit
  if not valid(unit) then return fail(run, tb, 10, "kein Wurm 300 Ticks nach dem Spawn") end
  s.unit = unit
  local ok, err = pcall(function() unit.damage(KILL_DAMAGE, d.force) end)
  if not ok then check(s.failed, false, "damage: " .. tostring(err)) end
  s.states, s.reads = {}, 0
  return 10
end

function steps.s10_state(run, tb, d, s)
  s.reads = s.reads + 1
  local ai = valid(s.unit) and read(function() return s.unit.get_ai_state() end)
  local state = ai and tb.enum_name(defines.segmented_unit_ai_state, ai.type) or "–"
  table.insert(s.states, (s.reads * 10) .. " " .. state)
  if state == "investigating" and not s.back then s.back = s.reads * 10 end
  if s.reads < KILL_STATE_MAX / 10 then return again(10) end
  tb.log(run, "MESSUNG", "10) Zustand nach dem Schaden: " .. table.concat(s.states, ", "))
  check(s.failed, s.back ~= nil and s.back <= KILL_STATE_MAX, "nach 40 Ticks nicht wieder investigating [W9]")
  return math.max(1, s.watch.spawn_tick + KILL_AFTER - game.tick)
end

function steps.s10_die(run, tb, d, s)
  local hunt = s.hunt
  local unit = hunt.worm and hunt.worm.unit
  if not valid(unit) then return fail(run, tb, 10, "kein Wurm 600 Ticks nach dem Spawn") end
  local un = unit.unit_number
  s.rescued = hunt.state == "warning" and not hunt.lost and valid(hunt.target)
  s.die_tick = game.tick
  local ok, err = pcall(function() unit.die(d.force) end)
  if not ok then return fail(run, tb, 10, "die: " .. tostring(err)) end
  local ev = unit_events(d, un)
  check(s.failed, #ev.died == 1 and ev.died[1] == s.die_tick, "segmented_unit_died " .. #ev.died .. "× statt einmal im selben Tick")
  if worms_lib.KILL_RESCUES then
    check(s.failed, storage.hunts.list[hunt.id] == nil, "Jagd nach dem Tod noch da")
  else
    check(s.failed, hunt.phase == "ohne" and hunt.no_worm == "verloren", "Phase " .. tostring(hunt.phase) .. "/" .. tostring(hunt.no_worm) .. " statt ohne/verloren")
  end
  return 1
end

function steps.s10_after(run, tb, d, s)
  local failed = s.failed
  local hunt = s.hunt
  local stats = worms_lib.stats_of(d.force)
  check(failed, (stats.killed or 0) == (s.stats0.killed or 0) + 1, "killed " .. tostring(s.stats0.killed) .. " → " .. tostring(stats.killed))
  if worms_lib.KILL_RESCUES then
    local e = log_entry(hunt.id) or {}
    check(failed, e.outcome == "killed", "Protokoll: Ergebnis " .. tostring(e.outcome) .. " statt killed")
    check(failed, stats.first_escape_tick ~= nil, "first_escape_tick nicht gesetzt")
    -- Der Chat ist per Skript nicht lesbar: geprüft wird die Bedingung für msg-worm-killed (Plan 4.11).
    check(failed, s.rescued, "Bedingung für msg-worm-killed (vor 0, Ziel gültig, nicht verloren) nicht erfüllt")
    local surface = tb.surface()
    check(failed, nine_zero(surface, hunt.origin_key), "9 Chunks um den Ursprung nicht 0")
    local until_tick = vibration_lib.resting(surface.index, hunt.sector_key)
    check(failed, until_tick and until_tick >= s.die_tick + REST_MIN, "Sektor ruht bis " .. tostring(until_tick) .. " statt ≥ Tod + 7200")
  end
  return math.max(1, hunt.eta_tick + 60 - game.tick)
end

function steps.s10_alive(run, tb, d, s)
  local failed = s.failed
  local w = s.watch
  if worms_lib.KILL_RESCUES then
    check(failed, valid(s.car) and not died(d, s.car_un), "H10 bei eta + 60 nicht am Leben")
  else
    check(failed, died(d, s.car_un) ~= nil, "H10 lebt, obwohl KILL_RESCUES = false bei 0 beißt")
  end
  no_corpse(run, tb, s, w)
  if not w.ended then
    w.ended = game.tick
    w.entry = log_entry(w.id)
  end
  local e = w.entry or log_entry(w.id) or {}
  w.entry = e
  general(run, tb, d, s, w)
  return verdict(run, tb, 10, "Wurm getötet [W8, W9]", failed, string.format("Schaden: investigating nach %s Ticks, Tod %s, Ergebnis %s, killed %s, H10 %s",
    tostring(s.back), rel(s.die_tick, w.eta), tostring(e.outcome), tostring(worms_lib.stats_of(d.force).killed), valid(s.car) and "lebt" or "tot"))
end

-- Schritt 11: Wurm verloren (Feld 11) [W7].
function steps.s11_build(run, tb, d, s)
  local c = field(d, 11)
  s.c = c
  local a = make(run, tb, s, {name = CHEST, position = at(c, 0, -30), force = d.force})
  local b = make(run, tb, s, {name = CHEST, position = at(c, 0, 30), force = d.force})
  if not (a and b) then return fail(run, tb, 11, "Kisten ließen sich nicht bauen") end
  s.a_un, s.b_un = a.unit_number, b.unit_number
  s.a_pos, s.b_pos = copy_pos(a.position), copy_pos(b.position)
  local ha, ra = worms_lib.start_hunt(a, {seconds = 60, debug = true, spawn = {position = at(c, -160, -30), direction = defines.direction.east}})
  local hb, rb = worms_lib.start_hunt(b, {seconds = 60, debug = true, spawn = {position = at(c, 160, 30), direction = defines.direction.west}})
  if not (ha and hb) then return fail(run, tb, 11, "Befehlsjagden gingen nicht: " .. tostring(ra) .. "/" .. tostring(rb)) end
  s.hunt, s.hunt2 = ha, hb
  s.watch, s.watch2 = watch_new(d, 11, ha), watch_new(d, 11, hb)
  d.active[11] = true
  return 1
end

function steps.s11_wait(run, tb, d, s)
  if s.watch.ended or s.watch2.ended then return fail(run, tb, 11, "Jagd vor dem Verlust vorbei") end
  if not (s.hunt.worm and s.hunt2.worm) then return "poll" end
  return math.max(1, math.max(s.watch.spawn_tick, s.watch2.spawn_tick) + LOST_AFTER - game.tick)
end

function steps.s11_destroy(run, tb, d, s)
  local ua, ub = s.hunt.worm and s.hunt.worm.unit, s.hunt2.worm and s.hunt2.worm.unit
  if not (valid(ua) and valid(ub)) then return fail(run, tb, 11, "Würmer 300 Ticks nach dem Spawn nicht da") end
  s.lost_tick = game.tick
  ua.destroy{raise_destroy = true}
  check(s.failed, s.hunt.phase == "ohne" and s.hunt.no_worm == "verloren",
    "a nach destroy{raise_destroy}: " .. tostring(s.hunt.phase) .. "/" .. tostring(s.hunt.no_worm) .. " statt ohne/verloren im selben Tick")
  ub.destroy{}
  return 1
end

function steps.s11_b(run, tb, d, s)
  local hunt = s.hunt2
  if hunt.phase == "ohne" and hunt.no_worm == "verloren" then
    s.b_delay = game.tick - s.lost_tick
    return math.max(1, hunt.eta_tick + 2 - game.tick)
  end
  if game.tick - s.lost_tick > 10 then
    check(s.failed, false, "b nach destroy{} nicht binnen 10 Ticks ohne/verloren (" .. tostring(hunt.phase) .. "/" .. tostring(hunt.no_worm) .. ")")
    return math.max(1, hunt.eta_tick + 2 - game.tick)
  end
  return "poll"
end

function steps.s11_eval(run, tb, d, s)
  if not (s.watch.ended and s.watch2.ended) then return "poll" end
  local failed = s.failed
  for _, item in ipairs({{label = "a", un = s.a_un, w = s.watch}, {label = "b", un = s.b_un, w = s.watch2}}) do
    local record = died(d, item.un)
    check(failed, record and record.tick == item.w.eta, "Kiste " .. item.label .. " " .. (record and rel(record.tick, item.w.eta) or "lebt") .. " statt genau bei eta")
    check(failed, record and record.eruptions >= 1, "keine Eruption an Kiste " .. item.label)
  end
  s.watch.box, s.watch2.box = d.fields[11].box, nil
  general(run, tb, d, s, s.watch)
  local keep = s.failed
  general(run, tb, d, {failed = keep}, s.watch2)
  return verdict(run, tb, 11, "Wurm verloren [W7]", failed, string.format("a ohne/verloren im selben Tick, b nach %s Ticks, Bisse %s und %s",
    tostring(s.b_delay), rel(died(d, s.a_un) and died(d, s.a_un).tick, s.watch.eta), rel(died(d, s.b_un) and died(d, s.b_un).tick, s.watch2.eta)))
end

-- Schritt 12: Flucht per Fahrt (Feld 2) [W3].
function steps.s12_build(run, tb, d, s)
  local c = field(d, 2)
  s.c = c
  s.car = new_harvester(run, tb, d, s, c, {coal = 50, field = 1000, driver = true})
  if not s.car then return fail(run, tb, 12, "Ernter H12 ließ sich nicht bauen") end
  s.car_un = s.car.unit_number
  s.driver = driver_of(s, s.car)
  s.cars = {s.car}
  local ok, reason = deploy(s.car)
  if not ok then return fail(run, tb, 12, "Aufbauen ging nicht: " .. tostring(reason)) end
  return 1
end

function steps.s12_sign(run, tb, d, s)
  local hunt = worms_lib.hunt_of(s.car)
  if not hunt then
    if game.tick > s.set_tick + 100 then return fail(run, tb, 12, "kein Wurmzeichen nach set_heat 999 (" .. car_state(s.car) .. ")") end
    return "poll"
  end
  s.hunt = hunt
  s.watch = watch_new(d, 12, hunt)
  d.active[12] = true
  s.packed = harvester.pack(harvester.get(s.car))
  s.pack_tick = game.tick
  check(s.failed, s.packed, "Einpacken im Tick des Wurmzeichens ging nicht (" .. car_state(s.car) .. ")")
  check(s.failed, not hunt.debug and hunt.eta_tick - hunt.warn_tick == WARN_TICKS, "keine reguläre 60-s-Jagd")
  s.start_pos = copy_pos(s.car.position)
  return 1
end

function steps.s12_drive(run, tb, d, s)
  local w = s.watch
  local car = s.car
  if w.ended then
    if valid(car) then gas(car, s.driver, false) end
    return 1
  end
  if valid(car) and car_state(car) == "mobile" then
    if not s.turned then
      s.turned = game.tick
      pcall(function() car.orientation = 0.625 end)
    end
    gas(car, s.driver, true)
    s.last_pos = copy_pos(car.position)
  end
  return "poll"
end

function steps.s12_eval(run, tb, d, s)
  if game.tick < s.watch.ended + 2 then return "poll" end
  local w = s.watch
  local failed = s.failed
  local e = w.entry or {}
  if sandworm_lib.SPRINT then
    bite_checks(run, tb, s, w, {reach = R_HARVESTER})
  else
    bite_checks(run, tb, s, w, {ersatz_ok = true})
    if e.ersatz then tb.log(run, "INFO", "12) Ersatzbiss: SPRINT = false (Plan 4.9)") end
  end
  general(run, tb, d, s, w)
  local travelled = s.last_pos and dist(s.start_pos, s.last_pos) or 0
  tb.log(run, "MESSUNG", string.format("12) %s, Gas ab %s, Weg von H12 seit dem Wurmzeichen %s Kacheln", sprint_text(tb, w), rel(s.turned, w.eta),
    tb.num(travelled)))
  return verdict(run, tb, 12, "Flucht per Fahrt [W3]", failed, string.format("Biss %s, Abstand %s, Ersatzbiss %s, Sprint-Takte %s, Weg %s",
    rel(e.bite_tick, w.eta), tb.num(e.bite_dist, 2), tostring(e.ersatz), tostring(e.sprint), tb.num(travelled)))
end

-- Schritt 13: Grenzen (Feld 12, nach den Wellen).
function steps.s13_build(run, tb, d, s)
  local c = field(d, 12)
  s.c = c
  s.info_only = foreign_count({[d.force.index] = true}) > 0
  if s.info_only then tb.log(run, "INFO", "13) Jagden anderer Forces laufen: Schritt 13 schreibt nur MESSUNG") end
  s.chests = {}
  for i = 1, 6 do
    local chest = make(run, tb, s, {name = CHEST, position = at(c, -60 + 20 * i, -50), force = d.force})
    if not chest then return fail(run, tb, 13, "Kisten ließen sich nicht bauen") end
    s.chests[i] = chest
  end
  s.car = new_harvester(run, tb, d, s, at(c, 0, 40), {coal = 20, field = 1000})
  if not s.car then return fail(run, tb, 13, "Ernter ließ sich nicht bauen") end
  s.cars = {s.car}
  s.units0 = sandworms_in(tb.surface(), d.fields[12].box)
  local ok, reason = deploy(s.car)
  if not ok then return fail(run, tb, 13, "Aufbauen ging nicht: " .. tostring(reason)) end
  return 1
end

function steps.s13_four(run, tb, d, s)
  s.hunts = {}
  s.t0 = game.tick
  local phases = {}
  for i = 1, 4 do
    local hunt = worms_lib.start_hunt(s.chests[i], {seconds = 60, debug = true})
    s.hunts[i] = hunt
    table.insert(phases, hunt and (tostring(hunt.phase) .. (hunt.no_worm and ("/" .. hunt.no_worm) or "")) or "–")
  end
  s.phases = phases
  local h = s.hunts
  check(s.failed, h[1] and h[2] and h[3] and h[1].phase == "warten" and h[2].phase == "warten" and h[3].phase == "warten",
    "drei Befehlsjagden nicht warten: " .. table.concat(phases, ", "))
  check(s.failed, h[4] and h[4].phase == "ohne" and h[4].no_worm == "grenze", "vierte Befehlsjagd " .. tostring(phases[4]) .. " statt ohne/grenze")
  heat_chunk(tb.surface(), s.car.position, 999)
  s.set_tick = game.tick
  local short = worms_lib.start_hunt(s.chests[5], {seconds = SHORT_SECONDS, debug = true})
  table.insert(s.hunts, short)
  check(s.failed, short and short.phase == "ohne" and short.no_worm == "kurz", "Befehlsjagd 20 s " .. tostring(short and short.phase) .. "/"
    .. tostring(short and short.no_worm) .. " statt ohne/kurz")
  worms_lib.set_worm_off(d.force, true)
  local off = worms_lib.start_hunt(s.chests[6], {seconds = 60, debug = true})
  worms_lib.set_worm_off(d.force, false)
  table.insert(s.hunts, off)
  check(s.failed, off and off.phase == "ohne" and off.no_worm == "aus", "Befehlsjagd mit set_worm_off " .. tostring(off and off.phase) .. "/"
    .. tostring(off and off.no_worm) .. " statt ohne/aus")
  return 1
end

function steps.s13_regular(run, tb, d, s)
  local hunt = worms_lib.hunt_of(s.car)
  if not hunt then
    if game.tick > s.set_tick + 100 then
      check(s.failed, false, "keine reguläre Jagd nach set_heat 999")
      return 1
    end
    return "poll"
  end
  table.insert(s.hunts, hunt)
  s.regular = hunt
  check(s.failed, not hunt.debug and hunt.phase == "warten", "reguläre Jagd " .. tostring(hunt.phase) .. "/" .. tostring(hunt.no_worm) .. " statt warten")
  return 1
end

function steps.s13_abort(run, tb, d, s)
  local failed = s.failed
  local worms = 0
  for _, hunt in pairs(s.hunts) do
    if hunt.worm then worms = worms + 1 end
    end_if_running(hunt)
  end
  local waited = game.tick - s.t0
  check(failed, waited <= LIMIT_WINDOW, "Abbruch erst " .. waited .. " Ticks nach den vier Befehlsjagden")
  check(failed, next(storage.path_requests) == nil, count_list(storage.path_requests) .. " Einträge in path_requests")
  local units = sandworms_in(tb.surface(), d.fields[12].box)
  check(failed, worms == 0 and units == s.units0, "Wurm entstanden (" .. worms .. " Jagden mit Wurm, " .. units .. " im Feld)")
  local values = string.format("Phasen %s, reguläre Jagd %s, Abbruch nach %d Ticks", table.concat(s.phases, ", "),
    s.regular and tostring(s.regular.phase) or "–", waited)
  if s.info_only then
    tb.log(run, "INFO", "13) Grenzen (nur MESSUNG, fremde Jagden): " .. values .. (#failed > 0 and (" | abweichend: " .. table.concat(failed, "; ")) or ""))
    run.data.results[13] = "INFO"
    return "end"
  end
  return verdict(run, tb, 13, "Grenzen", failed, values)
end

-- Schritt 14: Migration und Waisen (Feld 12).
function steps.s14_run(run, tb, d, s)
  local failed = s.failed
  local c = field(d, 12)
  local chest = make(run, tb, s, {name = CHEST, position = at(c, 0, -80), force = d.force})
  if not chest then return fail(run, tb, 14, "Kiste ließ sich nicht bauen") end
  local hunt = worms_lib.start_hunt(chest, {seconds = 60, debug = true})
  if not hunt then return fail(run, tb, 14, "Befehlsjagd ging nicht") end
  s.hunts = {hunt}
  hunt.phase = nil
  hunt.r = nil
  worms_lib.migrate_schema4{hunts = {hunt}}
  check(failed, hunt.phase == "ohne" and hunt.no_worm == "migration", "nach migrate_schema4 " .. tostring(hunt.phase) .. "/" .. tostring(hunt.no_worm)
    .. " statt ohne/migration")
  check(failed, type(hunt.r) == "number" and hunt.r > 0, "r nicht gesetzt (" .. tostring(hunt.r) .. ")")
  worms_lib.end_hunt(hunt, nil, "abort")
  check(failed, storage.hunts.list[hunt.id] == nil, "Jagd nach abort noch da")
  local orphan = spawn_unit(run, tb, d, WORM, at(c, -100, 60), 0, worm_force())
  local test_worm = spawn_unit(run, tb, d, TEST_WORM, at(c, 100, 60), 0, tb.worm_force())
  check(failed, orphan ~= nil, WORM .. " ohne Jagd ließ sich nicht erzeugen")
  check(failed, test_worm ~= nil, TEST_WORM .. " ließ sich nicht erzeugen")
  local n = sandworm_lib.sweep({tb.surface()})
  check(failed, n == 1, "sweep → " .. tostring(n) .. " statt 1")
  check(failed, orphan and not orphan.valid, "Waise noch da")
  check(failed, valid(test_worm), "Testwurm entfernt")
  if valid(test_worm) then test_worm.destroy{} end
  return verdict(run, tb, 14, "Migration und Waisen", failed, string.format("Migration %s/%s, r %s, sweep %s, Testwurm %s", tostring(hunt.phase),
    tostring(hunt.no_worm), tb.num(hunt.r, 2), tostring(n), test_worm and "blieb" or "–"))
end

-- Schritt 15: Entfernen (immer zuletzt, Feld 12).
function steps.s15_start(run, tb, d, s)
  local c = field(d, 12)
  local a = make(run, tb, s, {name = CHEST, position = at(c, -40, 100), force = d.force})
  local b = make(run, tb, s, {name = CHEST, position = at(c, 40, 100), force = d.force})
  s.c_chest = make(run, tb, s, {name = CHEST, position = at(c, 0, 140), force = d.force})
  if not (a and b and s.c_chest) then return fail(run, tb, 15, "Kisten ließen sich nicht bauen") end
  local ha = worms_lib.start_hunt(a, {seconds = UNINSTALL_SECONDS, debug = true})
  local hb = worms_lib.start_hunt(b, {seconds = UNINSTALL_SECONDS, debug = true})
  if not (ha and hb) then return fail(run, tb, 15, "Befehlsjagden gingen nicht") end
  s.hunts = {ha, hb}
  s.t0 = game.tick
  return 1
end

function steps.s15_uninstall(run, tb, d, s)
  local failed = s.failed
  local ha, hb = s.hunts[1], s.hunts[2]
  if not (ha.worm and hb.worm) then
    if game.tick - s.t0 > 200 then return fail(run, tb, 15, "Befehlsjagden mit 27 s ohne Wurm (" .. tostring(ha.phase) .. "/" .. tostring(hb.phase) .. ")") end
    return "poll"
  end
  s.spawn_after = math.max(ha.spawn_tick - ha.warn_tick, hb.spawn_tick - hb.warn_tick)
  local orphan = spawn_unit(run, tb, d, WORM, at(field(d, 12), 0, 180), 0, worm_force())
  check(failed, orphan ~= nil, "Waise ließ sich nicht erzeugen")
  local n_exp = count_list(storage.hunts.list)
  local m_exp = 0
  for _, hunt in pairs(storage.hunts.list) do
    if hunt.worm and valid(hunt.worm.unit) then m_exp = m_exp + 1 end
  end
  local owned = {}
  for _, hunt in pairs(storage.hunts.list) do if hunt.worm then owned[hunt.worm.un] = true end end
  for _, surface in pairs(game.surfaces) do
    for _, unit in pairs(surface.get_segmented_units()) do
      if unit.valid and not owned[unit.unit_number] and unit.prototype.name:sub(1, #PREFIX) == PREFIX
          and not sandworm_lib.diving(unit) then
        m_exp = m_exp + 1
      end
    end
  end
  local n, m = worms_lib.uninstall()
  s.n, s.m = n, m
  if n_exp == 2 and m_exp == 3 then
    check(failed, n == 2 and m == 3, "uninstall → " .. tostring(n) .. " und " .. tostring(m) .. " statt 2 und 3")
  else
    tb.log(run, "INFO", "15) Weitere Jagden oder Würmer im Spiel: erwartet " .. n_exp .. " und " .. m_exp)
    check(failed, n == n_exp and m == m_exp, "uninstall → " .. tostring(n) .. " und " .. tostring(m) .. " statt " .. n_exp .. " und " .. m_exp)
  end
  check(failed, sandworms_on(tb.surface()) == 0, sandworms_on(tb.surface()) .. " arrakis-sandworm-* auf der Prüfstand-Fläche")
  check(failed, next(storage.path_requests) == nil, "path_requests nicht leer")
  return 1
end

function steps.s15_force(run, tb, d, s)
  check(s.failed, game.forces[WORM_FORCE] == nil, "Sandwurm-Force nach 1 Tick noch da")
  local ok, hunt = pcall(worms_lib.start_hunt, s.c_chest, {seconds = UNINSTALL_SECONDS, debug = true})
  if not ok then return fail(run, tb, 15, "Skriptfehler beim Start ohne Force: " .. tostring(hunt)) end
  if not hunt then return fail(run, tb, 15, "Befehlsjagd ohne Force ging nicht") end
  s.c_hunt = hunt
  table.insert(s.hunts, hunt)
  return 1
end

function steps.s15_worm(run, tb, d, s)
  local hunt = s.c_hunt
  if not hunt.worm then
    if storage.hunts.list[hunt.id] ~= hunt or game.tick - hunt.warn_tick > 120 then
      check(s.failed, false, "kein Wurm ohne ensure_force (" .. tostring(hunt.phase) .. "/" .. tostring(hunt.no_worm) .. ")")
      return 1
    end
    return "poll"
  end
  s.c_spawn = hunt.spawn_tick - hunt.warn_tick
  -- 60 Ticks (Plan 4.4: D = 80,5) bis auf den Takt (eta auf 10 Ticks aufgerundet) und die Kachelmitte des Spawnpunkts.
  check(s.failed, math.abs(s.c_spawn - UNINSTALL_SPAWN) <= UNINSTALL_SLACK, "Wurm " .. s.c_spawn .. " Ticks nach dem Start statt 60 ± 9")
  check(s.failed, game.forces[WORM_FORCE] ~= nil, "Sandwurm-Force nicht neu angelegt")
  worms_lib.end_hunt(hunt, nil, "abort")
  return 1
end

function steps.s15_eval(run, tb, d, s)
  check(s.failed, sandworms_on(tb.surface()) == 0, "Wurm nach abort noch da")
  return verdict(run, tb, 15, "Entfernen", s.failed, string.format("Spawn nach %s Ticks, uninstall %s und %s, danach Wurm nach %s Ticks ohne ensure_force",
    tostring(s.spawn_after), tostring(s.n), tostring(s.m), tostring(s.c_spawn)))
end

local T21_STEPS =
{
  {steps.s1_check},
  {steps.s2_build, wait_deployed(2), set_phase(2), sign_phase(2, "Zeitlinie"), wait_end, steps.s2_eval},
  {steps.s3_build, wait_end, steps.s3_eval},
  {steps.s4_build, wait_end, steps.s4_eval},
  {steps.s5_build, wait_deployed(5), steps.s5_start, wait_end, steps.s5_eval},
  {steps.s6_build, steps.s6_wait, steps.s6_escort_start, steps.s6_escort, steps.s6_rest, steps.s6_flight, wait_end, steps.s6_eval},
  {steps.s7_build, wait_deployed(7), steps.s7_start, steps.s7_couple, steps.s7_carried, steps.s7_before, steps.s7_end, steps.s7_drop},
  {steps.s8_build, wait_end, steps.s8_eval},
  {steps.s9_build, wait_end, steps.s9_eval},
  {steps.s10_build, wait_deployed(10), set_phase(10), sign_phase(10, "Wurm getötet"), steps.s10_wait, steps.s10_damage, steps.s10_state,
    steps.s10_die, steps.s10_after, steps.s10_alive},
  {steps.s11_build, steps.s11_wait, steps.s11_destroy, steps.s11_b, steps.s11_eval},
  {steps.s12_build, wait_deployed(12), set_phase(12), steps.s12_sign, steps.s12_drive, steps.s12_eval},
  {steps.s13_build, wait_deployed(13), steps.s13_four, steps.s13_regular, steps.s13_abort},
  {steps.s14_run},
  {steps.s15_start, steps.s15_uninstall, steps.s15_force, steps.s15_worm, steps.s15_eval}
}

-- Hat jeder Schritt der Welle seine Jagd gestartet (oder ist fertig)?
local function wave_started(d, numbers)
  for _, number in ipairs(numbers) do
    if not (d.lanes[number].done or d["s" .. number].hunt) then return false end
  end
  return true
end

local function all_done(d, from, to)
  for number = from, to do
    if not d.lanes[number].done then return false end
  end
  return true
end

local function t21_start(run, tb)
  local d = run.data
  local surface = tb.surface()
  if not storage_ready() then
    tb.log(run, "FEHLER", "storage des Laufzeitcodes fehlt (scripts/migrate.lua init, Schema 4)")
    tb.finish(run, "abgebrochen (kein storage)")
    return
  end
  if not terrain.harvest_allowed(surface) then
    tb.log(run, "FEHLER", "terrain.harvest_allowed(" .. surface.name .. ") = false: der Laufzeitcode zählt hier nicht")
    tb.finish(run, "abgebrochen (Prüfstand-Fläche nicht erlaubt)")
    return
  end
  d.origin = tb.area(run.id)
  d.box = box_of(d.origin, AREA_HALF)
  local force = force_named(T21_FORCE)
  d.force = force
  d.saved = {grace = worms_lib.grace_snapshot(force), paused = storage.hunts.paused_until}
  d.units, d.active, d.path_events, d.arrived = {}, {}, {}, {}
  abort_hunts({[force.index] = true})
  clear_area(surface, d.box)
  worms_lib.ensure_force()
  worms_lib.set_paused(nil)
  vibration_lib.testbench_enable(force)
  worms_lib.set_grace(force, {awake = true, first_hunt_done = true}, {"first_hunt"})
  worms_lib.set_worm_off(force, false)
  worms_lib.set_spawn_dir(force, 2)
  -- Statistik der Test-Force neu anlegen lassen (stats_for legt killed mit an; Schritt 1 prüft killed = 0).
  storage.worm_stats[force.index] = nil
  d.fields = {}
  for number = 1, 12 do
    local col = (number - 1) % 3 + 1
    local row = math.floor((number - 1) / 3) + 1
    local center = {x = d.origin.x + COLS[col] + 0.5, y = d.origin.y + ROWS[row] + 0.5}
    d.fields[number] = {center = center, box = box_of(center, {x = FIELD_HALF, y = FIELD_HALF})}
  end
  d.prep = 1
  d.reg = {queue = {}}
  for _, number in ipairs(REGULAR_ORDER) do table.insert(d.reg.queue, number) end
  d.open = {}
  lanes_init(d)
  d.foreign = regular_count({[force.index] = true})
  if d.foreign > 0 then
    tb.log(run, "INFO", d.foreign .. " reguläre Jagden anderer Forces laufen: Schritt 12, danach 10, startet erst, wenn eine frei wird")
  end
  pcall(function() force.chart(surface, d.box) end)
  if tb.player(run) then tb.watch(run, nil, at(d.origin, 0, -20)) end
  tb.log(run, "INFO", "Fünfzehn Schritte mit dem echten Sandwurm (Force " .. T21_FORCE .. ", wach, Startrichtung Nordost) in zwölf Feldern,"
    .. " Schritte 2 bis 12 in drei Wellen, Dauer etwa 3,5 min Spielzeit. Je Schritt eine OK/FEHLER-Zeile, Einzelwerte in der Datei.")
  tb.log(run, "INFO", string.format("Standardwahlen (Max 27.10.): CRUSH_SPARES_VEHICLES %s, KILL_RESCUES %s, SPRINT %s, NO_ROUTE_BITE %s",
    tostring(worms_lib.CRUSH_SPARES_VEHICLES), tostring(worms_lib.KILL_RESCUES), tostring(sandworm_lib.SPRINT), tostring(worms_lib.NO_ROUTE_BITE)))
end

local function t21_tick(run, tb)
  local d = run.data
  if not d.lanes or d.done_all then return end
  -- Ein Feld je Tick vorbereiten (Plan 6: 160 000 Kacheln je Tick).
  if d.prep <= 12 then
    tb.prepare(d.fields[d.prep].center, FIELD_HALF)
    d.prep = d.prep + 1
    if d.prep > 12 then d.open.A = true end
    return
  end
  for number = 1, STEP_COUNT do
    local s = d["s" .. number]
    for _, key in ipairs({"watch", "watch2"}) do
      local w = s[key]
      if w and not w.ended and not w.broken then
        local ok, err = pcall(watch_tick, run, tb, d, w)
        if not ok then
          w.broken = true
          tb.log(run, "FEHLER", number .. ") Skriptfehler in der Beobachtung: " .. tostring(err))
        end
      end
    end
  end
  if d.open.A and not d.open.B and wave_started(d, WAVE_DEBUG.A) and sandworm_lib.counted(true) == 0 then
    d.open.B = true
    tb.log(run, "INFO", "Welle B (Schritte 6, 7, 8) ab Tick " .. (game.tick - run.started))
  end
  if d.open.B and not d.open.C and wave_started(d, WAVE_DEBUG.B) and sandworm_lib.counted(true) == 0 then
    d.open.C = true
    tb.log(run, "INFO", "Welle C (Schritte 9, 11) ab Tick " .. (game.tick - run.started))
  end
  if d.open.C and not d.open.T13 and all_done(d, 2, 12) then
    d.open.T13 = true
    tb.log(run, "INFO", "Schritte 13 bis 15 ab Tick " .. (game.tick - run.started))
  end
  if d.open.T13 and not d.open.T14 and d.lanes[13].done then d.open.T14 = true end
  if d.open.T14 and not d.open.T15 and d.lanes[14].done then d.open.T15 = true end
  for number = 1, STEP_COUNT do
    if d.open[WAVE[number]] then lane_step(run, tb, d, T21_STEPS, number) end
  end
  if all_done(d, 1, STEP_COUNT) then
    d.done_all = true
    tb.finish(run, summary(run, STEP_COUNT))
  end
end

local function t21_on_event(run, tb, name, event)
  local d = run.data
  if not d.lanes then return end
  if name == "entity_died" then
    note_death(d, event)
  elseif name == "segmented_unit_died" then
    note_unit(d, "died", event)
  elseif name == "segmented_unit_destroyed" then
    note_unit(d, "destroyed", event)
  elseif name == "script_path" then
    local path = event.path
    d.path_events[event.id] = {tick = event.tick, n = path and #path or nil, later = event.try_again_later == true}
  elseif name == "spider_command_completed" then
    local vehicle = event.vehicle
    if valid(vehicle) and vehicle.unit_number then d.arrived[vehicle.unit_number] = event.tick end
  end
end

-- Jagden der Force abbrechen (Würmer still weg), Schritte aufräumen, Waisen und eigene Würmer weg, Wärme und Ruhe der
-- Fläche löschen, Prüfstand-Merker, Schonfrist und Pause zurück.
local function t21_cleanup(run, tb)
  local d = run.data
  local force = d.force
  if not valid(force) then return end
  local surface = tb.surface()
  pcall(abort_hunts, {[force.index] = true})
  if d.lanes then
    for number in pairs(d.lanes) do pcall(tidy, d["s" .. number]) end
  end
  for _, unit in ipairs(d.units or {}) do
    if valid(unit) then pcall(function() unit.destroy{} end) end
  end
  pcall(sandworm_lib.sweep, {surface})
  if d.box then
    local left = read(function() return sandworms_in(surface, d.box) end) or 0
    if left > 0 then tb.log(run, "FEHLER", left .. " arrakis-sandworm-* nach dem Aufräumen im Bereich von T21") end
    pcall(clear_area, surface, d.box)
  end
  worms_lib.set_worm_off(force, false)
  worms_lib.set_spawn_dir(force, nil)
  vibration_lib.testbench_disable(force)
  if d.saved then
    worms_lib.grace_restore(force, d.saved.grace)
    worms_lib.set_paused(d.saved.paused)
  end
  worms_lib.ensure_force()
end

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
  d.flyer = valid(d.flyer) and d.flyer or new_flyer(run, tb, d, d.made, at(base, 4, 0), {force = d.force, coal = 50})
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
  T21 =
  {
    title = "Sandwurm: echter Code",
    timeout = 300 * 60,
    interactive = false,
    confirm = nil,
    start = t21_start,
    tick = t21_tick,
    on_event = t21_on_event,
    cleanup = t21_cleanup
  },
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
