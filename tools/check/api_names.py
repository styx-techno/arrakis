#!/usr/bin/env python3
"""Statische Prüfung der Factorio-API-Namen im Laufzeitcode von Arrakis.

Liest control.lua und scripts/**/*.lua als Text (es wird nichts ausgeführt) und vergleicht
die benutzten Namen mit den Typdefinitionen der Factorio-Laufzeit-API:

  1. defines-Pfade, die es in 2.0.75 (bzw. 2.1.20) nicht gibt
  2. defines.events.X, die es in 2.0.75 nicht gibt; dazu Felder von event.X
  3. Methodenaufrufe x.name(...), x.name{...}, x.name"...", deren Name weder ein Member
     einer Lua*-Klasse noch eine Lua-Standardfunktion noch eine eigene Funktion ist
     (außerdem: Stdlib-Module, Doppelpunkt-Aufrufe, eigene Modultabellen wie tb)
  4. Schreibzugriffe x.name = ..., wenn name in JEDER Klasse schreibgeschützt ist
     (2.0.75; zusätzlich: erst in 2.1.20 schreibgeschützt; und wo der Typ bekannt ist)
  5. Member, die es in 2.0.75 gibt, in 2.1.20 aber in keiner Klasse mehr
  6. Globale Einstiegspunkte (game.*, script.*, rendering.*, helpers.*, commands.*,
     settings.*, prototypes.*, remote.*, rcon.*, storage) und unbekannte Namen darin
  7. Typ-Plausibilität: Wo sich der Typ des Empfängers ableiten lässt (game.surfaces[…] →
     LuaSurface, local e = surface.create_entity{…} → LuaEntity, for _, u in
     pairs(surface.get_segmented_units()) → LuaSegmentedUnit, d.car = car → d.car,
     OWN_RETURNS, RECEIVER_HINTS), muss der Member auf genau dieser Klasse (oder einer
     Unterklasse) existieren; Schreiben nur, wenn er dort beschreibbar ist.
  8. Tabellen-Argumente: Bei x.methode{…} / x.methode(…, {…}) und x.attr = {…} mit bekanntem
     Typ müssen die Schlüssel im Parametertyp vorkommen (z. B. create_entity{positon = …}).

Treffer sind Kandidaten für eine Prüfung von Hand (Datei:Zeile). Bestätigte Fehlalarme
kommen in die Listen unten (CALL_WHITELIST, WRITE_WHITELIST, DATA_ROOTS). Grenzen: Felder
eigener Datentabellen (run.data …) und Variablen ohne ableitbaren Typ prüfen nur 3–5 nach
Namen; Werte, Einheiten und nil-Zugriffe prüft das Skript nicht.

Einrichtung (einmalig; npm nur zum Herunterladen der Typdateien, nicht zum Ausführen):
  cd tools/check && mkdir api && cd api      # Standardort, wird automatisch gefunden
  npm pack typed-factorio@3.36.0      # API 2.0.75 → package/runtime/generated/*.d.ts
  npm pack factorio-types@1.2.69      # API 2.1.20 → package/dist/*.d.ts
  mkdir typed-factorio-3.36.0 factorio-types-1.2.69
  tar xzf typed-factorio-3.36.0.tgz -C typed-factorio-3.36.0
  tar xzf factorio-types-1.2.69.tgz -C factorio-types-1.2.69
  # optional (für require("util") und __core__/lualib/event_handler), wie bei datastage.py:
  git clone --depth 1 --branch 2.0.77 https://github.com/wube/factorio-data fd2077

Aufruf (aus dem Repo-Root; nur Python-Standardbibliothek):
  python3 tools/check/api_names.py [--api20 PFAD] [--api21 PFAD] [--fd PFAD] [-v]
    --api20  Ordner mit classes.d.ts, defines.d.ts, events.d.ts, concepts.d.ts
             von typed-factorio 3.36.0 (…/package/runtime/generated)
    --api21  dasselbe von factorio-types 1.2.69 (…/package/dist)
    --fd     Vanilla-Daten 2.0.77 (Ordner mit core/lualib), optional
    --repo   anderer Mod-Ordner (z. B. eine Kopie mit absichtlichen Fehlern zum Testen)
    -v       zusätzlich jeden Zugriff mit abgeleitetem Typ und jeden ohne Typ auflisten

Exit-Code: 0 = keine Treffer der Stufe FEHLER, 1 = Treffer, 2 = Selbsttest des Parsers gescheitert.
"""
import argparse
import bisect
import difflib
import glob
import os
import re
import sys
from collections import OrderedDict, defaultdict

# ---------------------------------------------------------------------------------------------
# Einstellungen (von Hand gepflegt)
# ---------------------------------------------------------------------------------------------

# Standardpfade: zuerst tools/check/api/… (siehe Einrichtung), sonst die Ablage der Entwicklungssitzung.
_HERE = os.path.dirname(os.path.abspath(__file__))
_SCRATCH = "/tmp/claude-0/-home-claude-arrakis/9eef4ee3-2856-53aa-b01e-e92827ccbebf/scratchpad"


def _first_existing(*paths):
  for path in paths:
    if os.path.isdir(path):
      return path
  return paths[-1]


DEFAULT_API20 = _first_existing(os.path.join(_HERE, "api", "typed-factorio-3.36.0", "package", "runtime", "generated"),
                                _SCRATCH + "/api/typed-factorio-3.36.0/package/runtime/generated")
DEFAULT_API21 = _first_existing(os.path.join(_HERE, "api", "factorio-types-1.2.69", "package", "dist"),
                                _SCRATCH + "/api/factorio-types-1.2.69/package/dist")
DEFAULT_FD = _first_existing(os.path.join(os.path.dirname(os.path.dirname(_HERE)), "fd2077"),
                             "/tmp/claude-0/-home-claude/9eef4ee3-2856-53aa-b01e-e92827ccbebf/scratchpad/fd2077")

# Namen, die als Methodenaufruf erlaubt sind, obwohl der Prüfer sie nirgends findet.
CALL_WHITELIST = set()

# Schreibzugriffe auf eigene Datentabellen, deren Feld zufällig wie ein schreibgeschütztes
# API-Attribut heißt. Einträge: "name" (überall) oder "empfänger.name" (genau diese Kette,
# z. B. "d.position"). Nur nach Prüfung von Hand eintragen.
WRITE_WHITELIST = {
  # t_flyer: lane/check sind Messtabellen in run.data (Höchsttempo, Prüf-Tick)
  "lane.max_speed", "check.tick",
  # t_map: d = run.data, f = Spicefeld-Datensatz (Gruppenliste, Felsabstand in Kacheln)
  "d.groups", "f.grid",
  # t_worm: p/lane/check = Datensätze je Teil (Wurm-Referenz, Weglänge, Höchsttempo, Modusname)
  "p.unit", "p.path", "p.max_speed", "p.mode", "lane.unit", "check.unit",
}

# Wurzel-Bezeichner, die immer eigene Daten (keine API-Objekte) sind: für sie entfallen die
# Prüfungen 4 und 5 (Lesen/Schreiben von Feldern), Aufrufe werden weiter geprüft.
DATA_ROOTS = set()

# Bezeichner, die überall eine eigene Modultabelle meinen: name -> (Datei, Tabellenname).
# Zugriffe tb.x müssen dann in dieser Datei als tb.x definiert sein.
MODULE_PARAMS = {"tb": ("scripts/testbench/runner.lua", "tb")}

# Rückgabetypen eigener Funktionen (für Prüfung 7): "tabelle.funktion" -> API-Klasse.
OWN_RETURNS = {
  "tb.player": "LuaPlayer",
  "tb.surface": "LuaSurface",
  "tb.hold_surface": "LuaSurface",
  "tb.worm_force": "LuaForce",
  "tb.dummy_driver": "LuaEntity",
  "arrakis_surface.get_or_create": "LuaSurface",
  # lokale Funktionen: "datei.lua:name"
  "t_worm.lua:create_worm": "LuaSegmentedUnit",
  "t_worm.lua:create_entity": "LuaEntity",
  "t_worm.lua:create_harvester": "LuaEntity",
  "t_worm.lua:create_flyer": "LuaEntity",
  "t_flyer.lua:create_flyer": "LuaEntity",
}

# Variablennamen -> vermutete API-Klasse, wenn der Typ sonst nicht ableitbar ist (Parameter,
# Rückgaben unbekannter Funktionen). Nur eindeutige Namen eintragen; Treffer daraus sind
# als „Name-Hinweis“ markiert.
RECEIVER_HINTS = {
  "surface": "LuaSurface",
  "player": "LuaPlayer",
  "force": "LuaForce",
  "inventory": "LuaInventory",
  "character": "LuaEntity",
  "entity": "LuaEntity",
  "vehicle": "LuaEntity",
  "flyer": "LuaEntity",
  "harvester": "LuaEntity",
  "combinator": "LuaEntity",
  "sticker": "LuaEntity",
  "behavior": "LuaControlBehavior",
  # nur in einer Datei eindeutig: "datei.lua:name"
  "t_harvester.lua:car": "LuaEntity",
  "t_harvester.lua:driver": "LuaEntity",
  "t_harvester.lua:inserter": "LuaEntity",
  "t_harvester.lua:burner": "LuaBurner",
  "t_harvester.lua:clone": "LuaEntity",
  "t_worm.lua:unit": "LuaSegmentedUnit",
}

# Parameter-/Variablennamen für Ereignis-Tabellen: Felder müssen in irgendeinem Ereignis vorkommen.
EVENT_NAMES = {"event"}

# Globale Einstiegspunkte der Laufzeit -> Klasse.
GLOBAL_ROOTS = OrderedDict([
  ("game", "LuaGameScript"),
  ("script", "LuaBootstrap"),
  ("rendering", "LuaRendering"),
  ("helpers", "LuaHelpers"),
  ("commands", "LuaCommandProcessor"),
  ("settings", "LuaSettings"),
  ("prototypes", "LuaPrototypes"),
  ("remote", "LuaRemote"),
  ("rcon", "LuaRCON"),
])

