data:extend({
  {
    -- Prüfstand (Phase 3a): nur für Testspielstände. Aus: keine Test-Prototypen, kein /arrakis-test.
    type = "bool-setting",
    name = "arrakis-testbench",
    setting_type = "startup",
    default_value = false,
    order = "z"
  }
})
