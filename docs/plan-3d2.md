# Umsetzungsplan Phase 3d2 (0.8.0): Sandwurm mit verzögertem Spawn, Route, Fels-Wächter und Abtauchen

Stand 26.10.2026. Grundlage: Design v0.3 (docs/design-ernter-ornithopter.md, kurz DOC), Plan 3d1 (docs/plan-3d1.md, kurz P3D1),
Code 0.7.0 (main 7d881a4), Prüfstand-Lauf vom 26.10.2026 mit 0.7.0 (T5 bis T7 mit dem Testwurm, T18 11/11, T19 10/10; Datei
`arrakis-test-20261026-225608.txt`, kurz PS070). API-Belege: A23 = factorio-types 1.2.72 (API 2.1.23, `dist/classes.d.ts`, `concepts.d.ts`,
`events.d.ts`, `prototypes.d.ts`, `types.d.ts`, `defines.d.ts`), A20 = typed-factorio 3.36.0 (API 2.0.75), V23 = Vanilla-Daten 2.1.23.
Dieser Plan ist der Bauvertrag: Namen, Dateien, Phasen, Zahlen und Texte gelten so, wie sie hier stehen. Wo der Plan von DOC oder P3D1
abweicht, gilt der Plan; DOC wird danach angeglichen (Liste in 7).

3d1 hat die Gefahr gebaut: Vibration, Wurmzeichen, Countdown und einen geskripteten Biss ohne Wurm. 3d2 macht den Wurm sichtbar: Er taucht
weit entfernt auf, fährt nur über Sand und um Fels herum zum Ziel, beißt bei 0 (höchstens 3 s später) und taucht wieder ab. Die Regeln aus
3d1 (wer gebissen wird, wer entkommt) bleiben in Inhalt und Reihenfolge, wie sie sind; der Wurm ändert nur, wann und wo man es sieht.

**Kennzeichnung:** **[Wn]** markiert eine Aussage, die auf noch nicht geprüftem Engine-Verhalten beruht. Abschnitt 4.17 sagt je Annahme,
welcher Test sie entscheidet und was gilt, wenn sie nicht hält. W statt V, weil V1 bis V22 zu P3D1 gehören.

**Antworten von Max (27.10.2026):** Alle vier Fragen in 1 mit „ja“ beantwortet (ROUTING, Sprint, Zerdrücken, Wurm getötet). Neu ist damit nur das
Zerdrücken: Der Wurm zerdrückt auf seinem Weg auch Fahrzeuge (Autos, Panzer, Spice-Ernter) und Figuren, ohne eigenen Alarm (Festlegung „Zerdrücken“).
Abschnitte 0, 4.10, 6 und 7 nennen stellenweise noch die alte Standardwahl („Fahrzeuge und Figuren nie“); dort gilt die Festlegung in 1 (4.12 ist seit der
Gegenprüfung angeglichen).
Im Code ist jede Antwort eine benannte Konstante: `CRUSH_SPARES_VEHICLES = false`, `KILL_RESCUES = true`, `NO_ROUTE_BITE = true` (scripts/worms.lua),
`SPRINT = true` (scripts/sandworm.lua).

**Gesichert aus PS070 (Testwurm `arrakis-test-worm`, nicht neu zu prüfen):**
- T5 a: `investigating` zu einem Punkt 120 Kacheln weiter: Ankunft nach 36,2 s für 117 Kacheln (Mittel 3,2, Spitze 3,5 Kacheln/s, 3,5 nach etwa 7 s);
  bei Abstand 4,0 wechselt der Zustand auf `patrolling` (1,1 Kacheln/s); mit `investigating` bleibt `activity_mode` auf full, minimal erst etwa 4 s
  nach `patrolling`. Der Ernter im Weg starb nach 31,1 s am Kontaktschaden.
- T5 b: `attacking` auf ein Fahrzeug fällt sofort auf `patrolling` zurück (0 von 30 s), kein Schaden.
- T5 c: `speed` alle 10 Ticks auf 1,0 Kacheln/s geschrieben: gefahren 1,2; danach frei 2,4 im Mittel, am Ende 3,5.
- T5 d: Flieger 3 s jeden Tick auf den Kopf teleportiert: 3000 → 3000 Gesundheit, 0 Sticker, Tempo danach 100 %.
- T6: Fels-Ebene `arrakis_rock` in der Wurmmaske hält nichts (Bahn A und B je 69 von 354 Messpunkten auf Fels, Ankunft 59,0 s); mit Wächter
  (Bahn C) 0 Messpunkte auf Fels, Kopfbox berührte Fels 14×, zwei Umwege (+60°, +30°), Ankunft 64,2 s (+5,2 s); Bahn D: Ernter 10 Kacheln vor
  Fels erreicht nach 21,5 s (Abstand 4,0), Kontaktschaden tötete ihn nach 22,8 s, 0 Messpunkte auf Fels.
- T7: `extended = true` gibt 22 Knoten (= `max_body_nodes`), Körper 21 Kacheln gerade hinter dem Kopf; jeder vierte Knoten = 6 Prüfungen,
  Felsprobe 4 Treffer (erster Knoten 9, 8 Kacheln hinter dem Kopf), Sandprobe 0; nach 1 Tick gleich.

## 0. Umfang

**In 0.8.0**
- Prototyp **Sandwurm** `arrakis-sandworm-small`: Kopie des kleinen Demolishers mit 12 Segmenten, sandfarben, ohne Asche, ohne Kontaktschaden,
  ohne Beute; Bohrstaub und Partikel in Sand; Effekt `arrakis-worm-dive` fürs Auf- und Abtauchen (3).
- Jede reguläre Jagd und bis zu 3 Befehlsjagden zugleich bekommen ab 27 s Countdown einen Wurm: Spawnplanung in 16 Richtungen mit Sandlinie, sonst ein Weg per `request_path` (ROUTING),
  verzögerter Spawn mit 3 s Reserve, Körperprüfung (4.4 bis 4.6).
- Anfahrt und Angriff mit Fels-Wächter, Umweg, einmaliger Neuplanung, Drosselung, Halten und Sprint; Biss nie vor 0, spätestens 3 s danach (4.7 bis 4.9).
- Zerdrücken auf dem Weg: Bänder, Schienen und Gebäude auf Sand vor dem Kopf sterben; Fahrzeuge, Figuren, Ornithopter und Bauten von Forces
  in der Schonfrist nie; nichts bei einem Ziel vor 0 (4.10).
- Abtauchen nach Biss und Suche; Wurm getötet: Jagd endet, Ziel gerettet; Wurm verloren: Biss wie 0.7.0 (4.11).
- Grenzen, Speichern/Laden, Migration auf Schema 4, Waisen, `/arrakis-uninstall` (4.13, 4.14).
- Prüfstand: T21 (automatisch, echter Wurm und echter Code), T22 (interaktiv, Optik und Laden); T19 und T20 laufen ohne Wurm wie 0.7.0 (6).

**Nicht in 0.8.0**
- Großer Wurm (`arrakis-sandworm-large`, Wärme ab 2000), Thumper, Beute und Wurmzahn, Mod-Einstellungen für die Zahlen, Balancing-Runde:
  3d3 (0.9.0). 3d2 zählt getötete Würmer schon in `storage.worm_stats` (4.2).
- Neue Fenster-, Alarm- oder Statustexte für die Wurm-Phasen: Die Anzeige aus 0.7.0 bleibt (4.3 „Anzeige“).
- Frühwarnung, Ernte-Dämpfung, Rettung durch Carryalls: 3e/3f. 2.1-Komfort (Pins, Musik, `LuaForce.add_custom_alert`): 3g.
- Zweig `factorio-2.0`: bleibt bei 0.5.0. Prototypen und Laufzeit bleiben 2.0-tauglich (A20-Belege stehen jeweils dabei).

## 1. Festlegungen (Standardwahl, Max kann widersprechen)

| Punkt | Festlegung | Grund |
|---|---|---|
| Werte | Alle Zahlen sind Konstanten im Code (4.1), keine Mod-Einstellung | Wie 3b bis 3d1; Einstellungen kommen mit 3d3 (DOC 2) |
| Module | Neu `scripts/sandworm.lua`: der Wurm als Fahrzeug (Planung, Weg, Erzeugen, Steuern, Wächter, Tempo, Abtauchen, Waisen). `scripts/worms.lua` bleibt Herr der Jagd: Phasen an Biss und Ende, Biss, Zerdrücken, Tod und Verlust des Wurms | sandworm entscheidet nie, wer stirbt; worms entscheidet nie, wohin der Wurm fährt. Abhängigkeit ohne Kreis: `worms` → `sandworm` → `terrain` |
| Takte | Kein neuer Takt: der 10-Tick-Takt von worms.lua ruft je Jagd in fester Reihenfolge `track`, `sandworm.step`, Zerdrücken, Biss-Fenster (4.3) | event_handler sichert keine Reihenfolge zwischen Modulen zu (P3D1 1 „Takte“); Wächter, Tempo und Biss müssen im selben Takt aufeinander folgen |
| Prototyp | `arrakis-sandworm-small` = deepcopy von `small-demolisher` (V23 space-age/prototypes/entity/enemies.lua:6500) mit 12 Segmenten (die ersten 11 und der Schwanz), sandfarben, in der Factoriopedia sichtbar ohne Simulation. Der Testwurm (prototypes/testbench/worms.lua) bleibt unverändert | DOC 4.3 „Kürzere Körper“; T7 maß mit 12 Segmenten 22 Knoten und 21 Kacheln. Mit eigenem Prototyp bleiben die Belege aus T5 bis T7 gültig, egal was 3d2 ändert |
| Tempo | `investigating_speed`, `attacking_speed` und `enraged_speed` = 3,5 Kacheln/s (`3.5 / 60`), `patrolling_speed` 1 (`1 / 60`), `enraged_duration = 60`; Beschleunigung (0,55 Kacheln/s²), `turn_radius` 6 und `patrolling_turn_radius` 10 bleiben Vanilla | T5 a bestätigt 3,5 Kacheln/s; T5 b: `attacking` hält kein Fahrzeug, also bringt `attacking_speed` 6 nichts (DOC 4.3 „nur, wenn T5 den Sprint bestätigt“ ist nicht erfüllt); gereizt fährt er nicht schneller und höchstens 1 s anders |
| Kontaktschaden | Fällt an Kopf und Segmenten weg (V23 enemies.lua:1021–1044 und :1481–1503); an seine Stelle tritt das Zerdrücken per Skript (4.10) | Der Vanilla-Schaden (500 je Treffer, Radius 2,5) tötete den Ernter in T5 a nach 31,1 s und in T6 D nach 22,8 s, also vor 0, und fragt weder nach Fels noch nach dem Bissmodus: DOC 2.4 „Ein Biss kommt nie vor Ablauf des Countdowns“ und „Was vollständig auf Fels steht …, wird nie gefressen“ |
| Effekte | Ohne Asche, Spuren, `destroy-cliffs`, Sticker, Erdspalten (`revenge_attack_parameters`) und Gereizt-Effekte. Bohrstaub als vier sandfarbene Kopien, Vulcanus-Steine und Lava als Sandsteine, Sterbe-Rauch als `arrakis-sand-dust`; Haut- und Panzerteile bleiben | DOC 4.3 „Ascheeffekte entfernen“; Befund ERG07 (0.4.0): dunkler Bohrstaub und orange Lava passen nicht nach Arrakis |
| Beute | Keine: `loot = nil`, `corpse = nil`, kein `create-entity` einer Leiche in `dying_trigger_effect`; kein Wolfram | Beute und Wurmzahn kommen mit 3d3; die Vanilla-Leiche trägt 5 bis 16 Wolframerz (V23 enemies.lua:1333) |
| Gesundheit | Vanilla: 30 000, Heilung 40 je Tick, Resistenzen des Demolishers | Balancing ist 3d3; der Wurm bleibt eine echte, tötbare Einheit (DOC 2.5) |
| Maske | Vanilla-Maske der `segmented-unit` {player, train, rail, transport_belt, is_object} (V23 core/lualib/collision-mask-defaults.lua:193–194), ohne `arrakis_rock` | T6 B: Die Fels-Ebene hält den Wurm nicht; Fels hält nur der Wächter fern (4.8) |
| Wurm oder nicht | Beim Start bekommt eine Jagd einen Wurm, wenn ihre Force nicht per Prüfstand ausgeschaltet ist, der Countdown mindestens 27 s ist und sie die Grenze (Zeile „Grenze“) nicht überschreitet; sonst Phase `ohne` mit Biss wie 0.7.0 genau bei 0 | Unter 27 s reicht die kürzeste Anfahrt (80 Kacheln mit 1 s Planung und 3 s Reserve, 4.4) nicht. Befehlsjagden mit 2, 10 und 20 s (T19 Schritte 3 und 5) bleiben so, wie sie sind |
| Regeln | Countdown fest, Entscheidung wie P3D1 4.7 (weg; getragen oder andere Oberfläche; ganz auf Fels; außer Reichweite; sonst Biss), in Reihenfolge und Wirkung unverändert. Neu ist nur der Zeitpunkt: in jedem 10-Tick-Takt des Biss-Fensters `[eta_tick, eta_tick + 180]` | P3D1 1 „Entscheidung“; DOC Roadmap 3d2 „Biss höchstens 3 s nach Countdown-Ende“. Die Regeln gelten im Moment des Bisses: Wer im Fenster noch anhebt, ist gerettet |
| Biss | Bei `tick ≥ eta_tick`, beißbar und Kopfmitte höchstens `R = 3 + r` von der Zielmitte (r = halbe Diagonale der Zielbox beim Start; Ernter 1,58, also R = 4,58): Biss nach P3D1 4.9 an der Zielmitte. Bei `eta_tick + 180` ohne Biss: **Ersatzbiss** genau so, mit Logzeile und Zähler; der Wurm taucht dort ab, wo er ist | DOC 4.3 Schritt 6. Der Ersatzbiss hält die 3-s-Regel auch dann, wenn ein Wurm hängt; T21 verlangt ihn im Normalfall nie |
| Zielpunkt | `P` = Mitte des Ziels, wenn es gültig, auf der Oberfläche der Jagd, nicht getragen und mit Sand darunter ist, sonst `last_pos`; liegt dieser Punkt weiter als `reach` von `warn_pos`, rückt P auf den Rand des Reichweitenkreises (`warn_pos + reach · Einheitsvektor`); jeden Takt neu. Suche und Schutzzone nehmen denselben Punkt | Ersetzt ENTKOMMEN aus DOC 4.3: Der Wurm fährt zur letzten Stelle und wartet dort; entschieden wird bei 0 (P3D1). Der Rand hält P3D1 4.7 „so weit kam der Wurm nicht“ ein: Wo Fenster und Ring „außer Reichweite: sicher“ zeigen (messages.cfg:79), hält der Wurm am Kreis, statt neben dem Ziel zu warten |
| Spawn | Countdown T s, Weglänge L: `D = min(160, 3,5 · (T − 4))`, `spawn_tick = eta_tick − ceil((L / 3,5 + 3) · 6) · 10`. 60 s: D = 160, Spawn 670 Ticks nach dem Wurmzeichen (2930 vor 0); Lehrjagd 90 s: 2470 danach; 27 s: D = 80,5, 60 danach | DOC 4.3 Schritt 1 (`D = clamp(v · t, 80, 160)`, Ankunft genau bei 0) hatte keine Reserve. Gegen ein stehendes Ziel bleiben 4,4 s Luft (3 s Reserve, R / 3,5 = 1,3 s, Aufrunden 0,1 s), mit dem Biss-Fenster 7,4 s bis zum Ersatzbiss: genug für einen Umweg wie T6 C (+5,2 s) oder einen Start ohne Schwung (V / 2a = 3,2 s, [W1]), nicht für beides; hält W1 nicht, wächst die Reserve (4.17). Ein Ziel, das davonfährt, holt nur der Sprint ein (4.9). Die 4 in `T − 4` sind 3 s Reserve und 1 s Planung |
| Planung | 16 Richtungen um P mit Abstand D, dann 120 und 80 (nur, wenn mindestens 10 Kacheln kürzer als D). Startrichtung: Fahrtrichtung des Ziels, wenn es fährt (der Wurm kommt von vorn), sonst `storage.rng(0, 15)`; `speed` gibt es nur bei Fahrzeugen, ein Gebäude steht. Gültig: Spawnpunkt und Körperlinie (20 Kacheln dahinter, alle 4) auf Sand in generierten Chunks, dort bis 4 Kacheln kein Fahrzeug und keine Figur, und Sandlinie zu P alle 4 Kacheln bis 6 Kacheln vor P; ungenerierte Chunks zählen als Fels | DOC 4.3 Schritt 1; Segmente in ungenerierten Chunks werden zerstört (A23 classes.d.ts:18962). Auf Fahrzeugen und Figuren taucht er nie auf (ihr Zerdrücken auf dem Weg ist die Ausnahme ohne Alarm, Zeile „Zerdrücken“). Höchstens 8 Kandidaten je Takt, damit ein Takt nie mehr als etwa 360 Kachelabfragen braucht |
| ROUTING | Nur wenn keine Richtung gültig ist: `request_path` (4.5) für höchstens 2 Kandidaten, deren Spawn und Körper passen, kürzester Abstand zuerst, mit Box ±3,5 (Körper ±2,3 plus Spiel), nur bei Fels am Start oder ohne Weg einmal mit ±1,5; der Weg wird auf natürlichen Sand geprüft und nur so weit ausgedünnt, wie die Sichtlinie (Mitte und ±1,5) Sand bleibt. Ohne Wurm bis `eta_tick − 1440`: Phase `ohne`, Biss wie 0.7.0 | DOC 4.3 Schritt 2 ließ die Jagd dann „still entfallen“. Das widerspräche P3D1 (nur ganz auf Fels ist sicher) und machte Sandtaschen im Fels zu sicheren Bauplätzen (Frage an Max; Max 27.10.: ja, `NO_ROUTE_BITE = true`) |
| Körper | Direkt nach dem Erzeugen jeder vierte Knoten aus `get_body_nodes()` auf Sand in generiertem Chunk; sonst im selben Tick zerstören und nächster Kandidat, höchstens 3 Erzeugungen je Jagd | DOC 4.3 Schritt 3; T7 belegt Knotenzahl, Lage und Erkennung |
| Steuern | `set_ai_state{type = investigating, destination}` bei jedem Zielwechsel um mehr als 2 Kacheln und sonst alle 30 Ticks, immer; `minimum_activity_mode` minimal ab dem Spawn, full im Angriff | DOC 4.3 Schritt 3. T6 führte nur bei anderem Zustandstyp nach; ein veraltetes Ziel blieb dann stehen. Das Neusetzen beendet auch einen Gereizt-Zustand (Geschütze) [W9] |
| Wächter | Alle 10 Ticks: Kopfmitte auf Fels oder in ungeneriertem Chunk → sofort abtauchen. Vorausschau längs Kopfrichtung und zum Ziel, je höchstens 18 Kacheln und nie über den Haltepunkt hinaus, Mittellinie und zwei Seitenlinien (±1,5) alle 2 Kacheln. Fels → Umweg ±30/60/90°, erst 30, dann 15, dann 8 Kacheln weit; ohne Umweg einmal Neuplanung vom Kopf (`request_path`), sonst abtauchen. 300 Ticks ohne 0,5 Kacheln Bewegung → abtauchen | DOC 4.3 „Fels-Wächter“, Werte aus T6 C (0 Messpunkte auf Fels). Die Seitenlinien sollen die 14 Berührungen der Kopfbox senken; „nie über das Ziel hinaus“ (DOC, Angriff) gilt für jedes Ziel, auch Wegpunkt und Suchort. T6 C prüfte 30 Kacheln nur auf offenem Sand; in einem Gang passen erst die kurzen Umwege [W17] |
| Angriff | Erst, wenn kein Wegpunkt und kein Umweg mehr offen ist, der Kopf höchstens 40 Kacheln von P ist und die Linie Kopf → Reichweitenpunkt Sand ist (zurück zur Anfahrt über 50, bei einem Umweg oder neuer Route): Fahrziel 20 Kacheln hinter P, wenn die Linie P → dort Sand ist, sonst 6 Kacheln hinter P (auch über Fels); `minimum_activity_mode = full`; Tempo je Takt `clamp(S / Restzeit, 0, 6)` mit dem Restweg S; in Reichweite vor 0: Tempo 0 (halten) | DOC 4.3 Schritte 5 und 6; T5 c: Drosseln per `speed` alle 10 Ticks wirkt. Mit offenen Wegpunkten schnitte die Linie zu P den Fels der Route. Das Fahrziel liegt nie näher als 6 Kacheln hinter dem Haltepunkt, weil die Engine 4 Kacheln vor dem Fahrziel auf `patrolling` wechselt (T5 a) und ein kleines Ziel (R unter 4, etwa Pumpe oder Bohrer) sonst nie erreicht würde; gehalten wird über das Tempo |
| Sprint | Zu spät (Restweg / 3,5 > Restzeit − 1 s) oder nach 0 noch nicht in Reichweite: `speed` je Takt bis 6 Kacheln/s, also über `target_speed` [W3]; Ersatz 1 `move_forward`, Ersatz 2 Knotenschub per `set_body_nodes` (4.9) (Frage an Max; Max 27.10.: ja, `SPRINT = true`) | DOC nannte 6 Kacheln/s; `attacking` scheitert (T5 b), also Tempo per Skript. Ohne Sprint bekommt ein Ernter, der einpackt und davonfährt, in etwa 40 % der Anfahrtsrichtungen den Ersatzbiss bei 0 + 3 s, während der Wurm noch etwa 50 Kacheln zurück ist (4.9); die Reichweite (P am Kreis) bleibt 3,5 Kacheln je Sekunde Countdown |
| Zerdrücken | Nur der Kopf, alle 10 Ticks, und beim Auftauchen einmal an jedem vierten Knoten: Es stirbt jede Entity mit Gesundheit, deren Box höchstens 2,5 Kacheln von der Mitte liegt und Sand berührt, auch Fahrzeuge (`VEHICLE_TYPES`: Autos, Panzer, Spice-Ernter) und Figuren (Max 27.10.). Ein Spice-Ernter folgt dabei `arrakis-worm-bite` wie beim Biss (`devour`): Totalverlust samt Insassen oder schwer beschädigt; andere Fahrzeuge sterben samt Insassen. Ausgenommen ist alles, was der Biss ausnimmt (Ornithopter samt Insassen, Spinnenbeine, Ressourcen, Leichen, Geister, Klippen, `destructible == false`, Sandwurm-Force), dazu Hochschienen samt Schienenfahrzeugen darauf (`draw_data.height > 0`, auch auf der Rampe; Gegenprüfung 0.8.0), Segmente, Entities einer Force, die noch nicht wach ist (`storage.grace[i].awake == false`), jedes Ziel einer laufenden Jagd und alles bis 5 Kacheln um deren Schutzpunkt. Keine Eruption, kein Chat, kein Alarm (Frage an Max: auch Fahrzeuge und Figuren? Max 27.10.: ja, auch Fahrzeuge und Figuren; `CRUSH_SPARES_VEHICLES = false`, mit `true` die alte Standardwahl) | DOC 2.1 Schritt 9: „Auf dem Weg zerdrückt der Wurmkörper Bänder, Schienen und Gebäude auf Sand“. Bis 27.10. galt hier „Fahrzeuge und Figuren nicht“ mit dieser Begründung: Ein Ernter im Vorsichtsmodus darf nur einer laufenden Jagd auf sich selbst oder einem Biss nebenan zum Opfer fallen (DOC 2.1 Schritt 6, P3D1 1 „Grenze Vorsicht“), und ein Nachbar im Gang der Anfahrt bekäme weder Alarm noch Countdown. Forces in der Schonfrist verlieren nichts (DOC 2.1 Schritt 3). Der Körper folgt der Kopfspur (DOC 4.3), also reicht der Kopf. Die Schutzzone (Bissradius 4 + 1) hält „nie vor 0“ für alles, was der Biss treffen könnte |
| Flieger | Ornithopter samt Insassen werden nie getroffen und nicht spürbar gebremst: kein Kontaktschaden, keine Sticker, die Maske des Fliegers hat nur `trigger_target` (V23 collision-mask-defaults.lua:190). Der Prüfstand vom 27.10.2026 abends (0.8.1) maß über dem Körper trotzdem 89 % des Vergleichstempos für 115 Ticks (Ursache offen, W12); seit 0.8.2 gilt als Grenze: über dem Körper mindestens 80 % des Vergleichstempos, Flugzeit höchstens 5 % länger | DOC 2.4; T5 d mit dem Testwurm; T21 prüft es mit dem echten Wurm und dem echten Flug [W12] |
| Abtauchen | Nach dem Biss im selben Takt; in der Suche, sobald der Kopf höchstens 8 Kacheln von P (`last_pos`, am Kreis geklemmt) ist, spätestens bei `end_tick = eta_tick + 600`. Staub an jedem vierten Knoten, `arrakis-worm-dive` und Rumpeln am Kopf, dann `destroy{raise_destroy = true}` | DOC 4.3 Schritte 7 und 8; `raise_destroy` meldet anderen Mods das Ende (A23 classes.d.ts:18996) |
| Auftauchen | Dieselben Effekte am Spawn | Wer in der Nähe ist, sieht, woher der Wurm kommt |
| Wurm getötet | `on_segmented_unit_died` für einen eigenen Wurm: Jagd endet sofort, vor 0 mit `killed` (Rücksetzen, Ruhe, Statistik `killed` + 1, `first_escape_tick`), in der Suche mit dem schon gesetzten Ergebnis und `killed` + 1 dazu; Chat `msg-worm-killed` („… ist gerettet“) nur vor 0 mit gültigem, nicht verlorenem Ziel, sonst `msg-worm-killed-plain`; das Ziel lebt | DOC 4.3 „Wurm getötet → Beute, Ende“ (Beute 3d3). Neue Ausnahme zu „eine Jagd endet nie vor `eta_tick`“ (P3D1 4.8) (Frage an Max; Max 27.10.: ja, `KILL_RESCUES = true`) |
| Wurm verloren | Zerstört, ohne dass wir es waren (anderer Mod, `tb.prepare`), oder ungültig: Phase `ohne` mit `no_worm = "verloren"`, Biss wie 0.7.0 genau bei 0 | Eine Jagd endet nie still. `tb.prepare` zerstört Würmer ohne Ereignis (scripts/testbench/runner.lua:364–372) |
| Grenze | Reguläre Jagden bekommen immer einen Wurm (höchstens 3 zugleich, P3D1 4.5). Befehlsjagden nur, solange weniger als `MAX_DEBUG_WORMS = 3` Befehlsjagden in den Phasen `warten` bis `angriff` oder mit Wurm in der Suche sind; darüber Phase `ohne` (`"grenze"`). Zusammen also höchstens 6 Würmer | P3D1 1 „Grenzen“: Befehlsjagden zählen nicht mit und sperren nichts; ein Admin mit vielen `/arrakis-worm` nimmt regulären Jagden so keinen Wurm. Die Doku rät ab, viele Einheiten aktiv zu halten (A23 classes.d.ts:19087) |
| Anzeige | `hunt.state` bleibt warning/biting/searching; Fenster, Ring, Alarm, Status und Chat wie 0.7.0; neu sind nur `hunt.phase` und `hunt.no_worm` | Der Spieler sieht den Wurm selbst. worms-gui und T19 bleiben unverändert |
| Befehlsjagd | `/arrakis-worm` bekommt ab 27 s einen Wurm (höchstens 3 zugleich), darunter beißt es wie 0.7.0 | Zum Ausprobieren im eigenen Spielstand; der Hilfetext sagt es (5) |
| Force | Vor dem ersten `sandworm.step` eines Takts holt worms die Sandwurm-Force (`game.forces[FORCE] or lib.ensure_force()`) und gibt die LuaForce weiter; sandworm nennt die Force nie als Text. Gibt es keine (64er-Grenze), wird jede Jagd mit Wurm-Phase `ohne` (`"keine-force"`); ein schon erzeugter Wurm taucht dabei ab (4.3 „Wechsel auf `ohne`“) | Nach `/arrakis-uninstall ja` ist die Force einen Tick später verschmolzen, die Pause sperrt aber nur Wurmzeichen, nicht `/arrakis-worm`. In 0.7.0 legt nur `bite` sie neu an (scripts/worms.lua:726) |
| Migration | Schema 4; laufende Jagden ohne `phase` oder `r` (aus 0.7.0, auch nach einem Umweg über 0.7.0) bekommen bei jedem `on_configuration_changed` Phase `ohne` (`"migration"`); jeder `on_configuration_changed` räumt Würmer unseres Prototyps ohne Jagd | Eine 0.7.0-Jagd hat keine Planung, und ihr Countdown ist vielleicht schon zu kurz. Nach 0.8.0 → 0.7.0 → 0.8.0 steht `schema` schon auf 4 (`math.max`), deshalb hängt das nicht an `old < 4` |
| Entfernen | `/arrakis-uninstall ja` lässt zusätzlich alle Würmer abtauchen und räumt Waisen auf allen Oberflächen, vor dem Verschmelzen der Force; die Meldung zählt beide | Beim Entfernen der Mod löscht Factorio unsere Würmer ohnehin; bleibt die Mod, sollen keine Waisen bleiben |
| Herunterstufen | Auf 0.7.0: vorher `/arrakis-uninstall ja`. Sonst löscht die Engine die Würmer (Prototyp fehlt), und laufende Jagden beißen in 0.7.0 ohne Wurm | 0.7.0 kennt Phase und Wurm nicht |
| Protokoll | `storage.hunts.log`: die letzten 20 beendeten Jagden mit Phasen, Zeiten, Abstand beim Biss, Umwegen, Wegen und Ersatzbiss; je Jagd mit Wurm eine Zeile in `factorio-current.log` (4.16) | T21 wertet daraus aus; Max kann Auffälliges aus dem Spiel schicken |
| Prüfstand | T19 und T20 schalten den Wurm für ihre Forces aus und bleiben in Ablauf und Erwartung wie 0.7.0; T18 nur mit neutraler Schemaprüfung (Schritt 1); T5 bis T7 unverändert; neu T21 (automatisch) und T22 (interaktiv) | Die 3d1-Erwartung „Biss genau bei 0“ gilt für Phase `ohne` weiter; den Wurm prüfen T21 und T22. T18 prüft heute `storage.schema == 3` (scripts/testbench/t_jagd.lua:728) |
| Mindestversion | unverändert `base >= 2.1.23`, `space-age >= 2.1.23` | Der Demolisher kommt aus Space Age, das ohnehin Pflicht ist |

