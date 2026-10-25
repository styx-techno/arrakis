# Arrakis

Factorio-Mod für **Factorio 2.1 + Space Age** (ab 2.1.23): ein neuer Wüstenplanet mit Wassermangel, Sandwürmern und Spice. Factorio 2.1 lädt keine Mods für 2.0. Für **Factorio 2.0.77** gibt es den Zweig `factorio-2.0` (Mod 0.5.0): im Mod-Ordner `arrakis` einmal `git fetch` und dann `git checkout factorio-2.0` ausführen.

Stand: Phase 3b (0.5.5). Sandwüste mit Felsinseln, Erze nur auf Fels, Spice-Sand im offenen Sand, Tiefenwasser-Brunnen und Windfalle. Dazu die Spice-Kette mit Spice-Raffinerie, Melange, Spice-Essenz und Spice-Wissenschaft. Neu ist der Spice-Ernter: Er wird auf einem Spicefeld aufgebaut (`Umschalt+H` oder Knopf im Fahrzeugfenster) und fördert Spice-Sand, eine Spice-Annahme auf Fels entlädt ihn, ein Tankstutzen tankt ihn auf. Spice-Sand bauen nur noch der Ernter und die Hand ab, keine Bohrer. Dazu das Spice-Brikett als Brennstoff und die Mod-Einstellung „Wurmbiss“ (wirkt erst mit den Sandwürmern).

Neu in 0.5.4 ist die Karte von Arrakis: Der Start liegt auf einer Startinsel mit allen Erzen und einem Tiefenbrunnen, ringsum bis 220 Kacheln vom Start nur Sand, dahinter gleich große Felsinseln. Ein Lehrfeld mit etwa 100 000 Spice-Sand liegt 41–59 Kacheln vom Inselrand, alle anderen Spicefelder mindestens 100 Kacheln vom Fels. **Sicher gibt es die neue Karte nur in einem neuen Spiel.** Spielstände, in denen Arrakis schon angelegt ist, behalten die alte Karte, auch in neu erkundeten Gebieten. Ob ein älterer Spielstand, in dem Arrakis noch nicht angelegt ist, beim ersten Besuch die neue oder die alte Karte bekommt, ist noch nicht geprüft. Bekommt Arrakis die alte Karte, sagt die Mod das einmal im Chat.

Neu in 0.5.5: Die regulären Spicefelder sind häufiger und größer (geschätzt etwa 5 Felder in den 800 × 800 Kacheln um den Start statt knapp einem, im Median etwa 1150 statt 134 Kacheln). Auch das gilt nur für eine neu angelegte Arrakis-Oberfläche; eine Oberfläche aus 0.5.4 behält ihre wenigen kleinen Felder.

Der Prüfstand `/arrakis-test` ist für Testspielstände (siehe unten). Grafiken sind eingefärbte Vanilla-Platzhalter.

## Installation zum Testen

1. Repo in den Factorio-Mod-Ordner klonen, der Ordner muss `arrakis` heißen:
   - Windows: `%APPDATA%\Factorio\mods\arrakis`
   - Linux: `~/.factorio/mods/arrakis`
   - Nur für Factorio 2.0.77: danach im Ordner `arrakis` `git fetch` und `git checkout factorio-2.0`.
   - Aktualisieren: im Ordner `arrakis` `git pull`.
2. Factorio starten, Mod aktivieren, neues Spiel mit Space Age.
3. Schnelltest ohne Forschung: im Chat `/arrakis` eingeben (als Admin). Erzeugt die Oberfläche und teleportiert dich hin.
   Alle Arrakis-Forschungen auf einmal freischalten (schaltet Achievements ab):
   `/c for _, t in pairs({"planet-discovery-arrakis", "arrakis-windtrap", "arrakis-spice-processing", "spice-science-pack", "arrakis-spice-harvesting"}) do game.player.force.technologies[t].researched = true end`

## Prüfstand

Der Prüfstand baut im Spiel Testaufbauten für Ernter, Ornithopter, Sandwürmer und den Kartengenerator, misst selbst und schreibt die Ergebnisse auf. Er ist nur für Testspielstände gedacht. Ausführliche Anleitung je Test: [`docs/pruefstand.md`](docs/pruefstand.md).

1. **Einstellung einschalten:** im Hauptmenü *Einstellungen → Mod-Einstellungen → Start* das Häkchen bei **Prüfstand** setzen und bestätigen (Factorio startet neu). Ist die Einstellung aus, gibt es weder Test-Objekte noch den Befehl.
2. **Neues Spiel oder Wegwerf-Spielstand** mit Space Age nehmen, nie den echten Spielstand. Die Tests laufen auf einer eigenen Oberfläche. T11 legt nur kurz leere Testoberflächen an und erzeugt keine Karte; T14 erzeugt die Karte von Arrakis auf eigenen Testoberflächen und löscht sie danach.
3. **Befehle** im Chat (nur Admins; im Einzelspiel ist man Admin):
   - `/arrakis-test`: Liste aller Tests mit Dauer und Hinweisen
   - `/arrakis-test T1` (bzw. `T2` … `T14`, `T2b`): einen Test starten; `T11 lang` und `T14 lang` mit 30 statt 9 Seeds
   - `/arrakis-test alle`: alle nicht-interaktiven Tests nacheinander (geschätzt etwa 13 min)
   - `/arrakis-test stop`: laufenden Test abbrechen
   - `/arrakis-test zurück`: zurück an die Stelle vor dem Test
   - `/arrakis-test T7 ja`: T7 mit Teil b (kann das Spiel abstürzen lassen, nur im Wegwerf-Spielstand)
