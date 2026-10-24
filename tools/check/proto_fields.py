#!/usr/bin/env python3
"""Prüft die Feldnamen der eigenen Prototypen gegen die Prototyp-Typdateien.

Factorio ignoriert unbekannte Schlüssel in Prototypen ohne Fehlermeldung. Ein Feld, das
eine neue Version umbenennt (z. B. 2.1: braking_power → braking_force), wirkt dann einfach
nicht mehr. Der Datenstufen-Test (datastage.py) prüft keine Feldnamen. Dieses Skript liest
einen Dump aller eigenen Prototypen nach dem kompletten Data-Lifecycle (datastage.py
--dump) und vergleicht ihn mit den Typdateien:

  (a) Schlüssel oben im Prototyp, die das Interface (mit extends-Kette, z. B.
      CarPrototype < VehiclePrototype < EntityWithOwnerPrototype < …) nicht kennt
  (b) Pflichtfelder (in den Typdateien nicht optional), die fehlen, auch verschachtelt
  (c) unbekannte Schlüssel in verschachtelten Konzepten (energy_source, minable,
      results, research_trigger, effects, icons, tile_buildability_rules …), Tiefe --tiefe
  (d) Form und Wert: Tabelle statt Liste o. ä., type-Wert ohne passende Variante,
      Zeichenkette außerhalb einer festen Werteliste

Unions werden aufgelöst: Passt type = "…" zu genau einer Variante, gilt diese; sonst die
Variante mit den wenigsten unbekannten Schlüsseln. Typen, die sich nicht auflösen lassen,
stehen unter "nicht geprüft" (es wird nicht geraten). Zu jedem Treffer steht die Stelle im
Mod-Quelltext: Datei:Zeile des Prototyps (aus der data:extend-Stelle, die datastage.py
mitschreibt) und des Schlüssels, oder "nicht im Mod-Quelltext" (z. B. per deepcopy geerbt).

Fehlalarme klein halten:
  - Die Vanilla-Prototypen derselben Typen werden mitgeprüft. Dieselbe Meldung bei Vanilla
    steht unter "wie Vanilla" und zählt nicht (Lücke der Typdatei, z. B. Pflichtfelder in
    FootstepTriggerEffectItem, oder Vanilla-Altlast wie switch_vibration_data). Mit
    --ohne-vanilla zählt alles (z. B. für einen Kreuztest 2.0-Dump gegen 2.1-Typdateien).
  - STRUCT_PARENTS: factorio-types lässt bei "Struktur oder X" das extends weg
    (WorkingSound ohne MainSound); hier ergänzt.
  - ALT_NAMES: typed-factorio führt zweite Feldnamen doppelt als Pflichtfeld
    (braking_power/braking_force, friction/friction_force); einer reicht.
  - BEKANNT: bestätigte Fehlalarme von Hand (zählen nicht für den Exit-Code).

Einrichtung (einmalig; npm nur zum Herunterladen der Typdateien):
  cd tools/check/api                    # wie bei api_names.py
  npm pack factorio-types@1.2.72        # API 2.1.23 → package/dist/prototypes.d.ts, types.d.ts
  mkdir factorio-types-1.2.72 && tar xzf factorio-types-1.2.72.tgz -C factorio-types-1.2.72
  # 2.0 (nur für den Zweig factorio-2.0): typed-factorio 3.36.0 (API 2.0.75) → package/prototype/generated/*.d.ts
  # Vanilla-Daten wie bei datastage.py: fd2123 = factorio-data 2.1.23 (Ziel), fd2077 = 2.0.77,
  # jeweils ohne den Ordner .git

Aufruf (aus dem Repo-Root):
  .venv/bin/python tools/check/datastage.py fd2123 --dump /tmp/p2123.json
  python3 tools/check/proto_fields.py /tmp/p2123.json --typings tools/check/api/factorio-types-1.2.72/package/dist
  .venv/bin/python tools/check/datastage.py fd2077 --dump /tmp/p2077.json
  python3 tools/check/proto_fields.py /tmp/p2077.json --typings tools/check/api/typed-factorio-3.36.0/package/prototype/generated
    --typings   Ordner mit prototypes.d.ts und types.d.ts (factorio-types …/dist oder
                typed-factorio …/prototype/generated); die Settings-Typdatei wird daneben
                gesucht (factorio-types …/src/settings.d.ts, typed-factorio …/settings/types.d.ts)
    --settings  Settings-Typdatei ausdrücklich angeben
    --tiefe N   wie tief verschachtelte Tabellen geprüft werden (Standard 2: z. B.
                minable.results[].probability; 1 = nur eine Ebene unter dem Prototyp,
                8 = auch Grafiken wie animation.layers[].…)
    --repo      Mod-Ordner für die Quelltext-Stellen (Standard: dieses Repo)
    --ohne-vanilla  Meldungen nicht mit Vanilla abgleichen
    -v          auch nicht geprüfte Stellen einzeln auflisten

Nur Python-Standardbibliothek. Exit-Code: 0 = keine Treffer, 1 = Treffer (ohne BEKANNT),
2 = Typdateien nicht lesbar oder Selbsttest des Parsers gescheitert.
"""
import argparse
import json
import os
import re
import sys
from collections import OrderedDict, defaultdict

# Bestätigte Fehlalarme: (Prototyp-Typ oder "*", Pfad ohne Listenindex) → Begründung.
# Pfad wie in der Ausgabe, z. B. "minable.results[].probability" oder "foo".
BEKANNT = {
    # Fehlt in den Prototyp-Typdateien 2.1.23 und 2.0.75, ist aber ein echtes Feld: Die Laufzeit-API kennt
    # LuaItemPrototype.factoriopedia_durability_description_key in beiden Versionen (factorio-types 1.2.72
    # classes.d.ts:14547), Vanilla 2.0.77 setzt es an allen Tools. In 2.1.23 gibt es nur kein Vanilla-Tool mehr.
    ("tool", "factoriopedia_durability_description_key"):
        "nur in der Prototyp-Doku nicht aufgeführt; Laufzeit-API 2.1.23 kennt es (LuaItemPrototype)",
}

NUMBER_ALIASES = {"double", "float", "int", "int8", "int16", "int32", "int64", "uint", "uint8",
                  "uint16", "uint32", "uint64", "number"}
