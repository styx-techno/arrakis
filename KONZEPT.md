# Projekt Dune – Konzept v0.1

Factorio-Mod für **Factorio 2.0 + Space Age**: neuer Planet **Arrakis** mit eigener Umwelt, eigener Wissenschaft und Produktionsketten, die Spice und Wassermangel ins Zentrum stellen.

Stand: 05.10.2026 · Status: Entwurf zur Diskussion

---

## 1. Leitidee

Jeder Space-Age-Planet hat ein zentrales Problem, das man lösen muss (Vulcanus: Hitze und Demolisher, Fulgora: Schrott und Blitze, Gleba: Verderb, Aquilo: Kälte). Auf **Arrakis** sind es zwei:

1. **Wasser ist knapp.** Es gibt keine Wasserflächen, keine Offshore-Pumpe. Jeder Tropfen muss aus Luft, Tiefe oder Recycling gewonnen werden.
2. **Die Wüste lebt.** Sandwürmer reagieren auf Vibrationen. Wer auf offenem Sand groß baut, wird gefressen. Sicher ist nur Fels.

Belohnung: **Melange (Spice)**, die nur hier vorkommt und die Spice-Wissenschaft sowie Endgame-Boni für das ganze Imperium liefert.

## 2. Der Planet

### 2.1 Oberflächen-Eigenschaften (surface_properties)

| Eigenschaft | Wert (Vorschlag) | Wirkung |
|---|---|---|
| Schwerkraft | 8 m/s² | normal baubar |
| Luftdruck | 800 hPa | etwas dünner als Nauvis |
| Sonneneinstrahlung | 250 % | Solar ist stark, aber Stürme (s. u.) |
| Tag/Nacht | lang, sehr heller Tag | |
| **Luftfeuchtigkeit** (neu) | 2 % | eigene surface-property; begrenzt Windfallen, sperrt wasserintensive Rezepte |

Neue Eigenschaft **„humidity“** erlaubt Rezept-/Gebäudebeschränkungen wie bei Druck oder Magnetfeld (z. B. Windfalle nur bei Feuchte > 0, Arrakis-Rezepte nur bei Feuchte < 10 %).

### 2.2 Gelände

- **Tiefer Sand** (der Großteil): baubar, aber Wurmgebiet. Bauwerke erzeugen „Vibration“.
- **Fels / Schildwall-Gestein**: Inseln und Gebirgsketten. Würmer kommen nicht hinein. Begrenzt Platz → Logistik zwischen Felsinseln wird zum Kernspiel.
- **Salzpfannen**: Ressource Salz/Mineralien, flach, offen, gefährlich.
- **Spicefelder**: rötlich-orange Sandflächen, immer im offenen Sand.

### 2.3 Ressourcen

| Ressource | Vorkommen | Nutzung |
|---|---|---|
| Sand | überall (Abbau oder per Rezept) | Silizium, Glas, Gießformen |
| Spice-Sand (Melange-Erz) | Spicefelder im Wurmgebiet | Spice-Kette |
| Gestein (Fels) | Felsinseln | Steinziegel, Plast-Stahl-Zuschlag |
| Eisen-/Kupfererz | wenig, Felsinseln | Basismaterial vor Ort |
| Tiefenwasser (Fluid) | seltene „Tiefenbrunnen“-Felder, wie Öl | Startwasser, versiegt nicht, aber niedriger Ertrag |
| Salz | Salzpfannen | Elektrolyt, Konservierung |

### 2.4 Gefahren

- **Sandwürmer (Shai-Hulud)**: segmentierte Gegner auf Basis des Demolisher-Prototyps (`segmented-unit`). Eigene Territorien im Sand, betreten nie Fels. Neu: Sie werden von **Vibration** angezogen (Summe laufender Maschinen in einem Gebiet). Wenig Vibration = Wurm zieht vorbei, viel = Angriff.
  - Gegenmittel: auf Fels bauen, „Schwebe“-Fundamente (Suspensor-Plattform, später), **Thumper** als Köder, schwere Waffen zum Erlegen (Belohnung: Wurmzähne/Spice-Essenz).
- **Coriolis-Stürme**: Wetterereignis per Skript. Solarleistung sinkt stark, ungeschützte Gebäude im Sand nehmen Schaden, Bots können nicht fliegen. Warnung vorab (wie Blitzsturm-Logik auf Fulgora, aber als Ereignis).
- **Hitze**: Tagsüber Effizienzverlust bei manchen Maschinen ohne Kühlung (optional, s. offene Fragen).

