#!/usr/bin/env python3
"""Prüft die eigenen Bilder (__arrakis__/…png) gegen ihre Sprite-Definitionen.

Der Prüfstand-Server lädt keine Bilder. Passt ein Ausschnitt nicht in die Datei (falsche Breite, Bildzahl, Zeilenlänge)
oder hat ein Symbol die falsche Größe, bricht erst das Spiel bei Max ab. Dieses Skript liest den Dump von datastage.py
(--dump) und prüft für jede Bilddefinition mit __arrakis__-Pfad:

- Datei vorhanden;
- Sprite/Animation: x/y + Spalten × width und Zeilen × height liegen in der Datei; Spalten = line_length (0 = alle Bilder
  in einer Zeile), Bilder = frame_count × direction_count; bei filenames + lines_per_file je Datei;
- Symbol (icon + icon_size, Vorgabe 64): Höhe = icon_size, Breite ≥ icon_size.

Aufruf (aus dem Repo-Root):
  .venv/bin/python tools/check/datastage.py fd2123 --dump /tmp/arrakis.json
  python3 tools/check/bilder.py /tmp/arrakis.json
Braucht pillow. Rückgabe 1 bei Fehlern.
"""
import json
import math
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
PREFIX = "__arrakis__/"
sizes = {}
errors = []
checked = {"sprite": 0, "icon": 0}


def size_of(path):
    if path not in sizes:
        f = ROOT / path[len(PREFIX):]
        sizes[path] = Image.open(f).size if f.is_file() else None
    return sizes[path]


def wh(d):
    s = d.get("size")
    if isinstance(s, (int, float)):
        return s, s
    if isinstance(s, list):
        return s[0], s[1]
    return d.get("width"), d.get("height")


def xy(d):
    p = d.get("position")
    if isinstance(p, list):
        return p[0], p[1]
    return d.get("x", 0) or 0, d.get("y", 0) or 0


def check_sprite(where, d):
    files = d.get("filenames") or [d.get("filename")]
    own = [f for f in files if isinstance(f, str) and f.startswith(PREFIX) and f.endswith(".png")]
    if not own:
        return
    checked["sprite"] += 1
    w, h = wh(d)
    if not w or not h:
        errors.append(f"{where}: ohne width/height ({own[0]})")
        return
    x, y = xy(d)
    n = (d.get("frame_count") or 1) * (d.get("direction_count") or 1)
    line = d.get("line_length") or 0
    cols = min(line, n) if line > 0 else n
    rows_total = math.ceil(n / cols)
    per_file = d.get("lines_per_file") or rows_total
    for i, f in enumerate(own):
        size = size_of(f)
        if size is None:
            errors.append(f"{where}: Datei fehlt {f}")
            continue
        rows = min(per_file, rows_total - i * per_file) if d.get("filenames") else rows_total
        need = (x + cols * w, y + rows * h)
        if need[0] > size[0] or need[1] > size[1]:
            errors.append(f"{where}: {f} ist {size[0]}×{size[1]}, Ausschnitt braucht {need[0]}×{need[1]}"
                          f" ({n} Bilder, {cols} je Zeile, {w}×{h})")


def check_icon(where, path, icon_size):
    if not (isinstance(path, str) and path.startswith(PREFIX)):
        return
    checked["icon"] += 1
    size = size_of(path)
    s = icon_size or 64
    if size is None:
        errors.append(f"{where}: Datei fehlt {path}")
    elif size[1] != s or size[0] < s:
        errors.append(f"{where}: Symbol {path} ist {size[0]}×{size[1]}, icon_size {s}")


def walk(where, node):
    if isinstance(node, dict):
        if "filename" in node or "filenames" in node:
            check_sprite(where, node)
        for key in ("icon", "small_icon"):
            if isinstance(node.get(key), str):
                check_icon(f"{where}.{key}", node[key], node.get("icon_size"))
        for k, v in node.items():
            walk(f"{where}.{k}", v)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(f"{where}[{i}]", v)


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    dump = json.load(open(sys.argv[1], encoding="utf-8"))
    for p in dump["prototypes"]:
        walk(f"{p['type']}/{p['name']}", p["data"])
    for e in errors:
        print("FEHLER", e)
    print(f"== {checked['sprite']} Bilddefinitionen, {checked['icon']} Symbole, {len(sizes)} Dateien geprüft,"
          f" {len(errors)} Fehler")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