## 2. Dateien

Neu:
- `prototypes/sandworm.lua`: Sandwurm samt Segmenten, vier Bohrstaub-Kopien, Effekt `arrakis-worm-dive` (3).
- `scripts/sandworm.lua`: Spawnplanung, ROUTING samt `on_script_path_request_finished`, Erzeugen und Körperprüfung, Steuern, Fels-Wächter,
  Tempo, Abtauchen, Waisen, Prüfstand-Haken. Modultabelle `lib`, andere binden sie als `sandworm_lib`.
- `scripts/testbench/t_sandwurm.lua`: T21 und T22.

Geändert: `data.lua` (require `prototypes.sandworm` direkt nach `prototypes.worms`: `arrakis-worm-dive` kopiert die Eruption), `control.lua`
(`scripts.sandworm` vor `scripts.worms`), `scripts/worms.lua` (Phasen, Biss-Fenster, Zerdrücken, gemeinsamer Kern `devour`, Ereignisse des Wurms,
Force vor dem Takt, Grenze, `killed` in `stats_for` und `on_forces_merging`, Prüfstand-Felder in `on_force_created`, neuer Handler
`on_pre_surface_cleared`, Migration Schema 4, Entfernen, Haken), `scripts/migrate.lua` (Schema 4), `scripts/flyer.lua` (nur `/arrakis-uninstall`: zweite Zahl),
`locale/{de,en}/arrakis.cfg`, `locale/{de,en}/messages.cfg`, `scripts/testbench/runner.lua` (ORDER, Modulliste, zwei Weiterleitungen, Vertrag),
`scripts/testbench/t_jagd.lua` (T18 Schritt 1 Schemaprüfung, T19 und T20 ohne Wurm, T19 Statistik mit `killed`), `tools/check/checks.lua`,
`tools/check/api_names.py` (neue Namen, 7), `tools/pc/pruefstand.py` (Hilfetexte Z. 34 und 767), `info.json`, `changelog.txt`, `README.md`, `docs/pruefstand.md` (6), DOC (danach, 7).

Unverändert: `prototypes/testbench/worms.lua` und `scripts/testbench/t_worm.lua` (T5 bis T7), `prototypes/worms.lua`, `prototypes/noise.lua`
(die veröffentlichten Ausdrücke `arrakis_v2_*` und `arrakis_v3_*` bleiben, wie sie sind), `scripts/vibration.lua`, `scripts/worms-gui.lua`,
`scripts/harvester.lua`, `scripts/harvester-gui.lua`, `scripts/terrain.lua`, alle übrigen Prototypen und Testmodule.

## 3. Prototypen (2.0-Schreibweise; `compat.finish` setzt 2.1 um)

Alles in `prototypes/sandworm.lua`. Sandtönung `SAND = {r = 1, g = 0.85, b = 0.6}` wie prototypes/worms.lua (Eruption, Symbol). Hilfen wie im
Testwurm (Ascheerkennung, `remove_loot`, `tint_layers`, `rename`, prototypes/testbench/worms.lua), aber als eigene Kopie: Der Testwurm-Code bleibt
unberührt. Keine eigenen Bild- oder Tonpfade; was nicht geerbt wird, kommt aus V23 wörtlich.

**Kopf** `arrakis-sandworm-small` (`segmented-unit`, A23 prototypes.d.ts:8751): `table.deepcopy(data.raw["segmented-unit"]["small-demolisher"])`
(V23 enemies.lua:468 `make_demolisher_head`, Werte :6500: scale 0,5, 30 000 Gesundheit, Heilung 40, Tempofaktor 0,55), dann
- `name`, `localised_name = {"entity-name.arrakis-sandworm-small"}`, `localised_description = {"entity-description.arrakis-sandworm-small"}`,
  `icons = {{icon = <geerbtes icon>, icon_size = <geerbt oder 64>, tint = SAND}}`, `icon = nil`, `order = "s-z[arrakis]-a[sandworm-small]"` (hinter den
  Demolishern `s-h` bis `s-j`), `subgroup` bleibt `enemies`, `factoriopedia_simulation = nil`, nicht versteckt, `autoplace = nil`.
- Tempo (Kacheln je Tick): `investigating_speed = 3.5 / 60` (:8783), `attacking_speed = 3.5 / 60` (:8763), `enraged_speed = 3.5 / 60` (:8771),
  `patrolling_speed = 1 / 60` (:8787), `enraged_duration = 60` (:8767). Bleiben: `acceleration_rate` (:8755, 0,55/3600), `turn_radius` 6 (:8816),
  `patrolling_turn_radius` 10 (:8791), `turn_smoothing` 0,75 (:8820), `collision_box` ±1,5, `max_health`, `healing_per_tick`, `resistances`.
- `vision_distance = 0` (:8824, zulässig 0 bis 100), `territory_radius = 1` (:8808, Pflicht), `revenge_attack_parameters = nil` (:8795),
  `update_effects_while_enraged = nil` (:8746).
- `update_effects` (:8742, V23 enemies.lua:573–1053), Eintrag für Eintrag:
  - weg: alles mit Asche, Spur oder Sticker (`…-ash-cloud-trail` :573–581, `…-trail-upper` :584–590, `…-trail-lower` :592–599, Muster wie der Testwurm),
    `destroy-cliffs` (:1047–1053) und jeder Eintrag, der irgendwo `type = "damage"` enthält (der Flächenschaden :1021–1044);
  - Bohrstaub: `smoke_name = "demolisher-mining-smoke-<x>"` → `"arrakis-sandworm-smoke-<x>"` für x = front, small-top, small-bottom, big (:602–770);
  - Partikel: `vulcanus-stone-particle-small` und `-medium` → `sand-1-stone-particle-small` bzw. `-medium`, `-big` → `sand-1-stone-particle-medium`
    (es gibt kein „big“, V23 base/prototypes/particles.lua:2979, :3010, :3030), `vulcanus-blood-particle-lower-layer-small` → `sand-1-stone-particle-tiny` (:781).
- `dying_trigger_effect` (A23 prototypes.d.ts:3680, V23 enemies.lua:1065 ff.): ohne `create-entity` der Leiche; `demolisher-dying-smoke` →
  `arrakis-sand-dust`; `vulcanus-lava-particle-long-life-small` → `sand-1-stone-particle-small`, `-big` → `sand-1-stone-particle-medium`;
  `demolisher-skin-particle-*` und `demolisher-shell-particle-*` bleiben. `corpse = nil` (:3673), `loot = nil` (:3717).
- `animation`: jede Bildebene `tint = SAND`, außer Schatten, Leuchten, Licht und Laufzeit-Tönung (wie `tint_layers` im Testwurm).
- Maske bleibt geerbt (nicht gesetzt, also die Vorgabe der `segmented-unit`), ohne `arrakis_rock`.
- `segment_engine.segments` (:8804, types.d.ts:9596): die ersten 11 Einträge und der letzte (Schwanz) der Vanilla-Liste (41 Einträge, V23 enemies.lua:286–328),
  umbenannt: Präfix `small-demolisher` → `arrakis-sandworm-small` (`…-segment-x0_…` bzw. `…-tail-x0_…`, V23 :408, :1753).

**Segmente** (`segment`, A23 prototypes.d.ts:8703): deepcopy jedes benutzten Vanilla-Segments (V23 enemies.lua:1366 `make_demolisher_segment`), einmal je
Name, `hidden = true`, `localised_name = {"entity-name.arrakis-sandworm-small"}`, `factoriopedia_simulation = nil`, `update_effects` wie beim Kopf
(Flächenschaden :1481–1503 weg, Partikel :1399–1478 in Sand), `update_effects_while_enraged = nil`, `dying_trigger_effect`, `corpse`, `loot` wie beim Kopf,
Tönung wie beim Kopf.

**Bohrstaub** (`trivial-smoke`, A23 prototypes.d.ts:10651): je eine deepcopy von `demolisher-mining-smoke-front`, `-small-top`, `-small-bottom`, `-big`
(V23 space-age/prototypes/entity/smoke.lua:227, :241, :255, :269) als `arrakis-sandworm-smoke-front`, `-small-top`, `-small-bottom`, `-big`, nur `color` neu:
front und small-top `{0.80, 0.65, 0.40, 0.6}`, small-bottom `{0.50, 0.41, 0.25, 0.46}` (Vanilla teilt dort durch 1,6 bzw. 1,3), big `{0.70, 0.57, 0.36, 0.6}`.
Dauer, Größe und Ausbreitung bleiben geerbt.

**Auf- und Abtauchen** `arrakis-worm-dive` (`explosion`, A23 prototypes.d.ts:3889): deepcopy von `data.raw.explosion["arrakis-worm-eruption"]`
(prototypes/worms.lua), `localised_name = {"entity-name.arrakis-worm-dive"}`, jede Animation bzw. Ebene `scale = 1.0` statt 1,5, `sound = nil`
(den Ton spielt das Skript als `arrakis-rumble`). Partikel und Sandstaub der Eruption bleiben. Kein Schaden (die Eruption hat keinen).

Keine Änderung an Forschungen, Rezepten, Items, Tasten, Verknüpfungen, Kacheln und Kollisionsebenen.

## 4. Laufzeit

### 4.1 Module und Ereignisse
`control.lua` lädt per event_handler wie 0.7.0, dazu `scripts.sandworm` direkt vor `scripts.worms`. Abhängigkeiten ohne Kreis: `worms` → `sandworm`
(neu), `vibration`, `harvester`, `terrain`, `worms-gui`; `sandworm` → `terrain`. sandworm liest und schreibt nur die Wurm-Felder einer Jagd (4.2) und
`storage.path_requests`; worms ruft es auf.

`scripts.sandworm` stellt bereit: `begin(hunt, opts) → phase, no_worm` (beim Start, 4.4), `step(hunt, tick, worm_force)` (10-Tick-Takt, 4.3), `head_of(hunt) →
position|nil, nodes|nil`, `dive(hunt, why, quiet)` (4.11), `forget(hunt)` (Wurm und Anfragen vergessen, ohne zu zerstören), `drop_requests(hunt)`,
`to_none(hunt, why, dive_why)` (jeder Wechsel auf `ohne`, 4.3), `tidy(tick)` (alte Anfragen räumen, 4.5),
`counted(debug) → n` (für die Grenze, nur Befehlsjagden bzw. nur reguläre), `sweep(surfaces|nil) → n` (Waisen, 4.14), Prüfstand-Haken (4.18), Konstanten
`NAME = "arrakis-sandworm-small"`, `PREFIX = "arrakis-sandworm-"`, `V = 3.5`, `V_SPRINT = 6` (Kacheln/s), `LEAD = 3` (s), `T_MIN = 27` (s), `D_MAX = 160`,
`D_MIN = 80`, `D_STEPS = {120, 80}`, `DIRECTIONS = 16`, `LINE_STEP = 4`, `LINE_END = 6`, `BODY_LEN = 20`, `BODY_STEP = 4`, `BODY_CLEAR = 4`, `CHECKS_PER_TICK = 8`,
`PLAN_EARLY = 300`, `SPAWN_DEADLINE = 1440`, `SPAWN_MAX = 3`, `PATH_MAX = 2`, `PATH_RETRY = 60`, `PATH_TRIES = 5`, `PATH_TIMEOUT = 300`, `PATH_RADIUS = 8`,
`PATH_RESOLUTION = -2`, `PATH_BOX = 3.5`, `PATH_BOX_MIN = 1.5`, `WP_NEAR = 6`, `STATE_TICKS = 30`, `GOAL_MOVE = 2`, `LOOKAHEAD = 18`, `LOOK_STEP = 2`, `SIDE = 1.5`,
`DETOUR_RADII = {30, 15, 8}`, `DETOUR_ANGLES = {30, -30, 60, -60, 90, -90}`, `DETOUR_REACHED = {10, 6, 6}` (je Umweglänge), `DETOUR_MAX = 900`, `REROUTE_MAX = 1`, `HOLD_MAX = 300`,
`STALL_TICKS = 300`, `STALL_DIST = 0.5`, `ATTACK_RANGE = 40`, `ATTACK_LEAVE = 50`, `BEHIND = 20`, `BEHIND_MIN = 6`, `SEARCH_REACHED = 8`, `DUST_PER_NODE = 2`,
`BOOST_MIN = 0.9`, `BOOST_TAKTS = 2`, `PUSH_MAX = 0.4` (Kacheln je Takt), `TIDY_AGE = 600` (Ticks).

