-- Ornithopter (Phase 3c, docs/plan-3c.md 4.1 bis 4.12 und 4.15): Datensätze, Bedienung (Taste, Shortcut, Knopf),
-- Ankoppeln, Anheben mit Notstart, Sitze, Absetzen, Tempo-Sticker, Lastbild, Absturz, Landesuche mit Warteliste,
-- Pflege und /arrakis-uninstall. Bibliothek für __core__/lualib/event_handler. Daten nur in storage (Schema 2, siehe
-- scripts/migrate.lua), Schlüssel ist unit_number. Ereignisse kommen ungefiltert: Jeder Handler prüft zuerst den Namen
-- und kehrt sofort zurück. Die Modultabelle heißt lib (tools/check/api_names.py hält flyer für LuaEntity); andere
-- Dateien binden sie als flyer_lib.
--
-- Getragen wird so (DOC 4.2): Der Ernter steht gesperrt (Zustand carried, scripts/harvester.lua) auf der Ablage
-- arrakis-hold (scripts/hold.lua), am Ornithopter hängen sein Bild und sein Schatten. Jeder Fall gehört genau einem
-- Modul (Plan 4.1): Die Reihenfolge der Handler zwischen Modulen ist nicht zugesichert (event_handler fasst sie je
-- Ereignis mit pairs zusammen). Den Träger eines Ernters findet dieses Modul deshalb immer über storage.flyers
-- (cargo == un), nie über den Datensatz des Ernters.
--
-- Datensatz storage.flyers[un] (Plan 4.2):
--   un, entity, kind = "ornithopter", cargo = harvester_un|nil,
--   coupling = {harvester = harvester_un, start_tick, done_tick, player_index|nil}|nil,
--   renders = {image, shadow, ring}, sticker = LuaEntity|nil, image_index = 0..15|nil,
--   last_cargo = LuaEntity|nil, last_toggle_tick
-- storage.couplings[flyer_un] = true (laufende Kopplungen, 10-Tick-Takt)
-- storage.stranded[harvester_un] = {crash_pos = {surface, x, y}|nil, damage = true|nil, reason = "crash"|"returned"}
--
-- Zustände (Plan 4.3): leer (cargo und coupling nil), koppelt (coupling), beladen (cargo).
-- [Un] markiert ungeprüftes Engine-Verhalten (Plan 4.16).

local harvester = require("scripts.harvester")
local hold = require("scripts.hold")

local lib = {}

local NAME = "arrakis-ornithopter"
local HARVESTER = harvester.NAME
local PROBE = "arrakis-harvester-probe"
local CARRY_INPUT = "arrakis-carry-toggle"
local CARRY_SHORTCUT = "arrakis-carry"
local REMOTE_ITEM = "spidertron-remote"
local SPICE = "spice-sand"
local ARRAKIS = "arrakis"
local NAUVIS = "nauvis"
local IMAGE_SPRITE = "arrakis-harvester-carried-"
local SHADOW_SPRITE = "arrakis-harvester-carried-shadow-"

-- Name des Ornithopter-Prototyps.
lib.NAME = NAME
-- Ankoppeln (Ticks); geprüft im 10-Tick-Takt, also 120 bis 129 Ticks.
lib.COUPLE_TICKS = 120
-- Ankoppel- und Suchabstand Flieger ↔ Ernter (Kacheln, Mittelpunkte).
lib.COUPLE_RANGE = 4
-- Entprellen: zweiter Aufruf für denselben Flieger innerhalb so vieler Ticks wird ignoriert.
lib.DEBOUNCE = 15
-- Absturzschaden als Anteil der Höchstgesundheit (direkt geschrieben, nicht über damage(): Die Panzer-Resistenzen
-- ließen aus 600 nur 110 LP übrig, Plan 1).
lib.CRASH_DAMAGE = 0.3
-- Suchradien der Landesuche um Todesstelle und Abhebepunkt (Kacheln); nie 0, sonst sucht die Engine ohne Ende
-- (A23 classes.d.ts:20536).
lib.SEARCH_RADII = {6, 16, 32}
-- Suchradien um den Startpunkt der Force (Kacheln).
lib.SPAWN_RADII = {6, 16, 32, 64}
-- Warteliste (retry_stranded): Jeder Versuch sucht nur bis zu diesem Radius, jeder RETRY_FULL_EVERY-te (also alle 10 s)
-- mit allen. Ohne Treffer prüft find_non_colliding_position jede Stelle im Kreis, bei Schrittweite 0,5 etwa
-- π · (r / 0,5)²: mit allen Stufen und Radien gut 10^5 Stellen je Ernter, bis 16 Kacheln gut 11 000.
lib.RETRY_RADIUS = 16
lib.RETRY_FULL_EVERY = 10
-- Suchradius beim Absetzen (Kacheln, Plan 4.8).
lib.DROP_RADIUS = 6
-- Schrittweite von find_non_colliding_position (Kacheln).
lib.PRECISION = 0.5
-- „In den Ernter steigen“ nur bis zu diesem Abstand (Kacheln, Plan 4.7).
lib.BOARD_RANGE = 6
-- Tempo-Sticker (Plan 1: 0,52 → 8 Kacheln/s leer, 0,364 → 5,6 beladen) [U6].
lib.STICKER_EMPTY = "arrakis-ornithopter-empty"
lib.STICKER_LOADED = "arrakis-ornithopter-loaded"
-- Ein Sticker mit weniger Restzeit wird ersetzt (Ticks; halbe Laufzeit von 216000).
lib.STICKER_MIN_TTL = 108000
-- Lastbild und Schatten relativ zum Bodenpunkt des Fliegers (Kacheln, Plan 4.12) [U27].
lib.IMAGE_OFFSET = {0, -1.5}
lib.SHADOW_OFFSET = {1, 1}

local OWN_STICKER = {[lib.STICKER_EMPTY] = true, [lib.STICKER_LOADED] = true}
local RING_COLOR = {r = 0.45, g = 1, b = 0.55, a = 0.8}
-- Grund → Hinweis (toggle_carry).
local REASON_HINT =
{
  foreign = "hint-foreign",
  busy = "hint-coupling-busy",
  no_harvester = "hint-no-harvester"
}

-- Oberflächen, die gerade gelöscht werden (nur während on_pre_surface_deleted; nie in storage).
local deleting = {}

-- Hilfen ----------------------------------------------------------------------------------------

local function is_flyer(entity)
  return entity and entity.valid and entity.name == NAME
end

local function is_harvester(entity)
  return entity and entity.valid and entity.name == HARVESTER
end

local function distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function gps(surface, position)
  return string.format("[gps=%d,%d,%s]", math.floor(position.x), math.floor(position.y), surface.name)
end

-- Ort {surface = index, x, y} als GPS-Text; fehlt die Oberfläche, nur die Koordinaten.
local function gps_of(place)
  if not place then return "?" end
  local surface = game.get_surface(place.surface)
  if surface then return gps(surface, place) end
  return string.format("%d, %d", math.floor(place.x), math.floor(place.y))
end

local function describe(entity)
  if not (entity and entity.valid) then return "ungültig" end
  return entity.name .. " " .. tostring(entity.unit_number)
end

