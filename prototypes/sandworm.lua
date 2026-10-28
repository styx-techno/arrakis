-- Phase 3d2 (docs/plan-3d2.md 3): Sandwurm arrakis-sandworm-small samt Segmenten, vier Bohrstaub-Kopien und der Effekt
-- arrakis-worm-dive fürs Auf- und Abtauchen. Steuern, Zerdrücken und Biss macht das Skript (scripts/sandworm.lua,
-- scripts/worms.lua). Kommt direkt nach prototypes/worms.lua: arrakis-worm-dive kopiert die Eruption, die Sterbewolke
-- nimmt arrakis-sand-dust.
-- 2.0-Schreibweise wie überall; compat.finish (prototypes/compat.lua) schreibt unter 2.1 um. Hier braucht nichts eine
-- Umschreibung: kein Rezept, keine Forschung, kein Item, kein Brennstoff.
-- Keine eigenen Bild- oder Tonpfade: Alles kommt per deepcopy aus Space Age bzw. aus der Eruption. Die Hilfen ähneln dem
-- Testwurm (prototypes/testbench/worms.lua), sind aber eine eigene Kopie: Der Testwurm bleibt, wie er ist (T5 bis T7).

local SAND = {r = 1, g = 0.85, b = 0.6}
local BASE = "small-demolisher"
local NAME = "arrakis-sandworm-small"
-- Die ersten 11 Segmente der Vanilla-Liste und der Schwanz (Plan 1 „Prototyp“; T7: 22 Knoten, 21 Kacheln).
local SEGMENTS = 12

-- Tempo (Kacheln je Tick, Plan 1 „Tempo“): 3,5 Kacheln/s in allen Zuständen außer Patrouille, gereizt höchstens 1 s.
local SPEED = 3.5 / 60
local PATROL_SPEED = 1 / 60
local ENRAGED_TICKS = 60

-- Lauter und weiter hörbar (0.8.4, T22 am 28.10.2026: „dürfte früher oder mehr zu hören sein“). Den kleinen Demolisher
-- hört man am Kopf nur auf halbe Normalweite (V23 space-age/prototypes/entity/enemies.lua:549–557,
-- audible_distance_modifier 0.5), Segmente und Schwanz mit Lautstärke 0.25 und 0.3 (V23 sounds.lua:494, :508).
local VOLUME_FACTOR = 2
local AUDIBLE_MIN = 2

-- Bohrstaub: eigene Kopien in Sandfarbe (Plan 3 „Bohrstaub“), Vanilla teilt bei small-bottom die Farbe durch 1,6 bzw. 1,3.
local SMOKES =
{
  front = {0.80, 0.65, 0.40, 0.6},
  ["small-top"] = {0.80, 0.65, 0.40, 0.6},
  ["small-bottom"] = {0.50, 0.41, 0.25, 0.46},
  big = {0.70, 0.57, 0.36, 0.6}
}
-- Partikel in Sand (V23 base/prototypes/particles.lua:2979, :3010, :3030; ein „big“ gibt es nicht).
local PARTICLES =
{
  ["vulcanus-stone-particle-small"] = "sand-1-stone-particle-small",
  ["vulcanus-stone-particle-medium"] = "sand-1-stone-particle-medium",
  ["vulcanus-stone-particle-big"] = "sand-1-stone-particle-medium",
  ["vulcanus-blood-particle-lower-layer-small"] = "sand-1-stone-particle-tiny",
  -- Sterben (dying_trigger_effect): Lava als Sandsteine.
  ["vulcanus-lava-particle-long-life-small"] = "sand-1-stone-particle-small",
  ["vulcanus-lava-particle-long-life-big"] = "sand-1-stone-particle-medium"
}
-- Sterbe-Rauch als Sandstaub (prototypes/worms.lua).
local DYING_SMOKE = {["demolisher-dying-smoke"] = "arrakis-sand-dust"}

-- Ascheeffekte: Ascheschwaden und Sticker, Spuren (trail-upper/-lower), destroy-cliffs, Sticker. Dazu jeder Eintrag mit
-- Schaden irgendwo darin (der Flächenschaden, Plan 1 „Kontaktschaden“).
local ASH_PATTERNS = {"ash%-cloud", "ash%-sticker", "%-trail%-upper", "%-trail%-lower"}

