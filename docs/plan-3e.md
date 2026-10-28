# Bauplan Phase 3e: Leitstelle und Carryalls (0.10.0)

Stand: gebaut in 0.10.0 (28.10.2026); Abweichungen vom Entwurf stehen jeweils als „Umgesetzt:“ dabei. Grundlage ist das Design (docs/design-ernter-ornithopter.md), Abschnitte 2.2 (Stufe 2), 3, 4.4 und 6. Abschnitt 1 hier sammelt die Festlegungen, bei denen Max widersprechen kann; ohne Widerspruch gilt die Standardwahl.

Ziel aus dem Fahrplan (Design 7, Zeile 3e): **3 Ernter, eine Leitstelle, 2 Carryalls, Treibstoff in der Leitstelle: 60 min ohne Eingriff, kein Ernter verloren, kein Ernter ohne Treibstoff.**

## 0. Umfang

In 0.10.0:
- Forschung „Ornithopter-Leitstelle“ (erste Forschung mit Spice-Paketen).
- Leitstelle auf Fels: Inventar für Treibstoff, Reichweitenanzeige beim Bauen, Fenster mit Stand der Flotte.
- Carryall: unbemannter Flieger der Leitstelle, eigene Grafik (Ableitung des Ornithopter-Modells).
- Aufträge RETTUNG, TANKEN, ENTLADEN, RÜCKKEHR mit Verteilung, Notregel und ehrlicher Absage „Rettung nicht möglich“.
- Handbetrieb: Ein Carryall, in dem jemand sitzt oder den jemand per Fernbedienung schickt, gehört bis zum nächsten Parken nicht der Automatik.
- Prüfstand T23 (automatisch, alle Aufträge einzeln) und T24 (Dauerlauf 60 min Spielzeit, im Zeitraffer etwa 6 min), T25 interaktiv.

Nicht in 0.10.0 (kommt mit 3f „Flottenleitung“): EINSATZ, UMSETZEN, RÜCKRUF, Feldsuche, Schaltung (Signale H/R, Statussignale), Bereitschaftsflug, Frühwarnung, Ernte-Dämpfung, Ersatz-Ernter im Inventar. Thumper, Wurmzahn und großer Wurm bleiben in 3d3.

## 1. Festlegungen (Standardwahl, Max kann widersprechen)

1. **Carryall-Treibstoff wie beim Ornithopter:** nur Flugtreibstoff (Kategorie `arrakis-flight-fuel` aus 0.9.0), besserer Treibstoff fliegt schneller. Den Ernter betankt er mit gewöhnlichem Brennstoff aus seinem Kofferraum (Kohle, Festbrennstoff, Spice-Brikett; nur wenn davon nichts da ist, Flugtreibstoff).
2. **Tempo:** Carryall leer 9, beladen 6,3 Kacheln/s mit Raketentreibstoff (1,125 × Ornithopter), mit besserem Treibstoff im selben Verhältnis schneller wie der Ornithopter.
3. **Reichweite fest 300 Kacheln** um die Leitstelle (Mod-Einstellung 150–600). Sie gilt für die Betreuung und die Anzeige; ob eine Rettung rechtzeitig ankommt, rechnet die Verteilung mit dem wirklichen Tempo des Carryalls (Abschnitt 4.5).
4. **Rettung = Anheben und Schweben:** Der Carryall hebt den Ernter an und schwebt an Ort und Stelle, bis die Jagd vorbei ist. Danach setzt er ihn an der alten Stelle wieder ab und baut ihn auf. Ist der Laderaum ≥ 90 % voll, fliegt er stattdessen gleich zum Entladen.
5. **Zuordnung:** Carryalls gehören zur nächsten Leitstelle der eigenen Force, an der sie zuletzt geparkt haben; ein neu gebauter Carryall gehört zur nächsten Leitstelle im Umkreis von 20 Kacheln. Ernter werden von jeder Leitstelle betreut, in deren Reichweite sie stehen (bei mehreren die nächste).
6. **Betreut wird nur, wer arbeitet:** Ernter im Zustand aufgebaut, aufbauend oder einpackend auf Sand. Fahrende Ernter, angedockte und solche mit Spieler am Steuer betreut die Automatik nicht (sie rettet sie aber bei einem Wurmzeichen, wenn kein Spieler drinsitzt).
7. **Kosten** wie im Design 3.1: Leitstelle 50 Stahl, 200 Ziegel, 20 Fortgeschrittener Schaltkreis, 10 Spice-Essenz; Carryall wie Ornithopter + 10 Stahl. Forschung: 300 × Automatisierung, Logistik, Chemie, Weltraum, Spice.
8. **Grafik:** Carryall = Ornithopter-Modell, 1,25-mal so groß, dunkles Metall statt Sandgrau, Kanzel durch geschlossene Nase ersetzt, breitere Klauen. Leitstelle = flacher Bau 4×4 mit Landeplatz, Mast und Lampe (Blender wie die Fahrzeuge). Animationen wie vereinbart später.
9. **Insassen:** Ein Carryall hat einen Sitz (Handbetrieb), die Automatik startet nie mit Insasse. Ein geretteter Ernter mit Spieler am Steuer wird nicht automatisch angehoben (der Spieler entscheidet selbst).

