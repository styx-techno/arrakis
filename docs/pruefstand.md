# Prüfstand `/arrakis-test` – Anleitung für Max

Stand: Mod 0.8.3 · Factorio 2.1.23 mit Space Age

Der Prüfstand baut im Spiel Testaufbauten, misst selbst und schreibt die Ergebnisse in den Chat und in eine Datei.
Er klärt die offenen Fragen aus dem Design (`docs/design-ernter-ornithopter.md`, Abschnitt 8), ab 0.6.0 die Engine-Annahmen des Ornithopters (`docs/plan-3c.md`, Abschnitt 4.16), ab 0.7.0 die der Würmer (`docs/plan-3d1.md`, Abschnitt 4.17) und ab 0.8.0 die des Sandwurms (`docs/plan-3d2.md`, Abschnitt 4.17, W1 bis W19).
Du musst nur zuschauen, ein paar Fragen beantworten und am Ende die Dateien schicken.

## Vorbereitung

1. **Einstellung einschalten:** im Hauptmenü *Einstellungen → Mod-Einstellungen → Start* das Häkchen bei **Prüfstand** setzen und bestätigen. Factorio startet neu.
2. **Wegwerf-Spielstand:** ein neues Spiel mit Space Age starten (oder einen Spielstand, der kaputtgehen darf). Nie den echten Spielstand nehmen.
   Die Tests laufen auf einer eigenen Oberfläche `arrakis-testbench`, deine Basis bleibt unberührt. T11 legt kurz leere Testoberflächen `arrakis-t11-…` an und löscht sie wieder. T14 erzeugt die Karte von Arrakis nacheinander auf Testoberflächen `arrakis-t14-…` und löscht auch diese wieder; die Oberfläche Arrakis selbst fasst er nicht an.
   T15 benutzt die echte Ablage `arrakis-hold`, setzt am Ende alle getragenen Ernter ab und löscht sie. Das trifft auch Ernter, die ein Ornithopter deines Spielstands gerade trägt: Sie stehen danach am Boden bei ihrem Ornithopter. T16 hebt ebenfalls echte Ernter auf diese Ablage und entfernt am Ende seine eigenen.
   T18 und T19 (ab 0.7.0) laufen mit eigenen Forces `arrakis-t18` und `arrakis-t19`, die im Spielstand bleiben. T19 Schritt 10 ruft auf, was hinter `/arrakis-uninstall ja` steht: Das beendet jede laufende Jagd des Spielstands ohne Biss, auch deine, und legt die Sandwurm-Force neu an; die Pause von 10 min nimmt der Test am Ende wieder zurück. T19 stellt dazu kurz die Einstellung **Biss** um und am Ende zurück.
   T21 (ab 0.8.0) läuft mit der eigenen Force `arrakis-t21`, die ebenfalls im Spielstand bleibt. T21 Schritt 15 ruft wie T19 Schritt 10 auf, was hinter `/arrakis-uninstall ja` steht: Das beendet jede laufende Jagd des Spielstands ohne Biss (ihre Würmer tauchen still ab), entfernt jeden Sandwurm auf allen Oberflächen und legt die Sandwurm-Force neu an; auch hier nimmt der Test die Pause am Ende zurück.
3. **Alte Ergebnisdatei löschen** (wenn du eine saubere Datei willst): `%APPDATA%\Factorio\script-output\arrakis-test.txt`. Der Prüfstand hängt nur an.
4. Danach die Einstellung wieder ausschalten, bevor du normal spielst.

## Factorio 2.1

Seit 0.5.1 läuft die Mod nur noch in Factorio 2.1 (ab 2.1.23). Fast alle bisherigen Messwerte stammen aus 2.0.77. Bitte in 2.1.23 neu laufen lassen:

