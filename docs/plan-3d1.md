# Umsetzungsplan Phase 3d1 (0.7.0): Vibration, Wärme, Unruhe, Wurmzeichen, Countdown, Schonfrist, Briefings, Vorsichtsmodus und geskripteter Biss

Stand 26.10.2026. Grundlage: Design v0.3 (docs/design-ernter-ornithopter.md, kurz DOC), Plan 3b (docs/plan-3b.md), Plan 3c
(docs/plan-3c.md, kurz P3C), Code 0.6.1 (main 0f9d582), Max' Entscheidung vom 26.10.2026 („Würmer starten“: erste Wurm-Stufe 0.7.0).
API-Belege: A23 = factorio-types 1.2.72 (API 2.1.23, `dist/classes.d.ts`, `concepts.d.ts`, `events.d.ts`, `prototypes.d.ts`,
`types.d.ts`, `defines.d.ts`), A20 = typed-factorio 3.36.0 (API 2.0.75), V23 = Vanilla-Daten 2.1.23. Dieser Plan ist der Bauvertrag:
Namen, Dateien, Zustände, Zahlen und Texte gelten so, wie sie hier stehen. Wo der Plan von DOC abweicht, gilt der Plan; DOC wird danach
angeglichen (Liste in 7).

Max' Wunsch (P3C): Spice-Ernter, „die man via ornikopter transportiert (und auch vor den würmern retten kann)“. 3c hat das Tragen gebaut.
3d1 liefert die Gefahr, vor der man rettet: Vibration auf Sand heizt die Gegend auf, der Sand bebt, ein Wurmzeichen kündigt den Biss an,
und nach dem Countdown bricht eine Sandfontäne hervor. Einen sichtbaren Wurm gibt es noch nicht (3d2).

**Kennzeichnung:** **[Vn]** markiert eine Aussage, die auf noch nicht geprüftem Engine-Verhalten beruht. Abschnitt 4.17 sagt je Annahme,
welcher Test sie entscheidet und was gilt, wenn sie nicht hält. Die Nummern enden vor V23; V23 bleibt die Abkürzung für die Vanilla-Daten.

## 0. Umfang

**In 0.7.0**
- Vibration: Ernter, Fahrzeuge und arbeitende Gebäude auf Sand vibrieren mit festen Gewichten (4.3).
- Wärme je Chunk mit Zerfall 2 % je Sekunde, gewertet über die 3×3-Nachbarschaft (4.4); Sektoren aus 4×4 Chunks, höchstens eine Jagd
  je Sektor, höchstens drei zugleich, danach 2 bis 4 Minuten Ruhe (4.5).
- Unruhe ab 600: Sandstaub, Rumpeln, Status „Der Sand bebt“ (4.12).
- Wurmzeichen ab 1000: Alarm, Kartenmarkierung, Warnton, roter Ring mit Sekunden (grün, sobald das Ziel sicher steht), Fenster oben links,
  Status am Ernter (4.10); Countdown 60 s, die erste Jagd jeder Force auf einen Spice-Ernter ist eine Lehrjagd mit 90 s (4.8).
- Geskripteter Biss genau bei 0, ohne Wurm-Entity: Eruption, Ton, Tod des Ziels und von allem auf Sand im Umkreis von 4 Kacheln;
  Mod-Einstellung `arrakis-worm-bite` wirkt (4.9). Getragen, ganz auf Fels, außer Reichweite des Wurms (3,5 Kacheln je Sekunde Countdown)
  oder weg: kein Biss, der Wurm „sucht“ 10 s (4.7).
- Schonfrist je Force: 10 min nach „Ornithopter“, spätestens 30 min nach der ersten Landung auf Arrakis, sichtbar oben links (4.6).
- Briefings: Tipps-und-Tricks-Einträge `arrakis-briefing` und `arrakis-wormsign-tip`, dazu je eine Chatzeile (4.13).
- Vorsichtsmodus: Schalter im Ernterfenster; packt bei Unruhe ein, baut bei Ruhe wieder auf (4.11).
- Vibrationsanzeige: umschaltbare Verknüpfung `arrakis-vibration-overlay`, zeigt die Wärme der Chunks um den Spieler (4.12).
- Admin-Befehl `/arrakis-worm [Sekunden|lehr]` (Jagd auf die ausgewählte Entity), Statistik je Force als Vorbereitung für den Thumper.
- Migration 0.6.x und 0.5.x → 0.7.0 (Schema 3), `/arrakis-uninstall` räumt auch Jagden, Markierungen, Fenster und Anzeigen (4.16).
- Prüfstand: T18 (Wärme, automatisch), T19 (Jagd, automatisch), T20 (Bedienung, interaktiv).

**Nicht in 0.7.0**
- Die Wurm-Entity (`segmented-unit`), verzögerter Spawn, Route, ROUTING, Fels-Wächter, Abtauchen, Körperprüfung, Zerdrücken von
  Bändern und Gebäuden auf dem Weg, Biss „höchstens 3 s nach Countdown-Ende“: 3d2 (0.8.0, DOC 4.3 Schritte 2 bis 7, T5 bis T7).
- Thumper (Ablenkung, Köder, Forschung `scripted`), Beute und Wurmzahn, großer Wurm ab 2000, Mod-Einstellungen für die Zahlen,
  Balancing-Runde (Ziel 15 Pakete/min): 3d3 (0.9.0). 3d1 zählt dafür schon `storage.worm_stats` (4.2).
- Frühwarnung, Ernte-Dämpfung, Rettung durch Carryalls: 3e/3f. 2.1-Komfort (Pins, Musik, `LuaForce.add_custom_alert`): 3g.
- Zweig `factorio-2.0`: bleibt bei 0.5.0 (DOC 5.2). Prototypen und Laufzeit bleiben trotzdem 2.0-tauglich (3, 7).

## 1. Festlegungen (Standardwahl, Max kann widersprechen)

| Punkt | Festlegung | Grund |
|---|---|---|
| Werte | Alle Zahlen sind Konstanten im Code (4.1), keine Mod-Einstellung; nur `arrakis-worm-bite` gibt es schon | Wie in 3b und 3c; die Einstellungen kommen mit der Balancing-Runde 3d3 (DOC 2 „werden als Mod-Einstellungen änderbar“) |
| Module | `scripts/vibration.lua` (Quellen, Wärme, Unruhe, Vorsichtsmodus, Anzeige), `scripts/worms.lua` (Schonfrist, Jagden, Biss, Warnungen, Sandwurm-Force, Briefing-Chat, `/arrakis-worm`), `scripts/worms-gui.lua` (Fenster oben links) | DOC 4.0 nennt `worms.lua`; die Vibration ist eigenständig und wird von 3d2/3d3 weiterbenutzt. Kein `debug.lua`: Der eine Befehl steht in worms.lua |
| Takte | Nur worms.lua hat `on_nth_tick(60)` und `on_nth_tick(10)` für die Würmer und ruft vibration.lua in fester Reihenfolge auf (4.4); worms-gui 30 Ticks | event_handler sichert keine Reihenfolge zwischen Modulen zu (P3C 4.1), `on_nth_tick` hat keinen Versatz (A23 classes.d.ts:4565–4573). Wärme, Vorsichtsmodus, Unruhe und Wurmzeichen müssen im selben Takt aufeinander folgen |
| Sand | Natürliche Kachel ungleich `arrakis-rock` (`terrain.natural_tile_name`, scripts/terrain.lua:30–33); „ganz auf Fels“ heißt `not terrain.has_sand_under(entity)` (scripts/terrain.lua:47–66) | Wie 3b: gepflasterter Fels ist Fels, gepflasterter Sand bleibt Sand (plan-3b.md 1). DOC 4.3 prüfte nur sichtbare Sandkacheln |
| Oberflächen | Vibration und Jagden nur, wo `terrain.harvest_allowed(surface)` (Arrakis; mit Prüfstand auch `arrakis-testbench`, dort nur für eingeschaltete Test-Forces, 4.18) | Laborkacheln zählen als Sand; ohne die Sperre heizten alte Prüfstand-Aufbauten die Testfläche |
| Gewichte Ernter | aufgebaut 30 (auch bei „Laderaum voll“, „Feld erschöpft“, „Kein Treibstoff“), beim Einpacken 30, beim Einpacken durch den Vorsichtsmodus 0, beim Aufbauen 0, mobil fahrend (`math.abs(speed) ≥ 0,001` Kacheln/Tick) 10, stehend, angedockt, getragen 0 | DOC 4.3; der aufgebaute Ernter steht verankert auf dem Feld, ob er fördert oder nicht. Vorsichtsmodus mit 0 siehe Zeile „Vorsichtsmodus“ |
| Gewichte sonst | Panzer (`tank`) 8, anderes `car` 4, `spider-vehicle` 6 (nicht `arrakis-ornithopter`), `locomotive` 6, jeweils nur fahrend; `big-mining-drill` 8, `pumpjack` 2, anderer `mining-drill` 3, `assembling-machine` und `furnace` 1, jeweils nur bei `status == working`; alles andere 0 und nicht eingetragen | DOC 4.3 Tabelle. Wagen, Bänder, Rohre, Masten, Spieler zu Fuß und Flieger vibrieren nicht |
| Anmelden | Fahrzeuge bei jedem Bau, Klon und Einsteigen auf einer erlaubten Oberfläche; feste Gebäude, wenn unter der Box Sand liegt, neu gewertet bei Kachel-Ereignissen; Ernter immer über `storage.harvesters` | DOC 4.3; Fahrzeuge prüfen den Sand jeden Takt an der Position, weil sie vom Fels in den Sand fahren |
| Wärme | Je Oberfläche und Chunk: `H ← H · 0,98^Δs + ΣV · min(Δs, 2)` im 60-Tick-Takt, alle Einträge jeden Takt; Einträge unter 1 ohne Quelle fliegen raus, eine Oberfläche ohne Einträge verliert ihren Wärme-Datensatz (4.4 Schritt 7) | DOC 4.3. Δs ist im 60-Tick-Takt immer 1: `on_nth_tick(60)` fällt nie aus, und eine leere Oberfläche beginnt neu mit `tick − 60`. `min(Δs, 2)` bleibt nur als Absicherung wie beim Ernter (DOC 4.0 „höchstens 2 s“) |
| Nachbarschaft | S(c) = Summe der Wärme über die 3×3 Chunks um c, gespeichert je Takt (`sum3`). Am Ort einer Quelle gilt W = größtes S(d) über die 3×3 Chunks d um ihren Chunk | W ist der Wert, mit dem irgendein Wurmzeichen-Kandidat die Quelle erfasst; nur so hält der Vorsichtsmodus jede Schwelle ein |
| Schwellen | Unruhe W ≥ 600, Wurmzeichen S(d) ≥ 1000 und S(d) im Takt davor ≥ 600; 2000 (großer Wurm) erst in 3d3 | DOC 4.3. Die Zusatzbedingung erfüllt „jedes neue Wurmzeichen kündigt sich mit Unruhe an“ auch bei vielen Quellen |
| Zeiten | Ein Ernter allein: Unruhe im 26. Takt (594,8 → 612,9), Wurmzeichen im 55. Takt (996,1 → 1006,2), also 1500 bis 1619 bzw. 3240 bis 3359 Ticks nach „aufgebaut“ (4.4: der erste Takt mit Beitrag liegt 0 bis 119 Ticks danach). Gilt ab kaltem Sand (abgesetzt per Ornithopter oder vorher 2 min gestanden). Nach der Anfahrt aufs Lehrfeld (41 bis 59 Kacheln mit Gewicht 10, dann 5 s Aufbau) liegen schon etwa 200 bis 260 an: Unruhe nach etwa 15 bis 19 s, Wurmzeichen nach etwa 45 bis 48 s | H_n = 1500 · (1 − 0,98^n); n ≥ ln 0,6 / ln 0,98 = 25,28 und n ≥ ln 3 / 0,020203 = 54,38. DOC 2.1: „etwa 25 s“, „etwa 55 s“. Die Fahrspur (höchstens 59 Kacheln, also höchstens 3 Chunks in einer Reihe) liegt immer ganz in einer 3×3-Summe neben dem Ernter (nachgerechnet für alle Richtungen und Chunk-Lagen) |
| Ziel | Stärkste berechtigte Quelle in der 3×3-Nachbarschaft des heißen Chunks; gleich stark: Ernter vor anderen, dann kleinste `unit_number`. Ursprung ist der Chunk des Ziels | DOC 4.3 „die stärkste Quelle in der Nachbarschaft“; feste Reihenfolge für den Mehrspieler |
| Berechtigt | Gewicht > 0 in diesem Takt, auf Sand, Force wach (4.6), nicht getragen, nicht schon Ziel, sein Sektor ohne Jagd und nicht in Ruhe, Lehrjagd-Regel | Sonst träfe ein Wurmzeichen eine stehende Kiste oder eine Force in der Schonfrist |
| Grenzen | Höchstens 1 Jagd je Sektor (4×4 Chunks), 3 zugleich über alle Forces und Oberflächen, 1 neue je Takt und Oberfläche; Befehlsjagden zählen nicht mit und sperren nichts | DOC 4.3 „Grenzen“; die Thumper-Ausnahme aus DOC kommt in 3d3 an dieselbe Stelle |
| Ende | Jede Jagd außer per Befehl setzt am Ende die Wärme der 3×3 Chunks um den Ursprung auf 0, und der ganze Sektor des Ursprungs ruht `rng(7200, 14400)` Ticks; während der Ruhe tragen seine Quellen nichts bei, seine Einträge bleiben 0 | DOC 4.3; „gefressen oder entkommen“ gilt genauso für „Ziel weg“ |
| Zufall | Nur die Ruhezeit kommt aus `storage.rng` (gespeichert, A23 classes.d.ts:11748, Grenzen einschließlich :17440); Staubwolken liegen an festen Stellen aus Tick und `unit_number` | DOC 4.0; deterministisch im Mehrspieler, und Kosmetik verbraucht keine Zufallszahlen |
| Countdown | 60 s (3600 Ticks), Lehrjagd 90 s (5400); er verlängert sich nie. Wurmzeichen entsteht im 60-Tick-Takt, also ist `eta_tick` ein Vielfaches von 10, und der Biss fällt genau im 10-Tick-Takt bei `eta_tick` | DOC 2.4 „Ein Biss kommt nie vor Ablauf des Countdowns“; Roadmap 3d1 „Biss genau bei 0“ |
| Lehrjagd | Die erste Jagd jeder Force auf einen Spice-Ernter; solange sie läuft, bekommt dieselbe Force keine zweite. Jagden auf Gebäude und Fahrzeuge haben immer 60 s und sperren nichts. Ist bei Schonfrist-Ende schon genug Wärme da, kommt sie im Takt des Erwachens (4.4: Schritt 3 Schonfrist vor Schritt 5 Wurmzeichen) | DOC 2.1 Schritte 4 und 7, 2.4: Die Lehrjagd lehrt die Flucht vom Lehrfeld, also gehört sie dem Ernter. Sie ist die Ausnahme vom Abnahmekriterium (Zeile „Flucht per Fahrt“) |
| Entscheidung | Erst beim Biss-Tick: getragen oder auf einer anderen Oberfläche → entkommen; ganz auf Fels → entkommen; weiter als die Reichweite `reach = 3,5 · (eta_tick − warn_tick) / 60` Kacheln von `warn_pos` (60 s: 210, Lehrjagd: 315) → entkommen; ungültig → weg; sonst Biss an der jetzigen Position, auch wenn das Ziel inzwischen woanders steht | DOC 2.4 „Was vollständig auf Fels steht oder getragen wird, wird nie gefressen“ und Zahlenregel „langsamer als der Wurm (3,5 Kacheln/s)“: Wer schneller ist, entkommt auch ohne Fels. Ohne Wurm-Entity folgt der Biss dem Ziel, aber nur so weit, wie ein Wurm käme; 3d2 lässt den echten Wurm hinterherfahren. Ein Ernter (≤ 1,41 Kacheln/s, in 60 s höchstens 85 Kacheln) bleibt immer in Reichweite. Ohne die Grenze träfe der Biss eine Lokomotive (bis 72 Kacheln/s) kilometerweit weg. Alternative (Frage an Max): In 3d1 werden nur Ernter und feste Gebäude Ziel, Fahrzeuge heizen nur |
| Ziel weg | Wird das Ziel vor 0 zerstört oder abgebaut, läuft der Countdown als „Ziel verloren“ weiter; bei 0 harmlose Eruption an der letzten Stelle auf Sand | Spieler sehen, dass die Gefahr echt war; keine Schäden an Unbeteiligten |
| Suchen | Entkommen oder weg: Zustand „sucht“ 600 Ticks ohne Biss, dann Ende mit Rücksetzen und Ruhe. Gebissen: sofort Ende | DOC 2.1 Schritt 9 „Er sucht 10 s und taucht ab“ |
| Angedockt | Keine Ausnahme: Ein angedockter Ernter ist sicher, wenn seine ganze Box auf Fels steht | DOC 2.4 Regel. Die Annahme sichert nur ±5 Kacheln Fels (scripts/intake.lua:26), der Ernter reicht bis 4 + 1,58 = 5,58 |
| Force-Wechsel | Die Jagd läuft weiter; Warnungen wechseln zur neuen Force, erkannt im 10-Tick-Takt (4.7) | Ein Wurm kennt keine Forces. Für `entity.force = …` gibt es kein Ereignis (A23 events.d.ts kennt nur `on_player_changed_force` :2161 und das Verschmelzen :1015, :1040) |
| Biss | Eruption `arrakis-worm-eruption` am Ziel; Opfer sind alle Entities mit Gesundheit, deren Box höchstens 4 Kacheln von der Zielmitte entfernt liegt und Sand berührt; ausgenommen Ornithopter samt Insassen, Spinnenbeine, Ressourcen, Leichen, Geister, Klippen, `destructible == false`, die Sandwurm-Force und Insassen eines Fahrzeugs, das überlebt. Erst sammeln, dann töten | DOC 2.1 Schritt 9 und 2.4 „Ornithopter in der Luft werden nie getroffen“. `die()` löst `on_entity_died` sofort aus (A23 classes.d.ts:6712–6724) [V1] und ändert dabei storage |
| Täter | `die("arrakis-sandworm")`, ohne `cause` | Eine Wurm-Entity gibt es nicht; die Force zeigt in Statistik und Todesmeldung, wer es war |
| Totalverlust | Standard: Kofferraum und Treibstoff des Ernters leeren, Insassen töten, dann `die`; das Wrack `tank-remnants` bleibt (vom Panzer geerbt, V23 base/prototypes/entity/entities.lua:7961) | Mod-Einstellung „Totalverlust: Ernter und Ladung weg, das Wrack bleibt“ (locale/de/arrakis.cfg:106) |
| Schwer beschädigt | Einstellung `heavy-damage`: jeder Spice-Ernter im Radius überlebt mit `max(1, 0,1 · max_health)`, Kofferraum leer, Treibstoff bleibt, wird mobil (angedockt: abgedockt), Insassen bleiben; alles andere stirbt trotzdem | Text der Einstellung (locale/de/arrakis.cfg:107): „Ernter überlebt, Ladung weg“. Gilt nur für Ernter, nicht für andere Fahrzeuge |
| Sandwurm-Force | `arrakis-sandworm`, angelegt in `on_init`, in der Migration und bei Bedarf; in beide Richtungen feindlich zu jeder Force außer `neutral`, auch zu neuen | DOC 4.3; wie `tb.worm_force` (scripts/testbench/runner.lua:500–511), damit T5 bis T7 dieselbe Force benutzen |
| Warnungen | Je Spieler der Force: eigener Alarm mit Symbol `arrakis-wormsign`, Warnton ohne Position; für die Force: Kartenmarkierung (nur Symbol), roter Ring mit Radius 4 und Sekunden am Ziel, Fenster oben links, Status am Ernter. Steht das Ziel sicher (ganz auf Fels oder außer Reichweite), wird der Ring grün, und Fenster und Status sagen „sicher“; geht es zurück auf Sand, wieder rot | DOC 4.3 WURMZEICHEN. Die Lehrjagd soll die Flucht lehren; ohne Rückmeldung sähe der Spieler nicht, ob der Ernter schon ganz auf Fels steht (Box ±0,9/±1,3, angedockt bis 5,58 Kacheln Reichweite). Der 10-Tick-Takt prüft den Sand ohnehin (4.7). `LuaForce.add_custom_alert` gibt es erst in 2.1 (A23 classes.d.ts:11013, A20 hat sie nicht), deshalb die Schleife über die Spieler wie in scripts/harvester.lua:191–196 |
| Getragen | Während das Ziel getragen wird oder auf einer anderen Oberfläche steht: Alarm, Ring und Sekunden weg, Fenster zeigt „wird getragen: erst nach 0 auf Sand absetzen“; zurück auf der Oberfläche der Jagd kommt alles wieder | Ein Alarm auf die Ablage `arrakis-hold` führte ins Leere; Render-Objekte verlieren ihr Ziel ohnehin (DOC 4.2) |
| Pins, Musik | Keine | `LuaPin` (2.1.10) und `play_music` gehören zur Komfortschicht 3g |
| Schonfrist | Je Force: `active_from = min(Ornithopter erforscht + 36000, erste Landung + 108000)`; wach ab dann, nie wieder zurück. Vorher gibt es Vibration und Unruhe, aber keine Jagd | DOC 2.1 Schritt 3 und 4.3. Im Mehrspieler mit mehreren Forces hat jede ihre eigene (DOC 4.5 kennt nur eine) |
| Erste Landung | `on_player_changed_surface` und zusätzlich jede Sekunde: ein verbundener Spieler der Force mit `physical_surface.name == "arrakis"` (A23 classes.d.ts:16571). Die Prüfstand-Fläche zählt nicht | Fernsicht soll nicht als Landung zählen [V3] |
| Anzeige Schonfrist | Fenster oben links „Die Wüste regt sich in 9:42“ für alle verbundenen Spieler der Force, sobald `active_from` feststeht; Chat beim Start und jedes Mal, wenn der Termin früher wird; beim Ende „Die Wüste ist erwacht“ | DOC 2.1 Schritt 3 |
| Vorsichtsmodus | Schalter je Ernter (Kontrollkästchen im Ernterfenster). W ≥ 600: aufgebaut → einpacken mit Gewicht 0, beim Aufbauen → abbrechen; dann warten. Steht er noch an der Stelle (≤ 0,25 Kacheln) und W < 300: wieder aufbauen. Fahren, Anheben, Andocken oder `Umschalt+H` beenden das Warten. Gilt auch in der Schonfrist; eine laufende Jagd hebt er nicht auf | DOC 2.1 Schritt 6, 4.1. Einpacken mit 0 statt 30 (Abweichung von DOC 4.1): Mit 30 stiege die Wärme von zwei Erntern im selben Chunk beim Einpacken von 600 auf 3000 − 2400 · 0,98^10 = 1039, also über die Wurmzeichen-Schwelle |
| Vorsichts-Zyklus | Ein Ernter allein: 16 s ernten (267 → 608), 36 s warten samt 10 s Einpacken (608 → 296), 5 s aufbauen, also 57 s, 28 % Erntezeit, etwa 7 Pakete/min | DOC 3.1 „im Vorsichtsmodus etwa 7/min“ passt; DOC 4.1 nannte 14 s/34 s. Mit Gewicht 30 beim Einpacken wären es 78 s und 20 % |
| Grenze Vorsicht | Ein Ernter im Vorsichtsmodus wird nie selbst Ziel, solange er aufgebaut ist oder aufbaut: Ein Wurmzeichen verlangt W ≥ 600 im Takt davor, und in dem Takt packt er schon mit Gewicht 0 (bzw. bricht das Aufbauen ab). Fahrend (10) und beim Einpacken von Hand (30) zählt er wie jeder Ernter. Gefahr bleibt als Opfer im Bissradius eines anderen Ziels und bei einer schon laufenden Jagd; viele Ernter senken nur die Ausbeute | Zeile „Schwellen“: W ist das größte S(d) um den Ernter, also W im Takt davor ≥ `prev3[d]` für jedes d, dessen Nachbarschaft ihn erfasst. Beispiel: 40 Vorsichts-Ernter in einem Chunk (1200/s) geben im ersten Takt S = 1200 ohne Wurmzeichen (prev3 = 0) und packen alle; im zweiten ist keiner berechtigt |
| Vibrationsanzeige | Verknüpfung `arrakis-vibration-overlay` (`toggleable`, frei mit „Spice-Ernte“); je Spieler 7×7 Chunks um die Stelle, die er sieht: gefülltes Rechteck je Chunk mit S(c) ≥ 1 (grün unter 600, gelb bis 999, rot ab 1000, grau in Ruhe) und die Zahl bzw. „Ruhe 2:31“; nur in der Spielansicht | DOC 3 und 4.0 „normales Spielerwerkzeug“; Render-Objekte nur für diesen Spieler |
| Fenster Ernter | Zwei Zeilen „Vibration: 30/s, Wärme 612“ und Countdown, Kontrollkästchen „Vorsichtsmodus“ mit Warte-Zeile | DOC 4.1 Anzeige |
| Status Ernter | Vorrang: Wurmzeichen (rot, „Wurmzeichen! Biss in 37 s“; sicher: grün, „Wurmzeichen: sicher (noch 37 s)“) vor Vorsicht wartet (gelb) vor Unruhe (gelb, „Der Sand bebt“) vor dem Zustand aus 3b/3c; auch im Zustand mobil | DOC 2.1 Schritte 6 und 7 |
| Unruhe-Effekte | Je Quelle auf Sand mit Gewicht > 0 und W ≥ 600: 1 + floor((W − 600) / 200), höchstens 3 Staubwolken 3 bis 10 Kacheln entfernt, höchstens 24 Quellen je Oberfläche und Takt; Rumpeln je Sektor höchstens alle 300 Ticks | DOC 2.1 Schritt 6; gedeckelt, damit 50 Ernter das Spiel nicht mit Rauch füllen |
| Briefings | Tipps `arrakis-briefing` (Forschung „Entdeckung Arrakis“) und `arrakis-wormsign-tip` (Forschung „Spice-Ernte“, eingerückt) in der Space-Age-Kategorie hinter Aquilo; dazu immer je eine Chatzeile an die Force. `allow_tip_activation` schreibt die Mod nie | DOC 2.1 Schritt 0, DOC 6. Das Szenario entscheidet, ob Tipps erscheinen (A23 classes.d.ts:12053–12057, Standard false) [V4]; die Chatzeile kommt immer |
| Befehlsjagd | `/arrakis-worm [Sekunden\|lehr]`: Admin, ausgewählte Entity mit Gesundheit und `unit_number` (Bäume, Felsen und Klippen haben keine) auf einer erlaubten Oberfläche (sonst `worm-cmd-not-allowed`), 5 bis 600 s (Standard 60, `lehr` 90); ohne Schonfrist und Grenzen, am Ende ohne Rücksetzen, Ruhe, Statistik und Lehrjagd-Merker | DOC 4.0 „Debug“; zum Ausprobieren im eigenen Spielstand, ohne das Spiel zu verstellen |
| Statistik | `storage.worm_stats[force_index] = {bitten, escaped, gone, first_escape_tick}` | DOC 6: „Thumper“ erforscht sich nach der ersten überstandenen Jagd (3d3) |
| Flucht per Fahrt | Kein Sonderfall: Einpacken 10 s, dann 50 s × 1,41 = 70,5 Kacheln. Lehrfeld (bis 59 + 1,3) entkommt, reguläre Felder (≥ 100) nicht. In der Lehrjagd (80 s × 1,41 ≈ 112,8) entkommt man auch von regulären Feldern bis etwa 111 Kacheln vom Fels. Die Reichweite (Zeile „Entscheidung“, 210 bzw. 315 Kacheln) erreicht ein Ernter nie; ihn retten nur Fels und Anheben | DOC 2.4 Abnahmekriterium gilt für die Vorwarnzeit 60 s; die Lehrjagd ist die bewusste Ausnahme (Frage an Max) |
| Entfernen | `/arrakis-uninstall ja` beendet zusätzlich alle Jagden ohne Biss, löscht Markierungen, Ringe, Alarme, Fenster und Anzeigen, schaltet die Verknüpfungen aus, pausiert neue Wurmzeichen 10 min und verschmilzt die Sandwurm-Force mit `enemy` | Kartenmarkierungen und Forces blieben nach dem Entfernen der Mod im Spielstand (DOC 4.6) |
| Herunterstufen | Auf 0.6.x: vorher `/arrakis-uninstall ja`; sonst bleiben Markierungen laufender Jagden und die Sandwurm-Force | 0.6.x kennt beides nicht |
| Mindestversion | unverändert `base >= 2.1.23`, `space-age >= 2.1.23` | Die Geräusche kommen aus Space Age, das ohnehin Pflicht ist |

