#!/usr/bin/env python3
"""Statische Prüfung der Dateipfade aus base, core und space-age in den Prototypen von Arrakis.

Ein headless-Server lädt keine Grafiken: Ein falscher Pfad wie __base__/graphics/icons/signal/signal-S.png
(richtig: signal_S.png) fällt im Prüfstand nicht auf, erst beim Start des Spiels (0.12.0). Dieses Skript liest
prototypes/**/*.lua und data*.lua als Text und verlangt, dass jeder wörtliche Pfad "__base__/…", "__core__/…" oder
"__space-age__/…" mit Dateiendung auch irgendwo in den Lua-Dateien von factorio-data vorkommt (dort sind die Pfade
echt, weil die Spieldateien sie laden). Nummerierte Varianten wie demolisher-explosion-1.ogg gelten als bekannt, wenn
factorio-data den Stamm ("…/demolisher-explosion") an sound_variations o. ä. übergibt. Pfade, die in Arrakis aus Teilen
zusammengesetzt werden, sieht es nicht.

Aufruf: python3 tools/check/base_paths.py <factorio-data-Ordner>   (mit base/, core/, space-age/; Ziel 2.1, z. B.
factorio-data 2.1.23; mit 2.0.77 fehlen die Wurm-Töne demolisher-explosion-1/2, die es dort nicht gibt)
Rückgabe 1 bei Treffern.
"""
import pathlib
import re
import sys

PATH = re.compile(r'"(__(?:base|core|space-age)__/[^"]+\.(?:png|ogg|wav|jpg))"')
STEM = re.compile(r'"(__(?:base|core|space-age)__/[^"]+)"')
VARIANT = re.compile(r'^(.*?)[-_]\d+\.(?:ogg|wav|png)$')


def lua_files(root):
    return sorted(p for p in root.rglob("*.lua") if p.is_file())


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    fd = pathlib.Path(sys.argv[1])
    repo = pathlib.Path(__file__).resolve().parents[2]
    known, stems = set(), set()
    for sub in ("base", "core", "space-age"):
        for f in lua_files(fd / sub):
            text = f.read_text(encoding="utf-8", errors="replace")
            known.update(PATH.findall(text))
            stems.update(STEM.findall(text))
    if not known:
        print("FEHLER: keine Pfade in " + str(fd) + " gefunden")
        return 2
    own = lua_files(repo / "prototypes") + sorted(repo.glob("data*.lua"))
    hits = 0
    seen = 0
    for f in own:
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            for path in PATH.findall(line):
                seen += 1
                m = VARIANT.match(path)
                if path not in known and not (m and m.group(1) in stems):
                    hits += 1
                    print("FEHLER %s:%d: %s kommt in factorio-data nicht vor" % (f.relative_to(repo), n, path))
    print("== %d Pfade geprüft, %d unbekannt (Vergleich: %d Pfade aus factorio-data)" % (seen, hits, len(known)))
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
