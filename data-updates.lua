-- Spice-Wissenschaft in alle Labore aufnehmen, die Metallurgie-Wissenschaft verarbeiten
-- (Labor, Biolabor und Labore anderer Mods).
for _, lab in pairs(data.raw.lab) do
  local inputs = lab.inputs or {}
  local has_metallurgic, has_spice = false, false
  for _, input in pairs(inputs) do
    if input == "metallurgic-science-pack" then has_metallurgic = true end
    if input == "spice-science-pack" then has_spice = true end
  end
  if has_metallurgic and not has_spice then
    table.insert(inputs, "spice-science-pack")
  end
end
