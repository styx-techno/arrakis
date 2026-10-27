r"""Prüfstand ohne Spieler: Factorio-Server (headless) in eigenem Ordner starten, Tests von
/arrakis-test über RCON laufen lassen, Ergebnisse abholen.

Nur Python-Standardbibliothek (ab 3.8), Windows und Linux. Max' normale Factorio-Ordner bleiben
unberührt: Konfiguration, Mods, Spielstand und script-output liegen alle im Arbeitsordner.

Aufruf (aus dem Repo-Root; --factorio zeigt auf bin/x64/factorio(.exe) einer entpackten Kopie):
  python tools/pc/pruefstand.py --factorio "C:\Factorio-2.1.23\bin\x64\factorio.exe" T2b T13
  python tools/pc/pruefstand.py --factorio ... alle
  python tools/pc/pruefstand.py --factorio ... --ordner D:\pruefstand --zeitlimit 45 T11 T7:ja
  python tools/pc/pruefstand.py --factorio ... --tempo 1 alle      (echte Zeit wie vor 0.5.5)

Ablauf:
  1. Arbeitsordner (Standard: <System-Temp>/arrakis-pruefstand) einrichten: config/config.ini
     (read-data = Factorio-Kopie, write-data = Arbeitsordner), mods/ mit Kopie der Mod (ohne .git),
     mod-list.json, mod-settings.dat mit arrakis-testbench = true, server-settings.json
     (nicht öffentlich, auto_pause aus: sonst tickt ein Server ohne Spieler nicht).
  2. Frischen Spielstand anlegen (factorio --create).
  3. Server starten, nur an 127.0.0.1 (Spiel-Port 34297, RCON 27115, Zufallspasswort).
     Solange er läuft, stehen PID, Port und Passwort in <ordner>/server.json (von Hand fragen:
     python tools/pc/rcon.py --passwort … arrakis-test status). Bleibt nach einem harten
     Abbruch ein Server übrig, beendet ihn der nächste Lauf damit.
  4. Zeitraffer: /arrakis-test tempo N (--tempo, Standard 10) senden und die Antwort prüfen. Kennt die
     Mod den Befehl nicht (vor 0.5.5), geht es nur mit --tempo 1 weiter. Die Tests zählen Ticks, ihre
     Ergebnisse hängen nicht am Tempo; alle Zeitgrenzen hier (--zeitlimit, --abfrage, STALL …) sind echte
     Zeit und gelten unverändert, mit Zeitraffer enden die Tests nur früher.
  5. Je Test: /arrakis-test <id> senden, alle 5 s /arrakis-test status abfragen, bis das
     ERGEBNIS da ist (bei „alle“: bis der Stand wieder „bereit“ ist).
  6. /quit, Server beenden (auch bei Fehlern und Strg+C), script-output/arrakis-test.txt
     (und arrakis-t11-karten.txt) mit Zeitstempel nach <ordner>/ergebnisse/ kopieren.

Rückgabewert: 0 = kein FEHLER, 1 = mindestens ein FEHLER oder Zeitlimit, 2 = Einrichtung oder
Infrastruktur (Factorio startet nicht, RCON, Prüfstand-Einstellung nicht aktiv, Zeitraffer nicht
einstellbar, Test nicht gestartet, Ordner schon in Benutzung, Server tickt nicht mehr). Interaktive Tests (T9, T12, T17, T20, T22) lehnt der Server ohne Spieler ab; „alle“ lässt sie aus.
"""
import argparse
import errno
import json
import os
import re
import secrets
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time
import traceback
from pathlib import Path

sys.dont_write_bytecode = True   # kein __pycache__ in tools/pc
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mod_settings  # noqa: E402
import rcon  # noqa: E402

HOST = "127.0.0.1"
BUILTIN_MODS = ("base", "elevated-rails", "quality", "recycler", "space-age")
RESULT_FILES = ("arrakis-test.txt", "arrakis-t11-karten.txt")
MARKER = "arrakis-pruefstand.txt"
CREATE_TIMEOUT = 600       # s für --create
COMMAND_TIMEOUT = 30       # s für eine RCON-Antwort
QUIT_WAIT = 60             # s, bis der Server nach /quit weg sein muss
HEARTBEAT = 60             # s: Fortschritt auch ohne Änderung
STALL = 90                 # s: so lange darf der Tick während eines Tests stehen
TEMPO_MIN, TEMPO_MAX = 1, 50   # --tempo, wie /arrakis-test tempo in runner.lua
LOCK = "pruefstand.lock"
_lock = None               # offene Sperrdatei, solange der Lauf geht (unlock_folder in main)
COPY_IGNORE = (".git", "__pycache__", "*.pyc", "*.zip", ".vscode", ".DS_Store")

STATUS_RE = re.compile(r"^STATUS (?:(bereit)|(laeuft) (\S+) \+(\d+(?:\.\d+)?) s|(wartet) (\S+)) \| Tick (\d+)"
                       r"(?: \| alle, danach noch (\d+))?$")
