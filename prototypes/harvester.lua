-- Phase 3b: Spice-Ernter, Spice-Annahme, Tankstutzen, Spice-Brikett, Forschung „Spice-Ernte“ und Taste.
-- Spice-Sand baut nur noch der Ernter ab (und die Hand, data-final-fixes.lua).
-- Abbau, Andocken und Tempo steuert das Skript (scripts/harvester.lua, scripts/intake.lua).
-- Der Ernter hat ab 0.8.5 eigene Grafik (tools/grafik/ernter-modell.py, Blender); Annahme, Tankstutzen und Brikett sind
-- noch getönte Vanilla-Platzhalter, wie im Prüfstand (prototypes/testbench/harvester.lua, proxies.lua).
local compat = require("prototypes.compat")
local item_sounds = require("__base__.prototypes.item_sounds")

local harvester_gfx = "__arrakis__/graphics/entity/spice-harvester/"
local intake_tint = {r = 1, g = 0.6, b = 0.3}
local nozzle_tint = {r = 1, g = 0.35, b = 0.3}
local spice_tint = {r = 1, g = 0.45, b = 0.15}

local function tinted(icon, tint)
  return {{icon = icon, tint = tint}}
end

-- Bild der Eisenkiste, skaliert und getönt (Schatten nur skaliert).
local function chest_picture(factor, tint)
  local picture = table.deepcopy(data.raw.container["iron-chest"].picture)
  local layers = picture.layers or {picture}
  for _, layer in pairs(layers) do
    layer.scale = (layer.scale or 1) * factor
    if layer.shift then
      layer.shift = {(layer.shift[1] or layer.shift.x) * factor, (layer.shift[2] or layer.shift.y) * factor}
    end
    if not layer.draw_as_shadow then layer.tint = tint end
  end
  return picture
end

-- Kopie des Vanilla-Proxy-Containers. Der Schaltungsanschluss kommt mit dem deepcopy (ab 2.1.21 eine Liste,
-- vorher ein einzelnes Objekt). Nie den einer Kiste kopieren: 2.0 und 2.1.20 erwarten beim Proxy kein Array.
local function make_proxy(name, tint)
  local proxy = table.deepcopy(data.raw["proxy-container"]["proxy-container"])
  proxy.name = name
  proxy.hidden = nil
  proxy.icon = nil
  proxy.icons = tinted("__base__/graphics/icons/iron-chest.png", tint)
  proxy.minable = {mining_time = 0.5, result = name}
  proxy.fast_replaceable_group = nil
  return proxy
end

-- Spice-Ernter: Kopie des Panzers ohne Waffen, Turm und Ausrüstungsgitter, mit eigener Grafik.
local harvester = table.deepcopy(data.raw.car.tank)
harvester.name = "spice-harvester"
harvester.icon = "__arrakis__/graphics/icons/spice-harvester.png"
harvester.icon_size = 64
harvester.icons = nil
harvester.minable = {mining_time = 0.5, result = "spice-harvester"}
harvester.guns = nil
harvester.inventory_size = 40
-- Brennstoffkategorien bleiben die des Panzers (chemical).
harvester.energy_source.fuel_inventory_size = 3
-- Keine Fahrt aus der Kartenansicht, kein Logistik-Tab, keine Mitnahme durch Förderbänder.
harvester.allow_remote_driving = false
harvester.trash_inventory_size = 0
harvester.equipment_grid = nil
harvester.has_belt_immunity = true
harvester.factoriopedia_simulation = nil
-- 64 Richtungen je Blatt (8 × 8, 0 = Norden, im Uhrzeigersinn), ein Bild je Richtung: Die Ketten laufen nicht sichtbar.
-- Rumpf und Farbmaske als HR-Bild (384 px = 6 Kacheln, scale 0,5), Schatten mit 32 px je Kachel (256 px = 8 Kacheln,
-- scale 1). Der Bodenpunkt unter der Fahrzeugmitte liegt in jeder Bildmitte, deshalb ohne shift.
local function harvester_layer(file, size, scale, extra)
  local layer =
  {
    filename = harvester_gfx .. file,
    width = size,
    height = size,
    line_length = 8,
    direction_count = 64,
    frame_count = 1,
    max_advance = 1,
    scale = scale
  }
  for key, value in pairs(extra or {}) do layer[key] = value end
  return layer
