-- T26 Flottenleitung: echter Code: Prüfstand-Test (aus t_fleet.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_fleet.lua.

local common = require("scripts.testbench.gemeinsam_fleet")
local fleet = require("scripts.fleet")
local fields = require("scripts.fleet-fields")
local harvester = require("scripts.harvester")
local worms_lib = require("scripts.worms")
local vibration_lib = require("scripts.vibration")
local DEPOT = common.DEPOT
local NAME = common.NAME
local SPICE = common.SPICE
local T23_FORCE = common.T23_FORCE
local valid = common.valid
local fleet_distance = common.fleet_distance
local at = common.at
local pos_text = common.pos_text
local t23_force = common.t23_force
local create = common.create
local tidy = common.tidy
local h_of = common.h_of
local state_of = common.state_of
local build_base = common.build_base
local new_harvester = common.new_harvester
local verdict = common.verdict
local fail = common.fail
local check = common.check
local wait_for = common.wait_for
local prepare = common.prepare
local run_steps = common.run_steps
local FLEET_TECH = common.FLEET_TECH
local T26_FIELDS = common.T26_FIELDS
local fleet_force = common.fleet_force
local depot_record = common.depot_record
local depot_items = common.depot_items
local owned = common.owned
local depot_jobs = common.depot_jobs
local set_wire_signal = common.set_wire_signal
local place_fields = common.place_fields
local chart_area = common.chart_area
local charted = common.charted
local skip_chart = common.skip_chart
local sweep = common.sweep
local empty_field = common.empty_field

local T26_SETTLE = 130

local function red_signal(entity, name)
  if not valid(entity) then return 0 end
  return entity.get_signal({type = "virtual", name = name}, defines.wire_connector_id.circuit_red)
end

-- Meiste gleichzeitig fliegende Aufträge einer Art mit Carryalls dieser Leitstelle (Max 01.11.: Einsetzen und
-- Zurückbringen nach dem Rückruf parallel, nicht nacheinander).
local function note_parallel(s, kind)
  local n = 0
  local un = valid(s.depot) and s.depot.unit_number
  for _, job in pairs(storage.jobs.list) do
    local record = job.kind == kind and job.carryall and storage.flyers[job.carryall]
    if record and record.depot == un then n = n + 1 end
  end
  s.parallel = math.max(s.parallel or 0, n)
end

local t26 = {}

-- 1) Prototypen, storage (Schema 6) und das versteckte Schaltungsgebäude an einer neuen Leitstelle.
function t26.s1(run, tb, d)
  local s = d.s1
  local failed = {}
  fleet_force(true)
  check(failed, prototypes.technology[FLEET_TECH] ~= nil, "Forschung " .. FLEET_TECH .. " fehlt")
  for _, name in ipairs(fleet.STATUS_SIGNALS) do
    check(failed, prototypes.virtual_signal[name] ~= nil, "Signal " .. name .. " fehlt")
  end
  check(failed, prototypes.entity["arrakis-depot-signals"] ~= nil, "arrakis-depot-signals fehlt")
  check(failed, storage.schema >= 6 and storage.fields ~= nil and storage.fields.chunks ~= nil, "storage Schema 6 fehlt")
  s.depot = create(run, tb, {name = DEPOT, position = d.pos.depot, force = t23_force(), raise_built = true}, "others")
  local dr = s.depot and fleet.depot_of(s.depot.unit_number)
  local cc = dr and dr.signal_entity
  check(failed, valid(cc) and cc.name == "arrakis-depot-signals", "kein Schaltungsgebäude an der Leitstelle")
  local wired = 0
  if valid(cc) then
    for _, id in ipairs({defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green}) do
      local connector = cc.get_wire_connector(id, false)
      if connector and connector.connection_count >= 1 then wired = wired + 1 end
    end
  end
  check(failed, wired == 2, wired .. " von 2 Drähten am Schaltungsgebäude")
  check(failed, dr and dr.target == 0 and dr.recall_button == false, "Soll nicht aus oder Rückruf an")
  return verdict(run, tb, 1, "Prototypen, Schema 6, Schaltungsgebäude", failed, string.format(
    "Schema %s, Schaltungsgebäude %s, Drähte %d", tostring(storage.schema), valid(cc) and "da" or "fehlt", wired))
