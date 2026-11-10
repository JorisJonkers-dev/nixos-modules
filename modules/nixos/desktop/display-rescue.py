"""Bring back a monitor that GNOME thinks is on but the kernel has turned off.

After a suspend or a screen blank, the kernel can stop offering a monitor's
mode, for example when a DisplayPort-to-HDMI adapter comes back reporting a
lower clock limit. Mutter keeps asking for the old mode, every commit fails,
and the screen stays black. This loop notices that state and applies the
fastest mode the kernel accepts, as a temporary config, so monitors.xml keeps
the user's choice and the next hotplug restores it.
"""

from __future__ import annotations

import glob
import os
import subprocess
import sys
import time

from gi.repository import Gio, GLib

POLL = float(os.environ.get("DISPLAY_RESCUE_POLL", "5"))
SETTLE = float(os.environ.get("DISPLAY_RESCUE_SETTLE", "3"))
DARK_POLLS = int(os.environ.get("DISPLAY_RESCUE_DARK_POLLS", "2"))
COOLDOWN = float(os.environ.get("DISPLAY_RESCUE_COOLDOWN", "60"))
MAX_TRIES = 8

NAME = "org.gnome.Mutter.DisplayConfig"
PATH = "/org/gnome/Mutter/DisplayConfig"
APPLY_TYPE = "(uua(iiduba(ssa{sv}))a{sv})"
TEMPORARY = 1


def log(message: str) -> None:
    print(message, flush=True)


def notify(body: str) -> None:
    try:
        subprocess.run(["notify-send", "Monitor recovered", body], check=False, timeout=5)
    except (OSError, subprocess.SubprocessError):
        pass


def proxy() -> Gio.DBusProxy:
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    return Gio.DBusProxy.new_sync(bus, Gio.DBusProxyFlags.NONE, None, NAME, PATH, NAME)


def state(p: Gio.DBusProxy) -> tuple[int, list, list]:
    serial, monitors, logical, _props = p.call_sync("GetCurrentState", None, 0, -1, None).unpack()
    return serial, monitors, logical


def power_save_mode(p: Gio.DBusProxy) -> int:
    # No main loop runs here, so the proxy's property cache never updates; ask.
    value = p.get_connection().call_sync(
        NAME, PATH, "org.freedesktop.DBus.Properties", "Get",
        GLib.Variant("(ss)", (NAME, "PowerSaveMode")), None, 0, -1, None,
    )
    return value.unpack()[0]


def sysfs_dir(connector: str) -> str | None:
    # Mutter says HDMI-2 where the kernel says HDMI-A-2.
    names = [connector]
    if connector.startswith("HDMI-") and not connector.startswith("HDMI-A-"):
        names.append("HDMI-A-" + connector[len("HDMI-"):])
    for name in names:
        found = glob.glob(f"/sys/class/drm/card*-{name}")
        if found:
            return found[0]
    return None


def read(path: str) -> str:
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return ""


def is_dark(connector: str) -> bool:
    d = sysfs_dir(connector)
    if d is None:
        return False
    return read(f"{d}/status") == "connected" and read(f"{d}/enabled") == "disabled"


def modes_by_connector(monitors: list) -> dict[str, list]:
    return {spec[0]: modes for spec, modes, _props in monitors}


def current_mode(modes: list) -> tuple | None:
    for mode in modes:
        if mode[6].get("is-current"):
            return mode
    for mode in modes:
        if mode[6].get("is-preferred"):
            return mode
    return modes[0] if modes else None


def candidates(modes: list, wanted: tuple | None) -> list[str]:
    """Same resolution first, fastest first; then smaller resolutions."""
    w, h = (wanted[1], wanted[2]) if wanted else (0, 0)
    same = sorted((m for m in modes if (m[1], m[2]) == (w, h)), key=lambda m: -m[3])
    rest = sorted((m for m in modes if (m[1], m[2]) != (w, h)), key=lambda m: (-m[1] * m[2], -m[3]))
    return [m[0] for m in same + rest][:MAX_TRIES]


def apply(p: Gio.DBusProxy, dark: str, mode_id: str) -> bool:
    serial, monitors, logical = state(p)
    modes = modes_by_connector(monitors)
    layout = []
    for x, y, scale, transform, primary, specs, _props in logical:
        entries = []
        for spec in specs:
            connector = spec[0]
            if connector == dark:
                chosen = mode_id
            else:
                mode = current_mode(modes.get(connector, []))
                if mode is None:
                    return False
                chosen = mode[0]
            entries.append((connector, chosen, {}))
        layout.append((x, y, scale, transform, primary, entries))
    try:
        p.call_sync("ApplyMonitorsConfig", GLib.Variant(APPLY_TYPE, (serial, TEMPORARY, layout, {})), 0, -1, None)
    except GLib.Error as e:
        log(f"{dark}: {mode_id} refused: {e.message}")
        return False
    time.sleep(SETTLE)
    return not is_dark(dark)


def rescue(p: Gio.DBusProxy, connector: str) -> None:
    _serial, monitors, _logical = state(p)
    modes = modes_by_connector(monitors).get(connector, [])
    wanted = current_mode(modes)
    log(f"{connector}: connected but dark while GNOME has it on (asked for {wanted[0] if wanted else '?'})")
    for mode_id in candidates(modes, wanted):
        if wanted and mode_id == wanted[0]:
            continue
        if apply(p, connector, mode_id):
            log(f"{connector}: lit again at {mode_id}")
            notify(f"{connector} came back dark and now runs at {mode_id}. Power-cycle it to get the old mode back.")
            return
    log(f"{connector}: no mode brought it back")


def main() -> int:
    p = proxy()
    dark_polls: dict[str, int] = {}
    cooldown_until: dict[str, float] = {}
    log("watching for monitors that GNOME has on but the kernel has off")
    while True:
        time.sleep(POLL)
        try:
            # A blanked screen is off on purpose.
            if power_save_mode(p) != 0:
                dark_polls.clear()
                continue
            _serial, _monitors, logical = state(p)
            active = [spec[0] for lm in logical for spec in lm[5]]
            for connector in active:
                if not is_dark(connector):
                    dark_polls.pop(connector, None)
                    continue
                dark_polls[connector] = dark_polls.get(connector, 0) + 1
                if dark_polls[connector] < DARK_POLLS or time.monotonic() < cooldown_until.get(connector, 0):
                    continue
                rescue(p, connector)
                dark_polls.pop(connector, None)
                cooldown_until[connector] = time.monotonic() + COOLDOWN
        except GLib.Error as e:
            # Mutter restarts with the session; reconnect.
            log(f"D-Bus error: {e.message}")
            time.sleep(POLL)
            p = proxy()


if __name__ == "__main__":
    sys.exit(main())
