# Umsetzungsplan Phase 3c (0.6.0): Ornithopter, Ablage, Anheben und Absetzen

Stand 25.10.2026. Grundlage: Design v0.3 (docs/design-ernter-ornithopter.md, kurz DOC), Plan 3b (docs/plan-3b.md),
Code 0.5.5 (main 7d784f9), Prüfstand-Lauf 0.5.5 vom 25.10.2026 ohne Spieler mit game.speed 10
(/mnt/project-files/pruefstand/2026-10-25/2026-10-25_0.5.5_7d784f9/arrakis-test-20261025-211533.txt, kurz RUN055) und
Ergebnisse 0.4.0 (/mnt/project-files/pruefstand/2026-10-07/ergebnisse.md, kurz ERG). API-Belege: A23 = factorio-types 1.2.72
(API 2.1.23, `dist/classes.d.ts`, `events.d.ts`, `prototypes.d.ts`), A20 = typed-factorio 3.36.0 (API 2.0.75),
V23 = Vanilla-Daten 2.1.23. Dieser Plan ist der Bauvertrag: Namen, Dateien, Zustände und Texte gelten so, wie sie hier
stehen. Wo der Plan von DOC abweicht, gilt der Plan; DOC wird danach angeglichen (Liste in 7).

Max' Wunsch: „es muss wie in den filmen und den büchern Spice harvester maschinen geben die mobil sind und die man via
ornikopter transportiert (und auch vor den würmern retten kann). Am anfang manuell, später in einer automatisierten form“.
3c liefert den manuellen Teil: Der Spieler fliegt den Ornithopter selbst. Die Automatik (Carryall, Leitstelle) kommt mit 3e/3f.

**Kennzeichnung:** **[Un]** markiert eine Aussage, die auf noch nicht geprüftem Engine-Verhalten beruht. Abschnitt 4.16
sagt je Annahme, welcher Test sie entscheidet und was gilt, wenn sie nicht hält.

## 0. Umfang

**In 0.6.0**
- Ornithopter `arrakis-ornithopter` (`spider-vehicle`, 4 unsichtbare, kollisionsfreie Beine, Brenner 800 kW, 2 Sitze),
  Item, Rezept, Trigger-Forschung „Ornithopter“ (ersten Spice-Ernter herstellen).
- Ablage-Oberfläche `arrakis-hold` mit 256 Stellplätzen.
- Ankoppeln (2 s), Anheben mit Notstart (aufgebaut, im Auf- oder Abbau, angedockt), Tragen mit Lastbild und Schatten,
  Absetzen mit Platzprüfung; abgesetzt auf einer Annahme dockt der Ernter wie gefahren an.
- Drei gleichwertige Bedienwege für Anheben/Absetzen: Taste `Umschalt+C`, Verknüpfung (Shortcut) in der Leiste, Knopf
  im Ornithopter-Fenster. Dazu ein eigener Fernbedienungs-Shortcut, ein Fernbedienungs-Knopf und Fernfahren aus der Karte.
- Insassen: Wer im Ernter sitzt, fliegt mit; nach dem Absetzen Knopf „In den Ernter steigen“.
- Tempo: leer 8, beladen 5,6 Kacheln/s über je einen eigenen Sticker.
- Absturzregeln: Tod des Ornithopters → Ernter fällt mit 30 % Schaden; anders entfernt → Ernter zurück zum Abhebepunkt;
  Tank leer → schwebt mit Last. Dazu Klon, Teleport, Abriss, gelöschte Oberflächen. Findet ein Ernter ohne Träger nirgends
  Platz, wartet er auf der Ablage und wird jede Sekunde neu versucht.
- Migration 0.5.x → 0.6.0 (Schema 2, Forschung für Spielstände mit Ernter nachholen), Befehl `/arrakis-uninstall`.
- Prüfstand: T15 (echter Code, automatisch), T16 (Flugphysik, automatisch), T17 (Bedienung, interaktiv).

**Nicht in 0.6.0**
- Würmer, Vibration, Wärme, Unruhe, Wurmzeichen, Countdown, Biss, Schonfrist, Briefings, Vorsichtsmodus (3d1 bis 3d3).
  Die Regel „getragen wird nie gefressen“ (DOC 2.4) setzt 3d1 auf dem Zustand `carried` aus 3c um. Die Mod-Einstellung
  `arrakis-worm-bite` bleibt unberührt.
- Carryall, Leitstelle, Aufträge, Hangar (3e), Flottenleitung (3f). Der Datensatz trägt schon `kind = "ornithopter"`,
  damit 3e denselben Code nutzt (DOC 2.5).
- Tragen anderer Fahrzeuge (Auto, Panzer, Spidertron) und mehrerer Ernter je Flieger.
- Ein Lastbild, das mit der Flugrichtung dreht, und eigene Grafik (Phase 6).
- 2.1-Komfort aus DOC 4.2 (Absetz-Vorschau am Cursor, Positionslichter): Phase 3g.
- Zweig `factorio-2.0`: bleibt bei 0.5.0 (DOC 5.2). Die Prototypen stehen trotzdem in 2.0-Schreibweise (3).

## 1. Festlegungen (Standardwahl, Max kann widersprechen)

| Punkt | Festlegung | Grund |
|---|---|---|
| Tempo | Ziel leer 8, beladen 5,6 Kacheln/s (beladen = 0,7 × leer) | DOC 2.4 verlangt ≥ 5 und „300 Kacheln in 50 bis 60 s“: beladen 54 s, leer 38 s. Der Ernter fährt 1,41 |
| Drossel | Immer genau ein eigener Sticker: `arrakis-ornithopter-empty` mit `vehicle_speed_modifier = 0.52` (= 8 / 15,4), `arrakis-ornithopter-loaded` mit `0.364` (= 0,7 · 0,52); Tausch beim Anheben und Absetzen | RUN055 T1: Sticker 0,7 → 70,1 % (10,8 von 15,4 Kacheln/s), zum dritten Mal gleich. Die Beine sind keine Stellschraube (doppelte Beinwerte ergeben 19,6 statt 15,4, nicht das Doppelte) |
| Last kostet Treibstoff | Kein Abzug per Skript (DOC 4.2 Punkt 5 entfällt) | RUN055 T1: Leistung konstant ≈ 810 kW, also kostet Last je Kachel von selbst mehr (75,0 statt 52,7 kJ/Kachel) |
| Antrieb | 4 Beine (Trab wie T1), Bein unverändert aus T1 (Faktor 1), Brenner `chemical` mit 2 Slots, `movement_energy_consumption = 800kW` | Das ist der in T1 gemessene Prüfling. 100 kJ/Kachel leer, 143 beladen; 100 Kohle reichen 500 s Flug |
| Werte | Konstanten im Code, keine Mod-Einstellung | Wie die Deckel-Werte in 3b; Balancing-Runde 3d3 |
| Taste | `arrakis-carry-toggle` = `SHIFT + C`, `consuming = "none"` | DOC 2.1 Schritt 8. ALT+O kam in T12 nie an (ERG), deshalb ist die Taste nie der einzige Weg |
| Rückfall ohne Taste | Shortcut `arrakis-carry` (`action = "lua"`) und Knopf im Ornithopter-Fenster; alle drei rufen dieselbe Funktion | Funktioniert, auch wenn eine Taste nicht ankommt oder doppelt belegt ist; der Shortcut auch in der Kartenansicht |
| Fernbedienung | Eigener Shortcut `arrakis-give-remote` (`spawn-item` `spidertron-remote`, frei mit „Ornithopter“) und Knopf „Fernbedienung“ im Fenster, der den Ornithopter gleich auswählt | Der Vanilla-Shortcut kommt erst mit „Spidertron“ (V23 base/prototypes/shortcuts.lua:222–235; T12 in docs/pruefstand.md) |
| Fernfahren | Ornithopter `allow_remote_driving = true`, Ernter bleibt `false` | DOC 4.2; Rettung aus der Karte ohne Fernflucht des Ernters (DOC 2.4) |
| Welcher Flieger | `player.vehicle`, dann Fernbedienungsauswahl (nächster zum Bezugspunkt), dann `player.selected`, dann der nächste eigene leere Ornithopter ≤ 4 Kacheln um den Ernter, in dem der Spieler sitzt oder auf den er zeigt | Die letzte Stufe ist die Solo-Rettung: im Ernter sitzen, den Ornithopter per Fernbedienung herholen, Taste |
| Welcher Ernter | `player.selected`, dann das Fahrzeug des Spielers, dann der nächste freie eigene Ernter; jeweils ≤ 4 Kacheln vom Flieger | DOC 4.2 Anheben 2; 4 Kacheln = Ankoppel-Abstand |
| Ankoppeln | 2 s (120 Ticks, im 10-Tick-Takt, also 120 bis 129 Ticks), Abbruch bei > 4 Kacheln oder zweitem Druck; der Ernter darf dabei fahren; Entprellen 15 Ticks je Flieger | DOC 2.4 und 4.2; Entprellen wie `harvester.DEBOUNCE` (scripts/harvester.lua:46) |
| Notstart | aufbauend, aufgebaut, einpackend → sofort mobil; angedockt → abgedockt; danach getragen | DOC 2.1 Schritt 8: „samt Verankerung herausgerissen“ |
| Sitze | Fahrer des Ernters → erster freier Sitz des Fliegers, Pilot zuerst; Beifahrer des Ernters → der übrige Sitz. Greift das Setzen nicht, wird die Figur an den Flieger gestellt und noch einmal gesetzt; erst wenn auch das scheitert oder kein Sitz frei ist, bleibt sie am Boden und bekommt einen Hinweis | Mit Pilot an Bord wird der Fahrer Beifahrer wie in DOC 4.2. Beim Fernflug ist der Pilotensitz leer; als Beifahrer könnte der Gerettete nicht wegfliegen (Abweichung von DOC 4.2) |
| Nach dem Absetzen | Insassen bleiben im Flieger; Knopf „In den Ernter steigen“ | DOC 4.2 Absetzen |
| Wer darf | Nur Ernter der eigenen Force; Anheben überall, wo der Ornithopter sein kann (Schwerkraft ≥ 1, geerbt), auch mit leerem Tank | Kein Diebstahl im Mehrspieler. Die Rettung darf nicht am Tank scheitern, Schweben kostet nichts [U10] |
| Was | Nur `spice-harvester`, einer je Flieger | Bauvertrag 3c; andere Fahrzeuge bräuchten eigene Bilder und Regeln |
| Absetzen | Probe `arrakis-harvester-probe` (±1,6 Kacheln, Maske des Ernters) an der Fliegerposition, sonst Suche im Radius 6, sonst Hinweis „Kein Platz“; die Last bleibt dran | Teleport zwischen Oberflächen prüft keine Kollision (A23 classes.d.ts:5476). Der Kasten deckt jede Ausrichtung des Ernters (halbe Diagonale 1,58) |
| Absturz | Ernter an der nächsten freien Stelle (Probe, Radius 6 → 16 → 32 um die Todesstelle, dann ebenso um den Abhebepunkt, dann Radius 6 → 16 → 32 → 64 um den Startpunkt der Force), Gesundheit − 30 % der Höchstgesundheit, direkt geschrieben, mindestens 1 | `damage()` ginge durch die Panzer-Resistenzen: Aufprall 50/80 % ergäbe aus 600 nur 110 LP (5,5 %). Totalverlust bleibt dem Wurm vorbehalten (3d1). Auch am Startpunkt wird gesucht, weil ein Teleport zwischen Oberflächen keine Kollision prüft (A23 classes.d.ts:5476) |
| Kein Landeplatz | Scheitern alle Stufen oder der Teleport: Der Ernter bleibt getragen auf der Ablage, steht in `storage.stranded` und wird jede Sekunde neu versucht; eine Meldung an die Force | Kein Ernter geht verloren, und keiner landet in Gebäuden. Kein Suchradius 0: Die Engine sucht dann ohne Ende (A23 classes.d.ts:20536) |
| Anders entfernt | Ernter zurück zum Abhebepunkt, ohne Schaden (gleiche Stufen ohne Todesstelle) | DOC 4.2 Sonderfälle |
| Tank leer | Flieger schwebt, Last bleibt | DOC 4.2; RUN055 T1: ohne Treibstoff bleibt er stehen |
| Ablage | `arrakis-hold`, angelegt beim ersten Anheben, 5 × 5 Chunks, 256 Plätze im 10er-Raster x, y ∈ {−60, −50, …, 90}, für alle Forces versteckt. Frei ist ein Platz, auf dem nichts steht; eine Liste freier Plätze gibt es nicht | DOC 4.2; alle Plätze liegen in den erzeugten Chunks (Kacheln −64 bis 95). Ohne Liste kann kein Platz verloren gehen, wenn ein Datensatz fehlt (Abweichung von DOC 4.2) |
| Lastbild | 16 Richtungen aus den Panzer-Sheets (Rumpf + Turm), getönt wie der Ernter, ohne Farbmaske; Richtung beim Anheben fest; hängt 1,5 Kacheln über dem Boden; Schatten als `draw_as_shadow` am Boden | T9 Schatten Variante A (ERG). Der Rumpf fliegt in Höhe 3. Drehen mit der Flugrichtung kommt mit eigener Grafik (Phase 6) |
| Sichtbarkeit | Lastbild und Schatten für alle Forces, Ankoppelring nur für die eigene | Sonst verschwände ein Ernter für andere spurlos (Abweichung von DOC 4.0 „Render-Objekte sieht nur die eigene Force“) |
| Forschung | `arrakis-ornithopter`, Trigger `craft-item` `spice-harvester` (Anzahl 1), Voraussetzung „Spice-Ernte“ | DOC 2.1 Schritt 3 und DOC 6 |
| Schonfrist | In 3c nichts speichern | Es gibt sie erst mit 3d1; dessen Migration startet sie beim Laden, wenn „Ornithopter“ schon erforscht ist |
| Alte Spielstände | „Ornithopter“ gilt als erforscht, wenn „Spice-Ernte“ erforscht ist und die Force einen Ernter hat oder je einen hergestellt hat | Der Trigger feuert nicht rückwirkend [U12] |
| Rezept | 30 Stahl, 20 Motoreinheit, 10 Fortgeschr. Schaltkreis, 10 Melange, 10 s | DOC 3.1 |
| Ornithopter-Werte | 3000 LP, Resistenzen, Leiche, Militärziel und Schwerkraft-Bedingung vom Spidertron geerbt; Kofferraum 10, keine Waffen, kein Gitter, Erkundungsradius 2; `torso_bob_speed = 0.4` | DOC 4.2 Prototypen; Optik prüft Max (T17) |
| Herunterstufen | Auf 0.5.x mit getragenem Ernter nicht unterstützt: vorher absetzen | 0.5.x kennt den Zustand nicht; Hinweis in changelog und README |
| Entfernen der Mod | `/arrakis-uninstall` (Admin, zweistufig mit `ja`): jeden Ernter auf der Ablage absetzen, dann die Ablage löschen; findet einer keinen Platz, bleibt die Ablage, und der Befehl meldet es | DOC 4.6 |
| Mindestversion | unverändert `base >= 2.1.23`, `space-age >= 2.1.23` | Ziel seit 0.5.1; nichts in 3c braucht mehr |

