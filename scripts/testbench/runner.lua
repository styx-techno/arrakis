-- Prüfstand (Phase 3a): Befehl /arrakis-test, Ablauf, Protokoll und Hilfsfunktionen.
-- Nur geladen mit der Startup-Einstellung "arrakis-testbench" (siehe control.lua).
--
-- Vertrag mit den Testmodulen (t_flyer, t_harvester, t_worm, t_map, t_ernter):
--   Ein Modul gibt {T1 = {title, timeout, interactive, confirm, start, tick, on_event, cleanup}, …} zurück.
--   start(run, tb), tick(run, tb), on_event(run, tb, name, event), cleanup(run, tb).
--   Optional: hint (Text für die Testliste), answer_time (Ticks Pause bei „alle“ nach diesem Test,
--   damit Max eine FRAGE vom Testende vor Ort beantworten kann).
--   run = storage.testbench.run = {id, player_index, started, data = {}, args = {…}, counts = {…}}, nur Daten.
--     run.data gehört dem Test; Schlüssel mit "tb_" benutzt der Runner (z. B. tb_protect).
--   tb = diese Bibliothek (Funktionen unten), liegt nie in storage.
--   Weitergeleitete Ereignisse (name): spider_command_completed, test_key, entity_died,
--   driving_changed, script_path.
--
-- storage.testbench = {
--   run = run | nil,                         -- laufender Test (höchstens einer)
--   queue = {id…} | nil,                     -- restliche Tests bei „alle“
--   all = {started, list = {…}} | nil,       -- Ergebnisse von „alle“
--   pending = {tick, id, player_index} | nil, -- nächster Test bei „alle“
--   back = {[player_index] = {surface, position}}, -- für /arrakis-test zurück
--   results = {[id] = {summary, tick, counts}},
-- }

local tb = {}
local runner = {}

local SURFACE_NAME = "arrakis-testbench"
local HOLD_NAME = "arrakis-test-hold"
local LOG_FILE = "arrakis-test.txt"
local ORDER = {"T1", "T2", "T3", "T4", "T5", "T6", "T7", "T9", "T11", "T12", "T13", "T2b"}
local AREA_SPACING = 2000
local DEFAULT_TIMEOUT = 60 * 60
local NEXT_TEST_DELAY = 60

local COLORS =
{
  OK = {r = 0.35, g = 1, b = 0.35},
  FEHLER = {r = 1, g = 0.35, b = 0.35},
  INFO = {r = 0.85, g = 0.85, b = 0.85},
  MESSUNG = {r = 0.45, g = 0.8, b = 1},
  FRAGE = {r = 1, g = 0.85, b = 0.25},
  ENDE = {r = 1, g = 1, b = 1}
}

local tests = {}
for _, module_name in ipairs({"scripts.testbench.t_flyer", "scripts.testbench.t_harvester",
                              "scripts.testbench.t_worm", "scripts.testbench.t_map",
                              "scripts.testbench.t_ernter"}) do
  for id, test in pairs(require(module_name)) do
    tests[id] = test
  end
end

-- Test-ID zu einem eingegebenen Wort, ohne Groß-/Kleinschreibung (T2b); nil, wenn es keinen Test gibt.
local function find_id(word)
  local key = string.upper(word)
  for id in pairs(tests) do
    if string.upper(id) == key then return id end
  end
  return nil
end

-- Test-IDs in fester Reihenfolge, unbekannte (neue) hinten angehängt.
local function ordered_ids()
  local result, known = {}, {}
  for _, id in ipairs(ORDER) do
    known[id] = true
    if tests[id] then table.insert(result, id) end
  end
  local extra = {}
  for id in pairs(tests) do
    if not known[id] then table.insert(extra, id) end
  end
  table.sort(extra)
  for _, id in ipairs(extra) do table.insert(result, id) end
  return result
end

local function state()
  storage.testbench = storage.testbench or {}
  local s = storage.testbench
  s.back = s.back or {}
  s.results = s.results or {}
  return s
end

-- Positionen dürfen als {x = …, y = …} oder {…, …} kommen.
local function xy(position)
  return position.x or position[1], position.y or position[2]
end

local function box(area)
  local left_top = area.left_top or area[1]
  local right_bottom = area.right_bottom or area[2]
  local x1, y1 = xy(left_top)
  local x2, y2 = xy(right_bottom)
  return x1, y1, x2, y2
end

