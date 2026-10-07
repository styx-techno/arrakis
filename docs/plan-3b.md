# Umsetzungsplan Phase 3b (0.5.0): Spice-Ernter, Annahme, Tankstutzen, Brikett

Stand 07.10.2026. Grundlage: Design v0.3 (docs/design-ernter-ornithopter.md, kurz DOC), Prüfstand-Ergebnisse 0.4.0
(/mnt/project-files/pruefstand/2026-10-07/ergebnisse.md, kurz ERG) und die Recherche zu API, Fahrphysik,
Vanilla-Vorbildern und Risiken (Belege dort). Dieser Plan ist der Bauvertrag: Namen, Dateien, Zustände und
Texte gelten so, wie sie hier stehen. Wo der Plan von DOC abweicht, gilt der Plan; DOC wird danach angeglichen.

## 0. Umfang

**In 0.5.0**
- Spice-Ernter (`car`): Fahren mit Tempo-Ausgleich je Brennstoff und Tempo-Deckel jeden Tick, Aufbauen (5 s),
  Abbau per Skript, Einpacken (10 s), Statusanzeige, Alarme, relatives Fenster mit Knopf, Taste `Umschalt+H`.
- Ressourcenkategorie `arrakis-spice-harvest`: Spice nur per Ernter und Hand; Meldung alter Bohrer auf Spice.
- Spice-Annahme und Tankstutzen (`proxy-container`), Andocken mit Hysterese, Abdocken.
- Spice-Brikett (Item und Rezept in der Raffinerie), Forschung „Spice-Ernte“.
- Mod-Einstellung `arrakis-worm-bite` (wirkt erst ab 3d1, wenn es Bisse gibt).
- Prüfstand: T13 (echter Code, automatisch) und T2b (Fahrphysik des echten Ernters).

**Nicht in 0.5.0**
- Kartengenerator (Lehrfeld, Mindestabstand, steile Felsregel): wartet auf Max' T11-Lauf, kommt als 0.5.x.
- Vorsichtsmodus: braucht die Vibration/Wärme aus 3d1 und kommt mit ihr. Ohne Wärme hätte der Schalter keine Wirkung.
- Ornithopter/Anheben (3c), Vibration, Würmer, Biss (3d). Staubwolken und Rumpeln kommen mit der Unruhe in 3d1.

## 1. Festlegungen (Standardwahl, Max kann widersprechen)

| Punkt | Festlegung | Grund |
|---|---|---|
| Tempo | `consumption = 330kW`, Ausgleich `effectivity_modifier = min(1, 1/a_eff)`, Deckel jeden Tick bei 1,5 Kacheln/s, Rücksetzen auf 1,45 | Modell aus T2 sagt für jeden Brennstoff 1,453 voraus, Bodentempo 1,406 (6/256 je Tick) |
| Deckel-Werte | Konstanten im Code, keine Mod-Einstellung | Eine Einstellung würde die Fluchtregel aushebeln; Balancing-Runde 3d3 |
| Brikett | ohne Produktivität: 5 Spice-Sand + 1 Kohle → 1 Brikett (20 MJ), 4 s | Entscheidung 5 sagt 20 MJ; mit Produktivität wären es 30 MJ |
| Brikett-Gewicht | 10 kg (100 je Rakete) | bleibt lokaler Brennstoff |
| Aufheben | Ernter auf Arrakis ist nicht abbaubar, solange unter ihm Sand liegt oder er aufgebaut ist | sonst Flucht per Aufheben in 22 s (Risiko 1) |
| Bedienung aus der Ferne | Taste und Knopf gehen auch aus der Kartenansicht (gleiche Force) | Aufbauen/Einpacken bewegt nichts, Fernfahren bleibt aus |
| Gepflasterter Fels | zählt im Skript als Fels (natürliche Kachel). Von Hand lässt sich die Annahme auf gepflastertem Fels nicht bauen (Prototyp-Regel); Hinweis „vor dem Pflastern bauen“ | Prototyp-Regel gibt die rote Bauvorschau |
| Mindestversion | `base >= 2.0.67`, `space-age >= 2.0.67` | Tasten-Fix und Bauregel-Fix aus 2.0.66/2.0.67; Max spielt 2.0.77 |
| Ernter-Qualität | ändert nur Lebenspunkte | keine Regel im Design |

