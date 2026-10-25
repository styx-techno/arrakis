# Prüfstand `/arrakis-test` – Anleitung für Max

Stand: Mod 0.6.0 · Factorio 2.1.23 mit Space Age

Der Prüfstand baut im Spiel Testaufbauten, misst selbst und schreibt die Ergebnisse in den Chat und in eine Datei.
Er klärt die offenen Fragen aus dem Design (`docs/design-ernter-ornithopter.md`, Abschnitt 8) und ab 0.6.0 die Engine-Annahmen des Ornithopters (`docs/plan-3c.md`, Abschnitt 4.16).
Du musst nur zuschauen, ein paar Fragen beantworten und am Ende die Dateien schicken.

## Vorbereitung

1. **Einstellung einschalten:** im Hauptmenü *Einstellungen → Mod-Einstellungen → Start* das Häkchen bei **Prüfstand** setzen und bestätigen. Factorio startet neu.
2. **Wegwerf-Spielstand:** ein neues Spiel mit Space Age starten (oder einen Spielstand, der kaputtgehen darf). Nie den echten Spielstand nehmen.
   Die Tests laufen auf einer eigenen Oberfläche `arrakis-testbench`, deine Basis bleibt unberührt. T11 legt kurz leere Testoberflächen `arrakis-t11-…` an und löscht sie wieder. T14 erzeugt die Karte von Arrakis nacheinander auf Testoberflächen `arrakis-t14-…` und löscht auch diese wieder; die Oberfläche Arrakis selbst fasst er nicht an.
   T15 benutzt die echte Ablage `arrakis-hold`, setzt am Ende alle getragenen Ernter ab und löscht sie. Das trifft auch Ernter, die ein Ornithopter deines Spielstands gerade trägt: Sie stehen danach am Boden bei ihrem Ornithopter. T16 hebt ebenfalls echte Ernter auf diese Ablage und entfernt am Ende seine eigenen.
3. **Alte Ergebnisdatei löschen** (wenn du eine saubere Datei willst): `%APPDATA%\Factorio\script-output\arrakis-test.txt`. Der Prüfstand hängt nur an.
4. Danach die Einstellung wieder ausschalten, bevor du normal spielst.

## Factorio 2.1

Seit 0.5.1 läuft die Mod nur noch in Factorio 2.1 (ab 2.1.23). Fast alle bisherigen Messwerte stammen aus 2.0.77. Bitte in 2.1.23 neu laufen lassen:

