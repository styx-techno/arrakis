-- Prüfstand T11: Kandidaten für das Fels-Rauschen. T11 wertet sie per calculate_tile_properties
-- auf Testoberflächen mit verschiedenen Seeds aus; die Karte nutzt sie nicht.
-- Alle Werte sind roh (> 0 nicht unbedingt Fels): Bei c1 und c2 setzt T11 die Schwelle je Seed so,
-- dass ein fester Felsanteil herauskommt; bei c3 ist 0 die Inselkante.

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
    -- Verzerrte Koordinaten für c3, damit die Inseln nicht kreisrund sind.
    type = "noise-expression",
    name = "arrakis_t11_wx",
    expression = "x + arrakis_wobble_x * 18"
  },
  {
    type = "noise-expression",
    name = "arrakis_t11_wy",
    expression = "y + arrakis_wobble_y * 18"
  },
  {
    -- c3: Felsinseln in einem Sandmeer (Muster wie die Inseln auf Fulgora).
    -- Jede Voronoi-Zelle (400 Kacheln) trägt mit 65 % Wahrscheinlichkeit eine Insel um ihren Punkt.
    -- cone ist 1 am Zellpunkt und etwa 0,5 am Zellrand; Inselkante bei cone = 0,77 (Radius etwa 90).
    type = "noise-expression",
    name = "arrakis_t11_c3",
    expression = "keep * (cone - 0.77) + (1 - keep) * (cone - 1.27)",
    local_expressions =
    {
      cone = "1 - voronoi_spot_noise{x = arrakis_t11_wx, y = arrakis_t11_wy, seed0 = map_seed, seed1 = 7231,\z
                                     grid_size = 400, distance_type = 'euclidean', jitter = 0.75}",
      keep = "voronoi_cell_id{x = arrakis_t11_wx, y = arrakis_t11_wy, seed0 = map_seed, seed1 = 7231,\z
                              grid_size = 400, distance_type = 'euclidean', jitter = 0.75} < 0.65"
    }
  }
})
