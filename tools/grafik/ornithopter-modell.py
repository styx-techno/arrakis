# Ornithopter aus einfachen Formen: schlanker Rumpf mit Kanzel, zwei Flügelpaare, Triebwerke, Greifklauen.
# Aufruf: python ornithopter-modell.py ROH_DIR MODUS [richtungen]  (Python mit dem Modul bpy, pip install bpy)
# MODUS wie beim Ernter (szene.py). Der Rumpf sitzt mit seiner Mitte im Ursprung: Das ist der Rumpfpunkt des
# Spider-Fahrzeugs in Flughöhe (prototypes/ornithopter.lua, height = 3). Der Schatten fällt aus dieser Höhe.
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import szene
from szene import mat, box, cyl, slab

FLIGHT_HEIGHT = 3
# Spannweite gut 4,4 Kacheln; mit dem Schatten aus 3 Kacheln Höhe reicht ein Schattenbild von 9 Kacheln.
szene.start("ornithopter", {"vorschau": 7, "shadow": 9, "default": 6}, ("stripe",))

BODY = mat("body", (0.30, 0.27, 0.22), 0.6, 0.35)        # sandgraues Metall
BODY2 = mat("body2", (0.17, 0.155, 0.135), 0.6, 0.4)     # dunklere Rahmen und Gelenke
WING = mat("wing", (0.40, 0.36, 0.29), 0.55, 0.3)        # Flügelflächen, heller
STEEL = mat("steel", (0.06, 0.06, 0.06), 0.5, 0.5)
GLASS = mat("glass", (0.05, 0.09, 0.10), 0.08, 0.3, False)
GLOW = mat("glow", (1.0, 0.7, 0.35), 0.3, 0.0, False)
GLOW.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (1.0, 0.6, 0.25, 1)
GLOW.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 3.0

# Maße in Kacheln. Vorne = -Y. Rumpf 3,0 lang, 0,8 breit.
# Rumpf: drei Abschnitte, vorne Kanzel, Mitte Kabine, hinten der schmale Ausleger
slab("nose", (-0.3, 0.3, -1.55, -1.5), (-0.38, 0.38, -1.0, -0.9), -0.15, 0.2, BODY, 0.05)
slab("cabin", (-0.42, 0.42, -1.0, 0.45), (-0.32, 0.32, -0.9, 0.35), -0.25, 0.3, BODY, 0.05)
slab("canopy", (-0.3, 0.3, -1.3, -0.45), (-0.2, 0.2, -1.1, -0.55), 0.2, 0.42, GLASS, 0.06)
slab("spine", (-0.12, 0.12, -0.5, 0.4), (-0.08, 0.08, -0.45, 0.35), 0.3, 0.42, BODY2, 0.02)
slab("boom", (-0.22, 0.22, 0.45, 1.45), (-0.12, 0.12, 0.45, 1.4), -0.12, 0.15, BODY, 0.03)
# Leitwerk: zwei schräge Flossen am Ende
for sx in (-1, 1):
    box(f"fin{sx}", (0.04, 0.35, 0.3), (sx * 0.14, 1.35, 0.25), BODY2, 0.01, rot=(0, sx * math.radians(25), 0))
box("tailplane", (0.9, 0.22, 0.03), (0, 1.38, 0.05), BODY2, 0.01)
# Triebwerke seitlich hinten, Glut am Auslass
for sx in (-1, 1):
    cyl(f"engine{sx}", 0.13, 0.7, (sx * 0.5, 0.15, -0.05), BODY2, rot=(math.pi / 2, 0, 0), verts=16)
    cyl(f"exhaust{sx}", 0.09, 0.04, (sx * 0.5, 0.51, -0.05), GLOW, rot=(math.pi / 2, 0, 0), verts=16)
# Zwei Flügelpaare wie bei einer Libelle: vorne und hinten, je Seite ein langer, schmaler Flügel mit Rahmen und
# einem Streifen in Spielerfarbe. Leicht nach oben angestellt (V-Form).
for pair, (y, span, chord, sweep) in enumerate(((-0.45, 2.2, 0.42, -8), (0.25, 2.0, 0.38, 6))):
    for sx in (-1, 1):
        rot = (0, sx * math.radians(-6), sx * math.radians(sweep))
        x = sx * (0.42 + span / 2)
        box(f"wing{pair}{sx}", (span, chord, 0.03), (x, y, 0.22), WING, 0.01, rot=rot)
        box(f"spar{pair}{sx}", (span, 0.05, 0.05), (x, y - chord / 2 + 0.03, 0.24), BODY2, 0.01, rot=rot)
        box(f"stripe{pair}{sx}", (span * 0.25, chord * 0.9, 0.035), (sx * (0.42 + span * 0.8), y, 0.225), WING, 0.0, rot=rot)
        cyl(f"hinge{pair}{sx}", 0.08, 0.18, (sx * 0.42, y, 0.22), STEEL, rot=(math.pi / 2, 0, 0), verts=12)
# Greifklauen unter dem Rumpf für den Ernter
for sy in (-1, 1):
    box(f"claw{sy}", (0.7, 0.06, 0.06), (0, -0.25 + sy * 0.35, -0.32), STEEL, 0.01)
    for sx in (-1, 1):
        box(f"talon{sy}{sx}", (0.05, 0.05, 0.22), (sx * 0.33, -0.25 + sy * 0.35, -0.42), STEEL, 0.01)
# Positionslichter an den Flügelspitzen
for sx in (-1, 1):
    box(f"tip{sx}", (0.06, 0.06, 0.04), (sx * 2.6, -0.45, 0.28), GLOW, 0.0)

szene.render(lift=FLIGHT_HEIGHT)
