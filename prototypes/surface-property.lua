-- Neue Oberflächen-Eigenschaft: Luftfeuchtigkeit in Prozent.
-- Später für surface_conditions an Rezepten und Gebäuden (z. B. Windfalle).
data:extend({
  {
    type = "surface-property",
    name = "humidity",
    default_value = 50
  }
})
