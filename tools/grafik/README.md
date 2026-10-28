# Grafik

Die Fahrzeuggrafiken entstehen aus Skripten: Blender baut das Modell aus einfachen Formen und rendert es, `pack.py`
setzt die Bilder zu Spritesheets zusammen. Es braucht kein Blender-Programm, nur Python 3.11 mit den Modulen `bpy`
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
