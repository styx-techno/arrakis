-- Leitstelle und Carryalls (Phase 3e, docs/plan-3e.md 4): Leitstellen-Datensätze, Zuordnung der Carryalls, Parken
-- und Nachfüllen, Aufträge RETTUNG, TANKEN, ENTLADEN, RÜCKKEHR, Verteilung, Notregel, ehrliche Absage und
-- Handbetrieb. Bibliothek für __core__/lualib/event_handler. Daten nur in storage (Schema 5, scripts/migrate.lua).
--
-- Fliegen, Ankoppeln, Anheben und Absetzen macht scripts/flyer.lua (der Carryall ist dort ein Flieger mit
-- kind = "carryall"); dieses Modul setzt nur Ziele und ruft flyer_lib.couple und flyer_lib.drop. Jagden liest es aus
-- storage.hunts (scripts/worms.lua) im 30-Tick-Takt, ohne Haken in worms.lua.
--
-- storage.depots[un] = {un, entity, surface_index, position = {x, y}, force_index}
-- Carryall-Felder im Flieger-Datensatz (storage.flyers[un], kind = "carryall"):
--   depot = depot_un|nil, job = job_id|nil, fleet_mode = "auto"|"manual", fleet_goal = {x, y}|nil (zuletzt gesetztes Ziel)
-- storage.jobs = {next_id, list = {[id] = job}}; job = {id, kind = "rescue"|"refuel"|"unload"|"return",
--   harvester = un, carryall = un|nil, state, created, hunt = hunt_id|nil, return_pos = {surface, x, y}|nil,
--   intake = un|nil, wait_until = tick|nil, refused = true|nil}
-- storage.job_of[harvester_un] = job_id: jeder Ernter steht in höchstens einem Auftrag.
-- storage.jobs.refused[hunt_id] = tick: Jagden mit ehrlicher Absage (nur einmal melden, kein neuer Auftrag).
-- storage.harvesters[un].fleet_refuel_after = tick: kein neuer Tankauftrag vorher (Kofferraum war leer).
-- storage.harvesters[un].fleet_wait = {surface, x, y, base = {x, y}, depot = un, since}: gerettet und an der Leitstelle
--   abgestellt (0.11.0); ein Rückflug bringt ihn nach (x, y), sobald dort kein Wurm mehr lauert (scripts/worms.lua).
-- storage.harvesters[un].fleet_home = {surface, x, y}: an der Annahme abgesetzt, Rückweg (0.12.0); geht der
--   Entladeauftrag dort verloren, wartet er angedockt (fleet_wait) und fliegt danach zurück.
-- Ablauf der Rettung ab 0.11.0: anheben, zur Leitstelle (über 90 % voll erst zur Annahme), dort absetzen; Rückflug,
-- wenn der Sektor ruhig ist. Lauert dort kein Wurm mehr, fliegt ein Carryall nach dem Entladen gleich zurück.
--
-- Flottenleitung (Phase 3f, docs/plan-3f.md, Schema 6, nur mit der Forschung arrakis-fleet-control):
-- storage.depots[un] zusätzlich target (Soll aus dem Fenster, 0 = aus), recall_button, signal_entity (LuaEntity
--   arrakis-depot-signals), last_h, last_r (zuletzt gelesene Signale H und R), soll (geltende Soll-Zahl), recall (Rückruf
--   gilt), census (Zahlen fürs Fenster und die Statussignale), signals_written.
-- Aufträge zusätzlich kind "deploy" (EINSATZ), "move" (UMSETZEN), "recall" (RÜCKRUF) mit depot = un, target = {x, y}
--   (Platz aus scripts/fleet-fields.lua, reserviert), store = true (ins Lager legen), wait_reason, priority.
-- storage.harvesters[un] zusätzlich fleet_owner = depot_un (von der Leitstelle eingesetzt), fleet_wait.reason =
--   "rescue"|"recall"|"reserve" (Reserve: kein Rückweg, x und y fehlen).

local harvester = require("scripts.harvester")
local flyer_lib = require("scripts.flyer")
local worms_lib = require("scripts.worms")
local vibration_lib = require("scripts.vibration")
local terrain = require("scripts.terrain")
local fields = require("scripts.fleet-fields")
local speed = require("prototypes.ornithopter-speed")

local lib = {}

local DEPOT = "arrakis-depot"
local CARRYALL = flyer_lib.CARRYALL
local TECH = "arrakis-fleet-control"
local SIGNALS = "arrakis-depot-signals"

-- Reichweite der Leitstelle (Kacheln, Mod-Einstellung, Plan 1.3).
lib.RANGE = settings.startup["arrakis-depot-range"].value
-- Ein neu gebauter Carryall gehört zur nächsten Leitstelle in so vielen Kacheln (Plan 1.5).
lib.ADOPT_RADIUS = 20
-- Prioritäten (Plan 4.3).
lib.PRIORITY = {rescue = 100, refuel = 60, unload = 50, ["return"] = 40, move = 30, deploy = 20, recall = 10}
-- Rückruf über Signal R oder den Knopf geht vor Tanken und Entladen (docs/plan-3f.md 3.3).
lib.RECALL_URGENT = 70
-- Tempo leer mit Raketentreibstoff (Kacheln/s); mit anderem Flugtreibstoff mal g (prototypes/ornithopter-speed.lua).
lib.SPEED_EMPTY = 8 * speed.CARRYALL_FACTOR
lib.SPEED_LOADED = 5.6 * speed.CARRYALL_FACTOR
-- Energie je Kachel (J): Die Engine verbraucht 800 kW (prototypes/ornithopter.lua), beladen fliegt er langsamer.
lib.ENERGY_PER_TILE_EMPTY = 800000 / lib.SPEED_EMPTY
lib.ENERGY_PER_TILE_LOADED = 800000 / lib.SPEED_LOADED
-- Reserve auf die nötige Energie (Plan 4.5).
lib.RESERVE = 1.2
-- Ankoppeln dauert flyer_lib.COUPLE_TICKS plus höchstens 10 Ticks Takt; Puffer vor Countdown-Ende (Ticks, Plan 4.5).
lib.RESCUE_MARGIN = 3 * 60
-- Angekommen: so nah am Ziel (Kacheln).
lib.ARRIVE = 2.5
-- So oft fliegt ein Carryall nach einer abgebrochenen Kopplung wieder an den Ernter heran, bevor der Auftrag endet.
lib.COUPLE_TRIES = 5
-- Tanken: Abstand zum Ernter (Kacheln) und Schwelle (J): unter 100 MJ (gut 4 min Ernten bei 400 kW).
lib.REFUEL_RANGE = 4
lib.REFUEL_BELOW = 100e6
-- Entladen ab diesem Füllstand (belegte Slots / Slots, Plan 4.3) und höchstens so lange an der Annahme (Ticks).
lib.UNLOAD_FILL = 0.9
lib.UNLOAD_WAIT = 60 * 60
-- Andocken an der Annahme dauert intake.STILL_TICKS (120); so lange wartet der Auftrag mindestens (Ticks).
lib.DOCK_GRACE = 10 * 60
-- Ankunft am Absetzpunkt neben der Annahme (Kacheln), siehe arrived_at_intake.
lib.DOCK_ARRIVE = 0.5
-- Vorrat im Kofferraum: bis zu so vielen Stapeln Ernter-Treibstoff (Plan 4.4).
lib.TRUNK_STACKS = 2
-- Abstand der Parkplätze von der Mitte der Leitstelle (Kacheln).
lib.PARK_OFFSETS = {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}}
-- Tankflug ohne Ernter-Treibstoff an Bord: so lange keinen neuen Tankauftrag für diesen Ernter (Ticks).
lib.REFUEL_COOLDOWN = 5 * 60 * 60
-- Abstellplätze für gerettete Ernter an der Leitstelle (0.11.0, Max 29.10.2026: „zur Basis fliegen“): Versatz von der
-- Mitte der Leitstelle (Kacheln), in dieser Reihenfolge; Fels bevorzugt, frei von anderen Erntern.
lib.BASE_OFFSETS =
{
  {7, 0}, {-7, 0}, {0, 7}, {0, -7}, {7, 7}, {-7, 7}, {7, -7}, {-7, -7},
  {12, 0}, {-12, 0}, {0, 12}, {0, -12}, {12, 12}, {-12, 12}, {12, -12}, {-12, -12}
}
-- Ein wartender Ernter, den jemand weiter als so weit vom Abstellplatz fährt, gilt als übernommen (Kacheln).
lib.WAIT_LEAVE = 8
-- Einsatz aus dem Lager: so viele Items Ernter-Treibstoff aus der Leitstelle (docs/plan-3f.md 1.7).
lib.DEPLOY_FUEL = 5
-- Höchste Soll-Zahl im Fenster.
lib.TARGET_MAX = 50
-- Statussignale in dieser Reihenfolge (docs/plan-3f.md 1.8): aktive Ernter, Reserve, freie Carryalls, laufende
-- Rettungen, Spice-Sand in allen Laderäumen, Wurmalarm.
lib.STATUS_SIGNALS = {"arrakis-signal-harvesters", "arrakis-signal-reserve", "arrakis-signal-carryalls",
  "arrakis-signal-rescues", "arrakis-signal-spice", "arrakis-wormsign"}

