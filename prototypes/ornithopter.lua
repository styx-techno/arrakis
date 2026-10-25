-- Phase 3c (docs/plan-3c.md 3): Ornithopter mit Bein, Item, Rezept und Forschung „Ornithopter“, zwei Tempo-Sticker,
-- 32 Sprites des Lastbilds (getragener Spice-Ernter und Schatten), Absetz-Probe, Taste und zwei Verknüpfungen.
-- Anheben, Tragen und Absetzen steuert das Skript (scripts/flyer.lua, scripts/hold.lua).
-- 2.0-Schreibweise wie überall; compat.finish (prototypes/compat.lua) schreibt unter 2.1 um. Hier braucht nichts eine
-- Umschreibung: Das Rezept hat keine Kategorie, die Forschung einen craft-item-Trigger, kein Item ist Brennstoff.
-- Grafiken sind getönte Vanilla-Platzhalter wie beim Ernter (prototypes/harvester.lua) und im Prüfstand
-- (prototypes/testbench/flyers.lua); eigene Grafik kommt mit Phase 6.
-- Muss nach prototypes/harvester.lua laufen: Die Probe liest die Kollisionsmaske des Ernters (data.lua).
local collision_mask_util = require("collision-mask-util")

local sand_tint = {r = 1, g = 0.85, b = 0.55}
-- Ernter-Tönung wie prototypes/harvester.lua:8, damit das Lastbild aussieht wie der Ernter am Boden.
local harvester_tint = {r = 1, g = 0.8, b = 0.5}

local function tinted(icon, tint)
  return {{icon = icon, tint = tint}}
end

-- Tönt alle normalen Bildebenen; Schatten, Farbmasken und Leuchten bleiben (Regel wie prototypes/testbench/flyers.lua:7–15).
local function tint_layers(animation, tint)
  if type(animation) ~= "table" then return end
  if animation.layers then
    for _, layer in pairs(animation.layers) do tint_layers(layer, tint) end
    return
  end
  if animation.draw_as_shadow or animation.apply_runtime_tint or animation.draw_as_glow or animation.draw_as_light then return end
  animation.tint = tint
end

-- Bein: Kopie eines Spidertron-Beins ohne Grafik (graphics_set ist optional), ohne Geräusche, ohne Kollision.
-- Bewusst eine Kopie von make_leg(name, 1) aus prototypes/testbench/flyers.lua:19–33 (Plan 3): Die Test-Prototypen
-- gibt es nur mit Prüfstand, und T1 misst weiter die alten Prüflinge. Faktor 1 heißt: Bewegungswerte wie Vanilla
-- (0,06 Start, 0,03 Beschleunigung), der in T1 gemessene Prüfling. Der Carryall (3e) kann das Bein mitbenutzen.
local function make_leg(name)
  local leg = table.deepcopy(data.raw["spider-leg"]["spidertron-leg-1"])
  leg.name = name
  leg.localised_name = nil
  leg.hidden = true
  leg.graphics_set = nil
  leg.working_sound = nil
  leg.walking_sound_volume_modifier = 0
  leg.upper_leg_dying_trigger_effects = nil
  leg.lower_leg_dying_trigger_effects = nil
  leg.collision_mask = {layers = {}}
  return leg
end

local spidertron = data.raw["spider-vehicle"]["spidertron"]
local vanilla_legs = spidertron.spider_engine.legs

-- Beinposition aus Vanilla-Bein Nr. index übernehmen (ohne Bodenstaub-Trigger), wie prototypes/testbench/flyers.lua:39–48.
local function vanilla_leg(leg_name, index, walking_group)
  local source = vanilla_legs[index]
  return
  {
    leg = leg_name,
    mount_position = table.deepcopy(source.mount_position),
    ground_position = table.deepcopy(source.ground_position),
    walking_group = walking_group
  }
end