-- Hinweis als fliegender Text am Objekt; in der Fernsicht oder auf einer anderen Oberfläche am Mauszeiger.
local function hint(player, entity, key, param)
  if not (player and player.valid) then return end
  local text = {"arrakis-message." .. key}
  if param ~= nil then text = {"arrakis-message." .. key, param} end
  if entity and entity.valid and player.controller_type ~= defines.controllers.remote
      and player.surface.index == entity.surface.index then
    player.create_local_flying_text{text = text, position = entity.position, surface = entity.surface}
  else
    player.create_local_flying_text{text = text, create_at_cursor = true}
  end
end

-- Steht die Entity auf der Ablage?
local function on_hold(entity)
  return entity.surface.name == hold.NAME
end

-- Darf auf dieser Oberfläche gelandet werden? Nicht auf der Ablage, nicht auf einer, die gerade gelöscht wird.
local function usable(surface)
  return surface ~= nil and surface.valid and not deleting[surface.index] and surface.name ~= hold.NAME
end

local function surface_by_index(index)
  local surface = index and game.get_surface(index)
  if usable(surface) then return surface end
  return nil
end

-- Render-Objekte -------------------------------------------------------------------------------

local function destroy_render(record, key)
  local object = record.renders[key]
  if object and object.valid then object.destroy() end
  record.renders[key] = nil
end

local function render_valid(record, key)
  local object = record.renders[key]
  return object ~= nil and object.valid
end

-- Lastbild und Schatten am Flieger; zeichnet nur fehlende neu [U16]. Kein forces: alle sehen sie (Plan 1).
-- smoke liegt unter dem Rumpf (air-object) und über allem am Boden; der Schatten auf floor (Ebenen wie T9).
local function draw_cargo(record)
  local flyer = record.entity
  local index = record.image_index or 0
  if not render_valid(record, "shadow") then
    record.renders.shadow = rendering.draw_sprite{
      sprite = SHADOW_SPRITE .. index,
      target = {entity = flyer, offset = lib.SHADOW_OFFSET},
      surface = flyer.surface,
      render_layer = "floor"
    }
  end
  if not render_valid(record, "image") then
    record.renders.image = rendering.draw_sprite{
      sprite = IMAGE_SPRITE .. index,
      target = {entity = flyer, offset = lib.IMAGE_OFFSET},
      surface = flyer.surface,
      render_layer = "smoke"
    }
  end
end

-- Ankoppelring um den Ernter, Fortschritt 0 → 1; sieht nur die Force des Fliegers.
local function draw_ring(record, entity, fraction)
  local angle = math.max(0.01, 2 * math.pi * math.min(1, math.max(0, fraction)))
  local ring = record.renders.ring
  if ring and ring.valid then
    ring.angle = angle
    return
  end
  record.renders.ring = rendering.draw_arc{
    color = RING_COLOR,
    max_radius = 3.2,
    min_radius = 2.8,
    start_angle = -math.pi / 2,
    angle = angle,
    target = entity,
    surface = entity.surface,
    forces = {record.entity.force}
  }
end

-- Tempo-Sticker (Plan 4.9) --------------------------------------------------------------------------

-- Genau ein eigener Sticker je Flieger, Name nach Zustand. Der gemerkte taugt, wenn er gültig ist, am Flieger hängt
-- (sticked_to, A23 classes.d.ts:8552), richtig heißt und noch lange genug lebt (time_to_live nur lesen [U9]).
-- Jeder andere eigene Sticker in flyer.stickers (A23 classes.d.ts:8564) wird zerstört; 0,52 · 0,364 ergäbe sonst
-- etwa 2,9 Kacheln/s. Fremde Sticker (z. B. Verlangsamungskapsel) bleiben.
local function ensure_sticker(record)
  local flyer = record.entity
  if not flyer.valid then return end
  local wanted = record.cargo and lib.STICKER_LOADED or lib.STICKER_EMPTY
  local sticker = record.sticker
  local keep = nil
  if sticker and sticker.valid and sticker.name == wanted and sticker.sticked_to == flyer
      and sticker.time_to_live >= lib.STICKER_MIN_TTL then
    keep = sticker
  end
  for _, other in pairs(flyer.stickers or {}) do
    if other.valid and OWN_STICKER[other.name] and other ~= keep then other.destroy() end
  end
  if keep then return end
  if sticker and sticker.valid then sticker.destroy() end
  record.sticker = flyer.surface.create_entity{name = wanted, position = flyer.position, target = flyer, force = flyer.force}
end

-- Datensätze ------------------------------------------------------------------------------------

-- Datensatz zur Entity oder nil.
function lib.get(entity)
  if not (entity and entity.valid) then return nil end
  local flyers = storage.flyers
  return flyers and flyers[entity.unit_number]
end

-- Ornithopter leer eintragen (Sticker leer, abbaubar) und für on_object_destroyed anmelden; gibt den Datensatz zurück.
-- Wer einen Ornithopter braucht, ruft get(entity) or register(entity): So bekommt auch einer, der ohne raise_built
-- entstand, beim ersten Kontakt Datensatz und Sticker (Plan 4.1).
function lib.register(entity)
  if not is_flyer(entity) then return nil end
  local un = entity.unit_number
  local record = storage.flyers[un]
  if record then return record end
  record =
  {
    un = un,
    entity = entity,
    kind = "ornithopter",
    renders = {},
    last_toggle_tick = 0
  }
  storage.flyers[un] = record
  storage.reg[script.register_on_object_destroyed(entity)] = {kind = "flyer", un = un}
  if not entity.minable_flag then entity.minable_flag = true end
  ensure_sticker(record)
  return record
end

-- Kopplung beenden: Ring weg, aus storage.couplings (Schlüssel ist immer der Flieger).
local function end_coupling(record)
  record.coupling = nil
  storage.couplings[record.un] = nil
  destroy_render(record, "ring")
end

-- Flieger, der gerade an diesen Ernter koppelt, oder nil.
local function coupling_of(harvester_un)
  for flyer_un in pairs(storage.couplings) do
    local record = storage.flyers[flyer_un]
    if record and record.coupling and record.coupling.harvester == harvester_un then return record end
  end
  return nil
end

-- Träger dieses Ernters über storage.flyers (cargo == un) oder nil (Plan 4.1).
local function carrier_of(harvester_un)
  for _, record in pairs(storage.flyers) do
    if record.cargo == harvester_un and record.entity.valid then return record end
  end
  return nil
end

-- Last lösen ohne den Flieger anzufassen (er wird gleich ausgetragen): Eintrag und Bilder weg.
local function release_cargo(record)
  record.cargo = nil
  record.image_index = nil
  destroy_render(record, "image")
  destroy_render(record, "shadow")
end

-- Flieger leeren: Last lösen, abbaubar, Sticker leer.
local function clear_cargo(record)
  release_cargo(record)
  local flyer = record.entity
  if not flyer.valid then return end
  if not flyer.minable_flag then flyer.minable_flag = true end
  ensure_sticker(record)
end

-- Flieger austragen: Datensatz, Kopplung, Bilder und eigener Sticker weg. Die Last bleibt im Datensatz stehen,
-- damit der Aufrufer sie danach absetzen kann (return_cargo, crash).
local function forget_flyer(record)
  storage.flyers[record.un] = nil
  end_coupling(record)
  destroy_render(record, "image")
  destroy_render(record, "shadow")
  local sticker = record.sticker
  if sticker and sticker.valid then sticker.destroy() end
  record.sticker = nil
