-- Prüfstand T5, T6, T7: Testwurm, Kopie des kleinen Demolishers samt Segmenten (Design 4.3).
-- arrakis-test-worm-rockmask hat zusätzlich die Kollisionsebene arrakis_rock (T6).
local collision_mask_util = require("collision-mask-util")

local base_name = "small-demolisher"
local sand_tint = {r = 1, g = 0.85, b = 0.55}
local segment_count = 12

-- Tempo: SegmentedUnitPrototype erwartet Kacheln je Tick. Vanilla schreibt
-- investigating_speed = 4.0 * speed_multiplier / 60 (klein: 0,55 → 2,2 Kacheln/s),
-- also Kacheln/s geteilt durch 60.
local investigating_speed = 3.5 / 60
local attacking_speed = 6 / 60

-- Ascheeffekte erkennen: Ascheschwaden und Sticker, Spuren (trail-upper/-lower), destroy-cliffs.
-- Kontaktschaden (area + damage), Bohrstaub und Partikel bleiben.
local ash_patterns = {"ash%-cloud", "ash%-sticker", "%-trail%-upper", "%-trail%-lower"}

local function is_ash_effect(node, depth)
  if type(node) ~= "table" or depth > 30 then return false end
  if node.type == "destroy-cliffs" or node.type == "create-sticker" then return true end
  for _, key in pairs({"entity_name", "smoke_name", "sticker", "delayed_trigger"}) do
    local value = node[key]
    if type(value) == "string" then
      for _, pattern in pairs(ash_patterns) do
        if value:find(pattern) then return true end
      end
    end
  end
  for _, child in pairs(node) do
    if is_ash_effect(child, depth + 1) then return true end
  end
  return false
end

local function without_ash(effects)
  if not effects then return nil end
  local result = {}
  for _, entry in pairs(effects) do
    if not is_ash_effect(entry, 0) then table.insert(result, entry) end
  end
  return result
end

-- Beute entfernen: Die Leiche (simple-entity mit Wolfram) entsteht über corpse und
-- dying_trigger_effect; beides fällt weg.
local function is_corpse_effect(effect)
  return type(effect) == "table" and effect.type == "create-entity"
    and type(effect.entity_name) == "string" and effect.entity_name:find("corpse") ~= nil
end

local function remove_loot(prototype)
  prototype.loot = nil
  prototype.corpse = nil
  local effects = prototype.dying_trigger_effect
  if type(effects) == "table" then
    if is_corpse_effect(effects) then
      prototype.dying_trigger_effect = nil
    elseif not effects.type then
      local kept = {}
      for _, effect in pairs(effects) do
        if not is_corpse_effect(effect) then table.insert(kept, effect) end
      end
      prototype.dying_trigger_effect = kept
    end
  end
end

-- Tönt alle normalen Bildebenen; Schatten, Farbmasken und Leuchten bleiben.
local function tint_layers(animation, tint)
  if type(animation) ~= "table" then return end
  if animation.layers then
    for _, layer in pairs(animation.layers) do tint_layers(layer, tint) end
    return
  end
  if animation.draw_as_shadow or animation.apply_runtime_tint or animation.draw_as_glow or animation.draw_as_light then return end
  animation.tint = tint
end

local function add_rock_layer(prototype)
  local mask = table.deepcopy(collision_mask_util.get_mask(prototype))
  mask.layers.arrakis_rock = true
  prototype.collision_mask = mask
end

-- Alte Namen "small-demolisher-segment-x0_5…" werden zu "<name>-segment-x0_5…".
local function rename(old_name, new_base)
  if old_name:sub(1, #base_name) == base_name then
    return new_base .. old_name:sub(#base_name + 1)
  end
  return new_base .. "-" .. old_name
end

local function make_worm(name, rock_mask)
  local source = data.raw["segmented-unit"][base_name]
  local head = table.deepcopy(source)
  head.name = name
  head.localised_name = nil
  head.hidden = true
  head.factoriopedia_simulation = nil
  head.update_effects = without_ash(head.update_effects)
  head.update_effects_while_enraged = nil
  head.revenge_attack_parameters = nil
  head.vision_distance = 0
  head.territory_radius = 1
  head.investigating_speed = investigating_speed
  head.attacking_speed = attacking_speed
  remove_loot(head)
  tint_layers(head.animation, sand_tint)
  if rock_mask then add_rock_layer(head) end

  -- Körper: erste 11 Segmente plus Schwanz (letzter Eintrag), umbenannt kopiert.
  local old_segments = source.segment_engine.segments
  local chosen = {}
  for i = 1, math.min(segment_count - 1, #old_segments - 1) do
    table.insert(chosen, old_segments[i].segment)
  end
  table.insert(chosen, old_segments[#old_segments].segment)

  local prototypes = {head}
  local copied = {}
  local segments = {}
  for _, old_name in ipairs(chosen) do
    local new_name = rename(old_name, name)
    if not copied[new_name] then
      copied[new_name] = true
      local segment = table.deepcopy(data.raw["segment"][old_name])
      segment.name = new_name
      segment.localised_name = {"entity-name." .. name}
      segment.hidden = true
      segment.factoriopedia_simulation = nil
      segment.update_effects = without_ash(segment.update_effects)
      segment.update_effects_while_enraged = nil
      remove_loot(segment)
      tint_layers(segment.animation, sand_tint)
      if rock_mask then add_rock_layer(segment) end
      table.insert(prototypes, segment)
    end
    table.insert(segments, {segment = new_name})
  end
  head.segment_engine.segments = segments
  log("Prüfstand: " .. name .. " mit " .. #segments .. " Segmenten, update_effects " ..
    #(source.update_effects or {}) .. " -> " .. #(head.update_effects or {}))
  return prototypes
end

data:extend(make_worm("arrakis-test-worm", false))
data:extend(make_worm("arrakis-test-worm-rockmask", true))
