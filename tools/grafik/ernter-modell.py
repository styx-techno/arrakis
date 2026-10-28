# Spice-Ernter aus einfachen Formen, gerendert wie Factorio-Fahrzeuge (Ortho, 45 Grad, Licht von links oben).
# Aufruf: python ernter-modell.py ROH_DIR MODUS [richtungen]  (Python mit dem Modul bpy, pip install bpy)
# MODUS: vorschau (mit Schatten, 7 Kacheln), base (ohne Boden), shadow (nur Schatten, 32 px je Kachel),
#        mask (Farbmaske für die Spielerfarbe), icon (eine Schrägansicht für Symbole).
import math, os, sys
import bpy
from mathutils import Vector

OUT = sys.argv[1]
MODE = sys.argv[2] if len(sys.argv) > 2 else "vorschau"
DIRS = int(sys.argv[3]) if len(sys.argv) > 3 else 8
PX_PER_TILE = {"shadow": 32, "icon": 128}.get(MODE, 64)   # Fahrzeug als HR-Grafik, Schatten halb so fein
FRAME_TILES = {"vorschau": 7, "shadow": 8}.get(MODE, 6)
MASK_PREFIXES = ("skirt", "plate")                        # Teile in Spielerfarbe

os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def col(sockets, name):
    """Farb-Socket eines Mix-Knotens (gleichnamige Float- und Vektor-Sockets überspringen)."""
    return next(x for x in sockets if x.name == name and x.type == "RGBA")


def mat(name, color, rough=0.6, metal=0.0, weather=True):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if weather:
        nt = m.node_tree
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 35.0
        noise.inputs["Detail"].default_value = 8.0
        dirt = nt.nodes.new("ShaderNodeMix")
        dirt.data_type = "RGBA"
        col(dirt.inputs, "A").default_value = (*color, 1)
        col(dirt.inputs, "B").default_value = (color[0] * 0.7, color[1] * 0.65, color[2] * 0.6, 1)
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.5
        ramp.color_ramp.elements[1].position = 0.7
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], dirt.inputs["Factor"])
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(geo.outputs["Position"], sep.inputs["Vector"])
        hramp = nt.nodes.new("ShaderNodeMapRange")
        hramp.inputs["From Min"].default_value = 0.05
        hramp.inputs["From Max"].default_value = 0.6
        hramp.inputs["To Min"].default_value = 0.28
        hramp.inputs["To Max"].default_value = 0.0
        nt.links.new(sep.outputs["Z"], hramp.inputs["Value"])
        sand = nt.nodes.new("ShaderNodeMix")
        sand.data_type = "RGBA"
        col(sand.inputs, "B").default_value = (0.62, 0.48, 0.30, 1)
        nt.links.new(col(dirt.outputs, "Result"), col(sand.inputs, "A"))
        nt.links.new(hramp.outputs["Result"], sand.inputs["Factor"])
        # Flugsand auf Flächen, die nach oben zeigen
        sepn = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(geo.outputs["Normal"], sepn.inputs["Vector"])
        nramp = nt.nodes.new("ShaderNodeMapRange")
        nramp.inputs["From Min"].default_value = 0.6
        nramp.inputs["From Max"].default_value = 1.0
        nramp.inputs["To Min"].default_value = 0.0
        nramp.inputs["To Max"].default_value = 0.3
        nt.links.new(sepn.outputs["Z"], nramp.inputs["Value"])
        noise2 = nt.nodes.new("ShaderNodeTexNoise")
        noise2.inputs["Scale"].default_value = 6.0
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        nt.links.new(nramp.outputs["Result"], mul.inputs[0])
        nt.links.new(noise2.outputs["Fac"], mul.inputs[1])
        mul2 = nt.nodes.new("ShaderNodeMath")
        mul2.operation = "MULTIPLY"
        mul2.inputs[1].default_value = 1.2
        nt.links.new(mul.outputs[0], mul2.inputs[0])
        top = nt.nodes.new("ShaderNodeMix")
        top.data_type = "RGBA"
        col(top.inputs, "B").default_value = (0.66, 0.52, 0.34, 1)
        nt.links.new(col(sand.outputs, "Result"), col(top.inputs, "A"))
        nt.links.new(mul2.outputs[0], top.inputs["Factor"])
        nt.links.new(col(top.outputs, "Result"), bsdf.inputs["Base Color"])
    return m