## 2. Dateien

Neu:
- `prototypes/ornithopter.lua`: Bein, Ornithopter (Entity, Item, Rezept), Forschung, zwei Sticker, 32 Sprites des Lastbilds,
  Probe, Taste, zwei Shortcuts.
- `prototypes/testbench/ornithopter.lua`: zwei Test-Sticker mit `vehicle_speed_max` für T16 (nur mit Prüfstand).
- `scripts/hold.lua`: Ablage-Oberfläche, Stellplätze, Verstecken.
- `scripts/flyer.lua`: Ornithopter-Datensätze, Bedienung, Ankoppeln, Anheben, Sitze, Absetzen, Tempo, Lastbild, Absturz,
  Landesuche und Warteliste, Pflege, `/arrakis-uninstall`. Die Modultabelle heißt `lib` (wie in scripts/harvester.lua:15–17:
  tools/check/api_names.py hält `flyer` und `harvester` für LuaEntity, tools/check/api_names.py:181–182). Andere Dateien binden es
  als `flyer_lib`.
- `scripts/flyer-gui.lua`: relatives Fenster am Ornithopter.
- `scripts/testbench/t_ornithopter.lua`: T15, T16, T17.

Geändert: `data.lua` (require `prototypes.ornithopter` direkt nach `prototypes.harvester`, vor `compat.finish`; die Probe
liest die Maske des Ernters), `prototypes/testbench/init.lua` (require), `control.lua` (Reihenfolge 4.1),
`scripts/harvester.lua`, `scripts/harvester-gui.lua`, `scripts/migrate.lua`, `locale/*/arrakis.cfg`, `locale/*/messages.cfg`,
`locale/*/testbench.cfg` (`[entity-name]` für `arrakis-test-speed-max-tick` und `arrakis-test-speed-max-second`),
`scripts/testbench/runner.lua` (ORDER, Modulliste, Weiterleitung, Vertrag), `tools/check/checks.lua`,
`tools/pc/pruefstand.py` (Hilfetexte Z. 34 und 767: interaktiv sind T9, T12 und T17), `info.json`, `changelog.txt`,
`README.md`, `docs/pruefstand.md` (6), DOC (danach, 7).

Unverändert: `scripts/intake.lua` (Andocken nach dem Absetzen läuft über `undocked_from = nil`, 4.8), `scripts/terrain.lua`,
`prototypes/testbench/flyers.lua`, `scripts/testbench/t_flyer.lua` (T1, T9, T12 bleiben, wie sie sind).

## 3. Prototypen (2.0-Schreibweise; `compat.finish` setzt 2.1 um)

**Bein** `arrakis-flyer-leg` (Name wie DOC 3 und 4.2: Der Carryall in 3e kann es mitbenutzen, und ein Bein im Spielstand muss
später nicht umbenannt werden): wie `make_leg(name, 1)` in prototypes/testbench/flyers.lua:19–33 (deepcopy
`spidertron-leg-1`, `hidden = true`, `graphics_set = nil`, Geräusche aus, keine Sterbe-Trigger, `collision_mask = {layers = {}}`).
Bewusst eine Kopie der Funktion: Die Test-Prototypen gibt es nur mit Prüfstand, und T1 misst weiter die alten Prüflinge.

**Ornithopter** `arrakis-ornithopter`: `table.deepcopy(data.raw["spider-vehicle"]["spidertron"])`, dann
- `icon = nil`, `icons` = Spidertron-Icon mit Sandtönung `{r = 1, g = 0.85, b = 0.55}`, `minable = {mining_time = 1, result = "arrakis-ornithopter"}`,
  `factoriopedia_simulation = nil`, `guns = nil`, `equipment_grid = nil`, `trash_inventory_size = 0`, `inventory_size = 10`,
  `chunk_exploration_radius = 2`, `allow_remote_driving = true`, `torso_bob_speed = 0.4`.
- Flug wie T1: `height = 3`, `alert_icon_shift = {0, -3}`, `drawing_box_vertical_extension = 4`, `graphics_set.render_layer = "air-object"`,
  Rumpf getönt (gleiche `tint_layers`-Regel wie flyers.lua:7–15), kein `tall` (DOC 4.2).
- `energy_source = {type = "burner", fuel_categories = {"chemical"}, effectivity = 1, fuel_inventory_size = 2}`,
  `movement_energy_consumption = "800kW"`.
- `spider_engine.legs`: 4 × `arrakis-flyer-leg` an den Vanilla-Positionen 1, 8 (Gruppe 1) und 5, 4 (Gruppe 2) wie flyers.lua:67–69.
- Geerbt und so gewollt: `max_health = 3000`, Resistenzen, `corpse`, `dying_explosion`, `is_military_target = true`,
  `surface_conditions` (Schwerkraft ≥ 1, V23 space-age/base-data-updates.lua:192), Kollision ±1, `sticker_box` ±1,5,
  `collision_mask` nicht gesetzt (Vorgabe nur `trigger_target`, V23 core/lualib/collision-mask-defaults.lua:190).
- Nach dem deepcopy: kein `factoriopedia_alternative` und kein anderes 2.1-Feld übernehmen, das auf den Spidertron zeigt (DOC 5.5); die Liste liefert der Dump in 7.

**Item** `arrakis-ornithopter`: deepcopy von `data.raw["item-with-entity-data"]["spidertron"]` (Gewicht und Geräusche bleiben),
`icon = nil`, Icon wie die Entity, `icon_tintable`, `icon_tintable_mask`, `icon_tintable_size`, `icon_tintable_mask_size`,
`icon_tintables` und `icon_tintable_masks` auf nil (der Spidertron bringt die ersten beiden mit, V23 base/prototypes/item.lua:2117–2118;
sonst zeigte ein Item mit gespeicherter Farbe das getönte Spidertron-Bild, A23 prototypes.d.ts:5330–5356), `place_result = "arrakis-ornithopter"`, `subgroup = "transport"`, `order = "b[personal-transport]-z[spice-ornithopter]"`
(direkt nach dem Ernter), `stack_size = 1`, `default_import_location = "arrakis"`.
**Rezept** `arrakis-ornithopter`: 30 steel-plate, 20 engine-unit, 10 advanced-circuit, 10 melange; `energy_required = 10`; `enabled = false`.

**Forschung** `arrakis-ornithopter`: Spidertron-Forschungsbild getönt, `prerequisites = {"arrakis-spice-harvesting"}`,
`research_trigger = {type = "craft-item", item = "spice-harvester"}` (A23 types.d.ts:3373–3377), `effects = {{type = "unlock-recipe", recipe = "arrakis-ornithopter"}}`.
Die Shortcuts hängen über `technology_to_unlock` an ihr.

**Sticker** `arrakis-ornithopter-empty` und `arrakis-ornithopter-loaded`: `type = "sticker"`, `hidden = true`, `flags = {"not-on-map"}`,
`duration_in_ticks = 216000` (1 h), `vehicle_speed_modifier = 0.52` bzw. `0.364`, keine Animation (wie flyers.lua:114–123, in T1 geladen und wirksam).

**Lastbild** `arrakis-harvester-carried-<i>` und `arrakis-harvester-carried-shadow-<i>` für i = 0 … 15 (`type = "sprite"`, je zwei Ebenen),
aus den Panzer-Sheets (V23 base/prototypes/entity/entities.lua:8079–8222, `tank_shift_y = 6` in Z. 43). Mit d = 4 · i (von 64 Richtungen, 0 = Nord, im Uhrzeigersinn):
- Rumpf: `tank-base-<floor(d/16)+1>.png`, x = 0, y = (d mod 16) · 212, 270 × 212, `scale = 0.5`, `shift = by_pixel(0, -10)`.
- Turm: `tank-turret.png`, x = (d mod 8) · 179, y = floor(d/8) · 132, 179 × 132, `scale = 0.5`, `shift = by_pixel(0.25, -34.5)`.
- Beide mit der Ernter-Tönung `{r = 1, g = 0.8, b = 0.5}` (prototypes/harvester.lua). Die Farbmaske (`apply_runtime_tint`) fehlt bewusst.
- Schatten: `tank-base-shadow-<floor(d/16)+1>.png`, x = 0, y = (d mod 16) · 194, 302 × 194, `scale = 0.5`, `shift = by_pixel(22.5, 7)`, und
  `tank-turret-shadow.png`, x = (d mod 8) · 193, y = floor(d/8) · 134, 193 × 134, `scale = 0.5`, `shift = by_pixel(56.25, 6.5)`;
  beide `draw_as_shadow = true`, ungetönt. Auch die Vanilla-Schatten sind HR-Bilder mit `scale = 0.5` (V23 entities.lua:8179, :8218);
  ohne Angabe gälte 1, und der Schatten würde doppelt so groß wie das Lastbild.

**Probe** `arrakis-harvester-probe`: deepcopy von `data.raw["simple-entity-with-owner"]["simple-entity-with-owner"]` (V23 entities.lua:9953),
`hidden = true`, `flags = {"not-on-map", "placeable-off-grid", "not-blueprintable", "not-deconstructable"}`, `minable = nil`,
`collision_box = {{-1.6, -1.6}, {1.6, 1.6}}`, `collision_mask = collision_mask_util.get_mask(data.raw.car["spice-harvester"])`
(Kopie; beim Panzer die Auto-Vorgabe `player, car, train, is_object`, collision-mask-defaults.lua:174). Sie wird nie gebaut, nur abgefragt.

**Taste** `{type = "custom-input", name = "arrakis-carry-toggle", key_sequence = "SHIFT + C", consuming = "none"}`.

**Shortcuts** (Muster V23 base/prototypes/shortcuts.lua:222–235):
- `arrakis-carry`: `action = "lua"`, `associated_control_input = "arrakis-carry-toggle"` (nur für den Tooltip),
  `technology_to_unlock = "arrakis-ornithopter"`, `unavailable_until_unlocked = true`, `localised_name = {"shortcut-name.arrakis-carry"}`,
  `order = "e[spidertron-remote]-z[arrakis-a]"`, Icons: Panzer-Icon (64 px) mit Ernter-Tönung als `icons` und `small_icons`.
- `arrakis-give-remote`: deepcopy von `give-spidertron-remote`, `associated_control_input = nil`,
  `technology_to_unlock = "arrakis-ornithopter"`, `localised_name = {"shortcut-name.arrakis-give-remote"}`, `order = "e[spidertron-remote]-z[arrakis-b]"`.
  Die Locale-Kategorie der Shortcuts ist lokal nicht belegt, deshalb steht `localised_name` ausdrücklich da.

**Prüfstand** (`prototypes/testbench/ornithopter.lua`): `arrakis-test-speed-max-tick` (`vehicle_speed_max = 8 / 60`) und
`arrakis-test-speed-max-second` (`vehicle_speed_max = 8`), sonst wie die Sticker oben. Das Feld gibt es in 2.0.75 (A20
prototype/generated/prototypes.d.ts:14036) und 2.1.23 (A23 prototypes.d.ts:9947), ohne dokumentierte Einheit [U22]. Nur T16 misst sie.

## 4. Laufzeit