local function unwanted(node, depth)
  if type(node) ~= "table" or depth > 30 then return false end
  if node.type == "destroy-cliffs" or node.type == "create-sticker" or node.type == "damage" then return true end
  for _, key in pairs({"entity_name", "smoke_name", "sticker", "delayed_trigger"}) do
    local value = node[key]
    if type(value) == "string" then
      for _, pattern in pairs(ASH_PATTERNS) do
        if value:find(pattern) then return true end
      end
    end
  end
  for _, child in pairs(node) do
    if unwanted(child, depth + 1) then return true end
  end
  return false
end

-- Eintrag für Eintrag: unerwünschte fallen weg, die übrigen bleiben in ihrer Reihenfolge.
local function keep_wanted(effects)
  if type(effects) ~= "table" then return nil end
  if effects.effect ~= nil or effects.type ~= nil then effects = {effects} end
  local result = {}
  for _, entry in pairs(effects) do
    if not unwanted(entry, 0) then table.insert(result, entry) end
  end
  return result
end

-- Namen von Rauch und Partikeln in Sand umschreiben (rekursiv, auch in verschachtelten Triggern).
local function to_sand(node, depth)
  if type(node) ~= "table" or depth > 30 then return end
  local smoke = node.smoke_name
  if type(smoke) == "string" then
    local size = smoke:match("^demolisher%-mining%-smoke%-(.+)$")
    if size and SMOKES[size] then node.smoke_name = "arrakis-sandworm-smoke-" .. size end
    if DYING_SMOKE[smoke] then node.smoke_name = DYING_SMOKE[smoke] end
  end
  local particle = node.particle_name
  if type(particle) == "string" and PARTICLES[particle] then node.particle_name = PARTICLES[particle] end
  for _, child in pairs(node) do to_sand(child, depth + 1) end
end

-- Leiche und Beute weg (Plan 1 „Beute“): corpse, loot und jedes create-entity einer Leiche im Sterbe-Effekt.
local function is_corpse_effect(effect)
  return type(effect) == "table" and effect.type == "create-entity"
    and type(effect.entity_name) == "string" and effect.entity_name:find("corpse") ~= nil
end

local function remove_loot(prototype)
  prototype.loot = nil
  prototype.corpse = nil
  local effects = prototype.dying_trigger_effect
  if type(effects) ~= "table" then return end
  if effects.type ~= nil then effects = {effects} end
  local kept = {}
  for _, effect in pairs(effects) do
    if not is_corpse_effect(effect) then table.insert(kept, effect) end
  end
  to_sand(kept, 0)
  prototype.dying_trigger_effect = kept
end

-- Tönt alle normalen Bildebenen; Schatten, Leuchten, Licht und Laufzeit-Tönung bleiben.
local function tint_layers(animation)
  if type(animation) ~= "table" then return end
  if animation.layers then
    for _, layer in pairs(animation.layers) do tint_layers(layer) end
    return
  end
  if animation.draw_as_shadow or animation.apply_runtime_tint or animation.draw_as_glow or animation.draw_as_light then return end
  animation.tint = SAND
end