## 2. Dateien

Neu:
- `prototypes/harvester.lua`: Ressourcenkategorie, Ernter (Entity, Item, Rezept), Annahme und Tankstutzen (Entity, Item, Rezept), Brikett (Item, Rezept), Forschung, Taste.
- `data-final-fixes.lua`: Kategorie an alle Spielfiguren und God-Controller anhängen.
- `scripts/terrain.lua`: `harvest_allowed(surface)`, `natural_tile_name(surface, x, y)`, `is_rock_area(surface, area)`, `has_sand_under(entity)`.
- `scripts/harvester.lua`: Ernter-Zustände, Abbau, Treibstoff, Tempo, Abbausperre, Andocken/Abdocken, Taste.
- `scripts/harvester-gui.lua`: relatives Fenster am Fahrzeugfenster.
- `scripts/intake.lua`: Annahme und Tankstutzen: Bauen, Felsprüfung, Andock-Takt, Zerstören.
- `scripts/migrate.lua`: `storage`-Aufbau, Schema, Meldung alter Bohrer.
- `locale/de/messages.cfg`, `locale/en/messages.cfg`: nur Abschnitt `[arrakis-message]` (Laufzeittexte).
- `scripts/testbench/t_ernter.lua`: T13 und T2b.

Geändert: `data.lua` (require vor `compat.finish`), `prototypes/resources.lua` (Kategorie), `settings.lua`,
`control.lua`, `locale/*/arrakis.cfg`, `info.json`, `changelog.txt`, `README.md`, `docs/pruefstand.md`,
`scripts/testbench/runner.lua` (ORDER), `tools/check/checks.lua`, DOC.

## 3. Prototypen (2.0-Schreibweise; `compat.finish` setzt 2.1 um)

**Ressourcenkategorie** `{type = "resource-category", name = "arrakis-spice-harvest"}`; `spice.category = "arrakis-spice-harvest"` in resources.lua.
`data-final-fixes.lua`: für jede `data.raw.character` und `data.raw["god-controller"]`, deren `mining_categories`
(Standard `{"basic-solid"}`, auch wenn das Feld fehlt) `basic-solid` enthält, `arrakis-spice-harvest` anhängen,
falls noch nicht da. Nie die Liste ersetzen. Kein Bohrer bekommt die Kategorie.

**Spice-Ernter** `spice-harvester`: `table.deepcopy(data.raw.car.tank)`, dann
- `minable = {mining_time = 0.5, result = "spice-harvester"}`, `guns = nil`, `inventory_size = 40`,
  `energy_source.fuel_inventory_size = 3` (fuel_categories geerbt, chemical), `allow_remote_driving = false`,
  `trash_inventory_size = 0`, `equipment_grid = nil`, `has_belt_immunity = true`, `factoriopedia_simulation = nil`.
- Physik: `consumption = "330kW"`, `effectivity = 0.9`, `weight = 20000`, `terrain_friction_modifier = 0`,
  `compat.vehicle_physics(p, 800 * 1000 / 60, 0.1)`.
- Bild: Panzer getönt `{r = 1, g = 0.8, b = 0.5}` (wie prototypes/testbench/harvester.lua, gleiche tint_layers-Regel).
- Item `item-with-entity-data`, Panzer-Icon getönt, `subgroup = "transport"`, `order = "b[personal-transport]-z[spice-harvester]"`, Panzer-Sounds, `stack_size = 1`, `default_import_location = "arrakis"`.
- Rezept `spice-harvester`: 40 steel-plate, 20 engine-unit, 10 advanced-circuit, 100 stone-brick, 10 melange; 10 s; `enabled = false`.