## 2. Dateien

Neu:
- `prototypes/worms.lua`: Eruption, Sandstaub, Signal, zwei Geräusche, Verknüpfung, zwei Tipps (3).
- `scripts/vibration.lua`: Quellen, Gewichte, Wärme, Sektoren und Ruhe (Speicher), Vorsichtsmodus, Unruhe-Effekte, Vibrationsanzeige.
  Modultabelle `lib`, andere binden sie als `vibration_lib`.
- `scripts/worms.lua`: Takte, Schonfrist, Wurmzeichen, Jagden, Biss, Warnungen, Sandwurm-Force, Briefing-Chat, `/arrakis-worm`,
  Migration Schema 3, Entfernen. Modultabelle `lib`, andere binden sie als `worms_lib`.
- `scripts/worms-gui.lua`: Fenster oben links (Schonfrist und Jagden).
- `scripts/testbench/t_jagd.lua`: T18, T19, T20 (der Name `t_worm.lua` gehört T5 bis T7).

Geändert: `data.lua` (require `prototypes.worms` nach `prototypes.technology`, vor `prototypes.testbench.init` und `compat.finish`),
`control.lua` (Reihenfolge 4.1), `settings.lua` (Kommentar Z. 11), `scripts/harvester.lua`, `scripts/harvester-gui.lua`,
`scripts/flyer.lua` (nur `/arrakis-uninstall`), `scripts/migrate.lua`, `locale/{de,en}/arrakis.cfg`, `locale/{de,en}/messages.cfg`,
`scripts/testbench/runner.lua` (ORDER, Modulliste, Vertrag), `tools/check/checks.lua`, `tools/pc/pruefstand.py` (Hilfetexte Z. 34 und 767:
interaktiv sind T9, T12, T17 und T20), `info.json`, `changelog.txt`, `README.md`, `docs/pruefstand.md` (6), DOC (danach, 7).

Unverändert: `scripts/intake.lua`, `scripts/hold.lua`, `scripts/flyer-gui.lua`, `scripts/terrain.lua`, `scripts/arrakis-surface.lua`,
alle Prototypen aus 3b und 3c, `prototypes/noise.lua` (die veröffentlichten Ausdrücke `arrakis_v2_*` und `arrakis_v3_*` bleiben, wie sie sind),
alle bisherigen Testmodule (T1 bis T17 laufen wie bisher; die Isolation in 4.18 schützt sie).

## 3. Prototypen (2.0-Schreibweise; `compat.finish` setzt 2.1 um)

Alles in `prototypes/worms.lua`. Sandtönung `SAND = {r = 1, g = 0.85, b = 0.6}`. Dateipfade nur, wie sie in V23 wörtlich vorkommen; ein falscher
Sound- oder Bildpfad bricht das Laden ab. Keine eigenen Sprite-Prototypen: Fenster und Chat nutzen `[virtual-signal=arrakis-wormsign]`.

**Eruption** `arrakis-worm-eruption` (`explosion`, A23 prototypes.d.ts:3889): `table.deepcopy(data.raw.explosion["big-artillery-explosion"])`
(V23 base/prototypes/entity/explosions.lua:4443), dann
- `localised_name = {"entity-name.arrakis-worm-eruption"}`, `icons = {{icon = "__base__/graphics/icons/explosion.png", tint = SAND}}`,
  `order = "z[arrakis]-a[worm-eruption]"`, `hidden = true` und `flags = {"not-on-map"}` bleiben.
- Jede Animation in `animations` (mit `layers`: jede Ebene) bekommt `tint = SAND`; `scale = 1.5`.
- In `created_effect` wird jedes `particle_name = "explosion-stone-particle-<größe>"` zu `"sand-1-stone-particle-<größe>"` (tiny, small, medium;
  V23 base/prototypes/particles.lua:2979, :3010, :3030); dazu ein Eintrag `{type = "create-trivial-smoke", smoke_name = "arrakis-sand-dust",
  repeat_count = 8, offset_deviation = {{-3, -3}, {3, 3}}, speed_from_center = 0.04}` (A23 types.d.ts:3614–3628, `repeat_count` :13335).
- `sound = {variations = {{filename = "__space-age__/sound/explosions/demolisher-explosion-1.ogg", volume = 1}, {… -2.ogg …}}}`
  (V23 space-age/prototypes/entity/sounds.lua:645). Ausgeschrieben statt `sound_variations`, damit die Datei nicht von core/lualib/sound-util.lua abhängt.

**Sandstaub** `arrakis-sand-dust` (`trivial-smoke`, A23 prototypes.d.ts:10651): deepcopy von `data.raw["trivial-smoke"]["demolisher-mining-smoke-big"]`
(V23 space-age/prototypes/entity/smoke.lua:269), `color = {0.80, 0.65, 0.40, 0.6}`, sonst geerbt (Dauer 300 Ticks, ohne Wind).

**Signal** `arrakis-wormsign` (`virtual-signal`, A23 prototypes.d.ts:12454): `icons = {{icon = "__base__/graphics/icons/signal/signal-alert.png",
tint = {r = 1, g = 0.55, b = 0.2}}}` (V23 base/prototypes/signal.lua:117), `subgroup = "virtual-signal"`, `order = "e[alert]-z[arrakis-wormsign]"`.
Es ist das Symbol für Alarm, Kartenmarkierung, Fenster und Tipp; Schaltungsausgänge kommen mit 3f.

**Geräusche** (`sound`, A23 prototypes.d.ts:9174–9250):
- `arrakis-wormsign`: `category = "alert"` (A23 types.d.ts:10320), Varianten `__space-age__/sound/enemies/demolisher/demolisher-roar-big-1.ogg` bis `-6.ogg`,
  `volume = 0.9` (V23 space-age/prototypes/entity/sounds.lua:588).
- `arrakis-rumble`: `category = "environment"`, `filename = "__space-age__/sound/enemies/demolisher/demolisher-tail-rumble.ogg"`, `volume = 0.6`
  (V23 space-age/prototypes/entity/sounds.lua:508, :628), `audible_distance_modifier = 2`.

**Verknüpfung** `arrakis-vibration-overlay` (A23 prototypes.d.ts:8900–8966): `action = "lua"` (:8904), `toggleable = true` (:8961, Pflicht für
`set_shortcut_toggled`), `technology_to_unlock = "arrakis-spice-harvesting"` (:8957), `unavailable_until_unlocked = true` (:8965),
`localised_name = {"shortcut-name.arrakis-vibration-overlay"}`, `order = "e[spidertron-remote]-z[arrakis-c]"` (hinter den beiden aus 3c),
`icons` und `small_icons` = `{{icon = "__base__/graphics/icons/signal/signal-alert.png", icon_size = 64, tint = SAND}}`. Keine Taste.

**Tipps** (`tips-and-tricks-item`, A23 prototypes.d.ts:10410–10474; Muster V23 space-age/prototypes/tips-and-tricks.lua:6–47):
- `arrakis-briefing`: `category = "space-age"` (:10414), `order = "e-a"` (hinter Aquilo `d-a`, V23 space-age/prototypes/tips-and-tricks.lua:129–132), `tag = "[planet=arrakis]"` (:10460),
  `trigger = {type = "research", technology = "planet-discovery-arrakis"}` (:10464, A23 types.d.ts:9201–9204), kein `skip_trigger`, keine Simulation,
  `localised_name = {"tips-and-tricks-item-name.arrakis-briefing"}`, `localised_description = {"tips-and-tricks-item-description.arrakis-briefing"}`.
- `arrakis-wormsign-tip`: wie oben, `order = "e-b"`, `indent = 1` (:10439, wie `lightning-mechanics`), `tag = "[virtual-signal=arrakis-wormsign]"`,
  `trigger = {type = "research", technology = "arrakis-spice-harvesting"}`.
  Die Locale-Kategorien der Tipps sind lokal nicht belegt (V23 enthält keine Übersetzungen), deshalb stehen die Namen ausdrücklich da.

Keine Änderung an Forschungen, keine neue Taste, kein neues Item.

## 4. Laufzeit

### 4.1 Module und Ereignisse
`control.lua` lädt per event_handler: `scripts.migrate`, `scripts.arrakis-surface`, `scripts.harvester`, `scripts.harvester-gui`, `scripts.intake`,
`scripts.hold`, `scripts.flyer`, `scripts.flyer-gui`, `scripts.vibration`, `scripts.worms`, `scripts.worms-gui`, (Prüfstand). `on_init` und
`on_configuration_changed` laufen in dieser Reihenfolge; für Ereignisse gilt weiter: jeder Fall gehört genau einem Modul (P3C 4.1).
Abhängigkeiten ohne Kreis: `vibration` → `harvester`, `terrain`; `worms` → `vibration`, `harvester`, `terrain`, `worms-gui`;
`harvester-gui` → `harvester`, `vibration`, `worms`; `flyer` → `worms` (nur für `/arrakis-uninstall`). `worms-gui` liest nur storage.

