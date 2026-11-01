-- T9 Flieger: Schatten der Last: Prüfstand-Test (aus t_flyer.lua aufgeteilt, Verhalten unverändert).
-- Gemeinsame Helfer der Familie: scripts/testbench/gemeinsam_flyer.lua.

local common = require("scripts.testbench.gemeinsam_flyer")
local FLYER_4 = common.FLYER_4
local guarded = common.guarded
local read = common.read
local pos_text = common.pos_text
local offset = common.offset
local bring_player = common.bring_player
local create_flyer = common.create_flyer
local add_fuel = common.add_fuel

local HOLD_NAME = "arrakis-test-hold"

-- T9 Schatten der Last ------------------------------------------------------------------------

local T9_CARRIED = "arrakis-test-carried"
local T9_SHADOW = "arrakis-test-carried-shadow"
local T9_CARRIED_OFFSET = {0, 0.5}
local T9_SHADOW_OFFSET = {1, 1} -- leicht nach rechts unten versetzt
local T9_SCALE = 1.5
local T9_CIRCLE_RADIUS = 8
local T9_CIRCLE_STEP = 45 -- Grad je neuem Ziel
local T9_CIRCLE_TICKS = 3 * 60
local T9_CHECK_DELAY = 60
local T9_HOLD_SLOT = {x = -25, y = -25} -- abseits vom Stellplatz {5, 5} aus T3
local T9_END_TICKS = 57 * 60 -- vor dem Zeitlimit (60 s) selbst beenden

local function t9_draw(run, tb, what, kind, params)
  local ok, object = guarded(run, tb, what, function()
    if kind == "text" then return rendering.draw_text(params) end
    return rendering.draw_sprite(params)
  end)
  if ok then return object end
  return nil
end

-- Bild der Last (unter dem Flieger) und Schatten nach Art: "sprite" (draw_as_shadow), "tint" (Ersatz) oder nil.
local function t9_decorate(run, tb, flyer, label, shadow_kind)
  local objects = {}
  local surface = flyer.surface
  local function keep(object)
    if object then table.insert(objects, object) end
  end
  if shadow_kind == "sprite" then
    keep(t9_draw(run, tb, label .. ": Schatten-Sprite zeichnen", "sprite", {
      sprite = T9_SHADOW, target = {entity = flyer, offset = T9_SHADOW_OFFSET}, surface = surface,
      x_scale = T9_SCALE, y_scale = T9_SCALE, render_layer = "floor"}))
  elseif shadow_kind == "tint" then
    keep(t9_draw(run, tb, label .. ": Ersatzschatten zeichnen", "sprite", {
      sprite = T9_CARRIED, target = {entity = flyer, offset = T9_SHADOW_OFFSET}, surface = surface,
      x_scale = T9_SCALE, y_scale = T9_SCALE, render_layer = "floor", tint = {r = 0, g = 0, b = 0, a = 0.5}}))
  end
  keep(t9_draw(run, tb, label .. ": Bild der Last zeichnen", "sprite", {
    sprite = T9_CARRIED, target = {entity = flyer, offset = T9_CARRIED_OFFSET}, surface = surface,
    x_scale = T9_SCALE, y_scale = T9_SCALE, render_layer = "smoke"}))
  keep(t9_draw(run, tb, label .. ": Beschriftung", "text", {
    text = label, target = {entity = flyer, offset = {0, 2.5}}, surface = surface,
    color = {r = 1, g = 1, b = 1}, scale = 1.5, alignment = "center"}))
  return objects
end

local function t9_circle_point(circle, angle)
  local rad = math.rad(angle)
  return {x = circle.center.x + circle.radius * math.cos(rad), y = circle.center.y + circle.radius * math.sin(rad)}
end

local function t9_valid_count(objects)
  local valid = 0
  for _, object in pairs(objects or {}) do
    local ok, is_valid = pcall(function() return object.valid end)
    if ok and is_valid then valid = valid + 1 end
  end
  return valid
end

