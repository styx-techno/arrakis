-- Phase 3i (docs/plan-3i.md, Max' Wahl 1b 2b 3b 4a): Ernter Mk2, Rezept mit Wurmzähnen, Forschung „Ernter Mk2“.
-- Kopie des Ernters (prototypes/harvester.lua), dazu Laderaum 60 und +50 % Lebenspunkte. Förderung ×1,5 und Vibration ×0,8 setzt das Skript
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
-- Plan 1.1 b: Laderaum 60 statt 40, Lebenspunkte ×1,5.
mk2.inventory_size = 60
mk2.max_health = (data.raw.car["spice-harvester"].max_health or 2000) * 1.5
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
    -- Plan 1.2 b: nichts Verderbliches.
    type = "recipe",
    name = NAME,
    enabled = false,
    energy_required = 20,
    ingredients =
    {
      {type = "item", name = "spice-harvester", amount = 1},
      {type = "item", name = "arrakis-worm-tooth", amount = 4},
      {type = "item", name = "melange", amount = 10},
      {type = "item", name = "processing-unit", amount = 5}
    },
    results = {{type = "item", name = NAME, amount = 1}}
  },
  {
    -- Plan 1.3 b: normale Forschung mit Spice-Wissenschaft hinter „Thumper“ (wer Zähne hat, hat eine Jagd überstanden).
    type = "technology",
    name = TECH,
    icons = {{icon = GFX .. "technology/spice-harvester-mk2.png", icon_size = 256}},
    effects =
    {
      {type = "unlock-recipe", recipe = NAME}
    },
    prerequisites = {"arrakis-thumper"},
    unit =
    {
      count = 500,
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
