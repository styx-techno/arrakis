# Plan 3g: Wurm-Reviere (Ziel 0.13.0)

Stand: 01.11.2026, Umsetzung in PR #3 (0.13.0). Grundlage: docs/plan-3e.md (Nachtrag 0.11.0, „Später: echte Reviere mit festen Wurmgebieten“), docs/plan-3f.md, Design 2.5 („Jagdwurm auf Abruf“). Abschnitt 1 sind die Festlegungen; **Max hat am 01.11.2026 01:42 gewählt: „1a 2a 3b 4c 5a“.** Volle Begründungen früherer Phasen: docs/protokolle/.

## 0. Ziel

Arrakis bekommt feste Wurmgebiete. Die Wüste ist in Reviere aufgeteilt, in jedem lebt ein Wurm mit eigenem Charakter. Man lernt, wo man sicher ernten kann und wo nicht; wer einen Wurm tötet, hat in seinem Revier eine Weile Ruhe, dann zieht ein neuer ein.

Technisch bleibt es beim Jagdwurm auf Abruf (Design 2.5): Kein Wurm wohnt sichtbar und dauerhaft auf der Karte, die Engine-Territorien nutzen wir nicht. Ein Revier ist reine Skriptbuchhaltung über den Sektoren (4×4 Chunks = 128×128 Kacheln, scripts/vibration.lua), die schon heute Ruhe und Lauern tragen.

Nicht in 3g: Thumper, Beute/Wurmzahn, großer Wurm, Mod-Einstellungen (nächste Phase), Patrouillen und Radar-Modus aus 2.1.

## 1. Festlegungen (gewählt: 1a 2a 3b 4c 5a)

1. **Zuschnitt.** a) unregelmäßig, etwa 256×256 Kacheln (2×2 Sektoren): Je 256er-Zelle ein Mittelpunkt, aus dem Kartenseed verschoben; jeder Sektor gehört zum nächsten Mittelpunkt. Ergibt natürliche Grenzen entlang der Sektorkanten. b) feste Quadrate 256×256. c) größer, etwa 512×512.
2. **Gefahrenstufen.** a) drei Stufen ruhig / normal / wild, je weiter vom Landeplatz, desto wilder (Zahlen 3). Das Startrevier (Landeplatz und Lehrfeld) ist immer ruhig. b) drei Stufen rein zufällig, nur das Startrevier ruhig. c) keine Stufen, Reviere regeln nur Besetzung und Ruhe.
3. **Getöteter Wurm.** a) Das Revier ist 30 min frei (keine Wurmzeichen, kein Lauern), dann zieht ein neuer Wurm ein, mit einer Ankündigung im Chat 60 s vorher. b) 60 min frei. c) Töten ändert am Revier nichts.
4. **Sichtbarkeit.** a) Ein Revier wird für eine Force bekannt, sobald dort ihr erstes Wurmzeichen kommt; bekannte Reviere zeigen Grenze, Name und Stufe in der Vibrationsanzeige und im Leitstellen-Fenster. b) alle Reviere von Anfang an sichtbar. c) sichtbar erst mit einer neuen Forschung „Revierkunde“ (Spice-Wissenschaft).
5. **Leitstelle.** a) Sie verteilt Ernter zuerst auf Felder in ruhigen, dann normalen, zuletzt wilden Revieren und meidet freie Reviere nicht. b) Sie ignoriert Reviere (Verteilung wie 0.12.x).

## 2. Regeln (nach Max' Wahl)

- **Ein Wurm je Revier.** Höchstens eine reguläre Jagd je Revier zugleich (bisher je Sektor). MAX_HUNTS = 3 über alles bleibt. Befehlsjagden (/arrakis-worm, Prüfstand) ignorieren Reviere wie bisher.
- **Ruhe gilt fürs ganze Revier.** Nach einer Jagd ruht das Revier REST_MIN bis REST_MAX mal Stufenfaktor. Lauern (0.11.0) bleibt am Sektor der Jagd, sperrt aber das Revier für neue Wurmzeichen außerhalb des Lauerns.
- **Stufe wirkt auf drei Dinge:** Schwelle des Wurmzeichens (vibration.WORMSIGN × Faktor), Countdown (± Sekunden, nach der Frühwarnung, nie unter 30 s) und Ruhe. Die Unruhe (600) bleibt gleich, Staub und Rumpeln warnen also überall gleich früh.
- **Lehrjagd** bleibt unverändert (90 s, erste Jagd jeder Force); das Startrevier ist ruhig, also kommt sie wie bisher am Lehrfeld.
- **Forschung „Revierkunde“ (4c):** Voraussetzung Ornithopter-Leitstelle (arrakis-ornithopter-depot), 300 Einheiten mit denselben Paketen wie die Leitstelle, 30 s. Danach sieht die Force alle Reviere auf Arrakis: Grenze, Name und Stufe in der Vibrationsanzeige, Stufe je Feld im Leitstellen-Fenster. Ohne die Forschung gibt es nur das Wurmzeichen wie bisher.
- **Leitstelle (5a):** Mit Revierkunde verteilt sie Ernter zuerst auf Felder in ruhigen, dann freien und normalen, zuletzt wilden Revieren. Ohne die Forschung kennt sie die Stufen nicht und verteilt wie 0.12.x.
- **Freies Revier** nach einem getöteten Wurm (3b, 60 min): kein Wurmzeichen, kein Lauern, die Leitstelle zählt es als ruhig. Ein Wurm aus einem Nachbarrevier kommt nicht herüber (einfach, eindeutig).
- **Deterministisch:** Zuschnitt und Stufen hängen nur vom Kartenseed der Oberfläche ab, werden pro Sektor bei Bedarf berechnet und zwischengespeichert. Laufende Spielstände bekommen die Reviere per Migration; bestehende Ruhe und Lauern bleiben gültig.
- **Andere Oberflächen:** Reviere nur auf Arrakis und der Prüfstand-Fläche (dort mit fester Testkarte der Reviere).
- **Namen:** Reviere heißen nach Lage und Nummer, z. B. „Revier N3-O2“ (Richtung und Abstand in 256er-Schritten vom Landeplatz). Keine Namen aus Büchern oder Filmen.