**Spice-Annahme** `arrakis-spice-intake`: deepcopy von `data.raw["proxy-container"]["proxy-container"]` (nie einen
circuit_connector von einer Kiste kopieren), `hidden = nil`, eigene Icons, `minable = {mining_time = 0.5, result = "arrakis-spice-intake"}`,
`fast_replaceable_group = nil`, Kollision ±0,9, Auswahl ±1, Bild Eisenkiste ×2 getönt, `tile_buildability_rules =
{{area = {{-5, -5}, {5, 5}}, required_tiles = {layers = {arrakis_rock = true}}}}`. Item (stack 10), Rezept 20 steel-plate, 50 stone-brick, 5 electronic-circuit.
**Tankstutzen** `arrakis-fuel-nozzle`: dasselbe Muster 1×1, ohne Bauregel. Rezept 5 steel-plate, 5 pipe.

**Spice-Brikett** `arrakis-spice-briquette`: Item, Kohle-Icon getönt, `fuel_category = "chemical"`, `fuel_value = "20MJ"`,
`stack_size = 50`, `weight = 10 * kg`, `subgroup = "arrakis-spice"`, `default_import_location = "arrakis"`, keine Tempo-Multiplikatoren.
Rezept `category = "spice-refining"`, 5 spice-sand + 1 coal → 1, `energy_required = 4`, kein `allow_productivity`.

**Forschung** `arrakis-spice-harvesting`: Voraussetzung `arrakis-spice-processing`, `research_trigger = {type = "craft-item", item = "melange", count = 10}`,
schaltet die Rezepte spice-harvester, arrakis-spice-intake, arrakis-fuel-nozzle, arrakis-spice-briquette frei.

**Taste** `{type = "custom-input", name = "arrakis-harvester-toggle", key_sequence = "SHIFT + H", consuming = "none"}`.

**Einstellung** `{type = "string-setting", name = "arrakis-worm-bite", setting_type = "runtime-global", default_value = "total-loss", allowed_values = {"total-loss", "heavy-damage"}, order = "a[worm]-a[bite]"}`.

## 4. Laufzeit

### 4.1 Module und Ereignisse
`control.lua` lädt per event_handler in dieser Reihenfolge: `scripts.migrate`, `scripts.arrakis-surface`,
`scripts.harvester`, `scripts.harvester-gui`, `scripts.intake`, (Prüfstand). Kein Modul ruft `script.on_event`
oder `script.on_nth_tick` direkt auf; alles läuft über `events` und `on_nth_tick` der Bibliothek.
Ereignisse kommen ungefiltert: Jeder Handler prüft zuerst den Namen (Tabellen-Lookup) und kehrt sofort zurück.

`scripts.harvester` stellt für die anderen Module und den Prüfstand bereit:
`get(entity) → Datensatz|nil`, `register(entity)`, `toggle(entity, player|nil) → bool`, `deploy`, `pack`,
`dock(h, intake_record)`, `undock(h)`, `state_text(h)`, `refresh_minable(h)`, `apply_fuel_normalization(entity)`,
`CAP`, `RESET`. `scripts.intake` ruft `harvester.dock/undock`; harvester.lua kennt intake.lua nicht.

### 4.2 storage (Schema 1)
```lua
storage.schema = 1
storage.harvesters[un] = {
  entity, state = "mobile"|"deploying"|"deployed"|"packing"|"docked",
  timer_start, timer_end,            -- Aufbauen/Einpacken
  resources = {LuaEntity…}, res_index = 1,
  progress = 0, drain_rest = 0, prod_rest = 0, last_tick,
  deploy_pos = {x, y}, deploy_surface = surface_index,
  status = nil|"harvesting"|"trunk_full"|"field_empty"|"no_fuel",
  renders = {ring = LuaRenderObject|nil, frame = LuaRenderObject|nil},
  dock = intake_un|nil, undocked_from = intake_un|nil, still_since = tick|nil,
  fuel_key = "name/quality"|nil, last_toggle_tick = 0, minable_pos = {x, y}|nil,
}
storage.driven[un] = LuaEntity        -- Ernter, für die der Deckel jeden Tick läuft
storage.timers[un] = true              -- Ernter im Aufbauen/Einpacken (Ring)
storage.intakes[un] = {entity, docked = harvester_un|nil, nozzles = {un…}, bad = false}
storage.nozzles[un] = {entity, intake = intake_un|nil}
storage.reg[registration_number] = {kind = "harvester"|"intake"|"nozzle", un = un}
storage.gui_open[player_index] = harvester_un
storage.migration = {spice_drills = {LuaEntity…}}
```
`scripts.migrate` legt alle Tabellen in `on_init` und `on_configuration_changed` an (eine Funktion `init()`), als
erste Bibliothek. `on_load` schreibt nie. Schlüssel sind `unit_number`; keine Funktionen in storage.