### 4.1 Module und Ereignisse
`control.lua` lädt per event_handler in dieser Reihenfolge: `scripts.migrate`, `scripts.arrakis-surface`, `scripts.harvester`,
`scripts.harvester-gui`, `scripts.intake`, `scripts.hold`, `scripts.flyer`, `scripts.flyer-gui`, (Prüfstand). Wie in 3b ruft
kein Modul `script.on_event` oder `script.on_nth_tick` direkt auf. `on_init` und `on_configuration_changed` laufen in dieser
Reihenfolge (migrate zuerst). Für ein Ereignis, das mehrere Module behandeln, ist die Reihenfolge zwischen den Modulen dagegen
nicht zugesichert: event_handler fasst die Handler je Ereignis mit `pairs` zusammen (V23 core/lualib/event_handler.lua).
Deshalb gilt: Jeder Fall gehört genau einem Modul, und kein Handler verlässt sich darauf, dass ein anderer schon lief.
Beispiel: Stirbt ein getragener Ernter, löscht harvester.lua seinen Datensatz; flyer.lua findet den Träger über
`storage.flyers` (`cargo == un`), nie über den Datensatz des Ernters.

`scripts.hold` stellt bereit: `ensure() → LuaSurface`, `surface() → LuaSurface|nil`, `take_slot() → {x, y}|nil`,
`free_count()`, `forget()` (nach dem Löschen), `NAME = "arrakis-hold"`. Es gibt kein `free_slot`: Ein Platz wird frei, sobald nichts
mehr auf ihm steht (4.11). Ereignis: `on_force_created` (neue Force bekommt die Ablage versteckt).

`scripts.flyer` stellt bereit: `get(entity)`, `register(entity)`, `toggle_carry(flyer_entity, harvester_entity|nil, player|nil) → ok, reason`,
`resolve_flyer(player)`, `resolve_harvester(flyer_entity, player|nil)`, `drop(record, player|nil) → ok, reason`, `crash(record)`,
`return_cargo(record, reason)`, `land_cargo(h, crash_pos|nil, damage) → ok` (Landesuche ohne Träger, sonst `storage.stranded`, 4.10),
`care(record)` (Pflege eines Datensatzes wie im 60-Tick-Takt), `retry_stranded()` (wie der 60-Tick-Takt), `update_couplings()`
(wie der 10-Tick-Takt), `state_text(record)`, `board_harvester(record, player)`, `give_remote(record, player)`, `uninstall() → n, rest`,
Konstanten `COUPLE_TICKS = 120`, `COUPLE_RANGE = 4`, `DEBOUNCE = 15`, `CRASH_DAMAGE = 0.3`, `SEARCH_RADII = {6, 16, 32}`,
`SPAWN_RADII = {6, 16, 32, 64}`, `STICKER_EMPTY`, `STICKER_LOADED`, `IMAGE_OFFSET = {0, -1.5}`, `SHADOW_OFFSET = {1, 1}`.
Eintragen gilt wie beim Ernter (scripts/harvester.lua:519, :821): Wer einen Ornithopter braucht, ruft `get(entity) or register(entity)`.
So bekommt auch einer, der per Skript oder von einer anderen Mod ohne `raise_built` entstand, beim ersten Kontakt Datensatz und Sticker.
Ereignisse von flyer.lua:

| Ereignis | Ornithopter | Spice-Ernter |
|---|---|---|
| `on_built_entity`, `on_robot_built_entity`, `script_raised_built`, `script_raised_revive` | eintragen, leer (Sticker leer) | – |
| `on_entity_cloned` | Klon leer eintragen; Original unverändert | – (harvester.lua trägt den Klon mobil ein) |
| `on_entity_died` | Absturz (4.10) | Kopplung abbrechen; war er getragen: Träger leeren; aus `storage.stranded` streichen |
| `on_player_mined_entity`, `on_robot_mined_entity`, `script_raised_destroy` | Last zum Abhebepunkt, austragen | Kopplung abbrechen; Träger leeren; aus `storage.stranded` streichen |
| `on_object_destroyed` (`reg.kind == "flyer"`) | wie oben, falls der Datensatz noch da ist | – (gehört harvester.lua) |
| `on_marked_for_deconstruction` | beladen: `cancel_deconstruction(force)` | – |
| `script_raised_teleported` | Bilder neu zeichnen, Kopplung prüfen | getragen und nicht mehr auf der Ablage: landen wie `care` Fall b (4.4) |
| `on_player_driving_changed_state` | `get or register` (Spieler steigt ein oder aus) | – (gehört harvester.lua) |
| `on_pre_surface_deleted` | 4.10 | 4.10 |
| `arrakis-carry-toggle`, `on_lua_shortcut` (`prototype_name == "arrakis-carry"`) | 4.5 | 4.5 |

Dazu `on_nth_tick` 10 und 60 (4.4), `on_configuration_changed` (4.15), `add_commands` (`/arrakis-uninstall`, Muster
scripts/arrakis-surface.lua:29–31). Handler prüfen zuerst den Namen und kehren sonst sofort zurück. `on_player_driving_changed_state`
hat immer einen `player_index` (A23 events.d.ts:2561); eine Puppe ohne Spieler löst es nicht aus, unregistrierte Prüfstand-Flieger
(T16) bleiben also unregistriert.

`scripts.harvester` bekommt (sonst unverändert):
- `LOCKED` (scripts/harvester.lua:50) um `carried = true` erweitert. Damit gilt der Ernter als gesperrt und nicht abbaubar
  (`refresh_minable`, Z. 325–334), und der Tempo-Deckel trägt ihn aus (`on_tick`, Z. 701–728).
- `update_timer` (Z. 679–691) prüft statt `not LOCKED[h.state] or h.state == "deployed"` eine eigene Tabelle
  `TIMED = {deploying = true, packing = true}`. Sonst verglich ein getragener Ernter `tick >= h.timer_end` mit nil (Skriptfehler).
- `toggle` (Z. 513–540): Zweig `carried` → Hinweis `hint-carried`, false.
- `on_teleported` (Z. 792–804): Zustand `carried` → nichts tun (vorher prüfen, sonst risse `to_mobile` ihn los). Landet ein
  fremdes Skript ihn außerhalb der Ablage, holt flyer.lua ihn herunter (4.4 `care` Fall b).
- `lib.lift(h, carrier_un, lift_pos)`: `lib.to_mobile(h)` (Notstart; angedockt → abdocken), dann `state = "carried"`,
  `carried_by`, `lift_pos` setzen, `undocked_from = nil`, `still_since = nil`, `storage.driven[un] = nil`,
  `storage.timers[un] = nil`, `entity.speed = 0` (ein angekoppelt fahrender Ernter rollte nach dem Absetzen sonst weiter),
  `lock(entity)`, `write_custom_status(h)`, `refresh_minable(h)`.
- `lib.land(h)`: `carried_by`, `lift_pos`, `undocked_from` auf nil, dann `set_mobile(h)` (entsperrt, Abbausperre und
  Tempo-Ausgleich am neuen Ort, `last_tick`).
- Kopfkommentar: Zustand `carried`, Verweis auf diesen Plan.

`scripts.harvester-gui`: `BUTTON_CAPTION.carried = "gui-carried"`, Knopf gesperrt (Z. 47–48 um `carried` erweitern); der
30-Tick-Takt schließt das Fenster auch, wenn der Ernter getragen wird.

### 4.2 storage (Schema 2)
```lua
storage.schema = 2
storage.harvesters[un] = {…,                      -- wie Schema 1 (plan-3b.md 4.2), dazu:
  state = …|"carried",
  carried_by = flyer_un|nil,                      -- nil, solange er in storage.stranded wartet
  lift_pos = {surface = surface_index, x, y}|nil, -- Abhebepunkt
}
storage.flyers[un] = {
  un, entity, kind = "ornithopter",
  cargo = harvester_un|nil,
  coupling = {harvester = harvester_un, start_tick, done_tick, player_index|nil}|nil,
  renders = {image = LuaRenderObject|nil, shadow = LuaRenderObject|nil, ring = LuaRenderObject|nil},
  sticker = LuaEntity|nil,                        -- der eine eigene Sticker
  image_index = 0..15|nil,                        -- Richtung des Lastbilds, beim Anheben fest
  last_cargo = LuaEntity|nil,                     -- zuletzt abgesetzter Ernter (Knopf „In den Ernter steigen“)
  last_toggle_tick = 0,
}
storage.couplings[flyer_un] = true                -- laufende Kopplungen (10-Tick-Takt)
storage.stranded[harvester_un] = {                -- Ernter ohne Träger und ohne Landeplatz (4.10)
  crash_pos = {surface = surface_index, x, y}|nil,-- Todesstelle des Fliegers, nur beim Absturz
  damage = true|nil,                              -- 30 % Schaden steht noch aus
  reason = "crash"|"returned",
}
storage.hold = {surface = LuaSurface|nil}         -- keine Liste: frei ist, worauf nichts steht (4.11)
storage.flyer_gui_open[player_index] = flyer_un
storage.reg[registration_number] = {kind = "harvester"|"intake"|"nozzle"|"flyer", un = un}
```
`migrate.init()` legt `flyers`, `couplings`, `stranded`, `hold`, `flyer_gui_open` an. Abweichung von DOC 4.5: `docking` heißt `coupling`;
`hangar`, `job`, `manual`, `last_tick` kommen mit 3e. DOC 4.5 zeigt das Gesamtbild als „Schema 2“; der Plan zählt je Phase hoch
(3c = 2, 3d1 = 3).

### 4.3 Zustände und Übergänge
Spice-Ernter (3b-Tabelle in plan-3b.md 4.3, dazu Spalten und Zeile für das Tragen):

| Zustand \ Eingabe | Taste/Knopf (`Umschalt+H`) | Kopplung fertig | Absetzen | Tod/Abbau | Teleport/Klon |
|---|---|---|---|---|---|
| mobile | wie 3b | → carried | – | wie 3b | wie 3b |
| deploying | wie 3b | Notstart → carried | – | wie 3b | wie 3b |
| deployed | wie 3b | Notstart → carried | – | wie 3b | wie 3b |
| packing | wie 3b | Notstart → carried | – | wie 3b | wie 3b |
| docked | wie 3b | abdocken → carried | – | wie 3b | wie 3b |
| carried | Hinweis „wird getragen“ | – | → mobile (`land`) | aufräumen; flyer.lua leert den Träger | Teleport auf der Ablage: bleibt carried; von der Ablage weg: flyer.lua → mobile (`land`, 4.4 `care` Fall b); Klon: Klon mobil eingetragen, Original bleibt carried |

Ornithopter:

| Zustand \ Eingabe | Taste/Shortcut/Knopf | 10-Tick-Takt | Tod | anders entfernt | Tank leer | Teleport | Klon |
|---|---|---|---|---|---|---|---|
| leer | Ernter gefunden → koppelt (Ring, Hinweis); sonst Hinweis | – | austragen | austragen | – | – | Klon leer |
| koppelt | → leer (Abbruch) | ungültig, andere Oberfläche oder > 4 Kacheln → leer + Hinweis; Zeit um → Anheben → beladen (scheitert es: leer + Hinweis) | Ring weg, austragen | Ring weg, austragen | koppelt weiter | gleiche Oberfläche: Abstand zählt; andere: Abbruch | Klon leer |
| beladen | Absetzen → leer; kein Platz: bleibt beladen + Hinweis | – | Absturz (4.10) | Ernter zum Abhebepunkt | schwebt, bleibt beladen | Bilder neu (sofort bei `script_raised_teleported`, sonst im 60-Tick-Takt) | Klon leer, Original bleibt beladen |

- Entprellen: ein zweiter Aufruf für denselben Flieger innerhalb 15 Ticks wird ignoriert (`last_toggle_tick`).
- Beladen: `flyer.minable_flag = false`, Sticker beladen. Leer: `minable_flag = true`, Sticker leer.
- Ein Ernter ist höchstens in einer Kopplung und an höchstens einem Flieger; ein zweiter Flieger bekommt `hint-coupling-busy`.

### 4.4 Takte
- `on_tick`: nichts Neues. Der Deckel aus 3b trägt getragene Ernter aus (nicht mobile).
- flyer `on_nth_tick(10)`: `if next(storage.couplings) == nil then return end`. Je Kopplung: Flieger und Ernter gültig, gleiche
  Oberfläche, Abstand ≤ 4, Ernter nicht schon getragen, Flieger leer; sonst Abbruch. Ring nachführen. Ab `done_tick`: Anheben (4.6).
- flyer `on_nth_tick(60)`, Pflege je Ornithopter (`care`): ungültig → austragen (Last wie „anders entfernt“). Beladen: Ernter-Datensatz
  da, Entity gültig und auf `arrakis-hold`: in Ordnung. Sonst zwei Fälle:
  a) Datensatz fehlt oder Entity ungültig: Last-Eintrag leeren, Bild weg, Sticker leer, `minable_flag = true`, Log und `msg-cargo-lost`.
  b) Entity gültig, aber nicht auf der Ablage (ein fremdes Skript hat sie wegteleportiert; harvester.lua tut bei `carried` nichts):
     `harvester.land(h)` am jetzigen Ort, Flieger leeren wie in a), Log, keine Meldung. Sonst bliebe der Ernter für immer gesperrt.
  Sticker (4.9) und Render-Objekte (4.12) prüfen und neu anlegen. Danach `retry_stranded()`:
  `if next(storage.stranded) == nil then return end`, sonst je Eintrag die Landesuche aus 4.10 noch einmal; ein Eintrag ohne gültigen
  Ernter oder ohne Datensatz wird gestrichen. Kosten: ein Durchlauf über `storage.flyers` je Sekunde, dazu die (meist leere) Liste
  `storage.stranded`.
