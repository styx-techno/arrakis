data:extend({
  {
    -- Prüfstand (Phase 3a): nur für Testspielstände. Aus: keine Test-Prototypen, kein /arrakis-test.
    type = "bool-setting",
    name = "arrakis-testbench",
    setting_type = "startup",
    default_value = false,
    order = "z"
  },
  {
    -- Wurmbiss (Entscheidung 4): wirkt erst, wenn es Würmer gibt (Phase 3d).
    type = "string-setting",
    name = "arrakis-worm-bite",
    setting_type = "runtime-global",
    default_value = "total-loss",
    allowed_values = {"total-loss", "heavy-damage"},
    order = "a[worm]-a[bite]"
  }
})