# Lua 5.2 (wie in Factorio) ---------------------------------------------------------------------
LUA_BASE = set("""assert collectgarbage error getmetatable ipairs load next pairs pcall print rawequal
rawget rawlen rawset require select setmetatable tonumber tostring type xpcall""".split())
# Factorio-eigene globale Funktionen
FACTORIO_GLOBAL_FUNCS = {"log", "localised_print", "table_size"}
LUA_MODULES = {
  "string": set("byte char dump find format gmatch gsub len lower match rep reverse sub upper".split()),
  "table": set("concat insert pack remove sort unpack".split()),
  "math": set("""abs acos asin atan atan2 ceil cos cosh deg exp floor fmod frexp huge ldexp log log10 max
min modf pi pow rad random randomseed sin sinh sqrt tan tanh""".split()),
  "bit32": set("arshift band bnot bor btest bxor extract lrotate lshift replace rrotate rshift".split()),
  "debug": set("""debug getuservalue gethook getinfo getlocal getmetatable getregistry getupvalue sethook
setlocal setmetatable setupvalue setuservalue traceback upvalueid upvaluejoin""".split()),
  "serpent": set("block line dump load".split()),
}
# Laut Factorio-Doku („Libraries and functions“) in Factorio nicht vorhanden bzw. Lua-5.1-Reste.
UNAVAILABLE_MODULES = {"os", "io", "coroutine"}
UNAVAILABLE_FUNCS = {"dofile", "loadfile", "loadstring", "module", "setfenv", "getfenv", "unpack"}
LUA_KEYWORDS = set("""and break do else elseif end false for function goto if in local nil not or repeat
return then true until while""".split())

# ---------------------------------------------------------------------------------------------
# TypeScript-Deklarationen (d.ts) lesen
# ---------------------------------------------------------------------------------------------

TS_NAME = r"[A-Za-z_$][\w$]*"
TS_STR_RE = re.compile(r'"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'|`(?:\\.|[^`\\])*`')
MEMBER_RE = re.compile(r"^\s*(readonly\s+)?(?:(get|set)\s+)?(" + TS_NAME + r"|\"[^\"]+\"|'[^']+')(\?)?\s*([:(<])")
IFACE_RE = re.compile(r"^\s*(?:export\s+)?(?:declare\s+)?interface\s+(" + TS_NAME + r")\b")


def strip_ts_comments(text):
  """Entfernt /* */- und //-Kommentare; Zeilenumbrüche und String-Literale bleiben stehen."""
  out = []
  i, n = 0, len(text)
  while i < n:
    c = text[i]
    if c == "/" and text.startswith("/*", i):
      j = text.find("*/", i + 2)
      j = n if j < 0 else j + 2
      out.append(re.sub(r"[^\n]", " ", text[i:j]))
      i = j
    elif c == "/" and text.startswith("//", i):
      j = text.find("\n", i)
      j = n if j < 0 else j
      out.append(" " * (j - i))
      i = j
    elif c in "\"'`":
      j = i + 1
      while j < n and text[j] != c:
        if text[j] == "\\":
          j += 1
        elif text[j] == "\n" and c != "`":
          break
        j += 1
      out.append(text[i:j + 1])
      i = j + 1
    else:
      out.append(c)
      i += 1
  return "".join(out)


def bracket_delta(line):
  s = TS_STR_RE.sub('""', line)
  return sum(s.count(c) for c in "{[(") - sum(s.count(c) for c in "}])")


CUSTOM_NAME_RE = re.compile(r"/\*\*(?:(?!\*/).)*?@customName\s+([\w-]+)(?:(?!\*/).)*\*/\s*", re.S)


def lines_with_depth(path):
  """Zeilen ohne Kommentare, Klammertiefe am Zeilenanfang und @customName-Umbenennungen
  (factorio-types: 'x_write' steht für Schreiben auf x, 'active_trigger' für 'active-trigger')."""
  raw = open(path, encoding="utf-8").read()
  custom = {}
  for m in CUSTOM_NAME_RE.finditer(raw):
    custom[raw.count("\n", 0, m.end())] = m.group(1)
  text = strip_ts_comments(raw)
  lines = text.split("\n")
  depths, d = [], 0
  for line in lines:
    depths.append(d)
    d += bracket_delta(line)
  return lines, depths, custom


def match_close(s, i, open_c, close_c):
  """Index der schließenden Klammer zu s[i] == open_c (Strings werden übersprungen)."""
  depth = 0
  j = i
  while j < len(s):
    c = s[j]
    if c in "\"'`":
      m = TS_STR_RE.match(s, j)
      if m:
        j = m.end()
        continue
    if c == open_c:
      depth += 1
    elif c == close_c:
      depth -= 1
      if depth == 0:
        return j
    j += 1
  return None


def clean_type(t):
  t = re.sub(r"\s+", " ", t or "").strip()
  return t.rstrip(";").strip()


class Member:
  __slots__ = ("name", "cls", "line", "method", "attr", "readable", "writable", "type_text", "ret_text", "params",
               "write_text")

  def __init__(self, name, cls, line):
    self.name, self.cls, self.line = name, cls, line
    self.method = self.attr = self.readable = self.writable = False
    self.type_text = self.ret_text = None
    self.params = []  # Parameterlisten-Texte, je Überladung einer
    self.write_text = None  # Typ beim Schreiben (set-Accessor oder Attributtyp)

  def describe(self):
    if self.method and not self.attr:
      return "Methode"
    if self.writable and self.readable:
      return "Attribut, beschreibbar"
    if self.writable:
      return "Attribut, nur schreibbar"
    return "Attribut, readonly"


def parse_interfaces(path):
  """Alle interface-Blöcke einer d.ts: name -> {members, extends, line}."""
  lines, depths, custom = lines_with_depth(path)
  ifaces = OrderedDict()
  stack = []  # [name, body_depth]
  for i, line in enumerate(lines):
    d0 = depths[i]
    while stack and d0 < stack[-1][1]:
      stack.pop()
    if stack and d0 == stack[-1][1]:
      m = MEMBER_RE.match(line)
      if m:
        j = i + 1
        while j < len(lines) and depths[j] > stack[-1][1]:
          j += 1
        add_member(ifaces[stack[-1][0]], m, " ".join(lines[i:j]), i + 1, custom.get(i))
    m = IFACE_RE.match(line)
    if m:
      header, k = line, i
      while "{" not in header and k + 1 < len(lines) and k < i + 10:
        k += 1
        header += " " + lines[k]
      if "{" not in header:
        continue
      name = m.group(1)
      rest = header[m.end():header.index("{")]
      rest = re.sub(r"<[^<>]*(?:<[^<>]*>[^<>]*)*>", "", rest)
      extends = []
      em = re.search(r"\bextends\b(.*)$", rest)
      if em:
        extends = [x.strip() for x in em.group(1).split(",") if x.strip()]
      info = ifaces.setdefault(name, {"members": OrderedDict(), "extends": [], "line": i + 1, "file": path})
      info["extends"] += extends
      stack.append([name, depths[i] + 1])
  return ifaces


def add_member(info, m, full, line_no, custom_name=None):
  ro, acc, name, _opt, ch = m.groups()
  name = custom_name or name.strip("\"'")
  mem = info["members"].get(name)
  if mem is None:
    mem = Member(name, None, line_no)
    info["members"][name] = mem
  rest = full[m.end() - 1:]  # beginnt mit ':' '(' oder '<'
  if acc in ("get", "set") or ch in "(<":
    ret = None
    k = 0
    if rest.startswith("<"):
      k = match_close(rest, 0, "<", ">")
      k = None if k is None else k + 1
    params = None
    if k is not None:
      p = rest.find("(", k)
      q = match_close(rest, p, "(", ")") if p >= 0 else None
      if q is not None:
        params = rest[p + 1:q]
        after = rest[q + 1:].lstrip()
        if after.startswith(":"):
          ret = clean_type(after[1:])
    if acc == "get":
      mem.attr = mem.readable = True
      mem.type_text = mem.type_text or ret
    elif acc == "set":
      mem.attr = mem.writable = True
      if params is not None:
        pt = param_types(params)
        if pt and pt[0]:
          mem.write_text = mem.write_text or clean_type(pt[0])
    else:
      mem.method = True
      mem.ret_text = mem.ret_text or ret
      if params is not None:
        mem.params.append(params)
  else:
    mem.attr = mem.readable = True
    this_type = clean_type(rest[1:])
    mem.type_text = mem.type_text or this_type
    if not ro:
      mem.writable = True
      mem.write_text = mem.write_text or this_type


ALIAS_RE = re.compile(r"^\s*(?:export\s+)?(?:declare\s+)?type\s+(" + TS_NAME + r")\s*(?:<[^=]*>)?\s*=(.*)$")
PRIMITIVE_TYPES = {"string", "number", "boolean", "any", "unknown", "never", "void", "object", "nil", "null",
                   "undefined", "true", "false", "bigint", "symbol", "Function"}


def parse_type_aliases(path):
  """type X = … (auch mehrzeilige Unions) -> {X: Text}."""
  lines, depths, _custom = lines_with_depth(path)
  out = {}
  i = 0
  while i < len(lines):
    m = ALIAS_RE.match(lines[i])
    if not m:
      i += 1
      continue
    d = depths[i]
    parts = [m.group(2)]
    j = i + 1
    while j < len(lines):
      k = j
      while k < len(lines) and not lines[k].strip():
        k += 1
      if k >= len(lines):
        break
      nxt = lines[k].strip()
      if depths[k] > d or nxt.startswith(("|", "&")) or parts[-1].rstrip().endswith(("|", "&", "=", ",", "<")):
        parts.append(lines[k])
        j = k + 1
      else:
        break
    out.setdefault(m.group(1), " ".join(parts))
    i = j
  return out


def inline_keys(inner):
  """Schlüssel eines Objekttyps { a?: T  readonly b: U … } -> {Schlüssel: Typtext}."""
  keys = OrderedDict()
  depth = 0
  marks = []
  i = 0
  key_re = re.compile(r"(?:readonly\s+)?(" + TS_NAME + r"|\"[^\"]+\"|'[^']+')\s*\??\s*:")
  while i < len(inner):
    c = inner[i]
    if c in "\"'`":
      m = TS_STR_RE.match(inner, i)
      if m:
        i = m.end()
        continue
    if c in "{([<":
      depth += 1
    elif c in "})]>" and not (c == ">" and i > 0 and inner[i - 1] == "="):
      depth -= 1
    elif depth == 0 and (i == 0 or inner[i - 1] in " \t\n;,"):
      m = key_re.match(inner, i)
      if m:
        marks.append((m.start(), m.end(), m.group(1).strip("\"'")))
        i = m.end()
        continue
    i += 1
  for n, (a, b, key) in enumerate(marks):
    end = marks[n + 1][0] if n + 1 < len(marks) else len(inner)
    keys.setdefault(key, []).append(clean_type(inner[b:end].rstrip(" ;,")))
  return keys