`scripts.worms` bekommt dazu: `set_worm_off(force, on)`, `set_spawn_dir(force, k|nil)`, `migrate_schema4(opts)`, `hunt_log() → storage.hunts.log`
(Haken, 4.18), Konstanten `BITE_REACH = 3`, `BITE_WINDOW = 180`, `CRUSH_RADIUS = 2.5`, `ZONE_RADIUS = 5` (= `BITE_RADIUS + 1`), `MAX_DEBUG_WORMS = 3`,
`LOG_SIZE = 20`. `start_hunt`-Optionen zusätzlich `spawn = {position, direction, tick|nil}` und `spawn_dir = k` (nur Prüfstand, 4.18).

Neue Ereignisse (Handler prüfen zuerst, ob es ihr Fall ist, und kehren sonst zurück):

| Ereignis | sandworm.lua | worms.lua |
|---|---|---|
| `on_script_path_request_finished` (A23 events.d.ts:4398; A20 :4157) | nur Kennungen in `storage.path_requests`: Weg übernehmen, neu fragen oder nächster Kandidat (4.5) | – |
| `on_segmented_unit_died` (A23 events.d.ts:4556; A20 :4329) | – | eigener Wurm einer Jagd: Ende `killed` (4.11) |
| `script_raised_destroy_segmented_unit` (A23 events.d.ts:5305; A20 :5128) | – | Wurm einer Jagd: Phase `ohne`, `"verloren"` (4.11). Unser eigenes Abtauchen leert `hunt.worm` vorher und kommt hier nie an |
| `on_pre_surface_cleared` (A23 events.d.ts:3926; A20 :3658) | – | neu: jede Jagd dieser Oberfläche `end_hunt(hunt, nil, "abort")`, solange Ziel und Wurm noch da sind (der Wurm taucht still ab) |

Unverändert aus 0.7.0 (P3D1 4.1), mit diesen Zusätzen: `on_entity_died` usw. lösen auch Zerdrücken und Biss aus; Ziele laufender Jagden zerdrückt der Wurm
nie (4.10), also bleibt `on_target_removed` (scripts/worms.lua:1100–1108) richtig. `on_pre_surface_deleted` (:1197–1203): Ende `"abort"`, dabei verschwindet
der Wurm (4.11). Eine geleerte Oberfläche kannte worms in 0.7.0 nicht (nur vibration.lua:951 hört auf `on_surface_cleared`): Ziel und Wurm verschwänden
ohne Ereignis, die Jagd ginge „verloren“, und bei 0 bräche eine Eruption auf der leeren Fläche hervor; deshalb der neue Handler oben. worms
`on_configuration_changed`: zusätzlich Migration Schema 4 und Waisen (4.14). `on_force_created` (:1163–1170) löscht zusätzlich `storage.hunts.worm_off[i]` und
`storage.hunts.spawn_dir[i]` (Indizes werden wiederverwendet); `on_forces_merging` (:1182–1191) addiert zusätzlich `killed` (nil-sicher wie die anderen
Zähler) und löscht `worm_off` und `spawn_dir` der Quelle; `stats_for` (:282–290) legt `killed = 0` mit an. Die Sekundenarbeit (`hunts_second`, :912) ruft
vor ihrer Rückkehr bei leerer Liste `sandworm.tidy(tick)`, wenn `storage.path_requests` nicht leer ist (4.5).
Der Runner leitet zusätzlich `on_segmented_unit_died` als `segmented_unit_died` und `script_raised_destroy_segmented_unit` als
`segmented_unit_destroyed` weiter (6).

`start_hunt` (scripts/worms.lua:414–473) setzt zusätzlich `r` (halbe Diagonale der Box, `LuaEntity.bounding_box`, A23 classes.d.ts:7662) und ruft am
Ende `sandworm.begin(hunt, opts)` (4.4). `end_hunt` (:477–507) ruft vor dem Austragen `sandworm.dive(hunt, "ende", mode == "abort")` und
schreibt den Protokolleintrag (4.16). `bite` (:657–740) wird zu Eruption + `devour(center, target, mode)` + Ende; `devour` (Sammeln, `settle`, Töten in
fester Reihenfolge, wie P3D1 4.9 Schritte 3 bis 5) benutzt auch das Zerdrücken (4.10). `miss` (:610–626) nimmt die Kopfposition, wenn es einen Wurm gibt.

### 4.2 storage (Schema 4)
```lua
storage.schema = 4
storage.path_requests[request_id] = {hunt = hunt_id, kind = "plan"|"reroute", sent = tick}   -- weg bei Antwort, Zeitablauf, Ende, to_none, tidy (4.5)
storage.hunts = {next_id, list, paused_until,               -- wie Schema 3
  worm_off = {[force_index] = true},                        -- nur Prüfstand (4.18)
  spawn_dir = {[force_index] = k},                          -- nur Prüfstand: Startrichtung auch regulärer Jagden (4.18)
  log = {[i] = eintrag}, log_next = 1, ersatz = 0}          -- 4.16
hunt = {…Schema 3 (P3D1 4.2)…,
  r = Kacheln,                                              -- halbe Diagonale der Zielbox beim Start; R = 3 + r
  phase = "warten"|"routing"|"anfahrt"|"angriff"|"suche"|"ohne",
  no_worm = nil|"aus"|"kurz"|"grenze"|"kein-weg"|"keine-force"|"migration"|"verloren"|"abgetaucht",
  dive = nil|"fels"|"stillstand"|"kein-weg"|"keine-force"|"suche"|"ende"|…,  -- Grund des Abtauchens (4.11), bleibt nach dem Abtauchen
  zone = {x, y},                                            -- Schutzpunkt dieses Takts (4.10)
  plan_tick, spawn_tick = tick|nil, d = D,
  plan = {k0, list = {{k, d}…}, next = i, checked = n, route_cands = {i…},
          chosen = {position, direction, route = {{x, y}…}, length, box = 3.5|1.5|nil}|nil, spawns = 0, paths = 0},
  path = {id, cand = i, tries = n, sent = tick, retry_tick = tick|nil, kind, box = 3.5|1.5}|nil,
  worm = {unit = LuaSegmentedUnit, un, spawned = tick, route = {{x, y}…}, wp = i,
          dest = {x, y}, set_tick = tick, set_dest = {x, y}, mode = activity_mode,
          detour = {x, y, tick, reached}|nil, reroutes = 0, hold_since = tick|nil, head = {x, y},
          moved = {x, y, tick}, detours = 0, samples = 0, rock_box = 0, vmax = 0, crushed = 0,
          sprint = 0, boost = 0|1|2, slow = 0}|nil,         -- Sprint-Takte, Ersatzstufe, Sprint-Takte in Folge zu langsam (4.9)
  bite_tick = tick|nil, bite_dist = Kacheln|nil, ersatz = true|nil,
  spawn_hook = {position, direction, tick|nil}|nil, spawn_dir = k|nil,   -- nur Prüfstand (4.18)
}
storage.worm_stats[force_index] = {bitten = 0, escaped = 0, gone = 0, killed = 0, first_escape_tick = nil}   -- stats_for legt killed mit an
```
`migrate.init()` legt `path_requests`, `hunts.worm_off`, `hunts.spawn_dir`, `hunts.log`, `hunts.log_next` und `hunts.ersatz` an. Abweichungen von DOC 4.5: statt
`spawn_tick, candidates, spawn, path_request, route, worm` die Felder oben; `path_requests` mit Art und Sendetick statt nur der Jagd; `worm` ist ein
Datensatz um die `LuaSegmentedUnit` [W11].

### 4.3 Lebenslauf der Jagd: Phasen, Takte, Übergänge
`state` (warning/biting/searching) bleibt wie 0.7.0 und steuert Anzeige und Ende. `phase` sagt, was der Wurm tut. worms `on_nth_tick(10)` (kehrt sofort
zurück, wenn `storage.hunts.list` leer ist), in dieser Reihenfolge:
1. Für jede Jagd `zone` = Zielpunkt P (Festlegung „Zielpunkt“) und die Menge der Ziel-`unit_number`s, alles vor dem ersten Zerdrücken dieses Takts.
2. Je Jagd nach `id` (scripts/worms.lua:756 `sorted_ids`):
   a. `state == "warning"`: `track(hunt, tick)` wie 0.7.0 (:555–607).
   b. Phase `warten`, `routing`, `anfahrt`, `angriff` oder `suche` mit Wurm: `sandworm.step(hunt, tick, worm_force)` (4.4 bis 4.9, 4.11); kann auf `ohne`
      wechseln. `worm_force` holt worms einmal je Takt vor der ersten solchen Jagd (Festlegung „Force“); ohne Force `to_none(hunt, "keine-force")`
      (ein vorhandener Wurm taucht ab).
   c. Mit Wurm: Zerdrücken (4.10).
   d. `state == "warning"` und `tick ≥ eta_tick`: Biss-Fenster (4.9).
   e. `state == "searching"` und `tick ≥ end_tick`: `end_hunt(hunt)` (taucht einen verbliebenen Wurm ab).

| Phase | Beginnt | sandworm tut je Takt | Weiter |
|---|---|---|---|
| `warten` | beim Start (`begin`) | nichts | `tick ≥ plan_tick` → `routing` |
| `routing` | `plan_tick` | Kandidaten prüfen (8 je Takt), sonst Wege anfragen (4.5); mit gewähltem Kandidaten bis `spawn_tick` warten, dann erzeugen (4.6) | erzeugt und Körper gut → `anfahrt`; kein Kandidat, kein Weg, 3 Fehlversuche oder `tick ≥ eta_tick − 1440` ohne Wurm → `ohne` (`"kein-weg"`) |
| `anfahrt` | Spawn | Steuern (4.7), Wächter (4.8), Sprint, wenn zu spät (4.9) | kein Wegpunkt und kein Umweg offen, Abstand Kopf–P ≤ 40 und Linie Kopf → Reichweitenpunkt Sand → `angriff` |
| `angriff` | siehe oben | Ziel hinter P, Drosseln, Halten, nach 0 Sprint (4.9); Wächter nur bis zum Reichweitenpunkt | Abstand > 50, Umweg oder neue Route → `anfahrt` |
| `suche` | Fehlbiss (`miss`) | fährt zu P (`last_pos`, am Kreis geklemmt), Wächter | Kopf ≤ 8 Kacheln von P → abtauchen (Phase bleibt `suche`, ohne Wurm) |
| `ohne` | kein Wurm | – | – (Biss bei 0 wie 0.7.0) |

Übergänge von außen, in jeder Phase mit Wurm: Kopf auf Fels, in ungeneriertem Chunk, Stillstand oder kein Weg nach Umweg und Neuplanung → abtauchen,
vor dem Biss Phase `ohne` (`"abgetaucht"`), in der Suche bleibt `suche`; Wurm ungültig oder fremd zerstört → `ohne` (`"verloren"`); Wurm getötet → Ende `killed`.
Ende einer Jagd (jede Art, P3D1 4.7 „Ende“) → Wurm abtauchen, Anfragen weg.

**Wechsel auf `ohne`** (jeder Grund, auch `"kein-weg"` an der Frist, `"keine-force"`, `"verloren"`, `"abgetaucht"`) geht immer über
`to_none(hunt, why, dive_why)`: ein vorhandener gültiger Wurm taucht ab (`dive(hunt, dive_why or why)`), `drop_requests(hunt)`, `hunt.path = nil`,
`phase = "ohne"`, `no_worm = why`. In der Suche räumt dieselbe Funktion ebenso auf, lässt aber die Phase `suche` stehen. Damit gilt in Phase `ohne`
immer `hunt.worm == nil`, `hunt.path == nil` und kein Eintrag in `storage.path_requests`; eine späte Antwort findet keinen Eintrag mehr (4.5), und
kein Wurm fährt ohne Steuerung bis zum Ende der Jagd weiter. **Lebensdauer:** Jeder Wurm endet spätestens mit seiner Jagd, und die endet spätestens
bei `eta + 180` (Biss oder Ersatzbiss) bzw. `end_tick = eta + 600` (Suche); Waisen ohne Jagd räumt jeder `on_configuration_changed` (4.14).

**Zeitlinie, 60 s, freier Sand** (Ticks relativ zum Wurmzeichen w, `eta = w + 3600`): w + 370 Planung (ein Takt), w + 670 Spawn 160 Kacheln entfernt,
Anfahrt mit 3,5 Kacheln/s, bei Abstand 40 (w + 2730) Angriff mit etwa 2,4 Kacheln/s, Ankunft in Reichweite kurz vor `eta`, halten, Biss bei `eta`, Abtauchen
im selben Takt. Der Wurm lebt 48,8 s; mit Suche höchstens 58,8 s, mit Ersatzbiss 51,8 s. Lehrjagd: Spawn bei w + 2470, sonst gleich.

### 4.4 Spawnplanung
`sandworm.begin(hunt, opts)` beim Start der Jagd (Schritt 1), die Planung selbst in `routing` (Schritte 3 bis 6):
1. **Wurm oder nicht:** `storage.hunts.worm_off[force_index]` → `ohne`, `"aus"`; `T = (eta_tick − warn_tick) / 60 < 27` → `ohne`, `"kurz"`;
   Befehlsjagd (`debug`) und `counted(true) ≥ MAX_DEBUG_WORMS` → `ohne`, `"grenze"`; reguläre Jagden prüfen keine Zahl (höchstens 3, P3D1 4.5).
   Sonst `phase = "warten"`.
2. **Zeiten:** `D = min(160, 3,5 · (T − 4))`, also D ≥ 80 genau ab T ≥ 26,86 s. Nennspawn `s0 = eta − ceil((D / 3,5 + 3) · 6) · 10`,
   `plan_tick = max(⌈(warn_tick + 10) / 10⌉ · 10, s0 − 300)`. Beispiele: T = 60 (D 160): `s0 = eta − 2930`, `plan_tick = eta − 3230 = w + 370`;
   T = 90: `s0 = eta − 2930 = w + 2470`, `plan_tick = w + 2170`; T = 40 (D 126): `s0 = eta − 2340 = w + 60`; T = 27 (D 80,5): `s0 = eta − 1560 = w + 60`,
   `plan_tick` im ersten Takt nach dem Start. Frist: ohne Wurm bis `eta − 1440` (80 Kacheln mit 1 s Reserve: `ceil((80 / 3,5 + 1) · 6) · 10`) → `ohne`.
3. **Kandidaten** (beim ersten `routing`-Takt): Abstände D, dann 120 und 80, soweit sie mindestens 10 Kacheln kleiner als D sind; je Abstand die
   16 Richtungen k in der Reihenfolge k0, k0 + 1, k0 − 1, k0 + 2, …, k0 + 8 (mod 16). Lage `c = P + d · (sin θ, −cos θ)` mit θ = 22,5° · k (defines.direction:
   north = 0, im Uhrzeigersinn, east = 4, A23 defines.d.ts:416), Blickrichtung `(k + 8) mod 16` (der Kopf zeigt auf P), der Körper liegt dahinter (T7).
   k0: `local v = target.valid and target.speed` (`speed` ist nil außer bei Auto, Schienenfahrzeug, Einheit, Projektil und Spidertron, A23
   classes.d.ts:8519–8523); fährt das Ziel (`v ~= nil` und `math.abs(v) ≥ 0,001`), dann `floor(o · 16 + 0,5) mod 16` mit `o = target.orientation` (:8241,
   0 = Norden, im Uhrzeigersinn), rückwärts (`v < 0`) `o + 0,5`: Der Wurm kommt ihm entgegen. Sonst `storage.rng(0, 15)` (A23 classes.d.ts:17436–17439,
   Grenzen einschließlich). Prüfstand: `opts.spawn_dir`, sonst `storage.hunts.spawn_dir[force_index]` (auch für reguläre Jagden, 4.18); ein Haken geht
   vor Fahrtrichtung und Zufall (T21 Schritt 12 braucht k0 = 2, auch wenn der Ernter bei der Planung schon fährt).
4. **Prüfen** (höchstens 8 Kandidaten je Takt): „Sand“ heißt `terrain.natural_tile_name(surface, x, y) ~= "arrakis-rock"` (scripts/terrain.lua:30–33) und
   `surface.is_chunk_generated{floor(x / 32), floor(y / 32)}` (A23 classes.d.ts:20707). (a) Spawnpunkt und Körperlinie: c und die Punkte 4, 8, 12, 16, 20 Kacheln
   weiter weg von P (die Lagen der Knoten 1, 5, …, 21), dazu `surface.count_entities_filtered{area = Rechteck um c und den Punkt 20 dahinter, 4 Kacheln
   größer, type = {"character", "car", "spider-vehicle", "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon"}, limit = 1} == 0` (A23
   classes.d.ts:20220; eine Figur im Fahrzeug findet die Suche nicht, das Fahrzeug schon): Auf Fahrzeugen und Figuren taucht er nicht auf.
   (b) Sandlinie: Punkte alle 4 Kacheln von c Richtung P bis 6 Kacheln vor P (die letzten Kacheln gehören zum Haltepunkt; das Ziel selbst darf mit der
   Mitte auf Fels stehen, solange eine Ecke Sand berührt). (a) und (b) gut → gewählt, Weg leer, L = d. Nur (b) schlecht → Wegkandidat (4.5). (a) schlecht →
   verworfen.
5. **Gewählt:** `spawn_tick = max(nächster Takt, eta − ceil((L / 3,5 + 3) · 6) · 10)`. Ein späterer Kandidat mit kleinerem d spawnt entsprechend später.
6. **Kein Kandidat gültig** (alle 48 geprüft, höchstens 6 Takte): ROUTING mit den Wegkandidaten (4.5); keiner da → `ohne`, `"kein-weg"`.

Prüfstand-Haken `opts.spawn = {position, direction, tick}`: kein Prüfen, `chosen = {position, direction, route = {}, length = |position − P|}`,
`spawn_tick = opts.spawn.tick` oder nach Schritt 5; Körperprüfung (4.6) gilt trotzdem, ohne weitere Kandidaten.

### 4.5 ROUTING mit `request_path`
Nur aus Schritt 6 (Planung) oder aus dem Wächter (Neuplanung vom Kopf, 4.8). Je Jagd läuft höchstens eine Anfrage; insgesamt höchstens 2 für die Planung
und 1 Neuplanung. Wegkandidaten in der Reihenfolge kürzester Abstand zuerst (80, 120, D), darin wie die Liste: Ein kürzerer Start gibt einen kürzeren Weg,
und der muss in die Restzeit passen.
```lua
local b = box                                        -- 3.5 (PATH_BOX) oder 1.5 (PATH_BOX_MIN), siehe unten
local id = surface.request_path{                     -- A23 classes.d.ts:20777, Parameter :20760–20790; A20 :31833
  bounding_box = {{-b, -b}, {b, b}},                 -- Körper ±2,28 (3 · 1,52 · 0,5, V23 enemies.lua:1379, :286–328) plus Spiel; Kopf ±1,5 (:485)
  collision_mask = {layers = {arrakis_rock = true}}, -- nur Fels (prototypes/tiles.lua:13; CollisionMask concepts.d.ts:1797)
  start = c,                                         -- Kandidat bzw. Kopf
  goal = P, force = worm_force,                      -- LuaForce aus worms (Festlegung „Force“)
  radius = 8,                                        -- fertig 8 Kacheln vor P
  path_resolution_modifier = -2,                     -- Raster 4 × 4 Kacheln
  pathfind_flags = {prefer_straight_paths = true, cache = false}   -- PathfinderFlags concepts.d.ts:7582
}
storage.path_requests[id] = {hunt = hunt.id, kind = "plan", sent = tick}
hunt.path = {id = id, cand = i, tries = 1, sent = tick, kind = "plan", box = b}
```
Der Aufruf läuft in `pcall`: Ein Fehler (etwa eine Box, die der Pfadfinder ablehnt) schreibt eine Logzeile und zählt wie eine Antwort mit `path == nil`
(unten), es entsteht kein Eintrag.
`cache = false`: Die Kacheln können sich ändern (Bau, Prüfstand), und jede Jagd fragt neu. Entities zählen nicht (Maske nur Fels): Gebäude im Weg zerdrückt
der Wurm, Fahrzeuge und Figuren fährt er nach [W10] an. **Box:** erst ±3,5, damit der Weg dem breiteren Körper und dem Wenderadius Platz lässt; liegt im Quadrat
±3,5 um den Start eine Felskachel (dann stünde der Pfadfinder schon am Start im Fels), oder kommt mit ±3,5 `path == nil`, einmal mit ±1,5 (zählt nicht zu
`PATH_MAX`). Die Neuplanung startet am Kopf: Er steht auf Sand (sonst hätte das Sicherheitsnetz in 4.8 schon abgetaucht).

**Antwort** (`on_script_path_request_finished`, A23 events.d.ts:4398 mit `id`, `path?`, `try_again_later`) [W4]: Eintrag zu `id` holen und löschen; fehlt er
oder ist `hunt.path.id ~= id` (Jagd vorbei, neu gefragt), nichts tun.
- `try_again_later` → `retry_tick = tick + 60`; der Takt fragt dann neu (gleicher Kandidat, `tries + 1`); nach 5 Versuchen wie Fehlschlag.
- `path == nil` mit Box ±3,5 → einmal mit ±1,5 neu fragen (oben „Box“); sonst Fehlschlag: nächster Wegkandidat, sonst `ohne` (`"kein-weg"`); bei der
  Neuplanung: abtauchen.