## 2. Dateien

| Datei | Inhalt |
|---|---|
| `prototypes/carryall.lua` (neu) | Carryall-Fahrzeug, Item, Rezept; Tempo-Sticker über `prototypes/ornithopter-speed.lua` mit eigenem Grundwert |
| `prototypes/depot.lua` (neu) | Leitstelle (`container` 4×4, nur auf Fels), Item, Rezept, Reichweitenanzeige |
| `prototypes/technology.lua` | Forschung „Ornithopter-Leitstelle“ |
| `scripts/fleet.lua` (neu) | Leitstellen-Datensätze, Zuordnung, Parken und Nachfüllen, Aufträge, Verteilung (30-Tick-Takt), Flug, Ablauf je Auftrag, Notregel, Absage (Umgesetzt: eine Datei statt `depot.lua` und `fleet.lua`) |
| `scripts/fleet-gui.lua` (neu) | Fenster der Leitstelle (relativ zum Lagerfenster); `scripts/flyer-gui.lua` zeigt am Carryall Automatik oder Handbetrieb |
| `scripts/flyer.lua` | Carryall als zweite Art (`kind = "carryall"`); Kopplung, Anheben, Absetzen, Absturz unverändert mitbenutzt |
| `scripts/worms.lua` | Carryall ist kein Wurmziel (Umgesetzt: kein Haken; `fleet` liest `storage.hunts` im 30-Tick-Takt) |
| `scripts/migrate.lua` | Schema 5: `storage.depots`, `storage.jobs`, Carryall-Felder |
| `scripts/testbench/t_fleet.lua` (neu) | T23, T24, T25 |
| `graphics/entity/carryall/`, `graphics/entity/depot/`, Icons | Spritesheets aus `tools/grafik/carryall-modell.py`, `leitstelle-modell.py` |
| Locale de/en, changelog, info.json, README, docs/pruefstand.md | Texte |

## 3. Prototypen (2.0-Schreibweise; `compat.finish` setzt 2.1 um)

- `arrakis-carryall`: Kopie von `arrakis-ornithopter`, Brenner nur Flugtreibstoff, 2 Brennstoff-Slots, Kofferraum 20 Slots (Ernter-Treibstoff), kein Fahrzeugwaffen-Slot, `guns` leer. Eigene Grafikebenen wie beim Ornithopter (Basis, Maske, Schatten), `corpse = "big-remnants"`.
- `arrakis-depot`: `container` 4×4, `inventory_size` 48, `tile_buildability_rules` nur Fels (wie die Annahme), `radius_visualisation_specification` mit 300 Kacheln (Mod-Einstellung: Prototyp liest den Startup-Wert).
- Forschung „Ornithopter-Leitstelle“: Voraussetzungen Spice-Wissenschaft und Ornithopter, schaltet Leitstelle und Carryall frei.
- checks.lua: Ebenen, Symbole, Brennerkategorie, Baubarkeit nur auf Fels, Forschung und Rezepte.

## 4. Laufzeit

### 4.1 Datensätze (Schema 5)

- `storage.depots[un] = {un, entity, surface_index, position, carryalls = {[un] = true}, alarm}`.
- Carryall: derselbe Datensatz wie der Ornithopter in `storage.flyers` mit `kind = "carryall"`, dazu `depot` (un), `job` (id), `fleet_mode` (`"auto"` oder `"manual"`), `fleet_goal` (zuletzt gesetztes Ziel). Umgesetzt: kein `parked`, geparkt heißt ≤ 3 Kacheln von der Mitte der Leitstelle; die Leitstelle führt keine Liste ihrer Carryalls.
- `storage.jobs = {next_id, list = {[id] = {id, kind, harvester, carryall, state, target, return_pos, deadline, created}}}`. Jeder Ernter steht in höchstens einem Auftrag (`storage.job_of_harvester[un] = id`).

### 4.2 Takte

- 30 Ticks: Verteilung (offene Aufträge nach Priorität, freien Carryall mit genug Treibstoff suchen), Ablauf aller laufenden Aufträge.
- 60 Ticks: Aufträge erzeugen (Tanken, Entladen), Parken und Nachfüllen an der Leitstelle.
- Umgesetzt: kein Haken in `worms.lua`; Wurmzeichen und Jagdende liest der 30-Tick-Takt aus `storage.hunts` (höchstens 0,5 s später, in der Zeitrechnung der Rettung enthalten).