end
harvester.animation =
{
  layers =
  {
    harvester_layer("harvester-base.png", 384, 0.5),
    harvester_layer("harvester-mask.png", 384, 0.5, {apply_runtime_tint = true}),
    harvester_layer("harvester-shadow.png", 256, 1, {draw_as_shadow = true})
  }
}
harvester.turret_animation = nil
harvester.light_animation = nil
harvester.water_reflection = nil
-- Wrack: allgemeiner Schutt statt Panzerwrack.
harvester.corpse = "big-remnants"

-- Physik aus dem Prüfstand (T2), Leistung 330 kW: mit Kohle etwa 1,45 Kacheln/s (Modell, T2b misst).
-- Schnellere Brennstoffe gleicht das Skript aus (effectivity_modifier), dazu kommt der Tempo-Deckel.
harvester.consumption = "330kW"
harvester.effectivity = 0.9
harvester.weight = 20000
harvester.terrain_friction_modifier = 0
compat.vehicle_physics(harvester, 800 * 1000 / 60, 0.1)

-- Spice-Annahme: 2×2, darf nur stehen, wenn die ganze Fläche 10×10 um sie (Andockkreis) Fels ist.
-- Gepflasterter Fels zählt hier nicht: vor dem Pflastern bauen.
local intake = make_proxy("arrakis-spice-intake", intake_tint)
intake.collision_box = {{-0.9, -0.9}, {0.9, 0.9}}
intake.selection_box = {{-1, -1}, {1, 1}}
intake.picture = chest_picture(2, intake_tint)
intake.tile_buildability_rules =
{
  {area = {{-5, -5}, {5, 5}}, required_tiles = {layers = {arrakis_rock = true}}}
}

-- Tankstutzen: 1×1, ohne Bauregel.
local nozzle = make_proxy("arrakis-fuel-nozzle", nozzle_tint)
nozzle.picture = chest_picture(1, nozzle_tint)