- **T2 und T2b (Tempo):** 2.1.13 hat geändert, wie das Höchsttempo der Brennstoffe bei Autos wirkt: Es wirkt jetzt linear (Endtempo ∝ √(a · Ausgleich) · t, gemessen in 2.1.23). Seit 0.5.3 rechnet der Ausgleich ab 2.1.13 deshalb mit min(1, 1/(a · t²)), davor mit min(1, 1/a) (Modell aus T2 in 2.0.77). Bestätigt am 25.10.2026 mit 0.5.3: In T2b fuhren alle 13 Läufe des echten Ernters speed 1,453 wie Kohle, ab 1 s griff der Deckel nie ein.
- **T4 (Annahme und Tankstutzen):** Bauregel auf Fels und Proxy-Container; der Schaltungsanschluss des Proxys ist seit 2.1.21 anders aufgebaut.
- **T12 (Tasten):** 2.1 nimmt in Tasten nur noch dokumentierte Namen. `ALT+O` (T12) und `Umschalt+H` (Ernter) sollten gehen; bitte bestätigen. Kommt `ALT+O` nicht an, schaltet `/arrakis-test weiter` T20 und T22 genauso weiter (ab 0.8.3). `Umschalt+C` (Ornithopter, ab 0.6.0) prüft T17.
- **T11 und T14 (Kartengenerator 0.5.4, Spicefelder 0.5.5):** Die neue Karte ist gebaut, aber noch nicht im Spiel abgenommen. T11 entscheidet über die Spice-Regel (B oder A), T14 prüft die erzeugte Karte auf Kacheln. Beide zusammen laufen lassen, etwa mit `python tools/pc/pruefstand.py --factorio … T11 T14`; siehe dort. T14 lief mit 0.5.4 auf 9 Seeds ohne FEHLER, fand aber im Mittel nur 0,9 reguläre Felder je Seed (5 Seeds ohne, Median 134 Kacheln). 0.5.5 macht die Felder dichter und größer, T14 prüft jetzt auch Zahl und Größe („Felder“, „Feldgröße“); bitte mit 0.5.5 noch einmal laufen lassen.
- **T13** einmal ganz, als Gegenprobe für den Ernter-Code.
- **T18, T19 und T20 (Würmer, neu in 0.7.0):** T18 und T19 ohne Spieler laufen lassen, etwa mit `python tools/pc/pruefstand.py --factorio … T18 T19` (beide sollen ohne FEHLER enden), dann T20 mit dir im Spiel (vorher `/arrakis-test tempo 1`). Sie entscheiden die Engine-Annahmen V1 bis V22 aus `docs/plan-3d1.md`, Abschnitt 4.17; in eckigen Klammern steht bei jedem Schritt, welche er klärt. Was dazu von Hand zu prüfen ist, steht dort in Abschnitt 8.
- **T21 und T22 (Sandwurm, neu in 0.8.0):** T21 ohne Spieler laufen lassen, zusammen mit den Würmern aus 0.7.0 und den Testwürmern, etwa mit `python tools/pc/pruefstand.py --factorio … T21 T5 T6 T7 T18 T19` (alle sollen ohne FEHLER enden), dann T22 mit dir im Spiel (vorher `/arrakis-test tempo 1`). Sie entscheiden die Engine-Annahmen W1 bis W19 aus `docs/plan-3d2.md`, Abschnitt 4.17; in eckigen Klammern steht bei jedem Schritt, welche er klärt. Die Läufe vom 27.10.2026 haben W1, W3, W4, W12, W17 und W18 geklärt (halten) und W19 (hält nicht); mit 0.8.2 endete T21 mit 15 von 15 Schritten ohne FEHLER. Jetzt fehlt T22 mit dir im Spiel. Was dazu von Hand zu prüfen ist, steht dort in Abschnitt 8. T19 und T20 laufen ab 0.8.0 ohne Wurm (ihre Jagden beißen wie in 0.7.0 genau bei 0); den Wurm prüfen T21 und T22.
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
Ohne Spieler gehen sie auch an der Serverkonsole und über RCON (außer `zurück`, `weiter`, T9, T12, T17, T20 und T22), siehe [Automatisch ohne Spieler](#automatisch-ohne-spieler-server-und-rcon).

| Befehl | Wirkung |
|---|---|
| `/arrakis-test` | Liste aller Tests mit Dauer, Hinweisen und letztem Ergebnis |
| `/arrakis-test T1` | Test T1 starten (ebenso `T2` … `T22` und `T2b`, groß oder klein geschrieben); ein laufender Test wird abgebrochen |
| `/arrakis-test T11 lang`, `/arrakis-test T14 lang` | T11 bzw. T14 mit 30 statt 9 Seeds |
| `/arrakis-test alle` | alle nicht-interaktiven Tests nacheinander: T1–T7 (T7 nur Teil a), T11, T13, T2b, T14, T15, T16, T18, T19, T21. Dauer ohne Zeitraffer gut 27 min ([„alle“](#alle)) |
| `/arrakis-test stop` | laufenden Test bzw. „alle“ abbrechen |
| `/arrakis-test status` | Stand in festen Zeilen: bereit, läuft oder wartet, dazu das letzte Ergebnis je Test ([Format](#arrakis-test-status)) |
| `/arrakis-test tempo 10` | Zeitraffer: das Spiel läuft bis zu 10-mal so schnell (`game.speed`, Zahlen von 1 bis 50); `tempo` ohne Zahl zeigt den Stand, `tempo 1` stellt auf echte Zeit zurück. Die Ergebnisse ändern sich nicht ([Zeitraffer](#zeitraffer-arrakis-test-tempo)) |
| `/arrakis-test zurück` | zurück an die Stelle, an der du vor dem Test warst |
| `/arrakis-test weiter` | wie die Prüfstand-Taste `ALT+O`: schaltet T20 und T22 zum nächsten Schritt (ab 0.8.3), falls die Taste bei dir nicht ankommt. Nur, wer den Test gestartet hat; bei anderen Tests sagt der Prüfstand, dass es nichts weiterzuschalten gibt |
| `/arrakis-test T7 ja` | T7 mit Teil b (kann das Spiel abstürzen lassen) |

Die meisten Tests bringen dich zum Zuschauen an den Testaufbau. Mit `/arrakis-test zurück` kommst du zurück.
Jeder Test hat ein Zeitlimit; danach meldet er „Zeitüberschreitung“ und räumt auf.

## Automatisch ohne Spieler (Server und RCON)

Ab 0.5.2 nimmt der Prüfstand Befehle auch ohne Spieler an: an der Konsole eines Factorio-Servers oder über RCON. Ein solcher Aufrufer gilt als Admin.
Die Antworten gehen dann an RCON und ins Log des Servers (`factorio-current.log`), nicht in den Chat; `status` antwortet nur über RCON, an der Konsole des Servers selbst also womöglich gar nicht. Die Testzeilen stehen wie immer in `script-output/arrakis-test.txt`.
Ein eigener Server braucht in `server-settings.json` `"auto_pause": false`, sonst steht er ohne Spieler still und kein Test kommt voran.
Am einfachsten macht das alles das Werkzeug [`tools/pc/pruefstand.py`](#werkzeug-toolspcpruefstandpy).

**Was ohne Spieler läuft:** alle nicht-interaktiven Tests, einzeln oder mit `alle`: T1 bis T7 (T7 Teil b nur mit `T7 ja`), T11, T13, T2b, T14, T15, T16, T18, T19 und T21.
T9, T12, T17, T20 und T22 brauchen dich im Spiel und gehen nur von Hand. Ohne Spieler antwortet der Prüfstand `T9 braucht einen Spieler im Spiel (interaktiv).` und startet nichts; ein laufender Test läuft weiter. `alle` lässt sie wie immer aus.
`/arrakis-test zurück` gibt es nur für Spieler.
Weil niemand den Chat sieht, bestätigt der Prüfstand ohne Spieler kurz: `Gestartet: T13. Stand: /arrakis-test status`, `„alle“ gestartet: …` oder `Gestoppt.` Endet ein Test schon beim Start (etwa mit Skriptfehler), steht dort `T13 gleich beim Start beendet: …`.

**Was ohne Spieler anders ist:**

- FRAGE-Zeilen beantwortet niemand, sie bleiben offen. Fragen stellen T1, T2 (am Ende), T4 (am Ende), T5, T6 und T7 (nur mit `ja`). T3, T11, T13, T2b, T14, T15, T16, T18, T19 und T21 fragen nichts. Die Antworten gibt es nur, wenn du den Test später im Spiel laufen lässt.
- `alle` wartet ohne Spieler nach einer FRAGE nicht (mit Spieler nach T2 und T4 je 30 s).
- Die Zusammenfassung von `alle` lässt den Hinweis auf `/arrakis-test zurück` weg.
- T2: Geht die Skriptfahrt nicht, setzt der Test sonst dich in den Ernter. Ohne Spieler entfällt das: FEHLER „Manuelle Messung entfällt: kein Spieler im Spiel“, dann wertet der Test gleich aus.
- T5, T6 und T7 schreiben eine INFO-Zeile „Kein Spieler gefunden; der Test läuft ohne Zuschauer“. Seit 0.5.3 laufen die fahrenden Testwürmer (T5 b, c, d, T6, T7 b) mit `minimum_activity_mode = full`. Factorio rechnet sie dann auch ohne Zuschauer so, als sähe jemand zu. Bis 0.5.2 standen T5 c, d und T6 Bahn A bis C auf `minimal`. Messbar geändert hat die Umstellung nichts: Die Würmer fuhren schon vorher full, und Bahn C kam auch im ersten Lauf ohne Spieler an (0.5.2: nach 64,2 s; die Begründung im Changelog zu 0.5.3 stimmte nicht). Nur T5 a bleibt auf `minimal`, wie echte Würmer (Design 4.3). Den Modus minimal misst a damit aber nicht: Im Zustand `investigating` hält die Engine den Wurm auch ohne Zuschauer auf full (0.5.3 unter 2.1.23: full bis zur Ankunft, minimal erst etwa 4 s nach dem Wechsel zu `patrolling`). a zeigt also den ungedrosselten Anmarsch. Mit Spieler ändert sich nichts, dort liefen die Würmer schon immer als `full`.
- Die Karte wird nicht aufgedeckt. In T13 Schritt 10 steht dann „Kartenmarkierungen entfernt 0“; das zählt nicht für OK oder FEHLER. T18 kartiert seine Fläche selbst (`force.chart`); ist der Chunk des Wurmzeichens trotzdem nicht kartiert, prüft Schritt 2 die Kartenmarkierung nicht (INFO) [V6].
- T18 und T19 sehen keine Alarme, Töne und Fenster, weil es keinen Spieler gibt, der sie bekäme. Das prüft T20.
- T21 sieht ebenso nicht, wie der Wurm aussieht und klingt, und lädt keinen Spielstand. Das prüft T22.

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

Danach kommt je Test mit gespeichertem Ergebnis eine Zeile, in fester Reihenfolge (T1 bis T7, T9, T11, T12, T13, T2b, T14, T15, T16, T17, T18, T19, T20, T21, T22):

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
- **Was du im Spiel tust, läuft mit:** Zuschauen (T1, T5, T6), die Fahrt von Hand in T2 („W gedrückt halten“, bei Tempo 10 etwa 7,5 s statt 75 s) und die interaktiven Tests T9, T12, T17, T20 und T22 (T12 endet nach 3 min Spielzeit, bei Tempo 10 also nach 18 s; T17 nach 6 min, also nach 36 s; T20 nach 15 min, also nach 90 s; T22 nach 20 min, also nach 2 min). Wer zuschauen, FRAGEn während des Tests beantworten oder etwas von Hand prüfen will, lässt das Tempo auf 1.

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
| `TEST …` | Test-IDs wie `T2b T13`, oder `alle`. `T7:ja` schickt `/arrakis-test T7 ja`, ebenso `T11:lang` und `T14:lang`. T9, T12, T17, T20 und T22 nicht angeben. |

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
`alle` dauert ohne Zeitraffer gut 27 min, mit dem Standard `--tempo 10` geschätzt knapp 4 min ([„alle“](#alle)). Wer das Werkzeug aus einem Programm mit kurzem Zeitlimit für Befehle startet (etwa einem Assistenten), startet es im Hintergrund mit der Ausgabe in eine Datei, verfolgt die Datei und liest am Ende den Rückgabewert. Beendet man das Werkzeug von außen (Strg+C, `kill`), stoppt es den Server noch. Wird es hart beendet (Task-Manager, `kill -9`), läuft der Server weiter, bis der nächste Lauf im selben Ordner ihn beendet.

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
| 2 | Einrichtung oder Infrastruktur: Factorio startet nicht, Spielstand oder RCON geht nicht, Prüfstand-Einstellung nicht aktiv, Zeitraffer geht nicht (Mod vor 0.5.5 und `--tempo` nicht 1), Server abgestürzt (etwa mit `T7:ja`) oder tickt nicht mehr, Ordner schon in Benutzung, Strg+C, ein Test wurde abgelehnt (T9, T12, T17, T20, T22, unbekannte ID) oder endete ohne ERGEBNIS. 2 geht vor 1. |

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
3. Die erbetenen Screenshots (T1, T5, T6, T9, T17, T20, T22).

## „alle“

`/arrakis-test alle` startet T1, T2, T3, T4, T5, T6, T7 (Teil a), T11, T13, T2b, T14, T15, T16, T18, T19 und T21 nacheinander, mit 1 s Abstand.
Nach T2 und T4 wartet er 30 s, damit du deren FRAGE vor Ort beantworten kannst; der Chat sagt das an. Die 30 s gelten in echter Zeit, auch mit [Zeitraffer](#zeitraffer-arrakis-test-tempo).
Die FRAGEn von T1, T5 und T6 gelten während des Tests: einfach zuschauen.
Am Ende kommt eine Zusammenfassung mit allen offenen FRAGEn. Was du verpasst hast, wiederholst du einzeln (z. B. `/arrakis-test T2`).
T9, T12, T17, T20 und T22 brauchen dich und laufen nur einzeln.

**Dauer ohne Zeitraffer: gut 27 min (geschätzt für 0.8.0), mit Tempo 10 geschätzt knapp 4 min.**
- Gemessen mit 0.5.4 ohne Spieler: 44 352 Ticks (739,2 s Spielzeit), in echter Zeit 12,3 min bei 60 Ticks je Sekunde. Die größten Teile in echter Zeit: T2b 4,6 min, T13 und T5 je 1,7 min, T4 1,2 min, T2 und T6 je 1,1 min, alle übrigen unter 30 s. Die Simulation braucht dabei nur etwa 0,1 ms je Tick, das Spiel wartet fast die ganze Zeit auf den nächsten Tick. (0.5.3: 724,7 s Spielzeit; in 0.5.4 kamen T14 und das längere T11 dazu.)
- Mit 0.6.0 kamen T15 und T16 (etwa 18 s: 30 Ticks Aufbau, 140 bis zum Start, 900 Messung) dazu. Gemessen mit 0.6.0 ohne Spieler (Lauf vom 26.10.2026): 51 972 Ticks (866,2 s Spielzeit), darin T15 108,3 s und T16 17,8 s. 0.6.1 verlängert T15 um geschätzt etwa 10 s (Schritt 2 mit beiden Wegen, Schritt 15 mit zwei Teilen mehr): etwa 52 700 Ticks, knapp 15 min ohne Zeitraffer.
- Mit 0.7.0 kommen T18 und T19 dazu. Der Plan schätzte etwa 9000 und 21 600 Ticks; im Trockenlauf gegen die Lua-Attrappe der Engine (vor der Übergabe) brauchte T18 7710 Ticks (128,5 s) und T19 24 660 Ticks (411 s). Zusammen etwa 85 000 Ticks, gut 23 min ohne Zeitraffer. Gemessen im Spiel ist das noch nicht. T19 hängt fast nur an festen Zeiten (Countdowns, Ruhe, Takte), T18 an den Vorsichts-Zyklen der Schritte 8 und 9.
- Mit 0.8.0 kommt T21 dazu. Der Plan schätzte etwa 11 700 Ticks (drei Wellen zu etwa 3800 Ticks, dazu Vorbereiten und die Schritte 13 bis 15); im Trockenlauf gegen die Lua-Attrappe brauchte T21 12 204 Ticks (203,4 s). Zusammen etwa 97 000 Ticks (Plan: 95 000), gut 27 min ohne Zeitraffer. Gemessen im Spiel ist auch das noch nicht. T21 hängt an festen Zeiten (Countdowns von 60 s, Ende der Suche) und daran, wann eine Welle frei wird; das Zeitlimit von 300 s Spielzeit lässt gut 90 s Luft.
- Die Spielzeit hängt nur an der Zahl der Ticks, auch bei T11 und T14, nicht an der Rechenlast.
- Mit [Zeitraffer](#zeitraffer-arrakis-test-tempo) (`/arrakis-test tempo 10`, Standard von `tools/pc/pruefstand.py`) rechnet das Spiel bis zu 600 Ticks je Sekunde: Für die 44 352 Ticks von 0.5.4 sind das gut 1 min, mit T15 und T16 knapp 1,5 min; dazu kommt, was T11 und T14 je Tick länger rechnen (T14 erzeugt rund 6600 Chunks). Daher geschätzt etwa 2,5 min, mit T18 und T19 (0.7.0) etwa 50 s mehr, also etwa 3,5 min, mit T21 (0.8.0) etwa 20 s mehr, also knapp 4 min; gemessen ist das noch nicht. Die Ergebnisse bleiben dieselben.

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

### T15 Ornithopter: echter Code (etwa 2 min Spielzeit, ab 0.6.0)

**Was passiert:** Ab 0.6.0 gibt es den echten Ornithopter. T15 prüft genau diesen Code (Anheben, Tragen, Absetzen, Absturz, Ablage, Migration), nicht die Testflieger aus T1, T9 und T12.
Er baut auf einer eigenen Fläche der Prüfstand-Oberfläche: Sand mit zwei Spice-Teppichen A und B, 150 Kacheln auseinander, eine Felsinsel mit Annahme, ein Wasser- und ein Mauerfeld. Ornithopter und Ernter entstehen wie gebaut; Piloten und Fahrer sind Puppen. Er braucht keinen Spieler, läuft mit Zeitraffer (bei Tempo 10 etwa 12 s) und hat ein Zeitlimit von 4 min Spielzeit. Gemessen mit 0.6.0: 108 s Spielzeit; 0.6.1 braucht geschätzt etwa 10 s mehr.
T15 hebt echte Ernter auf die echte Ablage `arrakis-hold`. Vor dem Start und am Ende (auch nach Zeitüberschreitung oder Skriptfehler) räumt er seine Reste dort und auf seiner Fläche ab. Zahlen zur Ablage prüft er nur gegen den Stand vor dem Schritt, denn der Spielstand kann selbst Ernter tragen.
In eckigen Klammern steht die Annahme aus `docs/plan-3c.md` 4.16, die der Schritt klärt. Die 17 Schritte:

1. Prototypen: Ornithopter (Spider-Vehicle, 4 Beine, Brenner für chemischen Brennstoff mit 2 Slots, Fernfahren an), die beiden Familien der Tempo-Sticker (seit 0.6.1 je 106: leer und beladen, je eine Stufe des Brennstoff-Tempos; die Stufen für Kohle und Raketentreibstoff müssen da sein, die beiden Sticker aus 0.6.0 nicht mehr), die 32 Bilder der Last, Absetz-Probe, Taste und beide Verknüpfungen. FEHLER nennt das fehlende Stück. Wo die Ergebniszeilen einen Sticker nennen, steht seine Stufe dabei, etwa „beladen t1,00“ (Kohle) oder „beladen t1,15“ (Raketentreibstoff); fliegt der Ornithopter mit Kohle, verlangt die Prüfung t1,00.
2. Forschung [U11]: Eine eigene Force `arrakis-t15` (bleibt im Spielstand und wird wiederverwendet) stellt einen Spice-Ernter her, beide Wege nacheinander: a) eine Puppe von Hand (600 Ticks), b) eine Montagemaschine 3 (480 Ticks). Vor jedem Weg setzt der Test „Ornithopter“ und den Herstellzähler (jede Qualität) zurück; gäbe die Migration schon vorher „erforscht“, steht dort eine INFO „nicht prüfbar“. Seit 0.6.1 erforscht auch die Mod selbst (jede Sekunde, wenn die Force einen Ernter hergestellt hat), deshalb wartet der Test nach dem Item bis zu 130 Ticks. MESSUNG je Weg: Ticks bis erforscht, wer erforscht hat (Engine oder Skript) und ob die Produktionsstatistik das Item zählt (Summe über alle Qualitäten, wie die Mod sie abfragt). FEHLER, wenn die Maschine ein Item liefert und „Ornithopter“ danach nicht erforscht ist, oder wenn das Item von Hand gezählt wird und nichts erforscht. Zählt die Statistik das Item der Puppe nicht und erforscht nichts, ist das nur eine MESSUNG (für die Puppe feuerte der Auslöser der Engine im Lauf vom 26.10.2026 nicht, und `on_player_crafted_item` gibt es nur mit Spieler); dann prüfst du die Forschung von Hand (Abnahme). Kommt aus keinem Weg ein Item, steht dort ebenfalls nur eine MESSUNG.
3. Anheben mit Insassen [U14]: ein Ernter mit Fahrer- und Beifahrer-Puppe, 2 Kacheln vom Ornithopter. a) Mit Pilot an Bord wird der Fahrer Beifahrer, der Beifahrer bleibt am Boden (höchstens 6 Kacheln entfernt). b) Ohne Pilot wird der Fahrer Pilot und der Beifahrer Beifahrer. OK, wenn der Ernter auf einem Stellplatz der Ablage steht, getragen, gesperrt und nicht abbaubar, und der Ornithopter beladen, nicht abbaubar, mit Sticker „beladen“, Bild und Schatten. Nach dem Absetzen sitzen alle wie vorher. MESSUNG je Insasse: gleich gesetzt oder erst nach dem Teleport an den Ornithopter.
4. Ankoppeln: Fliegt der Ornithopter 10 Kacheln weg oder kommt ein zweiter Aufruf, bricht die Kopplung ab (Ring weg). Ein zweiter Aufruf nach 5 Ticks wird ignoriert (Entprellen). Stirbt der Ernter beim Ankoppeln, gibt es keinen Skriptfehler. Ein zweiter Ornithopter auf denselben Ernter bekommt „schon angekoppelt“.
5. Notstart [U13]: je ein Ernter beim Aufbauen, aufgebaut, beim Einpacken und angedockt wird angehoben. OK, wenn er danach getragen ist, ohne laufende Aufbau- oder Einpack-Uhr, ohne Feldrahmen und Ring, und die Annahme nicht mehr auf ihn zeigt. Den angedockten setzt der Test über derselben Annahme ab: Nach höchstens 180 Ticks ist er wieder angedockt.
6. Voller Ernter von Feld A nach B [U13, U28]: Qualität „ungewöhnlich“ (mit Quality), Ausrichtung 0,375, 60 % Gesundheit, 20 Kohle (eine brennt), Farbe wie in T3. Kofferraum voll (40 Slots: 1900 Spice-Sand, 100 Eisenplatten, 10 Eisenplatten „selten“; ohne Quality statt der seltenen 50 normale Eisenplatten), dann auf A aufgebaut; gefüllt wird vorher, sonst förderte der Ernter schon in den freien Platz. Anheben aus dem aufgebauten Zustand, der Ornithopter fliegt per Autopilot über B (höchstens 40 s), Absetzen. OK, wenn alles aus T3 gleich ist (Kofferraum, Treibstoff, Restbrennwert, brennendes Item, Gesundheit, Qualität, Farbe, unit_number, Ausrichtung), der Ernter höchstens 1,5 Kacheln von der Ankunftsstelle steht, der Fahrer noch im Ornithopter sitzt („der Fahrer fliegt mit“) und auf der Ablage wieder so viele Plätze frei sind wie vorher. Danach erntet der Ernter auf B: Sein Erntefeld liegt um die neue Stelle, und nach 60 Ticks ist mehr Spice-Sand im Kofferraum. MESSUNG: Flugzeit, Tempo, Brennwert.
7. Absturz [U17, U23, U24]: Ein beladener Ornithopter wird zerstört. OK im selben Tick: Der Ernter steht höchstens 6 Kacheln von der Absturzstelle, fahrbereit und entsperrt, mit 30 % der Höchstgesundheit weniger (± 0,5); der Ornithopter ist ausgetragen, die Ablage hat ihren Platz wieder. 2 Ticks später hat sich nichts verändert (keine Doppelbehandlung). Ein Ernter mit 20 % Gesundheit behält 1 Lebenspunkt. Mit Pilot an Bord: MESSUNG, wie weit die Figur vom Ernter landet.
8. Anders entfernt: Ein beladener Ornithopter 30 Kacheln vom Abhebepunkt verschwindet per Skript. Nach höchstens 2 Ticks steht der Ernter höchstens 6 Kacheln vom Abhebepunkt, Gesundheit unverändert; mit `raise_destroy` sofort.
9. Kein Platz [U19]: Über einem Feld aus Steinmauern (13 × 13) und über Wasser (15 × 15) geht Absetzen nicht („Kein Platz“), der Ernter bleibt dran; 20 Kacheln weiter geht es. Ein Absturz über dem Mauerfeld landet den Ernter im Radius 16. Dazu die Probe an einer Klippe, wenn die Fläche eine erzeugen kann, sonst INFO. Zuletzt „kein Landeplatz“: Sandinsel in einem See, der Startpunkt der Force liegt im Wasser; der Test macht die Insel zu Wasser und lässt den beladenen Ornithopter abstürzen. Der Ernter wartet dann auf der Ablage (Warteliste, Schaden steht aus). Wird die Insel wieder Sand, landet er nach höchstens 60 Ticks dort, mit 30 % Schaden. Am Ende stellt der Test den Startpunkt zurück.
10. Leerer Tank [U10]: Ein beladener Ornithopter ohne Treibstoff mit Ziel 50 Kacheln steht nach 3 s noch an seiner Stelle (± 0,1), beladen, mit Bild; Absetzen geht.
11. Abbausperre [U26]: Beladen ist der Ornithopter nicht abbaubar und lässt sich nicht zum Abriss markieren, leer ist er abbaubar.
12. Ablage [U25]: Sie ist für alle Forces versteckt, auch für eine eben angelegte (`arrakis-t15n`, am Ende mit `neutral` verschmolzen). Drei Ornithopter heben im selben Tick an und bekommen drei verschiedene Plätze. Danach vergisst der Test die Ablage, wie nach dem Wiederhinzufügen der Mod, und hebt noch einmal an: geht, die Ablage ist wieder eingetragen und versteckt.
13. Zustandstabellen: jede Eingabe aus `docs/plan-3c.md` 4.3 in jedem Zustand von Ernter und Ornithopter. Dazu `Umschalt+H` am getragenen Ernter (nur Hinweis), ein Teleport des getragenen Ernters auf der Ablage (bleibt getragen) und von ihr weg (landet dort, sofort mit `raise_teleported`, sonst nach höchstens 60 Ticks), Tod und spurloses Verschwinden des getragenen Ernters (der Ornithopter ist danach leer) und je ein Klon des getragenen Ernters (Klon fahrbereit, Original getragen) und des beladenen Ornithopters (Klon leer).
14. Migration: Für die Force mit Ernter holt die Mod „Ornithopter“ nach, ein zweiter Aufruf ändert nichts, ohne erforschte „Spice-Ernte“ auch nicht. Am Ende stehen beide Forschungen wieder wie vorher.
15. Pflege [U7, U9, U16], sechs Teile: a) Der Test zerstört den Sticker des beladenen Ornithopters, b) heftet einen zweiten eigenen Sticker des anderen Zustands an („leer“), c) zerstört das Bild, d) teleportiert den Ornithopter auf `arrakis-test-hold` und zurück, e) heftet einen zweiten Sticker mit genau dem Namen des vorhandenen an und f) tauscht den Brennstoff von Kohle gegen Raketentreibstoff. Jedes Mal ist nach höchstens 60 Ticks wieder genau ein eigener Sticker „beladen“ dran, und Bild und Schatten sind da; in b) ist der Sticker von vorher noch gültig, in f) hat der Sticker die Stufe t1,15. In e) steht zuerst eine MESSUNG, was die Engine mit dem gleichnamigen Sticker tat (neuer Sticker, alter gültig oder nicht, wie viele eigene). MESSUNG je Teil: Zahl der eigenen Sticker und wie lange die Pflege brauchte.
16. Fremde Force und Unterflug [U21]: Einen Ernter einer anderen Force hebt der Ornithopter nicht an. MESSUNG: Ein Ernter fährt 3 s unter einem stehenden Ornithopter durch; Gesundheit beider vorher und nachher.
17. Entfernen (immer zuletzt): zwei beladene Ornithopter und eine Waise, also ein Ernter auf der Ablage ohne Träger. Der Test ruft das auf, was hinter `/arrakis-uninstall ja` steht: Die beiden Ernter stehen danach höchstens 6 Kacheln neben ihrem Ornithopter, die Waise höchstens 6 Kacheln von ihrem Abhebepunkt; einen Tick später gibt es `arrakis-hold` nicht mehr. Trägt der Spielstand selbst Ernter, werden auch diese abgesetzt. Der nächste Lauf legt die Ablage neu an.