`scripts.vibration` stellt bereit: `tick(tick)`, `careful_tick(tick)`, `unrest_tick(tick)`, `overlay_tick(tick)` (nur von worms.lua gerufen),
`near_heat(surface, position) → W`, `chunk_key(cx, cy)`, `sector_key(cx, cy)`, `key_of(position) → chunk_key, sector_key`, `sum3(surface_index, key)`,
`weight_of(entity) → weight, on_sand`, `source_of(entity)`, `register(entity) → record|nil`, `scan(surface, area|nil) → n`, `resting(surface_index, sector_key) → until|nil`,
`rest(surface_index, sector_key, ticks)`, `reset_around(surface_index, key)`, `set_careful(h, on, player|nil) → ok`, `overlay_off(player_index)`,
`drop_surface(surface_index)`, Prüfstand-Haken (4.18), Konstanten `DECAY = 0.98`, `MAX_DT = 2`, `UNREST = 600`, `WORMSIGN = 1000`,
`CAREFUL_LOW = 300`, `CAREFUL_RANGE = 0.25`, `MOVING = 0.001`, `WEIGHTS` (4.3), `DUST_MAX = 24`, `RUMBLE_TICKS = 300`, `OVERLAY_RADIUS = 3`.

`scripts.worms` stellt bereit: `start_hunt(entity, opts) → hunt|nil, reason` (`opts = {seconds, teaching, debug, bite}`), `hunt_of(entity)`,
`end_hunt(hunt, outcome, mode)` (`mode` nil, `"quiet"` oder `"abort"`, 4.7), `grace_of(force)`, `ensure_force() → LuaForce`, `migrate_schema3(opts)`, `uninstall() → n`, Prüfstand-Haken (4.18),
Konstanten `WARN_TICKS = 3600`, `TEACH_TICKS = 5400`, `SEARCH_TICKS = 600`, `BITE_RADIUS = 4`, `WORM_SPEED = 3.5` (Kacheln/s, für `reach`), `REST_MIN = 7200`, `REST_MAX = 14400`,
`MAX_HUNTS = 3`, `GRACE_ORNITHOPTER = 36000`, `GRACE_LANDING = 108000`, `HEAVY_HEALTH = 0.1`, `PAUSE_TICKS = 36000`, `DEBUG_MIN = 5`,
`DEBUG_MAX = 600`, `FORCE = "arrakis-sandworm"`, `ICON = {type = "virtual", name = "arrakis-wormsign"}`.

`scripts.worms-gui` stellt bereit: `refresh(player)`, `refresh_force(force)`, `destroy(player)`.

Ereignisse (Handler prüfen zuerst Name bzw. Typ und kehren sonst zurück):

| Ereignis | vibration.lua | worms.lua | worms-gui.lua |
|---|---|---|---|
| `on_built_entity` (A23 events.d.ts:272), `on_robot_built_entity` (:4120), `script_raised_built` (:5271), `script_raised_revive` (:5322) | Quelle anmelden (4.3) | – | – |
| `on_entity_cloned` (:688) | Klon anmelden | – (eine Jagd folgt nie dem Klon) | – |
| `on_player_driving_changed_state` (:2552, `entity` optional, `player_index` Pflicht: nur echte Spieler) | Fahrzeug anmelden, falls unbekannt | – | – |
| `script_raised_teleported` (:5364) | Oberfläche neu werten (verlässt sie die erlaubten: austragen) | – (der 10-Tick-Takt sieht den Ort) | – |
| `on_player_built_tile` (:1990), `on_robot_built_tile` (:4149), `script_raised_set_tiles` (:5343–5360) | feste Quellen im Kachelbereich neu werten (Sand, Anmelden) | – | – |
| `on_entity_died` (:761), `on_player_mined_entity` (:2816), `on_robot_mined_entity` (:4237), `script_raised_destroy` (:5288) | – (ungültige Quellen fallen im Takt raus) | Ziel einer Jagd im Zustand warning: `lost = true`, Warnungen weg (4.7); im Zustand biting nichts | – |
| `on_lua_shortcut` (:1549, `prototype_name == "arrakis-vibration-overlay"`) | Anzeige umschalten | – | – |
| `on_player_changed_surface` (:2199) | Anzeige der alten Oberfläche löschen | Landung prüfen (4.6) | – |
| `on_player_joined_game` (:2723) | Verknüpfungszustand angleichen | alle Wurmzeichen-Alarme des Spielers löschen (`remove_alert{type = custom, icon = ICON}`, auch alte aus Jagden, die endeten, während er weg war) und ihn aus jedem `alerted` streichen, die Sekundenarbeit setzt die laufender Jagden neu | Fenster aufbauen |
| `on_player_left_game` (:2762), `on_player_removed` (:2983) | Anzeige löschen | `alerted` des Spielers vergessen | Fenster weg |
| `on_player_changed_force` (:2161) | – | wie bei `on_player_joined_game`: Wurmzeichen-Alarme des Spielers löschen und ihn aus jedem `alerted` streichen; die Sekundenarbeit setzt ihm die Alarme seiner neuen Force (sonst behielte er die der alten bis zu deren Ende) | Fenster neu |
| `on_research_finished` (:4000) | – | „Ornithopter“: `ornithopter_tick`; „Entdeckung Arrakis“, „Spice-Ernte“: Chatzeile (4.13) | – |
| `on_force_created` (:957) | – | Sandwurm-Force feindlich setzen; einen vorhandenen Schonfrist- oder Statistik-Datensatz unter `event.force.index` verwerfen (4.14) | – |
| `on_forces_merging` (:1040) | Prüfstand-Merker der Quelle löschen | Jagden der Quelle: `force_index` der Ziel-Force und `redraw = true` (4.7); Statistik addieren, Datensätze der Quelle löschen (4.14) | – |
| Force-Wechsel einer Entity (`entity.force = …`) | – (der Takt liest die Force jedes Mal neu) | kein Ereignis: 10-Tick-Takt (4.7) | – |
| `on_pre_surface_deleted` (:3940), `on_surface_cleared` (:4850) | Wärme, Ruhe, Rumpeln, Anzeigen dieser Oberfläche weg | gelöscht: Jagden dort ohne Biss beenden | – |

Dazu worms `on_nth_tick` 60 und 10 (4.4), worms-gui `on_nth_tick` 30, worms `add_commands` (`/arrakis-worm`), worms und migrate
`on_init`/`on_configuration_changed` (4.16), harvester-gui `on_configuration_changed` (offene Ernterfenster schließen, unten). Den Kontrollkasten „Vorsichtsmodus“ behandelt harvester-gui (`on_gui_checked_state_changed`,
A23 events.d.ts:1076) und ruft `vibration_lib.set_careful`.

`scripts.harvester` bekommt (sonst unverändert):
- `remove_alerts` (scripts/harvester.lua:185–189) filtert nach dem eigenen Symbol: `player.remove_alert{entity = entity, type = defines.alert_type.custom,
  icon = {type = "item", name = SPICE}}` (AlertFilter mit `icon`, A23 concepts.d.ts:130–138). Sonst löschte „Laderaum voll ist vorbei“ auch das Wurmzeichen.
- `write_custom_status` (Z. 167–183): vor dem Zustand der Vorrang aus 1 (`h.alarm_hunt_eta` mit `h.alarm_hunt_safe`, `h.careful_wait`, `h.alarm_unrest`);
  getragen bleibt `state-carried`. Geschrieben wird nur, wenn sich Text oder Sekunde ändern (`h.status_written`, ein Schlüssel wie `"hunt:37"` bzw. `"safe:37"`).
- `lib.set_alarm(h, kind, value, safe)` mit `kind = "hunt"` (eta oder nil; `safe` true oder nil) bzw. `"unrest"` (true oder nil), schreibt über `write_custom_status`.
- `lib.register` legt die neuen Felder mit Startwerten an: `careful = false`, `vib_weight = 0`, `vib_sand = false` (0.6.x-Datensätze: 4.16).
- `lib.toggle` (Z. 521–555): `h.careful_wait = nil` vor der Zustandsweiche (der Spieler übernimmt). `lib.lift` (Z. 557–575) und `lib.dock`:
  `careful_wait`, `careful_pos`, `careful_packing` auf nil. `set_mobile` (Z. 347–369) setzt `careful_packing = nil`.
- Kopfkommentar: neue Felder, Verweis auf diesen Plan.

`scripts.harvester-gui` (Aufbau Z. 54–74): unter dem Treibstoff die Labels `arrakis_vibration` und `arrakis_hunt`, das Kontrollkästchen
`arrakis_careful` (Tooltip `gui-careful-tooltip`, `state = h.careful == true`, A23 classes.d.ts:12977 verlangt ein boolean) und das Label
`arrakis_careful_wait`; der 30-Tick-Takt füllt sie (4.11, 4.12), Zahlen mit `or 0` (Ernter außerhalb erlaubter Oberflächen haben nach dem
ersten Takt keinen `vib_key` mehr, 4.4 Schritt 3; ihre Wärme ist 0). `arrakis_hunt` zeigt `gui-hunt`, mit `alarm_hunt_safe` `status-wormsign-safe`, ohne Jagd
nichts. Neu: harvester-gui `on_configuration_changed` schließt alle offenen Ernterfenster (`close` für jeden Eintrag in `storage.gui_open`). Ein in 0.6.x offen
gespeichertes Fenster hat die neuen Elemente nicht, und `update` schriebe dann in `frame.arrakis_vibration` (nil) einen Skriptfehler; beim nächsten Öffnen
baut `build` das Fenster vollständig.

### 4.2 storage (Schema 3)
```lua
storage.schema = 3
storage.rng = LuaRandomGenerator                  -- game.create_random_generator() (Kartenseed), nur für Ruhezeiten
storage.grace[force_index] = {
  landed_tick = tick|nil, ornithopter_tick = tick|nil,
  active_from = tick|nil,                         -- min(ornithopter_tick + 36000, landed_tick + 108000)
  awake = false,                                  -- wird nie wieder false
  announced = tick|nil,                           -- zuletzt im Chat genannter active_from
  first_hunt = hunt_id|nil, first_hunt_done = false,
}
storage.vib = {
  sources = {[un] = {un, entity, kind = "vehicle"|"fixed", base = gewicht, sand = bool|nil,  -- fixed: beim Anmelden, vehicle: letzter Takt
                     weight = 0, key = chunk_key|nil, surface = surface_index}},              -- weight, key: Stand des letzten Takts
  heat = {[surface_index] = {tick = T, chunks = {[chunk_key] = h},
                             sum3 = {[chunk_key] = s}, prev3 = {[chunk_key] = s}}},          -- 3×3-Summen dieses und des letzten Takts
  rumble = {[surface_index] = {[sector_key] = tick}},
  overlay = {[player_index] = {surface = surface_index, cells = {[chunk_key] = {rect = LuaRenderObject, text = LuaRenderObject, stage}}}},
  testbench = {[force_index] = true},             -- nur Prüfstand (4.18)
}
storage.hunts = {next_id = 1, list = {[id] = hunt}, paused_until = tick|nil}
hunt = {
  id, kind = "harvest"|"vehicle"|"building", debug = false, teaching = false, bite = nil|"total-loss"|"heavy-damage", -- bite nur per Befehl/Prüfstand
  target = LuaEntity, target_un, force_index, surface_index,
  target_name = LocalisedString,                  -- entity.localised_name beim Start (A23 classes.d.ts:8173), für Alarm, Fenster und Chat, auch nach dem Tod
  origin_key, sector_key,                         -- Chunk und Sektor des Ziels beim Wurmzeichen
  state = "warning"|"biting"|"searching", warn_tick, eta_tick, end_tick|nil,
  warn_pos = {x, y}, last_pos = {x, y},           -- last_pos: letzte Stelle mit Sand unter dem Ziel
  reach = Kacheln,                                -- 3,5 · (eta_tick − warn_tick) / 60, fest ab dem Start (4.7)
  safe = false|"rock"|"far",                     -- Stand des 10-Tick-Takts: ganz auf Fels bzw. weiter als reach von warn_pos
  lost = false, outcome = nil|"bitten"|"escaped"|"gone",
  tag = LuaCustomChartTag|nil, tag_logged = true|nil,  -- tag_logged: Fehlschlag von add_chart_tag schon geloggt (4.10)
  renders = {ring = LuaRenderObject|nil, text = LuaRenderObject|nil},
  second = n, hidden = false, alerted = {[player_index] = true},
  redraw = true|nil,                              -- nach on_forces_merging: Ring, Text, Markierung für force_index neu (4.7, 4.14)
}
storage.sector_cooldown[surface_index][sector_key] = until_tick
storage.worm_stats[force_index] = {bitten = 0, escaped = 0, gone = 0, first_escape_tick = nil}
storage.harvesters[un] = {…,                      -- wie Schema 2 (P3C 4.2), dazu:
  careful = false, careful_wait = true|nil, careful_pos = {surface = surface_index, x, y}|nil, careful_packing = true|nil,
  vib_weight = 0, vib_key = chunk_key|nil, vib_sand = bool,   -- Stand des letzten Takts (Fenster, Wurmzeichen)
  alarm_unrest = true|nil, alarm_hunt_eta = tick|nil, alarm_hunt_safe = true|nil, status_written = string|nil,
}
storage.migration.worms_pending = true|nil        -- von migrate gesetzt, von worms abgearbeitet (4.16)
storage.migration.worm_notice = true|nil
```
Schlüssel: `chunk_key(cx, cy) = (cx + 65536) · 131072 + (cy + 65536)` mit cx = floor(x / 32); `sector_key` ebenso aus sx = floor(cx / 4).
Zurück: `cx = floor(key / 131072) − 65536`, `cy = key mod 131072 − 65536`. Die Karte reicht ±1 000 000 Kacheln, also ±31 250 Chunks; die Schlüssel bleiben unter 2^35.
`migrate.init()` legt `rng`, `grace`, `vib` (mit allen Untertabellen), `hunts`, `sector_cooldown` und `worm_stats` an. Abweichungen von DOC 4.5:
`grace` je Force; `vib.heat` je Oberfläche mit `sum3`; keine Felder für den Wurm (`spawn_tick`, `candidates`, `route`, `worm`: 3d2);
`sector_cooldown` je Oberfläche. Jagd-Feld `kind`: `"harvest"` und `"building"` wie DOC, dazu `"vehicle"`; `"thumper"` erst in 3d3.

### 4.3 Vibrationsquellen und Gewichte
Ernter stehen nicht in `vib.sources`: Der Takt geht über `storage.harvesters` (scripts/harvester.lua), Gewicht aus dem Zustand:

| Ernter-Zustand | Gewicht |
|---|---|
| `deployed` (jeder Status) | 30 |
| `packing` | 30, mit `careful_packing` 0 |
| `deploying` | 0 |
| `mobile`, `math.abs(speed) ≥ 0,001` (A23 classes.d.ts:8523) | 10 |
| `mobile` stehend, `docked`, `carried` | 0 |

Andere Quellen (`vib.sources`), `kind = "vehicle"` mit Gewicht nur bei `math.abs(speed) ≥ 0,001` (auch Spidertron: `speed` ist lesbar, A23 classes.d.ts:8519):
`car` mit Name `tank` 8, anderes `car` außer `spice-harvester` 4, `spider-vehicle` außer `arrakis-ornithopter` 6, `locomotive` 6.
`kind = "fixed"` mit Gewicht nur bei `status == defines.entity_status.working` (A23 classes.d.ts:8548, defines.d.ts:739) [V13]:
Name `big-mining-drill` 8, Name `pumpjack` 2, andere `mining-drill` 3, `assembling-machine` 1, `furnace` 1. Andere Typen werden nicht eingetragen.

- **Sand:** Ernter und Fahrzeuge: `terrain.natural_tile_name(surface, position.x, position.y) ~= "arrakis-rock"` an der Mitte (Signatur scripts/terrain.lua:30–33), jeden Takt. Feste Quellen: `sand = terrain.has_sand_under(entity)`
  beim Anmelden und bei Kachel-Ereignissen; eine feste Quelle auf Fels wird gar nicht erst eingetragen (`register` gibt nil zurück).
- **Anmelden** (`register`): nur auf einer erlaubten Oberfläche (1), nur gültige Entities der Typen oben, eine Quelle je `unit_number`.
  Bau, Klon, Einsteigen und `scan` rufen es; `scan(surface, area)` sucht einmal `find_entities_filtered{type = {"car", "spider-vehicle", "locomotive",
  "mining-drill", "assembling-machine", "furnace"}, area}` (A23 classes.d.ts:20487) und meldet an, was fehlt (Migration, Prüfstand).
- **Kachel-Ereignisse:** Bereich der Kacheln (umschließendes Rechteck, für `script_raised_set_tiles` aus `tiles`), darin `find_entities_filtered{type = …feste…}`:
  eingetragene neu werten, uneingetragene auf Sand anmelden. Pflastern ändert die natürliche Kachel nicht und braucht nichts.
- **Austragen:** Der Takt wirft Quellen mit ungültiger Entity oder auf einer nicht erlaubten Oberfläche hinaus. Keine eigene Anmeldung für
  `on_object_destroyed`: `register_on_object_destroyed` gäbe für einen Ernter dieselbe Nummer wie in harvester.lua zurück und überschriebe `storage.reg`.
- **Prüfstand-Fläche:** Auf `arrakis-testbench` zählen Quellen und Ernter nur, wenn ihre Force in `storage.vib.testbench` steht (4.18); sonst schreibt der
  Takt Gewicht 0 (kein Beitrag, kein Staub, nie Ziel; Ernter wie in 4.4 Schritt 3). Auf Arrakis immer.

### 4.4 Wärme: Takt und Formel
worms `on_nth_tick(60)` (Reihenfolge fest): 1. `vibration.tick`, 2. `vibration.careful_tick` (4.11), 3. Schonfrist (4.6), 4. `vibration.unrest_tick` (4.12),
5. Wurmzeichen (4.8), 6. Sekundenarbeit der Jagden (Alarme, Markierung, Fenster-Merker, 4.10), 7. `vibration.overlay_tick` (4.12).
worms `on_nth_tick(10)`: Jagden nachführen und beißen (4.7, 4.9); kehrt sofort zurück, wenn `storage.hunts.list` leer ist.

`vibration.tick(tick)` je erlaubter Oberfläche s mit Quellen, Wärme oder Einträgen in `storage.sector_cooldown[s]`:
1. `e = storage.vib.heat[s]` (neu: `{tick = tick − 60, chunks = {}, sum3 = {}, prev3 = {}}`), `Δs = (tick − e.tick) / 60`, `f = 0,98^Δs`, `m = min(Δs, 2)`.
2. Jeder Eintrag: `h ← h · f`.
3. Jede Quelle (Ernter und `vib.sources`) auf s: Gewicht w und Sand bestimmen (4.3), in den Datensatz schreiben (`weight`/`vib_weight`, `key`/`vib_key`, `vib_sand`).
   Mit w > 0, auf Sand und Sektor nicht in Ruhe: `chunks[key] = (chunks[key] or 0) + w · m`.
   Jeder Ernter, der in diesem Takt auf keiner gewerteten Oberfläche steht (getragen auf der Ablage, auf einer anderen Oberfläche, auf der Prüfstand-Fläche
   mit ausgeschalteter Force), bekommt `vib_weight = 0`, `vib_key = nil`, `vib_sand = false`, `careful_wait = nil`, `careful_pos = nil` und
   `set_alarm(h, "unrest", nil)`. Sonst wählte 4.8 ihn nach einem alten `vib_key` als Ziel, und Fenster und Status zeigten alte Werte. Eine Schleife über
   `storage.harvesters` für alle Oberflächen; die Ernter auf s zählen dann wie oben.
