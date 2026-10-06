# Prüfstand `/arrakis-test` – Anleitung für Max

Stand: Mod 0.4.0 · Factorio 2.0.77 mit Space Age

Der Prüfstand baut im Spiel Testaufbauten, misst selbst und schreibt die Ergebnisse in den Chat und in eine Datei.
Er klärt die offenen Fragen aus dem Design (`docs/design-ernter-ornithopter.md`, Abschnitt 8).
Du musst nur zuschauen, ein paar Fragen beantworten und am Ende die Datei schicken.

## Vorbereitung

1. **Einstellung einschalten:** im Hauptmenü *Einstellungen → Mod-Einstellungen → Start* das Häkchen bei **Prüfstand** setzen und bestätigen. Factorio startet neu.
2. **Wegwerf-Spielstand:** ein neues Spiel mit Space Age starten (oder einen Spielstand, der kaputtgehen darf). Nie den echten Spielstand nehmen.
   Die Tests laufen auf einer eigenen Oberfläche `arrakis-testbench`, deine Basis bleibt unberührt. T11 erzeugt aber Kartenbereiche auf Arrakis.
3. **Alte Ergebnisdatei löschen** (wenn du eine saubere Datei willst): `%APPDATA%\Factorio\script-output\arrakis-test.txt`. Der Prüfstand hängt nur an.
4. Danach die Einstellung wieder ausschalten, bevor du normal spielst.

## Befehle

Im Chat eingeben (nur Admins; im Einzelspiel bist du Admin):

| Befehl | Wirkung |
|---|---|
| `/arrakis-test` | Liste aller Tests mit Dauer, Hinweisen und letztem Ergebnis |
| `/arrakis-test T1` | Test T1 starten (ebenso `T2` … `T12`); ein laufender Test wird abgebrochen |
| `/arrakis-test alle` | alle nicht-interaktiven Tests nacheinander: T1–T7 (T7 nur Teil a), T11. Dauer etwa 10 min |
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
2. Deine Antworten auf alle FRAGE-Zeilen, mit Testnummer.
3. Die erbetenen Screenshots (T1, T5, T6, T9).

## „alle“

`/arrakis-test alle` startet T1, T2, T3, T4, T5, T6, T7 (Teil a) und T11 nacheinander, mit 1 s Abstand.
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

### T11 Kartengenerator (etwa 20 s)

**Was passiert:** Erzeugt auf Arrakis die Karte im Umkreis von 12 Chunks um (0, 0). **Das Spiel hängt dabei kurz.**
Danach werden Spicefelder gesucht und ihr Abstand zum Fels gemessen, dazu eine Tabelle für die Noise-Schwelle. Du bleibst, wo du bist.

**Du:** nichts. **Melden:** nur die Datei.

### T12 Flieger: Rettung aus der Kartenansicht (interaktiv, 3 min)

**Was passiert:** Neben dir steht ein Flieger mit Treibstoff. Ist deine Hand leer, bekommst du eine Spidertron-Fernbedienung; der Flieger ist damit ausgewählt.
Jeder Druck auf **ALT+O** schreibt eine MESSUNG-Zeile. Der Test endet nach 3 min oder mit `/arrakis-test stop`.

**Du, in drei Schritten:**
1. In den Flieger einsteigen (Enter), Karte öffnen (M), den Flieger aus der Karte steuern (WASD) und ALT+O drücken.
2. Aussteigen, die Fernbedienung in die Hand nehmen (ist sie weg: Verknüpfungsleiste unten rechts), damit auf den Flieger klicken, Karte öffnen (M) und ALT+O drücken.
3. Karte schließen und in der normalen Ansicht ALT+O drücken.

**Melden:** ob bei jedem Schritt eine MESSUNG-Zeile kam (die Datei reicht).

## Bekannte Grenzen

- Die Flieger-Beine drehen nicht mit der Flugrichtung. T1 fliegt nur nach Osten; die Werte für 1 und 2 Beine gelten für Ost-West-Flug.
- Der Tempo-Deckel in T2 läuft mit Raketentreibstoff. Fährt der Ernter ohne Deckel nicht schneller als 1,6 Kacheln/s, nimmt der Test einen Ersatzdeckel (70 % seines Höchsttempos), damit der Deckel überhaupt greifen muss.
- T6, Bahn D: Bewertet wird der Kopf bis zum Biss. Was der Wurm danach tut, steht als MESSUNG/INFO da (im Spiel taucht er beim Biss ab).