- flyer-gui `on_nth_tick(30)`: offene Fenster auffrischen (Countdown, Laderaum), schließen bei ungültigem Flieger.

### 4.5 Bedienung: Taste, Shortcut, Knopf, Fernbedienung
Alle drei Wege rufen `toggle_carry(flyer, nil, player)`; die Taste und der Shortcut suchen den Flieger vorher mit `resolve_flyer`.
`toggle_carry` holt den Datensatz mit `get(flyer) or register(flyer)` (4.1). Für denselben Druck wirkt die Funktion auf genau einen Flieger:
- beladen → Absetzen (4.8); koppelt → Abbruch; leer → Ernter suchen (`resolve_harvester`), gefunden → Kopplung starten, sonst `hint-no-harvester`.
- Fremder Flieger → `hint-flyer-foreign`; fremder Ernter → `hint-foreign` (gibt es schon).

`resolve_flyer(player)`, erste Stufe mit Treffer gilt (nur `arrakis-ornithopter` der eigenen Force):
1. `player.vehicle` [U2].
2. `player.spidertron_remote_selection` [U3, U4, U5]: der Ornithopter, der dem Bezugspunkt am nächsten ist. Bezugspunkt:
   ausgewählter Ernter, sonst `event.cursor_position` (nur bei der Taste, A23 events.d.ts:18–60), sonst `player.position`.
3. `player.selected` [U3].
4. Sitzt der Spieler in einem Ernter (`player.physical_vehicle`, A23 classes.d.ts:16579) oder zeigt er auf einen: der nächste
   eigene leere Ornithopter ≤ 4 Kacheln um diesen Ernter (`find_entities_filtered{name, position, radius = 4, force}`).
Kein Treffer → `hint-no-flyer`.

`resolve_harvester(flyer, player)`, jeweils eigene Force, ≤ 4 Kacheln vom Flieger, nicht getragen, nicht in einer Kopplung:
1. `player.selected`, 2. `player.physical_vehicle` bzw. `player.vehicle`, wenn es ein Ernter ist, 3. der nächste
`spice-harvester` per `find_entities_filtered{name = "spice-harvester", position = flyer.position, radius = 4, force}`.
Unregistrierte Funde trägt `harvester.register` ein (wie `lib.get(entity) or lib.register(entity)`).

- **Taste** `arrakis-carry-toggle`: wirkt auch aus der Kartenansicht und während des Fernfahrens [U1, U2, U3].
- **Shortcut** `arrakis-carry`: `on_lua_shortcut` mit `prototype_name == "arrakis-carry"` (A23 events.d.ts:1549), sonst gleich.
  Er ist der Rückfall, wenn die Taste nicht ankommt (T12-Befund), und geht in der Kartenansicht.
- **Knopf** im Ornithopter-Fenster (4.13): Flieger = das offene Fenster, keine Suche.
- **Fernbedienung:** Shortcut `arrakis-give-remote` (Engine legt `spidertron-remote` in die Hand) oder Knopf „Fernbedienung“:
  `if player.clear_cursor() then player.cursor_stack.set_stack{name = "spidertron-remote"}; player.spidertron_remote_selection = {flyer} end`,
  sonst `hint-remote-cursor` (A23 classes.d.ts:15991, :16616) [U5]. Rechtsklick in der Karte schickt den Ornithopter (Engine-Autopilot).
- **Fernfahren:** `allow_remote_driving = true`; der Spieler fährt den Ornithopter aus der Karte und drückt Taste oder Shortcut [U2].
- Aus der Ferne gilt dieselbe Force-Regel wie in 3b (Bedienung aus der Ferne erlaubt, plan-3b.md 1).

### 4.6 Ankoppeln und Anheben
Kopplung starten: `coupling = {harvester = harvester_un, start_tick = tick, done_tick = tick + 120, player_index}`,
`storage.couplings[flyer_un] = true` (Schlüssel ist immer der Flieger, 4.2), Ring um den Ernter (nur eigene Force), Hinweis
`hint-coupling-start` (2 s über dem Ernter bleiben). Der Ernter darf weiterfahren.
Anheben, wenn der 10-Tick-Takt `done_tick` erreicht (Reihenfolge fest):
1. Datensatz des Ernters holen oder anlegen; Ernter gültig, eigene Force, nicht getragen. Platz in der Ablage: `hold.ensure()`,
   `slot = hold.take_slot()`; kein Platz → `hint-hold-full`, Kopplung endet (`coupling = nil`, `storage.couplings[flyer_un] = nil`).
2. Fenster schließen: jeder Spieler mit `player.opened == harvester` bekommt `player.opened = nil` (harvester-gui räumt in `on_gui_closed` auf).
3. Insassen merken und herausnehmen: `harvester.get_driver()`, `harvester.get_passenger()`, dann `set_driver(nil)`, `set_passenger(nil)`
   (A23 classes.d.ts:7402, :7470–7475) [U14]. Ohne das reiste der Fahrer mit auf die Ablage (RUN055 T3 a: „Fahrer sitzt im Ernter, auf arrakis-test-hold“).
4. `harvester.lift(h, flyer_un, {surface = surface.index, x, y})` (Notstart, sperren, 4.1).
5. `ok = harvester_entity.teleport(slot, hold_surface)`. Bei false: `harvester.land(h)`, Insassen zurück in den Ernter, Log,
   `hint-lift-failed`; der Platz bleibt von selbst frei. Ein Teleport zwischen Oberflächen prüft keine Kollision, deshalb nur
   freie Plätze (4.11) [U13].
6. Insassen setzen (4.7).
7. Flieger: `cargo = harvester_un`, `minable_flag = false`, Sticker beladen (4.9), Lastbild und Schatten zeichnen (4.12), Ring weg,
   `coupling = nil`, `storage.couplings[flyer_un] = nil`.
Die Bewegung des Ernters hält `disabled_by_script` (in T2 bestätigt); seine Ladung, Treibstoff, Gesundheit, Qualität, Farbe,
unit_number und Ausrichtung bleiben beim Teleport erhalten (RUN055 T3 b: 10/10 gleich, auf der Ablage und zurück).

### 4.7 Sitze
- Reihenfolge: zuerst der Fahrer des Ernters, dann sein Beifahrer. Jeder bekommt den ersten freien Sitz des Fliegers, Pilot zuerst
  (`flyer.get_driver() == nil` → `set_driver`, sonst `get_passenger() == nil` → `set_passenger`).
- Insasse ist eine Spielfigur (LuaEntity) oder ein LuaPlayer (`get_driver` liefert beides, A23 classes.d.ts:6838). Den Besitzer einer
  Figur bestimmt `for _, p in pairs(game.players) do if p.character == figur then … end end`; `figur.player` bzw. `figur.associated_player`
  ist nur die Abkürzung, denn in der Fernsicht ist `figur.player` nicht verlässlich gesetzt (deshalb sucht schon
  scripts/testbench/runner.lua:314–331 über `player.character`). Ist dieser Spieler in der Fernsicht (`controller_type == remote`),
  zuerst `player.exit_remote_view()` (DOC 5.5; CL:870) [U15]. Erst danach wird der freie Sitz bestimmt: Fuhr dieser Spieler den
  Flieger gerade fern, ist der Pilotensitz jetzt frei.
- Danach zurücklesen. Sitzt ein Insasse nicht, wo er sitzen soll, und ist ein Sitz frei: Rückfall Stufe 1 `figur.teleport(flyer.position)`
  (gleiche Oberfläche, die Figur steht höchstens 4 Kacheln entfernt), dann `set_driver` bzw. `set_passenger` noch einmal und
  zurücklesen [U14]. Scheitert auch das oder ist kein Sitz frei, bleibt er am Boden (die Engine hat ihn in Schritt 3 neben den Ernter
  gestellt, Stufe 1 an den Flieger) und bekommt `hint-seat-full`; Log mit Name und Stufe.
- Absetzen ändert die Sitze nicht. Knopf „In den Ernter steigen“ (4.13): sichtbar, wenn der Spieler im Flieger sitzt, `last_cargo`
  gültig ist, ≤ 6 Kacheln entfernt steht und sein Fahrersitz frei ist; dann Spieler aus dem Flieger (`set_driver(nil)` bzw.
  `set_passenger(nil)`) und `last_cargo.set_driver(player)` [U14].

### 4.8 Absetzen
1. Ort: Fliegerposition. `surface.can_place_entity{name = "arrakis-harvester-probe", position, force, build_check_type = defines.build_check_type.manual}`
   (A23 classes.d.ts:20060–20085); sonst `surface.find_non_colliding_position("arrakis-harvester-probe", position, 6, 0.5)` mit
   `is_chunk_generated` für das Ergebnis [U19]. Nichts gefunden → `hint-no-space`, Rückgabe `false, "no_space"`, die Last bleibt.
2. `ok = harvester_entity.teleport(pos, flyer.surface)` (Ausrichtung bleibt); false → Log, `hint-no-space`, Last bleibt.
3. `harvester.land(h)`. Der Stellplatz ist damit frei (4.11).
4. Flieger: `cargo = nil`, `last_cargo = harvester_entity`, Bild und Schatten löschen, Sticker leer, `minable_flag = true`.
5. Steht der Ernter ≤ 4 Kacheln an einer freien Annahme, dockt er nach 2 s Stillstand an (scripts/intake.lua:219–254;
   `undocked_from` ist nil, siehe `land`). Abdocken durch Anheben steht in Schritt 4 von 4.6.

### 4.9 Tempo und Last
- Gemessen (RUN055 T1, 4 Beine, Raketentreibstoff): 15,4 Kacheln/s ohne Sticker, 10,8 mit `vehicle_speed_modifier = 0.7`
  (70,1 %), 52,7 kJ/Kachel ohne und 75,0 mit Sticker, also ≈ 810 kW in beiden Fällen. Höchstwert nach Norden 16,1 (RUN055 T5d),
  gleich dem nach Osten (16,1 bei Reisetempo 15,4, T1); ob die Richtung das Reisetempo ändert (die Beine drehen nicht mit,
  docs/pruefstand.md, Bekannte Grenzen), misst T16.
- Daraus: leer 0,52 → 8,0 Kacheln/s, beladen 0,364 → 5,6 [U6]. Der Verbrauch je Kachel steigt auf 100 bzw.
  143 kJ; Treibstoff für Last zieht das Skript nicht ab. Brennstoff und Qualität sollen das Tempo nicht ändern [U7, U8].
- Genau ein eigener Sticker je Flieger: `surface.create_entity{name, position = flyer.position, target = flyer, force = flyer.force}`
  (wie scripts/testbench/t_flyer.lua:508). Tausch: alten Sticker `destroy()`, neuen erzeugen, im Datensatz merken.
- Pflege im 60-Tick-Takt und in `register`: Der gemerkte Sticker taugt, wenn er gültig ist, `sticker.sticked_to == flyer` gilt
  (A23 classes.d.ts:8552), sein Name zum Zustand passt und `time_to_live >= 108000` ist. Dann werden die eigenen Sticker in
  `flyer.stickers` (A23 classes.d.ts:8564) gezählt, also die mit Name `arrakis-ornithopter-empty` oder `-loaded`: Jeder außer dem
  gemerkten wird zerstört (ein Klon oder ein fremdes Skript kann einen zweiten bringen; 0,52 · 0,364 ergäbe sonst etwa 2,9 Kacheln/s).
  Taugt der gemerkte nicht, werden alle eigenen zerstört und ein neuer angeheftet. `time_to_live` wird nur gelesen
  (A23 classes.d.ts:8615), nie geschrieben [U9]. Fremde Sticker (z. B. Verlangsamungskapsel) bleiben und wirken zusätzlich.
- Ausweichweg, falls U6 nicht hält: T16 gibt die passenden Modifier als INFO aus; sie werden als Konstanten übernommen.
  Erst wenn auch das nicht linear genug ist: `vehicle_speed_max` (T16 misst es, [U22]).

### 4.10 Absturzregeln und Sonderfälle
- **Landesuche** `land_cargo(h, crash_pos, damage)`, gemeinsam für Absturz, „anders entfernt“, Waisen, gelöschte Oberflächen und
  `storage.stranded`. Stufen, die erste mit Treffer gilt:
  1. nur beim Absturz: um `crash_pos` mit der Probe (4.8) in `SEARCH_RADII` (6, 16, 32);
  2. um den Abhebepunkt `h.lift_pos` ebenso, wenn es seine Oberfläche noch gibt;
  3. um den Startpunkt der Force: `force.get_spawn_position(s)` auf der Oberfläche des Abhebepunkts, fehlt sie, auf Arrakis, sonst
     nauvis (A23 classes.d.ts:11216). Vorher `s.request_to_generate_chunks(spawn, 2)` und `s.force_generate_chunk_requests()`, dann die
     Probe in `SPAWN_RADII` (6, 16, 32, 64). Ein Teleport zwischen Oberflächen prüft keine Kollision (A23 classes.d.ts:5476); ohne
     diese Suche stünde der Ernter womöglich mitten in den Gebäuden am Startpunkt. Kein Radius 0: Die Suche endet dann nie, wenn es
     keinen Platz gibt (A23 classes.d.ts:20536).
  Jeder Treffer: `ok = entity.teleport(pos, s)`; false → nächster Treffer bzw. nächste Stufe. Gelungen: `harvester.land(h)`, bei
  `damage` der Schaden, `storage.stranded[un] = nil`, Meldung. Scheitert alles: Der Ernter bleibt `carried` auf der Ablage mit
  `carried_by = nil`, `storage.stranded[un] = {crash_pos, damage, reason}`, Log und einmal `msg-stranded`; `retry_stranded` versucht es
  jede Sekunde neu (4.4). So geht kein Ernter verloren, und der Datensatz des Fliegers kann trotzdem sofort weg.
