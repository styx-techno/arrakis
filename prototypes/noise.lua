-- Kartengenerierung für Arrakis.
-- arrakis_rock > 0 bedeutet Fels (sichere Bauinsel), < 0 offener Sand (Wurmgebiet, Spice).
-- Der Startpunkt liegt immer auf einer Felsinsel mit allen Grunderzen und einem Tiefenbrunnen.
--
-- Zwei Karten (0.5.4):
--   Karte 1 (bis 0.5.3): die Ausdrücke arrakis_* ohne v2. Sie stehen in den Prototypen (Kacheln, Spice,
--     Tiefenwasser) und in den gespeicherten map_gen_settings alter Spielstände und bleiben deshalb
--     unverändert, sonst bekäme eine alte Oberfläche Kanten zwischen alten und neuen Chunks.
--   Karte 2 (ab 0.5.4): die Ausdrücke arrakis_v2_* weiter unten. Eingehängt nur über
--     property_expression_names des Planeten (prototypes/planet/planet-map-gen.lua), gilt also erst
--     für eine neu angelegte Oberfläche.

-- Fels-Ausdrücke je Karte: Namenspräfix, Gunst für Erz- und Brunnenflecken, Bedingung „auf Fels“.
-- Karte 2 verlangt 0,005 Abstand zur Felskante: Dort ist die Kachel nach der steilen Felsregel sicher Fels.
-- keep_clear (nur Karte 2): Erz bleibt dem Start-Brunnen fern (arrakis_v2_well_clear).
local MAP_1 = {prefix = "arrakis_", rock_favorability = "arrakis_rock_favorability", on_rock = "arrakis_rock > 0"}
local MAP_2 = {prefix = "arrakis_v2_", rock_favorability = "arrakis_v2_rock_favorability", on_rock = "arrakis_v2_rock > 0.005",
               keep_clear = "arrakis_v2_well_clear"}

local function ore(map, name, control, seed, base, angle, start_distance, start_radius, spacing)
  return
  {
    {
      type = "noise-expression",
      name = map.prefix .. name .. "_richness",
      expression = base .. " * max(starting, arrakis_spot(" .. seed .. ", " .. start_radius .. " * size ^ 0.5, " .. spacing .. " / frequency ^ 0.5, " .. map.rock_favorability .. ")) * richness / size",
      local_expressions =
      {
        richness = "var('control:" .. control .. ":richness')",
        frequency = "var('control:" .. control .. ":frequency')",
        size = "var('control:" .. control .. ":size')",
        starting = "starting_spot_at_angle{angle = arrakis_starting_angle + " .. angle .. ", distance = " .. start_distance .. ", radius = " .. start_radius .. " * size ^ 0.5, x_distortion = arrakis_wobble_x * " .. start_radius .. " * 0.7, y_distortion = arrakis_wobble_y * " .. start_radius .. " * 0.7}"
      }
    },
    {
      type = "noise-expression",
      name = map.prefix .. name .. "_probability",
      expression = "(var('control:" .. control .. ":size') > 0) * (" .. map.prefix .. name .. "_richness > 1) * (" .. map.on_rock .. ")"
                   .. (map.keep_clear and (" * " .. map.keep_clear) or "")
    }
  }
end

