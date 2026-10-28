# Carryall: unbemannter Lastenflieger der Leitstelle. Abgeleitet vom Ornithopter (ornithopter-modell.py), 1,25-mal so
# groß, dunkles Metall, geschlossene gepanzerte Nase statt Glaskanzel, vier Triebwerke und ein breiter Greifrahmen für
# den Ernter. Aufruf wie beim Ornithopter: python carryall-modell.py ROH_DIR MODUS [richtungen]
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import szene
from szene import mat, box, cyl, slab, prism

LIFT = 0.6
K = 1.25    # Maßstab gegenüber dem Ornithopter
# Spannweite gut 5,5 Kacheln, mit V-Form ragen die Spitzen knapp 4 Kacheln aus der Mitte: Rumpf 9, Schatten 10 Kacheln.
szene.start("carryall", {"vorschau": 9, "shadow": 10, "default": 9}, ("stripe",))

BODY = mat("body", (0.12, 0.11, 0.10), 0.55, 0.5)       # dunkles Metall
BODY2 = mat("body2", (0.07, 0.065, 0.06), 0.6, 0.5)     # Rahmen und Gelenke, noch dunkler
WING = mat("wing", (0.20, 0.18, 0.15), 0.55, 0.35)      # Flügelflächen
STEEL = mat("steel", (0.05, 0.05, 0.05), 0.5, 0.6)
GLOW = mat("glow", (1.0, 0.7, 0.35), 0.3, 0.0, False)
GLOW.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (1.0, 0.6, 0.25, 1)
GLOW.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 3.0


def k(*v):
    return tuple(x * K for x in v)


# Rumpf: gepanzerte Nase, breite Mittelkabine (Antrieb und Seilwinden), Ausleger mit Leitwerk. Vorne = -Y.
slab("nose", k(-0.3, 0.3, -1.6, -1.5), k(-0.42, 0.42, -1.0, -0.9), -0.15 * K, 0.22 * K, BODY, 0.05)
slab("nosecap", k(-0.22, 0.22, -1.5, -1.0), k(-0.12, 0.12, -1.35, -1.05), 0.2 * K, 0.3 * K, BODY2, 0.04)
slab("cabin", k(-0.5, 0.5, -1.0, 0.5), k(-0.4, 0.4, -0.9, 0.4), -0.28 * K, 0.32 * K, BODY, 0.05)
slab("spine", k(-0.16, 0.16, -0.7, 0.45), k(-0.1, 0.1, -0.65, 0.4), 0.32 * K, 0.46 * K, BODY2, 0.02)
slab("boom", k(-0.24, 0.24, 0.5, 1.5), k(-0.14, 0.14, 0.5, 1.45), -0.12 * K, 0.16 * K, BODY, 0.03)
for sx in (-1, 1):
    box(f"fin{sx}", k(0.05, 0.4, 0.34), k(sx * 0.16, 1.4, 0.26), BODY2, 0.01, rot=(0, sx * math.radians(25), 0))
box("tailplane", k(1.0, 0.24, 0.035), k(0, 1.43, 0.05), BODY2, 0.01)
# Vier Triebwerke, je zwei an jeder Seite, Glut am Auslass
for sx in (-1, 1):
    for y in (-0.35, 0.2):
        cyl(f"engine{sx}{y}", 0.13 * K, 0.6 * K, k(sx * 0.6, y, -0.05), BODY2, rot=(math.pi / 2, 0, 0), verts=16)
        cyl(f"exhaust{sx}{y}", 0.09 * K, 0.04 * K, k(sx * 0.6, y + 0.31, -0.05), GLOW, rot=(math.pi / 2, 0, 0), verts=16)
# Zwei Flügelpaare wie beim Ornithopter, Spielerfarbe an den Spitzen
ROOT_X = 0.5
for pair, (y, span, chord, sweep) in enumerate(((-0.5, 2.2, 0.55, -0.25), (0.25, 1.9, 0.48, 0.2))):
    for sx in (-1, 1):
        tip = chord * 0.45
        outline = [(0, -chord / 2), (span, sweep - tip / 2), (span, sweep + tip / 2), (0, chord / 2)]
        outline = [(x * K, yy * K) for x, yy in outline]
        if sx < 0:
            outline = [(-x, yy) for x, yy in reversed(outline)]
        rot = (0, sx * math.radians(-7), 0)
        loc = k(sx * ROOT_X, y, 0.22)
        prism(f"wing{pair}{sx}", outline, -0.014, 0.014, WING, loc, rot, 0.005)
        spar = [(0, -chord / 2), (span, sweep - tip / 2), (span, sweep - tip / 2 + 0.05), (0, -chord / 2 + 0.08)]
        prism(f"spar{pair}{sx}", [(sx * x * K, yy * K) for x, yy in spar][::sx], -0.035, 0.035, BODY2, loc, rot, 0.005)
        for n in range(1, 6):
            f = n / 6
            x = span * f
            y0 = -chord / 2 + (sweep - tip / 2 + chord / 2) * f
            y1 = chord / 2 + (sweep + tip / 2 - chord / 2) * f
            rib = [(x - 0.015, y0), (x + 0.015, y0), (x + 0.015, y1), (x - 0.015, y1)]
            prism(f"rib{pair}{sx}{n}", [(sx * xx * K, yy * K) for xx, yy in rib][::sx], -0.02, 0.02, BODY2, loc, rot, 0.0)
        f0 = 0.72
        s0 = [(span * f0, -chord / 2 + (sweep - tip / 2 + chord / 2) * f0),
              (span * 0.92, -chord / 2 + (sweep - tip / 2 + chord / 2) * 0.92),
              (span * 0.92, chord / 2 + (sweep + tip / 2 - chord / 2) * 0.92),
              (span * f0, chord / 2 + (sweep + tip / 2 - chord / 2) * f0)]
        prism(f"stripe{pair}{sx}", [(sx * xx * K, yy * K) for xx, yy in s0][::sx], -0.018, 0.018, WING, loc, rot, 0.0)
        cyl(f"hinge{pair}{sx}", 0.09 * K, 0.2 * K, k(sx * ROOT_X, y, 0.22), STEEL, rot=(math.pi / 2, 0, 0), verts=12)
# Greifrahmen unter dem Rumpf: zwei Längsträger in Ernterbreite, vier Klauen an den Ecken
for sx in (-1, 1):
    box(f"rail{sx}", k(0.07, 1.5, 0.07), k(sx * 0.55, -0.2, -0.34), STEEL, 0.01)
    for sy in (-1, 1):
        box(f"talon{sx}{sy}", k(0.06, 0.06, 0.26), k(sx * 0.55, -0.2 + sy * 0.68, -0.46), STEEL, 0.01)
box("crossbar", k(1.2, 0.08, 0.07), k(0, -0.2, -0.3), STEEL, 0.01)
# Positionslichter an den Flügelspitzen
for sx in (-1, 1):
    box(f"tip{sx}", k(0.06, 0.06, 0.04), k(sx * (ROOT_X + 2.2), -0.75, 0.5), GLOW, 0.0)

szene.render(lift=LIFT)
