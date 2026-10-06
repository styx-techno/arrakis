-- Prüfstand T1, T9, T12: Flieger als Spider-Vehicle mit unsichtbaren, kollisionsfreien Beinen
-- (Design 4.2). Kopien des Spidertrons mit 1, 2 oder 4 Beinen, dazu ein Last-Sticker.

local sand_tint = {r = 1, g = 0.85, b = 0.55}

-- Tönt alle normalen Bildebenen; Schatten, Farbmasken und Leuchten bleiben.
local function tint_layers(animation, tint)
  if type(animation) ~= "table" then return end
  if animation.layers then
    for _, layer in pairs(animation.layers) do tint_layers(layer, tint) end
    return
  end
  if animation.draw_as_shadow or animation.apply_runtime_tint or animation.draw_as_glow or animation.draw_as_light then return end
  animation.tint = tint
end

-- Bein: Kopie eines Spidertron-Beins ohne Grafik (graphics_set ist optional), ohne Geräusche,
-- ohne Kollision. speed_factor skaliert die Bewegungswerte (Vanilla: 0,06 Start, 0,03 Beschleunigung).
local function make_leg(name, speed_factor)
  local leg = table.deepcopy(data.raw["spider-leg"]["spidertron-leg-1"])
  leg.name = name
  leg.localised_name = nil
  leg.hidden = true
  leg.graphics_set = nil
  leg.working_sound = nil
  leg.walking_sound_volume_modifier = 0
  leg.upper_leg_dying_trigger_effects = nil
  leg.lower_leg_dying_trigger_effects = nil
  leg.collision_mask = {layers = {}}
  leg.initial_movement_speed = leg.initial_movement_speed * speed_factor
  leg.movement_acceleration = leg.movement_acceleration * speed_factor
  return leg
end

local spidertron = data.raw["spider-vehicle"]["spidertron"]
local vanilla_legs = spidertron.spider_engine.legs

-- Beinposition aus Vanilla-Bein Nr. index übernehmen (ohne Bodenstaub-Trigger).
local function vanilla_leg(leg_name, index, walking_group)
  local source = vanilla_legs[index]
  return
  {
    leg = leg_name,
    mount_position = table.deepcopy(source.mount_position),
    ground_position = table.deepcopy(source.ground_position),
    walking_group = walking_group
  }
end

-- Beinanordnungen. Laufgruppen beginnen bei 1 und sind lückenlos.
-- Die Positionen drehen nicht mit der Flugrichtung: Sie drehen nur in den Richtungen von
-- base_animation, und die Spidertron-Kopie hat dort nur eine (direction_count = 1). Die Angaben
-- gelten also fest zur Karte (wie bei Blick nach Norden).
-- 1 Bein: Bodenpunkt 1 Kachel südlich der Rumpfmitte (Abstand ungleich 0, damit keine Nulllänge
--   entsteht). Beim Flug nach Osten (T1) steht das Bein also seitlich.
-- 2 Beine: Vanilla 2 (Bodenpunkt östlich) und 7 (westlich), abwechselnd. Beim Flug nach Osten (T1)
--   liegen sie vorn und hinten, bei Nord-Süd-Flug lägen sie seitlich.
-- 4 Beine: Trab wie beim Spidertron (1 und 8 zusammen, 5 und 4 zusammen).
local layouts =
{
  [1] = function(leg_name)
    return {{leg = leg_name, mount_position = {0, 0}, ground_position = {0, 1}, walking_group = 1}}
  end,
  [2] = function(leg_name)
    return {vanilla_leg(leg_name, 2, 1), vanilla_leg(leg_name, 7, 2)}
  end,
  [4] = function(leg_name)
    return {vanilla_leg(leg_name, 1, 1), vanilla_leg(leg_name, 8, 1), vanilla_leg(leg_name, 5, 2), vanilla_leg(leg_name, 4, 2)}
  end
}

local function make_flyer(name, leg_name, leg_count)
  local flyer = table.deepcopy(spidertron)
  flyer.name = name
  flyer.hidden = true
  flyer.factoriopedia_simulation = nil
  flyer.minable = {mining_time = 1}
  flyer.guns = nil
  flyer.equipment_grid = nil
  flyer.trash_inventory_size = 0
  flyer.inventory_size = 10
  flyer.chunk_exploration_radius = 2
  flyer.allow_remote_driving = true
  -- Flughöhe ~3 (Spidertron 1,5). "tall" wird bewusst nicht gesetzt (2.1: sonst im Modus
  -- "Hohe Objekte ausblenden" nicht anwählbar).
  flyer.height = 3
  flyer.alert_icon_shift = {0, -3}
  flyer.drawing_box_vertical_extension = 4
  -- Die Engine verbraucht den Treibstoff selbst (Spidertron: void).
  flyer.energy_source =
  {
    type = "burner",
    fuel_categories = {"chemical"},
    effectivity = 1,
    fuel_inventory_size = 2
  }
  flyer.movement_energy_consumption = "800kW"
  -- Oberteil über allem am Boden. base_render_layer bleibt (higher-object-above, schon über
  -- Gebäuden), damit das Unterteil unter dem Oberteil gezeichnet wird.
  flyer.graphics_set.render_layer = "air-object"
  tint_layers(flyer.graphics_set.base_animation, sand_tint)
  tint_layers(flyer.graphics_set.animation, sand_tint)
  flyer.spider_engine = {legs = layouts[leg_count](leg_name)}
  return flyer
end

data:extend({
  make_leg("arrakis-test-flyer-leg", 1),
  make_leg("arrakis-test-flyer-leg-fast", 2),
  make_flyer("arrakis-test-flyer-1", "arrakis-test-flyer-leg", 1),
  make_flyer("arrakis-test-flyer-2", "arrakis-test-flyer-leg", 2),
  make_flyer("arrakis-test-flyer-4", "arrakis-test-flyer-leg", 4),
  make_flyer("arrakis-test-flyer-4-fast", "arrakis-test-flyer-leg-fast", 4),
  {
    -- Last-Sticker: bremst Fahrzeuge auf 70 %. Ob das bei Spider-Vehicles wirkt, misst T1.
    type = "sticker",
    name = "arrakis-test-load-sticker",
    hidden = true,
    flags = {"not-on-map"},
    duration_in_ticks = 10 * 60 * 60,
    vehicle_speed_modifier = 0.7
  },
  {
    -- Zweiter Last-Sticker mit dem anderen Bremsfeld (wie die Vanilla-Verlangsamungskapsel, die laut
    -- 2.0-Changelog auch Spidertrons bremst). T1 vergleicht beide auf eigenen Bahnen.
    type = "sticker",
    name = "arrakis-test-load-sticker-move",
    hidden = true,
    flags = {"not-on-map"},
    duration_in_ticks = 10 * 60 * 60,
    target_movement_modifier = 0.7
  }
})