# Zusammenfassung darf leer sein (Zeile endet dann auf "|", strip() nimmt das Leerzeichen).
RESULT_RE = re.compile(r"^ERGEBNIS (\S+) \| Tick (\d+) \| OK (\d+) FEHLER (\d+) FRAGE (\d+) \|(?: (.*))?$")
# Antwort auf /arrakis-test tempo N (ab 0.5.5): TEMPO <neu> | vorher <alt>.
TEMPO_RE = re.compile(r"^TEMPO (\d+(?:\.\d+)?) \| vorher (\d+(?:\.\d+)?(?:e[-+]?\d+)?)$")
# Antwort einer Mod ohne tempo (0.5.2 bis 0.5.4): „tempo“ gilt dort als Test-ID.
OLD_MOD_PREFIX = "Unbekannter Test: tempo"


class Abbruch(Exception):
  """Einrichtung oder Infrastruktur ging schief (Rückgabewert 2)."""


def say(text=""):
  print(text, flush=True)


def clock():
  return time.strftime("%H:%M:%S")


def tail(path, lines=30):
  try:
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
      content = handle.read().splitlines()
  except OSError:
    return "(%s nicht lesbar)" % path
  return "\n".join("    " + line for line in content[-lines:]) or "    (leer)"


def log_tail(*candidates):
  """Ende des ersten nicht leeren Logs. Unter Windows kann die Prozessausgabe leer bleiben
  (factorio.exe hängt sich an die Konsole des Aufrufers); factorio-current.log gibt es immer."""
  for path in candidates:
    try:
      if os.path.getsize(path) > 0:
        return "Ende von %s:\n%s" % (path, tail(path))
    except OSError:
      pass
  return "(kein Log: %s)" % ", ".join(str(path) for path in candidates)


# Status ------------------------------------------------------------------------------------

def parse_status(text):
  """Antwort auf /arrakis-test status zerlegen. None, wenn Zeile 1 nicht mit STATUS beginnt;
  ValueError, wenn sie nicht dem vereinbarten Format folgt."""
  lines = [line.strip() for line in text.splitlines() if line.strip()]
  if not lines or not lines[0].startswith("STATUS"):
    return None
  match = STATUS_RE.match(lines[0])
  if not match:
    raise ValueError("Statuszeile nicht im vereinbarten Format: %r" % lines[0])
  bereit, laeuft, run_id, sec, wartet, wait_id, tick, left = match.groups()
  status = {
    "zustand": bereit or laeuft or wartet,
    "id": run_id or wait_id,
    "sekunden": float(sec) if sec else None,
    "tick": int(tick),
    "danach": int(left) if left is not None else None,
    "zeile": lines[0],
    "ergebnisse": {},
  }
  for line in lines[1:]:
    result = RESULT_RE.match(line)
    if not result and line.startswith("ERGEBNIS"):
      # Nicht still übergehen: sonst fehlte ein FEHLER im Rückgabewert.
      raise ValueError("Ergebniszeile nicht im vereinbarten Format: %r" % line)
    if result:
      test_id, r_tick, ok, fehler, frage, summary = result.groups()
      status["ergebnisse"][test_id.upper()] = {
        "id": test_id, "tick": int(r_tick), "OK": int(ok), "FEHLER": int(fehler),
        "FRAGE": int(frage), "text": summary or "", "zeile": line}
  return status


def fresh_results(status, before, start_tick):
  """Ergebnisse, die seit start_tick neu oder anders sind (Schlüssel: ID in Großbuchstaben)."""
  return {key: entry for key, entry in status["ergebnisse"].items()
          if entry["tick"] >= start_tick and entry != before["ergebnisse"].get(key)}


def describe(status):
  if status["zustand"] == "laeuft":
    text = "läuft %s (+%.1f s, Tick %d)" % (status["id"], status["sekunden"], status["tick"])
  elif status["zustand"] == "wartet":
    text = "wartet auf %s (Tick %d)" % (status["id"], status["tick"])
  else:
    text = "bereit (Tick %d)" % status["tick"]
  if status["danach"] is not None:
    text += ", „alle“: danach noch %d" % status["danach"]
  return text


# RCON mit Wiederverbinden ------------------------------------------------------------------

def ask(link, text, retry=True, timeout=COMMAND_TIMEOUT):
  """Befehl über RCON. Bei Verbindungsfehler (nur mit retry) einmal neu verbinden."""
  for attempt in (1, 2):
    try:
      if link["conn"] is None:
        link["conn"] = rcon.connect(HOST, link["rcon_port"], link["password"], timeout=10)
      return rcon.command(link["conn"], text, timeout)
    except rcon.AuthError as err:
      raise Abbruch("RCON: %s" % err)
    except rcon.RconError as err:
      rcon.close(link["conn"])
      link["conn"] = None
      check_alive(link)
      if not retry or attempt == 2:
        raise Abbruch("RCON bei „%s“: %s" % (text, err))
      say("  RCON: %s, verbinde neu …" % err)
      time.sleep(2)