local function distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function gps(surface, position)
  return string.format("[gps=%.1f,%.1f,%s]", position.x, position.y, surface.name)
end

-- Datensätze -----------------------------------------------------------------------------------------

local function depot_of(un)
  local d = un and storage.depots[un]
  if d and not (d.entity and d.entity.valid) then
    if d.signal_entity and d.signal_entity.valid then d.signal_entity.destroy() end
    storage.depots[un] = nil
    return nil
  end
  return d
end

-- Verstecktes Schaltungsgebäude unter der Leitstelle (docs/plan-3f.md 1.8), per Skript mit rotem und grünem Draht an
-- sie angeschlossen; gibt die Entity zurück.
local function ensure_signals(d)
  local cc = d.signal_entity
  if cc and cc.valid then return cc end
  local entity = d.entity
  cc = entity.surface.create_entity{name = SIGNALS, position = d.position, force = entity.force, create_build_effect_smoke = false}
  if not cc then return nil end
  cc.destructible = false
  for _, id in ipairs({defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green}) do
    entity.get_wire_connector(id, true).connect_to(cc.get_wire_connector(id, true), false, defines.wire_origin.script)
  end
  d.signal_entity = cc
  d.signals_written = nil
  return cc
end

local function register_depot(entity)
  local un = entity.unit_number
  local d = storage.depots[un]
  if d then return d end
  local position = entity.position
  d = {un = un, entity = entity, surface_index = entity.surface.index, position = {x = position.x, y = position.y},
    force_index = entity.force.index, target = 0, recall_button = false, last_h = 0, last_r = 0, soll = 0,
    recall = false}
  storage.depots[un] = d
  ensure_signals(d)
  storage.reg[script.register_on_object_destroyed(entity)] = {kind = "depot", un = un}
  return d
end

-- Nächste Leitstelle der Force auf der Oberfläche, wahlweise nur bis radius.
local function nearest_depot(surface_index, force_index, position, radius)
  local best, best_d = nil, radius or math.huge
  for un, d in pairs(storage.depots) do
    if depot_of(un) and d.surface_index == surface_index and d.force_index == force_index then
      local dist = distance(d.position, position)
      if dist <= best_d then best, best_d = d, dist end
    end
  end
  return best
end

local function carryall_record(entity)
  if not (entity and entity.valid and entity.name == CARRYALL) then return nil end
  local record = flyer_lib.get(entity) or flyer_lib.register(entity)
  if record and not record.fleet_mode then record.fleet_mode = "auto" end
  return record
end

-- Alle Carryall-Datensätze (gültig) in fester Reihenfolge (unit_number aufsteigend: gleiche Wahl auf jedem Rechner).
local function carryalls()
  local list = {}
  for _, record in pairs(storage.flyers) do
    if record.kind == "carryall" and record.entity.valid then
      if not record.fleet_mode then record.fleet_mode = "auto" end
      table.insert(list, record)
    end
  end
  table.sort(list, function(a, b) return a.un < b.un end)
  return list
end

-- Ziel setzen und merken; ein fremdes Ziel (Fernbedienung) erkennt manual_check am Unterschied.
local function fly(record, position)
  local entity = record.entity
  record.fleet_goal = {x = position.x, y = position.y}
  entity.autopilot_destination = record.fleet_goal
end

local function stop(record)
  record.fleet_goal = nil
  if record.entity.valid then record.entity.autopilot_destination = nil end
end

local function arrived(record, position)
  return distance(record.entity.position, position) <= lib.ARRIVE
end

-- An der Annahme genauer: Der Ernter dockt nur im Umkreis von intake.DOCK_RADIUS (4) an, der Absetzpunkt liegt 3 Kacheln
-- neben der Annahme. Mit lib.ARRIVE (2,5) landete er im Mock-Dauerlauf (T24) oft 4,3 bis 4,6 Kacheln weg und dockte
-- nicht an. Angekommen also erst auf lib.DOCK_ARRIVE oder wenn der Autopilot sein Ziel erreicht hat.
local function arrived_at_intake(record, position)
  local d = distance(record.entity.position, position)
  return d <= lib.DOCK_ARRIVE or (d <= lib.ARRIVE and record.entity.autopilot_destination == nil)
end

-- Treibstoff ------------------------------------------------------------------------------------------

-- Energie an Bord (J): was gerade brennt plus Brennwert des Brennstofffachs.
local function onboard_energy(entity)
  local burner = entity.burner
  if not burner then return 0 end
  local energy = burner.remaining_burning_fuel or 0
  local inventory = burner.inventory
  for i = 1, #inventory do
    local stack = inventory[i]
    if stack.valid_for_read then energy = energy + stack.count * stack.prototype.fuel_value end
  end
  return energy
end

-- Tempo-Faktor g des Brennstoffs (Raketentreibstoff 1), wie flyer.lua die Stufe wählt.
local function fuel_gain(entity)
  local burner = entity.burner
  local item, quality = nil, nil
  if burner then
    local burning = burner.currently_burning
    if burning then
      item, quality = burning.name, burning.quality
    else
      local inventory = burner.inventory
      for i = 1, #inventory do
        local stack = inventory[i]
        if stack.valid_for_read then item, quality = stack.prototype, stack.quality break end
      end
    end
  end
  if not item then return 1 end
  local level = quality and quality.level or 0
  return speed.gain(item.fuel_acceleration_multiplier + level * item.fuel_acceleration_multiplier_quality_bonus)
end

-- Genug Treibstoff für leer hin (d_empty) und beladen weiter (d_loaded), plus Reserve? (Plan 4.5)
local function enough_fuel(record, d_empty, d_loaded)
  local need = (d_empty * lib.ENERGY_PER_TILE_EMPTY + d_loaded * lib.ENERGY_PER_TILE_LOADED) * lib.RESERVE
  return onboard_energy(record.entity) >= need
end

-- Energie des Ernters (J) wie onboard_energy.
local function harvester_energy(entity)
  return onboard_energy(entity)
end

-- Füllstand des Laderaums: belegte Slots / Slots.
local function fill_of(entity)
  local inventory = entity.get_inventory(defines.inventory.car_trunk)
  if not inventory or #inventory == 0 then return 0 end
  return 1 - inventory.count_empty_stacks() / #inventory
end

-- Brennstoff für Ernter im Kofferraum (Items mit Brennwert).
local function trunk_fuel(record)
  local trunk = record.entity.get_inventory(defines.inventory.spider_trunk)
  local n = 0
  if not trunk then return 0 end
  for i = 1, #trunk do
    local stack = trunk[i]
    if stack.valid_for_read and stack.prototype.fuel_value > 0 then n = n + stack.count end
  end
  return n
end

-- Ernter-Treibstoff aus dem Kofferraum des Carryalls in den Ernter; gibt die Zahl der Items zurück.
local function refuel_harvester(record, entity)
  local trunk = record.entity.get_inventory(defines.inventory.spider_trunk)
  local fuel = entity.get_fuel_inventory()
  if not (trunk and fuel) then return 0 end
  local moved = 0
  for i = 1, #trunk do
    local stack = trunk[i]
    if stack.valid_for_read and stack.prototype.fuel_value > 0 and fuel.can_insert(stack) then
      local n = fuel.insert(stack)
      if n > 0 then
        stack.count = stack.count - n
        moved = moved + n
      end
    end
  end
  return moved
