local planet_map_gen = {}

-- Phase 0: einfache Wüste aus den Nauvis-Sandkacheln, ohne Wasser und ohne Gegner.
-- Feuchte wird niedrig gehalten, damit nur die Sand-Kacheln gewinnen; aux sorgt für Variation.
-- Felsinseln, Spicefelder und eigene Erzverteilung folgen in Phase 1.
planet_map_gen.arrakis = function()
  return
  {
    property_expression_names =
    {
      moisture = "arrakis_moisture",
      aux = "arrakis_aux",
      cliffiness = "0"
    },
    autoplace_controls =
    {
      ["iron-ore"] = {},
      ["copper-ore"] = {},
      ["stone"] = {},
      ["coal"] = {}
    },
    autoplace_settings =
    {
      ["tile"] =
      {
        settings =
        {
          ["sand-1"] = {},
          ["sand-2"] = {},
          ["sand-3"] = {}
        }
      },
      ["entity"] =
      {
        settings =
        {
          ["iron-ore"] = {},
          ["copper-ore"] = {},
          ["stone"] = {},
          ["coal"] = {}
        }
      }
    }
  }
end

data:extend({
  {
    type = "noise-expression",
    name = "arrakis_moisture",
    expression = "0.05"
  },
  {
    type = "noise-expression",
    name = "arrakis_aux",
    expression = "0.3 + 0.25 * multioctave_noise{x = x, y = y, persistence = 0.6, seed0 = map_seed, seed1 = 7101, octaves = 4, input_scale = 1/120}"
  }
})

return planet_map_gen
