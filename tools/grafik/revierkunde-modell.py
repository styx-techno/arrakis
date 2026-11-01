# Forschungsbild „Revierkunde“: Kartentafel mit Wurm-Revieren (ruhig/normal/wild, dunkle Grenzen), darüber ein
# Sandwurm-Rücken, der aus dem wilden Revier auftaucht, und Markierungsfähnchen.
# Aufruf: python revierkunde-modell.py ROH_DIR icon   (danach pack.py ... revierkunde; Bild icon-256)
import math, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from PIL import Image, ImageDraw, ImageFilter
import szene
from szene import mat, box, cyl

szene.start("revierkunde", {"default": 4.1}, ())

# Kartenbild: Voronoi-Reviere, Farbe nach Abstand zur Startecke (links unten ruhig, rechts oben wild)
N = 512
rnd = random.Random(7)
seeds = [(rnd.uniform(0, N), rnd.uniform(0, N)) for _ in range(9)]
CALM, NORMAL, WILD = (150, 150, 96), (196, 152, 88), (176, 84, 52)


def kind(p):
    d = math.hypot(p[0], N - p[1]) / (N * 1.414)
    return CALM if d < 0.38 else NORMAL if d < 0.68 else WILD


owner = [[0] * N for _ in range(N)]
img = Image.new("RGB", (N, N))
px = img.load()
for y in range(N):
    for x in range(N):
        k = min(range(len(seeds)), key=lambda i: (seeds[i][0] - x) ** 2 + (seeds[i][1] - y) ** 2)
        owner[y][x] = k
        c = kind(seeds[k])
        dune = 10 * math.sin((x * 0.7 + y) * 0.09 + math.sin(x * 0.03) * 2)
        px[x, y] = tuple(int(max(0, min(255, v + dune))) for v in c)
edge = Image.new("L", (N, N), 0)
ep = edge.load()
for y in range(1, N - 1):
    for x in range(1, N - 1):
        if owner[y][x] != owner[y][x + 1] or owner[y][x] != owner[y + 1][x]:
            ep[x, y] = 255
edge = edge.filter(ImageFilter.MaxFilter(5))
img.paste((52, 36, 24), mask=edge)
ImageDraw.Draw(img).rectangle((0, 0, N - 1, N - 1), outline=(52, 36, 24), width=10)
tex_path = os.path.join(szene.OUT, "karte.png")
img.save(tex_path)

MAP = bpy.data.materials.new("map")
MAP.use_nodes = True
nt = MAP.node_tree
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = bpy.data.images.load(tex_path)
nt.links.new(tex.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85

FRAME = mat("frame", (0.16, 0.13, 0.10), 0.5, 0.5)
WORM = mat("worm", (0.47, 0.38, 0.27), 0.7, 0.0)
MOUTH = mat("mouth", (0.18, 0.08, 0.05), 0.5, 0.0, False)
FLAG = mat("flag", (0.85, 0.55, 0.12), 0.5, 0.0, False)
POLE = mat("pole", (0.2, 0.2, 0.2), 0.4, 0.8, False)

# Tafel (mit UV-Karte) und Rahmen
bpy.ops.mesh.primitive_plane_add(size=2.6, location=(0, 0, 0.12))
plate = bpy.context.object
plate.name = "karte"
plate.data.materials.append(MAP)
plate.parent = szene.root
box("rahmen", (2.8, 2.8, 0.12), (0, 0, 0.05), FRAME, 0.03)

# Wurmrücken: Bogen über dem wilden Revier, quer zur Blickrichtung des Symbols
cx, cy, R = 0.5, 0.5, 0.42
cu = bpy.data.curves.new("wurm", "CURVE")
cu.dimensions = "3D"
cu.bevel_depth = 0.13
cu.bevel_resolution = 6
sp = cu.splines.new("POLY")
pts = []
for k in range(25):
    a = math.radians(200 * k / 24 - 10)
    d = math.cos(a) * R
    pts.append((cx + d * 0.707, cy + d * 0.707, 0.1 + math.sin(a) * R * 1.1, 1))
sp.points.add(len(pts) - 1)
for pt, co in zip(sp.points, pts):
    pt.co = co
worm = bpy.data.objects.new("wurm", cu)
szene.scene.collection.objects.link(worm)
worm.data.materials.append(WORM)
worm.parent = szene.root
# Ringfurchen: dunkle Bänder quer über den Rücken
for k in range(3, 22, 3):
    x, y, z, _ = pts[k]
    bpy.ops.mesh.primitive_torus_add(major_radius=0.135, minor_radius=0.016, location=(x, y, z))
    t = bpy.context.object
    a = math.radians(200 * k / 24 - 10)
    t.rotation_mode = "QUATERNION"
    import mathutils
    tang = mathutils.Vector((-math.sin(a) * R * 0.707, -math.sin(a) * R * 0.707, math.cos(a) * R * 1.1)).normalized()
    t.rotation_quaternion = mathutils.Vector((0, 0, 1)).rotation_difference(tang)
    t.data.materials.append(MOUTH)
    t.parent = szene.root
cyl("maul", 0.12, 0.03, (cx + R * 0.707 * math.cos(math.radians(-10)), cy + R * 0.707 * math.cos(math.radians(-10)), 0.125), MOUTH, verts=20)

# Fähnchen an den Revieren
for i, (x, y) in enumerate(((-0.75, -0.75), (-0.2, 0.1), (0.55, -0.35))):
    cyl(f"stab{i}", 0.02, 0.5, (x, y, 0.37), POLE, verts=8)
    box(f"fahne{i}", (0.02, 0.22, 0.14), (x, y - 0.11, 0.55), FLAG, 0.0)

szene.render(frames=1, pose=lambda i: None, icon_frame=0)
