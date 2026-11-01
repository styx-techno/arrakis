-- Gerüst der interaktiven Spielabend-Tests T31, T34, T36 und T38 (0.16.1). Bis 0.16.0 standen sie nur in den Plänen
-- (docs/plan-3g.md, -3h, -3i, -3j); im Spiel meldete der Prüfstand „Unbekannter Test“ (Max 01.11.2026).
-- Ablauf wie T20 und T22: Max' Force auf der Prüfstand-Fläche, Würmer an (wach, Lehrjagd verbraucht), Max unverwundbar;
-- ALT+O oder /arrakis-test weiter schaltet zum nächsten Schritt, nach dem letzten endet der Test. Beim Weiterschalten
-- enden laufende Befehlsjagden des Tests ohne Biss, damit kein Wurm überlebt. Gebautes bleibt zum Ansehen stehen;
-- Jagden, Würmer, Wärme, Ruhe, Schonfrist, Pause und Statistik räumt cleanup.
--
-- spec = {id, title, minutes, half, last, intro, techs = {Namen}, max_at = {dx, dy}, no_hunts, keep_hunts, setup(run, tb, d),
--         enter = {[n] = function(run, tb, d)}, watch = {[n] = function(run, tb, d)}, teardown(run, tb, d)}

local common = require("scripts.testbench.gemeinsam_sandwurm")
local worms_lib = common.worms_lib
local vibration_lib = common.vibration_lib
local sandworm_lib = common.sandworm_lib
local terrain = common.terrain
local valid = common.valid
local at = common.at
local read = common.read
local copy = common.copy
local box_of = common.box_of
local clear_area = common.clear_area
local abort_hunts = common.abort_hunts
local end_if_running = common.end_if_running
local sandworms_in = common.sandworms_in
local new_made = common.new_made

local M = {}

-- Befehlsjagd mit Merker; label für die Datei.
function M.hunt(run, tb, d, entity, opts, label)
  local hunt, reason = worms_lib.start_hunt(entity, opts)
  if not hunt then
    tb.log(run, "FEHLER", d.step .. ") " .. label .. ": Jagd ging nicht (" .. tostring(reason) .. ")")
    return nil
  end
  table.insert(d.hunts, hunt)
  tb.log(run, "INFO", string.format("%d) %s: Jagd %d%s, Biss bei 0 in %s s", d.step, label, hunt.id,
    hunt.size == "large" and " (großer Wurm)" or "", tb.num((hunt.eta_tick - game.tick) / 60, 0)))
  return hunt
end

function M.ask(run, tb, d, text)
  tb.log(run, "FRAGE", d.step .. ") " .. text)
end

-- Forschung für Max' Force (wie T17); schreibt eine INFO, wenn sie neu ist.
function M.research(run, tb, force, names)
  for _, name in ipairs(names or {}) do
    local tech = force.technologies[name]
    if not tech then
      tb.log(run, "FEHLER", "Forschung " .. name .. " fehlt")
    elseif not tech.researched then
      tech.researched = true
      tb.log(run, "INFO", "Forschung " .. name .. " für deine Force erforscht")
    end
  end
end

-- Items in Max' Inventar (INFO mit der Menge, die passte).
function M.give(run, tb, player, name, count)
  local ok, n = pcall(function() return player.insert{name = name, count = count} end)
  tb.log(run, ok and n == count and "INFO" or "FEHLER", string.format("%d × %s in dein Inventar%s", ok and n or 0, name,
    ok and "" or (": " .. tostring(n))))
  return ok and n or 0
end

-- Stelle zum Hinstellen: gelber Kreis am Boden (10 min sichtbar) und gps-Text für den Chat.
function M.mark(tb, position, radius)
  pcall(function()
    rendering.draw_circle{color = {r = 1, g = 0.85, b = 0.2, a = 0.9}, radius = radius or 1.5, width = 4, filled = false,
      target = position, surface = tb.surface(), time_to_live = 36000}
  end)
  return string.format("[gps=%d,%d,%s]", math.floor(position.x), math.floor(position.y), tb.surface().name)
end

-- Felsinsel x1..x2 × y1..y2 (Kacheln relativ zu base) mit n Geschützen am Rand (Seite side: "west" oder "east"), je 50
-- Uranmunition, Force force. Gibt die Zahl der gebauten Geschütze zurück.
function M.turret_island(run, tb, d, base, x1, y1, x2, y2, n, side)
  local surface = tb.surface()
  local bx, by = math.floor(base.x), math.floor(base.y)
  common.tiles(surface, bx + x1, by + y1, bx + x2, by + y2, common.ROCK)
  local built = 0
  local x = side == "east" and (bx + x2 - 1) or (bx + x1 + 1)
  local span = y2 - y1 - 2
  for i = 0, n - 1 do
    local column = math.floor(i / math.max(1, math.floor(span / 2)))
    local row = i % math.max(1, math.floor(span / 2))
    local px = x + (side == "east" and -2 * column or 2 * column)
    local turret = common.make(run, tb, d.made, {name = "gun-turret", position = {x = px + 0.0, y = by + y1 + 2 + 2 * row}, force = d.force})
    if turret then
      turret.insert{name = "uranium-rounds-magazine", count = 50}
      built = built + 1
    end
  end
  return built