## 3. Zahlen (Standard, im Code als lib-Konstanten)

| Stufe | Schwelle Wurmzeichen | Countdown | Ruhe nach Jagd | Anteil 520–1100 Kacheln | Anteil über 1100 |
|---|---|---|---|---|---|
| ruhig | 1400 (×1,4) | +15 s | ×1,5 (3–6 min) | 30 % | 10 % |
| normal | 1000 | ±0 | ×1 (2–4 min) | 55 % | 50 % |
| wild | 700 (×0,7) | −10 s | ×0,5 (1–2 min) | 15 % | 40 % |

Revier mit Mittelpunkt näher als 520 Kacheln am Landeplatz: ruhig (deckt das Lehrfeld 140 Kacheln vom Start sicher ab). Einordnung: Ein einzelner Ernter ohne Dämpfung (30/s, Zerfall 0,98) braucht bis zum Wurmzeichen etwa 31 s (wild), 54 s (normal), 134 s (ruhig). Mit voller Ernte-Dämpfung (−50 %) löst ein einzelner Ernter in ruhigen und normalen Revieren gar nicht mehr aus, in wilden nach etwa 90 s. Freies Revier nach Tod: 60 min = 216 000 Ticks, Ankündigung 3600 Ticks vorher.

## 4. Umsetzung

- Neue Datei scripts/territory.lua (lib als territory_lib): Zuschnitt, Stufe, Name, Zustand je Revier `storage.territory[s][id] = {level, known = {force → true}, free_until, rest_until}`, Abfragen `of_sector`, `of_position`, `threshold`, `warn_bonus`, `rest_factor`.
- scripts/worms.lua: `eligible` und `wormsign_tick` prüfen Revier statt Sektor; `start_hunt` merkt sich das Revier; Ruhe über territory; `on_segmented_unit_died` setzt free_until; Countdown-Bonus in `warn_ticks`.
- prototypes/technology.lua oder depot.lua: Forschung arrakis-territory-survey (Revierkunde) mit Icon (Pfad per Skript prüfen).
- scripts/vibration.lua: Overlay zeigt nach Revierkunde die Reviere (Grenzlinie und Text, nur im sichtbaren 7×7-Bereich).
- scripts/fleet-fields.lua / fleet-gui.lua: Stufe je Feld, Sortierung (1.5 a), Anzeige im Fenster.
- scripts/migrate.lua: neues Schema, legt storage.territory an.
- Locale de/en, changelog, info.json nur über das übliche Versionsskript, Pflichtfelder in checks.lua, Grafikpfade per Skript.

## 5. Prüfstand

- **T30 (automatisch, 8 Schritte):** 1 Zuschnitt (zweimal gleich, 2–8 Sektoren, sectors_of passt); 2 Startrevier mit Lehrfeld bei 4 Seeds ruhig; 3 Stufenanteile; 4 Schwelle 1400/1000/700 und Countdown 75/60/50 s, wild mit Frühwarnung 6 → 80 s; 5 Ruhe fürs ganze Revier (×1,5) und Lauern; 6 freies Revier (Standard 60 min, im Test 15 s), Rang, Ankündigung, Ablauf; 7 Revierkunde (known, Ränge); 8 Schema 7. Nicht automatisch: echtes Wurmzeichen erst ab Revier-Schwelle und das Freiwerden beim Töten eines echten Wurms (über die Kette in worms.lua, im Spiel bei Max).
- Bestehende T19, T21, T23–T29 müssen grün bleiben (Prüfstand-Fläche bekommt eine feste „normal“-Revierkarte, damit alte Erwartungen gelten).
- **T31 (interaktiv, im Spiel bei Max):** Reviergrenzen und Namen in der Vibrationsanzeige und im Leitstellen-Fenster sehen verständlich aus.

## 6. Abnahme

T30 und alle alten automatischen Tests grün auf Max' PC → selbst mergen (Max 01.11.: „Wenn alle Tests in einem Thread erfolgreich waren, kann es auto-merged werden“). T31 sammelt Max für den Spielabend.
