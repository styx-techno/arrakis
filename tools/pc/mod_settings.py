"""mod-settings.dat von Factorio lesen und schreiben (nur Python-Standardbibliothek, ab 3.8).

Aufbau laut Factorio-Wiki („Mod settings file format“, „Property tree“), gegengeprüft mit
draftsman (environment/mod_settings.py) und clusterio (ModPack.toModSettingsDat):
  Kopf: Version als 4 × uint16 LE (z. B. 2, 1, 23, 0), dann ein Byte (immer 0).
  Danach ein Property-Tree: uint8 Typ, bool „any type“, dann die Daten je Typ:
    0 nichts · 1 bool (1 Byte) · 2 Zahl (double) · 3 Text · 4 Liste · 5 Wörterbuch
    6 int64 · 7 uint64 (6 und 7 seit 2.0)
  Text: bool „leer“; sonst Länge (1 Byte, ab 255: 0xFF + uint32) und die UTF-8-Bytes.
  Liste und Wörterbuch: uint32 Anzahl, je Eintrag Schlüssel (Text wie oben, bei Listen leer)
  und Property-Tree. (draftsman liest Listeneinträge ohne Schlüssel; Wiki und clusterio mit.)
  Wurzel: Wörterbuch mit "startup", "runtime-global", "runtime-per-user"; darin je
  Einstellung ein Wörterbuch {"value": …}.

Ein Knoten ist hier ein Tupel (typ, any_flag, wert). Text ohne Inhalt („leer“) ist None.
Bei Liste und Wörterbuch ist wert eine Liste von (schlüssel, knoten). So schreibt encode()
genau die gelesenen Bytes zurück; set_setting() prüft das vor jedem Schreiben.

Kommandozeile:
  python tools/pc/mod_settings.py DATEI                                    # Inhalt zeigen
  python tools/pc/mod_settings.py DATEI --set startup arrakis-testbench true
"""
import argparse
import json
import os
import shutil
import struct
import sys
import tempfile

NONE, BOOL, NUMBER, STRING, LIST, DICT, INT, UINT = range(8)
SECTIONS = ("startup", "runtime-global", "runtime-per-user")


# Lesen -------------------------------------------------------------------------------------

def _take(data, pos, count):
  if pos[0] + count > len(data):
    raise ValueError("Datei zu kurz (Byte %d)" % pos[0])
  chunk = data[pos[0]:pos[0] + count]
  pos[0] += count
  return chunk


def _read_string(data, pos):
  if _take(data, pos, 1)[0]:
    return None
  length = _take(data, pos, 1)[0]
  if length == 255:
    length = struct.unpack("<I", _take(data, pos, 4))[0]
  raw = _take(data, pos, length)
  try:
    return raw.decode("utf-8")
  except UnicodeDecodeError:
    raise ValueError("Text ist kein UTF-8 (Byte %d)" % (pos[0] - length))


def _read_node(data, pos, depth=0):
  if depth > 64:
    raise ValueError("Property-Tree zu tief verschachtelt")
  kind, any_flag = _take(data, pos, 2)
  if kind == NONE:
    value = None
  elif kind == BOOL:
    value = _take(data, pos, 1)[0] != 0
  elif kind == NUMBER:
    value = struct.unpack("<d", _take(data, pos, 8))[0]
  elif kind == STRING:
    value = _read_string(data, pos)
  elif kind in (LIST, DICT):
    count = struct.unpack("<I", _take(data, pos, 4))[0]
    value = []
    for _ in range(count):
      key = _read_string(data, pos)
      value.append((key, _read_node(data, pos, depth + 1)))
  elif kind == INT:
    value = struct.unpack("<q", _take(data, pos, 8))[0]
  elif kind == UINT:
    value = struct.unpack("<Q", _take(data, pos, 8))[0]
  else:
    raise ValueError("unbekannter Typ %d (Byte %d)" % (kind, pos[0] - 2))
  return (kind, any_flag, value)


def decode(data):
  """Bytes → (version, kopf_byte, wurzel). version ist ein Tupel aus 4 Zahlen."""
  pos = [0]
  version = struct.unpack("<4H", _take(data, pos, 8))
  flag = _take(data, pos, 1)[0]
  root = _read_node(data, pos)
  if pos[0] != len(data):
    raise ValueError("%d Byte zu viel am Ende" % (len(data) - pos[0]))
  return version, flag, root


