# Arrakis

Factorio-Mod für **Factorio 2.1 + Space Age** (ab 2.1.23): ein neuer Wüstenplanet mit Wassermangel, Sandwürmern und Spice. Factorio 2.1 lädt keine Mods für 2.0. Für **Factorio 2.0.77** gibt es den Zweig `factorio-2.0` (Mod 0.5.0): im Mod-Ordner `arrakis` einmal `git fetch` und dann `git checkout factorio-2.0` ausführen.

Stand: Phase 3d2 (0.8.6). Sandwüste mit Felsinseln, Erze nur auf Fels, Spice-Sand im offenen Sand, Tiefenwasser-Brunnen und Windfalle. Dazu die Spice-Kette mit Spice-Raffinerie, Melange, Spice-Essenz und Spice-Wissenschaft. Seit 0.5.0 gibt es den Spice-Ernter: Er wird auf einem Spicefeld aufgebaut (`Umschalt+H` oder Knopf im Fahrzeugfenster) und fördert Spice-Sand, eine Spice-Annahme auf Fels entlädt ihn, ein Tankstutzen tankt ihn auf. Spice-Sand bauen nur noch der Ernter und die Hand ab, keine Bohrer. Dazu das Spice-Brikett als Brennstoff und die Mod-Einstellung „Wurmbiss“ (wirkt seit 0.7.0).

Neu in 0.5.4 ist die Karte von Arrakis: Der Start liegt auf einer Startinsel mit allen Erzen und einem Tiefenbrunnen, ringsum bis 220 Kacheln vom Start nur Sand, dahinter gleich große Felsinseln. Ein Lehrfeld mit etwa 100 000 Spice-Sand liegt 41–59 Kacheln vom Inselrand, alle anderen Spicefelder mindestens 100 Kacheln vom Fels. **Sicher gibt es die neue Karte nur in einem neuen Spiel.** Spielstände, in denen Arrakis schon angelegt ist, behalten die alte Karte, auch in neu erkundeten Gebieten. Ob ein älterer Spielstand, in dem Arrakis noch nicht angelegt ist, beim ersten Besuch die neue oder die alte Karte bekommt, ist noch nicht geprüft. Bekommt Arrakis die alte Karte, sagt die Mod das einmal im Chat.

Neu in 0.5.5: Die regulären Spicefelder sind häufiger und größer (geschätzt etwa 5 Felder in den 800 × 800 Kacheln um den Start statt knapp einem, im Median etwa 1150 statt 134 Kacheln). Auch das gilt nur für eine neu angelegte Arrakis-Oberfläche; eine Oberfläche aus 0.5.4 behält ihre wenigen kleinen Felder.

Neu in 0.6.0 ist der **Ornithopter**: ein bemannter Flieger, der einen Spice-Ernter anhebt, trägt und absetzt (leer 8, beladen 5,6 Kacheln/s; der Ernter selbst fährt höchstens 1,5). Die Forschung „Ornithopter“ erforscht sich von selbst, sobald der erste Spice-Ernter hergestellt ist. Über den eigenen Ernter fliegen und `Umschalt+C` drücken, die Verknüpfung „Ernter anheben oder absetzen“ in der Leiste klicken oder im Ornithopter-Fenster „Ernter anheben“ wählen: Nach 2 s Ankoppeln hängt der Ernter dran, auch ein aufgebauter oder angedockter, mit Laderaum, Treibstoff, Gesundheit, Qualität und Farbe. Wer im Ernter sitzt, fliegt mit. Dieselben Wege setzen ihn wieder ab; über einer Spice-Annahme dockt er an. Aus der Karte holt man den Ornithopter mit der Verknüpfung „Fernbedienung für Ornithopter“ oder fährt ihn fern. Stürzt ein beladener Ornithopter ab, fällt der Ernter mit 30 % Schaden herunter. Seit 0.7.0 rettet er den Ernter vor dem Wurmbiss: anheben und bis 0 in der Luft halten.

Neu in 0.6.1: Der Ornithopter fliegt mit jedem Brennstoff gleich schnell, leer 8,0 und beladen 5,6 Kacheln/s (in 0.6.0 mit Kohle nur 6,9 und 4,8, mit Raketentreibstoff schneller). Wechselt der Brennstoff, passt die Mod das Tempo binnen 1 s an. Die Forschung „Ornithopter“ erforscht seit 0.6.1 auch die Mod selbst, sobald die Force einen Spice-Ernter hergestellt hat; dann steht eine Zeile im Chat.