local function t9_start(run, tb)
  local data = run.data
  local player = tb.player(run)
  if not player then
    tb.log(run, "FEHLER", "Kein Spieler für den interaktiven Test")
    tb.finish(run, "abgebrochen (kein Spieler)")
    return
  end
  local origin = tb.area(run.id)
  tb.prepare(origin, 40)
  local surface = tb.surface()
  bring_player(run, tb, player, origin)
  local force = player.force

  for _, sprite in ipairs({T9_CARRIED, T9_SHADOW}) do
    local ok, valid = pcall(function() return helpers.is_valid_sprite_path(sprite) end)
    if not (ok and valid) then
      tb.log(run, "FEHLER", "Sprite " .. sprite .. " ist kein gültiger SpritePath (" .. tostring(valid) .. ")")
    end
  end

  -- A: Schatten-Sprite mit draw_as_shadow; B: Ersatzschatten; C: Kreisflug; D: Teleport-Test.
  data.flyers = {}
  local layout =
  {
    {key = "A", position = offset(origin, -6, -5), label = "A: Schatten-Sprite (draw_as_shadow)", shadow = "sprite"},
    {key = "B", position = offset(origin, 6, -5), label = "B: Ersatzschatten (schwarz, halbtransparent)", shadow = "tint"},
    {key = "C", position = offset(origin, T9_CIRCLE_RADIUS, 14), label = "C: Kreisflug mit Bild"},
    {key = "D", position = offset(origin, 0, -16), label = "D: Teleport-Test", shadow = "sprite"}
  }
  data.objects = {}
  for _, entry in ipairs(layout) do
    local flyer = create_flyer(run, tb, surface, FLYER_4, entry.position, force)
    if flyer then
      add_fuel(run, tb, flyer, 3)
      data.flyers[entry.key] = flyer
      data.objects[entry.key] = t9_decorate(run, tb, flyer, entry.label, entry.shadow)
    end
  end

  -- C fliegt im Kreis: alle 3 s ein neues autopilot_destination, nie Wegpunkte anhängen.
  data.circle = {center = offset(origin, 0, 14), radius = T9_CIRCLE_RADIUS, angle = 0, next_tick = game.tick, targets = 0}
  data.check = {state = "wait", tick = game.tick + T9_CHECK_DELAY}

  tb.log(run, "INFO", "A, B und C stehen neben dir, D verschwindet nach 1 s auf die Ablage. Die Flieger bleiben nach Testende stehen.")
  tb.log(run, "FRAGE", "Welcher Schatten sieht richtig aus: A (Schatten-Sprite mit draw_as_shadow) oder B (schwarz getöntes, " ..
    "halbtransparentes Bild)? Liegt das Panzerbild unter dem Rumpf, und folgt es bei C dem Flug ohne Ruckeln? " ..
    "Bitte Screenshot von A, B und C und Antwort melden.")
end