## 3. Produktionsketten

### 3.1 Wasser (Pflicht-Kette)

```
Luft  ──► Windfalle ───────────────► Wasser (wenig, stetig)
Tiefenwasser ──► Tiefenpumpe ─────► Wasser (Startphase)
Verderb/Biomasse ──► Todesdestille ► Wasser + Dünger
Abwasser ──► Rückgewinnungsanlage ─► Wasser (Rückführung aus Kühlkreisen)
```

- **Windfalle** (neu): kleines Gebäude, sehr geringe Rate, keine Energie nötig, nur bei humidity > 0.
- **Todesdestille** (neu): verarbeitet Spoilage/organisches Material → Wasser. Nebenbei nützlich für Gleba-Verderb auf Plattformen.
- **Wasserbilanz** als Kernpuzzle: viele Rezepte liefern **Abwasser** zurück, das recycelt werden kann. Wer sauber im Kreislauf baut, kommt mit wenig Frischwasser aus.

### 3.2 Spice (Hauptkette)

```
Spice-Sand ─► Spice-Erntemaschine ─► Roh-Spice
Roh-Spice + Wasser ─► Spice-Raffinerie ─► Melange + Sand (Rückgabe)
Melange ─► Spice-Essenz (konzentriert, verderblich)
Melange + Plast-Stahl + Elektronik ─► Spice-Wissenschaftspaket
```

- **Spice-Erntemaschine** (neu): großer Bohrer, muss im Sand stehen (Spicefelder). Erzeugt viel Vibration → Wurmrisiko. Später als **mobiler Ernter** (Fahrzeug mit Laderaum, das abgesetzt wird) denkbar.
- **Melange** verdirbt nicht. **Spice-Essenz** verdirbt (zu Melange-Staub), damit Export auf Plattformen spannend bleibt.
- **Spice-Explosion** (optional): Spicefelder entstehen nach Ereignis neu und versiegen, damit man Ernteposten verlegen muss.

### 3.3 Material

| Produkt | Rezept (grob) | Zweck |
|---|---|---|
| Silizium / Glas | Sand + Hitze | Solarpanels, Optik |
| **Plast-Stahl** | Stahl + Silizium + Spice-Staub | Arrakis-Leitmaterial (wie Wolframkarbid auf Vulcanus) |
| **Suspensor-Spule** | Plast-Stahl + Supraleiter (Fulgora) | Schwebe-Technik, Fundamente, Fahrzeuge |
| **Holtzman-Generator** | Suspensor + Prozessor + Melange | Schilde, Feldtechnik |
| Destillanzug-Gewebe | Plastik + Salz + Wasser | Rüstung |

### 3.4 Neue Gebäude (Überblick)

| Gebäude | Rolle | Pendant in Space Age |
|---|---|---|
| Windfalle | Wasser aus Luft | Offshore-Pumpe (Ersatz) |
| Todesdestille | Verderb → Wasser | Recycler-artig |
| Spice-Erntemaschine | Spice-Abbau | Großer Bergbaubohrer |
| Spice-Raffinerie | Spice-Verarbeitung, Planeten-Bonus-Produktivität | Gießerei / EM-Werk |
| Thumper | lockt Würmer an eine Stelle | – |
| Schildwall-Generator | Gebietsschild gegen Stürme/Würmer (Energiefresser) | – |

## 4. Forschung

### 4.1 Freischaltung

1. **Planet-Entdeckung: Arrakis** – benötigt Weltraum-Wissenschaft + eine Planetenwissenschaft (Vorschlag: Metallurgie von Vulcanus, wegen Hitze-Thema).
2. **Ersthelfer-Techs auf Arrakis** (Trigger-Techs wie in Space Age): Windfalle (Trigger: Ankunft), Spice-Ernte (Trigger: Spice-Sand abbauen), Todesdestille (Trigger: 1000 Wasser herstellen).
3. **Spice-Wissenschaftspaket** (neue Farbe: Orange-Rot).

### 4.2 Was Spice-Wissenschaft freischaltet

