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
    -- Wurmbiss (Entscheidung 4): gilt für Spice-Ernter im Bissradius (docs/protokolle/plan-3d1.md 4.9).
    type = "string-setting",
    name = "arrakis-worm-bite",
    setting_type = "runtime-global",
    default_value = "total-loss",
    allowed_values = {"total-loss", "heavy-damage"},
    order = "a[worm]-a[bite]"
  },
  {
    -- Reichweite der Ornithopter-Leitstelle (docs/plan-3e.md 1.3): Betreuung und Anzeige beim Bauen. Startup, weil die
    -- Reichweitenanzeige im Prototyp steht.
    type = "int-setting",
    name = "arrakis-depot-range",
    setting_type = "startup",
    default_value = 300,
    minimum_value = 150,
    maximum_value = 600,
    order = "b[fleet]-a[range]"
  },
  -- Phase 3h (docs/plan-3h.md 2.3): Spielwerte der Würmer, jederzeit änderbar. Standard = Verhalten bis 0.13.0.
  -- scripts/config.lua überträgt sie in die Modul-Konstanten.
  {
    type = "bool-setting",
    name = "arrakis-worms-enabled",
    setting_type = "runtime-global",
    default_value = true,
    order = "a[worm]-b[enabled]"
  },
  {
    type = "int-setting",
    name = "arrakis-warn-seconds",
    setting_type = "runtime-global",
    default_value = 60,
    minimum_value = 30,
    maximum_value = 180,
    order = "a[worm]-c[warn]"
  },
  {
    type = "int-setting",
    name = "arrakis-wormsign-threshold",
    setting_type = "runtime-global",
    default_value = 1000,
    minimum_value = 300,
    maximum_value = 5000,
    order = "a[worm]-d[threshold]"
  },
  {
    type = "int-setting",
    name = "arrakis-vibration-percent",
    setting_type = "runtime-global",
    default_value = 100,
    minimum_value = 25,
    maximum_value = 400,
    order = "a[worm]-e[vibration]"
  },
  {
    type = "int-setting",
    name = "arrakis-rest-percent",
    setting_type = "runtime-global",
    default_value = 100,
    minimum_value = 25,
    maximum_value = 400,
    order = "a[worm]-f[rest]"
  },
  {
    type = "int-setting",
    name = "arrakis-max-hunts",
    setting_type = "runtime-global",
    default_value = 3,
    minimum_value = 1,
    maximum_value = 10,
    order = "a[worm]-g[hunts]"
  },
  {
    type = "int-setting",
    name = "arrakis-free-minutes",
    setting_type = "runtime-global",
    default_value = 60,
    minimum_value = 0,
    maximum_value = 240,
    order = "a[worm]-h[free]"
  },
  {
    type = "int-setting",
    name = "arrakis-thumper-seconds",
    setting_type = "runtime-global",
    default_value = 60,
    minimum_value = 20,
    maximum_value = 300,
    order = "a[worm]-i[thumper]"
  },
  {
    type = "int-setting",
    name = "arrakis-tooth-percent",
    setting_type = "runtime-global",
    default_value = 100,
    minimum_value = 0,
    maximum_value = 500,
    order = "a[worm]-j[tooth]"
  },
  -- Phase 3j (docs/plan-3j.md 2.3): großer Wurm an/aus.
  {
    type = "bool-setting",
    name = "arrakis-large-worm",
    setting_type = "runtime-global",
    default_value = true,
    order = "a[worm]-k[large]"
  }
})