-- Automatische Prüfung: D samt Render-Objekten per teleport auf die Ablage-Oberfläche.
local function t9_check(run, tb)
  local data = run.data
  local check = data.check
  local objects = data.objects.D or {}
  if check.state == "wait" then
    local flyer = data.flyers.D
    if not (flyer and flyer.valid) then
      tb.log(run, "FEHLER", "Teleport-Test: Flieger D fehlt")
      check.state = "done"
      return
    end
    check.before = t9_valid_count(objects)
    check.total = #objects
    -- Ablage-Oberfläche wie in T3 (tb.hold_surface: Laborkacheln, 5×5 Chunks, für alle Forces versteckt).
    local ok_hold, hold = guarded(run, tb, "Ablage-Oberfläche " .. HOLD_NAME .. " anlegen", function()
      return tb.hold_surface()
    end)
    if not (ok_hold and hold) then
      check.state = "done"
      return
    end
    -- Reste eines früheren Laufs vom Stellplatz räumen
    pcall(function()
      for _, old in pairs(hold.find_entities_filtered{position = T9_HOLD_SLOT, radius = 6, name = FLYER_4}) do
        old.destroy()
      end
    end)
    local ok, result = guarded(run, tb, "Teleport von D auf die Ablage", function()
      return flyer.teleport(T9_HOLD_SLOT, hold)
    end)
    check.now = t9_valid_count(objects)
    local where = read(function() return flyer.valid and (flyer.surface.name .. " " .. pos_text(tb, flyer.position)) or "ungültig" end)
    tb.log(run, "MESSUNG", string.format("Teleport-Test: teleport() = %s, D danach auf %s; Render-Objekte gültig vorher %d von %d, direkt danach %d",
      ok and tostring(result) or "Fehler", tostring(where), check.before, check.total, check.now))
    if not (ok and result) then
      tb.log(run, "FEHLER", "Teleport auf die Ablage fehlgeschlagen, Render-Prüfung nicht möglich")
      check.state = "done"
      return
    end
    check.state = "teleported"
    check.tick = game.tick + 1
  elseif check.state == "teleported" or check.state == "late" then
    -- Einen Tick nach dem Teleport prüfen; sind noch Objekte gültig, nach 1 s ein zweites Mal.
    local after = t9_valid_count(objects)
    check.after = after
    if check.total == 0 then
      tb.log(run, "FEHLER", "Teleport-Test: D hatte keine Render-Objekte")
      check.state = "done"
    elseif after == 0 then
      tb.log(run, "OK", string.format("Render-Objekte am Flieger verschwinden beim Oberflächenwechsel (render_object.valid = false bei %d von %d%s)",
        check.total, check.total, check.state == "late" and ", erst nach 1 s" or ""))
      check.state = "done"
    elseif check.state == "teleported" then
      tb.log(run, "MESSUNG", string.format("Einen Tick nach dem Teleport noch %d von %d Render-Objekten gültig, prüfe nach 1 s erneut",
        after, check.total))
      check.state = "late"
      check.tick = game.tick + 60
    else
      local where = "?"
      for _, object in pairs(objects) do
        local ok, name = pcall(function() return object.valid and object.surface.name end)
        if ok and name then
          where = name
          break
        end
      end
      tb.log(run, "FEHLER", string.format("Nach dem Oberflächenwechsel sind nach 1 s noch %d von %d Render-Objekten gültig (Oberfläche %s)",
        after, check.total, where))
      check.state = "done"
    end
  end
end

local function t9_tick(run, tb)
  local data = run.data
  if not data.circle then return end
  local now = game.tick

  local circle = data.circle
  local flyer = data.flyers.C
  if now >= circle.next_tick and flyer and flyer.valid then
    circle.next_tick = now + T9_CIRCLE_TICKS
    circle.angle = (circle.angle + T9_CIRCLE_STEP) % 360
    local ok = guarded(run, tb, "C: autopilot_destination setzen", function()
      flyer.autopilot_destination = t9_circle_point(circle, circle.angle)
    end)
    if ok then circle.targets = circle.targets + 1 end
  end

  if data.check.state ~= "done" and now >= data.check.tick then
    t9_check(run, tb)
  end

  if now - run.started >= T9_END_TICKS then
    if flyer and flyer.valid then
      local queue = read(function() return #flyer.autopilot_destinations end)
      tb.log(run, "MESSUNG", string.format("C: %d Ziele gesetzt, Warteschlange jetzt %s (erwartet ≤ 1), Tempo %s Kacheln/s",
        circle.targets, tostring(queue), tb.num(tb.speed_tps(flyer))))
    end
    local check = data.check
    local result
    if check.after == 0 and (check.total or 0) > 0 then
      result = "Render-Objekte verschwinden: OK"
    elseif check.after then
      result = "Render-Objekte bleiben: FEHLER"
    else
      result = "Render-Prüfung nicht gelaufen"
    end
    tb.finish(run, result .. "; Schatten: Antwort von Max")
  end
end

-- C hält an; D (auf der versteckten Ablage) wird entfernt. A, B, C bleiben samt Bildern stehen.
local function t9_cleanup(run, tb)
  local flyers = run.data.flyers or {}
  if flyers.C and flyers.C.valid then
    pcall(function() flyers.C.autopilot_destination = nil end)
  end
  if flyers.D and flyers.D.valid then
    pcall(function() flyers.D.destroy() end)
  end
end

return
{
  T9 =
  {
    title = "Flieger: Schatten der Last",
    timeout = 60 * 60,
    interactive = true,
    confirm = nil,
    start = t9_start,
    tick = t9_tick,
    cleanup = t9_cleanup
  }
}