end

-- Parken: Brennstofffach mit Flugtreibstoff aus der Leitstelle füllen, Kofferraum mit Ernter-Treibstoff bis
-- TRUNK_STACKS Stapel (zuerst Brennstoffe, die keine Flugtreibstoffe sind).
local function restock(record, d)
  local depot_inv = d.entity.get_inventory(defines.inventory.chest)
  local entity = record.entity
  local burner = entity.burner
  if not (depot_inv and burner) then return end
  local fuel = burner.inventory
  for i = 1, #depot_inv do
    local stack = depot_inv[i]
    if stack.valid_for_read and flyer_lib.flight_fuel(burner, stack.prototype) and fuel.can_insert(stack) then
      local n = fuel.insert(stack)
      if n > 0 then stack.count = stack.count - n end
    end
  end
  local trunk = entity.get_inventory(defines.inventory.spider_trunk)
  if not trunk then return end
  local have = 0
  for i = 1, #trunk do
    if trunk[i].valid_for_read and trunk[i].prototype.fuel_value > 0 then have = have + 1 end
  end
  for pass = 1, 2 do
    for i = 1, #depot_inv do
      if have >= lib.TRUNK_STACKS then return end
      local stack = depot_inv[i]
      if stack.valid_for_read and stack.prototype.fuel_value > 0 then
        local flight = flyer_lib.flight_fuel(burner, stack.prototype)
        if (pass == 1 and not flight) or (pass == 2 and flight) then
          local n = trunk.insert(stack)
          if n > 0 then
            stack.count = stack.count - n
            have = have + 1
          end
        end
      end
    end
  end
end

-- Aufträge ----------------------------------------------------------------------------------------------

local function job_of_harvester(un)
  local id = storage.job_of[un]
  return id and storage.jobs.list[id]
end

local function new_job(kind, h, fields)
  local jobs = storage.jobs
  local id = jobs.next_id
  jobs.next_id = id + 1
  local job = {id = id, kind = kind, harvester = h.un, state = "open", created = game.tick}
  for key, value in pairs(fields or {}) do job[key] = value end
  jobs.list[id] = job
  storage.job_of[h.un] = id
  return job
end

local function end_job(job, why)
  storage.jobs.list[job.id] = nil
  fields.release(job.id)
  if storage.job_of[job.harvester] == job.id then storage.job_of[job.harvester] = nil end
  local record = job.carryall and storage.flyers[job.carryall]
  if record and record.job == job.id then
    record.job = nil
    if not record.cargo then stop(record) end
  end
  if why then log("Arrakis Leitstelle: Auftrag " .. job.id .. " (" .. job.kind .. ") Ende: " .. why) end
end

-- Auftrag in einen anderen umwandeln (Rettung → Rückkehr/Entladen, Entladen → Rückkehr); der Carryall bleibt.
local function convert(job, kind, state)
  job.kind = kind
  job.state = state
end

local function harvester_of(job)
  local h = storage.harvesters[job.harvester]
  if h and h.entity and h.entity.valid then return h end
  return nil
end

-- Ernter betreut? Gleiche Force, Leitstelle in Reichweite auf derselben Oberfläche, kein Spieler am Steuer.
local function covering_depot(entity)
  local d = nearest_depot(entity.surface.index, entity.force.index, entity.position, lib.RANGE)
  return d
end

local function driven_by_player(entity)
  local driver = entity.get_driver()
  return driver ~= nil
end

local function nearest_intake(surface_index, position, force_index)
  local best, best_d = nil, lib.RANGE
  for un, record in pairs(storage.intakes or {}) do
    local e = record.entity
    if e and e.valid and e.surface.index == surface_index and e.force.index == force_index and not record.bad
      and not record.docked then
      local dist = distance(e.position, position)
      if dist <= best_d then best, best_d = un, dist end
    end
  end
  return best
end

-- Ehrliche Absage (Plan 4.5): Text an die Force, Alarm beim Ernter.
local function refuse(job, h, reason)
  if job.refused then return end
  job.refused = true
  if job.hunt then storage.jobs.refused[job.hunt] = game.tick end
  local entity = h.entity
  entity.force.print({"arrakis-message.msg-rescue-impossible", gps(entity.surface, entity.position),
    {"arrakis-message.rescue-reason-" .. reason}})
  for _, player in pairs(entity.force.connected_players) do
    player.add_custom_alert(entity, {type = "item", name = "arrakis-carryall"},
      {"arrakis-message.alert-rescue-impossible"}, true)
  end
end

-- Neue Aufträge ------------------------------------------------------------------------------------------

local ACTIVE = {deployed = true, deploying = true, packing = true}
-- Aufträge der Flottenleitung (step_transfer).
local TRANSFER = {deploy = true, move = true, recall = true}

local function scan_hunts(tick)
  local hunts = storage.hunts
  if not (hunts and hunts.list) then return end
  local refused = storage.jobs.refused
  for id in pairs(refused) do
    local hunt = hunts.list[id]
    if not hunt or hunt.outcome then refused[id] = nil end
  end
  for _, hunt in pairs(hunts.list) do
    if hunt.kind == "harvest" and not hunt.outcome and not refused[hunt.id] and hunt.target and hunt.target.valid then
      local h = harvester.get(hunt.target)
      -- An der Leitstelle abgestellt (fleet_wait): schon in Sicherheit, kein neuer Rettungsflug.
      -- Angedockt an der Annahme steht er auf Fels und ist sicher; ein Auftrag aus dieser Jagd (Rettung, die zum
      -- Entladen wurde) läuft weiter, sonst bliebe der Ernter nach dem Entladen an der Annahme hängen.
      if h and h.state ~= "carried" and h.state ~= "docked" and not h.fleet_wait and not driven_by_player(h.entity)
          and covering_depot(h.entity) then
        local job = job_of_harvester(h.un)
        -- An der Annahme abgesetzt (unloading, relift) steht er auf Fels: Der Entladeauftrag läuft weiter (PC-Lauf
        -- daf3cb4, T24: abgebrochen, dann dockte der Ernter an und blieb dort ohne Auftrag stehen).
        local at_intake = job and job.kind == "unload" and (job.state == "unloading" or job.state == "relift")
        if job and not at_intake and job.kind ~= "rescue" and job.hunt ~= hunt.id and not (job.carryall and storage.flyers[job.carryall]
            and storage.flyers[job.carryall].cargo == h.un) then
          -- Ein laufender Tank- oder Entladeauftrag ohne Last weicht der Rettung.
          end_job(job, "Wurmzeichen")
          job = nil
        end
        if not job then
          new_job("rescue", h, {hunt = hunt.id, eta_tick = hunt.eta_tick})
        end
      end
    end
  end
end

-- Ist es an der Stelle ruhig: kein lauernder Wurm (scripts/worms.lua) und keine Jagd im selben Sektor? Auch eine Jagd
-- mit Ergebnis zählt, solange sie in der Liste steht (der Wurm sucht nach dem Fehlbiss noch, SEARCH_TICKS).
local function calm(pos)
  if not pos then return false end
  if worms_lib.lurking_at(pos.surface, pos) then return false end
  local hunts = storage.hunts and storage.hunts.list
  if hunts then
    local sector = vibration_lib.sector_of_key(vibration_lib.key_of(pos))
    for _, hunt in pairs(hunts) do
      if hunt.surface_index == pos.surface and hunt.sector_key == sector then
        return false
      end
    end
  end
  return true
end
lib.calm = calm