data:extend({
  {
    type = "noise-expression",
    name = "arrakis_starting_angle",
    expression = "map_seed_normalized * 360"
  },
  {
    -- Verzerrung, damit Startfelder nicht kreisrund sind.
    type = "noise-expression",
    name = "arrakis_wobble_x",
    expression = "multioctave_noise{x = x, y = y, persistence = 0.5, seed0 = map_seed, seed1 = 7601, octaves = 3, input_scale = 1/12}"
  },
  {
    type = "noise-expression",
    name = "arrakis_wobble_y",
    expression = "multioctave_noise{x = x, y = y, persistence = 0.5, seed0 = map_seed, seed1 = 7602, octaves = 3, input_scale = 1/12}"
  },
  {
    type = "noise-expression",
    name = "arrakis_rock_noise",
    expression = "multioctave_noise{x = x, y = y, persistence = 0.55, seed0 = map_seed, seed1 = 7201, octaves = 5, input_scale = 1/220} - 0.35"
  },
  {
    -- Startinsel: Radius etwa 55 bis 95 Felder um den Startpunkt, mit ausgefranstem Rand.
    type = "noise-expression",
    name = "arrakis_rock",
    expression = "max(arrakis_rock_noise, 0.5 - distance / 150 + 0.15 * arrakis_island_edge)"
  },
  {
    type = "noise-expression",
    name = "arrakis_island_edge",
    expression = "multioctave_noise{x = x, y = y, persistence = 0.6, seed0 = map_seed, seed1 = 7203, octaves = 4, input_scale = 1/40}"
  },
  {
    type = "noise-expression",
    name = "arrakis_rock_favorability",
    expression = "clamp(arrakis_rock * 6, 0, 1)"
  },
  {
    type = "noise-expression",
    name = "arrakis_sand_favorability",
    expression = "clamp(-arrakis_rock * 6, 0, 1)"
  },
  {
    type = "noise-expression",
    name = "arrakis_moisture",
    expression = "0.05"
  },
  {
    type = "noise-expression",
    name = "arrakis_aux",
    expression = "0.3 + 0.25 * multioctave_noise{x = x, y = y, persistence = 0.6, seed0 = map_seed, seed1 = 7101, octaves = 4, input_scale = 1/120}"
  },
  {
    type = "noise-function",
    name = "arrakis_spot",
    parameters = {"seed1", "radius", "spacing", "favorability"},
    expression = "spot_noise{x = x + arrakis_wobble_x * 0.5 * radius,\z
                             y = y + arrakis_wobble_y * 0.5 * radius,\z
                             seed0 = map_seed,\z
                             seed1 = seed1,\z
                             skip_span = 1,\z
                             skip_offset = 1,\z
                             region_size = spacing * 5,\z
                             density_expression = favorability,\z
                             spot_favorability_expression = favorability,\z
                             candidate_spot_count = 22,\z
                             suggested_minimum_candidate_point_spacing = spacing,\z
                             spot_quantity_expression = radius * radius,\z
                             spot_radius_expression = radius,\z
                             hard_region_target_quantity = 0,\z
                             basement_value = -1,\z
                             maximum_spot_basement_radius = radius * 2}"
  },

  -- Spice: nur im offenen Sand. Ein garantiertes Feld außerhalb der Startinsel.
  {
    type = "noise-expression",
    name = "arrakis_spice_richness",
    expression = "6000 * max(starting, arrakis_spot(7301, 14 * size ^ 0.5, 250 / frequency ^ 0.5, arrakis_sand_favorability)) * richness",
    local_expressions =
    {
      richness = "var('control:arrakis_spice:richness')",
      frequency = "var('control:arrakis_spice:frequency')",
      size = "var('control:arrakis_spice:size')",
      starting = "starting_spot_at_angle{angle = arrakis_starting_angle + 135, distance = 150, radius = 14 * size ^ 0.5, x_distortion = arrakis_wobble_x * 10, y_distortion = arrakis_wobble_y * 10}"
    }
  },
  {
    type = "noise-expression",
    name = "arrakis_spice_probability",
    expression = "(var('control:arrakis_spice:size') > 0) * (arrakis_spice_richness > 1) * (arrakis_rock < 0)"
  },

  -- Tiefenwasser: seltene Brunnen unter Fels, einer davon auf der Startinsel.
  {
    type = "noise-expression",
    name = "arrakis_deep_water_spot",
    expression = "max(starting, arrakis_spot(7401, 6 * size ^ 0.5, 300 / frequency ^ 0.5, arrakis_rock_favorability))",
    local_expressions =
    {
      frequency = "var('control:arrakis_deep_water:frequency')",
      size = "var('control:arrakis_deep_water:size')",
      starting = "starting_spot_at_angle{angle = arrakis_starting_angle + 225, distance = 45, radius = 6 * size ^ 0.5, x_distortion = 0, y_distortion = 0}"
    }
  },
  {
    type = "noise-expression",
    name = "arrakis_deep_water_probability",
    expression = "(var('control:arrakis_deep_water:size') > 0) * (arrakis_deep_water_spot > 0) * (arrakis_rock > 0) * 0.04"
  },
  {
    type = "noise-expression",
    name = "arrakis_deep_water_richness",
    expression = "(150000 + 300000 * arrakis_deep_water_spot) * var('control:arrakis_deep_water:richness')"
  }
})

