# Prüfstand `/arrakis-test` – Anleitung für Max

Stand: Mod 0.5.0 · Factorio 2.0.77 mit Space Age

Der Prüfstand baut im Spiel Testaufbauten, misst selbst und schreibt die Ergebnisse in den Chat und in eine Datei.
Er klärt die offenen Fragen aus dem Design (`docs/design-ernter-ornithopter.md`, Abschnitt 8).
Du musst nur zuschauen, ein paar Fragen beantworten und am Ende die Dateien schicken.

## Vorbereitung

1. **Einstellung einschalten:** im Hauptmenü *Einstellungen → Mod-Einstellungen → Start* das Häkchen bei **Prüfstand** setzen und bestätigen. Factorio startet neu.
2. **Wegwerf-Spielstand:** ein neues Spiel mit Space Age starten (oder einen Spielstand, der kaputtgehen darf). Nie den echten Spielstand nehmen.
   Die Tests laufen auf einer eigenen Oberfläche `arrakis-testbench`, deine Basis bleibt unberührt. T11 legt kurz leere Testoberflächen `arrakis-t11-…` an und löscht sie wieder.
3. **Alte Ergebnisdatei löschen** (wenn du eine saubere Datei willst): `%APPDATA%\Factorio\script-output\arrakis-test.txt`. Der Prüfstand hängt nur an.
4. Danach die Einstellung wieder ausschalten, bevor du normal spielst.

## Befehle

Im Chat eingeben (nur Admins; im Einzelspiel bist du Admin):

| Befehl | Wirkung |
|---|---|
| `/arrakis-test` | Liste aller Tests mit Dauer, Hinweisen und letztem Ergebnis |
| `/arrakis-test T1` | Test T1 starten (ebenso `T2` … `T13` und `T2b`, groß oder klein geschrieben); ein laufender Test wird abgebrochen |
| `/arrakis-test alle` | alle nicht-interaktiven Tests nacheinander: T1–T7 (T7 nur Teil a), T11, T13, T2b. Dauer etwa 15 min |
| `/arrakis-test stop` | laufenden Test bzw. „alle“ abbrechen |
| `/arrakis-test zurück` | zurück an die Stelle, an der du vor dem Test warst |
| `/arrakis-test T7 ja` | T7 mit Teil b (kann das Spiel abstürzen lassen) |

Die meisten Tests bringen dich zum Zuschauen an den Testaufbau. Mit `/arrakis-test zurück` kommst du zurück.
Jeder Test hat ein Zeitlimit; danach meldet er „Zeitüberschreitung“ und räumt auf.

## Was die Zeilen bedeuten

Jede Zeile beginnt mit der Testnummer und einer Art, z. B. `[T1] OK: …`:

- **OK / FEHLER:** ein festes Kriterium ist erfüllt bzw. nicht erfüllt.
- **MESSUNG:** Messwerte (Zahlen mit Dezimalpunkt).
- **INFO:** Hinweise zum Ablauf.
- **FRAGE:** Das kann nur dein Auge prüfen. Bitte genau das beantworten, was dort steht.
- **ENDE:** einzeilige Zusammenfassung des Tests.

In der Datei stehen zusätzlich Messpunkte im Sekundentakt (nicht im Chat).
Steht irgendwo „Skriptfehler“, bitte unbedingt melden.

## Was du schicken sollst

1. Die Datei `%APPDATA%\Factorio\script-output\arrakis-test.txt`.
   Nach T11 zusätzlich `arrakis-t11-karten.txt` aus demselben Ordner (Kartenbilder; T11 überschreibt sie bei jedem Lauf).
2. Deine Antworten auf alle FRAGE-Zeilen, mit Testnummer.
3. Die erbetenen Screenshots (T1, T5, T6, T9).

## „alle“