# Schreiben ---------------------------------------------------------------------------------

def _write_string(out, text):
  if text is None:
    out.append(b"\x01")
    return
  raw = text.encode("utf-8")
  out.append(b"\x00")
  if len(raw) < 255:
    out.append(struct.pack("<B", len(raw)))
  else:
    out.append(b"\xff" + struct.pack("<I", len(raw)))
  out.append(raw)


def _write_node(out, node):
  kind, any_flag, value = node
  out.append(struct.pack("<BB", kind, any_flag))
  if kind == NONE:
    pass
  elif kind == BOOL:
    out.append(b"\x01" if value else b"\x00")
  elif kind == NUMBER:
    out.append(struct.pack("<d", value))
  elif kind == STRING:
    _write_string(out, value)
  elif kind in (LIST, DICT):
    out.append(struct.pack("<I", len(value)))
    for key, child in value:
      _write_string(out, key)
      _write_node(out, child)
  elif kind == INT:
    out.append(struct.pack("<q", value))
  elif kind == UINT:
    out.append(struct.pack("<Q", value))
  else:
    raise ValueError("unbekannter Typ %r" % (kind,))


def encode(version, flag, root):
  """(version, kopf_byte, wurzel) → Bytes."""
  out = [struct.pack("<4H", *version), struct.pack("<B", flag)]
  _write_node(out, root)
  return b"".join(out)


# Knoten ------------------------------------------------------------------------------------

def make_node(value):
  """Python-Wert → Knoten (bool, Zahl, Text, int als int64, dict, list, None)."""
  if value is None:
    return (NONE, 0, None)
  if isinstance(value, bool):
    return (BOOL, 0, value)
  if isinstance(value, int):
    return (INT, 0, value)
  if isinstance(value, float):
    return (NUMBER, 0, value)
  if isinstance(value, str):
    return (STRING, 0, value)
  if isinstance(value, dict):
    return (DICT, 0, [(key, make_node(child)) for key, child in value.items()])
  if isinstance(value, (list, tuple)):
    return (LIST, 0, [("", make_node(child)) for child in value])
  raise ValueError("Wert %r geht nicht in einen Property-Tree" % (value,))


def to_python(node):
  """Knoten → einfacher Python-Wert (zum Anzeigen; any_flag und Textform gehen verloren)."""
  kind, _, value = node
  if kind == DICT:
    return {key: to_python(child) for key, child in value}
  if kind == LIST:
    return [to_python(child) for _, child in value]
  return value


def dict_get(node, key):
  """Kindknoten eines Wörterbuchs oder None."""
  if node[0] != DICT:
    return None
  for entry_key, child in node[2]:
    if entry_key == key:
      return child
  return None


def dict_put(node, key, child):
  """Eintrag ersetzen (Reihenfolge bleibt) oder hinten anhängen."""
  entries = node[2]
  for index, (entry_key, _) in enumerate(entries):
    if entry_key == key:
      entries[index] = (key, child)
      return
  entries.append((key, child))


def empty_tree():
  return make_node({section: {} for section in SECTIONS})


# Datei -------------------------------------------------------------------------------------

def read_file(path):
  with open(path, "rb") as handle:
    return decode(handle.read())


def get_setting(path, scope, name):
  """Wert einer Einstellung als Python-Wert oder None."""
  _, _, root = read_file(path)
  setting = dict_get(dict_get(root, scope) or (NONE, 0, None), name)
  value = setting and dict_get(setting, "value")
  return to_python(value) if value else None


def _write_atomic(path, data):
  folder = os.path.dirname(os.path.abspath(path))
  handle, temp = tempfile.mkstemp(dir=folder, prefix=os.path.basename(path) + ".", suffix=".tmp")
  try:
    with os.fdopen(handle, "wb") as out:
      out.write(data)
      out.flush()
      os.fsync(out.fileno())
    os.replace(temp, path)
  except BaseException:
    if os.path.exists(temp):
      os.remove(temp)
    raise


