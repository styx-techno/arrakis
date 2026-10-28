-- Phase 3e (docs/plan-3e.md 3): Ornithopter-Leitstelle, ein Lager 4×4 nur auf Fels. Ihr Inventar nimmt Flugtreibstoff
-- für die Carryalls und Brennstoff für die Ernter auf; die Carryalls parken auf ihr (scripts/fleet.lua). Beim Bauen
-- zeigt ein Kreis die Reichweite (Mod-Einstellung arrakis-depot-range). Grafik aus tools/grafik/leitstelle-modell.py.
local RANGE = settings.startup["arrakis-depot-range"].value

local gfx = "__arrakis__/graphics/entity/depot/"

local depot =
{
  type = "container",
  name = "arrakis-depot",
  icon = "__arrakis__/graphics/icons/depot.png",
  icon_size = 64,
  flags = {"placeable-player", "player-creation"},
  minable = {mining_time = 1, result = "arrakis-depot"},
  max_health = 1500,
  corpse = "big-remnants",
  dying_explosion = "medium-explosion",
  collision_box = {{-1.9, -1.9}, {1.9, 1.9}},
  selection_box = {{-2, -2}, {2, 2}},
  inventory_size = 48,
  -- Wie die Annahme (prototypes/harvester.lua): nur auf Fels.
  tile_buildability_rules =
  {
    {area = {{-1.9, -1.9}, {1.9, 1.9}}, required_tiles = {layers = {arrakis_rock = true}}}
  },
  picture =
  {
    layers =
    {
      {filename = gfx .. "depot-base.png", width = 448, height = 448, scale = 0.5},
      {filename = gfx .. "depot-shadow.png", width = 256, height = 256, scale = 1, draw_as_shadow = true}
    }
  },
  radius_visualisation_specification =
  {
    -- Dasselbe Bild wie der Versorgungsbereich des kleinen Strommasts (V2123 base/prototypes/entity/entities.lua:1745).
    sprite = {filename = "__base__/graphics/entity/small-electric-pole/electric-pole-radius-visualization.png",
      priority = "extra-high-no-scale", width = 12, height = 12},
    distance = RANGE
  },
  open_sound = {filename = "__base__/sound/metallic-chest-open.ogg", volume = 0.5},
  close_sound = {filename = "__base__/sound/metallic-chest-close.ogg", volume = 0.5}
}

data:extend({
  depot,
  {
    type = "item",
    name = "arrakis-depot",
    icon = depot.icon,
    icon_size = 64,
    subgroup = "transport",
    order = "b[personal-transport]-z[spice-ornithopter]-c[depot]",
    place_result = "arrakis-depot",
    stack_size = 10,
    default_import_location = "arrakis"
  },
  {
    -- Design 3.1: Spice-Essenz verdirbt, die Leitstelle wird also auf Arrakis gebaut.
    type = "recipe",
    name = "arrakis-depot",
    enabled = false,
    energy_required = 20,
    ingredients =
    {
      {type = "item", name = "steel-plate", amount = 50},
      {type = "item", name = "stone-brick", amount = 200},
      {type = "item", name = "advanced-circuit", amount = 20},
      {type = "item", name = "spice-essence", amount = 10}
    },
    results = {{type = "item", name = "arrakis-depot", amount = 1}}
  },
  {
    -- Design 6: erste Forschung mit Spice-Paketen; schaltet Leitstelle und Carryall frei.
    type = "technology",
    name = "arrakis-ornithopter-depot",
    icon = "__arrakis__/graphics/technology/depot.png",
    icon_size = 256,
    effects =
    {
      {type = "unlock-recipe", recipe = "arrakis-depot"},
      {type = "unlock-recipe", recipe = "arrakis-carryall"}
    },
    prerequisites = {"spice-science-pack", "arrakis-ornithopter"},
    unit =
    {
      count = 300,
      ingredients =
      {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"space-science-pack", 1},
        {"spice-science-pack", 1}
      },
      time = 30
    }
  }
})
