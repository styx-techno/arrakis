local planet_map_gen = {}

-- Wüste aus Nauvis-Sand (niedrige Feuchte), dazwischen Felsinseln (arrakis-rock).
-- Grunderze und Tiefenwasser liegen nur auf Fels, Spice nur im offenen Sand.
-- Ausdrücke siehe prototypes/noise.lua.
planet_map_gen.arrakis = function()
  return
  {
    property_expression_names =
    {
      moisture = "arrakis_moisture",
      aux = "arrakis_aux",
      ["entity:iron-ore:probability"] = "arrakis_iron_ore_probability",
      ["entity:iron-ore:richness"] = "arrakis_iron_ore_richness",
      ["entity:copper-ore:probability"] = "arrakis_copper_ore_probability",
      ["entity:copper-ore:richness"] = "arrakis_copper_ore_richness",
      ["entity:stone:probability"] = "arrakis_stone_probability",
      ["entity:stone:richness"] = "arrakis_stone_richness",
      ["entity:coal:probability"] = "arrakis_coal_probability",
      ["entity:coal:richness"] = "arrakis_coal_richness"
    },
    cliff_settings =
    {
      name = "cliff",
      richness = 0
    },
    autoplace_controls =
    {
      ["iron-ore"] = {},
      ["copper-ore"] = {},
      ["stone"] = {},
      ["coal"] = {},
      ["arrakis_spice"] = {},
      ["arrakis_deep_water"] = {}
    },
    autoplace_settings =
    {
      ["tile"] =
      {
        settings =
        {
          ["sand-1"] = {},
          ["sand-2"] = {},
          ["sand-3"] = {},
          ["arrakis-rock"] = {}
        }
      },
      ["entity"] =
      {
        settings =
        {
          ["iron-ore"] = {},
          ["copper-ore"] = {},
          ["stone"] = {},
          ["coal"] = {},
          ["spice-sand"] = {},
          ["arrakis-deep-water"] = {}
        }
      }
    }
  }
end

return planet_map_gen