local function inside(area, position, margin)
  local x1, y1, x2, y2 = box(area)
  local x, y = xy(position)
  margin = margin or 0
  return x >= x1 - margin and x <= x2 + margin and y >= y1 - margin and y <= y2 + margin
end

-- Protokoll --------------------------------------------------------------------------------

local function write(line)
  helpers.write_file(LOG_FILE, line .. "\n", true)
end

local function chat(text, color)
  game.print(text, {color = color, skip = defines.print_skip.never})
end

-- Eine Zeile in Chat (farbig) und Datei (mit Sekunden seit Teststart).
local function emit(run, level, text)
  local prefix = run and ("[" .. run.id .. "] ") or "[Prüfstand] "
  chat(prefix .. level .. ": " .. text, COLORS[level] or COLORS.INFO)
  local elapsed = run and string.format(" +%.1fs", (game.tick - run.started) / 60) or ""
  write(prefix .. level .. elapsed .. ": " .. text)
end

-- Ticks als Sekundenangabe: ganze Sekunden ohne Nachkommastelle.
local function seconds(ticks)
  if ticks % 60 == 0 then return string.format("%d s", math.floor(ticks / 60)) end
  return string.format("%.1f s", ticks / 60)
end

-- Fehler in Testcode abfangen: melden statt das Spiel anzuhalten.
local function call(run, what, fn, ...)
  if not fn then return true end
  local ok, err = pcall(fn, ...)
  if not ok then
    tb.log(run, "FEHLER", "Skriptfehler in " .. what .. ": " .. tostring(err))
  end
  return ok
end

local function format_counts(counts)
  counts = counts or {}
  return string.format("OK %d, FEHLER %d, FRAGE %d", counts.OK or 0, counts.FEHLER or 0, counts.FRAGE or 0)
end

local function report_all()
  local s = state()
  local all = s.all
  s.queue = nil
  s.all = nil
  s.pending = nil
  if not all then return end
  write("")
  write(string.format("=== Zusammenfassung „alle“ | Tick %d | %.1f s ===", game.tick, (game.tick - all.started) / 60))
  chat("[Prüfstand] Zusammenfassung „alle“:", COLORS.ENDE)
  for _, entry in ipairs(all.list) do
    local line = string.format("%s %s: %s (%s)", entry.id, entry.title, entry.summary, format_counts(entry.counts))
    chat(line, (entry.counts.FEHLER or 0) > 0 and COLORS.FEHLER or COLORS.OK)
    write(line)
  end
  if all.skipped and #all.skipped > 0 then
    local line = "Übersprungen (interaktiv oder mit Bestätigung): " .. table.concat(all.skipped, ", ")
    chat(line, COLORS.INFO)
    write(line)
  end
  -- FRAGEn lassen sich bei „alle“ oft nicht vor Ort beantworten (der nächste Test teleportiert weiter).
  local asked = {}
  for _, entry in ipairs(all.list) do
    if (entry.counts.FRAGE or 0) > 0 then table.insert(asked, entry.id) end
  end
  if #asked > 0 then
    local line = "Offene FRAGEn bei " .. table.concat(asked, ", ") .. ": stehen oben und in der Datei. "
      .. "Was du nicht mehr ansehen konntest, mit /arrakis-test " .. asked[1] .. " (usw.) einzeln wiederholen."
    chat(line, COLORS.FRAGE)
    write(line)
  end
  local back = "Zurück zu deiner Position vor dem Test: /arrakis-test zurück"
  chat(back, COLORS.INFO)
  write(back)
end

-- Ablauf -----------------------------------------------------------------------------------

