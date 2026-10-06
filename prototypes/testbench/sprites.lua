-- Prüfstand T9: Bild eines getragenen Ernters und Schatten-Variante für rendering.draw_sprite.
data:extend({
  {
    type = "sprite",
    name = "arrakis-test-carried",
    filename = "__base__/graphics/icons/tank.png",
    size = 64
  },
  {
    type = "sprite",
    name = "arrakis-test-carried-shadow",
    filename = "__base__/graphics/icons/tank.png",
    size = 64,
    draw_as_shadow = true
  }
})
