# Wurmzahn (Item-Symbol): gebogener, milchweißer Zahn mit dunkler Wurzel, schräg liegend.
# Aufruf: python zahn-modell.py ROH_DIR icon
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
import szene
from szene import mat

szene.start("zahn", {"default": 3}, ())

IVORY = mat("ivory", (0.86, 0.82, 0.70), 0.22, 0.0, False)
bs = IVORY.node_tree.nodes["Principled BSDF"]
bs.inputs["Coat Weight"].default_value = 0.6
bs.inputs["Subsurface Weight"].default_value = 0.25
ROOT = mat("root", (0.40, 0.30, 0.20), 0.7, 0.0, False)


def curved(name, material, t0, t1, steps=40, thick=1.0):
    """Zahn als Schlauch entlang eines Bogens: Querschnitt flache Ellipse, Radius nimmt zur Spitze hin ab."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    seg = 16
    R = 1.1             # Bogenradius
    for k in range(steps + 1):
        t = t0 + (t1 - t0) * k / steps
        a = math.radians(-60 + 110 * t)
        cx, cy = R * math.sin(a), R * (1 - math.cos(a)) - 0.25
        tx, ty = math.cos(a), math.sin(a)          # Tangente
        nx, ny = -ty, tx                            # Normale in der Ebene
        r = (0.27 * (1 - t) ** 0.75 + 0.008) * thick
        ring = []
        for j in range(seg):
            p = 2 * math.pi * j / seg
            u, v = math.cos(p) * r, math.sin(p) * r * 0.55
            ring.append(bm.verts.new((cx + nx * u, cy + ny * u, 0.2 + v)))
        rings.append(ring)
    for a_, b_ in zip(rings, rings[1:]):
        for j in range(seg):
            bm.faces.new((a_[j], a_[(j + 1) % seg], b_[(j + 1) % seg], b_[j]))
    bm.faces.new(list(reversed(rings[0])))
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    szene.scene.collection.objects.link(o)
    o.data.materials.append(material)
    for f in o.data.polygons:
        f.use_smooth = True
    o.parent = szene.root
    return o


curved("wurzel", ROOT, 0.0, 0.17, 8, 1.06)
curved("zahn", IVORY, 0.14, 1.0, 48)
szene.root.rotation_euler = (0, 0, 0)
szene.render(frames=1, pose=lambda i: None, icon_frame=0)