`/arrakis-test alle` startet T1, T2, T3, T4, T5, T6, T7 (Teil a), T11, T13 und T2b nacheinander, mit 1 s Abstand.
Nach T2 und T4 wartet er 30 s, damit du deren FRAGE vor Ort beantworten kannst; der Chat sagt das an.
Die FRAGEn von T1, T5 und T6 gelten während des Tests: einfach zuschauen.
Am Ende kommt eine Zusammenfassung mit allen offenen FRAGEn. Was du verpasst hast, wiederholst du einzeln (z. B. `/arrakis-test T2`).
T9 und T12 brauchen dich und laufen nur einzeln.

## Die Tests

### T1 Flieger: Beine, Tempo, Gelände (bis 110 s)

**Was passiert:** Sieben Testflieger starten gleichzeitig nach Osten, 220 Kacheln weit über Sand, Fels, Wasser und ein Gebäuderaster.
Varianten: 1, 2 und 4 Beine, 4 schnelle Beine, ohne Treibstoff und zweimal mit Last-Sticker (zwei verschiedene Bremsfelder).
Du stehst am Ostende des Sandstegs durchs Wasser, direkt vor dem Gebäuderaster (x = 110). Der Test wertet selbst aus, sobald alle angekommen sind, spätestens nach 110 s.

**Du:** zuschauen, während des Flugs einen Screenshot machen.

**Melden:** Sieht der Flug glatt aus? Sind die Beine unsichtbar? Dazu der Screenshot.

### T2 Ernter: Skriptfahrt, Tempo, Sperre, Status (etwa 70 s)

**Was passiert:** Ein Test-Ernter fährt mit einer Puppe am Steuer fünfmal je 15 s nach Osten: mit Kohle, Festbrennstoff, Raketentreibstoff, mit Tempo-Deckel und gesperrt (`disabled_by_script`).
Am Ende bleibt er stehen, nicht abbaubar und mit dem Status „Prüfstand: aufgebaut“.

**Falls die Skriptfahrt nicht geht:** Der Chat meldet FEHLER „Skriptfahrt geht nicht“ und setzt dich selbst in den Ernter.
Dann **W gedrückt halten, bis die Meldung „W loslassen“ kommt** (etwa 75 s). Aussteigen nur, wenn der Chat es sagt.

**Du am Ende:** den Ernter anklicken (Fenster öffnen) und versuchen, ihn abzubauen (Rechtsklick halten).

**Melden:** Steht „Prüfstand: aufgebaut“ im Fenster? Lässt er sich abbauen (sollte nicht)?

### T3 Ernter: Teleport zur Ablage (etwa 4 s)

**Was passiert:** Ein voll beladener Ernter (Qualität, Ladung, Treibstoff, Brennvorgang, 60 % Gesundheit, Farbe) wird auf eine versteckte Ablage-Oberfläche `arrakis-test-hold` teleportiert und zurück.
Jedes Feld wird mit dem Zustand vorher verglichen (etwa 24 OK/FEHLER-Zeilen). Die Ablage bleibt im Spielstand und wird wiederverwendet.

**Du:** nichts. **Melden:** nur die Datei.

### T4 Annahme und Tankstutzen (etwa 70 s)

**Was passiert:** Ein Felsquadrat im Sand. Die Bauregel der Spice-Annahme wird an drei Stellen geprüft.
Dann: Annahme (orange 2×2-Kiste in der Felsmitte) mit Greifarm zu einer Kiste, Kohlekiste mit Greifarm zum Tankstutzen (blaue Kiste), daneben ein Ernter und ein Rechenkombinator, per Skript mit rotem Draht an der Annahme.
60 s Betrieb, dann werden die Ziele gelöst und 10 s weiter gemessen. Alles bleibt stehen.

**Du am Ende:** zum Kombinator links neben der Annahme schauen und versuchen, den roten Draht zu entfernen.

**Melden:** Siehst du den roten Draht zwischen Annahme und Kombinator? Kannst du ihn entfernen? (Erwartet: unsichtbar und nicht entfernbar.)

### T5 Wurm-KI (etwa 100 s)

**Was passiert:** Nacheinander vier Testwürmer auf vier Bahnen: a) zu einem Punkt hinter einem Ernter, b) Angriff auf einen Ernter, c) gebremst, d) ein Flieger schwebt 3 s über dem Wurmkopf.
Deine Spielfigur ist dabei unverwundbar und steht südlich der Bahnen.

