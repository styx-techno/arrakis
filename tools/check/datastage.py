"""Datenstufen-Test für Arrakis mit echten Vanilla-Prototypen.

Lässt den kompletten Data-Lifecycle (Settings + Data) von core, base,
space-age, quality, elevated-rails und Arrakis per draftsman/lupa laufen und
prüft danach Referenzen in data.raw (checks.lua).

Einrichtung (einmalig):
  python3 -m venv .venv && .venv/bin/pip install factorio-draftsman
  # draftsman bringt Vanilla 2.1.x mit. Für 2.0.77:
  git clone --depth 1 --branch 2.0.77 https://github.com/wube/factorio-data fd2077

Aufruf (aus dem Repo-Root):
  .venv/bin/python tools/check/datastage.py              # mitgelieferte Vanilla-Daten (2.1.x)
  .venv/bin/python tools/check/datastage.py fd2077       # Vanilla 2.0.77
  .venv/bin/python tools/check/datastage.py fd2077 --set arrakis-testbench=true
"""
import argparse, json, os, sys, tempfile

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

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("game_path", nargs="?", default=None, help="Vanilla-Datenordner (Standard: draftsman-Daten)")
    parser.add_argument("--set", action="append", default=[], help="Startup-Einstellung name=wert (JSON-Wert)")
    args = parser.parse_args()

    overrides = {}
    for item in args.set:
        name, value = item.split("=", 1)
        overrides[name] = json.loads(value)

    original = update.run_settings_stage

    def run_settings_stage(lua, *a, **k):
        # helpers gibt es in Factorio seit 2.0.55 auch in Settings- und Data-Stage.
        lua.execute(HELPERS_STUB)
        original(lua, *a, **k)
        for name, value in overrides.items():
            setting = lua.globals().settings["startup"][name]
            if setting is None:
                sys.exit("Unbekannte Einstellung: " + name)
            setting.value = value

    update.run_settings_stage = run_settings_stage

    repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    with tempfile.TemporaryDirectory() as mods:
        os.symlink(repo, os.path.join(mods, "arrakis"))
        lua = update.run_data_lifecycle(game_path=args.game_path, mods_path=mods, show_logs=True)
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "checks.lua"), encoding="utf-8") as f:
        result = lua.execute(f.read())
    print(result)
    if "FEHLER" in result:
        sys.exit(1)

if __name__ == "__main__":
    main()