-- Gerettete Ernter an der Leitstelle (0.11.0): Ist es am Feld ruhig, holt ein Rückflug sie ab. Wer den Ernter
-- selbst fährt, ihn wegbringt oder aufbaut, hat übernommen; dann wartet er nicht mehr.
local function check_wait(un, h)
  local fw = h.fleet_wait
  local entity = h.entity
  -- Angedockt wartet er nur nach einem abgebrochenen Auftrag an der Annahme (end_job).
  if (h.state ~= "mobile" and h.state ~= "docked") or driven_by_player(entity) or entity.surface.index ~= fw.surface
      or distance(entity.position, fw.base) > lib.WAIT_LEAVE then
    h.fleet_wait = nil
    return
  end
  if storage.job_of[un] then return end
  local d = covering_depot(entity)
  -- Reserve (docs/plan-3f.md 1.6) hat keinen Rückweg; solange der Rückruf gilt, bringt die Leitstelle keinen zurück.
  if not d or fw.reason == "reserve" or not fw.x or d.recall then return end
  local pos = {surface = fw.surface, x = fw.x, y = fw.y}
  if calm(pos) then new_job("return", h, {return_pos = pos}) end
end

local function scan_harvesters(tick)
  for un, h in pairs(storage.harvesters) do
    local entity = h.entity
    -- Leer an der Annahme ohne Auftrag (der Entladeauftrag ging verloren): wie nach einer Rettung zurück an den Platz,
    -- sonst bliebe die Annahme für alle belegt (PC-Läufe 1e4d625 und daf3cb4).
    if h.fleet_home and h.state == "docked" and not h.fleet_wait and not storage.job_of[un] and entity and entity.valid
        and entity.get_inventory(defines.inventory.car_trunk).is_empty() then
      local pos, p = h.fleet_home, entity.position
      h.fleet_wait = {surface = pos.surface, x = pos.x, y = pos.y, base = {x = p.x, y = p.y}, since = tick, reason = "rescue"}
      h.fleet_home = nil
    end
    if h.fleet_wait and entity and entity.valid and not storage.job_of[un] then check_wait(un, h) end
    if entity and entity.valid and ACTIVE[h.state] and not storage.job_of[un] and covering_depot(entity) then
      if fill_of(entity) >= lib.UNLOAD_FILL or h.status == "trunk_full" then
        if nearest_intake(entity.surface.index, entity.position, entity.force.index) then
          new_job("unload", h)
        end
      elseif (h.status == "no_fuel" or harvester_energy(entity) < lib.REFUEL_BELOW)
          and tick >= (h.fleet_refuel_after or 0) then
        new_job("refuel", h)
      end
    end
  end
end

-- Verteilung ------------------------------------------------------------------------------------------

local function free_carryall(record)
  local entity = record.entity
  return record.fleet_mode == "auto" and not record.job and not record.cargo and not record.coupling
    and entity.get_driver() == nil and record.depot ~= nil
end

-- Bester Carryall für einen Auftrag am Ernter h: frei (oder bei Rettung leer unterwegs), Leitstelle deckt den
-- Ernter, genug Treibstoff; der nächste gewinnt. Gibt record, Grund zurück.
local function pick(job, h, list)
  local target = h.entity.position
  local best, best_d = nil, math.huge
  local reason = "none_free"
  for _, record in ipairs(list) do
    local usable = free_carryall(record)
    -- Tanken nur mit Brennstoff an Bord (sonst wartet der Auftrag, bis einer nachgefüllt hat).
    if usable and job.kind == "refuel" and trunk_fuel(record) == 0 then usable = false end
    if not usable and job.kind == "rescue" and record.fleet_mode == "auto" and record.job and not record.cargo
        and not record.coupling and record.depot then
      local other = storage.jobs.list[record.job]
      usable = other ~= nil and other.kind ~= "rescue"
    end
    local d = usable and depot_of(record.depot)
    if d and d.surface_index == h.entity.surface.index and distance(d.position, target) <= lib.RANGE then
      local dist = distance(record.entity.position, target)
      local back = distance(target, d.position)
      -- Einsatz und Umsetzen tragen ihn erst zum Platz, dann fliegt der Carryall leer heim (gerechnet wie beladen).
      if job.target then back = distance(target, job.target) + distance(job.target, d.position) end
      if not enough_fuel(record, dist, back) then
        reason = "no_fuel"
      elseif dist < best_d then
        best, best_d = record, dist
      end
    end
  end
  return best, best and nil or reason, best_d
end

local function assign(job, record)
  if record.job and record.job ~= job.id then
    local other = storage.jobs.list[record.job]
    if other then
      other.carryall = nil
      other.state = "open"
    end
  end
  record.job = job.id
  job.carryall = record.un
  job.state = "fly"
end

-- Bereitschaft (Plan 4.3): Hat eine Leitstelle mindestens zwei Carryalls in Automatik, bleibt für Rettungen immer einer
-- frei; Tanken, Entladen und Rückflüge bekommen nur die übrigen. Zählt freie Carryalls je Leitstelle.
local function free_counts(list)
  local free, total = {}, {}
  for _, record in ipairs(list) do
    if record.depot and record.fleet_mode == "auto" then
      total[record.depot] = (total[record.depot] or 0) + 1
      if free_carryall(record) then free[record.depot] = (free[record.depot] or 0) + 1 end
    end
  end
  return free, total
end

local function dispatch(tick)
  local open = {}
  for _, job in pairs(storage.jobs.list) do
    if job.state == "open" then table.insert(open, job) end
  end
  if #open == 0 then return end
  table.sort(open, function(a, b)
    local pa, pb = a.priority or lib.PRIORITY[a.kind], b.priority or lib.PRIORITY[b.kind]
    if pa ~= pb then return pa > pb end
    return a.id < b.id
  end)
  local list = carryalls()
  local free, total = free_counts(list)
  for _, job in ipairs(open) do
    local h = harvester_of(job)
    if not h then
      end_job(job, "Ernter weg")
    else
      local record, reason, dist = pick(job, h, list)
      if record and job.kind ~= "rescue" and (total[record.depot] or 0) >= 2 and (free[record.depot] or 0) <= 1 then
        record = nil
      end
      if job.kind == "rescue" then
        local left = (job.eta_tick or tick) - tick
        if record then
          local secs = dist / (lib.SPEED_EMPTY * fuel_gain(record.entity))
          local need = secs * 60 + flyer_lib.COUPLE_TICKS + 10 + lib.RESCUE_MARGIN
          if need > left then
            record = nil
            reason = "too_far"
          end
        end
        if not record then
          refuse(job, h, reason)
          end_job(job, "keine Rettung: " .. reason)
        end
      end
      if record then
        if free_carryall(record) then free[record.depot] = (free[record.depot] or 0) - 1 end
        assign(job, record)
      end
    end
  end
end

-- Ablauf je Auftrag ------------------------------------------------------------------------------------

local function hunt_running(job)
  local hunts = storage.hunts
  local hunt = job.hunt and hunts and hunts.list and hunts.list[job.hunt]
  return hunt ~= nil and not hunt.outcome
end

-- Ziel zum Absetzen an der Annahme: 3 Kacheln südlich der Annahme (der Ernter dockt im Umkreis von 4 an).
local function intake_spot(intake_un)
  local record = storage.intakes and storage.intakes[intake_un]
  local e = record and record.entity
  if not (e and e.valid) then return nil end
  local p = e.position
  return {x = p.x, y = p.y + 3}
end

local function begin_return(job, h)
  local pos = job.return_pos
  if not pos then
    end_job(job, "kein Rückweg")
    return
  end
  convert(job, "return", "to_spot")
end

-- Abstellplatz an der Leitstelle für einen geretteten Ernter: der erste Versatz aus BASE_OFFSETS mit Fels unter dem
-- Ernter, ohne anderen Ernter und ohne anderen Auftrag dorthin; sonst der erste freie, sonst der erste.
local function base_spot(d, job)
  local surface = d.entity.surface
  local taken = {}
  for _, other in pairs(storage.jobs.list) do
    if other ~= job and other.base_spot then taken[other.base_spot.x .. "/" .. other.base_spot.y] = true end
  end
  local first_free
  for _, offset in ipairs(lib.BASE_OFFSETS) do
    local p = {x = d.position.x + offset[1], y = d.position.y + offset[2]}
    local free = not taken[p.x .. "/" .. p.y]
      and #surface.find_entities_filtered{name = harvester.NAME, position = p, radius = 3, limit = 1} == 0
    if free then
      if terrain.is_rock_area(surface, {{p.x - 2, p.y - 2}, {p.x + 2, p.y + 2}}) then return p end
      first_free = first_free or p
    end
  end
  return first_free or {x = d.position.x + lib.BASE_OFFSETS[1][1], y = d.position.y + lib.BASE_OFFSETS[1][2]}