Neu in 0.7.0 sind **Vibration, Wurmzeichen und Biss** (Phase 3d1, noch ohne sichtbaren Wurm): Maschinen auf Sand vibrieren, am stärksten ein aufgebauter Spice-Ernter, und heizen ihre Gegend auf. Ein Ernter allein bringt den Sand nach etwa 25 s zum Beben (Staub, Rumpeln, Status „Der Sand bebt“) und löst nach etwa 55 s ein **Wurmzeichen** aus: Alarm, Kartenmarkierung, Warnton, ein roter Ring mit Sekunden und ein Fenster oben links. Nach 60 s (bei der ersten Jagd auf einen Ernter 90 s) bricht genau bei 0 eine Sandfontäne hervor, und alles auf Sand im Umkreis von 4 Kacheln stirbt, auch wer in einem Fahrzeug sitzt; nur mit der Einstellung „Wurmbiss: Schwer beschädigt“ überlebt ein Ernter mit 10 % Gesundheit, seine Insassen bleiben sitzen, die Ladung ist weg. Sicher ist, was bei 0 getragen wird, ganz auf Fels steht oder dem Wurm (3,5 Kacheln/s) davongefahren ist; dann wird der Ring grün. Danach ruht die Gegend 2 bis 4 min. Am Anfang lässt die Wüste Zeit: 10 min nach „Ornithopter“, spätestens 30 min nach der ersten Landung auf Arrakis (Anzeige oben links). Neu sind auch der **Vorsichtsmodus** im Ernterfenster (packt bei Unruhe selbst ein, gut ein Viertel der Ausbeute), die Verknüpfung **Vibrationsanzeige** (Wärme der Chunks ringsum), zwei Tipps samt Chatzeilen und der Admin-Befehl `/arrakis-worm [Sekunden|lehr]` zum Ausprobieren. In einem Spielstand aus 0.6.x beginnt die Schonfrist beim Laden.

Neu in 0.8.0 ist der **Sandwurm** selbst (Phase 3d2): Gut 11 s nach dem Wurmzeichen (bei der ersten Jagd auf einen Ernter gut 41 s) taucht etwa 160 Kacheln entfernt ein sandfarbener Wurm mit Staub und Rumpeln auf. Er fährt nur über Sand, biegt vor Fels ab und findet auch einen Weg durch Felsgänge, wartet vor dem Ziel und beißt bei 0, höchstens 3 s später; danach taucht er ab. Wer gerettet ist, bestimmen dieselben Regeln wie in 0.7.0: getragen, ganz auf Fels oder außer Reichweite. Ist das Ziel weg, beißt er an der letzten Stelle ins Leere. Auf dem Weg zerdrückt sein Kopf, was auf Sand vor ihm liegt: Bänder, Schienen, Gebäude, Fahrzeuge (einen Spice-Ernter je nach Einstellung „Wurmbiss“) samt Insassen und Figuren, ohne eigenen Alarm; Ornithopter in der Luft, Hochschienen samt Rampen, Stützen und Zügen darauf und alles auf Fels bleiben heil. Fährt ein Ernter davon, holt der Wurm ihn mit bis zu 6 Kacheln/s ein. Ein Wurm hat 30 000 Lebenspunkte; wer ihn vor 0 tötet, rettet sein Ziel (Beute kommt später). `/arrakis-worm` bringt ab 27 s Countdown einen Wurm mit (höchstens 3 zugleich), darunter beißt es wie in 0.7.0. Jagden, die beim Update auf 0.8.0 laufen, beißen noch ohne Wurm; die nächste hat einen.

**Vor dem Entfernen der Mod** als Admin `/arrakis-uninstall` und dann `/arrakis-uninstall ja` eingeben: Das setzt alle getragenen Ernter ab, löscht die versteckte Ablage-Oberfläche `arrakis-hold`, beendet laufende Jagden ohne Biss, lässt alle Sandwürmer abtauchen und räumt Markierungen, Fenster und Anzeigen. **Zurück auf 0.7.0** erst danach, sonst löscht Factorio die Würmer, und laufende Jagden beißen ohne Wurm. **Zurück auf 0.6.x** ebenso, sonst bleiben Markierungen laufender Jagden und die Sandwurm-Force im Spielstand. **Zurück auf 0.5.x** mit einem getragenen Ernter geht nicht; vorher jeden Ernter absetzen.