-- Grunderze, nur auf Fels. Startfelder im Kreis um den Startpunkt. Karte 1 und Karte 2 gleich bis auf den Fels.
for _, map in ipairs({MAP_1, MAP_2}) do
  data:extend(ore(map, "iron_ore",   "iron-ore",   7501, 150000, 0,   35, 10, 220))
  data:extend(ore(map, "copper_ore", "copper-ore", 7502, 120000, 90,  35, 9,  240))
  data:extend(ore(map, "stone",      "stone",      7503, 60000,  180, 35, 7,  260))
  data:extend(ore(map, "coal",       "coal",       7504, 80000,  270, 35, 8,  260))
end


-- Karte 2 (0.5.4) ------------------------------------------------------------------------------------
-- Nach der T11-Empfehlung vom 25.10.2026 (Prüfstand-Lauf mit 0.5.3, Kandidat c4 mit Felsschwelle 0):
--   Fels: Kegel-Inseln (c4) ab 220 Kacheln vom Start (Graben) und die Startinsel (Radius 90 ± 22,5).
--   Spice: reguläre Felder nur, wo jeder Fels mindestens 100 Kacheln weg ist, dazu das Lehrfeld
--   41–59 Kacheln vom Inselrand. Beides folgt aus festen Zahlen, nicht aus dem Seed.
-- T11 misst die Spice-Regel auf dem Raster, T14 prüft die erzeugte Karte auf Kacheln.
-- Eine Oberfläche behält die Ausdrucksnamen aus der Zeit ihrer Anlage, die Ausdrücke selbst kommen aber aus
-- den aktuellen Prototypen (A23 concepts.d.ts:6987-6993). Ist 0.5.4 einmal veröffentlicht, darf sich deshalb
-- kein Ausdruck arrakis_v2_* mehr ändern, sonst bekäme eine Karte-2-Oberfläche Kanten; eine Änderung
-- braucht dann neue Namen (arrakis_v3_*). Darum hat auch Regel A eigene Spice-Ausdrücke (…_a).

-- Richtung des Lehrfelds (wie das Spice-Startfeld der Karte 1).
local LEHR_ANGLE = "arrakis_starting_angle + 135"

-- c4: bis zu 9 Kegel je 1024 × 1024 Kacheln, Parameter wie arrakis_t11_c4 (prototypes/testbench/noise.lua).
-- Ein Kegel hat die Menge 90² und den Radius 90, also die Höhe h = 3 · 90² / (π · 90²) = 0,955. Er fällt
-- um h / 90 = 0,0106 je Kachel bis zum Sockel −3 (nach 373 Kacheln, innerhalb maximum_spot_basement_radius).
-- Verzerrter und unverzerrter Aufruf unterscheiden sich nur in x und y; mit Dichte und Gunst 1 setzen
-- beide dieselben Kegelmitten. Seit 2.1.7 legt die Engine spot_noise mit verschiedenen inneren
-- Ausdrücken nicht mehr zusammen (FD changelog.txt:1236).
local function cones(x, y)
  return "spot_noise{x = " .. x .. ", y = " .. y .. ", seed0 = map_seed, seed1 = 7241,\z
                     candidate_spot_count = 9,\z
                     suggested_minimum_candidate_point_spacing = 300,\z
                     skip_span = 1,\z
                     skip_offset = 0,\z
                     region_size = 1024,\z
                     density_expression = 1,\z
                     spot_quantity_expression = 90 * 90,\z
                     spot_radius_expression = 90,\z
                     hard_region_target_quantity = 0,\z
                     spot_favorability_expression = 1,\z
                     basement_value = -3,\z
                     maximum_spot_basement_radius = 400}"
end