- **Tod** (`on_entity_died`, Ornithopter beladen): `land_cargo(h, Todesposition, true)`. Schaden:
  `entity.health = math.max(1, entity.health - 0.3 * entity.max_health)` (max_health mit Qualität, A23 classes.d.ts:8185) [U23].
  Chat an die Force beim Landen (aus der Warteliste also erst später): `msg-crash` mit `[gps=x,y,Oberfläche]`. Flieger-Datensatz
  austragen, Bild weg. Die Insassen wirft die Engine
  aus [U17]. `on_object_destroyed` kommt danach (A23 events.d.ts:1693) und findet keinen Datensatz mehr [U24]. Beladen und koppelnd
  zugleich gibt es nicht.
- **Anders entfernt** (`on_object_destroyed`, `script_raised_destroy`, Abbau, der bei `minable_flag = false` nur per Skript vorkommt):
  `land_cargo(h, nil, false)`, ohne Schaden, `msg-returned`; landet er erst in Stufe 3: `msg-returned-fallback`.
- **Tank leer:** Die Engine hält den Flieger an (RUN055 T1: bleibt bei x = 2,0, kein Ankunftsereignis); die Last hängt weiter dran,
  Absetzen geht. Schweben ohne Ziel verbraucht nichts [U10].
- **Fremder Teleport** des Fliegers: auf derselben Oberfläche bleibt alles; auf eine andere verlieren Bild, Schatten und Ring ihr
  Ziel (ERG T9); ob der Sticker mitkommt, ist offen, `care` prüft dafür `sticked_to` (4.9). `care` zeichnet bzw. heftet neu an.
  Abgesetzt wird dann auf der neuen Oberfläche.
- **Klon** eines Ornithopters: wird leer eingetragen (kein zweiter Träger derselben Last).
- **Abriss:** beladener Ornithopter → `cancel_deconstruction(force)` [U26]; per Hand nicht abbaubar (`minable_flag = false`).
- **Getragener Ernter stirbt oder verschwindet** (nur per Skript möglich): harvester.lua räumt seinen Datensatz; flyer.lua leert
  den Träger sofort in `on_entity_died`/`script_raised_destroy`, sonst im nächsten 60-Tick-Takt (`care` Fall a, `msg-cargo-lost`).
  Ein Stellplatz geht dabei nicht verloren, weil es keine Liste gibt (4.11).
- **`on_pre_surface_deleted`** (A23 events.d.ts:3940), behandelt nur in flyer.lua: Ist es die Ablage, wird jeder `spice-harvester`
  auf ihr heruntergeholt (`find_entities_filtered{name = "spice-harvester"}`), nicht nur die Lasten an Fliegern: Hat er einen Träger,
  wird an ihm abgesetzt (4.8 ohne Hinweis), sonst und bei „kein Platz“ `land_cargo` ohne Warteliste. Was dann noch auf der Ablage
  steht, geht mit ihr verloren: Log und `msg-cargo-lost` je Ernter. Danach `hold.forget()`, `storage.stranded` leeren. Ist es eine
  andere Oberfläche: Kopplungen dort abbrechen; Lasten von Fliegern dort per `land_cargo` (die Stufen überspringen Oberflächen, die
  gerade gelöscht werden).
- **Waisen:** Ein Ernter auf der Ablage ohne Flieger, dessen `cargo` auf ihn zeigt, und ohne Eintrag in `storage.stranded` (etwa
  nach einem Fehler oder einer fremden Mod), wird im 60-Tick-Takt nicht gesehen. Ihn finden `on_configuration_changed` (4.15),
  `/arrakis-uninstall` und `on_pre_surface_deleted` über die Suche auf der Ablage und geben ihn an `land_cargo`.
- **Mehrspieler:** Logik deterministisch, Fenster je Spieler. Bekanntes Risiko: Desync beim Töten und Neubauen von Spinnen (DOC 8) [U20].

### 4.11 Ablage (hold.lua)
`ensure()`: Steht in `storage.hold.surface` eine gültige Oberfläche, gibt es sie zurück. Sonst `game.get_surface("arrakis-hold")`
oder `game.create_surface("arrakis-hold")`; `generate_with_lab_tiles = true`, `request_to_generate_chunks({0, 0}, 2)`,
`force_generate_chunk_requests()`, `force.set_surface_hidden(surface, true)` für alle Forces (A23 classes.d.ts:11399) [U25], dann in
storage eintragen. Das gilt auch für eine vorgefundene Oberfläche: Wird die Mod ohne `/arrakis-uninstall` entfernt, bleibt die leere
Ablage im Spielstand (DOC 4.6), und nach dem Wiederhinzufügen beginnt `storage.hold` leer.
`take_slot()`: die 256 Plätze in fester Reihenfolge (y, dann x); der erste mit `count_entities_filtered{area = slot ± 4, limit = 1} == 0`
gilt, sonst nil. Weil Anheben und Teleport im selben Tick nacheinander laufen, bekommt der nächste Aufruf schon den nächsten Platz.
`free_count()`: Zahl der Plätze, auf denen nichts steht (256 Abfragen; nur für den Prüfstand). Eine Liste freier
Plätze gibt es nicht (Abweichung von DOC 4.2): Fehlt ein Datensatz oder läuft ein Handler in anderer Reihenfolge, kann so kein Platz
verloren gehen, und ein wartender Ernter (`storage.stranded`) belegt seinen Platz einfach weiter. Name bewusst anders als die
Prüfstand-Ablage `arrakis-test-hold` (scripts/testbench/runner.lua:37).

### 4.12 Lastbild
- Richtung beim Anheben: `i = floor(orientation · 16 + 0.5) mod 16`, Sprite `arrakis-harvester-carried-<i>`.
- `rendering.draw_sprite{sprite, target = {entity = flyer, offset = IMAGE_OFFSET}, surface = flyer.surface, render_layer = "smoke"}`
  (unter dem Rumpf auf `air-object`, über allem am Boden), Schatten mit `SHADOW_OFFSET`, `render_layer = "floor"`. Ebenen wie T9
  (scripts/testbench/t_flyer.lua:626–665). Der Offset weicht von T9 (`{0, 0.5}`) ab: Er gilt relativ zur Entity-Position, und die ist
  beim Spider-Vehicle der Bodenpunkt; den Rumpf zeichnet die Engine um `height` = 3 höher (A23 prototypes.d.ts:9578). Mit `{0, 0.5}`
  lägen Lastbild und Schatten fast an derselben Stelle am Boden, 3,5 Kacheln unter dem Rumpf. `IMAGE_OFFSET = {0, -1.5}` hängt die
  Last zwischen Rumpf und Boden; `SHADOW_OFFSET = {1, 1}` bleibt am Bodenpunkt. T9 hat nur die Art des Schattens bewertet, den
  Kreisflug nicht (ERG T9); beide Werte bleiben Konstanten, Max entscheidet in T17 mit dem Auge [U27]. Kein `forces`: alle sehen es.
- Ring beim Ankoppeln: `draw_arc` um den Ernter, Fortschritt 0 → 1, `forces = {flyer.force}`.
- Vor jeder Nutzung `valid` prüfen; `care` zeichnet fehlende neu [U16].

### 4.13 Fenster (flyer-gui.lua)
`player.gui.relative`, Anker `{gui = defines.relative_gui_type.spider_vehicle_gui, position = defines.relative_gui_position.right, names = {"arrakis-ornithopter"}}`
(A23 defines.d.ts:2114) [U18], aufgebaut in `on_gui_opened` (Datensatz per `flyer_lib.get(entity) or flyer_lib.register(entity)`,
wie scripts/harvester-gui.lua:85, :95), entfernt in `on_gui_closed` (Muster scripts/harvester-gui.lua).
Inhalt: Zustand (`flyer-empty`, `flyer-coupling` mit Restsekunden, `flyer-loaded` mit Spice-Sand im Laderaum des Ernters),
Hauptknopf `arrakis_carry_toggle` (Anheben / Abbrechen / Absetzen, Tooltip mit `__CONTROL__arrakis-carry-toggle__`),
Knopf `arrakis_give_remote`, Knopf `arrakis_board_harvester` (4.7). Auffrischen im 30-Tick-Takt, `storage.flyer_gui_open`.

### 4.14 Forschung
`arrakis-ornithopter` wird von der Engine erforscht, sobald die Force den ersten `spice-harvester` herstellt (Hand oder Maschine) [U11].
Voraussetzung „Spice-Ernte“ schaltet das Ernter-Rezept frei, also kommt der Trigger nie zu früh. Ab dann sind Rezept und beide
Shortcuts frei. Keine Paketkosten (DOC 6, DOC 2.5 „Ornithopter per Trigger“).

### 4.15 Migration und Entfernen
- `migrate.lua`: `SCHEMA = 2` (Z. 25), `init()` legt die neuen Tabellen an (4.2). In `on_configuration_changed`: `local old = storage.schema or 0`;
  wie bisher `old < 1` → Bohrer melden; neu `old < 2` → je Force `migrate.ornithopter_research(force)`; dann Schema hochsetzen.
  Kopfkommentar um Schema 2 ergänzen.
- `migrate.ornithopter_research(force) → bool`: Technologie `arrakis-ornithopter` vorhanden und nicht erforscht, `arrakis-spice-harvesting`
  erforscht, und (ein Eintrag in `storage.harvesters` mit dieser Force oder `force.get_item_production_statistics(surface).get_input_count("spice-harvester") > 0`
  auf irgendeiner Oberfläche, A23 classes.d.ts:11187, :10737) → `technologies["arrakis-ornithopter"].researched = true` (A23 :22293), true.
  Für T15 exportiert. Grund: Der Trigger feuert nicht für früher hergestellte Ernter [U12].
- flyer `on_configuration_changed` (nach migrate): `care` für alle Flieger; Waisen: jeder `spice-harvester` auf der Ablage ohne
  gültigen Träger (Datensatz fehlt, `carried_by` zeigt auf keinen Flieger mit dieser Last) und ohne Eintrag in `storage.stranded` geht
  an `land_cargo(h, nil, false)` (4.10), DOC 4.6. Fehlt sein Datensatz, wird er vorher mit `harvester.register` eingetragen und mit
  `harvester.lift(h, nil, nil)` wieder als getragen gesperrt (ohne Abhebepunkt gilt nur Stufe 3).
- Herunterstufen auf 0.5.x mit getragenem Ernter: nicht unterstützt (1).
- `/arrakis-uninstall` (nur Admins): ohne Argument Warnung mit Zahl der Ernter auf der Ablage; mit `ja`: jeden `spice-harvester` auf der
  Ablage herunterholen wie beim Löschen der Ablage (4.10, mit Träger an ihm absetzen, sonst `land_cargo`), alle Bilder weg. Steht danach
  nichts mehr auf der Ablage: `game.delete_surface("arrakis-hold")` (A23 classes.d.ts:11769), `hold.forget()`, Meldung `uninstall-done`.
  Bleiben Ernter ohne Platz übrig, wird die Ablage nicht gelöscht: Meldung `uninstall-stuck` mit ihrer Zahl, die Ernter warten in
  `storage.stranded`, und der Befehl kann wiederholt werden. Rückgabe `n` (abgesetzt), `rest` (übrig). Danach kann Max die Mod entfernen.
  Hebt jemand vorher wieder an, legt `ensure()` die Ablage neu an.