4. **Ergebnisse** stehen im Chat und in der Datei `%APPDATA%\Factorio\script-output\arrakis-test.txt` (Linux: `~/.factorio/script-output/arrakis-test.txt`). Die Datei wird fortgeschrieben, nie geleert. Bitte die Datei schicken, nach T11 auch `arrakis-t11-karten.txt` aus demselben Ordner, dazu die Antworten auf die FRAGE-Zeilen und Screenshots.
5. **Ohne Spieler:** `tools/pc/pruefstand.py` lässt die nicht-interaktiven Tests auf einem eigenen Factorio-Server über RCON laufen (dazu `/arrakis-test status`), siehe [Automatisch ohne Spieler](docs/pruefstand.md#automatisch-ohne-spieler-server-und-rcon).

## Aufbau

| Datei | Inhalt |
|---|---|
| `prototypes/planet/planet.lua` | Planet und Raumverbindung Vulcanus – Arrakis |
| `prototypes/planet/planet-map-gen.lua` | Kartengenerator (welche Kacheln und Ressourcen): der Planet nutzt ab 0.5.4 Karte 2, `arrakis_v1()` liefert die alte Karte zum Vergleich |
| `prototypes/noise.lua` | Noise-Ausdrücke: Felsinseln, Erz-, Spice- und Wasserverteilung; Karte 1 (`arrakis_*`, alte Spielstände) und Karte 2 (`arrakis_v2_*`, ab 0.5.4; reguläres Spice ab 0.5.5 `arrakis_v3_spice_*`) |
| `prototypes/collision-layers.lua` | Kollisionsebene `arrakis_rock` (liegt an der Fels-Kachel) |
| `prototypes/tiles.lua` | Arrakis-Fels |
| `prototypes/resources.lua` | Spice-Sand, Tiefenwasser |
| `prototypes/harvester.lua` | Spice-Ernter, Spice-Annahme, Tankstutzen, Spice-Brikett, Forschung Spice-Ernte, Taste `Umschalt+H`, Ressourcenkategorie `arrakis-spice-harvest` |
| `prototypes/windtrap.lua` | Windfalle |
| `prototypes/spice.lua` | Spice-Raffinerie, Melange, Spice-Essenz, Sand, Spice-Wissenschaft |
| `prototypes/compat.lua` | Versionsweiche: Prototypen in 2.0-Syntax, unter 2.1 umgeschrieben (bleibt, falls der Zweig `factorio-2.0` noch einmal aus diesem Code gebaut wird) |
| `data-updates.lua` | Spice-Wissenschaft in die Labore eintragen |
| `data-final-fixes.lua` | Spice von Hand: Kategorie `arrakis-spice-harvest` an alle Spielfiguren und God-Controller |
| `docs/design-ernter-ornithopter.md` | Design v0.3: Spice-Ernter, Ornithopter, Sandwürmer, Automatik |
| `prototypes/surface-property.lua` | Luftfeuchtigkeit (`humidity`) |
| `prototypes/technology.lua` | Entdeckungs-Technologie |
| `control.lua` | Lädt die Laufzeit-Bibliotheken (`event_handler`) |
| `scripts/arrakis-surface.lua` | Oberfläche von Arrakis anlegen, Entwicklerbefehl `/arrakis` |
| `scripts/migrate.lua` | `storage` anlegen (Schema 1), Meldung alter Bohrer auf Spice, Hinweis auf die alte Karte |
| `scripts/harvester.lua` | Spice-Ernter: Zustände, Abbau, Treibstoff, Tempo-Deckel, Abbausperre, Andocken, Taste |
| `scripts/harvester-gui.lua` | Fenster am Fahrzeugfenster des Ernters |
| `scripts/intake.lua` | Spice-Annahme und Tankstutzen: Bauen, Felsprüfung, Andock-Takt |
| `scripts/terrain.lua` | Fels, Sand und wo geerntet werden darf |
| `settings.lua` | Startup-Einstellung „Prüfstand“, Mod-Einstellung „Wurmbiss“ |
| `locale/*/messages.cfg` | Laufzeittexte (Status, Alarme, Hinweise, Fenster) |
| `prototypes/testbench/` | Test-Prototypen (nur mit Prüfstand) |
| `scripts/testbench/` | Prüfstand: `runner.lua` (Befehl, Ablauf, Protokoll) und die Tests T1–T14 und T2b (`t_ernter.lua`: echter Ernter-Code, `t_karte.lua`: T14 Karte echt) |
| `docs/pruefstand.md` | Anleitung zum Prüfstand |
| `tools/check/` | Datenstufen-Test mit echten Vanilla-Prototypen, API-Namen im Laufzeitcode, Feldnamen der Prototypen (`proto_fields.py`) |
| `tools/pc/` | Prüfstand ohne Spieler: `pruefstand.py` (eigener Factorio-Server, Tests über RCON), `rcon.py` (RCON-Client), `mod_settings.py` (`mod-settings.dat` lesen und schreiben) |

## Roadmap

Siehe Konzept: Phase 1 Gelände und Wasser, Phase 2 Spice-Kette und Spice-Wissenschaft, Phase 3 Sandwürmer, Phase 4 Stürme und Plast-Stahl, Phase 5 Endgame, Phase 6 Balancing und Release.