HULL = mat("hull", (0.085, 0.08, 0.075), 0.7, 0.3)       # dunkles, warmes Metall
HULL2 = mat("hull2", (0.14, 0.13, 0.115), 0.7, 0.3)      # hellere Panzerplatten
STEEL = mat("steel", (0.06, 0.06, 0.06), 0.5, 0.5)
TRACK = mat("track", (0.06, 0.055, 0.05), 0.9, 0.3)
GLASS = mat("glass", (0.08, 0.10, 0.10), 0.1, 0.2, False)
LAMP = mat("lamp", (1.0, 0.85, 0.5), 0.3, 0.0, False)
LAMP.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (1.0, 0.75, 0.35, 1)
LAMP.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 4.0
MAW = mat("maw", (0.02, 0.02, 0.02), 0.9, 0.0, False)

root = bpy.data.objects.new("harvester", None)
scene.collection.objects.link(root)


def finish(o, material, bevel):
    if bevel:
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
    o.data.materials.append(material)
    o.parent = root
    return o


def box(name, size, loc, material, bevel=0.04, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return finish(o, material, bevel)


def cyl(name, r, depth, loc, material, rot=(0, 0, 0), verts=24):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, rotation=rot, vertices=verts)
    o = bpy.context.object
    o.name = name
    o.data.materials.append(material)
    bpy.ops.object.shade_smooth()
    o.parent = root
    return o


def slab(name, bottom, top, z0, z1, material, bevel=0.05):
    """Pyramidenstumpf: bottom/top = (x0, x1, y0, y1) auf Höhe z0/z1."""
    import bmesh
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    vs = []
    for (x0, x1, y0, y1), z in ((bottom, z0), (top, z1)):
        for x, y in ((x0, y0), (x1, y0), (x1, y1), (x0, y1)):
            vs.append(bm.verts.new((x, y, z)))
    bm.faces.new(vs[3::-1])
    bm.faces.new(vs[4:8])
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((vs[i], vs[j], vs[4 + j], vs[4 + i]))
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    scene.collection.objects.link(o)
    return finish(o, material, bevel)


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

# Boden als Schattenfänger
bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
ground = bpy.context.object
ground.is_shadow_catcher = True
parts = [o for o in scene.objects if o.parent == root]
if MODE in ("base", "mask", "icon"):
    ground.hide_render = True
if MODE == "shadow":
    for o in parts:
        o.visible_camera = False
if MODE == "mask":
    white = bpy.data.materials.new("mask")
    white.use_nodes = True
    white.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (1, 1, 1, 1)
    white.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
    for o in parts:
        if o.name.startswith(MASK_PREFIXES):
            o.data.materials.clear()
            o.data.materials.append(white)
        else:
            o.is_holdout = True

# Licht: Sonne von links oben (Factorio-Schatten fallen nach rechts unten)
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 2.2
sun.data.angle = math.radians(3)
sun.rotation_euler = (math.radians(35), 0, math.radians(45))
scene.collection.objects.link(sun)
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.9, 0.8, 0.65, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.3
scene.world = world

# Kamera: orthografisch, 45 Grad über dem Boden. Sie steht im Süden (+Y) und schaut nach Norden (-Y ist oben im
# Bild). Der Bodenpunkt unter der Fahrzeugmitte liegt in der Bildmitte, das Sprite braucht also kein shift.
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.type = "ORTHO"
cam.data.ortho_scale = FRAME_TILES
cam.location = (0, 14.14, 14.14)
cam.rotation_euler = (math.radians(45), 0, math.radians(180))
scene.collection.objects.link(cam)
scene.camera = cam

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16 if MODE in ("shadow", "mask") else 48
scene.cycles.use_denoising = True
scene.render.film_transparent = True
scene.view_settings.view_transform = "Standard"  # Sprites sind schlichtes sRGB, AgX wäscht die Farben aus
# Die Kamera sieht den Boden um 1/sqrt(2) gestaucht. pack.py streckt die Höhe danach um sqrt(2), dann ist eine Kachel
# im Bild quadratisch wie in Factorio.
size = round(FRAME_TILES * PX_PER_TILE)
scene.render.resolution_x = size
scene.render.resolution_y = round(size / math.sqrt(2))
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"

turns = [5] if MODE == "icon" else range(DIRS)
for i in turns:
    # Richtung i: 0 = Norden, im Uhrzeigersinn (Factorio-Reihenfolge der 64 Richtungen)
    root.rotation_euler = (0, 0, -2 * math.pi * i / (8 if MODE == "icon" else DIRS))
    scene.render.filepath = os.path.join(OUT, f"{MODE}-{i:02d}.png")
    bpy.ops.render.render(write_still=True)
print("fertig", MODE, len(turns))