- Weg da (`PathfinderWaypoint`s, concepts.d.ts:7608): jede Strecke zwischen zwei Wegpunkten alle 2 Kacheln auf Sand prüfen (natürliche Kachel und
  generierter Chunk); gepflasterter Fels hat die Ebene `arrakis_rock` nicht, der Pfadfinder hält ihn für frei → Fehlschlag. Dann nach Sichtlinie ausdünnen:
  Ein Wegpunkt fällt weg, wenn die Strecke vom letzten behaltenen Wegpunkt (anfangs c) zum Wegpunkt danach Sand ist (Mittellinie und Parallelen ±1,5, alle
  2 Kacheln); sonst bleibt er. So schneidet keine Sehne eine innere Felsecke, die der Pfadfinder umfahren hat. Der letzte bleibt; P kommt nicht in die
  Liste (es wandert). Länge L = Summe der Strecken plus Abstand letzter Wegpunkt–P. Passt `L / 3,5 + 1 ≤ (eta − tick) / 60` (Neuplanung in der Suche:
  `end_tick` statt `eta`, Gegenprüfung 0.8.0; an `eta` gemessen passte dort nie ein Weg), gilt der Weg: Planung
  `chosen = {c, Blickrichtung auf den ersten Wegpunkt (auf 16 Richtungen gerundet), route, L}`, `spawn_tick` nach 4.4 Schritt 5; Neuplanung: `worm.route`
  ersetzen, `wp = 1`, Halten endet, im Angriff zurück in die Anfahrt. Passt er nicht → Fehlschlag.
- **Zeitablauf:** `sent + 300 ≤ tick` ohne Antwort (auch nach Speichern und Laden, [W5]) → Eintrag löschen, nur wenn er noch zu dieser Jagd gehört
  (`path_requests[id].hunt == hunt.id`; nach dem Laden kann die Engine eine Kennung neu vergeben haben), und neu fragen (`tries + 1`); nach 5 Versuchen
  wie Fehlschlag.
- **Aufräumen:** `tidy(tick)` (aus der Sekundenarbeit von worms, auch ohne laufende Jagd, 4.1) löscht jeden Eintrag, dessen Jagd fehlt, deren
  `hunt.path` nicht mehr auf ihn zeigt oder dessen `sent` mindestens `TIDY_AGE = 600` Ticks zurückliegt. So bleibt kein Eintrag liegen, auch wenn eine
  Antwort nie kommt [W5].
- Planung mit gewähltem Weg und Blickrichtung nicht auf P: Körperlinie (4.4 Schritt 4 a) für diese Richtung noch einmal prüfen; schlecht → Fehlschlag.

### 4.6 Erzeugen, Körperprüfung, Auftauchen
Im ersten Takt mit `tick ≥ spawn_tick` (Phase `routing`, `chosen` gesetzt):
```lua
local unit = surface.create_segmented_unit{name = "arrakis-sandworm-small", position = c, direction = dir,
  extended = true, force = worm_force}               -- A23 classes.d.ts:20316, :22143–22160, :22175–22188; A20 :31182
```
Ohne `territory` patrouilliert er um den Spawn (:22157); deshalb führt das Skript den Zustand nach (4.7). `extended = false` erzeugte nur den Kopf (:22183).
1. `nil` oder Fehler [W14] (der Aufruf läuft in `pcall`, ein Fehler schreibt eine Logzeile) → `spawns + 1`, weiter mit dem nächsten Kandidaten der Liste
   (Prüfung nach 4.4, neues `spawn_tick`; liegt es in der Vergangenheit, im nächsten Takt, wenn `L / 3,5 + 1 ≤ Restzeit`).
2. Körperprüfung: `nodes = unit.get_body_nodes()` (A23 classes.d.ts:19021, vorne zuerst, Kopie); `for i = 1, #nodes, 4` Sand und generierter Chunk. Ein Fehler →
   `unit.destroy{}` (ohne `raise_destroy`: niemand hat ihn gesehen), `spawns + 1`, nächster Kandidat wie 1. Nach 3 Erzeugungen → `ohne` (`"kein-weg"`).
3. Gut: `hunt.worm = {unit, un = unit.unit_number (:19121), spawned = tick, route, wp = 1, …}`, `unit.minimum_activity_mode =
   defines.segmented_unit_activity_mode.minimal` (:19087, defines.d.ts:2253), `unit.speed = 3.5 / 60` [W1] (:19105), `set_ai_state` (4.7), Phase `anfahrt`.
4. **Auftauchen:** je Knoten 1, 5, …, 21 zwei `surface.create_trivial_smoke{name = "arrakis-sand-dust", position}` (A23 classes.d.ts:20331) an festen Versätzen aus
   Tick und Knotennummer (Muster scripts/vibration.lua:595–605, kein Zufall), `surface.create_entity{name = "arrakis-worm-dive", position = Kopf}` (:20294),
   `surface.play_sound{path = "arrakis-rumble", position = Kopf}` (:20719).
5. **Zerdrücken beim Auftauchen:** worms zerdrückt im selben Takt (4.3 Schritt 2 c) einmal an jedem vierten Knoten nach 4.10, danach nur noch am Kopf. Fahrzeuge
   und Figuren liegen dort nach 4.4 Schritt 4 (a) nicht; Bänder und Gebäude unter dem Körper blieben sonst im Wurm stehen.

### 4.7 Steuern: Ziel, Zustand, Wegpunkte
- Kopf = `nodes[1]`, Kopfrichtung h = normiert `nodes[1] − nodes[3]` (DOC 4.3, wie T6). `LuaSegment.position` wäre teuer (A23 classes.d.ts:18946); ein
  `get_body_nodes()` je Takt und Wurm reicht für Kopf, Richtung und Abtauchen. `worm.head` merkt die letzte Kopfposition (Chat bei Tod, Fehlbiss).
- **Fahrziel** `dest`, in dieser Rangfolge: Umwegpunkt (4.8); nächster Wegpunkt der Route; sonst nach Phase: `anfahrt` P, `angriff` Punkt 20 bzw.
  6 Kacheln hinter P (4.9), `suche` P. Zum folgenden Wegpunkt (bzw. nach dem letzten zu P) wechselt er, sobald die Strecke Kopf → dorthin frei ist
  (Mittellinie und ±1,5 alle 2 Kacheln, wie die Vorausschau), spätestens 6 Kacheln vor dem aktuellen (`WP_NEAR`, mehr als die 4 Kacheln aus T5 a); ist die
  Strecke dann nicht frei, greift der Wächter (4.8).
- **Zustand:** `unit.set_ai_state{type = defines.segmented_unit_ai_state.investigating, destination = dest}` (A23 classes.d.ts:19031, concepts.d.ts:9133,
  defines.d.ts:2267), wenn `dest` sich um mehr als 2 Kacheln gegenüber `set_dest` bewegt hat, und sonst in jedem Takt mit `tick − set_tick ≥ 30`, auch wenn
  `get_ai_state` schon `investigating` sagt [W9]. Erreicht er `dest` bis auf 4 Kacheln, wechselt die Engine auf `patrolling` und rollt weiter (T5 a: 3,1
  bis 1,1 Kacheln/s, 6,1 Kacheln über das Ziel hinaus). Deshalb liegt jedes Fahrziel weiter als 4 Kacheln vor dem Punkt, an dem er halten oder wechseln soll:
  Wegpunkt 6 (`WP_NEAR`), Umweg 10 bzw. 6, Suche 8, Angriff mindestens 6 hinter P (also mindestens R + 6 vom Haltepunkt, auch bei R unter 4).
- **Aktivität:** `minimum_activity_mode` `minimal` in `anfahrt` und `suche`, `full` in `angriff`; nur bei Wechsel schreiben (`worm.mode`). Das ist nur
  eine Untergrenze (A23 classes.d.ts:19087); in `investigating` fährt die Engine ohnehin full (T5 a: 35 von 35 Messungen) [W13]. Höchstens 6 Würmer
  gleichzeitig (Grenze).

### 4.8 Fels-Wächter, Umweg, Neuplanung, Stillstand
In jedem Takt mit Wurm (Phasen `anfahrt`, `angriff`, `suche`), vor dem Tempo:
1. **Sicherheitsnetz:** Chunk des Kopfes nicht generiert oder natürliche Kachel unter der Kopfmitte Fels → `dive(hunt, "fels")`. Vor dem Biss Phase `ohne`
   (`"abgetaucht"`), sonst bleibt `suche`.
2. **Haltepunkt** je Fahrziel: P im Angriff und in der Anfahrt (Abstand R), P in der Suche (8), Wegpunkt (6), Umwegpunkt (10 bzw. 6). Länge der Vorausschau
   `L_v = min(18, Abstand(Kopf, dest) − Halteabstand)`; ≤ 0 → nichts zu prüfen.
3. **Vorausschau:** Strecken Kopf → Kopf + h · L_v und Kopf → Kopf + L_v · (dest − Kopf)/|dest − Kopf|, je die Mittellinie und zwei Parallelen im Abstand ±1,5,
   Punkte alle 2 Kacheln, „frei“ = Sand nach 4.4 Schritt 4. Im Angriff nur die Mittellinie Kopf → Reichweitenpunkt (P − R · u, u = Einheitsvektor Kopf → P):
   DOC 4.3 „nie darüber hinaus“, und neben einem Ziel an der Felskante läge die Parallele schon im Fels. Den Angriff gibt es nur ohne offene Wegpunkte und mit
   freier Linie (4.9); solange Wegpunkte offen sind, gilt die Vorausschau der Anfahrt mit dem Haltepunkt am Wegpunkt. Während eines Umwegs nur die Strecken
   zum Umwegpunkt.
4. **Umweg**, wenn etwas nicht frei ist: für die Längen 30, 15, 8 Kacheln nacheinander und darin a in 30, −30, 60, −60, 90, −90 Grad: Punkt Kopf + Länge ·
   rot(h, a); die Strecke dorthin (Mittellinie und Parallelen, alle 2 Kacheln) frei → `detour = {Punkt, tick, reached}`, `dest` neu, Zustand sofort setzen,
   `detours + 1`; im Angriff zurück in `anfahrt`. Der Umweg endet bei 10 (30er) bzw. 6 Kacheln Nähe (15er, 8er) oder nach 900 Ticks (T6). Werte für 30 wie
   T6 C, dort ohne Parallelen und mit Schritt 4 für die Umweglinie; die kurzen Umwege passen in Gänge, in denen 30 Kacheln immer im Fels enden [W17].
5. **Kein Umweg:** erste Neuplanung (`REROUTE_MAX = 1`): `request_path` vom Kopf nach P (4.5, Art `reroute`, Box wie dort), währenddessen halten (Tempo 0
   je Takt, [W2]), höchstens 300 Ticks. Weg da → neue Route. Fehlschlag, Zeitablauf oder zweites Mal → `dive(hunt, "kein-weg")`. Gegenprüfung 0.8.0:
   Passt nicht einmal ein Weg der Länge 0 mehr in die Frist (unter 1 s bis `eta`, in der Suche bis `end_tick`), fragt er nicht und hält nicht, sondern taucht
   gleich ab (`"kein-weg"`); eine offene Neuplanung endet dann ebenso. Ohne Wurm beißt es bei 0 wie 0.7.0, nach 0 im selben Takt (Biss-Fenster).
6. **Stillstand:** nicht haltend und seit 300 Ticks weniger als 0,5 Kacheln von `moved` → `dive(hunt, "stillstand")`. `moved` wird bei jeder Bewegung über
   0,5 Kacheln neu gesetzt. 0.8.1 [W18]: Knoten 1 springt im Kachelraster, „über 0,5“ heißt also „ein Knotensprung“. Gezählt wird nur, wenn das geschriebene
   Tempo (ohne Schreiben 3,5) ihn seit dem letzten Sprung mindestens 1,5 Kacheln weit getragen hätte (`moved.want`); sonst tauchte ein Wurm ab, der vor der
   Zeit langsam fährt (v = S / t unter 0,2 Kacheln/s, etwa nach dem Halten), weil Knoten 1 dabei länger als 300 Ticks nicht springt (Trockenlauf 0.8.1,
   D7 „früh“). Ab derselben Schwelle steht der wahre Kopf bis 1 Kachel vor Knoten 1 an etwas an: `worm.front` = Knoten 1 + 1 · h, dort zerdrückt er auch (4.10).
7. **Messung** (für T21 und das Protokoll): `samples + 1`; berührt die Kopfbox ±1,5 eine Felskachel (vier Ecken und Mitte), `rock_box + 1`; `vmax` = größtes
   `unit.speed · 60`.

### 4.9 Anfahrt, Angriff, Drosselung, Sprint und Biss-Fenster
Bezeichnungen: R = 3 + r; d = Abstand Kopf–P; Restzeit t = (eta − tick) / 60 s; Restweg S = Weg Kopf → offene Wegpunkte → P minus R; v in Kacheln/s,
geschrieben als `unit.speed = v / 60` (A23 classes.d.ts:19105, schreibbar ≥ 0; ohne Eingriff beschleunigt er zurück auf `target_speed` :19113, um 0,092 Kacheln/s
je 10 Ticks).
- **Anfahrt:** S / 3,5 ≤ t − 1 → nichts schreiben (die Engine fährt 3,5). Sonst Sprint: `v = min(6, S / max(t − 1, 1/6))` [W3]. Kein Wegpunkt und kein
  Umweg offen, d ≤ 40 und die Mittellinie Kopf → Reichweitenpunkt frei (4.8 Schritt 3) → `angriff`. Mit offenen Wegpunkten bleibt er in der Anfahrt, auch
  wenn d schon kleiner ist: Die gerade Linie zu P schnitte dann den Fels, um den die Route führt.
- **Angriff:** Fahrziel B = P + 20 · u, wenn die Punkte alle 2 Kacheln von P bis B Sand sind (dann fährt er durch und bremst nicht vorher, DOC 4.3 Schritt 5),
  sonst P + 6 · u, auch wenn dort Fels liegt (4.7 „Zustand“; der Wächter prüft im Angriff nur bis zum Reichweitenpunkt, gehalten wird über das Tempo).
  `minimum_activity_mode = full`. Vor 0: S ≤ 0 → v = 0 (halten, [W2]), sonst `v = min(6, S / t)`; ohne offene Wegpunkte ist S = d − R. Ab 0: v = 6 bis
  zum Biss. d > 50, ein Umweg (4.8 Schritt 4) oder eine neue Route (Neuplanung) → `anfahrt`.
  Beispiel 60 s auf freiem Sand: Abstand 40 nach (160 − 40) / 3,5 = 34,3 s Fahrt, Restzeit 14,5 s, v = (40 − 4,58) / 14,5 = 2,4 Kacheln/s. Weil die Engine
  zwischen zwei Schreibvorgängen um bis zu 0,09 Kacheln/s beschleunigt, kommt er knapp vor 0 an und hält.
- **Sprint-Ersatz** [W3]: Ein Sprint-Takt ist jeder Takt, in dem das Skript v über 3,5 schreibt (`worm.sprint + 1`). Gemessen wird über die Spur
  `worm.trail` (0.8.1, W18): je Takt der Weg von Knoten 1 seit dem letzten Takt, das im Takt davor geschriebene v und der Schub des Takts davor, die letzten
  `SPEED_TAKTS = 30` Takte. Knoten 1 springt im Kachelraster und liegt bis zu `NODE_STEP = 1` Kachel hinter dem wahren Kopf; ein Takt allein zeigt bei
  6 Kacheln/s nur 0 oder 6 (Prüfstand 2026-10-27, T21), über ein Fenster bleibt der Fehler des Wegs unter 1 Kachel. `worm.slow` zählt einen Sprint-Takt,
  wenn der Weg im Fenster (die letzten `worm.judge` Sprint-Takte, höchstens 30) samt Schub auch mit dem Rasterfehler unter `BOOST_MIN = 0,9` des geschriebenen
  Wegs bleibt: Weg + 1 < 0,9 · Σ v / 6. So zählt kein Takt, in dem die Engine das Tempo hält; ein Wurm, der nur 3,5 fährt, fällt nach etwa 7 Sprint-Takten
  auf. Jeder andere Takt setzt `slow` auf 0. Steht der Kopf (2 Takte ohne Knotensprung, wahr unter 3 Kacheln/s, also unter 3,5), zählt das nicht als
  Sprintversagen (Sache des Stillstands, 4.8 Schritt 6), und das Fenster beginnt neu. Nach `BOOST_TAKTS = 2` gezählten Takten hintereinander steigt
  `worm.boost` um 1 (höchstens 2, nie zurück, je Stufe eine Logzeile mit den Tempi im Fenster), das Fenster beginnt neu. Bis 0.8.0 verglich er den Weg eines
  Takts und hätte im Raster nie gegriffen (0 zählte als Stehen, 6 nie als zu langsam). Stufe 1: zusätzlich je Sprint-Takt `unit.move_forward(Δ)` (A23
  classes.d.ts:19026, A20 :28085) mit Δ = min(0,4, (v − Tempo der Engine) · 10 / 60) Kacheln (`PUSH_MAX`); das Tempo der Engine ist der Weg ohne die
  eigenen Schübe über die letzten `MEAN_TAKTS = 12` Sprint-Takte (bei weniger als 6 solchen Takten 3,5). `worm.v_head` ist das Kopftempo der letzten
  12 Takte für Protokoll und Prüfstand. Stufe 2: statt `move_forward` die Knotenkette selbst schieben: `set_body_nodes`
  (A23 classes.d.ts:19040, A20 :28130, in `pcall`, ein Fehler schreibt eine Logzeile und der Takt schiebt nicht) mit einem neuen Kopf Δ + Vorsprung
  Kacheln vor Knoten 1 längs der Richtung zu `dest` und den übrigen Knoten im Abstand 1 längs der alten Spur (der letzte fällt weg), höchstens bis
  6 Kacheln/s insgesamt. Vorsprung (0.8.1, Gegenprüfung): Hat der Takt davor geschoben, stand der Kopf danach auf `worm.push_head` (der zuletzt gesetzte
  Kopf, ohne Migration), und die Engine fuhr ihn seither etwa v_now / 6 weiter (v_now = `unit.speed` · 60 vor dem Schreiben dieses Takts); Knoten 1 kam
  davon nur in ganzen Kacheln mit [W18]. Vorsprung = v_now / 6 − |Knoten 1 − `push_head`|, begrenzt auf 0 bis 0,99 Kacheln; ohne Schub im Takt davor 0. Er ist Weg der
  Engine, kein Schub: Als Schub des Takts zählt weiter Δ. Ohne ihn setzte jeder Schub den Kopf auf den nachhinkenden Knoten 1 zurück, der Weg der Engine
  ginge verloren, und der Wurm führe mit dem Schub allein 0,4 Kacheln je Takt (2,4 Kacheln/s), langsamer als ganz ohne Schub (Trockenlauf: Ersatzbiss
  mit Abstand 68 statt Biss bei eta + 0). Das hängt an W20 (der gesetzte erste Knoten ist danach der Kopf) und am Setzen der Knoten selbst; der Wächter
  prüft den neuen Kopf im selben Takt. `sprint` und `boost` stehen im Protokoll (4.16).
- **Biss-Fenster** (worms.lua, Schritt 2 d in 4.3), mit Wurm:
  1. Regeln nach P3D1 4.7 Schritte 1 bis 4 (`decide` ohne Wirkung, scripts/worms.lua:743–753) → nicht beißbar: `miss(hunt, outcome, Kopf)` (Eruption am Kopf,
     Chat wie 0.7.0), `state = "searching"`, `end_tick = eta + 600`, Phase `suche`.
  2. Beißbar und Abstand Kopf–Zielmitte ≤ R → `bite(hunt)` wie P3D1 4.9 an der Zielmitte; `bite_tick`, `bite_dist`; das Ende taucht den Wurm ab.
  3. Beißbar, nicht in Reichweite, `tick < eta + 180` → warten (Sprint läuft).
  4. `tick ≥ eta + 180` → **Ersatzbiss**: `bite(hunt)` an der Zielmitte, `ersatz = true`, `storage.hunts.ersatz + 1`, `log("Arrakis: Ersatzbiss …")` mit Jagd,
     Abstand und Phase; das Ende taucht den Wurm dort ab, wo er ist.
  Ohne Wurm (Phase `ohne`, auch nach Abtauchen oder Verlust): `decide(hunt)` im ersten Takt mit `tick ≥ eta`, wie 0.7.0 (Eruption an `last_pos` bzw. `warn_pos`).
  Damit gilt immer `eta ≤ bite_tick ≤ eta + 180`; ohne Wurm `bite_tick = eta`.