BUILTIN_ALIASES = {
    # typed-factorio: bedingter Typ in common/types.d.ts, ohne eigene Deklarationen = string
    "CustomInputName": ("prim", "string"),
}
# typed-factorio (2.0.75) führt Felder mit zweitem Namen doppelt als Pflichtfeld (VehiclePrototype:
# "There is no functional difference between the two ways"). Einer von beiden reicht.
ALT_NAMES = {"braking_power": "braking_force", "braking_force": "braking_power",
             "friction": "friction_force", "friction_force": "friction"}
STRUCT_PARENTS = {"WorkingSound": "MainSound", "Fade": "Attenuation", "LayeredSprite": "Sprite"}
SETTING_TYPES = {"bool-setting", "int-setting", "double-setting", "string-setting", "color-setting"}

# ---------------------------------------------------------------------------------------------
# TypeScript-Deklarationen lesen (nur das, was die Typdateien benutzen)

TOKEN_RE = re.compile(r"""
    (?P<ws>\s+)
  | (?P<bc>/\*.*?\*/)
  | (?P<lc>//[^\n]*)
  | (?P<str>'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*"|`(?:[^`\\]|\\.)*`)
  | (?P<num>\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)
  | (?P<id>[A-Za-z_$][\w$]*)
  | (?P<op>=>|\.\.\.|[{}()\[\]<>;:,|&=?.*+\-!@#%^~])
""", re.S | re.X)


class ParseError(Exception):
    pass


def tokenize(text):
    tokens, pos, line = [], 0, 1
    while pos < len(text):
        m = TOKEN_RE.match(text, pos)
        if not m:
            raise ParseError("Zeichen %r in Zeile %d" % (text[pos], line))
        kind = m.lastgroup
        value = m.group()
        if kind not in ("ws", "bc", "lc"):
            if kind == "str":
                value = re.sub(r"\\(.)", r"\1", value[1:-1])
            tokens.append((kind, value, line))
        line += m.group().count("\n")
        pos = m.end()
    tokens.append(("eof", "", line))
    return tokens


class Parser:
    def __init__(self, tokens, filename):
        self.t = tokens
        self.i = 0
        self.file = filename
        self.ns = "prototype"

    def peek(self, k=0):
        return self.t[min(self.i + k, len(self.t) - 1)]

    def at(self, value, k=0):
        tok = self.peek(k)
        return tok[0] in ("op", "id") and tok[1] == value

    def take(self, value=None):
        tok = self.t[self.i]
        if value is not None and not (tok[0] in ("op", "id") and tok[1] == value):
            raise ParseError("%s:%d: erwartet %r, gefunden %r" % (self.file, tok[2], value, tok[1]))
        self.i += 1
        return tok

    # --- Typausdrücke
    def parse_type(self):
        if self.at("|"):
            self.take()
        alts = [self.parse_inter()]
        while self.at("|"):
            self.take()
            alts.append(self.parse_inter())
        return alts[0] if len(alts) == 1 else ("union", alts)

    def parse_inter(self):
        if self.at("&"):
            self.take()
        parts = [self.parse_postfix()]
        while self.at("&"):
            self.take()
            parts.append(self.parse_postfix())
        node = parts[0] if len(parts) == 1 else ("inter", parts)
        if self.at("extends"):
            # bedingter Typ (A extends B ? C : D): nicht auswertbar, Deklaration wird übersprungen
            raise ParseError("%s:%d: bedingter Typ" % (self.file, self.peek()[2]))
        return node

    def parse_postfix(self):
        node = self.parse_primary()
        while self.at("["):
            if self.at("]", 1):
                self.take()
                self.take()
                node = ("arr", node)
            elif self.peek(1)[0] == "id" and (self.at(":", 2) or self.at("in", 2) or self.at("?", 2)):
                break  # nächstes Member ist eine Indexsignatur (typed-factorio ohne Semikolon)
            else:
                self.take()
                self.parse_type()
                self.take("]")
                node = ("unk", "Indexzugriff")
        return node

    def parse_primary(self):
        kind, value, line = self.peek()
        if kind == "op" and value == "(":
            # Funktionstyp oder Klammer
            if self.at(")", 1) or self.at("...", 1) or (self.peek(1)[0] == "id" and (self.at(":", 2) or self.at("?", 2))):
                self.skip_balanced("(", ")")
                self.take("=>")
                self.parse_type()
                return ("func",)
            self.take()
            node = self.parse_type()
            self.take(")")
            return node
        if kind == "op" and value == "{":
            members, index = self.parse_members()
            return ("obj", members, index)
        if kind == "op" and value == "[":
            self.take()
            elems = []
            while not self.at("]"):
                rest = False
                if self.at("..."):
                    self.take()
                    rest = True
                if self.peek()[0] == "id" and (self.at(":", 1) or (self.at("?", 1) and self.at(":", 2))):
                    self.take()
                    if self.at("?"):
                        self.take()
                    self.take(":")
                elem = self.parse_type()
                if self.at("?"):
                    self.take()
                elems.append(("rest", elem) if rest else elem)
                if self.at(","):
                    self.take()
            self.take("]")
            return ("tup", elems)
        if kind == "str":
            self.take()
            return ("lit", value)
        if kind == "num":
            self.take()
            return ("lit", float(value))
        if kind == "op" and value == "-" and self.peek(1)[0] == "num":
            self.take()
            return ("lit", -float(self.take()[1]))
        if kind == "id":
            if value in ("readonly", "unique"):
                self.take()
                return self.parse_postfix()
            if value in ("keyof", "typeof"):
                self.take()
                self.parse_postfix()
                return ("unk", value)
            if value in ("true", "false"):
                self.take()
                return ("lit", value == "true")
            self.take()
            name = value
            while self.at(".") and self.peek(1)[0] == "id":
                self.take()
                name += "." + self.take()[1]  # Namensraum, z. B. settings.dataExtendType
            args = []
            if self.at("<"):
                self.take()
                while not self.at(">"):
                    args.append(self.parse_type())
                    if self.at(","):
                        self.take()
                self.take(">")
            if name in ("string", "number", "boolean", "any", "unknown", "object", "never",
                        "undefined", "null", "void", "nil", "bigint", "symbol"):
                return ("prim", name)
            return ("ref", name, args)
        raise ParseError("%s:%d: unerwartet %r" % (self.file, line, value))

    def skip_balanced(self, open_, close):
        depth = 0
        while True:
            tok = self.take()
            if tok[0] == "eof":
                raise ParseError("%s: Dateiende in Klammer" % self.file)
            if tok[0] == "op" and tok[1] == open_:
                depth += 1
            elif tok[0] == "op" and tok[1] == close:
                depth -= 1
                if depth == 0:
                    return

    def parse_members(self):
        """{ name?: Typ; … } → (OrderedDict name → (optional, Typ, Zeile), Index-Typ oder None)"""
        self.take("{")
        members, index = OrderedDict(), None
        while not self.at("}"):
            if self.at(";") or self.at(","):
                self.take()
                continue
            if self.at("readonly") and not (self.at(":", 1) or self.at("?", 1)):
                self.take()
            kind, value, line = self.peek()
            if kind == "op" and value == "[":
                # Indexsignatur [key: string]: T oder abgebildeter Typ [K in X]: T
                self.take()
                self.take()
                if self.at("in"):
                    self.take()
                else:
                    self.take(":")
                self.parse_type()
                self.take("]")
                if self.at("?"):
                    self.take()
                self.take(":")
                index = self.parse_type()
                continue
            if kind == "op" and value in ("(", "<"):
                raise ParseError("%s:%d: Aufrufsignatur" % (self.file, line))
            if kind not in ("id", "str", "num"):
                raise ParseError("%s:%d: Member erwartet, gefunden %r" % (self.file, line, value))
            self.take()
            optional = False
            if self.at("?"):
                self.take()
                optional = True
            if self.at("(") or self.at("<"):
                # Methode: überspringen
                if self.at("<"):
                    self.skip_balanced("<", ">")
                self.skip_balanced("(", ")")
                if self.at(":"):
                    self.take()
                    self.parse_type()
                continue
            self.take(":")
            members[value] = (optional, self.parse_type(), line)
        self.take("}")
        return members, index

    def parse_type_params(self):
        params = []
        if self.at("<"):
            self.take()
            while not self.at(">"):
                params.append(self.take()[1])
                if self.at("extends"):
                    self.take()
                    self.parse_type()
                if self.at("="):
                    self.take()
                    self.parse_type()
                if self.at(","):
                    self.take()
            self.take(">")
        return params

    def parse_file(self, decls):
        while self.peek()[0] != "eof":
            kind, value, line = self.peek()
            # declare namespace settings { … } (factorio-types), declare module "factorio:settings" { … } (typed-factorio)
            if kind == "id" and value in ("namespace", "module") and self.peek(1)[0] in ("id", "str"):
                self.ns = self.peek(1)[1].split(":")[-1]
            if kind == "id" and value == "interface" and self.peek(1)[0] == "id":
                start = self.i
                try:
                    self.take()
                    name = self.take()[1]
                    params = self.parse_type_params()
                    extends = []
                    if self.at("extends"):
                        self.take()
                        extends.append(self.parse_postfix())
                        while self.at(","):
                            self.take()
                            extends.append(self.parse_postfix())
                    members, index = self.parse_members()
                    decls.add_interface(name, params, extends, members, index, self.file, line, self.ns)
                except ParseError as e:
                    decls.errors.append(str(e))
                    self.i = start + 1
                continue
            if kind == "id" and value == "type" and self.peek(1)[0] == "id" and (self.at("=", 2) or self.at("<", 2)):
                start = self.i
                try:
                    self.take()
                    name = self.take()[1]
                    params = self.parse_type_params()
                    self.take("=")
                    decls.add_alias(name, params, self.parse_type(), self.file, line, self.ns)
                except ParseError as e:
                    decls.errors.append(str(e))
                    self.i = start + 1
                continue
            self.i += 1


