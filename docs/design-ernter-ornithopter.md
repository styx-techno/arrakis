# Arrakis – Design v0.3: Spice-Ernter, Ornithopter und Sandwürmer

Stand: 06.10.2026 · Mod-Stand 0.3.0 · Max spielt Factorio 2.0.77 · Factorio 2.1 (bis 2.1.20) ist berücksichtigt

Dieses Dokument ersetzt drei Teile von Konzept v0.1:
- die „Spice-Erntemaschine (großer Bohrer)“ aus 3.2 und 3.4,
- den Ornithopter als Endgame-Technik aus 4.2,
- die Roadmap ab Phase 3 aus Abschnitt 7.

**Was sich gegenüber v0.2 geändert hat (nach dem Review, jeder Punkt in den Referenzen nachgeprüft)**
- Die Rettung per Ornithopter wird wirklich gebraucht. Der Ernter kriecht nur noch, Spicefelder liegen weit vom Fels, und der Ernter lässt sich nicht aus der Kartenansicht fahren (2.4).
- Den Ornithopter schaltet eine Trigger-Forschung gleich nach dem ersten Ernter frei. Die Schonfrist ist sichtbar und hängt an Ereignissen statt an einer verborgenen Uhr (2.1, 6).
- Fehler im Fels-Wächter behoben: Ernter am Felsrand waren praktisch unangreifbar (4.3).
- Die Ascheeffekte des Demolishers fliegen aus der Wurm-Kopie. Sonst würden sie auch Flieger treffen und bremsen (4.3).
- Neuer Treibstoffkreislauf: Tankstutzen an der Annahme, Auftrag TANKEN, Carryalls haben Treibstoff an Bord (4.1, 4.4).
- Neuer Wurm-Rhythmus: Die Wärme fällt nach jeder Jagd auf null, Countdown und Biss sind gekoppelt, der Wurm erscheint verzögert, der Thumper ist kein Pausenknopf mehr (4.3).
- Technische Korrekturen: `request_path` läuft asynchron, die Ablage wird vorab generiert, das Proxy-Ziel wird wieder gelöst, Budgets rechnen mit Zeitstempeln.
- Neu sind Kosten und Beute, Briefing, Migration und die Aufteilung von Phase 3d. Die Aussagen zu den Versionen sind präzisiert.

**Versionsmarken**
- **[2.0]**: läuft mit 2.0.77 und unverändert auch mit 2.1.
- **[2.0/2.1]**: geht in beiden Versionen, braucht aber eine andere Schreibweise. Das regelt die Versionsweiche (5.3).
- **[2.1]**: nur mit 2.1. Gehört zur Komfortschicht; das Spiel ist auch ohne sie vollständig.

**Belegkürzel** (alle Quellen lokal geprüft)
- **CL**: Changelog bis 2.1.20, enthält auch alle 2.0-Einträge (`…/scratchpad/factorio-data/changelog.txt`).
- **A20**: Lua-API 2.0.75 (typed-factorio 3.36.0). Für unsere Zwecke gleich 2.0.77, denn 2.0.76 und 2.0.77 ergänzen nur Prototyp-Lesefelder (CL:1149-1153, CL:1168). Ohne Dateiangabe ist `runtime/generated/classes.d.ts` gemeint.
- **A21**: Lua-API 2.1.20 (factorio-types 1.2.69, `dist/`).
- **V20/V21**: Vanilla-Prototypen 2.0.77 (`…/scratchpad/fd2077`) bzw. 2.1.20 (`…/scratchpad/factorio-data`).
- **Repo**: `/home/claude/arrakis` (Stand 0.3.0).

---

## 1. Kurzfassung

Spice gibt es auf Arrakis nur noch mit dem **Spice-Ernter**. Das ist ein schweres, langsames Raupenfahrzeug: Auf einem Spicefeld wird es verankert und fördert dann Spice-Sand in seinen Laderaum. Seine Vibration lockt nach etwa einer Minute einen **Sandwurm** an. Das **Wurmzeichen** warnt 60 Sekunden vorher, aber die Spicefelder liegen weit vom rettenden Fels, und davonfahren kann der Ernter dem Wurm nicht. Retten kann ihn nur der **Ornithopter**, und den erforscht man direkt nach dem ersten Ernter: hinfliegen, ankoppeln, hochziehen, und der Wurm greift ins Leere. Getragen wird immer dasselbe Fahrzeug, deshalb bleiben Ladung, Treibstoff und Zustand erhalten. In Stufe 2 übernimmt eine **Ornithopter-Leitstelle** mit unbemannten **Carryalls** Rettung, Entladen und Tanken. In Stufe 3 führt sie eine ganze Ernter-Flotte mit Feldsuche, Umsetzen und Schaltungssignalen. Das gesamte Spiel läuft mit Factorio 2.0.77; 2.1 bringt nur Komfort. Der Code wird ab sofort so geschrieben, dass der Umstieg auf 2.1 nur noch eine Änderung an info.json und einen Test braucht.

## 2. Spielablauf aus Spielersicht

Alle Zahlen sind Startwerte und werden als Mod-Einstellungen änderbar.

### 2.1 Stufe 1: manuell

0. **Briefing.** Mit der Forschung „Entdeckung Arrakis“ erscheint ein Tipps-und-Tricks-Eintrag: Fels ist sicher, Sand lebt, Maschinen auf Sand erzeugen Vibration, Wurmzeichen bedeutet Lebensgefahr.
1. **Erster Spice.** Spice-Sand wird von Hand abgebaut. Das löst wie bisher „Spice-Verarbeitung“ aus. Normale Bohrer bauen Spice nicht ab (offene Frage 2).
2. **Spice-Ernte.** Diese Trigger-Forschung (10 Melange herstellen) schaltet Spice-Ernter, Spice-Annahme und Tankstutzen frei.
3. **Erster Ernter.** Sobald der erste Ernter hergestellt ist, ist der **Ornithopter** erforscht (Trigger). Ab diesem Moment läuft die **Schonfrist**, sichtbar oben links: „Die Wüste regt sich in 10:00“. Sie endet spätestens 30 Minuten nach der ersten Landung auf Arrakis, auch wenn noch kein Ernter gebaut wurde.
4. **Zum Feld bringen.**
   - Das garantierte Startfeld ist das **Lehrfeld**. Es liegt 40 bis 80 Kacheln vom Inselrand entfernt, dorthin kann man noch kriechen (höchstens 1,5 Kacheln/s).
   - Alle anderen Felder liegen mindestens 100 Kacheln tief im Sand. Dorthin kommt man praktisch nur mit dem Ornithopter.
5. **Aufbauen** mit `Umschalt+H` oder dem Knopf im Fahrzeugfenster.
   - Nach 5 s ist der Ernter verankert.
   - Er fördert 5 Spice-Sand pro Sekunde aus einem 13×13-Feld und verbraucht dabei 400 kW Treibstoff.
   - Die Statuszeile zeigt „Erntet“, „Laderaum voll“, „Feld erschöpft“ oder „Kein Treibstoff“.
6. **Unruhe.** Nach etwa 25 s wirbelt Sand auf, es rumpelt, und der Status meldet „Der Sand bebt“.
   - Im Ernterfenster gibt es den Schalter **Vorsichtsmodus**: Dann packt die Crew bei Unruhe selbst ein und baut wieder auf, wenn es ruhig geworden ist.
   - Das ist sicher, bringt aber nur etwa ein Drittel der Ausbeute. Gedacht ist er für Zeiten, in denen der Spieler woanders ist.
7. **Wurmzeichen** nach etwa 55 s Ernten:
   - Alarm am Ernter, Kartenmarkierung, Warnton, roter Gefahrenring,
   - Countdown 60 s. Die allererste Jagd ist eine **Lehrjagd** mit 90 s.
8. **Rettung.**
   - *Mit Ornithopter:* über den Ernter fliegen und `Umschalt+C` drücken.
     - Nach 2 s Ankoppeln wird der Ernter samt Verankerung herausgerissen; ein Einpacken ist nicht nötig.
     - Wer im Ernter sitzt, wird Beifahrer des Ornithopters.
     - Danach schwebt man einfach über der Stelle oder fliegt weg. Mit derselben Taste wird der Ernter wieder abgesetzt.
   - *Aus der Kartenansicht:* Den Ornithopter mit der Spidertron-Fernbedienung hinschicken und die Taste drücken, solange er ausgewählt ist. Alternativ fährt man ihn ferngesteuert hin, falls T12 das bestätigt.
   - *Ohne Ornithopter:* einpacken (10 s) und auf Fels kriechen. Das gelingt nur auf dem Lehrfeld.
9. **Der Wurm kommt an.**
   - *Ziel weg:* Er sucht 10 s und taucht ab.
   - *Ziel noch da:* Eine Sandfontäne bricht hervor, und der Ernter wird gefressen (wie hart, entscheidet Max mit offener Frage 4). Mit ihm stirbt alles im Umkreis von 4 Kacheln, das auf Sand steht.
   - Auf dem Weg zerdrückt der Wurmkörper Bänder, Schienen und Gebäude auf Sand.
   - Danach ist die Wärme der Gegend null, und der Sektor bleibt 2 bis 4 Minuten ruhig.
10. **Entladen.** Den Ernter auf den Andockplatz einer Spice-Annahme fahren oder dort absetzen; die Annahme steht auf Fels.
    - Der Ernter dockt an, und die Annahme zeigt seinen Laderaum. Greifarme ziehen den Spice-Sand auf Bänder.
    - Ein Tankstutzen daneben füllt Treibstoff nach.
    - Abgedockt wird mit `Umschalt+H` oder durch Anheben.
11. **Umsetzen.** Ist das Feld erschöpft, anheben und zum nächsten Feld tragen. Ein Ornithopter kartiert im Vorbeiflug das Gelände und deckt so neue Felder auf.
12. **Gegenwehr.**
    - Würmer sind echte Gegner; der kleine hat 30 000 Lebenspunkte. Wer einen tötet, erhält Wurmzähne. Daraus baut man Ernter Mk2 und später Carryall Mk2.
    - Nach der ersten überstandenen Jagd gibt es den **Thumper**. Er lenkt eine laufende Jagd auf sich um (so gewinnt man Zeit) oder lockt einen Wurm gezielt vor die Geschütze. Eine Ruhezeit verschafft er nicht.

### 2.2 Stufe 2: halbautomatisch (mit Spice-Wissenschaft)

- **Leitstelle.** Die Ornithopter-Leitstelle steht auf Fels. Ihre **Carryalls** betreuen alle Ernter in Reichweite (Standard etwa 300 Kacheln, abgeleitet aus dem Carryall-Tempo, siehe 4.4).
- **Automatische Rettung.** Bei einem Wurmzeichen fliegt ein freier Carryall zum Ernter, hebt ihn an und schwebt, bis der Wurm abgetaucht ist. Dann setzt er ihn wieder ab und baut ihn auf. Ist der Laderaum zu mindestens 90 % voll, fliegt er stattdessen gleich zur Annahme.
- **Automatisches Entladen.** Ab 90 % Füllung bringt ein Carryall den Ernter zur Annahme, wartet, bis der Laderaum leer ist, und bringt ihn zurück.
- **Tanken.**
  - Carryalls haben Treibstoff im Kofferraum und füllen den Ernter bei jedem Kontakt auf.
  - Fällt ein Ernter unter 20 % Treibstoff, entsteht ein eigener Auftrag TANKEN.
  - Treibstoff legt man in die Leitstelle.
- **Ehrliche Absage.** Kann keine Rettung rechtzeitig kommen, gibt es sofort den Alarm „Rettung nicht möglich“ mit Grund: kein Carryall frei, zu weit oder kein Treibstoff.
- **Felder** wählt weiterhin der Spieler, indem er Ernter auf Felder setzt.
- **Handbetrieb.** Sitzt ein Spieler in einem Carryall oder schickt er ihn mit der Fernbedienung los, lässt die Automatik diesen Carryall in Ruhe.

