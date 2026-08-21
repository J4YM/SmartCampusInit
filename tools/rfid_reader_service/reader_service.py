"""Central reader-service for the multi-floor RFID attendance network.

Runs on the one central machine that has every floor's USB RFID reader
attached (directly or via USB-over-RJ45 extenders). Reads each reader as a
distinct HID device, decodes tapped card UIDs, and calls Supabase's
`record_rfid_tap` RPC (see supabase/add_rfid_reader_network_schema.sql) for
every tap — exactly the same call the in-app dev simulator makes
(lib/ui/admin/rfid_tap_simulator_dialog.dart), so both paths produce
identical, correctly-toggled in/out events.

IMPORTANT — untested against physical hardware. This was written without
access to real RFID reader units, so two things WILL likely need adjusting
once real hardware is in hand:

1. Device identity (see `list_devices()` / the `readers` section of
   config.json): many cheap USB-HID RFID reader modules do not expose a
   genuinely unique `serial_number` in their USB descriptor — some report a
   blank string, others the same fixed value across every unit of the same
   model. If that's true for your hardware, `serial_number` matching in the
   config won't tell two identical readers apart, and you'll need to match
   on `path` instead (which encodes physical USB port topology and stays
   stable as long as nothing gets re-plugged into a different port).
   Run `python reader_service.py --list-devices` with everything plugged in
   to see both fields for every attached reader before deciding.

2. UID decoding (`_decode_hid_report`): implemented for the common case —
   readers that behave like a USB keyboard typing the card UID as digits
   followed by Enter (the same "keyboard wedge" behavior the Flutter kiosk's
   invisible text field already relies on). A reader using a different
   encoding (e.g. raw Wiegand-over-HID) will need a different decode
   function here.

Setup:
    pip install -r requirements.txt
    cp config.example.json config.json   # then edit it — see below
    python reader_service.py --list-devices   # identify your readers
    python reader_service.py                  # run for real
"""

from __future__ import annotations

import argparse
import json
import logging
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import hid
import requests

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
log = logging.getLogger("rfid_reader_service")

# Standard USB HID keyboard usage-code -> character map, for the digits and
# Enter key most RFID keyboard-wedge readers actually send. Extend if your
# reader's card UIDs include letters.
_HID_KEYCODES = {
    0x1E: "1", 0x1F: "2", 0x20: "3", 0x21: "4", 0x22: "5",
    0x23: "6", 0x24: "7", 0x25: "8", 0x26: "9", 0x27: "0",
    0x28: "\n",  # Enter
}

# Offline queue (a network blip or Supabase hiccup shouldn't drop a tap) —
# persisted to disk so it survives a service restart, and flushed on every
# successful send.
_QUEUE_FILE = Path(__file__).parent / "pending_taps.jsonl"


@dataclass
class ReaderConfig:
    usb_serial: str  # must match `rfid_readers.usb_serial` in Supabase
    label: str
    match_field: str  # "serial_number" or "path"
    match_value: str


def list_devices() -> None:
    """Prints every attached HID device's identity fields, to help you build
    config.json. Run this with all readers plugged in and nothing else
    ambiguous attached."""
    for d in hid.enumerate():
        print(
            f"vendor_id=0x{d['vendor_id']:04x} product_id=0x{d['product_id']:04x} "
            f"serial_number={d.get('serial_number')!r} path={d.get('path')!r} "
            f"product_string={d.get('product_string')!r}"
        )


def _load_config(path: Path) -> tuple[str, str, list[ReaderConfig]]:
    data = json.loads(path.read_text())
    readers = [
        ReaderConfig(
            usb_serial=r["usb_serial"],
            label=r["label"],
            match_field=r["match_field"],
            match_value=r["match_value"],
        )
        for r in data["readers"]
    ]
    return data["supabase_url"], data["supabase_anon_key"], readers


def _find_device_path(reader: ReaderConfig) -> Optional[bytes]:
    for d in hid.enumerate():
        value = d.get(reader.match_field)
        if value == reader.match_value:
            return d["path"]
    return None