end

-- Landesuche (Plan 4.10) ----------------------------------------------------------------------------

-- Passt die Probe genau hier hin (A23 classes.d.ts:20060–20085)? Die Probe hat die Maske des Ernters und einen
-- Kasten von ±1,6 Kacheln, der jede Ausrichtung des Ernters deckt [U19].
local function probe_fits(surface, position, force)
  return surface.can_place_entity{
    name = PROBE,
    position = position,
    force = force,
    build_check_type = defines.build_check_type.manual
  }
end

-- Nächste freie Stelle für die Probe in radius um center, nur in erzeugten Chunks; sonst nil.
local function free_spot(surface, center, radius)
  local position = surface.find_non_colliding_position(PROBE, center, radius, lib.PRECISION)
  if not position then return nil end
  if not surface.is_chunk_generated({x = math.floor(position.x / 32), y = math.floor(position.y / 32)}) then return nil end
  return position
end

-- Eine Stufe: zuerst genau center, dann je Radius die nächste freie Stelle; jeder Treffer per teleport. Ein Teleport
-- zwischen Oberflächen prüft keine Kollision (A23 classes.d.ts:5476), deshalb nur Stellen, die die Probe frei fand.
-- max_radius: größere Radien auslassen (Warteliste); nil: alle.
local function try_stage(entity, surface, center, radii, max_radius)
  local position = {x = center.x or center[1], y = center.y or center[2]}
  if probe_fits(surface, position, entity.force) and entity.teleport(position, surface) then return position end
  for _, radius in ipairs(radii) do
    if max_radius and radius > max_radius then break end
    local spot = free_spot(surface, position, radius)
    if spot and entity.teleport(spot, surface) then return spot end
  end
  return nil
end

-- Chunks um den Startpunkt erzeugen, aber nur, wenn einer fehlt (Radius 2 Chunks wie request_to_generate_chunks,
-- A23 classes.d.ts:20796, :20707): force_generate_chunk_requests erzeugt sofort jede offene Anfrage der Oberfläche,
-- auch die von Spielern und Radar, und die Warteliste fragt jede Sekunde.
local SPAWN_CHUNKS = 2
local function generate_spawn_chunks(surface, spawn)
  local cx, cy = math.floor(spawn.x / 32), math.floor(spawn.y / 32)
  for dx = -SPAWN_CHUNKS, SPAWN_CHUNKS do
    for dy = -SPAWN_CHUNKS, SPAWN_CHUNKS do
      if not surface.is_chunk_generated({x = cx + dx, y = cy + dy}) then
        surface.request_to_generate_chunks(spawn, SPAWN_CHUNKS)
        surface.force_generate_chunk_requests()
        return
      end
    end
  end
end

-- Oberfläche für Stufe 3: die des Abhebepunkts, fehlt sie, Arrakis, sonst nauvis.
local function spawn_surface(h)
  local surface = surface_by_index(h.lift_pos and h.lift_pos.surface)
  if surface then return surface end
  surface = game.get_surface(ARRAKIS)
  if usable(surface) then return surface end
  surface = game.get_surface(NAUVIS)
  if usable(surface) then return surface end
  return nil
end

-- Sucht und teleportiert; gibt Oberfläche und Stufe (1 Todesstelle, 2 Abhebepunkt, 3 Startpunkt) zurück oder nil.
-- max_radius wie bei try_stage.
local function search_landing(h, crash_pos, max_radius)
  local entity = h.entity
  if crash_pos then
    local surface = surface_by_index(crash_pos.surface)
    if surface and try_stage(entity, surface, crash_pos, lib.SEARCH_RADII, max_radius) then return surface, 1 end
  end
  local lift = h.lift_pos
  if lift then
    local surface = surface_by_index(lift.surface)
    if surface and try_stage(entity, surface, lift, lib.SEARCH_RADII, max_radius) then return surface, 2 end
  end
  local surface = spawn_surface(h)
  if surface then
    -- Startpunkt der Force (A23 classes.d.ts:11216); Chunks vorher erzeugen, sonst findet die Probe dort nichts.
    local spawn = entity.force.get_spawn_position(surface)
    generate_spawn_chunks(surface, spawn)
    if try_stage(entity, surface, spawn, lib.SPAWN_RADII, max_radius) then return surface, 3 end
  end
  return nil
end

-- Landesuche für einen Ernter ohne Träger; no_wait: scheitert sie, nicht in die Warteliste (Löschen der Ablage).
-- max_radius: nur die Warteliste setzt ihn (RETRY_RADIUS), sonst nil.
local function land(h, crash_pos, damage, no_wait, max_radius)
  local entity = h and h.entity
  if not (entity and entity.valid) then
    if h then storage.stranded[h.un] = nil end
    return false
  end
  local un = h.un
  local surface, stage = search_landing(h, crash_pos, max_radius)
  if surface then
    harvester.land(h)
    if damage then
      -- max_health enthält die Qualität (A23 classes.d.ts:8185) [U23]; mindestens 1 LP: Totalverlust gibt es nur
      -- durch den Wurm (3d1).
      entity.health = math.max(1, entity.health - lib.CRASH_DAMAGE * entity.max_health)
    end
    storage.stranded[un] = nil
    local key = "msg-returned"
    if damage then key = "msg-crash" elseif stage == 3 then key = "msg-returned-fallback" end
    entity.force.print({"arrakis-message." .. key, gps(surface, entity.position)})
    return true
  end
  if no_wait then return false end
  -- Kein Landeplatz: bleibt getragen auf der Ablage, ohne Träger, und wartet (retry_stranded jede Sekunde).
  h.carried_by = nil
  local known = storage.stranded[un] ~= nil
  storage.stranded[un] = {crash_pos = crash_pos, damage = damage and true or nil, reason = damage and "crash" or "returned"}
  if not known then
    local last = crash_pos or h.lift_pos
    log("Arrakis: kein Landeplatz für Spice-Ernter " .. un .. ", wartet auf der Ablage (zuletzt bei " .. gps_of(last) .. ")")
    entity.force.print({"arrakis-message.msg-stranded", gps_of(last)})
  end
  return false
end

-- Landesuche ohne Träger (Plan 4.10): Absturz (crash_pos, damage), „anders entfernt“, Waisen, gelöschte Oberflächen
-- und die Warteliste. Gelungen: mobil, ggf. 30 % Schaden, Meldung, true. Sonst storage.stranded, false.
function lib.land_cargo(h, crash_pos, damage)
  return land(h, crash_pos, damage, false)
end

-- Ein getragener Ernter steht nicht mehr auf der Ablage (fremdes Skript): am jetzigen Ort landen, Träger leeren.
local function land_here(h)
  local un = h.un
  for _, record in pairs(storage.flyers) do
    if record.cargo == un then clear_cargo(record) end
  end
  storage.stranded[un] = nil
  harvester.land(h)
  log("Arrakis: getragener Spice-Ernter " .. un .. " außerhalb der Ablage gefunden, dort abgesetzt")
end

