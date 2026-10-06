# Arrakis

Factorio-Mod für **Factorio 2.0 + Space Age** (ab 2.0.61): ein neuer Wüstenplanet mit Wassermangel, Sandwürmern und Spice. Der Code ist auf Factorio 2.1 vorbereitet; dafür muss nur `info.json` umgestellt werden (`"factorio_version": "2.1"`, Abhängigkeiten `>= 2.1.20`).

Stand: Phase 2. Sandwüste mit Felsinseln, Erze nur auf Fels, Spice-Sand im offenen Sand, Tiefenwasser-Brunnen und Windfalle. Dazu die Spice-Kette mit Spice-Raffinerie, Melange, Spice-Essenz und Spice-Wissenschaft. Grafiken sind eingefärbte Vanilla-Platzhalter.

## Installation zum Testen

1. Repo in den Factorio-Mod-Ordner klonen, der Ordner muss `arrakis` heißen:
   - Windows: `%APPDATA%\Factorio\mods\arrakis`
   - Linux: `~/.factorio/mods/arrakis`
2. Factorio starten, Mod aktivieren, neues Spiel mit Space Age.
3. Schnelltest ohne Forschung: im Chat `/arrakis` eingeben (als Admin). Erzeugt die Oberfläche und teleportiert dich hin.
   Alle Arrakis-Forschungen auf einmal freischalten (schaltet Achievements ab):
   `/c for _, t in pairs({"planet-discovery-arrakis", "arrakis-windtrap", "arrakis-spice-processing", "spice-science-pack"}) do game.player.force.technologies[t].researched = true end`

## Aufbau

| Datei | Inhalt |
|---|---|
| `prototypes/planet/planet.lua` | Planet und Raumverbindung Vulcanus – Arrakis |
| `prototypes/planet/planet-map-gen.lua` | Kartengenerator (welche Kacheln und Ressourcen) |
| `prototypes/noise.lua` | Noise-Ausdrücke: Felsinseln, Erz-, Spice- und Wasserverteilung |
| `prototypes/tiles.lua` | Arrakis-Fels |
| `prototypes/resources.lua` | Spice-Sand, Tiefenwasser |
| `prototypes/windtrap.lua` | Windfalle |
| `prototypes/spice.lua` | Spice-Raffinerie, Melange, Spice-Essenz, Sand, Spice-Wissenschaft |
| `data-updates.lua` | Spice-Wissenschaft in die Labore eintragen |
| `docs/design-ernter-ornithopter.md` | Design v0.3: Spice-Ernter, Ornithopter, Sandwürmer, Automatik |
| `prototypes/surface-property.lua` | Luftfeuchtigkeit (`humidity`) |
| `prototypes/technology.lua` | Entdeckungs-Technologie |
| `control.lua` | Entwicklerbefehl `/arrakis` |

## Roadmap

Siehe Konzept: Phase 1 Gelände und Wasser, Phase 2 Spice-Kette und Spice-Wissenschaft, Phase 3 Sandwürmer, Phase 4 Stürme und Plast-Stahl, Phase 5 Endgame, Phase 6 Balancing und Release.