4. Ruhende Sektoren (`storage.sector_cooldown[s]`): abgelaufene (`until ≤ tick`) streichen, in den übrigen jeden Eintrag auf 0; eine leere Tabelle
   `sector_cooldown[s]` fliegt raus.
5. Einträge unter 1, zu denen in Schritt 3 keine Quelle beitrug, löschen.
6. `prev3 = sum3`; `sum3` neu, gestreut: Jeder Eintrag h im Chunk c addiert h zu `sum3[d]` für die 9 Chunks d um c (so erfasst S auch Chunks ohne Eintrag).
7. `e.tick = tick`. Hat `e.chunks` danach keinen Eintrag mehr, wird `storage.vib.heat[s]` gelöscht; der nächste Takt mit einer Quelle legt ihn mit
   `tick − 60` neu an (Schritt 1). So bleibt Δs immer 1, und die erste Quelle nach einer leeren Zeit zählt nicht doppelt.

`near_heat(surface, position)` = größtes `sum3[d]` über die 9 Chunks d um den Chunk von `position` (fehlende zählen 0, ohne `heat[s]` ist es 0). Es gilt für Vorsichtsmodus,
Unruhe, Fenster; die Vibrationsanzeige zeigt `sum3[c]` selbst.

Rechnung für einen Ernter allein (Gewicht 30 ab dem ersten Takt nach „aufgebaut“): H_n = 30 · (1 − 0,98^n) / 0,02 = 1500 · (1 − 0,98^n).
H_25 = 594,8, H_26 = 612,9: Unruhe im 26. Takt. H_54 = 996,1, H_55 = 1006,2, und S im Takt davor ≥ 600: Wurmzeichen im 55. Takt.
Der erste Takt liegt 0 bis 59 Ticks nach „aufgebaut“, also Unruhe 1500 bis 1559 und Wurmzeichen 3240 bis 3299 Ticks danach; läuft der 10-Tick-Takt
des Ernters im selben Tick nach dem 60-Tick-Takt, zählt der erste Takt erst 60 Ticks später (Prüfung in T18 mit ± 60). Zerfall ohne Quelle:
1000 · 0,98^10 = 817,07; ein Eintrag mit 1,5 fällt nach 21 Takten unter 1 (1,5 · 0,98^21 = 0,98).

### 4.5 Sektoren, Grenzen, Ruhe
- Sektor = 4×4 Chunks (`sector_key` aus floor(cx / 4), floor(cy / 4)), also 128 × 128 Kacheln. Je Sektor höchstens eine Jagd (nicht per Befehl).
- Höchstens `MAX_HUNTS = 3` Jagden zugleich (`warning`, `biting`, `searching`, nicht per Befehl), über alle Forces und Oberflächen; je Takt und
  Oberfläche höchstens eine neue. Blockiert: im nächsten Takt neu versuchen, nichts merken.
- **Ende einer Jagd** (`end_hunt`, nicht per Befehl): `reset_around(s, origin_key)` setzt die 9 Chunks um den Ursprung auf 0 (auch über die Sektorgrenze),
  dann `rest(s, sector_key, storage.rng(REST_MIN, REST_MAX))`, also 7200 bis 14400 Ticks (2 bis 4 min). Während der Ruhe bleibt der ganze Sektor auf 0 (4.4 Schritt 4),
  und seine Quellen sind nicht berechtigt. Danach beginnt die Wärme bei 0, also kommt vor jedem Wurmzeichen wieder Unruhe.
- `storage.hunts.paused_until` (nur nach `/arrakis-uninstall`): bis dahin kein neues Wurmzeichen.

### 4.6 Schonfrist
- **Datensatz** je Force, angelegt bei Bedarf (`grace_of(force)`), nur für Forces außer `enemy`, `neutral` und `arrakis-sandworm`.
- **Ornithopter:** `on_research_finished` mit `research.name == "arrakis-ornithopter"` (A23 events.d.ts:4000) setzt `ornithopter_tick = tick`, falls nil.
  Zusätzlich jede Sekunde: erforscht (`force.technologies["arrakis-ornithopter"].researched`, A23 classes.d.ts:22293) und nil → jetzt. Das deckt Forschungen
  ab, die ein Skript ohne Ereignis setzt (migrate.lua erforscht seit 0.6.1 selbst) [V2]. Wird die Forschung zurückgenommen (`on_research_reversed`), bleibt der Wert.
- **Erste Landung:** `on_player_changed_surface` und jede Sekunde für Forces mit `landed_tick == nil`: ein verbundener Spieler der Force mit
  `player.physical_surface.name == "arrakis"` (A23 classes.d.ts:16571) → `landed_tick = tick` [V3]. Spieler in einer Frachtkapsel über Arrakis zählen,
  sobald die Engine sie auf die Oberfläche stellt.
- **Termin:** `active_from` = Minimum der vorhandenen Werte `ornithopter_tick + 36000` und `landed_tick + 108000`, sonst nil. Neu berechnet wird nur,
  wenn `ornithopter_tick` oder `landed_tick` gerade gesetzt wurden (Ereignis, Sekundentakt, Migration, `set_grace` ohne `active_from`, 4.18). Wird er gesetzt
  oder früher, Chatzeile `msg-grace-start` an die Force mit der Restzeit (m:ss) und `announced = active_from`.
- **Erwachen:** `tick ≥ active_from` → `awake = true`, Chat `msg-grace-awake`, Fenster neu. Einmal wach, immer wach. Weil die Schonfrist im
  60-Tick-Takt vor dem Wurmzeichen läuft (4.4 Schritte 3 und 5), kann die erste Jagd schon im Takt des Erwachens beginnen.
- **Lehrjagd-Merker:** Die erste Ernter-Jagd (`kind == "harvest"`) einer wachen Force setzt `first_hunt` und hat 5400 Ticks; solange sie läuft
  (`storage.hunts.list[grace.first_hunt] ~= nil`), sind die Quellen dieser Force nicht berechtigt. Beim Ende einer Jagd bekommt jeder
  Schonfrist-Datensatz mit `first_hunt == hunt.id` (nach einem Force-Wechsel des Ziels also der der alten Force, nicht der von `hunt.force_index`)
  `first_hunt = nil` und `first_hunt_done = true`, egal wie sie ausging; ein Ende mit `"abort"` setzt nur `first_hunt = nil` und lässt `first_hunt_done`
  stehen (die nächste Ernter-Jagd ist wieder eine Lehrjagd). Nur eine Ernter-Jagd setzt die Merker; Jagden auf Gebäude und Fahrzeuge haben immer 60 s und sperren nichts.
  Befehlsjagden berühren die Merker nicht.
- **Anzeige:** worms-gui zeigt allen verbundenen Spielern der Force `worm-gui-grace` mit m:ss, solange `active_from` gesetzt und `awake == false` ist.
  Die Prüfstand-Fläche zählt nie als Landung; Test-Forces stellen ihre Schonfrist selbst (4.18).

### 4.7 Jagd ohne Wurm-Entity: Zustände und Übergänge
| Zustand \ Eingabe | Biss-Tick (`tick ≥ eta_tick`, 10-Tick-Takt) | Ziel getragen oder andere Oberfläche | Ziel ungültig, gestorben, abgebaut | Ziel wechselt die Force | `end_tick` erreicht | Oberfläche gelöscht |
|---|---|---|---|---|---|---|
| warning, Ziel da | Entscheidung (unten) | `hidden = true`: Alarme, Ring, Sekunden weg, Fenster „wird getragen“; zurück auf der Oberfläche: alles neu | `lost = true`, Alarme, Ring, Sekunden weg, Fenster „Ziel verloren“; Countdown läuft (ohne Ereignis: der 10-Tick-Takt sieht es) | im 10-Tick-Takt: `force_index` neu, alte Alarme weg, Ring, Text und Markierung für die neue Force neu | – | Ende `"abort"` |
| warning, `lost` | harmlose Eruption an `last_pos`, → searching, `outcome = "gone"` | – | – | – | – | wie oben |
| biting | (nur innerhalb des Biss-Aufrufs) | – | wird ignoriert (eigene Tötung) | – | – | – |
| searching | – | – | – | – | Ende (normal) | wie oben |

**Entscheidung am Biss-Tick** (in dieser Reihenfolge):
1. `lost` oder Ziel ungültig → weg (`gone`).
2. Ernter mit Zustand `carried` (auch in `storage.stranded`) oder Ziel auf einer anderen Oberfläche → entkommen (`escaped`).
3. `not terrain.has_sand_under(target)` → entkommen (ganz auf Fels, auch angedockt).
4. Abstand von `target.position` zu `warn_pos` größer als `hunt.reach` → entkommen (schneller als der Wurm, DOC 2.4).
5. Sonst → Biss (4.9) an `target.position`, `outcome = "bitten"`, Ende sofort.
Bei 1 bis 4: `arrakis-worm-eruption` an `last_pos` (bei 4 an `warn_pos`: so weit kam der Wurm nicht; harmlos, keine Opfer), immer auf der Oberfläche
der Jagd (`surface_index`), Chat `msg-escaped` bzw. `msg-gone`, `state = "searching"`, `end_tick = eta_tick + 600`; im Fenster „Der Wurm sucht“. Im selben
Aufruf gehen Alarme (4.10 „Weg“), Ring und Sekunden weg, und `harvester.set_alarm(h, "hunt", nil)` setzt den Status zurück; nur die Markierung bleibt bis
zum Ende. Sonst stünde 10 s lang ein roter Ring mit „0“ am entkommenen Ziel. Ein Ziel, das während des Suchens wieder auf Sand steht, wird nicht gebissen.

**Nachführen im 10-Tick-Takt** je Jagd im Zustand warning, mit `redraw` auch im Zustand searching (höchstens 3 + Befehlsjagden Sandprüfungen je 10 Ticks):
- Ziel ungültig, ohne dass ein Ereignis kam (`destroy()` ohne `raise_destroy`) → wie „Ziel ungültig“ in der Tabelle: `lost = true`, Warnungen weg
  (Alarme über den Oberflächen-Filter, 4.10).
- Ziel gültig und `target.force_index ~= hunt.force_index` (A23 classes.d.ts:5636) → Force-Wechsel: Alarme über `alerted` weg (4.10), Ring und Text
  mit `forces = {neue Force}` neu, Markierung der alten Force zerstören (`valid` prüfen) und für die neue setzen, `force_index` neu, Fenster beider
  Forces neu (die alte nur, wenn `game.forces[alt]` gültig ist). Es gibt kein Ereignis dafür (1, „Force-Wechsel“).
- `redraw` gesetzt (nach `on_forces_merging`, 4.14; `force_index` ist dann schon die Ziel-Force): dasselbe ohne neuen `force_index`, also Ring und Text
  (nur wenn nicht `hidden` und nicht `lost`) und Markierung für `game.forces[force_index]` neu, Fenster neu, dann `redraw = nil`. Gilt auch für eine Jagd
  mit `lost` oder ungültigem Ziel und im Zustand searching (dann nur Markierung und Fenster).
- Ziel gültig und auf der Oberfläche der Jagd → `sand = has_sand_under(target)`; mit Sand `last_pos` = Position. `safe = "rock"` ohne Sand,
  sonst `"far"`, wenn Abstand(target.position, warn_pos) > reach, sonst false. Wechselt `safe`, Ring und Sekundentext grün `{0.2, 0.8, 0.2, 0.9}` bzw. wieder rot
  (`LuaRenderObject.color`, A23 classes.d.ts:18121), Fenster der Force und Status neu. Ring und Sekundentext prüfen und neu zeichnen (`valid`),
  Sekunde `ceil((eta_tick − tick) / 60)` schreiben, wenn sie sich ändert (`LuaRenderObject.text`, A23 classes.d.ts:18272), dazu
  `harvester.set_alarm(h, "hunt", eta, safe and true or nil)`.
`safe` ist nur Anzeige: Entschieden wird bei 0 nach den Regeln oben, mit dem Ort von dann.

**Sonderfälle**
- Ein mobil gemachter, fahrender Ernter: Biss an der Stelle bei 0, auch 70 Kacheln weiter. Ein abgesetzter Ernter: Biss dort, wo er bei 0 steht,
  wenn das höchstens `reach` von `warn_pos` ist (60 s: 210 Kacheln); weiter weg abgesetzt → entkommen.
- Fahrzeuge (Auto, Panzer, Spidertron, Lokomotive bis 72 Kacheln/s, V23 base/prototypes/entity/trains.lua:504) fahren dem Biss leicht davon;
  gebissen wird nur, wer bei 0 noch in Reichweite auf Sand steht.
- Ziel ist ein Gebäude: Es kann nicht fliehen; abgebaut → weg.
- Ein Ernter, dessen Box mit einer Ecke Sand berührt, wird gebissen (auch angedockt, 1).
- Teleport per Skript auf eine andere Oberfläche (für Autos erlaubt) → entkommen bei 0; Rückkehr vor 0 → Jagd läuft dort weiter.
- Der Biss tötet das Ziel; harvester.lua räumt den Datensatz über `on_entity_died` (scripts/harvester.lua `on_removed`). worms.lua hat die Jagd
  vorher auf `biting` gestellt und ignoriert das eigene Ereignis.
- `/arrakis-uninstall`, `on_pre_surface_deleted`: Ende `"abort"` ohne Biss, ohne Rücksetzen, ohne Ruhe, ohne Statistik.

**Ende** (`end_hunt(hunt, outcome, mode)`): immer Markierung `if hunt.tag and hunt.tag.valid then hunt.tag.destroy() end` (A23 classes.d.ts:5877
sagt nicht zu, dass `destroy` ungültige Markierungen verträgt; Spieler können sie in der Karte löschen), Ring und Text `destroy()` (verträgt ungültige
Objekte, :18078), Alarme weg (4.10, auch bei ungültigem Ziel), `alarm_hunt_eta = nil` und `alarm_hunt_safe = nil` am Ernter (wenn sein Datensatz
noch da ist), Datensatz aus `storage.hunts.list`, Fenster der Force neu. Dazu je nach Art:

| Art | Rücksetzen und Ruhe (4.5) | Lehrjagd-Merker | Statistik | Chat |
|---|---|---|---|---|
| normal (`mode` nil) | ja | ja | ja (`bitten`, `escaped` mit `first_escape_tick`, `gone`) | ja |
| `"quiet"` (nur Prüfstand) | ja | ja | nein | nein |
| `"abort"` (Entfernen, gelöschte oder nicht mehr erlaubte Oberfläche, Prüfstand-Aufräumen) | nein | nur `first_hunt = nil` (4.6) | nein | nein |
| Befehlsjagd (`debug`), jede Art | nein | nein | nein | wie oben |

### 4.8 Wurmzeichen und Countdown
Im 60-Tick-Takt nach Unruhe (4.4 Schritt 5), nur wenn `storage.hunts.paused_until` nil oder vorbei ist, je erlaubter Oberfläche s:
1. Kandidaten: alle d mit `sum3[d] ≥ 1000` und `prev3[d] ≥ 600`, absteigend nach `sum3[d]`, bei Gleichstand nach Schlüssel.
2. d überspringen, wenn eine laufende Jagd auf s (nicht per Befehl) ihren Ursprung höchstens 1 Chunk von d hat (die Wärme gehört zu ihr).
3. Ziel: unter allen Quellen in den 9 Chunks um d (Ernter und `vib.sources`, nach `vib_key`/`key` aus diesem Takt) die stärkste berechtigte (1);
   Gleichstand: Ernter vor anderen, dann kleinste `unit_number`. Keine → nächstes d.
4. Grenzen (4.5): voll → Schluss für diesen Takt.
5. `start_hunt(target, {teaching = (kind == "harvest") and not grace.first_hunt_done})`, dann Schluss für s in diesem Takt.

`start_hunt(entity, opts)`: Gültige Entity mit Gesundheit (`is_entity_with_health`, A23 classes.d.ts:8091) und `unit_number` (nur EntityWithOwner,
A23 classes.d.ts:8703; sonst `nil, "no-target"`, Meldung `worm-cmd-no-target`) auf einer erlaubten Oberfläche (sonst `nil, "not-allowed"`, Meldung
`worm-cmd-not-allowed`), kein `arrakis-ornithopter` (`nil, "flyer"`), noch kein Ziel (`nil, "busy"`). Datensatz nach 4.2: `kind`,
`target_name = entity.localised_name`, `warn_tick = tick`, `eta_tick = tick + 60 · s` mit s = 90 bei `teaching`,
sonst 60, per Befehl `opts.seconds` (dann `eta_tick = ceil((tick + 60 · s) / 10) · 10`, damit der Biss im 10-Tick-Takt genau fällt), `origin_key` und
`sector_key` aus der Position des Ziels, `warn_pos = last_pos = Position`, `reach = 3.5 * (eta_tick − warn_tick) / 60`, `safe = false`. Dann Warnungen (4.10), Chat `msg-wormsign` an die Force mit
`[gps=x,y,Oberfläche]`, Fenster, Status. Lehrjagd: `grace.first_hunt = id`.

Der Countdown ist fest: `eta_tick` ändert sich nach dem Start nie. Eine Jagd endet nie vor `eta_tick` (außer Entfernen und gelöschte Oberfläche).

### 4.9 Biss
`bite(hunt)` am Biss-Tick, wenn die Entscheidung „Biss“ lautet:
1. `hunt.state = "biting"`. `center = target.position`, `surface = target.surface`, `mode = hunt.bite or settings.global["arrakis-worm-bite"].value` (A23 classes.d.ts:19163).
2. `surface.create_entity{name = "arrakis-worm-eruption", position = center}` (A23 classes.d.ts:20294); Ton und Staub bringt der Prototyp mit [V16].
3. Opfer sammeln: `find_entities_filtered{area = {{cx − 4, cy − 4}, {cx + 4, cy + 4}}}`, dann je Entity: gültig, `is_entity_with_health`,
   `destructible ~= false` (A23 classes.d.ts:7811), nicht Force `arrakis-sandworm`, Typ nicht `resource`, `corpse`, `character-corpse`, `entity-ghost`,
   `tile-ghost`, `cliff`, `spider-leg`, Name nicht `arrakis-ornithopter`; Abstand von `center` zum nächsten Punkt der Box (umschließendes Rechteck
   wie in scripts/terrain.lua:47–66) ≤ 4; `terrain.has_sand_under(entity)`. Das Ziel ist immer dabei. Figuren in einem Fahrzeug (`character.vehicle`,
   A23 classes.d.ts:5756) teilen dessen Los: Sie fliegen von der Liste, und Schritt 4 holt die Insassen jedes Fahrzeugs auf der Liste über `get_driver`
   und `get_passenger` (A23 classes.d.ts:6838, :7039), Figur oder `player.character`. So hängt nichts daran, ob die Suche Insassen liefert.
   Insassen durchlaufen denselben Filter wie alle anderen (`destructible ~= false`, nicht Force `arrakis-sandworm`): Eine geschützte Figur (T20: `tb.protect`)
   kommt nicht auf die Liste. Die Liste ist fertig, bevor das erste Opfer stirbt.
