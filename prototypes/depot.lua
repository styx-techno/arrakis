-- Phase 3e (docs/plan-3e.md 3): Ornithopter-Leitstelle, ein Lager 4×4 nur auf Fels. Ihr Inventar nimmt Flugtreibstoff
-- für die Carryalls und Brennstoff für die Ernter auf; die Carryalls parken auf ihr (scripts/fleet.lua). Beim Bauen
-- zeigt ein Kreis die Reichweite (Mod-Einstellung arrakis-depot-range). Grafik aus tools/grafik/leitstelle-modell.py.
-- Phase 3f: Draht-Anschluss, verstecktes Schaltungsgebäude für die Statussignale, Forschung „Flottenleitung“.
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

-- Phase 3f (docs/plan-3f.md 1.8, 1.9): Draht-Anschluss wie die Eisenkiste. Die Leitstelle gibt ihren Inhalt aus wie jede
-- Kiste; die Flottenleitung liest dort H und R und schreibt ihre Statussignale über arrakis-depot-signals dazu.
local chest = data.raw.container["iron-chest"]
depot.circuit_connector = table.deepcopy(chest.circuit_connector)
depot.circuit_wire_max_distance = chest.circuit_wire_max_distance

-- Verstecktes Schaltungsgebäude unter der Leitstelle (scripts/fleet.lua verdrahtet es per Skript mit ihr).
local signals = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
signals.name = "arrakis-depot-signals"
signals.icon = depot.icon
signals.icon_size = 64
signals.icons = nil
signals.flags = {"placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable", "hide-alt-info",
  "not-flammable", "no-copy-paste", "not-upgradable"}
signals.hidden = true
signals.minable = nil
signals.selectable_in_game = false
signals.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
signals.selection_box = {{-0.1, -0.1}, {0.1, 0.1}}
signals.collision_mask = {layers = {}}
signals.sprites = nil
signals.activity_led_sprites = nil
-- circuit_wire_connection_points und activity_led_light_offsets sind Pflicht (ConstantCombinatorPrototype) und bleiben
-- aus der Vorlage; gezeichnet wird kein Draht (draw_circuit_wires).
signals.draw_circuit_wires = false
signals.circuit_wire_max_distance = 10
signals.corpse = nil
signals.dying_explosion = nil
signals.fast_replaceable_group = nil
signals.next_upgrade = nil
signals.placeable_by = nil

-- Statussignale (docs/plan-3f.md 1.8); den Wurmalarm trägt das Signal arrakis-wormsign aus prototypes/worms.lua.
local function status_signal(name, icon, order)
  return
  {
    type = "virtual-signal",
    name = name,
    icon = icon,
    icon_size = 64,
    subgroup = "virtual-signal",
    order = "e[alert]-z[arrakis-fleet-" .. order .. "]"
  }
end

data:extend({
  depot,
  signals,
  status_signal("arrakis-signal-harvesters", "__arrakis__/graphics/icons/spice-harvester.png", "a"),
  status_signal("arrakis-signal-reserve", "__arrakis__/graphics/icons/depot.png", "b"),
  status_signal("arrakis-signal-carryalls", "__arrakis__/graphics/icons/carryall.png", "c"),
  status_signal("arrakis-signal-rescues", "__arrakis__/graphics/icons/ornithopter.png", "d"),
  {
    type = "virtual-signal",
    name = "arrakis-signal-spice",
    -- Symbol von signal-S übernehmen (die Datei heißt signal_S.png; 0.12.0 lud mit signal-S.png nicht, tools/check/base_paths.py).
    icons = {{icon = data.raw["virtual-signal"]["signal-S"].icon, tint = {r = 1, g = 0.7, b = 0.3}}},
    subgroup = "virtual-signal",
    order = "e[alert]-z[arrakis-fleet-e]"
  },
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
  },
  {
    -- Design 6, docs/plan-3f.md 1.10: Stufe 3. Die Leitstelle setzt Ernter ein, setzt um und ruft zurück; Signale H und R.
    type = "technology",
    name = "arrakis-fleet-control",
    icon = "__arrakis__/graphics/technology/depot.png",
    icon_size = 256,
    effects =
    {
      {type = "nothing", effect_description = {"technology-effect.arrakis-fleet-control"},
        icon = "__arrakis__/graphics/icons/spice-harvester.png", icon_size = 64}
    },
    prerequisites = {"arrakis-ornithopter-depot", "metallurgic-science-pack"},
    unit =
    {
      count = 1000,
      ingredients =
      {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"space-science-pack", 1},
        {"metallurgic-science-pack", 1},
        {"spice-science-pack", 1}
      },
      time = 30
    }
  }
})