def get_status(link, text=None):
  if text is None:
    text = ask(link, "/arrakis-test status")
  try:
    status = parse_status(text)
  except ValueError as err:
    raise Abbruch(str(err))
  if status is None:
    first = (text.strip().splitlines() or ["(leere Antwort)"])[0]
    raise Abbruch("Antwort auf /arrakis-test status ohne STATUS: %r. Ist die Startup-Einstellung "
                  "arrakis-testbench aktiv und die Mod ab 0.5.2?" % first)
  link["last_status"] = status
  return status


def check_alive(link):
  proc = link["proc"]
  if proc.poll() is not None:
    raise Abbruch("Server unerwartet beendet (Code %s). %s" % (proc.returncode, log_tail(*link["logs"])))


# Arbeitsordner -----------------------------------------------------------------------------

def _inside(child, parent):
  try:
    child.relative_to(parent)
    return True
  except ValueError:
    return False


def _remove_tree(path):
  def force(func, target, *_):
    os.chmod(target, stat.S_IWRITE)
    func(target)
  if sys.version_info >= (3, 12):
    shutil.rmtree(path, onexc=force)
  else:
    shutil.rmtree(path, onerror=force)


def factorio_version(exe, data, config):
  """Version für den Kopf der mod-settings.dat: aus --version, sonst aus data/base/info.json."""
  try:
    out = subprocess.run([str(exe), "--version", "-c", str(config)], stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, timeout=120)
    match = re.search(r"Version: (\d+)\.(\d+)\.(\d+)", out.stdout.decode("utf-8", errors="replace"))
    if match:
      return tuple(int(n) for n in match.groups()) + (0,), "factorio --version"
  except (OSError, subprocess.SubprocessError):
    pass
  try:
    with open(data / "base" / "info.json", encoding="utf-8") as handle:
      parts = [int(n) for n in json.load(handle)["version"].split(".")]
    return tuple((parts + [0, 0, 0])[:3]) + (0,), "data/base/info.json"
  except (OSError, ValueError, KeyError):
    raise Abbruch("Factorio-Version nicht feststellbar (weder --version noch data/base/info.json)")


def lock_folder(folder):
  """Sperre für den ganzen Lauf, damit ein zweiter Lauf im selben Ordner nicht den Server des
  ersten beendet. main() gibt sie am Ende frei; endet der Prozess hart, tut es das System."""
  global _lock
  handle = open(folder / LOCK, "a+")
  try:
    if os.name == "nt":
      import msvcrt
      handle.seek(0)
      msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
    else:
      import fcntl
      fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
  except OSError as err:
    handle.close()
    if err.errno in (errno.EACCES, errno.EAGAIN, errno.EWOULDBLOCK, errno.EDEADLK):
      raise Abbruch("In %s läuft schon ein Prüfstand. Erst dessen Ende abwarten oder einen anderen "
                    "Ordner mit --ordner angeben." % folder)
    raise Abbruch("Sperrdatei %s lässt sich nicht sperren: %s" % (folder / LOCK, err))
  _lock = handle


def unlock_folder():
  global _lock
  if _lock is None:
    return
  try:
    if os.name == "nt":
      import msvcrt
      _lock.seek(0)
      msvcrt.locking(_lock.fileno(), msvcrt.LK_UNLCK, 1)
    else:
      import fcntl
      fcntl.flock(_lock.fileno(), fcntl.LOCK_UN)
  except OSError:
    pass
  _lock.close()
  _lock = None


