# Central Reader Service

Runs on the one central machine with every floor's RFID reader attached
(directly or via USB-over-RJ45 extenders). Reads each reader, decodes tapped
card UIDs, and calls Supabase's `record_rfid_tap` RPC — the same call the
in-app dev simulator makes, so both paths behave identically.

See `reader_service.py`'s module docstring for the full picture, including
two things that are **untested against real hardware** and will likely need
adjusting: device identity matching, and UID decoding.

## Setup

```
pip install -r requirements.txt
python reader_service.py --list-devices
```

Plug in every reader first. `--list-devices` prints each attached HID
device's `vendor_id`, `product_id`, `serial_number`, and `path`. Use this to
figure out which field reliably tells your specific readers apart —
`serial_number` if your hardware reports a real per-unit value, `path`
(physical USB port position) if it doesn't (common for cheap RFID modules).

Then:

```
cp config.example.json config.json
```

Edit `config.json`:
- `supabase_url` / `supabase_anon_key` — same values as this repo's root
  `.env`.
- `readers` — one entry per physical reader. `usb_serial` **must exactly
  match** a row already seeded in `rfid_readers.usb_serial` (see
  `supabase/add_rfid_reader_network_schema.sql`) or one you add yourself via
  the RFID Mapping admin page / a direct insert. `match_field`/`match_value`
  is whichever identity strategy you settled on above.

Run it:

```
python reader_service.py
```

It logs each tap sent, retries failures automatically (queued to
`pending_taps.jsonl` and flushed on the next successful send or on
restart), and reconnects automatically if a reader is unplugged and
replugged.

## Testing without hardware yet

Use the in-app simulator instead: Admin Dashboard → RFID Mapping →
"Simulate Reader Tap" button. It calls the exact same `record_rfid_tap` RPC,
so everything downstream (in/out toggling, reader heartbeat, student
resolution) is fully exercised without this script or any physical reader.
