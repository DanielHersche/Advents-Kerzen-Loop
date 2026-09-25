#!/usr/bin/python2.7
# Kerzen Loop Player - Zeitsteuerung
# Schaltet den Bildschirm zur eingestellten Zeit aus und wieder ein.
import os, sys, json, time, socket
from datetime import datetime
import pytz

def log(msg):
    sys.stderr.write("[zeitplan] %s\n" % (msg,))
    sys.stderr.flush()

def load_config():
    try:
        with open("config.json") as f:
            return json.load(f)
    except Exception as err:
        log("config.json nicht lesbar: %s" % (err,))
        return {}

def parse_hm(value, default):
    try:
        h, m = str(value).strip().replace(".", ":").split(":")
        h, m = int(h), int(m)
        if 0 <= h <= 23 and 0 <= m <= 59:
            return h * 60 + m
    except Exception:
        pass
    return default

def syncer(cmd):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(os.getenv("SYNCER_SOCKET", "/tmp/syncer"))
        s.send(cmd + "\n")
        s.close()
    except Exception as err:
        log("Befehl '%s' fehlgeschlagen: %s" % (cmd, err))

udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
def node_send(state):
    try:
        udp.sendto("%s/power:%s" % (os.getenv("NODE", "root"), state),
                   ("127.0.0.1", 4444))
    except Exception as err:
        log("Senden an Node fehlgeschlagen: %s" % (err,))

def should_be_on(config, now):
    if not config.get("schedule_enabled", True):
        return True
    off_at = parse_hm(config.get("off_time", "22:30"), 22 * 60 + 30)
    on_at = parse_hm(config.get("on_time", "07:30"), 7 * 60 + 30)
    minute = now.hour * 60 + now.minute
    if off_at == on_at:
        return True
    if off_at > on_at:
        # z.B. aus 22:30, an 07:30 (ueber Mitternacht)
        return not (minute >= off_at or minute < on_at)
    return not (off_at <= minute < on_at)

def local_now(config):
    tzname = config.get("__metadata", {}).get("timezone") or "Europe/Zurich"
    try:
        tz = pytz.timezone(tzname)
    except Exception:
        tz = pytz.timezone("Europe/Zurich")
    return pytz.utc.localize(datetime.utcnow()).astimezone(tz)

# Bis die Uhrzeit synchronisiert ist, bleibt der Bildschirm an
syncer("tv on")
node_send("on")
while time.time() < 1000000000:
    log("warte auf korrekte Systemzeit")
    time.sleep(5)

current = None
last_tv = 0
while True:
    config = load_config()
    now = local_now(config)
    on = should_be_on(config, now)
    state = "on" if on else "off"
    node_send(state)
    # TV-Befehl bei Wechsel senden und alle 10 Minuten wiederholen
    if state != current or time.time() - last_tv > 600:
        log("%s -> Bildschirm %s" % (now.strftime("%Y-%m-%d %H:%M"), state))
        syncer("tv " + state)
        current = state
        last_tv = time.time()
    time.sleep(20)