def setup(args):
  exe = Path(args.factorio).expanduser().resolve()
  if not exe.is_file():
    raise Abbruch("Factorio nicht gefunden: %s" % exe)
  install = exe.parent.parent.parent
  data = install / "data"
  if not (data / "base" / "info.json").is_file():
    raise Abbruch("Kein Datenordner unter %s. --factorio muss auf bin/x64/factorio(.exe) einer "
                  "entpackten Factorio-Kopie zeigen (daneben data/)." % data)
  if not (data / "space-age" / "info.json").is_file():
    raise Abbruch("Space Age fehlt in %s" % data)

  mod_src = Path(args.mod).expanduser().resolve() if args.mod else Path(__file__).resolve().parents[2]
  try:
    with open(mod_src / "info.json", encoding="utf-8") as handle:
      mod_info = json.load(handle)
  except (OSError, ValueError) as err:
    raise Abbruch("Mod-Ordner %s ohne lesbare info.json: %s" % (mod_src, err))
  if mod_info.get("name") != "arrakis":
    raise Abbruch("%s ist nicht die Mod arrakis (name = %r)" % (mod_src, mod_info.get("name")))

  # abspath vor resolve: Python 3.8/3.9 unter Windows lässt nicht vorhandene relative Pfade relativ.
  folder = Path(os.path.abspath(os.path.expanduser(args.ordner))).resolve() if args.ordner else Path(tempfile.gettempdir()) / "arrakis-pruefstand"
  if _inside(folder, install) or _inside(install, folder) or _inside(folder, mod_src) or _inside(mod_src, folder):
    raise Abbruch("Arbeitsordner %s darf weder in der Factorio-Kopie noch in der Mod liegen (oder umgekehrt)" % folder)
  if folder.exists() and not folder.is_dir():
    raise Abbruch("%s ist kein Ordner" % folder)
  if folder.exists() and any(folder.iterdir()) and not (folder / MARKER).is_file():
    raise Abbruch("%s ist nicht leer und kein Prüfstand-Ordner (%s fehlt). Bitte einen neuen oder leeren "
                  "Ordner mit --ordner angeben." % (folder, MARKER))
  paths = {
    "exe": exe, "data": data, "mod_src": mod_src, "mod_version": mod_info.get("version", "?"),
    "folder": folder, "config": folder / "config" / "config.ini", "mods": folder / "mods",
    "save": folder / "saves" / "pruefstand.zip", "settings": folder / "server-settings.json",
    "server_json": folder / "server.json", "server_log": folder / "server.log",
    "create_log": folder / "create.log", "game_log": folder / "factorio-current.log",
    "output": folder / "script-output", "results": folder / "ergebnisse",
  }
  for sub in ("config", "mods", "saves", "script-output", "ergebnisse"):
    (folder / sub).mkdir(parents=True, exist_ok=True)
  (folder / MARKER).write_text("Arbeitsordner von tools/pc/pruefstand.py (Arrakis-Prüfstand). "
                               "Wird bei jedem Lauf neu eingerichtet.\n", encoding="utf-8")

  # Vor dem Umbau der Mods: Ordner sperren, alten Server beenden, Ports prüfen.
  lock_folder(folder)
  stop_old_server(paths)
  if tcp_in_use(args.rcon_port):
    raise Abbruch("RCON-Port %d ist belegt. Läuft noch ein anderer Server? Anderen Port mit --rcon-port." % args.rcon_port)
  if udp_in_use(args.port):
    raise Abbruch("Spiel-Port %d (UDP) ist belegt. Läuft noch ein Factorio-Server? Anderen Port mit --port." % args.port)

  # Standardform der config.ini; Schrägstriche gehen auch unter Windows.
  paths["config"].write_text("; Arrakis-Pruefstand (tools/pc/pruefstand.py)\n[path]\n"
                             "read-data=__PATH__executable__/../../data\n"
                             "write-data=%s\n" % folder.as_posix(), encoding="utf-8")
  version, source = factorio_version(exe, data, paths["config"])
  say("Factorio %s (%s): %s" % (".".join(str(n) for n in version[:3]), source, exe))
  say("Arbeitsordner: %s" % folder)

  # Mod frisch kopieren.
  target = paths["mods"] / "arrakis"
  if target.exists():
    _remove_tree(target)
  shutil.copytree(mod_src, target, ignore=shutil.ignore_patterns(*COPY_IGNORE))
  say("Mod: arrakis %s aus %s" % (paths["mod_version"], mod_src))
  enabled = [name for name in BUILTIN_MODS if (data / name / "info.json").is_file()]
  missing = [name for name in BUILTIN_MODS if name not in enabled]
  if missing:
    say("  Hinweis: nicht in dieser Factorio-Kopie: %s" % ", ".join(missing))
  mod_list = {"mods": [{"name": name, "enabled": True} for name in enabled + ["arrakis"]]}
  (paths["mods"] / "mod-list.json").write_text(json.dumps(mod_list, indent=2) + "\n", encoding="utf-8")

  dat = paths["mods"] / "mod-settings.dat"
  try:
    mod_settings.set_setting(str(dat), "startup", "arrakis-testbench", True, version)
  except ValueError as err:
    # Der Ordner gehört dem Prüfstand: unlesbare Datei beiseitelegen und neu anlegen.
    say("  mod-settings.dat: %s" % err)
    os.replace(dat, str(dat) + ".unlesbar")
    say("  → beiseitegelegt als mod-settings.dat.unlesbar, lege neu an")
    mod_settings.set_setting(str(dat), "startup", "arrakis-testbench", True, version)
  if mod_settings.get_setting(str(dat), "startup", "arrakis-testbench") is not True:
    raise Abbruch("arrakis-testbench steht nach dem Schreiben nicht auf true (%s)" % dat)

  # Alte Ergebnisdateien beiseite: die Mod hängt nur an.
  stamp = time.strftime("%Y%m%d-%H%M%S")
  for name in RESULT_FILES:
    old = paths["output"] / name
    if old.is_file():
      os.replace(old, paths["results"] / ("%s-vorher-%s.txt" % (old.stem, stamp)))

  settings = {
    "name": "Arrakis-Pruefstand",
    "description": "tools/pc/pruefstand.py, nur 127.0.0.1",
    "tags": [],
    "max_players": 0,
    "visibility": {"public": False, "lan": False},
    "username": "", "password": "", "token": "", "game_password": "",
    "require_user_verification": False,
    "max_upload_in_kilobytes_per_second": 0,
    "max_upload_slots": 5,
    "minimum_latency_in_ticks": 0,
    "max_heartbeats_per_second": 60,
    "ignore_player_limit_for_returning_players": False,
    "allow_commands": "admins-only",
    "autosave_interval": 10,
    "autosave_slots": 1,
    "afk_autokick_interval": 0,
    "auto_pause": False,                       # wichtig: ohne Spieler weiterticken
    "auto_pause_when_players_connect": False,
    "only_admins_can_pause_the_game": True,
    "autosave_only_on_server": True,
    "non_blocking_saving": False,
    "minimum_segment_size": 25,
    "minimum_segment_size_peer_count": 20,
    "maximum_segment_size": 100,
    "maximum_segment_size_peer_count": 10,
  }
  paths["settings"].write_text(json.dumps(settings, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
  return paths


def create_save(paths):
  save = paths["save"]
  if save.exists():
    save.unlink()
  cmd = [str(paths["exe"]), "--create", str(save), "-c", str(paths["config"]),
         "--mod-directory", str(paths["mods"])]
  say("Spielstand anlegen (--create) …")
  try:
    with open(paths["create_log"], "wb") as log:
      result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                              timeout=CREATE_TIMEOUT)
    code = result.returncode
  except subprocess.TimeoutExpired:
    code = "Zeitlimit %d s" % CREATE_TIMEOUT
  except OSError as err:
    raise Abbruch("Factorio lässt sich nicht starten: %s" % err)
  if code != 0 or not save.is_file():
    raise Abbruch("Spielstand anlegen ging nicht (Code %s). %s"
                  % (code, log_tail(paths["create_log"], paths["game_log"])))


# Server ------------------------------------------------------------------------------------

def tcp_in_use(port):
  try:
    with socket.create_connection((HOST, port), timeout=1):
      return True
  except OSError:
    return False


def udp_in_use(port):
  sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
  try:
    sock.bind((HOST, port))
    return False
  except OSError:
    return True
  finally:
    sock.close()


def stop_old_server(paths):
  """Läuft noch ein Server eines abgebrochenen Laufs (server.json), mit dessen Passwort beenden."""
  try:
    info = json.loads(paths["server_json"].read_text(encoding="utf-8"))
    port, password = int(info["rcon_port"]), info["password"]
  except (OSError, ValueError, KeyError, TypeError):
    return
  if tcp_in_use(port):
    try:
      conn = rcon.connect(HOST, port, password, timeout=5)
      say("Alter Prüfstand-Server läuft noch (PID %s): /quit" % info.get("pid"))
      try:
        rcon.command(conn, "/quit", timeout=5)
      except rcon.RconError:
        pass
      rcon.close(conn)
      deadline = time.monotonic() + QUIT_WAIT
      while tcp_in_use(port) and time.monotonic() < deadline:
        time.sleep(1)
    except rcon.RconError:
      pass
    if tcp_in_use(port):
      # server.json behalten: PID und Passwort braucht man noch, um ihn zu beenden.
      raise Abbruch("Ein alter Prüfstand-Server (PID %s, RCON-Port %d) läuft noch und reagiert nicht auf "
                    "/quit. Bitte von Hand beenden (Task-Manager) und neu starten." % (info.get("pid"), port))
  try:
    paths["server_json"].unlink()
  except OSError:
    pass


def start_server(paths, args, password):
  cmd = [str(paths["exe"]), "--start-server", str(paths["save"]), "-c", str(paths["config"]),
         "--mod-directory", str(paths["mods"]), "--server-settings", str(paths["settings"]),
         "--bind", "%s:%d" % (HOST, args.port), "--rcon-bind", "%s:%d" % (HOST, args.rcon_port),
         "--rcon-password", password]
  say("Server starten: Spiel %s:%d, RCON %s:%d, Log %s" % (HOST, args.port, HOST, args.rcon_port, paths["server_log"]))
  log = open(paths["server_log"], "wb")
  try:
    # stdin offen lassen (Pipe): Factorio liest Konsolenbefehle; Notweg für /quit (nur Linux:
    # factorio.exe liest unter Windows die Konsole des Aufrufers, nicht die Pipe).
    proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.PIPE)
  except OSError as err:
    log.close()
    raise Abbruch("Factorio lässt sich nicht starten: %s" % err)
  try:
    # Für den nächsten Lauf, falls dieser hart abgebrochen wird (stop_old_server).
    info = {"pid": proc.pid, "port": args.port, "rcon_port": args.rcon_port, "password": password}
    paths["server_json"].write_text(json.dumps(info) + "\n", encoding="utf-8")
  except BaseException:
    proc.kill()
    proc.wait()
    log.close()
    raise
  return proc, log