end

-- Nach dem Anheben (Rettung, Rückflug von der Leitstelle) oder nach dem Entladen: über 90 % voll erst zur Annahme,
-- sonst zurück aufs Feld, wenn es dort ruhig ist, sonst zur Leitstelle.
local function after_lift(job, record, h, unloaded)
  local entity = h.entity
  local d = depot_of(job.depot) or depot_of(record.depot)
  local recall = d ~= nil and d.recall
  -- Ins Lager (docs/plan-3f.md 1.3): erst zur Annahme, wenn der Laderaum nicht leer ist (nicht bei Signal R), dann zur
  -- Leitstelle.
  if job.store and d then
    local trunk = entity.get_inventory(defines.inventory.car_trunk)
    if not unloaded and not recall and trunk and not trunk.is_empty() then
      local intake = nearest_intake(record.entity.surface.index, record.entity.position, record.entity.force.index)
      if intake then
        job.intake = intake
        convert(job, "unload", "to_intake")
        return
      end
    end
    job.base_spot = base_spot(d, job)
    convert(job, "recall", "to_base")
    return
  end
  -- Rückruf (docs/plan-3f.md 1.4): gleich zur Leitstelle, ohne Umweg über die Annahme.
  if recall then
    job.wait_reason = "recall"
    job.base_spot = base_spot(d, job)
    convert(job, "recall", "to_base")
    return
  end
  if not unloaded and fill_of(entity) >= lib.UNLOAD_FILL then
    local intake = nearest_intake(record.entity.surface.index, record.entity.position, record.entity.force.index)
    if intake then
      job.intake = intake
      convert(job, "unload", "to_intake")
      return
    end
  end
  if calm(job.return_pos) then
    begin_return(job, h)
    return
  end
  if not d then
    -- Ohne Leitstelle (abgerissen): in der Luft warten wie bis 0.10.x.
    convert(job, "rescue", "hover")
    return
  end
  job.base_spot = base_spot(d, job)
  convert(job, "rescue", "to_base")
end

local function step_coupling(job, record, h)
  if record.cargo == h.un then return true end
  if not record.coupling then
    -- Abgedriftet, etwa nach einer abgebrochenen Kopplung (PC-Lauf 1e4d625: Umsetzen und Wiederanheben an der Annahme
    -- endeten mit „no_harvester“, der Ernter blieb an der Annahme hängen): wieder heranfliegen und neu ankoppeln.
    local entity = h.entity
    if entity.valid and distance(record.entity.position, entity.position) > lib.ARRIVE then
      if not job.realign then
        job.couple_tries = (job.couple_tries or 0) + 1
        job.realign = true
      end
      if job.couple_tries <= lib.COUPLE_TRIES then
        fly(record, entity.position)
        return false
      end
    elseif job.realign then
      job.realign = nil
      stop(record)
    end
    local ok, why = flyer_lib.couple(record, h.entity)
    if not ok then
      end_job(job, "Ankoppeln: " .. tostring(why))
    end
  end
  return false
end

-- Flottenleitung (docs/plan-3f.md 3.3) -------------------------------------------------------------------

-- Ins Lager der Leitstelle legen (Item mit Qualität und gespeicherten Werten; Ladung und Brennstoff landen mit im
-- Lager). Gibt true zurück, wenn es geklappt hat; passt nicht alles ins Lager, bleibt er stehen.
local function store_harvester(h, d)
  local inventory = d.entity.get_inventory(defines.inventory.chest)
  local entity = h.entity
  if not (inventory and entity.valid) then return false end
  if not inventory.can_insert({name = harvester.NAME, quality = entity.quality.name}) then return false end
  return entity.mine{inventory = inventory, force = false, raise_destroyed = true, ignore_minable = true}
end

-- An der Leitstelle abstellen: Ins Lager (job.store) oder warten (Rückruf mit Rückweg, sonst Reserve).
local function park_at_base(job, record, h, d, tick)
  local entity = h.entity
  if job.store and d and store_harvester(h, d) then
    end_job(job, nil)
    return
  end
  local p = entity.position
  local pos = job.return_pos
  local reason = job.wait_reason or "reserve"
  if reason ~= "reserve" and not pos then reason = "reserve" end
  h.fleet_wait = {surface = entity.surface.index, base = {x = p.x, y = p.y}, depot = d and d.un or record.depot,
    since = tick, reason = reason}
  if reason ~= "reserve" then
    h.fleet_wait.surface, h.fleet_wait.x, h.fleet_wait.y = pos.surface, pos.x, pos.y
  end
  end_job(job, nil)
end

-- Einsatz, Umsetzen, Rückruf: hinfliegen, ankoppeln, dann zum Platz (to_target) oder zur Leitstelle (to_base).
local function step_transfer(job, record, h, tick)
  local entity = h.entity
  local d = depot_of(job.depot) or depot_of(record.depot)
  if job.state == "fly" then
    if job.kind == "recall" and not job.return_pos then
      local p = entity.position
      job.return_pos = {surface = entity.surface.index, x = p.x, y = p.y}
    end
    if not arrived(record, entity.position) then
      fly(record, entity.position)
      return
    end
    stop(record)
    job.state = "couple"
  end
  if job.state == "couple" then
    if not step_coupling(job, record, h) then return end
    h.fleet_wait = nil
    refuel_harvester(record, entity)
    if job.kind == "recall" then
      after_lift(job, record, h, false)
      if not TRANSFER[job.kind] then return end
    else
      job.state = "to_target"
    end
  end
  if record.cargo ~= h.un then
    end_job(job, "Last verloren")
    return
  end
  if job.state == "to_target" then
    local target = job.target
    if target and not fields.quiet(entity.surface.index, target) and d then
      -- Inzwischen lauert dort ein Wurm oder es läuft eine Jagd: anderer Platz, sonst zur Leitstelle.
      fields.release(job.id)
      target = fields.find_spot(d, lib.RANGE, h.un)
      job.target = target
      if target then fields.reserve(job.id, entity.surface.index, target) end
    end
    if not target then
      if not d then
        end_job(job, "keine Leitstelle")
        return
      end
      job.wait_reason = "reserve"
      job.base_spot = base_spot(d, job)
      job.state = "to_base"
    elseif arrived(record, target) then
      stop(record)
      if flyer_lib.drop(record, nil, true) then
        refuel_harvester(record, entity)
        if not harvester.deploy(h) then
          entity.force.print({"arrakis-message.msg-fleet-deploy-failed", gps(entity.surface, entity.position)})
        end
        end_job(job, nil)
      end
      return
    else
      fly(record, target)
      return
    end
  end
  if job.state == "to_base" then
    if not job.base_spot and d then job.base_spot = base_spot(d, job) end
    local spot = job.base_spot
    if not spot then
      end_job(job, "keine Leitstelle")
    elseif arrived(record, spot) then
      stop(record)
      if flyer_lib.drop(record, nil, true) then park_at_base(job, record, h, d, tick) end
    else
      fly(record, spot)
    end
  end
end