end

-- 2) Soll 2 aus dem Fenster: zwei Ernter aus dem Lager (3 Items) auf zwei Felder, Reserve 1.
function t26.s2_build(run, tb, d)
  local s = d.s2
  fleet_force(true)
  if not build_base(run, tb, d, s, {carryalls = 2, rocket = 60, coal = 300}) then return fail(run, tb, 2, "Leitstelle oder Carryalls ließen sich nicht bauen") end
  s.depot.get_inventory(defines.inventory.chest).insert{name = NAME, count = 3}
  s.fields = place_fields(tb, d, T26_FIELDS)
  chart_area(tb, d)
  s.deadline = game.tick + 10 * 60
  return 1
end

function t26.s2_chart(run, tb, d)
  local s = d.s2
  local r = wait_for(s, function() return charted(tb, s.fields) end,
    function() skip_chart(run, tb, "2) ") return 1 end)
  if r == 1 then
    fleet.set_target(depot_record(s), 2)
    s.start = game.tick
    s.deadline = game.tick + 240 * 60
  end
  return r
end

function t26.s2_wait(run, tb, d)
  local s = d.s2
  local r = wait_for(s, function()
    note_parallel(s, "deploy")
    return #owned(s, "deployed") == 2 and depot_jobs(s) == 0
  end, function()
    return fail(run, tb, 2, string.format("nach 240 s %d eigene Ernter aufgebaut, %d im Lager, Aufträge %d, Feldsuche offen %d",
      #owned(s, "deployed"), depot_items(s, NAME), depot_jobs(s), fields.queue_length()))
  end)
  if r == 1 then return T26_SETTLE end
  return r
end

local function on_field(h)
  return h.entity.valid and fields.amount_at(h.entity.surface, h.entity.position) >= fields.MIN_AMOUNT
end

function t26.s2_check(run, tb, d)
  local s = d.s2
  local failed = {}
  local list = owned(s, "deployed")
  check(failed, depot_items(s, NAME) == 1, depot_items(s, NAME) .. " Ernter im Lager statt 1")
  local gap = #list == 2 and fleet_distance(list[1].entity.position, list[2].entity.position) or 0
  check(failed, gap >= fields.SPACING, "Abstand der beiden " .. tb.num(gap))
  for i, h in ipairs(list) do check(failed, on_field(h), "Ernter " .. i .. " nicht auf Spice") end
  check(failed, (s.parallel or 0) >= 2, "Einsätze nacheinander (höchstens " .. (s.parallel or 0) .. " gleichzeitig)")
  local active, reserve = red_signal(s.depot, "arrakis-signal-harvesters"), red_signal(s.depot, "arrakis-signal-reserve")
  check(failed, active == 2 and reserve == 1, "Statussignale aktiv " .. active .. ", Reserve " .. reserve)
  s.ok = #failed == 0
  local result = verdict(run, tb, 2, "Soll 2 aus dem Fenster", failed, string.format(
    "zwei eingesetzt nach %s s (%d gleichzeitig), Abstand %s, Signale aktiv %d / Reserve %d / freie Carryalls %d",
    tb.num((game.tick - s.start) / 60), s.parallel or 0, tb.num(gap), active, reserve, red_signal(s.depot, "arrakis-signal-carryalls")))
  d.s3, d.s4, d.s5 = s, s, s
  return s.ok and "keep" or result
end

-- 3) Signal H = 3 (Vorrang vor dem Fenster): der dritte Ernter aus dem Lager.
function t26.s3_set(run, tb, d)
  local s = d.s3
  if not (s and s.ok) then return fail(run, tb, 3, "folgt aus Schritt 2 (nicht erfüllt)") end
  if not set_wire_signal(run, tb, s, "H", 3) then return fail(run, tb, 3, "Konstant-Schaltungsgebäude ließ sich nicht bauen") end
  s.start = game.tick
  s.deadline = game.tick + 240 * 60
  return 1
end

function t26.s3_wait(run, tb, d)
  local s = d.s3
  local r = wait_for(s, function()
    return #owned(s, "deployed") == 3 and depot_jobs(s) == 0
  end, function()
    local dr = depot_record(s)
    return fail(run, tb, 3, string.format("nach 240 s %d eigene Ernter aufgebaut, Soll %s, gelesenes H %s",
      #owned(s, "deployed"), tostring(dr and dr.soll), tostring(dr and dr.last_h)))
  end)
  if r == 1 then return T26_SETTLE end
  return r
end

function t26.s3_check(run, tb, d)
  local s = d.s3
  local failed = {}
  local dr = depot_record(s)
  check(failed, dr and dr.soll == 3 and dr.last_h == 3, "Soll " .. tostring(dr and dr.soll) .. " statt 3")
  check(failed, depot_items(s, NAME) == 0, depot_items(s, NAME) .. " Ernter im Lager statt 0")
  local active, reserve = red_signal(s.depot, "arrakis-signal-harvesters"), red_signal(s.depot, "arrakis-signal-reserve")
  check(failed, active == 3 and reserve == 0, "Statussignale aktiv " .. active .. ", Reserve " .. reserve)
  s.ok = #failed == 0
  local result = verdict(run, tb, 3, "Signal H = 3", failed, string.format("dritter nach %s s, Signale aktiv %d / Reserve %d",
    tb.num((game.tick - s.start) / 60), active, reserve))
  return s.ok and "keep" or result
end

-- 4) H = 1: die zwei zuletzt eingesetzten zurück ins Lager (Ladung im Lager, kein Umweg ohne Annahme).
function t26.s4_set(run, tb, d)
  local s = d.s4
  if not (s and s.ok) then return fail(run, tb, 4, "folgt aus Schritt 3 (nicht erfüllt)") end
  set_wire_signal(run, tb, s, "H", 1)
  s.start = game.tick
  s.deadline = game.tick + 400 * 60
  return 1
end

function t26.s4_wait(run, tb, d)
  local s = d.s4
  local r = wait_for(s, function()
    return #owned(s) == 1 and depot_items(s, NAME) == 2 and depot_jobs(s) == 0
  end, function()
    return fail(run, tb, 4, string.format("nach 400 s %d eigene Ernter draußen, %d im Lager, Aufträge %d",
      #owned(s), depot_items(s, NAME), depot_jobs(s)))
  end)
  if r == 1 then return T26_SETTLE end
  return r
end

function t26.s4_check(run, tb, d)
  local s = d.s4
  local failed = {}
  local list = owned(s, "deployed")
  check(failed, #list == 1, #list .. " aufgebaut statt 1")
  local active, reserve = red_signal(s.depot, "arrakis-signal-harvesters"), red_signal(s.depot, "arrakis-signal-reserve")
  check(failed, active == 1 and reserve == 2, "Statussignale aktiv " .. active .. ", Reserve " .. reserve)
  s.ok = #failed == 0
  local result = verdict(run, tb, 4, "Signal H = 1 holt zwei ins Lager", failed, string.format(
    "nach %s s, im Lager %d Ernter und %d Spice-Sand, Signale aktiv %d / Reserve %d", tb.num((game.tick - s.start) / 60),
    depot_items(s, NAME), depot_items(s, SPICE), active, reserve))
  return s.ok and "keep" or result
end

-- 5) Umsetzen: Das Feld des letzten wird leer (Spice-Sand entfernt), die Leitstelle setzt ihn auf ein freies Feld.
function t26.s5_empty(run, tb, d)
  local s = d.s5
  if not (s and s.ok) then return fail(run, tb, 5, "folgt aus Schritt 4 (nicht erfüllt)") end
  local h = owned(s, "deployed")[1]
  if not h then return fail(run, tb, 5, "kein aufgebauter Ernter") end
  s.mover = h.entity
  s.from = {x = h.entity.position.x, y = h.entity.position.y}
  empty_field(tb, s.from)
  s.start = game.tick
  s.deadline = game.tick + 240 * 60
  return 1
end

function t26.s5_wait(run, tb, d)
  local s = d.s5
  local r = wait_for(s, function()
    local h = h_of(s.mover)
    if h and h.status == "field_empty" then s.seen_empty = true end
    return h and h.state == "deployed" and h.status ~= "field_empty" and fleet_distance(s.mover.position, s.from) >= fields.SPACING
      and depot_jobs(s) == 0
  end, function()
    return fail(run, tb, 5, string.format("nach 240 s Ernter %s bei %s (vorher %s), Status %s", state_of(s.mover),
      valid(s.mover) and pos_text(tb, s.mover.position) or "–", pos_text(tb, s.from), tostring((h_of(s.mover) or {}).status)))
  end)
  if r == 1 then return T26_SETTLE end
  return r
end

function t26.s5_check(run, tb, d)
  local s = d.s5
  local failed = {}
  local h = h_of(s.mover)
  check(failed, s.seen_empty, "Status „Feld leer“ nie gesehen")
  check(failed, h and on_field(h), "nicht auf Spice")
  check(failed, red_signal(s.depot, "arrakis-signal-harvesters") == 1, "Signal aktiv " .. red_signal(s.depot, "arrakis-signal-harvesters"))
  check(failed, depot_items(s, NAME) == 2, depot_items(s, NAME) .. " im Lager statt 2")
  return verdict(run, tb, 5, "Umsetzen bei leerem Feld", failed, string.format("umgesetzt nach %s s, %s Kacheln weiter",
    tb.num((game.tick - s.start) / 60), tb.num(valid(s.mover) and fleet_distance(s.mover.position, s.from) or 0)))
end

-- 6) Feldsuche ohne Flug: nähere Felder gewinnen, eine Kartenmarkierung mit Spice-Sand-Symbol geht vor, ein lauernder
-- Wurm sperrt seinen Sektor.
function t26.s6_build(run, tb, d)
  local s = d.s6
  fleet_force(true)
  s.depot = create(run, tb, {name = DEPOT, position = d.pos.depot, force = t23_force(), raise_built = true}, "others")
  if not s.depot then return fail(run, tb, 6, "Leitstelle ließ sich nicht bauen") end
  -- P1 110 Kacheln von der Leitstelle, P2 250 Kacheln: mehr als ein Sektor (128) auseinander. y = 20: weg von der
  -- Sektorgrenze bei y = 0 (Sektoren 128 Kacheln, ab 0 gezählt), sonst hätte jedes Feld Plätze in zwei Sektoren.
  s.fields = place_fields(tb, d, {{x = -40, y = 20}, {x = 100, y = 20}})
  chart_area(tb, d)
  s.deadline = game.tick + 10 * 60
  return 1
end

function t26.s6_chart(run, tb, d)
  local s = d.s6
  return wait_for(s, function() return charted(tb, s.fields) end,
    function()
      skip_chart(run, tb, "6) ")
      s.uncharted = true
      return 1
    end)
end

function t26.s6_check(run, tb, d)
  local s = d.s6
  local failed = {}
  local surface = tb.surface()
  for _, p in ipairs(s.fields) do
    local cx, cy = math.floor(p.x / 32), math.floor(p.y / 32)
    for dx = -1, 1 do for dy = -1, 1 do fields.count(surface, cx + dx, cy + dy) end end
  end
  local dr = depot_record(s)
  local function near(spot, p) return spot and fleet_distance(spot, p) <= 3 end
  local a = fields.find_spot(dr, fleet.RANGE)
  check(failed, near(a, s.fields[1]), "ohne Markierung nicht das nähere Feld: " .. pos_text(tb, a))
  -- Kartenmarkierungen gehen nur auf kartierten Chunks.
  local tag
  if s.uncharted then
    tb.log(run, "INFO", "6) Vorrang der Kartenmarkierung nicht prüfbar (Chunks nicht kartiert, V6)")
  else
    tag = t23_force().add_chart_tag(surface, {position = s.fields[2], icon = {type = "item", name = SPICE}})
    check(failed, tag ~= nil, "Kartenmarkierung ließ sich nicht setzen")
  end
  local b = fields.find_spot(dr, fleet.RANGE)
  if not s.uncharted then
    check(failed, near(b, s.fields[2]), "mit Markierung nicht das markierte Feld: " .. pos_text(tb, b))
  end
  local _, sector = vibration_lib.key_of(s.fields[2])
  worms_lib.lurk(surface.index, sector, game.tick + 60 * 60)
  local c = fields.find_spot(dr, fleet.RANGE)
  check(failed, near(c, s.fields[1]), "lauernder Wurm am markierten Feld nicht gemieden: " .. pos_text(tb, c))
  local _, sector1 = vibration_lib.key_of(s.fields[1])
  check(failed, sector1 ~= sector, "beide Felder im selben Sektor")
  worms_lib.lurk(surface.index, sector1, game.tick + 60 * 60)
  local e = fields.find_spot(dr, fleet.RANGE)
  check(failed, e == nil, "beide Sektoren gesperrt, trotzdem Platz " .. pos_text(tb, e))
  worms_lib.clear_lurk(surface.index)
  if tag and tag.valid then tag.destroy() end
  return verdict(run, tb, 6, "Feldsuche: Abstand, Markierung, lauernder Wurm", failed, string.format(
    "ohne Markierung %s, mit Markierung %s, Wurm am markierten %s, beide gesperrt %s; Plätze bekannt %d",
    pos_text(tb, a), pos_text(tb, b), pos_text(tb, c), pos_text(tb, e), fields.known_spots(dr, fleet.RANGE)))
end

-- 7) Signal R: beide Ernter (einer selbst gesetzt, einer eigener mit Ladung) an die Leitstelle; solange R gilt, keiner
-- zurück; R = 0 bringt beide auf ihre Felder.
local T26_R_FIELDS = {{x = -60, y = 20}, {x = -10, y = -20}}

function t26.s7_build(run, tb, d)
  local s = d.s7
  fleet_force(true)
  if not build_base(run, tb, d, s, {carryalls = 2, rocket = 60, coal = 300}) then return fail(run, tb, 7, "Leitstelle oder Carryalls ließen sich nicht bauen") end
  local origin = tb.area(run.id)
  s.cars = {
    new_harvester(run, tb, d, at(origin, T26_R_FIELDS[1].x, T26_R_FIELDS[1].y)),
    new_harvester(run, tb, d, at(origin, T26_R_FIELDS[2].x, T26_R_FIELDS[2].y), {fill = 1})
  }
  if not (s.cars[1] and s.cars[2]) then return fail(run, tb, 7, "Ernter ließen sich nicht bauen") end
  h_of(s.cars[2]).fleet_owner = s.depot.unit_number
  s.origins = {}
  for i, car in ipairs(s.cars) do s.origins[i] = {x = car.position.x, y = car.position.y} end
  fleet.set_target(depot_record(s), 2)
  return harvester.DEPLOY_TICKS + 30
end

function t26.s7_recall(run, tb, d)
  local s = d.s7
  for i, car in ipairs(s.cars) do
    if state_of(car) ~= "deployed" then return fail(run, tb, 7, "Ernter " .. i .. " baut nicht auf (" .. state_of(car) .. ")") end
  end
  if not set_wire_signal(run, tb, s, "R", 1) then return fail(run, tb, 7, "Konstant-Schaltungsgebäude ließ sich nicht bauen") end
  s.start = game.tick
  s.deadline = game.tick + 240 * 60
  return 1
end

local function both_recalled(s)
  for _, car in ipairs(s.cars) do
    local h = h_of(car)
    if not (h and h.state == "mobile" and h.fleet_wait and h.fleet_wait.reason == "recall") then return false end
  end
  return true
end

function t26.s7_home(run, tb, d)
  local s = d.s7
  local r = wait_for(s, function()
    if not both_recalled(s) then return false end
    s.home_tick = game.tick
    return true
  end, function()
    return fail(run, tb, 7, string.format("nach 240 s nicht beide an der Leitstelle: %s / %s", state_of(s.cars[1]), state_of(s.cars[2])))
  end)
  if r == 1 then return 15 * 60 end
  return r
end

function t26.s7_hold(run, tb, d)
  local s = d.s7
  -- 15 s später: noch immer beide an der Leitstelle (R gilt), kein Auftrag.
  s.held = both_recalled(s) and depot_jobs(s) == 0
  s.dist_home = valid(s.cars[1]) and fleet_distance(s.cars[1].position, s.depot.position) or -1
  set_wire_signal(run, tb, s, "R", 0)
  s.release = game.tick
  s.parallel = 0
  s.deadline = game.tick + 240 * 60
  return 1
end

function t26.s7_back(run, tb, d)
  local s = d.s7
  return wait_for(s, function()
    note_parallel(s, "return")
    for i, car in ipairs(s.cars) do
      if not (state_of(car) == "deployed" and fleet_distance(car.position, s.origins[i]) <= 4) then return false end
    end
    return true
  end, function()
    return fail(run, tb, 7, string.format("nach 240 s nicht beide zurück: %s / %s", state_of(s.cars[1]), state_of(s.cars[2])))
  end)
end

function t26.s7_check(run, tb, d)
  local s = d.s7
  local failed = {}
  check(failed, s.held, "während R nicht beide wartend an der Leitstelle")
  check(failed, s.dist_home <= 18, "Ernter 1 " .. tb.num(s.dist_home) .. " Kacheln von der Leitstelle")
  check(failed, (s.parallel or 0) >= 2, "Rückflüge nacheinander (höchstens " .. (s.parallel or 0) .. " gleichzeitig)")
  return verdict(run, tb, 7, "Signal R holt alle, R = 0 bringt sie zurück", failed, string.format(
    "an der Leitstelle nach %s s, zurück nach %s s (%d gleichzeitig)", tb.num((s.home_tick - s.start) / 60),
    tb.num((game.tick - s.release) / 60), s.parallel or 0))
end

local T26_STEPS =
{
  {t26.s1},
  {t26.s2_build, t26.s2_chart, t26.s2_wait, t26.s2_check},
  {t26.s3_set, t26.s3_wait, t26.s3_check},
  {t26.s4_set, t26.s4_wait, t26.s4_check},
  {t26.s5_empty, t26.s5_wait, t26.s5_check},
  {t26.s6_build, t26.s6_chart, t26.s6_check},
  {t26.s7_build, t26.s7_recall, t26.s7_home, t26.s7_hold, t26.s7_back, t26.s7_check}
}

local function t26_start(run, tb)
  prepare(run, tb)
  local d = run.data
  d.run_id = run.id
  for number = 1, #T26_STEPS do d["s" .. number] = d["s" .. number] or {} end
  d.after_step = "sweep"
  fleet_force(true)
  fields.reset()
  tb.watch(run, nil, d.pos.watch)
  tb.log(run, "INFO", "Sieben Schritte Flottenleitung mit der echten Automatik (Soll, H, Rückruf ins Lager, Umsetzen,"
    .. " Feldsuche, R), Force " .. T23_FORCE .. " ohne Wurm. Dauer etwa 12 min Spielzeit.")
  d.step, d.phase, d.wait_until = 1, 1, game.tick + 30
end

local function t26_tick(run, tb)
  run_steps(run, tb, T26_STEPS)
end

local function t26_cleanup(run, tb)
  pcall(tidy, run)
  pcall(sweep, run, tb)
  pcall(fleet_force, false)
  storage.fleet_pause_until = nil
end

return
{
  T26 =
  {
    title = "Flottenleitung: echter Code",
    timeout = 20 * 60 * 60,
    interactive = false,
    confirm = nil,
    start = t26_start,
    tick = t26_tick,
    cleanup = t26_cleanup
  }
}