class Decls:
    def __init__(self):
        self.interfaces = {}
        self.aliases = {}
        self.errors = []
        self.files = []

    # Namen außerhalb des Prototyp-Namensraums (settings) stehen als "settings.X" und, wenn frei, als "X".
    def add_interface(self, name, params, extends, members, index, file, line, ns="prototype"):
        key = name if ns == "prototype" else ns + "." + name
        if key in self.interfaces:
            # gleichnamige Interfaces werden in TypeScript zusammengeführt
            old = self.interfaces[key]
            old["extends"] += extends
            old["members"].update(members)
            old["index"] = old["index"] or index
            return
        self.interfaces[key] = {"params": params, "extends": extends, "members": members,
                                "index": index, "where": "%s:%d" % (os.path.basename(file), line)}
        if key != name:
            self.interfaces.setdefault(name, self.interfaces[key])

    def add_alias(self, name, params, type_, file, line, ns="prototype"):
        key = name if ns == "prototype" else ns + "." + name
        decl = {"params": params, "type": type_, "where": "%s:%d" % (os.path.basename(file), line)}
        self.aliases.setdefault(key, decl)
        if key != name:
            self.aliases.setdefault(name, decl)

    def lookup(self, name):
        """→ ("iface"|"alias"|None, Schlüssel); qualifizierte Namen notfalls ohne Namensraum."""
        for key in (name, name.rsplit(".", 1)[-1]):
            if key in self.interfaces:
                return "iface", key
            if key in self.aliases:
                return "alias", key
        return None, name

    def patch_struct_parents(self):
        # factorio-types schreibt "Struktur oder X" als type X = {…} | … und lässt dabei das extends
        # der Struktur weg; typed-factorio 3.36 hat es (WorkingSoundStruct extends MainSound usw.).
        for name, parent in STRUCT_PARENTS.items():
            decl = self.aliases.get(name)
            if not decl or parent not in self.interfaces:
                continue
            t = decl["type"]
            alts = t[1] if t[0] == "union" else [t]
            alts = [("inter", [("ref", parent, []), a]) if a[0] == "obj" else a for a in alts]
            decl["type"] = ("union", alts) if t[0] == "union" else alts[0]

    def load(self, path):
        with open(path, encoding="utf-8") as f:
            text = f.read()
        Parser(tokenize(text), path).parse_file(self)
        self.files.append(path)


# ---------------------------------------------------------------------------------------------
# Typen zu "Formen" auflösen