4. Ernter in der Liste (Name `spice-harvester`):
   - `total-loss`: Kofferraum und Treibstoff leeren (`get_inventory(defines.inventory.car_trunk).clear()`, `get_fuel_inventory().clear()`, A23 classes.d.ts:13732, :6934),
     Insassen auf die Liste, dann stirbt er wie alle anderen.
   - `heavy-damage`: nicht töten; `harvester.to_mobile(h)` (aufgebaut, im Auf- oder Abbau: sofort mobil; angedockt: abgedockt, scripts/harvester.lua:478–482),
     Kofferraum leeren, `entity.health = math.max(1, 0.1 * entity.max_health)` (A23 classes.d.ts:8023, :8185), Insassen bleiben sitzen.
   - Andere Fahrzeuge auf der Liste (auch der Spidertron): Insassen auf die Liste.
5. Töten in fester Reihenfolge: erst Figuren (noch im Sitz) [V14], dann Fahrzeuge, dann der Rest, zuletzt das Ziel; je Opfer
   `if entity.valid then entity.die(force_sandworm) end` (A23 classes.d.ts:6724), ohne `cause`. Was durch ein früheres Opfer ungültig wurde, wird übersprungen.
6. `end_hunt(hunt, "bitten")`, Chat `msg-bitten` bzw. `msg-bitten-damaged` mit Ort und Name des Ziels.
Der Wurmbiss ist ein Sterben ohne Schadensart: Resistenzen spielen keine Rolle, Panzerung auch nicht. Wrack: die Leiche des Prototyps (`tank-remnants`) [V20].

### 4.10 Warnungen, Fenster und Aufräumen
- **Alarm:** je verbundenem Spieler der Force `player.add_custom_alert(target, ICON, {"arrakis-message.alert-wormsign", target_name}, true)`
  (A23 classes.d.ts:15899; A20 classes.d.ts:22996) [V5], gemerkt in `alerted`. Die Sekundenarbeit setzt ihn für jeden verbundenen Spieler der Force, der ihn
  noch nicht hat (auch nach `on_player_joined_game`), solange die Jagd im Zustand warning ist und das Ziel gültig, nicht verborgen und nicht verloren ist.
  **Weg:** für jeden `player_index` in `alerted` (nicht für die Spieler der Force: Ziel oder Spieler können die Force gewechselt haben), Spieler gültig.
  Ziel gültig → `player.remove_alert{entity = target, type = defines.alert_type.custom, icon = ICON}` (A23 classes.d.ts:16245, AlertFilter concepts.d.ts:130–138).
  Ziel ungültig (nach dem Biss, nach `destroy()` ohne Ereignis) → `player.remove_alert{type = defines.alert_type.custom, icon = ICON, surface = hunt.surface_index}`;
  ein ungültiges LuaEntity als Filter wäre ein Laufzeitfehler (deshalb prüft scripts/harvester.lua:610 vorher `entity.valid`). Der Oberflächen-Filter trifft
  auch Alarme anderer Jagden dort; deren `alerted` wird geleert, die Sekundenarbeit setzt sie binnen 60 Ticks neu. Danach `alerted = {}`.
- **Markierung:** `force.add_chart_tag(surface, {position = warn_pos, icon = ICON})` (A23 classes.d.ts:11008), nur Symbol: `ChartTagSpec.text` ist ein
  String ohne Übersetzung (A23 concepts.d.ts:1577–1582). Gibt sie nil zurück (Chunk nicht kartiert), versucht die Sekundenarbeit es weiter und loggt einmal (Merker `tag_logged`) [V6].
  Ist `hunt.tag` gesetzt, aber ungültig (vom Spieler gelöscht), setzt die Sekundenarbeit sie nicht neu.
- **Ton:** `player.play_sound{path = "arrakis-wormsign"}` je verbundenem Spieler, ohne Position, also überall hörbar (A23 classes.d.ts:16216–16222, concepts.d.ts:7784) [V8].
- **Ring und Sekunden:** `rendering.draw_circle{color = {1, 0.15, 0.1, 0.9}, radius = BITE_RADIUS, width = 3, filled = false, target = target, surface,
  forces = {force}, draw_on_ground = true}` (A23 classes.d.ts:18415–18429) und `rendering.draw_text{text = tostring(sekunden), target = {entity = target,
  offset = {0, -3}}, surface, forces = {force}, color = {1, 0.3, 0.2}, scale = 2.5, alignment = "center", vertical_alignment = "middle"}` (:18640–18690).
  Mit `safe` beide grün `{0.2, 0.8, 0.2, 0.9}` (4.7 Nachführen); neu gezeichnet wird in der Farbe des aktuellen `safe`.
- **Fenster** (worms-gui): `mod_gui.get_frame_flow(player)` (V23 core/lualib/mod-gui.lua:36–40), Rahmen `arrakis_worm_frame` mit Überschrift
  `worm-gui-title`. Zeilen: Schonfrist (4.6), dann je Jagd der Force nach `eta_tick`: `worm-gui-hunt` (Name, Sekunden), mit `safe` stattdessen
  `worm-gui-hunt-safe` (`"rock"`) bzw. `worm-gui-hunt-far` (`"far"`), `worm-gui-hunt-carried`, `worm-gui-hunt-lost`,
  `worm-gui-hunt-searching`; bei der Lehrjagd zusätzlich `worm-gui-teaching`. Leer → Rahmen weg. 30-Tick-Takt für verbundene
  Spieler, sofort bei Start, Entscheidung und Ende (`refresh_force`). Solange `storage.hunts.paused_until > tick` (nach `/arrakis-uninstall`, 4.16), zeigt
  worms-gui gar nichts, auch keine Schonfrist; sonst baute der 30-Tick-Takt das eben entfernte Fenster gleich wieder auf.
- **Status am Ernter:** `harvester.set_alarm(h, "hunt", eta, safe and true or nil)` bei Start, jeder neuen Sekunde und jedem Wechsel von `safe`, nil beim Ende
  (Vorrang 1; mit `safe` `status-wormsign-safe`).
- **Aufräumen:** Alarme, Ring und Sekunden bei der Entscheidung ohne Biss (4.7), alles beim Ende, Entfernen, gelöschte Oberfläche (4.7). Verlässt ein Spieler das Spiel, bleiben seine Alarme der Engine überlassen; beim
  Wiederkommen setzt die Sekundenarbeit sie neu.

### 4.11 Vorsichtsmodus
`vibration.set_careful(h, on, player)`: nur eigene Force (sonst `hint-foreign`), `h.careful = on`; aus → `careful_wait = nil`, `careful_packing = nil`.
`careful_tick` je Ernter mit `careful == true` auf einer erlaubten Oberfläche (Prüfstand-Regel 4.3), W = `near_heat(Ort)`:

| Zustand | Bedingung | Aktion |
|---|---|---|
| deployed | W ≥ 600 | `careful_wait = true`, `careful_pos = Ort`, `careful_packing = true`, `harvester.pack(h)` |
| deploying | W ≥ 600 | `harvester.to_mobile(h)` (Abbruch), `careful_wait = true`, `careful_pos = Ort` |
| packing | – | nichts (Gewicht 0, wenn `careful_packing`) |
| mobile, `careful_wait` | weiter als 0,25 von `careful_pos` oder andere Oberfläche | `careful_wait = nil` (der Spieler fährt) |
| mobile, `careful_wait` | steht (`math.abs(speed) < 0,001`) und W < 300 | `harvester.deploy(h)`; gelingt es: `careful_wait = nil`, `careful_pos = nil` (sonst zeigte der Status beim Ernten weiter „wartet auf Ruhe“); geht es nicht (`no-spice`, `not-allowed`): ebenso `careful_wait = nil` |
| docked, carried | – | `careful_wait`, `careful_pos`, `careful_packing` nil |

- Ein von Hand gestartetes Aufbauen bei W ≥ 600 bricht der nächste Takt ab und wartet (gleiche Regel).
- Aufgebaut oder beim Aufbauen wird ein Vorsichts-Ernter nie Ziel (1, „Grenze Vorsicht“): Jedes Wurmzeichen braucht `prev3 ≥ 600`, also hat
  `careful_tick` im Takt davor schon eingepackt (Gewicht 0) oder abgebrochen. Fahrend und beim Einpacken von Hand hat er sein normales Gewicht.
- Der Modus schützt nicht vor einer laufenden Jagd: Er packt dann zwar ein, aber gebissen wird bei 0, wo der Ernter steht. Ebenso wenig schützt er
  als Nachbar im Bissradius eines anderen Ziels.
- Fenster: Kontrollkästchen spiegelt `careful`; mit `careful_wait` zeigt `arrakis_careful_wait` `gui-careful-wait` mit W.
- Zyklus und Grenze siehe 1 („Vorsichts-Zyklus“, „Grenze Vorsicht“); T18 misst beides.

### 4.12 Vibrationsanzeige und Unruhe-Effekte
**Unruhe** (`unrest_tick`), je erlaubter Oberfläche:
- Status: jeder Ernter außer `carried` mit `vib_sand` und W ≥ 600 → `set_alarm(h, "unrest", true)`, sonst nil.
- Staub: Quellen mit Gewicht > 0 auf Sand und W ≥ 600, sortiert nach W absteigend und `unit_number`, die ersten `DUST_MAX = 24`. Je Quelle
  n = min(3, 1 + floor((W − 600) / 200)) Wolken `surface.create_trivial_smoke{name = "arrakis-sand-dust", position}` (A23 classes.d.ts:20331) [V17] mit
  t = floor(tick / 60), Winkel `(un · 37 + t · 11 + k · 97) mod 360` Grad, Abstand `3 + (un · 13 + t · 7 + k · 29) mod 8` Kacheln (k = 1 … n).
- Rumpeln: je Sektor mit einer solchen Quelle, wenn `vib.rumble[s][sector] ≤ tick − 300` oder nil: `surface.play_sound{path = "arrakis-rumble",
  position = Ort der heißesten Quelle}` (A23 classes.d.ts:20719), Tick merken. Hörbar für Spieler in der Nähe. Einträge, die mindestens 300 Ticks alt
  sind, löscht `unrest_tick` am Ende (sie sperren nichts mehr), eine leere Tabelle `vib.rumble[s]` ebenso; sonst wüchse `vib.rumble` mit jedem Sektor, der je bebte.

**Vibrationsanzeige** (`overlay_tick` und Verknüpfung):
- Klick: `on = vib.overlay[i] == nil` (storage gilt, nicht `is_shortcut_toggled`, das bis zum nächsten Takt abweichen kann; sonst ersetzte ein Klick
  einen bestehenden Eintrag, und seine Objekte blieben liegen), `player.set_shortcut_toggled(name, on)` (A23 classes.d.ts:16323; A20 :23342);
  an → `vib.overlay[i] = {surface, cells = {}}`, aus → `overlay_off(i)` (alle Objekte `destroy()`, dann `vib.overlay[i] = nil`).
- Takt je eingeschaltetem, verbundenem Spieler: Oberfläche `player.surface`, Mitte `player.position`; nicht erlaubt → alle Zellen weg. Wechselt die
  Oberfläche gegenüber `cells`, erst alles weg. Für die 7×7 Chunks c um den Chunk der Mitte: Stufe `rest` (Sektor ruht), sonst nach `sum3[c]`:
  `red` ab 1000, `yellow` ab 600, `green` ab 1, sonst keine (Zelle weg). Neue Zelle: `draw_rectangle{color, filled = true, left_top, right_bottom
  (Chunkrand, 0,5 eingerückt), surface, players = {player}, draw_on_ground = true}` (A23 classes.d.ts:18560–18580) und `draw_text{text, target = Chunkmitte,
  surface, players = {player}, scale = 3, alignment = "center", vertical_alignment = "middle", draw_on_ground = true}`. Bestehende Zelle: `color` und `text`
  schreiben (:18121, :18272). Farben `green {0.2, 0.8, 0.2, 0.25}`, `yellow {0.9, 0.8, 0.1, 0.3}`, `red {1, 0.15, 0.1, 0.35}`, `rest {0.5, 0.5, 0.5, 0.3}`;
  Text: ganze Zahl, in Ruhe `overlay-rest` mit m:ss. Höchstens 49 Zellen, also 98 Objekte je Spieler.
- Weg bei: Ausschalten, `on_player_left_game`, `on_player_removed`, `/arrakis-uninstall` (jeweils `overlay_off`, der Eintrag geht mit; beim Wiederkommen
  stellt `on_player_joined_game` die Verknüpfung auf aus), Oberflächenwechsel (nur die Zellen, der Eintrag bleibt; neu im nächsten Takt).
- `on_player_joined_game` und `on_configuration_changed`: `set_shortcut_toggled(name, vib.overlay[i] ~= nil)` [V9]. Weil `on_player_joined_game`
  beim Laden im Einzelspieler nicht kommt (A23 events.d.ts:2721), vergleicht `overlay_tick` außerdem jede Sekunde je verbundenem Spieler
  `is_shortcut_toggled(name)` mit `vib.overlay[i] ~= nil` und gleicht an, wenn sie sich unterscheiden (storage gilt).

### 4.13 Briefings
- Tipps erscheinen, wenn das Szenario sie zulässt; die Mod schreibt `game.allow_tip_activation` nie (A23 classes.d.ts:12053–12057) [V4].
- `on_research_finished`: `planet-discovery-arrakis` → `force.print(msg-briefing)`; `arrakis-spice-harvesting` → `force.print(msg-wormsign-tip)`.
  Immer, auch per Skript erforscht.
- Migration: Chatzeile `msg-worms-migrated` bzw. `msg-worms-migrated-later` je Force mit Spielern, einmal (`storage.migration.worm_notice`).

### 4.14 Mehrspieler und mehrere Forces
- Logik nur in Takten und Ereignissen, Zustand nur in storage. Kein Modul hält Werte zwischen Takten außerhalb von storage (auch `sum3` liegt dort).
- Zufall nur `storage.rng` (Ruhezeit); Kosmetik aus Tick und `unit_number`. Kandidaten- und Zielreihenfolge fest sortiert.
- Biss: erst sammeln, dann töten (4.9), weil `die()` Ereignisse sofort auslöst und storage ändert [V1].
- Wärme gehört der Oberfläche, nicht der Force: Quellen mehrerer Forces heizen gemeinsam. Ziele nur aus wachen Forces; Opfer im Radius ohne Ansehen der Force.
- Warnungen, Fenster und Ring nur für die Force des Ziels; die Vibrationsanzeige nur für ihren Spieler.
- `on_forces_merging`: Jagden mit `force_index` der Quelle bekommen den der Ziel-Force und `redraw = true`: Ring, Text und Markierung gehören noch der
  Quelle (`forces = {Quelle}`, `add_chart_tag` der Quelle) und wären nach dem Verschmelzen für niemanden sichtbar; der nächste 10-Tick-Takt zeichnet sie
  für die Ziel-Force neu (4.7). Alarme gehen über `alerted` (Spieler bleiben gültig). Statistik wird addiert (`first_escape_tick`: der frühere),
  Schonfrist der Ziel-Force bleibt;
  danach `storage.grace[source.index]`, `storage.worm_stats[source.index]` und `storage.vib.testbench[source.index]` löschen. „Indexes of merged forces
  can be reused“ (A23 classes.d.ts:11510): Sonst erbte eine neue Force (T15, T19, Mehrspieler-Teams) `awake = true` und `first_hunt_done`.
  `on_force_created` verwirft deshalb auch einen vorhandenen Datensatz unter `event.force.index` und legt ihn bei Bedarf neu an (`grace_of`).

### 4.15 Leistung
- 60-Tick-Takt: eine Schleife über Ernter und Quellen (Gewicht, Position, eine Kachel), eine über die Einträge (Zerfall, 9 Streuungen), die Kandidaten
  (meist keine). Bei 500 Quellen etwa 2500 API-Aufrufe je Sekunde. Ein Budget je Takt kommt erst, wenn T8 es verlangt (DOC 4.0).
- 10-Tick-Takt: nur bei laufenden Jagden, höchstens 3 plus Befehlsjagden; je Jagd eine Sandprüfung der Box und ein Textwechsel je Sekunde.
- Anzeige: höchstens 49 Zellen je Spieler, Farbwechsel in place. Staub höchstens 72 Wolken je Oberfläche und Sekunde.
- Biss: eine Flächensuche 8 × 8 Kacheln.

### 4.16 Zusammenspiel mit 0.6.x, Migration und Entfernen
- **Getragen** (`carried`, auch wartend in `storage.stranded`): Gewicht 0, nie Ziel, bei 0 entkommen. Der Ornithopter selbst vibriert nicht und wird nie gebissen.
- **Absturz eines Ornithopters** setzt den Ernter am Boden ab (P3C 4.10); läuft eine Jagd, entscheidet der Ort bei 0.
- **migrate.lua:** `SCHEMA = 3` (Z. 40), `init()` legt die Tabellen aus 4.2 an (`storage.rng = storage.rng or game.create_random_generator()`).
  `on_configuration_changed`: wie bisher `old < 1`, `old < 2`, neu `old < 3` → jedem Datensatz in `storage.harvesters` fehlende Felder nachtragen
  (`careful = false`, `vib_weight = 0`, `vib_sand = false`) und `storage.migration.worms_pending = true`; dann Schema. Kopfkommentar um Schema 3.
  `worms_pending` steht schon vor `old < 2`: `researched = true` löst `on_research_finished` sofort aus [V2], und solange `worms_pending` steht,
  merkt sich worms dort nur `ornithopter_tick`, `active_from` und `announced` ohne `msg-grace-start`; den Termin nennt die Chatzeile der Migration einmal.
- **worms `on_init`:** `ensure_force()`; je Force `grace_of(force)`. **worms `on_configuration_changed`** (läuft nach migrate): `ensure_force()`; mit
  `worms_pending`: `migrate_schema3()`, dann `worms_pending = nil`. Außerdem immer: Verknüpfungszustände angleichen, verwaiste Render-Objekte und Fenster neu;
  jede Oberfläche in `vib.heat`, `sector_cooldown` und `vib.rumble`, die es nicht mehr gibt oder die nicht mehr erlaubt ist (Startup-Einstellung
  `arrakis-testbench` aus), räumt `vibration.drop_surface`, und Jagden mit diesem `surface_index` enden mit `"abort"`. Sonst blieben ihre Daten für immer
  liegen (der Takt läuft nur über erlaubte Oberflächen), und eine Jagd dort bisse ohne Wärme weiter.