Der Prüfstand `/arrakis-test` ist für Testspielstände (siehe unten). Der Spice-Ernter hat ab 0.8.5 eigene Grafik (aus Blender-Skripten, siehe `tools/grafik/`), die übrigen Grafiken sind eingefärbte Vanilla-Platzhalter.

## Installation zum Testen

1. Repo in den Factorio-Mod-Ordner klonen, der Ordner muss `arrakis` heißen:
   - Windows: `%APPDATA%\Factorio\mods\arrakis`
   - Linux: `~/.factorio/mods/arrakis`
   - Nur für Factorio 2.0.77: danach im Ordner `arrakis` `git fetch` und `git checkout factorio-2.0`.
   - Aktualisieren: im Ordner `arrakis` `git pull`.
2. Factorio starten, Mod aktivieren, neues Spiel mit Space Age.
3. Schnelltest ohne Forschung: im Chat `/arrakis` eingeben (als Admin). Erzeugt die Oberfläche und teleportiert dich hin.
   Alle Arrakis-Forschungen auf einmal freischalten (schaltet Achievements ab):
   `/c for _, t in pairs({"planet-discovery-arrakis", "arrakis-windtrap", "arrakis-spice-processing", "spice-science-pack", "arrakis-spice-harvesting", "arrakis-ornithopter"}) do game.player.force.technologies[t].researched = true end`

## Prüfstand

Der Prüfstand baut im Spiel Testaufbauten für Ernter, Ornithopter, Sandwürmer und den Kartengenerator, misst selbst und schreibt die Ergebnisse auf. Er ist nur für Testspielstände gedacht. Ausführliche Anleitung je Test: [`docs/pruefstand.md`](docs/pruefstand.md).