def wait_for_rcon(link, limit):
  started = time.monotonic()
  deadline = started + limit
  last_error, next_note = None, started + 15
  while time.monotonic() < deadline:
    check_alive(link)
    try:
      timeout = max(1.0, min(10.0, deadline - time.monotonic()))
      link["conn"] = rcon.connect(HOST, link["rcon_port"], link["password"], timeout=timeout)
      say("RCON verbunden nach %.0f s" % (time.monotonic() - started))
      return
    except rcon.AuthError as err:
      raise Abbruch("RCON: %s (Passwort aus --rcon-password nicht angenommen)" % err)
    except rcon.RconError as err:
      last_error = err
    if time.monotonic() >= next_note:
      say("  warte auf RCON … %.0f s" % (time.monotonic() - started))
      next_note += 15
    time.sleep(1)
  raise Abbruch("RCON nach %.0f s nicht erreichbar (%s). %s" % (limit, last_error, log_tail(*link["logs"])))


def stop_server(link, log):
  proc = link["proc"]
  try:
    if proc.poll() is None:
      say("Server beenden (/quit) …")
      # Factorio antwortet auf /quit vielleicht nicht mehr: Fehler hier sind normal.
      try:
        if link["conn"] is None:
          link["conn"] = rcon.connect(HOST, link["rcon_port"], link["password"], timeout=5)
        rcon.command(link["conn"], "/quit", timeout=5)
      except rcon.RconError:
        pass
      # Notweg über die Konsole (stdin), falls RCON nicht ging (wirkt nur unter Linux).
      try:
        proc.wait(2)
      except subprocess.TimeoutExpired:
        try:
          proc.stdin.write(b"/quit\n")
          proc.stdin.flush()
        except OSError:
          pass
      try:
        proc.wait(QUIT_WAIT)
      except subprocess.TimeoutExpired:
        say("  Server reagiert nicht auf /quit: beende ihn hart")
        proc.terminate()
        try:
          proc.wait(15)
        except subprocess.TimeoutExpired:
          proc.kill()
          proc.wait()
  except KeyboardInterrupt:
    proc.kill()
    proc.wait()
  finally:
    rcon.close(link["conn"])
    link["conn"] = None
    for handle in (proc.stdin, log):
      try:
        handle.close()
      except (OSError, AttributeError):
        pass
  say("Server beendet (Code %s)" % proc.returncode)