- **`migrate_schema3(opts)`:** je Force mit Datensatz-Pflicht (4.6), nur was fehlt: „Ornithopter“ erforscht → `ornithopter_tick = tick`; gibt es die Oberfläche
  Arrakis und hat die Force Spieler → `landed_tick = tick` (DOC 4.6 „die Schonfrist beginnt also jetzt“); `active_from` nach 4.6. Dann `vibration.scan` auf
  Arrakis. Chatzeile (4.13). Ein 0.6.x-Spiel mit Ornithopter ist also 10 min später wach, eines ohne nach 30 min. Nur Prüfstand: `opts.surfaces` begrenzt den
  Scan, `opts.forces = {LuaForce…}` die Forces; mit `opts` gibt es keine Chatzeile und keinen `worm_notice`-Merker (sonst startete ein Testlauf im eigenen
  Spielstand die Schonfrist von Max' Force).
- **0.5.x → 0.7.0:** `old < 2` (Ornithopter nachholen) läuft vor `old < 3`; die Schonfrist sieht die nachgeholte Forschung.
- **Herunterstufen** auf 0.6.x: vorher `/arrakis-uninstall ja` (1). Die übrigen neuen Felder ignoriert 0.6.x.
- **`/arrakis-uninstall`** (scripts/flyer.lua:1159–1180): ohne Argument zusätzlich `uninstall-worms-warn` mit der Zahl laufender Jagden; mit `ja` nach
  `flyer_lib.uninstall()` noch `worms_lib.uninstall()`: alle Jagden `end_hunt(hunt, nil, "abort")` ohne Biss und ohne Rücksetzen; Markierungen (nur gültige),
  Ringe, Texte, Alarme (4.10 „Weg“), Fenster (alle Spieler; bis `paused_until` baut worms-gui keins neu, 4.10) und Anzeigen weg; `set_shortcut_toggled(…, false)` für alle Spieler; `harvester.set_alarm` nil für alle Ernter;
  `storage.hunts.paused_until = tick + 36000`; `game.merge_forces("arrakis-sandworm", "enemy")` (A23 classes.d.ts:11848) per pcall [V21]. Rückgabe n
  (beendete Jagden), Meldung `uninstall-worms`. Danach kann die Mod entfernt werden; bleibt sie, legt `ensure_force` die Force bei Bedarf neu an.
- **Prüfstand-Hilfe** `tb.worm_force` (scripts/testbench/runner.lua:500–511) legt dieselbe Force genauso an; beide Wege vertragen sich.

### 4.17 Ungeprüfte Engine-Annahmen
| Nr | Annahme | Entscheidet | Wenn sie nicht hält |
|---|---|---|---|
| V1 | `die(force)` löst `on_entity_died` noch im Aufruf aus, mit `event.force` = Sandwurm-Force | T19 Schritt 2 (Tick und Force aus dem weitergeleiteten `entity_died`) | Ohne Folgen für die Logik (erst sammeln, dann töten); Statistik der Engine nennt dann keine Force |
| V2 | `technology.researched = true` per Skript löst `on_research_finished` aus | T19 Schritt 7 (MESSUNG: Ereignis oder Takt) | Der Sekundentakt holt es nach (höchstens 60 Ticks später) |
| V3 | `on_player_changed_surface` feuert bei der Landung; `physical_surface` bleibt in der Fernsicht die echte Oberfläche | Fernsicht: T20 Schritt 1 (MESSUNG); Landung: Abnahme (der Prüfstand landet nie auf Arrakis) | Sekundentakt über `physical_surface`; zählt auch die Fernsicht, gilt die Landung eben früher |
| V4 | Tipps mit `research`-Auslöser erscheinen im Freeplay, auch wenn die Forschung vor 0.7.0 schon erforscht war | T20 Schritt 8, Abnahme | Die Chatzeilen (4.13) tragen das Briefing allein |
| V5 | Ein eigener Alarm mit einem virtuellen Signal als Symbol erscheint und lässt sich über `icon` gezielt entfernen | T20 Schritt 4; T19 MESSUNG nicht möglich (keine Spieler) | Symbol `item` `spice-sand` mit eigener Nachricht; beim Entfernen alle eigenen Alarme des Ernters löschen und die 3b-Alarme neu setzen |
| V6 | `force.chart` kartiert die Prüfstand-Chunks ohne Spieler binnen weniger Ticks, danach geht `add_chart_tag` | T18 Schritt 2 (sonst INFO „nicht prüfbar“) | Markierung nur, wo kartiert; die übrigen Warnungen reichen |
| V7 | Die Geräuschdateien der Demolisher liegen unter den V23-Pfaden | Laden des Spiels (Max, T18 Schritt 1 `is_valid_sound_path`) | Andere Vanilla-Pfade aus V23 nehmen; ohne Ton weiter |
| V8 | `player.play_sound` ohne Position ist überall hörbar | T20 Schritt 4 (FRAGE) | Position = `player.position` |
| V9 | Der Zustand eines `toggleable` Lua-Shortcuts bleibt über Speichern/Laden | Abnahme | Angleichen aus storage, auch beim Laden im Einzelspieler: `overlay_tick` vergleicht jede Sekunde (geplant, 4.12) |
| V10 | Render-Objekte mit `players = {…}` bzw. `forces = {…}` und eigene Alarme (`add_custom_alert`) überleben Speichern/Laden | Abnahme (Speichern und Laden während eines Countdowns: Ring, Text, Alarm) | Render-Objekte: Die Takte prüfen `valid` und zeichnen neu (geplant). Alarme: Die Sekundenarbeit prüft je Spieler in `alerted` mit `player.get_alerts{entity = target, type = defines.alert_type.custom, icon = ICON}` (A23 classes.d.ts:16139) und setzt fehlende neu; sonst stünde `alerted` auf true, und der Alarm käme nie zurück |
| V11 | `settings.global["arrakis-worm-bite"] = {value = …}` ist aus dem Skript schreibbar | T19 Schritt 3 (pcall) | Befehls-/Prüfstand-Option `bite` (4.2) |
| V12 | `on_player_driving_changed_state` reicht, um Fahrzeuge zu finden, die ohne `raise_built` entstanden | T20 Schritt 9 (Max steigt in ein per Test ohne `raise_built` gebautes Auto, MESSUNG `source_of`), Abnahme. Headless nicht prüfbar: Eine Puppe ohne Spieler löst das Ereignis nicht aus (A23 events.d.ts:2552–2561, scripts/testbench/t_ornithopter.lua:2732–2733) | `scan` in `on_configuration_changed` und im 60-Tick-Takt für Fahrzeuge in der Nähe verbundener Spieler, nie aus `on_load` |
| V13 | `status == working` gilt für arbeitende Bohrer, Pumpen, Fabriken und Öfen, auch auf Laborkacheln | T18 Schritt 4 | `mining_progress` bzw. `is_crafting()` als Ersatz |
| V14 | Eine Figur, die in einem Fahrzeug sitzt, stirbt per `die()` im Sitz (der Spieler erscheint neu) | T19 Schritt 2 (Fahrer von H1 tot, keine Figur am Boden) | Vorher `set_driver(nil)` bzw. `set_passenger(nil)`, dann `die()` |
| V15 | `has_sand_under` am angedockten Ernter: die gedrehte Box schließt die Ecken richtig ein | T19 Schritt 5 i | Box mit Sicherheitsrand 0,1 |
| V16 | Die Eruption spielt Ton, Partikel und Staub aus dem Prototyp ab | T20 Schritte 5 und 6 (Auge, Ohr) | Ton per `surface.play_sound`, Staub per Skript |
| V17 | Der eigene `trivial-smoke` erscheint mit `create_trivial_smoke` | T20 Schritt 2 | `create_entity` einer Explosion ohne Schaden |
| V18 | `mod_gui.get_frame_flow` gibt es unverändert in 2.1.23 | T20 Schritt 1; datastage lädt `control.lua` nicht | `player.gui.left` direkt |
| V19 | Ein Ernter, dem `health` geschrieben wird, behält danach `disabled_by_script = false` und fährt | T19 Schritt 3 | `harvester.to_mobile` nach dem Schreiben noch einmal |
| V20 | `die()` am Ernter hinterlässt `tank-remnants` | T19 Schritt 2 (Zahl der Leichen) | Wrack per `create_entity{name = "tank-remnants"}` |
| V21 | `merge_forces` mit der Sandwurm-Force läuft fehlerfrei | T19 Schritt 10 | Force bleiben lassen, nur Feindschaft lassen |
| V22 | Ein Spidertron als Ziel: `has_sand_under` an seiner Körperbox sagt, ob er im Sand steht | T19 Schritt 5 (MESSUNG), Abnahme | Prüfen an der Position statt an der Box |

### 4.18 Prüfstand-Haken
- vibration: `testbench_enable(force)`/`testbench_disable(force)` (Merker in `storage.vib.testbench`), `heat_entry(surface, key) → h|nil`,
  `set_heat(surface, cx, cy, h)` (schreibt den Eintrag und rechnet `sum3` sofort neu, `prev3 = sum3`), `near_heat`, `weight_of`, `source_of`, `scan`,
  `resting`, `rest` (wie 4.1).
- worms: `set_grace(force, felder, loeschen)`: schreibt die Felder aus `felder` (auch `awake`) und setzt jedes Feld aus der Liste `loeschen` auf nil
  (ein Tabellenliteral mit `= nil` hat diese Schlüssel nicht). Ohne `active_from` in `felder` wird `active_from` danach nach 4.6 neu berechnet, mit
  `active_from` nicht. `grace_snapshot(force) → Kopie|nil` und `grace_restore(force, kopie)` ersetzen den ganzen Datensatz (nil löscht ihn).
  Dazu `grace_of`, `start_hunt` mit `opts.bite`, `end_hunt(hunt, outcome, "quiet")`, `hunt_of`, `stats_of(force)`, `set_paused(until|nil)`,
  `migrate_schema3{surfaces = {…}, forces = {…}}` (4.16), `ensure_force`, `uninstall`.
- Isolation: Die Prüfstand-Fläche zählt nur für eingeschaltete Forces (4.3). T18 und T19 benutzen eigene Forces `arrakis-t18` und `arrakis-t19`
  (einmal anlegen, wiederverwenden wie `tb.worm_force`), schalten sie in `start` ein und in `cleanup` aus und beenden dort jede Jagd ihrer Force mit
  `"abort"`, löschen Wärme und Ruhe der eigenen Sektoren und stellen Einstellung, Pause und Schonfrist wieder her (Schonfrist per `grace_snapshot` in
  `start` und `grace_restore` in `cleanup`). T20 schaltet Max' Force genauso ein und aus (6). Spieler-Forces auf der Prüfstand-Fläche bleiben sonst für
  T1 bis T17 und für Max' Aufbauten stumm.

## 5. Texte

`locale/{de,en}/arrakis.cfg` (Datenstufe):
- `[entity-name]` `arrakis-worm-eruption=Wurm-Eruption`.
- Neuer Abschnitt `[virtual-signal-name]` `arrakis-wormsign=Wurmzeichen`.
- `[shortcut-name]` `arrakis-vibration-overlay=Vibrationsanzeige`.
- Neue Abschnitte `[tips-and-tricks-item-name]` `arrakis-briefing=Arrakis`, `arrakis-wormsign-tip=Wurmzeichen` und
  `[tips-and-tricks-item-description]`:
  `arrakis-briefing=Auf Arrakis ist Fels sicher, Sand lebt. Jede Maschine auf Sand erzeugt Vibration: ein aufgebauter Spice-Ernter viel, ein fahrendes Fahrzeug weniger, arbeitende Bohrer und Fabriken wenig. Die Vibration heizt die Gegend auf. Erst bebt der Sand, dann erscheint ein Wurmzeichen, und nach dem Countdown frisst ein Sandwurm alles im Umkreis von 4 Kacheln auf Sand (den Ernter je nach Einstellung „Wurmbiss“). Was ganz auf Fels steht oder in der Luft ist, bleibt verschont. Am Anfang lässt die Wüste dir Zeit: Die Schonfrist steht oben links.`
  `arrakis-wormsign-tip=Wurmzeichen heißt Lebensgefahr: Alarm, Kartenmarkierung, Warnton und ein roter Ring mit Countdown zeigen das Ziel. Nach 60 s (beim ersten Ernter 90 s) beißt der Wurm. Retten: mit dem Ornithopter über den Ernter fliegen und anheben (__CONTROL__arrakis-carry-toggle__ oder Verknüpfung „Ernter anheben oder absetzen“) und bis 0 in der Luft halten. Ohne Ornithopter: einpacken und ganz auf Fels fahren – das schafft der Ernter nur vom Lehrfeld nah am Fels. Wird der Ring grün, steht das Ziel sicher. Danach ist die Gegend 2 bis 4 Minuten ruhig. Im Ernterfenster packt der Vorsichtsmodus bei Unruhe selbst ein. Die Verknüpfung „Vibrationsanzeige“ zeigt, wie heiß der Sand ist.`
- `[mod-setting-description]` `arrakis-worm-bite=Was ein Sandwurmbiss mit einem Spice-Ernter im Bissradius macht. Andere Fahrzeuge und Gebäude auf Sand sterben immer.`
  (ersetzt locale/de/arrakis.cfg:103); `settings.lua` Z. 11: „Wurmbiss (Entscheidung 4): gilt für Spice-Ernter im Bissradius (docs/plan-3d1.md 4.9).“

`locale/{de,en}/messages.cfg`, Abschnitt `[arrakis-message]`:
- Status: `status-unrest=Der Sand bebt`, `status-wormsign=Wurmzeichen! Biss in __1__ s`, `status-wormsign-safe=Wurmzeichen: sicher (noch __1__ s)`,
  `status-careful-wait=Vorsichtsmodus: wartet auf Ruhe`
- Alarm: `alert-wormsign=Wurmzeichen: __1__`
- Fenster oben links: `worm-gui-title=Wüste`, `worm-gui-grace=Die Wüste regt sich in __1__`, `worm-gui-hunt=[virtual-signal=arrakis-wormsign] __1__: Biss in __2__ s`,
  `worm-gui-hunt-safe=[virtual-signal=arrakis-wormsign] __1__ steht ganz auf Fels: sicher (noch __2__ s)`,
  `worm-gui-hunt-far=[virtual-signal=arrakis-wormsign] __1__ ist außer Reichweite des Wurms: sicher (noch __2__ s)`,
  `worm-gui-hunt-carried=[virtual-signal=arrakis-wormsign] __1__ wird getragen: erst nach __2__ s auf Sand absetzen`, `worm-gui-hunt-lost=[virtual-signal=arrakis-wormsign] Ziel verloren (noch __1__ s)`,
  `worm-gui-hunt-searching=Der Wurm sucht (noch __1__ s)`, `worm-gui-teaching=Erste Jagd auf einen Ernter: 90 s Vorwarnung.`
- Ernterfenster: `gui-vibration=Vibration: __1__/s, Wärme __2__ (Unruhe ab 600, Wurmzeichen ab 1000)`, `gui-vibration-rest=Ruhe: noch __1__`,
  `gui-hunt=Wurmzeichen! Biss in __1__ s`, `gui-careful=Vorsichtsmodus`,
  `gui-careful-tooltip=Packt bei Unruhe (Wärme 600) selbst ein und baut unter 300 wieder auf. Schützt vor neuen Wurmzeichen, nicht vor einem laufenden und nicht als Nachbar eines anderen Ziels. Gut ein Viertel der Ausbeute.`,
  `gui-careful-wait=Wartet auf Ruhe: Wärme __1__, Aufbau unter 300`
- Chat: `msg-grace-start=Die Wüste regt sich in __1__. Bis dahin vibrieren Maschinen auf Sand gefahrlos; danach ruft zu viel Vibration einen Sandwurm.`,
  `msg-grace-awake=Die Wüste ist erwacht: Ab jetzt kann Vibration ein Wurmzeichen auslösen.`,
  `msg-wormsign=[virtual-signal=arrakis-wormsign] Wurmzeichen bei __1__: __2__, Biss in __3__ s. Anheben oder ganz auf Fels bringen.`,
  `msg-bitten=Ein Sandwurm hat bei __1__ zugeschlagen: __2__ verloren.`,
  `msg-bitten-damaged=Ein Sandwurm hat bei __1__ zugeschlagen: __2__ schwer beschädigt, Ladung verloren.`,
  `msg-escaped=Entkommen: Der Sandwurm hat bei __1__ nichts erwischt.`, `msg-gone=Der Sandwurm findet bei __1__ kein Ziel mehr.`,
  `msg-briefing=[planet=arrakis] Arrakis: Fels ist sicher, Sand lebt. Maschinen auf Sand erzeugen Vibration; zu viel davon ruft einen Sandwurm. Ein Wurmzeichen heißt Lebensgefahr.`,
  `msg-wormsign-tip=[virtual-signal=arrakis-wormsign] Erst bebt der Sand, dann kommt ein Wurmzeichen, und nach 60 s (beim ersten Ernter 90 s) beißt der Wurm. Rettung: mit dem Ornithopter anheben (__CONTROL__arrakis-carry-toggle__ oder Verknüpfung „Ernter anheben oder absetzen“) und bis 0 halten. Ohne Ornithopter: einpacken und ganz auf Fels fahren, das schafft der Ernter nur vom Lehrfeld.`,
  `msg-worms-migrated=Arrakis 0.7.0: Vibration auf Sand ruft jetzt Sandwürmer. Die Wüste regt sich in __1__.`,
  `msg-worms-migrated-later=Arrakis 0.7.0: Vibration auf Sand ruft jetzt Sandwürmer. Die Schonfrist beginnt mit der Forschung „Ornithopter“ oder der ersten Landung auf Arrakis.`
- Anzeige: `overlay-rest=Ruhe __1__`
- Befehl: `worm-cmd-help=Hetzt einen Sandwurm auf die ausgewählte Entity (nur Admins): /arrakis-worm [Sekunden 5–600 | lehr]. Ohne Ruhezeit und ohne Statistik.`,
  `worm-cmd-admin=Nur Admins dürfen /arrakis-worm benutzen.`, `worm-cmd-no-target=Erst auf eine Entity auf Sand zeigen.`,
  `worm-cmd-not-allowed=Sandwürmer gibt es nur auf Arrakis.`,
  `worm-cmd-busy=Auf diese Entity läuft schon eine Jagd.`, `worm-cmd-flyer=Ornithopter in der Luft trifft kein Wurm.`,
  `worm-cmd-bad=Sekunden zwischen 5 und 600 oder „lehr“.`, `worm-cmd-started=Wurmzeichen auf __1__: Biss in __2__ s (Test).`
- Entfernen: `uninstall-worms-warn=Dazu enden __1__ laufende Jagden ohne Biss, und 10 Minuten lang kommt kein Wurmzeichen.`,
  `uninstall-worms=__1__ Jagden ohne Biss beendet; 10 Minuten lang kommt kein Wurmzeichen.`; `uninstall-help` wird zu „Setzt alle getragenen
  Spice-Ernter ab, löscht die Ablage, beendet laufende Jagden und räumt Wurm-Markierungen, damit die Mod entfernt werden kann (nur Admins). Erst ohne
  Argument, dann mit „ja“.“

Englisch sinngemäß: „Wormsign“, „The sand is trembling“, „Careful mode“, „Vibration“, „Heat“, „The desert stirs in __1__“, „The desert has awoken“,
„Vibration overlay“, „Worm eruption“. Zeiten m:ss formatiert das Skript als Zeichenkette. Kein neuer Text nennt die Werkvorlage beim Namen.

## 6. Prüfstand

Wie in 3c: ohne Spieler über tools/pc/pruefstand.py (RCON) mit game.speed 10, nur Ticks, OK oder FEHLER mit Werten, Einzelwerte als MESSUNG.
Die Flächen hängen am Index in `ORDER` (scripts/testbench/runner.lua:293–298): T18 bei x = 32 000, T19 bei 34 000, T20 bei 36 000; keine alte Fläche
verschiebt sich. x = 32 000 ist eine Sektor-Ecke (Chunk 1000 = 4 · 250), 34 000 und 36 000 sind es nicht (Chunk 1062 bzw. 1125): Die Tests rechnen Sektoren immer mit
`vibration.key_of`. Zeitlimits: T18 `timeout = 240 * 60`, T19 `timeout = 540 * 60`, T20 `timeout = 920 * 60`, `interactive = true`. Bauten mit
`raise_built = true`, Fahrer sind `tb.dummy_driver`, gefahren wird wie in scripts/testbench/t_ernter.lua:146–154 (`riding_state` an Auto und Fahrer jeden Tick).
**Aufräumen je Schritt:** Jeder Schritt entfernt seine Quellen nach seiner letzten Messung (`destroy{raise_destroy = true}`) und setzt ihre Chunks mit
`set_heat(…, 0)` zurück, bevor der nächste beginnt; sonst heizen sie weiter und nehmen einem späteren Schritt das Wurmzeichen (eine neue Jagd je Takt und
Oberfläche, Lehrjagd sperrt die Force, `MAX_HUNTS = 3`). In T18 gilt das für die Schritte 3, 4 und 7 spätestens nach ihrem letzten Messtakt; dauerhaft
aufgebaute Ernter gibt es dort nur in den Schritten 2, 8, 9 und 10.

**T18 „Wärme: echter Code“** (automatisch, etwa 2,5 min Spielzeit, bei Tempo 10 etwa 15 s). Force `arrakis-t18` (wach, `first_hunt_done = false`), eingeschaltet.
Sandfläche ±300 Kacheln, darin Felsinseln wo nötig. Quellen stehen in eigenen Chunks mit mindestens 3 Chunks Abstand. Alle Schritte laufen parallel ab Tick 2.
1. Prototypen: Eruption, Staub, Signal, beide Geräusche (`helpers.is_valid_sound_path`, A23 classes.d.ts:13599), Verknüpfung (`toggleable`) da.
   Tipps: `LuaPrototypes` hat keine Tabelle für `tips-and-tricks-item` (A23 classes.d.ts:16833 ff.), deshalb nur MESSUNG mit
   `pcall(prototypes.get_history, "tips-and-tricks-item", name)` (:16877, ungeprüft); verbindlich prüft tools/check/checks.lua (7). storage-Tabellen aus 4.2 da; Sandwurm-Force da und feindlich zu `arrakis-t18` und `player`. FEHLER nennt das fehlende Stück.
2. Zeitlinie (ein Ernter allein, eigener Sektor): Ernter auf Spice (13×13 Teppich wie t_ernter.lua) aufbauen; T_d = erster Tick mit `deployed`.
   Der Test liest jeden Tick die Wärme seines Chunks: nach k Takten mit Beitrag 1500 · (1 − 0,98^k) ± 0,01 (FEHLER bei der ersten Abweichung). OK: Unruhe (`alarm_unrest`) genau ab k = 26
   und Tick in [T_d + 1440, T_d + 1620]; Wurmzeichen genau bei k = 55, Tick in [T_d + 3180, T_d + 3360], Wärme dabei 1006,2 ± 0,5; Jagd mit `teaching`,
   `eta_tick − warn_tick == 5400`, `eta_tick % 10 == 0`, Ring und Text gültig, `alarm_hunt_eta` gesetzt; Markierung gültig, wenn der Chunk kartiert ist
   (`force.chart` beim Start, `is_chunk_charted`, A23 classes.d.ts:11226), sonst INFO [V6]. MESSUNG: T_d, Tick und k von Unruhe und Wurmzeichen.
   Dann `end_hunt(hunt, "escaped", "quiet")`: 9 Chunks um den Ursprung 0, Sektor ruht 7200 bis 14400 Ticks, `first_hunt_done`, Ring und Markierung weg.
3. Gewichte (je Quelle eigener Chunk, `weight_of` und nach 3 Takten die Wärme w · (1 + 0,98 + 0,98²) = 2,9404 · w ± 0,01): Ernter aufgebaut 30, beim Aufbauen 0,
   Einpacken von Hand 30, mobil fahrend 10, mobil stehend 0, angedockt 0 (Annahme auf Fels, Ernter mit Ecke im Sand: Gewicht trotzdem 0); Auto fahrend 4,
   stehend 0; Panzer fahrend 8; Spidertron mit Ziel 6 (Autopilot wie T15), stehend 0; Ornithopter fliegend 0 und nicht eingetragen; Lokomotive:
   nur `weight_of` mit `train.speed` > 0 (Schienen und Zug aus Vanilla).
4. Feste Quellen [V13]: Großbohrer auf Eisenerz mit Strom (`electric-energy-interface` und Mast wie t_harvester.lua:1145–1146) 8, Bohrer 3, Pumpe auf Rohöl 2,
   Montagemaschine mit Rezept und Zutaten 1, Steinofen mit Kohle und Erz 1, Bohrer ohne Strom 0; Bohrer auf Fels: nicht eingetragen; die Kacheln unter
   ihm per `set_tiles(…, raise_event = true)` zu Sand → nach höchstens 60 Ticks eingetragen und Gewicht 3; ein Bohrer auf Sand, darunter Fels → Gewicht 0.
   Jeder Bohrer bekommt eine Holzkiste an `drop_position`, die Pumpe gibt in einen Lagertank: Ohne Abnehmer legt ein Bohrer ein Erz auf den Boden und steht
   dann mit „Warten auf Platz“ (der Großbohrer nach unter 1 s), und die Pumpe läuft voll. Gewicht und `status` werden im selben Takt gelesen, frühestens
   120 Ticks nach Strom an. MESSUNG: `status` je Gebäude bei jeder Lesung.
5. Zerfall und Löschen: `set_heat` 1000 auf einem leeren Chunk → nach 10 Takten 817,07 ± 0,05; `set_heat` 1,5 → nach 21 Takten Eintrag weg, nach 20 noch da.
6. Nachbarschaft (`set_heat`, sofort geprüft): zwei Chunks nebeneinander mit je 500 → `sum3` am ersten 1000; zwei Chunks mit 2 Abstand → `sum3` in der Mitte 1000,
   an den beiden 500, `near_heat` an beiden 1000; drei Abstand → überall höchstens 500. Kein Wurmzeichen, weil dort keine Quelle steht.
7. Erstbefüllung: Auto und Montagemaschine ohne `raise_built` → `source_of` nil; `scan(surface, Fläche)` → beide eingetragen, `n ≥ 2`. Das Einsteigen
   prüft erst T20 Schritt 9 [V12]: Eine Puppe ohne Spieler löst `on_player_driving_changed_state` nicht aus (A23 events.d.ts:2552–2561, `player_index`
   Pflicht; scripts/testbench/t_ornithopter.lua:2732–2733).
8. Vorsichtsmodus, ein Ernter (eigener Sektor, ab Tick 2): `set_careful` an, aufbauen, 2 volle Zyklen (etwa 115 s). OK: Einpacken beginnt im Takt mit W ≥ 600,
   Gewicht beim Einpacken 0, Wiederaufbau im ersten Takt mit W < 300, W nie ≥ 1000, kein Wurmzeichen. MESSUNG: Ernte-, Warte- und Aufbauzeit je Zyklus und
   Anteil (erwartet 16 / 36 / 5 s, 28 %).
9. Vorsichtsmodus, zwei Ernter im selben Chunk: 2 min, W nie ≥ 1000. MESSUNG: größtes W (erwartet unter 660).
10. Abbruch: zwei Ernter H10a und H10b mit `careful`, je eigener Chunk mit `set_heat` 700, `harvester.toggle` (Aufbauen) → nach höchstens 60 Ticks beide mobil
    mit `careful_wait`. H10a bleibt stehen: im ersten Takt mit W < 300 (700 · 0,98^42 = 299,6, also etwa 42 Takte nach `set_heat`) wieder `deploying`, dabei
    `careful_wait` und `careful_pos` nil. H10b fährt 1 Kachel (Puppe, `riding_state` wie oben): binnen 60 Ticks `careful_wait` nil, und 3 Takte nachdem sein W unter
    300 fiel ist er noch mobil (kein Wiederaufbau ohne `careful_wait`).
11. Prüfstand-Sperre: Ernter der Force `player` auf der Fläche, aufgebaut: nach 3 Takten kein Eintrag in seinem Chunk.

**T19 „Jagd: echter Code“** (automatisch, etwa 6 min Spielzeit, bei Tempo 10 etwa 36 s). Force `arrakis-t19`, eingeschaltet, wach. Schritte nacheinander.
1. Vorbedingung: Zahl der Jagden anderer Forces (nicht per Befehl). Mehr als 0 → INFO, Schritt 6 nur MESSUNG. Sandwurm-Force feindlich zu `arrakis-t19`.
2. Lehrjagd mit Biss [V1, V14, V20]: `first_hunt_done = false`. Ernter H1 aufgebaut (500 Spice-Sand, Kohle, Figur als Fahrer), `set_heat` 999 auf seinen Chunk.
   Um H1: Auto (2 Kacheln), Holzkiste (3), Figur zu Fuß (3), Band (1), Eisenkiste mit `destructible = false` (2), Steinmauer 4,5 Kacheln vom Rand (außerhalb),
   Kiste auf einer 3×3-Felsinsel 3 Kacheln entfernt, Ornithopter mit Puppe als Pilot genau über H1. OK: Wurmzeichen im nächsten Takt, Lehrjagd, 5400 Ticks;
   bis `eta_tick − 10` keine Gesundheit verändert, kein `entity_died` im Bereich; bei `eta_tick` im selben Tick `entity_died` für H1 mit Force `arrakis-sandworm`
   und ohne `cause`; gestorben: H1, Fahrer, Auto, Holzkiste, Figur, Band; am Leben: Eisenkiste, Mauer, Felskiste, Ornithopter und Pilot; eine `tank-remnants` mehr;
   keine Items am Boden im Radius; 9 Chunks um den Ursprung 0; Ruhe `until − eta_tick` in [7200, 14400]; Statistik `bitten` + 1; `first_hunt_done`; Jagd,
   Markierung und Ring weg. MESSUNG: ob `find_entities_filtered` den Fahrer lieferte, Reihenfolge der `entity_died`-Ereignisse.
3. Schwer beschädigt [V11, V19]: Einstellung per pcall auf `heavy-damage` (sonst `opts.bite`, INFO). Ernter H2 aufgebaut mit 500 Spice-Sand, 10 Kohle, Puppe als Fahrer,
   Auto daneben; `start_hunt(H2, {seconds = 2, debug = true})`. OK bei 0: H2 lebt, Gesundheit = max(1, 0,1 · max) ± 0,5, Kofferraum leer, Treibstoff gleich,
   mobil, Fahrer sitzt; Auto tot; Ruhe und Statistik unverändert (Befehlsjagd). Danach fährt H2 per `riding_state` 1 s: bewegt sich (mindestens 0,05 Kacheln, Schwelle wie
   scripts/testbench/t_ernter.lua:1921–1923). Einstellung zurück.
4. Rettung: `first_hunt_done = true`, Ernter H3 aufgebaut, `set_heat` 999 → Wurmzeichen, 3600 Ticks. Ornithopter mit Puppe über H3; bei `eta_tick − 720`
   `flyer_lib.toggle_carry(flyer, H3, nil)`. OK: bei `eta_tick − 590` getragen; Alarm-Merker leer, Ring weg, `hidden`; bei 0 kein Tod, `escaped`, Zustand
   searching, MESSUNG Zahl der Explosionen an `last_pos`; bei `eta_tick + 600` Ende, 9 Chunks 0, Ruhe, `escaped` + 1, `first_escape_tick` gesetzt. Absetzen an
   der alten Stelle, aufbauen: 5 Takte lang Wärme seines Chunks 0. Dann `rest(s, sector, 60)`: Nach Ablauf Unruhe genau im 26. und Wurmzeichen im 55. Takt
   mit Beitrag (wie T18 Schritt 2), keine Lehrjagd, 3600 Ticks. Ende `"quiet"`.
5. Feste Regeln (Befehlsjagden mit 10 s, alle zugleich, je eigener Sektor; OK je Teil, FEHLER nennt den Teil):
   a) Ernter fährt vor 0 ganz auf eine Felsinsel → entkommen, nichts gestorben.
   b) Ernter steht auf Fels, eine Ecke über Sand → gebissen.
   c) Ziel per `destroy{raise_destroy = true}` vor 0 → `lost`, bei 0 `gone`, Kiste 2 Kacheln neben `last_pos` lebt.
   d) Ziel per `teleport` auf `arrakis-test-hold` → entkommen; zurück vor 0 (zweite Jagd) → gebissen.
   e) Force des Ziels wechselt auf `arrakis-t19b` (wird angelegt, am Ende in `arrakis-t19` verschmolzen) → Jagd läuft, `force_index` neu, gebissen.
   f) Ernter angehoben und 30 Kacheln weiter auf Sand abgesetzt → gebissen dort; Kiste an der alten Stelle lebt. Eigene Befehlsjagd mit 20 s (`reach` 70),
      Flug per Autopilot: 120 Ticks Ankoppeln und 30 Kacheln beladen bei 5,7 Kacheln/s brauchen gut 7,3 s. OK, wenn vor 0 abgesetzt, sonst INFO
      „nicht rechtzeitig abgesetzt“.
   g) Ernter fährt 10 Kacheln über Sand → gebissen an der neuen Stelle.
   h) Montagemaschine (arbeitend) als Ziel, Band daneben → beide tot.
   i) [V15] Angedockter Ernter mit Ecke über Sand → gebissen; angedockt auf großer Felsfläche → entkommen.
   j) `start_hunt(ornithopter)` → `nil, "flyer"`; `start_hunt(Baum)` → `nil, "no-target"`; zweite Jagd auf dasselbe Ziel → `nil, "busy"`; Spidertron auf
      Sand als Ziel → gebissen (MESSUNG `has_sand_under`) [V22].
   k) Reichweite (`reach` 35 bei 10 s): Auto per `teleport` 50 Kacheln weiter auf Sand → entkommen, harmlose Eruption an `warn_pos`; ein zweites Auto
      30 Kacheln weiter → gebissen dort.
   Bei a) und k) zusätzlich: `safe` wird binnen 10 Ticks `"rock"` bzw. `"far"`, sobald das Ziel ganz auf Fels bzw. außer Reichweite steht; Ring grün.
