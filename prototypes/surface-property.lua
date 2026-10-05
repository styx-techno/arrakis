-- Neue Oberflächen-Eigenschaft: Luftfeuchtigkeit in Prozent.
-- Später für surface_conditions an Rezepten und Gebäuden (z. B. Windfalle).
data:extend({
  {
    type = "surface-property",
    name = "humidity",
    default_value = 50
  }
})

-- Im Weltraum gibt es keine Luft, also auch keine Feuchte (Windfallen funktionieren dort nicht).
data.raw.surface["space-platform"].surface_properties.humidity = 0
