# Grafik

Die Fahrzeuggrafiken entstehen aus Skripten: Blender baut das Modell aus einfachen Formen und rendert es, `pack.py`
setzt die Bilder zu Spritesheets zusammen. Es braucht kein Blender-Programm, nur Python 3.11 (bpy 4.x) oder 3.13 (bpy 5.x) mit den Modulen `bpy`
(Blender als Python-Modul, `pip install bpy`) und `pillow`.

`szene.py` enthält, was alle Modelle teilen: Materialien, Grundformen (`box`, `cyl`, `slab`), Licht, Kamera und das
Rendern je Modus. Ein Modellskript ruft `szene.start(...)`, baut seine Teile und ruft `szene.render(...)`.

## Spice-Ernter (ab 0.8.5)

```
python ernter-modell.py roh base 64
python ernter-modell.py roh mask 64
python ernter-modell.py roh shadow 64
python ernter-modell.py roh icon
python pack.py roh blaetter
```

Danach kommen aus `blaetter/` die Dateien `harvester-base.png`, `harvester-mask.png` und `harvester-shadow.png` nach
`graphics/entity/spice-harvester/`, `harvester-icon-64.png` als `graphics/icons/spice-harvester.png` und
`harvester-icon-256.png` als `graphics/technology/spice-harvester.png`. `python ernter-modell.py roh vorschau 8` rendert
acht Ansichten mit Schatten zum Ansehen.

Festlegungen, an denen `prototypes/harvester.lua` und das Lastbild in `prototypes/ornithopter.lua` hängen:

- Kamera orthografisch, 45 Grad über dem Boden, aus Süden; `pack.py` streckt die Bildhöhe um √2, dann ist eine Kachel
  quadratisch wie im Spiel. Der Bodenpunkt unter der Fahrzeugmitte liegt in der Bildmitte (kein `shift`).
- Licht von links oben, Schatten fallen nach rechts unten.
- 64 Richtungen, 0 = Norden, im Uhrzeigersinn, 8 Bilder je Zeile.
- Rumpf und Farbmaske: 6 Kacheln zu 64 px (384 px, im Spiel `scale = 0.5`). Schatten: 8 Kacheln zu 32 px (256 px,
  `scale = 1`). Die Farbmaske zeigt Seitenschürzen und Rückenplatten in Spielerfarbe.
- Farben in Standard-sRGB (`view_transform = "Standard"`); Blenders Vorgabe AgX wäscht sie aus.

## Ornithopter (ab 0.8.9)

```
python ornithopter-modell.py roh base 64
python ornithopter-modell.py roh mask 64
python ornithopter-modell.py roh shadow 64
python ornithopter-modell.py roh icon
python pack.py roh blaetter ornithopter
```

Aus `blaetter/` kommen `ornithopter-base.png`, `ornithopter-mask.png` und `ornithopter-shadow.png` nach
`graphics/entity/ornithopter/`, die Symbole nach `graphics/icons/ornithopter.png` und
`graphics/technology/ornithopter.png`.

Abweichend vom Ernter:

- Die Bildmitte ist der Rumpfmittelpunkt, nicht ein Bodenpunkt. `prototypes/ornithopter.lua` schiebt das Bild mit dem
  Vanilla-shift des Spidertron-Rumpfs (−19 px) dorthin, wo das Spiel den Rumpf zeichnet.
- Die Flughöhe setzt das Spiel selbst über den Abstand des Schattens. Das Schattenbild entsteht deshalb nur 0,6 Kacheln
  über dem Boden (`LIFT`, damit die Klauen nicht im Boden stecken), 8 Kacheln zu 32 px (256 px, `scale = 1`). Sein
  Schwerpunkt liegt im Mittel 0,33 Kacheln rechts und 0,33 unter der Bildmitte; das zieht der shift im Prototyp ab.
- Rumpf und Farbmaske sind 7 Kacheln breit (448 px, `scale = 0.5`), sonst stoßen die Flügelspitzen an den Rand. Die
  Farbmaske zeigt die Streifen an den Flügelspitzen.
- Die Greifklauen reichen 0,6 Kacheln unter die Rumpfmitte; daran hängt das Lastbild des Ernters
  (`scripts/flyer.lua`, `IMAGE_OFFSET`).

## Carryall und Leitstelle (ab 0.10.0)

```
python carryall-modell.py roh base 64
python carryall-modell.py roh mask 64
python carryall-modell.py roh shadow 64
python carryall-modell.py roh icon
python pack.py roh blaetter carryall
python leitstelle-modell.py roh2 base 1
python leitstelle-modell.py roh2 shadow 1
python leitstelle-modell.py roh2 icon
python pack.py roh2 blaetter2 depot
```

Der Carryall ist der Ornithopter 1,25-mal so groß (`K` im Modell), dunkel, mit vier Triebwerken und Greifrahmen.
Rumpf und Farbmaske 9 Kacheln (576 px, `scale = 0.5`), Schatten 10 Kacheln (320 px, `scale = 1`); der Schatten-shift
in `prototypes/carryall.lua` ist der des Ornithopters mal 1,25 (0,41 statt 0,33 Kacheln). Aus `blaetter/` kommen
`carryall-base.png`, `carryall-mask.png` und `carryall-shadow.png` nach `graphics/entity/carryall/`, das Symbol
`carryall-icon-64.png` nach `graphics/icons/carryall.png`.

