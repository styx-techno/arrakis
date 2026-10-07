-- Prüfstand T11: Kandidaten für das Fels-Rauschen. T11 wertet sie per calculate_tile_properties
-- auf Testoberflächen mit verschiedenen Seeds aus; die Karte nutzt sie nicht.
-- Die Werte sind roh: Fels ist, wo Wert − Felsschwelle > 0. T11 probiert je Kandidat mehrere
-- Felsschwellen. Spice soll später dort liegen, wo der Wert unter einer zweiten Schwelle t100 liegt;
-- das klappt nur, wenn der Wert mit dem Abstand zum Fels fällt.

local function basis(seed1, scale, amplitude)
  return "basis_noise{x = x, y = y, seed0 = map_seed, seed1 = " .. seed1 ..
    ", input_scale = 1 / " .. scale .. ", output_scale = " .. amplitude .. "}"
end

data:extend({
  {
    -- c1: drei Oktaven mit fester Größe, größte Struktur etwa 300 Kacheln.
    type = "noise-expression",
    name = "arrakis_t11_c1",
    expression = basis(7211, 300, 1) .. " + " .. basis(7212, 110, 0.45) .. " + " .. basis(7213, 40, 0.2)
  },
  {
    -- c2: wie c1, aber größere Strukturen (etwa 500 Kacheln), also weitere Sandflächen.
    type = "noise-expression",
    name = "arrakis_t11_c2",
    expression = basis(7221, 500, 1) .. " + " .. basis(7222, 170, 0.45) .. " + " .. basis(7223, 55, 0.2)
  },
  {
    -- Verzerrte Koordinaten für c3 und c4 (bekannte Größe: Maßstab 80 Kacheln, Ausschlag bis etwa 25).
    type = "noise-expression",
    name = "arrakis_t11_wx",
    expression = "x + " .. basis(7251, 80, 25)
  },
  {
    type = "noise-expression",
    name = "arrakis_t11_wy",
    expression = "y + " .. basis(7252, 80, 25)
  },
  {
    -- Voronoi-Kegel für c3: 1 am Zellpunkt, fällt nach außen. T11 misst seine Werte mit,
    -- damit klar wird, ob er mit der Zellgröße oder mit dem Abstand zum Nachbarpunkt skaliert.
    type = "noise-expression",
    name = "arrakis_t11_cone",
    expression = "1 - voronoi_spot_noise{x = arrakis_t11_wx, y = arrakis_t11_wy, seed0 = map_seed, seed1 = 7231,\z
                                         grid_size = 400, distance_type = 'euclidean', jitter = 0.75}"
  },
  {
    -- c3: Felsinseln in einem Sandmeer (Muster wie die Inseln auf Fulgora).
    -- Jede Voronoi-Zelle (400 Kacheln) trägt mit 65 % Wahrscheinlichkeit eine Insel um ihren Punkt,
    -- Inselkante bei Kegel = 0,77. Zellen ohne Insel bleiben unter −0,1, damit auch Felsschwellen
    -- bis −0,05 dort keinen Fels erzeugen.
    type = "noise-expression",
    name = "arrakis_t11_c3",
    expression = "keep * (arrakis_t11_cone - 0.77) + (1 - keep) * min(arrakis_t11_cone - 0.77, -0.1)",
    local_expressions =
    {
      keep = "voronoi_cell_id{x = arrakis_t11_wx, y = arrakis_t11_wy, seed0 = map_seed, seed1 = 7231,\z
                              grid_size = 400, distance_type = 'euclidean', jitter = 0.75} < 0.65"
    }
  },
  {
    -- c4: Felsinseln als Kegel (spot_noise, wie Erz- und Vulkanflecken), etwa 9 Inseln je
    -- 1024 × 1024 Kacheln, Radius 90. Der Wert fällt mit dem Abstand zur nächsten Insel weiter ab
    -- (Sockel bis 400 Kacheln, tiefstens −3), passt also zur Spice-Schwelle.
    type = "noise-expression",
    name = "arrakis_t11_c4",
    expression = "spot_noise{x = arrakis_t11_wx, y = arrakis_t11_wy, seed0 = map_seed, seed1 = 7241,\z
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
  }
})