# Tests -------------------------------------------------------------------------------------

def run_test(link, test, limit_min, poll):
  """Einen Test (oder „alle“) starten und bis zum Ende verfolgen. „T7:ja“ sendet /arrakis-test T7 ja."""
  test_id, _, argument = test.partition(":")
  command = " ".join(["/arrakis-test", test_id] + ([argument] if argument else []))
  is_all = test_id.lower() == "alle"
  key = test_id.upper()
  before = get_status(link)
  if before["zustand"] != "bereit":
    say("  Hinweis: Stand vor dem Start: %s" % describe(before))
  start_tick = before["tick"]
  say("")
  say("[%s] %s" % (clock(), command))
  reply = ask(link, command, retry=False)
  for line in reply.strip().splitlines():
    say("  > " + line)
  outcome = {"test": test, "zustand": "fertig", "antwort": reply.strip()}
  status = get_status(link)
  fresh = fresh_results(status, before, start_tick)
  started = status["zustand"] != "bereit" or (fresh if is_all else key in fresh)
  if not started:
    outcome["zustand"] = "nicht gestartet"
    say("  nicht gestartet")
    return outcome
  t0 = time.monotonic()
  last_state, last_note, shown = None, t0, set()
  left_ready = False
  last_tick, tick_since = status["tick"], t0
  while True:
    if status["tick"] != last_tick:
      last_tick, tick_since = status["tick"], time.monotonic()
    elif status["zustand"] != "bereit" and time.monotonic() - tick_since > STALL:
      raise Abbruch("Der Server tickt seit %.0f s nicht mehr (Tick %d). Pausiert? %s"
                    % (time.monotonic() - tick_since, last_tick, log_tail(*link["logs"])))
    state = (status["zustand"], status["id"], status["danach"])
    if state != last_state or time.monotonic() - last_note >= HEARTBEAT:
      say("  [%s] %s" % (clock(), describe(status)))
      last_state, last_note = state, time.monotonic()
    fresh = fresh_results(status, before, start_tick)
    for entry_key, entry in fresh.items():
      if (entry_key, entry["tick"]) not in shown:
        shown.add((entry_key, entry["tick"]))
        say("  " + entry["zeile"])
    if status["zustand"] != "bereit":
      left_ready = True
    elif is_all or key in fresh:
      return outcome
    elif left_ready:
      outcome["zustand"] = "ohne Ergebnis"
      say("  Stand wieder „bereit“, aber kein ERGEBNIS für %s" % test)
      return outcome
    if time.monotonic() - t0 > limit_min * 60:
      say("  Zeitlimit %.1f min überschritten: /arrakis-test stop" % limit_min)
      try:
        for line in ask(link, "/arrakis-test stop", retry=False).strip().splitlines():
          say("  > " + line)
      except Abbruch as err:
        say("  %s" % err)
      outcome["zustand"] = "zeitlimit"
      return outcome
    check_alive(link)
    time.sleep(poll)
    status = get_status(link)


