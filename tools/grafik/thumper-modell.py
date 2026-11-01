# Thumper: Pochpfahl im Sand (2×2 Kacheln). Dreibein mit Ankerdornen, Gehäuse mit Feder, Führungsstange; ein
# Schlaggewicht wird langsam hochgezogen und fällt auf den Amboss, beim Aufschlag springt ein Sandring auf.
# Aufruf: python thumper-modell.py ROH_DIR MODUS   (MODUS vorschau/base/shadow/icon; 16 Bilder, eine Ansicht)
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import szene
from szene import mat, box, cyl, slab

FRAMES = 16
# Bildbreite 4 Kacheln: der Pfahl ragt 1,7 Kacheln hoch, die Bildmitte ist der Bodenpunkt (kein shift).
szene.start("thumper", {"vorschau": 4, "shadow": 5, "default": 4}, ())

DARK = mat("dark", (0.10, 0.095, 0.085), 0.6, 0.5)
METAL = mat("metal", (0.24, 0.21, 0.17), 0.45, 0.7)
BRASS = mat("brass", (0.42, 0.30, 0.14), 0.35, 0.8)
MARK = mat("mark", (0.75, 0.48, 0.12), 0.6, 0.0)
SAND = mat("sand", (0.50, 0.37, 0.22), 0.95, 0.0, False)
GLOW = mat("glow", (1.0, 0.45, 0.2), 0.3, 0.0, False)
GLOW.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (1.0, 0.35, 0.12, 1)
GLOW.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 5.0
DUST = mat("dust", (0.82, 0.68, 0.47), 1.0, 0.0, False)

# Aufgewühlter Sand um den Fuß (flacher Kegel) – gehört zum Bild, damit der Pfahl im Boden steckt.
bpy.ops.mesh.primitive_cone_add(vertices=40, radius1=0.85, radius2=0.45, depth=0.05, location=(0, 0, 0.02))
mound = bpy.context.object
mound.name = "mound"
mound.data.materials.append(SAND)
bpy.ops.object.shade_smooth()
mound.parent = szene.root

# Dreibein: drei schräge Streben mit Ankerdornen
for k in range(3):
    a = math.radians(90 + 120 * k)
    cx, cy = math.cos(a) * 0.38, math.sin(a) * 0.38
    leg = box(f"leg{k}", (0.07, 0.07, 0.75), (cx, cy, 0.32), DARK, 0.01,
              rot=(math.sin(a) * math.radians(28), -math.cos(a) * math.radians(28), 0))
    cyl(f"foot{k}", 0.09, 0.06, (math.cos(a) * 0.55, math.sin(a) * 0.55, 0.06), METAL, verts=12)
# Amboss: breite Scheibe am Boden, darauf das Gehäuse
cyl("anvil", 0.26, 0.12, (0, 0, 0.1), METAL, verts=32)
cyl("housing", 0.15, 0.55, (0, 0, 0.43), DARK, verts=24)
cyl("band", 0.155, 0.08, (0, 0, 0.6), MARK, verts=24)
# Feder um das Gehäuse (Ringe)
for j in range(6):
    bpy.ops.mesh.primitive_torus_add(major_radius=0.19, minor_radius=0.022, location=(0, 0, 0.2 + j * 0.07),
                                     major_segments=24, minor_segments=8)
    t = bpy.context.object
    t.name = f"spring{j}"
    t.rotation_euler = (math.radians(6), 0, 0)
    t.data.materials.append(BRASS)
    t.parent = szene.root
# Führungsstange mit Kopf, Kurbelkasten und Warnlicht
cyl("rod", 0.045, 0.95, (0, 0, 1.13), METAL, verts=12)
box("crank", (0.2, 0.16, 0.22), (0.2, 0.0, 0.5), METAL, 0.02)
cyl("crankwheel", 0.1, 0.04, (0.31, 0.0, 0.52), BRASS, rot=(0, math.pi / 2, 0), verts=16)
cyl("cap", 0.1, 0.06, (0, 0, 1.6), DARK, verts=16)
cyl("lamp", 0.05, 0.08, (0, 0, 1.67), GLOW, verts=12)

# Schlaggewicht: wandert an der Stange
hammer = []
hammer.append(cyl("weight", 0.2, 0.26, (0, 0, 0), DARK, verts=24))
hammer.append(cyl("weightband", 0.205, 0.07, (0, 0, 0), MARK, verts=24))
LOW, HIGH = 0.84, 1.36

# Sandring beim Aufschlag (wirft keinen Schatten)
bpy.ops.mesh.primitive_torus_add(major_radius=0.75, minor_radius=0.08, location=(0, 0, 0.05),
                                 major_segments=48, minor_segments=8)
ring = bpy.context.object
ring.name = "fxring"
ring.data.materials.append(DUST)
ring.parent = szene.root
ring.visible_shadow = False

# Höhe des Gewichts je Bild (0 unten, 1 oben): 13 Bilder langsam hoch, kurz halten, 2 Bilder Fall.
LIFT = [0.0, 0.0, 0.06, 0.14, 0.23, 0.32, 0.41, 0.5, 0.59, 0.68, 0.77, 0.86, 0.94, 1.0, 0.45, 0.0]
# Sandring: Größe und Deckkraft je Bild (nur kurz nach dem Aufschlag in Bild 15)
RING = {15: (0.9, 1.0), 0: (1.15, 0.7), 1: (1.35, 0.35)}
bsdf = DUST.node_tree.nodes["Principled BSDF"]


def pose(i):
    z = LOW + (HIGH - LOW) * LIFT[i]
    hammer[0].location.z = z
    hammer[1].location.z = z
    if i in RING:
        s, alpha = RING[i]
        ring.hide_render = False
        ring.scale = (s, s, 0.6 + 0.4 * alpha)
        bsdf.inputs["Alpha"].default_value = alpha
    else:
        ring.hide_render = True


szene.render(frames=FRAMES, pose=pose, icon_frame=13)