Je Schritt kommt eine OK- oder FEHLER-Zeile mit den gemessenen Werten; die Einzelwerte stehen nur in der Datei.

**Du:** nichts. **Melden:** nur die Datei.

### T16 Ornithopter: Flugphysik (etwa 18 s, ab 0.6.0)

**Was passiert:** Echte Ornithopter mit ihrem echten Tempo-Sticker fliegen wie in T1 auf parallelen Bahnen je 400 Kacheln weit, jeder mit einer Puppe als Pilot. Gemessen wird zwischen 5 s und 15 s nach dem Start. Eigene Fläche, kein Spieler nötig, Zeitlimit 90 s Spielzeit.
- Leer: mit Kohle, Festbrennstoff, Raketentreibstoff, Atomtreibstoff, Spice-Brikett und legendärem Raketentreibstoff (wenn Quality); mit Kohle nach Osten, Westen, Norden, Süden und Nordosten; Ornithopter in Qualität „ungewöhnlich“ und „legendär“ (wenn Quality).
- Beladen (echtes Anheben): mit Kohle und Raketentreibstoff, nach Osten und Norden.
- Zum Vergleich vier Ornithopter, die die Mod nicht kennt: einer ohne Sticker mit Raketentreibstoff (Rohwert), zwei mit je einem Test-Sticker `vehicle_speed_max` (8/60 bzw. 8, weil die Einheit nicht dokumentiert ist) [U22] und (seit 0.6.1) einer ohne Sticker mit Raketentreibstoff und `effectivity_modifier = 0,5`: Ob das Feld bei einem Spider-Vehicle schreibbar ist und wirkt, sagt die API nicht; die Bahn ist nur MESSUNG.
- Schweben [U10]: beladen, mit Kohle, ohne Ziel, 10 s.