data:extend({
  {
    -- Verzerrte Koordinaten für die Inseln (wie arrakis_t11_wx/wy: Maßstab 80 Kacheln), aber je Achse hart
    -- auf ±25 Kacheln begrenzt. Die Grenze trägt die Abstandsrechnung bei arrakis_v2_spice_zone.
    type = "noise-expression",
    name = "arrakis_v2_wx",
    expression = "x + clamp(basis_noise{x = x, y = y, seed0 = map_seed, seed1 = 7251, input_scale = 1 / 80, output_scale = 25}, -25, 25)"
  },
  {
    type = "noise-expression",
    name = "arrakis_v2_wy",
    expression = "y + clamp(basis_noise{x = x, y = y, seed0 = map_seed, seed1 = 7252, input_scale = 1 / 80, output_scale = 25}, -25, 25)"
  },
  {
    -- Kegel-Inseln, Fels bei > 0 (Felsschwelle 0).
    type = "noise-expression",
    name = "arrakis_v2_c4",
    expression = cones("arrakis_v2_wx", "arrakis_v2_wy")
  },
  {
    -- Dieselben Kegel ohne Verzerrung: misst den Abstand zur nächsten Kegelmitte (nur für Spice).
    type = "noise-expression",
    name = "arrakis_v2_c4u",
    expression = cones("x", "y")
  },
  {
    -- 1 auf dem Inselrand in Richtung Lehrfeld (bis ±25,7° um die Achse), 0 ab ±52,8°: Ein Randpunkt bei 90
    -- und Winkel θ liegt 2 · 90 · sin(θ/2) von der Maskenmitte, 1 gilt bis 40, 0 ab 80.
    -- starting_spot_at_angle ist 1 − Abstand / Radius vom Punkt relativ zum Start (FD
    -- core/prototypes/noise-functions.lua:32-43), mit clamp als Maske wie vulcanus_starting_volcano_spot
    -- (FD space-age/prototypes/planet/planet-vulcanus-map-gen.lua:343).
    type = "noise-expression",
    name = "arrakis_v2_lehr_mask",
    expression = "clamp(2 * starting_spot_at_angle{angle = " .. LEHR_ANGLE .. ", distance = 90, radius = 80, x_distortion = 0, y_distortion = 0}, 0, 1)"
  },
  {
    -- Startinsel: Rand bei 90 ± 22,5 Kacheln (Randrauschen auf ±1 begrenzt, in Karte 1 schwankt der Rand
    -- um bis zu ±50), zum Lehrfeld hin fest bei 90. Ursprung, Erz-Startfelder (35 + 10) und der
    -- Start-Brunnen (45 + 6) liegen damit bei Standardgröße immer auf Fels.
    type = "noise-expression",
    name = "arrakis_v2_island",
    expression = "0.6 - distance / 150 + 0.15 * clamp(arrakis_island_edge, -1, 1) * (1 - arrakis_v2_lehr_mask)"
  },
  {
    -- Fels > 0. Graben: c4-Fels erst ab 220 Kacheln vom Start. Die nächste Insel liegt so mindestens
    -- 107,5 Kacheln vom Startinselrand und 71 von jeder Lehrfeld-Kachel.
    type = "noise-expression",
    name = "arrakis_v2_rock",
    expression = "max(min(arrakis_v2_c4, (distance - 220) / 150), arrakis_v2_island)"
  },
  {
    type = "noise-expression",
    name = "arrakis_v2_rock_favorability",
    expression = "clamp(arrakis_v2_rock * 6, 0, 1)"
  },
  {
    -- Steile Felsregel für die Kachel arrakis-rock (Karte 1: 1 + 20 · arrakis_rock, Kante bis etwa
    -- 50 Kacheln neben rock = 0). Die Sandkacheln erreichen höchstens 1 + noise_layer_noise, das Rauschen
    -- liegt bei etwa ±1,7 (FD core/prototypes/noise-functions.lua:64-69). Fels und Sand sind sich also nur
    -- bei |rock| < 0,0017 uneins, das sind weniger als 0,3 Kacheln. expression_in_range ist eingebaut und
    -- lokal nicht beschrieben; hat eine Sandsorte am Rand ihres Bereichs 0 statt 1, sind es |rock| < 0,0027,
    -- also weniger als eine halbe Kachel. Die Abstände 0,005 bei Erz und Spice (Tiefenwasser 0,03) decken
    -- beides.
    type = "noise-expression",
    name = "arrakis_v2_rock_tile",
    expression = "1 + 1000 * arrakis_v2_rock"
  },
  {
    -- aux höchstens 0,39: Bei Feuchte 0,05 liegt dann immer eine Sandsorte im Bereich (sand-1 bis 0,25,
    -- sand-2 bis 0,3, sand-3 bis 0,4), und der zweite Term von sand-1 (ab aux 0,5) bleibt unter 0
    -- (FD base/prototypes/tile/tiles.lua:1710-1712, :1745-1746, :1779-1780). Darüber fielen alle Sandsorten
    -- mit Steigung 20, und die Felskante wäre nicht mehr steil.
    type = "noise-expression",
    name = "arrakis_v2_aux",
    expression = "min(arrakis_aux, 0.39)"
  },

  -- Spice: reguläre Felder in der Spicezone, dazu das Lehrfeld.
  {
    -- Regel B (eingehängt): 1 = reguläres Spice erlaubt. Nur wo der unverzerrte Kegel unter −1,46 liegt
    -- und mehr als 215 Kacheln vom Start. Rechnung (T11-Empfehlung 5.2):
    --   Eine c4-Felskachel q liegt verzerrt näher als 90 an einer Kegelmitte c. Die Verzerrung verschiebt
    --   um höchstens √2 · 25 = 35,4, also |q − c| < 125,4.
    --   c4u < −1,46 heißt: Jede Kegelmitte liegt mindestens 90 · (1 + 1,46 / 0,955) = 227,6 Kacheln weg.
    --   Jede c4-Felskachel liegt also mindestens 227,6 − 125,4 = 102,2 Kacheln von jeder Spice-Kachel.
    --   Startinsel: Rand höchstens 112,5, plus 102,5 ergibt 215.
    -- Allgemein −1,46 = F − (h / 90) · (√2 · 25 + 102) mit Felsschwelle F = 0; die 2 Kacheln über 100 decken
    -- die Felskante der steilen Regel. Die Annahmen (spot_noise ist das Maximum linearer Kegel, beide
    -- Aufrufe haben dieselben Mitten, clamp begrenzt) prüft T11 („Kegel“: t100 von c4u mindestens −1,53).
    type = "noise-expression",
    name = "arrakis_v2_spice_zone",
    expression = "(arrakis_v2_c4u < -1.46) * (distance > 215)"
  },
  {
    -- Regel A (Rückfall, nicht eingehängt, siehe SPICE_RULE in planet-map-gen.lua): verzerrtes c4 unter −2,10.
    -- Das ist das kleinste gemessene t100 aller c4-Stufen (−1,994, R053:333) minus 0,10 Rasterzuschlag. Die Zone
    -- ist etwa ein Viertel so groß wie bei Regel B.
    type = "noise-expression",
    name = "arrakis_v2_spice_zone_a",
    expression = "(arrakis_v2_c4 < -2.1) * (distance > 215)"
  },
  {
    -- Gunst der regulären Fleckmitten: > 0 erst 0,3 unter der Grenze von Regel B (etwa 28 Kacheln tiefer:
    -- Fleckradius 14 plus Wobble bis etwa 16, arrakis_spot) und ab 245 Kacheln vom Start. So werden Felder
    -- am Zonenrand selten angeschnitten; den Abstand hält die Zone ohnehin.
    type = "noise-expression",
    name = "arrakis_v2_spice_favorability",
    expression = "clamp((-1.76 - arrakis_v2_c4u) * 10, 0, 1) * (distance > 245)"
  },
  {
    -- Lehrfeld: runder Fleck mit Radius 9, Mitte 140 Kacheln vom Start, ohne Verzerrung. > 0 im Lehrfeld,
    -- 1 in der Mitte. Seine Kacheln liegen 131–149 Kacheln vom Start, also 41–59 Kacheln vom dort festen
    -- Inselrand bei 90 (Design 2.1: 40–60). Ein dichter 13×13-Block für den Ernter passt nur, wenn die Mitte
    -- nah genug an einem Rasterpunkt liegt (Eckkacheln 8,5 bis 9,2 von der Mitte, Spice nur bis 8,99):
    -- nachgerechnet bei etwa 83 % der Lagen, sonst fehlen dem besten Block 1 bis 4 Eckkacheln.
    type = "noise-expression",
    name = "arrakis_v2_lehrfeld",
    expression = "starting_spot_at_angle{angle = " .. LEHR_ANGLE .. ", distance = 140, radius = 9, x_distortion = 0, y_distortion = 0}"
  }
})