end

-- Wurmzähne am Boden in box (Zahl der Items).
function M.teeth_in(tb, box)
  local n = 0
  for _, e in pairs(tb.surface().find_entities_filtered{area = box, name = "item-on-ground"}) do
    local stack = e.stack
    if stack and stack.valid_for_read and stack.name == "arrakis-worm-tooth" then n = n + stack.count end
  end
  return n
end

function M.define(spec)
  local end_ticks = spec.minutes * 3600

  local function next_step(run, tb, d)
    if d.step >= spec.last then
      d.done_all = true
      tb.finish(run, string.format("%d Schritte, %d Jagden", d.step, #d.hunts))
      return
    end
    if not spec.keep_hunts then
      for _, hunt in ipairs(d.hunts) do end_if_running(hunt) end
    end
    d.step = d.step + 1
    tb.log(run, "INFO", "Schritt " .. d.step .. " von " .. spec.last)
    local fn = spec.enter[d.step]
    if fn then
      local ok, err = pcall(fn, run, tb, d)
      if not ok then tb.log(run, "FEHLER", d.step .. ") Skriptfehler: " .. tostring(err)) end
    end
  end

  local function start(run, tb)
    local d = run.data
    local player = tb.player(run)
    if not player then
      tb.log(run, "FEHLER", spec.id .. " braucht einen Spieler im Spiel")
      tb.finish(run, "abgebrochen (kein Spieler)")
      return
    end
    if not common.storage_ready() then
      tb.log(run, "FEHLER", "storage des Laufzeitcodes fehlt (scripts/migrate.lua init)")
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
    d.box = box_of(d.origin, {x = spec.half, y = spec.half})
    d.saved = {grace = worms_lib.grace_snapshot(force), paused = storage.hunts.paused_until}
    d.stats = copy(worms_lib.stats_of(force))
    d.made = {made = new_made()}
    d.hunts = {}
    d.step = 0
    clear_area(surface, d.box)
    tb.prepare(d.origin, spec.half)
    worms_lib.ensure_force()
    -- no_hunts: keine regulären Wurmzeichen während des Tests (Befehlsjagden gehen weiter).
    worms_lib.set_paused(spec.no_hunts and (game.tick + end_ticks + 600) or nil)
    worms_lib.set_worm_off(force, false)
    vibration_lib.testbench_enable(force)
    worms_lib.set_grace(force, {awake = true, first_hunt_done = true})
    M.research(run, tb, force, spec.techs)
    tb.protect(run, player)
    d.max_pos = at(d.origin, spec.max_at[1], spec.max_at[2])
    tb.watch(run, player, d.max_pos)
    tb.log(run, "INFO", spec.intro .. " " .. spec.last .. " Schritte mit deiner Force (" .. force.name .. ", Würmer an); ALT+O oder"
      .. " /arrakis-test weiter schaltet zum nächsten, nach Schritt " .. spec.last .. " endet der Test. Ende sonst nach " .. spec.minutes
      .. " min Spielzeit oder mit /arrakis-test stop. Bitte vorher /arrakis-test tempo 1.")
    if game.speed ~= 1 then
      tb.log(run, "INFO", "Zeitraffer an (game.speed " .. string.format("%g", game.speed) .. "): zurück mit /arrakis-test tempo 1")
    end
    if spec.setup then
      local ok, err = pcall(spec.setup, run, tb, d)
      if not ok then tb.log(run, "FEHLER", "Aufbau: Skriptfehler: " .. tostring(err)) end
    end
    next_step(run, tb, d)
  end

  local function tick(run, tb)
    local d = run.data
    if not d.made or d.done_all then return end
    local fn = spec.watch and spec.watch[d.step]
    if fn then
      local ok, err = pcall(fn, run, tb, d)
      if not ok then tb.log(run, "FEHLER", d.step .. ") Skriptfehler: " .. tostring(err)) end
    end
    if game.tick - run.started >= end_ticks then
      d.done_all = true
      tb.finish(run, string.format("%d min um: Schritt %d, %d Jagden", spec.minutes, d.step, #d.hunts))
    end
  end

  local function on_event(run, tb, name, event)
    local d = run.data
    if not d.made or d.done_all then return end
    if (name == "test_key" or name == "test_next") and event.player_index == run.player_index then next_step(run, tb, d) end
  end

  local function cleanup(run, tb)
    local d = run.data
    local force = d.force
    if not valid(force) then return end
    if spec.teardown then pcall(spec.teardown, run, tb, d) end
    pcall(abort_hunts, {[force.index] = true})
    local surface = tb.surface()
    pcall(sandworm_lib.sweep, {surface})
    if d.box then
      local left = read(function() return sandworms_in(surface, d.box) end) or 0
      if left > 0 then tb.log(run, "FEHLER", left .. " arrakis-sandworm-* nach dem Aufräumen im Bereich von " .. spec.id) end
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
    title = spec.title,
    timeout = end_ticks + 60,
    interactive = true,
    steps = true,
    confirm = nil,
    start = start,
    tick = tick,
    on_event = on_event,
    cleanup = cleanup
  }
end

return M