### 4.3 Zustände und Übergänge
| Zustand \ Eingabe | Taste/Knopf | Andock-Takt (steht ≥ 2 s im Kreis) | Tod/Abbau | Teleport/Klon |
|---|---|---|---|---|
| mobile | Aufbauen, wenn Tempo 0, `harvest_allowed`, Spice im Feld; sonst Hinweis | → docked | aufräumen | Abbausperre neu werten |
| deploying | Abbruch → mobile sofort | – | aufräumen | → mobile sofort |
| deployed | → packing | – | aufräumen | → mobile sofort |
| packing | ignorieren | – | aufräumen | → mobile sofort |
| docked | → mobile (Abdocken) | – | aufräumen, Ziele löschen | → mobile (Abdocken) |

- Entprellen: zweite Taste für denselben Ernter innerhalb 15 Ticks ignorieren.
- Aufbauen: `disabled_by_script = true` (zurücklesen, bei false Fehler loggen), `speed = 0`, `minable_flag = false`,
  Ring 5 s. Am Ende: Feld (13×13 um `floor(x)+0.5, floor(y)+0.5`, ±6,5) per `find_entities_filtered{name = "spice-sand"}`
  in den Cache, Feldrahmen zeichnen, `last_tick = game.tick`, `deploy_pos` merken, Status „Erntet“.
- Einpacken: Abbau stoppt sofort, Rahmen weg, Ring 10 s, danach `disabled_by_script = false`, Abbausperre neu werten.
- Abdocken: zuerst `proxy_target_entity = nil` an Annahme und Stutzen, dann entsperren, `undocked_from = intake_un`.

### 4.4 Takte
- `on_tick` (statisch): `if next(storage.driven) == nil then return end`. Je Eintrag: ungültig → austragen;
  `|speed| > CAP/60` → `speed = ±RESET/60` (Vorzeichen bleibt). Alle 10 Ticks zusätzlich: Ausgleich prüfen
  (nur bei geändertem Brennstoff schreiben); austragen, wenn nicht mobile oder ohne Fahrer mit Tempo 0.
  Eintragen bei `on_player_driving_changed_state` (Einsteigen) und im 30-Tick-Takt bei `speed ≠ 0`.
- `on_nth_tick(10)`: Ringe in `storage.timers` nachführen, abgelaufene Aufbau-/Einpackvorgänge abschließen.
- `on_nth_tick(30)`: Abbau für alle `deployed`; dazu Fahrten erkennen (siehe oben); offene Fenster auffrischen.
- `on_nth_tick(60)`: Andock-Takt (intake.lua) und Abbausperre für ruhende mobile Ernter, deren Position sich geändert hat.

### 4.5 Abbau (je 30-Tick-Durchlauf und Ernter im Zustand deployed)
1. Ist der Ernter bewegt (> 0,25 Kacheln) oder auf einer anderen Oberfläche: sofort → mobile, Cache leeren.
2. `dt = min((game.tick − last_tick) / 60, 2)`; `last_tick = game.tick` (immer, auch bei Pause).
3. Pausen in dieser Reihenfolge: Laderaum nimmt kein Spice-Sand → `trunk_full`; Cache leer (einmal neu suchen) →
   `field_empty`; kein Brennwert und kein Brennstoff → `no_fuel`. In der Pause kein Fortschritt.