1. **Einstellung einschalten:** im Hauptmenü *Einstellungen → Mod-Einstellungen → Start* das Häkchen bei **Prüfstand** setzen und bestätigen (Factorio startet neu). Ist die Einstellung aus, gibt es weder Test-Objekte noch den Befehl.
2. **Neues Spiel oder Wegwerf-Spielstand** mit Space Age nehmen, nie den echten Spielstand. Die Tests laufen auf einer eigenen Oberfläche. T11 legt nur kurz leere Testoberflächen an und erzeugt keine Karte; T14 erzeugt die Karte von Arrakis auf eigenen Testoberflächen und löscht sie danach. T15 und T16 heben echte Ernter auf die echte Ablage `arrakis-hold`; T15 setzt am Ende alle getragenen Ernter ab (auch solche des Spielstands) und löscht die Ablage. T19 beendet am Ende wie `/arrakis-uninstall ja` jede laufende Jagd des Spielstands ohne Biss, T21 ebenso und entfernt dazu jeden Sandwurm.
3. **Befehle** im Chat (nur Admins; im Einzelspiel ist man Admin):
   - `/arrakis-test`: Liste aller Tests mit Dauer und Hinweisen
   - `/arrakis-test T1` (bzw. `T2` … `T22`, `T2b`): einen Test starten; `T11 lang` und `T14 lang` mit 30 statt 9 Seeds. T9, T12, T17, T20 und T22 sind interaktiv und brauchen dich im Spiel
   - `/arrakis-test alle`: alle nicht-interaktiven Tests nacheinander (ohne Zeitraffer gut 27 min)
   - `/arrakis-test stop`: laufenden Test abbrechen
   - `/arrakis-test zurück`: zurück an die Stelle vor dem Test
   - `/arrakis-test tempo 10`: Zeitraffer (`game.speed`, 1 bis 50), die Ergebnisse bleiben gleich; `/arrakis-test tempo 1` stellt zurück, im eigenen Spielstand bitte vor dem Ausschalten der Einstellung ([Zeitraffer](docs/pruefstand.md#zeitraffer-arrakis-test-tempo))
   - `/arrakis-test T7 ja`: T7 mit Teil b (kann das Spiel abstürzen lassen, nur im Wegwerf-Spielstand)
4. **Ergebnisse** stehen im Chat und in der Datei `%APPDATA%\Factorio\script-output\arrakis-test.txt` (Linux: `~/.factorio/script-output/arrakis-test.txt`). Die Datei wird fortgeschrieben, nie geleert. Bitte die Datei schicken, nach T11 auch `arrakis-t11-karten.txt` aus demselben Ordner, dazu die Antworten auf die FRAGE-Zeilen und Screenshots.
5. **Ohne Spieler:** `tools/pc/pruefstand.py` lässt die nicht-interaktiven Tests auf einem eigenen Factorio-Server über RCON laufen (dazu `/arrakis-test status`), standardmäßig mit Zeitraffer 10 (`--tempo`), siehe [Automatisch ohne Spieler](docs/pruefstand.md#automatisch-ohne-spieler-server-und-rcon).

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
| `prototypes/ornithopter.lua` | Ornithopter mit unsichtbarem Bein, Item, Rezept und Forschung, Tempo-Sticker (ab 0.6.1 je Zustand 106, eine je Brennstoff-Stufe), Lastbild (16 Richtungen samt Schatten), Absetz-Probe, Taste `Umschalt+C`, Verknüpfungen „Ernter anheben oder absetzen“ und „Fernbedienung für Ornithopter“ |
| `prototypes/ornithopter-speed.lua` | Tempo des Ornithopters je Brennstoff (ab 0.6.1): Basiswerte, Stufen, Stickernamen; reines Lua für Datenstufe, Laufzeit und Prüfstand |
| `prototypes/worms.lua` | Ab 0.7.0: Wurm-Eruption, Sandstaub, Signal „Wurmzeichen“, Geräusche Wurmzeichen und Rumpeln, Verknüpfung „Vibrationsanzeige“, Tipps „Arrakis“ und „Wurmzeichen“ |
| `prototypes/sandworm.lua` | Ab 0.8.0: Sandwurm `arrakis-sandworm-small` (Kopie des kleinen Demolishers mit 12 Segmenten, sandfarben, ohne Asche, Kontaktschaden und Beute), vier Bohrstaub-Kopien, Effekt `arrakis-worm-dive` fürs Auf- und Abtauchen |
| `prototypes/windtrap.lua` | Windfalle |
| `prototypes/spice.lua` | Spice-Raffinerie, Melange, Spice-Essenz, Sand, Spice-Wissenschaft |
| `prototypes/compat.lua` | Versionsweiche: Prototypen in 2.0-Syntax, unter 2.1 umgeschrieben (bleibt, falls der Zweig `factorio-2.0` noch einmal aus diesem Code gebaut wird) |
| `data-updates.lua` | Spice-Wissenschaft in die Labore eintragen |
| `data-final-fixes.lua` | Spice von Hand: Kategorie `arrakis-spice-harvest` an alle Spielfiguren und God-Controller |
| `docs/design-ernter-ornithopter.md` | Design v0.3: Spice-Ernter, Ornithopter, Sandwürmer, Automatik |
| `docs/plan-3b.md`, `docs/plan-3c.md`, `docs/plan-3d1.md`, `docs/plan-3d2.md` | Baupläne der Phasen 3b (Ernter, 0.5.0), 3c (Ornithopter, 0.6.0), 3d1 (Vibration und Biss, 0.7.0) und 3d2 (Sandwurm, 0.8.0); wo sie vom Design abweichen, gilt der Plan |
| `prototypes/surface-property.lua` | Luftfeuchtigkeit (`humidity`) |
| `prototypes/technology.lua` | Entdeckungs-Technologie |
| `control.lua` | Lädt die Laufzeit-Bibliotheken (`event_handler`) |
| `scripts/arrakis-surface.lua` | Oberfläche von Arrakis anlegen, Entwicklerbefehl `/arrakis` |
| `scripts/migrate.lua` | `storage` anlegen (Schema 3 ab 0.7.0, Schema 4 ab 0.8.0), Meldung alter Bohrer auf Spice, Hinweis auf die alte Karte, Forschung „Ornithopter“ für Spielstände aus 0.5.x nachholen und ab 0.6.1 jede Sekunde sowie beim Herstellen von Hand per Skript erforschen |
| `scripts/harvester.lua` | Spice-Ernter: Zustände (ab 0.6.0 auch „getragen“), Abbau, Treibstoff, Tempo-Deckel, Abbausperre, Andocken, Taste; ab 0.7.0 Status mit Wurmzeichen, Vorsicht und Unruhe |
| `scripts/harvester-gui.lua` | Fenster am Fahrzeugfenster des Ernters (ab 0.7.0 mit Vibration, Wurmzeichen und Vorsichtsmodus) |
| `scripts/intake.lua` | Spice-Annahme und Tankstutzen: Bauen, Felsprüfung, Andock-Takt |
| `scripts/hold.lua` | Ablage-Oberfläche `arrakis-hold`: versteckte Stellplätze für getragene Ernter (256) |
| `scripts/flyer.lua` | Ornithopter: Taste und Verknüpfung, Ankoppeln, Anheben, Sitze, Absetzen, Tempo-Sticker, Lastbild, Absturz, Landesuche mit Warteliste, `/arrakis-uninstall` |
| `scripts/flyer-gui.lua` | Fenster am Fahrzeugfenster des Ornithopters (Anheben/Absetzen, Fernbedienung, In den Ernter steigen) |
| `scripts/vibration.lua` | Ab 0.7.0: Vibrationsquellen und Gewichte, Wärme je Chunk, Sektoren und Ruhe, Unruhe (Staub, Rumpeln), Vorsichtsmodus, Vibrationsanzeige |
| `scripts/worms.lua` | Ab 0.7.0: Takte der Würmer, Schonfrist je Force, Wurmzeichen, Jagd und Biss, Warnungen, Sandwurm-Force, Briefing-Chat, `/arrakis-worm`, Migration auf Schema 3, Entfernen; ab 0.8.0 Phasen der Jagd mit Wurm, Biss-Fenster und Ersatzbiss, Zerdrücken, Wurm getötet oder verloren, Protokoll, Migration auf Schema 4 |
| `scripts/sandworm.lua` | Ab 0.8.0: der Sandwurm als Fahrzeug: Spawnplanung, Wege per `request_path`, Erzeugen mit Körperprüfung, Steuern, Fels-Wächter mit Umwegen, Tempo, Halten und Sprint, Auf- und Abtauchen, Waisen |
| `scripts/worms-gui.lua` | Ab 0.7.0: Fenster oben links mit Schonfrist und Jagden |
| `scripts/terrain.lua` | Fels, Sand und wo geerntet werden darf |
| `settings.lua` | Startup-Einstellung „Prüfstand“, Mod-Einstellung „Wurmbiss“ |
| `locale/*/messages.cfg` | Laufzeittexte (Status, Alarme, Hinweise, Fenster) |
| `prototypes/testbench/` | Test-Prototypen (nur mit Prüfstand) |
| `scripts/testbench/` | Prüfstand: `runner.lua` (Befehl, Ablauf, Protokoll) und die Tests T1–T22 und T2b (`t_ernter.lua`: echter Ernter-Code, `t_karte.lua`: T14 Karte echt, `t_ornithopter.lua`: T15–T17 Ornithopter, `t_jagd.lua`: T18–T20 Wärme, Jagd und Bedienung der Würmer, `t_sandwurm.lua`: T21 und T22 echter Sandwurm, Optik und Laden) |
| `docs/pruefstand.md` | Anleitung zum Prüfstand |
| `tools/check/` | Datenstufen-Test mit echten Vanilla-Prototypen, API-Namen im Laufzeitcode, Feldnamen der Prototypen (`proto_fields.py`) |
| `tools/pc/` | Prüfstand ohne Spieler: `pruefstand.py` (eigener Factorio-Server, Tests über RCON), `rcon.py` (RCON-Client), `mod_settings.py` (`mod-settings.dat` lesen und schreiben) |

## Roadmap

Siehe Konzept: Phase 1 Gelände und Wasser, Phase 2 Spice-Kette und Spice-Wissenschaft, Phase 3 Sandwürmer, Phase 4 Stürme und Plast-Stahl, Phase 5 Endgame, Phase 6 Balancing und Release.

Phase 3 im Einzelnen steht in [`docs/design-ernter-ornithopter.md`](docs/design-ernter-ornithopter.md), Abschnitt 7: gebaut sind der Spice-Ernter (3b, 0.5.x), der Ornithopter (3c, 0.6.x), Vibration, Wurmzeichen und Biss (3d1, 0.7.0) und der Sandwurm selbst (3d2, 0.8.0); als Nächstes kommen Thumper, Beute, großer Wurm und Balancing (3d3, 0.9.0), dann die Automatik mit Leitstelle und Carryalls (3e, 3f).
