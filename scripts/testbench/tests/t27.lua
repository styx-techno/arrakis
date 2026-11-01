-- T27 Flottenleitung: Dauerlauf: Prüfstand-Test (aus t_fleet.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_fleet.lua.

local common = require("scripts.testbench.gemeinsam_fleet")
local fields = require("scripts.fleet-fields")
local worms_lib = require("scripts.worms")
local NAME = common.NAME
local INTAKE = common.INTAKE
local valid = common.valid
local pos_text = common.pos_text
local t23_force = common.t23_force
local create = common.create
local tidy = common.tidy
local build_base = common.build_base
local check = common.check
local prepare = common.prepare
local T26_FIELDS = common.T26_FIELDS
local fleet_force = common.fleet_force
local depot_record = common.depot_record
local depot_items = common.depot_items
local owned = common.owned
local depot_jobs = common.depot_jobs
local set_wire_signal = common.set_wire_signal
local place_fields = common.place_fields
local chart_area = common.chart_area
local chart_or_skip = common.chart_or_skip
local sweep = common.sweep
local empty_field = common.empty_field

-- T27 Dauerlauf Flottenleitung ---------------------------------------------------------------------------

local T27_TICKS = 60 * 60 * 60
local T27_SETTLE = 300 * 60
local T27_HUNT_EVERY = 75 * 60
-- Nach so vielen Minuten wird je ein Feld leer (das Feld eines aufgebauten Ernters).
local T27_EMPTY_AT = {8, 23, 38}
-- Nach einem leeren Feld spätestens so lange, bis wieder drei laufen (Ticks).
local T27_RECOVER = 240 * 60

local function open_transfer(s)
  local un = valid(s.depot) and s.depot.unit_number
  for _, job in pairs(storage.jobs.list) do
    if job.depot == un and (job.kind == "move" or job.kind == "deploy") then return true end
  end
  return false
end

local function t27_start(run, tb)
  prepare(run, tb)
  local d = run.data
  d.run_id = run.id
  d.s = {}
  local s = d.s
  fleet_force(true)
  fields.reset()
  if not build_base(run, tb, d, s, {carryalls = 3, rocket = 100, coal = 1500}) then
    tb.log(run, "FEHLER", "Leitstelle oder Carryalls ließen sich nicht bauen")
    tb.finish(run, "abgebrochen (Aufbau)")
    return
  end
  -- 48 Plätze: 30 Kohle, 5 Raketentreibstoff, 5 Ernter (Stapel 1).
  local inserted = s.depot.get_inventory(defines.inventory.chest).insert{name = NAME, count = 5}
  if inserted ~= 5 then
    tb.log(run, "FEHLER", "nur " .. inserted .. " von 5 Erntern passen ins Lager der Leitstelle")
    tb.finish(run, "abgebrochen (Aufbau)")
    return
  end
  s.intake = create(run, tb, {name = INTAKE, position = d.pos.intake, force = t23_force(), raise_built = true}, "others")
  s.fields = place_fields(tb, d, T26_FIELDS)
  chart_area(tb, d)
  if not set_wire_signal(run, tb, s, "H", 3) then
    tb.finish(run, "abgebrochen (Aufbau)")
    return
  end
  s.start = game.tick
  s.next_hunt = game.tick + 90 * 60
  s.target = 0
  s.hunts = {}
  s.kinds = {}
  s.jobs = {}
  s.max_active = 0
  s.empties = {}
  s.recover = {}
  s.docked = 0
  tb.watch(run, nil, d.pos.watch)
  tb.log(run, "INFO", "Dauerlauf 60 min Spielzeit: 5 Ernter im Lager, Signal H = 3, sechs Felder, nach 8, 23 und 38 min wird je"
    .. " ein Feld leer, alle 75 s ein Wurmzeichen. Erwartet: nie mehr als 3 aktiv, nach jedem leeren Feld binnen 4 min wieder 3"
    .. " aufgebaut, kein Biss, kein Ernter verloren.")
end

local function t27_tick(run, tb)
  local d = run.data
  local s = d.s
  if not (s and s.start) then return end
  local tick = game.tick
  chart_or_skip(run, tb, s)
  local dr = depot_record(s)
  local c = dr and dr.census
  if c and c.active > s.max_active then s.max_active = c.active end
  for id, job in pairs(storage.jobs.list) do
    if not s.jobs[id] then
      s.jobs[id] = true
      s.kinds[job.kind] = (s.kinds[job.kind] or 0) + 1
    end
  end
  local deployed = owned(s, "deployed")
  -- Annahme wie in T24: angedockte Ernter werden geleert.
  if tick % 60 == 0 then
    for _, h in ipairs(owned(s, "docked")) do
      local trunk = h.entity.get_inventory(defines.inventory.car_trunk)
      if not trunk.is_empty() then
        trunk.clear()
        s.docked = s.docked + 1
      end
    end
  end
  -- Felder leeren.
  local minute = (tick - s.start) / 3600
  for i, at_min in ipairs(T27_EMPTY_AT) do
    if not s.empties[i] and minute >= at_min and #deployed > 0 then
      local h = deployed[(i % #deployed) + 1]
      empty_field(tb, h.entity.position)
      s.empties[i] = tick
      s.moves_before = s.moves_before or {}
      s.moves_before[i] = s.kinds.move or 0
      tb.trace(run, "Feld leer bei " .. pos_text(tb, h.entity.position))
    end
    -- Wieder drei: seit dem leeren Feld ein Umsetzen begonnen, drei aktiv (aufgebaut oder nach einer Rettung wartend)
    -- und kein Einsatz oder Umsetzen offen. (PC-Lauf 325d24b zählte ohne die erste Bedingung 2 s, bevor der Ernter
    -- „Feld leer“ meldete.)
    if s.empties[i] and not s.recover[i] and (s.kinds.move or 0) > s.moves_before[i] and c and c.active == 3
        and not open_transfer(s) then
      s.recover[i] = tick - s.empties[i]
    end
  end
  -- Wurmzeichen.
  if tick >= s.next_hunt and tick < s.start + T27_TICKS then
    s.next_hunt = tick + T27_HUNT_EVERY
    if #deployed > 0 then
      s.target = s.target % #deployed + 1
      local hunt = worms_lib.start_hunt(deployed[s.target].entity, {seconds = 60, debug = true})
      if hunt then table.insert(s.hunts, hunt) end
    else
      s.skipped = (s.skipped or 0) + 1
    end
  end
  if (tick - s.start) % 1800 == 0 then
    tb.trace(run, string.format("Stand: aufgebaut %d, aktiv %s, Reserve %s, Aufträge %d", #deployed, tostring(c and c.active),
      tostring(c and c.reserve), depot_jobs(s)))
  end
  if tick < s.start + T27_TICKS + T27_SETTLE then return end
  local failed = {}
  local escaped, bitten, open = 0, 0, 0
  for _, hunt in ipairs(s.hunts) do
    if hunt.outcome == "escaped" then escaped = escaped + 1
    elseif hunt.outcome == "bitten" then bitten = bitten + 1
    else open = open + 1 end
  end
  check(failed, #s.hunts >= 25, #s.hunts .. " Wurmzeichen statt mindestens 25")
  check(failed, bitten == 0 and open == 0, bitten .. " gebissen, " .. open .. " ohne Ende")
  check(failed, s.max_active <= 3, "bis zu " .. s.max_active .. " aktiv")
  -- Aktiv statt aufgebaut: Auch nach den Wurmzeichen sind oft ein oder zwei gerade zum Entladen an der Annahme
  -- (PC-Lauf fa36b5f: aufgebaut 1 bis 3, aktiv immer 3).
  check(failed, c ~= nil and c.active == 3, tostring(c and c.active) .. " aktiv am Ende statt 3")
  local total = #owned(s) + depot_items(s, NAME)
  check(failed, total == 5, total .. " Ernter statt 5 (draußen und im Lager)")
  local recover = {}
  for i = 1, #T27_EMPTY_AT do
    local r = s.recover[i]
    table.insert(recover, r and tb.num(r / 60) or "nie")
    check(failed, r ~= nil and r <= T27_RECOVER, "nach leerem Feld " .. i .. " nicht binnen 4 min wieder 3")
  end
  check(failed, (s.kinds.move or 0) >= #T27_EMPTY_AT, (s.kinds.move or 0) .. " Umsetzen statt mindestens " .. #T27_EMPTY_AT)
  local kinds = {}
  for _, kind in ipairs({"deploy", "move", "recall", "rescue", "return", "unload", "refuel"}) do
    table.insert(kinds, kind .. " " .. (s.kinds[kind] or 0))
  end
  tb.log(run, #failed == 0 and "OK" or "FEHLER", string.format(
    "Dauerlauf Flottenleitung: Wurmzeichen %d (entkommen %d), höchstens %d aktiv, wieder 3 nach %s s, Aufträge %s, entladen %d"
    .. ", ausgefallen %d", #s.hunts, escaped, s.max_active, table.concat(recover, "/"), table.concat(kinds, ", "), s.docked,
    s.skipped or 0) .. (#failed > 0 and (" | nicht erfüllt: " .. table.concat(failed, "; ")) or ""))
  s.start = nil
  tb.finish(run, #failed == 0 and "Dauerlauf OK" or "Dauerlauf FEHLER")
end

local function t27_cleanup(run, tb)
  pcall(tidy, run)
  pcall(sweep, run, tb)
  pcall(fleet_force, false)
end

return
{
  T27 =
  {
    title = "Flottenleitung: Dauerlauf",
    timeout = T27_TICKS + T27_SETTLE + 60 * 60,
    interactive = false,
    confirm = nil,
    start = t27_start,
    tick = t27_tick,
    cleanup = t27_cleanup
  }
}