class Shape:
    """kind: obj | arr | scalar | any | unk"""

    def __init__(self, kind, **kw):
        self.kind = kind
        self.members = kw.get("members")       # obj: name → (optional, typ, herkunft)
        self.index = kw.get("index")           # obj: Typ für beliebige Schlüssel
        self.label = kw.get("label", "")
        self.chain = kw.get("chain", [])
        self.elem = kw.get("elem")             # arr: Elementtyp (oder Liste bei Tupel)
        self.prims = kw.get("prims", set())    # scalar: string/number/boolean/nil/function
        self.lits = kw.get("lits", set())      # scalar: feste Werte
        self.reason = kw.get("reason", "")
        self.subst = kw.get("subst", {})

    def type_literals(self):
        if self.kind != "obj" or "type" not in self.members:
            return None
        _, t, _ = self.members["type"]
        lits = set()
        for s in RESOLVER.expand(t, {}):
            if s.kind == "scalar" and s.lits and not s.prims:
                lits |= s.lits
            else:
                return None
        return lits or None

    def describe(self):
        if self.kind == "obj":
            return self.label or "Tabelle"
        if self.kind == "arr":
            return "Liste"
        if self.kind == "scalar":
            parts = sorted(self.prims) + sorted(repr(l) for l in self.lits)
            return "|".join(parts[:6]) + ("|…" if len(parts) > 6 else "")
        return self.kind


class Resolver:
    def __init__(self, decls):
        self.d = decls
        self.iface_cache = {}

    def type_name(self, t):
        if t[0] == "ref":
            return t[1] + ("<…>" if t[2] else "")
        if t[0] == "arr":
            return self.type_name(t[1]) + "[]"
        if t[0] == "union":
            return " | ".join(self.type_name(a) for a in t[1][:4]) + (" | …" if len(t[1]) > 4 else "")
        if t[0] == "inter":
            return " & ".join(self.type_name(a) for a in t[1])
        if t[0] == "lit":
            return repr(t[1])
        if t[0] == "prim":
            return t[1]
        if t[0] == "tup":
            return "[…]"
        if t[0] == "obj":
            return "{…}"
        return t[0]

    def interface(self, name, args=(), stack=()):
        key = (name, tuple(map(repr, args)))
        if key in self.iface_cache:
            return self.iface_cache[key]
        decl = self.d.interfaces[self.d.lookup(name)[1]]
        subst = dict(zip(decl["params"], args))
        members, chain, index = OrderedDict(), [name], decl["index"]
        if name in stack:
            return Shape("unk", reason="rekursives Interface " + name)
        for base in decl["extends"]:
            base = self.subst(base, subst)
            if base[0] == "ref" and self.d.lookup(base[1])[0] == "iface":
                b = self.interface(base[1], base[2], stack + (name,))
                if b.kind == "obj":
                    members.update(b.members)
                    chain += b.chain
                    index = index or b.index
                    continue
            shapes = self.expand(base, {})
            for s in shapes:
                if s.kind == "obj":
                    members.update(s.members)
                    index = index or s.index
            chain.append(self.type_name(base))
        for m, (opt, t, line) in decl["members"].items():
            members[m] = (opt, self.subst(t, subst), name)
        shape = Shape("obj", members=members, index=index, label=name, chain=chain)
        self.iface_cache[key] = shape
        return shape

    def subst(self, t, subst):
        if not subst:
            return t
        k = t[0]
        if k == "ref":
            if t[1] in subst and not t[2]:
                return subst[t[1]]
            return ("ref", t[1], [self.subst(a, subst) for a in t[2]])
        if k in ("arr", "rest"):
            return (k, self.subst(t[1], subst))
        if k in ("union", "inter", "tup"):
            return (k, [self.subst(a, subst) for a in t[1]])
        if k == "obj":
            return ("obj", OrderedDict((m, (o, self.subst(x, subst), l)) for m, (o, x, l) in t[1].items()),
                    t[2] and self.subst(t[2], subst))
        return t

    def expand(self, t, subst, stack=()):
        """Typ → Liste von Shapes (Unions flach)."""
        k = t[0]
        if len(stack) > 40:
            return [Shape("unk", reason="zu tief verschachtelt")]
        if k == "prim":
            n = t[1]
            if n in ("string", "number", "boolean"):
                return [Shape("scalar", prims={n})]
            if n in ("undefined", "null", "void", "nil"):
                return [Shape("scalar", prims={"nil"})]
            if n == "never":
                return []
            return [Shape("any", reason=n)]
        if k == "lit":
            return [Shape("scalar", lits={t[1]})]
        if k == "func":
            return [Shape("scalar", prims={"function"})]
        if k == "unk":
            return [Shape("unk", reason=t[1])]
        if k == "arr":
            return [Shape("arr", elem=self.subst(t[1], subst))]
        if k == "tup":
            return [Shape("arr", elem=[self.subst(e, subst) for e in t[1]])]
        if k == "union":
            out = []
            for a in t[1]:
                out += self.expand(a, subst, stack)
            return merge_scalars(out)
        if k == "obj":
            members = OrderedDict((m, (o, self.subst(x, subst), "{…}")) for m, (o, x, l) in t[1].items())
            return [Shape("obj", members=members, index=t[2] and self.subst(t[2], subst), label="{…}", chain=["{…}"])]
        if k == "inter":
            combos = [[]]
            for part in t[1]:
                shapes = self.expand(part, subst, stack)
                combos = [c + [s] for c in combos for s in shapes][:64]
            out = []
            for combo in combos:
                objs = [s for s in combo if s.kind == "obj"]
                if any(s.kind == "unk" for s in combo):
                    out.append(next(s for s in combo if s.kind == "unk"))
                elif len(objs) == len(combo):
                    members, chain, index = OrderedDict(), [], None
                    for s in objs:
                        for m, v in s.members.items():
                            # spätere Teile überschreiben, nur ein festes type = '…' bleibt stehen
                            if m == "type" and m in members and members[m][1][0] == "lit":
                                continue
                            members[m] = v
                        chain += s.chain
                        index = index or s.index
                    label = " & ".join(s.label for s in objs if s.label != "{…}") or "{…}"
                    out.append(Shape("obj", members=members, index=index, label=label, chain=chain))
                else:
                    out.append(Shape("unk", reason="Schnitt aus " + ", ".join(s.kind for s in combo)))
            return out
        if k == "ref":
            name, args = t[1], [self.subst(a, subst) for a in t[2]]
            if name in subst and not args:
                return self.expand(subst[name], {}, stack)
            if name in NUMBER_ALIASES or name.startswith("defines."):
                # defines.* sind in der Data-Stage Zahlen
                return [Shape("scalar", prims={"number"})]
            if name in ("Array", "ReadonlyArray") and args:
                return [Shape("arr", elem=args[0])]
            if name == "Record" and len(args) == 2:
                return [Shape("obj", members=OrderedDict(), index=args[1], label="Record", chain=["Record"])]
            if name in ("Omit", "Pick") and len(args) == 2:
                keys = set()
                for s in self.expand(args[1], {}, stack):
                    keys |= {l for l in s.lits if isinstance(l, str)}
                out = []
                for s in self.expand(args[0], {}, stack):
                    if s.kind == "obj":
                        keep = (lambda m: m not in keys) if name == "Omit" else (lambda m: m in keys)
                        s = Shape("obj", members=OrderedDict((m, v) for m, v in s.members.items() if keep(m)),
                                  index=s.index, label=s.label, chain=s.chain)
                    out.append(s)
                return out
            if name in ("Partial", "Readonly", "Required") and args:
                out = []
                for s in self.expand(args[0], {}, stack):
                    if s.kind == "obj" and name == "Partial":
                        s = Shape("obj", members=OrderedDict((m, (True, x, o)) for m, (_, x, o) in s.members.items()),
                                  index=s.index, label="Partial<" + s.label + ">", chain=s.chain)
                    out.append(s)
                return out
            if name in ("LuaTable", "LuaMap", "Table", "LuaObject", "LuaCustomTable"):
                return [Shape("any", reason=name)]
            found, key = self.d.lookup(name)
            if found and key in stack:
                return [Shape("unk", reason="rekursiv " + key)]
            if found == "iface":
                return [self.interface(key, args, stack)]
            if found == "alias":
                decl = self.d.aliases[key]
                return self.expand(decl["type"], dict(zip(decl["params"], args)), stack + (key,))
            if name in BUILTIN_ALIASES:
                return self.expand(BUILTIN_ALIASES[name], {}, stack)
            return [Shape("unk", reason="Typ %s unbekannt" % name)]
        if k == "rest":
            return self.expand(t[1], subst, stack)
        return [Shape("unk", reason="Ausdruck " + k)]