-- Ornithopter: Kopie des Spidertrons, Flug wie der T1-Prüfling arrakis-test-flyer-4 (prototypes/testbench/flyers.lua:72–105).
-- Geerbt und so gewollt: max_health 3000, Resistenzen, corpse, dying_explosion, is_military_target, Kollision ±1,
-- sticker_box ±1,5 und surface_conditions (Schwerkraft ≥ 1; setzt Space Age schon in seiner data.lua,
-- V23 space-age/base-data-updates.lua:192, also vor dieser Datei). collision_mask bleibt ungesetzt: Vorgabe nur
-- trigger_target (V23 core/lualib/collision-mask-defaults.lua:190), der Ernter fährt darunter durch [U21].
local ornithopter = table.deepcopy(spidertron)
ornithopter.name = "arrakis-ornithopter"
ornithopter.icon = nil
ornithopter.icons = tinted("__base__/graphics/icons/spidertron.png", sand_tint)
ornithopter.minable = {mining_time = 1, result = "arrakis-ornithopter"}
ornithopter.factoriopedia_simulation = nil
ornithopter.guns = nil
ornithopter.equipment_grid = nil
-- 0: kein Logistik-Tab (A23 prototypes.d.ts:9595).
ornithopter.trash_inventory_size = 0
ornithopter.inventory_size = 10
-- Kartiert im Vorbeiflug 2 Chunks um sich (Spidertron 3).
ornithopter.chunk_exploration_radius = 2
-- Fernfahren aus der Karte für die Rettung (Plan 1 „Fernfahren“); der Ernter bleibt false (prototypes/harvester.lua:66).
ornithopter.allow_remote_driving = true
-- Ruhiger als der Spidertron (Optik prüft Max in T17).
ornithopter.torso_bob_speed = 0.4
-- Flughöhe 3 (Spidertron 1,5). "tall" wird bewusst nicht gesetzt (2.1: sonst im Modus „Hohe Objekte ausblenden“
-- nicht anwählbar, DOC 4.2).
ornithopter.height = 3
ornithopter.alert_icon_shift = {0, -3}
ornithopter.drawing_box_vertical_extension = 4
-- Die Engine verbraucht den Treibstoff selbst (Spidertron: void). RUN055 T1: Leistung konstant ≈ 810 kW, mit oder ohne
-- Sticker. Also 800 kW / 8 Kacheln/s = 100 kJ/Kachel leer und / 5,6 = 143 kJ beladen: Last kostet von selbst mehr, das
-- Skript zieht nichts ab (Plan 1). 100 Kohle (400 MJ) reichen 500 s Flug.
ornithopter.energy_source =
{
  type = "burner",
  fuel_categories = {"chemical"},
  effectivity = 1,
  fuel_inventory_size = 2
}
ornithopter.movement_energy_consumption = "800kW"
-- Oberteil über allem am Boden. base_render_layer bleibt (higher-object-above, schon über Gebäuden), damit das
-- Unterteil unter dem Oberteil gezeichnet wird. Das Lastbild liegt darunter auf "smoke" (Plan 4.12).
ornithopter.graphics_set.render_layer = "air-object"
tint_layers(ornithopter.graphics_set.base_animation, sand_tint)
tint_layers(ornithopter.graphics_set.animation, sand_tint)
-- 4 Beine im Trab wie der T1-Prüfling (prototypes/testbench/flyers.lua:67–69): Vanilla 1 und 8 zusammen, 5 und 4
-- zusammen. Laufgruppen beginnen bei 1 und sind lückenlos. Die Positionen drehen nicht mit der Flugrichtung
-- (flyers.lua:51–53); T16 misst N und S deshalb getrennt.
ornithopter.spider_engine.legs =
{
  vanilla_leg("arrakis-flyer-leg", 1, 1),
  vanilla_leg("arrakis-flyer-leg", 8, 1),
  vanilla_leg("arrakis-flyer-leg", 5, 2),
  vanilla_leg("arrakis-flyer-leg", 4, 2)
}

-- Item: Kopie des Spidertron-Items (Gewicht 1 t und Geräusche bleiben). Die icon_tintable*-Felder müssen weg: Der
-- Spidertron bringt icon_tintable und icon_tintable_mask mit (V23 base/prototypes/item.lua:2117–2118), und ein Item mit
-- gespeicherter Farbe zeigte sonst das getönte Spidertron-Bild statt des Ornithopters (A23 prototypes.d.ts:5330–5356).
local item = table.deepcopy(data.raw["item-with-entity-data"]["spidertron"])
item.name = "arrakis-ornithopter"
item.icon = nil
item.icons = ornithopter.icons
for _, key in pairs({"icon_tintable", "icon_tintable_mask", "icon_tintable_size", "icon_tintable_mask_size",
  "icon_tintables", "icon_tintable_masks"}) do
  item[key] = nil
end
item.place_result = "arrakis-ornithopter"
item.subgroup = "transport"
-- Direkt nach dem Ernter (b[personal-transport]-z[spice-harvester], prototypes/harvester.lua:113).
item.order = "b[personal-transport]-z[spice-ornithopter]"
item.stack_size = 1
item.default_import_location = "arrakis"

-- Tempo-Sticker (Plan 1 „Drossel“, 4.9). Genau einer hängt am Flieger; das Skript tauscht ihn beim Anheben und Absetzen.
-- RUN055 T1: 15,4 Kacheln/s ohne Sticker, 10,8 mit vehicle_speed_modifier = 0,7 (70,1 %). Daraus leer 0,52 = 8 / 15,4
-- → 8,0 Kacheln/s, beladen 0,364 = 0,7 · 0,52 → 5,6 [U6]. Wie der T1-Sticker (prototypes/testbench/flyers.lua:114–122),
-- ohne Animation. Dauer 1 h = 216 000 Ticks; die Pflege heftet ab time_to_live < 108 000 einen neuen an (Plan 4.9).
local function speed_sticker(name, modifier)
  return
  {
    type = "sticker",
    name = name,
    hidden = true,
    flags = {"not-on-map"},
    duration_in_ticks = 60 * 60 * 60,
    vehicle_speed_modifier = modifier
  }