### 2.3 Stufe 3: automatisch (Flottenleitung)

- **Soll-Zahl.** Die Leitstelle hat Ersatz-Ernter im Inventar und hält eine Soll-Zahl aktiver Ernter. Die Zahl kommt aus ihrem Fenster oder aus Signal H.
- **Feldsuche.**
  - Gesucht wird nur in kartierten Gebieten in Reichweite.
  - Bevorzugt werden große Felder mit kurzem Flugweg zur Leitstelle und zur Annahme, in deren Sektor es zuletzt keine Jagd gab.
  - Spieler können Zonen mit einer Kartenmarkierung mit Spice-Symbol vorgeben.
- **Umsetzen.** Ist ein Feld leer, setzt die Leitstelle den Ernter selbst um.
- **Rückruf.** Signal R holt alle Ernter auf Fels, zum Beispiel vor einem Sturm (Phase 4). Überzählige, leere Ernter wandern ins Inventar der Leitstelle zurück.
- **Bereitschaftsflug** (eigene Forschung). Ein Carryall folgt seinem Ernter dauerhaft; eine Rettung braucht dann nur noch die 2 s Ankoppeln.
- **Statussignale** auf eigenen virtuellen Signalen: aktive Ernter, freie Carryalls, laufende Rettungen, Spice in den Laderäumen, Wurmalarm.
- **Nur mit 2.1:** Patrouillenflüge und Signale zwischen Oberflächen per Radar (5.6).

### 2.4 Feste Regeln und Zahlenregeln

**Regeln**
- Was vollständig auf Fels steht oder getragen wird, wird nie gefressen. Vollständig heißt: Unter der Kollisionsbox liegt keine einzige Sandkachel.
- Würmer betreten nie Fels.
- Ornithopter und Carryall in der Luft werden vom Wurm weder getroffen noch gebremst.
- Anheben, Tragen und Absetzen verlieren nichts. Laderaum, Treibstoff, Gesundheit, Qualität, Name und Farbe bleiben erhalten.
- Ein Biss kommt nie vor Ablauf des Countdowns.

**Zahlenregeln** (damit der Ornithopter wirklich gebraucht wird)

| Größe | Startwert | Warum |
|---|---|---|
| Höchsttempo Ernter | ≤ 1,5 Kacheln/s | Langsamer als der Wurm (3,5 Kacheln/s) |
| Aufbauen / Einpacken | 5 s / 10 s | Flucht per Fahrt kostet Zeit |
| Ankoppeln am Flieger | 2 s, ohne Einpacken | Fliegen ist der schnelle Weg |
| Fernsteuerung des Ernters | aus (`allow_remote_driving = false`) | Sonst flieht man aus der Kartenansicht |
| Vorwarnzeit | 60 s, Lehrjagd 90 s | |
| Abstand Spicefeld → Fels | ≥ 100 Kacheln Sand; Lehrfeld 40–80 | 10 s + 100 / 1,5 ≈ 77 s > 60 s |
| Tempo Ornithopter / Carryall | ≥ 5 / ≥ 6 Kacheln/s (Kriterium T1) | 300 Kacheln in 50 bis 60 s |

**Abnahmekriterium** (Phase 3d1): Auf einem Feld, das nicht das Lehrfeld ist, entkommt ein Ernter ohne Flieger nicht innerhalb der Vorwarnzeit.

### 2.5 Bereits getroffene Designentscheidungen

Diese Punkte standen in v0.2 noch als Fragen da. Sie sind aber durch Max' Vorgaben und die Technik schon entschieden. Max muss nur widersprechen, wenn er es anders will.

- **Wurmmodell: Jagdwurm auf Abruf.**
  - Ein Wurm entsteht erst bei genug Vibration, jagt ein Ziel und taucht danach ab.
  - Feste Würmer in Territorien kommen nicht in Frage. Demolisher lassen sich seit 2.0.14 von Fahrzeugen nicht stören (CL:3677), und ihre Bewegung kennt keine Kachelgrenzen: Segmente werden nur auf „out-of-map“ ausgeblendet (A20 :28000-28003). Das Skript müsste sie also ständig gegen die Engine-KI steuern.
  - Die Würmer bleiben echte, tötbare segmented-units.
- **Zwei Fluggeräte: Ornithopter (bemannt) und Carryall (unbemannt, gehört zur Leitstelle).**
  - Beide teilen sich denselben Code.
  - Der Carryall kann größer und schneller sein, und die Automatik erkennt sofort, welche Geräte zu ihr gehören.
- **Ornithopter per Trigger** statt per Paketforschung.
  - Max will ihn „am Anfang“.
  - In Space Age kommt das Schlüsselgerät eines Planeten ebenfalls per Trigger, zum Beispiel der Großbohrer über „Gießerei herstellen“ (V20 space-age/prototypes/technology.lua:653-656).
- **Thumper** ist Ablenkung und Köder, kein Pausenknopf (4.3).
- **Abwesenheit** regeln Vorsichtsmodus und Leitstelle. Eine Sonderregel gibt es nicht.
- **Würmer auch ohne Ernter.** Nach der Schonfrist können auch große Bauten auf Sand ein Wurmzeichen auslösen, etwa 25 arbeitende Maschinen in einem Gebiet von 96×96 Kacheln. So steht es in Konzept v0.1: „Die Wüste lebt“.

## 3. Neue Prototypen

| Name (intern) | Prototyp-Typ | Rolle | Stufe | Platzhalter-Grafik |
|---|---|---|---|---|
| Spice-Ernter (`spice-harvester`) | `car`, Item `item-with-entity-data` | Fahrbarer Abbau, Laderaum = Kofferraum | 1 | Panzer orange-sand getönt; Staub (`trivial-smoke`) und Feldrahmen per Rendering |
| Spice-Annahme (`arrakis-spice-intake`) | `proxy-container` 2×2, nur auf Fels | Zeigt den Laderaum des angedockten Ernters | 1 | Stahlkiste getönt; Andockkreis gezeichnet |
| Tankstutzen (`arrakis-fuel-nozzle`) | `proxy-container` 1×1 | Zeigt das Treibstoff-Inventar des angedockten Ernters | 1 | Kleine Kiste, rot getönt |
| Ornithopter (`arrakis-ornithopter`) | `spider-vehicle` | Bemannter Flieger, trägt einen Ernter | 1 | Spidertron-Rumpf sand-getönt, keine Beine sichtbar |
| Flieger-Bein (`arrakis-flyer-leg`) | `spider-leg` | Unsichtbares, kollisionsfreies Trägerbein | – | keine |
| Getragener Ernter (`arrakis-harvester-carried`, `-shadow`) | `sprite` | Bild unter dem Flieger | 1 | Erster Frame von `__base__/graphics/entity/tank/tank-base-1.png`, getönt; Schatten-Sprite |
| Thumper (`arrakis-thumper`) | `simple-entity-with-owner`, nur auf Sand | Ablenkung/Köder, 60 s | 1 | Verkleinerte Pumpjack-Animation per Rendering |
| Spice-Brikett (`arrakis-spice-briquette`), nur wenn Frage 5 = B | `item` mit Brennwert | Lokaler Brennstoff | 1 | Kohle-Icon orange getönt |
| Ornithopter-Leitstelle (`arrakis-ornithopter-control`) | `container` 4×4 auf Fels + versteckter `constant-combinator` | Basis für Carryalls, Treibstoff, Ersatz-Ernter, Schaltung | 2/3 | Roboport getönt |
| Carryall (`arrakis-carryall`) | `spider-vehicle` | Unbemannter Lastenträger | 2 | Spidertron-Rumpf größer und dunkler |
| Ernter Mk2 (`spice-harvester-mk2`) | `car` | +50 % Abbau, −20 % Vibration | 2 | Ernter dunkler getönt |
| Sandwurm klein/groß (`arrakis-sandworm-small`, `-large`) | `segmented-unit` + `segment`, verkürzte Segmentliste | Jagdwurm | – | Kopie von small/medium-demolisher, sand-getönt |
| Wurm-Eruption (`arrakis-worm-eruption`) | `explosion` | Biss, Auftauchen | – | Große Vanilla-Explosion, sand-getönt |
| Sandstaub (`arrakis-sand-dust`) | `trivial-smoke` | Unruhe, Wurmspur, Abtauchen | – | Vanilla-Rauch, sand-getönt |
| Signale (`arrakis-wormsign`, `arrakis-signal-…`) | `virtual-signal` | Alarm-Symbol und Schaltungsausgänge | – | Getönte Warn- und Zahlensymbole |
| Wurmzahn (`arrakis-worm-tooth`) | `item` | Beute, Zutat für Mk2 | – | Getöntes Icon |
| Fels-Ebene (`arrakis_rock`) | `collision-layer` an Kachel `arrakis-rock` | Bauregeln, Wurmrouten | – | – |
| Spice-Abbau (`arrakis-spice-harvest`) | `resource-category` | Nur Ernter und Hand | – | – |
| Tasten (`arrakis-harvester-toggle`, `arrakis-carry-toggle`) | `custom-input` | Aufbauen/Einpacken/Abdocken, Anheben/Absetzen | 1 | – |
| Vibrationsanzeige (`arrakis-vibration-overlay`) | `shortcut` | Zeigt dem Spieler die Wärme pro Chunk | 1 | Getöntes Icon |
| Briefings (`arrakis-briefing`, `arrakis-wormsign-tip`) | `tips-and-tricks-item` | Einführung der Gefahr | 1 | nur Text |
| Ablage (`arrakis-hold`) | Oberfläche, per Skript erzeugt | Stellplätze für getragene Ernter | 1 | Laborkacheln, versteckt |

### 3.1 Kosten, Beute, Durchsatz (Startwerte)

| Ding | Rezept | Hinweis |
|---|---|---|
| Spice-Ernter | 40 Stahl, 20 Motoreinheit, 10 Fortgeschr. Schaltkreis, 100 Ziegel, 10 Melange | Verlust = Material + bis zu 2000 Spice-Sand Ladung. Ziel: spürbar, aber nicht lähmend, etwa 2 bis 3 Laderaumfüllungen |
| Ornithopter | 30 Stahl, 20 Motoreinheit, 10 Fortgeschr. Schaltkreis, 10 Melange | Schaltkreise werden importiert wie schon bei der Raffinerie |
| Spice-Annahme / Tankstutzen | 20 Stahl, 50 Ziegel, 5 Elektr. Schaltkreis / 5 Stahl, 5 Rohr | |
| Thumper | 5 Eisenplatte, 5 Zahnrad, 2 Kohle | Verbrauchsgut |
| Leitstelle | 50 Stahl, 200 Ziegel, 20 Fortgeschr. Schaltkreis, 10 Spice-Essenz | Essenz verdirbt, also wird auf Arrakis gebaut |
| Carryall | wie Ornithopter + 10 Stahl | |
| Spice-Brikett (Frage 5) | 5 Spice-Sand + 1 Kohle → 1 Brikett (20 MJ), in der Raffinerie | |
| Ernter Mk2 / Carryall Mk2 | Ernter + 4 Wurmzahn + 10 Spice-Essenz / Carryall + 8 Wurmzahn (Phase 5) | Gibt dem Wurmtöten einen Zweck |