-- Warteliste (wie der 60-Tick-Takt): jeden Eintrag noch einmal landen; ohne gültigen Ernter oder Datensatz streichen.
-- Jede Sekunde bis RETRY_RADIUS, jede RETRY_FULL_EVERY-te Sekunde mit allen Radien. Der Zähler kommt aus dem Tick: kein
-- storage, für alle Spieler gleich. Die Stufen gelten je Versuch in ihrer Reihenfolge; ein kurzer Versuch kann also am
-- Startpunkt landen, wo ein voller weiter weg an der Todesstelle fände (beides ist ein freier Platz).
function lib.retry_stranded()
  local stranded = storage.stranded
  if next(stranded) == nil then return end
  local max_radius = lib.RETRY_RADIUS
  if math.floor(game.tick / 60) % lib.RETRY_FULL_EVERY == 0 then max_radius = nil end
  local harvesters = storage.harvesters
  for un, entry in pairs(stranded) do
    local h = harvesters[un]
    if not (h and h.entity.valid and h.state == "carried") then
      stranded[un] = nil
    elseif not on_hold(h.entity) then
      land_here(h)
    else
      land(h, entry.crash_pos, entry.damage, false, max_radius)
    end
  end
end

-- Sitze (Plan 4.7) ----------------------------------------------------------------------------------

-- Spieler zu einem Insassen (LuaPlayer oder Spielfigur, A23 classes.d.ts:6838). figur.player und associated_player
-- sind nur die Abkürzung: In der Fernsicht ist figur.player nicht verlässlich gesetzt (vgl. runner.lua, Spielerfiguren).
local function owner_of(occupant)
  if occupant.object_name == "LuaPlayer" then return occupant end
  local player = occupant.player or occupant.associated_player
  if player then return player end
  for _, p in pairs(game.players) do
    if p.character == occupant then return p end
  end
  return nil
end

-- Sitzt dieser Insasse auf dem Platz? get_driver kann die Figur oder den Spieler liefern.
local function sits(actual, occupant, owner)
  if not actual then return false end
  if actual == occupant then return true end
  if not owner then return false end
  if actual.object_name == "LuaPlayer" then return actual.index == owner.index end
  return owner.character ~= nil and owner.character == actual
end

-- Erster freier Sitz, Pilot zuerst.
local function free_seat(vehicle)
  if vehicle.get_driver() == nil then return "driver" end
  if vehicle.get_passenger() == nil then return "passenger" end
  return nil
end

-- Setzt den Insassen auf den Platz und liest zurück [U14]. pcall: Lehnt die Engine das Setzen mit einem Fehler ab,
-- greift der Rückfall, statt das Anheben halb fertig abzubrechen (der Ernter stünde dann ohne Träger auf der Ablage).
local function put(vehicle, seat, occupant, owner)
  pcall(function()
    if seat == "driver" then vehicle.set_driver(occupant) else vehicle.set_passenger(occupant) end
  end)
  local actual
  if seat == "driver" then actual = vehicle.get_driver() else actual = vehicle.get_passenger() end
  return sits(actual, occupant, owner)
end

-- Einen Insassen in den Flieger setzen. Gibt die Stufe zurück (0 gleich gesetzt, 1 nach Teleport an den Flieger)
-- oder nil (bleibt am Boden, Hinweis an ihn bzw. den Bediener).
local function seat_one(flyer, occupant, operator)
  if not occupant.valid then return nil end
  local owner = owner_of(occupant)
  -- Fernsicht zuerst verlassen (DOC 5.5; CL:870) [U15]; fuhr er den Flieger fern, ist der Pilotensitz danach frei.
  if owner and owner.controller_type == defines.controllers.remote then owner.exit_remote_view() end
  local seat = free_seat(flyer)
  if seat and put(flyer, seat, occupant, owner) then return 0 end
  seat = free_seat(flyer)
  local name = owner and owner.name or (occupant.object_name == "LuaEntity" and occupant.name) or "?"
  if seat and occupant.object_name == "LuaEntity" and occupant.valid then
    -- Rückfall Stufe 1: Figur an den Flieger stellen (gleiche Oberfläche, höchstens 4 Kacheln) und noch einmal setzen.
    occupant.teleport(flyer.position)
    if put(flyer, seat, occupant, owner) then
      log("Arrakis: Insasse " .. name .. " erst nach dem Teleport an den Ornithopter gesetzt (Stufe 1)")
      return 1
    end
  end
  log("Arrakis: Insasse " .. name .. " bleibt am Boden (" .. (seat and "Setzen scheitert auch in Stufe 1" or "kein Sitz frei") .. ")")
  local text_name = owner and owner.name or (occupant.object_name == "LuaEntity" and occupant.localised_name) or "?"
  hint(owner or operator, flyer, "hint-seat-full", text_name)
  return nil
end

-- Fahrer zuerst, dann Beifahrer; gibt die Stufen je Insasse zurück ({driver = 0|1|nil, passenger = …}).
local function seat_occupants(flyer, driver, passenger, operator)
  local result = {}
  if driver then result.driver = seat_one(flyer, driver, operator) end
  if passenger then result.passenger = seat_one(flyer, passenger, operator) end
  return result
end

-- Fenster des Ernters bei allen Spielern schließen (harvester-gui räumt in on_gui_closed auf).
local function close_windows(entity)
  for _, player in pairs(game.connected_players) do
    local opened = player.opened
    if opened and type(opened) ~= "number" and opened.object_name == "LuaEntity" and opened == entity then
      player.opened = nil
    end
  end
end

-- Ankoppeln und Anheben (Plan 4.6) -----------------------------------------------------------------

-- Warum dieser Ernter nicht angekoppelt werden kann ("foreign", "busy", "no_harvester") oder nil.
local function candidate_problem(flyer, entity)
  if not is_harvester(entity) then return "no_harvester" end
  if entity.force.index ~= flyer.force.index then return "foreign" end
  if entity.surface.index ~= flyer.surface.index then return "no_harvester" end
  if distance(entity.position, flyer.position) > lib.COUPLE_RANGE then return "no_harvester" end
  local h = harvester.get(entity)
  if h and h.state == "carried" then return "busy" end
  if coupling_of(entity.unit_number) then return "busy" end
  return nil
end

local function start_coupling(record, entity, player)
  local h = harvester.get(entity) or harvester.register(entity)
  if not h then return false, "no_harvester" end
  local tick = game.tick
  record.coupling =
  {
    harvester = h.un,
    start_tick = tick,
    done_tick = tick + lib.COUPLE_TICKS,
    player_index = player and player.index
  }
  storage.couplings[record.un] = true
  draw_ring(record, entity, 0)
  hint(player, entity, "hint-coupling-start")
  return true, "coupling"
end