### 4.3 Aufträge

| Auftrag | Auslöser | Ablauf |
|---|---|---|
| RETTUNG (100) | Wurmzeichen mit einem betreuten Ernter als Ziel | Hinfliegen, Kopplung 2 s, anheben, schweben bis Jagdende, dann RÜCKKEHR (bei Laderaum ≥ 90 % ENTLADEN) |
| TANKEN (60) | Ernter-Treibstoff unter 20 % oder Alarm „Kein Treibstoff“ | Hinfliegen bis 4 Kacheln, Treibstoff aus dem Kofferraum in den Ernter (`get_fuel_inventory().insert`, Kofferraum `remove`), zurück |
| ENTLADEN (50) | Laderaum ≥ 90 % | Anheben, zur nächsten freien Annahme in Reichweite, absetzen (dockt nach 2 s an), warten bis leer (höchstens 60 s), anheben, RÜCKKEHR |
| RÜCKKEHR (40) | nach Rettung oder Entladen | Zur alten Stelle, absetzen, aufbauen; ist die Stelle leer geerntet, auf Fels neben der Annahme absetzen und Alarm „Feld leer“ (Umsetzen erst 3f) |

- Eine RETTUNG darf einen leer fliegenden Carryall umleiten, nie einen mit Last.
- Umgesetzt, Bereitschaft: Hat eine Leitstelle mindestens zwei Carryalls in Automatik, bekommen Tanken, Entladen und Rückflug nur so viele, dass einer für Rettungen frei bleibt (im Mock-Dauerlauf biss sonst ein Wurm, während beide Carryalls Ernter zur Annahme trugen).
- Umgesetzt: TANKEN bekommt nur ein Carryall mit Brennstoff im Kofferraum; fliegt trotzdem einer ohne Erfolg hin, wartet der Ernter 5 min auf den nächsten Tankauftrag. Schwelle: Brennwert unter 100 MJ (gut 4 min Ernten).
- Umgesetzt, Feld leer: Der Ernter bleibt an der alten Stelle stehen, die Force bekommt die Meldung „Feld leer“.
- Kontakt tankt mit: Jeder Carryall, der einen Ernter anhebt oder absetzt, füllt dessen Treibstoff auf.

### 4.4 Flug und Parken

- `carryall.autopilot_destination = ziel`; Ankunft, wenn `autopilot_destination == nil` und Abstand ≤ 2 Kacheln (Abfrage im 30-Tick-Takt; `on_spider_command_completed` nur als Beschleuniger, falls es bei Skriptzielen feuert, Annahme V1).
- Parken: auf dem Landeplatz der Leitstelle (Ring um die Mitte, 4 Plätze, weitere daneben). Beim Parken füllt das Skript aus dem Leitstellen-Inventar nach: zuerst das Brennstofffach mit Flugtreibstoff, dann bis 2 Stapel Ernter-Treibstoff in den Kofferraum.

### 4.5 Verteilung, Reserve, ehrliche Absage

- Genug Treibstoff = Energie für Hin- und Rückweg zur Leitstelle (beladen mit Aufschlag) plus 20 % Reserve, gerechnet aus `burner.remaining_burning_fuel` plus Brennwert des Brennstofffachs.
- RETTUNG nur, wenn Abstand / Tempo + 2 s Kopplung < Restzeit − 3 s. Sonst sofort Alarm „Rettung nicht möglich“ mit Grund: kein Carryall frei, zu weit, kein Treibstoff.
- Notregel: Unter der Reserve setzt ein Carryall seine Last auf dem nächsten Felsplatz ab (Annahme oder Leitstelle); läuft keine Jagd, an Ort und Stelle. Dann fliegt er zum Tanken an die Leitstelle. Umgesetzt: Er setzt immer an Ort und Stelle ab, außer während einer laufenden Rettung (dann hält er durch).
- Umgesetzt: Eine Absage meldet die Leitstelle je Jagd nur einmal (`storage.jobs.refused`).

### 4.6 Handbetrieb

- Ein Insasse oder ein fremdes Flugziel (Fernbedienung) setzt `fleet_mode = "manual"` und bricht einen laufenden Auftrag ab; trägt der Carryall dabei einen Ernter, bleibt die Last beim Spieler. Umgesetzt: erkannt im 30-Tick-Takt am Fahrer und am Ziel, das nicht `fleet_goal` ist (`on_player_used_spidertron_remote` nennt das Fahrzeug nicht).
- Zurück in `auto`, sobald der Carryall leer und ohne Insassen an der Leitstelle parkt.

### 4.7 Abstürze, Abriss, Speichern