- **Beute:** kleiner Wurm 2 bis 4 Wurmzähne, großer 6 bis 10. Verteilt wird sie per Skript (4.3).
- **Durchsatz:** Mit 50 % Grundproduktivität der Raffinerie braucht ein Spice-Wissenschaftspaket rund 12 Spice-Sand (Repo: prototypes/spice.lua:126-178). Ein Ernter mit 5/s schafft im Dauerbetrieb 25 Pakete/min. Im Wurm-Rhythmus mit etwa 65 % Erntezeit sind es rund 15/min, im Vorsichtsmodus etwa 7/min. **Balancing-Ziel für 3d3: 1 Ernter ≈ 15 Pakete/min.**
- **Erschöpfung:** wie beim Großbohrer werden 50 % der geförderten Menge vom Feld abgezogen (V20 space-age/prototypes/entity/big-mining-drill.lua:570).

## 4. Technische Umsetzung

### 4.0 Grundgerüst [2.0]

- **Dateien.** `control.lua` lädt nur Module über `__core__/lualib/event_handler`. Die Module sind `scripts/compat.lua`, `hold.lua`, `harvester.lua`, `flyer.lua`, `worms.lua`, `fleet.lua`, `migrate.lua` und `debug.lua`. In der Datenstufe kommen `prototypes/compat.lua` und `settings.lua` dazu.
- **Zustand.** Alles liegt in `storage`, Schlüssel ist jeweils `unit_number`.
  - Aufgeräumt wird über `script.register_on_object_destroyed` und `on_object_destroyed`, auch für `LuaSegmentedUnit` (A20 :500-512).
  - `on_load` schreibt nichts.
  - Zufall kommt aus einem gespeicherten `game.create_random_generator()`, also deterministisch und im Mehrspieler sicher (A20 :16187, :24574).
- **Takt.** Im Normalbetrieb gibt es kein `on_tick`.
  - `on_nth_tick(30)`: Abbau und Auftragsverteilung.
  - `on_nth_tick(60)`: Vibration und Andocken.
  - `on_nth_tick(10)`: Wurm-Wächter, Ankoppeln und Tempo-Deckel. Er kehrt sofort zurück, wenn nichts läuft.
  - Jede Schleife hat ein Budget. Jeder Eintrag speichert `last_tick` und rechnet mit Δt = (game.tick − last_tick)/60. So zählt ein übersprungener Ernter beim nächsten Mal voll mit.
  - Der Rundlauf-Zeiger wird vor dem Löschen eines Eintrags weitergeschoben, damit `next()` nie über einen gelöschten Schlüssel stolpert.
- **Ereignisfilter.** `on_entity_died`, `on_built_entity`, `on_robot_built_entity` und `on_player_mined_entity` werden mit Filtern auf unsere Namen und Typen registriert. `on_entity_damaged` brauchen wir nicht.
- **Mehrspieler.**
  - Die Logik ist rein ereignisgesteuert und deterministisch.
  - GUIs gibt es pro Spieler über `player.gui.relative`.
  - Render-Objekte sieht nur die eigene Force, die Vibrationsanzeige nur der jeweilige Spieler.
  - Spielwerte sind globale Mod-Einstellungen.
- **Debug.**
  - `/arrakis` gibt es schon.
  - `/arrakis-worm` hetzt einen Wurm auf die ausgewählte Entity.
  - `/arrakis-test <Tn>` ist der Prüfstand (Abschnitt 8).
  - Die Vibrationsanzeige ist ein normales Spielerwerkzeug (Shortcut), kein Debug-Befehl.

### 4.1 Spice-Ernter

**Entscheidung:** Der Ernter ist ein `car`, das per Skript selbst abbaut; sein Kofferraum ist der Laderaum.
- Es gibt keinen Entity-Tausch. Qualität, Gesundheit, Name, Farbe, `unit_number` und Pins bleiben deshalb von selbst erhalten.
- Nur Spieler, Autos und Spinnen dürfen zwischen Oberflächen teleportiert werden (A20 :1716-1741). Genau das braucht der Transport.

**Prototyp** [2.0/2.1]
- `table.deepcopy(data.raw.car.tank)`, dann:
  - Waffen entfernen, `inventory_size = 40`, Treibstoffslots `fuel_inventory_size = 3`.
  - `allow_remote_driving = false`; der Panzer hat `true` (V20 base/prototypes/entity/entities.lua:7650).
  - `trash_inventory_size = 0`. Dann hat der Ernter keinen Logistik-Tab, und Roboter können die Annahme nicht umgehen (A20 prototype/generated/prototypes.d.ts:2119-2123; Panzer: 20, entities.lua:7652).
  - Kein Ausrüstungsgitter, in keiner Version, denn wir brauchen keins.
  - Leistung, Gewicht und Reibung so wählen, dass das Höchsttempo bei etwa 1,5 Kacheln/s liegt.
- Bremse und Reibung setzt `compat.vehicle_physics`. Die Funktion löscht `braking_power` und `friction` und setzt nur `braking_force` und `friction_force`, denn 2.1 hat die alten Felder entfernt (CL:740).
- **Tempo-Deckel als Sicherheitsnetz** [2.0]: Fährt ein mobiler Ernter mit Fahrer schneller als 1,5 Kacheln/s, setzt der 10-Tick-Takt `harvester.speed` zurück. Das Feld ist für Autos schreibbar (A20 :4166-4172). Nötig ist das, weil das Höchsttempo vom Brennstoff abhängt und 2.1.13 diese Modifikatoren geändert hat (CL:244).
- Das Item ist wie beim Panzer `item-with-entity-data` (V20 base/prototypes/item.lua:1377).
- **Ressourcenkategorie:** `spice-sand.category = "arrakis-spice-harvest"`. In `data-updates.lua` bekommt jede Spielfigur die Kategorie in `mining_categories` (A20 prototype/generated/prototypes.d.ts:2438). So bleibt Handabbau möglich, und der bestehende Trigger „Spice-Sand abbauen“ feuert weiter. Das Muster gibt es in Vanilla bei Kalzit (V20 space-age/prototypes/technology.lua:611-614).

**Zustände**
```
mobil --Aufbauen 5 s--> aufgebaut --Einpacken 10 s--> mobil
mobil/aufgebaut --Anheben (2 s Ankoppeln, Notstart ohne Einpacken)--> getragen --Absetzen--> mobil
mobil, steht im Andockkreis einer Annahme --> angedockt --Umschalt+H / Anheben / Automatik--> mobil
```

**Aufbauen** [2.0] (per `custom-input` oder Knopf im relativen GUI an `car_gui`)
- Bedingungen:
  - Der Ernter steht, ist auf Arrakis und nicht angedockt.
  - `find_entities_filtered{area = Feld, name = "spice-sand"}` findet etwas. Die Liste wird als Ressourcen-Cache gespeichert.
- Danach:
  - `car.disabled_by_script = true`, das Auto steht still (A20 :5387-5397).
  - `car.minable_flag = false`, damit niemand den vollen Ernter aufhebt (A20 :4040-4042).
  - 5 s Fortschrittsring (`rendering.draw_arc`), dann Feldrahmen und `custom_status` (A20 :5011).
- `active` und `minable` werden nie geschrieben. In 2.1 sind diese Schreibzugriffe entfernt (CL:811-812).

**Abbau** [2.0] (`on_nth_tick(30)`, budgetiert)
1. `progress += 5 · Δt`. Davon werden die ganzen Einheiten `n` entnommen.
2. Abzug vom Feld: `drain_rest += 0.5 · n`; die ganzen Teile werden in einer Schleife über den Cache von `res.amount` abgezogen. Reicht der Rest einer Ressource nicht, folgt `res.deplete()`, und `on_resource_depleted` feuert (A20 :3604-3612).
3. Ausbeute: `n · (1 + force.mining_drill_productivity_bonus)`; der Nachkommarest wird gemerkt. Die normale Bergbau-Produktivitätsforschung wirkt also automatisch.
4. Einfügen in `get_inventory(defines.inventory.car_trunk)`. Statistik über `force.get_item_production_statistics(surface).on_flow` (A20 :15496).
5. Treibstoff: 400 kW · Δt werden von `burner.remaining_burning_fuel` abgezogen. Ist der Brennwert aufgebraucht, nimmt das Skript das nächste Item aus dem Treibstoffinventar und setzt `currently_burning` (A20 :885, :893). Ein stehendes Auto verbraucht sonst nichts.
6. Ist der Laderaum voll, das Feld leer oder kein Treibstoff mehr da, pausiert der Ernter, setzt seinen Status und meldet einen Alarm.
7. Zur Einordnung: Mit Kohle reichen 3 Slots für 25 min Ernten, mit Spice-Brikett etwa 2 h (Kohle 4 MJ, Stapel 50; V20 base/prototypes/item.lua:72, :78).

**Einpacken** [2.0]
- 10 s Ring; in dieser Zeit vibriert der Ernter weiter mit 30.
- Danach `disabled_by_script = false`, `minable_flag = true`, Renderings und Status zurücksetzen.
- Vibrationsgewicht: 10, solange er fährt, 0, solange er steht.

**Vorsichtsmodus** [2.0]
- Ein Schalter pro Ernter. Erreicht die Wärme in seiner Nachbarschaft 600, packt der Ernter ein; fällt sie unter 300, baut er wieder auf.
- Mit einem einzelnen Ernter ergibt das einen Zyklus aus etwa 14 s Ernten und 34 s Pause.

**Tod** [2.0]
- `on_entity_died` (gefiltert) räumt auf und beendet die Jagd als „gefressen“.
- Es bleibt ein Wrack wie beim Panzer.

**Spice-Annahme und Tankstutzen** [2.0]
- Beide sind `proxy-container` (V20 base/prototypes/entity/entities.lua:10080). `proxy_target_entity` und `proxy_target_inventory` sind schreibbar (A20 :5535-5548).
- Die Annahme darf nur auf Fels stehen: `tile_buildability_rules = {{area = {{-5,-5},{5,5}}, required_tiles = {layers = {arrakis_rock = true}}}}`. Das Pflichtfeld `area` umfasst hier den ganzen Andockkreis (A20 prototype/generated/types.d.ts:15197-15198). Ob `area` größer als das Gebäude sein darf, prüft T4. Sonst prüft das Skript den Fels beim Bauen und gibt das Gebäude andernfalls zurück.
- **Andocken** (60-Tick-Takt):
  - Bedingungen: Der Ernter ist mobil, hat Tempo 0 und steht mit dem Mittelpunkt höchstens 4 Kacheln von der Annahme entfernt.
  - Dann wird der Ernter gesperrt (`disabled_by_script = true`).
  - Die Annahme bekommt `proxy_target_entity = harvester` und `proxy_target_inventory = defines.inventory.car_trunk`.
  - Jeder Tankstutzen in höchstens 3 Kacheln Abstand bekommt dasselbe Ziel mit `defines.inventory.fuel`.
- **Abdocken** über `Umschalt+H`, Anheben, Automatik, Tod oder ungültiges Ziel:
  - Zuerst `proxy_target_entity = nil` an Annahme und Stutzen, dann den Ernter entsperren.
  - Der 60-Tick-Takt löscht zusätzlich jedes Ziel, das nicht mehr im Andockkreis steht.
  - So ist ein Fern-Entladen ausgeschlossen.
- Ausweichplan, falls T4 scheitert: Das Skript lädt in normale Kisten um. In 2.0 geht das per `get_contents`/`insert`/`remove`, in [2.1] mit `transfer_from_inventory` (CL:852).

**Anzeige**
- [2.0] `custom_status` und ein relatives GUI mit Ladebalken, Treibstoff, Vibration und Vorsichtsmodus. Falls T2 zeigt, dass `custom_status` im Fahrzeugfenster nicht erscheint, gibt es die Statuszeile nur im relativen GUI.
- [2.1] `set_tooltip_field` für Ladung, Feldrest und Vibration im Hover-Tooltip (CL:797).
- [2.1] GUI-Element „inventory“ (CL:848).

