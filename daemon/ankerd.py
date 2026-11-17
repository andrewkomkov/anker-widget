"""Anker Prime wireless charger telemetry daemon.

Prints one JSON state per line on stdout; AnkerBar.app reads it.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys
import time

from bleak import BleakScanner
from SolixBLE import MagGo3in1
from SolixBLE.const import UUID_IDENTIFIER
from SolixBLE.states import PortStatus

HEARTBEAT_S = 15
RESCAN_S = 30
PADS = ("a2", "a3", "a4")
LOG = logging.getLogger("ankerd")


class Charger(MagGo3in1):
    """MagGo3in1 telemetry plus the device info the charger sends during the handshake."""

    def __init__(self, ble_device):
        super().__init__(ble_device)
        self.info: dict[str, str] = {}

    async def _process_negotiation(self, cmd: bytes, payload: bytes) -> None:
        # One handshake reply carries a2=name, a3=firmware ("v0.0.5.2"), a4=serial,
        # a5=mac+serial. Recognise it by content: the command id differs by stage.
        if not self.info:
            try:
                p = self._parse_payload(self._decrypt_payload(payload))
                fw = p.get("a3", b"")
                if fw[:1] == b"v" and fw.isascii() and len(p.get("a4", b"")) >= 8:
                    self.info = {
                        "name": p["a2"].decode("ascii", "replace"),
                        "firmware": fw.decode("ascii"),
                        "serial": p["a4"].decode("ascii", "replace"),
                        "mac": ":".join(f"{b:02x}" for b in p["a5"][:6]) if "a5" in p else "",
                    }
            except Exception:  # not this packet, or not parseable; info is optional
                pass
        return await super()._process_negotiation(cmd, payload)


def emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def snapshot(c: Charger | None, advertised: str) -> dict:
    state = {
        "type": "state",
        "ts": time.time(),
        "advertisedName": advertised,
        "connected": bool(c and c.available and c._data),
        "device": c.info if c else {},
        "pads": [],
        "total": 0.0,
    }
    if not state["connected"]:
        return state
    for i, key in enumerate(PADS, start=1):
        raw = c._data.get(key, b"")
        status = PortStatus(c._parse_int(key, begin=1, end=2)) if len(raw) >= 2 else PortStatus.UNKNOWN
        watts = c._parse_int(key, begin=6, end=8) / 100.0 if len(raw) >= 8 else 0.0
        volts = c._parse_int(key, begin=2, end=4) / 100.0 if len(raw) >= 4 else 0.0
        amps = c._parse_int(key, begin=4, end=6) / 100.0 if len(raw) >= 6 else 0.0
        state["pads"].append({
            "id": i, "status": status.name.lower(), "watts": round(watts, 2),
            "volts": volts, "amps": amps, "raw": raw.hex(),
        })
    state["total"] = round(sum(p["watts"] for p in state["pads"]), 2)
    return state


async def find_charger(name: str | None):
    if name:
        return await BleakScanner.find_device_by_name(name, timeout=20)
    return await BleakScanner.find_device_by_filter(
        lambda _d, adv: UUID_IDENTIFIER in adv.service_uuids, timeout=20)


async def run(name: str | None, once: bool) -> None:
    while True:
        dev = await find_charger(name)
        if dev is not None:
            name = dev.name or name
        if dev is None:
            emit(snapshot(None, name) | {"error": "not found"})
            if once:
                return
            await asyncio.sleep(RESCAN_S)
            continue

        c = Charger(dev)
        changed = asyncio.Event()
        c.add_callback(changed.set)
        if not await c.connect():
            emit(snapshot(None, name) | {"error": "connect failed"})
            await asyncio.sleep(RESCAN_S)
            continue

        last = None
        last_emit = 0.0
        try:
            while True:
                try:
                    await asyncio.wait_for(changed.wait(), timeout=HEARTBEAT_S)
                except asyncio.TimeoutError:
                    pass
                changed.clear()
                s = snapshot(c, name)
                key = (s["connected"], json.dumps(s["pads"]))
                if key != last or time.time() - last_emit >= HEARTBEAT_S:
                    emit(s)
                    last, last_emit = key, time.time()
                if once and s["connected"]:
                    return
                # SolixBLE reconnects on its own; give up after a long outage and rescan.
                if not c.available and c.last_update and time.time() - c.last_update.timestamp() > 300:
                    break
        finally:
            await c.disconnect()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--name", help="advertised BLE name of the charger (default: first Anker device found)")
    ap.add_argument("--once", action="store_true", help="print one connected state and exit")
    args = ap.parse_args()
    logging.basicConfig(level=logging.WARNING, stream=sys.stderr, format="%(levelname)s %(name)s: %(message)s")
    try:
        asyncio.run(run(args.name, args.once))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