4. `progress += 5 · dt`; `n = floor(progress)`; `progress -= n`. Ausbeute `total = n · (1 + force.mining_drill_productivity_bonus) + prod_rest`, `k = floor(total)`, `prod_rest = total − k`.
5. `inserted = trunk.insert{name = "spice-sand", count = k}`. Statistik `on_flow("spice-sand", inserted)` (nur das Eingefügte).
6. Abzug vom Feld nur für Eingefügtes: `drain_rest += 0.5 · inserted / (1 + bonus)`; ganze Einheiten reihum je 1 vom Cache
   (`res_index`), ungültige entfernen; `if res.amount <= 1 then res.deplete() else res.amount = res.amount − 1 end`.
   Der `on_resource_depleted`-Weg ändert den Cache nicht, während die Schleife läuft.
7. Treibstoff: `consume(entity, 400 kW · dt)` (eine Hilfsfunktion): reicht `remaining_burning_fuel` nicht, genau ein Item
   gleicher Sorte und Qualität aus dem Treibstoffinventar nehmen, `currently_burning` setzen, Rest weiter abziehen;
   `on_flow(Brennstoff, −1)` je geladenem Item. Danach Ausgleich neu setzen.
8. Statuswechsel nur bei Änderung schreiben: `custom_status`, Alarm (`add_custom_alert` an alle Spieler der Force bei
   trunk_full, field_empty, no_fuel; `remove_alert` beim Zurückwechseln).

### 4.6 Tempo-Ausgleich
`apply_fuel_normalization(entity)`: `cb = entity.burner.currently_burning`; ohne `cb` nichts ändern. `a = cb.name.fuel_acceleration_multiplier + cb.quality.level · cb.name.fuel_acceleration_multiplier_quality_bonus`;
`entity.effectivity_modifier = math.min(1, 1 / a)`; Schlüssel `name/quality` merken. Nie `fuel_category` lesen (2.1).
Aufrufe: Einsteigen, alle 10 Ticks für gefahrene Ernter, nach `consume`, nach Teleport/Klon/Bauen.

### 4.7 Abbausperre (gegen Flucht per Aufheben)
`refresh_minable(h)`: `minable_flag = false`, wenn Zustand deploying/deployed/packing, oder wenn `harvest_allowed` und
unter `entity.bounding_box` mindestens eine natürliche Nicht-Fels-Kachel liegt; sonst `true`. Neu werten bei Aussteigen,
Ende Einpacken, Abdocken, Bauen, Teleport/Klon und im 60-Tick-Takt (ruhend, Position geändert).
`on_marked_for_deconstruction`: Ernter mit `minable_flag == false` → `cancel_deconstruction(entity.force)`.

### 4.8 Annahme und Tankstutzen (intake.lua)
- Bauen (`on_built_entity`, `on_robot_built_entity`, `script_raised_built`, `script_raised_revive`, `on_entity_cloned`):
  registrieren; Annahme: `is_rock_area(surface, ±5 um die Mitte)`, sonst `bad = true`, `order_deconstruction(force)`, fliegender Text.
  Stutzen: nächste Annahme in ≤ 3 Kacheln zuordnen; ist sie angedockt, sofort Ziel setzen.
- Andock-Takt (60 Ticks) je mobilem Ernter auf erlaubter Oberfläche: `speed ≠ 0` → `still_since = nil`; sonst
  `still_since = still_since or tick`; ab 120 Ticks Stillstand: nächste Annahme in ≤ 4 Kacheln, nicht `bad`, frei, nicht
  `undocked_from` (das wird gelöscht, sobald der Abstand > 5 ist) → `harvester.dock`. Andocken: sperren, `proxy_target_entity = harvester`,
  `proxy_target_inventory = defines.inventory.car_trunk`; zugeordnete Stutzen: `defines.inventory.fuel`.
- Prüfen bei jedem Takt: angedockter Ernter weiter gültig und im Kreis, Annahme gültig; sonst abdocken bzw. Ziele löschen.
- Zerstören/Abbauen von Annahme oder Stutzen (`on_object_destroyed`, dazu sofort in `on_entity_died`/`on_*_mined_entity`):
  angedockten Ernter abdocken, Einträge löschen. Tod des Ernters: zuerst alle Proxy-Ziele löschen.