def parse_defines(path):
  """defines.d.ts -> (Container-Pfade, Blatt-Pfade) relativ zu 'defines' als Tupel."""
  lines, depths, custom = lines_with_depth(path)
  containers, leaves = set(), set()
  stack = []  # (pfad, body_depth, art)
  key = r"(" + TS_NAME + r"|\"[^\"]*\"|'[^']*')"
  for i, line in enumerate(lines):
    d0 = depths[i]
    while stack and d0 < stack[-1][1]:
      stack.pop()
    if not stack:
      if re.match(r"\s*(?:export\s+)?(?:declare\s+)?namespace\s+defines\s*\{", line):
        stack.append(((), d0 + 1, "namespace"))
        containers.add(())
      continue
    if d0 != stack[-1][1]:
      continue
    path_, _, kind = stack[-1]
    m = re.match(r"\s*(?:export\s+)?(?:declare\s+)?(?:const\s+)?(enum|namespace|interface)\s+(" + TS_NAME + r")\s*\{(.*)$", line)
    if m:
      p = path_ + (custom.get(i, m.group(2)),)
      containers.add(p)
      inner = m.group(3)
      if "}" in inner:
        for nm in re.findall(key + r"\s*(?:=[^,}]*)?\s*[,}]", inner):
          leaves.add(p + (nm.strip("\"'"),))
      else:
        stack.append((p, d0 + 1, m.group(1)))
      continue
    m = re.match(r"\s*" + key + r"\??\s*:\s*\{(.*)$", line)
    if m and kind in ("interface", "object"):
      p = path_ + (custom.get(i, m.group(1).strip("\"'")),)
      containers.add(p)
      if "}" not in m.group(2):
        stack.append((p, d0 + 1, "object"))
      continue
    m = re.match(r"\s*(?:export\s+)?(?:const|let)\s+(" + TS_NAME + r")\s*:", line)
    if m:
      leaves.add(path_ + (custom.get(i, m.group(1)),))
      continue
    if kind == "enum":
      m = re.match(r"\s*" + key + r"\s*(?:=.*)?,?\s*$", line)
      if m:
        leaves.add(path_ + (custom.get(i, m.group(1).strip("\"'")),))
    elif kind in ("interface", "object"):
      m = re.match(r"\s*" + key + r"\??\s*:", line)
      if m:
        leaves.add(path_ + (custom.get(i, m.group(1).strip("\"'")),))
  leaves -= containers
  return containers, leaves


class Api:
  """Eine API-Version: Klassen (mit Vererbung), defines, Ereignisfelder."""

  def __init__(self, label, folder, exclude_re):
    self.label = label
    self.folder = folder
    classes_path = os.path.join(folder, "classes.d.ts")
    all_ifaces = parse_interfaces(classes_path)
    self.all_ifaces = all_ifaces
    self.classes = OrderedDict((k, v) for k, v in all_ifaces.items() if not re.search(exclude_re, k))
    # typed-factorio: LuaGuiElement ist ein Typ-Alias über BaseGuiElement + *GuiElementMembers.
    if "LuaGuiElement" not in self.classes and "BaseGuiElement" in self.classes:
      merged = {"members": OrderedDict(), "extends": [], "line": self.classes["BaseGuiElement"]["line"], "file": classes_path}
      for name, info in self.classes.items():
        if name == "BaseGuiElement" or name.endswith("GuiElementMembers"):
          for mname, mem in info["members"].items():
            old = merged["members"].get(mname)
            if old is None:
              merged["members"][mname] = mem
            else:
              comb = Member(mname, "LuaGuiElement", old.line)
              for a in ("method", "attr", "readable", "writable"):
                setattr(comb, a, getattr(old, a) or getattr(mem, a))
              comb.type_text = old.type_text or mem.type_text
              comb.ret_text = old.ret_text or mem.ret_text
              merged["members"][mname] = comb
      self.classes["LuaGuiElement"] = merged
    for cname, info in list(all_ifaces.items()) + list(self.classes.items()):
      for mem in info["members"].values():
        if mem.cls is None:
          mem.cls = cname
    self._members_cache = {}
    # Name -> Liste der eigenen Deklarationen (ohne Vererbung)
    self.by_name = defaultdict(list)
    for cname, info in self.classes.items():
      for mname, mem in info["members"].items():
        self.by_name[mname].append(mem)
    self.def_containers, self.def_leaves = parse_defines(os.path.join(folder, "defines.d.ts"))
    # Für Tabellen-Argumente: Konzept-Interfaces und Typ-Aliase
    concepts_path = os.path.join(folder, "concepts.d.ts")
    concept_ifaces = parse_interfaces(concepts_path) if os.path.exists(concepts_path) else {}
    self.type_ifaces = OrderedDict(concept_ifaces)
    self.type_ifaces.update(all_ifaces)
    self.aliases = {}
    for f in ("concepts.d.ts", "classes.d.ts"):
      fp = os.path.join(folder, f)
      if os.path.exists(fp):
        for k, v in parse_type_aliases(fp).items():
          self.aliases.setdefault(k, v)
    self._iface_members_cache = {}
    self.event_fields = set()
    self._event_types = defaultdict(set)
    for info in parse_interfaces(os.path.join(folder, "events.d.ts")).values():
      self.event_fields.update(info["members"])
      for mname, mem in info["members"].items():
        self._event_types[mname].add(self.resolve_type(mem.type_text) if mem.type_text else None)
    ed = concept_ifaces.get("EventData")
    if ed:
      self.event_fields.update(ed["members"])

  def iface_members(self, name):
    """Member eines (Konzept-)Interfaces inklusive extends."""
    if name in self._iface_members_cache:
      return self._iface_members_cache[name]
    self._iface_members_cache[name] = {}
    info = self.type_ifaces.get(name)
    result = {}
    if info:
      for base in info["extends"]:
        b = re.match(TS_NAME, base)
        if b:
          result.update(self.iface_members(b.group(0)))
      result.update(info["members"])
    self._iface_members_cache[name] = result
    return result

  def object_keys(self, text, seen=frozenset()):
    """Erlaubte Schlüssel eines Tabellen-Typs: {Schlüssel: [Typtexte]}; leer, wenn der Typ keine
    benannten Schlüssel hat (Zahl, Array …); None, wenn er nicht auflösbar ist."""
    t = clean_type(text)
    result = OrderedDict()
    any_obj = False

    def merge(d):
      for k, v in d.items():
        result.setdefault(k, [])
        result[k] += v

    for part in split_top(t, "|"):
      part = part.strip()
      while part.startswith("(") and match_close(part, 0, "(", ")") == len(part) - 1:
        part = part[1:-1].strip()
      if part.startswith("readonly "):
        part = part[9:].strip()
      if part in ("", "nil", "null", "undefined"):
        continue
      inter = split_top(part, "&")
      if len(inter) > 1:
        for sub in inter:
          r = self.object_keys(sub, seen)
          if r is None:
            return None
          merge(r)
        any_obj = True
        continue
      if part.startswith("{"):
        e = match_close(part, 0, "{", "}")
        if e != len(part) - 1:
          return None
        merge(inline_keys(part[1:-1]))
        any_obj = True
        continue
      if part.endswith("]") or part.startswith("[") or part[0] in "\"'`" or re.match(r"^-?\d", part):
        continue  # Array, Tupel, Literal: keine benannten Schlüssel
      m = re.match(TS_NAME, part)
      if not m:
        return None
      name = m.group(0)
      if name in PRIMITIVE_TYPES or name.startswith("defines."):
        continue
      if name.startswith("Lua") and name in self.classes:
        continue  # Laufzeitobjekt statt Tabelle
      if name in self.type_ifaces:
        merge({k: [mem.type_text or ""] for k, mem in self.iface_members(name).items()})
        any_obj = True
        continue
      if name in self.aliases and name not in seen:
        r = self.object_keys(self.aliases[name], seen | {name})
        if r is None:
          return None
        if r:
          merge(r)
          any_obj = True
        continue
      return None  # unbekannter Typname (generisch, Rekursion …): nicht prüfbar
    return result if any_obj else OrderedDict()  # leer: kein Objekttyp (nichts zu prüfen)

  def event_field_type(self, name):
    t = self._event_types.get(name)
    if t and len(t) == 1:
      return next(iter(t))
    return None

  def members_of(self, cls):
    """Member einer Klasse inklusive geerbter (extends)."""
    if cls in self._members_cache:
      return self._members_cache[cls]
    self._members_cache[cls] = {}
    info = self.all_ifaces.get(cls) or self.classes.get(cls)
    if cls == "LuaGuiElement":
      info = self.classes.get(cls)
    result = {}
    if info:
      for base in info["extends"]:
        result.update(self.members_of(base))
      result.update(info["members"])
    self._members_cache[cls] = result
    return result

  def member(self, cls, name):
    return self.members_of(cls).get(name)

  def subclasses(self, cls):
    """Alle Klassen, die (auch über Zwischenstufen) von cls erben."""
    if not hasattr(self, "_subs"):
      self._subs = defaultdict(set)
      for cname, info in self.classes.items():
        for base in info["extends"]:
          b = re.match(TS_NAME, base)
          if b:
            self._subs[b.group(0)].add(cname)
    out, todo = set(), [cls]
    while todo:
      for sub in self._subs.get(todo.pop(), ()):
        if sub not in out:
          out.add(sub)
          todo.append(sub)
    return out

  def member_or_sub(self, cls, name):
    """(Member, Klassen) – auf cls selbst oder, wenn dort nicht vorhanden, auf Unterklassen
    (z. B. LuaControlBehavior -> LuaContainerControlBehavior.read_contents)."""
    mem = self.member(cls, name)
    if mem is not None:
      return mem, [cls]
    subs = sorted(c for c in self.subclasses(cls) if self.member(c, name) is not None)
    if subs:
      return self.member(subs[0], name), subs
    return None, []

  def has_name(self, name):
    return name in self.by_name

  def writable_anywhere(self, name):
    return any(m.writable for m in self.by_name.get(name, ()))

  def attr_anywhere(self, name):
    return any(m.attr for m in self.by_name.get(name, ()))

  def method_anywhere(self, name):
    return any(m.method for m in self.by_name.get(name, ()))

  def define_status(self, path_):
    """'ok' | ('fehlt', längster gültiger Präfix)."""
    p = tuple(path_)
    if p in self.def_containers or p in self.def_leaves:
      return "ok"
    for k in range(len(p) - 1, -1, -1):
      if p[:k] in self.def_containers or p[:k] in self.def_leaves:
        return ("fehlt", p[:k])
    return ("fehlt", ())

  # Typen --------------------------------------------------------------------------------
  def resolve_type(self, text):
    """Typtext -> ('obj', {Klassen}) | ('idx', {Klassen}) | None."""
    t = clean_type(text)
    if not t:
      return None
    m = re.match(r"^LuaMultiReturn<\s*\[(.*)\]\s*>$", t)
    if m:
      t = split_top(m.group(1), ",")[0].strip()
    while t.startswith("(") and t.endswith(")") and match_close(t, 0, "(", ")") == len(t) - 1:
      t = t[1:-1].strip()
    kinds, classes = set(), set()
    for part in split_top(t, "|"):
      part = part.strip()
      if part in ("nil", "null", "undefined", ""):
        continue
      if part.startswith("readonly "):
        part = part[9:].strip()
      if self.is_class(part):
        kinds.add("obj")
        classes.add(part)
        continue
      m = re.match(r"^(?:LuaCustomTable|LuaTable|LuaMap|LuaReadonlyMap|Record)<(.*)>$", part)
      if m:
        targs = split_top(m.group(1), ",")
        last = targs[1].strip() if len(targs) > 1 else ""  # <K, V> bzw. <K, V, IterKey>
        if self.is_class(last):
          kinds.add("idx")
          classes.add(last)
          continue
        return None
      m = re.match(r"^\(?\s*(" + TS_NAME + r")\s*\)?\[\]$", part)
      if m and self.is_class(m.group(1)):
        kinds.add("idx")
        classes.add(m.group(1))
        continue
      return None
    if len(kinds) != 1 or not classes:
      return None
    return (kinds.pop(), frozenset(classes))

  def is_class(self, name):
    return name.startswith("Lua") and (name in self.classes or name in self.all_ifaces)


