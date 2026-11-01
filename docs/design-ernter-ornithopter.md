# Arrakis – Design v0.3: Spice-Ernter, Ornithopter, Sandwürmer, Automatik – Kurzfassung

Das volle Design (Spielablauf je Stufe, technische Umsetzung, Versionsweiche 2.0/2.1, Risiken, Belege) steht in
[`docs/protokolle/design-ernter-ornithopter.md`](protokolle/design-ernter-ornithopter.md). **„DOC 2.4“, „Design 4.3“ usw.
in Plänen, Code-Kommentaren und changelog beziehen sich auf das Protokoll.** Wo ein Phasenplan abweicht, gilt der Plan.

Max' Anforderung (05.10.2026): mobile Spice-Ernter wie in Film und Buch, per Ornithopter transportierbar und vor Würmern
rettbar, erst von Hand, später automatisch.

## Max' Grundentscheidungen (06.10.2026, „1a,2a,3a,4c,5b“)
1. Zielversion: anfangs 2.0; **überholt seit 23.10.2026: Ziel ist Factorio 2.1 (ab 2.1.23)**. Zweig `factorio-2.0` bleibt bei 0.5.0. Prototypen in 2.0-Schreibweise, `prototypes/compat.lua` stellt um.
2. Spice nur per Ernter und von Hand (eigene Ressourcenkategorie); alte Bohrer auf Spice werden gemeldet.
3. Ohne Ornithopter kein Entkommen außer vom Lehrfeld (Ernter ≤ 1,5 Kacheln/s, Einpacken 10 s, Felder ≥ 100 Kacheln vom Fels, keine Fernsteuerung).
4. Wurmbiss als Mod-Einstellung, Standard Totalverlust (Wrack bleibt); Alternative „schwer beschädigt“.
5. Lokales Spice-Brikett (5 Spice-Sand + 1 Kohle → 20 MJ, Raffinerie).

## Feste Regeln
- Was ganz auf Fels steht (keine Sandkachel unter der Box) oder getragen wird, wird nie gefressen. Gepflasterter Fels ist Fels.
- Angedockt ist keine Ausnahme. Würmer betreten nie Fels.
- Ornithopter und Carryall in der Luft werden vom Wurm weder getroffen noch spürbar gebremst.
- Anheben, Tragen, Absetzen verlieren nichts (Laderaum, Treibstoff, LP, Qualität, Farbe).
- Biss nie vor Ablauf des Countdowns, höchstens 3 s danach.

## Zahlenregeln
| Größe | Wert |
|---|---|
| Ernter | ≤ 1,5 Kacheln/s (real 1,41); Aufbauen 5 s, Einpacken 10 s; Abbau 5/s; Laderaum 2000 Spice-Sand |
| Vorwarnzeit | 60 s, Lehrjagd 90 s (erste Jagd jeder Force auf einen Ernter) |
| Spicefeld → Fels | ≥ 100 Kacheln; Lehrfeld 41–59 Kacheln |
| Wurm | 3,5 Kacheln/s, Sprint 6 |
| Ornithopter | Flugtreibstoff only; leer 8,0 (Rakete) … 21,5 (legendär Atom), beladen ≈ 70 % |
| Carryall | leer 9, beladen 6,3 Kacheln/s; nur Flugtreibstoff |
| Erschöpfung | 50 % der geförderten Menge wird vom Feld abgezogen |
| Balancing-Ziel 3d3 | 1 Ernter ≈ 15 Spice-Pakete/min im Wurm-Rhythmus (Vorsichtsmodus ≈ 7) |

## Karte (ab 0.5.4/0.5.5, nur neue Spiele)
Kegel-Felsinseln (`spot_noise`, Radius 90, Verzerrung ±25), Startinsel 90 ± 22,5, Graben 220 ohne Inselfels, Lehrfeld
(Radius 9, Mitte 140, ~100 000 Spice-Sand), reguläre Spicefelder nach Regel B ≥ 215 Kacheln vom Start (0.5.5:
`arrakis_v3_spice_*`, Ø 5,3 Felder je 800×800). Veröffentlichte Noise-Ausdrücke (`arrakis_v2_*`, `arrakis_v3_*`) dürfen
sich nie ändern; Änderungen brauchen neue Namen.

## Grundentscheidungen der Technik
- Ernter = `car` (Panzer-Kopie), Abbau per Skript, Kofferraum = Laderaum.
- Ornithopter/Carryall = `spider-vehicle` mit unsichtbaren Beinen; Tragen = Ernter auf versteckte Oberfläche `arrakis-hold` teleportieren, Bild am Flieger.
- Wurm = Jagdwurm auf Abruf (`segmented-unit`-Kopie, Skript-KI), keine festen Territorien. Wärme je Chunk.
- Leitstelle + Carryalls für die Automatik; Thumper = Ablenkung/Köder, kein Pausenknopf.
- Würmer kommen auch ohne Ernter (große Bauten auf Sand).

## Forschungsbaum (Kurz)
Spice-Verarbeitung → Spice-Ernte (10 Melange) → Ornithopter (Trigger: ersten Ernter herstellen) / Thumper (Trigger: erste
Jagd überstanden). Spice-Wissenschaft + Ornithopter → Ornithopter-Leitstelle → Flottenleitung → Bereitschaftsflug,
Frühwarnung (6 Stufen, +5 s je Stufe, max. 90 s), Ernte-Dämpfung (endlos, −5 %/Stufe, max. −50 %). Ernter Mk2 mit Wurmzähnen.

## Roadmap und Stand
| Phase | Version | Inhalt | Stand / Plan |
|---|---|---|---|
| 3.0, 3a | 0.3.1, 0.4.x | Versionsweiche, Prüfstand | fertig |
| 3b | 0.5.x | Ernter, Annahme, Tankstutzen, Brikett, Karte | fertig, [plan-3b.md](plan-3b.md) |
| 3c | 0.6.x | Ornithopter | fertig, [plan-3c.md](plan-3c.md) |
| 3d1 | 0.7.0 | Vibration, Wurmzeichen, Biss | fertig, [plan-3d1.md](plan-3d1.md) |
| 3d2 | 0.8.x | sichtbarer Sandwurm | fertig, [plan-3d2.md](plan-3d2.md) |
| – | 0.9.0 | eigene Fahrzeuggrafiken, Flugtreibstoff | fertig |
| 3e | 0.10–0.11 | Carryall-Automatik, Leitstelle | fertig, [plan-3e.md](plan-3e.md) |
| 3f | 0.12.x | Flottenleitung, dann Bereitschaftsflug/Frühwarnung/Ernte-Dämpfung | 0.12.0 fertig, 0.12.1 läuft, [plan-3f.md](plan-3f.md) |
| danach | – | Wurm-Reviere; 3d3 Thumper, Beute/Wurmzahn, großer Wurm, Mod-Einstellungen, Balancing | offen |
| 3g | optional | 2.1-Komfortschicht | offen |
| 4–6 | – | Coriolis-Stürme, Endgame, Grafiken/Release | offen |
