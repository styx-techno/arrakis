r"""Ein ganzer Prüfstand-Lauf auf Max' PC in einem Schritt: neuesten Stand von main holen, pruefstand.py
laufen lassen, Ergebnisse in den Zweig pruefstand-ergebnisse hochladen.

Nur Python-Standardbibliothek. Der Thread-Claude ruft das nach jedem fertigen Push auf (Max muss nichts tun).

Aufruf (aus dem Repo-Root):
  python tools/pc/lauf.py --factorio "C:\...\factorio.exe" --ordner <Arbeitsordner> [TEST ...]
  Standard-Test ist „alle“. --ergebnis-repo zeigt auf einen Klon des Zweigs pruefstand-ergebnisse
  (Standard: <ordner>/ergebnis-repo). --ohne-pull testet den Stand, wie er ist.

Ablauf:
  1. git pull --ff-only origin main im Mod-Repo (dieses Repo).
  2. pruefstand.py mit --factorio, --ordner und den Tests; Ausgabe läuft durch.
  3. Neue Ergebnisdateien (arrakis-test-*.txt, arrakis-t11-karten-*.txt, ohne *-vorher-*) aus <ordner>/ergebnisse
     nach ergebnisse/<Datum>_<Version>_<Commit>/ im Ergebnis-Repo, Zeile in dessen README, commit, push.
  4. Letzte Zeile: LAUF <Rückgabewert> | <Version> <Commit> | <Ordner im Zweig> | hochgeladen ja/nein

Rückgabewert: der von pruefstand.py (0 kein FEHLER, 1 FEHLER, 2 Einrichtung); 3, wenn Holen oder Hochladen scheitert.
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[2]
ENDE_RE = re.compile(r"^\[(\w+)\] ENDE .*\(OK \d+, FEHLER (\d+), FRAGE \d+")


def say(text):
  print(text, flush=True)


def git(cwd, *args):
  done = subprocess.run(["git", "-C", str(cwd)] + list(args), capture_output=True, text=True, encoding="utf-8",
                        errors="replace")
  if done.returncode != 0:
    raise RuntimeError("git %s: %s" % (" ".join(args), (done.stderr or done.stdout).strip()))
  return done.stdout.strip()


def rc_text(rc, result_file):
  if rc == 0:
    return "0 (kein FEHLER)"
  if rc == 2:
    return "2 (Einrichtung/Infrastruktur)"
  failed = []
  if result_file:
    for line in result_file.read_text(encoding="utf-8", errors="replace").splitlines():
      match = ENDE_RE.match(line)
      if match and int(match.group(2)) > 0:
        failed.append(match.group(1))
  return "%d (FEHLER in %s)" % (rc, ", ".join(failed) if failed else "?")


def upload(args, results, version, commit, rc):
  repo = Path(args.ergebnis_repo) if args.ergebnis_repo else Path(args.ordner) / "ergebnis-repo"
  git(repo, "pull", "--ff-only", "origin", "pruefstand-ergebnisse")
  name = "%s_%s_%s" % (time.strftime("%Y-%m-%d"), version, commit)
  target = repo / "ergebnisse" / name
  target.mkdir(parents=True, exist_ok=True)
  for path in results:
    shutil.copy2(path, target / path.name)
  main_file = next((p for p in results if p.name.startswith("arrakis-test-")), None)
  row = "| %s | %s | %s | %s |" % (time.strftime("%Y-%m-%d %H:%M"), version, commit, rc_text(rc, main_file))
  readme = repo / "README.md"
  text = readme.read_text(encoding="utf-8").rstrip("\n") + "\n" + row + "\n"
  readme.write_text(text, encoding="utf-8")
  git(repo, "add", "-A")
  git(repo, "commit", "-q", "-m", "Prüfstand-Ergebnis %s (%s)" % (version, commit))
  git(repo, "push", "-q", "origin", "pruefstand-ergebnisse")
  return "ergebnisse/" + name


def main():
  for stream in (sys.stdout, sys.stderr):
    try:
      stream.reconfigure(errors="replace", line_buffering=True)
    except (AttributeError, ValueError):
      pass
  ap = argparse.ArgumentParser(description="Holen, Prüfstand, Ergebnisse hochladen")
  ap.add_argument("--factorio", required=True)
  ap.add_argument("--ordner", required=True)
  ap.add_argument("--ergebnis-repo")
  ap.add_argument("--ohne-pull", action="store_true")
  ap.add_argument("tests", nargs="*", default=["alle"])
  args = ap.parse_args()
  try:
    if not args.ohne_pull:
      git(REPO, "pull", "--ff-only", "-q", "origin", "main")
    commit = git(REPO, "rev-parse", "--short=7", "HEAD")
    version = json.loads((REPO / "info.json").read_text(encoding="utf-8"))["version"]
  except (RuntimeError, OSError, ValueError) as err:
    say("ABBRUCH beim Holen: %s" % err)
    say("LAUF 3 | ? ? | – | hochgeladen nein")
    return 3
  say("Stand %s (%s)" % (version, commit))
  start = time.time() - 2
  rc = subprocess.run([sys.executable, str(REPO / "tools" / "pc" / "pruefstand.py"), "--factorio", args.factorio,
                       "--ordner", args.ordner] + args.tests).returncode
  folder = Path(args.ordner) / "ergebnisse"
  results = sorted(p for p in folder.glob("arrakis-*.txt")
                   if p.stat().st_mtime >= start and "-vorher-" not in p.name
                   and (p.name.startswith("arrakis-test-") or p.name.startswith("arrakis-t11-karten-")))
  if not results:
    say("LAUF %d | %s %s | – | hochgeladen nein (keine Ergebnisdatei)" % (rc, version, commit))
    return rc
  try:
    where = upload(args, results, version, commit, rc)
  except (RuntimeError, OSError) as err:
    say("ABBRUCH beim Hochladen: %s" % err)
    say("LAUF %d | %s %s | – | hochgeladen nein" % (rc, version, commit))
    return 3
  say("LAUF %d | %s %s | %s | hochgeladen ja" % (rc, version, commit, where))
  return rc


if __name__ == "__main__":
  sys.exit(main())