**Du:** herauszoomen und zuschauen, ein Screenshot.

**Melden:** Ziehen die Würmer Ascheschwaden oder dunkle Spuren hinter sich her (sollten fehlen)? Sind sie sandfarben?

### T6 Fels-Ebene und Wächter (bis 110 s)

**Was passiert:** Vier Würmer gleichzeitig auf vier Bahnen, jede mit einer Felsinsel: A ohne Schutz, B mit Fels-Kollisionsebene, C mit Fels-Wächter, D greift einen Ernter vor dem Fels an.
Du stehst zwischen B und C und bist unverwundbar.

**Du:** Bahn B (nördlich von dir) und Bahn C (südlich) beobachten, ein Screenshot.

**Melden:** Was macht der Wurm auf Bahn B an der Felsinsel: hält er an, weicht er aus, flackert er oder fährt er durch? Wirkt das Ausweichen auf Bahn C glatt?

**Bewertung:** OK nur, wenn der Kopf auf Bahn C und D nie auf Fels war **und** Bahn C am Ziel ankam **und** Bahn D den Ernter erreicht hat. Kam C nicht an oder D nicht zum Ernter, steht dort FEHLER „Wächter nicht bestätigt“.

### T7 Körperprüfung und `extended = false` (1 s, mit `ja` etwa 12 s)

**Was passiert:** a) Zwei Würmer erscheinen kurz: einer mit dem Körper im Fels, einer ganz auf Sand. Geprüft wird, ob die Körperprüfung Fels erkennt.
b) Nur mit `/arrakis-test T7 ja`: ein Wurm mit `extended = false`. **Das kann das Spiel abstürzen lassen.** Vorher steht eine Warnung im Chat und in der Datei.

**Du:** für b) nur im Wegwerf-Spielstand, vorher speichern. **Melden:** ob das Spiel abgestürzt ist. Dann ist die Warnzeile die letzte Zeile der Datei.

### T9 Flieger: Schatten der Last (interaktiv, 57 s)

**Was passiert:** Neben dir schweben drei Flieger mit einem Panzerbild als „getragener Ernter“:
A mit Schatten-Sprite (`draw_as_shadow`), B mit Ersatzschatten (schwarz, halbtransparent), C fliegt mit dem Bild im Kreis.
Ein vierter Flieger wird automatisch auf die Ablage teleportiert (OK/FEHLER: verschwindet das Bild mit). A, B und C bleiben nach dem Test stehen.

**Du:** Screenshots von A, B und C.

**Melden:** Welcher Schatten sieht richtig aus, A oder B? Liegt das Panzerbild unter dem Rumpf? Folgt es bei C dem Flug ohne Ruckeln?

### T11 Kartengenerator: Fels-Varianten im Seed-Vergleich (etwa 5 s)

**Was passiert:** T11 vergleicht die Fels-Verteilung von 0.4.0 mit vier neuen Varianten (je mit mehreren Felsanteilen), auf dem Seed deines Spielstands und acht festen Seeds, je 1600 × 1600 Kacheln.
**Am besten im Testspielstand vom letzten Mal starten:** Dort hat Arrakis den Seed, bei dem rund um den Start alles Fels war. T11 verändert dort nichts.
Es wird keine Karte erzeugt: Für jeden Seed entsteht kurz eine leere Testoberfläche, T11 liest dort nur die Rauschwerte und löscht sie wieder. **Das Spiel ruckelt dabei etwa eine halbe Minute.** Du bleibst, wo du bist.
Gemessen werden Felsanteil, Inseln, Abstand des Sands zum Fels und die Schwelle, ab der Spice mindestens 100 Kacheln vom Fels entfernt liegt. Im Chat steht am Ende je Variante eine Zeile, alles Weitere in der Datei. (Variante c3 zählt vor allem für Fels und Inseln; ihre Spicefläche ist bauartbedingt klein.)

**Du:** nichts. **Melden:** zwei Dateien, `arrakis-test.txt` und `arrakis-t11-karten.txt` (Kartenbilder als Text, beide im selben Ordner).