-- "small-demolisher-segment-x0_545" → "arrakis-sandworm-small-segment-x0_545" (V23 enemies.lua:408, :1753).
local function rename(old_name)
  if old_name:sub(1, #BASE) == BASE then return NAME .. old_name:sub(#BASE + 1) end
  return NAME .. "-" .. old_name
end

-- Eine Sound-Tabelle (filename oder variations) lauter und weiter hörbar machen.
local function louder(sound)
  if type(sound) ~= "table" then return end
  local parts = sound.variations or {sound}
  for _, part in pairs(parts) do
    if type(part) == "table" then part.volume = math.min(1, (part.volume or 1) * VOLUME_FACTOR) end
  end
  sound.audible_distance_modifier = math.max(sound.audible_distance_modifier or 1, AUDIBLE_MIN)
end

-- Gemeinsam für Kopf und Segmente: Effekte, Leiche, Tönung (Plan 3 „Segmente“: wie beim Kopf).
local function prepare(prototype)
  prototype.update_effects = keep_wanted(prototype.update_effects)
  to_sand(prototype.update_effects, 0)
  prototype.update_effects_while_enraged = nil
  prototype.factoriopedia_simulation = nil
  remove_loot(prototype)
  tint_layers(prototype.animation)
  if type(prototype.working_sound) == "table" then louder(prototype.working_sound.sound or prototype.working_sound) end
end

-- Kopf (A23 prototypes.d.ts:8751; V23 space-age/prototypes/entity/enemies.lua:468, :6500) ---------------------------
local source = data.raw["segmented-unit"][BASE]
local head = table.deepcopy(source)
head.name = NAME
head.localised_name = {"entity-name." .. NAME}
head.localised_description = {"entity-description." .. NAME}
local icon = head.icon or (head.icons and head.icons[1] and head.icons[1].icon)
local icon_size = head.icon_size or (head.icons and head.icons[1] and head.icons[1].icon_size) or 64
head.icons = {{icon = icon, icon_size = icon_size, tint = SAND}}
head.icon = nil
head.icon_size = nil
head.order = "s-z[arrakis]-a[sandworm-small]"
head.hidden = nil
head.autoplace = nil
head.investigating_speed = SPEED
head.attacking_speed = SPEED
head.enraged_speed = SPEED
head.patrolling_speed = PATROL_SPEED
head.enraged_duration = ENRAGED_TICKS
-- Kein Blick und kein Revier: Das Skript führt ihn (Plan 4.6, 4.7); Erdspalten gibt es nicht.
head.vision_distance = 0
head.territory_radius = 1
head.revenge_attack_parameters = nil
prepare(head)

-- Segmente: die ersten 11 und der Schwanz, einmal je Name (Plan 3 „Segmente“) ------------------------------------
local old_segments = source.segment_engine.segments
local chosen = {}
for i = 1, math.min(SEGMENTS - 1, #old_segments - 1) do
  table.insert(chosen, old_segments[i].segment)
end
table.insert(chosen, old_segments[#old_segments].segment)

local prototypes = {head}
local copied = {}
local segments = {}
for _, old_name in ipairs(chosen) do
  local new_name = rename(old_name)
  if not copied[new_name] then
    copied[new_name] = true
    local segment = table.deepcopy(data.raw["segment"][old_name])
    segment.name = new_name
    segment.localised_name = {"entity-name." .. NAME}
    segment.localised_description = nil
    segment.hidden = true
    prepare(segment)
    table.insert(prototypes, segment)
  end
  table.insert(segments, {segment = new_name})
end
head.segment_engine.segments = segments

-- Bohrstaub (A23 prototypes.d.ts:10651; V23 space-age/prototypes/entity/smoke.lua:227, :241, :255, :269) -----------
for size, color in pairs(SMOKES) do
  local smoke = table.deepcopy(data.raw["trivial-smoke"]["demolisher-mining-smoke-" .. size])
  smoke.name = "arrakis-sandworm-smoke-" .. size
  smoke.color = color
  table.insert(prototypes, smoke)
end

-- Auf- und Abtauchen (A23 prototypes.d.ts:3889): die Eruption kleiner und ohne Ton; den Ton spielt das Skript als
-- arrakis-rumble. Partikel und Sandstaub der Eruption bleiben, Schaden hat sie keinen.
local dive = table.deepcopy(data.raw.explosion["arrakis-worm-eruption"])
dive.name = "arrakis-worm-dive"
dive.localised_name = {"entity-name.arrakis-worm-dive"}
dive.sound = nil
local function unscale(animation)
  if type(animation) ~= "table" then return end
  if animation.layers then
    for _, layer in pairs(animation.layers) do layer.scale = 1.0 end
    return
  end
  animation.scale = 1.0
end
local animations = dive.animations
if animations and (animations.filename or animations.layers or animations.stripes or animations.filenames) then
  unscale(animations)
else
  for _, animation in pairs(animations or {}) do unscale(animation) end
end
table.insert(prototypes, dive)

data:extend(prototypes)