def split_top(s, sep):
  """Teilt s an sep, aber nicht innerhalb von <>, (), [], {}."""
  parts, depth, cur = [], 0, []
  i = 0
  while i < len(s):
    c = s[i]
    if c in "<([{":
      depth += 1
    elif c in ">)]}":
      if not (c == ">" and i > 0 and s[i - 1] == "="):
        depth -= 1
    if c == sep and depth == 0:
      parts.append("".join(cur))
      cur = []
    else:
      cur.append(c)
    i += 1
  parts.append("".join(cur))
  return parts


# ---------------------------------------------------------------------------------------------
# Lua lesen
# ---------------------------------------------------------------------------------------------

LONG_OPEN = re.compile(r"\[(=*)\[")
IDENT = r"[A-Za-z_]\w*"


class LuaFile:
  def __init__(self, path, rel):
    self.path, self.rel = path, rel
    self.src = open(path, encoding="utf-8").read()
    self.code, self.code_s = lex_lua(self.src)
    self.nl = [m.start() for m in re.finditer("\n", self.src)]
    self.blocks = find_blocks(self.code)
    self.inner = innermost_brackets(self.code)
    self.bindings = defaultdict(list)  # name -> [(pos, scope_end, typ)]
    self.field_types = defaultdict(set)  # feld -> {typ} aus x.feld = <Ausdruck mit Typ>

  def field_type(self, name):
    t = self.field_types.get(name)
    return next(iter(t)) if t and len(t) == 1 else None

  def line(self, pos):
    return bisect.bisect_right(self.nl, pos - 1) + 1 if pos > 0 else 1

  def where(self, pos):
    return "%s:%d" % (self.rel, self.line(pos))

  def scope_end(self, pos):
    best = None
    for start, end in self.blocks:
      if start <= pos < end and (best is None or end - start < best[1] - best[0]):
        best = (start, end)
    return best[1] if best else len(self.code)


def lex_lua(src):
  """Gibt (code, code_s) zurück, beide so lang wie src. code: Kommentare -> Leerzeichen,
  String-Inhalte -> \\x01 (Anführungszeichen und Zeilenumbrüche bleiben). code_s: nur
  Kommentare entfernt."""
  n = len(src)
  out = list(src)
  outs = list(src)
  i = 0

  def blank(arr, a, b, ch):
    for k in range(a, b):
      if arr[k] != "\n":
        arr[k] = ch

  while i < n:
    c = src[i]
    if c == "-" and src.startswith("--", i):
      m = LONG_OPEN.match(src, i + 2)
      if m:
        close = "]" + m.group(1) + "]"
        j = src.find(close, m.end())
        j = n if j < 0 else j + len(close)
      else:
        j = src.find("\n", i)
        j = n if j < 0 else j
      blank(out, i, j, " ")
      blank(outs, i, j, " ")
      i = j
    elif c in "\"'":
      j = i + 1
      while j < n:
        if src[j] == "\\":
          j += 2
          continue
        if src[j] == c or src[j] == "\n":
          break
        j += 1
      blank(out, i + 1, min(j, n), "\x01")
      i = j + 1
    elif c == "[":
      m = LONG_OPEN.match(src, i)
      if m:
        close = "]" + m.group(1) + "]"
        j = src.find(close, m.end())
        j = n if j < 0 else j
        blank(out, m.end(), j, "\x01")
        i = j + len(close)
      else:
        i += 1
    else:
      i += 1
  return "".join(out), "".join(outs)


def find_blocks(code):
  """Lua-Blöcke (function/if/do/repeat … end/until) als Liste (start, ende)."""
  blocks, stack = [], []
  for m in re.finditer(r"(?<![\w.:])(" + IDENT + r")", code):
    w = m.group(1)
    if w in ("function", "if", "do", "repeat"):
      stack.append(m.start())
    elif w in ("end", "until"):
      if stack:
        blocks.append((stack.pop(), m.end()))
  return blocks


def innermost_brackets(code):
  """Für jede Position das innerste offene Klammerzeichen ('' auf oberster Ebene), kodiert
  als Liste von (pos, char)-Wechseln für bisect."""
  changes, stack = [(0, "")], []
  for i, c in enumerate(code):
    if c in "({[":
      stack.append(c)
      changes.append((i + 1, c))
    elif c in ")}]":
      if stack:
        stack.pop()
      changes.append((i + 1, stack[-1] if stack else ""))
  return changes


def bracket_at(lf, pos):
  k = bisect.bisect_right(lf.inner, (pos, "￿")) - 1
  return lf.inner[k][1]


def skip_ws_back(code, j):
  while j >= 0 and code[j] in " \t\r\n":
    j -= 1
  return j


def match_back(code, j, open_c, close_c):
  depth = 0
  while j >= 0:
    c = code[j]
    if c == close_c:
      depth += 1
    elif c == open_c:
      depth -= 1
      if depth == 0:
        return j
    j -= 1
  return None


def receiver_chain(code, dot_pos):
  """Ausdruck links vom Punkt/Doppelpunkt bei dot_pos als Token-Liste, z. B. game.surfaces[…]
  -> [('id','game'), ('dot','surfaces'), ('idx',)]. Leere Liste: nicht ableitbar."""
  toks = []
  j = skip_ws_back(code, dot_pos - 1)
  while j >= 0:
    c = code[j]
    if c.isalnum() or c == "_":
      k = j
      while k >= 0 and (code[k].isalnum() or code[k] == "_"):
        k -= 1
      word = code[k + 1:j + 1]
      if word[0].isdigit() or word in LUA_KEYWORDS:
        return []
      p = skip_ws_back(code, k)
      if p >= 0 and code[p] == "." and not (p > 0 and code[p - 1] == "."):
        toks.insert(0, ("dot", word))
        j = skip_ws_back(code, p - 1)
        continue
      if p >= 0 and code[p] == ":" and not (p > 0 and code[p - 1] == ":"):
        toks.insert(0, ("colon", word))
        j = skip_ws_back(code, p - 1)
        continue
      toks.insert(0, ("id", word))
      return toks
    if c in "])}":
      open_c = {"]": "[", ")": "(", "}": "{"}[c]
      k = match_back(code, j, open_c, c)
      if k is None:
        return []
      p = skip_ws_back(code, k - 1)
      is_call_or_index = p >= 0 and (code[p].isalnum() or code[p] in "_])}\"'")
      if not is_call_or_index or (p >= 0 and code[p].isalnum() and
                                  re.search(r"(?:^|[^\w])(" + "|".join(LUA_KEYWORDS) + r")$", code[max(0, p - 10):p + 1])):
        return []  # geklammerter Ausdruck oder Tabellenliteral
      toks.insert(0, ("idx",) if c == "]" else ("call",))
      j = p
      continue
    return []
  return []


def forward_chain(code, i):
  """Liest ab i einen Ausdruck id(.id|[…]|(…)|{…}|"…"|:id(…))*. Gibt (tokens, ende) oder (None, i)."""
  n = len(code)
  m = re.compile(r"[ \t]*(" + IDENT + r")").match(code, i)
  if not m or m.group(1) in LUA_KEYWORDS:
    return None, i
  toks = [("id", m.group(1))]
  j = m.end()
  while True:
    k = j
    while k < n and code[k] in " \t":
      k += 1
    if k >= n:
      break
    c = code[k]
    if c == "." and not code.startswith("..", k):
      m = re.compile(r"\.\s*(" + IDENT + r")").match(code, k)
      if not m:
        break
      toks.append(("dot", m.group(1)))
      j = m.end()
    elif c == "[" and not LONG_OPEN.match(code, k):
      e = match_close(code, k, "[", "]")
      if e is None:
        break
      toks.append(("idx",))
      j = e + 1
    elif c in "({":
      e = match_close(code, k, c, ")" if c == "(" else "}")
      if e is None:
        break
      toks.append(("call",))
      j = e + 1
    elif c in "\"'":
      e = code.find(c, k + 1)
      if e < 0:
        break
      toks.append(("call",))
      j = e + 1
    elif c == ":" and not code.startswith("::", k):
      m = re.compile(r":\s*(" + IDENT + r")").match(code, k)
      if not m:
        break
      toks.append(("colon", m.group(1)))
      j = m.end()
    else:
      break
  return toks, j


def chain_text(toks):
  out = ""
  for t in toks:
    if t[0] == "id":
      out += t[1]
    elif t[0] == "dot":
      out += "." + t[1]
    elif t[0] == "colon":
      out += ":" + t[1]
    elif t[0] == "idx":
      out += "[…]"
    else:
      out += "(…)"
  return out


# ---------------------------------------------------------------------------------------------
# Eigene Funktionen und Module
# ---------------------------------------------------------------------------------------------

def collect_functions(code):
  names = set()
  for m in re.finditer(r"\bfunction\s+([\w.:]+)\s*\(", code):
    names.add(re.split(r"[.:]", m.group(1))[-1])
  for m in re.finditer(r"\blocal\s+function\s+(" + IDENT + r")", code):
    names.add(m.group(1))
  for m in re.finditer(r"(" + IDENT + r")\s*=\s*function\b", code):
    names.add(m.group(1))
  return names


def collect_aliases(code, funcs):
  """name = f (f eine Funktion) bzw. x.name = y.f -> name gilt als Funktion."""
  new = set()
  for m in re.finditer(r"(" + IDENT + r")\s*=\s*(" + IDENT + r"(?:\s*\.\s*" + IDENT + r")*)\s*(?=[,\n;}]|$)", code):
    rhs = re.split(r"\s*\.\s*", m.group(2))[-1]
    if rhs in funcs and m.group(1) not in funcs:
      new.add(m.group(1))
  return new