local function start_test(id, player_index, args)
  local s = state()
  local test = tests[id]
  local run =
  {
    id = id,
    player_index = player_index,
    started = game.tick,
    data = {},
    args = args or {},
    counts = {}
  }
  s.run = run
  local player = tb.player(run)
  write("")
  write(string.format("=== %s %s | Tick %d | Arrakis %s | base %s | Spieler %s%s ===",
    id, test.title, game.tick, script.active_mods["arrakis"] or "?", script.active_mods["base"] or "?",
    player and player.name or "-", #run.args > 0 and (" | Argumente: " .. table.concat(run.args, " ")) or ""))
  tb.log(run, "INFO", "Start: " .. test.title)
  if not call(run, "start", test.start, run, tb) then
    tb.finish(run, "abgebrochen (Skriptfehler)")
  end
end

-- Bricht einen laufenden Test und „alle“ ab.
local function abort_running(reason)
  local s = state()
  s.pending = nil
  if s.queue then
    s.queue = {}
    emit(nil, "INFO", "„alle“ abgebrochen: " .. reason)
  end
  if s.run then
    tb.log(s.run, "INFO", "Abgebrochen: " .. reason)
    tb.finish(s.run, "abgebrochen (" .. reason .. ")")
  end
  if s.queue then report_all() end
end

local function leave_vehicle(player)
  if player.controller_type == defines.controllers.remote then
    pcall(function() player.exit_remote_view() end)
  end
  if player.driving then
    player.driving = false
  end
end

-- Hilfsfunktionen für Testmodule ----------------------------------------------------------

-- LuaPlayer des Tests oder nil.
function tb.player(run)
  local player = run and run.player_index and game.get_player(run.player_index)
  if player and player.valid then return player end
  return nil
end

-- Testoberfläche: Laborkacheln, keine Gegner (keine Kartengenerierung), immer Tag.
function tb.surface()
  local surface = game.get_surface(SURFACE_NAME)
  if surface then return surface end
  surface = game.create_surface(SURFACE_NAME)
  surface.generate_with_lab_tiles = true
  surface.always_day = true
  return surface
end

-- Ablage-Oberfläche (T3, T9): Laborkacheln, 5×5 Chunks um 0,0 sofort erzeugt, für alle Forces versteckt.
-- Gibt es sie schon, wird sie nur zurückgegeben (Chunks und Verstecken werden nachgeholt).
function tb.hold_surface()
  local surface = game.get_surface(HOLD_NAME)
  if not surface then
    surface = game.create_surface(HOLD_NAME)
    surface.generate_with_lab_tiles = true
  end
  surface.request_to_generate_chunks({0, 0}, 2)
  surface.force_generate_chunk_requests()
  for _, force in pairs(game.forces) do
    pcall(function() force.set_surface_hidden(surface, true) end)
  end
  return surface
end

-- Ursprung des Testbereichs: je Test 2000 Kacheln weiter in x (T1 bei 0, T2 bei 2000, …).
function tb.area(id)
  for index, known in ipairs(ordered_ids()) do
    if known == id then return {x = (index - 1) * AREA_SPACING, y = 0} end
  end
  return {x = (#ordered_ids()) * AREA_SPACING, y = 0}
end

-- Füllt ein Rechteck (BoundingBox) mit einer Kachel. Entities bleiben stehen (keine Spielerfigur
-- wird entfernt). Gibt die Zahl der Kacheln zurück.
function tb.fill(area, tile_name, surface)
  surface = surface or tb.surface()
  local x1, y1, x2, y2 = box(area)
  local tiles = {}
  for x = math.floor(x1), math.ceil(x2) - 1 do
    for y = math.floor(y1), math.ceil(y2) - 1 do
      tiles[#tiles + 1] = {name = tile_name, position = {x, y}}
    end
  end
  surface.set_tiles(tiles, true, false, true, false)
  return #tiles
end

-- Spielerfiguren nie entfernen. Zusätzlich zu player/associated_player zählt jede Figur, die
-- player.character eines Spielers ist (z. B. während er in der Kartenansicht/Fernsteuerung ist).
local function is_player_character(entity, keep)
  if entity.type ~= "character" then return false end
  if entity.unit_number and keep[entity.unit_number] then return true end
  return entity.player ~= nil or entity.associated_player ~= nil
end

local function player_characters()
  local keep = {}
  for _, player in pairs(game.players) do
    local character = player.character
    if character and character.valid and character.unit_number then
      keep[character.unit_number] = true
    end
  end
  return keep
end

-- Bereitet einen Testbereich vor: Chunks sofort erzeugen, alles außer Spielerfiguren entfernen
-- (auch Würmer), Grundkachel legen (Standard sand-1), für die Spieler kartieren.
-- half_size: Zahl oder {x, y}. Gibt die BoundingBox des Bereichs zurück.
function tb.prepare(origin, half_size, base_tile)
  local surface = tb.surface()
  local ox, oy = xy(origin)
  local hx, hy
  if type(half_size) == "table" then
    hx, hy = xy(half_size)
  else
    hx, hy = half_size, half_size
  end
  local area =
  {
    left_top = {x = math.floor(ox - hx), y = math.floor(oy - hy)},
    right_bottom = {x = math.ceil(ox + hx), y = math.ceil(oy + hy)}
  }
  surface.request_to_generate_chunks({ox, oy}, math.ceil(math.max(hx, hy) / 32) + 1)
  surface.force_generate_chunk_requests()

  -- Spieler steigen aus Fahrzeugen im Bereich aus, damit nichts mit ihnen entfernt wird.
  for _, player in pairs(game.connected_players) do
    local vehicle = player.physical_vehicle
    if vehicle and vehicle.valid and vehicle.surface.name == SURFACE_NAME and inside(area, vehicle.position) then
      leave_vehicle(player)
    end
  end

  for _, unit in pairs(surface.get_segmented_units()) do
    if unit.valid then
      for _, node in pairs(unit.get_body_nodes()) do
        if inside(area, node, 40) then
          pcall(function() unit.destroy({raise_destroy = false}) end)
          break
        end
      end
    end
  end

  local keep = player_characters()
  for _, entity in pairs(surface.find_entities_filtered{area = area}) do
    if entity.valid and entity.type ~= "segment" and entity.type ~= "segmented-unit"
      and not is_player_character(entity, keep) then
      pcall(function() entity.destroy() end)
    end
  end
  surface.destroy_decoratives{area = area}
  tb.fill(area, base_tile or "sand-1", surface)

  for _, player in pairs(game.connected_players) do
    pcall(function() player.force.chart(surface, area) end)
  end
  return area
end

-- Zeile in Chat und Datei. level: OK, FEHLER, INFO, MESSUNG, FRAGE. text: string.
function tb.log(run, level, text)
  if run and run.counts then
    run.counts[level] = (run.counts[level] or 0) + 1
  end
  emit(run, level, tostring(text))
end

-- Messzeile nur in die Datei (kein Chat, nicht gezählt), z. B. Messpunkte im Sekundentakt.
function tb.trace(run, text)
  local prefix = run and ("[" .. run.id .. "] ") or "[Prüfstand] "
  local elapsed = run and string.format(" +%.1fs", (game.tick - run.started) / 60) or ""
  write(prefix .. "MESSUNG" .. elapsed .. ": " .. tostring(text))
end

-- Beendet den Test: cleanup, Spielfigur wieder verwundbar, Zusammenfassung, ggf. nächster Test.
function tb.finish(run, summary)
  local s = state()
  if not run or s.run ~= run then return end
  s.run = nil
  local test = tests[run.id]
  if test and test.cleanup then
    call(run, "cleanup", test.cleanup, run, tb)
  end
  tb.unprotect(run)
  summary = summary and tostring(summary) or "-"
  local counts = run.counts or {}
  emit(run, "ENDE", string.format("%s (%s, %.1f s)", summary, format_counts(counts), (game.tick - run.started) / 60))
  s.results[run.id] = {summary = summary, tick = game.tick, counts = counts}
  if s.all then
    table.insert(s.all.list, {id = run.id, title = test and test.title or "?", summary = summary, counts = counts})
  end
  if s.queue then
    if #s.queue > 0 then
      local delay = NEXT_TEST_DELAY
      local answer_time = test and test.answer_time
      if type(answer_time) == "number" and answer_time > delay and (counts.FRAGE or 0) > 0 then
        delay = answer_time
      end
      local next_id = table.remove(s.queue, 1)
      s.pending = {tick = game.tick + delay, id = next_id, player_index = run.player_index}
      if delay > NEXT_TEST_DELAY then
        emit(nil, "INFO", string.format("Nächster Test (%s) in %s: Zeit für die FRAGE von %s. /arrakis-test stop hält „alle“ an.",
          next_id, seconds(delay), run.id))
      end
    else
      report_all()
    end
  end
end

-- Teleportiert den Spieler zum Testbereich (oder zu position). Merkt sich vorher Oberfläche und
-- Position für /arrakis-test zurück (nur wenn er nicht schon auf der Testoberfläche ist).
function tb.watch(run, player, position)
  player = player or tb.player(run)
  if not (player and player.valid) then return false end
  local s = state()
  local surface = tb.surface()
  leave_vehicle(player)
  local here = player.physical_surface
  if here.name ~= SURFACE_NAME then
    local x, y = xy(player.physical_position)
    s.back[player.index] = {surface = here.name, position = {x = x, y = y}}
    player.print("Prüfstand: Zurück zu dieser Stelle mit /arrakis-test zurück", {color = COLORS.INFO})
  end
  local target = position or tb.area(run.id)
  target = surface.find_non_colliding_position("character", target, 30, 0.5) or target
  return player.teleport(target, surface)
end

-- Legt count Stück item ins Brennstoffinventar. Gibt die eingelegte Menge zurück.
function tb.fuel(entity, item, count)
  local inventory = entity and entity.valid and entity.get_fuel_inventory()
  if not inventory then return 0 end
  return inventory.insert({name = item, count = count})
end

-- Erzeugt eine Spielfigur ohne Spieler (Force des Fahrzeugs, also des Spielers) und setzt sie als Fahrer.
function tb.dummy_driver(entity, force)
  local surface = entity.surface
  local position = surface.find_non_colliding_position("character", entity.position, 10, 0.5) or entity.position
  local character = surface.create_entity{name = "character", position = position, force = force or entity.force}
  if not character then return nil end
  entity.set_driver(character)
  return character
end

-- Name der Kachel an einer Position.
function tb.tiles_name(surface, position)
  local x, y = xy(position)
  return surface.get_tile(math.floor(x), math.floor(y)).name
end

function tb.on_rock(surface, position)
  return tb.tiles_name(surface, position) == "arrakis-rock"
end

-- Tempo in Kacheln/s (Auto, Spinne, Wurm: speed ist Kacheln je Tick). nil, wenn unbekannt.
function tb.speed_tps(entity)
  if not (entity and entity.valid) then return nil end
  local ok, speed = pcall(function() return entity.speed end)
  if not ok or not speed then return nil end
  return math.abs(speed) * 60
end

-- Force der Würmer, gegenseitig feindlich zu allen anderen Forces (ohne Waffenruhe).
function tb.worm_force()
  local force = game.forces["arrakis-sandworm"] or game.create_force("arrakis-sandworm")
  for name, other in pairs(game.forces) do
    if name ~= force.name and name ~= "neutral" then
      force.set_friend(other, false)
      other.set_friend(force, false)
      force.set_cease_fire(other, false)
      other.set_cease_fire(force, false)
    end
  end
  return force
end

-- Spielfigur unverwundbar machen; der alte Wert steht in run.data.tb_protect.
function tb.protect(run, player)
  player = player or tb.player(run)
  local character = player and player.valid and player.character
  if not character then return false end
  if not run.data.tb_protect then
    run.data.tb_protect = {character = character, destructible = character.destructible}
  end
  character.destructible = false
  return true
end

-- Alten Wert wiederherstellen. Läuft bei jedem Testende automatisch.
function tb.unprotect(run)
  local saved = run and run.data and run.data.tb_protect
  if not saved then return end
  run.data.tb_protect = nil
  if saved.character and saved.character.valid then
    saved.character.destructible = saved.destructible
  end
end

-- Kleine Helfer für Ausgaben.

-- Zahl mit einer (oder digits) Nachkommastelle, nil als „–“.
function tb.num(value, digits)
  if type(value) ~= "number" then return "–" end
  return string.format("%." .. (digits or 1) .. "f", value)
end

-- Name eines defines-Werts, z. B. tb.enum_name(defines.controllers, player.controller_type).
function tb.enum_name(enum, value)
  for name, v in pairs(enum or {}) do
    if v == value then return name end
  end
  return tostring(value)
end

function tb.distance(a, b)
  local ax, ay = xy(a)
  local bx, by = xy(b)
  return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- Sekunden seit Teststart.
function tb.elapsed(run)
  return (game.tick - run.started) / 60
end

-- Befehl ------------------------------------------------------------------------------------

local function list_tests(player)
  local s = state()
  player.print("Prüfstand: /arrakis-test Tn [Argument] | alle | stop | zurück")
  for _, id in ipairs(ordered_ids()) do
    local test = tests[id]
    local notes = {seconds(test.timeout or DEFAULT_TIMEOUT)}
    if test.interactive then table.insert(notes, "interaktiv, nicht bei „alle“") end
    if test.confirm then table.insert(notes, "nur mit /arrakis-test " .. id .. " " .. test.confirm) end
    if test.hint then table.insert(notes, test.hint) end
    local last = s.results[id]
    if last then table.insert(notes, "zuletzt: " .. last.summary) end
    player.print(id .. " – " .. test.title .. " (" .. table.concat(notes, "; ") .. ")")
  end
  player.print("Ergebnisse stehen im Chat und in script-output/" .. LOG_FILE .. ".")
  if s.run then player.print("Läuft gerade: " .. s.run.id) end
end

local function go_back(player)
  local s = state()
  local back = s.back[player.index]
  if not back then
    player.print("Keine gemerkte Position.")
    return
  end
  local surface = game.get_surface(back.surface)
  if not surface then
    s.back[player.index] = nil
    player.print("Die Oberfläche " .. back.surface .. " gibt es nicht mehr.")
    return
  end
  leave_vehicle(player)
  local target = surface.find_non_colliding_position("character", back.position, 10, 0.5) or back.position
  if player.teleport(target, surface) then
    s.back[player.index] = nil
    player.print("Zurück auf " .. surface.name .. ".")
  else
    player.print("Teleport zurück ging nicht.")
  end
end

local function start_all(player)
  local s = state()
  abort_running("neuer Start: alle")
  local queue, skipped = {}, {}
  for _, id in ipairs(ordered_ids()) do
    local test = tests[id]
    if test.interactive or test.confirm then
      table.insert(skipped, id)
    else
      table.insert(queue, id)
    end
  end
  if #queue == 0 then
    player.print("Keine Tests für „alle“.")
    return
  end
  write("")
  write(string.format("=== alle: %s | Tick %d ===", table.concat(queue, ", "), game.tick))
  s.queue = queue
  s.all = {started = game.tick, list = {}, skipped = skipped}
  start_test(table.remove(s.queue, 1), player.index, {})
end

local function on_command(command)
  local player = command.player_index and game.get_player(command.player_index)
  if not player then return end
  if not player.admin then
    player.print("Nur Admins dürfen /arrakis-test benutzen.")
    return
  end
  local words = {}
  for word in string.gmatch(command.parameter or "", "%S+") do
    table.insert(words, word)
  end
  if #words == 0 then
    list_tests(player)
    return
  end
  local key = string.lower(words[1])
  if key == "stop" then
    local s = state()
    if s.run or s.queue then
      abort_running("stop")
    else
      player.print("Es läuft kein Test.")
    end
  elseif key == "zurück" or key == "zurueck" then
    go_back(player)
  elseif key == "alle" then
    start_all(player)
  else
    local id = find_id(words[1])
    local test = id and tests[id]
    if not test then
      player.print("Unbekannter Test: " .. words[1] .. ". Liste: /arrakis-test")
      return
    end
    local args = {}
    for i = 2, #words do table.insert(args, words[i]) end
    if test.confirm and args[1] ~= test.confirm then
      player.print(id .. " startet nur mit /arrakis-test " .. id .. " " .. test.confirm .. " (nur in einem Wegwerf-Spielstand).")
      return
    end
    abort_running("neuer Test " .. id)
    start_test(id, player.index, args)
  end
end

-- Ereignisse -------------------------------------------------------------------------------

local function on_tick(event)
  local s = storage.testbench
  if not s then return end
  if s.pending and not s.run and event.tick >= s.pending.tick then
    local pending = s.pending
    s.pending = nil
    if tests[pending.id] then
      start_test(pending.id, pending.player_index, {})
    end
    return
  end
  local run = s.run
  if not run then return end
  local test = tests[run.id]
  if not test then
    s.run = nil
    return
  end
  if event.tick - run.started >= (test.timeout or DEFAULT_TIMEOUT) then
    tb.log(run, "FEHLER", "Zeitüberschreitung nach " .. seconds(test.timeout or DEFAULT_TIMEOUT))
    tb.finish(run, "Zeitüberschreitung")
    return
  end
  if test.tick and not call(run, "tick", test.tick, run, tb) then
    tb.finish(run, "abgebrochen (Skriptfehler)")
  end
end

local function forward(name)
  return function(event)
    local s = storage.testbench
    local run = s and s.run
    if not run then return end
    local test = tests[run.id]
    if not (test and test.on_event) then return end
    if not call(run, "on_event " .. name, test.on_event, run, tb, name, event) then
      tb.finish(run, "abgebrochen (Skriptfehler)")
    end
  end
end

runner.events =
{
  [defines.events.on_tick] = on_tick,
  [defines.events.on_spider_command_completed] = forward("spider_command_completed"),
  [defines.events.on_entity_died] = forward("entity_died"),
  [defines.events.on_player_driving_changed_state] = forward("driving_changed"),
  [defines.events.on_script_path_request_finished] = forward("script_path"),
  ["arrakis-test-key"] = forward("test_key")
}

runner.on_init = function()
  state()
end

runner.on_configuration_changed = function()
  state()
end

runner.add_commands = function()
  commands.add_command("arrakis-test", "Prüfstand (nur Admins): /arrakis-test [Tn [Argument] | alle | stop | zurück]", on_command)
end

runner.tb = tb

return runner