data:extend({
  {
    -- Spice-Sand (prototypes/resources.lua): kein Bohrer hat diese Kategorie.
    type = "resource-category",
    name = "arrakis-spice-harvest"
  },
  harvester,
  intake,
  nozzle,

  -- Items
  {
    type = "item-with-entity-data",
    name = "spice-harvester",
    icon = harvester.icon,
    icon_size = harvester.icon_size,
    subgroup = "transport",
    order = "b[personal-transport]-z[spice-harvester]",
    inventory_move_sound = item_sounds.vehicle_inventory_move,
    pick_sound = item_sounds.vehicle_inventory_pickup,
    drop_sound = item_sounds.vehicle_inventory_move,
    place_result = "spice-harvester",
    stack_size = 1,
    default_import_location = "arrakis"
  },
  {
    type = "item",
    name = "arrakis-spice-intake",
    icons = intake.icons,
    subgroup = "storage",
    order = "a[items]-y[arrakis-spice-intake]",
    inventory_move_sound = item_sounds.metal_chest_inventory_move,
    pick_sound = item_sounds.metal_chest_inventory_pickup,
    drop_sound = item_sounds.metal_chest_inventory_move,
    place_result = "arrakis-spice-intake",
    stack_size = 10,
    default_import_location = "arrakis"
  },
  {
    type = "item",
    name = "arrakis-fuel-nozzle",
    icons = nozzle.icons,
    subgroup = "storage",
    order = "a[items]-z[arrakis-fuel-nozzle]",
    inventory_move_sound = item_sounds.metal_chest_inventory_move,
    pick_sound = item_sounds.metal_chest_inventory_pickup,
    drop_sound = item_sounds.metal_chest_inventory_move,
    place_result = "arrakis-fuel-nozzle",
    stack_size = 10,
    default_import_location = "arrakis"
  },
  {
    -- Lokaler Brennstoff. Keine Tempo-Multiplikatoren: fährt wie Kohle.
    type = "item",
    name = "arrakis-spice-briquette",
    icons = tinted("__base__/graphics/icons/coal.png", spice_tint),
    fuel_category = "chemical",
    fuel_value = "20MJ",
    subgroup = "arrakis-spice",
    order = "e[spice-briquette]",
    inventory_move_sound = item_sounds.solid_fuel_inventory_move,
    pick_sound = item_sounds.solid_fuel_inventory_pickup,
    drop_sound = item_sounds.solid_fuel_inventory_move,
    stack_size = 50,
    weight = 10 * kg,
    default_import_location = "arrakis"
  },

  -- Rezepte
  {
    type = "recipe",
    name = "spice-harvester",
    enabled = false,
    energy_required = 10,
    ingredients =
    {
      {type = "item", name = "steel-plate", amount = 40},
      {type = "item", name = "engine-unit", amount = 20},
      {type = "item", name = "advanced-circuit", amount = 10},
      {type = "item", name = "stone-brick", amount = 100},
      {type = "item", name = "melange", amount = 10}
    },
    results = {{type = "item", name = "spice-harvester", amount = 1}}
  },
  {
    type = "recipe",
    name = "arrakis-spice-intake",
    enabled = false,
    energy_required = 5,
    ingredients =
    {
      {type = "item", name = "steel-plate", amount = 20},
      {type = "item", name = "stone-brick", amount = 50},
      {type = "item", name = "electronic-circuit", amount = 5}
    },
    results = {{type = "item", name = "arrakis-spice-intake", amount = 1}}
  },
  {
    type = "recipe",
    name = "arrakis-fuel-nozzle",
    enabled = false,
    energy_required = 2,
    ingredients =
    {
      {type = "item", name = "steel-plate", amount = 5},
      {type = "item", name = "pipe", amount = 5}
    },
    results = {{type = "item", name = "arrakis-fuel-nozzle", amount = 1}}
  },
  {
    -- Ohne allow_productivity: genau 1 Brikett (20 MJ), auch mit der Grundproduktivität der Raffinerie.
    type = "recipe",
    name = "arrakis-spice-briquette",
    category = "spice-refining",
    subgroup = "arrakis-spice",
    order = "e[spice-briquette]",
    enabled = false,
    energy_required = 4,
    ingredients =
    {
      {type = "item", name = "spice-sand", amount = 5},
      {type = "item", name = "coal", amount = 1}
    },
    results = {{type = "item", name = "arrakis-spice-briquette", amount = 1}}
  },

  -- Forschung „Spice-Ernte“
  {
    type = "technology",
    name = "arrakis-spice-harvesting",
    icon = "__arrakis__/graphics/technology/spice-harvester.png",
    icon_size = 256,
    effects =
    {
      {type = "unlock-recipe", recipe = "spice-harvester"},
      {type = "unlock-recipe", recipe = "arrakis-spice-intake"},
      {type = "unlock-recipe", recipe = "arrakis-fuel-nozzle"},
      {type = "unlock-recipe", recipe = "arrakis-spice-briquette"}
    },
    prerequisites = {"arrakis-spice-processing"},
    research_trigger =
    {
      type = "craft-item",
      item = "melange",
      count = 10
    }
  },

  -- Taste: Aufbauen, Einpacken, Abdocken (der Knopf im Ernterfenster tut dasselbe).
  {
    type = "custom-input",
    name = "arrakis-harvester-toggle",
    key_sequence = "SHIFT + H",
    consuming = "none"
  }
})
