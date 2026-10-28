-- Phase 3d1 (docs/plan-3d1.md 3): Wurm-Eruption, Sandstaub, Signal „Wurmzeichen“, zwei Geräusche, Verknüpfung
-- „Vibrationsanzeige“ und zwei Tipps (Briefings). Einen sichtbaren Wurm gibt es noch nicht (3d2); Vibration, Wärme,
-- Jagd und Biss steuert das Skript (scripts/vibration.lua, scripts/worms.lua, scripts/worms-gui.lua).
-- 2.0-Schreibweise wie überall; compat.finish (prototypes/compat.lua) schreibt unter 2.1 um. Hier braucht nichts eine
-- Umschreibung: kein Rezept, keine Forschung, kein Item, kein Brennstoff.
-- Dateipfade nur, wie sie in den Vanilla-Daten 2.1.23 wörtlich vorkommen: Ein falscher Sound- oder Bildpfad bricht das
-- Laden ab. Keine eigenen Sprite-Prototypen: Fenster und Chat nutzen [virtual-signal=arrakis-wormsign].

local SAND = {r = 1, g = 0.85, b = 0.6}
local SIGNAL_TINT = {r = 1, g = 0.55, b = 0.2}
local ALERT_ICON = "__base__/graphics/icons/signal/signal-alert.png"

-- Liste aus einem Einzelwert oder einer Liste (Trigger, Lieferungen und Effekte dürfen beides sein).
local function as_list(value)
  if value == nil then return {} end
  if value.type ~= nil then return {value} end
  return value
end

-- Tönt eine Animation (mit layers: jede Ebene) und vergrößert sie (Plan 3 „Eruption“).
local function tint_animation(animation)
  if type(animation) ~= "table" then return end
  if animation.layers then
    for _, layer in pairs(animation.layers) do
      layer.tint = SAND
      layer.scale = 1.5
    end
    return
  end
  animation.tint = SAND
  animation.scale = 1.5
end

-- Eruption: die große Artillerie-Explosion (V23 base/prototypes/entity/explosions.lua:4443), sandfarben und größer,
-- mit Sandsteinen statt Felsbrocken (V23 base/prototypes/particles.lua:2979, :3010, :3030) und Sandstaub. Kein Schaden:
-- created_effect erzeugt nur Partikel und Rauch.
local eruption = table.deepcopy(data.raw.explosion["big-artillery-explosion"])
eruption.name = "arrakis-worm-eruption"
eruption.localised_name = {"entity-name.arrakis-worm-eruption"}
eruption.icon = nil
eruption.icons = {{icon = "__base__/graphics/icons/explosion.png", tint = SAND}}
eruption.order = "z[arrakis]-a[worm-eruption]"
-- animations ist eine Animation oder eine Liste von Animationen (AnimationVariations).
local animations = eruption.animations
if animations and (animations.filename or animations.layers or animations.stripes or animations.filenames) then
  tint_animation(animations)
else
  for _, animation in pairs(animations or {}) do tint_animation(animation) end
end
for _, trigger in pairs(as_list(eruption.created_effect)) do
  for _, delivery in pairs(as_list(trigger.action_delivery)) do
    local effects = as_list(delivery.target_effects)
    for _, effect in pairs(effects) do
      local size = type(effect.particle_name) == "string" and effect.particle_name:match("^explosion%-stone%-particle%-(%a+)$")
      if size then effect.particle_name = "sand-1-stone-particle-" .. size end
    end
    -- Sandstaub (A23 types.d.ts:3614–3628, repeat_count :13335).
    table.insert(effects,
    {
      type = "create-trivial-smoke",
      smoke_name = "arrakis-sand-dust",
      repeat_count = 8,
      offset_deviation = {{-3, -3}, {3, 3}},
      speed_from_center = 0.04
    })
    delivery.target_effects = effects
  end
end
-- Ausgeschrieben statt sound_variations, damit die Datei nicht von core/lualib/sound-util.lua abhängt
-- (V23 space-age/prototypes/entity/sounds.lua:645).
eruption.sound =
{
  variations =
  {
    {filename = "__space-age__/sound/explosions/demolisher-explosion-1.ogg", volume = 1},
    {filename = "__space-age__/sound/explosions/demolisher-explosion-2.ogg", volume = 1}
  }
}

-- Sandstaub für Unruhe und Eruption: der große Demolisher-Staub (V23 space-age/prototypes/entity/smoke.lua:269) in
-- Sandfarbe, sonst geerbt (300 Ticks, ohne Wind).
local dust = table.deepcopy(data.raw["trivial-smoke"]["demolisher-mining-smoke-big"])
dust.name = "arrakis-sand-dust"
dust.color = {0.80, 0.65, 0.40, 0.6}