class TapSender:
    """Owns the HTTP call to `record_rfid_tap` plus the offline retry queue.
    One instance shared by every reader thread (thread-safe: each call is
    independent, no shared mutable state beyond the queue file, which is
    only appended/rewritten under `_lock`)."""

    def __init__(self, supabase_url: str, anon_key: str):
        self._rpc_url = f"{supabase_url.rstrip('/')}/rest/v1/rpc/record_rfid_tap"
        self._headers = {
            "apikey": anon_key,
            "Authorization": f"Bearer {anon_key}",
            "Content-Type": "application/json",
        }
        self._lock = threading.Lock()
        self._flush_pending()

    def _post(self, reader_usb_serial: str, rfid_uid: str) -> None:
        response = requests.post(
            self._rpc_url,
            headers=self._headers,
            json={
                "p_reader_usb_serial": reader_usb_serial,
                "p_rfid_uid": rfid_uid,
            },
            timeout=5,
        )
        response.raise_for_status()

    def send(self, reader_usb_serial: str, rfid_uid: str) -> None:
        try:
            self._post(reader_usb_serial, rfid_uid)
            log.info("Tap sent: reader=%s uid=%s", reader_usb_serial, rfid_uid)
        except requests.RequestException as exc:
            log.warning(
                "Tap send failed (queued for retry): reader=%s uid=%s error=%s",
                reader_usb_serial, rfid_uid, exc,
            )
            self._enqueue(reader_usb_serial, rfid_uid)

    def _enqueue(self, reader_usb_serial: str, rfid_uid: str) -> None:
        with self._lock:
            with _QUEUE_FILE.open("a", encoding="utf-8") as f:
                f.write(json.dumps({
                    "reader_usb_serial": reader_usb_serial,
                    "rfid_uid": rfid_uid,
                    "queued_at": time.time(),
                }) + "\n")

    def _flush_pending(self) -> None:
        """Retries anything queued from a previous run/outage. Best-effort —
        entries that still fail are re-queued rather than lost."""
        if not _QUEUE_FILE.exists():
            return
        with self._lock:
            lines = _QUEUE_FILE.read_text(encoding="utf-8").splitlines()
            _QUEUE_FILE.unlink()
        still_pending = []
        for line in lines:
            entry = json.loads(line)
            try:
                self._post(entry["reader_usb_serial"], entry["rfid_uid"])
                log.info(
                    "Flushed queued tap: reader=%s uid=%s",
                    entry["reader_usb_serial"], entry["rfid_uid"],
                )
            except requests.RequestException:
                still_pending.append(line)
        if still_pending:
            with _QUEUE_FILE.open("a", encoding="utf-8") as f:
                f.write("\n".join(still_pending) + "\n")


def _reader_loop(reader: ReaderConfig, sender: TapSender, stop: threading.Event) -> None:
    """Runs forever in its own thread, one per configured reader — a device
    open failure or a decode hiccup on one reader must never take down the
    others."""
    while not stop.is_set():
        device_path = _find_device_path(reader)
        if device_path is None:
            log.error(
                "Reader '%s' (%s=%r) not found — retrying in 10s. Is it "
                "plugged in? Run --list-devices to check current values.",
                reader.label, reader.match_field, reader.match_value,
            )
            time.sleep(10)
            continue

        try:
            device = hid.device()
            device.open_path(device_path)
            device.set_nonblocking(False)
            log.info("Reader '%s' connected.", reader.label)
        except OSError as exc:
            log.error("Could not open reader '%s': %s — retrying in 10s.", reader.label, exc)
            time.sleep(10)
            continue

        buffer = ""
        try:
            while not stop.is_set():
                report = device.read(64, timeout_ms=1000)
                if not report:
                    continue
                char = _decode_hid_report(report)
                if char is None:
                    continue
                if char == "\n":
                    if buffer:
                        sender.send(reader.usb_serial, buffer)
                    buffer = ""
                else:
                    buffer += char
        except OSError as exc:
            log.warning("Reader '%s' disconnected: %s — reconnecting.", reader.label, exc)
        finally:
            device.close()


def _decode_hid_report(report: list[int]) -> Optional[str]:
    """Standard 8-byte USB HID keyboard report: byte[2] is the primary
    keycode (bytes 0-1 are modifier/reserved, bytes 3-7 are additional
    simultaneous keys — unused here since a reader sends one key at a
    time). Returns None for a key-release report (all zeros) or an
    unrecognized keycode."""
    if len(report) < 3 or report[2] == 0:
        return None
    return _HID_KEYCODES.get(report[2])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list-devices", action="store_true",
                         help="List attached HID devices and exit (use this to build config.json).")
    parser.add_argument("--config", default="config.json",
                         help="Path to config.json (default: ./config.json).")
    args = parser.parse_args()

    if args.list_devices:
        list_devices()
        return

    config_path = Path(args.config)
    if not config_path.exists():
        log.error(
            "%s not found. Copy config.example.json to config.json and edit "
            "it first (see this file's module docstring).",
            config_path,
        )
        return

    supabase_url, anon_key, readers = _load_config(config_path)
    if not readers:
        log.error("No readers configured in %s.", config_path)
        return

    sender = TapSender(supabase_url, anon_key)
    stop = threading.Event()
    threads = [
        threading.Thread(
            target=_reader_loop, args=(reader, sender, stop), daemon=True,
            name=f"reader-{reader.label}",
        )
        for reader in readers
    ]
    for t in threads:
        t.start()

    log.info("Central reader-service running with %d reader(s). Ctrl+C to stop.", len(threads))
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        log.info("Stopping…")
        stop.set()
        for t in threads:
            t.join(timeout=2)


if __name__ == "__main__":
    main()
