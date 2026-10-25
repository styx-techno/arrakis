-- Prüfstand T16 (docs/plan-3c.md 3 und 6): zwei Test-Sticker mit vehicle_speed_max statt vehicle_speed_modifier,
-- sonst wie die Tempo-Sticker des Ornithopters (prototypes/ornithopter.lua). Das Feld gibt es in 2.0.75 (A20
-- prototype/generated/prototypes.d.ts:14036) und 2.1.23 (A23 prototypes.d.ts:9947), ohne dokumentierte Einheit [U22]:
-- 8 / 60 gälte bei Kacheln je Tick, 8 bei Kacheln je Sekunde; beide hießen 8 Kacheln/s. Nur der Ausweichweg aus
-- Plan 4.9 hängt daran. T16 heftet sie an unregistrierte Flieger (create_entity{target = flyer}).
local function speed_max_sticker(name, speed_max)
  return
  {
    type = "sticker",
    name = name,
    hidden = true,
    flags = {"not-on-map"},
    duration_in_ticks = 60 * 60 * 60,
    vehicle_speed_max = speed_max
  }
end

data:extend({
  speed_max_sticker("arrakis-test-speed-max-tick", 8 / 60),
  speed_max_sticker("arrakis-test-speed-max-second", 8)
})