### 4.16 Ungeprüfte Engine-Annahmen
| Nr | Annahme | Entscheidet | Wenn sie nicht hält |
|---|---|---|---|
| U1 | `SHIFT + C` mit `consuming = "none"` kommt im Ornithopter an und ist in Vanilla frei | T17 Schritte 1 und 7 | Shortcut und Knopf genügen; Taste in 0.6.x umlegen |
| U2 | Beim Fernfahren ist `player.vehicle` der Ornithopter; `get_driver()` liefert dann den LuaPlayer | T17 Schritt 6 | Stufe 2 bis 4 von `resolve_flyer` greifen; DOC 2.1 Schritt 8 anpassen |
| U3 | `player.selected` und `spidertron_remote_selection` sind in der Kartenansicht gesetzt (2.1.23) | T17 Schritt 5 | Rettung aus der Karte nur per Fernfahren |
| U4 | Ein Klick auf den Shortcut lässt die Fernbedienung in der Hand und die Auswahl stehen | T17 Schritt 5 | Taste statt Shortcut aus der Karte |
| U5 | Die vom eigenen Shortcut erzeugte `spidertron-remote` steuert den Ornithopter ohne Forschung „Spidertron“; `spidertron_remote_selection` ist schreibbar | T17 Schritt 5 | Fernbedienung erst mit „Spidertron“; bis dahin Fernfahren |
| U6 | `vehicle_speed_modifier` wirkt linear: 0,52 → 8,0, 0,364 → 5,6 Kacheln/s (gemessen nur 0,7) | T16 | Modifier aus der T16-INFO übernehmen |
| U7 | Brennstoff ändert das Tempo des Ornithopters nicht (T1 flog nur mit Raketentreibstoff) | T16 | Sticker je Brennstoff, wie `apply_fuel_normalization` beim Ernter |
| U8 | Qualität des Ornithopters ändert das Tempo nicht | T16 | wie U7, je Qualität |
| U9 | Der Sticker bleibt über Speichern/Laden am Flieger; Zerstören und Neuerzeugen wirkt sofort | T15 Schritt 15; Speichern/Laden bei der Abnahme | Neuanheften im ersten 60-Tick-Takt (`on_load` schreibt nie): höchstens 1 s volles Tempo |
| U10 | Ein Spider-Vehicle ohne Ziel verbraucht keinen Brennstoff | T16 Bahn „Schweben“ (MESSUNG, kein FEHLER) | Hinnehmen, Verbrauch in docs/pruefstand.md nennen |
| U11 | `craft-item` feuert bei Handarbeit (auch einer Figur ohne Spieler) und in Maschinen | T15 Schritt 2; Abnahme von Hand | Trigger `scripted`, ausgelöst im Skript (DOC 6: `force.script_trigger_research`) |
| U12 | Der Trigger wirkt nicht rückwirkend | Abnahme mit 0.5.5-Spielstand | Migration schadet nicht (setzt nur, was fehlt) |
| U13 | Teleport eines eben per Notstart gelösten Ernters zur Ablage und zurück verliert nichts (T3 prüfte nur einen mobilen) | T15 Schritte 5 und 6 | Absetzen per `clone` (DOC 8, T3) |
| U14 | `set_driver(nil)`/`set_passenger(nil)` stellen die Figur neben das Auto; `set_driver`/`set_passenger(Figur)` setzt sie in den Ornithopter, auch aus einigen Kacheln Abstand | T15 Schritt 3 (Figuren, MESSUNG welche Stufe griff); T17 Schritt 1 (Spieler) | Stufe 1 (4.7): Figur per `teleport` an den Flieger, erneut setzen. Erst wenn auch das scheitert: Insassen bleiben am Boden + Hinweis, „der Fahrer fliegt mit“ (Roadmap 3c) fällt dann aus; DOC anpassen |
| U15 | Nach `exit_remote_view()` setzt `set_driver(player)` die Figur des Spielers | T17 Schritt 8 | Spieler in der Fernsicht bleibt am Boden + Hinweis |
| U16 | Render-Objekte am Ornithopter bleiben gültig, solange er die Oberfläche nicht wechselt | T15 Schritt 15 | `care` jeden Takt statt bei Bedarf |
| U17 | Beim Tod wirft die Engine die Insassen aus, ohne den Absetzplatz zu blockieren | T15 Schritt 7 (MESSUNG Abstand) | Absetzen erst im nächsten Tick |
| U18 | Relatives Fenster mit `spider_vehicle_gui` und `names = {"arrakis-ornithopter"}` erscheint | T17 Schritt 4 | Anker ohne `names`, Filter im Skript |
| U19 | Die Probe sperrt dieselben Stellen wie der Ernter (Wasser, Klippen, Gebäude, Bäume, Fahrzeuge), auch mit `build_check_type.manual` | T15 Schritt 9 | `find_non_colliding_position` mit `spice-harvester` und Rest-Prüfung per `count_entities_filtered` |
| U20 | Kein Desync beim Töten und Neubauen von Spinnen (DOC 8) | Abnahme mit zwei Spielern | Melden; Fehler der Engine |
| U21 | Ein Ernter fährt unter einem stehenden Ornithopter durch, ohne dass einer Schaden nimmt (Masken ohne gemeinsame Ebene) | T15 Schritt 16 (MESSUNG) | Ornithopter-Körper `collision_mask = {layers = {}}` |
| U22 | Einheit von `vehicle_speed_max` (Kacheln je Tick oder je Sekunde) | T16 Bahnen „max“ (MESSUNG) | Nur Ausweichweg, nichts hängt daran |
| U23 | `health` schreiben wirkt sofort nach dem Teleport; `max_health` enthält die Qualität | T15 Schritt 7 | `entity.damage` mit Typ ohne Resistenz |
| U24 | `on_object_destroyed` des Ornithopters kommt nach `on_entity_died` | T15 Schritt 7 (keine Doppelbehandlung) | Datensatz in `on_entity_died` sofort löschen (so geplant), dann ist die Reihenfolge egal |
| U25 | `set_surface_hidden` wirkt für eine in `on_force_created` neue Force und für eine vorgefundene Ablage | T15 Schritt 12 | im 60-Tick-Takt nachholen |
| U26 | `cancel_deconstruction` wirkt an einem Spider-Vehicle | T15 Schritt 11 | `minable_flag = false` hält ihn trotzdem |
| U27 | Sprites aus Ausschnitten der Panzer-Sheets (Ebenen, `shift`, Tönung) erscheinen mit `draw_sprite` richtig | T17 Schritt 2 (Auge); Ladefehler in datastage (7) | T9-Bild (Panzer-Icon) |
| U28 | Der Autopilot fliegt mit Dummy-Pilot und Last ans Ziel (ohne Last: RUN055 T1, ja) | T15 Schritt 6 | Test fährt per `teleport` in Schritten (nur Test) |

### 4.17 Prüfstand-Haken
Keine neuen. `terrain.harvest_allowed` gibt die Prüfstand-Fläche schon frei (scripts/terrain.lua); T15 nutzt die echte Ablage
`arrakis-hold` und die exportierten Funktionen aus 4.1 und 4.15. Für den Waisen-Fall (T15 Schritt 17) streicht der Test einen
Flieger-Datensatz selbst aus `storage.flyers`; T13 liest storage schon genauso direkt (scripts/testbench/t_ernter.lua:816).

## 5. Texte

`locale/{de,en}/arrakis.cfg` (Datenstufe): `[entity-name]`/`[entity-description]` arrakis-ornithopter („Ornithopter“ /
„Bemannter Flieger. Hebt einen Spice-Ernter an (__CONTROL__arrakis-carry-toggle__ oder Verknüpfung in der Leiste), trägt ihn und setzt
ihn ab.“; die Taste steht nie fest im Text, wie bei spice-harvester, locale/de/arrakis.cfg:49); dazu `[entity-name]` für die versteckten
Prototypen wie im Prüfstand (`arrakis-flyer-leg=Ornithopter-Bein`, `arrakis-ornithopter-empty=Ornithopter-Drossel (leer)`,
`arrakis-ornithopter-loaded=Ornithopter-Drossel (beladen)`, `arrakis-harvester-probe=Absetz-Probe`); `[item-name]` arrakis-ornithopter;
`[technology-name]`/`[technology-description]` arrakis-ornithopter („Erforscht, sobald der erste Spice-Ernter hergestellt ist.“);
`[controls]` arrakis-carry-toggle („Ernter anheben oder absetzen“); neuer Abschnitt `[shortcut-name]` arrakis-carry,
arrakis-give-remote („Fernbedienung für Ornithopter“). Beim Ernter heißt Abbauen „aufheben“ (vorhanden), das Tragen heißt
„anheben“; die beiden Wörter nie vertauschen.

`locale/{de,en}/messages.cfg`, Abschnitt `[arrakis-message]` (Deutsch, Englisch sinngemäß):
- `state-carried=Wird getragen`, `gui-carried=Wird getragen`, `hint-carried=Der Spice-Ernter wird gerade getragen.`
- `flyer-empty=Leer`, `flyer-coupling=Koppelt an (noch __1__ s)`, `flyer-loaded=Trägt einen Spice-Ernter: __1__ / __2__ Spice-Sand`
- `gui-flyer-title=Ornithopter`, `gui-lift=Ernter anheben`, `gui-drop=Absetzen`, `gui-remote=Fernbedienung`,
  `gui-board-harvester=In den Ernter steigen`, `gui-carry-tooltip=Geht auch mit __CONTROL__arrakis-carry-toggle__ oder der Verknüpfung in der Leiste.`
  (`gui-abort=Abbrechen` gibt es schon)
- `hint-no-flyer=Kein Ornithopter: einsteigen, per Fernbedienung auswählen oder auf ihn zeigen.`
- `hint-no-harvester=Kein eigener Spice-Ernter in 4 Kacheln.`, `hint-coupling-start=Ankoppeln: 2 s über dem Ernter bleiben.`,
  `hint-coupling-busy=Dieser Spice-Ernter wird schon angekoppelt.`, `hint-coupling-lost=Ankoppeln abgebrochen: zu weit weg.`,
  `hint-coupling-aborted=Ankoppeln abgebrochen.`, `hint-lift-failed=Anheben ging nicht (siehe Log).`
- `hint-no-space=Kein Platz zum Absetzen.`, `hint-hold-full=Kein Stellplatz frei: Auf der Ablage stehen schon 256 Spice-Ernter.`,
  `hint-seat-full=Kein Sitz frei: __1__ bleibt am Boden.`, `hint-flyer-foreign=Dieser Ornithopter gehört einer anderen Fraktion.`,
  `hint-remote-cursor=Erst die Hand leeren, dann gibt es die Fernbedienung.`
- `msg-crash=Ornithopter abgestürzt: Der Spice-Ernter liegt mit 30 % Schaden bei __1__.`,
  `msg-returned=Ornithopter verloren: Der Spice-Ernter steht wieder am Abhebepunkt __1__.`,
  `msg-returned-fallback=Abhebepunkt fehlt oder ist zugebaut: Der Spice-Ernter steht bei __1__.`, `msg-cargo-lost=Ein getragener Spice-Ernter ist verschwunden.`,
  `msg-stranded=Kein Landeplatz für den Spice-Ernter (zuletzt bei __1__). Neuer Versuch jede Sekunde.`
- `uninstall-warn=__1__ Spice-Ernter werden getragen. /arrakis-uninstall ja setzt sie ab und löscht die Ablage; danach kann die Mod entfernt werden.`,
  `uninstall-done=__1__ Spice-Ernter abgesetzt, Ablage gelöscht.`,
  `uninstall-stuck=__1__ Spice-Ernter abgesetzt, __2__ fanden keinen Platz. Die Ablage bleibt; Platz schaffen und den Befehl wiederholen.`
Englisch: „Ornithopter“, „Lift harvester“, „Drop“, „Board harvester“, „Spice sand“.

## 6. Prüfstand

Alle neuen automatischen Tests laufen ohne Spieler über tools/pc/pruefstand.py (RCON) und mit game.speed 10: Sie messen nur in
Ticks, warten nie auf echte Zeit und brauchen keinen Spieler. Jeder Schritt schreibt OK oder FEHLER mit Werten; Einzelwerte stehen
als MESSUNG nur in der Datei (wie T13/T14). Die Flächen hängen wie bisher am Index in `ORDER` (`tb.area`, scripts/testbench/runner.lua:292–297);
die neuen IDs kommen deshalb ans Ende, und keine alte Fläche verschiebt sich: T15 bei x = 26 000, T16 bei 28 000, T17 bei 30 000.
Zeitlimits in Spielzeit-Ticks wie scripts/testbench/t_ernter.lua:1949 (ohne Angabe bricht der Runner nach 60 s ab,
scripts/testbench/runner.lua:41, :791–792): T15 `timeout = 240 * 60`, T16 `timeout = 90 * 60`, T17 `timeout = 380 * 60`.

**Isolation von T15 und T16.** Beide heben echte Ernter auf die echte Ablage `arrakis-hold`. Ohne Aufräumen setzte `return_cargo` alte Lasten in
eine eben vorbereitete Fläche (`tb.prepare` zerstört Flieger per `destroy()`, scripts/testbench/runner.lua:373–376, und
`on_object_destroyed` kommt erst am Ende dieses oder des nächsten Ticks, A23 events.d.ts:1689–1693), und `resolve_harvester` fände sie
dort als „nächsten Ernter“. Deshalb räumen beide Tests in `start` (Reste eines abgebrochenen Laufs) und in `cleanup` (läuft auch nach
Zeitüberschreitung und Skriptfehler, `tb.finish`, scripts/testbench/runner.lua:404–411) gleich auf:
1. Jeder `spice-harvester` auf `arrakis-hold`, dessen Abhebepunkt in der eigenen Fläche liegt, wird mit `destroy{raise_destroy = true}`
   entfernt; flyer.lua leert dabei seinen Träger und streicht ihn aus `storage.stranded` (4.1).
2. Danach jeder eingetragene Ornithopter in der eigenen Fläche mit `destroy{raise_destroy = true}`; er ist jetzt leer, also bringt
   „anders entfernt“ nichts zurück. Im `cleanup` dazu die eigenen Ernter am Boden und (nur T15) der Startpunkt von `arrakis-t15` wie
   vorher (Schritt 9 e).
3. Nur in `start`: dann `tb.prepare`; gebaut wird frühestens 2 Ticks danach.
Zahlen zur Ablage prüft T15 relativ zum Stand vor dem Schritt, nie absolut: Ein anderer Test oder der Spielstand kann Lasten tragen.