### T12 Flieger: Rettung aus der Kartenansicht (interaktiv, 3 min)

**Was passiert:** Neben dir steht ein Flieger mit Treibstoff. Ist deine Hand leer, bekommst du eine Spidertron-Fernbedienung; der Flieger ist damit ausgewählt.
Jeder Druck auf **ALT+O** schreibt eine MESSUNG-Zeile. Der Test endet nach 3 min oder mit `/arrakis-test stop`.

**Du, in drei Schritten:**
1. In den Flieger einsteigen (Enter), Karte öffnen (M), den Flieger aus der Karte steuern (WASD) und ALT+O drücken.
2. Aussteigen, die Fernbedienung in die Hand nehmen (ist sie weg: noch einmal ein- und mit leerer Hand aussteigen, dann legt der Test sie dir in die Hand; die Verknüpfungsleiste gibt sie erst nach der Forschung „Spidertron“), damit auf den Flieger klicken, Karte öffnen (M) und ALT+O drücken.
3. Karte schließen und in der normalen Ansicht ALT+O drücken.

**Melden:** ob bei jedem Schritt eine MESSUNG-Zeile kam (die Datei reicht).

### T13 Ernter: echter Code (etwa 2 min)

**Was passiert:** Ab 0.5.0 gibt es den echten Spice-Ernter mit Annahme und Tankstutzen. T13 prüft genau diesen Code, nicht den Nachbau aus T2–T4.
Auf der Prüfstand-Fläche entstehen nacheinander zwölf kleine Aufbauten: Spice-Teppiche auf Sand, eine Felsinsel mit Annahme, Stutzen, Greifarmen und Kisten, ein Bohrer auf Spice, zwei Bänder und eine Zustandstabelle aus 20 Feldern mit je einem Ernter (dazu drei einzelne Ernter für die Hinweis-Fälle, einer davon auf der Ablage-Oberfläche).
Der Test bringt dich jeweils zum Zuschauen hin. Die zwölf Schritte:

1. Aufbauen und 15 s Ernten: Ausbeute, Abzug am Feld, Treibstoff und Produktionsstatistik.
2. Im aufgebauten Ernter gibt eine Puppe 5 s Gas: er darf sich nicht bewegen und lässt sich nicht zum Abriss markieren. Sitzt die Puppe nicht im Ernter, meldet der Schritt FEHLER „nicht prüfbar“.
3. Laderaum voll, 10 s warten, leeren: danach kein Nachholen.
4. Einpacken: nach 10 s wieder fahrbereit; auf Sand nicht abbaubar, auf Fels schon.
5. Zwei Ernter leeren drei kleine Spice-Felder bis zum Ende („Feld erschöpft“).
6. Andocken an der Annahme, 10 s Greifarme (Spice raus, Kohle rein), Abdocken mit dem Umschalter, wieder Andocken.
7. Die Annahme wird zerstört, während der Ernter angedockt ist. Dann dockt er an einer neuen Annahme an und wird dort zerstört.
8. Kopie und Teleport eines aufgebauten Ernters. Die Kopie steht auf Fels und muss fahrbereit und abbaubar sein.
9. Eine Annahme auf Sand wird zum Abriss markiert und nimmt keinen Ernter an.
10. Ein Bohrer auf Spice wird gemeldet. Die Chat-Zeile „Arrakis: 1 Bohrer stehen auf Spice-Sand …“ und der Alarm gehören dazu; die Kartenmarkierung entfernt der Test wieder.
11. Ein Ernter auf einem laufenden Band bleibt stehen; ein normales Auto daneben muss sich bewegen, sonst meldet der Schritt FEHLER „nicht prüfbar“.
12. Zustandstabelle: fünf Zustände (fahrbereit, baut auf, aufgebaut, packt ein, angedockt) × vier Eingaben (Umschalter, Andocken, Tod, Teleport/Kopie), je ein eigener Ernter. Wo die Eingabe den Ernter von Sand auf Fels bringt (Abbruch des Aufbaus auf Fels, Teleport, Kopie), muss die Abbausperre sofort umspringen. Dazu drei Fälle, in denen der Umschalter nur einen Hinweis gibt: kein Spice im Feld, in Fahrt, nicht auf Arrakis.

