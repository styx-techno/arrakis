# Ornithopter aus einfachen Formen: schlanker Rumpf mit Kanzel, zwei Flügelpaare, Triebwerke, Greifklauen.
# Aufruf: python ornithopter-modell.py ROH_DIR MODUS [richtungen]  (Python mit dem Modul bpy, pip install bpy)
# MODUS wie beim Ernter (szene.py). Der Rumpf sitzt mit seiner Mitte im Ursprung: Das ist der Rumpfpunkt des
# Spider-Fahrzeugs (prototypes/ornithopter.lua). Den Abstand des Schattens zur Flughöhe setzt das Spiel selbst; das
# Schattenbild entsteht deshalb nur knapp über dem Boden (LIFT), damit die Klauen nicht im Boden stecken.
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import szene
from szene import mat, box, cyl, slab, prism

LIFT = 0.6
# Spannweite gut 4,4 Kacheln; mit der V-Form ragen die Flügelspitzen gut 3 Kacheln aus der Mitte: Rumpf 7, Schatten 8 Kacheln.
szene.start("ornithopter", {"vorschau": 7, "shadow": 8, "default": 7}, ("stripe",))

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
# Zwei Flügelpaare wie bei einer Libelle: vorne und hinten, je Seite ein langer, spitz zulaufender Flügel mit Rippen
# und einem Streifen in Spielerfarbe an der Spitze. Leicht nach oben angestellt (V-Form), das hintere Paar kürzer.
ROOT_X = 0.4
for pair, (y, span, chord, sweep) in enumerate(((-0.45, 2.2, 0.5, -0.25), (0.25, 1.9, 0.44, 0.2))):
    for sx in (-1, 1):
        tip = chord * 0.45
        outline = [(0, -chord / 2), (span, sweep - tip / 2), (span, sweep + tip / 2), (0, chord / 2)]
        if sx < 0:
            outline = [(-x, yy) for x, yy in reversed(outline)]
        rot = (0, sx * math.radians(-7), 0)
        loc = (sx * ROOT_X, y, 0.22)
        prism(f"wing{pair}{sx}", outline, -0.012, 0.012, WING, loc, rot, 0.005)
        # Vorderkante als Holm, Rippen quer
        prism(f"spar{pair}{sx}", [(sx * x, yy) for x, yy in ((0, -chord / 2), (span, sweep - tip / 2), (span, sweep - tip / 2 + 0.05),
                                                              (0, -chord / 2 + 0.07))][::sx], -0.03, 0.03, BODY2, loc, rot, 0.005)
        for k in range(1, 6):
            f = k / 6
            x = span * f
            y0 = -chord / 2 + (sweep - tip / 2 + chord / 2) * f
            y1 = chord / 2 + (sweep + tip / 2 - chord / 2) * f
            prism(f"rib{pair}{sx}{k}", [(sx * xx, yy) for xx, yy in ((x - 0.015, y0), (x + 0.015, y0), (x + 0.015, y1), (x - 0.015, y1))][::sx],
                  -0.018, 0.018, BODY2, loc, rot, 0.0)
        f0 = 0.72
        s0 = [(span * f0, -chord / 2 + (sweep - tip / 2 + chord / 2) * f0), (span * 0.92, -chord / 2 + (sweep - tip / 2 + chord / 2) * 0.92),
              (span * 0.92, chord / 2 + (sweep + tip / 2 - chord / 2) * 0.92), (span * f0, chord / 2 + (sweep + tip / 2 - chord / 2) * f0)]
        prism(f"stripe{pair}{sx}", [(sx * xx, yy) for xx, yy in s0][::sx], -0.016, 0.016, WING, loc, rot, 0.0)
        cyl(f"hinge{pair}{sx}", 0.08, 0.18, (sx * ROOT_X, y, 0.22), STEEL, rot=(math.pi / 2, 0, 0), verts=12)
# Greifklauen unter dem Rumpf für den Ernter
for sy in (-1, 1):
    box(f"claw{sy}", (0.7, 0.06, 0.06), (0, -0.25 + sy * 0.35, -0.32), STEEL, 0.01)
    for sx in (-1, 1):
        box(f"talon{sy}{sx}", (0.05, 0.05, 0.22), (sx * 0.33, -0.25 + sy * 0.35, -0.42), STEEL, 0.01)
# Positionslichter an den Flügelspitzen
for sx in (-1, 1):
    box(f"tip{sx}", (0.06, 0.06, 0.04), (sx * (ROOT_X + 2.2), -0.7, 0.5), GLOW, 0.0)

szene.render(lift=LIFT)