-- Anheben, wenn die Kopplung fertig ist (Plan 4.6, Reihenfolge fest). Die Kopplung endet hier in jedem Fall.
local function lift(record)
  local flyer = record.entity
  local c = record.coupling
  local player = c.player_index and game.get_player(c.player_index)
  local h = storage.harvesters[c.harvester]
  local entity = h and h.entity
  end_coupling(record)
  -- 1. Ernter gültig, eigene Force, nicht getragen; Platz in der Ablage.
  if not (entity and entity.valid and entity.force.index == flyer.force.index and h.state ~= "carried") then
    hint(player, flyer, "hint-coupling-aborted")
    return false
  end
  local hold_surface = hold.ensure()
  local slot = hold.take_slot()
  if not slot then
    hint(player, flyer, "hint-hold-full")
    return false
  end
  -- 2. Fenster schließen.
  close_windows(entity)
  -- 3. Insassen merken und herausnehmen (A23 classes.d.ts:7402, :7470–7475) [U14]; sonst reisten sie mit auf die Ablage.
  local driver = entity.get_driver()
  local passenger = entity.get_passenger()
  if driver then entity.set_driver(nil) end
  if passenger then entity.set_passenger(nil) end
  -- 4. Notstart und sperren (aufbauend, aufgebaut, einpackend → mobil; angedockt → abgedockt; dann carried).
  local origin = entity.surface
  local position = entity.position
  local orientation = entity.orientation
  harvester.lift(h, record.un, {surface = origin.index, x = position.x, y = position.y})
  -- 5. Auf den Stellplatz [U13]; Ladung, Treibstoff, Gesundheit, Qualität, Farbe und Ausrichtung bleiben (RUN055 T3 b).
  if not entity.teleport(slot, hold_surface) then
    harvester.land(h)
    if driver and driver.valid then pcall(function() entity.set_driver(driver) end) end
    if passenger and passenger.valid then pcall(function() entity.set_passenger(passenger) end) end
    log("Arrakis FEHLER: Teleport auf die Ablage gescheitert (" .. describe(entity) .. ")")
    hint(player, flyer, "hint-lift-failed")
    return false
  end
  -- 6. Insassen in den Flieger (Plan 4.7).
  local seats = seat_occupants(flyer, driver, passenger, player)
  -- 7. Flieger beladen.
  record.cargo = h.un
  record.image_index = math.floor(orientation * 16 + 0.5) % 16
  flyer.minable_flag = false
  ensure_sticker(record)
  draw_cargo(record)
  return true, seats
end

-- Kopplung im 10-Tick-Takt prüfen: ungültig, andere Oberfläche oder zu weit → Abbruch; Zeit um → Anheben.
local function update_coupling(record, tick)
  local c = record.coupling
  if not c then
    storage.couplings[record.un] = nil
    return
  end
  local flyer = record.entity
  local player = c.player_index and game.get_player(c.player_index)
  local h = storage.harvesters[c.harvester]
  local entity = h and h.entity
  if not (flyer.valid and entity and entity.valid) or h.state == "carried" or record.cargo then
    end_coupling(record)
    hint(player, flyer, "hint-coupling-aborted")
    return
  end
  if entity.surface.index ~= flyer.surface.index or distance(entity.position, flyer.position) > lib.COUPLE_RANGE then
    end_coupling(record)
    hint(player, flyer, "hint-coupling-lost")
    return
  end
  if tick >= c.done_tick then
    lift(record)
    return
  end
  draw_ring(record, entity, (tick - c.start_tick) / math.max(1, c.done_tick - c.start_tick))
end

-- Alle laufenden Kopplungen (wie der 10-Tick-Takt); tick ist sonst game.tick.
function lib.update_couplings(tick)
  local couplings = storage.couplings
  if next(couplings) == nil then return end
  tick = tick or game.tick
  local flyers = storage.flyers
  for un in pairs(couplings) do
    local record = flyers[un]
    if not record then
      couplings[un] = nil
    else
      update_coupling(record, tick)
    end
  end
end

-- Absetzen (Plan 4.8) ------------------------------------------------------------------------------

-- Pflege eines Datensatzes (vorwärts deklariert, steht unten).
local care

-- Setzt die Last an der Fliegerposition ab (Probe, sonst Suche im Radius 6). Gibt ok, Grund zurück
-- ("dropped", "no_space", "lost"). quiet: ohne Hinweis (Löschen der Ablage, /arrakis-uninstall).
function lib.drop(record, player, quiet)
  local flyer = record and record.entity
  if not (flyer and flyer.valid) then return false, "lost" end
  local h = record.cargo and storage.harvesters[record.cargo]
  local entity = h and h.entity
  if not (entity and entity.valid and h.state == "carried") then
    care(record)
    return false, "lost"
  end
  local surface = flyer.surface
  local center = flyer.position
  local position = nil
  if probe_fits(surface, center, flyer.force) then
    position = center
  else
    position = free_spot(surface, center, lib.DROP_RADIUS)
  end
  if not position then
    if not quiet then hint(player, flyer, "hint-no-space") end
    return false, "no_space"
  end
  -- Ausrichtung bleibt beim Teleport erhalten.
  if not entity.teleport(position, surface) then
    log("Arrakis FEHLER: Teleport zum Absetzen gescheitert (" .. describe(entity) .. ")")
    if not quiet then hint(player, flyer, "hint-no-space") end
    return false, "no_space"
  end
  -- Der Stellplatz ist damit frei (Plan 4.11). Steht er ≤ 4 Kacheln an einer freien Annahme, dockt er nach 2 s an.
  harvester.land(h)
  clear_cargo(record)
  record.last_cargo = entity
  return true, "dropped"
end

-- Auswahl: welcher Flieger, welcher Ernter (Plan 4.5) -----------------------------------------------------

-- Flieger für Taste und Shortcut; erste Stufe mit Treffer gilt, nur arrakis-ornithopter der eigenen Force.
-- cursor_position nur bei der Taste (A23 events.d.ts:18–60).
function lib.resolve_flyer(player, cursor_position)
  if not (player and player.valid) then return nil end
  local force_index = player.force.index
  local function own(entity)
    return is_flyer(entity) and entity.force.index == force_index
  end
  -- 1. Fahrzeug des Spielers (beim Fernfahren der ferngefahrene Flieger) [U2].
  local vehicle = player.vehicle
  if own(vehicle) then return vehicle end
  -- 2. Fernbedienungsauswahl: der Flieger, der dem Bezugspunkt am nächsten ist [U3, U4, U5]. Bezugspunkt: ausgewählter
  -- Ernter, sonst Mauszeiger, sonst Spielerposition (in der Fernsicht die gezeigte Stelle).
  local selected = player.selected
  local selection = player.spidertron_remote_selection
  if selection and #selection > 0 then
    local ref_surface, ref = player.surface.index, cursor_position or player.position
    if is_harvester(selected) then ref_surface, ref = selected.surface.index, selected.position end
    local best, best_distance = nil, nil
    for _, entity in pairs(selection) do
      if own(entity) then
        local d = math.huge
        if entity.surface.index == ref_surface then d = distance(entity.position, {x = ref.x or ref[1], y = ref.y or ref[2]}) end
        if not best or d < best_distance then best, best_distance = entity, d end
      end
    end
    if best then return best end
  end
  -- 3. Auswahl unter dem Mauszeiger [U3].
  if own(selected) then return selected end
  -- 4. Solo-Rettung: Sitzt der Spieler in einem Ernter (A23 classes.d.ts:16579) oder zeigt er auf einen, der nächste
  -- eigene Flieger ohne Last ≤ 4 Kacheln um diesen Ernter (auch ein koppelnder: dann bricht der zweite Druck ab).
  local car = player.physical_vehicle
  if not is_harvester(car) then
    car = nil
    if is_harvester(selected) then car = selected end
  end
  if car then
    local best, best_distance = nil, nil
    local found = car.surface.find_entities_filtered{name = NAME, position = car.position, radius = lib.COUPLE_RANGE,
      force = player.force}
    for _, entity in pairs(found) do
      local record = lib.get(entity)
      if not (record and record.cargo) then
        local d = distance(entity.position, car.position)
        if not best or d < best_distance then best, best_distance = entity, d end
      end
    end
    if best then return best end
  end
  return nil
