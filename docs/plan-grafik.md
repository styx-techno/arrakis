# Plan Grafik-Phase (ab 0.14.0)

Stand 01.11.2026. Thread „Grafiken und Animationen verbessern“, Zweig `claude/project-thread-0eenzc`. Nur Bilder,
Blender-/Render-Skripte unter `tools/grafik/` und die Prototyp-Zeilen, die Bilder einbinden; keine Spiellogik.
Gerendert wird im Container (`pip install bpy pillow`, Python 3.13, bpy 5.x). Festlegungen zu Kamera, Licht, Blättern:
`tools/grafik/README.md`.

## Bestand

Eigene Grafik (Blender, 64 Richtungen, Schatten, Farbmaske): Spice-Ernter (0.8.5), Ornithopter (0.8.9), Carryall und
Leitstelle (0.10.0). Alle ohne Animation, Symbole 64 px ohne Mipmaps.

Noch Vanilla-Platzhalter (getönt):

| Was | heute | Datei |
|---|---|---|
| Thumper (Entity, Item, Forschung) | Pumpjack verkleinert, Pumpjack-Symbol, Ölförderung-Forschung | prototypes/thumper.lua |
| Wurmzahn (Item) | Stein | prototypes/thumper.lua |
| Forschung Revierkunde | Leitstellen-Bild | prototypes/depot.lua |
| Spice-Sand, Melange, Spice-Essenz, Brikett, Spice-Wissenschaft | Erz, Schwefel, Stein, Produktionspaket | prototypes/spice.lua, resources.lua |
| Raffinerie, Windfalle (nur Symbole; Entity bleibt Vanilla) | Ölraffinerie, Chemiefabrik | spice.lua, windtrap.lua |
| Sandwurm | Space-Age-Demolisher in Sand getönt | prototypes/sandworm.lua (bleibt; großer Wurm ist eigene Phase) |

Fehlende Animationen: Flügelschlag Ornithopter und Carryall, Raupenketten des Ernters.

## Fragen an Max (ohne Antwort gilt a)

1. Thumper: **a** eigenes Modell (Stange im Sand, Federhammer, pocht sichtbar, 16 Bilder) mit Symbol und
   Forschungsbild; b Pumpjack-Kopie bleibt.
2. Flügelschlag Ornithopter und Carryall: **a** 4 Bilder, Flügel als eigene Ebene in halber Auflösung (spart
   Grafikspeicher), schlägt immer, auch geparkt; b nur leichtes Flirren (2 Bilder); c kein Flügelschlag.
3. Ernter: **a** Raupenketten laufen beim Fahren (2 Bilder, eigene Ebene) und mehr Details (Scheinwerfer, Leitern,
   Staubschürzen); b nur Details; c bleibt.
4. Ernter Mk2: **a** eigene Variante desselben Modells (Wurmzahn-Klingen am Ansaugmaul, hellere Panzerplatten);
   b Mk1-Grafik getönt.
5. Symbole: **a** eigene Symbole für Wurmzahn, Thumper, Revierkunde und die Spice-Kette (fünf Items, zwei Gebäude);
   b nur Wurmzahn, Thumper, Revierkunde.

## Reihenfolge (je ein PR, Auto-Merge wenn Prüfungen grün)

1. Symbole Wurmzahn, Revierkunde + Thumper-Modell (Entity-Animation, Symbol, Forschungsbild).
2. Flügelschlag Ornithopter und Carryall.
3. Ernter: Raupenanimation, Details; Mk2-Variante (Absprache mit Thread „Ernter Mk2 mit Wurmzähnen bauen“, der die
   Prototypen schreibt; dieser Thread liefert nur Bilder und Bildzeilen).
4. Symbole der Spice-Kette.

## Technik

- Neue Modelle nutzen `tools/grafik/szene.py`. Thumper: 1 Richtung, 16 Bilder Stampfzyklus, 3 Kacheln Bildbreite
  (192 px, `scale = 0.5`), Schatten getrennt, Entity-Typ bleibt `simple-entity-with-owner` (`animations`).
- Symbole 64 px mit Mipmaps (4 Stufen, 120 × 64 px wie Vanilla), Forschungsbilder 256 px.
- Flügel-Ebene: Rumpf ohne Flügel neu rendern, Flügel je Bild in 32 px/Kachel (`scale = 1`), `RotatedAnimation` mit
  `frame_count = 4`. Ernter-Raupen ebenso als eigene Ebene, der Car-Typ schaltet die Bilder mit der Fahrt weiter.
- Grafikspeicher: neue Blätter höchstens 4096 px Kante, Animationen nur als halbe Auflösung.

## Prüfung vor jedem Push

1. `tools/check/datastage.py fd2123` (checks.lua; jede `__arrakis__`-Datei muss existieren).
2. `tools/check/base_paths.py fd2123` (Vanilla-Pfade).
3. Neues Prüfskript `tools/check/bilder.py`: Breite/Höhe jeder eigenen Sprite-Definition passt zur PNG-Größe
   (x/y + width/height × line_length bzw. frame_count innerhalb der Datei). Der Prüfstand-Server lädt keine Bilder;
   Fehler hier sähe erst Max im Spiel.
4. Probebilder als PNG in den Thread; nach dem Merge schaut Max im Spiel kurz drauf (keine Prüfstand-Läufe nötig,
   solange nur Bilder und Bildzeilen geändert sind).
