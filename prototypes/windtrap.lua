-- Windfalle: gewinnt Wasser aus der Luft. Kein Strom nötig, aber geringe Rate.
-- Platzhalter-Grafik: Chemiefabrik.
local windtrap = table.deepcopy(data.raw["assembling-machine"]["chemical-plant"])
windtrap.name = "arrakis-windtrap"
windtrap.icon = nil
windtrap.icons = {{icon = "__base__/graphics/icons/chemical-plant.png", tint = {r = 1, g = 0.85, b = 0.6}}}
windtrap.minable = {mining_time = 0.2, result = "arrakis-windtrap"}
windtrap.crafting_categories = {"arrakis-windtrap"}
windtrap.fixed_recipe = "arrakis-windtrap-water"
windtrap.energy_source = {type = "void"}
windtrap.energy_usage = "1kW"
windtrap.module_slots = 0
windtrap.allowed_effects = {}
windtrap.fast_replaceable_group = nil
windtrap.next_upgrade = nil
windtrap.surface_conditions = {{property = "humidity", min = 1}}

-- Nur die beiden Ausgänge behalten.
local outputs = {}
for _, box in pairs(windtrap.fluid_boxes) do
  if box.production_type == "output" then table.insert(outputs, box) end
end
windtrap.fluid_boxes = outputs

data:extend({
  windtrap,
  {
    type = "recipe-category",
    name = "arrakis-windtrap"
  },
  {
    type = "item",
    name = "arrakis-windtrap",
    icons = windtrap.icons,
    subgroup = "production-machine",
    order = "e[chemical-plant]-z[arrakis-windtrap]",
    place_result = "arrakis-windtrap",
    stack_size = 10
  },
  {
    type = "recipe",
    name = "arrakis-windtrap",
    enabled = false,
    energy_required = 5,
    ingredients =
    {
      {type = "item", name = "steel-plate", amount = 10},
      {type = "item", name = "iron-gear-wheel", amount = 10},
      {type = "item", name = "pipe", amount = 10},
      {type = "item", name = "electronic-circuit", amount = 5}
    },
    results = {{type = "item", name = "arrakis-windtrap", amount = 1}}
  },
  {
    type = "recipe",
    name = "arrakis-windtrap-water",
    icon = "__base__/graphics/icons/fluid/water.png",
    category = "arrakis-windtrap",
    subgroup = "fluid-recipes",
    order = "z[arrakis]-a[windtrap-water]",
    enabled = false,
    hide_from_player_crafting = true,
    allow_productivity = false,
    energy_required = 1,
    ingredients = {},
    results = {{type = "fluid", name = "water", amount = 10}}
  }
})
