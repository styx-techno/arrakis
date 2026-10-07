# Arrakis

Factorio-Mod für **Factorio 2.0 + Space Age** (ab 2.0.61): ein neuer Wüstenplanet mit Wassermangel, Sandwürmern und Spice. Der Code ist auf Factorio 2.1 vorbereitet; dafür muss nur `info.json` umgestellt werden (`"factorio_version": "2.1"`, Abhängigkeiten `>= 2.1.20`).

Stand: Phase 3a (0.4.1). Sandwüste mit Felsinseln, Erze nur auf Fels, Spice-Sand im offenen Sand, Tiefenwasser-Brunnen und Windfalle. Dazu die Spice-Kette mit Spice-Raffinerie, Melange, Spice-Essenz und Spice-Wissenschaft. Neu ist der Prüfstand `/arrakis-test` für Testspielstände (siehe unten). Grafiken sind eingefärbte Vanilla-Platzhalter.

## Installation zum Testen

1. Repo in den Factorio-Mod-Ordner klonen, der Ordner muss `arrakis` heißen:
   - Windows: `%APPDATA%\Factorio\mods\arrakis`
   - Linux: `~/.factorio/mods/arrakis`
2. Factorio starten, Mod aktivieren, neues Spiel mit Space Age.
3. Schnelltest ohne Forschung: im Chat `/arrakis` eingeben (als Admin). Erzeugt die Oberfläche und teleportiert dich hin.
   Alle Arrakis-Forschungen auf einmal freischalten (schaltet Achievements ab):
   `/c for _, t in pairs({"planet-discovery-arrakis", "arrakis-windtrap", "arrakis-spice-processing", "spice-science-pack"}) do game.player.force.technologies[t].researched = true end`

## Prüfstand

Der Prüfstand baut im Spiel Testaufbauten für Ernter, Ornithopter, Sandwürmer und den Kartengenerator, misst selbst und schreibt die Ergebnisse auf. Er ist nur für Testspielstände gedacht. Ausführliche Anleitung je Test: [`docs/pruefstand.md`](docs/pruefstand.md).

1. **Einstellung einschalten:** im Hauptmenü *Einstellungen → Mod-Einstellungen → Start* das Häkchen bei **Prüfstand** setzen und bestätigen (Factorio startet neu). Ist die Einstellung aus, gibt es weder Test-Objekte noch den Befehl.
2. **Neues Spiel oder Wegwerf-Spielstand** mit Space Age nehmen, nie den echten Spielstand. Die Tests laufen auf einer eigenen Oberfläche. T11 legt nur kurz leere Testoberflächen an und erzeugt keine Karte.
3. **Befehle** im Chat (nur Admins; im Einzelspiel ist man Admin):
   - `/arrakis-test`: Liste aller Tests mit Dauer und Hinweisen
   - `/arrakis-test T1` (bzw. `T2` … `T12`): einen Test starten
   - `/arrakis-test alle`: alle nicht-interaktiven Tests nacheinander (etwa 10 min)
   - `/arrakis-test stop`: laufenden Test abbrechen
   - `/arrakis-test zurück`: zurück an die Stelle vor dem Test
   - `/arrakis-test T7 ja`: T7 mit Teil b (kann das Spiel abstürzen lassen, nur im Wegwerf-Spielstand)
4. **Ergebnisse** stehen im Chat und in der Datei `%APPDATA%\Factorio\script-output\arrakis-test.txt` (Linux: `~/.factorio/script-output/arrakis-test.txt`). Die Datei wird fortgeschrieben, nie geleert. Bitte die Datei schicken, nach T11 auch `arrakis-t11-karten.txt` aus demselben Ordner, dazu die Antworten auf die FRAGE-Zeilen und Screenshots.

## Aufbau

| Datei | Inhalt |
|---|---|
| `prototypes/planet/planet.lua` | Planet und Raumverbindung Vulcanus – Arrakis |
| `prototypes/planet/planet-map-gen.lua` | Kartengenerator (welche Kacheln und Ressourcen) |
| `prototypes/noise.lua` | Noise-Ausdrücke: Felsinseln, Erz-, Spice- und Wasserverteilung |
| `prototypes/collision-layers.lua` | Kollisionsebene `arrakis_rock` (liegt an der Fels-Kachel) |
| `prototypes/tiles.lua` | Arrakis-Fels |
| `prototypes/resources.lua` | Spice-Sand, Tiefenwasser |
| `prototypes/windtrap.lua` | Windfalle |
| `prototypes/spice.lua` | Spice-Raffinerie, Melange, Spice-Essenz, Sand, Spice-Wissenschaft |
| `data-updates.lua` | Spice-Wissenschaft in die Labore eintragen |
| `docs/design-ernter-ornithopter.md` | Design v0.3: Spice-Ernter, Ornithopter, Sandwürmer, Automatik |
| `prototypes/surface-property.lua` | Luftfeuchtigkeit (`humidity`) |
| `prototypes/technology.lua` | Entdeckungs-Technologie |
| `control.lua` | Lädt die Laufzeit-Bibliotheken (`event_handler`) |
| `scripts/arrakis-surface.lua` | Oberfläche von Arrakis anlegen, Entwicklerbefehl `/arrakis` |
| `settings.lua` | Startup-Einstellung „Prüfstand“ |
| `prototypes/testbench/` | Test-Prototypen (nur mit Prüfstand) |
| `scripts/testbench/` | Prüfstand: `runner.lua` (Befehl, Ablauf, Protokoll) und die Tests T1–T12 |
| `docs/pruefstand.md` | Anleitung zum Prüfstand |
| `tools/check/` | Datenstufen-Test mit echten Vanilla-Prototypen |

## Roadmap

Siehe Konzept: Phase 1 Gelände und Wasser, Phase 2 Spice-Kette und Spice-Wissenschaft, Phase 3 Sandwürmer, Phase 4 Stürme und Plast-Stahl, Phase 5 Endgame, Phase 6 Balancing und Release.