-- Wurmzeichen-Varianten (V23 space-age/prototypes/entity/sounds.lua:588: demolisher-roar-big, 6 Stück).
local roar = {}
for i = 1, 6 do
  roar[i] = {filename = "__space-age__/sound/enemies/demolisher/demolisher-roar-big-" .. i .. ".ogg", volume = 0.9}
end

-- Brüllen beim Auftauchen (0.8.4; V23 space-age/prototypes/entity/sounds.lua:468: demolisher-roar, 10 Stück).
local surface_roar = {}
for i = 1, 10 do
  surface_roar[i] = {filename = "__space-age__/sound/enemies/demolisher/demolisher-roar-" .. i .. ".ogg", volume = 1.0}
end

data:extend({
  eruption,
  dust,

  -- Symbol für Alarm, Kartenmarkierung, Fenster und Tipp (V23 base/prototypes/signal.lua:117). Schaltungsausgänge
  -- kommen mit 3f.
  {
    type = "virtual-signal",
    name = "arrakis-wormsign",
    icons = {{icon = ALERT_ICON, tint = SIGNAL_TINT}},
    subgroup = "virtual-signal",
    order = "e[alert]-z[arrakis-wormsign]"
  },

  -- Warnton beim Wurmzeichen, ohne Position abgespielt (A23 types.d.ts:10320 „alert“).
  {
    type = "sound",
    name = "arrakis-wormsign",
    category = "alert",
    variations = roar
  },

  -- Rumpeln bei Unruhe, je Sektor höchstens alle 5 s (V23 space-age/prototypes/entity/sounds.lua:508, :628).
  {
    type = "sound",
    name = "arrakis-rumble",
    category = "environment",
    filename = "__space-age__/sound/enemies/demolisher/demolisher-tail-rumble.ogg",
    volume = 0.6,
    audible_distance_modifier = 2
  },

  -- Rumpeln des Sandwurms (0.8.4): vor dem Auftauchen an der Stelle, beim Auf- und Abtauchen am Kopf. Lauter und weiter
  -- hörbar als arrakis-rumble (T22 am 28.10.2026).
  {
    type = "sound",
    name = "arrakis-worm-rumble",
    category = "enemy",
    filename = "__space-age__/sound/enemies/demolisher/demolisher-tail-rumble.ogg",
    volume = 1.0,
    audible_distance_modifier = 4
  },

  -- Brüllen beim Auftauchen (0.8.4).
  {
    type = "sound",
    name = "arrakis-worm-roar",
    category = "enemy",
    variations = surface_roar,
    audible_distance_modifier = 4
  },

  -- Vibrationsanzeige (A23 prototypes.d.ts:8900–8966): löst on_lua_shortcut aus, toggleable für
  -- set_shortcut_toggled; frei mit „Spice-Ernte“. Keine Taste. Hinter den beiden Verknüpfungen aus 3c.
  {
    type = "shortcut",
    name = "arrakis-vibration-overlay",
    order = "e[spidertron-remote]-z[arrakis-c]",
    action = "lua",
    toggleable = true,
    localised_name = {"shortcut-name.arrakis-vibration-overlay"},
    technology_to_unlock = "arrakis-spice-harvesting",
    unavailable_until_unlocked = true,
    icons = {{icon = ALERT_ICON, icon_size = 64, tint = SAND}},
    small_icons = {{icon = ALERT_ICON, icon_size = 64, tint = SAND}}
  },

  -- Briefings (A23 prototypes.d.ts:10410–10474; Muster V23 space-age/prototypes/tips-and-tricks.lua:6–47) in der
  -- Space-Age-Kategorie hinter Aquilo (d-a). Ob Tipps erscheinen, entscheidet das Szenario; die Chatzeilen kommen immer
  -- (scripts/worms.lua). Die Locale-Kategorien der Tipps sind lokal nicht belegt, deshalb stehen die Namen ausdrücklich da.
  {
    type = "tips-and-tricks-item",
    name = "arrakis-briefing",
    localised_name = {"tips-and-tricks-item-name.arrakis-briefing"},
    localised_description = {"tips-and-tricks-item-description.arrakis-briefing"},
    category = "space-age",
    order = "e-a",
    tag = "[planet=arrakis]",
    trigger =
    {
      type = "research",
      technology = "planet-discovery-arrakis"
    }
  },
  {
    type = "tips-and-tricks-item",
    name = "arrakis-wormsign-tip",
    localised_name = {"tips-and-tricks-item-name.arrakis-wormsign-tip"},
    localised_description = {"tips-and-tricks-item-description.arrakis-wormsign-tip"},
    category = "space-age",
    order = "e-b",
    indent = 1,
    tag = "[virtual-signal=arrakis-wormsign]",
    trigger =
    {
      type = "research",
      technology = "arrakis-spice-harvesting"
    }
  }
})
