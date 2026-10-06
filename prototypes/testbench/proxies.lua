-- Prüfstand T4: Spice-Annahme und Tankstutzen als proxy-container (Design 4.1).
-- Ziel (Ernter-Kofferraum bzw. -Treibstoff) setzt das Skript.

local intake_tint = {r = 1, g = 0.6, b = 0.3}
local nozzle_tint = {r = 0.5, g = 0.7, b = 1}

-- Bild der Eisenkiste, skaliert und getönt (Schatten nur skaliert).
local function chest_picture(factor, tint)
  local picture = table.deepcopy(data.raw.container["iron-chest"].picture)
  local layers = picture.layers or {picture}
  for _, layer in pairs(layers) do
    layer.scale = (layer.scale or 1) * factor
    if layer.shift then
      layer.shift = {(layer.shift[1] or layer.shift.x) * factor, (layer.shift[2] or layer.shift.y) * factor}
    end
    if not layer.draw_as_shadow then layer.tint = tint end
  end
  return picture
end

local function make_proxy(name, tint)
  local proxy = table.deepcopy(data.raw["proxy-container"]["proxy-container"])
  proxy.name = name
  proxy.hidden = true
  proxy.icon = nil
  proxy.icons = {{icon = "__base__/graphics/icons/iron-chest.png", tint = tint}}
  proxy.minable = {mining_time = 0.5}
  proxy.fast_replaceable_group = nil
  return proxy
end

-- Annahme: 2×2, darf nur stehen, wenn der ganze Andockkreis (11×11) Fels ist.
-- Schaltungsanschluss wie bei Kisten (von proxy-container übernommen).
local intake = make_proxy("arrakis-test-intake", intake_tint)
intake.collision_box = {{-0.9, -0.9}, {0.9, 0.9}}
intake.selection_box = {{-1, -1}, {1, 1}}
intake.picture = chest_picture(2, intake_tint)
intake.tile_buildability_rules =
{
  {area = {{-5, -5}, {5, 5}}, required_tiles = {layers = {arrakis_rock = true}}}
}

-- Tankstutzen: 1×1, ohne Bauregel.
local nozzle = make_proxy("arrakis-test-nozzle", nozzle_tint)
nozzle.picture = chest_picture(1, nozzle_tint)

data:extend({intake, nozzle})