def module_defs(code, table):
  """Namen, die in code als table.name definiert werden (Funktionen und Werte)."""
  t = re.escape(table)
  defs = set()
  for m in re.finditer(r"\bfunction\s+" + t + r"\s*[.:]\s*(" + IDENT + r")\s*\(", code):
    defs.add(m.group(1))
  for m in re.finditer(r"(?<![\w.])" + t + r"\s*\.\s*(" + IDENT + r")\s*=(?!=)", code):
    defs.add(m.group(1))
  m = re.search(r"\blocal\s+" + t + r"\s*=\s*\{", code)
  if m:
    e = match_close(code, m.end() - 1, "{", "}")
    if e:
      body = code[m.end():e]
      depth = 0
      for mm in re.finditer(r"[{}()\[\]]|(" + IDENT + r")\s*=(?!=)", body):
        tok = mm.group(0)
        if tok in "{([":
          depth += 1
        elif tok in "})]":
          depth -= 1
        elif depth == 0 and mm.group(1):
          defs.add(mm.group(1))
  return defs


def returned_table(code):
  m = None
  for m in re.finditer(r"\breturn\s+(" + IDENT + r")\s*$", code.rstrip()):
    pass
  if m:
    return m.group(1)
  ms = re.findall(r"^return\s+(" + IDENT + r")\s*$", code, re.M)
  return ms[-1] if ms else None


def resolve_require(name, repo, fd):
  name = name.replace("/", ".")
  if name.endswith(".lua"):
    name = name[:-4]
  m = re.match(r"^__(\w[\w-]*)__\.(.*)$", name)
  if m:
    mod, rest = m.group(1), m.group(2)
    if mod == "arrakis":
      return os.path.join(repo, *rest.split(".")) + ".lua"
    if fd:
      return os.path.join(fd, mod, *rest.split(".")) + ".lua"
    return None
  own = os.path.join(repo, *name.split(".")) + ".lua"
  if os.path.exists(own):
    return own
  if fd:
    core = os.path.join(fd, "core", "lualib", *name.split(".")) + ".lua"
    if os.path.exists(core):
      return core
  return None


# ---------------------------------------------------------------------------------------------
# Typableitung im Lua-Code
# ---------------------------------------------------------------------------------------------

class Typer:
  def __init__(self, api, own_returns, hints):
    self.api = api
    self.own_returns = own_returns
    self.hints = hints

  def hint(self, lf, name):
    cls = self.hints.get(os.path.basename(lf.rel) + ":" + name) or self.hints.get(name)
    return ("obj", frozenset([cls])) if cls else None

  def own_return(self, lf, dotted):
    cls = self.own_returns.get(os.path.basename(lf.rel) + ":" + dotted) or self.own_returns.get(dotted)
    return ("obj", frozenset([cls])) if cls else None

  def root_type(self, lf, name, pos):
    """(typ, quelle) für einen Bezeichner an pos. quelle: 'global' | 'abgeleitet' | 'Name-Hinweis'."""
    best = None
    for bpos, bend, typ in lf.bindings.get(name, ()):
      if bpos < pos < bend and (best is None or bpos > best[0]):
        best = (bpos, bend, typ)
    if best is not None:
      if best[2] is not None:
        return best[2], "abgeleitet"
      h = self.hint(lf, name)
      return (h, "Name-Hinweis") if h else (None, None)
    if name in GLOBAL_ROOTS:
      return ("obj", frozenset([GLOBAL_ROOTS[name]])), "global"
    h = self.hint(lf, name)
    return (h, "Name-Hinweis") if h else (None, None)

  def step(self, typ, tok):
    if typ is None:
      return None
    kind, classes = typ
    if tok[0] == "dot":
      if kind != "obj":
        return None
      results = []
      for cls in classes:
        mem, _where = self.api.member_or_sub(cls, tok[1])
        if mem is None:
          continue
        if mem.method and not mem.attr:
          r = self.api.resolve_type(mem.ret_text) if mem.ret_text else None
          results.append(("meth", r))
        else:
          results.append(("val", self.api.resolve_type(mem.type_text) if mem.type_text else None))
      if not results:
        return None
      if len(results) > 1 and len(set(results)) > 1:
        return None
      a, r = results[0]
      if a == "meth":
        return ("meth", r)
      return r
    if tok[0] == "idx":
      return ("obj", classes) if kind == "idx" else None
    if tok[0] == "call":
      return classes if kind == "meth" else None
    return None

  def eval(self, lf, toks, pos):
    """Typ einer Token-Kette (oder None) und Quelle des Wurzeltyps."""
    if not toks or toks[0][0] != "id":
      return None, None
    root = toks[0][1]
    typ, src = self.root_type(lf, root, pos)
    rest = list(toks[1:])
    if typ is None and root in EVENT_NAMES and rest and rest[0][0] == "dot":
      # event.entity, event.cause …: Typ des Felds, wenn er in allen Ereignissen gleich ist
      t = self.api.event_field_type(rest[0][1])
      if t:
        typ, src, rest = t, "Ereignisfeld", rest[1:]
    if typ is None:
      # eigene Funktion mit bekanntem Rückgabetyp, z. B. tb.surface() oder create_worm(…)
      dotted = root
      for k in range(len(rest)):
        if rest[k][0] == "call":
          t = self.own_return(lf, dotted)
          if t:
            typ, src, rest = t, "abgeleitet", rest[k + 1:]
          break
        if rest[k][0] != "dot":
          break
        dotted += "." + rest[k][1]
    if typ is None:
      # Datenpfad wie d.car oder p.unit: Typ aus Zuweisungen d.car = <Typ> in dieser Datei,
      # sonst Name-Hinweis für das Feld (kürzester Präfix zuerst)
      k = 0
      while k < len(rest) and rest[k][0] == "dot":
        k += 1
      for j in range(1, k + 1):
        field = rest[j - 1][1]
        t = lf.field_type(field)
        if t:
          typ, src, rest = t, "Feldzuweisung", rest[j:]
          break
        h = self.hint(lf, field)
        if h:
          typ, src, rest = h, "Name-Hinweis", rest[j:]
          break
    if typ is None:
      return None, None
    for t in rest:
      typ = self.step(typ, t)
      if typ is None:
        return None, None
    if typ[0] == "meth":
      return None, None
    return typ, src


def expr_type(typer, lf, start):
  """Typ eines einzeiligen Ausdrucks ab start (a and b or c …), sonst None."""
  code = lf.code
  end = code.find("\n", start)
  end = len(code) if end < 0 else end
  seg = code[start:end]
  # nur Ausdrücke ohne offene Klammern bis Zeilenende
  if bracket_delta(seg.replace("\x01", "")) != 0:
    return None
  types = []
  or_parts = []
  cur = []
  # Operanden an and/or trennen (auf oberster Klammerebene)
  depth, last = 0, start
  for m in re.finditer(r"[(\[{]|[)\]}]|\b(and|or)\b", seg):
    tok = m.group(0)
    if tok in "([{":
      depth += 1
    elif tok in ")]}":
      depth -= 1
    elif depth == 0:
      cur.append((last, start + m.start()))
      last = start + m.end()
      if tok == "or":
        or_parts.append(cur)
        cur = []
  cur.append((last, end))
  or_parts.append(cur)
  for part in or_parts:
    a, b = part[-1]
    text = code[a:b].strip()
    if text in ("nil", "false", "{}") or text.startswith("{"):
      continue
    toks, e = forward_chain(code, a)
    if toks is None or code[e:b].strip() not in ("", ";"):
      return None
    t, _src = typer.eval(lf, toks, a)
    if t is None:
      return None
    types.append(t)
  if not types or len(set(types)) != 1:
    return None
  return types[0]


def collect_bindings(typer, lf):
  """Sammelt Bindungen (local, Parameter, Schleifenvariablen, Zuweisungen) in Textreihenfolge,
  damit spätere Typen auf früheren aufbauen. Bindung: (gültig ab, gültig bis, Typ oder None)."""
  code = lf.code
  events = []
  for m in re.finditer(r"\bfunction\b[^(\n]*\(([^)]*)\)", code):
    events.append((m.start(), "params", m))
  for m in re.finditer(r"\bfor\s+([\w\s,]+?)\s+in\b", code):
    events.append((m.start(), "forin", m))
  for m in re.finditer(r"\bfor\s+(" + IDENT + r")\s*=", code):
    events.append((m.start(), "fornum", m))
  for m in re.finditer(r"\blocal\s+(?!function\b)(" + IDENT + r"(?:\s*,\s*" + IDENT + r")*)\s*(=(?!=))?", code):
    events.append((m.start(), "local", m))
  for m in re.finditer(r"\blocal\s+function\s+(" + IDENT + r")", code):
    events.append((m.start(), "localfunc", m))
  for m in re.finditer(r"(?<![\w.:\x01])(" + IDENT + r")\s*=(?!=)", code):
    events.append((m.start(), "assign", m))
  events.sort(key=lambda e: e[0])

  def line_end(pos):
    e = code.find("\n", pos)
    return len(code) if e < 0 else e

  for pos, kind, m in events:
    if kind == "params":
      for name in re.findall(IDENT, m.group(1)):
        lf.bindings[name].append((m.end(), lf.scope_end(m.end()), None))
    elif kind == "forin":
      names = [x.strip() for x in m.group(1).split(",")]
      dm = re.compile(r"[^\n]*?\bdo\b").match(code, m.end())
      if not dm:
        continue
      elem = None
      im = re.compile(r"\s*(i?pairs)\s*\(").match(code, m.end())
      if im:
        close = match_close(code, im.end() - 1, "(", ")")
        toks, e = forward_chain(code, im.end())
        if toks is not None and close is not None and code[e:close].strip() == "":
          t, _ = typer.eval(lf, toks, im.end())
          if t is not None and t[0] == "idx":
            elem = ("obj", t[1])
      for k, name in enumerate(names):
        lf.bindings[name].append((dm.end(), lf.scope_end(dm.end()), elem if k == len(names) - 1 else None))
    elif kind == "fornum":
      dm = re.compile(r"[^\n]*?\bdo\b").match(code, m.end())
      p = dm.end() if dm else m.end()
      lf.bindings[m.group(1)].append((p, lf.scope_end(p), None))
    elif kind == "localfunc":
      lf.bindings[m.group(1)].append((m.end(), lf.scope_end(m.start()), None))
    elif kind == "local":
      names = [x.strip() for x in m.group(1).split(",")]
      typ = None
      if m.group(2) and len(names) == 1:
        typ = expr_type(typer, lf, m.end())
      p = line_end(m.end()) if m.group(2) else m.end()
      for name in names:
        lf.bindings[name].append((p, lf.scope_end(m.start()), typ))
    else:
      # Zuweisung x = …: nicht in Tabellenkonstruktoren, nicht nach "local", nicht "for i ="
      name = m.group(1)
      if name in LUA_KEYWORDS or bracket_at(lf, m.start()) == "{":
        continue
      before = code[max(0, m.start() - 40):m.start()]
      if re.search(r"\b(local|for)\s+[\w\s,]*$", before) or re.search(r",\s*$", before):
        continue
      typ = expr_type(typer, lf, m.end())
      # gilt bis zum Ende des Gültigkeitsbereichs der sichtbaren Bindung
      vis = [b for b in lf.bindings.get(name, ()) if b[0] < m.start() < b[1]]
      end = max(vis, key=lambda b: b[0])[1] if vis else len(code)
      lf.bindings[name].append((line_end(m.end()), end, typ))


