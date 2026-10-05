local planet_map_gen = require("prototypes.planet.planet-map-gen")
local asteroid_util = require("__space-age__.prototypes.planet.asteroid-spawn-definitions")
local vulcanus = data.raw.planet["vulcanus"]

-- Platzhalter-Grafik: eingefärbte Vulcanus-Icons, bis eigene Grafiken existieren.
local sand_tint = {r = 1, g = 0.82, b = 0.55}

data:extend({
  {
    type = "planet",
    name = "arrakis",
    icons = {{icon = "__space-age__/graphics/icons/vulcanus.png", tint = sand_tint}},
    starmap_icons = {{icon = "__space-age__/graphics/icons/starmap-planet-vulcanus.png", icon_size = 512, tint = sand_tint}},
    gravity_pull = 10,
    distance = 7,
    orientation = 0.02,
    magnitude = 1.2,
    order = "b[vulcanus]-a[arrakis]",
    subgroup = "planets",
    map_gen_settings = planet_map_gen.arrakis(),
    pollutant_type = nil,
    solar_power_in_space = 500,
    platform_procession_set = vulcanus.platform_procession_set,
    planet_procession_set = vulcanus.planet_procession_set,
    procession_graphic_catalogue = vulcanus.procession_graphic_catalogue,
    surface_properties =
    {
      ["day-night-cycle"] = 10 * minute,
      ["magnetic-field"] = 40,
      ["solar-power"] = 250,
      pressure = 800,
      gravity = 8,
      humidity = 2
    },
    asteroid_spawn_influence = 1,
    asteroid_spawn_definitions = asteroid_util.spawn_definitions(asteroid_util.nauvis_vulcanus, 0.9),
    persistent_ambient_sounds = vulcanus.persistent_ambient_sounds,
    surface_render_parameters = vulcanus.surface_render_parameters
  },
  {
    type = "space-connection",
    name = "vulcanus-arrakis",
    subgroup = "planet-connections",
    from = "vulcanus",
    to = "arrakis",
    order = "z[arrakis]-a",
    length = 15000,
    asteroid_spawn_definitions = asteroid_util.spawn_definitions(asteroid_util.nauvis_vulcanus)
  }
})