def collect_files(paths):
  stamp = time.strftime("%Y%m%d-%H%M%S")
  copied = []
  for name in RESULT_FILES:
    src = paths["output"] / name
    if src.is_file():
      dst = paths["results"] / ("%s-%s.txt" % (src.stem, stamp))
      shutil.copy2(src, dst)
      copied.append(dst)
  return copied


def tempo_text(tempo):
  """Faktor wie im Befehl: 10, 2.5 (%g; zwischen 1 und 50 nie mit Exponent)."""
  return "%g" % tempo


def set_tempo(link, tempo):
  """Zeitraffer vor dem ersten Test: /arrakis-test tempo N senden und die Antwort prüfen. Eine Mod vor
  0.5.5 kennt den Befehl nicht (antwortet „Unbekannter Test: tempo …“, ohne etwas zu ändern); mit ihr
  geht es nur mit --tempo 1 weiter, sonst Abbruch."""
  text = tempo_text(tempo)
  reply = ask(link, "/arrakis-test tempo " + text)
  lines = [line.strip() for line in reply.splitlines() if line.strip()]
  first = lines[0] if lines else "(leere Antwort)"
  match = TEMPO_RE.match(first)
  if match:
    new = float(match.group(1))
    # game.speed ist ein float: 2.3 kommt etwa als 2.3 zurück, nie weiter weg als ein Promille.
    if abs(new - tempo) > tempo / 1000:
      raise Abbruch("Zeitraffer: game.speed steht nach /arrakis-test tempo %s auf %s (Antwort %r)" % (text, match.group(1), first))
    say("%s: game.speed %s (vorher %s)" % ("Zeitraffer aus" if tempo == 1 else "Zeitraffer", match.group(1), match.group(2)))
    return
  if first.startswith(OLD_MOD_PREFIX):
    if tempo == 1:
      say("Zeitraffer: Die Mod kennt /arrakis-test tempo nicht (vor 0.5.5); die Tests laufen wie bisher in echter Zeit.")
      return
    raise Abbruch("Die Mod kennt /arrakis-test tempo nicht (vor 0.5.5, Antwort %r). Mit --tempo 1 laufen die Tests "
                  "ohne Zeitraffer wie bisher." % first)
  raise Abbruch("Antwort auf /arrakis-test tempo %s nicht im vereinbarten Format: %r" % (text, first))


def first_status(link):
  """Erste Statusabfrage; eine leere Antwort (Server noch nicht ganz bereit) kurz wiederholen."""
  for _ in range(5):
    text = ask(link, "/arrakis-test status")
    if text.strip():
      break
    time.sleep(2)
  return get_status(link, text)


def run(args):
  paths = setup(args)
  create_save(paths)

  password = secrets.token_hex(16)
  proc, log = start_server(paths, args, password)
  link = {"proc": proc, "conn": None, "rcon_port": args.rcon_port, "password": password,
          "logs": (paths["server_log"], paths["game_log"]), "last_status": None}
  outcomes, problem, current = [], None, None
  try:
    wait_for_rcon(link, args.startzeit)
    first = first_status(link)
    say("Prüfstand antwortet: %s" % first["zeile"])
    set_tempo(link, args.tempo)
    for test in args.tests:
      limit = args.zeitlimit or (90 if test.lower() == "alle" else 30)
      current = test
      outcome = run_test(link, test, limit, args.abfrage)
      outcomes.append(outcome)
      current = None
      if outcome["zustand"] == "zeitlimit":
        say("Breche nach dem Zeitlimit ab; übrige Tests laufen nicht.")
        break
    get_status(link)
  except Abbruch as err:
    problem = str(err)
  except KeyboardInterrupt:
    problem = "Abgebrochen (Strg+C oder beendet)"
  finally:
    stop_server(link, log)
    try:
      paths["server_json"].unlink()
    except OSError:
      pass

  say("")
  if problem:
    say("ABBRUCH: %s" % problem)
  files = collect_files(paths)
  for path in files:
    say("Ergebnisdatei: %s" % path)
  if not files:
    say("Keine Ergebnisdatei in %s" % paths["output"])
  results = (link["last_status"] or {}).get("ergebnisse", {})
  say("Ergebnisse:")
  for entry in results.values():
    say("  " + entry["zeile"])
  if not results:
    say("  (keine)")
  for outcome in outcomes:
    if outcome["zustand"] == "nicht gestartet":
      say("%s: nicht gestartet (%s)" % (outcome["test"], outcome["antwort"] or "keine Antwort"))
    elif outcome["zustand"] != "fertig":
      say("%s: %s" % (outcome["test"], outcome["zustand"]))
  if current:
    say("Abgebrochen während: %s" % current)
  skipped = args.tests[len(outcomes) + (1 if current else 0):]
  if skipped:
    say("Nicht gelaufen: %s" % " ".join(skipped))

  if problem or any(o["zustand"] in ("nicht gestartet", "ohne Ergebnis") for o in outcomes):
    code = 2
  elif any(o["zustand"] == "zeitlimit" for o in outcomes) or any(e["FEHLER"] > 0 for e in results.values()):
    code = 1
  else:
    code = 0
  say("Rückgabewert %d (%s)" % (code, {0: "kein FEHLER", 1: "FEHLER oder Zeitlimit", 2: "Einrichtung/Infrastruktur"}[code]))
  return code


