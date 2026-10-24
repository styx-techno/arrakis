"""RCON-Client (Source-RCON-Protokoll) für den Factorio-Server des Prüfstands.

Nur Python-Standardbibliothek (ab 3.8), Windows und Linux. Benutzt von pruefstand.py,
geht aber auch allein, z. B. um einen laufenden Prüfstand-Server von Hand zu fragen:
  python tools/pc/rcon.py --port 27115 --passwort GEHEIM arrakis-test status
Der führende / ist freiwillig und wird ergänzt: Git Bash unter Windows macht aus "/arrakis-test"
sonst einen Pfad (C:/Program Files/Git/arrakis-test).

Paket: int32 LE Größe (ohne dieses Feld), int32 id, int32 Typ, Text (UTF-8), zwei NUL-Bytes.
Typen: 3 Anmeldung, 2 Befehl, 0 Antwort, 2 Antwort auf die Anmeldung (id -1 = Passwort falsch).
Eine Antwort kann über mehrere Pakete verteilt sein. Ob Factorio auf leere Pakete antwortet
(der übliche Trick, das Ende zu erkennen), lässt sich hier nicht prüfen. Darum: nach dem
ersten Antwortpaket weiterlesen, bis die Leitung kurz still ist (QUIET).
"""
import argparse
import re
import select
import socket
import struct
import sys
import time

AUTH = 3
EXEC = 2
RESPONSE = 0
AUTH_RESPONSE = 2
QUIET = 0.3              # s ohne neue Daten: Antwort vollständig
MAX_PACKET = 4 * 1024 * 1024


class RconError(Exception):
  """Verbindung oder Antwort ging schief."""


class AuthError(RconError):
  """Der Server hat das Passwort abgelehnt."""


def _send(conn, kind, text):
  conn["next_id"] = conn["next_id"] % 0x7FFFFFFF + 1
  packet_id = conn["next_id"]
  body = text.encode("utf-8") + b"\x00\x00"
  data = struct.pack("<iii", len(body) + 8, packet_id, kind) + body
  try:
    conn["sock"].sendall(data)
  except OSError as err:
    raise RconError("Senden ging nicht: %s" % err)
  return packet_id


def _recv_exact(sock, count, deadline):
  data = b""
  while len(data) < count:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
      raise RconError("keine Antwort vom Server (Zeitlimit)")
    sock.settimeout(remaining)
    try:
      chunk = sock.recv(count - len(data))
    except socket.timeout:
      continue
    except OSError as err:
      raise RconError("Verbindung unterbrochen: %s" % err)
    if not chunk:
      raise RconError("Server hat die Verbindung geschlossen")
    data += chunk
  return data


# Ein Paket lesen: (id, Typ, Text als Bytes).
def _read_packet(sock, deadline):
  size = struct.unpack("<i", _recv_exact(sock, 4, deadline))[0]
  if size < 10 or size > MAX_PACKET:
    raise RconError("ungültige Paketgröße %d" % size)
  rest = _recv_exact(sock, size, deadline)
  packet_id, kind = struct.unpack("<ii", rest[:8])
  return packet_id, kind, rest[8:].rstrip(b"\x00")


def _readable(sock, wait):
  try:
    ready, _, _ = select.select([sock], [], [], wait)
  except (OSError, ValueError):
    return False
  return bool(ready)


def connect(host, port, password, timeout=10.0):
  """Verbinden und anmelden. Gibt die Verbindung (dict) zurück; AuthError bei falschem Passwort."""
  try:
    sock = socket.create_connection((host, port), timeout=timeout)
  except OSError as err:
    raise RconError("keine Verbindung zu %s:%d: %s" % (host, port, err))
  conn = {"sock": sock, "next_id": 0, "timeout": timeout}
  try:
    auth_id = _send(conn, AUTH, password)
    deadline = time.monotonic() + timeout
    while True:
      packet_id, kind, _ = _read_packet(sock, deadline)
      # Source-Server schicken vor der Anmeldeantwort oft ein leeres Antwortpaket: überspringen.
      if kind != AUTH_RESPONSE:
        continue
      if packet_id == -1:
        raise AuthError("RCON-Passwort abgelehnt")
      if packet_id == auth_id:
        return conn
  except BaseException:
    sock.close()
    raise


def command(conn, text, timeout=None):
  """Befehl senden, Antworttext (UTF-8) zurückgeben. RconError ohne Antwort im Zeitlimit."""
  sock = conn["sock"]
  command_id = _send(conn, EXEC, text)
  deadline = time.monotonic() + (timeout or conn["timeout"])
  parts = []
  while not parts:
    packet_id, kind, body = _read_packet(sock, deadline)
    # Pakete mit anderer id sind Reste früherer Befehle.
    if packet_id == command_id and kind == RESPONSE:
      parts.append(body)
  # Weitere Teile derselben Antwort, bis die Leitung kurz still ist.
  while _readable(sock, QUIET):
    try:
      packet_id, kind, body = _read_packet(sock, time.monotonic() + (timeout or conn["timeout"]))
    except RconError:
      break
    if packet_id == command_id and kind == RESPONSE:
      parts.append(body)
  return b"".join(parts).decode("utf-8", errors="replace")


def close(conn):
  if conn:
    try:
      conn["sock"].close()
    except OSError:
      pass


def main(argv=None):
  # Windows mit umgeleiteter Ausgabe (Pipe, Datei) schreibt in der ANSI-Codepage: „→“ u. Ä.
  # ersetzen statt mit UnicodeEncodeError abzubrechen.
  for stream in (sys.stdout, sys.stderr):
    try:
      stream.reconfigure(errors="replace")
    except (AttributeError, ValueError):
      pass
  ap = argparse.ArgumentParser(description="Einen RCON-Befehl an einen Factorio-Server schicken und die Antwort zeigen.")
  ap.add_argument("--host", default="127.0.0.1", help="Adresse (Standard 127.0.0.1)")
  ap.add_argument("--port", type=int, default=27115, help="RCON-Port (Standard 27115 wie pruefstand.py)")
  ap.add_argument("--passwort", required=True, help="RCON-Passwort (pruefstand.py: steht in <ordner>/server.json)")
  ap.add_argument("befehl", nargs="+", help="Befehl, z. B. arrakis-test status (/ davor wird ergänzt)")
  args = ap.parse_args(argv)
  text = " ".join(args.befehl)
  if re.match(r"^[A-Za-z]:[\\/]", text):
    print("RCON: %r sieht nach einem Pfad aus (Git Bash wandelt \"/…\" um). Befehl ohne / angeben, "
          "z. B. arrakis-test status" % text, file=sys.stderr)
    return 2
  if not text.startswith("/"):
    text = "/" + text
  try:
    conn = connect(args.host, args.port, args.passwort)
    try:
      print(command(conn, text).rstrip("\n"))
    finally:
      close(conn)
  except RconError as err:
    print("RCON: %s" % err, file=sys.stderr)
    return 2
  return 0


if __name__ == "__main__":
  sys.exit(main())
