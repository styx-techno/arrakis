# Gemeinsame Szene für die Fahrzeugmodelle (ernter-modell.py, ornithopter-modell.py): Materialien, Grundformen,
# Licht, Kamera und Rendern wie Factorio-Fahrzeuge (Ortho, 45 Grad, Licht von links oben). Festlegungen in README.md.
# Ablauf im Modellskript: szene.start(...), Teile mit box/cyl/slab an szene.root bauen, szene.render(...).
import math, os, sys
import bpy

scene = None
root = None
MODE = None
DIRS = None
OUT = None
PX_PER_TILE = None
FRAME_TILES = None
MASK_PREFIXES = ()
# Teil (4. Argument): "alles" (Vorgabe), "schlag" (alles, mit Flügelschlag; zum Ansehen), "rumpf" (ohne Flügel; sie werfen aber Schatten) oder "fluegel" (nur die Flügel,
# Rumpf als Aussparung, halbe Auflösung, FLAP_FRAMES Bilder je Richtung). Siehe fluegel_vorbereiten().
TEIL = "alles"
FLAP_FRAMES = 4
WING_PARTS = []
PIVOTS = []


def start(name, frame_tiles, mask_prefixes):
    """Liest OUT_DIR MODUS [richtungen] aus sys.argv und legt eine leere Szene mit dem Wurzelobjekt an.
    frame_tiles: Bildbreite in Kacheln je Modus (Schlüssel vorschau, shadow, sonst default)."""
    global scene, root, MODE, DIRS, OUT, PX_PER_TILE, FRAME_TILES, MASK_PREFIXES, TEIL
    OUT = sys.argv[1]
    MODE = sys.argv[2] if len(sys.argv) > 2 else "vorschau"
    DIRS = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    TEIL = sys.argv[4] if len(sys.argv) > 4 else "alles"
    PX_PER_TILE = {"shadow": 32, "icon": 128}.get(MODE, 64)   # Fahrzeug als HR-Grafik, Schatten halb so fein
    if TEIL == "fluegel" and MODE in ("base", "mask"):
        PX_PER_TILE = 32                                          # Flügelschlag in halber Auflösung
    FRAME_TILES = frame_tiles.get(MODE, frame_tiles["default"])
    MASK_PREFIXES = mask_prefixes
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    root = bpy.data.objects.new(name, None)
    scene.collection.objects.link(root)


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


def prism(name, outline, z0, z1, material, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.01):
    """Senkrecht ausgezogenes Vieleck: outline = [(x, y), …] gegen den Uhrzeigersinn, von z0 bis z1, um den eigenen
    Ursprung gedreht (rot) und nach loc gesetzt."""
    import bmesh
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    low = [bm.verts.new((x, y, z0)) for x, y in outline]
    high = [bm.verts.new((x, y, z1)) for x, y in outline]
    bm.faces.new(list(reversed(low)))
    bm.faces.new(high)
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((low[i], low[j], high[j], high[i]))
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    o.location = loc
    o.rotation_euler = rot
    scene.collection.objects.link(o)
    return finish(o, material, bevel)


