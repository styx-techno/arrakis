
-- Feste Schwellen für die Spicefläche (Wert − Felsschwelle < t): T_STEPS[m] = −0,01 · (m − 1), also 0 … −4.
local T_STEP = 0.01
local T_COUNT = 401
local T_STEPS = {}
for index = 1, T_COUNT do
  T_STEPS[index] = -T_STEP * (index - 1)
end

-- Spice-Regel der Karte 0.5.4 (T11-Empfehlung 5.2): Zonen (1 = Spice erlaubt) und der unverzerrte Kegel.
-- strict: FEHLER, wenn ein Zonenpunkt näher als TARGET am Fels liegt; sonst nur Messung.
local ZONES =
{
  {key = "B", property = "arrakis_v2_spice_zone", title = "Regel B (c4u < −1,46)", strict = true},
  {key = "A", property = "arrakis_v2_spice_zone_a", title = "Regel A (c4 < −2,10)", strict = false}
}
local CONE = "arrakis_v2_c4u"

-- Rauschen, die T11 je Seed holt. minus: die Koordinate wird abgezogen (bei wx, wy bleibt die Verschiebung).
local PROPERTIES =
{
  {name = "arrakis_v2_rock", title = "Karte 0.5.4 (c4 mit Startinsel und Graben)"},
  {name = "arrakis_v2_c4", title = "c4 der Karte 0.5.4 (Verzerrung begrenzt)"},
  {name = CONE, title = "c4 der Karte 0.5.4, unverzerrt"},
  {name = "arrakis_v2_wx", title = "Verzerrung 0.5.4 in x (wx − x)", minus = "x", short = "wx − x"},
  {name = "arrakis_v2_wy", title = "Verzerrung 0.5.4 in y (wy − y)", minus = "y", short = "wy − y"},
  {name = ZONES[1].property, title = "Spicezone " .. ZONES[1].title},
  {name = ZONES[2].property, title = "Spicezone " .. ZONES[2].title},
  {name = "arrakis_rock", title = "Karte 0.4.0 mit Startinsel"},
  {name = "arrakis_rock_noise", title = "Rauschen 0.4.0 ohne Startinsel"},
  {name = "arrakis_wobble_x", title = "Verzerrung 0.4.0 (multioctave_noise, Maßstab 12)"},
  {name = "arrakis_t11_c1", title = "c1: 3 Oktaven bis 300 Kacheln"},
  {name = "arrakis_t11_c2", title = "c2: 3 Oktaven bis 500 Kacheln"},
  {name = "arrakis_t11_cone", title = "Voronoi-Kegel von c3"},
  {name = "arrakis_t11_c3", title = "c3: Voronoi-Inseln"},
  {name = "arrakis_t11_c4", title = "c4: Kegel-Inseln (spot_noise)"}
}
local PROPERTY_NAMES = {}
for index, property in ipairs(PROPERTIES) do
  PROPERTY_NAMES[index] = property.name
end

-- Varianten = Rauschen + Felsschwelle. share: Schwelle je Seed so, dass dieser Anteil Fels ist;
-- sonst feste Schwelle offset. picture: Kartenbild schreiben. family: Zeile in der Kurzfassung.
-- zones: Prüfung „Zone“ gegen den Fels dieser Variante. cone: Prüfung „Kegel“ gegen ihren Fels.
-- fixed: Spicefläche bei den festen Schwellen FIXED_T ausgeben.
local VARIANTS =
{
  {key = "live", family = "live", property = "arrakis_v2_rock", offset = 0, picture = true, zones = true,
   title = "Karte 0.5.4 (c4 mit Startinsel und Graben)", label = "0.5.4"},
  {key = "alt", family = "live", property = "arrakis_rock", offset = 0, picture = true,
   title = "Karte 0.4.0 (mit Startinsel)", label = "0.4.0"}
}
for _, family in ipairs({{key = "c1", property = "arrakis_t11_c1"}, {key = "c2", property = "arrakis_t11_c2"}}) do
  for _, percent in ipairs({15, 20, 25, 30}) do
    VARIANTS[#VARIANTS + 1] = {key = family.key .. "-" .. percent, family = family.key, property = family.property,
      share = percent / 100, picture = percent == 20, title = percent .. " % Fels je Seed", label = percent .. " %"}
  end
end
for _, offset in ipairs({-0.05, 0, 0.05}) do
  VARIANTS[#VARIANTS + 1] = {key = "c3" .. string.format("%+.2f", offset), family = "c3", property = "arrakis_t11_c3",
    offset = offset, picture = offset == 0, title = "Felsschwelle " .. offset, label = string.format("%+.2f", offset)}
end
for _, offset in ipairs({-0.2, 0, 0.2}) do
  VARIANTS[#VARIANTS + 1] = {key = "c4" .. string.format("%+.1f", offset), family = "c4", property = "arrakis_t11_c4",
    offset = offset, picture = offset == 0, fixed = offset == 0, title = "Felsschwelle " .. offset,
    label = string.format("%+.1f", offset)}
end
VARIANTS[#VARIANTS + 1] = {key = "c4v2", family = "c4", property = "arrakis_v2_c4", offset = 0, cone = true, fixed = true,
  title = "c4 der Karte 0.5.4 ohne Startinsel und Graben, Felsschwelle 0", label = "0.5.4 +0.0"}

-- Letzte Variante je Rauschen (auch Zonen und Kegel): danach werden seine Werte freigegeben.
local LAST_USE = {}
for index, variant in ipairs(VARIANTS) do
  LAST_USE[variant.property] = index
  if variant.zones then
    for _, zone in ipairs(ZONES) do LAST_USE[zone.property] = index end
  end
  if variant.cone then LAST_USE[CONE] = index end
end

-- Für die Testdateien scripts/testbench/tests/ (eine je Test; aufgeteilt aus t_map.lua, Verhalten unverändert).
return
{
  T_STEP = T_STEP,
  T_COUNT = T_COUNT,
  T_STEPS = T_STEPS,
  ZONES = ZONES,
  CONE = CONE,
  PROPERTIES = PROPERTIES,
  PROPERTY_NAMES = PROPERTY_NAMES,
  VARIANTS = VARIANTS,
  LAST_USE = LAST_USE,
}