- Warum ein Wurm zu spät sein kann: Umwege und Neuplanung, ein Ziel, das schneller als 3,5 Kacheln/s davonfährt, aber noch in Reichweite (`reach`) bleibt.
  Ein Auto, das mit 20 Kacheln/s im Kreis fährt, erwischt so erst der Ersatzbiss bei 0 + 3 s, an der Stelle, an der es dann ist (wie 0.7.0 bei 0).
  Der häufigste Fall ist aber die Flucht, die laut 3d1 scheitert: Der Ernter packt ein (10 s) und fährt davon. Geplant wird bei w + 370, also meist noch
  im Einpacken, und k0 kommt aus dem Zufall. Fährt er 48,8 s lang mit 1,41 Kacheln/s genau vom Wurm weg, wächst der Weg um etwa 68 Kacheln: (155,4 + 68) /
  48,8 = 4,6 Kacheln/s. Die Luft von 4,4 s (etwa 15,5 Kacheln, Festlegung „Spawn“) reicht nur, wenn er sich um höchstens so viel entfernt, also bei etwa
  77° oder mehr neben „genau weg“; in den übrigen etwa 40 % der Richtungen holt ihn nur der Sprint ein. Ohne Sprint (Antwort „nein“ auf die Frage an Max
  in der Festlegung „Sprint“; Max hat am 27.10. „ja“ gesagt) beißt dann der Ersatzbiss bei 0 + 3 s, während der Wurm noch etwa 50 Kacheln zurück ist, also wieder das Bild aus 3d1. Keine
  Spawnentfernung hilft ohne Sprint: Sie müsste unter etwa 34 Kacheln liegen. T21 Schritt 12 prüft die Flucht.

### 4.10 Zerdrücken auf dem Weg; Flieger
In Schritt 2 c (4.3) je Jagd mit Wurm, nach dem Steuern, mit dem Kopf dieses Takts (im Spawn-Takt zusätzlich an jedem vierten Knoten, 4.6 Schritt 5):
1. `surface.find_entities_filtered{area = {{hx − 2.5, hy − 2.5}, {hx + 2.5, hy + 2.5}}}` (A23 classes.d.ts:20487).
2. Je Entity: `victim_ok` (scripts/worms.lua:629–636: gültig, mit Gesundheit, `destructible ~= false` (A23 classes.d.ts:7811), kein `NO_VICTIM`-Typ, nicht
   `arrakis-ornithopter`, nicht Force `arrakis-sandworm`); Typ nicht `character`, nicht in `VEHICLE_TYPES` (scripts/worms.lua:71–79, darunter der Spice-Ernter
   als `car`), nicht `elevated-straight-rail`, `elevated-half-diagonal-rail`, `elevated-curved-rail-a`, `elevated-curved-rail-b` (V23
   elevated-rails/prototypes/entity/elevated-rails.lua:115, :149, :196, :242), `segment`, `segmented-unit`; kein Schienenfahrzeug (`locomotive`,
   `cargo-wagon`, `fluid-wagon`, `artillery-wagon`) über dem Boden, `draw_data.height > 0` (A23 classes.d.ts:7849, concepts.d.ts:8850; A20 classes.d.ts:5311;
   Gegenprüfung 0.8.0: sonst stürbe ein Zug auf der Hochschiene, die selbst heil bleibt); Force wach oder ohne Schonfrist-Datensatz
   (`g = storage.grace[entity.force.index]`, `g == nil or g.awake`; enemy und neutral haben keinen, scripts/worms.lua:202–212);
   `box_distance(entity, hx, hy) ≤ 2.5` (scripts/worms.lua:148–164); `terrain.has_sand_under(entity)` (scripts/terrain.lua:47–66); `unit_number` nicht in der
   Zielmenge; für jede laufende Jagd `box_distance(entity, zone) > 5`.
3. Töten in fester Reihenfolge (Sammeln, dann `die(worm_force)` ohne `cause`, A23 classes.d.ts:6724, wie P3D1 4.9 Schritt 5; `devour` mit leerer
   Fahrzeugliste). Keine Eruption, kein Chat; `worm.crushed + n`. `arrakis-worm-bite` und `heavy-damage` betreffen nur den Biss.
4. Fahrzeuge und Figuren im Weg zerdrückt er nicht: Der Wurm fährt durch sie hindurch oder bleibt an ihnen stehen [W10]; bleibt er stehen, taucht er nach
   300 Ticks ab (4.8 Schritt 6), und der Biss kommt bei 0 wie 0.7.0. Auf ihnen auftauchen kann er nicht (4.4 Schritt 4 a). (Das gilt mit
   `CRUSH_SPARES_VEHICLES = true`; mit dem Standard seit Max 27.10. zerdrückt er sie wie alles andere.) 0.8.1 [W18]: Der Kopf dieses Takts ist Knoten 1,
   bis 1 Kachel hinter dem wahren Kopf; das Zerdrücken kommt so höchstens einen Takt später, nie weiter weg. Steht er an etwas an (4.8 Schritt 6,
   `worm.front`), prüft der Takt auch an der Front; sonst erreichte er ein Auto, an dem der Kopf (Box ±1,5) steht, im Raster nicht immer (Trockenlauf
   0.8.1, D6 „auto“).
   Der Körper zerdrückt nach dem Auftauchen nichts: Er fährt die Spur des Kopfes nach, und was dort stand, ist schon weg. Was später in den Körper fährt,
   hält die Maske auf oder fährt durch (Vanilla-Verhalten).
5. **Schutzzone:** `zone` jeder laufenden Jagd (auch Phase `ohne`, auch `searching`) mit Radius 5. So stirbt vor 0 nichts, was der Biss (Radius 4) treffen
   könnte, und nach einem Fehlbiss nichts an der Stelle, an der das Ziel entkam. Ein Ziel blockiert den Kopf vielleicht (Maske); dann steht er etwa
   2,8 Kacheln vor der Mitte, also in Reichweite R [W10].
6. **Flieger:** Ornithopter und Insassen stehen nie auf der Liste. Physisch berührt der Wurm ihn nicht (Maske `trigger_target`), Sticker gibt es keine,
   Kontaktschaden auch nicht; T5 d belegt Tempo 100 % mit dem Testwurm; T21 prüft den echten (seit 0.8.2 mit der Grenze 80 % über dem Körper) [W12].

### 4.11 Abtauchen, Suche, Wurm getötet, Wurm verloren
- **`dive(hunt, why, quiet)`:** `unit = hunt.worm.unit`; `hunt.worm = nil`; Anfragen der Jagd aus `storage.path_requests`; ist `unit.valid`: ohne `quiet`
  Knoten holen, Staub an jedem vierten Knoten (4.6 Schritt 4), `arrakis-worm-dive` und `arrakis-rumble` am Kopf; dann `unit.destroy{raise_destroy = true}`
  (A23 classes.d.ts:18996): keine Leiche, keine Beute, kein `on_segmented_unit_died` [W7]. `quiet` nur bei Ende `"abort"` (Entfernen, gelöschte oder
  geleerte Oberfläche, Prüfstand-Aufräumen). `hunt.dive = why` bleibt stehen (Protokoll, T21). Rückgabe true, wenn eine gültige Einheit zerstört wurde.
- **Nach dem Biss:** `end_hunt` → `dive` im selben Takt (DOC 4.3 Schritt 7: Der Wurm muss nicht wenden).
- **Suche:** Fahrziel P (`last_pos`, am Reichweitenkreis geklemmt), Wächter wie in der Anfahrt (Halteabstand 8). Kopf ≤ 8 Kacheln → `dive(hunt, "suche")`; die Jagd bleibt bis `end_tick`
  im Zustand searching (Fenster „Der Wurm sucht“ wie 0.7.0); bei `end_tick` taucht `end_hunt` einen verbliebenen Wurm ab.
- **Wurm getötet** (`on_segmented_unit_died`, A23 events.d.ts:4556): `u = event.segmented_unit`; gültig → die Jagd mit `worm.un == u.unit_number` [W8];
  `hunt.worm = nil`, Anfragen weg; Chat an die Force mit Ort (`worm.head`): `msg-worm-killed` mit `target_name` („… ist gerettet“) nur bei
  `state == "warning"`, gültigem Ziel und `lost == false`, sonst `msg-worm-killed-plain` (nur der Ort). Ende: im Zustand warning `end_hunt(hunt, "killed")`
  wie normal (Rücksetzen, Ruhe, Lehrjagd-Merker), Statistik `killed + 1` und `first_escape_tick`, wenn leer (die Jagd ist überstanden); in der Suche
  `end_hunt(hunt)` mit dem schon gesetzten `outcome` (escaped bzw. gone, scripts/worms.lua:480 überschriebe es sonst) und `killed + 1` zusätzlich (nicht
  bei Befehlsjagden). Befehlsjagd: nur Aufräumen und Chat. Die Leiche entfällt im Prototyp; Haut- und Panzerteile fliegen.
- **Wurm verloren:** `script_raised_destroy_segmented_unit` (A23 events.d.ts:5305) mit `segmented_unit` einer Jagd, oder im Takt `unit.valid == false`:
  `hunt.worm = nil`, dann `to_none(hunt, "verloren")` (Anfragen weg, Phase `ohne`; in der Suche bleibt `suche`); bei 0 Biss wie 0.7.0.
  Kein `register_on_object_destroyed` (A23 classes.d.ts:4729):
  Der Takt sieht es binnen 10 Ticks, und ein Ereignis je Wurm bringt nichts dazu.

### 4.12 Zusammenspiel mit den Regeln aus 3d1 und allen Enden
| Regel oder Ende (P3D1) | 0.7.0 | 0.8.0 mit Wurm |
|---|---|---|
| Countdown fest, Biss nie vor 0 | fest | fest; Biss nur im Fenster; kein Kontaktschaden; Zerdrücken nie an Zielen und in Schutzzonen (an Fahrzeugen und Figuren nur mit `CRUSH_SPARES_VEHICLES = true` nicht, Max 27.10.) |
| Biss genau bei 0 | ja | ohne Wurm genau bei 0; mit Wurm bei 0, höchstens 3 s später |
| Getragen, andere Oberfläche | bei 0 entkommen, Eruption an `last_pos` | P = `last_pos`, der Wurm wartet dort; bei 0 Fehlbiss am Kopf, Suche, Abtauchen; der Ornithopter darüber bleibt unberührt |
| Ganz auf Fels | entkommen | P = `last_pos` am Felsrand, der Wächter hält ihn auf Sand; Fehlbiss am Kopf |
| Außer Reichweite (`far`) | entkommen, Eruption an `warn_pos` | P am Rand des Reichweitenkreises: Der Wurm hält dort (Fenster „sicher“ stimmt); bei 0 Fehlbiss am Kopf, also am Kreis |
| Ziel verloren vor 0 | `gone`, Eruption an `last_pos` | P = `last_pos`; Fehlbiss am Kopf, Suche, Abtauchen |
| Zurück auf Sand vor 0 | gebissen, wo es dann steht | P folgt; Biss, wenn er rechtzeitig dort ist, sonst Ersatzbiss bis 3 s danach |
| Force-Wechsel, Verschmelzen von Spieler-Forces | läuft weiter | läuft weiter; der Wurm gehört `arrakis-sandworm` |
| Lehrjagd | 90 s | Spawn 2470 Ticks nach dem Wurmzeichen |
| Vorsichtsmodus | – | Ein Ernter stirbt durch eine Jagd auf sich selbst oder als Nachbar im Bissradius (DOC 2.1 Schritt 6) und seit Max 27.10. auch, wenn ein Wurm auf dem Weg an ihm vorbeikommt (Zerdrücken, ohne Alarm); der Tooltip `gui-careful-tooltip` sagt es (Gegenprüfung 0.8.0) |
| Schonfrist | kein Wurmzeichen | dazu: Ein Wurm einer anderen Force zerdrückt nichts von einer Force, die noch nicht wach ist |
| `heavy-damage` | Ernter im Bissradius | unverändert, nur beim Biss |
| Ende normal, `"quiet"`, `"abort"` | P3D1 4.7 | dazu Abtauchen (bei `"abort"` ohne Effekte), Anfragen weg, Protokoll |
| Befehlsjagd | ohne Rücksetzen, Ruhe, Statistik | ab 27 s mit Wurm, höchstens 3 zugleich (`MAX_DEBUG_WORMS`); nimmt regulären Jagden keinen Wurm |
| Oberfläche gelöscht, nicht mehr erlaubt | `"abort"` | `"abort"`; ein schon ungültiger Wurm braucht nichts |
| Oberfläche geleert | nicht behandelt (Ziel weg ohne Ereignis, bei 0 `gone`) | neu `on_pre_surface_cleared`: `"abort"`, Wurm still weg |
| Entfernen | `"abort"`, Force verschmolzen | dazu Waisen auf allen Oberflächen vor dem Verschmelzen (4.14) |
| Wurm getötet | – | vor 0 Ende `killed`, Ziel gerettet; in der Suche Ende mit dem Ergebnis des Fehlbisses, `killed` zählt dazu |
| Wurm verloren | – | `ohne`, Biss wie 0.7.0 |
| Wurm taucht vor 0 ab (Fels, Stillstand, kein Weg) | – | `ohne`, Biss wie 0.7.0 bei 0 (bzw. im nächsten Takt, wenn es im Fenster geschah) |

### 4.13 Mehrere Jagden, Speichern und Laden, Mehrspieler
- **Reihenfolge:** Jagden nach `id`; die Schutzpunkte aller Jagden stehen vor dem ersten Zerdrücken fest (4.3 Schritt 1). Ein Wurm zerdrückt nie das Ziel
  oder die Schutzzone einer anderen Jagd. Treffen sich zwei Würmer, gilt die Vanilla-Maske zwischen ihnen; keiner zerdrückt den anderen (Typ `segment`).
- **Grenze:** `counted(true)` zählt Befehlsjagden in `warten`, `routing`, `anfahrt`, `angriff` und `suche` mit Wurm, über alle Forces und Oberflächen; nur
  sie haben eine Grenze (`MAX_DEBUG_WORMS = 3`). Reguläre Jagden sind durch P3D1 4.5 auf 3 begrenzt und bekommen immer einen Wurm; zusammen höchstens 6.
  Eine Befehlsjagd, die über der Grenze startet, bleibt `ohne`, auch wenn später Platz wird (einfach und vorhersagbar).
- **Speichern/Laden:** Alles steht in storage; `on_load` schreibt nichts. Der Wurm als `LuaSegmentedUnit` in storage [W11]; eine Anfrage über das Laden hinweg
  [W5] hat den Zeitablauf 300 Ticks.
- **Mehrspieler:** Zufall nur `storage.rng` (Startrichtung), sonst fest aus Tick, Knoten und Lage; Kandidaten, Winkel und Jagden in fester Reihenfolge.

### 4.14 Migration (Schema 4), Waisen, Entfernen
- **migrate.lua:** `SCHEMA = 4` (Z. 57), `init()` legt die neuen Tabellen an (4.2). `on_configuration_changed`: wie bisher, neu `old < 4` →
  jeder `storage.worm_stats[i].killed = killed or 0`; dann Schema. Kopfkommentar (Z. 29–44) um Schema 4. Einen Merker für worms braucht es nicht (unten).
- **worms `on_configuration_changed`** (nach migrate), immer, unabhängig von `old`: `migrate_schema4()`: jede Jagd ohne `phase` oder ohne `r` bekommt
  `phase = "ohne"`, `no_worm = "migration"`, `r` aus dem Ziel (ungültig: 1,58). Das deckt auch 0.8.0 → 0.7.0 → 0.8.0 ab: Dort steht `schema` schon auf 4
  (0.7.0 schreibt `math.max(old, 3)`), aber Jagden aus 0.7.0 haben weder `phase` noch `r`, und `R = 3 + r` bräche im Biss-Fenster. Außerdem immer: `sandworm.sweep()`; jede Jagd mit ungültigem
  Wurm → verloren (4.11); Einträge in `storage.path_requests` ohne Jagd weg; `storage.hunts.spawn_dir` und `worm_off` anlegen, wenn sie fehlen.
- **`sweep(surfaces)`:** je Oberfläche `get_segmented_units()` (A23 classes.d.ts:20679; A20 :31375), Prototypname (`unit.prototype.name`, :19095) beginnt mit
  `arrakis-sandworm-` und `unit_number` gehört keiner Jagd → `destroy{raise_destroy = true}`. Testwürmer (`arrakis-test-worm…`) bleiben. Rückgabe n.
- **`/arrakis-uninstall`** (scripts/flyer.lua:1159–1183): ohne Argument `uninstall-worms-warn` mit der Zahl laufender Jagden (Text neu, 5); mit `ja`
  `worms_lib.uninstall()`: alle Jagden `end_hunt(hunt, nil, "abort")` (Würmer still weg; m1 = Zahl der Jagden, deren `dive` true gab), dann `sweep()` auf
  allen Oberflächen → m2, m = m1 + m2 (alle entfernten Würmer, nicht nur die Waisen), `storage.path_requests = {}`, dann wie 0.7.0 (Alarme, Fenster, Pause,
  `merge_forces` per pcall, A23 classes.d.ts:11848). Rückgabe n, m; Meldung `uninstall-worms` mit beiden. `end_hunt` gibt dafür das Ergebnis von `dive` zurück.
- **Herunterstufen** auf 0.7.0: vorher `/arrakis-uninstall ja`. Sonst entfernt Factorio die Würmer beim Laden (Prototyp fehlt), und 0.7.0 beißt laufende
  Jagden bei 0 wie gewohnt; die neuen Felder und `schema = 4` stören 0.7.0 nicht (`math.max(old, SCHEMA)` in migrate). Zurück auf 0.8.0 gilt die
  Normalisierung oben.

### 4.15 Leistung
- Je Wurm und 10-Tick-Takt: 1 `get_body_nodes` (22 Lagen), 1 Kachel und 1 Chunk für das Sicherheitsnetz, Vorausschau höchstens 2 × 3 × 9 = 54 Kacheln (meist
  kürzer, im Angriff höchstens 9), 1 Flächensuche 5 × 5 mit wenigen Treffern, höchstens 1 Tempo und alle 30 Ticks 1 Zustand; im Spawn-Takt 6 Flächensuchen
  dazu. Bei 6 Würmern (3 reguläre, 3 Befehlsjagden) höchstens etwa 400 Abfragen je 10 Ticks, im Mittel unter 150. Die Engine-Kosten sind die von Würmern
  im Modus full: In `investigating` fährt der Wurm so (T5 a), `minimal` ist nur die Untergrenze [W13].
- Planung: höchstens 8 Kandidaten je Takt mit je höchstens 6 + 39 Kacheln und 1 Zählung von Fahrzeugen und Figuren (etwa 360 Abfragen), auf freiem Sand
  1 Kandidat; höchstens 6 Takte.
- Pfadsuche in der Engine, Raster 4 × 4, höchstens 3 Anfragen je Jagd und je eine Wiederholung mit Box ±1,5.
- Spawn und Abtauchen: 1 Erzeugen bzw. Zerstören, 12 Rauchwolken, 1 Effekt, 1 Ton.
- `minimum_activity_mode` höchstens bei 6 Würmern, zurück mit dem Abtauchen (die Einheit verschwindet). Ein Budget je Takt kommt erst, wenn T8 es verlangt.

### 4.16 Protokoll und Log
`end_hunt` schreibt je Jagd einen Eintrag nach `storage.hunts.log[log_next]` (Ring mit 20, `log_next` läuft um): `{id, kind, debug, force_index, outcome,
phase, no_worm, warn_tick, eta_tick, plan_tick, spawn_tick, bite_tick, bite_dist, ersatz, k, d, length, paths, box, spawns, reroutes, detours, samples,
rock_box, vmax, sprint, boost, crushed, dive}` (nur Zahlen, Texte und Wahrheitswerte, keine Lua-Objekte). Je Jagd mit Wurm dazu eine Zeile
`log("Arrakis: Jagd …")` mit denselben Zahlen (eine Zeile, kein Spam). `storage.hunts.ersatz` zählt
Ersatzbisse seit Spielbeginn.