6. Grenzen: `first_hunt_done = true`. Vier Ernter in vier Sektoren mit `set_heat` 999, ein fünfter im Sektor des ersten (3 Chunks weiter). OK: nach 1, 2, 3 Takten je
   eine neue Jagd, nach 5 Takten genau 3, keine zweite im selben Sektor; nach `end_hunt` einer Jagd, die nicht die des ersten Ernters ist (`"quiet"`), bekommt der
   vierte binnen 2 Takten seine. Alle mit
   `"abort"` beenden, dann die fünf Ernter entfernen und ihre Chunks auf 0 (sonst sind sie mit über 1000 im nächsten Takt wieder Kandidaten).
7. Schonfrist [V2]: `set_grace(force, {awake = false, first_hunt_done = false}, {"landed_tick", "ornithopter_tick", "active_from", "first_hunt"})`, „Ornithopter“
   `researched = false`, dann `true`.
   OK: `ornithopter_tick` binnen 60 Ticks (MESSUNG: im selben Tick = Ereignis, sonst Takt), `active_from == ornithopter_tick + 36000`; `set_grace(force, {landed_tick = tick − 100000})`
   (rechnet neu) → `active_from == landed_tick + 108000`; Ernter mit `set_heat` 999: 3 Takte keine Jagd; `set_grace(force, {landed_tick = tick − 108000 + 120})` → binnen
   3 Takten wach und im Takt des Erwachens eine Lehrjagd mit 5400 Ticks (4.6 „Erwachen“; FEHLER auch, wenn sie erst einen Takt später kommt). Ende `"quiet"`, Ernter entfernen, Chunk auf 0.
8. Flucht per Fahrt: Felsstreifen 40 × 300 Kacheln; Ernter E1 59 Kacheln, E2 und E3 100 Kacheln vor seinem Rand, je aufgebaut mit Puppe, Blick zum Fels.
   E1 und E2 regulär (`first_hunt_done = true`, `set_heat` 999), E3 per Befehl mit 90 s. E1 und E2 stehen in verschiedenen Sektoren (`key_of`) mit mindestens
   3 Chunks Abstand, ihre Wurmzeichen kommen in aufeinanderfolgenden Takten (eine neue Jagd je Takt und Oberfläche). Im Tick seines Wurmzeichens je Ernter
   `harvester.toggle` (Einpacken), danach Gas zum Fels.
   OK: E1 entkommen (ganz auf Fels), E2 gebissen. E3: INFO „Lehrjagd-Ausnahme: entkommt von 100 Kacheln“ bzw. INFO, wenn nicht. MESSUNG: Restabstand von E2 zum
   Fels bei 0 (erwartet etwa 30 Kacheln), Ankunftszeit von E1 (erwartet etwa 53 s nach dem Wurmzeichen).
9. Migration: Schonfrist-Datensatz von `arrakis-t19` löschen (`grace_restore(force, nil)`), „Ornithopter“ erforscht; Auto und Bohrer ohne `raise_built`.
   `migrate_schema3{surfaces = {Prüfstand}, forces = {arrakis-t19}}`. OK: `ornithopter_tick == tick`, `active_from == tick + 36000`; beide Quellen eingetragen;
   die Schonfrist aller anderen Forces unverändert (vorher und nachher verglichen); ein zweiter Aufruf ändert nichts (nur was fehlt).
10. Entfernen (immer zuletzt) [V21]: eine reguläre Jagd und eine Befehlsjagd laufen. `worms_lib.uninstall()` → 2; Jagden weg, Ring und Markierung ungültig,
    `paused_until == tick + 36000`; mit `set_heat` 999 kommt 3 Takte lang keine Jagd; nach 1 Tick gibt es `arrakis-sandworm` nicht mehr; `ensure_force()` legt sie neu an,
    feindlich. `cleanup` setzt `paused_until = nil`.

