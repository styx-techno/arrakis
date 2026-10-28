-- Phase 3e (docs/plan-3e.md 3): Carryall, der unbemannte Lastenflieger der Leitstelle, mit Item, Rezept und
-- Tempo-Stickern. Kopie des Ornithopters (prototypes/ornithopter.lua, muss vorher laufen): gleiche Beine, gleiche
-- Treibstoffregel (nur Flugtreibstoff), Kofferraum für Ernter-Treibstoff, 1,125-mal so schnell (eigene
-- Stickerfamilien aus prototypes/ornithopter-speed.lua). Eigene Grafik aus tools/grafik/carryall-modell.py.
-- Anheben, Tragen, Absetzen wie beim Ornithopter (scripts/flyer.lua, kind = "carryall"); die Aufträge steuert
-- scripts/fleet.lua.
local speed = require("prototypes.ornithopter-speed")

local gfx = "__arrakis__/graphics/entity/carryall/"

local function carryall_layer(file, size, scale, shift, extra)
  local layer =
  {
    filename = gfx .. file,
    width = size,
    height = size,
    line_length = 8,
    direction_count = 64,
    scale = scale,
    shift = shift
  }
  for key, value in pairs(extra or {}) do layer[key] = value end
  return layer
end

local carryall = table.deepcopy(data.raw["spider-vehicle"]["arrakis-ornithopter"])
carryall.name = "arrakis-carryall"
carryall.icon = "__arrakis__/graphics/icons/carryall.png"
carryall.icon_size = 64
carryall.icons = nil
carryall.minable = {mining_time = 1, result = "arrakis-carryall"}
-- Etwas zäher als der Ornithopter, er fliegt auch unbewacht.
carryall.max_health = 4000
-- Kofferraum: Vorrat an Ernter-Treibstoff (Plan 4.4), 2 Stapel werden beim Parken nachgefüllt.
carryall.inventory_size = 20
-- Sitze wie beim Ornithopter für den Handbetrieb (Plan 1.9); die Automatik startet nie mit Insasse
-- (scripts/fleet.lua manual_check).
-- Rumpf und Farbmaske 576 px mit scale 0,5 (9 Kacheln), Schatten 320 px mit scale 1 (10 Kacheln); Rumpfpunkt und
-- Schatten-shift wie beim Ornithopter (prototypes/ornithopter.lua). Das Modell ist 1,25-mal so groß, der Schwerpunkt
-- des Schattens liegt deshalb 1,25-mal so weit weg.
local SHADOW_SHIFT = {26 / 32 - 0.41, 0.5 / 32 - 0.41}
carryall.graphics_set.animation =
{
  layers =
  {
    carryall_layer("carryall-base.png", 576, 0.5, {0, -19 / 32}),
    carryall_layer("carryall-mask.png", 576, 0.5, {0, -19 / 32}, {apply_runtime_tint = true})
  }
}
carryall.graphics_set.shadow_animation = carryall_layer("carryall-shadow.png", 320, 1, SHADOW_SHIFT,
  {draw_as_shadow = true})
carryall.drawing_box_vertical_extension = 5

local item = table.deepcopy(data.raw["item-with-entity-data"]["arrakis-ornithopter"])
item.name = "arrakis-carryall"
item.icon = carryall.icon
item.icon_size = carryall.icon_size
item.icons = nil
item.place_result = "arrakis-carryall"
item.order = "b[personal-transport]-z[spice-ornithopter]-b[carryall]"

local function speed_sticker(state, j)
  return
  {
    type = "sticker",
    name = speed.name(state, j),
    localised_name = {"entity-name.arrakis-carryall-" .. (state == "carryall-loaded" and "loaded" or "empty")},
    hidden = true,
    flags = {"not-on-map"},
    duration_in_ticks = 60 * 60 * 60,
    vehicle_speed_modifier = speed.modifier(state, j)
  }
end

local stickers = {}
for _, state in ipairs(speed.KIND_STATES.carryall) do
  for j = speed.MIN_J, speed.MAX_J do
    table.insert(stickers, speed_sticker(state, j))
  end
end

data:extend({
  carryall,
  item,
  {
    type = "recipe",
    name = "arrakis-carryall",
    enabled = false,
    energy_required = 15,
    ingredients =
    {
      {type = "item", name = "arrakis-ornithopter", amount = 1},
      {type = "item", name = "steel-plate", amount = 10}
    },
    results = {{type = "item", name = "arrakis-carryall", amount = 1}}
  }
})
data:extend(stickers)