### 4.2 Ornithopter und Carryall

**Entscheidung:** Beide sind `spider-vehicle` mit unsichtbaren, kollisionsfreien Beinen. Getragen wird so: Der Ernter wird auf die versteckte Ablage-Oberfläche teleportiert, und am Flieger hängt ein Bild von ihm.

Gründe:
- Nur Spider-Vehicles haben einen Engine-Autopiloten: `autopilot_destination`, `follow_target` und `on_spider_command_completed` (A20 :5113-5114, :5177; A20 runtime/generated/events.d.ts:4589).
- Der Spinnenkörper kollidiert nur mit `trigger_target` (V20 core/lualib/collision-mask-defaults.lua:190). Den Kontaktschaden des Wurms gibt es nur für Masken mit player, train, rail, transport_belt, is_object oder is_lower_object (V20 space-age/prototypes/entity/enemies.lua:1015-1027). Der Flieger wird davon also nicht getroffen, ein `car` dagegen schon (collision-mask-defaults.lua:174).
- **Wichtige Einschränkung (aus dem Review, geprüft):** Die Ascheeffekte des Demolishers ignorieren Kollisionsmasken. Sie treffen alle Feinde im Umkreis mit einem Sticker, der Fahrzeuge auf 40 % Tempo bremst (enemies.lua:1934-1938, :2942-2946). Der Spidertron nimmt Sticker an (`sticker_box`, V20 entities.lua:9621). „Luftsicher“ gilt deshalb nur, weil die Wurm-Kopie diese Effekte nicht mehr hat (4.3).

**Prototypen** [2.0]
- `arrakis-ornithopter` ist eine deepcopy des Spidertrons:
  - Rumpf getönt, `graphics_set.render_layer = "air-object"`, `height` etwa 3, kleines `torso_bob_speed`.
  - `spider_engine.legs`: 1 bis 4 Beine `arrakis-flyer-leg`. Das ist ein `spider-leg` ohne Grafik mit `collision_mask = {layers = {}}`; ein einzelnes Bein ist erlaubt (A20 prototype/generated/types.d.ts:13487). Die beste Zahl klärt T1.
  - Energie: Der Vanilla-Spidertron fährt ohne Brennstoff (`type = "void"`, V20 entities.lua:9676-9680). Unser Flieger bekommt `BurnerEnergySource` mit `fuel_categories = {"chemical"}`, 2 Slots und `movement_energy_consumption` von etwa 800 kW (A20 prototype/generated/prototypes.d.ts:13503). Die Engine verbraucht den Treibstoff also selbst.
  - Keine Waffen, `trash_inventory_size = 0`, 10 Kofferraum-Slots, kein Gitter, 2 Sitze (Pilot und Beifahrer).
  - `chunk_exploration_radius = 2`: Der Flieger kartiert im Vorbeiflug (A20 prototype/generated/prototypes.d.ts:16969). Der Spidertron hat 3.
  - `allow_remote_driving` bleibt `true` (Spidertron-Wert, V20 entities.lua:9746).
- `arrakis-carryall`: dasselbe Gerüst, größer, schneller, ohne Pilot; gehört zur Leitstelle.
- `tall` wird nicht gesetzt. In 2.1 macht `tall` eine Entity im Modus „Hohe Objekte ausblenden“ unanwählbar (A21 prototypes.d.ts:3143-3145), und dann könnte man nicht mehr einsteigen.

**Ablage-Oberfläche** [2.0]
```lua
local hold = game.create_surface("arrakis-hold")
hold.generate_with_lab_tiles = true        -- Eigenschaft der Oberfläche, kein create_surface-Parameter (A20 :16143, :32108-32112)
hold.request_to_generate_chunks({0, 0}, 2) -- fester Block 5×5 Chunks
hold.force_generate_chunk_requests()
for _, f in pairs(game.forces) do f.set_surface_hidden(hold, true) end  -- plus on_force_created (A20 :15277)
```
- Die Stellplätze liegen im Raster von 10 Kacheln, das sind 256 Plätze. Freie Plätze stehen in einer Liste und werden wiederverwendet. Neue, ungenerierte Chunks entstehen so nie.
- Beim Teleport über Oberflächen prüft Factorio keine Kollision (`build_check_type` wird ignoriert, A20 :1735). Darum braucht es eigene, garantiert freie Plätze.

**Anheben** [2.0] (Taste `arrakis-carry-toggle`)
1. *Welcher Flieger?* Der, den der Spieler fährt, oder der in der Fernbedienung ausgewählte (`player.spidertron_remote_selection`, A20 :23539).
2. *Welcher Ernter?* `player.selected`, sonst `find_entities_filtered{position, radius = 4, name = "spice-harvester", limit = 1}`.
3. 2 s Ankoppeln mit Fortschrittsring. Entfernt sich der Flieger mehr als 4 Kacheln, bricht der Vorgang ab.
4. Dann:
   - Ein aufgebauter Ernter wird per Notstart sofort eingepackt; ein angedockter wird abgedockt.
   - **Insassen:** Fahrer und Beifahrer des Ernters werden mit `set_driver(nil)` und `set_passenger(nil)` herausgenommen. Der Fahrer wird mit `flyer.set_passenger(…)` Beifahrer im Flieger; das geht für Spider-Vehicles (A20 :3425). Ist der Sitz belegt (nur im Mehrspieler möglich), bleibt der Insasse neben dem Flieger stehen und bekommt eine Warnung.
   - `harvester.teleport(slot, hold)`; der Rückgabewert wird geprüft.
   - Bild und Schatten werden mit `rendering.draw_sprite{target = {entity = flyer, offset = {0, 0.5}}, render_layer = "smoke", …}` am **Flieger** gezeichnet. Render-Objekte verschwinden, sobald ihr Ziel die Oberfläche wechselt (A20 :27115). Stirbt der Flieger, verschwindet das Bild also von selbst.
   - `flyer.minable_flag = false`, der Ernter wird „getragen“, Jagden auf ihn enden als ENTKOMMEN.
5. **Last kostet Treibstoff.** Das Tempo einer Spinne ist nicht schreibbar (A20 :4166-4172). Deshalb zieht das Skript im Flug mit Last zusätzlich Brennwert ab. Optional (T1) heftet ein eigener Sticker mit `vehicle_speed_modifier = 0.7` die Last an; ob das bei Spider-Vehicles wirkt, ist nicht belegt.

**Absetzen** [2.0]
- Platz prüfen mit `surface.can_place_entity{…, build_check_type = defines.build_check_type.manual}`, sonst `find_non_colliding_position("spice-harvester", pos, 6, 0.5)`, sonst Hinweis „Kein Platz“.
- `harvester.teleport(pos, flyer.surface)`, Bild löschen, `minable_flag = true`. Der Beifahrer darf wieder einsteigen, wenn er möchte; ein Knopf im GUI erledigt das.

**Sonderfälle** [2.0]
- **Flieger zerstört** (`on_entity_died`): Der Ernter fällt an der nächsten freien Stelle herunter und nimmt 30 % Schaden.
- **Flieger anders entfernt** (`on_object_destroyed`): Der Ernter kommt an seinen Abhebepunkt zurück.
- **Treibstoff leer:** Der Flieger bleibt in der Luft, die Last hängt weiter dran. Für Carryalls gibt es TANKEN und Notregeln (4.4).
- **Bereitschaftsflug und neue Ziele:** Nach `follow_target` setzen wir neue Ziele nur über `autopilot_destination` und hängen nie Wegpunkte an. Einen Fehler beim Anhängen nach einem Folgebefehl behebt erst 2.1.7 (CL:1035). Die Forum-ID liegt vor dem Stand von 2.0.77, deshalb ist 2.0.77 wahrscheinlich betroffen.

**Ausweichplan, falls T1 scheitert:**
- Der Ornithopter wird ein `car` mit Maske `{layers = {}}` und `render_layer = "air-object"`, dazu `immune_to_*_impacts`.
- Carryalls werden dann rein virtuell: Render-Objekte, die nur während eines Flugs per `on_tick` bewegt werden.
- Das Tragen selbst funktioniert unverändert.

**2.1-Komfort**
- [2.1] Bewegte Objekte lassen sich in der Kartenansicht leichter anklicken (CL:536). Das hilft bei der Rettung aus der Karte.
- [2.1] Rechtsklick mit der Spidertron-Fernbedienung auf einen **Pin** schickt Flieger dorthin (CL:504).
- [2.1] Absetz-Vorschau über das Render-Ziel „cursor“ (CL:902-903), Positionslichter mit `light_mode` (CL:899), `LuaRenderObject.tall` ab 2.1.18 (CL:98).
- [2.1] Der Ausrüstungsbonus bleibt beim Teleport erhalten (CL:337). Damit wären später Gitter möglich.

### 4.3 Sandwürmer und Vibration

**Entscheidung:** Jagdwurm auf Abruf (siehe 2.5). Die nötige API (Demolisher und Territorien) gibt es seit 2.0.61 (CL:1565); in 2.1.20 hat `LuaSegmentedUnit` dieselben Member (A21 classes.d.ts).

**Prototypen** [2.0]
- Kopien von `small-demolisher` (klein) und `medium-demolisher` (groß) samt Segmenten, umbenannt und getönt.
- **Kürzere Körper:** `segment_engine.segments` wird von 41 Einträgen (enemies.lua:278-321) auf 12 bzw. 24 gekürzt. Das ergibt kürzere Körper und weniger Rechenlast.
- **Tempo:**
  - `investigating_speed` 3,5 Kacheln/s; `attacking_speed` 6 Kacheln/s, aber nur, wenn T5 den Sprint bestätigt.
  - `patrolling_speed` niedrig; `turn_radius` bleibt 12 · scale, also 6 bzw. 9 Kacheln (enemies.lua:485-490, :6629-6630).
- `vision_distance = 0`. Das ist zulässig, der Wert darf nicht negativ und höchstens 100 sein (A20 prototype/generated/prototypes.d.ts:12269-12272). T5 prüft nur das Verhalten.
- `revenge_attack_parameters = nil`, also keine Erdspalten.
- **Ascheeffekte entfernen.** In den `update_effects` des Kopfes bleiben nur der Kontaktschaden (Fläche, Maske wie Vanilla) und der Bohrstaub, sand-getönt.
  - Es entfallen: `…-ash-cloud-trail` (smoke-with-trigger mit Sticker), `…-trail-upper` und `…-trail-lower` sowie `destroy-cliffs` (enemies.lua:557-567, :2810-2851).
  - `update_effects_while_enraged = nil` (enemies.lua:1043-1045), `enraged_duration = 60`.
  - Segmente behalten nur ihren Flächenschaden; die Partikel werden sand-getönt.
- `territory_radius` ist Pflicht und bekommt 1. Eine Territory weisen wir nicht zu.
- **Keine Beute im Prototyp**, denn das Loot-Format hat sich in 2.1 geändert (CL:669). Beute verteilt das Skript bei `on_segmented_unit_died` mit `spill_item_stack`.
- **Gestaltung:** 2.1 hat die Demolisher-Grafik überarbeitet (CL:600). Durch die deepcopy übernehmen wir einfach die Grafik der jeweils laufenden Version.
- **Eigene Force** `arrakis-sandworm` (`game.create_force`), mit `set_cease_fire(…, false)` in beide Richtungen ausdrücklich feindlich.
- **Collision-Layer `arrakis_rock`** an der Kachel `arrakis-rock`. Vanilla belegt 24 Ebenen, die Grenze liegt bei 55, in 2.1 bei 256 (CL:634).
  - Die Ebene dient für Bauregeln, Wurmrouten per `request_path` und für T6 (bremst sie zusätzlich in der Wurmmaske?).
  - Der Ernter bekommt sie nicht in seine Maske.