### 4.17 Ungeprüfte Engine-Annahmen
| Nr | Annahme | Entscheidet | Wenn sie nicht hält |
|---|---|---|---|
| W1 | `unit.speed = 3.5 / 60` direkt nach dem Erzeugen hält: Der Wurm fährt sofort 3,5 statt in etwa 7 s zu beschleunigen | T21 Schritt 2 (Tempo 1 s nach dem Spawn ≥ 3,3) | Reserve `LEAD` um V / (2a) = 3,2 s auf 6,2 s erhöhen; der Spawn kommt so viel früher |
| W2 | Tempo 0 alle 10 Ticks hält den Wurm fest (Kriechen höchstens 0,1 Kacheln/s) | T21 Schritte 2 und 5 (MESSUNG Weg beim Halten) | Fahrziel beim Halten auf den Kopf (Engine: `patrolling` mit 1 Kachel/s); die Reichweite R reicht dafür |
| W3 | Ein Tempo über `target_speed` (Sprint 6 Kacheln/s) hält zwischen zwei Schreibvorgängen (Abbremsen mit der Beschleunigung, Mittel ≥ 5,5) | T21 Schritte 3, 9 und 12 (MESSUNG mittleres Tempo im Sprint, Sprint-Takte) | Ersatz 1: zusätzlich je Takt `unit.move_forward(Δ)` (A23 classes.d.ts:19026, A20 :28085) mit dem fehlenden Weg, höchstens 0,4 Kacheln je Takt. Ersatz 2: Knotenschub per `set_body_nodes` (A23 classes.d.ts:19040, A20 :28130, 4.9 „Sprint-Ersatz“) vom geschätzten wahren Kopf aus [W20]. Ohne jeden Sprint bekäme ein fliehender Ernter meist den Ersatzbiss (4.9); das ist kein zulässiger Ausgang mehr |
| W4 | `request_path` mit `collision_mask = {layers = {arrakis_rock = true}}` und Raster −2 findet Wege um Fels herum, die Antwort kommt mit `path`, `try_again_later` bei Last | T21 Schritt 4 (Sandtasche mit Knick), MESSUNG Wartezeit | Kein ROUTING: Ziele ohne gerade Sandlinie bekommen Phase `ohne` (Biss wie 0.7.0); der Wächter bleibt |
| W5 | Eine Anfrage, die über Speichern und Laden läuft, meldet sich danach oder gar nicht (kein Fehler); eine Kennung, die nach dem Laden neu vergeben wird, trifft keinen alten Eintrag einer anderen Jagd | T22 Schritt 9 (Laden im `routing`), nur wenn beim Speichern eine Anfrage offen war (MESSUNG); sonst bleibt W5 offen | Ist geplant: Zeitablauf 300 Ticks, dann neu fragen; der Zeitablauf löscht nur den eigenen Eintrag, `tidy` räumt den Rest (4.5) |
| W6 | `create_segmented_unit` mit `extended = true` liefert sofort alle 22 Knoten hinter dem Kopf, gegen die Blickrichtung | T21 Schritt 2 (Knoten, Lage); T7 belegt es für den Testwurm | Körperprüfung erst im nächsten Takt; bis dahin `speed = 0` |
| W7 | `destroy{raise_destroy = true}` hinterlässt keine Leiche, keine Beute und kein `on_segmented_unit_died`, löst aber `script_raised_destroy_segmented_unit` aus | T21 Schritte 2 und 11 (Leichen im Feld, Ereignisse) | Leichen unseres Wurms im Bereich des Körpers nach dem Abtauchen entfernen |
| W8 | `die()` auf unseren Wurm feuert `on_segmented_unit_died` mit gültiger Einheit und hinterlässt ohne `corpse` und ohne Leichen-Effekt weder Leiche noch Wolfram | T21 Schritt 10 | Zuordnung über `on_post_segmented_unit_died` mit `unit_number` (A23 events.d.ts:3544, :3580); Leichen und Wolfram im Bereich entfernen |
| W9 | `set_ai_state(investigating)` alle 30 Ticks stört die Fahrt nicht und beendet einen Gereizt-Zustand (nach Schaden) | T21 Schritte 2 und 10 (Zustände, Schaden) | Nur bei anderem Typ oder Ziel setzen; Gereizt per `on_segmented_unit_damaged` (A23 events.d.ts:4517) nur für eigene Würmer sofort zurücksetzen |
| W10 | Ohne Kontaktschaden fährt der Wurm durch Entities, die er nicht zerdrückt (`destructible == false`, Schutzzone, Fahrzeuge, Figuren), oder bleibt davor stehen, ohne die Steuerung zu verlieren | T21 Schritt 8 (unzerstörbare Kiste, Auto mit Fahrer, Figur und Ernter im Weg, Nachbar des Ziels) | Bleibt er stehen: Stillstand → abtauchen (geplant). Hängt er in der Schutzzone: Reichweite R + 2. Ist beides zu oft (ein geparktes Auto auf der Linie nähme jeder Jagd den Wurm): Maske leeren (`collision_mask = {layers = {}}`) |
| W11 | Ein `LuaSegmentedUnit` in storage ist nach dem Laden gültig und dieselbe Einheit | T22 Schritt 9 (Laden in der Anfahrt) | `un` merken und nach dem Laden einmal über `get_segmented_units()` suchen, sonst verloren |
| W12 | Der echte Ornithopter verliert über dem echten Wurm keine Gesundheit und höchstens wenig Tempo (seit 0.8.2: über dem Körper mindestens 80 % des Vergleichstempos) | T21 Schritt 6 (0.8.2: Mitflug über dem Kopf mit Abstand zum Zielpunkt höchstens 0,5 Kacheln mehr als im Mittel der Vergleichsflieger O6b, 60 Kacheln nördlich, und O6c, 60 südlich, Tempo nur MESSUNG; dann Ruhe; dann alle drei 80 Kacheln nach Westen, O6 über den Körper: mindestens 60 Ticks höchstens 3 Kacheln von einem Körperknoten, Tempo dort ≥ 0,8 × Mittel von O6b und O6c in denselben Ticks, Flugzeit ≤ 1,05 × deren Mittel; Sticker je Tick in Ruhe und Flug; MESSUNG zur Ursache: Wegpunkte des Autopiloten, Abweichung quer zur Flugrichtung, Tempo je 20 Ticks), T22 Schritt 5 | Offen. Prüfstand 2026-10-27 abends (0.8.1): Gesundheit und Sticker in Ordnung, über dem Körper 89 % für 115 Ticks, Weg dort 1,6 Kacheln zurück, Flugzeit 102,2 % (Grenze damals 1,02). In den Prototypen ist kein Mechanismus bekannt (Maske des Fliegers nur `trigger_target`, Bein ohne Ebenen, Wurmeffekte nur Partikel und Rauch). Unterscheiden sich O6b und O6c so wenig wie sonst zwei Bahnen, liegt es am Wurm: den Effekt suchen (checks.lua listet alle Effekte des Prototyps). Unter 80 % ist DOC 2.4 verletzt: Abnahme verweigern |
| W13 | In `investigating` bleibt der Wurm auch ohne Spieler in der Nähe im Modus full, wie in T5 a (35 von 35); `minimal` tritt im Wurmleben nicht auf, also gelten Steuerung und Kosten von full. Ob er im Modus `minimal` ebenso folgen würde, prüft 3d2 nicht | T21 alle Schritte (MESSUNG `activity_mode` je Takt; `minimal` irgendwo: INFO) | Tritt `minimal` auf: Schritt 2 zeigt, ob Zeiten und Tempo trotzdem stimmen; sonst `minimum_activity_mode = full` für das ganze Wurmleben (höchstens 6) |
| W14 | `create_segmented_unit` auf geprüftem Sand in generierten Chunks gibt nie nil und wirft keinen Fehler | T21 (Zahl der Erzeugungen je Jagd = 1, `spawns` im Protokoll) | Geplant: `pcall`, nächster Kandidat, höchstens 3 |
| W15 | Ein Ersatzbiss oder Biss mit `die()` im 10-Tick-Takt verträgt, dass dabei Einheiten und Ziele anderer Jagden ungültig werden | T21 Schritt 8 (Zerdrücken und Biss im selben Takt), Trockenlauf (7) | Je Opfer `valid` prüfen (wie 0.7.0) |
| W16 | Ein schreibender Zugriff auf `minimum_activity_mode` mit `minimal` gilt bis zum Abtauchen und kostet bei 6 Würmern (im Modus full, W13) spürbar nichts | T8 (später), Abnahme mit 3 Jagden | Nur im Angriff setzen |
| W17 | Der Wurm folgt einem Weg mit Box ±3,5 durch einen 16 Kacheln breiten Gang mit Knick, ohne dass die Kopfmitte Fels berührt und ohne Abtauchen; Sichtlinien-Ausdünnen, Wegpunktwechsel und kurze Umwege genügen | T21 Schritt 4 (Tasche mit Knick; OK: kein `dive` vor dem Biss, Wurm in der Tasche), MESSUNG Umwege, `rock_box` | Box auf ±5,5 und kein Rückgriff auf ±1,5: Für schmale Gänge findet der Pfadfinder dann keinen Weg, die Jagd wird `ohne` (`"kein-weg"`, Biss wie 0.7.0) |
| W18 | Körperknoten im Kachelraster: `get_body_nodes()` meldet die Spurpunkte im Abstand 1 (Kachelmitten nur auf Fahrt längs einer Achse); Knoten 1 bleibt bis 1 Kachel hinter dem wahren Kopf und kommt je 10 Ticks 0, 1 oder 2 Kacheln weit | Geklärt (hält) im Prüfstand 2026-10-27 (0.8.0, T21): auf Fahrt nach Osten Kopf auf Kachelmitten (x,5), schräg nicht (Schritte 2, 10 und 12 von Nordost: je 60 Ticks 2,97 oder 3,96 Kacheln); je 60 Ticks bei 3,5 Kacheln/s abwechselnd 3 und 4 Kacheln, im Sprint 5 oder 6 (Schritt 9); „Tempo“ aus einem Takt nur 0,0 oder 6,0; Bissverzug 10 Ticks in den Schritten 2, 3 und 5. T21 Schritt 2 misst es weiter (MESSUNG Raster) | Ist umgesetzt (0.8.1): Tempo nur über Fenster (4.9 „Sprint-Ersatz“), Stillstand mit dem geschriebenen Weg, Zerdrücken auch an der Front (4.8 Schritt 6, 4.10), Ersatz 2 schiebt vom geschätzten wahren Kopf statt von Knoten 1 (4.9, W20); Biss und Reichweite rechnen mit Knoten 1 (bis 1 Kachel und etwa einen Takt später, nie weiter weg) |
| W19 | `segments[1].position` ist der wahre Kopf (stetig, bis 1 Kachel vor Knoten 1) | Geklärt (hält nicht) im Prüfstand 2026-10-27 abends (0.8.1, T21 Schritt 2): `segments[1]` liegt im Mittel 1,49 Kacheln hinter Knoten 1 (1,00 bis 1,99), seitlich 0, und läuft stetig (Weg je 10 Ticks in 293 von 293 Proben nicht ganzzahlig); es ist das erste Körpersegment, nicht der Kopf | Wird nicht benutzt; Kopf und Tempo bleiben bei Knoten 1 und den Fenstern (0.8.1) |
| W20 | Nach `set_body_nodes` steht der wahre Kopf auf dem ersten Knoten der Liste, `get_body_nodes()[1]` meldet ihn dort, bis die Engine ihn 1 Kachel weiter gefahren hat (dann der nächste Spurpunkt), und `unit.speed` ist das Tempo, mit dem sie ihn fährt | Kein Schritt: Ersatz 2 läuft nur, wenn weder W3 noch `move_forward` wirkt; T21 kommt dorthin nicht, solange W3 hält (Schritt 9: 5,94 Kacheln/s). Trockenlauf D8 und D11 mit dieser Annahme | Hält sie nicht, ist der Vorsprung im Schub (4.9 Stufe 2) falsch geschätzt: zu klein, fehlt Weg wie vor 0.8.1; zu groß, schiebt er bis 0,99 Kacheln je Takt zu weit, das Tempo der Engine im Fenster zählt ihn aber als ihren Weg, und Δ fällt gegen 0. Erst prüfen, wenn Ersatz 2 je gebraucht wird (Logzeile „Ersatzstufe 2“): mit einem Testwurm, der nur 3,5 fährt, und `set_body_nodes` allein |

Stand nach dem Prüfstand 2026-10-27 (0.8.0, 80e1c6d, T21 14/15 OK): Geklärt (hält) sind W1 (Tempo 1 s nach dem Spawn 3,50), W3 (Schritt 9: im
Sprint 5,94 Kacheln/s im Mittel über 102 Sprint-Takte, der Kopf je 60 Ticks 5 oder 6 Kacheln weiter; Schritt 12 Biss bei eta + 70 ohne Ersatzbiss), W4 und W17 (Schritt 4: 1 Anfrage, 3 Wegpunkte, Box ±3,5,
Biss eta + 0) und W18 (neu). Offen bleiben W12, bis der neue Schritt 6 (0.8.1) gelaufen ist (0.8.0 scheiterte am Tempo im Mitflug, das dem Raster folgt;
Flugzeit 102 %), und W2: In den Schritten 2 und 5 hielt der Wurm nicht, Weg beim Halten wurde nicht gemessen. W20 (neu in der Gegenprüfung 0.8.1) ist offen
und prüft kein Schritt, solange W3 hält.

Stand nach dem Prüfstand 2026-10-27 abends (0.8.1, aa0ccf3, alle Tests außer T21 ohne FEHLER, T21 14/15 OK): W19 hält nicht (`segments[1]` ist das erste
Körpersegment, 1,49 Kacheln hinter Knoten 1). W12 bleibt offen: Schritt 6 maß aus der Ruhe über dem Körper 89 % des Vergleichstempos für 115 Ticks (Weg dort
1,6 Kacheln zurück, Flugzeit 102,2 %). 0.8.2 lässt leichtes Bremsen zu (Grenze 80 %, Flugzeit 1,05) und misst die Ursache mit einem zweiten Vergleichsflieger.
W2 kam wieder nicht vor (Schritt 5: Weg beim Halten 0 in 0 s), W20 auch nicht (Ersatzstufe 0 in den Schritten 3, 9 und 12).

### 4.18 Prüfstand-Haken
- worms: `set_worm_off(force, on)` (`storage.hunts.worm_off[force.index]`; gilt für Jagden, die danach starten); `set_spawn_dir(force, k|nil)`
  (`storage.hunts.spawn_dir[force.index]`: Startrichtung k0 für jede danach startende Jagd der Force, auch reguläre; nil löscht); `start_hunt` mit `opts.spawn =
  {position, direction, tick}` (Spawn ohne Planung, 4.4) und `opts.spawn_dir = k` (Startrichtung der Planung); `hunt_log()`; `migrate_schema4{hunts = {…}}`
  (nur diese Jagden); `stats_of`, `uninstall` (gibt n, m zurück) wie bisher.
- sandworm: `head_of(hunt)`, `counted(debug)`, `sweep(surfaces)`, Konstanten; die Felder `hunt.phase`, `hunt.no_worm`, `hunt.dive`, `hunt.plan`, `hunt.path`,
  `hunt.worm` sind lesbar.
- Isolation: T21 und T22 benutzen eine eigene Force `arrakis-t21` bzw. Max' Force, eingeschaltet wie T18/T19 (`vibration.testbench_enable`); `cleanup`
  beendet jede Jagd seiner Force mit `"abort"` (Würmer still weg), setzt `set_worm_off` und `set_spawn_dir` der Force zurück, ruft `sweep{Prüfstand}` und
  prüft, dass kein `arrakis-sandworm-*` im Bereich bleibt.
  Der Runner zerstört beim Vorbereiten ohnehin alle Würmer im Bereich (scripts/testbench/runner.lua:364–372); eine Jagd, deren Wurm so verschwindet, wird `ohne`.

## 5. Texte

`locale/{de,en}/arrakis.cfg` (Datenstufe):
- `[entity-name]` (Z. 37 ff.): `arrakis-sandworm-small=Sandwurm`, `arrakis-worm-dive=Sandwurm taucht auf oder ab`.
- `[entity-description]` (Z. 52 ff.): `arrakis-sandworm-small=Kommt bei einem Wurmzeichen aus der Tiefe, fährt nur über Sand und beißt nach dem Countdown. Unterwegs zerdrückt er Bänder, Schienen und Gebäude auf Sand, die vor seinem Kopf liegen. Ornithopter in der Luft erreicht er nie, und auf Fels kommt er nicht.`
- `[tips-and-tricks-item-description]` `arrakis-wormsign-tip` (Z. 110): hinter „Nach 60 s (beim ersten Ernter 90 s) beißt der Wurm.“ der neue Satz
  „Der Sandwurm taucht weit entfernt auf, fährt nie über Fels und zerdrückt auf dem Weg Bänder, Schienen und Gebäude auf Sand.“

`locale/{de,en}/messages.cfg`, Abschnitt `[arrakis-message]`:
- Chat neu: `msg-worm-killed=Ein Sandwurm ist bei __1__ gestorben: __2__ ist gerettet.` (nur vor 0 mit gültigem Ziel, 4.11) und
  `msg-worm-killed-plain=Ein Sandwurm ist bei __1__ gestorben.`
- Befehl (Z. 102): `worm-cmd-help=Hetzt einen Sandwurm auf die ausgewählte Entity (nur Admins): /arrakis-worm [Sekunden 5–600 | lehr]. Ab 27 s kommt ein echter Wurm angefahren (höchstens 3 zugleich), darunter beißt er ohne Anfahrt. Ohne Ruhezeit und ohne Statistik.`
- Entfernen (Z. 68, 110, 111): `uninstall-help=Setzt alle getragenen Spice-Ernter ab, löscht die Ablage, beendet laufende Jagden, lässt alle Sandwürmer abtauchen und räumt Wurm-Markierungen, damit die Mod entfernt werden kann (nur Admins). Erst ohne Argument, dann mit „ja“.`,
  `uninstall-worms-warn=Dazu enden __1__ laufende Jagden ohne Biss, alle Sandwürmer tauchen ab, und 10 Minuten lang kommt kein Wurmzeichen.`,
  `uninstall-worms=__1__ Jagden ohne Biss beendet, __2__ Sandwürmer entfernt; 10 Minuten lang kommt kein Wurmzeichen.`

Englisch sinngemäß: „Sandworm“, „Sandworm surfacing or diving“, „A sandworm died at __1__: __2__ is saved.“, „A sandworm died at __1__.“, „From 27 s a
real worm comes (at most 3 at once), below that it bites without approach.“, „all sandworms dive“, „crushes belts, rails and buildings on sand“. Fenster,
Status, Alarm und die übrigen Chatzeilen bleiben wie 0.7.0. Kein neuer Text nennt die Werkvorlage beim Namen.

## 6. Prüfstand

Wie in 3d1: ohne Spieler über tools/pc/pruefstand.py (RCON) mit game.speed 10, nur Ticks, OK oder FEHLER mit Werten, Einzelwerte als MESSUNG.
`ORDER` (scripts/testbench/runner.lua:40–41) endet mit `"T18", "T19", "T20", "T21", "T22"`; die Flächen hängen am Index (`tb.area`, :295–300): T21 bei
x = 38 000, T22 bei 40 000, keine alte Fläche verschiebt sich. Sektoren rechnen die Tests mit `vibration.key_of`. Zeitlimits: T21 `timeout = 300 * 60`,
T22 `timeout = 20 * 60 * 60`, `interactive = true`. Bauten mit `raise_built = true`, Fahrer sind `tb.dummy_driver`, Ernter auf Spice-Teppich wie T19.
Modulliste (:57–59) um `scripts.testbench.t_sandwurm`; Weiterleitungen (:819–827) neu `segmented_unit_died` und `segmented_unit_destroyed`; Vertrag (:10–33)
nennt das neue Modul und beide Namen. T21 und T22 messen den Kopf je 10 Ticks über `sandworm.head_of`. Knoten 1 springt im Kachelraster [W18]: Tempo und
Weg zählen nur über Fenster (Tempo über 1 s, Fehler unter 1 Kachel/s; Wege mit höchstens 1 Kachel Fehler je Lauf), und die Texte nennen das Fenster (0.8.1).

**T21 „Sandwurm: echter Code“** (automatisch, etwa 3,3 min Spielzeit, bei Tempo 10 etwa 20 s plus Aufbau). Force `arrakis-t21` (wach, `first_hunt_done = true`),
eingeschaltet, `set_spawn_dir(force, 2)` (Nordost) für alle Jagden ohne eigenen Haken. Sandfläche 1200 × 1600 Kacheln aus 12 Feldern zu 400 × 400 (Spalten
x = −400, 0, 400, Reihen y = −600, −200, 200, 600 um den Ursprung; Feld 1 bis 3 in der Reihe −600 von West nach Ost, 4 bis 6 bei −200, 7 bis 9 bei 200,
10 bis 12 bei 600). Vorbereitet wird ein Feld je Tick ab Tick 1 (`tb.prepare(Feldmitte, 200)`, je 160 000 Kacheln; ein einziges `tb.prepare` über alles
wären 1,92 Millionen Kacheln in einem Tick, T18 und T19 nehmen höchstens 360 000, und `pruefstand.py` bricht nach 90 s ohne Tick ab, `STALL`). Jedes Ziel
steht in der Mitte seines Felds: Wurm und Körper bleiben darin (160 + 21 < 200), Felder in verschiedenen Sektoren. Die Schritte 2 bis 12 laufen in drei
Wellen, damit nie mehr als 3 Befehlsjagden einen Wurm brauchen (Festlegung „Grenze“) und nie mehr als 6 Würmer fahren: Welle A ab Tick 13 mit den Schritten
2, 10 und 12 (regulär) und 3, 4, 5; Welle B mit 6, 7, 8, sobald `counted(true) == 0`; Welle C mit 9 und 11 ebenso; danach 13 bis 15 nacheinander in
Feld 12. Die regulären Jagden der Schritte 2, 10 und 12 bekommen ihr Wurmzeichen in drei aufeinanderfolgenden 60-Tick-Takten (höchstens eine neue je Takt
und Oberfläche, P3D1 4.5): `set_heat` 999 je Schritt einen Takt nach dem vorigen. Vorbedingung wie T19 Schritt 1: Laufen schon reguläre Jagden anderer
Forces, ist für die drei nicht Platz (höchstens 3); dann INFO, und Schritt 12, danach 10, startet erst, wenn eine frei wird. „Bissverzug“ =
`bite_tick − eta_tick`.
Allgemein in jedem Schritt mit Wurm: Kopfmitte nie auf Fels (FEHLER beim ersten Mal); weil der Takt von worms vor dem Messtakt des Tests laufen kann und
das Sicherheitsnetz den Wurm dann schon abgetaucht hat, zählt auch `hunt.dive == "fels"` als FEHLER, ebenso `"stillstand"` und `"kein-weg"`, wo der Schritt
sie nicht erwartet, und `no_worm == "abgetaucht"` vor `eta` (gelesen aus der Jagd vor dem Ende und aus dem Protokolleintrag). `rock_box / samples` als
MESSUNG (über 5 %: INFO), Erzeugungen je Jagd (`spawns`) 1 (mehr: INFO [W14]), `activity_mode` je Takt als MESSUNG (`minimal` irgendwo: INFO [W13]),
Weg beim Halten als MESSUNG (Weg von Knoten 1 vom ersten bis zum letzten Takt jedes Haltens; liegt er auch nach Abzug von 1 Kachel je Halten über
0,5 Kacheln plus 0,1 Kacheln je Sekunde Haltezeit: INFO [W2]), nach dem Ende kein `arrakis-sandworm-*` mehr im Feld.
1. Prototypen und storage: `prototypes.entity["arrakis-sandworm-small"]` mit Typ `segmented-unit`, vier Rauchkopien und `arrakis-worm-dive` da; ein Probewurm im
   Feld 12 hat `max_body_nodes == 22` (dann sofort weg); `storage.schema == 4`, `path_requests`, `hunts.log`, `hunts.worm_off`, `hunts.spawn_dir` da,
   `stats_of(force).killed == 0` (die Force ist neu, `stats_for` legt `killed` an).
