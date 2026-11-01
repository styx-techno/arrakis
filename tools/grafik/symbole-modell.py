# Item-Symbole der Spice-Kette: spice-sand, melange, spice-essence, spice-briquette, spice-science-pack.
# Aufruf: python symbole-modell.py ROH_DIR icon NAME   (danach pack.py ROH_DIR ZIEL NAME; Bild NAME-icon-64.png)
import math, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
import szene
from szene import mat, box, cyl

NAME = sys.argv[3]
sys.argv = sys.argv[:3]
szene.start(NAME, {"default": 3.4}, ())
rnd = random.Random(11)


def emit(m, color, strength):
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Emission Color"].default_value = (*color, 1)
    b.inputs["Emission Strength"].default_value = strength
    return m


def glass(name, color, alpha=0.25):
    m = mat(name, color, 0.05, 0.0, False)
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Transmission Weight"].default_value = 0.85
    b.inputs["IOR"].default_value = 1.45
    b.inputs["Alpha"].default_value = 0.6
    return m


def heap(name, r, h, material, bumps=0.06, seed=0):
    """Haufen aus einer verformten Halbkugel."""
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1, segments=48, ring_count=24, location=(0, 0, 0))
    o = bpy.context.object
    o.name = name
    rr = random.Random(seed)
    phases = [rr.uniform(0, 6.28) for _ in range(6)]
    for v in o.data.vertices:
        x, y, z = v.co
        if z < 0:
            z = 0
        a = math.atan2(y, x)
        k = 1 + bumps * (math.sin(3 * a + phases[0]) + 0.6 * math.sin(5 * a + phases[1]) + 0.4 * math.sin(7 * a + phases[2]))
        v.co = (x * r * k, y * r * k, z * h * (1 + bumps * math.sin(4 * a + phases[3])))
    o.data.materials.append(material)
    bpy.ops.object.shade_smooth()
    o.parent = szene.root
    return o


def grains(n, rad, height, mats, size=(0.03, 0.07)):
    for i in range(n):
        a = rnd.uniform(0, 2 * math.pi)
        d = rad * math.sqrt(rnd.random())
        z = height * math.sqrt(max(0.0, 1 - (d / rad) ** 2)) * 0.97
        s = rnd.uniform(*size)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=s, location=(math.cos(a) * d, math.sin(a) * d, z))
        g = bpy.context.object
        g.name = f"korn{i}"
        g.rotation_euler = (rnd.random() * 3, rnd.random() * 3, rnd.random() * 3)
        g.data.materials.append(rnd.choice(mats))
        g.parent = szene.root


SAND = mat("sand", (0.60, 0.44, 0.25), 0.95, 0.0)
SPICE = emit(mat("spice", (0.90, 0.38, 0.06), 0.6, 0.0, False), (1.0, 0.40, 0.06), 0.35)
MELANGE = mat("melange", (0.45, 0.20, 0.06), 0.8, 0.0, False)
DARK = mat("dark", (0.18, 0.12, 0.08), 0.7, 0.0, False)
CORK = mat("cork", (0.45, 0.32, 0.18), 0.9, 0.0, False)
METAL = mat("metal", (0.25, 0.22, 0.18), 0.4, 0.8, False)

if NAME == "spice-sand":
    heap("haufen", 0.9, 0.32, SAND, 0.05, 1)
    grains(160, 0.85, 0.32, [SPICE, SPICE, SAND], (0.03, 0.055))
elif NAME == "melange":
    heap("haufen", 0.8, 0.42, MELANGE, 0.04, 2)
    grains(220, 0.78, 0.42, [SPICE, MELANGE, MELANGE], (0.025, 0.045))
    # Kristalle am Rand
    for i, a in enumerate((0.4, 2.1, 3.9, 5.2)):
        o = cyl(f"kristall{i}", 0.06, 0.28, (math.cos(a) * 0.62, math.sin(a) * 0.62, 0.1), SPICE,
                rot=(rnd.uniform(-0.6, 0.6), rnd.uniform(-0.6, 0.6), 0), verts=6)
elif NAME == "spice-essence":
    LIQ = emit(mat("liq", (0.95, 0.30, 0.04), 0.1, 0.0, False), (1.0, 0.32, 0.04), 0.5)
    GL = glass("glas", (0.9, 0.85, 0.8))
    cyl("fluessig", 0.3, 0.7, (0, 0, 0.4), LIQ, verts=32)
    cyl("glas", 0.34, 1.0, (0, 0, 0.52), GL, verts=32)
    cyl("hals", 0.16, 0.25, (0, 0, 1.12), GL, verts=24)
    cyl("korken", 0.15, 0.2, (0, 0, 1.3), CORK, verts=24)
    szene.root.rotation_euler = (0.0, 0.0, 0.0)
elif NAME == "spice-briquette":
    BRICK = mat("brikett", (0.30, 0.14, 0.05), 0.85, 0.0, False)
    for i, (x, y, z, r) in enumerate(((-0.25, 0.1, 0.15, 0.2), (0.3, -0.1, 0.15, -0.15), (0.0, 0.0, 0.45, 0.6))):
        box(f"brikett{i}", (0.75, 0.42, 0.3), (x, y, z), BRICK, 0.06, rot=(0, 0, r))
elif NAME == "spice-science-pack":
    LIQ = emit(mat("liq", (0.85, 0.40, 0.10), 0.1, 0.0, False), (1.0, 0.45, 0.1), 0.3)
    GL = glass("glas", (0.9, 0.88, 0.85))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.48, location=(0, 0, 0.5), segments=32, ring_count=16)
    g = bpy.context.object; g.name = "bauch"; g.data.materials.append(GL); bpy.ops.object.shade_smooth(); g.parent = szene.root
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.42, location=(0, 0, 0.47), segments=32, ring_count=16)
    l = bpy.context.object; l.name = "fluessig"; l.data.materials.append(LIQ); bpy.ops.object.shade_smooth(); l.parent = szene.root
    l.scale = (1, 1, 0.8)
    cyl("hals", 0.14, 0.5, (0, 0, 1.1), GL, verts=24)
    cyl("ring", 0.17, 0.08, (0, 0, 1.3), METAL, verts=24)
    cyl("deckel", 0.15, 0.12, (0, 0, 1.4), DARK, verts=24)
    # Spice-Körner im Bauch
    for i in range(6):
        a = i * 1.05
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.05, location=(math.cos(a) * 0.2, math.sin(a) * 0.2, 0.25))
        k = bpy.context.object; k.data.materials.append(SPICE); k.parent = szene.root
else:
    raise SystemExit("unbekannt: " + NAME)

szene.render(frames=1, pose=lambda i: None, icon_frame=0)
