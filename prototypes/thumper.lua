-- Phase 3h (docs/plan-3h.md 2.1, 2.2): Thumper (Ablenkung und Köder) und Wurmzahn (Beute).
-- Grafik (Grafik-Phase, docs/plan-grafik.md): eigenes Blender-Modell (tools/grafik/thumper-modell.py), 16 Bilder
-- Stampfzyklus in einer Ansicht, Bildmitte = Bodenpunkt (kein shift). Ein Schlag je Sekunde.

local THUMPER = "arrakis-thumper"
local TOOTH = "arrakis-worm-tooth"
local GFX = "__arrakis__/graphics/"
local FRAMES = 16
local SPEED = FRAMES / 60

local function thumper_animation()
  return
  {
    layers =
    {
      {filename = GFX .. "entity/thumper/thumper-base.png", width = 256, height = 256, frame_count = FRAMES,
       line_length = 8, scale = 0.5, animation_speed = SPEED},
      {filename = GFX .. "entity/thumper/thumper-shadow.png", width = 160, height = 160, frame_count = FRAMES,
       line_length = 8, scale = 1, animation_speed = SPEED, draw_as_shadow = true}
    }
  }
end

local icons = {{icon = GFX .. "icons/thumper.png", icon_size = 64}}

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
thumper.animations = {thumper_animation()}

data:extend({
  thumper,
  {
    -- 0.16.2 (Max im Spiel, T34 Frage 1: nicht zu hören): ein Schlag, scripts/thumper.lua spielt ihn jede Sekunde.
    -- Eigener Ton aus tools/ton/thumper.py.
    type = "sound",
    name = "arrakis-thump",
    category = "game-effect",
    filename = "__arrakis__/sound/thumper.ogg",
    volume = 0.9,
    audible_distance_modifier = 1.5
  },
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
    -- Beute (Plan 2.2): Zutat des Ernter Mk2 (prototypes/harvester-mk2.lua, docs/plan-3i.md).
    type = "item",
    name = TOOTH,
    icons = {{icon = GFX .. "icons/worm-tooth.png", icon_size = 64}},
    subgroup = "raw-material",
    order = "z[arrakis]-t[worm-tooth]",
    stack_size = 50
  },
  {
    -- Trigger-Forschung (Design 6): erforscht, sobald die Force die erste Jagd überstanden hat (entkommen oder Wurm
    -- getötet). Das Skript löst sie aus (scripts/thumper.lua), auch für alte Spielstände.
    type = "technology",
    name = THUMPER,
    icons = {{icon = GFX .. "technology/thumper.png", icon_size = 256}},
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