- **T2 und T2b (Tempo):** 2.1.13 hat geändert, wie das Höchsttempo der Brennstoffe bei Autos wirkt: Es wirkt jetzt linear (Endtempo ∝ √(a · Ausgleich) · t, gemessen in 2.1.23). Seit 0.5.3 rechnet der Ausgleich ab 2.1.13 deshalb mit min(1, 1/(a · t²)), davor mit min(1, 1/a) (Modell aus T2 in 2.0.77). Bestätigt am 25.10.2026 mit 0.5.3: In T2b fuhren alle 13 Läufe des echten Ernters speed 1,453 wie Kohle, ab 1 s griff der Deckel nie ein.
- **T4 (Annahme und Tankstutzen):** Bauregel auf Fels und Proxy-Container; der Schaltungsanschluss des Proxys ist seit 2.1.21 anders aufgebaut.
- **T12 (Tasten):** 2.1 nimmt in Tasten nur noch dokumentierte Namen. `ALT+O` (T12) und `Umschalt+H` (Ernter) sollten gehen; bitte bestätigen. `Umschalt+C` (Ornithopter, ab 0.6.0) prüft T17.
- **T11 und T14 (Kartengenerator 0.5.4, Spicefelder 0.5.5):** Die neue Karte ist gebaut, aber noch nicht im Spiel abgenommen. T11 entscheidet über die Spice-Regel (B oder A), T14 prüft die erzeugte Karte auf Kacheln. Beide zusammen laufen lassen, etwa mit `python tools/pc/pruefstand.py --factorio … T11 T14`; siehe dort. T14 lief mit 0.5.4 auf 9 Seeds ohne FEHLER, fand aber im Mittel nur 0,9 reguläre Felder je Seed (5 Seeds ohne, Median 134 Kacheln). 0.5.5 macht die Felder dichter und größer, T14 prüft jetzt auch Zahl und Größe („Felder“, „Feldgröße“); bitte mit 0.5.5 noch einmal laufen lassen.
- **T13** einmal ganz, als Gegenprobe für den Ernter-Code.
- **T15, T16 und T17 (Ornithopter, neu in 0.6.0):** T15 und T16 ohne Spieler laufen lassen, etwa mit `python tools/pc/pruefstand.py --factorio … T15 T16` (beide sollen ohne FEHLER enden), T17 mit dir im Spiel. Sie entscheiden die noch ungeprüften Engine-Annahmen U1 bis U28 aus `docs/plan-3c.md`, Abschnitt 4.16; in eckigen Klammern steht bei jedem Schritt, welche er klärt. Was dazu von Hand zu prüfen ist, steht dort in Abschnitt 8.

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
Ohne Spieler gehen sie auch an der Serverkonsole und über RCON (außer `zurück`, T9, T12 und T17), siehe [Automatisch ohne Spieler](#automatisch-ohne-spieler-server-und-rcon).

| Befehl | Wirkung |
|---|---|
| `/arrakis-test` | Liste aller Tests mit Dauer, Hinweisen und letztem Ergebnis |
| `/arrakis-test T1` | Test T1 starten (ebenso `T2` … `T17` und `T2b`, groß oder klein geschrieben); ein laufender Test wird abgebrochen |
| `/arrakis-test T11 lang`, `/arrakis-test T14 lang` | T11 bzw. T14 mit 30 statt 9 Seeds |
| `/arrakis-test alle` | alle nicht-interaktiven Tests nacheinander: T1–T7 (T7 nur Teil a), T11, T13, T2b, T14, T15, T16. Dauer ohne Zeitraffer geschätzt gut 16 min ([„alle“](#alle)) |
| `/arrakis-test stop` | laufenden Test bzw. „alle“ abbrechen |
| `/arrakis-test status` | Stand in festen Zeilen: bereit, läuft oder wartet, dazu das letzte Ergebnis je Test ([Format](#arrakis-test-status)) |
| `/arrakis-test tempo 10` | Zeitraffer: das Spiel läuft bis zu 10-mal so schnell (`game.speed`, Zahlen von 1 bis 50); `tempo` ohne Zahl zeigt den Stand, `tempo 1` stellt auf echte Zeit zurück. Die Ergebnisse ändern sich nicht ([Zeitraffer](#zeitraffer-arrakis-test-tempo)) |
| `/arrakis-test zurück` | zurück an die Stelle, an der du vor dem Test warst |
| `/arrakis-test T7 ja` | T7 mit Teil b (kann das Spiel abstürzen lassen) |

Die meisten Tests bringen dich zum Zuschauen an den Testaufbau. Mit `/arrakis-test zurück` kommst du zurück.
Jeder Test hat ein Zeitlimit; danach meldet er „Zeitüberschreitung“ und räumt auf.

## Automatisch ohne Spieler (Server und RCON)

Ab 0.5.2 nimmt der Prüfstand Befehle auch ohne Spieler an: an der Konsole eines Factorio-Servers oder über RCON. Ein solcher Aufrufer gilt als Admin.
Die Antworten gehen dann an RCON und ins Log des Servers (`factorio-current.log`), nicht in den Chat; `status` antwortet nur über RCON, an der Konsole des Servers selbst also womöglich gar nicht. Die Testzeilen stehen wie immer in `script-output/arrakis-test.txt`.
Ein eigener Server braucht in `server-settings.json` `"auto_pause": false`, sonst steht er ohne Spieler still und kein Test kommt voran.
Am einfachsten macht das alles das Werkzeug [`tools/pc/pruefstand.py`](#werkzeug-toolspcpruefstandpy).

**Was ohne Spieler läuft:** alle nicht-interaktiven Tests, einzeln oder mit `alle`: T1 bis T7 (T7 Teil b nur mit `T7 ja`), T11, T13, T2b, T14, T15 und T16.
T9, T12 und T17 brauchen dich im Spiel und gehen nur von Hand. Ohne Spieler antwortet der Prüfstand `T9 braucht einen Spieler im Spiel (interaktiv).` und startet nichts; ein laufender Test läuft weiter. `alle` lässt sie wie immer aus.
`/arrakis-test zurück` gibt es nur für Spieler.
Weil niemand den Chat sieht, bestätigt der Prüfstand ohne Spieler kurz: `Gestartet: T13. Stand: /arrakis-test status`, `„alle“ gestartet: …` oder `Gestoppt.` Endet ein Test schon beim Start (etwa mit Skriptfehler), steht dort `T13 gleich beim Start beendet: …`.

**Was ohne Spieler anders ist:**

- FRAGE-Zeilen beantwortet niemand, sie bleiben offen. Fragen stellen T1, T2 (am Ende), T4 (am Ende), T5, T6 und T7 (nur mit `ja`). T3, T11, T13, T2b, T14, T15 und T16 fragen nichts. Die Antworten gibt es nur, wenn du den Test später im Spiel laufen lässt.
- `alle` wartet ohne Spieler nach einer FRAGE nicht (mit Spieler nach T2 und T4 je 30 s).
- Die Zusammenfassung von `alle` lässt den Hinweis auf `/arrakis-test zurück` weg.
- T2: Geht die Skriptfahrt nicht, setzt der Test sonst dich in den Ernter. Ohne Spieler entfällt das: FEHLER „Manuelle Messung entfällt: kein Spieler im Spiel“, dann wertet der Test gleich aus.
- T5, T6 und T7 schreiben eine INFO-Zeile „Kein Spieler gefunden; der Test läuft ohne Zuschauer“. Seit 0.5.3 laufen die fahrenden Testwürmer (T5 b, c, d, T6, T7 b) mit `minimum_activity_mode = full`. Factorio rechnet sie dann auch ohne Zuschauer so, als sähe jemand zu. Bis 0.5.2 standen T5 c, d und T6 Bahn A bis C auf `minimal`. Messbar geändert hat die Umstellung nichts: Die Würmer fuhren schon vorher full, und Bahn C kam auch im ersten Lauf ohne Spieler an (0.5.2: nach 64,2 s; die Begründung im Changelog zu 0.5.3 stimmte nicht). Nur T5 a bleibt auf `minimal`, wie echte Würmer (Design 4.3). Den Modus minimal misst a damit aber nicht: Im Zustand `investigating` hält die Engine den Wurm auch ohne Zuschauer auf full (0.5.3 unter 2.1.23: full bis zur Ankunft, minimal erst etwa 4 s nach dem Wechsel zu `patrolling`). a zeigt also den ungedrosselten Anmarsch. Mit Spieler ändert sich nichts, dort liefen die Würmer schon immer als `full`.
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
- `wartet`: bei `alle` zwischen zwei Tests. `<id>` kommt als Nächstes, nach 1 s Spielzeit (mit Spieler nach einer FRAGE von T2 oder T4 nach 30 s in echter Zeit, auch mit [Zeitraffer](#zeitraffer-arrakis-test-tempo)).
- Solange `alle` läuft, hängt an Zeile 1 noch ` | alle, danach noch <k>`. `<k>` zählt die Tests, die nach dem laufenden bzw. wartenden noch kommen.

Danach kommt je Test mit gespeichertem Ergebnis eine Zeile, in fester Reihenfolge (T1 bis T7, T9, T11, T12, T13, T2b, T14, T15, T16, T17):

```
ERGEBNIS <id> | Tick <tick> | OK <a> FEHLER <b> FRAGE <c> | <Zusammenfassung>
```

`<tick>` ist der Tick am Testende, `<a>`, `<b>` und `<c>` zählen die Zeilen dieser Art. Die Zusammenfassung ist die der ENDE-Zeile, ohne Zeilenumbrüche; sie kann selbst ` | ` enthalten.
Die Ergebnisse bleiben im Spielstand, auch die von früheren Läufen. `status` schreibt nichts ins Log, damit häufiges Abfragen es nicht füllt. Neu ist ein Ergebnis, wenn sein Tick nicht kleiner ist als der Tick der STATUS-Zeile vor dem Start. Ein Test, der schon beim Start endet (etwa mit Skriptfehler), kann denselben Tick haben.
Die Schlüsselwörter sind ASCII (`laeuft` ohne Umlaut), damit ein Programm sie sicher lesen kann.
Beispiel bei `alle`: `STATUS wartet T3 | Tick 11500 | alle, danach noch 7` (T3 kommt gleich, danach noch 7 Tests).

### Zeitraffer (`/arrakis-test tempo`)

Ab 0.5.5. `/arrakis-test tempo 10` setzt `game.speed` auf 10: Das Spiel rechnet dann bis zu 10-mal so viele Ticks je Sekunde (600 statt 60), soweit der Rechner mitkommt.
Erlaubt sind Zahlen von 1 bis 50, auch mit Nachkommastellen (`2.5` oder `2,5`). `/arrakis-test tempo` ohne Zahl zeigt den Stand, `/arrakis-test tempo 1` stellt auf echte Zeit zurück.
Es gelten dieselben Rechte wie für die anderen Befehle (nur Admins; Serverkonsole und RCON gelten als Admin). Den Befehl gibt es wie alle anderen nur mit der Einstellung **Prüfstand**. Ein laufender Test läuft einfach weiter.

Die Antwort ist eine feste ASCII-Zeile, damit ein Programm sie lesen kann:

```
TEMPO <neu> | vorher <alt>
TEMPO <jetzt>
```

Die zweite Form kommt ohne Zahl. Die Werte stehen wie `game.speed` selbst, mit Dezimalpunkt (`TEMPO 2.5 | vorher 1`). Eine falsche Eingabe (`tempo 0`, `tempo 51`, `tempo abc`) ändert nichts; die Antwort beginnt dann mit `Zeitraffer:` statt `TEMPO` und nennt den Stand.
Jeder Test schreibt am Anfang eine INFO-Zeile `Zeitraffer: game.speed 10`, bei 1 `Zeitraffer: game.speed 1 (aus)`. Ändert sich das Tempo mitten im Test, steht dort `Zeitraffer geändert: game.speed 2 (vorher 10)`. So lässt sich jedes Ergebnis einem Tempo zuordnen. Die STATUS- und ERGEBNIS-Zeilen bleiben, wie sie sind.

**Die Ergebnisse hängen nicht vom Tempo ab:** Alle Tests zählen Ticks, und ein Tick rechnet bei jedem Tempo dasselbe. Wartezeiten und Messdauern in den Tests, ihre Zeitlimits, die Pause von 1 s zwischen den Tests bei `alle` und alle Sekundenangaben in Chat und Datei (`+12.5s`, ENDE-Zeile, Zusammenfassung von `alle`, STATUS) sind Spielzeit aus dem Tick.
Durchgesehen für 0.5.5, wo echte Zeit eine Rolle spielt:

- **T14, Dauer der Chunk-Erzeugung:** die einzige Messung in echter Zeit. Ihr Profiler läuft nur, während Factorio im selben Tick die Chunks erzeugt (`force_generate_chunk_requests`), nie zwischen zwei Ticks. Die Dauer ist also reine Rechenzeit und mit und ohne Zeitraffer vergleichbar. T11 misst keine Zeit.
- **Pause für die FRAGE nach T2 und T4 bei `alle`** (nur mit Spieler): Das ist Zeit für dich, sie gilt deshalb in echter Zeit. Bei Tempo 10 sind es weiter 30 s, also 18 000 Ticks statt 1800. Änderst du das Tempo während der Pause, rechnet der Prüfstand die restlichen Ticks um; die restliche Zeit bleibt dieselbe. Ohne Spieler gibt es diese Pause nicht.
- **Was du im Spiel tust, läuft mit:** Zuschauen (T1, T5, T6), die Fahrt von Hand in T2 („W gedrückt halten“, bei Tempo 10 etwa 7,5 s statt 75 s) und die interaktiven Tests T9, T12 und T17 (T12 endet nach 3 min Spielzeit, bei Tempo 10 also nach 18 s; T17 nach 6 min, also nach 36 s). Wer zuschauen, FRAGEn während des Tests beantworten oder etwas von Hand prüfen will, lässt das Tempo auf 1.

**Im eigenen Spielstand:** `game.speed` bleibt im Spielstand; sonst speichert der Befehl nichts. Zurück geht es mit `/arrakis-test tempo 1`, und zwar bevor du die Einstellung **Prüfstand** ausschaltest. Danach gibt es den Befehl nicht mehr; zurückstellen ginge dann nur noch mit `/c game.speed = 1`, und `/c` schaltet in diesem Spielstand die Errungenschaften ab.
Solange das Tempo nicht 1 ist, erinnern die Liste (`/arrakis-test`) und, wenn du `alle` gestartet hast, auch dessen Zusammenfassung daran.
`tools/pc/pruefstand.py` stellt das Tempo selbst ein (Standard 10, `--tempo`); sein Server ist nach dem Lauf ohnehin weg.

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
| `--zeitlimit MIN` | Minuten je Test in echter Zeit, Standard 30, bei `alle` 90 |
| `--startzeit SEK`, `--abfrage SEK` | Sekunden bis RCON antworten muss (180) und zwischen zwei Statusabfragen (5) |
| `--tempo N` | [Zeitraffer](#zeitraffer-arrakis-test-tempo) während der Tests, 1 bis 50, Standard 10. `--tempo 1` läuft in echter Zeit wie vor 0.5.5 und geht als Einziges auch mit einer älteren Mod |
| `TEST …` | Test-IDs wie `T2b T13`, oder `alle`. `T7:ja` schickt `/arrakis-test T7 ja`, ebenso `T11:lang` und `T14:lang`. T9, T12 und T17 nicht angeben. |

**Was es tut:**

1. Eigener Arbeitsordner mit eigener `config.ini`: Factorio liest seine Daten aus der Installation und schreibt nur in diesen Ordner. Einen fremden Ordner, der nicht leer ist, nimmt es nicht.
2. Frische Kopie der Mod nach `mods\arrakis` (ohne `.git`), dazu `mod-list.json` mit den Vanilla-Mods und arrakis. In `mod-settings.dat` setzt es die Startup-Einstellung **Prüfstand**.
3. Frischer Spielstand (`factorio --create`).
4. Server nur auf 127.0.0.1 (Spiel-Port 34297, RCON-Port 27115), nicht öffentlich, mit Zufallspasswort für RCON und ohne Auto-Pause.
5. Sobald der Server über RCON antwortet, vor dem ersten Test: `/arrakis-test tempo 10` (bzw. der Wert von `--tempo`). Es prüft die Antwort und zeigt das Tempo in einer eigenen Zeile, etwa `Zeitraffer: game.speed 10 (vorher 1)`. Kennt die Mod den Befehl nicht (vor 0.5.5), bricht es ab (Rückgabewert 2), außer mit `--tempo 1`.
6. Je Test `/arrakis-test <id>`, dann alle 5 s `/arrakis-test status`, bis das neue ERGEBNIS da ist (bei `alle`: bis der Stand wieder `bereit` ist). Der Fortschritt steht in der Konsole. Steht der Tick während eines Tests länger als 90 s still, bricht es ab (Rückgabewert 2).
7. Am Ende `/quit`, auch nach einem Fehler oder Strg+C. Reagiert der Server nicht, beendet es ihn hart.
8. Es kopiert die Ergebnisdateien und zeigt alle ERGEBNIS-Zeilen.

Deine eigenen Spielstände, Einstellungen und Mods unter `%APPDATA%\Factorio` bleiben unberührt, auch die Einstellung **Prüfstand** in deinem Spiel. Die Factorio-Installation und die Mod im Repo liest es nur.
Nebenbei normal spielen geht: Der Server hat einen eigenen Ordner und eigene Ports.
Im selben Arbeitsordner läuft immer nur ein Lauf; ein zweiter bricht mit einem Hinweis ab (Sperrdatei `pruefstand.lock`).
Alle Zeitangaben des Werkzeugs (`--zeitlimit`, `--startzeit`, `--abfrage`, die 90 s Stillstand) sind echte Zeit. Mit Zeitraffer gelten sie unverändert, die Tests enden nur früher; eine Mindestdauer setzt das Werkzeug nicht voraus.
`alle` dauert ohne Zeitraffer gut 12 min, mit dem Standard `--tempo 10` geschätzt etwa 2 min ([„alle“](#alle)). Wer das Werkzeug aus einem Programm mit kurzem Zeitlimit für Befehle startet (etwa einem Assistenten), startet es im Hintergrund mit der Ausgabe in eine Datei, verfolgt die Datei und liest am Ende den Rückgabewert. Beendet man das Werkzeug von außen (Strg+C, `kill`), stoppt es den Server noch. Wird es hart beendet (Task-Manager, `kill -9`), läuft der Server weiter, bis der nächste Lauf im selben Ordner ihn beendet.

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
| 2 | Einrichtung oder Infrastruktur: Factorio startet nicht, Spielstand oder RCON geht nicht, Prüfstand-Einstellung nicht aktiv, Zeitraffer geht nicht (Mod vor 0.5.5 und `--tempo` nicht 1), Server abgestürzt (etwa mit `T7:ja`) oder tickt nicht mehr, Ordner schon in Benutzung, Strg+C, ein Test wurde abgelehnt (T9, T12, T17, unbekannte ID) oder endete ohne ERGEBNIS. 2 geht vor 1. |

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
3. Die erbetenen Screenshots (T1, T5, T6, T9, T17).

## „alle“

`/arrakis-test alle` startet T1, T2, T3, T4, T5, T6, T7 (Teil a), T11, T13, T2b, T14, T15 und T16 nacheinander, mit 1 s Abstand.
Nach T2 und T4 wartet er 30 s, damit du deren FRAGE vor Ort beantworten kannst; der Chat sagt das an. Die 30 s gelten in echter Zeit, auch mit [Zeitraffer](#zeitraffer-arrakis-test-tempo).
Die FRAGEn von T1, T5 und T6 gelten während des Tests: einfach zuschauen.
Am Ende kommt eine Zusammenfassung mit allen offenen FRAGEn. Was du verpasst hast, wiederholst du einzeln (z. B. `/arrakis-test T2`).
T9, T12 und T17 brauchen dich und laufen nur einzeln.

**Dauer ohne Zeitraffer: geschätzt gut 16 min, mit Tempo 10 geschätzt etwa 2,5 min.**
- Gemessen mit 0.5.4 ohne Spieler: 44 352 Ticks (739,2 s Spielzeit), in echter Zeit 12,3 min bei 60 Ticks je Sekunde. Die größten Teile in echter Zeit: T2b 4,6 min, T13 und T5 je 1,7 min, T4 1,2 min, T2 und T6 je 1,1 min, alle übrigen unter 30 s. Die Simulation braucht dabei nur etwa 0,1 ms je Tick, das Spiel wartet fast die ganze Zeit auf den nächsten Tick. (0.5.3: 724,7 s Spielzeit; in 0.5.4 kamen T14 und das längere T11 dazu.)
- Mit 0.6.0 kommen T15 (etwa 3 min Spielzeit) und T16 (etwa 45 s) dazu, mit den Pausen gut 13 600 Ticks. Zusammen sind das geschätzt etwa 58 000 Ticks, gut 16 min ohne Zeitraffer. Gemessen ist das noch nicht.
- Die Spielzeit hängt nur an der Zahl der Ticks, auch bei T11 und T14, nicht an der Rechenlast.
- Mit [Zeitraffer](#zeitraffer-arrakis-test-tempo) (`/arrakis-test tempo 10`, Standard von `tools/pc/pruefstand.py`) rechnet das Spiel bis zu 600 Ticks je Sekunde: Für die 44 352 Ticks von 0.5.4 sind das gut 1 min, mit T15 und T16 etwa 1,6 min; dazu kommt, was T11 und T14 je Tick länger rechnen (T14 erzeugt rund 6600 Chunks). Daher geschätzt etwa 2,5 min; gemessen ist das noch nicht. Die Ergebnisse bleiben dieselben.

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
Zuerst steigt eine Puppe ein. Ein Auto übernimmt beim Einsteigen die Farbe seines Fahrers und behält sie nach dem Aussteigen; solange jemand am Steuer sitzt, lässt sich seine Farbe per Skript nicht setzen (0.5.3 unter 2.1.23). Bis 0.5.3 war der Bezug deshalb Standard-Orange, und ein Teleport, der die Farbe auf Standard zurücksetzt, fiel nicht auf.
Seit 0.5.4 färbt der Test die Puppe vor dem Einsteigen mit einer eigenen Testfarbe (0.60/0.20/0.80/0.50, weder Standard-Orange noch die Farbe vom Aufbau). Eine INFO-Zeile nennt die Farbe vom Aufbau, die der Puppe und die des Autos mit Puppe am Steuer und sagt, woher diese kommt. Ließ sich die Puppe nicht färben und ist die Vorher-Farbe deshalb die Standardfarbe, sagt das eine eigene INFO-Zeile; dann tragen alle Farbzeilen und die ENDE-Zeile den Zusatz „nicht aussagekräftig (Standardfarbe)“ (gezählt werden sie trotzdem).
Verglichen wird mit dem Zustand mit Puppe am Steuer, jedes Feld einzeln (22 OK-Zeilen, wenn alles erhalten bleibt). Die Gegenprobe mit `clone` (Teil c) steht nur als INFO da. Die Ablage bleibt im Spielstand und wird wiederverwendet.

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
Bahn a fährt mit `minimum_activity_mode = minimal` wie echte Würmer. Welchen Modus der Wurm fährt, wählt aber die Engine: Im Zustand `investigating` war es in 0.5.3 auch ohne Zuschauer full, minimal kam erst etwa 4 s nach dem Wechsel zu `patrolling`. a misst also den ungedrosselten Anmarsch. Die MESSUNG-Zeile zählt `activity_mode` deshalb insgesamt und je Zustand.

**Du:** herauszoomen und zuschauen, ein Screenshot.

**Melden:** Ziehen die Würmer Ascheschwaden oder dunkle Spuren hinter sich her (sollten fehlen)? Sind sie sandfarben?

### T6 Fels-Ebene und Wächter (etwa 65 s, höchstens 110 s)

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

### T11 Kartengenerator: Rauschwerte im Seed-Vergleich (etwa 6 s Spielzeit, mit `lang` etwa 20 s)

**Was passiert:** T11 rechnet auf dem Seed deines Spielstands und acht festen Seeds (mit `/arrakis-test T11 lang` 30 Seeds) die Rauschwerte des Kartengenerators auf einem 8-Kachel-Raster aus, je 1600 × 1600 Kacheln.
Es wird keine Karte erzeugt: Für jeden Seed entsteht kurz eine leere Testoberfläche, T11 liest dort nur die Rauschwerte und löscht sie wieder. **Das Spiel ruckelt dabei**; wie lange in echter Zeit, ist mit 0.5.4 noch nicht gemessen (mit `lang` etwa dreimal so lange, weil es 30 statt 9 Seeds sind). Du bleibst, wo du bist.
Die Spielzeit im Titel hängt nur an der Zahl der Ticks: je Seed 40 (1 zum Anlegen, 7 für die Rauschwerte, je Rauschen einer für die Werteverteilung, also 15, und je Variante einer, also 17). Das sind 6,0 s für 9 Seeds und 20 s für 30. 0.5.3 hatte 8 Rauschwerte und 15 Varianten, also 31 Ticks je Seed, und brauchte gemessen 4,7 s.

Verglichen werden 17 Varianten:
- `live`: die Karte von 0.5.4 (`arrakis_v2_rock`: Kegel-Inseln c4 mit Startinsel und Graben). Im Kartenbild steht `o` hier für die Spicezone nach Regel B.
- `alt`: die Karte von 0.4.0 bis 0.5.3 (`arrakis_rock`), zum Vergleich.
- c1 bis c4: die Kandidaten aus 0.4.1 (c1 und c2 mit 15 bis 30 % Fels, c3 und c4 mit je drei Felsschwellen). Aus dem Lauf vom 25.10.2026 wurde c4 mit Felsschwelle 0 die Karte 0.5.4.
- `c4v2`: der Kegel der Karte 0.5.4 (`arrakis_v2_c4`, Verzerrung auf ±25 Kacheln je Achse begrenzt) ohne Startinsel und Graben, Felsschwelle 0.

Gemessen werden je Variante Felsanteil, Inseln, Abstand des Sands zum Fels und die Schwelle t100, ab der Spice mindestens 100 Kacheln vom Fels entfernt liegt. (Variante c3 zählt vor allem für Fels und Inseln; ihre Spicefläche ist bauartbedingt klein.)
Seit 0.5.4 prüft T11 außerdem die Spice-Regel der Karte 0.5.4:
- **Zone** (OK oder FEHLER): Kein Rasterpunkt der Spicezone nach Regel B (`arrakis_v2_spice_zone`) liegt näher als 100 Kacheln am nächsten Fels-Rasterpunkt von `live`; dazu der Flächenanteil der Zone. Ist die Zone auf einem Seed leer, sagt das eine INFO-Zeile; ist sie auf allen Seeds leer, ist das ein FEHLER „nicht prüfbar“ (sonst bestünde ein kaputter Ausdruck die Prüfung). Regel A (`arrakis_v2_spice_zone_a`) steht nur als MESSUNG da.
- **Kegel** (OK oder FEHLER): t100 des unverzerrten Kegels `arrakis_v2_c4u` gegen den Fels aus `arrakis_v2_c4 > 0` liegt auf jedem Seed bei mindestens −1,53. Regel B setzt voraus, dass `spot_noise` das Maximum linearer Kegel ist, dass verzerrter und unverzerrter Aufruf dieselben Kegelmitten setzen und dass `clamp` die Verzerrung wirklich begrenzt. Genau das prüft „Kegel“. Das Modell lässt bis −(0,955 / 90) · (√2 · 25 + 108) = −1,521 zu; die Grenze liegt eine Hundertstel darunter, damit ein Seed mit Verzerrung an der Klemme nicht fälschlich scheitert. Ohne c4-Fels auf allen Seeds: FEHLER „nicht prüfbar“.
- MESSUNG: die Spicefläche von c4 (Felsschwelle 0) und `c4v2` je Seed bei den festen Schwellen −1,9 / −2,0 / −2,1 / −2,2 und die gemessene Verzerrung `wx − x`, `wy − y` (Soll höchstens ±25).

Im Chat steht am Ende je Variante eine Zeile, alles Weitere in der Datei. Die ENDE-Zeile nennt das Urteil: „Zone ok“, „Zone verletzt“ oder „Zone nicht prüfbar“, „Regel B bestätigt“, „Regel B nicht belegt → Regel A“ oder „Kegel nicht prüfbar“.
**Was daraus folgt:** Die Karte 0.5.4 nutzt Regel B. Meldet „Kegel“ einen FEHLER, kommt Regel A (verzerrtes c4 unter −2,10, Spicezone etwa ein Viertel so groß): In `prototypes/planet/planet-map-gen.lua` wird dann `local SPICE_RULE = "_a"` eingetragen; vorher braucht Regel A ab 0.5.5 eine eigene Gunst, denn sie nimmt noch die von Regel B (`prototypes/noise.lua` bei `arrakis_v3_*`). Regel A hat eigene Ausdrücke (ab 0.5.5 `arrakis_v3_spice_richness_a`, `arrakis_v3_spice_probability_a`; in 0.5.4 `arrakis_v2_…_a`), eine schon angelegte Oberfläche behält so ihre Regel. Bei einem FEHLER in „Zone“ wird der Ausdruck angepasst, unter neuen Namen: 0.5.4 ist veröffentlicht, und nach 0.5.5 gilt das auch für `arrakis_v3_*`. Das Raster sieht Fels zwischen den Punkten nicht; genau auf Kacheln prüft T14.
T11 braucht die Einstellung **Prüfstand** (die Kandidaten c1 bis c4 gibt es nur dann) und alle Rauschausdrücke der Karte 0.5.4. Fehlt einer, bricht T11 gleich mit FEHLER „Rauschausdrücke fehlen: …“ ab.

In der Factorio-Version laufen lassen, in der gespielt wird (jetzt 2.1.23). 2.1.7 hat Voronoi-Rauschen mit hohem jitter korrigiert; c3-Werte aus 2.0.77 gelten dort nicht sicher.

**Du:** nichts. **Melden:** zwei Dateien, `arrakis-test.txt` und `arrakis-t11-karten.txt` (Kartenbilder als Text, beide im selben Ordner).

### T12 Flieger: Rettung aus der Kartenansicht (interaktiv, 3 min)

**Was passiert:** Neben dir steht ein Flieger mit Treibstoff. Ist deine Hand leer, bekommst du eine Spidertron-Fernbedienung; der Flieger ist damit ausgewählt.
Jeder Druck auf **ALT+O** schreibt eine MESSUNG-Zeile. Der Test endet nach 3 min oder mit `/arrakis-test stop`.

**Du, in drei Schritten:**
1. In den Flieger einsteigen (Enter), Karte öffnen (M), den Flieger aus der Karte steuern (WASD) und ALT+O drücken.
2. Aussteigen, die Fernbedienung in die Hand nehmen (ist sie weg: noch einmal ein- und mit leerer Hand aussteigen, dann legt der Test sie dir in die Hand; die Vanilla-Verknüpfung gibt sie erst nach der Forschung „Spidertron“, die Verknüpfung „Fernbedienung für Ornithopter“ ab 0.6.0 schon nach „Ornithopter“), damit auf den Flieger klicken, Karte öffnen (M) und ALT+O drücken.
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
FEHLER heißt (ab der ersten Sekunde eines Laufs): Spitze über 1,5 Kacheln/s, der Tempo-Deckel des Mods musste eingreifen (dann war das Tempo vor dem Deckel über 1,5), Bodentempo über 1,5 oder Ausgleich nicht wie erwartet (min(1, 1/(a · t²)) ab 2.1.13, sonst min(1, 1/a)). Dazu gegen zu viel Ausgleich: Alle eingetragenen Läufe mit einem anderen Brennstoff als Kohle und derselben Dauer wie Kohle (15 s) müssen im Mittel mindestens 97 % des Tempos mit Kohle fahren. Das sind fünf Läufe: Festbrennstoff, Raketentreibstoff, Atomtreibstoff, legendärer Raketentreibstoff und voller Laderaum (ohne Qualität vier). Nicht geprüft werden die sieben Läufe mit 10 s (nach Westen, Norden, Süden, schräg nach NO und SW, negative Koordinaten nach O und W) und die Läufe „ohne Deckel“ des zweiten Ernters. Die Start-INFO zählt die geprüften Läufe auf; die OK-Zeilen nennen nur verfehlte Kriterien. Ohne Qualität im Spiel entfallen die legendären Läufe (drei, vor 2.1.13 zwei) mit je einer INFO-Zeile.
Am Ende entfernt der Test beide Ernter.

**Du:** nichts, zuschauen (die Ernter fahren an dir vorbei). **Melden:** nur die Datei.

### T14 Kartengenerator: Karte echt (Kacheln) (geschätzt etwa 11 s Spielzeit, ab 0.5.4)

**Was passiert:** T14 nimmt die Karte 2 auf echten Kacheln ab (ab 0.5.4, die regulären Spicefelder ab 0.5.5). Für jeden Seed (der deines Spielstands und dieselben acht festen wie in T11; mit `/arrakis-test T14 lang` 30 Seeds) legt er eine Testoberfläche `arrakis-t14-…` mit den Kartengenerator-Einstellungen des Planeten Arrakis an und erzeugt dort die Chunks im Radius 12 um den Ursprung, also 800 × 800 Kacheln.
Dann liest er Felskacheln und Ressourcen und rechnet für jede Kachel den genauen Abstand zur nächsten Felskachel (von Kachelmitte zu Kachelmitte). Danach löscht er die Oberfläche. Arrakis selbst und deine Spielfigur bleiben unberührt; Testoberflächen eines abgebrochenen Laufs löscht der nächste Start.
Nach allen Seeds folgen zwei Durchgänge nur auf dem ersten Seed: das Spice mit dem Spice-Regler auf Größe 0 (Chunks im Radius 9, bis 288 Kacheln je Achse und damit auch dort, wo reguläre Felder liegen dürfen: in der Spicezone ab 215 Kacheln vom Start, die Fleckmitten ab 0.5.5 ab etwa 225 Kacheln) und dieselbe Fläche wie bei den Seeds mit der Karte 0.4.0, nur zum Zeitvergleich.
**Das Spiel läuft dabei langsam:** Je Tick erzeugt T14 eine Chunkreihe (25 Chunks), je Seed sind es etwa 70 Ticks. Die Dauer im Titel ist daraus geschätzt; wie lange die Chunk-Erzeugung in echter Zeit dauert, misst T14 selbst. Du bleibst, wo du bist.

Spice bis 160 Kacheln vom Start zählt als Lehrfeld, alles weiter draußen als reguläres Feld.
**FEHLER** heißt, je Seed:
- Reguläres Spice-Sand liegt näher als 100 Kacheln am Fels. Ein Seed ohne reguläres Spice im Gebiet ist dafür nicht prüfbar (INFO); gibt es auf keinem Seed reguläres Spice, ist das ein FEHLER „nicht prüfbar“.
- Es gibt kein Lehrfeld, eine Lehrfeld-Kachel liegt nicht 40–60 Kacheln vom Fels, oder das Lehrfeld hat nicht 100 000 Spice-Sand ± 5 % (nachgerechnet 99 910 bis 100 190). Von Kachelmitte zu Kachelmitte gemessen liegt eine richtige Karte bei 40,7 bis 60,0 Kacheln, eine Verschiebung um eine Kachel fällt also auf.
- Spice liegt auf Fels, Erz auf Sand, oder unter einem Tiefenwasser (3 × 3 Kacheln wie die Pumpe) liegt eine Sandkachel.
- Der Ursprung liegt nicht auf Fels, oder auf der Startinsel fehlt eines der Erze von Arrakis oder ein Tiefenbrunnen.
- Graben: Fels außer der Startinsel liegt näher als 218,5 Kacheln am Start (220 abzüglich Felskante und Kachelraster).
- Chunks wurden nicht erzeugt (drei Versuche je Reihe).

**FEHLER** heißt außerdem, über alle Seeds (seit 0.5.5). Nutzbar ist ein reguläres Feld (zusammenhängendes Spice, auch schräg) ab 300 Kacheln, auch wenn es am Gebietsrand angeschnitten ist:
- **Felder:** Im Mittel liegen weniger als 2 nutzbare Felder je Seed, oder mehr als ein Neuntel der Seeds (aufgerundet: bei 9 Seeds 1, mit `lang` 4 von 30) hat keins.
- **Feldgröße:** Die nutzbaren Felder aller Seeds sind im Median kleiner als 500 Kacheln. Gibt es gar kein nutzbares Feld, ist „Feldgröße“ nicht prüfbar (INFO); das meldet dann schon „Felder“. Ein Lauf, der vor 0.5.5 begann (gespeichert und mit 0.5.5 geladen), prüft beide nicht (INFO „Lauf vor 0.5.5 begonnen“).
- Zum Vergleich: Mit 0.5.4 fand T14 im Mittel 0,9 reguläre Felder je Seed (0 bis 3, 5 von 9 Seeds ohne), Median 134 Kacheln. Für 0.5.5 sind etwa 5 Felder je Seed mit im Median etwa 1150 Kacheln geschätzt. Die Simulation setzt Felder nur an Kandidaten im günstigen Teil der Zone, so wie es 0.5.5 jetzt tut (`arrakis_v3_spot`); in 0.5.4 bekamen auch Kandidaten am Zonenrand und außerhalb Flecken, daher die kleinen Felder. Es bleibt eine Schätzung (`prototypes/noise.lua` bei `arrakis_v3_*`).

Dazu einmal auf dem ersten Seed: Bei Spice-Größe 0 fehlt das Lehrfeld oder hat nicht 100 000 Spice-Sand ± 5 %, oder es liegt noch reguläres Spice.
Am Ende steht je Prüfung eine OK-Zeile über alle Seeds, bei Verstößen eine INFO-Zeile mit den Seeds (die FEHLER stehen darüber). Bei „Felder“ und „Feldgröße“ nennt die OK-Zeile die Werte (Mittel, Seeds ohne, Median).
Die ENDE-Zeile lautet „9 Seeds, alle Prüfungen bestanden“ bzw. „9 Seeds, K Verstöße; Einzelwerte in arrakis-test.txt“.

**MESSUNG:** Zahl und Größe der regulären Felder, nutzbare Felder je Seed (min, Mittel, max, Seeds ohne) und ihre Größe im Median über alle Seeds, Abstand vom Start zum nächsten regulären Feld, Lehrfeld (Lage, Menge, Abstand zum Fels, größter dichter Block für das 13×13-Feld des Ernters), Startinsel (Kacheln, Rand von … bis … Kacheln vom Start), Graben (nächster Fels außer der Startinsel), Felsanteil und die Dauer der Chunk-Erzeugung je Seed und zusammen, auch bei Spice-Größe 0 und mit der Karte 0.4.0. Die Zeitzeilen stehen nur in der Datei.
Der größte dichte Block ist nur Messung: Mit Radius 9 passt ein dichter 13×13-Block nur, wenn die Mitte des Lehrfelds nah genug an einer Kachelmitte liegt (nachgerechnet bei etwa 83 % der Lagen). Sonst fehlen dem besten Block 1 bis 4 Eckkacheln. Ob das so bleibt, entscheidet Max.
Nutzen die Planeten-Einstellungen keinen `arrakis_v2_…`-Ausdruck, sagt eine INFO-Zeile, dass T14 nicht die Karte 2 (ab 0.5.4) prüft.

**Du:** nichts. **Melden:** nur die Datei.

### T15 Ornithopter: echter Code (etwa 3 min Spielzeit, ab 0.6.0)

**Was passiert:** Ab 0.6.0 gibt es den echten Ornithopter. T15 prüft genau diesen Code (Anheben, Tragen, Absetzen, Absturz, Ablage, Migration), nicht die Testflieger aus T1, T9 und T12.
Er baut auf einer eigenen Fläche der Prüfstand-Oberfläche: Sand mit zwei Spice-Teppichen A und B, 150 Kacheln auseinander, eine Felsinsel mit Annahme, ein Wasser- und ein Mauerfeld. Ornithopter und Ernter entstehen wie gebaut; Piloten und Fahrer sind Puppen. Er braucht keinen Spieler, läuft mit Zeitraffer (bei Tempo 10 etwa 18 s) und hat ein Zeitlimit von 4 min Spielzeit.
T15 hebt echte Ernter auf die echte Ablage `arrakis-hold`. Vor dem Start und am Ende (auch nach Zeitüberschreitung oder Skriptfehler) räumt er seine Reste dort und auf seiner Fläche ab. Zahlen zur Ablage prüft er nur gegen den Stand vor dem Schritt, denn der Spielstand kann selbst Ernter tragen.
In eckigen Klammern steht die Annahme aus `docs/plan-3c.md` 4.16, die der Schritt klärt. Die 17 Schritte:

1. Prototypen: Ornithopter (Spider-Vehicle, 4 Beine, Brenner für chemischen Brennstoff mit 2 Slots, Fernfahren an), beide Tempo-Sticker, die 32 Bilder der Last, Absetz-Probe, Taste und beide Verknüpfungen. FEHLER nennt das fehlende Stück.
2. Forschung [U11]: Eine eigene Force `arrakis-t15` (bleibt im Spielstand und wird wiederverwendet) stellt einen Spice-Ernter her, zuerst eine Puppe von Hand (600 Ticks), sonst eine Montagemaschine 3 (480 Ticks). OK, wenn „Ornithopter“ höchstens 60 Ticks nach dem Ernter-Item erforscht ist. Kommt auch aus der Maschine kein Item, steht dort nur eine MESSUNG; dann prüfst du die Forschung von Hand (Abnahme).
3. Anheben mit Insassen [U14]: ein Ernter mit Fahrer- und Beifahrer-Puppe, 2 Kacheln vom Ornithopter. a) Mit Pilot an Bord wird der Fahrer Beifahrer, der Beifahrer bleibt am Boden (höchstens 6 Kacheln entfernt). b) Ohne Pilot wird der Fahrer Pilot und der Beifahrer Beifahrer. OK, wenn der Ernter auf einem Stellplatz der Ablage steht, getragen, gesperrt und nicht abbaubar, und der Ornithopter beladen, nicht abbaubar, mit Sticker „beladen“, Bild und Schatten. Nach dem Absetzen sitzen alle wie vorher. MESSUNG je Insasse: gleich gesetzt oder erst nach dem Teleport an den Ornithopter.
4. Ankoppeln: Fliegt der Ornithopter 10 Kacheln weg oder kommt ein zweiter Aufruf, bricht die Kopplung ab (Ring weg). Ein zweiter Aufruf nach 5 Ticks wird ignoriert (Entprellen). Stirbt der Ernter beim Ankoppeln, gibt es keinen Skriptfehler. Ein zweiter Ornithopter auf denselben Ernter bekommt „schon angekoppelt“.
5. Notstart [U13]: je ein Ernter beim Aufbauen, aufgebaut, beim Einpacken und angedockt wird angehoben. OK, wenn er danach getragen ist, ohne laufende Aufbau- oder Einpack-Uhr, ohne Feldrahmen und Ring, und die Annahme nicht mehr auf ihn zeigt. Den angedockten setzt der Test über derselben Annahme ab: Nach höchstens 180 Ticks ist er wieder angedockt.
6. Voller Ernter von Feld A nach B [U13, U28]: Qualität „ungewöhnlich“ (mit Quality), Ausrichtung 0,375, 60 % Gesundheit, 20 Kohle (eine brennt), Farbe wie in T3. Auf A aufgebaut, Kofferraum voll (40 Slots: 1900 Spice-Sand, 100 Eisenplatten, 10 Eisenplatten „selten“; ohne Quality 2000 Spice-Sand). Anheben aus dem aufgebauten Zustand, der Ornithopter fliegt per Autopilot über B (höchstens 40 s), Absetzen. OK, wenn alles aus T3 gleich ist (Kofferraum, Treibstoff, Restbrennwert, brennendes Item, Gesundheit, Qualität, Farbe, unit_number, Ausrichtung), der Ernter höchstens 1,5 Kacheln von der Ankunftsstelle steht, der Fahrer noch im Ornithopter sitzt („der Fahrer fliegt mit“) und auf der Ablage wieder so viele Plätze frei sind wie vorher. Danach erntet der Ernter auf B: Sein Erntefeld liegt um die neue Stelle, und nach 60 Ticks ist mehr Spice-Sand im Kofferraum. MESSUNG: Flugzeit, Tempo, Brennwert.
7. Absturz [U17, U23, U24]: Ein beladener Ornithopter wird zerstört. OK im selben Tick: Der Ernter steht höchstens 6 Kacheln von der Absturzstelle, fahrbereit und entsperrt, mit 30 % der Höchstgesundheit weniger (± 0,5); der Ornithopter ist ausgetragen, die Ablage hat ihren Platz wieder. 2 Ticks später hat sich nichts verändert (keine Doppelbehandlung). Ein Ernter mit 20 % Gesundheit behält 1 Lebenspunkt. Mit Pilot an Bord: MESSUNG, wie weit die Figur vom Ernter landet.
8. Anders entfernt: Ein beladener Ornithopter 30 Kacheln vom Abhebepunkt verschwindet per Skript. Nach höchstens 2 Ticks steht der Ernter höchstens 6 Kacheln vom Abhebepunkt, Gesundheit unverändert; mit `raise_destroy` sofort.
9. Kein Platz [U19]: Über einem Feld aus Steinmauern (13 × 13) und über Wasser (15 × 15) geht Absetzen nicht („Kein Platz“), der Ernter bleibt dran; 20 Kacheln weiter geht es. Ein Absturz über dem Mauerfeld landet den Ernter im Radius 16. Dazu die Probe an einer Klippe, wenn die Fläche eine erzeugen kann, sonst INFO. Zuletzt „kein Landeplatz“: Sandinsel in einem See, der Startpunkt der Force liegt im Wasser; der Test macht die Insel zu Wasser und lässt den beladenen Ornithopter abstürzen. Der Ernter wartet dann auf der Ablage (Warteliste, Schaden steht aus). Wird die Insel wieder Sand, landet er nach höchstens 60 Ticks dort, mit 30 % Schaden. Am Ende stellt der Test den Startpunkt zurück.
10. Leerer Tank [U10]: Ein beladener Ornithopter ohne Treibstoff mit Ziel 50 Kacheln steht nach 3 s noch an seiner Stelle (± 0,1), beladen, mit Bild; Absetzen geht.
11. Abbausperre [U26]: Beladen ist der Ornithopter nicht abbaubar und lässt sich nicht zum Abriss markieren, leer ist er abbaubar.
12. Ablage [U25]: Sie ist für alle Forces versteckt, auch für eine eben angelegte (`arrakis-t15n`, am Ende mit `neutral` verschmolzen). Drei Ornithopter heben im selben Tick an und bekommen drei verschiedene Plätze. Danach vergisst der Test die Ablage, wie nach dem Wiederhinzufügen der Mod, und hebt noch einmal an: geht, die Ablage ist wieder eingetragen und versteckt.
13. Zustandstabellen: jede Eingabe aus `docs/plan-3c.md` 4.3 in jedem Zustand von Ernter und Ornithopter. Dazu `Umschalt+H` am getragenen Ernter (nur Hinweis), ein Teleport des getragenen Ernters auf der Ablage (bleibt getragen) und von ihr weg (landet dort, sofort mit `raise_teleported`, sonst nach höchstens 60 Ticks), Tod und spurloses Verschwinden des getragenen Ernters (der Ornithopter ist danach leer) und je ein Klon des getragenen Ernters (Klon fahrbereit, Original getragen) und des beladenen Ornithopters (Klon leer).
14. Migration: Für die Force mit Ernter holt die Mod „Ornithopter“ nach, ein zweiter Aufruf ändert nichts, ohne erforschte „Spice-Ernte“ auch nicht. Am Ende stehen beide Forschungen wieder wie vorher.
15. Pflege [U9, U16]: Der Test zerstört den Sticker des beladenen Ornithopters, heftet einen zweiten eigenen an, zerstört das Bild und teleportiert den Ornithopter auf `arrakis-test-hold` und zurück. Jedes Mal ist nach höchstens 60 Ticks wieder genau ein Sticker „beladen“ dran, und Bild und Schatten sind da. MESSUNG: Zahl der eigenen Sticker.
16. Fremde Force und Unterflug [U21]: Einen Ernter einer anderen Force hebt der Ornithopter nicht an. MESSUNG: Ein Ernter fährt 3 s unter einem stehenden Ornithopter durch; Gesundheit beider vorher und nachher.
17. Entfernen (immer zuletzt): zwei beladene Ornithopter und eine Waise, also ein Ernter auf der Ablage ohne Träger. Der Test ruft das auf, was hinter `/arrakis-uninstall ja` steht: Die beiden Ernter stehen danach höchstens 6 Kacheln neben ihrem Ornithopter, die Waise höchstens 6 Kacheln von ihrem Abhebepunkt; einen Tick später gibt es `arrakis-hold` nicht mehr. Trägt der Spielstand selbst Ernter, werden auch diese abgesetzt. Der nächste Lauf legt die Ablage neu an.

Je Schritt kommt eine OK- oder FEHLER-Zeile mit den gemessenen Werten; die Einzelwerte stehen nur in der Datei.

**Du:** nichts. **Melden:** nur die Datei.

### T16 Ornithopter: Flugphysik (etwa 45 s, ab 0.6.0)

**Was passiert:** Echte Ornithopter mit ihrem echten Tempo-Sticker fliegen wie in T1 auf parallelen Bahnen je 400 Kacheln weit, jeder mit einer Puppe als Pilot. Gemessen wird zwischen 5 s und 15 s nach dem Start. Eigene Fläche, kein Spieler nötig, Zeitlimit 90 s Spielzeit.
- Leer: mit Kohle, Festbrennstoff, Raketentreibstoff, Atomtreibstoff, Spice-Brikett und legendärem Raketentreibstoff (wenn Quality); mit Kohle nach Osten, Westen, Norden, Süden und Nordosten; Ornithopter in Qualität „ungewöhnlich“ und „legendär“ (wenn Quality).
- Beladen (echtes Anheben): mit Kohle und Raketentreibstoff, nach Osten und Norden.
- Zum Vergleich drei Ornithopter, die die Mod nicht kennt: einer ohne Sticker mit Raketentreibstoff (Rohwert) und zwei mit je einem Test-Sticker `vehicle_speed_max` (8/60 bzw. 8, weil die Einheit nicht dokumentiert ist) [U22].
- Schweben [U10]: beladen, mit Kohle, ohne Ziel, 10 s.

**FEHLER** heißt: leer außerhalb 7,0–9,0 Kacheln/s auf einer Bahn; beladen außerhalb 5,0–6,5; beladen zu leer (gleicher Brennstoff, gleiche Richtung) außerhalb 0,65–0,75; die schnellste leere Brennstoff-Bahn mehr als 1,10-mal so schnell wie die langsamste [U7]; Qualität ändert das Tempo um mehr als 10 % [U8].
**MESSUNG:** Tempo, kJ je Kachel und kW je Bahn, der Rohwert ohne Sticker, die beiden `vehicle_speed_max`-Bahnen, beim Schweben Restbrennwert und Zahl der Brennstoffe vorher und nachher. Verbraucht der schwebende Ornithopter etwas, steht dort die INFO „U10 hält nicht: Schweben kostet x kW“; das ist kein FEHLER.
Am Ende schlägt eine INFO-Zeile Modifier für die beiden Sticker vor (0,52 · 8 / v_leer und 0,364 · 5,6 / v_beladen, aus den Ost-Bahnen mit Kohle) [U6]. Liegt das Tempo daneben, übernimmt 0.6.x diese Werte. Zuletzt entfernt T16 seine Ornithopter und Ernter, auch die auf der Ablage.

**Du:** nichts. **Melden:** nur die Datei.

### T17 Ornithopter: Bedienung (interaktiv, 6 min, ab 0.6.0)

**Was passiert:** Neben dir stehen ein Ornithopter mit Kohle und ein Spice-Ernter mit 500 Spice-Sand, 30 Kacheln weiter eine Spice-Annahme auf Fels. Jeder Druck auf `Umschalt+C` und jeder Klick auf eine Verknüpfung schreibt eine MESSUNG-Zeile, jeder Zustandswechsel eine INFO-Zeile.
T17 geht nur mit dir im Spiel; `alle` lässt ihn aus. Er endet nach 6 min Spielzeit oder mit `/arrakis-test stop`. Mit Zeitraffer läuft auch diese Zeit schneller (bei Tempo 10 nach 36 s), also vorher `/arrakis-test tempo 1`.

**Du, in acht Schritten:**
1. In den Ornithopter einsteigen, über den Ernter fliegen, `Umschalt+C`: Ein Ring läuft um den Ernter, nach 2 s hängt er dran. Noch einmal `Umschalt+C`: abgesetzt [U1, U14].
2. Wieder anheben. Dann fliegt der Test den Ornithopter 20 s im Kreis (wie T9 C). FRAGE: „Hängt der Ernter sichtbar unter dem Ornithopter, und liegt der Schatten passend am Boden?“ [U27]
3. Die Verknüpfung „Ernter anheben oder absetzen“ in der Leiste klicken: absetzen, noch einmal: anheben.
4. Das Fahrzeugfenster des Ornithopters öffnen; rechts daneben hängt das Ornithopter-Fenster [U18]. Dort „Absetzen“, dann „In den Ernter steigen“.
5. Aussteigen, die Verknüpfung „Fernbedienung für Ornithopter“ klicken [U5], mit der Fernbedienung den Ornithopter auswählen, Karte öffnen (M), Rechtsklick auf den Ernter. Wenn er angekommen ist, in der Karte `Umschalt+C` drücken, danach die Verknüpfung „Ernter anheben oder absetzen“ klicken [U3, U4].
6. Den Ornithopter aus der Karte fernfahren (WASD) und `Umschalt+C` drücken [U2].
7. FRAGE: „Ist Umschalt+C unter Einstellungen → Steuerung doppelt belegt?“ [U1]
8. Solo-Rettung: in den Ernter steigen, den Ornithopter per Fernbedienung herholen, die Karte offen lassen, `Umschalt+C`. Erwartet: Du sitzt danach als Pilot im Ornithopter, und der Ernter hängt dran [U15]. Über der Annahme absetzen: Nach 2 s dockt er an.

**Mit dem Auge prüfen** (hier und bei der Abnahme): Lastbild und Schatten (Lage, Tönung, Richtung), den Ankoppelring, das Fenster am Ornithopter, das Tempogefühl leer und beladen, das Wippen des Rumpfs und die Icons der beiden Verknüpfungen. „Ernter anheben oder absetzen“ hat vorerst das bunte Panzer-Icon; die Vanilla-Icons der Leiste sind weiß. Sag, ob es stört.

**Melden:** die Datei, deine Antworten auf beide FRAGEn, was dir beim Hinsehen auffällt, und einen Screenshot vom Lastbild im Flug.

## Bekannte Grenzen

- Die Flieger-Beine drehen nicht mit der Flugrichtung. T1 fliegt nur nach Osten; die Werte für 1 und 2 Beine gelten für Ost-West-Flug.
- Auch beim echten Ornithopter drehen die Beine nicht mit der Flugrichtung. T16 misst Norden und Süden deshalb getrennt von Osten und Westen.
- Das Lastbild dreht nicht mit der Flugrichtung: Es zeigt den Ernter in der Richtung, die er beim Anheben hatte (16 Richtungen). Mitdrehen kommt erst mit eigener Grafik (Phase 6).
- T15 und T16 prüfen den Ornithopter mit Puppen über dieselben Funktionen, die Taste, Verknüpfung und Fensterknopf aufrufen. Ob diese Wege im Spiel ankommen (Taste in der Kartenansicht, beim Fernfahren, Fernbedienung ohne „Spidertron“), zeigt nur T17.
- Der Tempo-Deckel in T2 läuft mit Raketentreibstoff. Fährt der Ernter ohne Deckel nicht schneller als 1,6 Kacheln/s, nimmt der Test einen Ersatzdeckel (70 % seines Höchsttempos), damit der Deckel überhaupt greifen muss. Der Durchgang zählt nicht für OK oder FEHLER (siehe T2).
- T6, Bahn D: Bewertet wird der Kopf bis zum Biss. Was der Wurm danach tut, steht als MESSUNG/INFO da (im Spiel taucht er beim Biss ab).
- Im normalen Spiel erntet der Ernter nur auf Arrakis. Die Prüfstand-Fläche gibt dieselbe Einstellung **Prüfstand** frei, die auch den Befehl bringt; nur deshalb kann T13 dort mit dem echten Code ernten.
- T13, Schritt 11: Bewegt sich auch das normale Auto auf dem Band nicht, sagt die Messung nichts; dann meldet der Schritt FEHLER „nicht prüfbar“. Bitte trotzdem die Datei schicken.
- T11 sieht Fels nur auf dem 8-Kachel-Raster. Fels zwischen zwei Rasterpunkten findet erst T14.
- T14 kennt nur Fels im erzeugten Gebiet (800 × 800 Kacheln). Spice-Kacheln, die weniger als 100 Kacheln vom Gebietsrand liegen und deren nächster Fels im Gebiet mindestens 100 Kacheln weg ist, gelten als „nicht gewertet“, nicht als FEHLER.
- Auch die Felder zählt T14 nur im Gebiet: Ein am Gebietsrand angeschnittenes Feld zählt mit seinen Kacheln im Gebiet, ein Feld knapp außerhalb gar nicht. „Felder“ und „Feldgröße“ messen also die Umgebung des Starts, nicht den ganzen Planeten.
- T11 und T14 lesen die Kartengenerator-Einstellungen des Planeten-Prototyps. Was ein vor 0.5.4 begonnener Spielstand erzeugt, in dem Arrakis noch nicht angelegt ist (Karte 1 oder Karte 2), zeigen sie nicht; das zeigt erst ein Ladetest mit einer Kopie (die Mod meldet die alte Karte beim Anlegen).
- T14 misst die Zeit mit einem Profiler, den Factorio nicht speichert. Wird mitten im Test ein Spielstand geladen, steht bei der Dauer „nicht messbar“. Er misst echte Rechenzeit, aber nur während der Chunk-Erzeugung im Tick; der Zeitraffer ändert die Dauer deshalb nicht.
- T2b liest das Tempo im Prüfstand-Takt, nach dem Tempo-Deckel des Mods. Deshalb zählt jeder Lauf, wie oft der Deckel eingegriffen hat („Deckel n× (ab 1 s m×)“); in der ersten Sekunde ist das nach einem Brennstoffwechsel erlaubt, danach ist es ein FEHLER. Die INFO-Zeile am Ende fasst das zusammen. Die echte Fahrt zeigt in jedem Fall das Bodentempo.