Die Leitstelle (4×4 Kacheln) hat eine Ansicht: Rumpf 7 Kacheln (448 px, `scale = 0.5`), Schatten 8 Kacheln (256 px,
`scale = 1`); `pack.py` legt bei einem Bild ein Blatt ohne leere Spalten an. `depot-base.png` und `depot-shadow.png`
kommen nach `graphics/entity/depot/`, `depot-icon-64.png` nach `graphics/icons/depot.png`, `depot-icon-256.png` nach
`graphics/technology/depot.png`.

## Thumper, Wurmzahn, Revierkunde (Grafik-Phase, docs/plan-grafik.md)

```
python thumper-modell.py roh3 base
python thumper-modell.py roh3 shadow
python thumper-modell.py roh3 icon
python pack.py roh3 blaetter3 thumper
python zahn-modell.py roh4 icon
python pack.py roh4 blaetter4 zahn
python revierkunde-modell.py roh5 icon
python pack.py roh5 blaetter5 revierkunde
```

Gebäude mit Animation nutzen `szene.render(frames=…, pose=…)`: eine Ansicht, vor jedem Bild stellt `pose(i)` die
beweglichen Teile, die Dateien heißen wie bei den Richtungen `<modus>-<nn>.png`. Der Thumper hat 16 Bilder
(13 Bilder Gewicht hochziehen, 2 Bilder Fall, Sandring in den Bildern 15, 0, 1), Rumpf 4 Kacheln (256 px,
`scale = 0.5`), Schatten 5 Kacheln (160 px, `scale = 1`), Bildmitte = Bodenpunkt, 8 Bilder je Zeile. Der Sandring
wirft keinen Schatten (`visible_shadow = False`). `thumper-base.png` und `thumper-shadow.png` kommen nach
`graphics/entity/thumper/`, `thumper-icon-64.png` nach `graphics/icons/thumper.png`, `thumper-icon-256.png` nach
`graphics/technology/thumper.png`. `zahn-icon-64.png` wird `graphics/icons/worm-tooth.png`; `revierkunde-icon-256.png`
und `-64.png` werden `graphics/technology/territory-survey.png` und `graphics/icons/territory-survey.png`.

Prüfen nach jedem Einbau: `tools/check/bilder.py` mit dem Dump von `datastage.py --dump` (Ausschnitte passen in die
Dateien, Symbolgrößen stimmen) und `tools/check/base_paths.py`.

## Flügelschlag Ornithopter und Carryall (Grafik-Phase)

```
python ornithopter-modell.py roh6 base 64 rumpf
python ornithopter-modell.py roh7 base 64 fluegel
python ornithopter-modell.py roh7 mask 64 fluegel
python pack.py roh6 blaetter6 ornithopter
python pack.py roh7 blaetter6 ornithopter-wings 16
```

(Carryall gleich, Name `carryall`.) Das 4. Argument wählt den Teil: `rumpf` rendert den Rumpf ohne Flügel (die Flügel
werfen weiter Schatten auf ihn), `fluegel` nur Flügel samt Holm, Rippen, Streifen und Positionslicht, der Rumpf ist
Aussparung (verdeckt die Flügel dahinter). `szene.fluegel_vorbereiten()` hängt jeden Flügel an ein Gelenk an der Stelle
von `hinge<paar><seite>`; Bild f von 4 schlägt um 22° · sin(2πf/4), vorderes und hinteres Paar gegenläufig, Bild 0 ist
die Ruhelage. `schlag` mit Modus `vorschau` zeigt alles mit Flügelschlag.

Blätter: Rumpf wie bisher (Ornithopter 448 px, Carryall 576 px, `scale = 0.5`, 8 je Zeile, `repeat_count = 4`), Flügel und
Flügel-Farbmaske in halber Auflösung (224 bzw. 288 px, `scale = 1`), 4 Bilder je Richtung hintereinander, 16 Bilder je
Zeile (`frame_count = 4`, `line_length = 16`). Eine eigene Rumpf-Farbmaske gibt es nicht mehr, die Spielerfarbe sitzt nur
an den Flügelspitzen. Der Schatten bleibt das Standbild (`repeat_count = 4`).

## Symbole der Spice-Kette (Grafik-Phase)

```
python symbole-modell.py roh8-NAME icon NAME
python pack.py roh8-NAME blaetter8 NAME
```

NAME: `spice-sand`, `melange`, `spice-essence`, `spice-briquette`, `spice-science-pack`. `NAME-icon-64.png` kommt nach
`graphics/icons/NAME.png` (Item, beim Spice-Sand auch die Ressource). Raffinerie und Windfalle behalten ihre getönten
Vanilla-Symbole, weil ihre Gebäude Vanilla-Grafik zeigen.