-- Spice-Menge und -Wahrscheinlichkeit je Regel: Regel B ohne Zusatz (eingehängt), Regel A mit „_a“ (Rückfall,
-- nicht eingehängt). Welche gilt, steht nur in prototypes/planet/planet-map-gen.lua (SPICE_RULE).
--
-- Lehrfeld mit Spitze 1180, erschöpfbar, Ziel 100 000 Spice-Sand: Ein Kegel mit Spitze S und Radius r
-- enthält S · π · r² / 3, also S = 3 · 100 000 / (π · 81) = 1178,9, gerundet 1180; das ergibt
-- 1180 · π · 81 / 3 = 100 091. Auf Kacheln (Kachel nur ab Menge > 1, also bis 8,99 von der Mitte, 248 bis
-- 257 Kacheln) sind es 99 910 bis 100 060 bei abgerundeter und 100 040 bis 100 190 bei gerundeter Menge
-- je Kachel, je nach Lage der Mitte (nachgerechnet). Die Mitte hat 1180; liegt sie auf einem Rasterpunkt,
-- hat die Eckkachel eines 13×13-Felds 67 und das 13×13-Feld im Mittel 529. Der Ernter zieht 50 %
-- der geförderten Menge ab (Design 3), das Lehrfeld gibt also etwa 200 000 Spice-Sand her, rund
-- 100 Laderaumfüllungen. Es hängt nicht am Größen-Regler (bleibt bei Größe 0), der Reichtum-Regler wirkt
-- (1/6 bis 6, also etwa 17 000 bis 600 000 Spice-Sand).
-- Reguläre Felder wie in Karte 1: 6000 · Fleck mit Radius 14 · √Größe, Abstand 250 / √Häufigkeit, nur
-- in der Spicezone der Regel. max(size, 1/6) hält den Radius bei Größe 0 endlich (der Regler reicht sonst
-- von 1/6 bis 6, FD core/prototypes/noise-functions.lua:9); (size > 0) schaltet die Felder dann ab.
-- Spice nur auf Sand: 0,005 Abstand zur Felskante, dort ist die Kachel nach der steilen Regel sicher
-- Sand. Das ersetzt eine tile_restriction am Prototyp spice-sand; die gälte auch für Karte 1 in alten
-- Spielständen und nähme dort Spice auf Felskacheln am Inselrand weg.
for _, rule in ipairs({{suffix = "", zone = "arrakis_v2_spice_zone"}, {suffix = "_a", zone = "arrakis_v2_spice_zone_a"}}) do
  data:extend({
    {
      type = "noise-expression",
      name = "arrakis_v2_spice_richness" .. rule.suffix,
      expression = "max(1180 * arrakis_v2_lehrfeld, regular) * richness",
      local_expressions =
      {
        richness = "var('control:arrakis_spice:richness')",
        frequency = "var('control:arrakis_spice:frequency')",
        size = "var('control:arrakis_spice:size')",
        regular = "6000 * (size > 0) * " .. rule.zone .. " * arrakis_spot(7301, 14 * max(size, 1 / 6) ^ 0.5, 250 / frequency ^ 0.5, arrakis_v2_spice_favorability)"
      }
    },
    {
      type = "noise-expression",
      name = "arrakis_v2_spice_probability" .. rule.suffix,
      expression = "(arrakis_v2_spice_richness" .. rule.suffix .. " > 1) * (arrakis_v2_rock < -0.005)"
    }
  })
