# Plan 3i: Ernter Mk2 (Ziel 0.15.0)

Stand 01.11.2026. Nachfolger von docs/plan-3h.md (Wurmzähne als Beute). Großer Wurm und Grafiken sind eigene Phasen.

## Ziel

Wer Würmer tötet, bekommt mit den Wurmzähnen einen besseren Ernter: Der **Ernter Mk2** (`spice-harvester-mk2`) fördert
mehr und lärmt weniger. Er ist ein eigenes Fahrzeug, kann aber alles, was der Ernter kann (Aufbauen, Andocken, Tragen,
Leitstelle, Jagdziel). Eigene Grafik kommt mit der Grafik-Phase; bis dahin ist es das Ernter-Bild mit Farbton.

Nicht in 3i: großer Wurm, neue Grafiken/Animationen, Umrüsten im Feld.

## 1. Festlegungen (Max 01.11. 04:59: „1b 2b 3b 4a“, umgesetzt in 0.15.1; 0.15.0 hatte überall a)

1. **Werte.** a) +50 % Abbau (7,5 statt 5 Spice-Sand/s), −20 % Vibration, sonst wie Mk1. b) wie a, dazu Laderaum
   60 statt 40 und +50 % Lebenspunkte. c) +100 % Abbau, Vibration wie Mk1.
2. **Rezept.** a) 1 Ernter + 4 Wurmzähne + 10 Spice-Essenz (verdirbt in 15 min, also frisch verbauen). b) 1 Ernter +
   4 Wurmzähne + 10 Melange + 5 Prozessoren (nichts Verderbliches).
3. **Freischaltung.** a) Trigger-Forschung: erforscht, sobald die Force zum ersten Mal Wurmzähne erbeutet (Wurm
   getötet). b) normale Forschung, 500 Einheiten mit Spice-Wissenschaft, Voraussetzung Thumper.
4. **Leitstelle.** a) setzt aus ihrem Lager zuerst Mk2 ein. b) keine Bevorzugung (erster im Lager).

## 2. Regeln (nach Wahl 1b 2b 3b 4a)

### 2.1 Fahrzeug
- Kopie des Ernters (`car`), Name `spice-harvester-mk2`, Item gleichen Namens (Stapel 1), Basis-Ebene und Symbol mit
  Farbton (kühler Stahlton {0,7; 0,8; 1}; ein Tint dunkelt nur ab, hell geht erst mit eigener Grafik), Farbmaske bleibt Spielerfarbe.
- Fahrphysik, Tempo-Deckel 1,5, Treibstoffe, Aufbau 5 s, Einpacken 10 s, Feld 13×13: wie Mk1.
- Abbau 7,5 Spice-Sand/s; Feldabzug je Spice-Sand wie Mk1 (Felder leeren sich 50 % schneller). Verbrauch beim Ernten
  600 kW statt 400 kW (gleicher Brennstoff je Spice-Sand).
- Vibration ×0,8 in jedem Zustand (fahrend, aufbauend, aufgebaut, einpackend); wirkt zusätzlich zur Ernte-Dämpfung
  (Stufe 10: 0,5 × 0,8 = 0,4).
- Laderaum 60, Brennstoff 3 Plätze, Lebenspunkte ×1,5.

### 2.2 Rezept und Forschung
- Rezept `spice-harvester-mk2`: 1 Ernter + 4 Wurmzähne + 10 Melange + 5 Prozessoren, 20 s, Handwerk/Montage.
- Forschung `arrakis-harvester-mk2`: 500 Einheiten (Automatisierung, Logistik, Chemie, Weltraum, Spice), 30 s,
  Voraussetzung „Thumper“. (0.15.0 hatte eine Trigger-Forschung beim ersten Wurmzahn.)

### 2.3 Gemeinsamer Code
- `scripts/harvester.lua`: `lib.NAMES` (Mk1, Mk2), `lib.is_name(name)`, `lib.MK2`, `lib.rate_factor(entity)`,
  `lib.vibration_factor(entity)`. Alle Module prüfen `harvester.is_name` statt `== harvester.NAME`: vibration, worms,
  flyer (Lastbild am Flieger mit gleichem Farbton), fleet (Lager zählen, einlagern, Mk2 zuerst ausgeben),
  harvester-gui, migrate (Ornithopter-Auslöser bleibt Mk1).
- tools/check/checks.lua: Mk2 als Pflicht-Prototyp, gleiche Ebenen/Grafikpfade wie Mk1, Rezept enthält Wurmzähne.

## 3. Tests

- **T35 Ernter Mk2 (Prüfstand):** Prototyp-Werte (Laderaum, Farbton, Rezept, Forschung); Abbau in 20 s ≈ 1,5 × Mk1
  nebeneinander auf gleichem Feld; Vibrationsgewicht aufgebaut = 0,8 × Mk1; Wurm-Beute schaltet die Forschung nicht frei (seit 0.15.1);
  Carryall hebt Mk2 an und setzt ihn ab (Name und Laderaum bleiben); Leitstelle lagert Mk2 ein und gibt ihn vor Mk1
  wieder aus; Jagd auf Mk2 gilt als Ernter-Jagd (Rettung wie Mk1).
- **T36 interaktiv (Spielabend):** Mk2 herstellen, Farbton und Fenster ansehen, mit Ornithopter tragen.
- Laufende Tests T1–T33 unverändert grün (Mk1-Verhalten bleibt gleich).
