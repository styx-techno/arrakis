# Plan 3j: Großer Wurm (Ziel 0.16.0)

Stand 01.11.2026. Nachfolger von docs/plan-3i.md (Ernter Mk2). Grundlage: Design v0.3 (Schwelle „großer Wurm ab
2000“, Beute 6–10 Zähne, Vorausschau 24 Kacheln), plan-3h.md Frage 5.

## Ziel

Bei einem Wurmzeichen kommt per Zufall nach der Revierstufe statt des kleinen der **große Wurm**
(`arrakis-sandworm-large`). Er ist größer, zäher und frisst mehr um sich herum, folgt aber denselben Regeln:
Wurmzeichen, Countdown, Rettung, Biss bei 0, Thumper-Ablenkung, Reviere. Wer ihn tötet, bekommt mehr Zähne.

Nicht in 3j: eigenes Wurm-Modell (Grafik-Thread), Patrouillen, Stürme.

## 1. Festlegungen (Max 01.11. 14:49: „1c 2a 3 zufall 4a“)

1. **Wann kommt er?** a) nach dem Lärm beim Wurmzeichen: Summe der Vibrationsgewichte in den 3×3 Chunks um den
   Ursprung ≥ 40 (das ist Gleichgewichtswärme 2000; Revierfaktor wie bei der Schwelle: ruhig 56, wild 28). Ein Ernter
   allein (30, Mk2 24) ruft nie den großen, zwei Ernter oder Ernter + Großbohrer/Panzer schon. b) nach der Wärme beim
   Auftauchen ≥ 2000: Wer nach dem Wurmzeichen weiter lärmt, bekommt den großen. c) Zufall je Revier (wild 30 %,
   normal 10 %, ruhig nie).
2. **Wie stark?** a) wie der mittlere Demolisher: 100 000 statt 30 000 Lebenspunkte, ~1,5-fache Größe, Biss-Umkreis 6
   statt 4, Zerdrücken 4 statt 2,5 Kacheln, Tempo wie der kleine (3,5, Sprint 6). b) wie a, dazu 30 % schneller
   (4,5, Sprint 7,5): Rettungen werden knapper.
3. **Thumper.** a) zählt beim Lärm nicht mit: Ein Köder ruft den kleinen Wurm (T34 bleibt wie geplant). b) zählt mit
   (Gewicht 60): Ein Thumper-Köder ruft immer den großen Wurm.
4. **Belohnung.** a) 6–10 Zähne, Revier nach dem Tod 120 statt 60 min frei. b) 6–10 Zähne, Revier 60 min wie beim kleinen.

## 2. Regeln (nach Max' Wahl)

### 2.1 Prototyp
- Kopie von `medium-demolisher` (Skalierung 0,75; Wenderadius 9), sonst wie der kleine Sandwurm: 12 Segmente (erste
  11 + Schwanz), Sandtönung, keine Leiche/Beute der Engine, kein Blick, kein Revier, lauter. Segmente heißen
  `arrakis-sandworm-large-segment-…`. Gemeinsamer Bauweg in prototypes/sandworm.lua (Funktion je Größe).
- Grafik vorerst Vanilla medium-demolisher getönt; eigenes Modell liefert der Grafik-Thread später nach
  graphics/entity/sandworm/ (abgesprochen).

### 2.2 Auswahl und Jagd
- `worms.wormsign_tick` würfelt mit `storage.rng` nach der Stufe des Reviers der Quelle (`LARGE_CHANCE` ruhig 0,
  normal 0,1, wild 0,3; Frage 1c), auch wenn die Quelle ein Thumper ist (Frage 3 „Zufall“), und gibt
  `opts.size = "large"` an `start_hunt`. Lehrjagd und Lauer-Jagd: immer klein. Nur auf Oberflächen mit echten
  Revieren (Arrakis, Prüfstand nach `territory.test_real`), damit die übrigen Testjagden klein bleiben.
- `hunt.size = "large"`; Meldung „Großes Wurmzeichen“, Ring größer (Biss-Umkreis 6, breiter Strich).
- scripts/sandworm.lua: Werte je Größe in `lib.SIZES` (Name, Körperlinie 30 statt 20, Vorausschau 24 statt 18,
  Wenderadius 9 statt 6); Spawn, Fels-Wächter und Planung nehmen die Werte der Jagd.
- scripts/worms.lua: Biss-Umkreis und Zerdrück-Radius je Größe; Beute 6–10 (TOOTH_FACTOR gilt auch);
  getöteter großer Wurm: Revier 2 × FREE_TICKS frei (Standard 120 min).
- Alte Spielstände: Jagden ohne `size` sind klein (kein Migrationsschritt nötig).

### 2.3 Einstellung
- Neue Laufzeit-Einstellung `arrakis-large-worm` (an/aus, Standard an) in settings.lua und scripts/config.lua.

## 3. Tests

- **T37 Großer Wurm (Prüfstand):** Prototyp (Name, 100 000 LP, Segmente, Tönung); Zufalls-Auswahl (je Stufe 1000 Würfe,
  Anteil 0/0,1/0,3 ± 0,05; Einstellung aus → klein; Lehrjagd klein); Jagd mit großem
  Wurm: Wurm erscheint, Biss bei 0 frisst Ziel und ein Auto 5 Kacheln neben der Box, eins 8 Kacheln daneben bleibt;
  getöteter großer Wurm wirft 6–10 Zähne und macht das Revier 2 × FREE_TICKS frei.
- **T38 interaktiv (Spielabend):** großen Wurm mit zwei Erntern rufen, ansehen (Größe, Staub, Ton), retten oder mit
  Geschützen töten.
- T1–T36 bleiben grün (kleiner Wurm unverändert).
