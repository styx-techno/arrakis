local planet_map_gen = {}

-- Wüste aus Nauvis-Sand (niedrige Feuchte), dazwischen Felsinseln (arrakis-rock).
-- Grunderze und Tiefenwasser liegen nur auf Fels, Spice nur im offenen Sand.
-- Ausdrücke siehe prototypes/noise.lua.
--
-- Karte 2 (ab 0.5.4) hängt sich nur hier ein: Die Schlüssel aux, tile:… und entity:… zeigen auf die
-- Ausdrücke arrakis_v2_* (Schlüsselform tile:NAME:probability: A23 concepts.d.ts:6993, in Vanilla nicht
-- benutzt; entity:NAME:probability/richness wie bei Vulcanus, FD space-age/prototypes/planet/
-- planet-map-gen.lua:15-22). Eine Oberfläche
-- behält ihre map_gen_settings aus der Zeit ihrer Anlage, alte Spielstände erzeugen also weiter
-- Karte 1 (scripts/migrate.lua meldet das einmal). Die Prototypen (Kachel, Spice, Tiefenwasser) tragen
-- weiter die Ausdrücke von Karte 1.
-- Ab 0.5.5 zeigt Spice-Sand auf arrakis_v3_spice_* (mehr und größere reguläre Felder, prototypes/noise.lua
-- ganz unten). Eine Oberfläche aus 0.5.4 behält arrakis_v2_spice_* und ihre wenigen kleinen Felder, ohne
-- Hinweis im Spiel; V2_KEY/V2_NAME unten erkennen beide als Karte 2.
-- Die Datei greift nicht auf data zu und lässt sich auch im Control-Stage laden.

-- Spice-Regel der Karte 2 (prototypes/noise.lua): "" = Regel B (eingehängt), "_a" = Regel A (Rückfall, wenn
-- T11 Regel B nicht bestätigt). Umgeschaltet wird nur hier: Jede Regel hat eigene Ausdrücke, eine schon
-- angelegte Oberfläche behält die Namen ihrer Regel und bekommt so keine Kanten.
local SPICE_RULE = ""

-- Karte 1 (bis 0.5.3): Kachel, Spice und Tiefenwasser kommen aus den Prototypen.
local function property_names_1()
  return
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
  }
end

-- Karte 2 (ab 0.5.4): Startinsel, Graben, Kegel-Inseln, Lehrfeld, Spice mindestens 100 Kacheln vom Fels.
-- Spice ab 0.5.5 aus arrakis_v3_spice_* (0.5.4: arrakis_v2_spice_*), alles andere arrakis_v2_*.
local function property_names_2()
  return
  {
    moisture = "arrakis_moisture",
    aux = "arrakis_v2_aux",
    ["tile:arrakis-rock:probability"] = "arrakis_v2_rock_tile",
    ["entity:iron-ore:probability"] = "arrakis_v2_iron_ore_probability",
    ["entity:iron-ore:richness"] = "arrakis_v2_iron_ore_richness",
    ["entity:copper-ore:probability"] = "arrakis_v2_copper_ore_probability",
    ["entity:copper-ore:richness"] = "arrakis_v2_copper_ore_richness",
    ["entity:stone:probability"] = "arrakis_v2_stone_probability",
    ["entity:stone:richness"] = "arrakis_v2_stone_richness",
    ["entity:coal:probability"] = "arrakis_v2_coal_probability",
    ["entity:coal:richness"] = "arrakis_v2_coal_richness",
    ["entity:spice-sand:probability"] = "arrakis_v3_spice_probability" .. SPICE_RULE,
    ["entity:spice-sand:richness"] = "arrakis_v3_spice_richness" .. SPICE_RULE,
    ["entity:arrakis-deep-water:probability"] = "arrakis_v2_deep_water_probability",
    ["entity:arrakis-deep-water:richness"] = "arrakis_v2_deep_water_richness"
  }
end

local function settings(property_expression_names)
  return
  {
    property_expression_names = property_expression_names,
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

-- Einstellungen des Planeten Arrakis: Karte 2.
planet_map_gen.arrakis = function()
  return settings(property_names_2())
end

-- Karte 1 wie bis 0.5.3, nur zum Vergleich (etwa für eine Testoberfläche); der Planet nutzt sie nicht mehr.
planet_map_gen.arrakis_v1 = function()
  return settings(property_names_1())
end

-- Daran erkennt man Karte 2 in LuaSurface::map_gen_settings.property_expression_names (scripts/migrate.lua),
-- mit Spice aus 0.5.4 (arrakis_v2_spice_*) wie aus 0.5.5 (arrakis_v3_spice_*).
planet_map_gen.V2_KEY = "tile:arrakis-rock:probability"
planet_map_gen.V2_NAME = "arrakis_v2_rock_tile"

return planet_map_gen