2. Zeitlinie 60 s, regulär [W1, W2, W6, W7, W9, W13] (Feld 1): Ernter H1 aufgebaut, vier Holzkisten je 3 Kacheln neben H1 (N, O, S, W), `set_heat` 999 →
   Wurmzeichen. Startrichtung k0 = 2 (Haken der Force): Die Anfahrtslinie von Nordost läuft mit 2,1 Kacheln Seitenabstand an der Nord- und der Ostkiste vorbei,
   die Kopfbox (±1,5) berührt keine (bei zufälligem k0 läge in 4 von 16 Richtungen eine Kiste vor dem Kopf; die Kiste im Weg prüft Schritt 8 [W10]).
   OK: `phase` warten ab dem Start, `routing` genau bei `eta − 3230`, Wurm genau bei `eta − 2930` (gerade Linie, `paths == 0`, k = 2) mit 22 Knoten, jeder vierte
   auf Sand, Körper auf der von H1 abgewandten Seite (letzter Knoten mindestens 18 Kacheln weiter von H1 als der Kopf);
   Tempo 1 s nach dem Spawn ≥ 3,3 Kacheln/s; `angriff` bei Abstand ≤ 40; vor `eta` kein `entity_died` im Feld
   (die Kisten liegen in der Schutzzone); Bissverzug 0 bis 180 (MESSUNG, über 0: INFO), kein Ersatzbiss, Abstand Kopf–H1 beim Biss ≤ 4,58; im Biss-Takt H1 und
   alle vier Kisten tot; Wurm im selben Takt weg, kein `segmented_unit_died`, ein `segmented_unit_destroyed`; im Feld keine Entity vom Typ `simple-entity` und
   kein Bodenstapel mit Wolframerz; Protokolleintrag mit `phase == "angriff"`, `outcome == "bitten"`. MESSUNG: Ankunft von Knoten 1 in Reichweite (gegen `eta`),
   Weg beim Halten, kleinstes Tempo im Angriff (Weg je 1 s), `activity_mode` je Phase, Zustände (`get_ai_state`) jede Sekunde; Raster [W18]: Weg von Knoten 1
   je 10 Ticks nach ganzen Kacheln gezählt; `segments[1]` [W19]: Lage gegen Knoten 1 längs der Kopfrichtung, ob ihr Weg je 10 Ticks ganzzahlig ist.
3. Felsinsel [W3] (Feld 3): Kiste K3 als Ziel, Felsinsel 40 × 40 mit Mitte 80 Kacheln westlich von K3, Befehlsjagd 60 s mit `spawn = {160 Kacheln westlich, Richtung Ost}`.
   OK: „biegt vor der Felsinsel ab“: erster Umweg, solange der Kopf noch mindestens 2 Kacheln vom Inselrand entfernt ist, und binnen 180 Ticks danach eine
   Richtungsänderung ≥ 20°; Kopfmitte nie auf Fels; Bissverzug 0 bis 180; kein Ersatzbiss (FEHLER nur, wenn W1 in Schritt 2 und W3 im Sprint dieses
   Schritts gehalten haben, sonst INFO: Ein Umweg wie T6 C kostet 5,2 s, ein Start ohne Schwung 3,2 s, zusammen mehr als die 7,4 s Luft bis zum Ersatzbiss).
   W3 gilt hier als gehalten, wenn der Weg von Knoten 1 in den Sprint-Proben auch nach Abzug von 1 Kachel je Lauf mindestens 5,5 / 6 des geschriebenen
   Wegs ist (0.8.1; im Raster nicht zu entscheiden: INFO). MESSUNG: Umwege, Winkel, Zeitverlust gegen die gerade Linie (Ankunft von Knoten 1 in Reichweite,
   also bis 1 Kachel Fahrt nach dem wahren Kopf [W18]), Sprint-Takte, mittleres Sprinttempo und Anteil des geschriebenen Wegs samt Rastergrenzen.
4. Sandtasche mit Knick [W4, W17] (Feld 4): Fels 140 × 140 um das Ziel, darin eine Sandtasche 30 × 30 mit Ernter H4, Gang 16 Kacheln breit von der Tasche 30 nach
   Osten, dann nach Norden bis zum Rand; keine gerade Linie von außen reicht in die Tasche. Befehlsjagd 60 s mit `spawn_dir = 0`. OK: Planung prüft alle Kandidaten
   ohne gültigen, dann 1 oder 2 Anfragen, ein Weg gilt (`chosen.route` nicht leer, Box ±3,5); keine Sehne der Route schneidet Fels (Mittellinie und ±1,5);
   `angriff` erst nach dem letzten Wegpunkt; Kopfmitte nie auf Fels; kein `dive` vor dem Biss; Wurm erreicht die Tasche (Abstand Kopf–H4 beim Biss ≤ R);
   Bissverzug 0 bis 180. MESSUNG: Wartezeit der Antwort (Ticks), `try_again_later`, Box, Weglänge, Wegpunkte vor und nach dem Ausdünnen, Umwege samt Länge,
   `rock_box`, Spawn-Tick gegen `eta`.
5. Ernter 10 Kacheln vor Fels [W2] (Feld 5): Ernter H5 aufgebaut, Fels ab 10 Kacheln östlich seiner Mitte über die ganze Feldhöhe; Befehlsjagd 60 s mit
   `spawn = {160 westlich, Richtung Ost}`, also frontal auf den Fels. OK: Fahrziel im Angriff ist P + 6 · u (hinter P liegt nach 10 Kacheln Fels); nie `patrolling`
   vor dem Biss; kein Umweg in den letzten 40 Kacheln;
   Kopfmitte nie auf Fels; H5 gebissen, Bissverzug 0 bis 180; Wurm danach weg. MESSUNG: kleinster Abstand Kopf–Fels, Weg beim Halten (mit Rasterfehler).
6. Ornithopter über dem Kopf [W12] (Feld 6): Kiste K6, Befehlsjagd 60 s, `spawn = {160 westlich, Richtung Ost}`. 600 Ticks nach dem Spawn steht Ornithopter O6
   (Kohle, Puppe als Pilot) über dem Kopf; 300 Ticks lang alle 10 Ticks `autopilot_destination` = Kopf + 6 · h; die Vergleichsflieger O6b und O6c fliegen
   dasselbe Muster 60 Kacheln nördlich und 60 Kacheln südlich mit einem Punkt, der sich mit dem Kopf mitbewegt. Danach Ruhe: Alle drei behalten ihren letzten
   Zielpunkt, bis alle drei 10 Ticks lang unter 0,05 Kacheln/s sind, höchstens 240 Ticks; der Wurm fährt dabei unter O6 hindurch. Dann fliegen alle drei aus
   der Ruhe 80 Kacheln nach Westen: O6 gegen die Fahrtrichtung über den Körper, O6b und O6c auf den Parallelen. OK: O6 und Pilot mit gleicher Gesundheit,
   keine Sticker außer den Tempo-Stickern des Ornithopters (prototypes/ornithopter-speed.lua), gelesen alle 10 Ticks im Mitflug und jeden Tick in Ruhe und
   Flug; im Mitflug (die 300 Ticks über dem Kopf) mittlerer Abstand O6 zu seinem Zielpunkt höchstens 0,5 Kacheln mehr als im Mittel von O6b und O6c; O6
   mindestens 60 Ticks des Flugs höchstens 3 Kacheln von einem Körperknoten (sonst hat der Flug den Wurm nicht geprüft); in diesen Ticks Tempo von O6
   mindestens 80 % des mittleren Tempos von O6b und O6c in denselben Ticks; Flugzeit der 80 Kacheln O6 ≤ 1,05 × Mittel von O6b und O6c; kommen die drei
   nicht zur Ruhe, ist das ein eigener FEHLER „nicht in Ruhe“ (kein Bremsen); der Wurm fährt unbeirrt weiter (Bissverzug 0 bis 180). MESSUNG: Abstand
   O6–Kopf, die Abstände zum Zielpunkt und die Tempi aller drei während des Mitflugs (O6 unter 98 % des Mittels: INFO), Dauer der Ruhe, die drei Flugzeiten,
   Ticks über dem Körper, kleinster Abstand zu einem Knoten, die drei Tempi in diesen Ticks und die drei Wege bis zum letzten Tick dort; zur Ursache [W12]
   je Flieger die Zahl der Wegpunkte des Autopiloten im ersten Flugtick, die größte Abweichung quer zur Flugrichtung und das Tempo je 20 Ticks in den ersten
   160 Ticks. Abänderung 0.8.1
   (Prüfstand 2026-10-27: Tempo im Mitflug 92 %, Flugzeit 102 %): Die Zielpunkte springen mit Knoten 1 im Raster [W18], dem folgen beide Flieger
   verschieden; der Flug nach Norden begann mit ungleichem Schwung und blieb kaum über dem Körper (im Trockenlauf 0 Ticks höchstens 3 Kacheln von einem
   Knoten, nach Westen 142). Gegenprüfung 0.8.1: Über dem Körper ist O6 nur etwa 140 der 600 Ticks, die Flugzeit allein ließe 5 bis 10 % Bremsen dort
   durch (Prüfstand-Attrappe: 5 % → 101,3 %); der Weg bis zum letzten Tick über dem Körper zeigt 5 % mit etwa 1 Kachel, 3 % mit 0,6. Ein kurzer Sticker
   über dem Körper wäre bis zur Auswertung abgelaufen, daher die Sticker je Tick.
   Abänderung 0.8.2 (Prüfstand 2026-10-27 abends, 0.8.1: über dem Körper 115 Ticks, Tempo dort O6 6,79 / O6b 7,61 Kacheln/s = 89 %, Weg bis zum letzten Tick
   dort 12,82 / 14,42, Flugzeit 603 / 590 Ticks = 102,2 %, Gesundheit und Sticker in Ordnung): Einen Mechanismus dafür kennen die Prototypen nicht. Die Grenze
   ist jetzt das, was im Spiel stört: Bremsen um ein Fünftel und mehr bleibt FEHLER, leichteres ist MESSUNG. Der Weg-Vergleich (O6b − 0,5) fällt weg; er misst
   dasselbe wie das Tempo über dem Körper und schlug bei 89 % schon mit 1,6 Kacheln an. O6c südlich zeigt, wie weit zwei Bahnen ohne Wurm auseinanderliegen;
   die Wegpunkte und die Querabweichung zeigen, ob der Autopilot um den Wurm herumfliegt.
7. Rettung (Feld 7): Ernter H7 aufgebaut mit Puppe, Ornithopter O7 mit Pilot darüber, Befehlsjagd 60 s (Planung frei), bei `eta − 720` `flyer_lib.toggle_carry`
   wie T19 Schritt 4. OK: bei `eta − 590` getragen; der Wurm wartet bis 0 höchstens R + 8 von `last_pos`; bei `eta` `escaped`, Eruption am Kopf, nichts gestorben,
   O7 und Pilot unverändert; Wurm spätestens 30 Ticks nach `eta` abgetaucht (er steht schon dort); Ende bei `eta + 600`.
8. Zerdrücken [W10, W15] (Feld 8): Kiste K8, Befehlsjagd 60 s, `spawn = {160 westlich, Richtung Ost}`; auf der Linie westlich von K8: 5 Bänder quer bei −100,
   Holzkiste bei −90, gerade Schiene quer bei −80, Auto mit Puppe als Fahrer bei −70, Figur zu Fuß bei −60, Hochschiene `elevated-straight-rail` bei −50 (per Skript,
   ohne Stütze), Eisenkiste mit `destructible = false` bei −40, Felsfleck 2 × 2 mit Rand 1,5 Kacheln neben der Linie bei −14 mit einer Kiste ganz darauf
   (Box 1,65 Kacheln von der Linie, also im Zerdrückradius; der Kopf erreicht sie erst im Angriff, dessen Vorausschau nur die Mittellinie prüft. Gegenprüfung
   0.8.0: Bei −30 mit Rand 2,5 lag die Kiste 3,65 Kacheln neben der Linie, und „Felskiste heil“ prüfte die Sandregel nicht),
   Ornithopter mit Pilot schwebend bei −25, Ernter H8 (stehend, Vorsichtsmodus an, Puppe als Fahrer) mit Mitte 3 Kacheln neben der Linie bei −20, Kiste Z
   3 Kacheln westlich von K8. OK: vor `eta` mit Force `arrakis-sandworm` gestorben: 5 Bänder, Holzkiste, Schiene, je in dem Takt, in dem der Kopf höchstens
   2,5 + 0,6 Kacheln entfernt ist; am Leben und mit voller Gesundheit: Auto und Fahrer, Figur, Hochschiene, Eisenkiste, Felskiste, Ornithopter und Pilot, H8 samt
   Fahrer und Laderaum; der Kopf kommt der Felskiste auf höchstens 2,5 Kacheln nahe (sonst ist die Sandregel ungeprüft); Z lebt bis `eta` und stirbt im
   Biss-Takt; kein Abtauchen wegen Stillstand. MESSUNG: ob der Kopf an Eisenkiste, Auto und Figur stehen
   blieb oder durchfuhr (Weg von Knoten 1 in 60 Ticks davor und danach, Raster ±1 [W18]: bei 3,5 Kacheln/s 3 oder 4, bei 2,4 Kacheln/s 2 oder 3, Stehen
   hieße 0 bis 1), Lage von Auto und Figur danach.
9. Ersatzbiss [W3] (Feld 9): Kiste K9, Befehlsjagd 60 s, `spawn = {160 westlich, Richtung Ost, tick = eta − 840}`: Für 155,4 Kacheln braucht er selbst mit
   8,4 Kacheln/s (Sprint und `move_forward`) 18,5 s, das Fenster endet 17 s nach dem Spawn; der Körper bleibt im Feld (160 + 21 < 200).
   OK: K9 stirbt genau bei `eta + 180`, `ersatz == true`, `storage.hunts.ersatz` + 1, der Wurm taucht dort ab, wo er ist (Abstand > R). MESSUNG: mittleres Tempo
   im Sprint (W3 hält ab 5,5) und Anteil des geschriebenen Wegs samt Rastergrenzen, Abstand beim Ersatzbiss.
10. Wurm getötet [W8, W9] (Feld 10): Ernter H10 aufgebaut, `set_heat` 999 (reguläre Jagd). 300 Ticks nach dem Spawn `unit.damage(1000, force)` (A23
    classes.d.ts:18991): MESSUNG Zustand nach 10, 20, 30, 40 Ticks (OK: spätestens nach 40 Ticks wieder `investigating`). 600 Ticks nach dem Spawn
    `unit.die(force)` (:19007). OK: im selben Tick `segmented_unit_died` und Jagd weg, Protokoll `outcome == "killed"`, Statistik `killed` + 1, `first_escape_tick`
    gesetzt, Chat `msg-worm-killed` (Ziel gerettet), 9 Chunks um den Ursprung 0, Sektor ruht noch mindestens 7200 Ticks (`vibration.resting`); H10 lebt bei
    `eta + 60`; keine `simple-entity` und kein Wolframerz im Feld.
11. Wurm verloren [W7] (Feld 11): zwei Kisten 60 Kacheln auseinander, je Befehlsjagd 60 s mit `spawn` von Westen bzw. Osten. 300 Ticks nach dem Spawn
    zerstört der Test Wurm a mit `destroy{raise_destroy = true}`, Wurm b mit `destroy{}`. OK: a im selben Tick `ohne`/`"verloren"`, b binnen 10 Ticks; beide
    Kisten sterben genau bei `eta` (Bissverzug 0) mit Eruption an der Kiste.
12. Flucht per Fahrt [W3] (Feld 2): Ernter H12 aufgebaut mit Puppe als Fahrer, `set_heat` 999 (reguläre Jagd, k0 = 2: Spawn 160 Kacheln nordöstlich).
    Im Tick des Wurmzeichens packt der Test H12 ein (`harvester.pack`, scripts/harvester.lua:520) und gibt nach dem Einpacken Gas genau nach Südwesten
    (`riding_state` an Fahrzeug und Puppe jeden Tick, wie T13), also direkt vom Wurm weg. OK: echter Biss, Bissverzug 0 bis 180, kein Ersatzbiss, Abstand
    Kopf–H12 beim Biss ≤ R. MESSUNG: Sprint-Takte, mittleres Tempo im Sprint und Anteil des geschriebenen Wegs, Ersatz 1 oder 2 aktiv, Weg von H12 seit dem
   Wurmzeichen.
13. Grenzen (Feld 12, nach den Wellen): Vorbedingung: keine Jagd einer anderen Force (sonst INFO und nur MESSUNG). Vier Befehlsjagden mit 60 s auf vier Kisten
    im selben Tick: drei `warten`, die vierte `ohne`/`"grenze"`; danach ein Ernter mit `set_heat` 999: seine reguläre Jagd bekommt trotzdem `warten`
    (Befehlsjagden sperren nichts); eine Befehlsjagd mit 20 s → `ohne`/`"kurz"`; `set_worm_off(force, true)`, dann 60 s → `ohne`/`"aus"`, danach
    `set_worm_off(force, false)`. Alle spätestens 300 Ticks nach den vier Befehlsjagden mit `"abort"` beenden, also vor dem ersten `plan_tick` (Start + 370;
    die reguläre Jagd startet erst im nächsten 60-Tick-Takt): `path_requests` leer, kein Wurm entstanden.
14. Migration und Waisen: Befehlsjagd 60 s, `hunt.phase = nil` und `hunt.r = nil` gesetzt (wie aus 0.7.0, auch nach 0.8.0 → 0.7.0 → 0.8.0 bei `schema` 4),
    `migrate_schema4{hunts = {hunt}}` → `ohne`/`"migration"`, `r` gesetzt; Ende `"abort"`. Ein `arrakis-sandworm-small` ohne Jagd und ein `arrakis-test-worm`
    im Feld: `sweep{Prüfstand}` → 1, der Testwurm ist noch gültig (dann entfernt ihn der Test).
15. Entfernen (immer zuletzt): zwei Befehlsjagden mit 27 s (Spawn 60 Ticks nach dem Start); sobald beide einen Wurm haben, dazu ein Waisenwurm per
    `create_segmented_unit`, dann `worms_lib.uninstall()` → 2 und 3 (zwei Jagdwürmer und die Waise); kein `arrakis-sandworm-*` auf der Prüfstand-Fläche,
    `path_requests` leer, nach 1 Tick gibt es `arrakis-sandworm` nicht mehr. Danach ohne `ensure_force()` eine Befehlsjagd mit 27 s: kein Skriptfehler,
    der Wurm entsteht 60 Ticks nach dem Start (worms legt die Force selbst an), Ende `"abort"`. `cleanup` stellt `paused_until` wie vor dem Test her
    (wie T19, `d.saved.paused`).

**T22 „Sandwurm: Optik und Laden“** (interaktiv, nur mit Max im Spiel, `alle` lässt ihn aus; endet nach 20 min Spielzeit oder mit `stop`). `start` wie T20:
`grace_snapshot` und Statistik-Kopie von Max' Force, `vibration.testbench_enable`, `tb.protect`, Max' Force wach; Sandfläche ±250 mit einer Felsinsel.
`cleanup` wie T20. Vorher `/arrakis-test tempo 1`. Jede FRAGE wartet auf Max' Antwort.
1. Auftauchen: Befehlsjagd 60 s auf eine Kiste 20 Kacheln vor Max, `spawn = {60 Kacheln östlich von Max, Richtung West, tick = jetzt + 120}`. FRAGE: „Siehst du den
   Wurm auftauchen (Staub, Rumpeln)? Ist er sandfarben, ohne Ascheschwaden, ohne dunkle Rauchspur, ohne orange Partikel?“
2. Halten, Biss und Abtauchen: FRAGE: „Wartet der Wurm vor der Kiste fast still bis 0? Kam der Biss genau bei 0 mit Sandfontäne, und tauchte er danach mit Staub und
   Rumpeln ab?“
3. Felsinsel: Befehlsjagd 60 s, Spawn so, dass die Insel zwischen Wurm und Ziel liegt. FRAGE: „Biegt er glatt vor der Insel ab, ohne den Fels zu berühren?“
   Danach ein Ernter 10 Kacheln vor dem Inselrand, Befehlsjagd 60 s mit Spawn frontal auf den Fels hinter ihm. FRAGE: „Wird der Ernter trotzdem gebissen,
   und bleibt der Wurm dabei auf dem Sand?“
4. Zerdrücken: Band, Kisten und ein Auto auf der Linie, eine Kiste auf einem Felsfleck dicht daneben (im Zerdrückradius, 16 Kacheln vor dem Ziel;
   Gegenprüfung 0.8.0). FRAGE: „Verschwinden Band und Kisten am Kopf (Wracks), bleiben das
   Auto und die Kiste auf dem Fels heil, und fährt der Wurm am Auto vorbei oder hindurch, ohne hängen zu bleiben?“