| Technologie | Wirkung |
|---|---|
| Plast-Stahl-Verarbeitung | neues Leitmaterial |
| Destillanzug (Rüstungs-Modul) | Spieler-Regeneration, Schutz in Stürmen |
| Holtzman-Schild (Equipment) | stärkerer persönlicher Schild |
| Suspensor-Fundamente | Bauen auf tiefem Sand ohne Vibration |
| Ornithopter | Flugfahrzeug (Spidertron-Basis, ignoriert Gelände) |
| Mentat-Rechenkern | Labor-Gebäude mit Forschungsbonus (wie Biolabor) |
| **Spice-Navigation** | Raumplattformen: Melange als Zusatzantrieb → höhere Geschwindigkeit/Reichweite |
| **Prescience** (Infinite) | kleiner globaler Qualitäts-Bonus |
| Faltraum-Antrieb (Endgame) | Voraussetzung für Reisen ans Systemende, alternative Route |

### 4.3 Einbindung ins Vanilla-Endgame

Spice-Wissenschaft soll **ergänzen, nicht blockieren**: Vanilla-Ziele (Aquilo, Systemrand) bleiben ohne Arrakis erreichbar. Spice-Wissenschaft wird aber in späten Infinite-Techs und eigenen Boni gebraucht. So bleibt die Mod mit anderen Planeten-Mods kompatibel.

## 5. Raumfahrt

- Arrakis liegt **innen** im System, in der Nähe von Vulcanus (heiß, sonnennah).
- Eigene Raumverbindung mit eigenem Asteroiden-Mix (mehr Kohlenstoff, weniger Eis → Wasser auch im Orbit knapp).
- Export-Gut: Melange, Plast-Stahl, Suspensor-Spulen.

## 6. Technische Umsetzung

### 6.1 Mod-Struktur

```
arrakis/
├── info.json                 (dependencies: "base >= 2.0", "space-age >= 2.0")
├── data.lua                  (lädt prototypes/*)
├── data-updates.lua          (Anpassungen an Vanilla-Techs)
├── control.lua               (Stürme, Wurm-Vibration, Spice-Explosionen)
├── prototypes/
│   ├── planet/               (planet, space-connection, surface-property)
│   ├── tiles/ autoplace/     (Sand, Fels, Spicefelder, Noise-Expressions)
│   ├── entities/             (Gebäude, Würmer)
│   ├── items/ recipes/ fluids/
│   └── technology/
├── locale/de/  locale/en/
└── graphics/
```

### 6.2 Wichtige Space-Age-Bausteine

- `planet`, `space-connection`, `surface-property`: Planet und neue „humidity“.
- `autoplace` + Noise-Expressions: Sand-/Fels-Verteilung, Spicefelder.
- `segmented-unit` (wie Demolisher) und Territorien für Würmer.
- `surface_conditions` an Rezepten/Gebäuden.
- `spoil_result`/`spoil_ticks` für Spice-Essenz.
- Technologie-Trigger (`research_trigger`) für Erstkontakt-Techs.

### 6.3 Grafik

Grafik ist der größte Aufwand. Plan: **MVP mit eingefärbten Vanilla-Grafiken** (Tint), danach schrittweise eigene Sprites (Blender-Renders oder Community-Assets mit passender Lizenz).

## 7. Roadmap

| Phase | Inhalt | Ergebnis |
|---|---|---|
| 0 | Repo, info.json, leerer Planet, Raumverbindung | Arrakis anfliegbar |
| 1 | Gelände (Sand/Fels), Ressourcen, Windfalle, Tiefenpumpe | Überleben möglich |
| 2 | Spice-Kette, Spice-Wissenschaft, erste Techs | Spielschleife steht |
| 3 | Sandwürmer + Vibration | Kerngefahr |
| 4 | Coriolis-Stürme, Todesdestille, Plast-Stahl | volle Planetenmechanik |
| 5 | Endgame-Techs (Ornithopter, Navigation, Schilde) | Langzeitziele |
| 6 | Balancing, eigene Grafiken, Mod-Portal-Release | v1.0 |

## 8. Offene Designfragen

Siehe Zusammenfassung im Thread; Entscheidungen werden hier nachgetragen.

1. Position in der Progression
2. Sandwürmer: echte Gegner oder Umweltgefahr
3. Spice verderblich oder nicht
4. Name der Mod (Markenrecht „Dune“)
5. Repo jetzt anlegen