**Vibration** [2.0]
- **Fahrzeuge** (Ernter, Auto, Panzer, Spidertron, Lokomotive) werden immer angemeldet. Ob sie auf Sand stehen, prüft jeder Vibrationstakt mit einem `get_tile` an ihrer Position. So zählt auch ein Panzer, der vom Fels in den Sand fährt.
- **Feste Gebäude** werden über `on_built_entity`, `on_robot_built_entity`, `script_raised_built` und `script_raised_revive` angemeldet. Voraussetzung: auf Arrakis, und unter der Box liegt mindestens eine Sandkachel (`count_tiles_filtered{…, name = {"sand-1","sand-2","sand-3"}}`, A20 :30844). Bei Kachel-Ereignissen wird neu bewertet.
- **Gewichte** (Vibration pro Sekunde; Fabriken und Öfen nur bei `status == working`):

  | Quelle | Gewicht |
  |---|---|
  | Ernter aufgebaut / beim Einpacken | 30 |
  | Ernter fahrend | 10 |
  | Ernter stehend, eingepackt oder angedockt | 0 |
  | Thumper | 60 |
  | Panzer / Spidertron / Auto (fahrend) | 8 / 6 / 4 |
  | Lokomotive (fahrend) | 6 |
  | Großbohrer / Bohrer / Pumpe | 8 / 3 / 2 |
  | Fabrik oder Ofen | 1 |
  | Bänder, Rohre, Masten, Spieler zu Fuß, Flieger | 0 |

  Bänder bleiben also der vibrationsfreie Weg über den Sand. Ein Wurm, der vorbeizieht, zerstört sie aber trotzdem.
- **Wärme pro Chunk:** `H ← H · 0,98^Δs + ΣV · Δs`. Gewertet wird die Summe über die 3×3-Nachbarschaft.
- **Schwellen:** Unruhe ab 600, Wurmzeichen ab 1000, großer Wurm ab 2000.
  - Ein Ernter allein strebt gegen 1500. Er erreicht 600 nach etwa 25 s und 1000 nach ln 3 / 0,0202 ≈ 55 s.
  - Ein Thumper allein strebt gegen 3000 und erreicht 1000 nach etwa 20 s.
- **Grenzen:**
  - Höchstens eine Jagd pro Sektor (4×4 Chunks), höchstens drei gleichzeitig. Thumper-Jagden zählen nicht mit.
  - Endet eine Jagd auf einen Ernter oder ein Gebäude (gefressen oder entkommen), wird die Wärme der 3×3-Nachbarschaft des Ursprungs auf 0 gesetzt.
  - Danach ist der Sektor 2 bis 4 Minuten ruhig, die Dauer würfelt der gespeicherte Zufallsgenerator. Während der Ruhe bleibt die Wärme bei 0. Danach kündigt sich jedes neue Wurmzeichen wieder mit Unruhe an.
- **Schonfrist:** Würmer werden aktiv 10 Minuten nach Abschluss der Ornithopter-Forschung, spätestens 30 Minuten nach der ersten Landung. Die Restzeit steht in einer kleinen Anzeige. Vibration und Unruhe-Staub gibt es schon vorher.

**Jagd als Zustandsmaschine** (`storage.hunts`)
```
WURMZEICHEN -> [ROUTING] -> WARTEN (bis Spawnzeit) -> ANNÄHERUNG -> ANGRIFF -> BISS -> ABTAUCHEN
Ziel getragen / ganz auf Fels / ungültig -> ENTKOMMEN -> SUCHEN (max. 10 s) -> ABTAUCHEN
Wurm getötet -> Beute, Ende          Zeitlimit t_warn + 60 s -> ABTAUCHEN
```

1. **WURMZEICHEN** [2.0]
   - *Ziel:* die stärkste Quelle in der Nachbarschaft.
   - *Warnung:*
     - `add_custom_alert` für jeden Spieler der Force; in 2.0 gibt es das nur pro Spieler (A20 :22996).
     - Eine Kartenmarkierung mit `force.add_chart_tag` (A20 :15317).
     - Warnton, Gefahrenring und Countdown-GUI.
   - *Spawnplanung mit verzögertem Spawn:*
     - Abstand `D = clamp(v · t_warn, 80, 160)` Kacheln.
     - Geprüft werden 16 Richtungen. Ein Kandidat muss in einem generierten Chunk auf Sand liegen, und die gerade Linie zum Ziel muss Sand sein (`get_tile` alle 4 Kacheln, synchron).
     - Spawnzeit `spawn_tick = warn_tick + (t_warn − D/v) · 60`. Der Wurm existiert also nur für die letzten 23 bis 46 s. Das spart Rechenzeit und vermeidet ungenerierte Chunks. Auch eine längere Frühwarnung vergrößert den Abstand nicht.
2. **ROUTING** [2.0], nur falls keine Richtung eine freie Sandlinie hat:
   - `surface.request_path{…, collision_mask = {layers = {arrakis_rock = true}}, path_resolution_modifier = -2}` liefert nur eine Kennung. Den Weg bringt später `on_script_path_request_finished` (A20 :31833ff; events.d.ts:4157-4169).
   - Die Zuordnung steht in `storage.path_requests[id] = hunt_id`.
   - Bei `try_again_later` wird nach 60 Ticks erneut angefragt, bei einem Fehlschlag der nächste Kandidat genommen.
   - Ist bis zur Spawnzeit kein Weg da, entfällt die Jagd still: Das Ziel ist dann von Fels umschlossen und damit sicher.
3. **Spawn** zur Spawnzeit:
   - `create_segmented_unit{name, position, direction, extended = true, force = "arrakis-sandworm"}`. Mit `extended = false` würde nur der Kopf entstehen (A20 :30676-30679). In 2.1.18 wurde ein Absturz bei kleiner Knotenzahl behoben (CL:77); ob 2.0.77 betroffen ist, klärt T7.
   - **Körperprüfung:** Direkt danach wird jeder vierte Knoten aus `get_body_nodes()` geprüft. Liegt einer auf Fels, wird der Wurm im selben Tick zerstört und die nächste Richtung probiert. So liegt nie ein Körper sichtbar auf Fels.
   - Danach `minimum_activity_mode = minimal` und `set_ai_state{type = investigating, destination = …}` (A20 :28137-28143, :28229). Ohne Territory patrouilliert ein Wurm sonst um seinen Spawnpunkt (A20 :30660); deshalb setzt das Skript den Zustand alle 30 Ticks neu.
4. **ANNÄHERUNG**
   - Alle 30 Ticks wird das Ziel nachgeführt, bei einem Umweg der nächste Wegpunkt.
   - `eta_tick` wird nachgerechnet: Restzeit = max(alte Restzeit − Δ, Restweg / v). Der Countdown kann sich also nur verlängern, nie springen.
5. **ANGRIFF** ab 40 Kacheln Abstand
   - Zieladresse ist ein Punkt 20 Kacheln **hinter** dem Ziel, falls dort Sand liegt, sonst das Ziel selbst. So fährt der Kopf durch und bremst nicht vorher ab.
   - `minimum_activity_mode = full`.
   - Sprint mit `set_ai_state{type = attacking, target = ziel}` nur, wenn T5 zeigt, dass der Wurm ein Auto als Ziel hält. Demolisher ignorieren Fahrzeuge als Störung (CL:3677).
6. **BISS**, wenn der Kopf näher als 3 Kacheln plus Zielradius ist **und** `game.tick ≥ eta_tick`.
   - Eruption und Ton, dann `ziel.die("arrakis-sandworm")`. Dazu sterben alle Bodenentities im Umkreis von 4 Kacheln, deren Kollisionsbox Sand berührt; Flieger nicht.
   - Kommt der Kopf zu früh in Reichweite, drosselt das Skript `speed` (schreibbar, A20 :28198) bis zum Ende des Countdowns.
   - Der Biss ist geskriptet, weil im Modus „minimal“ weniger Trigger-Effekte laufen (A20 runtime/generated/defines.d.ts:3218-3222).
7. **ABTAUCHEN** direkt nach dem Biss
   - Staub entlang jedes vierten Knotens, dann `destroy{raise_destroy = true}`.
   - Der Wurm muss nicht mehr wenden. Damit ist der Fehler aus v0.2 behoben, bei dem Ernter in Felsnähe praktisch unangreifbar waren.
8. **ENTKOMMEN / SUCHEN**
   - Der Wurm fährt zur letzten Position des Ziels. Nach höchstens 10 s oder sobald er dort ist, taucht er ab.
   - Ein Carryall, der über der Stelle schwebt, bleibt unberührt.

**Fels-Wächter** (`on_nth_tick(10)`, nur bei laufenden Jagden) [2.0]
- Der Kopf ist `get_body_nodes()[1]`, die Richtung ergibt sich aus den Knoten 1 und 3.
- **Sicherheitsnetz:** Steht der Kopf auf Fels, taucht der Wurm sofort ab.
- **ANNÄHERUNG und ENTKOMMEN:** Vorausschau 2 × Wenderadius + 6 Kacheln, also 18 beim kleinen und 24 beim großen Wurm.
  - Liegt dort Fels, wird ein neuer Wegpunkt gesucht: um ±30°, ±60° und ±90° gedreht, 30 Kacheln weit, mit Sandlinie.
  - Gibt es keinen, folgt ROUTING oder Abtauchen.
- **ANGRIFF:** geprüft wird nur die Strecke Kopf → Ziel, nie darüber hinaus. Liegt Fels dazwischen, geht die Jagd mit Umweg zurück in ANNÄHERUNG.
- **Auf Fels heißt:** `count_tiles_filtered{area = ziel.bounding_box, name = Sandkacheln, limit = 1} == 0`.
- Der Körper folgt der Spur des Kopfes. Deshalb reicht es, den Kopf zu überwachen, solange der Spawn sauber war.

**Thumper** [2.0]
- Kann nur auf Sand gebaut werden: `tile_buildability_rules = {{area = <collision_box>, colliding_tiles = {layers = {arrakis_rock = true}}}}`.
- Läuft 60 s mit Gewicht 60 und zerfällt dann.
- **Ablenkung:** Wird er im Umkreis von 160 Kacheln einer laufenden Jagd gebaut, bevor der Biss fällt, wechselt deren Ziel auf den Thumper.
- **Köder:** Läuft keine Jagd, löst er nach etwa 20 s selbst ein Wurmzeichen aus.
- Thumper-Jagden setzen keine Ruhezeit und die Wärme nicht zurück. Ein Ernter, der weiter erntet, bekommt also bald wieder ein Wurmzeichen. Der Thumper kauft Zeit oder lockt einen Wurm vor die Geschütze, mehr nicht.

**2.1-Komfort**
- [2.1] `LuaForce.add_custom_alert` und `remove_alert` ersetzen die Schleife über alle Spieler (CL:841).
- [2.1] `LuaPlayer.add_pin` gibt ein `LuaPin` zurück (CL:381-383). Nach Rettung oder Biss ruft das Skript `LuaPin.destroy()` auf (A21 classes.d.ts:15652ff); von selbst verschwindet ein Pin nicht.
- [2.1] `play_music` mit „script-track“ als Wurmzeichen-Musik (CL:897, CL:649).
- [2.1] `LuaEntity.protected` (CL:798), `ScriptTriggerEffectItem.custom_event` (CL:301).

### 4.4 Automatik: Leitstelle, Aufträge, Feldsuche, Schaltung

**Entscheidung:** Echte Carryall-Entities fliegen mit dem Engine-Autopiloten. Die Ankunft meldet `on_spider_command_completed`. Ob das Ereignis auch bei per Skript gesetztem Ziel feuert, prüft T1; der Ausweichplan fragt alle 30 Ticks `autopilot_destination == nil` ab.

