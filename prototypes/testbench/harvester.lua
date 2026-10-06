-- Prüfstand T2, T3, T4: Ernter-Fahrzeug, Kopie des Panzers (Design 4.1).
local compat = require("prototypes.compat")

local harvester_tint = {r = 1, g = 0.8, b = 0.5}

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

local harvester = table.deepcopy(data.raw.car.tank)
harvester.name = "arrakis-test-harvester"
harvester.hidden = true
harvester.factoriopedia_simulation = nil
-- Kein Item: Entities entstehen per Skript. Abbauen ergibt nichts.
harvester.minable = {mining_time = 1}
harvester.guns = nil
harvester.inventory_size = 40
harvester.energy_source.fuel_inventory_size = 3
harvester.allow_remote_driving = false
harvester.trash_inventory_size = 0
harvester.equipment_grid = nil
tint_layers(harvester.animation, harvester_tint)
tint_layers(harvester.turret_animation, harvester_tint)

-- Physik, Ziel: Höchsttempo mit Kohle etwa 1,5 Kacheln/s (T2 misst).
-- Schätzung (Modell, nicht belegt): Reibung nimmt je Tick den Anteil f der Geschwindigkeit,
-- der Motor liefert E = consumption/60 · effectivity Joule je Tick. Gleichgewicht bei
-- v² = E / (f · weight), v in Kacheln/s. Gegenprobe Panzer: E = 10 kJ · 0,9 = 9 kJ,
-- f = 0,002 · (1 + 0,8 · 0,2) auf Sand, weight 20000 → v ≈ 14 Kacheln/s ≈ 50 km/h (plausibel).
-- Ernter: E = 5 kJ · 0,9 = 4,5 kJ, f = 0,1, weight 20000 → v² = 2,25 → v ≈ 1,5 Kacheln/s.
-- terrain_friction_modifier = 0: Untergrund spielt keine Rolle, die Schätzung gilt auf jeder Kachel.
-- Hohe Reibung heißt auch: Der Ernter steht nach dem Loslassen fast sofort.
harvester.consumption = "300kW"
harvester.effectivity = 0.9
harvester.weight = 20000
harvester.terrain_friction_modifier = 0
compat.vehicle_physics(harvester, 800 * 1000 / 60, 0.1)

data:extend({harvester})
