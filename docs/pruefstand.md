# Prüfstand `/arrakis-test` – Anleitung für Max

Stand: Mod 0.5.3 · Factorio 2.1.23 mit Space Age

Der Prüfstand baut im Spiel Testaufbauten, misst selbst und schreibt die Ergebnisse in den Chat und in eine Datei.
Er klärt die offenen Fragen aus dem Design (`docs/design-ernter-ornithopter.md`, Abschnitt 8).
Du musst nur zuschauen, ein paar Fragen beantworten und am Ende die Dateien schicken.

## Vorbereitung

1. **Einstellung einschalten:** im Hauptmenü *Einstellungen → Mod-Einstellungen → Start* das Häkchen bei **Prüfstand** setzen und bestätigen. Factorio startet neu.
2. **Wegwerf-Spielstand:** ein neues Spiel mit Space Age starten (oder einen Spielstand, der kaputtgehen darf). Nie den echten Spielstand nehmen.
   Die Tests laufen auf einer eigenen Oberfläche `arrakis-testbench`, deine Basis bleibt unberührt. T11 legt kurz leere Testoberflächen `arrakis-t11-…` an und löscht sie wieder.
3. **Alte Ergebnisdatei löschen** (wenn du eine saubere Datei willst): `%APPDATA%\Factorio\script-output\arrakis-test.txt`. Der Prüfstand hängt nur an.
4. Danach die Einstellung wieder ausschalten, bevor du normal spielst.

## Factorio 2.1

Seit 0.5.1 läuft die Mod nur noch in Factorio 2.1 (ab 2.1.23). Fast alle bisherigen Messwerte stammen aus 2.0.77. Bitte in 2.1.23 neu laufen lassen:

- **T2 und T2b (Tempo):** 2.1.13 hat geändert, wie das Höchsttempo der Brennstoffe bei Autos wirkt: Es wirkt jetzt linear (Endtempo ∝ √(a · Ausgleich) · t, gemessen in 2.1.23). Seit 0.5.3 rechnet der Ausgleich ab 2.1.13 deshalb mit min(1, 1/(a · t²)), davor mit min(1, 1/a) (Modell aus T2 in 2.0.77). Der nächste T2b-Lauf soll das bestätigen.
- **T4 (Annahme und Tankstutzen):** Bauregel auf Fels und Proxy-Container; der Schaltungsanschluss des Proxys ist seit 2.1.21 anders aufgebaut.
- **T12 (Tasten):** 2.1 nimmt in Tasten nur noch dokumentierte Namen. `ALT+O` (T12) und `Umschalt+H` (Ernter) sollten gehen; bitte bestätigen.
- **T11 (Kartengenerator):** siehe dort.
- **T13** einmal ganz, als Gegenprobe für den Ernter-Code.

Von Hand prüfen (2.1.23):

- Spice-Wissenschaftspaket: Tooltip und Factoriopedia-Seite ohne „Unknown key“.
- Eine Raumplattform über Arrakis zeigt einen Planeten im Hintergrund (Platzhalter: Vulcanus).
- Arrakis-Fels hat eine eigene Factoriopedia-Seite.
- `/arrakis` aus der Karte oder der Fernsicht landet bei der Spielfigur auf Arrakis.
- Ein Spielstand mit 0.5.0 aus 2.0.77 lädt mit 0.5.1.

T10 (lädt 2.1 eine Mod für 2.0?) entfällt: Laut Factorio-Doku lädt 2.1 keine Mods mit `factorio_version "2.0"`.
In 2.1 lässt sich der Quality-Mod abschalten. Ohne Quality entfallen in T2b die drei legendären Läufe mit je einer INFO-Zeile; der Datenstufen-Test prüft vor der Übergabe auch diesen Fall (`tools/check/datastage.py fd2123 --ohne quality --set arrakis-testbench=true`).

## Befehle