Verworfen:
- `LuaSchedule`: nur für Züge und Raumplattformen (A20 :27792).
- Frachtkapseln: entstehen nur an Silo, Landefeld und Plattform-Hub (A20 :3800-3809).
- Roboter: tragen nur Items.

**Leitstelle** [2.0]
- Ein `container` 4×4 auf Fels. Ihr Inventar nimmt Treibstoff und Ersatz-Ernter auf.
- `radius_visualisation_specification` zeigt beim Bauen die Reichweite (A20 prototype/generated/prototypes.d.ts:4621).
- Der versteckte `constant-combinator` wird per `connect_to(…, false, defines.wire_origin.script)` verdrahtet (A20 :33670).
- Carryalls, die näher als 20 Kacheln an der Leitstelle gebaut werden, gehören zu ihr.
- **Beim Parken** füllt das Skript aus der Leitstelle nach: zuerst `carryall.get_fuel_inventory()`, dann einen Vorrat von bis zu 2 Stapeln im Carryall-Kofferraum.
- **Reichweite** R = v_carryall · (t_warn − 2 s Ankoppeln − 1 s Verteilung − 7 s Puffer) = v · 50 s. Bei 6 Kacheln/s sind das 300 Kacheln. v ist eine Einstellung mit dem Messwert aus T1 als Standard.

**Aufträge** (höchste Priorität zuerst)

| Auftrag | Auslöser | Ablauf | Stufe |
|---|---|---|---|
| RETTUNG (100) | Wurmzeichen mit einem betreuten Ernter als Ziel | Hinfliegen, anheben, schweben bis Jagdende (bei Laderaum ≥ 90 % gleich weiter zu ENTLADEN), absetzen, aufbauen | 2 |
| TANKEN (60) | Ernter unter 20 % oder „Kein Treibstoff“; Carryall mit Last und leerem Tank | Hinfliegen, Treibstoff aus dem Kofferraum-Vorrat übertragen (`get_fuel_inventory().insert`, Vorrat `remove`) | 2 |
| ENTLADEN (50) | Laderaum ≥ 90 % | Zur nächsten freien Annahme, andocken, warten bis leer (höchstens 60 s), Tankstutzen tankt mit | 2 |
| RÜCKKEHR (40) | Nach ENTLADEN oder nach einer Rettung, bei der der Ernter woanders abgesetzt wurde | Zur alten Position, aufbauen | 2 |
| UMSETZEN (30) | Ressourcen-Cache leer | Zum nächsten Feld | 3 |
| EINSATZ (20) | Weniger aktive Ernter als Soll | Ernter aus dem Inventar erzeugen, betanken, zum Feld tragen | 3 |
| RÜCKRUF (10) | Signal R > 0 oder zu viele Ernter | Zur Leitstelle; mit leerem Laderaum ins Inventar | 3 |

**Ablauf**
- **Verteilung** (`on_nth_tick(30)`): Der wichtigste offene Auftrag bekommt den nächsten freien Carryall mit genug Treibstoff.
  - Genug heißt: Energie für Hin- und Rückweg, bei Last mit Aufschlag, plus 20 % Reserve. Das wird geprüft gegen `burner.remaining_burning_fuel` plus Brennwert des Treibstoffinventars.
  - Eine RETTUNG darf einen leer fliegenden Carryall umleiten, aber nie einen, der schon einen Ernter trägt.
  - Jeder Ernter gehört zu höchstens einem Auftrag.
- **Notregel:** Ein Carryall unter der Reserve setzt seine Last auf dem nächsten bekannten Felsplatz ab (Annahme oder Leitstelle). Läuft gerade keine Jagd, setzt er sie an Ort und Stelle ab. Dann fliegt er zum Tanken.
- **Ehrliche Absage:** Kann kein Carryall vor dem Countdown-Ende ankommen (Distanz / v > Restzeit − 3 s), gibt es den Alarm „Rettung nicht möglich“ mit Grund.
- **Flug:** `carryall.autopilot_destination = ziel`. Anheben und Absetzen nutzen dieselben Funktionen wie in 4.2.
- **Handbetrieb erkennen:** über `on_player_driving_changed_state` und `on_player_used_spidertron_remote` (A20 events.d.ts:3177). Ein Carryall im Handbetrieb bleibt aus der Automatik, bis er wieder an der Leitstelle parkt.
- **Ersatz-Ernter** [2.0]
  - Erzeugen mit `surface.create_entity{name = "spice-harvester", …, item = stack}`; gespeicherte Werte werden übernommen (A20 :29792-29794).
  - Zurücklegen mit `harvester.mine{inventory = leitstellen_inventar}`, nur bei leerem Laderaum.
- **Feldsuche** [2.0]
  - `on_chunk_generated` (nur Arrakis) zählt pro Chunk `count_entities_filtered{area = chunk, name = "spice-sand"}`. `on_resource_depleted` hält die Zahlen aktuell.
  - Infrage kommen Chunks, die `force.is_chunk_charted` meldet (A20 :15169), die in Reichweite liegen, die nicht reserviert sind und keine Sektor-Ruhe haben.
  - Bewertet werden Menge, Flugweg zu Leitstelle und Annahme sowie Kartenmarkierungen mit Spice-Symbol (`force.find_chart_tags`, A20 :15322).
- **Bereitschaftsflug** [2.0]: `carryall.follow_target = harvester` (A20 :5177). Neue Ziele werden nur gesetzt, nicht angehängt (CL:1035).
- **Schaltung** [2.0]
  - Eingänge: `leitstelle.get_signal({type = "virtual", name = "signal-H"}, defines.wire_connector_id.circuit_red)`, dasselbe für Grün und für Signal R (A20 :3276-3285).
  - Ausgänge kommen nur auf eigene virtuelle Signale (`arrakis-signal-…`), nie auf H oder R. So entsteht keine Rückkopplung über das gemeinsame Netz.

**2.1-Komfort**
- [2.1] Patrouillen über `add_autopilot_destination` und `autopilot_patrol_size` (CL:495, CL:804).
- [2.1] Radar-Modus „universe“ (CL:481) und getrennte Drahtwahl für Ein- und Ausgang (CL:471).
- [2.1] Inventar-GUI (CL:848) und `transfer_from_inventory` (CL:852).

**Leistung** (Richtwert, nicht gemessen)
- 50 bis 100 Ernter und 20 bis 40 Carryalls sollten gehen.
- Flüge laufen in der Engine, der Abbau alle 30 Ticks mit Budget. Würmer existieren nur 25 bis 50 s pro Jagd.
- Würmer nicht massenhaft wachhalten; die Doku warnt vor den Kosten (A20 :28222-28229).
- Max misst im Spiel (T8).

### 4.5 storage-Struktur

```lua
storage = {
  schema = 2,
  rng   = LuaRandomGenerator,
  hold  = {surface = LuaSurface, free = {MapPosition...}},
  grace = {landed_tick = nil, ornithopter_tick = nil, active_from = nil, first_hunt_done = false},
  harvesters = { [un] = {entity, state = "mobile"|"deploying"|"deployed"|"packing"|"carried"|"docked",
                 timer_tick = nil, careful = false, resources = {LuaEntity...}, progress = 0,
                 drain_rest = 0, prod_rest = 0, last_tick = 0, renders = {...},
                 home = MapPosition|nil, lift_pos = MapPosition|nil, hold_slot = MapPosition|nil,
                 dock = un|nil, hangar = un|nil, job = id|nil} },
  flyers     = { [un] = {entity, kind = "ornithopter"|"carryall", cargo = un|nil,
                 docking = {harvester = un, done_tick = tick}|nil, renders = {...},
                 hangar = un|nil, job = id|nil, manual = false, last_tick = 0} },
  intakes    = { [un] = {entity, docked = un|nil, nozzles = {un...}} },
  nozzles    = { [un] = {entity, intake = un|nil} },
  hangars    = { [un] = {entity, out = LuaEntity, range = 300, target_count = 0, slots = {...}} },
  jobs       = { next_id = 1, list = { [id] = {type, prio, harvester = un, flyer = un|nil,
                 target = MapPosition, step, created_tick} } },
  vib        = { sources = { [un] = {entity, weight, mobile = bool} },
                 heat = { [chunk_key] = {h = 0, tick = 0} }, cursor = un|nil,
                 overlay = { [player_index] = {LuaRenderObject...} } },
  hunts      = { next_id = 1, list = { [id] = {kind = "harvest"|"building"|"thumper",
                 target = LuaEntity, target_un, origin_chunk, sector, state, warn_tick,
                 spawn_tick, eta_tick, candidates = {...}, spawn = MapPosition|nil,
                 path_request = uint|nil, route = {...}, worm = LuaSegmentedUnit|nil,
                 tag = LuaCustomChartTag|nil, renders = {...}} } },
  path_requests   = { [request_id] = hunt_id },
  sector_cooldown = { [sector_key] = tick },
  spice_chunks    = { [chunk_key] = {count, reserved_by = un|nil} },
  thumpers        = { [un] = {entity, until_tick} },
  reg             = { [registration_number] = {kind, un} },
  migration       = { pending_chunks = {ChunkPosition...}, done = false },
}
```
Alle gespeicherten Laufzeitobjekte (LuaEntity, LuaSegmentedUnit, LuaRenderObject, LuaCustomChartTag, LuaSurface, LuaRandomGenerator) dürfen in `storage` stehen.

### 4.6 Migration und Entfernen der Mod [2.0]

- **0.3.0 → 0.5.0** (`on_configuration_changed`, gesteuert über `storage.schema`):
  - **Bohrer auf Spice:** Durch die neue Kategorie bauen sie nichts mehr ab. Das Skript sucht auf Arrakis einmal `find_entities_filtered{type = "mining-drill"}`, prüft `mining_target` (A20 :4614) und meldet jeden Treffer mit Alarm und Kartenmarkierung.
  - **Erstbefüllung:** `on_chunk_generated` feuert für alte Chunks nicht noch einmal. Deshalb werden die Positionen aus `surface.get_chunks()` (A20 :31304) einmal in `storage.migration` kopiert und budgetiert abgearbeitet: Spice zählen und feste Vibrationsquellen auf Sand anmelden.
  - **Schonfrist:** Gibt es Arrakis schon, gilt `landed_tick = game.tick`; die Schonfrist beginnt also jetzt.
  - Verwaiste Ernter in der Ablage (ohne Träger) werden an ihren Abhebepunkt zurückgesetzt.
- **Entfernen der Mod:** Factorio löscht dabei alle Entities unserer Prototypen auf allen Oberflächen, und unser `on_configuration_changed` läuft nicht mehr. Ein Rettungsbefehl kann also keinen Ernter retten. Übrig bleibt nur die leere Oberfläche `arrakis-hold`; der Admin-Befehl `/arrakis-uninstall` löscht sie vorher mit `game.delete_surface`. Das neue `migrates_from` (CL:90, 2.1.18) hilft nur bei Umbenennungen.

## 5. Versionsstrategie 2.0 und 2.1

### 5.1 Was belegt ist

**Release-Stand von 2.1**
- Der 2.1-Teil des Changelogs reicht von 2.1.7 (23.06.2026) bis 2.1.20 (22.09.2026) (CL:2-3, CL:465-466).
- Dass 2.1 das letzte Update ist, steht dort nicht. Wir übernehmen es als Max' Aussage.
- Auch späte Patches ändern die Modding-API noch inkompatibel. Beispiel 2.1.20: `fuel_category` wird zu `fuel_categories` (CL:35).