def parse_args(argv):
  ap = argparse.ArgumentParser(
    description="Arrakis-Prüfstand auf einem eigenen Factorio-Server ohne Spieler laufen lassen (RCON).",
    epilog="Rückgabewert: 0 kein FEHLER, 1 FEHLER oder Zeitlimit, 2 Einrichtung/Infrastruktur. "
           "Interaktive Tests (T9, T12, T17, T20, T22) gehen nur von Hand im Spiel.", add_help=False)
  ap.add_argument("-h", "--help", action="help", help="diese Hilfe zeigen")
  ap.add_argument("--factorio", required=True, metavar="PFAD", help="Pfad zu bin/x64/factorio(.exe) einer entpackten Factorio-Kopie")
  ap.add_argument("--ordner", metavar="ORDNER", help="Arbeitsordner (Standard: <System-Temp>/arrakis-pruefstand)")
  ap.add_argument("--mod", metavar="ORDNER", help="Mod-Ordner (Standard: dieses Repo)")
  ap.add_argument("--rcon-port", type=int, default=27115, metavar="N", help="RCON-Port auf 127.0.0.1 (Standard 27115)")
  ap.add_argument("--port", type=int, default=34297, metavar="N", help="Spiel-Port auf 127.0.0.1 (Standard 34297)")
  ap.add_argument("--zeitlimit", type=float, metavar="MIN", help="Minuten je Test in echter Zeit (Standard 30, bei „alle“ 90)")
  ap.add_argument("--startzeit", type=float, default=180, metavar="SEK", help="Sekunden, die der Server bis RCON brauchen darf (Standard 180)")
  ap.add_argument("--abfrage", type=float, default=5, metavar="SEK", help="Sekunden zwischen zwei Statusabfragen (Standard 5)")
  ap.add_argument("--tempo", type=float, default=10, metavar="N",
                  help="Zeitraffer: game.speed während der Tests, %d bis %d (Standard 10; 1 = echte Zeit wie vor 0.5.5). "
                       "Die Ergebnisse hängen nicht davon ab." % (TEMPO_MIN, TEMPO_MAX))
  ap.add_argument("tests", nargs="+", metavar="TEST",
                  help="Test-IDs wie T2b T13, oder alle; mit Argument nach Doppelpunkt, z. B. T7:ja")
  args = ap.parse_args(argv)
  for test in args.tests:
    if not re.match(r"^[A-Za-z0-9_-]+(:[A-Za-z0-9_.=-]+)?$", test):
      ap.error("ungültige Test-ID: %r" % test)
  if args.zeitlimit is not None and args.zeitlimit <= 0:
    ap.error("--zeitlimit muss größer als 0 sein")
  if args.startzeit <= 0 or args.abfrage <= 0:
    ap.error("--startzeit und --abfrage müssen größer als 0 sein")
  # So geschrieben, dass auch nan und inf durchfallen.
  if not TEMPO_MIN <= args.tempo <= TEMPO_MAX:
    ap.error("--tempo muss zwischen %d und %d liegen (1 = echte Zeit)" % (TEMPO_MIN, TEMPO_MAX))
  return args


def main(argv=None):
  # Windows-Konsole: Zeichen ohne Entsprechung ersetzen statt abzustürzen; Fortschritt sofort zeigen.
  for stream in (sys.stdout, sys.stderr):
    try:
      stream.reconfigure(errors="replace", line_buffering=True)
    except (AttributeError, ValueError):
      pass
  args = parse_args(argv)
  # Beenden von außen (kill, timeout) wie Strg+C behandeln: Server stoppen, Ergebnis zeigen.
  if hasattr(signal, "SIGTERM"):
    def on_term(signum, frame):
      raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, on_term)
  try:
    return run(args)
  except Abbruch as err:
    say("ABBRUCH: %s" % err)
    say("Rückgabewert 2 (Einrichtung/Infrastruktur)")
    return 2
  except KeyboardInterrupt:
    say("Abgebrochen (Strg+C oder beendet).")
    say("Rückgabewert 2 (Einrichtung/Infrastruktur)")
    return 2
  except Exception:
    # Unerwartet (z. B. OSError beim Kopieren der Mod): nicht als FEHLER (1) melden.
    traceback.print_exc()
    say("ABBRUCH: unerwarteter Fehler (siehe oben)")
    say("Rückgabewert 2 (Einrichtung/Infrastruktur)")
    return 2
  finally:
    unlock_folder()


if __name__ == "__main__":
  sys.exit(main())
