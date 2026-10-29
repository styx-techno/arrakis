# Bauplan Phase 3f: Flottenleitung (0.12.0 und 0.12.1)

Stand: Entwurf vom 29.10.2026. Grundlage ist das Design (docs/design-ernter-ornithopter.md), Abschnitte 2.3 (Stufe 3), 4.4 und 6, dazu docs/plan-3e.md mit dem Nachtrag 0.11.0. Abschnitt 1 sammelt die Festlegungen, bei denen Max widersprechen kann; ohne Widerspruch gilt die Standardwahl. Max hat am 29.10.2026 „alle 3“ gewählt: erst die Flottenleitung, danach Wurm-Reviere, danach Thumper, Beute und Mod-Einstellungen.

Ziel aus dem Fahrplan (Design 7, Zeile 3f): **Mit 5 Erntern im Inventar der Leitstelle und Signal H = 3 laufen drei Ernter. R holt alle zurück. Die Statussignale stimmen.**

## 0. Umfang

In 0.12.0 („Flottenleitung“):
- Forschung „Flottenleitung“ nach „Ornithopter-Leitstelle“.
- Soll-Zahl aktiver Ernter je Leitstelle: im Fenster der Leitstelle einstellbar, Signal H am Draht hat Vorrang.
- Ersatz-Ernter als Item im Inventar der Leitstelle.
- Neue Aufträge EINSATZ, UMSETZEN, RÜCKRUF; Feldsuche.
- Signal R: Rückruf aller betreuten Ernter auf Fels an die Leitstelle; danach (R wieder 0) zurück auf ihre Felder.
- Statussignale auf eigenen virtuellen Signalen am Draht der Leitstelle.
- Prüfstand T26 (automatisch, alle neuen Teile einzeln), T27 (Dauerlauf), T28 (interaktiv).

In 0.12.1 (zweiter Schritt derselben Phase):
- Forschung „Bereitschaftsflug“: Ein Carryall folgt seinem Ernter dauerhaft.
- Forschung „Frühwarnung“ (6 Stufen, je +5 s Countdown, höchstens 90 s).
- Forschung „Ernte-Dämpfung“ (endlos, je −5 % Ernter-Vibration, höchstens −50 %).

Nicht in 3f: feste Wurm-Reviere (eigene Phase danach), Thumper, Wurmzahn, großer Wurm und Mod-Einstellungen für Zeiten und Schwellen (3d3), Patrouillen und Radar-Modus aus 2.1 (3g).

## 1. Festlegungen (Standardwahl, Max kann widersprechen)

