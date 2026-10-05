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

-- Phase 2: Spice-Kette
local spice_tint = {r = 1, g = 0.45, b = 0.15}

local melange_productivity_icons = util.technology_icon_constant_recipe_productivity("__base__/graphics/technology/sulfur-processing.png")
melange_productivity_icons[1].tint = spice_tint

data:extend({
  {
    type = "technology",
    name = "arrakis-spice-processing",
    icons = {{icon = "__base__/graphics/technology/sulfur-processing.png", icon_size = 256, tint = spice_tint}},
    effects =
    {
      {type = "unlock-recipe", recipe = "spice-refinery"},
      {type = "unlock-recipe", recipe = "melange"},
      {type = "unlock-recipe", recipe = "arrakis-sandstone-brick"}
    },
    prerequisites = {"planet-discovery-arrakis"},
    research_trigger =
    {
      type = "mine-entity",
      entity = "spice-sand"
    }
  },
  {
    type = "technology",
    name = "spice-science-pack",
    icons = {{icon = "__base__/graphics/technology/production-science-pack.png", icon_size = 256, tint = spice_tint}},
    essential = true,
    effects =
    {
      {type = "unlock-recipe", recipe = "spice-essence"},
      {type = "unlock-recipe", recipe = "spice-science-pack"}
    },
    prerequisites = {"arrakis-spice-processing"},
    research_trigger =
    {
      type = "craft-item",
      item = "melange",
      count = 20
    }
  },
  {
    type = "technology",
    name = "melange-productivity",
    icons = melange_productivity_icons,
    effects =
    {
      {type = "change-recipe-productivity", recipe = "melange", change = 0.1}
    },
    prerequisites = {"spice-science-pack"},
    unit =
    {
      count_formula = "1.5^L*500",
      ingredients =
      {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"space-science-pack", 1},
        {"spice-science-pack", 1}
      },
      time = 60
    },
    max_level = "infinite",
    upgrade = true
  }
})