**FEHLER** heißt: leer außerhalb 7,0–9,0 Kacheln/s auf einer Bahn; beladen außerhalb 5,0–6,5; beladen zu leer (gleicher Brennstoff, gleiche Richtung) außerhalb 0,65–0,75; die schnellste leere Brennstoff-Bahn mehr als 1,10-mal so schnell wie die langsamste [U7]; Qualität ändert das Tempo um mehr als 10 % [U8].
**MESSUNG:** Tempo, kJ je Kachel und kW je Bahn samt Sticker mit Stufe am Anfang und am Ende (seit 0.6.1 wählt die Mod den Sticker nach dem Brennstoff, etwa „leer t1,15“ bei Raketentreibstoff), der Rohwert ohne Sticker, die beiden `vehicle_speed_max`-Bahnen, die Bahn mit `effectivity_modifier` (geschrieben oder nicht, gelesener Wert, Tempo im Verhältnis zum Rohwert), beim Schweben Restbrennwert und Zahl der Brennstoffe vorher und nachher. Verbraucht der schwebende Ornithopter etwas, steht dort die INFO „U10 hält nicht: Schweben kostet x kW“; das ist kein FEHLER.
Am Ende schlägt eine INFO-Zeile Basiswerte für die Sticker vor, gerechnet aus den Konstanten in `prototypes/ornithopter-speed.lua` und den Ost-Bahnen mit Kohle: BASE_EMPTY · 8 / v_leer und BASE_LOADED · 5,6 / v_beladen [U6]. Liegt das Tempo daneben, übernimmt eine nächste Version diese Werte dort. Zuletzt entfernt T16 seine Ornithopter und Ernter, auch die auf der Ablage.

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

### T18 Wärme: echter Code (etwa 2 min Spielzeit, ab 0.7.0)

**Was passiert:** T18 prüft die Vibration mit dem echten Code aus `scripts/vibration.lua` und `scripts/worms.lua`: Wärme je Chunk, Gewichte aller Quellen, Unruhe, Wurmzeichen und den Vorsichtsmodus. Er baut auf einer eigenen Sandfläche (±300 Kacheln um x = 32 000) mit einer eigenen Force `arrakis-t18`, die wach ist und deren erste Jagd eine Lehrjagd ist. Ernter, Fahrzeuge und Gebäude entstehen wie gebaut, Fahrer sind Puppen. Die elf Schritte laufen gleichzeitig ab Tick 2, jeder in eigenen Chunks mit 3 Chunks Abstand. Kein Spieler nötig, Zeitlimit 4 min Spielzeit, bei Tempo 10 etwa 13 s.
Die Fläche zählt nur für eingeschaltete Forces: T18 schaltet `arrakis-t18` beim Start ein und am Ende aus, beendet ihre Jagden ohne Folgen, löscht Wärme und Ruhe seiner Fläche und stellt Pause und Schonfrist wieder her. Jeder Schritt räumt nach seiner letzten Messung seine Quellen ab und setzt ihre Chunks auf 0.
Die Sollwerte stehen im Test als Zahlen aus dem Plan. Nur die Standardwahlen, die du noch ändern kannst (Countdown der Lehrjagd, Untergrenze und Gewicht im Vorsichtsmodus), liest er aus dem Code. Wärme liest er in der Mitte zwischen zwei Sekundentakten.

1. Prototypen: Eruption (Explosion), Sandstaub, Signal, beide Geräusche, Verknüpfung „Vibrationsanzeige“ (umschaltbar) [V7]; die 13 storage-Tabellen aus 0.7.0 und das aktuelle Schema (ab 0.8.0: 4; dessen neue Tabellen prüft T21 Schritt 1); Sandwurm-Force da und feindlich zu `arrakis-t18` und `player`. Für die beiden Tipps nur MESSUNG (`prototypes.get_history`), verbindlich prüft sie der Datenstufen-Test.
2. Zeitlinie: ein Ernter allein auf Spice, aufgebaut (T_d = erster Tick „aufgebaut“). Jeden Takt mit Beitrag ist die Wärme seines Chunks 1500 · (1 − 0,98^k) ± 0,01. OK: Unruhe genau ab dem 26. Takt (T_d + 1440 bis + 1620), Wurmzeichen genau im 55. Takt (T_d + 3180 bis + 3360) bei Wärme 1006,2 ± 0,5; die Jagd ist eine Lehrjagd mit 90 s Countdown, Biss-Tick ein Vielfaches von 10, Ring und Sekunden da, Status am Ernter; Kartenmarkierung, wenn der Chunk kartiert ist, sonst INFO [V6]. Danach beendet der Test die Jagd still: 9 Chunks um den Ursprung 0, der Sektor ruht 2 bis 4 min, die Lehrjagd ist verbraucht, Ring und Markierung sind weg. MESSUNG: T_d, Tick und Takt von Unruhe und Wurmzeichen.
3. Gewichte: je Quelle `weight_of` und nach 3 Takten die Wärme 2,9404 · Gewicht ± 0,01 um sie. Ernter aufgebaut 30, beim Aufbauen 0, beim Einpacken von Hand 30, mobil fahrend 10, mobil stehend 0, angedockt 0 (Ecke im Sand); Auto fahrend 4, stehend 0; Panzer fahrend 8; Spidertron mit Ziel 6, stehend 0; Ornithopter fliegend 0 und nicht eingetragen; Lokomotive nur `weight_of`, solange der Test ihr `train.speed` gibt (sonst INFO).
4. Feste Quellen [V13]: Großbohrer 8 (nur mit Space Age, sonst INFO), Bohrer 3, Pumpe auf Rohöl 2, Montagemaschine mit Rezept und Zutaten 1, Steinofen mit Kohle und Erz 1, Bohrer ohne Strom 0; ein Bohrer auf Fels ist nicht eingetragen und hat Gewicht 0. Strom kommt wie in T4 aus einer Schnittstelle mit Mast, gelesen frühestens 120 Ticks nach dem Bau. Dann wechselt der Test die Kacheln (mit Ereignis): Der Bohrer auf Fels steht nach höchstens 60 Ticks auf Sand, ist eingetragen und hat Gewicht 3; ein Bohrer, unter den Fels kommt, hat Gewicht 0. MESSUNG: `status` je Gebäude bei beiden Lesungen.
5. Zerfall und Löschen: 1000 auf einem leeren Chunk ist nach 10 Takten 817,07 ± 0,05; 1,5 ist nach 20 Takten noch da, nach 21 gelöscht.
6. Nachbarschaft: zwei Chunks nebeneinander mit je 500 → 3×3-Summe 1000; zwei Chunks Abstand → in der Mitte 1000, an beiden 500, W an beiden 1000; drei Abstand → nirgends über 500.
7. Erstbefüllung: Auto und Montagemaschine ohne Bau-Ereignis sind nicht eingetragen; nach `scan` über ihren Chunk beide (das Einsteigen prüft T20 Schritt 9).
8. Vorsichtsmodus, ein Ernter: zwei volle Zyklen. OK: Er packt im ersten Takt mit W ≥ 600 ein, mit Gewicht 0, baut im ersten Takt mit W < 300 wieder auf, W erreicht nie 1000, kein Wurmzeichen. MESSUNG je Zyklus: Ernte-, Warte- und Aufbauzeit und Anteil (erwartet 16 / 36 / 5 s, 28 %; der erste Zyklus ab kaltem Sand erntet länger).
9. Vorsichtsmodus, zwei Ernter im selben Chunk: 2 min, W nie ≥ 1000, kein Wurmzeichen. MESSUNG: größtes W (erwartet unter 660).
10. Abbruch beim Aufbauen: zwei Ernter im Vorsichtsmodus bei Wärme 700 beginnen aufzubauen und warten nach höchstens 60 Ticks mobil. H10a bleibt stehen und baut im ersten Takt mit W < 300 wieder auf (etwa 42 Takte später, MESSUNG); H10b fährt 1 Kachel, wartet danach nicht mehr und bleibt mobil.
11. Prüfstand-Sperre: Ein aufgebauter Ernter der Force `player` hinterlässt nach 3 Takten keine Wärme (die Fläche zählt für `player` nicht). Läuft gerade T20 (dann ist `player` eingeschaltet), ist das nur eine INFO.

