# Phase 3d2 (0.8.x): sichtbarer Sandwurm – Kurzfassung

Abgeschlossen; T21 15/15 im Prüfstand, T22 am 28.10.2026 von Max im Spiel komplett bestätigt. Das volle Protokoll
(Bauvertrag, storage Schema 4, Planung/Wächter/Angriff im Detail, Engine-Annahmen W1–W20, Prüfstand T21/T22) steht in
[`docs/protokolle/plan-3d2.md`](protokolle/plan-3d2.md). **Abschnittsnummern in Code-Kommentaren und im changelog
(„plan-3d2 4.8“, „W12“) beziehen sich auf das Protokoll**, nicht auf diese Kurzfassung.

## Bauweise
- `scripts/sandworm.lua`: der Wurm als Fahrzeug (Planung, Weg, Erzeugen, Steuern, Wächter, Tempo, Abtauchen, Waisen).
  `scripts/worms.lua` bleibt Herr der Jagd (Phasen, Biss, Zerdrücken, Tod/Verlust). sandworm entscheidet nie, wer stirbt;
  worms nie, wohin der Wurm fährt. Kein neuer Takt: der 10-Tick-Takt von worms.lua ruft `track`, `sandworm.step`,
  Zerdrücken, Biss-Fenster in fester Reihenfolge.
- Prototyp `arrakis-sandworm-small`: Kopie des kleinen Demolishers, 12 Segmente, sandfarben, ohne Asche/Lava/Erdspalten,
  ohne Kontaktschaden, ohne Beute/Leiche, 30 000 LP (Vanilla). Maske ohne `arrakis_rock` (Fels hält nur der Wächter fern).
- `storage.hunts.log`: letzte 20 Jagden mit Phasen/Zeiten; je Jagd mit Wurm eine Logzeile.

## Festlegungen und Zahlen
| Punkt | Festlegung |
|---|---|
| Wurm oder nicht | Wurm ab 27 s Countdown, sonst Phase `ohne` (Biss wie 0.7.0 genau bei 0) |
| Tempo | 3,5 Kacheln/s (investigating/attacking/enraged), Patrouille 1; Sprint bis 6 Kacheln/s per Skript (Max: ja, `SPRINT = true`) |
| Spawn | `D = min(160, 3,5·(T−4))`; Spawn so, dass er mit 3 s Reserve bei 0 ankommt (60 s: 670 Ticks nach dem Wurmzeichen) |
| Planung | 16 Richtungen um den Zielpunkt mit Sandlinie (Abstand D, dann 120, 80); `request_path` nur ohne Sandlinie (höchstens 2 Kandidaten); Körperprüfung jeder 4. Knoten auf Sand, höchstens 3 Erzeugungen |
| Zielpunkt | Zielmitte, sonst letzte Stelle; geklemmt auf den Reichweitenkreis (3,5 Kacheln/s × Countdown um die Wurmzeichen-Stelle) |
| Wächter | alle 10 Ticks: Kopf auf Fels/ungeneriert → sofort abtauchen; Vorausschau 18 Kacheln, Umweg ±30/60/90°, einmal Neuplanung, 300 Ticks Stillstand → abtauchen. Betritt nie Fels |
| Biss | nie vor 0, spätestens 3 s danach (Ersatzbiss); Reichweite R = 3 + halbe Zieldiagonale (Ernter 4,58). Regeln wie 3d1 im Moment des Bisses |
| Zerdrücken | Kopf alle 10 Ticks, Radius 2,5, alles auf Sand **inklusive Fahrzeuge und Figuren** (Max 27.10., `worms.CRUSH_SPARES_VEHICLES = false`); Ernter nach `arrakis-worm-bite`. Nie Ornithopter, nie Bauten von Forces in der Schonfrist |
| Wurm getötet | Jagd endet, Ziel gerettet (Max: ja) |
| Sandtasche | Ziel ohne Weg für den Wurm wird bei 0 trotzdem gebissen (Max: ja) |
| Grenzen | reguläre Jagden immer mit Wurm (max. 3); Befehlsjagden max. 3 mit Wurm (`MAX_DEBUG_WORMS`); zusammen ≤ 6 |
| Flieger | Ornithopter werden nie getroffen und nicht spürbar gebremst (T21 Schritt 6 wacht mit 80 %) |
| Abtauchen | nach Biss bzw. Suche (≤ 8 Kacheln vom Zielpunkt, spätestens 10 s nach 0); ab 0.8.4 bleibt er `DIVE_TICKS` = 60 stehen, Staubwelle über den Körper (Max: Ton gut) |
| Migration | Schema 4; alte Jagden → Phase `ohne`; Waisen werden geräumt; `/arrakis-uninstall ja` lässt alle Würmer abtauchen |

## Nacharbeiten 0.8.4–0.8.9 (nach T22)
Wurm früher und lauter hörbar, Abtauchen als Sandstaub statt „Verschwinden“, `/arrakis-test weiter` schaltet interaktive
Tests wie ALT+O weiter (ALT+O kam in T12 nie an). Details im changelog.

## Offen
- T21 Schritt 6 (W12, Bremsen über dem Körper): einmal FEHLER; Messung, ob der Wurm unter dem gebremsten Vergleichsflieger lag.
- Engine-Annahmen W2, W5/W11, W16, W20 nicht abschließend belegt.
- Großer Wurm, Thumper, Beute/Wurmzahn, Mod-Einstellungen, Balancing: 3d3.