- Absturz mit Last: wie beim Ornithopter (Ernter fällt mit 30 % Schaden, Landesuche). Der Auftrag endet, die Leitstelle meldet es.
- Leitstelle abgerissen oder zerstört: ihre Carryalls fliegen zur nächsten Leitstelle der Force, sonst landen sie an Ort und Stelle (Last absetzen).
- Alles steht in `storage`; nach dem Laden laufen die Aufträge weiter (Flugziele neu setzen).
- `/arrakis-uninstall` setzt alle Lasten ab wie bisher. Umgesetzt: Er beendet vorher alle Aufträge und hält die Automatik 10 min an (`storage.fleet_pause_until`).

### 4.8 Ungeprüfte Engine-Annahmen

- V1: `on_spider_command_completed` feuert bei per Skript gesetztem `autopilot_destination` (sonst reicht die Abfrage).
- V2: Ein unbemannter Spider fliegt per `autopilot_destination` mit Brenner und Stickern wie bemannt.
- V3: `container` mit `tile_buildability_rules` lässt sich per Roboter nur auf Fels bauen.
- V4: Schweben eines Spiders über dem Wurm stört den Wurm nicht (W12 deutet darauf hin).
- V5: Ein Carryall über einer Felsinsel ohne Ziel bleibt stehen und verbraucht keinen Treibstoff im Stand.

## 5. Texte

Namen, Beschreibungen, Factoriopedia-Einträge, Alarme („Rettung nicht möglich: …“, „Feld leer“, „Carryall ohne Treibstoff“), Tipp „Leitstelle“, Fenster der Leitstelle (Carryalls, laufende Aufträge, Treibstoff). Deutsch und Englisch.

## 6. Prüfstand

- **T23** (automatisch, ohne Spieler): je ein Feld pro Auftrag: Rettung rechtzeitig (Ernter heil, alte Stelle, wieder aufgebaut), Rettung zu weit (Absage mit Grund, kein Carryall startet), Tanken (Ernter über 20 %), Entladen (Annahme leert, Rückkehr), Notregel, Handbetrieb (Fernbedienung bricht ab, Rückkehr in auto nach Parken), Absturz mit Last, Leitstelle abgerissen, Speichern und Laden mitten im Auftrag, Tempo leer/beladen je Treibstoff.
- **T24** (automatisch, Dauerlauf): Ziel aus dem Fahrplan, 3 Ernter, 1 Leitstelle, 2 Carryalls, Treibstoff in der Leitstelle, echte Würmer, 60 min Spielzeit. FEHLER bei einem verlorenen Ernter, einem Ernter ohne Treibstoff länger als 30 s oder einem festhängenden Auftrag. Umgesetzt: 4 Ernter, Jagden ohne sichtbaren Wurm (der Wurm würde auf dem Weg andere Ernter zerdrücken, das Ergebnis hinge vom Weg ab), Grenze ohne Treibstoff 2 min (die Bereitschaft hält einen Tankflug zurück, solange eine Rettung läuft). Nach dem letzten Wurmzeichen 4 min Nachlauf. Der erste Mock-Dauerlauf fand, dass Ernter an der Annahme bis 4,6 Kacheln weit abgesetzt wurden und nicht andockten (Ankunft auf 2,5 Kacheln); seitdem fliegt der Carryall dort bis auf 0,5 Kacheln an den Absetzpunkt (`lib.DOCK_ARRIVE`).
- Umgesetzt in T23: Übernahme und Nachfüllen, Rettung mit Tempomessung leer, Absage, Entladen, Tanken, Handbetrieb, Pause nach `/arrakis-uninstall`, Abriss. Noch ohne eigenen Schritt: Notregel, Absturz mit Last (Code des Ornithopters, T15), Speichern und Laden, Tempo beladen.
- **T25** (interaktiv, Max): Aussehen von Carryall und Leitstelle, Rettung aus Spielersicht, Fenster, Handbetrieb.
- Bestehende Tests T1–T22 müssen unverändert bestehen.

## 7. Prüfung vor der Übergabe

Wie bei 0.9.0: Syntax, `tools/check/api_names.py`, Datenstufe in fünf Varianten, Probelauf im Mock mit Carryall- und Leitstellen-Attrappen, dann der Lauf auf Max' PC (`tools/pc/lauf.py`, vom Thread gestartet).

## 8. Abnahme durch Max (0.10.0)

1. T23 und T24 ohne FEHLER auf seinem PC.
2. T25 im Spiel: Carryall und Leitstelle sehen passend aus, eine Rettung wirkt glaubwürdig, das Fenster zeigt den Stand.
3. Ein eigenes Spiel: Leitstelle bauen, Carryalls dazu, eine Weile laufen lassen.