Je Schritt kommt eine OK- oder FEHLER-Zeile mit den gemessenen Werten; die Einzelwerte stehen nur in der Datei.

**Du:** nichts. **Melden:** nur die Datei.

### T19 Jagd: echter Code (etwa 7 min Spielzeit, ab 0.7.0)

**Was passiert:** T19 prüft Jagd und Biss mit dem echten Code: Countdown, Entscheidung bei 0, Biss, Rettung, Grenzen, Schonfrist, Migration und Entfernen. Eigene Sandfläche (±300 Kacheln um x = 34 000), eigene Force `arrakis-t19` (wach), die zehn Schritte nacheinander, jeder in seinen festen Sektoren. Kein Spieler nötig, Zeitlimit 9 min Spielzeit, bei Tempo 10 etwa 41 s. Zwischen zwei Schritten beendet der Test übrig gebliebene Jagden seiner Force ohne Folgen; am Ende räumt er wie T18 und verschmilzt die Hilfs-Force `arrakis-t19b` mit `arrakis-t19`. Die Statistik von `arrakis-t19` setzt er beim Start auf 0.
Ab 0.8.0 läuft T19 ohne Wurm: Er schaltet den Sandwurm für `arrakis-t19` und `arrakis-t19b` aus und am Ende wieder ein. Seine Jagden beißen also wie in 0.7.0 genau bei 0, und alle Erwartungen bleiben; den Wurm prüft T21.
Befehlsjagden (wie `/arrakis-worm`) setzen keine Wärme zurück und lassen keinen Sektor ruhen; Schritt 5 benutzt nur sie.

1. Vorbedingung: Sandwurm-Force feindlich zu `arrakis-t19`. Laufen schon reguläre Jagden anderer Forces, sagt das eine INFO, und Schritt 6 misst nur.
2. Lehrjagd mit Biss [V1, V14, V20]: Ernter H1 aufgebaut mit 500 Spice-Sand, Kohle und einer Puppe als Fahrer, Wärme 999. Um ihn: Auto, Holzkiste, Figur zu Fuß, Band, Eisenkiste (unzerstörbar), Kiste auf einer kleinen Felsinsel, Steinmauer knapp außerhalb von 4 Kacheln, ein Ornithopter mit Pilot genau über H1. OK: Wurmzeichen im nächsten Takt, Lehrjagd mit 90 s; bis 10 Ticks vor 0 nichts beschädigt und nichts gestorben; bei 0 stirbt H1 im selben Tick durch die Sandwurm-Force, ohne Täter-Entity; gestorben sind H1, Fahrer, Auto, Holzkiste, Figur und Band, am Leben Eisenkiste, Mauer, Felskiste, Ornithopter und Pilot; ein Wrack `tank-remnants` mehr, keine Items am Boden; 9 Chunks 0, Ruhe 2 bis 4 min ab dem Biss, Statistik „gebissen“ + 1, Lehrjagd verbraucht, Jagd, Ring und Markierung weg. MESSUNG: ob die Suche nach Figuren den Fahrer im Ernter liefert, Reihenfolge der Tode.
3. Schwer beschädigt [V11, V19]: Der Test stellt die Einstellung **Biss** auf „schwer beschädigt“ (geht das nicht, nimmt er die Option der Befehlsjagd, INFO). Ernter H2 mit Spice-Sand, Kohle und Fahrer, daneben ein Auto, Befehlsjagd 2 s. OK bei 0: H2 lebt mit 10 % Gesundheit (± 0,5), Kofferraum leer, Treibstoff da (höchstens ein Stück weniger), mobil, Fahrer sitzt; das Auto ist tot; Ruhe und Statistik unverändert. Danach fährt H2 1 s und kommt mindestens 0,05 Kacheln weit. Einstellung zurück.
4. Rettung per Ornithopter: reguläre Jagd mit 60 s auf Ernter H3; 12 s vor 0 hebt ein Ornithopter mit Pilot ihn an. OK: 10 s vor 0 getragen, Alarm-Merker leer, Ring weg, verborgen; bei 0 kein Tod, „entkommen“, die Jagd sucht noch 10 s (MESSUNG: Eruptionen an der letzten Stelle); danach 9 Chunks 0, Ruhe, Statistik „entkommen“ + 1 und der Tick der ersten Flucht. Abgesetzt an der alten Stelle und wieder aufgebaut, bleibt sein Chunk 5 Takte lang kalt (der Sektor ruht). Dann verkürzt der Test die Ruhe auf 1 s: Unruhe kommt wieder genau im 26. und das Wurmzeichen im 55. Takt, jetzt keine Lehrjagd, 60 s.
5. Feste Regeln: elf Befehlsjagden mit 10 s, alle im selben Tick, je eigener Sektor; je Teil eine Zeile 5a) bis 5k):
   a) Der Ernter fährt vor 0 ganz auf eine Felsinsel → entkommen, nichts gestorben; binnen 10 Ticks gilt er als sicher, der Ring wird grün.
   b) Der Ernter steht auf Fels, eine Ecke über Sand → gebissen.
   c) Das Ziel verschwindet per Skript vor 0 → „Ziel verloren“, bei 0 „weg“; die Kiste neben seiner letzten Stelle lebt (MESSUNG: Eruptionen dort).
   d) Ein Auto geht per Teleport auf `arrakis-test-hold` → entkommen; ein zweites geht hin und vor 0 zurück → gebissen.
   e) Die Force des Ziels wechselt auf `arrakis-t19b` → die Jagd läuft weiter, gehört der neuen Force, gebissen.
   f) Der Ernter wird angehoben und 30 Kacheln weiter auf Sand abgesetzt → gebissen dort, die Kiste an der alten Stelle lebt (eigene Befehlsjagd mit 20 s; nicht rechtzeitig abgesetzt: INFO).
   g) Der Ernter fährt 10 Kacheln über Sand → gebissen an der neuen Stelle.
   h) Eine arbeitende Montagemaschine als Ziel, ein Band daneben → beide tot.
   i) [V15] Angedockt mit einer Ecke über Sand → gebissen; angedockt auf großer Felsfläche → entkommen.
   j) Gründe: Ornithopter → „flyer“, Baum → „no-target“, zweite Jagd auf dasselbe Ziel → „busy“; ein Spidertron auf Sand wird gebissen (MESSUNG `has_sand_under`) [V22].
   k) Reichweite 3,5 Kacheln je Sekunde Countdown (bei 10 s also 35, wegen des Biss-Takts bis 35,5): Ein Auto springt 15 Kacheln über die Reichweite hinaus → entkommen, sicher binnen 10 Ticks, Ring grün, Eruption am Ort des Wurmzeichens; ein zweites springt 5 Kacheln weniger weit → gebissen dort.
6. Grenzen: vier Ernter in vier Sektoren mit Wärme 999, ein fünfter im Sektor des ersten. OK: nach 1, 2 und 3 Takten je eine Jagd mehr, danach genau 3, keine zweite im selben Sektor; endet eine (nicht die des ersten), bekommt der freie Ernter binnen 2 Takten seine.
7. Schonfrist [V2]: Der Test nimmt „Ornithopter“ zurück und erforscht es wieder. OK: Die Schonfrist merkt die Forschung binnen 60 Ticks (MESSUNG: im selben Tick über das Ereignis oder erst im Takt) und endet 10 min danach; mit einer früheren Landung rechnet sie 30 min ab der Landung; währenddessen gibt es trotz Wärme 999 keine Jagd. Kurz vor dem Ende: wach binnen 3 Takten, und im Takt des Erwachens kommt eine Lehrjagd mit 90 s.
8. Flucht per Fahrt: Felsstreifen 40 × 300 Kacheln; Ernter E1 59, E2 und E3 100 Kacheln vor seinem Rand, Blick zum Fels. E1 und E2 bekommen reguläre Jagden in aufeinanderfolgenden Takten, E3 eine Befehlsjagd mit 90 s. Mit dem Wurmzeichen packen alle ein und fahren zum Fels. OK: E1 entkommt, E2 wird gebissen; E3 als INFO („Lehrjagd-Ausnahme“). MESSUNG: Ankunft von E1 (erwartet etwa 53 s nach dem Wurmzeichen) und wie weit E2 bei 0 noch vom Fels ist (erwartet etwa 30 Kacheln).
9. Migration: Der Test löscht die Schonfrist von `arrakis-t19`; ein Auto und ein Bohrer stehen ohne Bau-Ereignis. Die Migration (nur für `arrakis-t19` und die Prüfstand-Fläche) setzt die Schonfrist auf 10 min ab jetzt und trägt beide Quellen ein; die Schonfrist aller anderen Forces bleibt, wie sie war; ein zweiter Aufruf ändert nichts.
10. Entfernen [V21] (immer zuletzt): eine reguläre Jagd und eine Befehlsjagd laufen. Was hinter `/arrakis-uninstall ja` steht, beendet beide (Ring und Markierung weg) und pausiert 10 min: Trotz Wärme 999 kommt 3 Takte lang keine Jagd; die Sandwurm-Force ist mit `enemy` verschmolzen und wird danach neu und feindlich angelegt.

Je Schritt kommt eine OK- oder FEHLER-Zeile mit den gemessenen Werten (Schritt 5 eine je Teil); die Einzelwerte stehen nur in der Datei.

**Du:** nichts. **Melden:** nur die Datei.

### T20 Würmer: Bedienung (interaktiv, 15 min, ab 0.7.0)

