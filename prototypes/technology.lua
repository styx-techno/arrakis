data:extend({
  {
    type = "technology",
    name = "planet-discovery-arrakis",
    icons = util.technology_icon_constant_planet("__space-age__/graphics/technology/vulcanus.png"),
    essential = true,
    effects =
    {
      {
        type = "unlock-space-location",
        space_location = "arrakis",
        use_icon_overlay_constant = true
      }
    },
    prerequisites = {"metallurgic-science-pack"},
    unit =
    {
      count = 1000,
      ingredients =
      {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"space-science-pack", 1},
        {"metallurgic-science-pack", 1}
      },
      time = 60
    }
  }
})

-- Platzhalter: Technologie-Icon einfärben, bis ein eigenes existiert.
data.raw.technology["planet-discovery-arrakis"].icons[1].tint = {r = 1, g = 0.82, b = 0.55}

data:extend({
  {
    type = "technology",
    name = "arrakis-windtrap",
    icons = {{icon = "__base__/graphics/technology/oil-processing.png", icon_size = 256, tint = {r = 1, g = 0.85, b = 0.6}}},
    effects =
    {
      {type = "unlock-recipe", recipe = "arrakis-windtrap"},
      {type = "unlock-recipe", recipe = "arrakis-windtrap-water"}
    },
    prerequisites = {"planet-discovery-arrakis"},
    unit =
    {
      count = 200,
      ingredients =
      {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"space-science-pack", 1}
      },
      time = 30
    }
  }
})
