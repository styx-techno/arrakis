# Phase 3b (0.5.x): Spice-Ernter, Annahme, Tankstutzen, Brikett – Kurzfassung

Abgeschlossen und von Max abgenommen. Das volle Protokoll (Bauvertrag, Zustandstabellen, Texte, Prüfstand-Schritte)
steht in [`docs/protokolle/plan-3b.md`](protokolle/plan-3b.md). **Abschnittsnummern in Code-Kommentaren und im
changelog („plan-3b 4.5“) beziehen sich auf das Protokoll**, nicht auf diese Kurzfassung.

## Umfang 0.5.0
- Spice-Ernter (Typ `car`): Fahren mit Tempo-Ausgleich je Brennstoff und Tempo-Deckel jeden Tick, Aufbauen (5 s),
  Abbau per Skript, Einpacken (10 s), Status, Alarme, relatives Fenster mit Knopf, Taste `Umschalt+H`.
- Ressourcenkategorie `arrakis-spice-harvest`: Spice nur per Ernter und von Hand; alte Bohrer auf Spice werden gemeldet
  (Kartenmarkierung, Alarm; nicht erstattet, nicht abgerissen).
- Spice-Annahme und Tankstutzen (`proxy-container`), Andocken mit Hysterese, Abdocken.
- Spice-Brikett (Raffinerie), Forschung „Spice-Ernte“, Mod-Einstellung `arrakis-worm-bite` (wirkt ab 3d1).
- Prüfstand T13 (echter Code) und T2b (Fahrphysik).
- Kartengenerator kam mit 0.5.4/0.5.5 (Kegel-Inseln c4, Zahlen in `docs/protokolle/design-ernter-ornithopter.md` 2.4).

## Festlegungen (gelten weiter)
| Punkt | Festlegung |
|---|---|
| Tempo | `consumption = 330kW`; Ausgleich `effectivity_modifier = min(1, 1/(a·t²))` (a = Beschleunigungs-, t = Höchsttempo-Faktor des Brennstoffs inkl. Qualität; t wirkt ab 2.1.13 linear, 0.5.3). Deckel jeden Tick bei 1,5 Kacheln/s, Rücksetzen auf 1,45. Nie `fuel_category` lesen. |
| Deckel | Konstanten im Code, keine Mod-Einstellung (sonst Fluchtregel ausgehebelt) |
| Brikett | 5 Spice-Sand + 1 Kohle → 1 Brikett (20 MJ), 4 s, ohne Produktivität, 10 kg |
| Aufheben | Ernter auf Arrakis nicht abbaubar, solange Sand unter ihm liegt oder er aufgebaut ist (`refresh_minable`); Dekonstruktion wird storniert |
| Fernbedienung | Taste/Knopf auch aus der Kartenansicht (gleiche Force); Fernfahren nicht |
| Gepflasterter Fels | zählt im Skript als Fels; Annahme von Hand nur auf ungepflastertem Fels baubar |
| Qualität des Ernters | ändert nur Lebenspunkte |

## Zahlen
- Abbau: 5 Einheiten/s, Ausbeute × (1 + Bergbau-Produktivität); Feld 13×13 um die Ernter-Mitte; Abzug 0,5 je Eingefügtem / (1+Bonus).
- Verbrauch beim Ernten 400 kW (Skript, `consume`).
- Andocken: ≥ 2 s Stillstand, Annahme ≤ 4 Kacheln; nach Abdocken erst wieder ab > 5 Kacheln Abstand. Stutzen gehört zur nächsten Annahme in ≤ 3 Kacheln.
- Annahme nur auf Fels (±5 um die Mitte), sonst Abriss-Auftrag.
- Gemessen (T2, 0.4.0): Kohle 1,4 / Festbrennstoff 1,5–1,6 / Raketentreibstoff 1,9–2,1 Kacheln/s ohne Ausgleich; mit Ausgleich ≤ 1,5.

## Bauweise (Kurz)
- Zustände: `mobile`, `deploying`, `deployed`, `packing`, `docked` (Datensätze in `storage.harvesters[unit_number]`, Schema 1).
- Takte: `on_tick` nur für gefahrene Ernter (Deckel), 10 Ticks Ringe/Timer, 30 Ticks Abbau, 60 Ticks Andocken/Abbausperre.
- Module: `scripts/harvester.lua`, `harvester-gui.lua`, `intake.lua`, `terrain.lua`, `migrate.lua`; alles über event_handler, kein Modul ruft `script.on_event` direkt.

## Abnahme (Max, 0.5.0)
Spice von Hand → Forschung; Ernter aufbauen/ernten/einpacken; kein Brennstoff schneller als 1,5; Ernter auf Sand nicht
aufhebbar; Annahme/Stutzen docken an und leeren/tanken; alter Spielstand lädt. T13 und T2b laufen durch.