def merge_scalars(shapes):
    out, scalar = [], None
    for s in shapes:
        if s.kind == "scalar":
            if scalar is None:
                scalar = Shape("scalar", prims=set(s.prims), lits=set(s.lits))
                out.append(scalar)
            else:
                scalar.prims |= s.prims
                scalar.lits |= s.lits
        else:
            out.append(s)
    return out


RESOLVER = None

# ---------------------------------------------------------------------------------------------
# Werte prüfen


def value_kind(v):
    if isinstance(v, dict):
        return "empty" if not v else "obj"
    if isinstance(v, list):
        return "arr"
    if isinstance(v, bool):
        return "boolean"
    if isinstance(v, (int, float)):
        return "number"
    if isinstance(v, str):
        return "string"
    return "nil"


def scalar_match(shape, v):
    k = value_kind(v)
    if k in shape.prims:
        return True
    if k == "number" and any(isinstance(l, float) and not isinstance(l, bool) and l == v for l in shape.lits):
        return True
    if k in ("string", "boolean") and v in shape.lits and any(type(l) is type(v) for l in shape.lits if l == v):
        return True
    return False


def shape_matches(shape, v):
    k = value_kind(v)
    if shape.kind in ("any", "unk"):
        return True
    if shape.kind == "obj":
        return k in ("obj", "empty")
    if shape.kind == "arr":
        return k in ("arr", "empty")
    if shape.kind == "scalar":
        return scalar_match(shape, v)
    return False


def strip_index(path):
    return re.sub(r"\[\d+\]", "[]", path)


class Checker:
    def __init__(self, resolver, max_level):
        self.r = resolver
        self.max_level = max_level
        self.hits = []        # (kategorie, pfad, text)
        self.unchecked = []   # (pfad, grund)
        self.tables = 0       # geprüfte Tabellen
        self.free = 0         # Tabellen mit freiem Typ (any, Record, LuaTable …)

    def unknown_and_missing(self, shape, value):
        unknown = [k for k in value if k not in shape.members] if shape.index is None else []
        missing = [m for m, (opt, _, _) in shape.members.items()
                   if not opt and m not in value and not (ALT_NAMES.get(m, "") in value)]
        return unknown, missing

    def choose(self, shapes, value, path):
        """Wählt für eine Tabelle die passende Variante. Gibt (shape, problem) zurück."""
        objs = [s for s in shapes if s.kind == "obj"]
        if not objs:
            return None, None
        cands = objs
        vtype = value.get("type") if isinstance(value, dict) else None
        if isinstance(vtype, str) and len(objs) > 1:
            with_lit = [(s, s.type_literals()) for s in objs]
            typed = [s for s, lits in with_lit if lits and vtype in lits]
            untyped = [s for s, lits in with_lit if not lits]
            if typed:
                cands = typed
            elif untyped:
                cands = untyped
            else:
                names = sorted({s.label for s in objs})
                return None, "type = %r passt zu keiner Variante (%s)" % (vtype, ", ".join(names[:8]) + (", …" if len(names) > 8 else ""))

        def score(s):
            unknown, missing = self.unknown_and_missing(s, value)
            return (len(unknown), len(missing))
        return min(cands, key=score), None

    def check(self, value, t, path, level, proto_type):
        shapes = self.r.expand(t, {})
        if not shapes:
            return
        kinds = {s.kind for s in shapes}
        k = value_kind(value)
        if "unk" in kinds and not any(shape_matches(s, value) for s in shapes if s.kind != "unk"):
            reasons = sorted({s.reason for s in shapes if s.kind == "unk"})
            self.unchecked.append((path, "; ".join(reasons)))
            return
        if "any" in kinds and k in ("obj", "arr", "empty") and not any(s.kind in ("obj", "arr") for s in shapes):
            self.free += 1
            return
        matching = [s for s in shapes if shape_matches(s, value)]
        if not matching:
            expected = ", ".join(sorted({s.describe() for s in shapes}))
            if k in ("string", "number", "boolean") and all(s.kind == "scalar" for s in shapes):
                shown = json.dumps(value, ensure_ascii=False)
                self.hits.append(("d", path, "Wert %s nicht erlaubt (erwartet %s)" % (shown, expected)))
            else:
                self.hits.append(("d", path, "Form %s passt nicht (erwartet %s)" % (k, expected)))
            return
        if k == "empty":
            return
        if k == "obj":
            shape, problem = self.choose(matching, value, path)
            if problem:
                self.hits.append(("d", path, problem))
                return
            if shape is None:
                return
            if "unk" in kinds and self.unknown_and_missing(shape, value)[0]:
                # passt nicht sauber; vielleicht ist die nicht auflösbare Variante gemeint
                reasons = sorted({s.reason for s in shapes if s.kind == "unk"})
                self.unchecked.append((path, "; ".join(reasons)))
                return
            self.check_object(value, shape, path, level, proto_type)
        elif k == "arr":
            arrs = [s for s in matching if s.kind == "arr"]
            if not arrs:
                return
            if len(arrs) > 1:
                # mehrere Listenformen (z. B. Tupel oder Liste von Tabellen): erste ohne Treffer nehmen
                arrs.sort(key=lambda s: self.trial(value, s, path, level, proto_type))
            self.check_array(value, arrs[0], path, level, proto_type)

    def trial(self, value, shape, path, level, proto_type):
        probe = Checker(self.r, self.max_level)
        probe.check_array(value, shape, path, level, proto_type)
        return len(probe.hits)

    def check_array(self, value, shape, path, level, proto_type):
        if isinstance(shape.elem, list):
            elems = shape.elem
            for i, v in enumerate(value):
                if i < len(elems):
                    e = elems[i]
                elif elems and elems[-1][0] == "rest":
                    e = elems[-1]
                else:
                    self.hits.append(("d", "%s[%d]" % (path, i + 1), "Tupel hat nur %d Einträge" % len(elems)))
                    break
                if e[0] == "rest":
                    e = e[1]
                    if e[0] == "arr":
                        e = e[1]
                self.check(v, e, "%s[%d]" % (path, i + 1), level, proto_type)
        else:
            for i, v in enumerate(value):
                self.check(v, shape.elem, "%s[%d]" % (path, i + 1), level, proto_type)

    def check_object(self, value, shape, path, level, proto_type):
        self.tables += 1
        if shape.index is not None:
            self.free += 1
        unknown, missing = self.unknown_and_missing(shape, value)
        prefix = path + "." if path else ""
        cat_unknown = "a" if level == 0 else "c"
        for key in unknown:
            self.hits.append((cat_unknown, prefix + key, "unbekannt in %s" % shape.label))
        for key in missing:
            self.hits.append(("b", prefix + key, "Pflichtfeld aus %s fehlt" % shape.members[key][2]))
        if level >= self.max_level:
            return
        for key, v in value.items():
            if key in shape.members:
                t = shape.members[key][1]
            elif shape.index is not None:
                t = shape.index
            else:
                continue
            self.check(v, t, prefix + key, level + 1, proto_type)


