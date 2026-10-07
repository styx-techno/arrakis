local spice_tint = {r = 1, g = 0.45, b = 0.15}
local water_tint = {r = 0.35, g = 0.6, b = 1}

-- Spice-Sand: festes Erz, nur im offenen Sand.
-- Eigene Ressourcenkategorie (prototypes/harvester.lua): nur Ernter und Hand, kein Bohrer.
local spice = table.deepcopy(data.raw.resource["iron-ore"])
spice.name = "spice-sand"
spice.category = "arrakis-spice-harvest"
spice.icon = nil
spice.icons = {{icon = "__base__/graphics/icons/iron-ore.png", tint = spice_tint}}
spice.minable = {mining_particle = "copper-ore-particle", mining_time = 1, result = "spice-sand"}
spice.stages.sheet.tint = spice_tint
spice.map_color = {0.95, 0.4, 0.1}
spice.mining_visualisation_tint = spice_tint
spice.factoriopedia_simulation = nil
spice.autoplace =
{
  order = "b",
  probability_expression = "arrakis_spice_probability",
  richness_expression = "arrakis_spice_richness"
}

-- Tiefenwasser: Fluid-Vorkommen wie Rohöl, wird mit der Pumpe (Pumpjack) gefördert.
local deep_water = table.deepcopy(data.raw.resource["crude-oil"])
deep_water.name = "arrakis-deep-water"
deep_water.icon = nil
deep_water.icons = {{icon = "__base__/graphics/icons/crude-oil-resource.png", tint = water_tint}}
deep_water.minable.results = {{type = "fluid", name = "water", amount_min = 10, amount_max = 10}}
deep_water.stages.sheet.tint = water_tint
deep_water.map_color = {0.2, 0.45, 0.9}
deep_water.factoriopedia_simulation = nil
deep_water.autoplace =
{
  order = "c",
  probability_expression = "arrakis_deep_water_probability",
  richness_expression = "arrakis_deep_water_richness"
}

data:extend({
  spice,
  deep_water,
  {
    type = "item",
    name = "spice-sand",
    icons = {{icon = "__base__/graphics/icons/iron-ore.png", tint = spice_tint}},
    subgroup = "raw-resource",
    order = "z[arrakis]-a[spice-sand]",
    stack_size = 50,
    weight = 10 * kg
  }
})