- `on_entity_settings_pasted` auf Annahme/Stutzen: Ziele aus storage neu setzen.

### 4.9 Fenster und Taste
- Taste `arrakis-harvester-toggle`: Ernter = `player.vehicle`, sonst `player.selected`, wenn `spice-harvester` und gleiche Force.
- Fenster: `player.gui.relative`, Anker `{gui = defines.relative_gui_type.car_gui, position = defines.relative_gui_position.right, names = {"spice-harvester"}}`,
  aufgebaut in `on_gui_opened`, entfernt in `on_gui_closed`. Inhalt: Zustand/Status, Laderaum `x / Kapazität` als Balken
  (Kapazität = Slots × Stapelgröße), Treibstoff (Items, Restbrennwert), ein Knopf `arrakis_harvester_toggle` mit
  passender Beschriftung (Aufbauen/Einpacken/Abdocken, im Aufbau „Abbrechen“, im Einpacken gesperrt).
- Ringe und Rahmen nur für die eigene Force sichtbar; vor jeder Nutzung `valid` prüfen.

### 4.10 Migration (migrate.lua)
`on_configuration_changed`: `init()`; wenn `(storage.schema or 0) < 1`: Bohrer melden, dann `storage.schema = 1`.
Bohrer melden: Arrakis-Oberfläche (kann fehlen), `find_entities_filtered{type = "mining-drill"}`; Treffer, wenn
`mining_target` Spice ist oder `count_entities_filtered{area = drill.mining_area, name = "spice-sand", limit = 1} > 0`.
Je Treffer: Kartenmarkierung (Icon spice-sand) und `add_custom_alert` an alle Spieler der Force; eine Sammelzeile
mit Anzahl und `[gps=x,y,arrakis]`. Nicht erstatten, nicht abreißen. Funktion `migrate.report_drills(surface)` für T13 exportieren.

### 4.11 Prüfstand-Haken
`terrain.harvest_allowed(surface)`: Arrakis, oder mit Startup-Einstellung `arrakis-testbench` die Oberfläche `arrakis-testbench`.

## 5. Texte

`locale/{de,en}/arrakis.cfg` (Datenstufe): `[entity-name]`/`[entity-description]` spice-harvester, arrakis-spice-intake,
arrakis-fuel-nozzle; `[item-name]` dieselben plus arrakis-spice-briquette; `[item-description]` arrakis-spice-briquette;
`[technology-name]`/`[technology-description]` arrakis-spice-harvesting; `[controls]` arrakis-harvester-toggle;
`[mod-setting-name]`/`[mod-setting-description]` arrakis-worm-bite (Beschreibung: wirkt ab der Wurm-Phase);
`[string-mod-setting]` arrakis-worm-bite-total-loss, arrakis-worm-bite-heavy-damage.
`locale/{de,en}/messages.cfg`: Abschnitt `[arrakis-message]` mit allen Laufzeittexten (Status, Alarme, Hinweise,
Fenster, Migration); die Schlüssel legt der Laufzeitcode fest. Deutsch „Spice-Sand“, Englisch „Spice sand“.

## 6. Prüfstand

**T13 „Ernter: echter Code“** (automatisch, eigene Fläche auf `arrakis-testbench`, Sand mit Spice-Teppich, Felsinsel
mit Annahme, Stutzen, Greifarmen und Kisten). Jeder Schritt schreibt OK oder FEHLER mit Werten:
1. Aufbauen mit 3 Kohle, nie gefahren: nach 5 s deployed, gesperrt, nicht abbaubar; 15 s Ernten: Ausbeute ≈ 5/s,
   Feldabzug = 0,5 × Ausbeute ± 1, Brennwert −400 kW × 15 s ± 5 %, Itemzahl stimmt, Statistik zählt gleich.