**Kompatibilität zwischen 2.0 und 2.1**
- Eine Mod hat genau eine `factorio_version`. 2.0 lehnt eine Mod mit „2.1“ ab; das zeigte sich an Arrakis 0.1.0 (Repo-Commit 6f84fb9).
- Ob 2.1 eine Mod mit „2.0“ lädt, lässt sich lokal nicht belegen (T10).
- 2.0-Spielstände werden in 2.1 übernommen (CL:463). Der Weg zurück ist nicht dokumentiert.

**Mindestversion für 2.0**
- Demolisher-API ab 2.0.61 (CL:1565), `helpers` mit `compare_versions` in der Datenstufe ab 2.0.55 (CL:1758, CL:1761).
- Deshalb verlangt `info.json` künftig `base >= 2.0.61` statt `>= 2.0.0`. Getestet wird mit 2.0.77.

**Welche Fehlerbehebungen von 2.1 uns betreffen** (gegenüber v0.2 präzisiert)
- *Belegter 2.0-Fehler:* Sortierfehler zwischen Latenzausgleich und Render-Objekten (CL:1004; Forum-IDs aus der 2.0-Zeit). Er ist nur kosmetisch.
- *Wahrscheinlich ein 2.0-Fehler:* Spinnen-Wegpunkte anhängen nach einem Folgebefehl (CL:1035). Wir umgehen ihn (4.2).
- *Unklar, ob 2.0.77 betroffen ist:*
  - Absturz bei kleiner Knotenzahl (CL:77, T7),
  - Desync, wenn Spinnen getötet und neu gebaut werden (CL:81, Mehrspieler-Test),
  - Ausrüstungsbonus beim Teleport (CL:337). Der ist für uns egal, denn wir bauen kein Gitter ein.
- *Fehler, den es nur in 2.1 gab:* Spinnenbeine, behoben in 2.1.9 (CL:425). Er betrifft uns nicht, weil der 2.1-Build ohnehin mindestens 2.1.20 verlangt.

**Fazit:** Alle Kernmechaniken laufen mit 2.0.77. Ein technischer Zwang zum Umstieg besteht nicht.

### 5.2 Empfehlung

1. **Ab sofort versionsfest bauen (Phase 3.0).** Eine Quelle, eine kleine Weiche, keine API, die in 2.1 fehlt.
2. **Release-Ziel bleibt 2.0, solange Max 2.0.77 spielt.** Getestet wird in 2.0.77.
3. **Umstieg auf 2.1, sobald Max' übrige Mods 2.1 unterstützen.**
   - Gründe sind Komfort und eine ruhigere Mehrspieler-Basis, nicht fehlende Technik.
   - Beim Umstieg wird `info.json` umgestellt und der 2.0-Zweig eingefroren. Zwei Versionen dauerhaft zu pflegen, lohnt sich nicht.
4. **2.1-Extras nur hinter der Weiche.** Das Spiel ist ohne sie vollständig.

### 5.3 Die Weiche

```lua
-- prototypes/compat.lua
local compat = {}
local base = mods["base"]
compat.v21 = helpers.compare_versions(base, "2.1.0") >= 0
compat.v2120 = helpers.compare_versions(base, "2.1.20") >= 0

function compat.recipe_category(recipe, cat)          -- CL:707
  if compat.v21 then recipe.categories = {cat} else recipe.category = cat end
end
function compat.mine_trigger(name)                    -- CL:762
  if compat.v21 then return {type = "mine-entity", entities = {name}} end
  return {type = "mine-entity", entity = name}
end
function compat.vehicle_physics(p, braking, friction) -- CL:740
  p.braking_power, p.friction = nil, nil
  p.braking_force, p.friction_force = braking, friction
end
function compat.fuel_category(item, cat)              -- CL:35, erst ab 2.1.20
  if compat.v2120 then item.fuel_categories = {cat} else item.fuel_category = cat end
end
return compat

-- scripts/compat.lua (Laufzeit)
local V21 = helpers.compare_versions(script.active_mods["base"], "2.1.0") >= 0
```
- Für den 2.1-Build schreibt ein kleines Skript `info.json` um: `"factorio_version": "2.1"` und die Abhängigkeiten `"base >= 2.1.20"` und `"space-age >= 2.1.20"`. Ein 2.1.x vor 2.1.20 kommt damit nie zum Zug, und alle [2.1]-Funktionen sind sicher vorhanden (die spätesten kamen mit 2.1.18 und 2.1.20).
- Unbekannte Prototyp-Felder meldet Factorio nur mit `--check-unused-prototype-data` (CL:13997). Trotzdem stehen 2.1-Felder nur hinter der Weiche.

### 5.4 Breaking Changes im bestehenden Code (Stand 0.3.0)

| Stelle | Heute (2.0) | In 2.1 | Folge ohne Anpassung |
|---|---|---|---|
| `prototypes/technology.lua:79-83` | `research_trigger = {type = "mine-entity", entity = "spice-sand"}` | `entities = {"spice-sand"}` (CL:762, A21 types.d.ts) | Pflichtfeld fehlt, Ladefehler zu erwarten |
| `prototypes/spice.lua:127, 148, 164` | `category = "spice-refining"` | `categories = {…}` (CL:707) | Rezepte fallen auf „crafting“ zurück, das keine Fluide erlaubt. Melange und Spice-Essenz erzeugen Ladefehler |
| `prototypes/spice.lua:189` | `category = "smelting"` | `categories = {"smelting"}` | Sandziegel landet in „crafting“ |
| `prototypes/windtrap.lua:58` | `category = "arrakis-windtrap"` | `categories = {…}` | Wasserrezept in „crafting“, Ladefehler zu erwarten |
| `prototypes/resources.lua:26` | `probability = 1` | ersetzt durch `independent_probability` (CL:766) | Keine Wirkung. Streichen, Standardwert ist 1 |
| `info.json` (2.0-Build) | `base >= 2.0.0` | – | Unter 2.0.61 fehlt die Demolisher-API, also `>= 2.0.61` |
| `info.json` (2.1-Build) | `factorio_version "2.0"` | `"2.1"`, `>= 2.1.20` | Mod wird vermutlich nicht geladen (T10) |

Unverändert laufen `control.lua`, `data-updates.lua` (`LabPrototype.inputs` gibt es weiter), das Spice-Wissenschaftspaket als `tool` und alle per deepcopy übernommenen Vanilla-Prototypen.

### 5.5 Regeln für neuen Code (gelten für beide Versionen)

**Laufzeit**
- `disabled_by_script` statt `active =`, `minable_flag` statt `minable =` (CL:811-812).
- `defines.inventory.crafter_*` statt `assembling_machine_*` oder `furnace_*` (CL:923).
- Kein `LuaEntity.fluidbox` (CL:786), kein `create_cargo_pod` (CL:805), Display-Panel-Text nur als String (CL:806).
- Spinnen-Ziele setzen statt anhängen (CL:1035).

**Prototypen**
- Fahrzeuge nur mit `braking_force` und `friction_force`.
- Brennstoff-Items nur über `compat.fuel_category`.
- Beute per Skript statt über `loot` (CL:669).
- Container per deepcopy; `circuit_connector` ist in 2.1 ein Array (CL:661).
- In `key_sequence` nur dokumentierte Tastennamen (CL:646).
- Das Höchsttempo des Ernters in jeder getesteten Version kalibrieren (CL:244).

### 5.6 Was 2.1 zusätzlich bringt

Die [2.1]-Punkte stehen in 4.1 bis 4.4. Kurz zusammengefasst:
- **Warnungen:** für die ganze Force (CL:841), LuaPin (CL:381-383), Musik (CL:897).
- **Anzeige:** Tooltip-Felder (CL:797), Inventar-GUI (CL:848), Cursor-Vorschau (CL:902-903).
- **Flug:** Patrouille (CL:495, CL:804), Pin-Rechtsklick (CL:504), leichteres Anklicken in der Karte (CL:536).
- **Schaltung:** Radar „universe“ (CL:481), Drahtwahl (CL:471).
- **Latenzausgleich** für ferngesteuerte Autos (CL:494). Er nützt nur, falls Max die Fernsteuerung des Ernters erlaubt (offene Frage 3).
- **Für Phase 4 (Stürme):** die Oberflächen-Eigenschaft „robot-energy-usage“ (CL:642) und `play_music`.

## 6. Forschungsbaum

| Technologie | Voraussetzung | Auslöser / Kosten (grob) | Schaltet frei | Version |
|---|---|---|---|---|
| Spice-Verarbeitung (besteht) | Entdeckung Arrakis | Trigger: Spice-Sand abbauen | Raffinerie, Melange, Sandziegel | [2.0/2.1] Triggerschreibweise |
| **Spice-Ernte** (neu) | Spice-Verarbeitung | Trigger: 10 Melange herstellen | Ernter, Annahme, Tankstutzen, ggf. Spice-Brikett; Briefing „Wurmzeichen“ | [2.0] |
| **Ornithopter** (neu, war Endgame) | Spice-Ernte | Trigger `craft-item`: Spice-Ernter (A20 prototype/generated/types.d.ts:4083) | Ornithopter; startet die Schonfrist | [2.0] |
| **Thumper** (neu) | Spice-Ernte | Trigger `scripted`: erste Jagd überstanden, ausgelöst mit `force.script_trigger_research` (A20 :15550) | Thumper | [2.0] |
| Spice-Wissenschaft (besteht) | Spice-Verarbeitung | Trigger: 20 Melange | Spice-Essenz, Spice-Paket | [2.0] |
| **Ornithopter-Leitstelle** (Stufe 2) | Spice-Wissenschaft, Ornithopter | 300 × Automatisierung, Logistik, Chemie, Weltraum, Spice | Leitstelle, Carryall, Rettung, Entladen, Tanken | [2.0] |
| **Ernter Mk2** | Leitstelle | 300 × wie oben; Rezept mit Wurmzähnen | Ernter Mk2 | [2.0] |
| **Flottenleitung** (Stufe 3) | Leitstelle | 1000 × wie oben + Metallurgie | Einsatz, Umsetzen, Feldsuche, Schaltung | [2.0] |
| **Bereitschaftsflug** | Flottenleitung | 500 × wie oben | Carryall folgt seinem Ernter | [2.0] |
| **Frühwarnung** (6 Stufen) | Flottenleitung | steigend, mit Spice | +5 s Vorwarnzeit je Stufe, höchstens 90 s; Zeitlimit der Jagd = t_warn + 60 s | [2.0] |
| **Ernte-Dämpfung** (endlos) | Flottenleitung | `count_formula`, mit Spice | −5 % Ernter-Vibration je Stufe, höchstens −50 %. Effekt `type = "nothing"` mit `effect_description`; das Skript liest die Stufe | [2.0] |
| Suspensor-Dämpfung (Phase 4) | Plast-Stahl | Spice | Gebäude auf Suspensor-Fundament vibrieren nicht | [2.0] |

- Die endlose „Carryall-Reichweite“ aus v0.2 entfällt. Mehr Reichweite gibt es nur über ein schnelleres Fluggerät (Carryall Mk2), weil sie am Zeitbudget der Rettung hängt.
- Ornithopter, Ernter und Thumper sind Trigger-Forschungen wie die Ersthelfer-Techs in Space Age. Die erste Forschung mit Spice-Paketen ist die Leitstelle; Automatisierung ist damit der Lohn für die Spice-Kette.

## 7. Roadmap ab Phase 3

Ersetzt die alte Phase 3 und holt den Ornithopter aus Phase 5 nach vorn. Jede Phase endet mit einem Test, den Max im Spiel machen kann.