def collect_field_types(typer, lf):
  """x.feld = <Ausdruck mit bekanntem Typ> → Feldtyp (nur eindeutige zählen später)."""
  code = lf.code
  found = defaultdict(set)
  for m in re.finditer(r"\.[ \t]*(" + IDENT + r")\s*=(?!=)", code):
    p = m.start()
    if p > 0 and code[p - 1] == ".":
      continue
    b = skip_ws_back(code, p - 1)
    if b < 0 or not (code[b].isalnum() or code[b] in "_])"):
      continue
    t = expr_type(typer, lf, m.end())
    if t is not None and t[0] == "obj":
      found[m.group(1)].add(t)
  lf.field_types = found


# ---------------------------------------------------------------------------------------------
# Tabellen-Argumente (Prüfung 8)
# ---------------------------------------------------------------------------------------------

def lua_call_table_args(code, after):
  """after: Index von '(' oder '{' hinter dem Methodennamen. -> [(Argumentnummer, Index der '{')]"""
  if after >= len(code):
    return []
  if code[after] == "{":
    return [(0, after)]
  if code[after] != "(":
    return []
  close = match_close(code, after, "(", ")")
  if close is None:
    return []
  out, depth, start, idx = [], 0, after + 1, 0
  for j in range(after + 1, close + 1):
    c = code[j]
    if j == close or (c == "," and depth == 0):
      k = start
      while k < j and code[k] in " \t\r\n":
        k += 1
      if k < j and code[k] == "{":
        e = match_close(code, k, "{", "}")
        if e is not None and code[e + 1:j].strip() == "":
          out.append((idx, k))
      idx += 1
      start = j + 1
      continue
    if c in "({[":
      depth += 1
    elif c in ")}]":
      depth -= 1
  return out


def lua_table_fields(code, open_pos):
  """Felder name = Wert auf oberster Ebene eines Tabellenkonstruktors -> [(name, pos, wert_start, wert_ende)]."""
  close = match_close(code, open_pos, "{", "}")
  if close is None:
    return []
  segs, depth, start = [], 0, open_pos + 1
  for j in range(open_pos + 1, close):
    c = code[j]
    if c in "({[":
      depth += 1
    elif c in ")}]":
      depth -= 1
    elif c in ",;" and depth == 0:
      segs.append((start, j))
      start = j + 1
  segs.append((start, close))
  fields = []
  for a, b in segs:
    m = re.compile(r"\s*(" + IDENT + r")\s*=(?!=)").match(code, a, b)
    if m:
      fields.append((m.group(1), m.start(1), m.end(), b))
  return fields


def param_types(params_text):
  """Parameterliste -> Liste der Typtexte (None: nicht lesbar). 'this: void' entfällt."""
  out = []
  for pp in split_top(params_text, ","):
    pp = pp.strip()
    if not pp:
      continue
    m = re.match(r"(\.\.\.)?(" + TS_NAME + r")\??\s*:(.*)$", pp, re.S)
    if not m:
      out.append(None)
      continue
    if m.group(2) == "this":
      continue
    if m.group(1):
      break
    out.append(m.group(3).strip())
  return out


def table_key_problems(api, type_texts, code, brace, path_=""):
  """Unbekannte Schlüssel im Konstruktor bei brace gegen die Typen. -> [(pos, pfad, schlüssel, erlaubt)]
  oder None, wenn nicht prüfbar."""
  allowed = OrderedDict()
  for t in type_texts:
    if t is None:
      return None
    k = api.object_keys(t)
    if k is None:
      return None
    for key, v in k.items():
      allowed.setdefault(key, [])
      allowed[key] += v
  if not allowed:
    return []
  problems = []
  for key, kpos, vs, ve in lua_table_fields(code, brace):
    if key not in allowed:
      problems.append((kpos, path_, key, list(allowed)))
      continue
    j = vs
    while j < ve and code[j] in " \t\r\n":
      j += 1
    if j < ve and code[j] == "{" and path_.count(".") < 3:
      e = match_close(code, j, "{", "}")
      if e is not None and code[e + 1:ve].strip() == "":
        sub = table_key_problems(api, allowed[key], code, j, path_ + key + ".")
        if sub:
          problems += sub
  return problems


def check_table_args(api, classes, mname, code, after):
  """Alle Tabellenkonstruktor-Argumente eines Methodenaufrufs prüfen.
  -> (Liste der Probleme, True wenn mindestens ein Argument prüfbar war)."""
  args = lua_call_table_args(code, after)
  if not args:
    return [], False
  overloads = []
  for cls in classes:
    mem = api.member_or_sub(cls, mname)[0]
    if mem is not None and mem.method:
      overloads += [param_types(p) for p in mem.params]
  if not overloads:
    return [], False
  problems, checked = [], False
  for idx, brace in args:
    best = None
    for ov in overloads:
      if idx >= len(ov):
        continue
      r = table_key_problems(api, [ov[idx]], code, brace)
      if r is None:
        continue
      if best is None or len(r) < len(best):
        best = r
    if best is not None:
      checked = True
      problems += best
  return problems, checked


# ---------------------------------------------------------------------------------------------
# Prüfung
# ---------------------------------------------------------------------------------------------

class Report:
  def __init__(self):
    self.sections = OrderedDict()
    self.errors = 0

  def add(self, section, text, error=True):
    self.sections.setdefault(section, []).append(text)
    if error:
      self.errors += 1


def self_test(api20, api21):
  print("== Selbsttest Parser ==")
  ok = True

  def expect(api, cls, name, want):
    nonlocal ok
    mem = api.member(cls, name)
    got = mem.describe() if mem else "fehlt"
    good = got == want
    ok &= good
    where = ""
    if mem:
      where = " (%s:%d, deklariert in %s)" % (os.path.basename(api.classes.get(mem.cls, {}).get("file", "?")), mem.line, mem.cls)
    print("  [%s] %s %s.%s: %s%s" % ("ok" if good else "FALSCH", api.label, cls, name, got, where))

  for api in (api20, api21):
    expect(api, "LuaEntity", "speed", "Attribut, beschreibbar")
    expect(api, "LuaEntity", "position", "Attribut, readonly")
    expect(api, "LuaSurface", "create_entity", "Methode")
    expect(api, "LuaSegmentedUnit", "get_body_nodes", "Methode")
    for path_, want in ((("events", "on_tick"), True), (("direction", "north"), True),
                        (("inventory", "fuel"), True), (("events", "on_foo_bar"), False)):
      got = api.define_status(path_) == "ok"
      ok &= got == want
      print("  [%s] %s defines.%s %s" % ("ok" if got == want else "FALSCH", api.label, ".".join(path_),
                                          "vorhanden" if got else "fehlt"))
    t = api.resolve_type(api.member("LuaGameScript", "surfaces").type_text)
    good = t == ("idx", frozenset(["LuaSurface"]))
    ok &= good
    print("  [%s] %s Typ game.surfaces -> %s" % ("ok" if good else "FALSCH", api.label, t))
    t = api.resolve_type(api.member("LuaSurface", "create_entity").ret_text)
    good = t == ("obj", frozenset(["LuaEntity"]))
    ok &= good
    print("  [%s] %s Typ surface.create_entity(…) -> %s" % ("ok" if good else "FALSCH", api.label, t))
  print("  %s: %d Klassen, %d Membernamen, %d defines-Pfade"
        % (api20.label, len(api20.classes), len(api20.by_name), len(api20.def_leaves)))
  print("  %s: %d Klassen, %d Membernamen, %d defines-Pfade"
        % (api21.label, len(api21.classes), len(api21.by_name), len(api21.def_leaves)))
  print()
  return ok