end

-- Ernter für einen leeren Flieger: eigene Force, ≤ 4 Kacheln, nicht getragen, nicht in einer Kopplung. Stufen:
-- 1. player.selected, 2. Fahrzeug des Spielers, 3. der nächste spice-harvester der Force um den Flieger.
-- Gibt die Entity zurück oder nil plus Grund des ersten abgelehnten Treffers ("foreign", "busy").
function lib.resolve_harvester(flyer, player)
  if not is_flyer(flyer) then return nil, "no_harvester" end
  local reason = nil
  local function try(entity)
    if not is_harvester(entity) then return nil end
    local problem = candidate_problem(flyer, entity)
    if not problem then return entity end
    if problem ~= "no_harvester" then reason = reason or problem end
    return nil
  end
  if player and player.valid then
    local found = try(player.selected) or try(player.physical_vehicle) or try(player.vehicle)
    if found then return found end
  end
  local position = flyer.position
  local list = flyer.surface.find_entities_filtered{name = HARVESTER, position = position, radius = lib.COUPLE_RANGE,
    force = flyer.force}
  table.sort(list, function(a, b) return distance(a.position, position) < distance(b.position, position) end)
  for _, entity in ipairs(list) do
    local found = try(entity)
    if found then return found end
  end
  return nil, reason
end

-- Bedienung (Plan 4.5) ---------------------------------------------------------------------------

-- Taste, Shortcut und Knopf: beladen → Absetzen; koppelt → Abbruch; leer → Ernter suchen und ankoppeln.
-- target: Ernter (nil: resolve_harvester), player darf nil sein (Prüfstand). Gibt ok, Grund zurück:
-- "coupling", "aborted", "dropped" (ok) bzw. "no_flyer", "foreign", "debounce", "busy", "no_harvester",
-- "no_space", "lost".
function lib.toggle_carry(flyer, target, player)
  if not is_flyer(flyer) then return false, "no_flyer" end
  if player and player.force.index ~= flyer.force.index then
    hint(player, flyer, "hint-flyer-foreign")
    return false, "foreign"
  end
  local record = lib.get(flyer) or lib.register(flyer)
  local tick = game.tick
  if record.last_toggle_tick ~= 0 and tick - record.last_toggle_tick < lib.DEBOUNCE then return false, "debounce" end
  record.last_toggle_tick = tick
  if record.cargo then return lib.drop(record, player) end
  if record.coupling then
    end_coupling(record)
    hint(player, flyer, "hint-coupling-aborted")
    return true, "aborted"
  end
  local entity, reason = nil, nil
  if target then
    reason = candidate_problem(flyer, target)
    if not reason then entity = target end
  else
    entity, reason = lib.resolve_harvester(flyer, player)
  end
  if not entity then
    reason = reason or "no_harvester"
    local at = flyer
    if is_harvester(target) then at = target end
    hint(player, at, REASON_HINT[reason] or "hint-no-harvester")
    return false, reason
  end
  return start_coupling(record, entity, player)
end

-- Taste und Shortcut: Flieger suchen, dann toggle_carry; sonst Hinweis.
local function carry_for(player, cursor_position)
  local flyer = lib.resolve_flyer(player, cursor_position)
  if flyer then
    lib.toggle_carry(flyer, nil, player)
    return
  end
  for _, entity in pairs({player.vehicle, player.selected}) do
    if is_flyer(entity) and entity.force.index ~= player.force.index then
      hint(player, entity, "hint-flyer-foreign")
      return
    end
  end
  hint(player, nil, "hint-no-flyer")
end

-- Fernbedienung in die Hand, Flieger gleich ausgewählt (A23 classes.d.ts:15991, :16616) [U5].
function lib.give_remote(record, player)
  if not (record and record.entity.valid and player and player.valid) then return false end
  local stack = player.clear_cursor() and player.cursor_stack
  if not stack then
    hint(player, record.entity, "hint-remote-cursor")
    return false
  end
  if not stack.set_stack{name = REMOTE_ITEM, count = 1} then
    hint(player, record.entity, "hint-remote-cursor")
    return false
  end
  player.spidertron_remote_selection = {record.entity}
  return true
end

-- Ziel für „In den Ernter steigen“ (Plan 4.7) oder nil: Der Spieler sitzt im Flieger, der zuletzt abgesetzte
-- Ernter ist gültig, steht ≤ 6 Kacheln entfernt auf derselben Oberfläche und sein Fahrersitz ist frei.
function lib.board_target(record, player)
  if not (record and player and player.valid) then return nil end
  local flyer = record.entity
  if not (flyer.valid and player.physical_vehicle == flyer) then return nil end
  local target = record.last_cargo
  if not (target and target.valid and target.surface.index == flyer.surface.index) then return nil end
  if distance(target.position, flyer.position) > lib.BOARD_RANGE then return nil end
  if target.get_driver() ~= nil then return nil end
  local h = harvester.get(target)
  if h and h.state == "carried" then return nil end
  return target
end

-- Spieler vom Flieger in den zuletzt abgesetzten Ernter [U14]; true, wenn er danach dort sitzt.
function lib.board_harvester(record, player)
  local target = lib.board_target(record, player)
  if not target then return false end
  local flyer = record.entity
  local me = player.character or player
  if sits(flyer.get_driver(), me, player) then
    flyer.set_driver(nil)
  elseif sits(flyer.get_passenger(), me, player) then
    flyer.set_passenger(nil)
  end
  target.set_driver(player)
  return sits(target.get_driver(), me, player)
end

-- Zustand als LocalisedString (Fenster, Prüfstand).
function lib.state_text(record)
  if record.cargo then
    local h = storage.harvesters[record.cargo]
    local entity = h and h.entity
    local count, capacity = 0, 0
    if entity and entity.valid then
      local trunk = entity.get_inventory(defines.inventory.car_trunk)
      if trunk then
        count = trunk.get_item_count(SPICE)
        capacity = #trunk * prototypes.item[SPICE].stack_size
      end
    end
    return {"arrakis-message.flyer-loaded", count, capacity}
  elseif record.coupling then
    local left = math.max(0, math.ceil((record.coupling.done_tick - game.tick) / 60))
    return {"arrakis-message.flyer-coupling", left}
  end
  return {"arrakis-message.flyer-empty"}
end

-- Pflege, Absturz, Entfernen (Plan 4.4, 4.10) -----------------------------------------------------------

-- Last eines Fliegers zum Abhebepunkt (ohne Schaden; Stufen 2 und 3 der Landesuche). Der Flieger wird geleert;
-- ist er noch eingetragen und gültig, auch wieder abbaubar mit leerem Sticker. reason nur für das Log.
function lib.return_cargo(record, reason)
  local un = record and record.cargo
  if not un then return false end
  if storage.flyers[record.un] == record and record.entity.valid then
    clear_cargo(record)
  else
    release_cargo(record)
  end
  local h = storage.harvesters[un]
  if not (h and h.entity.valid and h.state == "carried") then return false end
  log("Arrakis: Ornithopter " .. record.un .. " " .. tostring(reason or "entfernt") .. ": Spice-Ernter " .. un .. " zum Abhebepunkt")
  h.carried_by = nil
  return land(h, nil, false, false)
end