# ---------------------------------------------------------------------------------------------
# Quelltext-Stellen


class Sources:
    def __init__(self, repo):
        self.repo = repo
        self.cache = {}

    def lines(self, rel):
        if rel not in self.cache:
            path = os.path.join(self.repo, rel)
            try:
                with open(path, encoding="utf-8") as f:
                    self.cache[rel] = f.read().split("\n")
            except OSError:
                self.cache[rel] = None
        return self.cache[rel]

    def resolve(self, source):
        """'prototypes/x.lua:12' → (datei, zeile) mit vorhandener Datei, sonst (None, None)."""
        if not source:
            return None, None
        rel, _, line = source.rpartition(":")
        if self.lines(rel) is None:
            # draftsman hängt bei verschachteltem require manchmal den Elternpfad doppelt an
            parts = rel.split("/")
            for i in range(1, len(parts)):
                if self.lines("/".join(parts[i:])) is not None:
                    rel = "/".join(parts[i:])
                    break
            else:
                return None, None
        return rel, int(line) if line.isdigit() else 0

    NAME_RE = re.compile(r'(^|[^\w])name\s*=\s*["\']')

    def find_name(self, rel, name, ptype, near):
        """Zeile, an der der Prototyp entsteht: name = "…" mit type = "…" in der Nähe, sonst
        x.name = "…" (Kopie), sonst "…" als Argument vor data:extend (z. B. make_proxy("…")),
        sonst die data:extend-Zeile."""
        lines = self.lines(rel) or []
        quoted = re.compile(r'["\']' + re.escape(name) + r'["\']')
        pat = re.compile(r'(^|[^\w])name\s*=\s*["\']' + re.escape(name) + r'["\']')
        found = [i + 1 for i, l in enumerate(lines) if pat.search(l)]
        tpat = re.compile(r'type\s*=\s*["\']' + re.escape(ptype) + r'["\']')
        typed = [i for i in found if any(tpat.search(l) for l in lines[max(0, i - 6):i + 5])]
        copied = [i for i in found if re.search(r"\.name\s*=", lines[i - 1])]  # x = table.deepcopy(…); x.name = …
        if typed or copied:
            return min(typed or copied, key=lambda i: abs(i - near))
        args = [i + 1 for i, l in enumerate(lines[:near]) if quoted.search(l) and "(" in l and not l.lstrip().startswith("--")]
        return args[-1] if args else near

    def find_key(self, rel, key, start):
        """→ (Datei, Zeile, im_prototyp) für "key =" ab start bis zum nächsten Prototyp, sonst
        irgendwo in der Datei, sonst in compat.lua (schreibt Felder für 2.1 um); oder None."""
        pat = re.compile(r'(^|[^\w.])' + re.escape(key) + r'\s*=[^=]|\.' + re.escape(key) + r'\s*=[^=]|\[\s*["\']'
                         + re.escape(key) + r'["\']\s*\]\s*=')
        for f in (rel, "prototypes/compat.lua"):
            lines = self.lines(f) or []
            found = [i + 1 for i, l in enumerate(lines) if pat.search(l) and not l.lstrip().startswith("--")]
            if not found:
                continue
            if f == rel:
                end = next((i + 1 for i in range(start, len(lines)) if self.NAME_RE.search(lines[i])), len(lines))
                inside = [i for i in found if start <= i <= end]
                if inside:
                    return f, inside[0], True
            return f, found[0], False
        return None


# ---------------------------------------------------------------------------------------------


def find_settings_typings(typings):
    for cand in (os.path.join(typings, "..", "src", "settings.d.ts"),
                 os.path.join(typings, "..", "..", "settings", "types.d.ts"),
                 os.path.join(typings, "settings.d.ts")):
        if os.path.isfile(cand):
            return os.path.normpath(cand)
    return None