1. **Soll-Zahl steht anfangs auf „aus“.** Ohne Soll-Zahl verhält sich die Leitstelle wie in 0.11.0 (Rettung, Tanken, Entladen, Rückkehr); erst mit einer Zahl im Fenster oder Signal H > 0 setzt sie Ernter aus dem Inventar ein. So ändert die neue Forschung an laufenden Spielständen nichts, bis man es will.
2. **Aktiv zählt jeder betreute Ernter,** auch einer, den der Spieler selbst gesetzt hat: aufgebaut, aufbauend, einpackend, getragen von einem Carryall dieser Leitstelle oder gerettet an der Leitstelle wartend. Bei Soll 3 und zwei selbst gesetzten setzt die Leitstelle also einen dazu.
3. **Überzählige holt die Leitstelle nur, wenn sie ihr gehören:** Ernter, die sie selbst eingesetzt hat (Merker `fleet_owner`). Selbst gesetzte bleiben stehen. Ein überzähliger Ernter wird erst entladen (Laderaum nicht leer: zur Annahme), dann an der Leitstelle ins Inventar gelegt.
4. **Signal R holt alle betreuten Ernter** (auch selbst gesetzte) auf die Abstellplätze an der Leitstelle. Solange R > 0 ist, setzt sie keinen ein und bringt keinen zurück. Fällt R auf 0, bringen die Carryalls jeden an seine alte Stelle (wie nach einer Rettung, Abschnitt 0.11.0). Ernter, die ihr gehören und leer sind, legt sie bei R > 0 gleich ins Inventar und setzt sie danach neu ein.
5. **Feldsuche:** nur in kartierten Chunks in Reichweite, nicht in einem Sektor mit Jagd, Ruhe oder lauerndem Wurm. Ein Platz braucht mindestens 20 000 Spice-Sand im Erntekreis (Radius 6,5). Bewertung: Menge im Erntekreis geteilt durch (1 + Flugweg zur Leitstelle / 100 + Flugweg zur nächsten Annahme / 100). Plätze näher als 14 Kacheln an einem anderen Ernter oder Ziel fallen weg. Kartenmarkierungen mit Spice-Sand-Symbol: Plätze bis 64 Kacheln um eine solche Markierung kommen vor allen anderen dran.
6. **Umsetzen:** Meldet ein Ernter „Feld leer“, setzt die Leitstelle ihn auf den besten freien Platz. Findet sie keinen, bringt sie ihn an die Leitstelle; dort zählt er als Reserve und wird eingesetzt, sobald ein Platz frei wird.
7. **Einsatz:** Neuer Ernter aus dem Inventar auf einen Abstellplatz an der Leitstelle (Ladung, Qualität und gespeicherte Werte des Items bleiben), betankt mit Ernter-Treibstoff aus der Leitstelle (5 Stück, wie die Carryalls), dann trägt ihn ein Carryall auf den gewählten Platz und baut ihn auf. Höchstens ein Einsatz zugleich je Leitstelle.
8. **Statussignale** (eigene virtuelle Signale, nie H oder R): aktive Ernter, Ernter im Inventar und an der Leitstelle (Reserve), freie Carryalls, laufende Rettungen, Spice-Sand in allen Laderäumen, Wurmalarm (1, solange ein betreuter Ernter Ziel einer Jagd ist). Ein verstecktes Schaltungsgebäude unter der Leitstelle gibt sie auf den roten und grünen Draht der Leitstelle aus.
9. **Fenster der Leitstelle:** Soll-Zahl mit Knöpfen − und + (0 = aus), Hinweis, wenn Signal H gilt, Knopf „Alle zurückrufen“ (wirkt wie R, bis man ihn wieder drückt), Zeilen für Reserve und Feldsuche.
10. **Kosten Flottenleitung** wie im Design 6: 1000 × Automatisierung, Logistik, Chemie, Weltraum, Metallurgie, Spice; Voraussetzungen „Ornithopter-Leitstelle“ und Metallurgie-Wissenschaft.
11. **Bereitschaftsflug (0.12.1):** Jeder aufgebaute Ernter mit freiem Carryall bekommt einen „Begleiter“, der über ihm schwebt (`follow_target`). Ein Begleiter gilt nicht als frei; die Bereitschafts-Regel aus 0.10.0 (einer bleibt für Rettungen) gilt weiter.
12. **Frühwarnung (0.12.1):** Stufe n verlängert den Countdown aller regulären Jagden der Force um 5 s · n (60 → höchstens 90 s), die Lehrjagd bleibt 90 s.
13. **Ernte-Dämpfung (0.12.1):** Stufe n senkt das Gewicht aufgebauter und einpackender Ernter um 5 % · n, höchstens 50 %.

## 2. Dateien