**T15 „Ornithopter: echter Code“** (automatisch, etwa 3 min Spielzeit, bei Tempo 10 etwa 18 s). Eigene Fläche auf `arrakis-testbench`:
Sand mit zwei Spice-Teppichen A und B, 150 Kacheln auseinander (Hilfsfunktion nach dem Muster von scripts/testbench/t_ernter.lua),
Felsinsel mit Annahme, Wasser- und Mauerfeld. Ornithopter und Ernter entstehen mit `raise_built = true`; Piloten sind `tb.dummy_driver`. Schritte:
1. Prototypen: `arrakis-ornithopter` ist `spider-vehicle`, 4 Beine, Brenner `chemical` mit 2 Slots, `allow_remote_driving`; beide Sticker,
   32 Sprites (`helpers.is_valid_sprite_path`), Probe, Taste, beide Shortcuts vorhanden. FEHLER nennt das fehlende Stück.
2. Forschung [U11]: Force `arrakis-t15` (einmal anlegen, wiederverwenden wie `tb.worm_force`). Weil die Force ihren Stand von Lauf zu
   Lauf behält, stellt der Schritt ihn zuerst her: „Spice-Ernte“ erforscht, `technologies["arrakis-ornithopter"].researched = false`,
   auf allen Oberflächen `force.get_item_production_statistics(s).set_input_count("spice-harvester", 0)` (A23 classes.d.ts:10775); Ernter
   der Force gibt es nach dem cleanup keine. Vorher-Probe: `migrate.ornithopter_research` → false (sonst INFO „nicht prüfbar“ mit Grund).
   a) Figur der Force mit den Zutaten (prototypes/harvester.lua:171–177), `begin_crafting{recipe = "spice-harvester", count = 1}`
      (A23 classes.d.ts:5300). Das Rezept dauert 10 s (prototypes/harvester.lua:169), von Hand 600 Ticks. OK: Item im Inventar höchstens
      660 Ticks nach `begin_crafting`, „Ornithopter“ erforscht höchstens 60 Ticks nach dem Item. FEHLER: Item da, 60 Ticks später nicht erforscht.
   b) Rückgabe 0 oder kein Item bis Tick 660 (eine Figur ohne Spieler craftet womöglich nie): INFO, dann eine Montagemaschine 3 der Force
      mit Rezept und Zutaten, Strom von einer `electric-energy-interface` über einen `medium-electric-pole` (wie
      scripts/testbench/t_harvester.lua:1145–1146). Tempo 1,25, also 480 Ticks: Item im Ausgang höchstens 540 Ticks nach `set_recipe`,
      „Ornithopter“ erforscht höchstens 60 Ticks nach dem Item; FEHLER wie in a).
   c) Auch aus der Maschine kein Item: MESSUNG, Max prüft von Hand (Abnahme 8).
3. Anheben mit Insassen [U14]: a) Pilot an Bord, Ernter mit Fahrer- und Beifahrer-Figur, 2 Kacheln entfernt; `toggle_carry`, 130 Ticks.
   OK: Ernter auf `arrakis-hold` an einem Stellplatz, `carried`, `carried_by` stimmt, `disabled_by_script`, nicht abbaubar; Flieger
   `cargo`, nicht abbaubar, Sticker beladen; Fahrer jetzt Beifahrer im Flieger, Beifahrer am Boden ≤ 6 Kacheln (MESSUNG Abstand),
   Bild und Schatten gültig. b) Flieger ohne Pilot: Fahrer wird Pilot, Beifahrer wird Beifahrer. Danach Absetzen: Sitze unverändert.
   MESSUNG je Insasse, welche Stufe aus 4.7 gegriffen hat (gleich gesetzt oder erst nach dem Teleport an den Flieger).
4. Ankoppeln: a) Flieger nach 30 Ticks per `autopilot_destination` 10 Kacheln weg → nach 130 Ticks nicht getragen, Kopplung und Ring weg;
   b) zweiter Aufruf nach 30 Ticks → abgebrochen; c) Aufruf nach 5 Ticks → ignoriert (Entprellen), Kopplung läuft; d) Ernter `die()`
   während der Kopplung → kein Skriptfehler, Kopplung weg; e) zweiter Flieger auf denselben Ernter → `false, "busy"`.
5. Notstart [U13]: je ein Ernter in deploying, deployed (nach 5 s Aufbau), packing und docked (an der Annahme) anheben. OK: getragen,
   `storage.timers`/`storage.driven` ohne ihn, Feldrahmen und Ring weg, Proxy-Ziele der Annahme nil. Den angedockten über derselben
   Annahme absetzen: nach höchstens 180 Ticks wieder docked.
6. Voller Ernter von Feld A nach B [U13, U28] (Roadmap 3c, DOC 2.1 Schritt 11): Ernter `uncommon` (wenn Quality da ist),
   Ausrichtung 0,375, Gesundheit 60 %, 20 Kohle (eine brennt). Die Puppe wird wie in T3 vor dem Einsteigen gefärbt und steigt dann ein
   (scripts/testbench/t_harvester.lua:737–771); das Auto übernimmt die Farbe seines Fahrers (RUN055 T3 Z. 112). Auf Teppich A aufbauen
   (`harvester.toggle`, nach 300 Ticks `deployed`). Kofferraum füllen: 1900 Spice-Sand (38 Slots), 100 Eisenplatten und 10 Eisenplatten
   `rare` (zusammen 40 Slots, voll; ohne Quality 2000 Spice-Sand). Grund: 40 Slots (prototypes/harvester.lua:62), Spice-Sand stapelt 50
   (prototypes/resources.lua:53), 2000 Spice-Sand allein füllten alles. Jede Einfügemenge wird geprüft; liefert `insert` weniger: FEHLER
   beim Aufbau, der Schritt endet. Vorher-Stand unmittelbar vor `toggle_carry`, mit sitzendem Fahrer (der volle Kofferraum hält den
   Abbau an, bis zum Anheben ändert sich also nichts). Dummy-Pilot im Flieger, Anheben (Notstart aus deployed), `autopilot_destination`
   über Teppich B, Ankunft per `spider_command_completed` (höchstens 40 s), Absetzen. OK für jedes Feld aus T3 (Kofferraum, Treibstoff,
   Restbrennwert, brennendes Item, Gesundheit, Qualität, Farbe, unit_number, Ausrichtung) gleich; Ernter ≤ 1,5 Kacheln von der
   Ankunftsstelle; der Fahrer sitzt noch im Flieger („der Fahrer fliegt mit“); `hold.free_count()` wie vor dem Anheben. Dann auf B
   ernten: 100 Eisenplatten heraus (ein Slot frei), `harvester.toggle` → nach 300 Ticks `deployed`; jede Ressource in `resources` liegt
   im Erntefeld um die Absetzstelle (`harvester.field_area`), keine bei A; nach weiteren 60 Ticks mehr Spice-Sand im Kofferraum und
   weniger Spice in den B-Ressourcen. MESSUNG: Flugzeit, Tempo, Brennwert.
7. Absturz [U17, U23, U24]: a) beladener Flieger (Ernter mit voller Gesundheit) `die()`. OK im selben Tick: Ernter auf der Testfläche
   ≤ 6 Kacheln von der Todesstelle, mobil, entsperrt, Gesundheit = max − 0,3 · max ± 0,5, Flieger-Datensatz weg, `free_count` wie vor
   dem Anheben. Nach 2 Ticks: Position und Gesundheit unverändert (keine Doppelbehandlung). b) Ernter mit 20 % Gesundheit → 1 LP, lebt.
   c) Pilot an Bord: Figur gültig, MESSUNG Abstand zum Ernter.
8. Anders entfernt: a) beladener Flieger 30 Kacheln vom Abhebepunkt `destroy()` → nach höchstens 2 Ticks Ernter ≤ 6 Kacheln vom
   Abhebepunkt, Gesundheit unverändert; b) `destroy{raise_destroy = true}` → sofort zurück.
9. Kein Platz [U19]: a) über einem Feld voller Steinmauern (13 × 13) und b) über Wasser (15 × 15) absetzen → `false, "no_space"`,
   weiter getragen; 20 Kacheln weiter → abgesetzt. c) Absturz über dem Mauerfeld → Ernter landet im Radius 16. d) Probe am Rand
   einer Klippe, wenn die Fläche eine erzeugen kann, sonst INFO. e) Kein Landeplatz (4.10): Flieger und Ernter der Force `arrakis-t15`.
   Wassersee 200 × 200 mit einer Sandinsel 8 × 8 in der Mitte; Startpunkt der Force auf `arrakis-testbench` per
   `force.set_spawn_position` (A23 classes.d.ts:11394) 20 Kacheln neben die Insel, also im See. Auf der Insel anheben, die Insel zu
   Wasser machen, beladenen Flieger dort `die()`. OK: Ernter auf der Ablage, `carried`, `carried_by` nil, Eintrag in `storage.stranded`
   mit `damage`, Flieger-Datensatz weg; nach 60 Ticks unverändert. Dann die Insel wieder Sand → nach höchstens 60 Ticks gelandet ≤ 6 Kacheln von der
   Todesstelle, mobil, Gesundheit − 30 %, Eintrag weg. Am Ende Startpunkt wie vorher.
10. Leerer Tank [U10]: beladener Flieger ohne Treibstoff, Ziel 50 Kacheln: nach 3 s Position ± 0,1, beladen, Bild gültig; Absetzen geht.
11. Abbausperre [U26]: beladen `minable_flag == false`, `order_deconstruction(force)` → nicht markiert; leer `minable_flag == true`.
12. Ablage [U25]: Oberfläche da, für alle Forces versteckt, auch für `arrakis-t15n`, die erst jetzt angelegt wird (am Ende in
    `neutral` verschmolzen; gibt es sie schon: INFO). Drei Flieger heben im selben Tick an: drei verschiedene Plätze, `free_count` =
    vorher − 3; nach dem Absetzen wieder wie vorher. Dann `hold.forget()` ohne Löschen (wie nach dem Wiederhinzufügen der Mod) und
    anheben: geht, `storage.hold.surface` ist wieder die Ablage, für alle Forces versteckt.
13. Zustandstabellen: jede Eingabe aus 4.3 in jedem Zustand von Ernter und Ornithopter, Folgezustand und Flags stimmen; dazu
    `harvester.toggle` am getragenen Ernter → false; Teleport mit `raise_teleported = true` auf der Ablage → bleibt getragen;
    Teleport des getragenen Ernters auf die Testfläche mit `raise_teleported = true` → im selben Tick mobil und entsperrt, Datensatz da,
    Flieger leer, und ohne `raise_teleported` dasselbe nach höchstens 60 Ticks (`care` Fall b, nicht a); getragenen Ernter `die()`
    → Flieger im selben Tick leer, `destroy()` ohne Ereignis → nach höchstens 60 Ticks leer (`care` Fall a), beide Male `free_count`
    wie vor dem Anheben; Klon des getragenen Ernters auf die Testfläche → Klon mobil, Original getragen; Klon des beladenen Fliegers → Klon leer.
14. Migration: an `arrakis-t15` zuerst `researched = false` für „Ornithopter“ (Schritt 2 hat ihn erforscht), dann
    `migrate.ornithopter_research` mit Ernter der Force → true und erforscht; zweiter Aufruf → false (schon erforscht); ohne erforschte
    „Spice-Ernte“ → false. Am Ende beide Forschungen wieder wie vor dem Schritt.
15. Pflege [U9, U16]: Sticker des beladenen Fliegers per Skript zerstören → nach höchstens 60 Ticks ein Sticker, Name „beladen“;
    zweiten eigenen Sticker per `create_entity{target = flyer}` anheften → nach höchstens 60 Ticks wieder genau einer, der gemerkte;
    Bild zerstören → neu gezeichnet; Flieger per `teleport` auf `arrakis-test-hold` und zurück → Bild, Schatten und Sticker nach
    höchstens 60 Ticks wieder gültig, `sticked_to` ist der Flieger. MESSUNG: Zahl der eigenen Sticker in `flyer.stickers` (muss 1 sein).
16. Fremde Force und Unterflug [U21]: Ernter der Force `arrakis-t15` neben einem Flieger der Spieler-Force → `false, "foreign"`. MESSUNG:
    Ernter mit Dummy-Fahrer fährt 3 s unter einem stehenden Flieger durch; Gesundheit beider vorher/nachher.
17. Entfernen (immer zuletzt): zwei beladene Flieger und eine Waise (beladener Flieger, dessen Datensatz der Test aus `storage.flyers`
    streicht, dann `destroy()`; der Ernter bleibt ohne Träger auf der Ablage). `flyer_lib.uninstall()` → `n >= 3`, `rest == 0`; beide
    eigenen Ernter am Boden ≤ 6 Kacheln von ihrem Flieger, die Waise ≤ 6 Kacheln von ihrem Abhebepunkt, Flieger leer; nach 1 Tick gibt es
    `arrakis-hold` nicht mehr. `n` kann größer sein, wenn der Spielstand selbst Ernter trägt. Der nächste Lauf legt die Ablage neu an.