end

-- Lastbild: 16 Richtungen aus den Panzer-Sheets (V23 base/prototypes/entity/entities.lua:8079–8222), Rumpf und Turm
-- in derselben Richtung. i = 0 … 15 nimmt d = 4 · i der 64 Panzerrichtungen (0 = Nord, im Uhrzeigersinn).
-- Rumpf: je Datei 16 Richtungen untereinander, je Zeile 2 Bilder (stripes width_in_frames = 2, height_in_frames = 16),
--   also tank-base-<floor(d/16)+1>.png, erstes Bild x = 0, y = (d mod 16) · 212; shift = by_pixel(0, -16 + tank_shift_y)
--   mit tank_shift_y = 6 (entities.lua:43).
-- Turm: line_length = 8, also x = (d mod 8) · 179, y = floor(d/8) · 132; shift = by_pixel(2,25 - 2, -40,5 + 6).
-- Beide getönt wie der Ernter. Die Farbmaske (apply_runtime_tint) fehlt bewusst: Ein Sprite kennt die Farbe des
-- Ernters nicht.
-- Schatten: tank-base-shadow-<n>.png mit 1 Bild je Zeile (util.multiplystripes(2, …) wiederholt nur die Datei),
--   y = (d mod 16) · 194, shift = by_pixel(22,5, 1 + 6); tank-turret-shadow.png, x = (d mod 8) · 193,
--   y = floor(d/8) · 134, shift = by_pixel(58,25 - 2, 0,5 + 6); beide draw_as_shadow, ungetönt.
-- Alle Ebenen sind HR-Bilder mit scale = 0.5 wie Vanilla (entities.lua:8179, :8218). Ohne Angabe gälte 1, und der
-- Schatten würde doppelt so groß wie das Lastbild. Die Richtung wählt das Skript beim Anheben (Plan 4.12).
local tank = "__base__/graphics/entity/tank/"

local function carried_sprites(i)
  local d = 4 * i
  local sheet = math.floor(d / 16) + 1
  local image =
  {
    type = "sprite",
    name = "arrakis-harvester-carried-" .. i,
    layers =
    {
      {
        filename = tank .. "tank-base-" .. sheet .. ".png",
        x = 0,
        y = (d % 16) * 212,
        width = 270,
        height = 212,
        scale = 0.5,
        shift = util.by_pixel(0, -10),
        tint = harvester_tint
      },
      {
        filename = tank .. "tank-turret.png",
        x = (d % 8) * 179,
        y = math.floor(d / 8) * 132,
        width = 179,
        height = 132,
        scale = 0.5,
        shift = util.by_pixel(0.25, -34.5),
        tint = harvester_tint
      }
    }
  }
  local shadow =
  {
    type = "sprite",
    name = "arrakis-harvester-carried-shadow-" .. i,
    layers =
    {
      {
        filename = tank .. "tank-base-shadow-" .. sheet .. ".png",
        x = 0,
        y = (d % 16) * 194,
        width = 302,
        height = 194,
        scale = 0.5,
        shift = util.by_pixel(22.5, 7),
        draw_as_shadow = true
      },
      {
        filename = tank .. "tank-turret-shadow.png",
        x = (d % 8) * 193,
        y = math.floor(d / 8) * 134,
        width = 193,
        height = 134,
        scale = 0.5,
        shift = util.by_pixel(56.25, 6.5),
        draw_as_shadow = true
      }
    }
  }
  return image, shadow
end

-- Absetz-Probe: wird nie gebaut, nur mit can_place_entity und find_non_colliding_position abgefragt (Plan 4.8, 4.10).
-- Der Kasten ±1,6 deckt den Ernter in jeder Ausrichtung: Panzer-Kasten ±0,9 × ±1,3 (V23 entities.lua:7999), halbe
-- Diagonale √(0,9² + 1,3²) = 1,58. Maske: Kopie der des Ernters; der hat keine eigene, es gilt die Auto-Vorgabe
-- player, car, train, is_object mit consider_tile_transitions (collision-mask-defaults.lua:174). get_mask gibt eine
-- gesetzte Maske ohne Kopie zurück, deshalb deepcopy (wie prototypes/testbench/worms.lua:81).
local probe = table.deepcopy(data.raw["simple-entity-with-owner"]["simple-entity-with-owner"])
probe.name = "arrakis-harvester-probe"
probe.hidden = true
probe.flags = {"not-on-map", "placeable-off-grid", "not-blueprintable", "not-deconstructable"}
probe.minable = nil
probe.collision_box = {{-1.6, -1.6}, {1.6, 1.6}}
probe.collision_mask = table.deepcopy(collision_mask_util.get_mask(data.raw.car["spice-harvester"]))