| Datei | Inhalt |
|---|---|
| `prototypes/technology.lua` bzw. `prototypes/depot.lua` | Forschung „Flottenleitung“ (0.12.1: „Bereitschaftsflug“, „Frühwarnung“, „Ernte-Dämpfung“) |
| `prototypes/depot.lua` | verstecktes Schaltungsgebäude `arrakis-depot-signals` (constant-combinator, nicht wählbar, ohne Kollision), virtuelle Signale `arrakis-signal-…`, Draht-Anschluss der Leitstelle |
| `scripts/fleet.lua` | Aufträge `deploy`, `move`, `recall`, Soll-Zahl, Rückruf-Zustand, Statussignale |
| `scripts/fleet-fields.lua` (neu) | Feldsuche: Spice je Chunk zählen (budgetiert), Plätze bewerten, Reservierungen |
| `scripts/fleet-gui.lua` | Soll-Zahl, Rückruf-Knopf, neue Zeilen |
| `scripts/migrate.lua` | Schema 6: `storage.fields`, Felder der Leitstelle (`target`, `recall`, `signals`), Merker `fleet_owner` am Ernter |
| `scripts/testbench/t_fleet.lua` | T26, T27, T28 |
| Locale de/en, changelog, info.json, docs/pruefstand.md | Texte |

## 3. Laufzeit

### 3.1 Datensätze (Schema 6)

- `storage.depots[un]` dazu: `target` (Soll aus dem Fenster, 0 = aus), `recall_button` (true/false), `signals` (LuaEntity des Schaltungsgebäudes), `last_h`, `last_r` (zuletzt gelesene Signale).
- `storage.harvesters[un]` dazu: `fleet_owner` (Leitstelle, die ihn eingesetzt hat), `fleet_wait.reason` (`"rescue"`, `"recall"`, `"reserve"`).
- `storage.fields = {chunks = {[s] = {[chunk_key] = {amount, tick}}}, queue = {...}, reserved = {[key] = job_id}}`.

### 3.2 Takte

- 30 Ticks wie bisher: Verteilung und Ablauf.
- 60 Ticks: Signale lesen und schreiben, Soll prüfen (höchstens ein neuer EINSATZ oder RÜCKRUF je Leitstelle und Takt), Feldsuche: höchstens 4 Chunks zählen.
- Chunk-Zählung veraltet nach 10 min; `on_resource_depleted` zieht ab.

### 3.3 Aufträge (neu)

| Auftrag | Auslöser | Ablauf |
|---|---|---|
| UMSETZEN (30) | Ernter mit Status „Feld leer“ | Hinfliegen, anheben, zum besten freien Platz, absetzen, aufbauen; ohne Platz an die Leitstelle (Reserve) |
| EINSATZ (20) | Aktive < Soll, Reserve vorhanden, Platz gefunden | Ernter aus dem Inventar (oder Reserve an der Leitstelle) anheben, zum Platz, absetzen, aufbauen |
| RÜCKRUF (10) | R > 0 oder Rückruf-Knopf; Aktive > Soll (nur eigene) | Anheben, an die Leitstelle; eigene und leere ins Inventar |

Priorität unter RÜCKKEHR (40). Ein Rückruf bei R > 0 hat Vorrang vor Tanken und Entladen (Priorität 70), weil er vor einem Sturm schnell gehen soll.

## 4. Prüfstand

- **T26 (automatisch):** Prototypen und Signale; Soll 2 aus dem Fenster setzt zwei Ernter aus dem Inventar ein; Signal H = 3 setzt einen dritten; H = 1 holt zwei eigene zurück ins Inventar; Umsetzen bei leerem Feld; Feldsuche meidet Sektor mit lauerndem Wurm und bevorzugt die Kartenmarkierung; R holt alle (auch einen selbst gesetzten) an die Leitstelle, R = 0 bringt sie zurück; Statussignale stimmen in jedem Schritt.
- **T27 (Dauerlauf, 60 min Spielzeit):** 5 Ernter im Inventar, H = 3, drei Spicefelder, die leer werden; Wurmzeichen alle 75 s. Erwartet: nie mehr als 3 aktiv, nach jedem Umsetzen wieder 3, kein Biss, kein Ernter verloren.
- **T28 (interaktiv):** Leitstelle mit Fenster und Draht zu einer Lampe; FRAGE an Max zum Fenster und zum Ablauf.
