# Plan 3h: Thumper, Beute und Einstellungen (Ziel 0.14.0)

Stand: 01.11.2026. Letzte Phase aus Max' Reihenfolge „alle 3“ (3f Flottenleitung → 3g Wurm-Reviere → 3h). Grundlage: Design v0.3 (/mnt/project-files/konzept/arrakis-design-v0.3-ernter.md, Abschnitte 2.2, 3, 3.1, 4.3 „Thumper“, 6, Roadmap 3d3) und docs/plan-3g.md. Abschnitt 1 sind die offenen Festlegungen; ohne Antwort gilt jeweils a.

## 0. Ziel

Der Spieler bekommt ein Werkzeug gegen den Wurm, das nichts verspricht, was es nicht hält: Der **Thumper** lenkt eine laufende Jagd auf sich um (Zeit gewinnen) oder lockt einen Wurm gezielt vor die Geschütze. Wer einen Wurm tötet, bekommt **Wurmzähne**. Die wichtigsten Zeiten und Schwellen werden **Mod-Einstellungen**, damit jeder die Wüste so hart macht, wie er will.

Nicht in 3h: großer Wurm (falls 5a), Ernter Mk2 (falls 3a), Patrouillen, Radar-Modus, Stürme (Phase 4).

## 1. Offene Festlegungen (Format „1a 2b …“, ohne Antwort a)

1. **Freischaltung.** a) Trigger-Forschung „Thumper“: kommt nach der ersten überstandenen Jagd (Design). b) normale Forschung mit Spice-Paketen.
2. **Wirkung.** a) 60 s Laufzeit, Vibration 60, Ablenkung im Umkreis 160 Kacheln (Design). b) 90 s, Umkreis 250.
3. **Beute.** a) kleiner Wurm 2–4 Wurmzähne; verwendet werden sie mit dem Ernter Mk2 in einer späteren Phase. b) Ernter Mk2 gleich mit (Ernter + 4 Wurmzähne + 10 Spice-Essenz; +50 % Abbau, −20 % Vibration).
4. **Einstellungen.** a) Einzelwerte (Liste in 2.3), jederzeit im Spiel änderbar. b) nur „Würmer an/aus“ und eine Schwierigkeit leicht/normal/schwer. c) beides.
5. **Großer Wurm.** a) später, eigene Phase. b) jetzt mit (ab Wärme 2000, 6–10 Zähne).

## 2. Regeln (nach Wahl a)

### 2.1 Thumper (`arrakis-thumper`)
- Rezept 5 Eisenplatte, 5 Zahnrad, 2 Kohle, Verbrauchsgut (Stapel 20). Nur auf Sand baubar (Bauregel `arrakis_rock`), wirkt nur auf Arrakis.
- Läuft 60 s mit Vibration 60 (ungedämpft, unabhängig von der Vibrations-Einstellung), dann zerfällt er mit Sandstaub.
- **Ablenkung:** Beim Bauen sucht er die nächste laufende Jagd seiner Force im Zustand Warnung innerhalb 160 Kacheln (Abstand zum Ziel). Deren Ziel wechselt auf den Thumper: Alarm am alten Ziel weg, Markierung am Thumper, Chat „Thumper lenkt den Wurm ab“. Der Countdown bleibt. Ein Wurm, der schon fährt, verwirft seine Route und fährt zum Thumper (Umweg/Neuplanung wie bisher); in der Planung beginnt die Planung neu.
- **Köder:** Ohne Jagd in Reichweite heizt er seinen Chunk; nach etwa 20 s kommt sein Wurmzeichen wie bei jeder Quelle (Revier-Schwelle, Schonfrist, freies Revier und Ruhe gelten). Köder-Jagden zählen nicht zu den höchstens 3 Jagden und sperren ihr Revier nicht.
- **Ende:** Jagden auf einen Thumper (umgelenkt oder Köder) setzen weder Wärme noch Ruhe zurück und lassen keinen Wurm lauern. Der Ernter, der weiter erntet, bekommt also bald ein neues Wurmzeichen. Statistik: eigener Zähler „thumper“, getötete Würmer zählen wie bisher als killed.
- Biss auf den Thumper: wie bei jedem Gebäude (Radius 4 um die Box), also Geschütze weiter weg bauen.

### 2.2 Beute
- Stirbt ein eigener Wurm (auch nach Jagdende beim Abtauchen), fallen 2–4 Wurmzähne (`arrakis-worm-tooth`, Stapel 50) am Kopf auf den Boden (gespeicherter Zufall, `spill_item_stack`, zum Aufheben markiert für Roboter). Faktor über Einstellung.

### 2.3 Einstellungen (runtime-global, Standard = bisheriges Verhalten)
| Name | Standard | Bereich |
|---|---|---|
| Würmer aktiv | an | an/aus (aus: keine neuen Wurmzeichen, Vibration bleibt) |
| Vorwarnzeit (s) | 60 | 30–180 (Frühwarnung und Reviere kommen dazu) |
| Wurmzeichen-Schwelle | 1000 | 300–5000 (Unruhe = 60 %) |
| Vibration (%) | 100 | 25–400 (alle Quellen außer Thumper) |
| Ruhezeit nach Jagd (%) | 100 | 25–400 (Grundwert 2–4 min) |
| Höchstens Jagden zugleich | 3 | 1–10 |
| Revier frei nach Tötung (min) | 60 | 0–240 |
| Thumper-Laufzeit (s) | 60 | 20–300 |
| Wurmzähne je Wurm (%) | 100 | 0–500 |

Wurmbiss (Totalverlust/schwer beschädigt) und Leitstellen-Reichweite gibt es schon. Umsetzung: scripts/config.lua schreibt die Werte in die Modul-Konstanten (on_init, on_load, on_configuration_changed, on_runtime_mod_setting_changed); deterministisch, weil Einstellungen für alle gleich sind.

## 3. Technik
- Neu: prototypes/thumper.lua (Item, Rezept, `simple-entity-with-owner` mit verkleinerter Pumpjack-Animation aus data.raw, keine festen Pfade), prototypes/worm-tooth.lua, Forschung `arrakis-thumper` (Trigger `scripted`, Voraussetzung Spice-Ernte; Auslöser bei `first_escape_tick`, Migration für alte Spielstände), scripts/thumper.lua, scripts/config.lua.
- Geändert: vibration.lua (Thumper-Zufluss, Faktor), worms.lua (Köder-Quelle, Umlenkung, Ende ohne Rücksetzen, Beute, Einstellungen), sandworm.lua (`retarget`), territory.lua (Freizeit aus Einstellung), migrate.lua (storage.thumpers), Texte de/en.

## 4. Tests (Prüfstand, je Datei)
- **T32 Thumper:** Bauregel (Fels nein, Sand ja); Köder: Wärme → Wurmzeichen nach ~20 s, zählt nicht zu MAX_HUNTS; Umlenkung einer Ernter-Jagd innerhalb 160 (Ziel, Alarm, Markierung), nicht bei 200; Zerfall nach Laufzeit; Ende ohne Ruhe/Rücksetzen; Forschung nach erster überstandener Jagd.
- **T33 Beute und Einstellungen:** Wurm töten → 2–4 Zähne am Boden; Einstellungen wirken (Schwelle, Vorwarnzeit, Würmer aus, Zahn-Faktor 0) und Standardwerte = bisherige Konstanten.
- Interaktiv für den Spielabend (T34): Thumper im Spiel bauen, Animation sehen, Wurm vor Geschütze locken, Zähne aufheben.