-- Flieger anders entfernt (Abbau, script_raised_destroy, on_object_destroyed): austragen, Last zum Abhebepunkt.
local function flyer_removed(record, reason)
  forget_flyer(record)
  if record.cargo then lib.return_cargo(record, reason) end
end

-- Absturz (Tod des Fliegers): austragen, Last an der Todesstelle mit 30 % Schaden (Stufe 1 bis 3). Die Insassen
-- wirft die Engine aus [U17]; on_object_destroyed kommt danach und findet keinen Datensatz mehr [U24].
function lib.crash(record)
  local flyer = record.entity
  local crash_pos = nil
  if flyer.valid then
    local position = flyer.position
    crash_pos = {surface = flyer.surface.index, x = position.x, y = position.y}
  end
  forget_flyer(record)
  local un = record.cargo
  if not un then return false end
  release_cargo(record)
  local h = storage.harvesters[un]
  if not (h and h.entity.valid and h.state == "carried") then return false end
  h.carried_by = nil
  return land(h, crash_pos, true, false)
end

-- Pflege eines Datensatzes (wie der 60-Tick-Takt): ungültig → austragen (Last wie „anders entfernt“). Beladen:
-- Ernter-Datensatz da, Entity gültig, getragen von diesem Flieger und auf der Ablage → in Ordnung. Sonst
-- a) Datensatz fehlt oder Entity ungültig: Flieger leeren, Log, msg-cargo-lost;
-- b) Entity gültig, aber nicht auf der Ablage (fremdes Skript): am jetzigen Ort landen, Flieger leeren, Log.
-- Danach Abbausperre, Sticker und Render-Objekte prüfen und neu anlegen.
care = function(record)
  local flyer = record.entity
  if not flyer.valid then
    flyer_removed(record, "ungültig")
    return
  end
  local un = record.cargo
  if un then
    local h = storage.harvesters[un]
    local entity = h and h.entity
    if not (entity and entity.valid) then
      log("Arrakis: getragener Spice-Ernter " .. un .. " verschwunden (Ornithopter " .. record.un .. ")")
      clear_cargo(record)
      flyer.force.print({"arrakis-message.msg-cargo-lost"})
    elseif h.state ~= "carried" or (h.carried_by ~= nil and h.carried_by ~= record.un) then
      log("Arrakis: Ornithopter " .. record.un .. " trägt Spice-Ernter " .. un .. " nicht mehr (Zustand " .. h.state .. ")")
      clear_cargo(record)
    elseif not on_hold(entity) then
      land_here(h)
    end
  end
  local minable = record.cargo == nil
  if flyer.minable_flag ~= minable then flyer.minable_flag = minable end
  ensure_sticker(record)
  if record.cargo then
    draw_cargo(record)
  else
    destroy_render(record, "image")
    destroy_render(record, "shadow")
  end
  if not record.coupling then destroy_render(record, "ring") end
end
lib.care = care

-- Ernter tot, abgebaut oder per Skript entfernt: Kopplung abbrechen, Träger leeren, aus der Warteliste streichen.
local function harvester_gone(un)
  storage.stranded[un] = nil
  local record = coupling_of(un)
  if record then end_coupling(record) end
  for _, flyer_record in pairs(storage.flyers) do
    if flyer_record.cargo == un then
      log("Arrakis: getragener Spice-Ernter " .. un .. " entfernt (Ornithopter " .. flyer_record.un .. ")")
      clear_cargo(flyer_record)
    end
  end
end

-- Ablage leeren (Plan 4.10, 4.15) ---------------------------------------------------------------------

local function hold_harvesters(surface)
  return surface.find_entities_filtered{name = HARVESTER}
end

-- Einen Ernter von der Ablage holen: mit Träger an ihm absetzen (ohne Hinweis), sonst und bei „kein Platz“ die
-- Landesuche (mit den Werten aus der Warteliste, falls er dort steht). Ohne Datensatz vorher eintragen und wieder als
-- getragen sperren (ohne Abhebepunkt gilt nur Stufe 3). no_wait: ohne Warteliste. Gibt true zurück, wenn er unten ist.
local function unload(entity, no_wait)
  local h = harvester.get(entity)
  if not h then
    h = harvester.register(entity)
    if not h then return false end
    harvester.lift(h, nil, nil)
  elseif h.state ~= "carried" then
    harvester.lift(h, nil, h.lift_pos)
  end
  local record = carrier_of(h.un)
  if record then
    if lib.drop(record, nil, true) then return true end
    clear_cargo(record)
  end
  h.carried_by = nil
  local entry = storage.stranded[h.un]
  return land(h, entry and entry.crash_pos, entry and entry.damage, no_wait)
end

-- Ernter auf der Ablage ohne gültigen Träger und ohne Eintrag in der Warteliste (Plan 4.10 „Waisen“) landen.
local function rescue_orphans()
  local surface = hold.surface() or game.get_surface(hold.NAME)
  if not surface then return 0 end
  local count = 0
  for _, entity in pairs(hold_harvesters(surface)) do
    if entity.valid and not storage.stranded[entity.unit_number] and not carrier_of(entity.unit_number) then
      log("Arrakis: Spice-Ernter " .. entity.unit_number .. " ohne Träger auf der Ablage gefunden")
      if unload(entity, false) then count = count + 1 end
    end
  end
  return count
end

-- /arrakis-uninstall ja (Plan 4.15): jeden Ernter auf der Ablage herunterholen, alle Bilder weg; steht danach keiner
-- mehr dort, die Ablage löschen (A23 classes.d.ts:11769). Gibt n (abgesetzt) und rest (übrig, warten) zurück.
function lib.uninstall()
  for _, record in pairs(storage.flyers) do care(record) end
  local surface = hold.surface() or game.get_surface(hold.NAME)
  if not surface then return 0, 0 end
  local n = 0
  for _, entity in pairs(hold_harvesters(surface)) do
    if entity.valid and unload(entity, false) then n = n + 1 end
  end
  local rest = surface.count_entities_filtered{name = HARVESTER}
  if rest == 0 then
    game.delete_surface(surface)
    hold.forget()
  end
  return n, rest
end

local function reply(player, message)
  if player then
    player.print(message)
  else
    rcon.print(message)
    log(message)
  end
end

-- /arrakis-uninstall: nur Admins (ohne Spieler: Serverkonsole oder RCON, gilt als Admin); zweistufig mit „ja“.
local function uninstall_command(command)
  local player = command.player_index and game.get_player(command.player_index)
  if command.player_index and not player then return end
  if player and not player.admin then
    reply(player, {"arrakis-message.uninstall-admin"})
    return
  end
  local word = string.lower(string.match(command.parameter or "", "^%s*(.-)%s*$"))
  if word ~= "ja" and word ~= "yes" then
    local surface = hold.surface() or game.get_surface(hold.NAME)
    local count = surface and surface.count_entities_filtered{name = HARVESTER} or 0
    reply(player, {"arrakis-message.uninstall-warn", count})
    return
  end
  local n, rest = lib.uninstall()
  if rest == 0 then
    reply(player, {"arrakis-message.uninstall-done", n})
  else
    reply(player, {"arrakis-message.uninstall-stuck", n, rest})
  end
end

-- Takte ------------------------------------------------------------------------------------------

-- Pflege aller Flieger, danach die Warteliste. Kosten: ein Durchlauf über storage.flyers je Sekunde.
local function on_nth_tick_60()
  for _, record in pairs(storage.flyers) do
    care(record)
  end
  lib.retry_stranded()