**Was passiert:** T20 prüft, was nur du sehen und hören kannst: Fenster, Staub, Rumpeln, Alarm, Ring, Eruption, Vibrationsanzeige und Tipps. Er läuft mit deiner Force auf der Prüfstand-Fläche (bei x = 36 000) und schaltet sie dort für die Würmer ein; deine übrigen Bauten auf der Prüfstand-Fläche vibrieren dann mit (INFO beim Start). Du bist unverwundbar. Am Ende beendet er die Jagden deiner Force ohne Folgen, löscht Wärme und Ruhe seiner Fläche und stellt Schonfrist und Wurm-Statistik deiner Force wieder her (sonst zählten die Jagden aus Schritt 4 und 5 mit). Die gebauten Ernter bleiben zum Ansehen stehen.
Ab 0.8.0 läuft auch T20 ohne Wurm (INFO „T20 prüft die Warnungen ohne Wurm; den Wurm zeigt T22.“): Alarm, Ring, Fenster und Biss kommen wie in 0.7.0, nur taucht kein Sandwurm auf.
T20 geht nur mit dir im Spiel; `alle` lässt ihn aus. `ALT+O` (oder `/arrakis-test weiter`, ab 0.8.3) schaltet zum nächsten Schritt (Schritt 2 erst nach dem Erwachen, nach Schritt 9 endet der Test). Er endet sonst nach 15 min Spielzeit oder mit `/arrakis-test stop`. Mit Zeitraffer läuft auch diese Zeit schneller (bei Tempo 10 nach 90 s), also vorher `/arrakis-test tempo 1`.
Jeder Klick auf eine Verknüpfung und jedes Umschalten des Vorsichtsmodus schreibt eine MESSUNG-Zeile, jeder Zustandswechsel eines Ernters oder einer Jagd eine INFO-Zeile.

**Du, in neun Schritten:**
1. Schonfrist [V3, V18]: Der Test setzt das Ende der Schonfrist auf 1 min. FRAGE: „Steht oben links ‚Die Wüste regt sich in 1:00‘ und zählt herunter? Kommt bei 0 im Chat ‚Die Wüste ist erwacht‘?“ Während der Minute die Karte öffnen und eine andere Oberfläche ansehen (Fernsicht); der Test schreibt jede Sekunde in die Datei, welche Oberfläche das Spiel als deine sieht und auf welcher du wirklich stehst.
2. Unruhe [V17]: Ein Ernter neben dir baut auf; der Test hält die Wärme bei 620. FRAGE: „Siehst du Sandstaub, hörst du ein Rumpeln, und zeigen Fahrzeugfenster und Ernterfenster ‚Der Sand bebt‘ bzw. die Wärme?“
3. Vibrationsanzeige: die Verknüpfung „Vibrationsanzeige“ klicken. FRAGE: „Siehst du farbige Chunks mit Zahlen, der um den Ernter gelb?“ Noch einmal klicken: weg?
4. Wurmzeichen [V5, V8]: Wärme 999, im nächsten Takt kommt ein Wurmzeichen mit 60 s. FRAGE je Zeichen: Alarm unten rechts mit Wurmzeichen-Symbol, Kartenmarkierung, Warnton, roter Ring mit Sekunden, Zeile oben links, Status „Wurmzeichen! Biss in … s“. Neben dir steht schon der Ornithopter für Schritt 5; gleich weiter, solange der Countdown läuft.
5. Rettung [V16]: einsteigen, über den Ernter fliegen, `Umschalt+C`. (Ist die Jagd aus Schritt 4 schon vorbei, startet der Test eine Befehlsjagd mit 60 s.) FRAGE: „Verschwinden Alarm und Ring, steht oben links ‚wird getragen: erst nach … s auf Sand absetzen‘, und kommt bei 0 eine Sandfontäne unter dir, ohne Schaden?“
6. Biss ohne Rettung: ein zweiter Ernter mit einer Kiste daneben und einer Befehlsjagd mit 30 s. FRAGE: „Kam die Eruption mit Ton genau bei 0, liegt das Wrack da, ist die Kiste weg?“ Dazu ein dritter Ernter am Rand einer Felsinsel (eine Ecke im Sand) mit einer Befehlsjagd mit 60 s: einsteigen, ganz auf den Fels fahren, dann zurück in den Sand. FRAGE: „Wird der Ring grün und steht oben links ‚steht ganz auf Fels: sicher‘, sobald er ganz auf Fels steht, und wieder rot, wenn du zurück in den Sand fährst?“
7. Vorsichtsmodus: Der Test bringt dich zu einem vierten Ernter 120 Kacheln östlich. Ernterfenster öffnen, Vorsichtsmodus einschalten; der Test setzt dann die Wärme auf 580. FRAGE: „Packt der Ernter nach wenigen Sekunden selbst ein (im zweiten Takt), und baut er gut eine halbe Minute später (etwa 36 s nach dem Einpacken) wieder auf?“
8. Tipps [V4]: FRAGE: „Stehen unter Tipps und Tricks (Space Age) die Einträge ‚Arrakis‘ und ‚Wurmzeichen‘?“
9. Fahrzeug ohne Bau-Ereignis [V12]: Neben dir steht ein Auto, das der Test ohne Bau-Ereignis gebaut hat (MESSUNG: nicht eingetragen). Einsteigen: Die MESSUNG danach sagt, ob es jetzt eingetragen ist (dann hält V12). Danach `ALT+O` oder `/arrakis-test weiter`: Ende.

**Mit dem Auge und Ohr prüfen** (hier und bei der Abnahme): Eruption (Größe, Tönung, Staub), Staubwolken, Rumpeln, Warnton, Ring und Zahl, Fenster oben links, Vibrationsanzeige (Farben, Lesbarkeit) und das Symbol des Wurmzeichens.

**Melden:** die Datei, deine Antworten auf die FRAGEn, was dir beim Hinsehen und Hinhören auffällt, und einen Screenshot vom roten Ring mit Sekunden und einen von der Vibrationsanzeige.

### T21 Sandwurm: echter Code (etwa 3,5 min Spielzeit, ab 0.8.0)

**Was passiert:** T21 prüft den Sandwurm mit dem echten Code aus `scripts/worms.lua` und `scripts/sandworm.lua`: Spawnplanung, Route um Fels, Fels-Wächter, Halten vor dem Ziel, Biss-Fenster, Sprint und Ersatzbiss, Zerdrücken, Ornithopter über dem Kopf, Rettung, Tod und Verlust des Wurms, Grenzen, Migration und Entfernen. Eigene Sandfläche 1200 × 1600 Kacheln um x = 38 000 aus zwölf Feldern zu 400 × 400 (ein Feld je Tick vorbereitet), eigene Force `arrakis-t21` (wach, Lehrjagd schon verbraucht); Würmer ohne festen Spawn kommen von Nordost. Jedes Ziel steht in der Mitte seines Felds, Wurm und Körper bleiben darin. Kein Spieler nötig, Zeitlimit 5 min Spielzeit, bei Tempo 10 etwa 20 s plus Aufbau.
Die Schritte 2 bis 12 laufen in drei Wellen, damit nie mehr als drei Befehlsjagden einen Wurm brauchen und nie mehr als sechs Würmer fahren: Welle A mit 2, 10 und 12 (regulär, Wurmzeichen in drei aufeinanderfolgenden Takten) und 3, 4, 5; Welle B mit 6, 7 und 8, sobald keine Befehlsjagd mehr einen Wurm hat; Welle C ebenso mit 9 und 11; danach 13 bis 15 nacheinander im Feld 12. Laufen schon reguläre Jagden anderer Forces, sagt das eine INFO, und Schritt 12, danach 10, startet erst, wenn eine frei wird.
Den Kopf misst der Test alle 10 Ticks. Er springt dabei um ganze Kacheln [W18]: Der gemeldete Kopf (Körperknoten 1) bleibt bis zu 1 Kachel hinter dem wahren und kommt je 10 Ticks 0, 1 oder 2 Kacheln weit. Tempo und Weg rechnet der Test deshalb nur über längere Strecken (Tempo über 1 s, Weg mit höchstens 1 Kachel Fehler je Abschnitt) und schreibt das Fenster dazu (ab 0.8.1). „Bissverzug“ ist die Zeit vom Ende des Countdowns bis zum Biss; erlaubt sind 0 bis 180 Ticks (das Biss-Fenster, bis 3 s nach 0). In jedem Schritt mit Wurm gilt außerdem: Die Kopfmitte steht nie auf Fels, kein Abtauchen wegen Fels, Stillstand oder fehlendem Weg, wo der Schritt es nicht erwartet, und nach dem Ende kein `arrakis-sandworm-*` mehr im Feld (sonst FEHLER). Als MESSUNG kommen dazu: wie oft die Kopfbox Fels berührt (über 5 % der Messpunkte: INFO), Erzeugungen je Jagd (mehr als eine: INFO [W14]), `activity_mode` (irgendwo `minimal`: INFO [W13]) und der Weg beim Halten (auch nach Abzug von 1 Kachel je Halten mehr als 0,5 Kacheln plus 0,1 je Sekunde: INFO [W2]).
Am Ende beendet T21 alle Jagden seiner Force ohne Biss, entfernt übrige Würmer seiner Fläche, löscht Wärme und Ruhe, schaltet `arrakis-t21` aus und stellt Pause und Schonfrist wieder her. Die Standardwahlen, die du am 27.10.2026 bestätigt hast, liest er aus dem Code und nennt sie in einer INFO-Zeile: `CRUSH_SPARES_VEHICLES` false (Fahrzeuge und Figuren auf der Spur werden zerdrückt), `KILL_RESCUES`, `SPRINT` und `NO_ROUTE_BITE` true.

