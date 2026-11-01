-- Phase 3h (docs/plan-3h.md 2.1, 2.2): Thumper (Ablenkung und Köder) und Wurmzahn (Beute).
-- Grafik ohne feste Bildpfade für die Entity: eine verkleinerte Kopie der Pumpjack-Grafik aus data.raw (Sockel als
-- stehende Ebene, Pferdekopf als Animation). Fehlt etwas davon (andere Mods), bleibt das Pumpjack-Icon als Bild.

local THUMPER = "arrakis-thumper"
local TOOTH = "arrakis-worm-tooth"
-- Verkleinerung gegenüber der Pumpjack (3×3 → etwa 2×2).
local SCALE = 0.6
local TINT = {r = 1, g = 0.85, b = 0.6}

local function scaled(layer, frames)
  local copy = table.deepcopy(layer)
  copy.scale = (copy.scale or 1) * SCALE
  local shift = copy.shift
  if shift then
    local x = shift.x or shift[1] or 0
    local y = shift.y or shift[2] or 0
    copy.shift = {x * SCALE, y * SCALE}
  end
  copy.priority = nil
  if frames then
    -- Stehender Sockel: ein Bild, so oft wiederholt, wie der Pferdekopf Bilder hat.
    copy.frame_count = 1
    copy.repeat_count = frames
    copy.animation_speed = copy.animation_speed or 0.5
  end
  if not copy.draw_as_shadow then copy.tint = TINT end
  return copy
end

local function thumper_animation()
  local pumpjack = data.raw["mining-drill"] and data.raw["mining-drill"]["pumpjack"]
  local set = pumpjack and pumpjack.graphics_set
  local head = set and set.animation and set.animation.north and set.animation.north.layers
  local visual = set and set.working_visualisations and set.working_visualisations[1]
  local base = visual and visual.north_animation and visual.north_animation.layers
  if not (head and base and head[1] and head[1].frame_count) then return nil end
  local frames = head[1].frame_count
  local layers = {}
  for _, layer in ipairs(base) do
    if layer.filename then layers[#layers + 1] = scaled(layer, frames) end
  end
  for _, layer in ipairs(head) do
    if layer.filename and layer.frame_count == frames then layers[#layers + 1] = scaled(layer, nil) end
  end
  if #layers == 0 then return nil end
  return {layers = layers}
end

local icons = {{icon = "__base__/graphics/icons/pumpjack.png", icon_size = 64, tint = TINT}}

local thumper =
{
  type = "simple-entity-with-owner",
  name = THUMPER,
  icons = icons,
  flags = {"placeable-neutral", "placeable-player", "player-creation"},
  -- Verbrauchsgut: Abbauen räumt ihn weg, gibt aber nichts zurück.
  minable = {mining_time = 0.2},
  max_health = 150,
  collision_box = {{-0.8, -0.8}, {0.8, 0.8}},
  selection_box = {{-1, -1}, {1, 1}},
  -- Nur auf Sand (Design 4.3): keine Felskachel unter der Box.
  tile_buildability_rules =
  {
    {area = {{-0.9, -0.9}, {0.9, 0.9}}, colliding_tiles = {layers = {arrakis_rock = true}}}
  },
  placeable_by = {item = THUMPER, count = 1},
  render_layer = "object",
  random_animation_offset = false
}
local animation = thumper_animation()
if animation then
  thumper.animations = {animation}
else
  thumper.picture = {filename = "__base__/graphics/icons/pumpjack.png", size = 64, scale = 0.5, tint = TINT}
end

data:extend({
  thumper,
  {
    type = "item",
    name = THUMPER,
    icons = icons,
    subgroup = "transport",
    order = "b[personal-transport]-z[spice-harvester]-t[thumper]",
    place_result = THUMPER,
    stack_size = 20
  },
  {
    type = "recipe",
    name = THUMPER,
    enabled = false,
    energy_required = 2,
    ingredients =
    {
      {type = "item", name = "iron-plate", amount = 5},
      {type = "item", name = "iron-gear-wheel", amount = 5},
      {type = "item", name = "coal", amount = 2}
    },
    results = {{type = "item", name = THUMPER, amount = 1}}
  },
  {
    -- Beute (Plan 2.2): verwendet erst mit dem Ernter Mk2 (spätere Phase).
    type = "item",
    name = TOOTH,
    icons = {{icon = "__base__/graphics/icons/stone.png", icon_size = 64, tint = {r = 1, g = 0.96, b = 0.82}}},
    subgroup = "raw-material",
    order = "z[arrakis]-t[worm-tooth]",
    stack_size = 50
  },
  {
    -- Trigger-Forschung (Design 6): erforscht, sobald die Force die erste Jagd überstanden hat (entkommen oder Wurm
    -- getötet). Das Skript löst sie aus (scripts/thumper.lua), auch für alte Spielstände.
    type = "technology",
    name = THUMPER,
    icons = {{icon = "__base__/graphics/technology/oil-gathering.png", icon_size = 256, tint = TINT}},
    effects =
    {
      {type = "unlock-recipe", recipe = THUMPER}
    },
    prerequisites = {"arrakis-spice-harvesting"},
    research_trigger =
    {
      type = "scripted",
      trigger_description = {"technology-description.arrakis-thumper-trigger"},
      icons = icons
    }
  }
})