| Phase | Version | Inhalt | Testbares Ergebnis |
|---|---|---|---|
| 3.0 | 0.3.1 | Versionsweiche, Breaking Changes aus 5.4, `probability` gestrichen, `base >= 2.0.61` | Ein 0.3.0-Spielstand lädt in 2.0.77 unverändert. Optional: Mit 2.1-`info.json` startet die Mod in 2.1.20 |
| 3a | 0.4.0 | Prüfstand `/arrakis-test` mit Test-Prototypen: T1–T7, T9, T11, T12 | Protokoll entscheidet: Spider oder Auto als Flieger, Proxy oder Skript, wie der Wurm gesteuert wird, Ernter-Tempo, Noise-Schwelle |
| 3b | 0.5.0 | Ernter (Abbau, Aufbauen/Einpacken, Tempo-Deckel, Vorsichtsmodus), Ressourcenkategorie samt Migration, Annahme und Tankstutzen, Forschung „Spice-Ernte“, Kartengenerator (Lehrfeld, Mindestabstand), Brennstoff nach Frage 5 | Ernter fährt höchstens 1,5 Kacheln/s, erntet 2000 Spice-Sand, die Annahme leert ihn per Greifarm, der Tankstutzen tankt; die Statistik zeigt Spice. Ein 0.3.0-Spielstand meldet Bohrer auf Spice |
| 3c | 0.6.0 | Ornithopter mit Trigger-Forschung, Ablage, Anheben/Absetzen per Taste und Fernbedienung, Fahrer als Beifahrer, Absturzregeln | Vollen Ernter von Feld A nach B tragen, Inhalt identisch; der Fahrer fliegt mit. Ornithopter mit Last zerstören: Der Ernter fällt mit 30 % Schaden |
| 3d1 | 0.7.0 | Vibration, Wärme, Unruhe, Wurmzeichen, Countdown, Schonfrist, Briefings, Vibrationsanzeige; **geskripteter Biss mit Eruption, noch ohne Wurm-Entity** | Ein einzelner Ernter: Unruhe nach etwa 25 s, Wurmzeichen nach etwa 55 s; Lehrjagd 90 s. Mit Rettung bleibt er heil, ohne Rettung kommt der Biss genau bei 0. Auf einem Nicht-Lehrfeld scheitert die Flucht per Fahrt |
| 3d2 | 0.8.0 | Wurm-Entity mit verzögertem Spawn, Körperprüfung, Route/ROUTING, Fels-Wächter, Abtauchen, ohne Ascheeffekte (T5–T7) | Biss höchstens 3 s nach Countdown-Ende. Vor einer Felsinsel biegt der Wurm ab. Ein Ernter 10 Kacheln vor Fels wird trotzdem gebissen. Ein Ornithopter über dem Kopf verliert kein Tempo |
| 3d3 | 0.9.0 | Thumper (Ablenkung/Köder), Beute und Wurmzahn, großer Wurm, Mod-Einstellungen, Balancing-Runde | Ein Thumper lenkt eine laufende Jagd um. Ein getöteter Wurm wirft Zähne. 1 Ernter liefert im Wurm-Rhythmus etwa 15 Pakete/min |
| 3e | 0.10.0 | Leitstelle, Carryall, RETTUNG (Schweben), TANKEN, ENTLADEN, RÜCKKEHR, Alarm „Rettung nicht möglich“ | 3 Ernter, eine Leitstelle, 2 Carryalls, Kohle in der Leitstelle: 60 min ohne Eingriff, kein Ernter verloren, kein Ernter ohne Treibstoff |
| 3f | 0.11.0 | Flottenleitung: EINSATZ, UMSETZEN, RÜCKRUF, Feldsuche, Schaltung, Bereitschaftsflug, Frühwarnung, Ernte-Dämpfung | Mit 5 Ernter im Inventar und Signal H = 3 laufen drei Ernter. R holt alle zurück. Die Statussignale stimmen |
| 3g | optional | 2.1-Komfortschicht (5.6) | Nur bei Umstieg: Alle [2.1]-Punkte sind sichtbar, der 2.0-Build bleibt unverändert |
| 4 | 0.12 | Coriolis-Stürme (Rückruf-Signal, Flugwarnung), Todesdestille, Plast-Stahl, Suspensor-Dämpfung | Ein Sturm kommt mit Vorwarnung, und die Leitstelle ruft auf Signal alle Ernter zurück |
| 5 | 0.13 | Endgame: Spice-Navigation, Holtzman-Schild, Mentat-Kern, Prescience, Carryall Mk2 | Die Endlos-Forschungen laufen |
| 6 | 1.0 | Eigene Grafiken (Wurm als Sandwelle, Ernter, Ornithopter), Balancing, Mod-Portal | Release-Kandidat |

## 8. Risiken und frühe Tests

Im Container läuft kein Factorio. Deshalb baut Phase 3a einen **Prüfstand**:
- `/arrakis-test Tn` baut in einem Wegwerf-Spielstand den Testaufbau auf, misst, was sich messen lässt, und schreibt OK oder FEHLER samt Werten in den Chat.
- Max meldet das Ergebnis, bei optischen Fragen mit Screenshot.

| Nr | Risiko (nicht belegt) | Test | Wenn es scheitert |
|---|---|---|---|
| T1 | Ein Spider-Vehicle mit 1 bis 4 unsichtbaren, kollisionsfreien Beinen fliegt nicht sauber oder zu langsam | Varianten über Sand, Fels, Wasser und Gebäude. **Kriterium: Ornithopter ≥ 5, Carryall ≥ 6 Kacheln/s.** Dazu: Verhalten ohne Treibstoff, feuert `on_spider_command_completed` bei Skript-Ziel, optional Last-Sticker | Flieger als `car` mit Flugmaske, Carryalls virtuell (4.2); Ankunft per Abfrage |
| T2 | `disabled_by_script` hält den Ernter nicht; `custom_status` ist im Fahrzeugfenster unsichtbar; das Tempo hängt vom Brennstoff ab | Aufbauen und losfahren versuchen; Höchsttempo mit Kohle, Festbrennstoff und Raketentreibstoff messen, in jeder getesteten Version | `effectivity_modifier = 0` beim Aufbauen (A20 :4129-4134); Status im eigenen GUI; Tempo-Deckel enger |
| T3 | Beim Teleport zur Ablage und zurück geht etwas verloren | Kofferraum, Treibstoff, Gesundheit, Qualität, Name und Farbe vorher und nachher vergleichen, auf vorgenerierten Stellplätzen | Absetzen per `clone` (A20 :3453) |
| T4 | `proxy-container` mit `car_trunk` oder `fuel`: Greifarme entnehmen bzw. befüllen nicht, die Schaltung liest nichts; `area` der Bauregel darf nicht größer als das Gebäude sein; Skriptdraht sichtbar/entfernbar | Annahme und Tankstutzen mit Ernter, Greifarmen und Kisten 60 s laufen lassen | Umladen per Skript; Felsprüfung beim Bauen im Skript |
| T5 | Die Wurm-KI folgt den Skriptzuständen nicht wie erwartet | `investigating` zu einem Punkt hinter dem Ziel; `attacking` auf ein Auto; `get_ai_state` nach der Ankunft; `vision_distance = 0`; Drosselung per `speed`; Flieger 3 s über dem Kopf (Tempo, Sticker) | Ziel laufend nachführen, `speed` bzw. `move_forward` per Skript (A20 :28085, :28198); fehlende Ascheeffekte nachträglich entfernen |
| T6 | Fels-Ebene in der Wurmmaske blockiert, flackert oder wirkt nicht; Wächter lenkt falsch um | Wurm über eine Felsinsel schicken, mit und ohne Ebene; Ernter 10 Kacheln vor Fels | Nur den Wächter nutzen |
| T7 | Absturz bei kleiner Knotenzahl in 2.0.77; die Körperprüfung findet Fels nicht | `extended = false` einmal probieren; Spawn neben einer Felskante | Immer `extended = true`; Prüfung dichter |
| T8 | Laufzeitkosten | 50 Ernter, 20 Carryalls, 3 Jagden; Debug-Anzeige „show-time-usage“ | Takt strecken, Budget senken |
| T9 | Schatten: `draw_as_shadow` am Sprite-Prototyp wirkt beim Rendern nicht | Schatten-Sprite unter getragenem Ernter | Schwarz getöntes, halbtransparentes Sprite |
| T10 | 2.1 lädt keine Mod mit `factorio_version "2.0"` | Nur falls Max 2.1 installiert: 0.3.1 einmal starten | Getrennte Builds per `info.json` |
| T11 | Die Noise-Schwelle ergibt nicht ≥ 100 Kacheln Sand zwischen Spicefeld und Fels | `/arrakis-test T11` misst in generierten Chunks per Stichprobe den Abstand jedes Felds zum nächsten Fels | Schwelle verschieben, Startwert `arrakis_rock < −0,25` |
| T12 | Rettung aus der Kartenansicht: Ist `player.vehicle` beim Fernsteuern des Ornithopters gesetzt, und kommt die Taste an? | Ornithopter aus der Karte fahren bzw. per Fernbedienung schicken, Taste drücken | Nur über `spidertron_remote_selection` |

Weitere Risiken:
- **Spielgefühl und Balancing.** Alle Zeiten und Schwellen sind Mod-Einstellungen. 3d1 testet das Timing früh, noch ohne Wurm-Technik, und 3d3 enthält eine eigene Balancing-Runde.
- **Mehrspieler.** Render-Sortierung (CL:1004, kosmetisch) und ein Desync, wenn Spinnen getötet und neu gebaut werden (CL:81; offen, ob 2.0.77 betroffen ist). Einmal mit zwei Spielern testen, dabei einen Ornithopter zerstören und neu bauen.
- **Platzhalter-Optik.** Getönte Panzer und Spidertrons erkennt man nicht sofort als Ernter und Ornithopter. Bis Phase 6 erklären Factoriopedia-Texte und Briefings die Rollen.

## 9. Bekannte Unsicherheiten

Das hier ist geplant, aber erst ein Test im Spiel kann es klären. Alles andere im Dokument ist in API, Vanilla-Daten oder Changelog belegt.

- **Flugverhalten (T1).** Ob eine Spinne mit unsichtbaren Beinen glatt fliegt, wie schnell sie ist und was sie ohne Treibstoff tut. Davon hängen Reichweite der Leitstelle und Rettungszeiten ab.
- **Ankunftsereignis (T1).** Ob `on_spider_command_completed` auch bei einem per Skript gesetzten Ziel feuert.
- **Wurm-KI (T5).** Die Doku beschreibt die KI-Zustände, nicht ihr genaues Verhalten. Offen ist, ob ein Wurm ein Auto als Angriffsziel hält, was er nach der Ankunft tut und wie gut sich sein Tempo drosseln lässt.
- **Ascheeffekte (T5).** Ob nach dem Entfernen wirklich nichts mehr Flieger bremst.
- **Proxy-Container (T4).** Ob sie mit Kofferraum und Treibstoffinventar eines Autos für Greifarme funktionieren und ob die Bauregel eine Fläche größer als das Gebäude zulässt.
- **Ernter-Tempo (T2).** Welches Höchsttempo der Panzer-Abkömmling mit welchem Brennstoff erreicht; 2.1.13 hat das geändert (CL:244).
- **Kartengenerator (T11).** Wie weit Spicefelder bei einer Noise-Schwelle tatsächlich vom Fels entfernt liegen.
- **Fehler aus 2.1.18 in 2.0.77 (T7, Mehrspieler-Test).** Ob 2.0.77 von den dort behobenen Fehlern betroffen ist: Absturz bei kleiner Knotenzahl, Spinnen-Desync.
- **2.1 und alte Mods (T10).** Ob 2.1 Mods mit `factorio_version "2.0"` lädt.
- **Leistung (T8).** Die Kosten bei großen Flotten.
- **Spielspaß.** Ob 55 s bis zum Wurmzeichen, 60 s Vorwarnung, 2 bis 4 Minuten Ruhe und etwa 15 Pakete/min pro Ernter sich gut anfühlen, zeigt nur Spielen.