1. Prototypen und storage: Sandwurm `arrakis-sandworm-small` (segmented-unit), vier Rauchkopien und das Abtauchen `arrakis-worm-dive`; ein Probewurm hat 22 Körperknoten und ist gleich wieder weg; storage mit Schema 4, `path_requests`, Protokoll, `worm_off` und `spawn_dir`; Statistik „getötet“ der neuen Force 0.
2. Zeitlinie 60 s, regulär [W1, W2, W6, W7, W9, W13] (Feld 1): Ernter H1 aufgebaut, vier Holzkisten je 3 Kacheln neben ihm, Wärme 999 → Wurmzeichen. OK: Phase `warten` ab dem Start, Planung (`routing`) genau 3230 Ticks vor 0, Wurm genau 2930 Ticks vor 0 auf gerader Linie von Nordost mit 22 Knoten, jeder vierte auf Sand, Körper von H1 abgewandt; Tempo 1 s nach dem Spawn mindestens 3,3 Kacheln/s [W1]; Angriff ab höchstens 40 Kacheln Abstand; vor 0 stirbt nichts im Feld; Bissverzug 0 bis 180, kein Ersatzbiss, Kopf beim Biss höchstens 4,58 Kacheln von H1; im Biss-Takt sind H1 und alle vier Kisten tot und der Wurm ist weg (ein Ereignis „zerstört“, keins „gestorben“); keine Leiche (`simple-entity`) und kein Wolframerz im Feld; Protokoll „angriff“ und „bitten“. MESSUNG: Ankunft in Reichweite (gegen 0), Weg beim Halten, kleinstes Tempo im Angriff (je 1 s), `activity_mode` je Phase, Zustände jede Sekunde; wie der Kopf springt (Weg je 10 Ticks in ganzen Kacheln [W18]) und wo `segments[1]` gegen ihn liegt [W19].
3. Felsinsel [W3] (Feld 3): Kiste als Ziel, Felsinsel 40 × 40 dazwischen, Wurm 160 Kacheln westlich. OK: Er biegt vor der Insel ab (erster Umweg mindestens 2 Kacheln vor ihrem Rand, binnen 3 s mindestens 20° Drehung), Bissverzug 0 bis 180, kein Ersatzbiss (FEHLER nur, wenn W1 in Schritt 2 und der Sprint hier gehalten haben, sonst INFO; der Sprint gilt als gehalten, wenn der Kopf auch mit dem Rasterfehler mindestens 5,5 / 6 des geschriebenen Wegs fuhr). MESSUNG: Umwege, Winkel, Zeitverlust gegen die gerade Linie (gemessen an der Ankunft des gemeldeten Kopfes, also bis 1 Kachel Fahrt zu spät), Sprint-Takte und -Tempo, Anteil des geschriebenen Wegs.
4. Sandtasche mit Knick [W4, W17] (Feld 4): Ernter H4 in einer Sandtasche 30 × 30 mitten in Fels 140 × 140, Zugang nur über einen 16 Kacheln breiten Gang mit Knick. OK: Die Planung findet keine gerade Linie und fragt den Pfadfinder (1 oder 2 Anfragen), ein Weg gilt, keine Sehne der Route schneidet Fels, Angriff erst nach dem letzten Wegpunkt, kein Abtauchen vor dem Biss, der Wurm erreicht die Tasche, Bissverzug 0 bis 180. MESSUNG: Wartezeit der Antwort, Box, Weglänge, Wegpunkte vor und nach dem Ausdünnen, Umwege, Spawn gegen 0.
5. Ernter 10 Kacheln vor Fels [W2] (Feld 5): Fels ab 10 Kacheln östlich von H5 über die ganze Feldhöhe, Wurm von Westen frontal darauf. OK: Fahrziel im Angriff 6 Kacheln hinter H5, nie `patrolling` vor dem Biss, kein Umweg in den letzten 40 Kacheln, H5 gebissen (Bissverzug 0 bis 180), Wurm danach weg. MESSUNG: kleinster Abstand Kopf–Fels, Weg beim Halten.
6. Ornithopter über dem Kopf [W12] (Feld 6): 10 s nach dem Spawn schwebt Ornithopter O6 mit Pilot 5 s lang über dem fahrenden Kopf, zwei Vergleichsflieger fliegen dasselbe Muster 60 Kacheln nördlich (O6b) und 60 Kacheln südlich (O6c); dann kommen alle drei an ihrem letzten Punkt zur Ruhe (höchstens 4 s), der Wurm fährt dabei unter O6 hindurch; dann fliegen alle drei aus der Ruhe 80 Kacheln nach Westen, O6 gegen die Fahrtrichtung über den Körper, die Vergleichsflieger auf den Parallelen. OK: O6 und Pilot ohne Schaden und ohne fremde Sticker (in Ruhe und Flug jeden Tick gelesen); im Mitflug höchstens 0,5 Kacheln mehr Abstand zum Zielpunkt als die Vergleichsflieger im Mittel; O6 mindestens 1 s des Flugs höchstens 3 Kacheln von einem Körperknoten (sonst hat der Flug den Wurm gar nicht berührt); in dieser Zeit fliegt O6 mindestens 80 % so schnell wie die Vergleichsflieger im Mittel in denselben Ticks; für die 80 Kacheln braucht er höchstens 5 % länger als sie im Mittel (kommen die drei nicht zur Ruhe, ist das ein eigener FEHLER „nicht in Ruhe“, kein Bremsen); der Wurm beißt im Fenster. MESSUNG: Abstände und Tempi im Mitflug (O6 unter 98 % der Vergleichsflieger: INFO), Dauer der Ruhe, Flugzeiten, Zeit über dem Körper, die drei Tempi und Wege dort; zur Ursache eine zweite Zeile mit den Wegpunkten des Autopiloten im ersten Flugtick, der größten Abweichung quer zur Flugrichtung und dem Tempo je 20 Ticks, je Flieger. Geändert in 0.8.1: Im Lauf vom 27.10. folgte das Tempo im Mitflug dem springenden Kopf (92 %), und der Flug nach Norden kam kaum über den Körper. Geändert in 0.8.2: Der Lauf mit 0.8.1 maß über dem Körper 89 % des Vergleichstempos für knapp 2 s (1,6 Kacheln Rückstand, Flugzeit 102,2 %, Grenze damals 102 %); die Ursache ist offen. Leichtes Bremsen ist seitdem MESSUNG, FEHLER erst ab einem Fünftel; der zweite Vergleichsflieger zeigt, wie weit zwei Bahnen ohne Wurm auseinanderliegen. Im Lauf mit 0.8.2 war O6 über dem Körper 5 % schneller als die beiden Vergleichsflieger (Flugzeit 99,5 %), die untereinander fast gleich flogen. Die Abweichung entsteht beim Anfahren aus der Ruhe. Im Lauf mit 0.8.3 fuhr dagegen der Vergleichsflieger O6b schneller an als O6 und O6c (O6 91 % des Mittels, 96 % gegen O6c): Einzelne Flieger fahren aus der Ruhe verschieden an, auch fern vom Wurm; ein Bremsen durch den Wurm zeigt sich nicht [W12 hält].
7. Rettung (Feld 7): Ernter H7 mit Fahrer, 12 s vor 0 hebt Ornithopter O7 mit Pilot ihn an. OK: knapp 10 s vor 0 getragen; der Wurm wartet bis 0 nahe der letzten Stelle; bei 0 „entkommen“, Eruption am Kopf, nichts gestorben, O7 und Pilot unverändert; Wurm spätestens 30 Ticks nach 0 abgetaucht; Jagd 10 s nach 0 vorbei.
8. Zerdrücken [W10, W15] (Feld 8): Auf der Linie des Wurms (von Westen auf Kiste K8) liegen fünf Bänder quer, eine Holzkiste, eine Schiene, ein Auto mit Fahrer, eine Figur zu Fuß, eine Hochschiene, eine unzerstörbare Eisenkiste, ein schwebender Ornithopter mit Pilot und 14 Kacheln vor K8 ein kleiner Felsfleck dicht neben der Linie mit einer Kiste ganz darauf (so nah, dass der Kopf sie ohne die Sandregel zerdrücken würde); 6 Kacheln neben der Spur stehen ein Auto mit Fahrer und Ernter H8 im Vorsichtsmodus mit Fahrer; Kiste Z steht 3 Kacheln vor K8. OK (Standardwahl seit 27.10.: Fahrzeuge und Figuren auf der Spur werden mit zerdrückt): vor 0 durch die Sandwurm-Force gestorben sind Bänder, Holzkiste, Schiene, Auto, Fahrer und Figur, je in dem Takt, in dem der Kopf höchstens 3,1 Kacheln entfernt ist; heil mit voller Gesundheit Hochschiene, Eisenkiste, Felskiste, Ornithopter und Pilot, das Auto neben der Spur mit Fahrer und H8 mit Fahrer und Laderaum; der Kopf kommt der Felskiste auf höchstens 2,5 Kacheln nahe (sonst FEHLER „Sandregel ungeprüft“); Z stirbt im Biss-Takt; kein Abtauchen wegen Stillstand. Steht im Code `CRUSH_SPARES_VEHICLES = true` (die alte Wahl), erwartet der Test Auto, Fahrer und Figur heil. MESSUNG: ob der Kopf an Auto, Figur, Hochschiene und Eisenkiste stehen blieb oder durchfuhr (Weg des gemeldeten Kopfes 60 Ticks davor und danach; er springt in ganzen Kacheln, also bei voller Fahrt 3 oder 4, im Angriff 2 oder 3, Stehen hieße 0 bis 1), Lage der Fahrzeuge danach, kleinster Abstand des Kopfes zur Felskiste.
9. Ersatzbiss [W3] (Feld 9): Spawn erst 14 s vor 0 und 160 Kacheln entfernt, zu weit selbst mit Sprint. OK: Die Kiste stirbt genau 3 s nach 0 (Ersatzbiss, Zähler + 1), der Wurm taucht dort ab, wo er ist. MESSUNG: mittleres Tempo im Sprint (W3 hält ab 5,5 Kacheln/s) und Anteil des geschriebenen Wegs, Abstand beim Ersatzbiss.
10. Wurm getötet [W8, W9] (Feld 10): reguläre Jagd auf Ernter H10. 5 s nach dem Spawn bekommt der Wurm 1000 Schaden: Nach höchstens 40 Ticks ist er wieder auf der Jagd (`investigating`). 10 s nach dem Spawn stirbt er. OK: im selben Tick das Ereignis und die Jagd weg, Protokoll „killed“, Statistik „getötet“ + 1, Tick der ersten Flucht gesetzt, die Meldung „… ist gerettet“ (geprüft über ihre Bedingung; den Chat kann der Test nicht lesen), 9 Chunks kalt, der Sektor ruht noch mindestens 2 min; H10 lebt 1 s nach 0; keine Leiche und kein Wolframerz im Feld.
11. Wurm verloren [W7] (Feld 11): zwei Kisten 60 Kacheln auseinander, je eine Befehlsjagd mit Wurm von Westen bzw. Osten. 5 s nach dem Spawn zerstört der Test Wurm a mit Ereignis und Wurm b ohne. OK: a im selben Tick „verloren“, b binnen 10 Ticks; beide Kisten sterben genau bei 0 mit Eruption an der Kiste (wie ohne Wurm).
12. Flucht per Fahrt [W3] (Feld 2): reguläre Jagd auf Ernter H12 mit Fahrer; im Tick des Wurmzeichens packt er ein und fährt dann mit Vollgas vom Wurm weg. OK: echter Biss, Bissverzug 0 bis 180, kein Ersatzbiss, Kopf beim Biss in Reichweite. MESSUNG: Sprint-Takte, mittleres Tempo im Sprint und Anteil des geschriebenen Wegs, Weg von H12.
13. Grenzen (Feld 12, nach den Wellen): vier Befehlsjagden im selben Tick: drei warten, die vierte bekommt keinen Wurm („grenze“); eine reguläre Jagd wartet trotzdem auf ihren (Befehlsjagden sperren nichts); eine mit 20 s → „kurz“; Wurm für die Force ausgeschaltet → „aus“. Alle enden vor der Planung: keine offene Anfrage, kein Wurm. Laufen Jagden anderer Forces, nur MESSUNG.
14. Migration und Waisen: eine Jagd wie aus 0.7.0 (ohne Phase) bekommt nach der Migration keinen Wurm („migration“); ein Sandwurm ohne Jagd verschwindet beim Aufräumen, ein Testwurm `arrakis-test-worm` bleibt.
15. Entfernen (immer zuletzt): zwei Befehlsjagden mit 27 s und ein Waisenwurm; was hinter `/arrakis-uninstall ja` steht, beendet die 2 Jagden und entfernt 3 Würmer; danach kein Sandwurm auf der Prüfstand-Fläche, keine offene Anfrage, und die Sandwurm-Force gibt es nicht mehr. Eine neue Befehlsjagd mit 27 s bekommt trotzdem ihren Wurm, 60 Ticks nach dem Start (± 9 Ticks, weil 0 auf 10 Ticks gerundet wird), und der Code legt die Force dafür selbst wieder an.

