-- Phase 3i (docs/plan-3i.md): Ernter Mk2, Rezept mit Wurmzähnen, Forschung „Ernter Mk2“.
-- Kopie des Ernters (prototypes/harvester.lua). Förderung ×1,5 und Vibration ×0,8 setzt das Skript
-- (scripts/harvester.lua rate_factor/vibration_factor, scripts/vibration.lua). Eigene Grafik aus der Grafik-Phase
-- (tools/grafik/ernter-modell.py mit ARRAKIS_VARIANTE=mk2: Wurmzahn-Klingen am Maul, hellere Panzerplatten, dritter
-- Schlot), gleiche Blattmaße wie Mk1. Das Lastbild am Flieger bleibt das Mk1-Bild mit Farbton (harvester.MK2_TINT).
local item_sounds = require("__base__.prototypes.item_sounds")

local NAME = "spice-harvester-mk2"
local TECH = "arrakis-harvester-mk2"
local GFX = "__arrakis__/graphics/"
local ICON = GFX .. "icons/spice-harvester-mk2.png"

local mk2 = table.deepcopy(data.raw.car["spice-harvester"])
mk2.name = NAME
mk2.icon = nil
mk2.icon_size = nil
mk2.icons = {{icon = ICON, icon_size = 64}}
mk2.minable = {mining_time = 0.5, result = NAME}
-- Eigene Blätter: harvester-*.png → spice-harvester-mk2/harvester-mk2-*.png, Ausschnitte wie Mk1.
for _, layer in pairs(mk2.animation.layers) do
  layer.filename = layer.filename:gsub("/spice%-harvester/harvester%-", "/spice-harvester-mk2/harvester-mk2-")
end

data:extend({
  mk2,
  {
    type = "item-with-entity-data",
    name = NAME,
    icons = mk2.icons,
    subgroup = "transport",
    order = "b[personal-transport]-z[spice-harvester]-b[mk2]",
    inventory_move_sound = item_sounds.vehicle_inventory_move,
    pick_sound = item_sounds.vehicle_inventory_pickup,
    drop_sound = item_sounds.vehicle_inventory_move,
    place_result = NAME,
    stack_size = 1,
    default_import_location = "arrakis"
  },
  {
    -- Plan 1.2 a: Spice-Essenz verdirbt in 15 min, also frisch verbauen.
    type = "recipe",
    name = NAME,
    enabled = false,
    energy_required = 20,
    ingredients =
    {
      {type = "item", name = "spice-harvester", amount = 1},
      {type = "item", name = "arrakis-worm-tooth", amount = 4},
      {type = "item", name = "spice-essence", amount = 10}
    },
    results = {{type = "item", name = NAME, amount = 1}}
  },
  {
    -- Plan 1.3 a: Trigger-Forschung, erforscht, sobald die Force zum ersten Mal Wurmzähne erbeutet (scripts/worms.lua
    -- drop_loot) oder einen aufhebt (scripts/harvester.lua). Voraussetzung nur „Spice-Ernte“: Die Zähne fallen schon
    -- beim Tod des Wurms, die Forschung „Thumper“ erst am Ende der Jagd.
    type = "technology",
    name = TECH,
    icons = {{icon = GFX .. "technology/spice-harvester-mk2.png", icon_size = 256}},
    effects =
    {
      {type = "unlock-recipe", recipe = NAME}
    },
    prerequisites = {"arrakis-spice-harvesting"},
    research_trigger =
    {
      type = "scripted",
      trigger_description = {"technology-description.arrakis-harvester-mk2-trigger"},
      icons = {{icon = ICON, icon_size = 64}}
    }
  }
})