2. Dummy-Fahrer gibt Gas, während aufgebaut: Weg 0. `order_deconstruction`: nicht markiert.
3. Laderaum voll, 600 Ticks warten, leeren, ein Takt: höchstens 5 + 1 eingefügt (kein Nachholen).
4. Einpacken: nach 10 s mobile, entsperrt, auf Sand nicht abbaubar; auf Fels teleportiert abbaubar.
5. Erschöpfung: 3 Ressourcen mit Menge 1–3 unter zwei überlappenden Ernter: kein Skriptfehler, `field_empty`.
6. Andocken: Ernter im Kreis, 3 s: docked, Ziele gesetzt; 10 s Greifarme: Kiste hat Spice, Treibstoff hat Kohle.
   Abdocken per `toggle`, 3 × 60 Ticks: bleibt mobile; 6 Kacheln weg und zurück: dockt wieder.
7. Annahme zerstören, während angedockt: Ernter nach 2 Ticks entsperrt. Ernter `die()` angedockt: Ziele nil, storage leer.
8. Klon eines aufgebauten Ernters: Klon mobile und entsperrt. Teleport eines aufgebauten Ernters ohne Ereignis: nach einem Takt mobile.
9. Annahme auf Sand per `create_entity{raise_built = true}`: zum Abriss markiert, dockt nicht.
10. Bohrer auf Spice: `migrate.report_drills` meldet ihn.
11. Band: Ernter auf laufendem Band 5 s: Weg 0.
12. Zustandstabelle: jede Eingabe aus 4.3 in jedem Zustand, Folgezustand und Flags stimmen.

**T2b „Ernter: Fahrphysik“**: echter `spice-harvester` mit Dummy-Fahrer, je 15 s Gas mit Kohle, Festbrennstoff,
Raketentreibstoff, Atomtreibstoff und legendärem Raketentreibstoff, mit Ausgleich; dazu Raketentreibstoff ohne
Ausgleich und Deckel (nur gemessen). Richtungen O, W, N, S, schräg, negative Koordinaten; einmal mit vollem Laderaum.
Erwartung: speed ≈ 1,45, Höchstwert ≤ 1,5, Bodentempo ≤ 1,5 Kacheln/s in jeder Richtung.

## 7. Prüfung vor der Übergabe
- `tools/check/datastage.py` mit Vanilla 2.0.77 und 2.1.x, jeweils mit und ohne `arrakis-testbench`; checks.lua prüft
  zusätzlich: spice-sand-Kategorie, jede Figur/jeder God-Controller mit basic-solid hat die neue Kategorie, kein Bohrer hat sie,
  Ernter `allow_remote_driving == false` und `has_belt_immunity == true`, Brikett 20 MJ ohne Multiplikatoren, Rezept ohne Produktivität.
- `tools/check/api_names.py` gegen 2.0.75 und 2.1.20 ohne neue Treffer.
- Statische Regeln: kein `script.on_event`/`script.on_nth_tick` außerhalb von event_handler; keine storage-Schreibzugriffe
  aus `on_load`; keine Nutzung von `event.in_gui`.
- Lua-Syntaxprüfung aller Dateien.

## 8. Abnahme durch Max (0.5.0)
- Neues Spiel: Spice von Hand abbauen, „Spice-Verarbeitung“ wird fertig. 10 Melange → „Spice-Ernte“.
- Ernter bauen, auf Spice fahren, `Umschalt+H` oder Knopf: aufbauen, ernten, Status im Tooltip und Fenster, einpacken.
- Mit Festbrennstoff und Raketentreibstoff nicht schneller als mit Kohle (≤ 1,5 Kacheln/s).
- Ernter auf Sand lässt sich nicht aufheben, auf Fels schon. Im aufgebauten Ernter W drücken: nichts bewegt sich; Aussteigen geht.
- Annahme auf Fels, Ernter hinfahren: dockt an, Greifarme leeren, Stutzen tankt; `Umschalt+H` dockt ab, bleibt frei.
- Alter Spielstand (0.4.1) lädt; Bohrer auf Spice werden gemeldet. `/arrakis-test T13` und `T2b` laufen durch.