def fluegel_vorbereiten(amplitude_deg=22.0):
    """Flieger (Ornithopter, Carryall): hängt jeden Flügel samt Holm, Rippen, Streifen (und das Positionslicht tip<sx>
    am vorderen Paar) an ein Gelenk an der Stelle von hinge<paar><sx>. Gibt pose(f) zurück: Bild f von FLAP_FRAMES,
    Bild 0 ist die Ruhelage (wie das Standbild), vorderes und hinteres Paar schlagen gegenläufig wie bei einer Libelle."""
    import re
    objs = {o.name: o for o in scene.objects if o.parent == root}
    groups = {}
    for name, o in objs.items():
        m = re.match(r"^(wing|spar|rib|stripe)(\d)(-?1)", name)
        t = re.match(r"^tip(-?1)$", name)
        key = (int(m.group(2)), int(m.group(3))) if m else (0, int(t.group(1))) if t else None
        if key:
            groups.setdefault(key, []).append(o)
    bpy.context.view_layer.update()
    for (pair, sx), parts in sorted(groups.items()):
        hinge = objs[f"hinge{pair}{sx}"]
        pivot = bpy.data.objects.new(f"gelenk{pair}{sx}", None)
        scene.collection.objects.link(pivot)
        pivot.parent = root
        pivot.location = hinge.location.copy()
        bpy.context.view_layer.update()
        for o in parts:
            mw = o.matrix_world.copy()
            o.parent = pivot
            o.matrix_parent_inverse = pivot.matrix_world.inverted()
            o.matrix_world = mw
            WING_PARTS.append(o)
        PIVOTS.append((pivot, pair, sx))
    amp = math.radians(amplitude_deg)

    def pose(f):
        phase = math.sin(2 * math.pi * f / FLAP_FRAMES)
        for pivot, pair, sx in PIVOTS:
            flap = amp * phase * (1 if pair == 0 else -1)
            pivot.rotation_euler = (0, -sx * flap, 0)
    return pose


def render(lift=0.0, frames=0, pose=None, icon_frame=0):
    """Rendert alle Richtungen im Modus MODE nach OUT/<modus>-<nn>.png. lift hebt das Modell für Schatten und Vorschau
    über den Boden (Flieger: Teile unter dem Rumpfpunkt stecken sonst im Boden); das Bild selbst bleibt auf der
    Bildmitte. Mit frames > 0 rendert es statt der Richtungen die Bilder einer Animation in einer Ansicht (Gebäude,
    z. B. Thumper): vor Bild i ruft es pose(i); im Modus icon nur das Bild icon_frame."""
    # Boden als Schattenfänger
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
    ground = bpy.context.object
    ground.is_shadow_catcher = True
    wing = set(WING_PARTS)
    parts = [o for o in scene.objects if o.type in ("MESH", "CURVE") and o != ground and (o.parent == root or o in wing)]
    if TEIL == "rumpf":
        for o in wing:
            o.visible_camera = False      # Flügel fehlen im Bild, werfen aber Schatten auf den Rumpf
    if TEIL == "fluegel":
        for o in parts:
            if o not in wing:
                o.is_holdout = True       # Rumpf verdeckt die Flügel dahinter, erscheint aber selbst nicht
    if MODE in ("shadow", "vorschau"):
        root.location.z = lift
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

    if frames:
        steps = [icon_frame] if MODE == "icon" else range(frames)
        for i in steps:
            pose(i)
            root.rotation_euler = (0, 0, -2 * math.pi * 5 / 8 if MODE == "icon" else 0)
            scene.render.filepath = os.path.join(OUT, f"{MODE}-{i:02d}.png")
            bpy.ops.render.render(write_still=True)
        print("fertig", MODE, len(steps))
        return

    turns = [5] if MODE == "icon" else range(DIRS)
    flaps = FLAP_FRAMES if (TEIL in ("fluegel", "schlag") and pose and MODE != "icon") else 0
    for i in turns:
        # Richtung i: 0 = Norden, im Uhrzeigersinn (Factorio-Reihenfolge der 64 Richtungen)
        root.rotation_euler = (0, 0, -2 * math.pi * i / (8 if MODE == "icon" else DIRS))
        if flaps:
            # Flügelschlag: Bilder einer Richtung hintereinander (RotatedAnimation), Datei <modus>-<rr>-<f>.png
            for f in range(flaps):
                pose(f)
                scene.render.filepath = os.path.join(OUT, f"{MODE}-{i:02d}-{f}.png")
                bpy.ops.render.render(write_still=True)
            continue
        scene.render.filepath = os.path.join(OUT, f"{MODE}-{i:02d}.png")
        bpy.ops.render.render(write_still=True)
    print("fertig", MODE, len(turns))
