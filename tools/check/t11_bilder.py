#!/usr/bin/env python3
"""Macht aus script-output/arrakis-t11-karten.txt (Prüfstand T11) ein PNG je Variante.

Jedes PNG zeigt alle Seeds einer Variante nebeneinander (1 Zeichen = 16 Kacheln = 3 Pixel).
Farben: Fels braun, Sand unter 100 Kacheln vom Fels hell, Sand ab 100 Kacheln mittel,
Spicefläche orange, Ursprung rot.

Aufruf (nur Python-Standardbibliothek):
  python3 tools/check/t11_bilder.py arrakis-t11-karten.txt ausgabe-ordner
"""
import os
import re
import struct
import sys
import zlib

COLORS = {
    "#": (120, 80, 50),
    "-": (235, 205, 150),
    ".": (205, 165, 100),
    "o": (230, 110, 30),
    "S": (220, 0, 0),
}
SCALE = 3
GAP = 6


def write_png(path, width, height, pixels):
    rows = b"".join(b"\x00" + bytes(pixels[y * width * 3:(y + 1) * width * 3]) for y in range(height))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(rows, 9)))
        f.write(chunk(b"IEND", b""))


def read_maps(path):
    maps = {}
    current = None
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            header = re.match(r"=== (\S+) Seed (\d+) \((.*?)\): (.*) ===", line)
            if header:
                current = {"seed": header.group(2), "label": header.group(3), "info": header.group(4), "rows": []}
                maps.setdefault(header.group(1), []).append(current)
            elif current is not None and line and line[0] in COLORS:
                current["rows"].append(line)
            else:
                current = None if not line else current
    return maps


def main():
    source, target = sys.argv[1], sys.argv[2]
    os.makedirs(target, exist_ok=True)
    for key, pictures in read_maps(source).items():
        size = max(len(p["rows"]) for p in pictures)
        width = len(pictures) * (size * SCALE + GAP)
        height = size * SCALE
        pixels = bytearray([255] * (width * height * 3))
        for n, picture in enumerate(pictures):
            left = n * (size * SCALE + GAP)
            for j, row in enumerate(picture["rows"]):
                for i, char in enumerate(row):
                    color = COLORS.get(char, (0, 0, 0))
                    for dy in range(SCALE):
                        base = ((j * SCALE + dy) * width + left + i * SCALE) * 3
                        for dx in range(SCALE):
                            pixels[base + dx * 3:base + dx * 3 + 3] = bytes(color)
        out = os.path.join(target, f"t11-{key}.png")
        write_png(out, width, height, pixels)
        print(out, "Seeds:", ", ".join(p["seed"] for p in pictures))
        for p in pictures:
            print("  ", p["seed"], p["label"], p["info"])


if __name__ == "__main__":
    main()