end

-- Tiefenwasser wie in Karte 1, nur auf dem Fels der Karte 2.
data:extend({
  {
    type = "noise-expression",
    name = "arrakis_v2_deep_water_spot",
    expression = "max(starting, arrakis_spot(7401, 6 * size ^ 0.5, 300 / frequency ^ 0.5, arrakis_v2_rock_favorability))",
    local_expressions =
    {
      frequency = "var('control:arrakis_deep_water:frequency')",
      size = "var('control:arrakis_deep_water:size')",
      starting = "starting_spot_at_angle{angle = arrakis_starting_angle + 225, distance = 45, radius = 6 * size ^ 0.5, x_distortion = 0, y_distortion = 0}"
    }
  },
  {
    -- 4 % je Kachel im Fleck wie in Karte 1. Dazu Wahrscheinlichkeit 1 bis 1 Kachel um die Mitte des
    -- Startflecks (1 bis 4 Kacheln), damit die Startinsel sicher einen Brunnen hat; mit 4 % allein
    -- blieben etwa 1 % der Startflecken leer (0,96 ^ 113). Brunnen überlappen sich nicht, es bleibt einer.
    -- Ein Erzfeld nähme den Platz weg (Tiefenwasser hat order "c", Erz "b", FD base/prototypes/entity/
    -- resources.lua:268), deshalb hält Erz in Karte 2 Abstand (arrakis_v2_well_clear).
    -- Brunnen ganz auf Fels: Die Rohöl-Kopie und die Pumpe darauf belegen 3 × 3 Kacheln (Kollisionsbox ±1,4,
    -- FD base/prototypes/entity/resources.lua:263), deren Mitten bis √2 von der Brunnenmitte liegen.
    -- Abstand 0,03 zur Felskante statt 0,005 wie beim Erz (1 × 1): etwa 2,8 Kacheln an c4-Kanten (0,0106 je
    -- Kachel), 4,5 am Inselrand und am Graben (1/150). Alle 9 Kacheln bleiben Fels, solange die Kante höchstens
    -- (0,03 − 0,0027) / √2 = 0,019 je Kachel fällt, also auch dort, wo die Verzerrung sie bis etwa 1,8-mal so
    -- steil macht. Mit einer Ecke auf Sand zählte die Pumpe ab 3d1 als Vibrationsquelle (Design 4.3).
    type = "noise-expression",
    name = "arrakis_v2_deep_water_probability",
    expression = "(var('control:arrakis_deep_water:size') > 0) * (arrakis_v2_rock > 0.03) * max((arrakis_v2_deep_water_spot > 0) * 0.04, start_well > 0)",
    local_expressions =
    {
      start_well = "starting_spot_at_angle{angle = arrakis_starting_angle + 225, distance = 45, radius = 1, x_distortion = 0, y_distortion = 0}"
    }
  },
  {
    type = "noise-expression",
    name = "arrakis_v2_deep_water_richness",
    expression = "(150000 + 300000 * arrakis_v2_deep_water_spot) * var('control:arrakis_deep_water:richness')"
  },
  {
    -- 1 außer bis 8 Kacheln um die Mitte des Start-Brunnens, 0 dort: Faktor der Erz-Wahrscheinlichkeit in
    -- Karte 2 (MAP_2.keep_clear). Der Brunnen steht bis 1 Kachel neben der Mitte, seine Box reicht 1,4 weiter,
    -- ein Erz-Kästchen 0,1 (FD base/prototypes/entity/resources.lua:36); 8 deckt dazu den ganzen Startfleck
    -- (Radius 6). Die Erz-Startfelder liegen mindestens 32 Kacheln von der Brunnenmitte (Kohle bei 270°,
    -- Stein bei 180°, je 35 vom Start) und bleiben bei Standardgröße unberührt.
    type = "noise-expression",
    name = "arrakis_v2_well_clear",
    expression = "starting_spot_at_angle{angle = arrakis_starting_angle + 225, distance = 45, radius = 8, x_distortion = 0, y_distortion = 0} <= 0"
  }
})
