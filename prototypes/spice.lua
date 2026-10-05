-- Spice-Kette (Phase 2):
--   Spice-Sand + Wasser  -> Melange + Sand          (Spice-Raffinerie)
--   Melange + Wasser     -> Spice-Essenz (verdirbt)  (Spice-Raffinerie)
--   Essenz + Melange + Stahl -> Spice-Wissenschaft   (Spice-Raffinerie, nur auf Arrakis)
--   Sand -> Steinziegel                              (Ofen)
-- Grafiken sind eingefärbte Vanilla-Platzhalter.

local item_sounds = require("__base__.prototypes.item_sounds")

local spice_tint = {r = 1, g = 0.45, b = 0.15}
local sand_tint = {r = 1, g = 0.85, b = 0.55}

local function tinted(icon, tint)
  return {{icon = icon, tint = tint}}
end

-- Spice-Raffinerie: Kopie der Ölraffinerie mit 50 % Grundproduktivität (wie Gießerei/Biokammer).
local refinery = table.deepcopy(data.raw["assembling-machine"]["oil-refinery"])
refinery.name = "spice-refinery"
refinery.icon = nil
refinery.icons = tinted("__base__/graphics/icons/oil-refinery.png", spice_tint)
refinery.minable = {mining_time = 0.2, result = "spice-refinery"}
refinery.crafting_categories = {"spice-refining"}
refinery.effect_receiver = {base_effect = {productivity = 0.5}}
refinery.fast_replaceable_group = nil
refinery.next_upgrade = nil
refinery.factoriopedia_simulation = nil

data:extend({
  refinery,
  {
    type = "recipe-category",
    name = "spice-refining"
  },
  {
    type = "item-subgroup",
    name = "arrakis-spice",
    group = "intermediate-products",
    order = "z[arrakis]-a"
  },

  -- Items
  {
    type = "item",
    name = "spice-refinery",
    icons = refinery.icons,
    subgroup = "production-machine",
    order = "e[chemical-plant]-z[spice-refinery]",
    place_result = "spice-refinery",
    stack_size = 10,
    default_import_location = "arrakis"
  },
  {
    type = "item",
    name = "melange",
    icons = tinted("__base__/graphics/icons/sulfur.png", spice_tint),
    subgroup = "arrakis-spice",
    order = "b[melange]",
    stack_size = 100,
    weight = 2 * kg,
    default_import_location = "arrakis",
    inventory_move_sound = item_sounds.sulfur_inventory_move,
    pick_sound = item_sounds.resource_inventory_pickup,
    drop_sound = item_sounds.sulfur_inventory_move
  },
  {
    type = "item",
    name = "spice-essence",
    icons = tinted("__base__/graphics/icons/sulfur.png", {r = 1, g = 0.25, b = 0.05}),
    subgroup = "arrakis-spice",
    order = "c[spice-essence]",
    stack_size = 50,
    weight = 5 * kg,
    default_import_location = "arrakis",
    spoil_ticks = 15 * minute,
    spoil_result = "spoilage"
  },
  {
    type = "item",
    name = "arrakis-sand",
    icons = tinted("__base__/graphics/icons/stone.png", sand_tint),
    subgroup = "arrakis-spice",
    order = "a[sand]",
    stack_size = 100,
    weight = 1 * kg,
    default_import_location = "arrakis"
  },
  {
    type = "tool",
    name = "spice-science-pack",
    localised_description = {"item-description.science-pack"},
    icons = tinted("__base__/graphics/icons/production-science-pack.png", spice_tint),
    subgroup = "science-pack",
    color_hint = {text = "S"},
    order = "h[metallurgic]-z[spice]",
    inventory_move_sound = item_sounds.science_inventory_move,
    pick_sound = item_sounds.science_inventory_pickup,
    drop_sound = item_sounds.science_inventory_move,
    stack_size = 200,
    default_import_location = "arrakis",
    weight = 1 * kg,
    durability = 1,
    durability_description_key = "description.science-pack-remaining-amount-key",
    factoriopedia_durability_description_key = "description.factoriopedia-science-pack-remaining-amount-key",
    durability_description_value = "description.science-pack-remaining-amount-value"
  },

  -- Rezepte
  {
    type = "recipe",
    name = "spice-refinery",
    enabled = false,
    energy_required = 10,
    ingredients =
    {
      {type = "item", name = "steel-plate", amount = 30},
      {type = "item", name = "iron-gear-wheel", amount = 20},
      {type = "item", name = "advanced-circuit", amount = 10},
      {type = "item", name = "pipe", amount = 20},
      {type = "item", name = "spice-sand", amount = 50}
    },
    results = {{type = "item", name = "spice-refinery", amount = 1}}
  },
  {
    type = "recipe",
    name = "melange",
    category = "spice-refining",
    subgroup = "arrakis-spice",
    order = "b[melange]",
    enabled = false,
    energy_required = 5,
    ingredients =
    {
      {type = "item", name = "spice-sand", amount = 10},
      {type = "fluid", name = "water", amount = 100}
    },
    results =
    {
      {type = "item", name = "melange", amount = 2},
      {type = "item", name = "arrakis-sand", amount = 6}
    },
    main_product = "melange",
    allow_productivity = true
  },
  {
    type = "recipe",
    name = "spice-essence",
    category = "spice-refining",
    subgroup = "arrakis-spice",
    order = "c[spice-essence]",
    enabled = false,
    energy_required = 10,
    ingredients =
    {
      {type = "item", name = "melange", amount = 5},
      {type = "fluid", name = "water", amount = 50}
    },
    results = {{type = "item", name = "spice-essence", amount = 1}},
    allow_productivity = true
  },
  {
    type = "recipe",
    name = "spice-science-pack",
    category = "spice-refining",
    enabled = false,
    energy_required = 10,
    -- Nur auf Arrakis herstellbar: trockene Luft, aber nicht im Vakuum.
    surface_conditions =
    {
      {property = "humidity", min = 1, max = 10}
    },
    ingredients =
    {
      {type = "item", name = "spice-essence", amount = 1},
      {type = "item", name = "melange", amount = 2},
      {type = "item", name = "steel-plate", amount = 2}
    },
    results = {{type = "item", name = "spice-science-pack", amount = 1}},
    allow_productivity = true
  },
  {
    type = "recipe",
    name = "arrakis-sandstone-brick",
    icons =
    {
      {icon = "__base__/graphics/icons/stone-brick.png"},
      {icon = "__base__/graphics/icons/stone.png", tint = sand_tint, scale = 0.25, shift = {-8, -8}}
    },
    category = "smelting",
    subgroup = "arrakis-spice",
    order = "d[sandstone-brick]",
    enabled = false,
    energy_required = 3.2,
    ingredients = {{type = "item", name = "arrakis-sand", amount = 4}},
    results = {{type = "item", name = "stone-brick", amount = 1}},
    allow_productivity = true
  }
})
