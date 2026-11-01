r"""Kurze Zusammenfassung einer Prüfstand-Ergebnisdatei (arrakis-test-*.txt).

Nur Python-Standardbibliothek. pruefstand.py ruft das nach jedem Lauf auf und legt neben
arrakis-test-<Stempel>.txt die Datei arrakis-zusammenfassung-<Stempel>.txt ab; lauf.py lädt sie mit hoch.
Wer einen Lauf prüfen will, liest zuerst nur diese Datei (wenige Zeilen statt Tausende).

Aufruf von Hand (auch für alte Ergebnisdateien):
  python tools/pc/zusammenfassung.py <arrakis-test-….txt> [--ausgabe <datei>]
  ohne --ausgabe: Ausgabe auf stdout.

Format:
  Kopfzeile: SUMMARY <Datei> | Tests n | bestanden a | FEHLER b | ohne ENDE c
  je Test eine Zeile:  <Nummer> | <Name> | bestanden|FEHLER|abgebrochen|ohne ENDE | <Dauer> s | OK x FEHLER y FRAGE z
  darunter bei FEHLER/Abbruch die Fehlerzeilen (ohne ENDE zusätzlich die letzte Zeile des Tests) des Tests, eingerückt mit „  ! “ (höchstens MAX_LINES je Test).
"""
import argparse
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True

HEAD_RE = re.compile(r"^=== (\S+) (.*?) \| Tick \d+ \| Arrakis ")
END_RE = re.compile(r"^\[(\S+)\] ENDE \+[\d.]+s: (.*) \(OK (\d+), FEHLER (\d+), FRAGE (\d+), ([\d.]+) s\)$")
FAIL_RE = re.compile(r"^\[(\S+)\] FEHLER ")
ABORT_RE = re.compile(r"^\[(\S+)\] INFO \+[\d.]+s: Abgebrochen: ")
MAX_LINES = 10
MAX_CHARS = 600


def parse(lines):
  """Tests in Reihenfolge des Starts. Ein Test, der zweimal läuft, steht zweimal da."""
  tests, open_runs = [], {}
  for line in lines:
    line = line.rstrip("\r\n")
    head = HEAD_RE.match(line)
    if head:
      entry = {"id": head.group(1), "name": head.group(2), "end": None, "errors": [], "last": None}
      tests.append(entry)
      open_runs[entry["id"]] = entry
      continue
    if line.startswith("[") and "]" in line and line[1:line.index("]")] in open_runs:
      open_runs[line[1:line.index("]")]]["last"] = line
    for regex in (FAIL_RE, ABORT_RE):
      match = regex.match(line)
      if match and match.group(1) in open_runs:
        open_runs[match.group(1)]["errors"].append(line)
        break
    match = END_RE.match(line)
    if match and match.group(1) in open_runs:
      entry = open_runs.pop(match.group(1))
      entry["end"] = {"summary": match.group(2), "ok": int(match.group(3)), "fehler": int(match.group(4)),
                      "frage": int(match.group(5)), "dauer": match.group(6)}
  return tests


def state_of(entry):
  end = entry["end"]
  if not end:
    return "ohne ENDE"
  if end["summary"].startswith("abgebrochen"):
    return "abgebrochen"
  return "FEHLER" if end["fehler"] > 0 else "bestanden"


def clip(text):
  return text if len(text) <= MAX_CHARS else text[:MAX_CHARS] + " …"


def render(tests, source_name):
  states = [state_of(t) for t in tests]
  out = ["SUMMARY %s | Tests %d | bestanden %d | FEHLER %d | abgebrochen %d | ohne ENDE %d"
         % (source_name, len(tests), states.count("bestanden"), states.count("FEHLER"),
            states.count("abgebrochen"), states.count("ohne ENDE"))]
  for entry, state in zip(tests, states):
    end = entry["end"]
    if end:
      out.append("%s | %s | %s | %s s | OK %d FEHLER %d FRAGE %d"
                 % (entry["id"], entry["name"], state, end["dauer"], end["ok"], end["fehler"], end["frage"]))
    else:
      out.append("%s | %s | %s | ? s | -" % (entry["id"], entry["name"], state))
    if state != "bestanden":
      for line in entry["errors"][:MAX_LINES]:
        out.append("  ! " + clip(line))
      if not end and entry["last"]:
        out.append("  ! letzte Zeile: " + clip(entry["last"]))
      if len(entry["errors"]) > MAX_LINES:
        out.append("  ! … %d weitere Fehlerzeilen im vollen Log" % (len(entry["errors"]) - MAX_LINES))
  return "\n".join(out) + "\n"


def summary_path(result_file):
  """arrakis-test-20261101-015437.txt → arrakis-zusammenfassung-20261101-015437.txt (gleicher Ordner)."""
  name = result_file.name.replace("arrakis-test", "arrakis-zusammenfassung", 1)
  return result_file.with_name(name)


def write_summary(result_file):
  """Zusammenfassung neben die Ergebnisdatei schreiben; gibt den Pfad zurück."""
  result_file = Path(result_file)
  text = render(parse(result_file.read_text(encoding="utf-8", errors="replace").splitlines()), result_file.name)
  target = summary_path(result_file)
  target.write_text(text, encoding="utf-8")
  return target


def main(argv=None):
  ap = argparse.ArgumentParser(description="Prüfstand-Ergebnis kurz zusammenfassen")
  ap.add_argument("datei")
  ap.add_argument("--ausgabe")
  args = ap.parse_args(argv)
  source = Path(args.datei)
  text = render(parse(source.read_text(encoding="utf-8", errors="replace").splitlines()), source.name)
  if args.ausgabe:
    Path(args.ausgabe).write_text(text, encoding="utf-8")
  else:
    sys.stdout.write(text)
  return 0


if __name__ == "__main__":
  sys.exit(main())