**T20 „Würmer: Bedienung“** (interaktiv, nur mit Max im Spiel, `alle` lässt ihn aus; endet nach 15 min Spielzeit oder mit `stop`). `start`: `grace_snapshot`
von Max' Force, eine Kopie von `stats_of(force)` in `run.data` und `vibration.testbench_enable(player.force)` (sonst zählt sein Ernter auf der Prüfstand-Fläche
nicht, 4.3); `cleanup`: jede Jagd dieser Force mit `"abort"` beenden, Wärme und Ruhe der T20-Sektoren löschen, `testbench_disable(player.force)`, `grace_restore`,
Statistik aus der Kopie zurückschreiben (die regulären Jagden aus Schritt 4 und 5 zählten sonst in Max' Force, und `first_escape_tick` schaltet in 3d3 den
Thumper frei). Während T20 vibrieren auch Max' übrige Bauten auf der Prüfstand-Fläche (Hinweis per INFO beim Start). Max bekommt `tb.protect`. Jede
Verknüpfung (weitergeleitetes `shortcut`) und jedes Kontrollkästchen schreibt MESSUNG, jeder Zustandswechsel INFO. Für das Kontrollkästchen gibt es keine
Weiterleitung: Der Test vergleicht jeden Tick `careful` seiner Ernter mit dem Wert davor.
1. Schonfrist [V3, V18]: `set_grace(force, {active_from = tick + 3600, awake = false, first_hunt_done = true})`. FRAGE: „Steht oben links ‚Die Wüste regt sich
   in 1:00‘ und zählt herunter?“ Bei 0 Chat „Die Wüste ist erwacht“. Danach ist Max' Force wach (bis zum Ende des Tests). Während der Minute [V3]: Max öffnet
   die Fernsicht auf eine andere Oberfläche (Karte, andere Oberfläche wählen, wenn es eine gibt); der Test schreibt jede Sekunde MESSUNG `surface.name` und
   `physical_surface.name` (V3 hält für die Fernsicht, wenn `physical_surface` dabei `arrakis-testbench` bleibt; gibt es keine andere Oberfläche, INFO).
2. Unruhe [V17]: Ernter neben Max, aufgebaut, `set_heat` 620 und bis zum Ende von Schritt 3 jeden Takt wieder auf 620 (sonst käme mit Gewicht 30 nach etwa
   30 s ein Wurmzeichen, während Max noch antwortet). FRAGE: „Siehst du Sandstaub, hörst du ein Rumpeln, und zeigen Fahrzeugfenster und Ernterfenster
   ‚Der Sand bebt‘ bzw. die Wärme?“
3. Vibrationsanzeige: Verknüpfung klicken. FRAGE: „Siehst du farbige Chunks mit Zahlen, der um den Ernter gelb?“ Noch einmal klicken: weg.
4. Wurmzeichen [V5, V8]: `set_heat` 999 → Wurmzeichen im nächsten Takt, 60 s (keine Lehrjagd, Schritt 1). FRAGE je Zeichen: Alarm unten rechts mit
   Wurmzeichen-Symbol, Kartenmarkierung, Warnton, roter Ring mit Sekunden, Zeile oben links, Status „Wurmzeichen! Biss in … s“.
5. Rettung [V16]: Ornithopter mit Kohle neben Max. Einsteigen, über den Ernter, `Umschalt+C`. FRAGE: „Verschwinden Alarm und Ring, steht oben links ‚wird getragen:
   erst nach … s auf Sand absetzen‘, und kommt bei 0 eine Sandfontäne unter dir, ohne Schaden?“
6. Biss ohne Rettung: zweiter Ernter, `/arrakis-worm 30` per Test, Kiste daneben. FRAGE: „Kam die Eruption mit Ton genau bei 0, liegt das Wrack da, ist die Kiste weg?“
   Dazu ein Ernter auf einer Felsinsel am Rand (eine Ecke im Sand), `/arrakis-worm 60` per Test; Max fährt ihn ganz auf den Fels. FRAGE: „Wird der Ring grün und
   steht oben links ‚steht ganz auf Fels: sicher‘, sobald er ganz auf Fels steht, und wieder rot, wenn du zurück in den Sand fährst?“
7. Vorsichtsmodus: im Ernterfenster einschalten, `set_heat` 580. FRAGE: „Packt der Ernter nach wenigen Sekunden selbst ein (im zweiten Takt), und baut er gut eine
   halbe Minute später (etwa 36 s nach dem Einpacken) wieder auf?“
8. Tipps [V4]: FRAGE: „Stehen unter Tipps und Tricks (Space Age) die Einträge ‚Arrakis‘ und ‚Wurmzeichen‘?“
9. Fahrzeug ohne `raise_built` [V12]: Auto neben Max per `create_entity` ohne `raise_built`, `source_of` nil (MESSUNG). Max steigt ein: MESSUNG `source_of`
   (eingetragen = V12 hält).
Was Max mit dem Auge und Ohr prüft (T20 und Abnahme): Eruption (Größe, Tönung, Staub), Staubwolken, Rumpeln, Warnton, Ring und Zahl, Fenster oben links,
Vibrationsanzeige (Farben, Lesbarkeit), Symbol des Wurmzeichens.

Runner (scripts/testbench/runner.lua): `ORDER` (Z. 40) endet mit `"T15", "T16", "T17", "T18", "T19", "T20"`; Modulliste (Z. 57–59) um
`scripts.testbench.t_jagd`; Vertrag (Z. 10–33): neues Modul; keine neue Weiterleitung (`entity_died`, `shortcut`, `research_finished` gibt es, Z. 815–826).
`docs/pruefstand.md`: Tests T18 bis T20 beschreiben; `alle` (Z. 50, 218) um T18 und T19; T20 überall neben T9, T12 und T17, wo die interaktiven Tests stehen
(Z. 43, 68, 128, 159, 192, 214, 222); Statusreihenfolge (Z. 96) „… T15, T16, T17, T18, T19, T20“; Abschnitt oben (Z. 27) um T18 bis T20 und die Annahmen V1 bis V22
aus diesem Plan; Bekannte Grenzen: Ohne Spieler prüfen T18/T19 keine Alarme, Töne und Fenster, das macht T20.
**Dauer von `alle`:** T18 etwa 9000 und T19 etwa 21 600 Ticks dazu, also etwa 83 000 Ticks statt 52 700: gut 23 min ohne Zeitraffer, mit Tempo 10 etwa 50 s mehr.
`tools/pc/pruefstand.py`: Hilfetexte (Z. 34, 767) nennen T9, T12, T17 und T20 als interaktiv.

**Was Max am Prüfstand tut:** `python tools/pc/pruefstand.py --factorio … T18 T19` (beide sollen ohne FEHLER enden), Datei schicken; dann T20 mit ihm im Spiel
(vorher `/arrakis-test tempo 1`), Datei und Antworten auf die FRAGEn schicken.

## 7. Prüfung vor der Übergabe
- `tools/check/datastage.py` mit Vanilla 2.1.23 (`fd2123`), mit und ohne `arrakis-testbench`, und `datastage.py fd2123 --ohne quality --set arrakis-testbench=true`.
  2.0.77 nur, wenn die Vanilla-Daten vorliegen (im Arbeitsordner gibt es `fd2077` derzeit nicht); dann prüft es nur die 2.0-Schreibweise.
- `tools/check/checks.lua` neu für 3d1 (`expected_3d1`): `explosion` arrakis-worm-eruption, `trivial-smoke` arrakis-sand-dust, `virtual-signal` arrakis-wormsign,
  `sound` arrakis-wormsign und arrakis-rumble, `shortcut` arrakis-vibration-overlay, `tips-and-tricks-item` arrakis-briefing und arrakis-wormsign-tip vorhanden.
  Dazu: Eruption ohne `explosion-stone-particle-*`, jede Animation bzw. Ebene getönt, `sound` mit 2 Varianten; Staub mit Sandfarbe; Signal mit Icon-Pfad aus V23;
  Geräusche mit genau den V23-Pfaden aus 3 (Liste fest in der Regel, nicht aus dem Modul gelesen); Verknüpfung `action == "lua"`, `toggleable == true`,
  `technology_to_unlock == "arrakis-spice-harvesting"`; Tipps mit Kategorie `space-age`, Auslöser `research` und der richtigen Technologie, `localised_name`
  und `localised_description` gesetzt, kein `skip_trigger`; Forschungen unverändert gegenüber 0.6.1 (Zahl, Namen, Auslöser). Die Namensprüfung der
  Laufzeitdateien liest auch `scripts/vibration.lua`, `scripts/worms.lua`, `scripts/worms-gui.lua` und `scripts/testbench/t_jagd.lua`.
- `datastage.py --dump` für die Eruption (was der deepcopy mitbringt); `tools/check/proto_fields.py` ohne Treffer.
- `tools/check/api_names.py` gegen 2.0.75 und 2.1.23 (factorio-types 1.2.72) ohne neue Treffer; insbesondere kein `LuaForce.add_custom_alert`, kein `LuaPin`,
  kein `play_music` (nur 2.1).
- Statische Regeln: kein `script.on_event`/`script.on_nth_tick` außerhalb von event_handler; keine storage-Schreibzugriffe aus `on_load`; kein `math.random`;
  keine Modultabelle namens `vibration` oder `worms` außerhalb ihres Moduls; jeder `arrakis-message`-Schlüssel aus dem Code steht in beiden Sprachen;
  kein Text nennt die Werkvorlage beim Namen; keine Modellnamen im Repo; `prototypes/noise.lua` unverändert (`git diff --stat` leer).
- Trockenlauf gegen eine Lua-Attrappe der Engine (wie T13- und 3c-Mock): Wärme (H_25, H_26, H_54, H_55, Zerfall, Löschen, Streuung, Ruhe), Kandidaten
  und Ziel samt Gleichstand, Grenzen, Lehrjagd-Regel (nur Ernter-Jagden, Ende mit `"abort"`), alle Zeilen der Tabelle in 4.7 samt Reichweite und `safe`,
  Biss-Filter (jede Ausnahme), beide Biss-Arten, Biss mit Aufräumen am ungültigen Ziel (Alarme über den Oberflächen-Filter), Ziel per `destroy()` ohne
  `raise_destroy`, Markierung vorher gelöscht, Force-Wechsel des Ziels ohne Ereignis, Vorsichtszyklus (Anteil 28 % ± 2, Wiederaufbau löscht
  `careful_wait`), Schonfrist-Formel samt `set_grace` mit `loeschen`, Lehrjagd im Takt des Erwachens, leere Oberfläche (Δs bleibt 1), Ernter verlässt die
  erlaubten Oberflächen (Felder genullt, nie Ziel), Aufräumen von `vib.rumble` und `sector_cooldown`, Migration aus Schema 1 und 2 (Ernter-Felder
  nachgetragen, offenes Ernterfenster geschlossen), Verschmelzen mit laufender Jagd (`redraw`, Lehrjagd-Merker der alten Force) und Neuanlage einer Force
  mit wiederverwendetem Index, ausgeschaltete Prüfstand-Fläche in `on_configuration_changed`, Entfernen (danach kein Fenster bis `paused_until`).
- Lua-Syntaxprüfung aller Dateien.
- Gegenprüfung durch zwei unabhängige Durchsichten (Laufzeit und Prüfstand) wie bei 0.6.1, Befunde vor der Übergabe eingearbeitet.
- Mit dabei: `info.json` 0.7.0; `changelog.txt` (Features, Changes, Hinweis zum Herunterstufen); `README.md` (Z. 5 „Stand“, Z. 11 letzter Satz, Z. 92,
  Tabelle „Aufbau“ mit den neuen Dateien); `docs/pruefstand.md` (6). DOC danach angleichen (vollständige Liste der Abweichungen):
  1. Wärme mit `min(Δs, 2)` beim Zufluss (Δs immer 1), Wurmzeichen nur nach Unruhe im Takt davor, W als größte 3×3-Summe; Zeiten 25 s / 55 s ab kaltem
     Sand, nach der Anfahrt aufs Lehrfeld etwa 17 s / 47 s (4.3, 2.1 Schritte 6 und 7).
  2. Vorsichtsmodus: Einpacken mit Gewicht 0, Zyklus 16 s / 36 s / 5 s statt 14 s / 34 s, „gut ein Viertel“ statt „etwa ein Drittel“ der Ausbeute;
     Schutz: nie selbst Ziel, solange aufgebaut oder beim Aufbauen, aber nicht als Nachbar und nicht vor einer laufenden Jagd (4.1 „Vorsichtsmodus“,
     „Einpacken“, 2.1 Schritt 6).
  3. Gewichte: aufgebaut immer 30, Fahrzeuge nur fahrend, Wagen 0, Ornithopter keine Quelle; Quellen ohne `on_object_destroyed` (4.3); Erstbefüllung
     der Quellen in einem `scan` statt budgetiert über `storage.migration.pending_chunks` (4.6 „Erstbefüllung“, 4.5 `migration`).
  4. Jagd in 3d1 ohne Wurm: Zustände warning/biting/searching, Entscheidung erst am Biss-Tick, Biss folgt dem Ziel bis zur Reichweite 3,5 Kacheln je Sekunde
     Countdown, „Ziel verloren“ mit harmloser Eruption, grüner Ring und „sicher“ für ein sicheres Ziel, Force-Wechsel im 10-Tick-Takt; WURMZEICHEN-Tabelle ohne
     Spawnplanung (4.3, 2.1 Schritt 9). Dazu DOC 4.2 Anheben Schritt 4 (getragen beendet die Jagd nicht, entschieden wird bei 0) und DOC 4.1 „Tod“ (vor 0
     gestorben: „Ziel verloren“, Ende `gone`, nicht „gefressen“).
  5. Schonfrist je Force, erste Landung per `physical_surface` (2.1 Schritt 3, 4.3, 4.5 `grace`).
  6. storage: `vib.heat` je Oberfläche mit `sum3`/`prev3`, `sector_cooldown` je Oberfläche, Jagd-Felder, Ernter-Felder für Vorsicht und Status (4.5).
  7. Lehrjagd nur für die erste Jagd auf einen Ernter, als Ausnahme vom Abnahmekriterium (2.1 Schritt 7, 2.4).
  8. Biss: Insassen sterben bei Totalverlust; „schwer beschädigt“ nur für Ernter; Täter ist die Force; Opferfilter (2.1 Schritt 9, 4.3 BISS).
  9. Briefings in der Space-Age-Kategorie, zusätzlich Chatzeilen (2.1 Schritt 0, 3).
  10. Vibrationsanzeige 7×7 Chunks, zeigt die 3×3-Summe (3, 4.0).
  11. `/arrakis-worm [Sekunden oder lehr]` in worms.lua, kein `debug.lua` (4.0).
  12. `/arrakis-uninstall` räumt auch die Würmer, Pause 10 min, Force-Verschmelzung (4.6).
  13. Sand = natürliche Kachel ungleich Fels, auch für „auf Fels“ (4.3 „Auf Fels heißt“).
  14. Angedockt ohne Ausnahme (2.4).
  15. Grenzen: 3 über alle Forces und Oberflächen, eine neue je Takt und Oberfläche, Befehlsjagden ausgenommen (4.3).
  16. Roadmap 7: 3d1 gebaut, Prüfstand T18 bis T20; Risiken 8: Zeile T18–T20 mit V1 bis V22; Unsicherheiten 9: Punkt „Würmer 3d1 (T18–T20)“ mit den
      wichtigsten Annahmen (V1, V5, V10, V12); Kopf: Mod-Stand 0.7.0 und Bauplan docs/plan-3d1.md.

## 8. Abnahme durch Max (0.7.0)
- `pruefstand.py` mit `T18 T19` (ohne Spieler, Tempo 10): beide ohne FEHLER, Datei schicken. T20 mit dir im Spiel, Datei und Antworten auf die FRAGEn.
- Neues Spiel bis „Entdeckung Arrakis“: Chatzeile und (wenn das Szenario Tipps zeigt) der Tipp „Arrakis“ [V4]. Mit „Spice-Ernte“ der Tipp „Wurmzeichen“.
- Auf Arrakis landen: oben links „Die Wüste regt sich in 30:00“ [V3]. Ersten Ernter herstellen: Die Zeit springt auf 10:00.
- In der Schonfrist einen Ernter auf dem Lehrfeld aufbauen: Staub, Rumpeln, „Der Sand bebt“ nach etwa 17 s (angefahren) bzw. 25 s (vorher 2 min gestanden
  oder per Ornithopter abgesetzt); kein Wurmzeichen. Vibrationsanzeige einschalten: der Chunk wird gelb, später rot (über 1000).
- Ende der Schonfrist abwarten (oder in einer Kopie mit `/arrakis-worm`): Lehrjagd mit 90 s sofort (spätestens 1 s nach „Die Wüste ist erwacht“), alle Warnzeichen da. Ernter einpacken und zum
  Fels fahren: Der Ring wird grün, sobald er ganz auf Fels steht; er entkommt.
- Zweite Jagd: Ernter per Ornithopter auf ein reguläres Feld (≥ 100 Kacheln vom Fels) setzen und aufbauen: Unruhe nach etwa 25 s, Wurmzeichen nach etwa 55 s
  (Roadmap 3d1), 60 s Countdown. Einpacken und zum Fels fahren reicht nicht: Biss genau bei 0, Wrack bleibt (Abnahmekriterium DOC 2.4).
- Dritte Jagd (neuer Ernter, nach der Ruhe von 2 bis 4 min oder in einem anderen Sektor): mit dem Ornithopter rechtzeitig anheben und bis 0 halten: „Entkommen“,
  danach ruhig, ein neues Wurmzeichen erst nach erneuter Unruhe.
- Vorsichtsmodus einschalten und 5 min ernten lassen, während du woanders bist (ab kaltem Sand): kein Wurmzeichen, danach etwa 450 bis 500 Spice-Sand im
  Laderaum (ohne Vorsicht 1500).
- Mod-Einstellung „Wurmbiss“ auf „Schwer beschädigt“, Biss abwarten (`/arrakis-worm 10` auf einen eigenen Ernter in einer Kopie): Ernter lebt mit 10 %, Laderaum leer.
- Speichern und laden während eines Countdowns: Countdown, Ring, Alarm, Fenster und Vibrationsanzeige laufen weiter [V9, V10].
- Einen 0.6.1-Spielstand mit erforschtem „Ornithopter“ laden: Chatzeile, „Die Wüste regt sich in 10:00“; bestehende Ernter vibrieren sofort.
- Mit zwei Spielern eine Jagd laufen lassen: beide sehen die Warnungen, kein Desync.
- Auf einer Kopie: `/arrakis-uninstall`, dann `/arrakis-uninstall ja`: keine Markierungen und Fenster mehr, 10 min kein Wurmzeichen.
- Offen aus 3c: die Abnahme-Punkte aus P3C 8 und 9, die noch ausstehen (T17, U1 bis U5 von Hand).