Je Schritt kommt genau eine OK- oder FEHLER-Zeile mit den gemessenen Werten; die Einzelwerte stehen nur in der Datei.
Was sich nicht automatisch prüfen lässt (Fenster, Knopf und Taste `Umschalt+H`, Abbauen von Hand oder per Roboter, Speichern und Laden, Mehrspieler, alter Spielstand), nennt eine INFO-Zeile am Anfang; das bleibt für deine Abnahme.
Am Ende entfernt der Test seine Ernter. Annahmen, Kisten, Bänder und der Bohrer bleiben auf der Prüfstand-Fläche stehen.

**Du:** nichts, zuschauen. **Melden:** nur die Datei.

### T2b Ernter: Fahrphysik (etwa 3 min)

**Was passiert:** Der echte Spice-Ernter mit einer Puppe am Steuer fährt 14 Läufe zu je 10 oder 15 s:
mit Kohle, Festbrennstoff, Raketentreibstoff, Atomtreibstoff und legendärem Raketentreibstoff (alle mit Tempo-Ausgleich), nach Westen, Norden, Süden und zweimal schräg, zweimal bei negativen Koordinaten (um −1000, −1000) und einmal mit vollem Laderaum.
Ein zweiter Ernter, den der Mod absichtlich nicht kennt, fährt mit Raketentreibstoff ohne Ausgleich und ohne Deckel; er wird nur gemessen.
Je Lauf stehen Tempo (`speed`), Spitze, Bodentempo (zurückgelegte Strecke ab 5 s) und der Ausgleichswert `effectivity_modifier` in der Zeile.
FEHLER heißt (ab der ersten Sekunde eines Laufs): Spitze über 1,5 Kacheln/s, der Tempo-Deckel des Mods musste eingreifen (dann war das Tempo vor dem Deckel über 1,5), Bodentempo über 1,5 oder Ausgleich nicht wie erwartet. Ohne Qualität im Spiel entfällt der legendäre Lauf mit einer INFO-Zeile.
Am Ende entfernt der Test beide Ernter.

**Du:** nichts, zuschauen (die Ernter fahren an dir vorbei). **Melden:** nur die Datei.

## Bekannte Grenzen

- Die Flieger-Beine drehen nicht mit der Flugrichtung. T1 fliegt nur nach Osten; die Werte für 1 und 2 Beine gelten für Ost-West-Flug.
- Der Tempo-Deckel in T2 läuft mit Raketentreibstoff. Fährt der Ernter ohne Deckel nicht schneller als 1,6 Kacheln/s, nimmt der Test einen Ersatzdeckel (70 % seines Höchsttempos), damit der Deckel überhaupt greifen muss.
- T6, Bahn D: Bewertet wird der Kopf bis zum Biss. Was der Wurm danach tut, steht als MESSUNG/INFO da (im Spiel taucht er beim Biss ab).
- Im normalen Spiel erntet der Ernter nur auf Arrakis. Die Prüfstand-Fläche gibt dieselbe Einstellung **Prüfstand** frei, die auch den Befehl bringt; nur deshalb kann T13 dort mit dem echten Code ernten.
- T13, Schritt 11: Bewegt sich auch das normale Auto auf dem Band nicht, sagt die Messung nichts; dann meldet der Schritt FEHLER „nicht prüfbar“. Bitte trotzdem die Datei schicken.
- T2b liest das Tempo im Prüfstand-Takt, nach dem Tempo-Deckel des Mods. Deshalb zählt jeder Lauf, wie oft der Deckel eingegriffen hat („Deckel n× (ab 1 s m×)“); in der ersten Sekunde ist das nach einem Brennstoffwechsel erlaubt, danach ist es ein FEHLER. Die INFO-Zeile am Ende fasst das zusammen. Die echte Fahrt zeigt in jedem Fall das Bodentempo.