def build_type_map(decls):
    """Prototyp-Typ ("car") → Typausdruck, aus dataCollection / PrototypeMap / dataExtendType."""
    tmap = {}
    for iface in ("dataCollection", "PrototypeMap", "settings.PrototypeMap"):
        decl = decls.interfaces.get(iface)
        if not decl:
            continue
        for key, (_, t, _) in decl["members"].items():
            if t[0] == "obj" and t[2] is not None:
                t = t[2]
            if t[0] == "ref":
                tmap.setdefault(key, t)

    def walk(t, seen):
        if t[0] == "union":
            for alt in t[1]:
                walk(alt, seen)
        elif t[0] == "ref" and t[1] not in seen:
            found, key = decls.lookup(t[1])
            if found == "alias":
                walk(decls.aliases[key]["type"], seen | {t[1]})
        elif t[0] == "inter":
            for part in t[1]:
                if part[0] == "obj" and "type" in part[1] and part[1]["type"][1][0] == "lit":
                    tmap.setdefault(part[1]["type"][1][1], t)
    for name in ("dataExtendType", "settings.dataExtendType"):
        if name in decls.aliases:
            walk(decls.aliases[name]["type"], {name})
    return tmap


def path_exists(value, parts):
    """Gibt es den Pfad (Teile ohne Index, "[]" = jedes Listenelement) in value?"""
    if not parts:
        return True
    head, rest = parts[0], parts[1:]
    if head == "[]":
        return isinstance(value, list) and any(path_exists(v, rest) for v in value)
    return isinstance(value, dict) and head in value and path_exists(value[head], rest)


def split_path(path):
    return [p for p in re.split(r"\.|(\[\])", strip_index(path)) if p]


def self_test():
    d = Decls()
    text = """
    declare namespace prototype {
    /** Kommentar mit `code` und // Strichen */
    interface Base { name: string; type: string; order?: Order; }
    interface Thing extends Base {
        /** a */
        energy_source: BurnerEnergySource | VoidEnergySource;
        list?: (ItemID | {name: string})[];
        tup?: [double, double] | {x: double, y: double};
        rec?: Record<string, double>
        flags?: ('a' | 'b')[]
        pic?: Pic
        stop?: double
    }
    interface PicParams { filename: string; width?: double }
    interface Pic extends Omit<PicParams, "filename"> { layers?: Pic[] }
    interface BurnerEnergySource { type: 'burner'; fuel_categories?: string[] }
    interface VoidEnergySource { type: 'void' }
    type Order = string
    type ItemID = string;
    type Cond<T> = [keyof T] extends [never] ? string : keyof T
    }
    """
    Parser(tokenize(text), "selbsttest").parse_file(d)
    Parser(tokenize("declare namespace settings { interface S extends prototype.Base { x?: boolean } "
                    "type dataExtendType = ({ type: 's' } & S) }"), "selbsttest").parse_file(d)
    r = Resolver(d)
    global RESOLVER
    RESOLVER = r
    c = Checker(r, 2)
    value = {"name": "x", "type": "thing", "energy_source": {"type": "burner", "fuel_category": "chemical"},
             "list": ["a", {"name": "b", "amount": 1}], "tup": [1, 2], "rec": {"q": 1}, "flags": ["a", "c"], "bogus": 1,
             "pic": {"width": 1, "filename": "x"}, "stop": [1]}
    c.check_object(value, r.interface("Thing"), "", 0, "thing")
    got = sorted((cat, p) for cat, p, _ in c.hits)
    want = [("a", "bogus"), ("c", "energy_source.fuel_category"), ("c", "list[2].amount"), ("c", "pic.filename"),
            ("d", "flags[2]"), ("d", "stop")]
    errors = []
    if len(d.errors) != 1 or "bedingter Typ" not in d.errors[0] or "Cond" in d.aliases:
        errors.append("Parserfehler: " + "; ".join(d.errors))
    if got != want:
        errors.append("Treffer %s statt %s" % (got, want))
    tm = build_type_map(d)
    shape = prototype_shape(r, tm, "s")
    c3 = Checker(r, 2)
    if shape:
        c3.check_object({"type": "s", "name": "n", "x": True, "y": 1}, shape, "", 0, "s")
    if not shape or [(cat, p) for cat, p, _ in c3.hits] != [("a", "y")]:
        errors.append("Settings-Namensraum: %s" % c3.hits)
    c2 = Checker(r, 2)
    c2.check_object({"name": "x", "type": "thing", "energy_source": {"type": "heat"}}, r.interface("Thing"), "", 0, "thing")
    if [(cat, p) for cat, p, _ in c2.hits] != [("d", "energy_source")]:
        errors.append("type-Variante: %s" % c2.hits)
    return errors


def load_typings(typings, settings_file):
    decls = Decls()
    files = [os.path.join(typings, n) for n in ("prototypes.d.ts", "types.d.ts", "datacollection.d.ts")]
    for f in files + ([settings_file] if settings_file else []):
        if os.path.isfile(f):
            decls.load(f)
    decls.patch_struct_parents()
    version = "?"
    for f in decls.files:
        with open(f, encoding="utf-8") as fh:
            head = fh.read(3000)
        m = re.search(r"Factorio version (\S+)|lua-api\.factorio\.com/(\d+\.\d+\.\d+)/", head)
        if m:
            version = m.group(1) or m.group(2)
            break
    return decls, version


def prototype_shape(resolver, tmap, ptype):
    t = tmap.get(ptype)
    if t is None:
        return None
    shapes = [s for s in resolver.expand(t, {}) if s.kind == "obj"]
    return shapes[0] if len(shapes) == 1 else None