5. Ornithopter [W12]: Max steigt in einen Ornithopter und schwebt über dem fahrenden Kopf, hält an, dann fliegt er voll nach Westen über den Körper weg (der
   Wurm fährt nach Osten; 0.8.1). MESSUNG je Sekunde Tempo, Gesundheit, Abstand zum Kopf und zum nächsten Körperknoten.
   FRAGE: „Merkst du ein Bremsen, Ruckeln oder Schaden?“
6. Rettung: Ernter neben Max, Befehlsjagd 60 s; Max hebt ihn vor 0 an und schwebt über der Stelle. FRAGE: „Hält der Wurm neben dir, beißt ins Leere und taucht ab?“
7. Wurm getötet: Befehlsjagd 60 s; in der Anfahrt ruft der Test `die(player.force)`. FRAGE: „Stirbt der Wurm mit Sandstaub, ohne Leiche und ohne Wolfram, steht im
   Chat ‚… ist gerettet‘, und verschwindet die Jagd oben links?“
8. Factoriopedia: FRAGE: „Steht der Sandwurm unter Gegner mit sandfarbenem Symbol, Name und Beschreibung?“
9. Speichern und Laden [W5, W11]: Befehlsjagd 90 s (`lehr`). `routing` dauert nur von 36,2 s bis 41,2 s nach dem Wurmzeichen (`plan_tick = w + 2170`,
   Spawn bei w + 2470); davor ist die Phase `warten`. Der Test sagt beides per INFO an; Max speichert zwischen 37 und 40 s und lädt (Phase `routing`,
   Kandidat gewählt, Spawn noch offen), nach dem Spawn noch einmal (Phase `anfahrt`). MESSUNG jede Sekunde von 30 s bis zum Biss (ein Laden erkennt der Test
   nicht, die Datei zeigt den Stand davor und danach): Phase, `plan.chosen`, `spawn_tick`, `hunt.path` (offene Anfrage ja/nein), `worm.unit.valid`.
   Auf freiem Sand gibt es meist keine offene Anfrage: W5 gilt nur als geprüft, wenn beim Speichern eine offen war, sonst INFO „W5 offen“
   (der Zeitablauf deckt beide Fälle, 4.5). FRAGE: „Taucht der Wurm auf, fährt er nach dem Laden weiter und beißt bei 0?“
Was Max mit Auge und Ohr prüft (T22 und Abnahme): Farbe, Staub, Partikel, Auf- und Abtauchen, Fahrt um Fels, Ernter vor Fels, Halten vor dem Ziel, Biss, Wracks beim Zerdrücken,
Ornithopter über dem Kopf, Tod des Wurms, Factoriopedia.

**Geänderte alte Tests:**
- T19 (scripts/testbench/t_jagd.lua): `start` ruft `worms_lib.set_worm_off(force, true)` für `arrakis-t19`, Schritt 5 e ebenso für `arrakis-t19b` beim Anlegen;
  `cleanup` schaltet beide zurück. `start` setzt die Statistik heute auf `bitten, escaped, gone = 0, 0, 0` und löscht alle anderen Schlüssel
  (t_jagd.lua:2958–2960); neu kommt `killed = 0` dazu, sonst fehlt das Feld der Test-Force (`stats_for` legt es nur in neuen Datensätzen an, die Migration
  nur bei `old < 4`). Alle Erwartungen bleiben (Biss genau bei 0, Eruption an `last_pos` bzw. `warn_pos`, Zahl der Explosionen in Schritt 4).
- T20: `start` `set_worm_off(player.force, true)`, `cleanup` zurück; sonst unverändert. Hinweis per INFO: „T20 prüft die Warnungen ohne Wurm; den Wurm zeigt T22.“
- T18 (scripts/testbench/t_jagd.lua:728): Schritt 1 prüft heute `{"schema 3", storage.schema == 3}` und meldete mit Schema 4 FEHLER („storage.schema 3
  fehlt“). Neu `{"schema", storage.schema == migrate.SCHEMA}` (Wert aus scripts/migrate.lua:64), Text ohne Zahl; die Tabellen von Schema 4 prüft T21 Schritt 1.
  Andere wörtliche Schemaprüfungen gibt es in den Testmodulen nicht (Grep `schema`: nur :728). Sonst unverändert: Die Lehrjagd aus Schritt 2 endet im Tick
  ihres Wurmzeichens (`"quiet"`), lange vor `plan_tick`; andere Jagden gibt es dort nicht.
- T5 bis T7: unverändert (Testwurm, eigener Prototyp).

`docs/pruefstand.md`: T21 und T22 beschreiben; wo T18 bis T20 stehen (Z. 15, 28, 45, 50, 52, 69–70, 76, 82, 99, 131, 162, 195, 217, 221, 225, 230, 232, 488),
T21 und T22 nachziehen: `alle` um T21; T22 neben T9, T12, T17 und T20 bei den interaktiven; Statusreihenfolge „… T19, T20, T21, T22“; Abschnitt oben um die
Annahmen W1 bis W17; Hinweis, dass T19 und T20 ohne Wurm laufen; Bekannte Grenzen: Ohne Spieler prüft T21 keine Optik und kein Laden, das macht T22.
`tools/pc/pruefstand.py`: Hilfetexte (Z. 34, 767) nennen T9, T12, T17, T20 und T22 als interaktiv.
**Dauer von `alle`:** T21 etwa 11 700 Ticks dazu (drei Wellen zu etwa 3800 Ticks, dazu Vorbereiten und die Schritte 13 bis 15), also etwa 95 000 statt
83 000: gut 26 min ohne Zeitraffer, mit Tempo 10 etwa 20 s mehr. Das Zeitlimit von T21 (300 s Spielzeit) lässt gut 100 s Luft.

**Was Max am Prüfstand tut:** `python tools/pc/pruefstand.py --factorio … T21 T5 T6 T7 T18 T19` (alle ohne FEHLER), Datei schicken; dann T22 mit ihm im Spiel
(vorher `/arrakis-test tempo 1`), Datei und Antworten auf die FRAGEn schicken.

## 7. Prüfung vor der Übergabe
- `tools/check/datastage.py` mit Vanilla 2.1.23 (`fd2123`), mit und ohne `arrakis-testbench`, und `datastage.py fd2123 --ohne quality --set arrakis-testbench=true`.
  2.0.77 nur, wenn die Vanilla-Daten vorliegen (`fd2077` gibt es im Arbeitsordner derzeit nicht); dann prüft es nur die 2.0-Schreibweise.
  `datastage.py --dump` für `arrakis-sandworm-small` und ein Segment (was der deepcopy mitbringt, welche Effekte bleiben); `tools/check/proto_fields.py` ohne Treffer.
- `tools/check/checks.lua` neu für 3d2 (`expected_3d2`, fest im Regelwerk, nicht aus dem Modul gelesen): `segmented-unit` arrakis-sandworm-small, `trivial-smoke`
  arrakis-sandworm-smoke-front, -small-top, -small-bottom, -big, `explosion` arrakis-worm-dive vorhanden. Für alles mit `^arrakis%-sandworm%-` (Kopf und Segmente):
  keine Ascheeffekte (Regel wie für den Testwurm, :151–167), kein Knoten `type = "damage"`, kein `create-sticker`, kein `destroy-cliffs` in `update_effects`,
  `update_effects_while_enraged == nil`, `revenge_attack_parameters == nil`, `loot == nil`, `corpse == nil`, kein `create-entity` mit „corpse“ in
  `dying_trigger_effect`, kein Partikel `vulcanus-*` und kein Rauch `demolisher-*` irgendwo; Kopf: 12 Segmente, alle mit Präfix `arrakis-sandworm-small-`,
  `investigating_speed`, `attacking_speed` und `enraged_speed` je 3,5/60 ± 1e-9, `patrolling_speed` 1/60, `enraged_duration ≤ 60`, `vision_distance == 0`,
  `territory_radius == 1`, kein `autoplace`, keine Ebene `arrakis_rock` in der Maske, Symbol getönt, `localised_name` gesetzt; Segmente versteckt; Rauch sandfarben
  (r > g > b, r ≥ 0,5 · a); `arrakis-worm-dive` ohne `sound`. Bestehende Regeln (Testwurm, Referenzen :87–125, Segmentzahl :144–150) bleiben. Die Namensprüfung
  der Laufzeitdateien liest auch `scripts/sandworm.lua` und `scripts/testbench/t_sandwurm.lua`.
- `tools/check/api_names.py` gegen 2.0.75 und 2.1.23 (factorio-types 1.2.72) ohne neue Treffer; neu benutzt und in beiden belegt: `create_segmented_unit`,
  `get_segmented_units`, `request_path`, `is_chunk_generated`, `get_body_nodes`, `set_ai_state`, `get_ai_state`, `minimum_activity_mode`, `move_forward` und
  `set_body_nodes` (nur Ersatz), `defines.segmented_unit_ai_state`, `defines.segmented_unit_activity_mode`, `on_script_path_request_finished`,
  `on_segmented_unit_died`, `script_raised_destroy_segmented_unit`; in worms.lua neu `on_pre_surface_cleared` (flyer.lua benutzt es schon).
- Statische Regeln wie 3d1: kein `script.on_event`/`script.on_nth_tick` außerhalb von event_handler; keine storage-Schreibzugriffe aus `on_load`; kein `math.random`;
  keine Modultabelle `sandworm` außerhalb ihres Moduls; sandworm.lua ruft kein `die()` und kein `devour` und hat kein `force = "arrakis-sandworm"` (Grep; die
  Force kommt als LuaForce aus worms); jeder `arrakis-message`-Schlüssel aus dem Code steht in
  beiden Sprachen; kein Text nennt die Werkvorlage beim Namen; keine Modellnamen im Repo; `prototypes/noise.lua`, `prototypes/testbench/worms.lua` und
  `scripts/testbench/t_worm.lua` unverändert (`git diff --stat` leer).
- Trockenlauf gegen eine Lua-Attrappe der Engine (wie die 3c- und 3d1-Attrappe), mit einem Wurm als Punktfahrzeug (Beschleunigung 0,55 Kacheln/s², Wenderadius 6,
  folgt `destination`, `speed` schreibbar, Knoten als Spur): Zeiten aus 4.4 für T = 27, 40, 60, 90 und 26 (`kurz`); Kandidatenreihenfolge und k0 für stehende und
  fahrende Ziele, ein Gebäude als Ziel (`speed == nil`) und ein rückwärts fahrendes; Kandidatenprüfung mit Fels, ungenerierten Chunks und einem Auto am
  Spawn; ROUTING mit Erfolg, `try_again_later`, Fehlschlag, Zeitablauf, zu langem Weg, gepflastertem Fels, Box ±3,5 mit Rückgriff auf ±1,5 und einer Tasche mit
  Knick (Sehnen nach dem Ausdünnen ohne Fels, Wegpunktwechsel per Sichtlinie, `angriff` erst nach dem letzten Wegpunkt); Körperprüfung mit Fehlschlag; Wächter
  (Sicherheitsnetz, Vorausschau mit Haltepunkt, Umwege 30/15/8, Neuplanung, Stillstand); Tempo in Anfahrt, Angriff (mit S), Halten und Sprint samt beiden Ersatz-
  stufen; ein Ziel mit R unter 4 vor Fels (Fahrziel P + 6 · u, nie `patrolling`); ein Ziel außer Reichweite (P am Kreis); ein fliehender Ernter; alle Zeilen der
  Tabelle in 4.12; Biss-Fenster mit allen vier Fällen und `eta ≤ bite_tick ≤ eta + 180` in 1000 Zufallsläufen; Zerdrücken mit jeder Ausnahme (Fahrzeug,
  Figur, Force in der Schonfrist) und der Schutzzone mehrerer Jagden; Zerdrücken beim Auftauchen; getötet vor 0 und in der Suche (Text, Ergebnis, `killed`),
  verloren (mit und ohne Ereignis); Grenze für Befehlsjagden neben 3 regulären; Force fehlt nach dem Entfernen; Migration aus Schema 3 und Rundweg über 0.7.0
  (`schema` 4, Jagd ohne `phase` und `r`); `stats_for` mit `killed`, `on_forces_merging` mit `killed`, `on_force_created` mit `worm_off` und `spawn_dir`;
  geleerte Oberfläche (`on_pre_surface_cleared`); `sweep`; Entfernen mit m = Jagdwürmer + Waisen. Dazu: jeder Wechsel auf `ohne` über `to_none` (danach
  `hunt.worm`, `hunt.path` und Einträge der Jagd leer), `"keine-force"` mit lebendem Wurm (taucht ab), `"kein-weg"` an der Frist mit offener Anfrage
  (späte Antwort ändert nichts); `tidy` mit verwaister, umgeleiteter und alter Anfrage; Zeitablauf, nachdem eine Kennung neu vergeben wurde (löscht nur
  den eigenen Eintrag); Fehler aus `create_segmented_unit`, `request_path` und `set_body_nodes` (per `pcall` abgefangen, Logzeile); Sprint-Stufen mit einer
  Attrappe, die v über 3,5 nicht hält (`boost` 1 nach 2 Takten unter 90 %) und danach auch `move_forward` schluckt (`boost` 2; 0.8.1: Biss bis eta + 30
  ohne Ersatzbiss, mit und ohne Raster, auch beim fliehenden Ernter); ein Ziel mit der Mitte auf
  Fels und einer Ecke auf Sand (Biss spätestens als Ersatzbiss oder nach Abtauchen bei 0). Am Ende jedes Laufs: kein Wurm ohne Jagd, keine Jagd mit
  Wurm nach `eta + 600`.
- Prüfstand-Trockenlauf: T21 in der Prüfstand-Attrappe (wie T18 bis T20 für 0.7.0) ohne Skriptfehler bis zum Ende, T22 bis zur ersten FRAGE.
- Lua-Syntaxprüfung aller Dateien.
- Gegenprüfung durch zwei unabhängige Durchsichten (Laufzeit und Prüfstand) wie bei 0.7.0, Befunde vor der Übergabe eingearbeitet.
- Mit dabei: `info.json` 0.8.0; `changelog.txt` (Features: Sandwurm, Auf- und Abtauchen, Route um Fels, Zerdrücken; Changes: Biss bis 3 s nach 0, Befehlsjagd ab 27 s
  mit Wurm, `/arrakis-uninstall` räumt Würmer; Hinweis zum Herunterstufen); `README.md` (Stand, Absatz Würmer, Tabelle „Aufbau“ mit den neuen Dateien);
  `docs/pruefstand.md` (6). DOC danach angleichen (vollständige Liste der Abweichungen):
  1. Prototyp: ohne Kontaktschaden (Kopf und Segmente), Zerdrücken per Skript nur am Kopf (und einmal beim Auftauchen am Körper) mit Sandregel, Schutzzone und
     Ausnahmen; Tempo 3,5 in allen Zuständen, `attacking_speed` 6 entfällt, Sprint per `speed` mit zwei Ersatzstufen; Bohrstaub als eigene Kopien, Partikel in
     Sand, keine Leiche (4.3 „Prototypen“, 2.1 Schritt 9 „zerdrückt der Wurmkörper“: der Kopf; Bänder, Schienen und Gebäude, keine Fahrzeuge und Figuren,
     keine Hochschienen, nichts von Forces in der Schonfrist).
  2. Spawn: `D = min(160, 3,5 · (T − 4))` statt `clamp(v · t, 80, 160)`, 3 s Reserve, Wurm erst ab 27 s, Startrichtung, Abstände 160/120/80 (4.3 Schritt 1).
  3. ROUTING: nur ohne Sandlinie, höchstens 2 Anfragen, Box ±3,5 (Rückgriff ±1,5), Prüfung auf gepflasterten Fels, Ausdünnen nach Sichtlinie, Zeitablauf;
     ohne Weg Biss wie 3d1 statt „entfällt still“ (4.3 Schritt 2).
  4. Körperprüfung mit höchstens 3 Erzeugungen; Auftauchen mit Effekt (4.3 Schritt 3).
  5. ANNÄHERUNG: kein Nachrechnen von `eta_tick`, der Countdown bleibt fest (2.1 Schritt 7); Sprint bei Verspätung (4.3 Schritt 4).
  6. ANGRIFF/BISS: erst nach dem letzten Wegpunkt, Fahrziel 20 bzw. mindestens 6 Kacheln hinter dem Ziel, Drosseln mit dem Restweg; Biss-Fenster bis 3 s,
     Ersatzbiss, Regeln in jedem Takt des Fensters (4.3 Schritte 5 und 6).
  7. ENTKOMMEN entfällt als Zustand: Zielpunkt `last_pos`, am Reichweitenkreis geklemmt, Entscheidung bei 0; SUCHEN bis 8 Kacheln an diesem Punkt
     (Zustandsmaschine, Schritt 8). Das „Zeitlimit t_warn + 60 s“ entfällt: Ein Wurm lebt höchstens bis `eta + 180` (Biss, Ersatzbiss) bzw. `eta + 600`
     (Suche).
  8. Wurm getötet: vor 0 Ende `killed`, Ziel gerettet, in der Suche Ergebnis der Suche; Statistik, ohne Beute (Zustandsmaschine; Beute 3d3). Wurm verloren
     und Abtauchen vor 0: Biss wie 3d1.
  9. Fels-Wächter: ungenerierte Chunks als Fels, Seitenlinien, Haltepunkt für jedes Ziel, Umwege 30/15/8, einmalige Neuplanung, Stillstand (4.3 „Fels-Wächter“).
  10. storage: Felder der Jagd und `path_requests` nach 4.2, `worm_stats.killed`, `hunts.log`, Schema 4 (4.5).
  11. Grenzen: reguläre Jagden immer mit Wurm, Befehlsjagden höchstens 3 mit Wurm, zusammen höchstens 6 (4.3 „Grenzen“). Leistung: Würmer leben 26 bis 59 s
      statt „25 bis 50 s“ (4.4).
  12. Migration 0.7.0 → 0.8.0 und `/arrakis-uninstall` mit Würmern (4.6).
  13. Roadmap 7: 3d2 gebaut, Prüfstand T21 und T22; Risiken 8: Zeile T21/T22 mit W1 bis W17; Unsicherheiten 9: Punkt „Sandwurm 3d2 (T21, T22)“ mit W3, W4, W10, W12;
      Kopf: Mod-Stand 0.8.0 und Bauplan docs/plan-3d2.md.

## 8. Abnahme durch Max (0.8.0)
- `pruefstand.py` mit `T21 T5 T6 T7 T18 T19` (ohne Spieler, Tempo 10): alle ohne FEHLER, Datei schicken. T22 mit dir im Spiel, Datei und Antworten auf die FRAGEn.
- Einen 0.7.0-Spielstand mit laufender Jagd laden: Die Jagd beißt ohne Wurm bei 0 wie gewohnt; die nächste Jagd hat einen Wurm.
- Neues Wurmzeichen (regulär oder `/arrakis-worm` auf einen eigenen Ernter in einer Kopie): etwa 11 s danach taucht etwa 160 Kacheln entfernt ein Sandwurm
  auf (in der Kartenansicht, soweit Radar oder Sicht reichen, oder im Spiel herausgezoomt, sobald er auf etwa 100 Kacheln heran ist), fährt über Sand zum
  Ernter, wartet und beißt genau bei 0 (höchstens 3 s später), dann taucht er ab. Lehrjagd: Auftauchen etwa 41 s nach dem Wurmzeichen.
- Abbiegen vor einer Felsinsel und der Ernter 10 Kacheln vor Fels: In freier Wildbahn wählt die Planung gerade Sandlinien, also zeigt beides T22 Schritt 3
  mit festem Spawn: Der Wurm biegt vor der Insel ab, und der Ernter vor dem Fels wird trotzdem gebissen, ohne dass der Wurm Fels betritt.
- Rettung mit dem Ornithopter vor 0: Der Wurm hält neben dir (etwa 4,6 Kacheln von der Stelle), beißt ins Leere und taucht ab; der Ornithopter wird über
  dem Kopf nicht spürbar langsamer [W12].
- Flucht per Fahrt von einem regulären Feld: Der Wurm holt den Ernter ein (er wird dabei schneller als 3,5 Kacheln/s) und beißt ihn bis 3 s nach 0.
- Flucht per Fahrt vom Lehrfeld auf Fels: Der Wurm hält am Felsrand an, beißt dort ins Leere; er betritt nie Fels.
- Eine Bandstrecke über Sand zwischen zwei Felsinseln: Der Wurm, der sie kreuzt, zerdrückt die Bänder auf seiner Spur (etwa 5 Kacheln breit) und ein Auto oder eine Figur auf der Spur; alles auf Fels bleibt,
  ebenso ein Auto oder ein Ernter neben der Spur.
- Geschütze am Felsrand beschießen den Wurm: Er bleibt auf Kurs (keine Erdspalten), heilt sich, und die Jagd läuft weiter.
- Speichern und Laden während der Anfahrt und während der Planung: der Wurm fährt weiter, der Biss kommt [W5, W11].
- Mit zwei Spielern eine Jagd mit Wurm: beide sehen ihn, kein Desync.
- Drei gleichzeitige Jagden mit Wurm: kein spürbares Ruckeln (sonst T8 vorziehen).
- Auf einer Kopie: `/arrakis-uninstall`, dann `/arrakis-uninstall ja`: alle Würmer weg, keine Markierungen, 10 min kein Wurmzeichen.
- Offen aus 3d1 und 3c: die Abnahme-Punkte aus P3D1 8 und P3C 8/9, die noch ausstehen.
