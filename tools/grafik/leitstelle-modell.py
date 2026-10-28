# Ornithopter-Leitstelle: flacher Bau 4×4 Kacheln auf Fels mit Landeplatz, Leitturm, Mast und Treibstofftanks.
# Aufruf: python leitstelle-modell.py ROH_DIR MODUS [richtungen]; Gebäude haben eine Ansicht (richtungen 1).
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import szene
from szene import mat, box, cyl, slab

# Turm und Mast ragen gut 2 Kacheln über den Bau hinaus; 7 Kacheln breit reichen für Bau, Turm und Schatten.
szene.start("leitstelle", {"vorschau": 7, "shadow": 8, "default": 7}, ("stripe",))

CONCRETE = mat("concrete", (0.36, 0.32, 0.27), 0.85, 0.0)       # sandfarbener Beton
DARK = mat("dark", (0.10, 0.095, 0.085), 0.6, 0.5)              # dunkles Metall wie Carryall
METAL = mat("metal", (0.22, 0.20, 0.17), 0.5, 0.6)
MARK = mat("mark", (0.75, 0.55, 0.15), 0.6, 0.0)                # gelbe Landemarkierung
GLASS = mat("glass", (0.05, 0.09, 0.10), 0.08, 0.3, False)
GLOW = mat("glow", (1.0, 0.45, 0.2), 0.3, 0.0, False)
GLOW.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (1.0, 0.35, 0.15, 1)
GLOW.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 4.0

# Fundament 4×4, Mitte im Ursprung, vorne = -Y (Norden)
slab("base", (-2.0, 2.0, -2.0, 2.0), (-1.9, 1.9, -1.9, 1.9), 0.0, 0.18, CONCRETE, 0.03)
# Landeplatz: Kreis mit Ring und Kreuz, leicht erhöht, links vorn
cyl("pad", 1.05, 0.04, (-0.55, -0.45, 0.2), DARK, verts=48)
cyl("ring", 0.95, 0.045, (-0.55, -0.45, 0.205), MARK, verts=48)
cyl("ringin", 0.85, 0.05, (-0.55, -0.45, 0.21), DARK, verts=48)
box("cross1", (0.9, 0.14, 0.02), (-0.55, -0.45, 0.235), MARK, 0.0)
box("cross2", (0.14, 0.9, 0.02), (-0.55, -0.45, 0.235), MARK, 0.0)
# Leitturm rechts hinten: Sockel, Kanzel mit Glas, Dach, Mast mit Warnlicht
box("tower", (0.9, 0.9, 1.2), (1.25, 1.2, 0.78), METAL, 0.04)
slab("cab", (-0.6, 0.6, -0.6, 0.6), (-0.5, 0.5, -0.5, 0.5), 1.38, 1.9, GLASS, 0.03)
for sx in (-1, 1):
    for sy in (-1, 1):
        box(f"post{sx}{sy}", (0.08, 0.08, 0.52), (1.25 + sx * 0.52, 1.2 + sy * 0.52, 1.64), DARK, 0.01)
slab("roof", (-0.68, 0.68, -0.68, 0.68), (-0.55, 0.55, -0.55, 0.55), 1.9, 2.02, DARK, 0.03)
cyl("mast", 0.04, 1.1, (1.25, 1.2, 2.55), METAL, verts=8)
cyl("lamp", 0.09, 0.12, (1.25, 1.2, 3.12), GLOW, verts=12)
# Treibstofftanks rechts vorn, liegend, mit Spielerfarben-Band
for i, y in enumerate((-1.45, -0.85)):
    cyl(f"tank{i}", 0.26, 1.4, (1.15, y, 0.46), METAL, rot=(0, math.pi / 2, 0), verts=24)
    cyl(f"stripe{i}", 0.27, 0.14, (1.15, y, 0.46), MARK, rot=(0, math.pi / 2, 0), verts=24)
# Ladekisten links hinten (Ersatzteile, Ernter-Treibstoff)
box("crate1", (0.55, 0.55, 0.45), (-1.35, 1.35, 0.4), DARK, 0.03)
box("crate2", (0.5, 0.5, 0.4), (-0.7, 1.4, 0.38), METAL, 0.03)
box("crate3", (0.45, 0.45, 0.35), (-1.35, 0.75, 0.36), METAL, 0.03)

szene.render()
