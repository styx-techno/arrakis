# Phase 3c (0.6.x, Nachtrag 0.9.0): Ornithopter, Ablage, Anheben und Absetzen – Kurzfassung

Abgeschlossen und von Max abgenommen. Das volle Protokoll (Bauvertrag, Engine-Annahmen U1–U28, Texte, Prüfstand T15–T17)
steht in [`docs/protokolle/plan-3c.md`](protokolle/plan-3c.md). **Abschnittsnummern in Code-Kommentaren und im changelog
(„plan-3c 4.9“, „U6“) beziehen sich auf das Protokoll**, nicht auf diese Kurzfassung.

Max' Wunsch: mobile Ernter, die man per Ornithopter transportiert und vor Würmern rettet; erst von Hand, später automatisch.
3c ist der Handteil (Spieler fliegt selbst); Automatik kam mit 3e/3f.

## Umfang
- `arrakis-ornithopter` (`spider-vehicle`, 4 unsichtbare kollisionsfreie Beine, Brenner, 2 Sitze), Trigger-Forschung
  „Ornithopter“ (ersten Spice-Ernter herstellen; Skript erforscht zusätzlich, weil der Trigger nicht immer feuert, U11).
- Ablage-Oberfläche `arrakis-hold` (256 Plätze im 10er-Raster, für alle Forces versteckt), dort steht ein getragener Ernter.
- Ankoppeln (2 s), Anheben mit Notstart (aufgebaut/angedockt → sofort mobil), Tragen mit Lastbild und Schatten, Absetzen mit
  Platzprüfung; auf einer Annahme abgesetzt dockt er an.
- Drei gleichwertige Bedienwege: Taste `Umschalt+C` (`arrakis-carry-toggle`), Shortcut `arrakis-carry`, Knopf im Fenster;
  dazu Fernbedienungs-Shortcut und Fernfahren (nur der Ornithopter, nie der Ernter).
- Insassen des Ernters fliegen mit; nach dem Absetzen Knopf „In den Ernter steigen“.
- `/arrakis-uninstall` (zweistufig mit `ja`), Migration Schema 2.

## Festlegungen (gelten weiter)
| Punkt | Festlegung |
|---|---|
| Wahl Flieger | `player.vehicle` → Fernbedienungsauswahl → `player.selected` → nächster eigener leerer Ornithopter ≤ 4 Kacheln (Solo-Rettung) |
| Wahl Ernter | `player.selected` → Fahrzeug des Spielers → nächster freier eigener Ernter, je ≤ 4 Kacheln |
| Wer darf | nur eigene Force, nur `spice-harvester`, einer je Flieger; Anheben auch mit leerem Tank |
| Absetzen | Probe `arrakis-harvester-probe` (±1,6) an der Fliegerposition, sonst Radius 6, sonst „Kein Platz“ (Last bleibt) |
| Absturz | Tod des Fliegers → Ernter an nächster freier Stelle (Radien 6/16/32 um Todesstelle, dann Abhebepunkt, dann Startpunkt bis 64), −30 % der Höchst-LP direkt geschrieben (mind. 1). Anders entfernt → zurück zum Abhebepunkt ohne Schaden. Kein Platz → wartet auf der Ablage (`storage.stranded`), jede Sekunde neuer Versuch |
| Tank leer | Flieger schwebt, Last bleibt |
| Last | kostet keinen Extra-Treibstoff per Skript (Leistung konstant, Kosten je Kachel steigen von selbst) |
| Sichtbarkeit | Lastbild und Schatten für alle Forces, Ankoppelring nur eigene |
| Werte | Konstanten im Code, keine Mod-Einstellung |
| Herunterstufen | auf 0.5.x mit getragenem Ernter nicht unterstützt |
| Rezept | 30 Stahl, 20 Motoreinheit, 10 Fortgeschr. Schaltkreis, 10 Melange, 10 s; 3000 LP, Kofferraum 10, keine Waffen |

## Tempo (Stand 0.9.0)
- Seit 0.9.0 nur **Flugtreibstoff**: eigene Kategorie `arrakis-flight-fuel`, `data-final-fixes.lua` gibt sie jedem chemischen
  Brennstoff mit Beschleunigung ≥ 1,8 und Höchsttempo ≥ 1,15 (Raketentreibstoff und besser). Altbestände räumt der
  60-Tick-Takt in den Kofferraum.
- Sticker-Familien (`prototypes/ornithopter-speed.lua`): je Zustand (`empty`/`loaded`) 106 Stufen t_j = 1,02^j, j = −35…70;
  `BASE_EMPTY = 0.603`, `BASE_LOADED = 0.427`. Stufe aus r = t / g, g = a / 1,8.
- Ergebnis leer: Raketentreibstoff 8,0, Atom 11,3, legendär Rakete 13,7, legendär Atom 21,5 Kacheln/s; beladen ≈ 70 %.
- Belegt (T16, 0.6.0): Tempo ∝ t des Brennstoffs; Sticker gleichen Namens ersetzt die Engine am selben Ziel.
- Offen: ob die Spinnenbeine 21 Kacheln/s mitgehen (T1 schaffte 19,6).

## Abnahme (Max)
T15/T16 ohne FEHLER, T17 im Spiel (noch offen bei Max). Anheben/Absetzen über alle drei Wege, voller Ernter behält Inhalt,
Treibstoff, LP und Farbe; Absturz −30 %; Speichern/Laden mit Last; `/arrakis-uninstall` stellt Ernter ab.