def main():
  ap = argparse.ArgumentParser(description="Statische Prüfung der Factorio-API-Namen (Laufzeitcode).")
  ap.add_argument("--api20", default=DEFAULT_API20, help="typed-factorio 3.36.0 runtime/generated (API 2.0.75)")
  ap.add_argument("--api21", default=DEFAULT_API21, help="factorio-types 1.2.69 dist (API 2.1.20)")
  ap.add_argument("--fd", default=DEFAULT_FD, help="Vanilla-Daten 2.0.77 (für __core__/lualib), optional")
  ap.add_argument("--repo", default=None, help="Mod-Ordner (Standard: der Ordner, in dem tools/ liegt)")
  ap.add_argument("-v", "--verbose", action="store_true", help="alle Zugriffe mit abgeleitetem Typ auflisten")
  args = ap.parse_args()

  repo = os.path.abspath(args.repo) if args.repo else \
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
  fd = args.fd if args.fd and os.path.isdir(args.fd) else None
  for folder in (args.api20, args.api21):
    if not os.path.exists(os.path.join(folder, "classes.d.ts")):
      sys.exit("Keine classes.d.ts in %s (siehe Einrichtung oben in der Datei)." % folder)

  api20 = Api("2.0.75", args.api20, r"(GuiSpec|SurfaceCreateEntity|SurfaceCreateSegmentedUnit|ControlSetGuiArrow)$|^GuiElementIndexer$")
  api21 = Api("2.1.20", args.api21, r"Params")
  if not self_test(api20, api21):
    print("Selbsttest gescheitert: Parser passt nicht zu den d.ts-Dateien.")
    return 2

  files = [os.path.join(repo, "control.lua")] + sorted(glob.glob(os.path.join(repo, "scripts", "**", "*.lua"), recursive=True))
  lfs = [LuaFile(p, os.path.relpath(p, repo)) for p in files if os.path.exists(p)]
  print("== Eingelesen ==")
  print("  Lua: " + ", ".join("%s (%d Z.)" % (lf.rel, lf.src.count("\n") + 1) for lf in lfs))

  # Eigene Funktionen, require-Aliase, Modultabellen ------------------------------------------
  own_funcs = set()
  for lf in lfs:
    own_funcs |= collect_functions(lf.code)
  module_files = {}  # Pfad -> (code, Tabelle)
  require_alias = {}  # (datei, alias) -> pfad
  util_required = False
  for lf in lfs:
    for m in re.finditer(r"(?:\blocal\s+)?(" + IDENT + r")\s*=\s*require\s*\(?\s*[\"']([^\"']+)[\"']", lf.code_s):
      target = resolve_require(m.group(2), repo, fd)
      if m.group(2) in ("util", "__core__.lualib.util", "__core__/lualib/util"):
        util_required = True
      if target and os.path.exists(target):
        require_alias[(lf.rel, m.group(1))] = target
    for m in re.finditer(r"\brequire\s*\(?\s*[\"']([^\"']+)[\"']", lf.code_s):
      if m.group(1) in ("util", "__core__.lualib.util", "__core__/lualib/util"):
        util_required = True
  for target in set(require_alias.values()):
    if target not in module_files:
      code, _ = lex_lua(open(target, encoding="utf-8").read())
      module_files[target] = (code, returned_table(code))
      if not target.startswith(repo):
        own_funcs |= collect_functions(code)
  for rel, (mfile, table) in MODULE_PARAMS.items():
    p = os.path.join(repo, mfile)
    if os.path.exists(p):
      code, _ = lex_lua(open(p, encoding="utf-8").read())
      module_files[("param", rel)] = (code, table)
  while True:
    new = set()
    for lf in lfs:
      new |= collect_aliases(lf.code, own_funcs)
    if not new - own_funcs:
      break
    own_funcs |= new
  module_def_cache = {}

  def defs_for(key):
    if key not in module_def_cache:
      code, table = module_files[key]
      module_def_cache[key] = module_defs(code, table) if table else None
    return module_def_cache[key]

  print("  eigene Funktionsnamen: %d; require-Module: %s" % (
    len(own_funcs), ", ".join(sorted("%s=%s" % (a, os.path.relpath(p, repo) if p.startswith(repo) else os.path.basename(p))
                                     for (f, a), p in require_alias.items()))))
  print()

  typer20 = Typer(api20, OWN_RETURNS, RECEIVER_HINTS)
  for lf in lfs:
    for _ in range(2):  # 2. Runde: Variablen aus Feldern (local car = d.car) kennen die Feldtypen
      lf.bindings = defaultdict(list)
      collect_bindings(typer20, lf)
      collect_field_types(typer20, lf)

  rep = Report()
  S1, S1b = "1. defines-Pfade, die in 2.0.75 fehlen", "1b. defines-Pfade, die in 2.1.20 fehlen"
  S2, S2b = "2. defines.events, die in 2.0.75 fehlen", "2b. Ereignisfelder event.X, die es in keinem Ereignis gibt"
  S3, S3b = "3. Methodenaufrufe mit unbekanntem Namen", "3b. Lua-Standardbibliothek: unbekannt oder in Factorio nicht verfügbar"
  S3c, S3d = "3c. Doppelpunkt-Aufrufe (API-Methoden wollen '.')", "3d. Zugriffe auf eigene Modultabellen ohne Definition"
  S3e = "3e. Attribut wird als Funktion aufgerufen"
  S4, S4b = "4. Schreibzugriffe: in 2.0.75 in jeder Klasse readonly", "4b. Schreibzugriffe: erst in 2.1.20 überall readonly"
  S4c = "4c. Schreibzugriffe: auf der abgeleiteten Klasse readonly"
  S5, S5b = "5. Member aus 2.0.75, die es in 2.1.20 in keiner Klasse gibt", "5b. Member, die es in 2.1.20 auf der abgeleiteten Klasse nicht mehr gibt (oder dort readonly sind)"
  S6 = "6. Globale Einstiegspunkte: unbekannte Namen, global statt storage, überdeckte Globals"
  S7 = "7. Typ-Plausibilität: Member fehlt auf der abgeleiteten Klasse (2.0.75)"
  S8 = "8. Tabellen-Argumente: Schlüssel, die der Parametertyp nicht kennt (2.0.75)"
  S8b = "8b. Tabellen-Argumente: Schlüssel, die es erst in 2.1.20 nicht mehr gibt"
  for s in (S1, S1b, S2, S2b, S3, S3b, S3c, S3d, S3e, S4, S4b, S4c, S5, S5b, S6, S7, S8, S8b):
    rep.sections[s] = []

  stats = defaultdict(int)
  typed_log = []
  untyped_log = []
  defines_used = OrderedDict()   # pfad -> [orte]
  entry_used = OrderedDict()     # (wurzel, name) -> [orte]
  storage_uses = []
  global_uses = []
  shadowed = []

  for lf in lfs:
    code, src = lf.code, lf.src

    # 1/2: defines ------------------------------------------------------------------------
    for m in re.finditer(r"(?<![\w.:])defines\b", code):
      path_, j = [], m.end()
      while True:
        k = j
        while k < len(code) and code[k] in " \t":
          k += 1
        if code.startswith(".", k) and not code.startswith("..", k):
          mm = re.compile(r"\.\s*(" + IDENT + r")").match(code, k)
          if not mm:
            break
          path_.append(mm.group(1))
          j = mm.end()
        elif code.startswith("[", k):
          mm = re.compile(r"\[\s*([\"'])(\x01*)\1\s*\]").match(code, k)
          if not mm:
            break
          path_.append(src[mm.start(2):mm.end(2)])
          j = mm.end()
        else:
          break
      defines_used.setdefault(tuple(path_), []).append(lf.where(m.start()))

    # Shadowing globaler Namen
    for m in re.finditer(r"\blocal\s+(" + "|".join(list(GLOBAL_ROOTS) + ["storage", "defines"]) + r")\b", code):
      shadowed.append("%s: local %s überdeckt das globale Objekt" % (lf.where(m.start()), m.group(1)))
    for m in re.finditer(r"(?<![\w.:])storage\b", code):
      storage_uses.append(lf.where(m.start()))
    for m in re.finditer(r"(?<![\w.:])global\s*[.\[]", code):
      global_uses.append(lf.where(m.start()))
    for m in re.finditer(r"(?<![\w.:])(" + "|".join(sorted(UNAVAILABLE_FUNCS)) + r")\s*[(\"'{]", code):
      rep.add(S3b, "%s: %s(…) – Lua-5.1-Rest bzw. in Factorio nicht verfügbar%s" % (
        lf.where(m.start()), m.group(1), "; table.unpack benutzen" if m.group(1) == "unpack" else ""))

    # Member-Zugriffe .name und :name ---------------------------------------------------------
    for m in re.finditer(r"([.:])[ \t]*(" + IDENT + r")", code):
      sep, name = m.group(1), m.group(2)
      p = m.start()
      if sep == "." and ((p > 0 and code[p - 1] == ".") or code.startswith("..", p)):
        continue
      if sep == ":" and ((p > 0 and code[p - 1] == ":") or code.startswith("::", p)):
        continue
      before = skip_ws_back(code, p - 1)
      if before < 0 or not (code[before].isalnum() or code[before] in "_])}"):
        continue
      if sep == "." and code[before].isdigit():
        k = before
        while k >= 0 and (code[k].isalnum() or code[k] == "_"):
          k -= 1
        if code[k + 1].isdigit():
          continue  # Zahl wie 1.5
      after = m.end()
      while after < len(code) and code[after] in " \t":
        after += 1
      nxt = code[after:after + 2]
      if nxt[:1] in ("(", "{", "\"", "'") or LONG_OPEN.match(code, after):
        use = "call"
      elif nxt[:1] == "=" and nxt != "==":
        use = "write"
      else:
        use = "read"
      toks = receiver_chain(code, p)
      where = lf.where(p)
      recv = chain_text(toks) if toks else "<Ausdruck>"
      full = recv + sep + name
      root = toks[0][1] if toks and toks[0][0] == "id" else None
      single = root is not None and len(toks) == 1

      if root == "defines":
        continue

      # Doppelpunkt-Aufrufe
      if sep == ":":
        if use != "call":
          continue
        if name in LUA_MODULES["string"]:
          continue
        if api20.method_anywhere(name) and name not in own_funcs:
          rep.add(S3c, "%s: %s(…) – API-Methoden mit '.' aufrufen (':' übergibt das Objekt als 1. Argument)" % (where, full))
        elif name not in own_funcs and name not in CALL_WHITELIST:
          rep.add(S3, "%s: %s(…) – Name unbekannt (weder API noch string noch eigene Funktion)" % (where, full))
        continue

      # Lua-Module
      if single and root in LUA_MODULES:
        allowed = set(LUA_MODULES[root])
        if root == "table" and util_required:
          allowed |= {"deepcopy", "compare"}
        if name not in allowed:
          extra = ""
          if root == "table" and name in ("deepcopy", "compare"):
            extra = " (nur nach require(\"util\"))"
          rep.add(S3b, "%s: %s – nicht in Lua 5.2 %s%s" % (where, full, root, extra))
        continue
      if single and root in UNAVAILABLE_MODULES:
        rep.add(S3b, "%s: %s – Bibliothek %s gibt es in Factorio nicht" % (where, full, root))
        continue

      # eigene Module (require-Alias oder MODULE_PARAMS)
      key = None
      if single and (lf.rel, root) in require_alias:
        key = require_alias[(lf.rel, root)]
      elif single and root in MODULE_PARAMS:
        key = ("param", root)
      if key is not None and key in module_files:
        defs = defs_for(key)
        if defs is not None and use != "write" and name not in defs:
          rep.add(S3d, "%s: %s – %s definiert kein '%s'" % (
            where, full, os.path.relpath(key, repo) if isinstance(key, str) else MODULE_PARAMS[root][0], name))
        continue

      # Ereignistabellen
      if single and root in EVENT_NAMES and use == "read":
        if name not in api20.event_fields:
          rep.add(S2b, "%s: %s – Feld gibt es in keinem Ereignis (2.0.75)" % (where, full))
        elif name not in api21.event_fields:
          rep.add(S2b, "%s: %s – Feld gibt es in 2.1.20 in keinem Ereignis mehr" % (where, full))
        continue

      typ, tsrc = typer20.eval(lf, toks, p) if toks else (None, None)
      if use == "write" and typ is not None and typ[0] == "obj":
        # x.attr = { … }: Schlüssel gegen den Schreibtyp des Attributs
        j = after + 1
        while j < len(code) and code[j] in " \t\r\n":
          j += 1
        if j < len(code) and code[j] == "{":
          seen_keys = set()
          for api, sec in ((api20, S8), (api21, S8b)):
            wt = [mm.write_text for mm in (api.member_or_sub(c, name)[0] for c in sorted(typ[1]))
                  if mm is not None and mm.write_text]
            probs = table_key_problems(api, wt, code, j) if wt else None
            for kpos, path_, key, allowed in probs or []:
              if (kpos, key) in seen_keys:
                continue
              seen_keys.add((kpos, key))
              near = difflib.get_close_matches(key, allowed, 3, 0.6)
              rep.add(sec, "%s: %s = {… %s%s …} – Schlüssel '%s' unbekannt%s [%s]" % (
                lf.where(kpos), full, path_, key, key, (" (meintest du: " + ", ".join(near) + "?)") if near else "",
                tsrc), error=(sec == S8))
            if api is api20 and probs is not None:
              stats["tabellen_geprueft"] += 1
      if use == "call" and typ is not None and typ[0] == "obj":
        probs20, ok20 = check_table_args(api20, sorted(typ[1]), name, code, after)
        stats["tabellen_geprueft"] += 1 if ok20 else 0
        for kpos, path_, key, allowed in probs20:
          near = difflib.get_close_matches(key, allowed, 3, 0.6)
          rep.add(S8, "%s: %s{… %s%s …} – Schlüssel '%s' unbekannt%s [%s]" % (
            lf.where(kpos), full, path_, key, key, (" (meintest du: " + ", ".join(near) + "?)") if near else "", tsrc))
        if ok20:
          probs21, ok21 = check_table_args(api21, sorted(typ[1]), name, code, after)
          known20 = {(k[0], k[2]) for k in probs20}
          for kpos, path_, key, allowed in (probs21 if ok21 else []):
            if (kpos, key) not in known20:
              rep.add(S8b, "%s: %s{… %s%s …} – Schlüssel '%s' kennt 2.1.20 nicht [%s]" % (
                lf.where(kpos), full, path_, key, key, tsrc), error=False)
      stats["zugriffe"] += 1
      if typ is not None and typ[0] == "obj":
        stats[tsrc] += 1
        typed_log.append("%s: %s%s%s (%s) -> %s [%s]" % (where, recv, sep, name, use, "/".join(sorted(typ[1])), tsrc))
      elif api20.has_name(name):
        stats["untypisiert_api_name"] += 1
        untyped_log.append("%s: %s%s%s (%s)" % (where, recv, sep, name, use))

      # 6: globale Einstiegspunkte
      if single and root in GLOBAL_ROOTS and tsrc == "global":
        entry_used.setdefault((root, name), []).append(where)
        cls = GLOBAL_ROOTS[root]
        mem20, mem21 = api20.member(cls, name), api21.member(cls, name)
        if mem20 is None:
          rep.add(S6, "%s: %s – %s hat kein '%s' (2.0.75)" % (where, full, cls, name))
        elif mem21 is None:
          rep.add(S5b, "%s: %s – %s hat in 2.1.20 kein '%s' mehr" % (where, full, cls, name), error=False)
        if use == "write" and mem20 is not None and not mem20.writable:
          rep.add(S4c, "%s: %s = … – %s.%s ist readonly (2.0.75, %s:%d)" % (where, full, cls, name, "classes.d.ts", mem20.line))
        if use == "call" and mem20 is not None and not mem20.method:
          rep.add(S3e, "%s: %s(…) – %s.%s ist ein Attribut" % (where, full, cls, name))
        continue

      data_root = root in DATA_ROOTS

      # 3: Aufrufe
      if use == "call":
        known = (api20.has_name(name) or name in own_funcs or name in LUA_BASE or name in FACTORIO_GLOBAL_FUNCS
                 or any(name in v for v in LUA_MODULES.values()) or name in CALL_WHITELIST)
        if not known:
          rep.add(S3, "%s: %s(…) – Name unbekannt (keine Lua*-Methode, keine Stdlib, keine eigene Funktion)" % (where, full))
        elif api20.has_name(name) and not api20.method_anywhere(name) and name not in own_funcs and typ is None:
          rep.add(S3e, "%s: %s(…) – '%s' ist in keiner Klasse eine Methode" % (where, full, name), error=False)

      # 4: Schreibzugriffe
      if use == "write" and not data_root:
        wl = name in WRITE_WHITELIST or full in WRITE_WHITELIST
        if api20.attr_anywhere(name) and not api20.writable_anywhere(name) and not wl:
          decl = ", ".join(sorted({m_.cls for m_ in api20.by_name[name]})[:6])
          rep.add(S4, "%s: %s = … – '%s' ist readonly in: %s" % (where, full, name, decl))
        elif (api20.writable_anywhere(name) and api21.attr_anywhere(name) and not api21.writable_anywhere(name)
              and not wl):
          rep.add(S4b, "%s: %s = … – '%s' ist in 2.1.20 in jeder Klasse readonly" % (where, full, name), error=False)

      # 5: in 2.1 entfernte Namen
      if not data_root and api20.has_name(name) and not api21.has_name(name):
        decl = ", ".join(sorted({m_.cls for m_ in api20.by_name[name]})[:4])
        rep.add(S5, "%s: %s (%s) – 2.0.75: %s; 2.1.20: in keiner Klasse" % (where, full, use, decl), error=False)

      # 7: Typ der Kette bekannt
      if typ is not None and typ[0] == "obj":
        classes = sorted(typ[1])
        mems = [api20.member_or_sub(c, name)[0] for c in classes]
        if all(mm is None for mm in mems):
          if api20.has_name(name) or name not in own_funcs:
            others = sorted({m_.cls for m_ in api20.by_name.get(name, ())})[:4]
            rep.add(S7, "%s: %s (%s) – %s hat kein '%s' [%s]%s" % (
              where, full, use, "/".join(classes), name, tsrc,
              ("; gibt es auf " + ", ".join(others)) if others else "; gibt es in keiner Klasse"))
          continue
        mem = next(mm for mm in mems if mm is not None)
        if use == "write" and not any(mm is not None and mm.writable for mm in mems):
          rep.add(S4c, "%s: %s = … – %s.%s ist readonly (2.0.75, classes.d.ts:%d) [%s]" % (
            where, full, mem.cls, name, mem.line, tsrc))
        if use == "call" and not any(mm is not None and mm.method for mm in mems):
          rep.add(S3e, "%s: %s(…) – %s.%s ist ein Attribut, keine Methode [%s]" % (where, full, mem.cls, name, tsrc))
        m21 = [api21.member_or_sub(c, name)[0] for c in classes]
        if all(mm is None for mm in m21):
          rep.add(S5b, "%s: %s (%s) – %s.%s fehlt in 2.1.20 [%s]" % (where, full, use, "/".join(classes), name, tsrc),
                  error=False)
        elif use == "write" and any(mm is not None and mm.writable for mm in mems) and \
            not any(mm is not None and mm.writable for mm in m21):
          mm21 = next(mm for mm in m21 if mm is not None)
          rep.add(S5b, "%s: %s = … – %s.%s ist in 2.1.20 readonly (%s:%d) [%s]" % (
            where, full, mm21.cls, name, "classes.d.ts", mm21.line, tsrc), error=False)

  # 1/2 auswerten ------------------------------------------------------------------------------
  for path_, wheres in defines_used.items():
    if not path_:
      continue
    text = "defines." + ".".join(path_)
    loc = "%s%s" % (wheres[0], " (+%d)" % (len(wheres) - 1) if len(wheres) > 1 else "")
    st20, st21 = api20.define_status(path_), api21.define_status(path_)
    is_event = path_[0] == "events" and len(path_) >= 2
    if st20 != "ok":
      rep.add(S2 if is_event else S1, "%s: %s – gültig nur bis defines.%s" % (loc, text, ".".join(st20[1]) or "(nichts)"))
    if st21 != "ok":
      rep.add(S1b, "%s: %s – in 2.1.20 gültig nur bis defines.%s" % (loc, text, ".".join(st21[1]) or "(nichts)"), error=False)

  # Ausgabe --------------------------------------------------------------------------------------
  print("== Benutzte defines (%d verschiedene) ==" % len([p for p in defines_used if p]))
  for path_, wheres in sorted(defines_used.items()):
    if path_:
      st = "ok" if api20.define_status(path_) == "ok" else "FEHLT"
      st21 = "ok" if api21.define_status(path_) == "ok" else "FEHLT"
      print("  defines.%-58s 2.0.75 %-5s 2.1.20 %-5s %dx" % (".".join(path_), st, st21, len(wheres)))
  print()
  print("== Globale Einstiegspunkte (%d verschiedene) ==" % len(entry_used))
  for (root, name), wheres in sorted(entry_used.items()):
    cls = GLOBAL_ROOTS[root]
    a = "ok" if api20.member(cls, name) else "FEHLT"
    b = "ok" if api21.member(cls, name) else "FEHLT"
    mem = api20.member(cls, name)
    kind = mem.describe() if mem else "-"
    print("  %-40s 2.0.75 %-5s 2.1.20 %-5s %-24s %dx" % (root + "." + name, a, b, kind, len(wheres)))
  print("  storage: %dx%s" % (len(storage_uses), " (erste: %s)" % storage_uses[0] if storage_uses else ""))
  for w in global_uses:
    rep.add(S6, "%s: global.… – in 2.0 heißt die Tabelle storage" % w)
  for s in shadowed:
    rep.add(S6, s, error=False)
  print()

  print("== Abdeckung ==")
  print("  Member-Zugriffe (ohne Module/defines/event): %d" % stats["zugriffe"])
  print("  Empfängertyp bekannt: global %d, abgeleitet %d, Feldzuweisung %d, Ereignisfeld %d, Name-Hinweis %d" % (
    stats["global"], stats["abgeleitet"], stats["Feldzuweisung"], stats["Ereignisfeld"], stats["Name-Hinweis"]))
  print("  ohne Typ, aber Name ist ein API-Member (nur Prüfungen 3-5 greifen): %d" % stats["untypisiert_api_name"])
  print("  Aufrufe mit geprüftem Tabellen-Argument (Prüfung 8): %d" % stats["tabellen_geprueft"])
  if args.verbose:
    for t in typed_log:
      print("  " + t)
    print("  -- ohne Typ, Name ist API-Member:")
    for t in untyped_log:
      print("  " + t)
  print()

  for section, items in rep.sections.items():
    print("== %s: %d ==" % (section, len(items)))
    for it in items:
      print("  " + it)
    print()
  print("== Zusammenfassung: %d Treffer (Stufe FEHLER), Liste oben von Hand prüfen ==" % rep.errors)
  return 1 if rep.errors else 0


if __name__ == "__main__":
  sys.exit(main())
