-- Spice-Sand hat die Ressourcenkategorie "arrakis-spice-harvest" (prototypes/harvester.lua).
-- Von Hand bleibt Spice abbaubar: Jede Spielfigur und jeder God-Controller, der basic-solid
-- abbaut, bekommt die Kategorie dazu. Fehlt mining_categories, gilt {"basic-solid"}.
-- Die Liste wird nur ergänzt, nie ersetzt. Bohrer bekommen die Kategorie nicht.
-- In data-final-fixes, damit auch Spielfiguren anderer Mods dabei sind.
local function add_spice_category(prototype)
  local categories = prototype.mining_categories or {"basic-solid"}
  local has_basic, has_spice = false, false
  for _, category in pairs(categories) do
    if category == "basic-solid" then has_basic = true end
    if category == "arrakis-spice-harvest" then has_spice = true end
  end
  if has_basic and not has_spice then
    table.insert(categories, "arrakis-spice-harvest")
    prototype.mining_categories = categories
  end
end

for _, prototype_type in pairs({"character", "god-controller"}) do
  for _, prototype in pairs(data.raw[prototype_type] or {}) do
    add_spice_category(prototype)
  end
end

-- Flugtreibstoff für den Ornithopter (0.9.0, prototypes/ornithopter-speed.lua): Jeder chemische Brennstoff, der in
-- Beschleunigung und Höchsttempo mindestens Raketentreibstoff erreicht, bekommt die Kategorie zusätzlich. chemical bleibt,
-- Autos, Panzer und Kessel nehmen ihn also weiter. In data-final-fixes, damit auch Brennstoffe anderer Mods dabei sind.
-- Erst ab 2.1.20 hat ein Item eine Liste von Kategorien (prototypes/compat.lua); davor bleibt alles, wie es ist.
if require("prototypes.compat").v2120 then
  local speed = require("prototypes.ornithopter-speed")
  local item_types = defines and defines.prototypes and defines.prototypes.item or {item = 0}
  for item_type in pairs(item_types) do
    for _, item in pairs(data.raw[item_type] or {}) do
      local categories = item.fuel_categories
      local chemical, flight = false, false
      for _, category in pairs(categories or {}) do
        if category == "chemical" then chemical = true end
        if category == speed.FUEL_CATEGORY then flight = true end
      end
      if chemical and not flight and speed.flight_fuel(item.fuel_acceleration_multiplier or 1, item.fuel_top_speed_multiplier or 1) then
        table.insert(categories, speed.FUEL_CATEGORY)
      end
    end
  end
end
