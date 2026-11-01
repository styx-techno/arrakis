-- T18 Wärme: echter Code: Prüfstand-Test (aus t_jagd.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_jagd.lua.

local common = require("scripts.testbench.gemeinsam_jagd")
local harvester = require("scripts.harvester")
local intake = require("scripts.intake")
local terrain = require("scripts.terrain")
local vibration_lib = require("scripts.vibration")
local worms_lib = require("scripts.worms")
local INTAKE = common.INTAKE
local ROCK = common.ROCK
local SAND = common.SAND
local ERUPTION = common.ERUPTION
local WORM_FORCE = common.WORM_FORCE
local DECAY = common.DECAY
local REST_MIN = common.REST_MIN
local REST_MAX = common.REST_MAX
local MAX_HUNTS = common.MAX_HUNTS
local HEAT_TOLERANCE = common.HEAT_TOLERANCE
local valid = common.valid
local copy_pos = common.copy_pos
local read = common.read
local check = common.check
local near = common.near
local to_mid = common.to_mid
local tiles = common.tiles
local gas = common.gas
local render_ok = common.render_ok
local car_state = common.car_state
local status_name = common.status_name
local zero_around = common.zero_around
local nine_zero = common.nine_zero
local foreign_regular = common.foreign_regular
local worm_hostile = common.worm_hostile
local hunt_text = common.hunt_text
local make = common.make
local new_harvester = common.new_harvester
local new_vehicle = common.new_vehicle
local new_flyer = common.new_flyer
local driver_of = common.driver_of
local keep_key = common.keep_key
local again = common.again
local verdict = common.verdict
local fail = common.fail
local lanes_init = common.lanes_init
local lane_step = common.lane_step
local summary = common.summary
local isolate_cleanup = common.isolate_cleanup
local timeline = common.timeline
local check_sign = common.check_sign
local isolate_start = common.isolate_start

local migrate = require("scripts.migrate")
local DUST = "arrakis-sand-dust"
local SIGNAL = "arrakis-wormsign"
local SOUNDS = {"arrakis-wormsign", "arrakis-rumble"}
local OVERLAY = "arrakis-vibration-overlay"
local TIPS = {"arrakis-briefing", "arrakis-wormsign-tip"}
local T18_FORCE = "arrakis-t18"
local UNREST = 600
local WORMSIGN = 1000
local CAREFUL_LOW = vibration_lib.CAREFUL_LOW
local CAREFUL_PACKING = vibration_lib.WEIGHTS.by_state.careful_packing
-- Wärme nach 3 Takten mit Gewicht w ab 0: w · (1 + 0,98 + 0,98²).
local THREE_TAKES = 1 + DECAY + DECAY * DECAY
-- Gewichte (Plan 4.3).
local WEIGHT =
{
  deployed = 30, deploying = 0, packing = 30, moving = 10, standing = 0, docked = 0,
  car = 4, tank = 8, spider = 6, locomotive = 6,
  big_drill = 8, drill = 3, pumpjack = 2, assembler = 1, furnace = 1
}
-- Tempo der Fahrzeuge in den Gewichtsmessungen (Kacheln/s): fährt sicher (≥ 0,06), bleibt in seinem Chunk.
local CRUISE = 1

local function entity_exists(name)
  local ok, exists = pcall(function() return prototypes.entity[name] ~= nil end)
  return ok and exists
end

-- Tempomat: Gas, solange das Fahrzeug langsamer als tps fährt.
local function cruise(car, driver, tps)
  if not valid(car) then return end
  gas(car, driver, math.abs(car.speed) * 60 < tps)
end

-- Spinne hin und her zwischen a und b; das Ziel wechselt, bevor sie ankommt (sie bleibt nie stehen).
local function patrol(spider, lane, tb)
  if not valid(spider) then return end
  local target = lane.leg == 2 and lane.b or lane.a
  if tb.distance(spider.position, target) < 5 then
    lane.leg = lane.leg == 2 and 1 or 2
    target = lane.leg == 2 and lane.b or lane.a
    pcall(function() spider.autopilot_destination = target end)
  elseif not read(function() return spider.autopilot_destination end) then
    pcall(function() spider.autopilot_destination = target end)
  end
end

-- Strom für ein Gebäude mit Mitte p (Kachelmitte): Schnittstelle 2×2 und Mittelmast westlich (wie T4).
local function power(run, tb, s, p, force)
  local n, m = math.floor(p.x), math.floor(p.y)
  local eei = make(run, tb, s, {name = "electric-energy-interface", position = {x = n - 6, y = m + 1}, force = force})
  local pole = make(run, tb, s, {name = "medium-electric-pole", position = {x = n - 3.5, y = m + 0.5}, force = force})
  return eei ~= nil and pole ~= nil
end

-- Erz unter einem Bohrer (Kacheln um die Mitte, radius 2 = 5×5).
local function ore(surface, p, name, radius, amount)
  local n, m = math.floor(p.x), math.floor(p.y)
  local placed = 0
  for x = n - radius, n + radius do
    for y = m - radius, m + radius do
      if surface.create_entity{name = name, position = {x + 0.5, y + 0.5}, amount = amount or 10000} then placed = placed + 1 end
    end
  end
  return placed
end

-- T18 Wärme: echter Code ---------------------------------------------------------------------------
-- Fläche ±300 Kacheln um den Ursprung (x = 32 000 ist eine Sektor-Ecke). Zellen sind Chunks im Raster von 3 Chunks:
-- cx, cy ∈ Ursprung + {−8, −5, −2, 1, 4, 7}; eine Quelle in Zelle (i, j) beeinflusst nur die 3×3 Chunks um sich, und W an
-- der Nachbarzelle liest keinen davon. Reihen (j): 1 Ernter-Zustände (Schritt 3), 2 Fahrzeuge (3), 3 Lokomotive (3) und
-- feste Quellen (4), 4 feste Quellen (4), Zeitlinie (2, Zelle 4 allein im Sektor), Zerfall (5); 5 Nachbarschaft (6) und
-- Erstbefüllung (7); 6 Vorsichtsmodus (8 bis 10) und Prüfstand-Sperre (11).

local T18_HALF = 300
local T18_GRID = {-8, -5, -2, 1, 4, 7}

-- Zelle (i, j): Chunk, Mitte (ganze Kachel), chunk_key.
local function t18_cell(d, i, j)
  local cx, cy = d.bcx + T18_GRID[i], d.bcy + T18_GRID[j]
  return {cx = cx, cy = cy, x = cx * 32 + 16, y = cy * 32 + 16, key = vibration_lib.chunk_key(cx, cy)}
end

-- Kachelmitte in Zelle (i, j), dx, dy Kacheln von der Mitte.
local function t18_pos(d, i, j, dx, dy)
  local c = t18_cell(d, i, j)
  return {x = c.x + (dx or 0) + 0.5, y = c.y + (dy or 0) + 0.5}
end

local t18_steps = {}

-- Schritt 1: Prototypen, storage, Sandwurm-Force.
function t18_steps.s1_check(run, tb, d, s)
  local failed = {}
  local eruption = read(function() return prototypes.entity[ERUPTION] end)
  check(failed, eruption ~= nil and eruption.type == "explosion", "Eruption " .. ERUPTION .. " fehlt (oder keine explosion)")
  check(failed, read(function() return prototypes.trivial_smoke[DUST] end) ~= nil, "Staub " .. DUST .. " fehlt")
  check(failed, read(function() return prototypes.virtual_signal[SIGNAL] end) ~= nil, "Signal " .. SIGNAL .. " fehlt")
  for _, path in ipairs(SOUNDS) do
    check(failed, read(function() return helpers.is_valid_sound_path(path) end) == true, "Geräusch " .. path .. " fehlt")
  end
  local shortcut = read(function() return prototypes.shortcut[OVERLAY] end)
  check(failed, shortcut ~= nil, "Verknüpfung " .. OVERLAY .. " fehlt")
  if shortcut then check(failed, read(function() return shortcut.toggleable end) == true, "Verknüpfung " .. OVERLAY .. " nicht toggleable") end
  -- Tipps: LuaPrototypes hat keine Tabelle dafür; verbindlich prüft tools/check/checks.lua.
  for _, name in ipairs(TIPS) do
    local ok, history = pcall(prototypes.get_history, "tips-and-tricks-item", name)
    local text
    if not ok then
      text = "nicht lesbar (" .. tostring(history) .. ")"
    elseif history then
      text = "angelegt von " .. tostring(history.created)
    else
      text = "nil"
    end
    tb.log(run, "MESSUNG", "1) Tipp " .. name .. ": get_history " .. text)
  end
  local vib = storage.vib or {}
  local hunts = storage.hunts or {}
  local parts =
  {
    {"schema", storage.schema == migrate.SCHEMA}, {"rng", storage.rng ~= nil}, {"grace", type(storage.grace) == "table"},
    {"vib.sources", type(vib.sources) == "table"}, {"vib.heat", type(vib.heat) == "table"},
    {"vib.rumble", type(vib.rumble) == "table"}, {"vib.overlay", type(vib.overlay) == "table"},
    {"vib.testbench", type(vib.testbench) == "table"}, {"hunts.list", type(hunts.list) == "table"},
    {"hunts.next_id", type(hunts.next_id) == "number"}, {"sector_cooldown", type(storage.sector_cooldown) == "table"},
    {"worm_stats", type(storage.worm_stats) == "table"}, {"migration", type(storage.migration) == "table"}
  }
  for _, part in ipairs(parts) do check(failed, part[2], "storage." .. part[1] .. " fehlt") end
  check(failed, game.forces[WORM_FORCE] ~= nil, "Sandwurm-Force " .. WORM_FORCE .. " fehlt")
  check(failed, worm_hostile(d.force), "Sandwurm-Force nicht feindlich zu " .. T18_FORCE)
  check(failed, worm_hostile(game.forces.player), "Sandwurm-Force nicht feindlich zu player")
  return verdict(run, tb, 1, "Prototypen, storage, Sandwurm-Force", failed,
    "Eruption, Staub, Signal, 2 Geräusche, Verknüpfung, 13 storage-Tabellen, Force geprüft")
end

-- Schritt 2: Zeitlinie eines Ernters ab kaltem Sand bis zum Wurmzeichen.
function t18_steps.s2_build(run, tb, d, s)
  local position = t18_pos(d, 4, 4)
  s.car = new_harvester(run, tb, s, position, {force = d.force, coal = 20, field = 1000})
  if not s.car then return fail(run, tb, 2, "Aufbau ging nicht (Einzelheiten in der Datei)") end
  s.key = keep_key(s, position)
  local h = harvester.get(s.car)
  if not h then return fail(run, tb, 2, "Ernter nicht eingetragen (raise_built)") end
  local ok, reason = harvester.deploy(h)
  if not ok then return fail(run, tb, 2, "Aufbauen ging nicht: " .. tostring(reason)) end
  s.k, s.last, s.start, s.failed = 0, 0, game.tick, {}
  return 1
end

function t18_steps.s2_watch(run, tb, d, s)
  if not valid(s.car) then return fail(run, tb, 2, "Ernter weg") end
  if timeline(s, s.car, s.failed) == true then return 1 end
  return "poll"
end

function t18_steps.s2_end(run, tb, d, s)
  local failed = s.failed
  local hunt = s.hunt
  local surface = tb.surface()
  check_sign(failed, s, "", true)
  local tag_text = "–"
  if hunt then
    local cx, cy = vibration_lib.chunk_of_key(hunt.origin_key)
    local charted = read(function() return d.force.is_chunk_charted(surface, {x = cx, y = cy}) end)
    if charted then
      tag_text = valid(hunt.tag) and "gültig" or "fehlt"
      check(failed, valid(hunt.tag), "Kartenmarkierung fehlt, obwohl der Chunk kartiert ist")
    else
      tag_text = "Chunk nicht kartiert"
      tb.log(run, "INFO", "2) Chunk des Wurmzeichens nicht kartiert (force.chart ohne Spieler): Markierung nicht prüfbar [V6]")
    end
    local ring, text, tag = hunt.renders.ring, hunt.renders.text, hunt.tag
    worms_lib.end_hunt(hunt, "escaped", "quiet")
    check(failed, storage.hunts.list[hunt.id] == nil, "Jagd nach end_hunt noch da")
    check(failed, nine_zero(surface, hunt.origin_key), "9 Chunks um den Ursprung nicht 0")
    local until_tick = vibration_lib.resting(surface.index, hunt.sector_key)
    local rest = until_tick and (until_tick - game.tick)
    check(failed, rest ~= nil and rest >= REST_MIN and rest <= REST_MAX, "Ruhe " .. tostring(rest) .. " Ticks statt 7200 bis 14400")
    local g = worms_lib.grace_snapshot(d.force)
    check(failed, g ~= nil and g.first_hunt_done == true, "first_hunt_done nicht gesetzt")
    check(failed, not render_ok(ring) and not render_ok(text), "Ring oder Sekunden nach dem Ende noch da")
    check(failed, not valid(tag), "Kartenmarkierung nach dem Ende noch da")
    s.rest = rest
  end
  tb.log(run, "MESSUNG", string.format("2) T_d = %s; Unruhe Tick %s (T_d + %s, Takt %s); Wurmzeichen Tick %s (T_d + %s, Takt %s, Wärme %s)",
    tostring(s.td), tostring(s.unrest_tick), s.unrest_tick and s.td and tostring(s.unrest_tick - s.td) or "–", tostring(s.unrest_k),
    tostring(s.sign_tick), s.sign_tick and s.td and tostring(s.sign_tick - s.td) or "–", tostring(s.sign_k),
    s.sign_heat and string.format("%.2f", s.sign_heat) or "–"))
  return verdict(run, tb, 2, "Zeitlinie bis zum Wurmzeichen", failed, string.format("Unruhe Takt %s, Wurmzeichen Takt %s, %s; Markierung %s, Ruhe %s Ticks",
    tostring(s.unrest_k), tostring(s.sign_k), hunt_text(tb, hunt), tag_text, tostring(s.rest)))
end

-- Schritt 3: Gewichte. Jede Quelle in ihrer Zelle; Messung über 3 Takte ab 0 in den 3×3 Chunks um die Quelle.
function t18_steps.s3_build(run, tb, d, s)
  local force = d.force
  local surface = tb.surface()
  s.src = {}
  local function add(label, entity, expect, extra)
    local entry = {label = label, entity = entity, expect = expect}
    for key, value in pairs(extra or {}) do entry[key] = value end
    table.insert(s.src, entry)
    if entity then keep_key(s, entity.position) end
    return entry
  end
  -- Reihe 1: Ernter-Zustände.
  add("Ernter aufgebaut", new_harvester(run, tb, s, t18_pos(d, 1, 1), {force = force, coal = 10, field = 1000}), WEIGHT.deployed,
    {state = "deployed", deploy = true})
  add("Ernter beim Aufbauen", new_harvester(run, tb, s, t18_pos(d, 2, 1), {force = force, coal = 10, field = 1000}), WEIGHT.deploying,
    {state = "deploying", late_deploy = true})
  add("Ernter beim Einpacken von Hand", new_harvester(run, tb, s, t18_pos(d, 3, 1), {force = force, coal = 10, field = 1000}),
    WEIGHT.packing, {state = "packing", deploy = true, pack = true})
  add("Ernter mobil fahrend", new_harvester(run, tb, s, t18_pos(d, 4, 1, -12, 0), {force = force, coal = 20, driver = true}),
    WEIGHT.moving, {state = "mobile", drive = true})
  add("Ernter mobil stehend", new_harvester(run, tb, s, t18_pos(d, 5, 1), {force = force, coal = 10}), WEIGHT.standing, {state = "mobile"})
  -- Angedockt: Annahme auf Fels (±6 Kacheln), Ernter 3,9 Kacheln östlich, seine Ostkante über Sand.
  local c = t18_cell(d, 6, 1)
  local p = {x = c.x - 4, y = c.y}
  tiles(surface, p.x - 6, p.y - 6, p.x + 4, p.y + 4, ROCK)
  local intake_entity = make(run, tb, s, {name = INTAKE, position = p, force = force, raise_built = true})
  local docked = new_harvester(run, tb, s, {x = p.x + 3.9, y = p.y}, {force = force, coal = 10})
  local docked_entry = add("Ernter angedockt (Ecke im Sand)", docked, WEIGHT.docked, {state = "docked"})
  local record = valid(intake_entity) and intake.get(intake_entity)
  local h = docked and harvester.get(docked)
  docked_entry.dock_ok = record and not record.bad and h and harvester.dock(h, record) or false
  docked_entry.corner = docked and terrain.has_sand_under(docked)
  -- Reihe 2: Fahrzeuge.
  add("Auto fahrend", new_vehicle(run, tb, s, "car", t18_pos(d, 1, 2, -12, 0), {force = force, coal = 10, driver = true, orientation = 0.25}),
    WEIGHT.car, {drive = true})
  add("Auto stehend", new_vehicle(run, tb, s, "car", t18_pos(d, 2, 2), {force = force, coal = 10, orientation = 0.25}), 0)
  add("Panzer fahrend", new_vehicle(run, tb, s, "tank", t18_pos(d, 3, 2, -12, 0), {force = force, coal = 10, driver = true, orientation = 0.25}),
    WEIGHT.tank, {drive = true})
  local sc = t18_cell(d, 4, 2)
  -- Spidertron zwischen x − 10 und x + 10: bleibt in seinem Chunk, die 3×3-Summe um ihn fasst jeden Beitrag.
  add("Spidertron mit Ziel", new_vehicle(run, tb, s, "spidertron", {x = sc.x - 10, y = sc.y}, {force = force}), WEIGHT.spider,
    {patrol = {a = {x = sc.x + 10, y = sc.y}, b = {x = sc.x - 10, y = sc.y}, leg = 1}})
  add("Spidertron stehend", new_vehicle(run, tb, s, "spidertron", t18_pos(d, 5, 2), {force = force}), 0)
  local fc = t18_cell(d, 6, 2)
  add("Ornithopter fliegend", new_flyer(run, tb, s, {x = fc.x - 10, y = fc.y}, {force = force, pilot = true}), 0,
    {patrol = {a = {x = fc.x + 10, y = fc.y}, b = {x = fc.x - 10, y = fc.y}, leg = 1}, flyer = true})
  -- Reihe 3, Zelle 1: Lokomotive auf Schienen (nur weight_of mit train.speed > 0).
  -- Aufbauen schon jetzt (5 s, fertig vor s3_run in 330 Ticks); eingepackt wird im ersten s3_run (10 s, reicht bis m1).
  for _, entry in ipairs(s.src) do
    local h = entry.deploy and valid(entry.entity) and harvester.get(entry.entity)
    if h then harvester.deploy(h) end
  end
  local lc = t18_cell(d, 1, 3)
  s.loco_text = "nicht gebaut"
  local rails = 0
  for x = lc.x - 15, lc.x + 15, 2 do
    if make(run, tb, s, {name = "straight-rail", position = {x = x, y = lc.y + 1}, direction = defines.direction.east, force = force}) then
      rails = rails + 1
    end
  end
  local loco = make(run, tb, s, {name = "locomotive", position = {x = lc.x, y = lc.y + 1}, orientation = 0.25, force = force, raise_built = true})
  if loco then
    tb.fuel(loco, "coal", 5)
    local ok, err = pcall(function()
      loco.train.manual_mode = true
      loco.train.speed = 0.05
    end)
    local speed = read(function() return loco.train.speed end)
    s.loco_weight = vibration_lib.weight_of(loco)
    s.loco_text = string.format("%d Schienen, train.speed %s, weight_of %s%s", rails, tb.num(speed, 3), tostring(s.loco_weight),
      ok and "" or (" (" .. tostring(err) .. ")"))
    s.loco_moving = type(speed) == "number" and speed > 0
    pcall(function() loco.train.speed = 0 end)
  end
  s.start = game.tick
  return 330
end

-- Jeden Tick: fahren; vor der Messung einpacken und das zweite Aufbauen beginnen; m0 Wärme 0, m1 nach 3 Takten lesen.
function t18_steps.s3_run(run, tb, d, s)
  local surface = tb.surface()
  if not s.m0 then
    for _, entry in ipairs(s.src) do
      local h = valid(entry.entity) and harvester.get(entry.entity)
      if h and entry.deploy and h.state == "mobile" then harvester.deploy(h) end
      if h and entry.pack then entry.pack_ok = harvester.toggle(entry.entity, nil) end
    end
    s.m0 = game.tick + to_mid(90)
    s.m1 = s.m0 + 180
  end
  local now = game.tick
  for _, entry in ipairs(s.src) do
    local entity = entry.entity
    if valid(entity) then
      if entry.drive then cruise(entity, driver_of(s, entity), CRUISE) end
      if entry.patrol then patrol(entity, entry.patrol, tb) end
      if entry.late_deploy and now == s.m0 - 20 then
        local h = harvester.get(entity)
        if h then entry.deploy_ok = harvester.deploy(h) end
      end
    end
  end
  if now == s.m0 then
    for _, entry in ipairs(s.src) do
      local entity = entry.entity
      if valid(entity) then
        entry.key = vibration_lib.key_of(entity.position)
        zero_around(surface, entry.key)
        entry.w0 = vibration_lib.weight_of(entity)
        entry.state0 = car_state(entity)
      end
    end
  elseif now >= s.m1 then
    local failed, parts = {}, {}
    for _, entry in ipairs(s.src) do
      local entity = entry.entity
      if not valid(entity) then
        check(failed, false, entry.label .. ": nicht gebaut oder weg")
      else
        local w1 = vibration_lib.weight_of(entity)
        local value = entry.key and vibration_lib.sum3(surface.index, entry.key) or -1
        local expected = entry.expect * THREE_TAKES
        check(failed, entry.w0 == entry.expect and w1 == entry.expect,
          entry.label .. ": weight_of " .. tostring(entry.w0) .. "/" .. tostring(w1) .. " statt " .. entry.expect)
        check(failed, near(value, expected, HEAT_TOLERANCE),
          entry.label .. string.format(": Wärme %.4f statt %.4f", value, expected))
        if entry.state then
          local state1 = car_state(entity)
          check(failed, entry.state0 == entry.state and state1 == entry.state,
            entry.label .. ": Zustand " .. tostring(entry.state0) .. "/" .. state1 .. " statt " .. entry.state)
        end
        if entry.flyer then check(failed, vibration_lib.source_of(entity) == nil, entry.label .. ": als Quelle eingetragen") end
        if entry.dock_ok ~= nil then
          check(failed, entry.dock_ok == true, entry.label .. ": Andocken ging nicht")
          check(failed, entry.corner == true, entry.label .. ": keine Ecke im Sand (Aufbau)")
        end
        table.insert(parts, string.format("%s %s/%.2f", entry.label, tostring(w1), value))
      end
    end
    if s.loco_moving then
      check(failed, s.loco_weight == WEIGHT.locomotive, "Lokomotive: weight_of " .. tostring(s.loco_weight) .. " statt " .. WEIGHT.locomotive)
    else
      tb.log(run, "INFO", "3) Lokomotive nicht prüfbar: " .. s.loco_text)
    end
    tb.trace(run, "3) Lokomotive: " .. s.loco_text)
    return verdict(run, tb, 3, "Gewichte", failed, table.concat(parts, ", ") .. "; Lokomotive " .. tostring(s.loco_weight))
  end
  if now > s.m1 + 60 then return fail(run, tb, 3, "Messung verpasst (Prüfstand-Fehler)") end
  return "poll"
end

-- Schritt 4: feste Quellen [V13]. Strom: Schnittstelle und Mast wie T4; Abnehmer: Kiste an drop_position, Lagertank.
function t18_steps.s4_build(run, tb, d, s)
  local force = d.force
  local surface = tb.surface()
  s.src = {}
  s.missing = {}
  local function add(label, entity, expect, extra)
    local entry = {label = label, entity = entity, expect = expect}
    for key, value in pairs(extra or {}) do entry[key] = value end
    table.insert(s.src, entry)
    if entity then keep_key(s, entity.position) else table.insert(s.missing, label) end
    return entry
  end
  local function drill(label, name, i, j, opts)
    local p = t18_pos(d, i, j)
    if opts.rock then tiles(surface, math.floor(p.x) - 2, math.floor(p.y) - 2, math.floor(p.x) + 2, math.floor(p.y) + 2, ROCK) end
    ore(surface, p, "iron-ore", opts.radius or 2)
    if opts.power then power(run, tb, s, p, force) end
    local entity = make(run, tb, s, {name = name, position = p, force = force, direction = defines.direction.north, raise_built = true})
    if entity then
      local drop = read(function() return entity.drop_position end)
      if drop then make(run, tb, s, {name = "wooden-chest", position = drop, force = force}) end
    end
    return add(label, entity, opts.expect, {rock = opts.rock, under = opts.under})
  end
  if entity_exists("big-mining-drill") then
    drill("Großbohrer", "big-mining-drill", 2, 3, {power = true, radius = 3, expect = WEIGHT.big_drill})
  else
    tb.log(run, "INFO", "4) big-mining-drill gibt es nicht (ohne Space Age): Großbohrer nicht prüfbar")
  end
  drill("Bohrer", "electric-mining-drill", 3, 3, {power = true, expect = WEIGHT.drill})
  -- Pumpe auf Rohöl, Ausgang nach Norden in einen Lagertank (Anschluss bei (1, −1), Tank 3 Kacheln nördlich).
  local pp = t18_pos(d, 4, 3)
  make(run, tb, s, {name = "crude-oil", position = pp, amount = 300000})
  power(run, tb, s, pp, force)
  local pump = make(run, tb, s, {name = "pumpjack", position = pp, force = force, direction = defines.direction.north, raise_built = true})
  make(run, tb, s, {name = "storage-tank", position = {x = pp.x, y = pp.y - 3}, force = force, direction = defines.direction.north})
  add("Pumpe", pump, WEIGHT.pumpjack)
  local ap = t18_pos(d, 5, 3)
  power(run, tb, s, ap, force)
  local assembler = make(run, tb, s, {name = "assembling-machine-1", position = ap, force = force, raise_built = true})
  if assembler then
    pcall(function() assembler.set_recipe("iron-gear-wheel") end)
    pcall(function() assembler.get_inventory(defines.inventory.crafter_input).insert{name = "iron-plate", count = 100} end)
  end
  add("Montagemaschine", assembler, WEIGHT.assembler)
  local fc = t18_cell(d, 6, 3)
  local furnace = make(run, tb, s, {name = "stone-furnace", position = {x = fc.x, y = fc.y}, force = force, raise_built = true})
  if furnace then
    tb.fuel(furnace, "coal", 10)
    pcall(function() furnace.get_inventory(defines.inventory.crafter_input).insert{name = "iron-ore", count = 50} end)
  end
  add("Steinofen", furnace, WEIGHT.furnace)
  drill("Bohrer ohne Strom", "electric-mining-drill", 1, 4, {expect = 0})
  drill("Bohrer auf Fels", "electric-mining-drill", 2, 4, {power = true, rock = true, expect = 0})
  drill("Bohrer, darunter Fels", "electric-mining-drill", 3, 4, {power = true, under = true, expect = WEIGHT.drill})
  if #s.missing > 0 then tb.log(run, "INFO", "4) nicht gebaut: " .. table.concat(s.missing, ", ") .. " (Einzelheiten in der Datei)") end
  return to_mid(120)
end

local function s4_read(run, tb, s, label)
  local parts = {}
  for _, entry in ipairs(s.src) do
    if valid(entry.entity) then
      entry.w_now = vibration_lib.weight_of(entry.entity)
      entry.st = status_name(entry.entity)
      entry.record = vibration_lib.source_of(entry.entity)
      table.insert(parts, entry.label .. " " .. entry.st)
    end
  end
  tb.log(run, "MESSUNG", "4) status " .. label .. ": " .. table.concat(parts, ", "))
end

function t18_steps.s4_first(run, tb, d, s)
  s.failed = {}
  s4_read(run, tb, s, "nach 120 Ticks Strom")
  for _, entry in ipairs(s.src) do
    if valid(entry.entity) then
      if entry.rock then
        check(s.failed, entry.record == nil, entry.label .. ": auf Fels eingetragen")
        check(s.failed, entry.w_now == 0, entry.label .. ": Gewicht " .. tostring(entry.w_now) .. " statt 0")
      else
        check(s.failed, entry.record ~= nil, entry.label .. ": nicht eingetragen")
        check(s.failed, entry.w_now == entry.expect, entry.label .. ": Gewicht " .. tostring(entry.w_now) .. " statt " .. entry.expect
          .. " (status " .. entry.st .. ")")
      end
    end
  end
  -- Kacheln wechseln (script_raised_set_tiles): Fels-Bohrer auf Sand, Sand-Bohrer auf Fels.
  local surface = tb.surface()
  for _, entry in ipairs(s.src) do
    if valid(entry.entity) and (entry.rock or entry.under) then
      local p = entry.entity.position
      local n, m = math.floor(p.x), math.floor(p.y)
      tiles(surface, n - 2, m - 2, n + 2, m + 2, entry.rock and SAND or ROCK, true)
    end
  end
  return 60
end

function t18_steps.s4_second(run, tb, d, s)
  local failed = s.failed
  s4_read(run, tb, s, "nach dem Kachelwechsel")
  local parts = {}
  for _, entry in ipairs(s.src) do
    if valid(entry.entity) then
      if entry.rock then
        check(failed, entry.record ~= nil, entry.label .. ": nach Kacheln zu Sand nicht eingetragen")
        check(failed, entry.w_now == WEIGHT.drill, entry.label .. ": nach Kacheln zu Sand Gewicht " .. tostring(entry.w_now) .. " statt 3")
      elseif entry.under then
        check(failed, entry.record ~= nil and entry.record.sand == false, entry.label .. ": sand nicht false")
        check(failed, entry.w_now == 0, entry.label .. ": Gewicht " .. tostring(entry.w_now) .. " statt 0")
      else
        check(failed, entry.w_now == entry.expect, entry.label .. ": Gewicht " .. tostring(entry.w_now) .. " statt " .. entry.expect)
      end
      table.insert(parts, entry.label .. " " .. tostring(entry.w_now))
    end
  end
  for _, label in ipairs(s.missing) do check(failed, false, label .. " nicht gebaut") end
  return verdict(run, tb, 4, "Feste Quellen [V13]", failed, table.concat(parts, ", "))
end

-- Schritt 5: Zerfall und Löschen.
function t18_steps.s5_wait(run, tb, d, s)
  return to_mid()
end

function t18_steps.s5_set(run, tb, d, s)
  local surface = tb.surface()
  s.a, s.b = t18_cell(d, 5, 4), t18_cell(d, 6, 4)
  s.keys = {[s.a.key] = true, [s.b.key] = true}
  vibration_lib.set_heat(surface, s.a.cx, s.a.cy, 1000)
  vibration_lib.set_heat(surface, s.b.cx, s.b.cy, 1.5)
  return 600
end

function t18_steps.s5_ten(run, tb, d, s)
  s.ten = vibration_lib.heat_entry(tb.surface(), s.a.key)
  return 600
end

function t18_steps.s5_twenty(run, tb, d, s)
  s.twenty = vibration_lib.heat_entry(tb.surface(), s.b.key)
  return 60
end

function t18_steps.s5_last(run, tb, d, s)
  local failed = {}
  local last = vibration_lib.heat_entry(tb.surface(), s.b.key)
  local expected = 1000 * DECAY ^ 10
  check(failed, near(s.ten, expected, 0.05), string.format("1000 nach 10 Takten %s statt %.2f ± 0,05", tb.num(s.ten, 3), expected))
  check(failed, s.twenty ~= nil, "1,5 nach 20 Takten schon gelöscht")
  check(failed, last == nil, "1,5 nach 21 Takten noch da (" .. tb.num(last, 4) .. ")")
  return verdict(run, tb, 5, "Zerfall und Löschen", failed, string.format("1000 → %s nach 10 Takten; 1,5 → %s nach 20, %s nach 21",
    tb.num(s.ten, 3), tb.num(s.twenty, 4), last == nil and "gelöscht" or tb.num(last, 4)))
end

-- Schritt 6: Nachbarschaft (sofort geprüft, danach wieder 0).
function t18_steps.s6_check(run, tb, d, s)
  local surface = tb.surface()
  local cy = d.bcy + T18_GRID[5]
  local failed, parts = {}, {}
  local function set(list, h)
    for _, cx in ipairs(list) do vibration_lib.set_heat(surface, cx, cy, h) end
  end
  local function sum(cx) return vibration_lib.sum3(surface.index, vibration_lib.chunk_key(cx, cy)) end
  local function nearby(cx) return vibration_lib.near_heat(surface, {x = cx * 32 + 16, y = cy * 32 + 16}) end
  local a = d.bcx - 8
  set({a, a + 1}, 500)
  check(failed, near(sum(a), 1000, 1e-6), "nebeneinander: sum3 am ersten " .. tb.num(sum(a)) .. " statt 1000")
  table.insert(parts, "nebeneinander " .. tb.num(sum(a)))
  set({a, a + 1}, 0)
  local b = d.bcx - 4
  set({b, b + 2}, 500)
  check(failed, near(sum(b + 1), 1000, 1e-6), "Abstand 2: sum3 in der Mitte " .. tb.num(sum(b + 1)) .. " statt 1000")
  check(failed, near(sum(b), 500, 1e-6) and near(sum(b + 2), 500, 1e-6),
    "Abstand 2: sum3 an den beiden " .. tb.num(sum(b)) .. "/" .. tb.num(sum(b + 2)) .. " statt 500")
  check(failed, near(nearby(b), 1000, 1e-6) and near(nearby(b + 2), 1000, 1e-6),
    "Abstand 2: near_heat " .. tb.num(nearby(b)) .. "/" .. tb.num(nearby(b + 2)) .. " statt 1000")
  table.insert(parts, string.format("Abstand 2: Mitte %s, Enden %s/%s, near_heat %s/%s", tb.num(sum(b + 1)), tb.num(sum(b)),
    tb.num(sum(b + 2)), tb.num(nearby(b)), tb.num(nearby(b + 2))))
  set({b, b + 2}, 0)
  local c = d.bcx + 1
  set({c, c + 3}, 500)
  local most = 0
  for cx = c - 1, c + 4 do most = math.max(most, sum(cx)) end
  check(failed, most <= 500 + 1e-6, "Abstand 3: sum3 bis " .. tb.num(most) .. " statt höchstens 500")
  table.insert(parts, "Abstand 3: höchstens " .. tb.num(most))
  set({c, c + 3}, 0)
  return verdict(run, tb, 6, "Nachbarschaft", failed, table.concat(parts, "; "))
end

-- Schritt 7: Erstbefüllung per scan (Auto und Montagemaschine ohne raise_built).
function t18_steps.s7_check(run, tb, d, s)
  local surface = tb.surface()
  local c = t18_cell(d, 6, 5)
  local car = make(run, tb, s, {name = "car", position = {x = c.x - 8, y = c.y + 0.5}, force = d.force, orientation = 0.25})
  local machine = make(run, tb, s, {name = "assembling-machine-1", position = {x = c.x + 6.5, y = c.y + 0.5}, force = d.force})
  if not (car and machine) then return fail(run, tb, 7, "Aufbau ging nicht (Einzelheiten in der Datei)") end
  keep_key(s, car.position)
  local failed = {}
  check(failed, vibration_lib.source_of(car) == nil, "Auto vor scan schon eingetragen")
  check(failed, vibration_lib.source_of(machine) == nil, "Montagemaschine vor scan schon eingetragen")
  local x0, y0 = c.cx * 32, c.cy * 32
  local n = vibration_lib.scan(surface, {{x0, y0}, {x0 + 32, y0 + 32}})
  check(failed, n >= 2, "scan meldet " .. tostring(n) .. " statt ≥ 2")
  check(failed, vibration_lib.source_of(car) ~= nil, "Auto nach scan nicht eingetragen")
  check(failed, vibration_lib.source_of(machine) ~= nil, "Montagemaschine nach scan nicht eingetragen")
  return verdict(run, tb, 7, "Erstbefüllung (scan)", failed, "scan: " .. tostring(n) .. " neu")
end

-- Schritte 8 und 9: Vorsichtsmodus. Lesen in jeder Takt-Mitte; Übergänge gegen W des Takts davor.
local function careful_new(run, tb, d, s, positions)
  s.cars = {}
  for _, position in ipairs(positions) do
    local car = new_harvester(run, tb, s, position, {force = d.force, coal = 30, field = 2000})
    if not car then return false end
    keep_key(s, position)
    local h = harvester.get(car)
    if not h then return false end
    vibration_lib.set_careful(h, true, nil)
    harvester.deploy(h)
    table.insert(s.cars, car)
  end
  s.reads, s.max_w, s.failed = 0, 0, {}
  return true
end

function t18_steps.s8_build(run, tb, d, s)
  if not careful_new(run, tb, d, s, {t18_pos(d, 1, 6)}) then return fail(run, tb, 8, "Aufbau ging nicht (Einzelheiten in der Datei)") end
  s.cycles, s.cycle = {}, {}
  return to_mid()
end

function t18_steps.s8_watch(run, tb, d, s)
  local car = s.cars[1]
  local failed = s.failed
  if not valid(car) then return fail(run, tb, 8, "Ernter weg") end
  local h = harvester.get(car)
  local W = vibration_lib.near_heat(car.surface, car.position)
  local state = h and h.state or "weg"
  local prev = s.prev
  local now = game.tick
  s.reads = s.reads + 1
  s.max_w = math.max(s.max_w, W)
  check(failed, W < WORMSIGN or s.over, "W " .. tb.num(W) .. " ≥ 1000")
  if W >= WORMSIGN then s.over = true end
  if worms_lib.hunt_of(car) and not s.sign then
    s.sign = true
    check(failed, false, "Wurmzeichen trotz Vorsichtsmodus")
  end
  if state == "deployed" then
    -- Ein Zyklus ist fertig, wenn nach Einpacken und Wiederaufbau wieder aufgebaut ist.
    local cycle = s.cycle
    if prev and prev.state == "deploying" then
      if cycle.deployed and cycle.pack and cycle.redeploy then
        local done = {harvest = cycle.pack - cycle.deployed, wait = cycle.redeploy - cycle.pack, deploy = now - cycle.redeploy}
        table.insert(s.cycles, done)
        local total = done.harvest + done.wait + done.deploy
        tb.log(run, "MESSUNG", string.format("8) Zyklus %d: Ernte %s s, Warten %s s, Aufbau %s s, Anteil %s %% (erwartet 16 / 36 / 5 s, 28 %%)",
          #s.cycles, tb.num(done.harvest / 60, 0), tb.num(done.wait / 60, 0), tb.num(done.deploy / 60, 0), tb.num(100 * done.harvest / total, 0)))
      end
      s.cycle = {deployed = now}
    end
    if W >= UNREST then check(failed, false, "aufgebaut mit W " .. tb.num(W) .. " ≥ 600 (kein Einpacken)") end
  elseif state == "packing" then
    if prev and prev.state == "deployed" then
      s.cycle.pack = now
      check(failed, W >= UNREST and prev.w < UNREST, string.format("Einpacken bei W %s (Takt davor %s) statt im ersten Takt mit W ≥ 600",
        tb.num(W), tb.num(prev.w)))
      check(failed, h.careful_packing == true, "Einpacken ohne careful_packing")
    end
    -- vib_weight gilt für den Takt davor: im Takt, der das Einpacken auslöst, trug der Ernter noch aufgebaut bei.
    local weight = vibration_lib.weight_of(car)
    local takes = prev and prev.state == "packing" and h.vib_weight or CAREFUL_PACKING
    if not s.pack_weight_bad and (weight ~= CAREFUL_PACKING or takes ~= CAREFUL_PACKING) then
      s.pack_weight_bad = true
      check(failed, false, "Gewicht beim Einpacken " .. tostring(weight) .. "/" .. tostring(h.vib_weight) .. " statt " .. CAREFUL_PACKING)
    end
  elseif state == "mobile" then
    if h.careful_wait and W < CAREFUL_LOW then check(failed, false, "wartet bei W " .. tb.num(W) .. " < 300") end
  elseif state == "deploying" and prev and prev.state == "mobile" then
    s.cycle.redeploy = now
    check(failed, W < CAREFUL_LOW and prev.w >= CAREFUL_LOW, string.format("Wiederaufbau bei W %s (Takt davor %s) statt im ersten Takt mit W < 300",
      tb.num(W), tb.num(prev.w)))
  end
  s.prev = {state = state, w = W}
  if #s.cycles >= 2 then
    return verdict(run, tb, 8, "Vorsichtsmodus, ein Ernter", failed, string.format("2 Zyklen, größtes W %s, kein Wurmzeichen", tb.num(s.max_w)))
  end
  if s.reads > 200 then
    check(failed, false, "nach " .. s.reads .. " Takten erst " .. #s.cycles .. " Zyklen")
    return verdict(run, tb, 8, "Vorsichtsmodus, ein Ernter", failed, "größtes W " .. tb.num(s.max_w))
  end
  return again(60)
end

function t18_steps.s9_build(run, tb, d, s)
  if not careful_new(run, tb, d, s, {t18_pos(d, 2, 6, 0, -4), t18_pos(d, 2, 6, 0, 4)}) then
    return fail(run, tb, 9, "Aufbau ging nicht (Einzelheiten in der Datei)")
  end
  return to_mid()
end

function t18_steps.s9_watch(run, tb, d, s)
  for _, car in ipairs(s.cars) do
    if not valid(car) then return fail(run, tb, 9, "Ernter weg") end
    s.max_w = math.max(s.max_w, vibration_lib.near_heat(car.surface, car.position))
    if worms_lib.hunt_of(car) then s.sign = true end
  end
  s.reads = s.reads + 1
  if s.reads < 120 then return again(60) end
  local failed = {}
  check(failed, s.max_w < WORMSIGN, "größtes W " .. tb.num(s.max_w) .. " ≥ 1000")
  check(failed, not s.sign, "Wurmzeichen trotz Vorsichtsmodus")
  tb.log(run, "MESSUNG", "9) größtes W mit zwei Erntern im selben Chunk: " .. tb.num(s.max_w) .. " (erwartet unter 660)")
  return verdict(run, tb, 9, "Vorsichtsmodus, zwei Ernter in einem Chunk", failed, "2 min, größtes W " .. tb.num(s.max_w))
end

-- Schritt 10: Abbruch beim Aufbauen; H10a wartet und baut wieder auf, H10b fährt weg und wartet nicht mehr.
function t18_steps.s10_build(run, tb, d, s)
  s.a = new_harvester(run, tb, s, t18_pos(d, 3, 6), {force = d.force, coal = 20, field = 1000})
  s.b = new_harvester(run, tb, s, t18_pos(d, 4, 6, -8, 0), {force = d.force, coal = 20, field = 1000, driver = true})
  if not (s.a and s.b) then return fail(run, tb, 10, "Aufbau ging nicht (Einzelheiten in der Datei)") end
  for _, car in ipairs({s.a, s.b}) do
    keep_key(s, car.position)
    vibration_lib.set_careful(harvester.get(car), true, nil)
  end
  return to_mid(30)
end

function t18_steps.s10_set(run, tb, d, s)
  local surface = tb.surface()
  s.failed = {}
  for _, car in ipairs({s.a, s.b}) do
    local cx, cy = vibration_lib.chunk_of_key(vibration_lib.key_of(car.position))
    vibration_lib.set_heat(surface, cx, cy, 700)
    check(s.failed, harvester.toggle(car, nil), "Aufbauen per toggle ging nicht")
  end
  s.set_tick = game.tick
  return 60
end

function t18_steps.s10_first(run, tb, d, s)
  for _, entry in ipairs({{"H10a", s.a}, {"H10b", s.b}}) do
    local label, car = entry[1], entry[2]
    local h = harvester.get(car)
    check(s.failed, h and h.state == "mobile" and h.careful_wait == true,
      label .. ": nach 60 Ticks " .. car_state(car) .. ", careful_wait " .. tostring(h and h.careful_wait))
  end
  s.b_start = copy_pos(s.b.position)
  return 1
end

function t18_steps.s10_run(run, tb, d, s)
  local failed = s.failed
  local now = game.tick
  if not (valid(s.a) and valid(s.b)) then return fail(run, tb, 10, "Ernter weg") end
  local ha, hb = harvester.get(s.a), harvester.get(s.b)
  -- H10b: 1 Kachel fahren.
  if not s.b_moved then
    local moved = tb.distance(s.b.position, s.b_start)
    gas(s.b, driver_of(s, s.b), moved < 1)
    if moved >= 1 then s.b_moved = now end
  elseif not s.b_cleared then
    gas(s.b, driver_of(s, s.b), false)
    if hb.careful_wait == nil then
      s.b_cleared = now
    elseif now > s.b_moved + 61 then
      s.b_cleared = now
      check(failed, false, "H10b: careful_wait nach 1 Kachel und 60 Ticks noch gesetzt")
    end
  end
  if now % 60 == 30 then
    local Wa = vibration_lib.near_heat(s.a.surface, s.a.position)
    local Wb = vibration_lib.near_heat(s.b.surface, s.b.position)
    if not s.a_done then
      if ha.state == "deploying" then
        s.a_done = true
        s.a_takes = math.floor((now - s.set_tick) / 60 + 0.5)
        check(failed, Wa < CAREFUL_LOW and (s.a_prev or 0) >= CAREFUL_LOW,
          string.format("H10a: Wiederaufbau bei W %s (Takt davor %s)", tb.num(Wa), tb.num(s.a_prev)))
        check(failed, ha.careful_wait == nil and ha.careful_pos == nil, "H10a: careful_wait oder careful_pos nach dem Wiederaufbau gesetzt")
        tb.log(run, "MESSUNG", "10) H10a baut " .. s.a_takes .. " Takte nach set_heat 700 wieder auf (erwartet etwa 42)")
      elseif ha.state ~= "mobile" or not ha.careful_wait then
        s.a_done = true
        check(failed, false, "H10a: " .. ha.state .. ", careful_wait " .. tostring(ha.careful_wait) .. " statt Warten")
      end
      s.a_prev = Wa
    end
    if not s.b_done then
      if not s.b_low and Wb < CAREFUL_LOW then s.b_low = now end
      if s.b_low and now >= s.b_low + 180 then
        s.b_done = true
        check(failed, hb.state == "mobile", "H10b: 3 Takte nach W < 300 " .. hb.state .. " statt mobil")
      end
    end
  end
  if s.a_done and s.b_done and s.b_cleared then
    return verdict(run, tb, 10, "Vorsichtsmodus: Abbruch und Weiterfahren", failed, string.format("H10a nach %s Takten wieder beim Aufbau, H10b fährt (careful_wait %s)",
      tostring(s.a_takes), tostring(hb.careful_wait)))
  end
  if now - s.set_tick > 70 * 60 then
    check(failed, false, "nach 70 s nicht fertig (H10a " .. tostring(s.a_done) .. ", H10b " .. tostring(s.b_done) .. ")")
    return verdict(run, tb, 10, "Vorsichtsmodus: Abbruch und Weiterfahren", failed, "abgebrochen")
  end
  return "poll"
end

-- Schritt 11: Prüfstand-Sperre (Force player ist nicht eingeschaltet).
function t18_steps.s11_build(run, tb, d, s)
  local player_force = game.forces.player
  if storage.vib.testbench[player_force.index] then
    tb.log(run, "INFO", "11) Force player ist für die Prüfstand-Fläche eingeschaltet (läuft T20?): Sperre nicht prüfbar")
    run.data.results[11] = "INFO"
    return "end"
  end
  s.car = new_harvester(run, tb, s, t18_pos(d, 5, 6), {force = player_force, coal = 10, field = 1000})
  if not s.car then return fail(run, tb, 11, "Aufbau ging nicht (Einzelheiten in der Datei)") end
  s.key = keep_key(s, s.car.position)
  harvester.deploy(harvester.get(s.car))
  s.start = game.tick
  return 1
end

function t18_steps.s11_wait(run, tb, d, s)
  if car_state(s.car) == "deployed" then return to_mid(180) end
  if game.tick - s.start > 600 then return fail(run, tb, 11, "Ernter baut nicht auf (" .. car_state(s.car) .. ")") end
  return "poll"
end

function t18_steps.s11_check(run, tb, d, s)
  local failed = {}
  local h = harvester.get(s.car)
  local entry = vibration_lib.heat_entry(tb.surface(), s.key)
  check(failed, entry == nil, "Wärme-Eintrag " .. tb.num(entry) .. " im Chunk")
  check(failed, h and h.vib_key == nil and h.vib_weight == 0, "vib_key " .. tostring(h and h.vib_key) .. ", vib_weight " .. tostring(h and h.vib_weight))
  return verdict(run, tb, 11, "Prüfstand-Sperre (Force player)", failed, "aufgebaut, nach 3 Takten kein Eintrag")
end

local T18_STEPS =
{
  {t18_steps.s1_check},
  {t18_steps.s2_build, t18_steps.s2_watch, t18_steps.s2_end},
  {t18_steps.s3_build, t18_steps.s3_run},
  {t18_steps.s4_build, t18_steps.s4_first, t18_steps.s4_second},
  {t18_steps.s5_wait, t18_steps.s5_set, t18_steps.s5_ten, t18_steps.s5_twenty, t18_steps.s5_last},
  {t18_steps.s6_check},
  {t18_steps.s7_check},
  {t18_steps.s8_build, t18_steps.s8_watch},
  {t18_steps.s9_build, t18_steps.s9_watch},
  {t18_steps.s10_build, t18_steps.s10_set, t18_steps.s10_first, t18_steps.s10_run},
  {t18_steps.s11_build, t18_steps.s11_wait, t18_steps.s11_check}
}

local function t18_start(run, tb)
  local d = run.data
  if not isolate_start(run, tb, T18_FORCE, T18_HALF) then return end
  worms_lib.set_grace(d.force, {awake = true, first_hunt_done = false}, {"first_hunt"})
  local others = foreign_regular({[d.force.index] = true})
  if others >= MAX_HUNTS then
    tb.log(run, "INFO", "Schon " .. others .. " reguläre Jagden anderer Forces (höchstens " .. MAX_HUNTS .. "): Schritt 2 bekommt kein Wurmzeichen")
  end
  lanes_init(d, #T18_STEPS, game.tick + 2)
  tb.log(run, "INFO", "Elf Schritte mit dem echten Vibrationscode (Force " .. T18_FORCE .. ", wach), parallel ab Tick 2, Dauer etwa 2 min"
    .. " Spielzeit. Je Schritt eine OK/FEHLER-Zeile, Einzelwerte in der Datei.")
end

local function t18_tick(run, tb)
  local d = run.data
  if not d.lanes or d.done_all then return end
  local open = false
  for number = 1, #T18_STEPS do
    lane_step(run, tb, d, T18_STEPS, number)
    if not d.lanes[number].done then open = true end
  end
  if not open then
    d.done_all = true
    tb.finish(run, summary(run, #T18_STEPS))
  end
end

local function t18_cleanup(run, tb)
  isolate_cleanup(run, tb, run.data, {run.data.force})
end

return
{
  T18 =
  {
    title = "Wärme: echter Code",
    timeout = 240 * 60,
    interactive = false,
    confirm = nil,
    start = t18_start,
    tick = t18_tick,
    cleanup = t18_cleanup
  }
}