Je Schritt kommt eine OK- oder FEHLER-Zeile mit den gemessenen Werten; die Einzelwerte stehen nur in der Datei.

**Du:** nichts. **Melden:** nur die Datei.

### T22 Sandwurm: Optik und Laden (interaktiv, 20 min, ab 0.8.0)

**Was passiert:** T22 zeigt dir den echten Sandwurm: Auftauchen, Farbe, Halten, Biss und Abtauchen, Fahrt um Fels, Zerdrücken, Ornithopter über dem Kopf, Rettung, Tod, Factoriopedia, Speichern und Laden. Er läuft mit deiner Force auf einer Sandfläche ±250 Kacheln bei x = 40 000 mit einer Felsinsel 40 × 40 und schaltet deine Force dort für die Würmer ein (wach). Du bist unverwundbar. Am Ende beendet er die Jagden deiner Force ohne Biss, entfernt übrige Würmer, löscht Wärme und Ruhe seiner Fläche und stellt Schonfrist, Pause und Wurm-Statistik deiner Force wieder her. Was er gebaut hat, bleibt zum Ansehen stehen.
T22 geht nur mit dir im Spiel; `alle` lässt ihn aus. `ALT+O` (oder `/arrakis-test weiter`, ab 0.8.3) schaltet zum nächsten Schritt; der alte Schritt beendet dabei seine laufenden Jagden, damit kein Wurm übrig bleibt. Nach Schritt 9 endet der Test, sonst nach 20 min Spielzeit oder mit `/arrakis-test stop`. Mit Zeitraffer läuft auch diese Zeit schneller (bei Tempo 10 nach 2 min), also vorher `/arrakis-test tempo 1`. Jede FRAGE kommt, sobald es etwas zu sehen gab; beantworte sie, bevor du weiterschaltest.

**Du, in neun Schritten:**
1. Auftauchen: eine Kiste 20 Kacheln vor dir mit einer Befehlsjagd mit 60 s; der Wurm taucht 2 s danach 60 Kacheln östlich auf. FRAGE: „Siehst du den Wurm auftauchen (Staub, Rumpeln)? Ist er sandfarben, ohne Ascheschwaden, ohne dunkle Rauchspur, ohne orange Partikel?“
2. Halten, Biss und Abtauchen: zuschauen, die FRAGE kommt nach dem Biss: „Wartet der Wurm vor der Kiste fast still bis 0? Kam der Biss genau bei 0 mit Sandfontäne, und tauchte er danach mit Staub und Rumpeln ab?“
3. Felsinsel: eine Befehlsjagd mit der Insel zwischen Wurm und Ziel. FRAGE: „Biegt er glatt vor der Insel ab, ohne den Fels zu berühren?“ Danach ein Ernter 10 Kacheln vor dem Inselrand, der Wurm kommt frontal auf den Fels dahinter zu. FRAGE: „Wird der Ernter trotzdem gebissen, und bleibt der Wurm dabei auf dem Sand?“
4. Zerdrücken: Band, zwei Kisten und ein Auto auf der Linie, ein zweites Auto 6 Kacheln daneben, eine Kiste auf einem Felsfleck dicht neben der Linie (im Zerdrückradius). FRAGE: „Verschwinden Band, Kisten und das Auto auf der Linie am Kopf (Wracks), bleiben das Auto neben der Spur und die Kiste auf dem Fels heil, und fährt der Wurm durch, ohne hängen zu bleiben?“ (Mit der alten Wahl `CRUSH_SPARES_VEHICLES = true` fragt er, ob beide Autos heil bleiben.)
5. Ornithopter [W12]: In den Ornithopter neben dir steigen, zum Wurm fliegen (er taucht 160 Kacheln westlich seiner Kiste auf und fährt nach Osten), über dem fahrenden Kopf schweben, anhalten, dann voll nach Westen über den Körper wegfliegen. Der Test schreibt jede Sekunde Tempo, Gesundheit und die Abstände zum Kopf und zum nächsten Körperknoten in die Datei. FRAGE: „Merkst du ein Bremsen, Ruckeln oder Schaden?“
6. Rettung: ein Ernter neben dir mit einer Befehlsjagd mit 60 s; heb ihn vor 0 mit dem Ornithopter an und schwebe über der Stelle. FRAGE: „Hält der Wurm neben dir, beißt ins Leere und taucht ab?“
7. Wurm getötet: Befehlsjagd mit 60 s; in der Anfahrt lässt der Test den Wurm sterben. FRAGE: „Stirbt der Wurm mit Sandstaub, ohne Leiche und ohne Wolfram, steht im Chat ‚… ist gerettet‘, und verschwindet die Jagd oben links?“
8. Factoriopedia: FRAGE: „Steht der Sandwurm in der Factoriopedia unter Gegner mit sandfarbenem Symbol, Name und Beschreibung?“
9. Speichern und Laden [W5, W11]: Befehlsjagd mit 90 s (wie eine Lehrjagd). Die Planung läuft nur von 36,2 s bis 41,2 s nach dem Wurmzeichen, davor wartet die Jagd; der Test sagt beides per INFO an. Speichere zwischen 37 und 40 s und lade sofort; nach dem Auftauchen noch einmal speichern und laden. Der Test schreibt von 30 s bis zum Biss jede Sekunde Phase, gewählten Weg, Spawn-Tick, offene Anfrage und Wurm in die Datei; ein Laden selbst erkennt er nicht. War beim Speichern keine Anfrage offen (auf freiem Sand der Normalfall), steht dort die INFO „W5 offen“. FRAGE: „Taucht der Wurm auf, fährt er nach dem Laden weiter und beißt bei 0?“ Danach `ALT+O` oder `/arrakis-test weiter`: Ende.

**Mit dem Auge und Ohr prüfen** (hier und bei der Abnahme): Farbe, Staub, Partikel, Auf- und Abtauchen, Fahrt um Fels, Ernter vor Fels, Halten vor dem Ziel, Biss, Wracks beim Zerdrücken, Ornithopter über dem Kopf, Tod des Wurms, Factoriopedia.

**Melden:** die Datei, deine Antworten auf die FRAGEn, was dir beim Hinsehen und Hinhören auffällt, und einen Screenshot vom fahrenden Wurm.

## Bekannte Grenzen

- Die Flieger-Beine drehen nicht mit der Flugrichtung. T1 fliegt nur nach Osten; die Werte für 1 und 2 Beine gelten für Ost-West-Flug.
- Auch beim echten Ornithopter drehen die Beine nicht mit der Flugrichtung. T16 misst Norden und Süden deshalb getrennt von Osten und Westen.
- Das Lastbild dreht nicht mit der Flugrichtung: Es zeigt den Ernter in der Richtung, die er beim Anheben hatte (16 Richtungen). Mitdrehen kommt erst mit eigener Grafik (Phase 6).
- T18 und T19 laufen ohne Spieler: Alarme, Warnton, Fenster oben links, Status-Anzeige, Staub, Rumpeln und Vibrationsanzeige prüfen sie nicht. Das macht T20. Ebenso das Einsteigen in ein Fahrzeug ohne Bau-Ereignis [V12]: Eine Puppe ohne Spieler löst das Ereignis dafür nicht aus.
- T18 Schritt 3: Die Lokomotive fährt nicht wirklich, der Test gibt ihrem Zug nur ein Tempo und liest `weight_of`; ihre Wärme misst er nicht.
- T19 Schritt 8: Wann E1 den Fels erreicht und wie weit E2 bei 0 noch weg ist, hängt am Tempo des Ernters. Bewertet wird nur, wer entkommt und wer gebissen wird.
- T19 Schritt 10, T21 Schritt 15, T20 und T22 wirken auf den ganzen Spielstand: Die beiden Schritte beenden jede laufende Jagd, T21 Schritt 15 entfernt dazu jeden Sandwurm (siehe [Vorbereitung](#vorbereitung)); T20 und T22 lassen die Bauten deiner Force auf der Prüfstand-Fläche vibrieren.
- T21 läuft ohne Spieler: Wie der Wurm aussieht und klingt (Farbe, Staub, Partikel, Auf- und Abtauchen), was ein Pilot über dem Kopf merkt und ob eine Jagd Speichern und Laden übersteht, prüft er nicht. Das macht T22. Die Meldung „… ist gerettet“ (Schritt 10) prüft er nur über ihre Bedingung, weil ein Test den Chat nicht lesen kann.
- T19 und T20 laufen ab 0.8.0 ohne Wurm, prüfen also nur Countdown, Entscheidung bei 0 und Bedienung wie in 0.7.0. Was der Wurm selbst tut, prüfen T21 und T22.
- T21 Schritt 15: Der Wurm der letzten Befehlsjagd entsteht 60 ± 9 Ticks nach dem Start, nicht genau nach 60: Das Ende des Countdowns liegt auf dem 10-Tick-Raster, und die Kachelmitte verschiebt die Weglänge leicht.
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