def set_setting(path, scope, name, value, version=None):
  """Eine Einstellung setzen. Bestehende Datei: erst prüfen, dass sie sich unverändert genau so
  zurückschreiben lässt (sonst ValueError, Datei bleibt unberührt), dann .bak anlegen und
  über eine Zwischendatei ersetzen. Fehlt die Datei, braucht es version (4 Zahlen).
  Gibt den alten Wert (Python) zurück."""
  if scope not in SECTIONS:
    raise ValueError("Bereich %r gibt es nicht (%s)" % (scope, ", ".join(SECTIONS)))
  exists = os.path.exists(path)
  if exists:
    with open(path, "rb") as handle:
      original = handle.read()
    try:
      version, flag, root = decode(original)
    except ValueError as err:
      raise ValueError("%s lässt sich nicht lesen: %s. Datei löschen, dann wird sie neu angelegt." % (path, err))
    if encode(version, flag, root) != original:
      raise ValueError("%s lässt sich nicht verlustfrei neu schreiben (unbekannte Form). "
                       "Nichts geändert. Datei löschen, dann wird sie neu angelegt." % path)
    if root[0] != DICT:
      raise ValueError("%s: Wurzel ist kein Wörterbuch. Nichts geändert." % path)
  else:
    if not version or len(version) != 4:
      raise ValueError("Neue mod-settings.dat braucht eine Version aus 4 Zahlen, z. B. (2, 1, 23, 0)")
    flag, root = 0, empty_tree()
  section = dict_get(root, scope)
  if section is None or section[0] != DICT:
    section = make_node({})
    dict_put(root, scope, section)
  setting = dict_get(section, name)
  old_value = None
  if setting is None or setting[0] != DICT:
    setting = make_node({})
    dict_put(section, name, setting)
  else:
    old = dict_get(setting, "value")
    old_value = to_python(old) if old else None
    # Zahl bleibt Zahl, wenn die Datei sie als double führt.
    if old and old[0] == NUMBER and isinstance(value, int) and not isinstance(value, bool):
      value = float(value)
  dict_put(setting, "value", make_node(value))
  data = encode(version, flag, root)
  # Gegenprobe: neu gelesen steht der Wert drin.
  check = decode(data)[2]
  if to_python(dict_get(dict_get(dict_get(check, scope), name), "value")) != value:
    raise ValueError("Gegenprobe nach dem Setzen ging schief. Nichts geändert.")
  if exists:
    shutil.copy2(path, path + ".bak")
  _write_atomic(path, data)
  return old_value


def _parse_value(text):
  low = text.lower()
  if low in ("true", "false"):
    return low == "true"
  try:
    return int(text)
  except ValueError:
    pass
  try:
    return float(text)
  except ValueError:
    return text


def main(argv=None):
  # Windows mit umgeleiteter Ausgabe (Pipe, Datei) schreibt in der ANSI-Codepage: „→“ u. Ä.
  # ersetzen statt mit UnicodeEncodeError abzubrechen.
  for stream in (sys.stdout, sys.stderr):
    try:
      stream.reconfigure(errors="replace")
    except (AttributeError, ValueError):
      pass
  ap = argparse.ArgumentParser(description="mod-settings.dat anzeigen oder eine Einstellung setzen.")
  ap.add_argument("datei", help="Pfad zur mod-settings.dat")
  ap.add_argument("--set", nargs=3, metavar=("BEREICH", "NAME", "WERT"),
                  help="z. B. --set startup arrakis-testbench true")
  ap.add_argument("--neue-version", metavar="VERSION", help="nur für eine neue Datei: Factorio-Version, z. B. 2.1.23")
  args = ap.parse_args(argv)
  try:
    if args.set:
      version = None
      if args.neue_version:
        version = tuple(int(n) for n in (args.neue_version.split(".") + ["0", "0", "0"])[:3]) + (0,)
      old = set_setting(args.datei, args.set[0], args.set[1], _parse_value(args.set[2]), version)
      print("%s/%s: %r → %r" % (args.set[0], args.set[1], old, _parse_value(args.set[2])))
    else:
      version, _, root = read_file(args.datei)
      print("Version %s" % ".".join(str(n) for n in version))
      print(json.dumps(to_python(root), indent=2, ensure_ascii=False))
  except (OSError, ValueError) as err:
    print("mod-settings.dat: %s" % err, file=sys.stderr)
    return 2
  return 0


if __name__ == "__main__":
  sys.exit(main())
