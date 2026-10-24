"""Datenstufen-Test für Arrakis mit echten Vanilla-Prototypen.

Lässt den kompletten Data-Lifecycle (Settings + Data) von core, base,
space-age, recycler, quality (2.1: abschaltbar), elevated-rails und Arrakis
per draftsman/lupa laufen und prüft danach Referenzen in data.raw (checks.lua).
Mit --dump schreibt es zusätzlich alle eigenen Prototypen als JSON
(proto_dump.lua) für proto_fields.py. Geladen wird jeder Vanilla-Mod im
Datenordner; --ohne MOD lässt einzelne weg (z. B. quality).

Ziel ist Factorio 2.1.23 (ab Mod 0.5.1). Der Lauf mit 2.0.77 prüft, dass der
2.0-Weg der Versionsweiche weiter geht (Zweig factorio-2.0). draftsman prüft
factorio_version und Abhängigkeiten aus info.json nicht.

Einrichtung (einmalig):
  python3 -m venv .venv && .venv/bin/pip install factorio-draftsman
  # draftsman bringt Vanilla 2.1.20 mit. Für 2.1.23 und 2.0.77:
  git clone --depth 1 --branch 2.1.23 https://github.com/wube/factorio-data fd2123
  git clone --depth 1 --branch 2.0.77 https://github.com/wube/factorio-data fd2077
  # danach in beiden den Ordner .git löschen, sonst hält draftsman ihn für eine Mod:
  rm -rf fd2123/.git fd2077/.git

Aufruf (aus dem Repo-Root):
  .venv/bin/python tools/check/datastage.py fd2123       # Vanilla 2.1.23 (Ziel)
  .venv/bin/python tools/check/datastage.py fd2123 --set arrakis-testbench=true
  .venv/bin/python tools/check/datastage.py fd2123 --ohne quality --set arrakis-testbench=true
  .venv/bin/python tools/check/datastage.py fd2077       # Vanilla 2.0.77 (Zweig factorio-2.0)
  .venv/bin/python tools/check/datastage.py fd2077 --set arrakis-testbench=true
  .venv/bin/python tools/check/datastage.py              # mitgelieferte Vanilla-Daten (2.1.20)
  .venv/bin/python tools/check/datastage.py fd2123 --dump /tmp/arrakis-2123.json
"""
import argparse, json, os, sys, tempfile

import draftsman
import draftsman.environment.update as update

HELPERS_STUB = """
helpers = helpers or {}
local function vparts(v) local t = {} for n in tostring(v):gmatch('%d+') do t[#t+1] = tonumber(n) end return t end
helpers.compare_versions = function(a, b)
  local x, y = vparts(a), vparts(b)
  for i = 1, 3 do
    local p, q = x[i] or 0, y[i] or 0
    if p < q then return -1 elseif p > q then return 1 end
  end
  return 0
end
"""

# Nur mit --dump: merkt sich bei jedem data:extend aus einer Datei dieser Mod die
# aufrufende Stelle (innerste Ebene in __arrakis__/…), Schlüssel "typ\0name".
SOURCE_HOOK = """
ARRAKIS_SOURCES = {}
local extend = data.extend
data.extend = function(self, otherdata)
  local list = otherdata
  if self ~= data and otherdata == nil then list = self end
  if type(list) == "table" then
    local where
    for level = 2, 40 do
      local info = debug.getinfo(level, "Sl")
      if not info then break end
      local src = info.source or ""
      if src:find("^__arrakis__/") then where = src:sub(13) .. ":" .. tostring(info.currentline) break end
    end
    if where then
      for _, p in pairs(list) do
        if type(p) == "table" and type(p.type) == "string" and type(p.name) == "string" then
          ARRAKIS_SOURCES[p.type .. "\\0" .. p.name] = where
        end
      end
    end
  end
  return extend(self, otherdata)
end
"""

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("game_path", nargs="?", default=None, help="Vanilla-Datenordner (Standard: draftsman-Daten)")
    parser.add_argument("--set", action="append", default=[], help="Startup-Einstellung name=wert (JSON-Wert)")
    parser.add_argument("--dump", metavar="DATEI", help="eigene Prototypen als JSON schreiben (für proto_fields.py)")
    parser.add_argument("--ohne", action="append", default=[], metavar="MOD",
                        help="Vanilla-Mod weglassen (mehrfach möglich), z. B. --ohne quality")
    args = parser.parse_args()

    overrides = {}
    for item in args.set:
        name, value = item.split("=", 1)
        overrides[name] = json.loads(value)

    original = update.run_settings_stage

    def run_settings_stage(lua, *a, **k):
        # helpers gibt es in Factorio seit 2.0.55 auch in Settings- und Data-Stage.
        lua.execute(HELPERS_STUB)
        if args.dump:
            lua.execute(SOURCE_HOOK)
        original(lua, *a, **k)
        for name, value in overrides.items():
            setting = lua.globals().settings["startup"][name]
            if setting is None:
                sys.exit("Unbekannte Einstellung: " + name)
            setting.value = value

    update.run_settings_stage = run_settings_stage

    repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    with tempfile.TemporaryDirectory() as mods, tempfile.TemporaryDirectory() as game:
        os.symlink(repo, os.path.join(mods, "arrakis"))
        game_path = args.game_path
        if args.ohne:
            # Eigener Datenordner aus Symlinks: alles aus dem Vanilla-Ordner außer den genannten Mods.
            source = os.path.abspath(game_path or os.path.join(os.path.dirname(os.path.abspath(draftsman.__file__)), "factorio-data"))
            missing = [name for name in args.ohne if not os.path.isdir(os.path.join(source, name))]
            if missing:
                sys.exit("Nicht im Vanilla-Ordner " + source + ": " + ", ".join(missing))
            for name in sorted(os.listdir(source)):
                if name not in args.ohne and not name.startswith("."):
                    os.symlink(os.path.join(source, name), os.path.join(game, name))
            game_path = game
            print("Ohne: " + ", ".join(args.ohne) + " (Vanilla aus " + source + ")")
        lua = update.run_data_lifecycle(game_path=game_path, mods_path=mods, show_logs=True)
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "checks.lua"), encoding="utf-8") as f:
        result = lua.execute(f.read())
    print(result)
    if args.dump:
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "proto_dump.lua"), encoding="utf-8") as f:
            dump = lua.execute(f.read())
        with open(args.dump, "w", encoding="utf-8") as f:
            f.write(dump)
        print("Dump: " + str(len(json.loads(dump)["prototypes"])) + " eigene Prototypen -> " + args.dump)
    if "FEHLER" in result:
        sys.exit(1)

if __name__ == "__main__":
    main()
