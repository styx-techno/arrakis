-- Simulationen der Tipps „Arrakis“ und „Wurmzeichen“ (0.16.2; Max im Spiel 01.11.2026: die Mod-Einträge sollen wie die
-- Vanilla-Einträge aussehen, mit Bild oben und kurzem Text). Muster: space-age/prototypes/tips-and-tricks-simulations.lua
-- (vulcanus_briefing, heating_mechanics: planet, set_tiles, script.on_nth_tick, storage).
--
-- Die Szenen laufen ohne den Laufzeitcode der Mod: Staubring, Countdown-Ring, Anheben und Eruption sind hier mit
-- rendering, create_trivial_smoke und create_entity nachgestellt. Jeder Aufruf steht in pcall, damit ein fehlendes
-- Objekt nur ein Bild leerer macht, nie die Simulation abbricht.

local simulations = {}

-- Gemeinsamer Anfang: Gelände (Sand mit Dünen-Streifen, Felsplateau links, Spice-Feld) und Hilfsfunktionen.
local COMMON =
[[
  local surface = game.surfaces[1]
  local function try(fn, ...) local ok, result = pcall(fn, ...) if ok then return result end end

  -- Fels links bis rock_edge(y), sonst Sand in drei Tönen als schräge Dünen-Streifen.
  local function paint(rock_x)
    local tiles = {}
    for x = -20, 19 do
      for y = -12, 12 do
        local edge = rock_x + math.floor(math.sin(y * 0.55) * 1.5 + math.cos(y * 0.23) * 1.2)
        local name
        if x < edge then
          name = "arrakis-rock"
        else
          local band = (x + y * 0.6 + math.sin(x * 0.4) * 2) % 7
          name = band < 3 and "sand-1" or (band < 5 and "sand-2" or "sand-3")
        end
        tiles[#tiles + 1] = {name = name, position = {x, y}}
      end
    end
    try(function() surface.set_tiles(tiles) end)
  end

  -- Spice-Feld: Kreis um (cx, cy) mit Radius r.
  local function spice(cx, cy, r)
    for x = cx - r, cx + r do
      for y = cy - r, cy + r do
        if (x - cx) ^ 2 + (y - cy) ^ 2 <= r * r then
          try(function() surface.create_entity{name = "spice-sand", position = {x + 0.5, y + 0.5}, amount = 3000} end)
        end
      end
    end
  end

  -- Staubring wie scripts/vibration.lua (DUST_RINGS): Puffs in festen Winkeln um p.
  local RINGS = {{gap = 1.5, puffs = 10}, {gap = 3.5, puffs = 14}}
  local function dust(p, radius)
    for i = 1, #RINGS do
      local ring = RINGS[i]
      local r = radius + ring.gap
      for k = 1, ring.puffs do
        local angle = (k + (i - 1) * 0.5) * 2 * math.pi / ring.puffs
        try(function()
          surface.create_trivial_smoke{name = "arrakis-sand-dust", position = {p.x + r * math.cos(angle), p.y + r * math.sin(angle)}}
        end)
      end
    end
  end

  local function fuel(entity, name, count)
    try(function() entity.get_fuel_inventory().insert{name = name, count = count} end)
  end
]]

-- Arrakis: Felsplateau mit Leitstelle und Windfalle, auf dem Sand ein Spice-Feld mit arbeitendem Ernter samt Staubring
-- und tiefem Brummen, darüber kreist ein Ornithopter.
simulations.arrakis_briefing =
{
  init_update_count = 120,
  planet = "arrakis",
  mute_wind_sounds = false,
  init = COMMON ..
  [[
    game.simulation.camera_position = {0, 0.5}
    game.simulation.camera_zoom = 0.9
    paint(-6)
    spice(6, 1, 4)
    try(function() surface.create_entity{name = "arrakis-depot", position = {-12, -2}, force = "player"} end)
    try(function() surface.create_entity{name = "arrakis-windtrap", position = {-12.5, 4.5}, force = "player"} end)
    storage.harvester = try(function()
      return surface.create_entity{name = "spice-harvester", position = {6, 1}, force = "player"}
    end)
    if storage.harvester then try(function() storage.harvester.orientation = 0.375 end) end
    storage.flyer = try(function() return surface.create_entity{name = "arrakis-ornithopter", position = {-4, -5}, force = "player"} end)
    if storage.flyer then fuel(storage.flyer, "rocket-fuel", 10) end
    storage.route = {{x = 2, y = -6}, {x = 11, y = -3}, {x = 12, y = 6}, {x = 2, y = 8}, {x = -4, y = 2}, {x = -4, y = -5}}
    storage.leg = 0
    storage.tick = 0

    script.on_nth_tick(1, function()
      storage.tick = storage.tick + 1
      local h = storage.harvester
      if h and h.valid and storage.tick % 20 == 0 then dust(h.position, 1.8) end
      if h and h.valid and storage.tick % 300 == 1 then
        try(function() surface.play_sound{path = "arrakis-rumble", position = h.position} end)
      end
      local f = storage.flyer
      if f and f.valid and storage.tick % 30 == 0 then
        local ok, empty = pcall(function() return #f.autopilot_destinations == 0 end)
        if ok and empty then
          storage.leg = storage.leg % #storage.route + 1
          try(function() f.add_autopilot_destination(storage.route[storage.leg]) end)
        end
      end
    end)
  ]]
}

-- Wurmzeichen: Ernter auf dem Spice-Feld, roter Ring mit Countdown, eine Staubspur kommt näher. Der Ornithopter fliegt
-- vom Fels herüber, hebt den Ernter an (Ring wird grün) und bringt ihn auf den Fels; bei 0 bricht die Sandfontäne leer
-- aus. Danach beginnt die Szene von vorn.
simulations.wormsign =
{
  init_update_count = 30,
  planet = "arrakis",
  mute_wind_sounds = false,
  init = COMMON ..
  [[
    game.simulation.camera_position = {0, 0.5}
    game.simulation.camera_zoom = 0.9
    paint(-7)
    spice(5, 1, 4)

    local SPOT = {x = 5, y = 1}
    local PARK = {x = -12, y = -1}
    local DROP = {x = -12, y = 4}
    local OFFSET = {0, 2}
    local SHADOW = {0.8, 2.8}
    local COUNT = 10
    local RED = {r = 0.9, g = 0.1, b = 0.05, a = 0.9}
    local GREEN = {r = 0.15, g = 0.85, b = 0.2, a = 0.9}
    local WORM_FROM = {x = 19, y = 9}

    storage.flyer = try(function() return surface.create_entity{name = "arrakis-ornithopter", position = PARK, force = "player"} end)
    if storage.flyer then fuel(storage.flyer, "rocket-fuel", 10) end
    storage.renders = {}

    local function clear(keys)
      for _, key in ipairs(keys) do
        local r = storage.renders[key]
        if r then try(function() r.destroy() end) end
        storage.renders[key] = nil
      end
    end

    local function draw(key, args)
      clear({key})
      args.surface = surface
      storage.renders[key] = try(function() return rendering.draw_sprite(args) end)
    end

    local function start()
      storage.t = 0
      storage.state = "warning"
      if storage.cargo_at then
        try(function() storage.cargo_at.destroy() end)
        storage.cargo_at = nil
      end
      if not (storage.harvester and storage.harvester.valid) then
        storage.harvester = try(function()
          return surface.create_entity{name = "spice-harvester", position = SPOT, force = "player"}
        end)
      end
      clear({"ring", "text", "sign", "image", "mask", "tracks", "shadow"})
      storage.renders.ring = try(function()
        return rendering.draw_circle{color = RED, radius = 4.5, width = 6, filled = false, target = SPOT, surface = surface}
      end)
      storage.renders.text = try(function()
        return rendering.draw_text{text = tostring(COUNT), color = RED, scale = 3, alignment = "center", vertical_alignment = "middle",
          target = {SPOT.x, SPOT.y - 5.5}, surface = surface}
      end)
      draw("sign", {sprite = "virtual-signal/arrakis-wormsign", target = {SPOT.x - 2.2, SPOT.y - 5.5}, x_scale = 1.2, y_scale = 1.2})
      try(function() surface.play_sound{path = "arrakis-wormsign", position = SPOT} end)
    end

    local function lift()
      local h = storage.harvester
      if h and h.valid then
        local color = h.color or h.force.color
        h.destroy()
        storage.harvester = nil
        local f = storage.flyer
        if f and f.valid then
          draw("shadow", {sprite = "arrakis-harvester-carried-shadow-0", target = {entity = f, offset = SHADOW}, render_layer = "floor"})
          draw("image", {sprite = "arrakis-harvester-carried-0", target = {entity = f, offset = OFFSET}, render_layer = "smoke"})
          draw("mask", {sprite = "arrakis-harvester-carried-mask-0", target = {entity = f, offset = OFFSET}, render_layer = "smoke", tint = color})
          draw("tracks", {sprite = "arrakis-harvester-carried-tracks-0", target = {entity = f, offset = OFFSET}, render_layer = "smoke"})
        end
      end
      local ring, text = storage.renders.ring, storage.renders.text
      if ring then try(function() ring.color = GREEN end) end
      if text then try(function() text.color = GREEN end) end
      storage.state = "carried"
    end

    local function fly(to)
      local f = storage.flyer
      if not (f and f.valid) then return end
      try(function()
        f.autopilot_destination = nil
        f.add_autopilot_destination(to)
      end)
    end

    local function near(to, d)
      local f = storage.flyer
      if not (f and f.valid) then return false end
      local p = f.position
      return (p.x - to.x) ^ 2 + (p.y - to.y) ^ 2 <= d * d
    end

    start()

    script.on_nth_tick(1, function()
      storage.t = storage.t + 1
      local t = storage.t
      local left = COUNT - math.floor(t / 60)
      local text = storage.renders.text
      if text and left >= 0 then try(function() text.text = tostring(left) end) end
      -- Staubspur des Wurms: von rechts unten zur Ernterstelle, bis 0.
      if storage.state ~= "done" and t % 6 == 0 then
        local k = math.min(1, t / (COUNT * 60))
        local p = {x = WORM_FROM.x + (SPOT.x - WORM_FROM.x) * k, y = WORM_FROM.y + (SPOT.y - WORM_FROM.y) * k + math.sin(t / 25) * 1.2}
        for k2 = 1, 3 do
          try(function()
            surface.create_trivial_smoke{name = "arrakis-sand-dust", position = {p.x + math.cos(t + k2 * 2.1) * 0.8, p.y + math.sin(t + k2 * 2.1) * 0.8}}
          end)
        end
      end
      if t % 300 == 1 and storage.state ~= "done" then
        try(function() surface.play_sound{path = "arrakis-rumble", position = SPOT} end)
      end
      -- Ornithopter: nach 1 s los, über dem Ernter anheben (Lastbild 2 Kacheln unter dem Flieger), zurück auf den Fels.
      local hover = {x = SPOT.x, y = SPOT.y - OFFSET[2]}
      if t == 60 then fly(hover) end
      if storage.state == "warning" and t >= 60 and (near(hover, 0.8) or left <= 3) then
        if not near(hover, 0.8) and storage.flyer and storage.flyer.valid then try(function() storage.flyer.teleport(hover) end) end
        lift()
        fly({x = DROP.x, y = DROP.y - OFFSET[2]})
      end
      if left == 0 and storage.state ~= "done" and storage.state ~= "warning" and t % 60 == 0 then
        try(function() surface.create_entity{name = "arrakis-worm-eruption", position = SPOT} end)
        clear({"ring", "text", "sign"})
        storage.state = "done"
      end
      -- Absetzen auf dem Fels, kurz stehen lassen, dann von vorn (der Ernter steht wieder auf dem Feld).
      if storage.state == "done" and storage.renders.image and near({x = DROP.x, y = DROP.y - OFFSET[2]}, 1.2) then
        clear({"image", "mask", "tracks", "shadow"})
        storage.cargo_at = try(function()
          return surface.create_entity{name = "spice-harvester", position = DROP, force = "player"}
        end)
        fly(PARK)
      end
      if t >= (COUNT + 6) * 60 then start() end
    end)
  ]]
}

return simulations