Im Chat eingeben (nur Admins; im Einzelspiel bist du Admin).
Ohne Spieler gehen sie auch an der Serverkonsole und über RCON (außer `zurück`, T9 und T12), siehe [Automatisch ohne Spieler](#automatisch-ohne-spieler-server-und-rcon).

| Befehl | Wirkung |
|---|---|
| `/arrakis-test` | Liste aller Tests mit Dauer, Hinweisen und letztem Ergebnis |
| `/arrakis-test T1` | Test T1 starten (ebenso `T2` … `T13` und `T2b`, groß oder klein geschrieben); ein laufender Test wird abgebrochen |
| `/arrakis-test alle` | alle nicht-interaktiven Tests nacheinander: T1–T7 (T7 nur Teil a), T11, T13, T2b. Dauer etwa 13 min |
| `/arrakis-test stop` | laufenden Test bzw. „alle“ abbrechen |
| `/arrakis-test status` | Stand in festen Zeilen: bereit, läuft oder wartet, dazu das letzte Ergebnis je Test ([Format](#arrakis-test-status)) |
| `/arrakis-test zurück` | zurück an die Stelle, an der du vor dem Test warst |
| `/arrakis-test T7 ja` | T7 mit Teil b (kann das Spiel abstürzen lassen) |

Die meisten Tests bringen dich zum Zuschauen an den Testaufbau. Mit `/arrakis-test zurück` kommst du zurück.
Jeder Test hat ein Zeitlimit; danach meldet er „Zeitüberschreitung“ und räumt auf.

## Automatisch ohne Spieler (Server und RCON)

Ab 0.5.2 nimmt der Prüfstand Befehle auch ohne Spieler an: an der Konsole eines Factorio-Servers oder über RCON. Ein solcher Aufrufer gilt als Admin.
Die Antworten gehen dann an RCON und ins Log des Servers (`factorio-current.log`), nicht in den Chat; `status` antwortet nur über RCON, an der Konsole des Servers selbst also womöglich gar nicht. Die Testzeilen stehen wie immer in `script-output/arrakis-test.txt`.
Ein eigener Server braucht in `server-settings.json` `"auto_pause": false`, sonst steht er ohne Spieler still und kein Test kommt voran.
Am einfachsten macht das alles das Werkzeug [`tools/pc/pruefstand.py`](#werkzeug-toolspcpruefstandpy).

**Was ohne Spieler läuft:** alle nicht-interaktiven Tests, einzeln oder mit `alle`: T1 bis T7 (T7 Teil b nur mit `T7 ja`), T11, T13 und T2b.
T9 und T12 brauchen dich im Spiel und gehen nur von Hand. Ohne Spieler antwortet der Prüfstand `T9 braucht einen Spieler im Spiel (interaktiv).` und startet nichts; ein laufender Test läuft weiter. `alle` lässt beide wie immer aus.
`/arrakis-test zurück` gibt es nur für Spieler.
Weil niemand den Chat sieht, bestätigt der Prüfstand ohne Spieler kurz: `Gestartet: T13. Stand: /arrakis-test status`, `„alle“ gestartet: …` oder `Gestoppt.` Endet ein Test schon beim Start (etwa mit Skriptfehler), steht dort `T13 gleich beim Start beendet: …`.

**Was ohne Spieler anders ist:**

- FRAGE-Zeilen beantwortet niemand, sie bleiben offen. Fragen stellen T1, T2 (am Ende), T4 (am Ende), T5, T6 und T7 (nur mit `ja`). T3, T11, T13 und T2b fragen nichts. Die Antworten gibt es nur, wenn du den Test später im Spiel laufen lässt.
- `alle` wartet ohne Spieler nach einer FRAGE nicht (mit Spieler nach T2 und T4 je 30 s).
- Die Zusammenfassung von `alle` lässt den Hinweis auf `/arrakis-test zurück` weg.
- T2: Geht die Skriptfahrt nicht, setzt der Test sonst dich in den Ernter. Ohne Spieler entfällt das: FEHLER „Manuelle Messung entfällt: kein Spieler im Spiel“, dann wertet der Test gleich aus.
- T5, T6 und T7 schreiben eine INFO-Zeile „Kein Spieler gefunden; der Test läuft ohne Zuschauer“. Seit 0.5.3 laufen die fahrenden Testwürmer (T5 b, c, d, T6, T7 b) mit `minimum_activity_mode = full`. Factorio rechnet sie dann auch ohne Zuschauer so, als sähe jemand zu. Bis 0.5.2 standen T5 c, d und T6 Bahn A bis C auf `minimal`; im ersten Lauf ohne Spieler kam Bahn C vermutlich deshalb nicht an. Nur T5 a bleibt auf `minimal`, wie echte Würmer (Design 4.3): Ohne Spieler misst a also, wie weit ein unbeobachteter Wurm kommt. Mit Spieler ändert sich nichts, dort liefen die Würmer schon immer als `full`.
- Die Karte wird nicht aufgedeckt. In T13 Schritt 10 steht dann „Kartenmarkierungen entfernt 0“; das zählt nicht für OK oder FEHLER.

### `/arrakis-test status`

Geht im Chat und ohne Spieler. Die erste Zeile ist genau eine dieser drei:

```
STATUS bereit | Tick <n>
STATUS laeuft <id> +<s> s | Tick <n>
STATUS wartet <id> | Tick <n>
```

- `bereit`: Es läuft kein Test.
- `laeuft`: Test `<id>` läuft seit `<s>` Sekunden Spielzeit, mit einer Nachkommastelle (z. B. `+12.5 s`).
- `wartet`: bei `alle` zwischen zwei Tests. `<id>` kommt als Nächstes, nach 1 s (mit Spieler nach einer FRAGE von T2 oder T4 nach 30 s).
- Solange `alle` läuft, hängt an Zeile 1 noch ` | alle, danach noch <k>`. `<k>` zählt die Tests, die nach dem laufenden bzw. wartenden noch kommen.

Danach kommt je Test mit gespeichertem Ergebnis eine Zeile, in fester Reihenfolge (T1 bis T7, T9, T11, T12, T13, T2b):

```
ERGEBNIS <id> | Tick <tick> | OK <a> FEHLER <b> FRAGE <c> | <Zusammenfassung>
```

`<tick>` ist der Tick am Testende, `<a>`, `<b>` und `<c>` zählen die Zeilen dieser Art. Die Zusammenfassung ist die der ENDE-Zeile, ohne Zeilenumbrüche; sie kann selbst ` | ` enthalten.
Die Ergebnisse bleiben im Spielstand, auch die von früheren Läufen. `status` schreibt nichts ins Log, damit häufiges Abfragen es nicht füllt. Neu ist ein Ergebnis, wenn sein Tick nicht kleiner ist als der Tick der STATUS-Zeile vor dem Start. Ein Test, der schon beim Start endet (etwa mit Skriptfehler), kann denselben Tick haben.
Die Schlüsselwörter sind ASCII (`laeuft` ohne Umlaut), damit ein Programm sie sicher lesen kann.
Beispiel bei `alle`: `STATUS wartet T3 | Tick 11500 | alle, danach noch 7` (T3 kommt gleich, danach noch 7 Tests).

### Werkzeug `tools/pc/pruefstand.py`

Das Werkzeug richtet einen eigenen Factorio-Server ein, lässt die Tests ohne Spieler laufen und holt die Ergebnisse ab.
Es braucht nur Python 3 (ab 3.8) ohne Zusatzpakete und läuft unter Windows und Linux (unter Windows geht auch `py` statt `python`).
Aufruf im Repo-Ordner, zum Beispiel mit Factorio aus Steam:

```
python tools/pc/pruefstand.py --factorio "C:\Program Files (x86)\Steam\steamapps\common\Factorio\bin\x64\factorio.exe" T2b T13
```

Oder mit einer anderen Factorio-Kopie und allen Tests:

```
python tools/pc/pruefstand.py --factorio "<Factorio-Ordner>\bin\x64\factorio.exe" alle
```

| Angabe | Bedeutung |
|---|---|
| `--factorio PFAD` | Pflicht: `bin\x64\factorio.exe` einer Factorio-Installation ab 2.1.23 mit Space Age (daneben liegt `data\`) |
| `--ordner ORDNER` | Arbeitsordner, Standard `%TEMP%\arrakis-pruefstand` (Linux meist `/tmp/arrakis-pruefstand`) |
| `--mod ORDNER` | Mod-Ordner, Standard: dieses Repo |
| `--rcon-port N`, `--port N` | Ports auf 127.0.0.1, Standard 27115 (RCON) und 34297 (Spiel) |
| `--zeitlimit MIN` | Minuten je Test, Standard 30, bei `alle` 90 |
| `--startzeit SEK`, `--abfrage SEK` | Sekunden bis RCON antworten muss (180) und zwischen zwei Statusabfragen (5) |
| `TEST …` | Test-IDs wie `T2b T13`, oder `alle`. `T7:ja` schickt `/arrakis-test T7 ja`. T9 und T12 nicht angeben. |

**Was es tut:**

1. Eigener Arbeitsordner mit eigener `config.ini`: Factorio liest seine Daten aus der Installation und schreibt nur in diesen Ordner. Einen fremden Ordner, der nicht leer ist, nimmt es nicht.
2. Frische Kopie der Mod nach `mods\arrakis` (ohne `.git`), dazu `mod-list.json` mit den Vanilla-Mods und arrakis. In `mod-settings.dat` setzt es die Startup-Einstellung **Prüfstand**.
3. Frischer Spielstand (`factorio --create`).
4. Server nur auf 127.0.0.1 (Spiel-Port 34297, RCON-Port 27115), nicht öffentlich, mit Zufallspasswort für RCON und ohne Auto-Pause.
5. Je Test `/arrakis-test <id>`, dann alle 5 s `/arrakis-test status`, bis das neue ERGEBNIS da ist (bei `alle`: bis der Stand wieder `bereit` ist). Der Fortschritt steht in der Konsole. Steht der Tick während eines Tests länger als 90 s still, bricht es ab (Rückgabewert 2).
6. Am Ende `/quit`, auch nach einem Fehler oder Strg+C. Reagiert der Server nicht, beendet es ihn hart.
7. Es kopiert die Ergebnisdateien und zeigt alle ERGEBNIS-Zeilen.

Deine eigenen Spielstände, Einstellungen und Mods unter `%APPDATA%\Factorio` bleiben unberührt, auch die Einstellung **Prüfstand** in deinem Spiel. Die Factorio-Installation und die Mod im Repo liest es nur.
Nebenbei normal spielen geht: Der Server hat einen eigenen Ordner und eigene Ports.
Im selben Arbeitsordner läuft immer nur ein Lauf; ein zweiter bricht mit einem Hinweis ab (Sperrdatei `pruefstand.lock`).
`alle` dauert etwa 13 min (erster Lauf ohne Spieler, 0.5.2: 12 min). Wer das Werkzeug aus einem Programm mit kurzem Zeitlimit für Befehle startet (etwa einem Assistenten), startet es im Hintergrund mit der Ausgabe in eine Datei, verfolgt die Datei und liest am Ende den Rückgabewert. Beendet man das Werkzeug von außen (Strg+C, `kill`), stoppt es den Server noch. Wird es hart beendet (Task-Manager, `kill -9`), läuft der Server weiter, bis der nächste Lauf im selben Ordner ihn beendet.

**Ergebnisse:**

- `<Arbeitsordner>\ergebnisse\arrakis-test-<Datum>-<Uhrzeit>.txt` (z. B. `arrakis-test-20261024-153012.txt`), nach T11 auch `arrakis-t11-karten-<Datum>-<Uhrzeit>.txt`. Diese Dateien bitte schicken, dazu die Ausgabe des Werkzeugs.
- Ergebnisdateien eines früheren Laufs legt es vorher als `…-vorher-<Datum>-<Uhrzeit>.txt` dorthin, denn die Mod hängt nur an.
- Das Log des Servers steht in `<Arbeitsordner>\factorio-current.log`, die Ausgabe des Prozesses in `server.log`, das Anlegen des Spielstands in `create.log`. Unter Windows können `server.log` und `create.log` leer bleiben (factorio.exe hängt sich an die Konsole des Aufrufers); `factorio-current.log` gibt es immer, das Werkzeug zeigt dann dessen Ende.
- Solange der Server läuft, stehen Port und RCON-Passwort in `<Arbeitsordner>\server.json`. Damit lässt sich von Hand fragen: `python tools/pc/rcon.py --port 27115 --passwort <Passwort> arrakis-test status` (den `/` ergänzt das Werkzeug; in Git Bash würde aus `"/arrakis-test"` sonst ein Pfad).
  Bricht ein Lauf hart ab, beendet der nächste Lauf im selben Ordner den übrig gebliebenen Server. Reagiert der nicht auf `/quit`, bricht der neue Lauf mit dessen PID ab; dann den Server im Task-Manager beenden.

**Rückgabewert:**

| Wert | Bedeutung |
|---|---|
| 0 | kein FEHLER (offene FRAGEn zählen nicht) |
| 1 | mindestens ein FEHLER, oder ein Test lief ins Zeitlimit. Dann schickt das Werkzeug `/arrakis-test stop`, die übrigen Tests laufen nicht. |
| 2 | Einrichtung oder Infrastruktur: Factorio startet nicht, Spielstand oder RCON geht nicht, Prüfstand-Einstellung nicht aktiv, Server abgestürzt (etwa mit `T7:ja`) oder tickt nicht mehr, Ordner schon in Benutzung, Strg+C, ein Test wurde abgelehnt (T9, T12, unbekannte ID) oder endete ohne ERGEBNIS. 2 geht vor 1. |

Mit `T7:ja` trifft ein Absturz nur den Server, nicht dein Spiel; das Ende des Server-Logs steht dann in der Ausgabe.

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
Der Durchgang mit Tempo-Deckel (Rücksetzen alle 10 Ticks) ist nur noch Messung, ohne OK oder FEHLER. Seit 0.4.0 ist klar, dass das mit Raketentreibstoff nicht reicht. Deshalb deckelt der echte Ernter jeden Tick; T2b zählt, wie oft dieser Deckel eingreift. Eine INFO-Zeile sagt das.

**Falls die Skriptfahrt nicht geht:** Der Chat meldet FEHLER „Skriptfahrt geht nicht“ und setzt dich selbst in den Ernter.
Dann **W gedrückt halten, bis die Meldung „W loslassen“ kommt** (etwa 75 s). Aussteigen nur, wenn der Chat es sagt.

**Du am Ende:** den Ernter anklicken (Fenster öffnen) und versuchen, ihn abzubauen (Rechtsklick halten).

**Melden:** Steht „Prüfstand: aufgebaut“ im Fenster? Lässt er sich abbauen (sollte nicht)?

### T3 Ernter: Teleport zur Ablage (etwa 4 s)

**Was passiert:** Ein voll beladener Ernter (Qualität, Ladung, Treibstoff, Brennvorgang, 60 % Gesundheit, Farbe) wird auf eine versteckte Ablage-Oberfläche `arrakis-test-hold` teleportiert und zurück.
Zuerst steigt eine Puppe ein. Dabei übernimmt der Ernter ihre Farbe (Orange); das ist kein Fehler, eine INFO-Zeile nennt die Farbe vor und nach dem Einsteigen. Danach färbt der Test ihn wieder hellblau, damit auffällt, falls der Teleport die Farbe zurücksetzt. Verglichen wird mit dem Zustand danach, jedes Feld einzeln (22 OK-Zeilen, wenn alles erhalten bleibt). Die Gegenprobe mit `clone` (Teil c) steht nur als INFO da. Die Ablage bleibt im Spielstand und wird wiederverwendet.

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

**Was passiert:** Vier Würmer gleichzeitig auf vier Bahnen, jede mit einer Felsinsel: A ohne Schutz, B mit Fels-Kollisionsebene, C mit Fels-Wächter, D greift einen Ernter vor dem Fels an (Ziel per `investigating` auf den Ernter; `attacking` hält bei Fahrzeugen nicht, siehe T5 b).
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

In der Factorio-Version laufen lassen, in der gespielt wird (jetzt 2.1.23). 2.1.7 hat Voronoi-Rauschen mit hohem jitter korrigiert; c3-Werte aus 2.0.77 gelten dort nicht sicher.

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

### T2b Ernter: Fahrphysik (knapp 5 min)

**Was passiert:** Zwei Spice-Ernter mit je einer Puppe am Steuer fahren 20 Läufe zu je 10 oder 15 s (vor 2.1.13: 17). Der echte (eingetragene) fährt 13 davon:
mit Kohle, Festbrennstoff, Raketentreibstoff, Atomtreibstoff und legendärem Raketentreibstoff (alle mit Tempo-Ausgleich), nach Westen, Norden, Süden und zweimal schräg, zweimal bei negativen Koordinaten (um −1000, −1000) und einmal mit vollem Laderaum.
Ein zweiter Ernter, den der Mod absichtlich nicht kennt, fährt mit Raketentreibstoff ohne Ausgleich und ohne Deckel; er wird nur gemessen.
Ab 2.1.13 wirkt das Höchsttempo t der Brennstoffe auch bei Autos, und zwar linear. Der Ausgleich ist dort min(1, 1/(a · t²)), davor min(1, 1/a); die Läufe mit dem eingetragenen Ernter erwarten die Formel der laufenden Version (die Start-INFO nennt sie und die base-Version).
Der zweite Ernter fährt dazu ohne Deckel, den Ausgleich setzt der Test: dreimal „mit altem Ausgleich 1/a“ (Festbrennstoff, Raketentreibstoff, legendärer Raketentreibstoff) und ab 2.1.13 dreimal „mit neuem Ausgleich 1/(a · t²)“ mit denselben Brennstoffen. Vor 2.1.13 entfallen die drei neuen Läufe, denn dort ist der neue Ausgleich gleich dem alten.
Die MESSUNG-Zeilen dieser Läufe nennen a, t, Tempo im Verhältnis zu Kohle, einen „Faktor“ (Tempo/Kohle geteilt durch das, was das 2.0-Modell ohne t erwartet) und den Exponenten p (Faktor = t^p).
Am Ende fassen zwei INFO-Zeilen zusammen. Die erste zeigt, wie t wirkt (Faktor 1.000 bzw. p = 0 heißt keine Wirkung, Faktor ≈ t bzw. p = 1 heißt linear). Die zweite zeigt, ob der neue Ausgleich das Tempo ohne Deckel unter 1,5 Kacheln/s hält („hält ohne Deckel“ / „hält NICHT ohne Deckel“), die größte Abweichung von Tempo/Kohle = 1,000 in Prozent und ab 1 % Abweichung die Formel, die zu den Messungen passen würde (min(1, 1/(a · t^(2p)))); vor 2.1.13 sagt sie nur, dass der neue Ausgleich dort gleich dem alten ist. Griff der Deckel schon im Lauf mit Kohle ein, warnt eine weitere INFO-Zeile: Dann sind Tempo/Kohle, Faktor und p zu hoch.
Die ENDE-Zeile nennt zusätzlich den Bereich von p und das höchste Tempo mit neuem Ausgleich ohne Deckel.
Je Lauf stehen Tempo (`speed`), Spitze, Bodentempo (zurückgelegte Strecke ab 5 s) und der Ausgleichswert `effectivity_modifier` in der Zeile.
FEHLER heißt (ab der ersten Sekunde eines Laufs): Spitze über 1,5 Kacheln/s, der Tempo-Deckel des Mods musste eingreifen (dann war das Tempo vor dem Deckel über 1,5), Bodentempo über 1,5 oder Ausgleich nicht wie erwartet (min(1, 1/(a · t²)) ab 2.1.13, sonst min(1, 1/a)). Dazu gegen zu viel Ausgleich: Festbrennstoff, Raketen- und Atomtreibstoff (je 15 s wie Kohle) müssen im Mittel mindestens 97 % des Tempos mit Kohle fahren. Ohne Qualität im Spiel entfallen die legendären Läufe (drei, vor 2.1.13 zwei) mit je einer INFO-Zeile.
Am Ende entfernt der Test beide Ernter.

**Du:** nichts, zuschauen (die Ernter fahren an dir vorbei). **Melden:** nur die Datei.

## Bekannte Grenzen

- Die Flieger-Beine drehen nicht mit der Flugrichtung. T1 fliegt nur nach Osten; die Werte für 1 und 2 Beine gelten für Ost-West-Flug.
- Der Tempo-Deckel in T2 läuft mit Raketentreibstoff. Fährt der Ernter ohne Deckel nicht schneller als 1,6 Kacheln/s, nimmt der Test einen Ersatzdeckel (70 % seines Höchsttempos), damit der Deckel überhaupt greifen muss. Der Durchgang zählt nicht für OK oder FEHLER (siehe T2).
- T6, Bahn D: Bewertet wird der Kopf bis zum Biss. Was der Wurm danach tut, steht als MESSUNG/INFO da (im Spiel taucht er beim Biss ab).
- Im normalen Spiel erntet der Ernter nur auf Arrakis. Die Prüfstand-Fläche gibt dieselbe Einstellung **Prüfstand** frei, die auch den Befehl bringt; nur deshalb kann T13 dort mit dem echten Code ernten.
- T13, Schritt 11: Bewegt sich auch das normale Auto auf dem Band nicht, sagt die Messung nichts; dann meldet der Schritt FEHLER „nicht prüfbar“. Bitte trotzdem die Datei schicken.
- T2b liest das Tempo im Prüfstand-Takt, nach dem Tempo-Deckel des Mods. Deshalb zählt jeder Lauf, wie oft der Deckel eingegriffen hat („Deckel n× (ab 1 s m×)“); in der ersten Sekunde ist das nach einem Brennstoffwechsel erlaubt, danach ist es ein FEHLER. Die INFO-Zeile am Ende fasst das zusammen. Die echte Fahrt zeigt in jedem Fall das Bodentempo.