def main():
    global RESOLVER
    ap = argparse.ArgumentParser(description="Feldnamen eigener Prototypen gegen die Typdateien prüfen")
    ap.add_argument("dump", help="JSON von datastage.py --dump")
    ap.add_argument("--typings", required=True, help="Ordner mit prototypes.d.ts und types.d.ts")
    ap.add_argument("--settings", help="Settings-Typdatei (Standard: neben --typings gesucht)")
    ap.add_argument("--tiefe", type=int, default=2, help="Tiefe für verschachtelte Tabellen (Standard 2)")
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    ap.add_argument("--ohne-vanilla", action="store_true", help="Meldungen nicht mit Vanilla abgleichen (alles zählt)")
    ap.add_argument("-v", action="store_true", help="nicht geprüfte Stellen einzeln auflisten")
    args = ap.parse_args()

    errors = self_test()
    if errors:
        print("Selbsttest gescheitert: " + " | ".join(errors))
        sys.exit(2)

    settings_file = args.settings or find_settings_typings(args.typings)
    decls, version = load_typings(args.typings, settings_file)
    if not decls.interfaces:
        print("Keine Typdateien in " + args.typings)
        sys.exit(2)
    resolver = Resolver(decls)
    RESOLVER = resolver
    tmap = build_type_map(decls)

    with open(args.dump, encoding="utf-8") as f:
        dump = json.load(f)
    sources = Sources(args.repo)
    vanilla = dump.get("vanilla_prototypes", {})

    print("Typdateien: API %s, %d Interfaces, %d Typen: %s" % (version, len(decls.interfaces), len(decls.aliases),
          ", ".join(decls.files)))
    if decls.errors:
        print("Parser: %d Deklarationen übersprungen (nicht geprüft): %s" % (len(decls.errors), "; ".join(decls.errors[:3])))
    tb = dump.get("startup_settings", {}).get("arrakis-testbench")
    print("Dump: base %s, Prüfstand %s, %d eigene Prototypen, Tiefe %d" % (
        dump.get("base"), "an" if tb else "aus", len(dump["prototypes"]), args.tiefe))
    if not settings_file:
        print("WARN keine Settings-Typdatei gefunden: Settings-Prototypen nicht geprüft")

    # Vanilla-Prototypen derselben Typen mitprüfen: gleiche Meldung dort = keine Eigenheit der Mod
    vanilla_hits = {}
    for ptype, protos in ({} if args.ohne_vanilla else vanilla).items():
        shape = prototype_shape(resolver, tmap, ptype)
        hits = defaultdict(set)
        if shape:
            for vp in protos:
                checker = Checker(resolver, args.tiefe)
                checker.check_object(vp["data"], shape, "", 0, ptype)
                for cat, path, _ in checker.hits:
                    hits[(cat, strip_index(path))].add(vp["name"])
        vanilla_hits[ptype] = hits

    totals = defaultdict(int)
    stats = defaultdict(int)
    known_total = 0
    like_vanilla = []
    unchecked_total = []
    not_mapped = []
    for proto in dump["prototypes"]:
        ptype, name, value = proto["type"], proto["name"], proto["data"]
        shape = prototype_shape(resolver, tmap, ptype)
        if shape is None:
            not_mapped.append(ptype + " " + name)
            continue
        checker = Checker(resolver, args.tiefe)
        checker.check_object(value, shape, "", 0, ptype)
        stats["prototypes"] += 1
        stats["tables"] += checker.tables
        stats["free"] += checker.free
        unchecked_total += [(ptype + " " + name, p, why) for p, why in checker.unchecked]
        if not checker.hits:
            continue
        rel, extend_line = sources.resolve(proto.get("source"))
        if rel:
            def_line = sources.find_name(rel, name, ptype, extend_line)
            where = "%s:%d" % (rel, def_line)
        else:
            def_line = 0
            where = "erzeugt (Recycling-Rezept von quality)" if name.endswith("-recycling") else "Quelle unbekannt"
        lines = []
        for cat, path, text in checker.hits:
            spath = strip_index(path)
            vnames = vanilla_hits.get(ptype, {}).get((cat, spath))
            if vnames:
                like_vanilla.append((ptype, name, cat, spath, text, len(vnames), len(vanilla.get(ptype, []))))
                continue
            reason = BEKANNT.get((ptype, spath)) or BEKANNT.get(("*", spath))
            notes = []
            leaf = re.sub(r"\[\d+\]$", "", path.rsplit(".", 1)[-1])
            top = re.split(r"[.\[]", path)[0]
            if rel and cat in ("a", "c", "d") and not leaf.startswith("["):
                kl = sources.find_key(rel, leaf, def_line)
                tl = sources.find_key(rel, top, def_line) if top != leaf else None
                if kl and (kl[2] or not tl):
                    notes.append(("gesetzt %s:%d" if kl[2] else "Schlüssel kommt vor in %s:%d") % kl[:2])
                elif tl and tl[2]:
                    notes.append("%s gesetzt %s:%d" % (top, tl[0], tl[1]))
                else:
                    notes.append("nicht im Mod-Quelltext (geerbt, z. B. deepcopy)")
            if cat in ("a", "c"):
                count = sum(1 for vp in vanilla.get(ptype, []) if path_exists(vp["data"], split_path(path)))
                if count:
                    notes.append("Schlüssel auch in %d von %d Vanilla-%s" % (count, len(vanilla[ptype]), ptype))
            if reason:
                notes.append("BEKANNT: " + reason)
                known_total += 1
            else:
                totals[cat] += 1
            lines.append("  (%s) %s: %s%s" % (cat, path, text, ("  [" + "; ".join(notes) + "]") if notes else ""))
        if lines:
            chain = [c.rsplit(".", 1)[-1] for c in shape.chain if c != "{…}"]
            chain = " < ".join(chain[:7]) + (" < …" if len(chain) > 7 else "")
            print("\n== %s %s  [%s]  %s" % (ptype, name, chain, where))
            print("\n".join(lines))

    print()
    if like_vanilla:
        groups = defaultdict(list)
        for ptype, name, cat, spath, text, n, m in like_vanilla:
            groups[(ptype, cat, spath, text, n, m)].append(name)
        print("wie Vanilla (dieselbe Meldung bei Vanilla-Prototypen desselben Typs; Lücke der Typdatei oder Altlast): %d" % len(groups))
        for (ptype, cat, spath, text, n, m), names in sorted(groups.items()):
            print("  (%s) %s %s: %s  [%s; Vanilla %d von %d]" % (cat, ptype, spath, text, ", ".join(sorted(set(names))), n, m))
    if not_mapped:
        print("nicht geprüft (kein Interface für den Typ): " + ", ".join(not_mapped))
    if unchecked_total:
        reasons = defaultdict(int)
        for _, p, why in unchecked_total:
            reasons[why] += 1
        print("nicht geprüft (Typ nicht auflösbar): %d Stellen; Gründe: %s" % (
            len(unchecked_total), ", ".join("%s (%d)" % (w, n) for w, n in sorted(reasons.items(), key=lambda x: -x[1]))))
        if args.v:
            for who, p, why in unchecked_total:
                print("  %s: %s (%s)" % (who, p, why))
    print("geprüft: %d Prototypen, %d Tabellen (davon %d mit freien Schlüsseln, z. B. Record)" % (
        stats["prototypes"], stats["tables"], stats["free"]))
    names = {"a": "unbekannt oben", "b": "Pflichtfeld fehlt", "c": "unbekannt verschachtelt", "d": "Form/Wert"}
    summary = ", ".join("%s %d" % (names[c], totals[c]) for c in "abcd")
    print("Treffer: %s; bekannt %d" % (summary, known_total))
    sys.exit(1 if sum(totals.values()) else 0)


if __name__ == "__main__":
    main()
