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

local harvester = require("scripts.harvester")
local flyer_lib = require("scripts.flyer")
local speed = require("prototypes.ornithopter-speed")

local lib = {}

local DEPOT = "arrakis-depot"
local CARRYALL = flyer_lib.CARRYALL

-- Reichweite der Leitstelle (Kacheln, Mod-Einstellung, Plan 1.3).
lib.RANGE = settings.startup["arrakis-depot-range"].value
-- Ein neu gebauter Carryall gehört zur nächsten Leitstelle in so vielen Kacheln (Plan 1.5).
lib.ADOPT_RADIUS = 20
-- Prioritäten (Plan 4.3).
lib.PRIORITY = {rescue = 100, refuel = 60, unload = 50, ["return"] = 40}
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
    storage.depots[un] = nil
    return nil
  end
  return d
end

local function register_depot(entity)
  local un = entity.unit_number
  local d = storage.depots[un]
  if d then return d end
  local position = entity.position
  d = {un = un, entity = entity, surface_index = entity.surface.index, position = {x = position.x, y = position.y},
    force_index = entity.force.index}
  storage.depots[un] = d
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
      if h and h.state ~= "carried" and not driven_by_player(h.entity) and covering_depot(h.entity) then
        local job = job_of_harvester(h.un)
        if job and job.kind ~= "rescue" and not (job.carryall and storage.flyers[job.carryall]
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

local function scan_harvesters(tick)
  for un, h in pairs(storage.harvesters) do
    local entity = h.entity
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
    local pa, pb = lib.PRIORITY[a.kind], lib.PRIORITY[b.kind]
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

local function step_coupling(job, record, h)
  if record.cargo == h.un then return true end
  if not record.coupling then
    local ok, why = flyer_lib.couple(record, h.entity)
    if not ok then
      end_job(job, "Ankoppeln: " .. tostring(why))
    end
  end
  return false
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
        job.state = "hover"
        refuel_harvester(record, entity)
      end
    elseif job.state == "hover" then
      if not carried_by_us then
        end_job(job, "Last verloren")
      elseif not hunt_running(job) then
        if fill_of(entity) >= lib.UNLOAD_FILL then
          local intake = nearest_intake(record.entity.surface.index, record.entity.position, record.entity.force.index)
          if intake then
            job.intake = intake
            convert(job, "unload", "to_intake")
          else
            begin_return(job, h)
          end
        else
          begin_return(job, h)
        end
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
        begin_return(job, h)
      elseif distance(record.entity.position, entity.position) > lib.ARRIVE then
        fly(record, entity.position)
      else
        stop(record)
        if step_coupling(job, record, h) then begin_return(job, h) end
      end
    end
    return
  end
  if job.kind == "return" then
    local pos = job.return_pos
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

-- Takt ---------------------------------------------------------------------------------------------

function lib.tick(tick)
  if next(storage.depots) == nil then return end
  if storage.fleet_pause_until then
    if tick < storage.fleet_pause_until then return end
    storage.fleet_pause_until = nil
  end
  scan_hunts(tick)
  if tick % 60 == 0 then scan_harvesters(tick) end
  local list = carryalls()
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
  [defines.events.on_object_destroyed] = on_object_destroyed
}

lib.on_nth_tick =
{
  [30] = function(event) lib.tick(event.tick) end
}

return lib