local function step(job, tick)
  local record = job.carryall and storage.flyers[job.carryall]
  if not (record and record.entity.valid) then
    if job.state ~= "open" then
      job.carryall = nil
      job.state = "open"
    end
    return
  end
  local h = harvester_of(job)
  if not h then
    end_job(job, "Ernter weg")
    return
  end
  local entity = h.entity
  local carried_by_us = record.cargo == h.un
  if h.state == "carried" and not carried_by_us then
    end_job(job, "fremd getragen")
    return
  end
  if TRANSFER[job.kind] then
    step_transfer(job, record, h, tick)
    return
  end
  if job.kind == "rescue" then
    if (job.state == "fly" or job.state == "couple") and not hunt_running(job) and not record.coupling
        and not record.cargo then
      -- Die Jagd ist vorbei, bevor er angehoben hat (Ernter eingepackt und weg, Wurm tot): nichts zu retten.
      end_job(job, "Jagd vorbei")
      return
    end
    if job.state == "fly" then
      if not job.return_pos then
        local p = entity.position
        job.return_pos = {surface = entity.surface.index, x = p.x, y = p.y}
      end
      if arrived(record, entity.position) then
        stop(record)
        job.state = "couple"
      else
        fly(record, entity.position)
      end
    end
    if job.state == "couple" then
      if step_coupling(job, record, h) then
        refuel_harvester(record, entity)
        after_lift(job, record, h, false)
      end
    end
    if job.kind == "rescue" and job.state == "hover" then
      if not carried_by_us then
        end_job(job, "Last verloren")
      else
        stop(record)
        if calm(job.return_pos) then begin_return(job, h) end
      end
      return
    end
    if job.kind == "rescue" and job.state == "to_base" then
      -- Zur Leitstelle und dort abstellen; der Rückflug kommt aus scan_harvesters, wenn es am Feld ruhig ist.
      local spot = job.base_spot
      if not carried_by_us then
        end_job(job, "Last verloren")
      elseif not spot then
        begin_return(job, h)
      elseif arrived(record, spot) then
        stop(record)
        local ok = flyer_lib.drop(record, nil, true)
        if ok then
          local p = entity.position
          local pos = job.return_pos
          h.fleet_wait = {surface = pos.surface, x = pos.x, y = pos.y, base = {x = p.x, y = p.y}, depot = record.depot,
            since = tick, reason = "rescue"}
          end_job(job, nil)
        end
      else
        fly(record, spot)
      end
    end
    return
  end
  if job.kind == "refuel" then
    if distance(record.entity.position, entity.position) <= lib.REFUEL_RANGE then
      if refuel_harvester(record, entity) == 0 then h.fleet_refuel_after = tick + lib.REFUEL_COOLDOWN end
      end_job(job, nil)
    else
      fly(record, entity.position)
    end
    return
  end
  if job.kind == "unload" then
    if job.state == "fly" then
      if not job.return_pos then
        local p = entity.position
        job.return_pos = {surface = entity.surface.index, x = p.x, y = p.y}
      end
      if arrived(record, entity.position) then
        stop(record)
        job.state = "couple"
      else
        fly(record, entity.position)
      end
    end
    if job.state == "couple" then
      if step_coupling(job, record, h) then
        refuel_harvester(record, entity)
        job.intake = job.intake or nearest_intake(record.entity.surface.index, record.entity.position,
          record.entity.force.index)
        job.state = "to_intake"
      end
    elseif job.state == "to_intake" then
      local spot = job.intake and intake_spot(job.intake)
      if not spot then
        begin_return(job, h)
        return
      end
      if arrived_at_intake(record, spot) then
        stop(record)
        local ok = flyer_lib.drop(record, nil, true)
        if ok then
          -- Rückweg auch am Ernter merken: Geht der Auftrag an der Annahme verloren, holt scan_harvesters ihn zurück.
          h.fleet_home = job.return_pos
          job.state = "unloading"
          job.wait_until = tick + lib.UNLOAD_WAIT
          job.dock_by = tick + lib.DOCK_GRACE
        end
      else
        fly(record, spot)
      end
    elseif job.state == "unloading" then
      local trunk = entity.get_inventory(defines.inventory.car_trunk)
      local empty = trunk and trunk.is_empty()
      local docked = h.state == "docked"
      if (docked and empty) or tick >= job.wait_until or (not docked and tick >= job.dock_by) then
        job.state = "relift"
      end
    end
    if job.state == "relift" then
      -- Erst prüfen, ob er schon hängt: Angehoben steht der Ernter auf der Ablage, sein Ort zählt dann nicht mehr.
      if carried_by_us then
        h.fleet_home = nil
        after_lift(job, record, h, true)
      elseif distance(record.entity.position, entity.position) > lib.ARRIVE then
        fly(record, entity.position)
      else
        stop(record)
        if step_coupling(job, record, h) then
          h.fleet_home = nil
          after_lift(job, record, h, true)
        end
      end
    end
    if job.kind ~= "unload" then step(job, tick) end
    return
  end
  if job.kind == "return" then
    local pos = job.return_pos
    -- Rückflug von der Leitstelle (0.11.0): erst hinfliegen und ankoppeln, dann wie nach dem Anheben (voll erst zur
    -- Annahme; lauert inzwischen wieder ein Wurm, zurück an die Leitstelle).
    if job.state == "fly" then
      if not arrived(record, entity.position) then
        fly(record, entity.position)
        return
      end
      stop(record)
      job.state = "couple"
    end
    if job.state == "couple" then
      if step_coupling(job, record, h) then
        h.fleet_wait = nil
        refuel_harvester(record, entity)
        after_lift(job, record, h, false)
        if job.kind ~= "return" then step(job, tick) end
      end
      return
    end
    if not carried_by_us then
      end_job(job, "Last verloren")
      return
    end
    if arrived(record, pos) then
      stop(record)
      local ok = flyer_lib.drop(record, nil, true)
      if ok then
        refuel_harvester(record, entity)
        local deployed = harvester.deploy(h)
        if not deployed then
          entity.force.print({"arrakis-message.msg-fleet-field-empty", gps(entity.surface, entity.position)})
        end
        end_job(job, nil)
      end
    else
      fly(record, pos)
    end
  end
end

-- Carryalls ohne Auftrag ----------------------------------------------------------------------------------

