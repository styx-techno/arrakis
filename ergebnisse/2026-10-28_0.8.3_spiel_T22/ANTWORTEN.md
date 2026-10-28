# T22 im Spiel (Max, 2026-10-28, Mod 0.8.3, Factorio 2.1.23)

Datei: script-output/arrakis-test.txt aus Max' echtem Factorio (enthält auch alte Läufe T9/T12 aus 0.4.0).
Der zweite T22-Lauf hatte beim Kopieren (18:00) noch keine ENDE-Zeile.

Antworten von Max auf die FRAGE-Zeilen (wörtlich):
- Frage 1: "ja, er dürfte aber früher oder mehr zu hören sein"
- Frage 2: "ja aber er ist mehr despawnt als abgetaucht"
- Frage 3: "ja" (Datei-Stand 18:03:28; T22 stellt zwei Fragen mit der Nummer 3: "Biegt er glatt vor der Insel ab, ohne den Fels zu berühren?" und "Wird der Ernter trotzdem gebissen, und bleibt der Wurm dabei auf dem Sand?" – Max' "ja" ist nicht einer davon zugeordnet)
- Nachtrag Frage 3: Max bestätigt "ja beide" – 3a (biegt glatt vor der Insel ab, ohne Fels) und 3b (Ernter wird trotzdem gebissen, Wurm bleibt auf Sand) beide ja.
- Frage 4: "ja er zerstört alles auf seinem weg, die kiste auf dem felsen bleibt heile, da die felsfläche sehr klein war kann ich nicht garantierent dass das pathfinding dem felsen wirklich ausgewichen ist"
- Nachtrag Frage 4: "ja und ja" – Auto neben der Spur bleibt heil; Wurm fährt durch, ohne hängen zu bleiben.
- Frage 5 (Ornithopter über dem Kopf, W12): nicht getestet. Max: "nicht geschafft" – er hat den Ablauf nicht verstanden (dachte, es gehe um die Holzkiste), der Wurm hatte schon gebissen, bevor er losflog. Muss in einem neuen T22-Lauf wiederholt werden. Hinweis für die Anleitung: die INFO zu Schritt 5 im Chat war offenbar nicht klar genug.
- Beobachtung von Max (17:14): "sollte das spice feld auf dem felsen spawnen? der spawn beim testen war etwas unglücklich" – nicht geklärt, ob Testfläche oder echte Karte und was genau auf dem Fels lag.
- Max hat T22 an dieser Stelle unterbrochen ("lass uns das später noch mal testen"). Offen: Schritte 5 (Ornithopter über dem Kopf) bis 9 sowie die Spice-auf-Fels-Beobachtung.
- Korrektur: T22 lief doch weiter (Schritt 6 bei +747,6 s, Schritt 7 bei +980,6 s).
- Frage 6 (Rettung: hält der Wurm neben dir, beißt ins Leere, taucht ab?): keine Antwort von Max.
- Frage 7 (Wurmtod: Sandstaub, keine Leiche, kein Wolfram, Chat „… ist gerettet“, Jagd verschwindet oben links): "ja, funktioniert alles"
- Frage 8 (Factoriopedia: Sandwurm unter Gegner mit sandfarbenem Symbol, Name, Beschreibung?): NEIN. Max: "es gibt in factoriopedia keine einträge für gegner und ich habe auch keinen für die würmer gefunden".
  Code-Stand 0.8.3 (prototypes/sandworm.lua): Kopf ist deepcopy eines Demolishers, hidden = nil, order "s-z[arrakis]-a[sandworm-small]", icons mit Sand-Tönung, subgroup geerbt; Segmente hidden = true. Dass Max gar keine Gegner-Gruppe sieht (auch keine Vanilla-Gegner), deutet eher auf Factoriopedia-Verhalten in 2.1.23 (z. B. nur bekannte/angetroffene Gegner) als auf den Mod hin – ungeprüft.
- Korrektur zu Frage 8: Max hatte versehentlich unter "Tipps und Tricks" statt in der Factoriopedia gesucht. Die Antwort "nein" ist damit ungültig; neue Antwort folgt.
- Frage 8 (neu, gültig): JA. Max: "er ist ordentlich in der factoriopedia drin".
- T22 endete durch das Zeitlimit: "ENDE +1199.0s: 20 min um: Schritt 8, 7 Jagden". Schritt 9 (Speichern/Laden, W5/W11) lief deshalb nicht; Max: "test 9 startet nicht". Rückmeldung: 20 min reichen für den interaktiven Test mit Erklärungen nicht.
- Frage 6 (Rettung): keine Antwort von Max; laut Factorio-Log (factorio-log-jagden.txt) Jagd 7 kind=harvest outcome=escaped, bite_tick=nil, also kein Biss.
- Zweiter T22-Lauf (dritter Block "=== T22" in der Datei, ab etwa 18:24): Max ist direkt zu Schritt 5 gesprungen.
- Frage 5 (Ornithopter über dem Kopf, W12): NEIN, "nein nichts davon" – kein Bremsen, kein Ruckeln, kein Schaden gespürt. Datei: Gesundheit durchgehend 3000; Tempo-Schwankungen (z. B. 2,5–8,05 Kacheln/s) stammen aus Max' eigener Steuerung (Schweben, Anhalten, Wegfliegen), Abstand zum Kopf bis 1,5 Kacheln.
