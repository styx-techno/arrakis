-- Kartengenerierung für Arrakis.
-- arrakis_rock > 0 bedeutet Fels (sichere Bauinsel), < 0 offener Sand (Wurmgebiet, Spice).
-- Der Startpunkt liegt immer auf einer Felsinsel mit allen Grunderzen und einem Tiefenbrunnen.

local function ore(name, control, seed, base, angle, start_distance, start_radius, spacing)
  return
  {
    {
      type = "noise-expression",
      name = "arrakis_" .. name .. "_richness",
      expression = base .. " * max(starting, arrakis_spot(" .. seed .. ", " .. start_radius .. " * size ^ 0.5, " .. spacing .. " / frequency ^ 0.5, arrakis_rock_favorability)) * richness / size",
      local_expressions =
      {
        richness = "var('control:" .. control .. ":richness')",
        frequency = "var('control:" .. control .. ":frequency')",
        size = "var('control:" .. control .. ":size')",
        starting = "starting_spot_at_angle{angle = arrakis_starting_angle + " .. angle .. ", distance = " .. start_distance .. ", radius = " .. start_radius .. " * size ^ 0.5, x_distortion = arrakis_wobble_x * " .. start_radius .. " * 0.7, y_distortion = arrakis_wobble_y * " .. start_radius .. " * 0.7}"
      }
    },
    {
      type = "noise-expression",
      name = "arrakis_" .. name .. "_probability",
      expression = "(var('control:" .. control .. ":size') > 0) * (arrakis_" .. name .. "_richness > 1) * (arrakis_rock > 0)"
    }
  }
end

data:extend({
  {
    type = "noise-expression",
    name = "arrakis_starting_angle",
    expression = "map_seed_normalized * 360"
  },
  {
    -- Verzerrung, damit Startfelder nicht kreisrund sind.
    type = "noise-expression",
    name = "arrakis_wobble_x",
    expression = "multioctave_noise{x = x, y = y, persistence = 0.5, seed0 = map_seed, seed1 = 7601, octaves = 3, input_scale = 1/12}"
  },
  {
    type = "noise-expression",
    name = "arrakis_wobble_y",
    expression = "multioctave_noise{x = x, y = y, persistence = 0.5, seed0 = map_seed, seed1 = 7602, octaves = 3, input_scale = 1/12}"
  },
  {
    type = "noise-expression",
    name = "arrakis_rock_noise",
    expression = "multioctave_noise{x = x, y = y, persistence = 0.55, seed0 = map_seed, seed1 = 7201, octaves = 5, input_scale = 1/220} - 0.35"
  },
  {
    -- Startinsel: Radius etwa 90 Felder um den Startpunkt.
    type = "noise-expression",
    name = "arrakis_rock",
    expression = "max(arrakis_rock_noise, 0.4 - distance / 150)"
  },
  {
    type = "noise-expression",
    name = "arrakis_rock_favorability",
    expression = "clamp(arrakis_rock * 6, 0, 1)"
  },
  {
    type = "noise-expression",
    name = "arrakis_sand_favorability",
    expression = "clamp(-arrakis_rock * 6, 0, 1)"
  },
  {
    type = "noise-expression",
    name = "arrakis_moisture",
    expression = "0.05"
  },
  {
    type = "noise-expression",
    name = "arrakis_aux",
    expression = "0.3 + 0.25 * multioctave_noise{x = x, y = y, persistence = 0.6, seed0 = map_seed, seed1 = 7101, octaves = 4, input_scale = 1/120}"
  },
  {
    type = "noise-function",
    name = "arrakis_spot",
    parameters = {"seed1", "radius", "spacing", "favorability"},
    expression = "spot_noise{x = x + arrakis_wobble_x * 0.5 * radius,\z
                             y = y + arrakis_wobble_y * 0.5 * radius,\z
                             seed0 = map_seed,\z
                             seed1 = seed1,\z
                             skip_span = 1,\z
                             skip_offset = 1,\z
                             region_size = spacing * 5,\z
                             density_expression = favorability,\z
                             spot_favorability_expression = favorability,\z
                             candidate_spot_count = 22,\z
                             suggested_minimum_candidate_point_spacing = spacing,\z
                             spot_quantity_expression = radius * radius,\z
                             spot_radius_expression = radius,\z
                             hard_region_target_quantity = 0,\z
                             basement_value = -1,\z
                             maximum_spot_basement_radius = radius * 2}"
  },

  -- Spice: nur im offenen Sand. Ein garantiertes Feld außerhalb der Startinsel.
  {
    type = "noise-expression",
    name = "arrakis_spice_richness",
    expression = "6000 * max(starting, arrakis_spot(7301, 14 * size ^ 0.5, 250 / frequency ^ 0.5, arrakis_sand_favorability)) * richness",
    local_expressions =
    {
      richness = "var('control:arrakis_spice:richness')",
      frequency = "var('control:arrakis_spice:frequency')",
      size = "var('control:arrakis_spice:size')",
      starting = "starting_spot_at_angle{angle = arrakis_starting_angle + 135, distance = 150, radius = 14 * size ^ 0.5, x_distortion = arrakis_wobble_x * 10, y_distortion = arrakis_wobble_y * 10}"
    }
  },
  {
    type = "noise-expression",
    name = "arrakis_spice_probability",
    expression = "(var('control:arrakis_spice:size') > 0) * (arrakis_spice_richness > 1) * (arrakis_rock < 0)"
  },

  -- Tiefenwasser: seltene Brunnen unter Fels, einer davon auf der Startinsel.
  {
    type = "noise-expression",
    name = "arrakis_deep_water_spot",
    expression = "max(starting, arrakis_spot(7401, 6 * size ^ 0.5, 300 / frequency ^ 0.5, arrakis_rock_favorability))",
    local_expressions =
    {
      frequency = "var('control:arrakis_deep_water:frequency')",
      size = "var('control:arrakis_deep_water:size')",
      starting = "starting_spot_at_angle{angle = arrakis_starting_angle + 225, distance = 45, radius = 6 * size ^ 0.5, x_distortion = 0, y_distortion = 0}"
    }
  },
  {
    type = "noise-expression",
    name = "arrakis_deep_water_probability",
    expression = "(var('control:arrakis_deep_water:size') > 0) * (arrakis_deep_water_spot > 0) * (arrakis_rock > 0) * 0.04"
  },
  {
    type = "noise-expression",
    name = "arrakis_deep_water_richness",
    expression = "(150000 + 300000 * arrakis_deep_water_spot) * var('control:arrakis_deep_water:richness')"
  }
})

-- Grunderze, nur auf Fels. Startfelder im Kreis um den Startpunkt.
data:extend(ore("iron_ore",   "iron-ore",   7501, 150000, 0,   35, 10, 220))
data:extend(ore("copper_ore", "copper-ore", 7502, 120000, 90,  35, 9,  240))
data:extend(ore("stone",      "stone",      7503, 60000,  180, 35, 7,  260))
data:extend(ore("coal",       "coal",       7504, 80000,  270, 35, 8,  260))