data:extend({
  make_leg("arrakis-flyer-leg"),
  ornithopter,
  item,
  {
    type = "recipe",
    name = "arrakis-ornithopter",
    enabled = false,
    energy_required = 10,
    ingredients =
    {
      {type = "item", name = "steel-plate", amount = 30},
      {type = "item", name = "engine-unit", amount = 20},
      {type = "item", name = "advanced-circuit", amount = 10},
      {type = "item", name = "melange", amount = 10}
    },
    results = {{type = "item", name = "arrakis-ornithopter", amount = 1}}
  },

  -- Forschung „Ornithopter“ (Plan 4.14): erforscht, sobald die Force den ersten Spice-Ernter herstellt, von Hand oder
  -- in einer Maschine [U11] (A23 types.d.ts:3373–3377). „Spice-Ernte“ schaltet das Ernter-Rezept frei, der Trigger kommt
  -- also nie zu früh. Keine Paketkosten. Alte Spielstände holt scripts/migrate.lua nach (Plan 4.15) [U12].
  -- Die beiden Verknüpfungen hängen über technology_to_unlock an ihr.
  {
    type = "technology",
    name = "arrakis-ornithopter",
    icons = {{icon = "__base__/graphics/technology/spidertron.png", icon_size = 256, tint = sand_tint}},
    effects =
    {
      {type = "unlock-recipe", recipe = "arrakis-ornithopter"}
    },
    prerequisites = {"arrakis-spice-harvesting"},
    research_trigger =
    {
      type = "craft-item",
      item = "spice-harvester",
      count = 1
    }
  },

  speed_sticker("arrakis-ornithopter-empty", 0.52),
  speed_sticker("arrakis-ornithopter-loaded", 0.364)
})

local sprites = {}
for i = 0, 15 do
  local image, shadow = carried_sprites(i)
  table.insert(sprites, image)
  table.insert(sprites, shadow)
end
data:extend(sprites)

-- Fernbedienung: Die Engine legt eine spidertron-remote in die Hand, schon mit „Ornithopter“. Der Vanilla-Shortcut
-- kommt erst mit „Spidertron“ (V23 base/prototypes/shortcuts.lua:222–235; T12 in docs/pruefstand.md) [U5].
-- associated_control_input = nil: Die Vanilla-Taste give-spidertron-remote gehört zum Vanilla-Shortcut.
local remote = table.deepcopy(data.raw.shortcut["give-spidertron-remote"])
remote.name = "arrakis-give-remote"
remote.order = "e[spidertron-remote]-z[arrakis-b]"
remote.localised_name = {"shortcut-name.arrakis-give-remote"}
remote.associated_control_input = nil
remote.technology_to_unlock = "arrakis-ornithopter"

data:extend({
  probe,

  -- Taste: Anheben, Abbrechen, Absetzen (Plan 4.5). Nie der einzige Weg: ALT + O kam in T12 nie an (ERG), deshalb
  -- gibt es dieselbe Funktion als Verknüpfung und als Knopf im Ornithopter-Fenster. consuming = "none" wie
  -- arrakis-harvester-toggle (prototypes/harvester.lua:244–249) [U1].
  {
    type = "custom-input",
    name = "arrakis-carry-toggle",
    key_sequence = "SHIFT + C",
    consuming = "none"
  },

  -- Verknüpfungen (Muster V23 base/prototypes/shortcuts.lua:222–235). Die Locale-Kategorie der Shortcuts ist lokal nicht
  -- belegt, deshalb steht localised_name ausdrücklich da. arrakis-carry löst on_lua_shortcut aus und tut dasselbe wie
  -- die Taste; associated_control_input zeigt nur die Taste im Tooltip. Geht auch in der Kartenansicht.
  {
    type = "shortcut",
    name = "arrakis-carry",
    order = "e[spidertron-remote]-z[arrakis-a]",
    action = "lua",
    localised_name = {"shortcut-name.arrakis-carry"},
    associated_control_input = "arrakis-carry-toggle",
    technology_to_unlock = "arrakis-ornithopter",
    unavailable_until_unlocked = true,
    icons = {{icon = "__base__/graphics/icons/tank.png", icon_size = 64, tint = harvester_tint}},
    small_icons = {{icon = "__base__/graphics/icons/tank.png", icon_size = 64, tint = harvester_tint}}
  },
  remote
})