**T16 „Ornithopter: Flugphysik“** (automatisch, parallele Bahnen wie T1, etwa 45 s Spielzeit). Echte Ornithopter, eingetragen über
flyer.lua (also mit echtem Sticker), Dummy-Pilot, Ziel 400 Kacheln voraus; gemessen wird zwischen 5 s und 15 s nach dem Start.
- Bahnen leer: Kohle, Festbrennstoff, Raketentreibstoff, Atomtreibstoff, Spice-Brikett, legendärer Raketentreibstoff (wenn Quality);
  Richtungen O, W, N, S und NO mit Kohle; Ornithopter `uncommon` und `legendary` (wenn Quality).
- Bahnen beladen (echtes Anheben über `toggle_carry`): Kohle und Raketentreibstoff, O und N.
- Vergleich, alle unregistriert (`create_entity` ohne `raise_built`; `care` sieht sie nie, und eine Puppe ohne Spieler löst kein
  `on_player_driving_changed_state` aus): ein Ornithopter ohne Sticker mit Raketentreibstoff (Rohwert) und zwei mit je einem Test-Sticker
  `vehicle_speed_max`, per `create_entity{target = flyer}` angeheftet [U22]. An einem eingetragenen Flieger hängte `care` binnen 60 Ticks
  den eigenen Sticker wieder an, und im Messfenster wirkten beide.
- Schweben [U10]: beladen, mit Kohle, ohne Ziel, 10 s. MESSUNG: Restbrennwert und Brennstoffzahl vorher und nachher, Verbrauch in kW
  und kJ je 10 s. Verbraucht er etwas: INFO „U10 hält nicht: Schweben kostet x kW“. Kein FEHLER, weil 4.16 das hinnimmt.
- FEHLER: leer außerhalb 7,0–9,0 Kacheln/s auf einer Bahn; beladen außerhalb 5,0–6,5; beladen/leer (gleicher Brennstoff, gleiche Richtung)
  außerhalb 0,65–0,75; größtes/kleinstes Tempo der leeren Brennstoff-Bahnen > 1,10 [U7]; Qualität ändert das Tempo um > 10 % [U8].
- MESSUNG: Tempo, kJ/Kachel und kW je Bahn; Rohwert ohne Sticker; `vehicle_speed_max`-Bahnen.
- INFO am Ende: vorgeschlagene Modifier `0,52 · 8 / v_leer` und `0,364 · 5,6 / v_beladen` aus den Ost-Bahnen mit Kohle [U6].

**T17 „Ornithopter: Bedienung“** (interaktiv, nur mit Max im Spiel, `alle` lässt ihn aus; endet nach 6 min Spielzeit oder mit `stop`).
Neben Max: ein Ornithopter mit Kohle, ein Ernter mit 500 Spice-Sand, dazu 30 Kacheln weiter eine Annahme auf Fels. Jeder Tastendruck
und Shortcut-Klick schreibt eine MESSUNG-Zeile (Weiterleitung siehe unten), jeder Zustandswechsel eine INFO-Zeile.
1. Einsteigen, über den Ernter fliegen, `Umschalt+C` [U1, U14]: Ankoppeln, Anheben. Zweiter Druck setzt ab.
2. Anheben, dann fliegt der Test 20 s im Kreis (wie T9 C). FRAGE: „Hängt der Ernter sichtbar unter dem Ornithopter, und liegt der Schatten
   passend am Boden?“ [U27]
3. Verknüpfung „Ernter anheben oder absetzen“ in der Leiste: absetzen, wieder anheben.
4. Ornithopter-Fenster öffnen [U18]: Knopf Absetzen, dann „In den Ernter steigen“.
5. Aussteigen, Shortcut „Fernbedienung für Ornithopter“ [U5], Ornithopter auswählen, Karte (M), Rechtsklick auf den Ernter, nach der
   Ankunft in der Karte `Umschalt+C` und danach der Shortcut [U3, U4].
6. Ornithopter aus der Karte fernfahren (WASD) und `Umschalt+C` [U2].
7. FRAGE: „Ist Umschalt+C unter Einstellungen → Steuerung doppelt belegt?“ [U1]
8. Solo-Rettung: in den Ernter steigen, Ornithopter per Fernbedienung herholen, Karte offen lassen, `Umschalt+C`. Erwartung: Max sitzt
   danach als Pilot im Ornithopter, der Ernter hängt dran [U15]. Über der Annahme absetzen: dockt nach 2 s an.

Was Max mit dem Auge prüft (T17 und Abnahme): Lastbild und Schatten (Lage, Tönung, Richtung), Ankoppelring, Fenster am Ornithopter,
Tempogefühl leer und beladen, Rumpf-Wippen (`torso_bob_speed`), Shortcut-Icons.

Runner (scripts/testbench/runner.lua): `ORDER` endet mit `"T14", "T15", "T16", "T17"`; Modulliste um `scripts.testbench.t_ornithopter`;
Weiterleitung `["arrakis-carry-toggle"] = forward("carry_key")` und `[defines.events.on_lua_shortcut] = forward("shortcut")`
(beide laufen zusätzlich zu flyer.lua, event_handler fasst zusammen); Vertrag (Z. 10–21) um die zwei Namen ergänzen.
`docs/pruefstand.md`: Tests T15 bis T17 beschreiben; `alle` und „Was ohne Spieler läuft“ um T15, T16; T17 überall neben T9 und T12, wo
die interaktiven Tests stehen (Z. 41, 66, 126, 157, 190, 220); Statusreihenfolge „T1 bis T7, T9, T11, T12, T13, T2b, T14, T15, T16, T17“
(Z. 94); „Vorbereitung“ Punkt 2 um den Satz „T15 benutzt die echte Ablage `arrakis-hold`, setzt am Ende alle getragenen Ernter ab und
löscht sie“; Bekannte Grenzen: Lastbild dreht nicht mit, T16 misst N und S wegen der festen Beine getrennt.
`tools/pc/pruefstand.py`: Hilfetexte (Z. 34, 767) nennen T9, T12 und T17 als interaktiv.

## 7. Prüfung vor der Übergabe
- `tools/check/datastage.py` mit Vanilla 2.1.23 (`fd2123`), mit und ohne `arrakis-testbench`, und `datastage.py fd2123 --ohne quality --set arrakis-testbench=true`.
  2.0.77 nur, wenn die Vanilla-Daten vorliegen (Zweig `factorio-2.0` ist eingefroren, DOC 5.2); dann prüft es nur die 2.0-Schreibweise.
- `tools/check/checks.lua` neu für 3c (`expected_3c`): `spider-vehicle` arrakis-ornithopter, `item-with-entity-data`, `recipe`,
  `technology` arrakis-ornithopter, `custom-input` arrakis-carry-toggle, `shortcut` arrakis-carry und arrakis-give-remote vorhanden und nicht
  hidden; hidden vorhanden: `spider-leg` arrakis-flyer-leg, beide Sticker, Probe. Dazu: Ornithopter `allow_remote_driving == true`,
  Beine mit leerer Maske, Brenner `chemical` mit 2 Slots, keine Waffen, kein Gitter, `trash_inventory_size == 0`, `minable.result`,
  kein `collision_mask` am Körper, kein `tall`, kein `icon`; Item ohne `icon` und ohne jedes `icon_tintable*`-Feld; Forschung mit
  `craft-item` spice-harvester und Voraussetzung; 32 Sprites mit je zwei Ebenen, jede Ebene `scale == 0.5`, die Schatten-Ebenen mit
  `draw_as_shadow`; Probe-Kasten ±1,6 und Maske gleich der des Ernters; Ernter `allow_remote_driving == false` (bleibt). Prüfstand-Liste:
  die zwei Test-Sticker; die Namensprüfung der Laufzeitdateien liest auch `scripts/testbench/t_ornithopter.lua`.
- `datastage.py --dump`: welche Felder der Spidertron-deepcopy in 2.1.23 mitbringt (DOC 5.5); `tools/check/proto_fields.py` ohne Treffer.
- `tools/check/api_names.py` gegen 2.0.75 und 2.1.23 (factorio-types 1.2.72) ohne neue Treffer.
- Statische Regeln: kein `script.on_event`/`script.on_nth_tick` außerhalb von event_handler; keine storage-Schreibzugriffe aus `on_load`;
  keine Nutzung von `event.in_gui`; kein Modul bindet `scripts.flyer` als `flyer`; jeder `arrakis-message`-Schlüssel aus dem Code steht in
  beiden Sprachen; kein neuer Text nennt die Werkvorlage beim Namen (Markenrecht, KONZEPT.md:188).
- Trockenlauf der Zustandslogik (flyer.lua, hold.lua, `harvester.lift/land`, `migrate.ornithopter_research`) gegen eine Lua-Attrappe der Engine
  wie beim T13-Mock: nur Logik und Tabellen, keine Physik.
- Lua-Syntaxprüfung aller Dateien.
- Mit dabei: `info.json` 0.6.0; `changelog.txt` (Features, Changes, Hinweis zum Herunterstufen); `README.md` („Stand“, Tabelle „Aufbau“
  mit den neuen Dateien); `docs/pruefstand.md` (6). DOC danach angleichen (vollständige Liste der Abweichungen):
  1. Sitze: Pilot zuerst, der Fahrer wird nur mit Pilot an Bord Beifahrer, Rückfall über den Teleport an den Flieger (DOC 2.1 Schritt 8
     „wird Beifahrer“, 4.2 Insassen, 7 Zeile 3c „Fahrer als Beifahrer“).
  2. Lastbild für alle sichtbar (4.0); 16 Richtungen `arrakis-harvester-carried-<i>` und `-shadow-<i>` aus Rumpf und Turm statt „Erster
     Frame von tank-base-1.png“, Offset aus der Flughöhe (DOC 3, 4.2 „offset = {0, 0.5}“).
  3. Prototypen-Tabelle DOC 3 um Probe `arrakis-harvester-probe`, Sticker `arrakis-ornithopter-empty`/`-loaded` und Shortcuts
     `arrakis-carry`/`arrakis-give-remote` ergänzen; das Bein heißt wie in DOC `arrakis-flyer-leg`.
  4. Welcher Flieger und welcher Ernter: die Stufen von `resolve_flyer`/`resolve_harvester` (4.5) statt DOC 4.2 „Anheben“ Punkt 1 und 2.
  5. `coupling` statt `docking`, Schema je Phase, `storage.stranded` (4.5).
  6. Ablage ohne Liste freier Plätze: frei ist, worauf nichts steht (DOC 4.2 „Freie Plätze stehen in einer Liste“).
  7. Landesuche mit Probe auch am Startpunkt, Warteliste statt Verlust (4.2 Sonderfälle).
  8. Kein Treibstoffabzug für Last (4.2 Punkt 5); Probe statt `spice-harvester` beim Absetzen (4.2); Tempo 8/5,6 (2.4).
  9. Eigener Fernbedienungs-Shortcut und Rückfallwege (2.1 Schritt 8, 8 T12).

## 8. Abnahme durch Max (0.6.0)
- `pruefstand.py` mit `T15 T16` (ohne Spieler, Tempo 10): beide ohne FEHLER, Datei schicken. T17 mit dir im Spiel, Datei und Antworten auf die FRAGEn.
- Neues Spiel bis „Spice-Ernte“, ersten Ernter herstellen: „Ornithopter“ ist sofort erforscht, Rezept und beide Verknüpfungen sind da.
- Ornithopter bauen, mit Kohle tanken, fliegen: deutlich schneller als der Ernter (leer 8 Kacheln/s), beladen spürbar langsamer.
- Vollen Ernter (2000 Spice-Sand) anheben, während du darin sitzt und ein Mitspieler oder du selbst per Fernbedienung den Ornithopter
  bringst; zu einem anderen Feld fliegen, absetzen: Inhalt, Treibstoff, Gesundheit und Farbe gleich, du sitzt im Ornithopter.
  Zurück in den Ernter steigen, Platz im Kofferraum schaffen, aufbauen: Er erntet auf dem neuen Feld.
- Aufgebauten und angedockten Ernter anheben (kein Einpacken); über einer Annahme absetzen: dockt an.
- Beladenen Ornithopter zerstören, in einer Kopie des Spielstands (`/c game.player.selected.die()` schaltet dort die Errungenschaften ab,
  docs/pruefstand.md „Im eigenen Spielstand“): Ernter liegt am Boden mit 30 % weniger Gesundheit, Meldung mit Ort.
- Anheben und Absetzen über Taste, Verknüpfung und Fensterknopf; aus der Karte mit der Fernbedienung und per Fernfahren.
- Beladener Ornithopter lässt sich nicht aufheben und nicht abreißen. Mit leerem Tank schwebt er mit Last; absetzen geht.
- Speichern und laden mit getragenem Ernter: Bild, Tempo und Last bleiben [U9].
- 0.5.5-Spielstand mit erforschter „Spice-Ernte“ laden [U12]: Wurde nie ein Ernter hergestellt, ist „Ornithopter“ nicht erforscht; mit
  einem hergestellten Ernter (gebaut, in einer Kiste oder im Inventar) ist er erforscht (4.15 zählt auch die Produktionsstatistik).
- Mit zwei Spielern einen Ornithopter zerstören und neu bauen: kein Desync [U20].
- Auf einer Kopie: `/arrakis-uninstall`, dann `/arrakis-uninstall ja`: getragene Ernter stehen am Boden, die Ablage ist weg.
- Offen aus 3b: die Abnahme-Punkte von Hand aus plan-3b.md 8 (T13 manuell, ERG053).
