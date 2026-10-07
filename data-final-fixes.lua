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
