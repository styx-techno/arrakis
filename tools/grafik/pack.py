# Rohbilder strecken (Höhe x sqrt(2)) und zu Spritesheets zusammensetzen.
# Aufruf: python pack.py ROH_DIR ZIEL_DIR  (braucht pillow)
import sys, glob, os
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)


def load(path):
    im = Image.open(path).convert("RGBA")
    w, _ = im.size
    return im.resize((w, w), Image.LANCZOS)


def sheet(mode, cols=8, shadow=False):
    files = sorted(glob.glob(f"{src}/{mode}-*.png"))
    frames = [load(f) for f in files]
    w = frames[0].width
    rows = (len(frames) + cols - 1) // cols
    out = Image.new("RGBA", (w * cols, w * rows), (0, 0, 0, 0))
    for i, im in enumerate(frames):
        if shadow:
            # Factorio-Schatten: schwarz, Deckkraft aus dem Schattenfänger
            a = im.getchannel("A")
            im = Image.merge("RGBA", (a.point(lambda _: 0),) * 3 + (a,))
        out.paste(im, ((i % cols) * w, (i // cols) * w))
    out.save(f"{dst}/harvester-{mode}.png", optimize=True)
    print(mode, len(frames), "Bilder je", w, "px, Blatt", out.size, os.path.getsize(f"{dst}/harvester-{mode}.png") // 1024, "KB")


for mode in ("base", "mask", "shadow"):
    if glob.glob(f"{src}/{mode}-*.png"):
        sheet(mode, shadow=(mode == "shadow"))
icons = glob.glob(f"{src}/icon-*.png")
if icons:
    im = load(icons[0])
    bbox = im.getbbox()
    im = im.crop(bbox)
    side = max(im.size)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
    for n in (64, 256):
        sq.resize((n, n), Image.LANCZOS).save(f"{dst}/harvester-icon-{n}.png", optimize=True)
    print("icon", bbox)