local function park_spot(record, d)
  local offset = lib.PARK_OFFSETS[(record.un % #lib.PARK_OFFSETS) + 1]
  return {x = d.position.x + offset[1], y = d.position.y + offset[2]}
end

-- Handbetrieb erkennen: Insasse oder ein Ziel, das nicht von hier kommt (Fernbedienung, Plan 4.6).
local function manual_check(record)
  local entity = record.entity
  if record.fleet_mode ~= "auto" then return end
  local driver = entity.get_driver()
  local dest = entity.autopilot_destination
  local foreign = dest ~= nil and not (record.fleet_goal and distance(dest, record.fleet_goal) < 0.01)
  if driver or foreign then
    record.fleet_mode = "manual"
    record.fleet_goal = nil
    local job = record.job and storage.jobs.list[record.job]
    if job then
      job.carryall = nil
      record.job = nil
      if record.cargo == job.harvester then
        end_job(job, "Handbetrieb")
      else
        job.state = "open"
      end
    end
  end
end

local function idle(record, tick)
  local entity = record.entity
  local d = depot_of(record.depot)
  if not d then
    d = nearest_depot(entity.surface.index, entity.force.index, entity.position)
    record.depot = d and d.un or nil
  end
  if not d then return end
  local spot = park_spot(record, d)
  local parked = distance(entity.position, d.position) <= 3
  if record.fleet_mode == "manual" then
    if parked and entity.get_driver() == nil and not record.cargo and entity.autopilot_destination == nil then
      record.fleet_mode = "auto"
    else
      return
    end
  end
  if record.job then return end
  if record.cargo then
    -- Last ohne Auftrag (zum Beispiel nach einem Ladefehler): auf dem Felsplatz der Leitstelle absetzen.
    if parked then
      stop(record)
      flyer_lib.drop(record, nil, true)
    else
      fly(record, d.position)
    end
    return
  end
  if parked then
    if entity.autopilot_destination ~= nil and record.fleet_goal and distance(record.fleet_goal, spot) > 0.01 then stop(record) end
    restock(record, d)
  elseif not (record.fleet_goal and distance(record.fleet_goal, spot) < 0.01) or entity.autopilot_destination == nil then
    fly(record, spot)
  end
end

-- Notregel (Plan 4.5): unter der Reserve für den Heimweg die Last auf Fels absetzen (oder hier, ohne Jagd) und
-- heimfliegen.
local function emergency(record)
  local d = depot_of(record.depot)
  if not d or not record.job then return end
  local home = distance(record.entity.position, d.position)
  if enough_fuel(record, 0, home) then return end
  local job = storage.jobs.list[record.job]
  if record.cargo and job and job.kind == "rescue" and hunt_running(job) then return end
  if record.cargo then flyer_lib.drop(record, nil, true) end
  if job then end_job(job, "Notregel: Treibstoff") end
  record.entity.force.print({"arrakis-message.msg-carryall-low-fuel", gps(record.entity.surface, record.entity.position)})
end

-- Flottenleitung: Soll, Rückruf, Signale (docs/plan-3f.md 1, 3.2) -------------------------------------------

local function fleet_on(d)
  local tech = d.entity.force.technologies[TECH]
  return tech ~= nil and tech.researched
end
lib.fleet_on = fleet_on

local function read_signal(d, name)
  return d.entity.get_signal({type = "virtual", name = name}, defines.wire_connector_id.circuit_red,
    defines.wire_connector_id.circuit_green)
end

-- Statussignale schreiben (values in der Reihenfolge von lib.STATUS_SIGNALS, nil löscht); nur bei einer Änderung.
local function write_signals(d, values)
  local key = values and table.concat(values, ",") or ""
  if d.signals_written == key and d.signal_entity and d.signal_entity.valid then return end
  local cc = ensure_signals(d)
  if not cc then return end
  d.signals_written = key
  local behavior = cc.get_or_create_control_behavior()
  local section = behavior.get_section(1) or behavior.add_section()
  if not section then return end
  for i, name in ipairs(lib.STATUS_SIGNALS) do
    local n = values and values[i] or 0
    if n ~= 0 then
      section.set_slot(i, {value = {type = "virtual", name = name, quality = "normal"}, min = n})
    else
      section.clear_slot(i)
    end
  end
end

-- Ernter-Treibstoff aus der Leitstelle in den Ernter (zuerst, was kein Flugtreibstoff ist), höchstens n Items.
local function fuel_from_depot(d, entity, n)
  local depot_inv = d.entity.get_inventory(defines.inventory.chest)
  local fuel = entity.get_fuel_inventory()
  if not (depot_inv and fuel) then return 0 end
  local flight = prototypes.entity[CARRYALL].burner_prototype.fuel_categories
  local moved = 0
  for pass = 1, 2 do
    for i = 1, #depot_inv do
      if moved >= n then return moved end
      local stack = depot_inv[i]
      if stack.valid_for_read and stack.prototype.fuel_value > 0 then
        local is_flight = false
        for _, category in pairs(stack.prototype.fuel_categories or {}) do
          if flight[category] then is_flight = true end
        end
        if (pass == 1) ~= is_flight and fuel.can_insert(stack) then
          local count = math.min(stack.count, n - moved)
          local k = fuel.insert({name = stack.name, quality = stack.quality.name, count = count})
          if k > 0 then
            stack.count = stack.count - k
            moved = moved + k
          end
        end
      end
    end
  end
  return moved
end

-- Ernter aus dem Lager auf einen Abstellplatz (docs/plan-3f.md 1.7): Item mit Qualität und gespeicherten Werten,
-- betankt, als Reserve dieser Leitstelle. Gibt den Datensatz zurück oder nil.
local function spawn_reserve(d, tick)
  local depot_inv = d.entity.get_inventory(defines.inventory.chest)
  if not depot_inv then return nil end
  local stack
  for i = 1, #depot_inv do
    if depot_inv[i].valid_for_read and depot_inv[i].name == harvester.NAME then stack = depot_inv[i] break end
  end
  if not stack then return nil end
  local surface = d.entity.surface
  local spot = base_spot(d, nil)
  local position = surface.find_non_colliding_position(harvester.NAME, spot, 6, 0.5)
  if not position then return nil end
  local entity = surface.create_entity{name = harvester.NAME, position = position, force = d.entity.force,
    quality = stack.quality, item = stack, raise_built = true}
  if not entity then return nil end
  stack.count = stack.count - 1
  local h = harvester.get(entity) or harvester.register(entity)
  if not h then return nil end
  fuel_from_depot(d, entity, lib.DEPLOY_FUEL)
  harvester.apply_fuel_normalization(entity)
  local p = entity.position
  h.fleet_owner = d.un
  h.fleet_wait = {surface = surface.index, base = {x = p.x, y = p.y}, depot = d.un, since = tick, reason = "reserve"}
  return h
end

local function harvester_items(d)
  local depot_inv = d.entity.get_inventory(defines.inventory.chest)
  local n = 0
  for _, item in pairs(depot_inv and depot_inv.get_contents() or {}) do
    if item.name == harvester.NAME then n = n + item.count end
  end
  return n
end

-- Leitstelle eines Ernters: wartend an seiner Leitstelle, getragen von einem ihrer Carryalls, sonst die betreuende.
local function home_of(h)
  local fw = h.fleet_wait
  local d = fw and fw.depot and depot_of(fw.depot)
  if d then return d end
  if h.state == "carried" then
    local record = h.carried_by and storage.flyers[h.carried_by]
    return record and record.kind == "carryall" and depot_of(record.depot) or nil
  end
  return covering_depot(h.entity)
end

-- Zählung je Leitstelle (docs/plan-3f.md 1.2, 1.8). Aktiv: aufgebaut, aufbauend, einpackend, getragen, wartend nach
-- Rettung oder Rückruf oder in einem Auftrag; Reserve: an der Leitstelle ohne Rückweg (plus Items im Lager).
local function census(list)
  local hunted = {}
  for _, hunt in pairs(storage.hunts and storage.hunts.list or {}) do
    if not hunt.outcome and hunt.target and hunt.target.valid then hunted[hunt.target.unit_number] = true end
  end
  local per = {}
  for un in pairs(storage.depots) do
    local d = depot_of(un)
    if d then per[un] = {active = {}, reserve = {}, idle = {}, free = 0, rescues = 0, spice = 0, alarm = 0, storing = 0} end
  end
  local uns = {}
  for un in pairs(storage.harvesters) do table.insert(uns, un) end
  table.sort(uns)
  for _, un in ipairs(uns) do
    local h = storage.harvesters[un]
    local e = h.entity
    local d = e and e.valid and home_of(h)
    local c = d and per[d.un]
    if c then
      local job = job_of_harvester(un)
      local fw = h.fleet_wait
      if fw and fw.reason == "reserve" and not job then
        table.insert(c.reserve, h)
      elseif job and job.kind == "recall" and job.store then
        c.storing = c.storing + 1
      elseif ACTIVE[h.state] or h.state == "carried" or fw or job then
        table.insert(c.active, h)
      elseif h.state ~= "docked" then
        table.insert(c.idle, h)
      end
      local trunk = e.get_inventory(defines.inventory.car_trunk)
      if trunk then c.spice = c.spice + trunk.get_item_count("spice-sand") end
      if hunted[un] then c.alarm = 1 end
    end
  end
  for _, record in ipairs(list) do
    local c = record.depot and per[record.depot]
    if c and free_carryall(record) then c.free = c.free + 1 end
  end
  for _, job in pairs(storage.jobs.list) do
    local record = job.carryall and storage.flyers[job.carryall]
    local c = record and record.depot and per[record.depot]
    if c and job.kind == "rescue" then c.rescues = c.rescues + 1 end
  end
  return per
end

local function depot_job(d, kind)
  for _, job in pairs(storage.jobs.list) do
    if job.kind == kind and job.depot == d.un then return job end
  end
  return nil
end

-- Rückruf beginnt: Einsätze, Umsetzen und Rückflüge dieser Leitstelle enden; wer schon hängt, fliegt zur Leitstelle.
local function cancel_for_recall(d)
  local list = {}
  for _, job in pairs(storage.jobs.list) do table.insert(list, job) end
  table.sort(list, function(a, b) return a.id < b.id end)
  for _, job in ipairs(list) do
    local h = harvester_of(job)
    if h and (job.kind == "deploy" or job.kind == "move" or job.kind == "return") and home_of(h) == d then
      local record = job.carryall and storage.flyers[job.carryall]
      if record and record.cargo == h.un then
        fields.release(job.id)
        job.wait_reason = job.kind == "return" and "recall" or "reserve"
        job.priority = lib.RECALL_URGENT
        job.base_spot = base_spot(d, job)
        convert(job, "recall", "to_base")
      else
        end_job(job, "Rückruf")
      end
    end
  end
end

-- Ein Takt für eine Leitstelle: Signale lesen und schreiben, dann höchstens ein neuer Auftrag (Plan 3.2).
local function control_depot(d, c, tick)
  if not fleet_on(d) then
    d.soll, d.recall, d.census = 0, false, nil
    write_signals(d, nil)
    return false
  end
  local h_signal, r_signal = read_signal(d, "signal-H"), read_signal(d, "signal-R")
  d.last_h, d.last_r = h_signal, r_signal
  local soll = h_signal > 0 and math.min(h_signal, lib.TARGET_MAX) or (d.target or 0)
  d.soll = soll
  local was = d.recall
  d.recall = r_signal > 0 or d.recall_button == true
  local items = harvester_items(d)
  d.census = {active = #c.active, reserve = #c.reserve + items, items = items, free = c.free, rescues = c.rescues,
    spice = c.spice, alarm = c.alarm, storing = c.storing}
  write_signals(d, {#c.active, #c.reserve + items, c.free, c.rescues, c.spice, c.alarm})
  if d.recall then
    if not was then cancel_for_recall(d) end
    for _, h in ipairs(c.active) do
      local e = h.entity
      if not storage.job_of[h.un] and not h.fleet_wait and h.state ~= "carried" and not driven_by_player(e) then
        local empty = e.get_inventory(defines.inventory.car_trunk).is_empty()
        new_job("recall", h, {depot = d.un, priority = lib.RECALL_URGENT, store = h.fleet_owner == d.un and empty or nil,
          wait_reason = "recall"})
        return false
      end
    end
    return false
  end
  if soll <= 0 then return false end
  local s = d.surface_index
  -- Umsetzen: Feld leer, oder ein eigener Ernter steht mobil herum (Absetzen ging daneben).
  local movers = {}
  for _, h in ipairs(c.active) do
    if h.state == "deployed" and h.status == "field_empty" then table.insert(movers, h) end
  end
  for _, h in ipairs(c.idle) do
    if h.fleet_owner == d.un and h.state == "mobile" and h.entity.speed == 0 then table.insert(movers, h) end
  end
  for _, h in ipairs(movers) do
    if not storage.job_of[h.un] and not driven_by_player(h.entity) then
      local spot = fields.find_spot(d, lib.RANGE, h.un)
      -- Ohne Platz erst zur Leitstelle, wenn die Feldsuche alle Chunks gezählt hat.
      if not spot and fields.queue_length() > 0 then return true end
      local job = new_job("move", h, {depot = d.un, target = spot})
      if spot then fields.reserve(job.id, s, spot) end
      return true
    end
  end
  if #c.active < soll then
    if depot_job(d, "deploy") then return true end
    local spot = fields.find_spot(d, lib.RANGE, nil)
    if not spot then return true end
    local h = c.reserve[1] or spawn_reserve(d, tick)
    if h then
      local job = new_job("deploy", h, {depot = d.un, target = spot})
      fields.reserve(job.id, s, spot)
    end
    return true
  elseif #c.active > soll then
    -- Überzählige: nur eigene (Plan 1.3), zuerst die an der Leitstelle wartenden, sonst der zuletzt eingesetzte.
    local pick_h
    for _, h in ipairs(c.active) do
      if h.fleet_owner == d.un and not storage.job_of[h.un] and h.state ~= "carried" and not driven_by_player(h.entity) then
        if h.fleet_wait then
          pick_h = h
          break
        end
        if not pick_h or h.un > pick_h.un then pick_h = h end
      end
    end
    if pick_h then new_job("recall", pick_h, {depot = d.un, store = true, wait_reason = "reserve"}) end
  end
  return true
end

local function control(tick, list)
  local per = census(list)
  local searching = {}
  local uns = {}
  for un in pairs(per) do table.insert(uns, un) end
  table.sort(uns)
  for _, un in ipairs(uns) do
    local d = depot_of(un)
    if d and control_depot(d, per[un], tick) then table.insert(searching, d) end
  end
  fields.tick(tick, searching, lib.RANGE)
end

-- Fenster: Soll-Zahl setzen (0 = aus) und Rückruf-Knopf umschalten.
function lib.set_target(d, n)
  d.target = math.max(0, math.min(lib.TARGET_MAX, math.floor(n)))
end

function lib.set_recall_button(d, on)
  d.recall_button = on and true or false
end

lib.census = census
lib.control = control

-- Takt ---------------------------------------------------------------------------------------------

function lib.tick(tick)
  -- Laufende Aufträge auch ohne Leitstelle zu Ende führen (oder beenden, wenn Ernter oder Carryall fehlen).
  if next(storage.depots) == nil and next(storage.jobs.list) == nil then return end
  if storage.fleet_pause_until then
    if tick < storage.fleet_pause_until then return end
    storage.fleet_pause_until = nil
  end
  scan_hunts(tick)
  local list = carryalls()
  if tick % 60 == 0 then
    scan_harvesters(tick)
    control(tick, list)
  end
  for _, record in ipairs(list) do
    manual_check(record)
  end
  dispatch(tick)
  local jobs = {}
  for _, job in pairs(storage.jobs.list) do table.insert(jobs, job) end
  table.sort(jobs, function(a, b) return a.id < b.id end)
  for _, job in ipairs(jobs) do
    if storage.jobs.list[job.id] then step(job, tick) end
  end
  for _, record in ipairs(list) do
    if record.entity.valid then
      emergency(record)
      idle(record, tick)
    end
  end
end

-- Ereignisse ------------------------------------------------------------------------------------------

local function on_built(event)
  local entity = event.entity or event.destination
  if not (entity and entity.valid) then return end
  if entity.name == DEPOT then
    register_depot(entity)
  elseif entity.name == CARRYALL then
    local record = carryall_record(entity)
    if record and not record.depot then
      local d = nearest_depot(entity.surface.index, entity.force.index, entity.position, lib.ADOPT_RADIUS)
      record.depot = d and d.un or nil
    end
  end
end

local function depot_removed(un)
  local d = storage.depots[un]
  if d and d.signal_entity and d.signal_entity.valid then d.signal_entity.destroy() end
  storage.depots[un] = nil
  for _, record in pairs(storage.flyers) do
    if record.kind == "carryall" and record.depot == un then record.depot = nil end
  end
end

local function on_removed(event)
  local entity = event.entity
  if entity and entity.valid and entity.name == DEPOT then depot_removed(entity.unit_number) end
end

local function on_object_destroyed(event)
  local entry = storage.reg[event.registration_number]
  if not (entry and entry.kind == "depot") then return end
  storage.reg[event.registration_number] = nil
  depot_removed(entry.un)
end

-- Für den Prüfstand und /arrakis-uninstall.
lib.depot_of = depot_of
lib.register_depot = register_depot
lib.fill_of = fill_of
lib.onboard_energy = onboard_energy
lib.fuel_gain = fuel_gain
lib.end_job = end_job
lib.job_of_harvester = job_of_harvester

-- Ruhe nach /arrakis-uninstall (Ticks): Die Mod soll danach entfernt werden, bis dahin hebt kein Carryall mehr an.
lib.UNINSTALL_PAUSE = 10 * 60 * 60

function lib.uninstall()
  for _, job in pairs(storage.jobs.list) do end_job(job, "uninstall") end
  for _, record in pairs(storage.flyers) do
    if record.kind == "carryall" and record.entity.valid then stop(record) end
  end
  storage.fleet_pause_until = game.tick + lib.UNINSTALL_PAUSE
end
flyer_lib.before_uninstall = lib.uninstall

lib.events =
{
  [defines.events.on_built_entity] = on_built,
  [defines.events.on_robot_built_entity] = on_built,
  [defines.events.script_raised_built] = on_built,
  [defines.events.script_raised_revive] = on_built,
  [defines.events.on_entity_cloned] = on_built,
  [defines.events.on_entity_died] = on_removed,
  [defines.events.on_player_mined_entity] = on_removed,
  [defines.events.on_robot_mined_entity] = on_removed,
  [defines.events.script_raised_destroy] = on_removed,
  [defines.events.on_object_destroyed] = on_object_destroyed,
  [defines.events.on_resource_depleted] = fields.on_resource_depleted
}

lib.on_nth_tick =
{
  [30] = function(event) lib.tick(event.tick) end
}

return lib
