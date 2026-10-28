# Spice-Ernter aus einfachen Formen, gerendert wie Factorio-Fahrzeuge (Ortho, 45 Grad, Licht von links oben).
# Aufruf: python ernter-modell.py ROH_DIR MODUS [richtungen]  (Python mit dem Modul bpy, pip install bpy)
# MODUS: vorschau (mit Schatten, 7 Kacheln), base (ohne Boden), shadow (nur Schatten, 32 px je Kachel),
#        mask (Farbmaske für die Spielerfarbe), icon (eine Schrägansicht für Symbole).
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import szene
from szene import mat, box, cyl, slab

# Bildbreite in Kacheln je Modus; Seitenschürzen und Rückenplatten in Spielerfarbe.
szene.start("harvester", {"vorschau": 7, "shadow": 8, "default": 6}, ("skirt", "plate"))


HULL = mat("hull", (0.085, 0.08, 0.075), 0.7, 0.3)       # dunkles, warmes Metall
HULL2 = mat("hull2", (0.14, 0.13, 0.115), 0.7, 0.3)      # hellere Panzerplatten
STEEL = mat("steel", (0.06, 0.06, 0.06), 0.5, 0.5)
TRACK = mat("track", (0.06, 0.055, 0.05), 0.9, 0.3)
GLASS = mat("glass", (0.08, 0.10, 0.10), 0.1, 0.2, False)
LAMP = mat("lamp", (1.0, 0.85, 0.5), 0.3, 0.0, False)
LAMP.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (1.0, 0.75, 0.35, 1)
LAMP.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 4.0
MAW = mat("maw", (0.02, 0.02, 0.02), 0.9, 0.0, False)

# Maße in Kacheln (1 Kachel = 1 m). Vorne = -Y (Factorio-Norden). Breit und flach: 2,4 x 3,2.
L, W = 3.2, 2.4
# Vier Raupen an den Ecken, schräg gestellte Laufwerke
for sx in (-1, 1):
    for sy in (-1, 1):
        x = sx * (W / 2 - 0.25)
        y = sy * 0.85
        slab(f"track{sx}{sy}", (x - 0.25, x + 0.25, y - 0.62, y + 0.62), (x - 0.25, x + 0.25, y - 0.5, y + 0.5),
             0.0, 0.42, TRACK, 0.06)
        for k in range(-2, 3):
            cyl(f"wheel{sx}{sy}{k}", 0.11, 0.52, (x, y + k * 0.24, 0.18), STEEL, rot=(0, math.pi / 2, 0), verts=12)
        box(f"fender{sx}{sy}", (0.56, 1.3, 0.06), (x, y, 0.47), HULL2, 0.02)
# Rumpf: breiter, flacher Keil über den Raupen, vorne lang abgeschrägt
slab("hull", (-W / 2 + 0.05, W / 2 - 0.05, -L / 2 + 0.35, L / 2 - 0.1), (-W / 2 + 0.35, W / 2 - 0.35, -L / 2 + 0.95, L / 2 - 0.35),
     0.5, 1.15, HULL, 0.05)
# Rückenplatte mit Panzerplatten
slab("deck", (-W / 2 + 0.35, W / 2 - 0.35, -L / 2 + 0.95, L / 2 - 0.35), (-W / 2 + 0.5, W / 2 - 0.5, -L / 2 + 1.15, L / 2 - 0.5),
     1.15, 1.32, HULL2, 0.03)
for k in range(4):
    box(f"plate{k}", (W - 1.15, 0.28, 0.04), (0, -0.25 + k * 0.33, 1.33), HULL, 0.015)
# Seitenschürzen schräg über den Raupen
for sx in (-1, 1):
    slab(f"skirt{sx}", (sx * (W / 2 - 0.02) - 0.03, sx * (W / 2 - 0.02) + 0.03, -L / 2 + 0.45, L / 2 - 0.15),
         (sx * (W / 2 - 0.2) - 0.03, sx * (W / 2 - 0.2) + 0.03, -L / 2 + 0.6, L / 2 - 0.25), 0.55, 0.95, HULL2, 0.01)
# Ansaugmaul vorne: breiter, dunkler Schlitz unter einer Lippe, mit Zähnen
slab("lip", (-W / 2 + 0.25, W / 2 - 0.25, -L / 2 + 0.05, -L / 2 + 0.4), (-W / 2 + 0.3, W / 2 - 0.3, -L / 2 + 0.25, -L / 2 + 0.45),
     0.32, 0.5, HULL2, 0.02)
box("maw", (W - 0.6, 0.12, 0.2), (0, -L / 2 + 0.2, 0.22), MAW, 0.0)
for k in range(9):
    box(f"tooth{k}", (0.06, 0.16, 0.08), (-0.8 + k * 0.2, -L / 2 + 0.07, 0.12), STEEL, 0.01)
# Kanzel vorne oben: schmales Fensterband
slab("cab", (-0.45, 0.45, -L / 2 + 0.95, -L / 2 + 1.35), (-0.38, 0.38, -L / 2 + 1.05, -L / 2 + 1.3), 1.15, 1.42, HULL2, 0.02)
box("window", (0.62, 0.03, 0.08), (0, -L / 2 + 0.99, 1.3), GLASS, 0.0, rot=(math.radians(-25), 0, 0))
for sx in (-1, 1):
    box(f"lamp{sx}", (0.12, 0.03, 0.05), (sx * 0.75, -L / 2 + 0.58, 0.7), LAMP, 0.0, rot=(math.radians(-40), 0, 0))
    box(f"lampt{sx}", (0.06, 0.03, 0.04), (sx * 0.25, -L / 2 + 0.98, 1.38), LAMP, 0.0)
# Heck: zwei Auswurfschlote, die Sand ausblasen
for sx in (-1, 1):
    cyl(f"vent{sx}", 0.14, 0.45, (sx * 0.45, L / 2 - 0.5, 1.45), STEEL, verts=16)
    cyl(f"ventin{sx}", 0.1, 0.05, (sx * 0.45, L / 2 - 0.5, 1.68), MAW, verts=16)
# Klammerschienen für den Lastenflieger entlang des Rückens
for sx in (-1, 1):
    box(f"rail{sx}", (0.07, 1.5, 0.07), (sx * 0.58, 0.05, 1.38), STEEL, 0.01)
    for sy in (-1, 1):
        box(f"clamp{sx}{sy}", (0.14, 0.14, 0.12), (sx * 0.58, 0.05 + sy * 0.7, 1.42), STEEL, 0.02)

szene.render()