end

-- Ereignisse ---------------------------------------------------------------------------------------

local function on_built(event)
  local entity = event.entity
  if is_flyer(entity) then lib.register(entity) end
end

-- Klon: leer eintragen (kein zweiter Träger derselben Last); das Original bleibt, wie es ist.
local function on_cloned(event)
  local entity = event.destination
  if is_flyer(entity) then lib.register(entity) end
end

local function on_died(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  if entity.name == NAME then
    local record = lib.get(entity)
    if record then lib.crash(record) end
  elseif entity.name == HARVESTER then
    harvester_gone(entity.unit_number)
  end
end

-- Abbau (bei beladenem Flieger nur per Skript möglich) und script_raised_destroy.
local function on_removed(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  if entity.name == NAME then
    local record = lib.get(entity)
    if record then flyer_removed(record, "entfernt") end
  elseif entity.name == HARVESTER then
    harvester_gone(entity.unit_number)
  end
end

local function on_object_destroyed(event)
  local reg = storage.reg[event.registration_number]
  if not (reg and reg.kind == "flyer") then return end
  storage.reg[event.registration_number] = nil
  local record = storage.flyers[reg.un]
  if record then flyer_removed(record, "verschwunden") end
end

-- Beladene Flieger dürfen nicht zum Abriss markiert bleiben [U26]; per Hand hält sie minable_flag = false.
local function on_marked_for_deconstruction(event)
  local entity = event.entity
  if not is_flyer(entity) then return end
  local record = lib.get(entity)
  if not (record and record.cargo) then return end
  local player = event.player_index and game.get_player(event.player_index)
  if player then
    entity.cancel_deconstruction(player.force, player)
  else
    entity.cancel_deconstruction(entity.force)
  end
end

-- Teleport: Flieger → Pflege sofort (Bilder neu, wenn er die Oberfläche wechselte) und Kopplung prüfen;
-- getragener Ernter außerhalb der Ablage → dort landen (wie care Fall b).
local function on_teleported(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  if entity.name == NAME then
    local record = lib.get(entity) or lib.register(entity)
    care(record)
    if record.coupling and storage.flyers[record.un] then update_coupling(record, event.tick) end
  elseif entity.name == HARVESTER then
    local h = harvester.get(entity)
    if h and h.state == "carried" and not on_hold(entity) then land_here(h) end
  end
end

-- Spieler steigt in einen Flieger oder aus: eintragen, falls noch nicht geschehen.
local function on_driving_changed(event)
  local entity = event.entity
  if is_flyer(entity) and not lib.get(entity) then lib.register(entity) end
end

-- Ablage wird gelöscht oder geleert: jeden Ernter auf ihr herunterholen (ohne Warteliste, die Ablage verliert ihn
-- gleich), was bleibt, geht verloren. Danach Ablage vergessen und Warteliste leeren.
local function evacuate_hold(surface)
  for _, entity in pairs(hold_harvesters(surface)) do
    if entity.valid and not unload(entity, true) then
      log("Arrakis: Spice-Ernter " .. tostring(entity.unit_number) .. " geht mit der Ablage verloren (kein Landeplatz)")
      entity.force.print({"arrakis-message.msg-cargo-lost"})
    end
  end
  hold.forget()
  storage.stranded = {}
end

-- Oberfläche wird gelöscht (A23 events.d.ts:3940). Ablage: evacuate_hold. Andere Oberfläche: Kopplungen dort
-- abbrechen, Lasten von Fliegern dort landen.
local function on_pre_surface_deleted(event)
  local index = event.surface_index
  local surface = game.get_surface(index)
  if not surface then return end
  deleting[index] = true
  if surface.name == hold.NAME then
    evacuate_hold(surface)
  else
    for flyer_un in pairs(storage.couplings) do
      local record = storage.flyers[flyer_un]
      local c = record and record.coupling
      if c then
        local h = storage.harvesters[c.harvester]
        local here = not record.entity.valid or record.entity.surface.index == index
          or (h and h.entity.valid and h.entity.surface.index == index)
        if here then end_coupling(record) end
      end
    end
    for _, record in pairs(storage.flyers) do
      local un = record.cargo
      if un and record.entity.valid and record.entity.surface.index == index then
        release_cargo(record)
        local h = storage.harvesters[un]
        if h and h.entity.valid and h.state == "carried" then
          h.carried_by = nil
          land(h, nil, false, false)
        end
      end
    end
  end
  deleting[index] = nil
end

-- Oberfläche wird geleert (A23 events.d.ts:3926; surface.clear() entfernt alle Entities und Chunks, die Oberfläche
-- bleibt gültig). Nur die Ablage: evacuate_hold, sonst gingen alle getragenen und wartenden Ernter verloren. forget()
-- lässt das nächste ensure() die Laborchunks neu erzeugen und die Ablage neu verstecken. Andere Oberflächen nicht:
-- Flieger dort verschwinden (on_object_destroyed), Lasten landen wie „anders entfernt“.
local function on_pre_surface_cleared(event)
  local surface = game.get_surface(event.surface_index)
  if surface and surface.name == hold.NAME then evacuate_hold(surface) end
end

local function on_carry_key(event)
  local player = game.get_player(event.player_index)
  if player then carry_for(player, event.cursor_position) end
end

-- Shortcut arrakis-carry (A23 events.d.ts:1549); geht auch in der Kartenansicht.
local function on_shortcut(event)
  if event.prototype_name ~= CARRY_SHORTCUT then return end
  local player = game.get_player(event.player_index)
  if player then carry_for(player, nil) end
end

lib.events =
{
  [defines.events.on_built_entity] = on_built,
  [defines.events.on_robot_built_entity] = on_built,
  [defines.events.script_raised_built] = on_built,
  [defines.events.script_raised_revive] = on_built,
  [defines.events.on_entity_cloned] = on_cloned,
  [defines.events.on_entity_died] = on_died,
  [defines.events.on_player_mined_entity] = on_removed,
  [defines.events.on_robot_mined_entity] = on_removed,
  [defines.events.script_raised_destroy] = on_removed,
  [defines.events.on_object_destroyed] = on_object_destroyed,
  [defines.events.on_marked_for_deconstruction] = on_marked_for_deconstruction,
  [defines.events.script_raised_teleported] = on_teleported,
  [defines.events.on_player_driving_changed_state] = on_driving_changed,
  [defines.events.on_pre_surface_deleted] = on_pre_surface_deleted,
  [defines.events.on_pre_surface_cleared] = on_pre_surface_cleared,
  [defines.events.on_lua_shortcut] = on_shortcut,
  [CARRY_INPUT] = on_carry_key
}

lib.on_nth_tick =
{
  [10] = function(event) lib.update_couplings(event.tick) end,
  [60] = on_nth_tick_60
}

-- Nach Mod-Änderungen (nach migrate und harvester): alle Flieger pflegen, dann Waisen auf der Ablage landen (Plan 4.15).
lib.on_configuration_changed = function()
  for _, record in pairs(storage.flyers) do
    care(record)
  end
  rescue_orphans()
end

lib.add_commands = function()
  commands.add_command("arrakis-uninstall", {"arrakis-message.uninstall-help"}, uninstall_command)
end

return lib
