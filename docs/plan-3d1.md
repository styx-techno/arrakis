# Phase 3d1 (0.7.0): Vibration, Wärme, Unruhe, Wurmzeichen, Countdown, Biss – Kurzfassung

Abgeschlossen (Lauf 26.10.2026: alle Tests grün, T18 11/11, T19 10/10). Das volle Protokoll (Bauvertrag, storage Schema 3,
Zustände der Jagd, Engine-Annahmen V1–V22, Prüfstand T18–T20) steht in
[`docs/protokolle/plan-3d1.md`](protokolle/plan-3d1.md). **Abschnittsnummern in Code-Kommentaren und im changelog
(„plan-3d1 4.9“, „V14“) beziehen sich auf das Protokoll**, nicht auf diese Kurzfassung.

3d1 liefert die Gefahr, vor der man rettet: Vibration heizt die Gegend auf, der Sand bebt, ein Wurmzeichen kündigt den Biss
an, nach dem Countdown bricht eine Sandfontäne hervor. Den sichtbaren Wurm brachte 3d2.

## Module
`scripts/vibration.lua` (Quellen, Wärme, Unruhe, Vorsichtsmodus, Vibrationsanzeige), `scripts/worms.lua` (Schonfrist, Jagden,
Biss, Warnungen, Sandwurm-Force, `/arrakis-worm`), `scripts/worms-gui.lua` (Fenster oben links). Nur worms.lua hat die
Wurm-Takte (60 und 10 Ticks) und ruft vibration.lua in fester Reihenfolge auf. Alle Zahlen sind Code-Konstanten.

## Festlegungen und Zahlen
| Punkt | Festlegung |
|---|---|
| Sand | natürliche Kachel ≠ `arrakis-rock`; gepflasterter Fels ist Fels. „Ganz auf Fels“ = `not terrain.has_sand_under(entity)` |
| Oberflächen | nur wo `terrain.harvest_allowed` (Arrakis; mit Prüfstand auch `arrakis-testbench` für Test-Forces) |
| Gewichte Ernter | aufgebaut/einpacken 30, fahrend 10, aufbauen/stehend/angedockt/getragen 0, Einpacken durch Vorsichtsmodus 0 |
| Gewichte sonst | fahrend: Panzer 8, Auto 4, Spinne 6 (nicht Ornithopter), Lok 6; arbeitend: großer Bohrer 8, Pumpe 2, Bohrer 3, Montage/Ofen 1 |
| Wärme | je Chunk `H ← H·0,98 + ΣV` im 60-Tick-Takt; gewertet als S(c) über 3×3 Chunks |
| Schwellen | Unruhe W ≥ 600; Wurmzeichen S ≥ 1000 und im Takt davor ≥ 600 (kündigt sich immer mit Unruhe an) |
| Zeiten | ein Ernter ab kaltem Sand: Unruhe im 26. Takt, Wurmzeichen im 55. Takt (belegt); nach Anfahrt aufs Lehrfeld ≈ 17 bzw. 47 s |
| Grenzen | 1 Jagd je Sektor (4×4 Chunks), 3 zugleich, 1 neue je Takt und Oberfläche; danach Wärme 3×3 auf 0, Sektor ruht 2–4 min (`storage.rng`) |
| Countdown | 60 s; erste Jagd jeder Force auf einen Ernter = Lehrjagd 90 s. Biss genau bei 0, Countdown verlängert sich nie |
| Entkommen | getragen, andere Oberfläche, ganz auf Fels, oder weiter als 3,5 Kacheln/s × Countdown von der Wurmzeichen-Stelle (210 / 315 Kacheln) |
| Ziel weg | Countdown läuft weiter, harmlose Eruption; danach „sucht“ 10 s |
| Biss | alle Entities mit Gesundheit ≤ 4 Kacheln um das Ziel auf Sand sterben (`die("arrakis-sandworm")`); ausgenommen Ornithopter samt Insassen |
| Totalverlust (Standard) | Kofferraum/Treibstoff leeren, **Insassen sterben mit** (Max), Wrack `tank-remnants` bleibt. Einstellung `heavy-damage`: Ernter überlebt mit 10 % LP, Laderaum leer |
| Fahrzeuge | Panzer/Auto sind Jagdziel (Max: ja) |
| Schonfrist je Force | `min(Ornithopter erforscht + 10 min, erste Landung + 30 min)`; vorher Vibration/Unruhe, aber keine Jagd |
| Vorsichtsmodus | Schalter je Ernter: bei W ≥ 600 einpacken mit Gewicht 0, bei W < 300 wieder aufbauen. ≈ 28 % Erntezeit, gut ein Viertel der Ausbeute (Max: so lassen). Ein Vorsichts-Ernter wird nie selbst Ziel |
| Flucht per Fahrt | Lehrfeld entkommt in 60 s; reguläre Felder (≥ 100 Kacheln vom Fels) nicht, außer in der Lehrjagd bis ≈ 111 Kacheln (Max: so lassen) |
| Warnungen | Alarm, Warnton, Kartenmarkierung, Ring mit Sekunden (grün, wenn sicher), Fenster oben links, Status am Ernter |
| Sandwurm-Force | `arrakis-sandworm`, feindlich zu allen außer `neutral` |
| Befehl | `/arrakis-worm [Sekunden|lehr]` (Admin) auf die ausgewählte Entity, ohne Grenzen/Ruhe/Statistik |
| Statistik | `storage.worm_stats[force] = {bitten, escaped, gone, first_escape_tick}` (für den Thumper in 3d3) |
| Briefings | Tipps `arrakis-briefing`, `arrakis-wormsign-tip` + je eine Chatzeile |

Konstanten zu Max' Entscheidungen: `worms.TOTAL_LOSS_OCCUPANTS`, `worms.TEACH_TICKS = 5400`, `vibration.CAREFUL_LOW = 300`,
`worms.VEHICLE_TARGETS`, `worms.WORM_SPEED = 3,5`. Texte, changelog und Tests nennen die Werte fest; beim Ändern mitziehen.

## Belegt im Prüfstand (26.10.2026)
- `find_entities_filtered` findet Figuren im Fahrzeug nicht (V14) → Weg über `get_driver`.
- `status == working` gilt auch auf Laborkacheln (V13).
- Vorsichtsmodus-Zyklen 39 % (erster ab kaltem Sand), dann 27 %.

## Offen bei Max
T20 (interaktiv, vorher `/arrakis-test tempo 1`).

## Nicht in 3d1
Wurm-Entity, Route, Fels-Wächter (3d2); Thumper, Beute, großer Wurm, Mod-Einstellungen, Balancing (3d3);
Frühwarnung, Ernte-Dämpfung (0.12.1); Pins/Musik (3g).
