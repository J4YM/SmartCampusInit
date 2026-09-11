# ID Card Template Designer + Print Redesign — Design

## Context

IT Technician's "Print ID" flow currently generates a single hardcoded card
layout (`lib/documents/student_id_card_pdf.dart`) — name, student number,
program, section, and a photo, on a plain CR-80 card with placeholder text
branding. Its own doc comment says this was always a stand-in: "no
photo/layout spec from ID Assist to replicate yet, per the app owner."

The app owner has now shared screenshots of **ID Assist** (IDAssist v6.7.0.594
Lite), the reference software this school currently uses for ID printing. It
has three modules — Design ID Layout (a drag-and-drop template editor: Static
Text, Image, ID Data, ID Picture, Signature, and shapes in its toolbox), Data
Entry, and Report — and its actual STI Baliuag SHS card design: front side
(STI logo, school name, photo, name), back side (student number, a signature
box, guardian/emergency-contact block, administrator signature, reminders).

This is the last remaining sub-project of the original 5-part feature
request from this development effort. The decision from design discussion:
build a real visual template designer (not a hardcoded redesign) — full
functional parity with IDAssist's Design ID Layout module, living inside the
existing IT Technician Dashboard, available on both the web and Windows
builds of this app (no platform-conditional code — this app already has
none, e.g. the existing webcam photo capture already works cross-platform
via the `camera` plugin's web support), plus a Windows installer once built.

## Goals

- A visual, drag-and-drop template editor for designing student ID cards —
  front and back — with the same element toolbox IDAssist has (minus
  Fingerprint — see Non-goals): Static Text, Image, ID Data (bound field),
  ID Picture (student photo), Signature, and shapes (Rectangle, Rounded
  Rectangle, Ellipse, Line).
- Full editor interaction parity: single/multi-select, move, resize
  (single-selection), alignment/snap guides, undo/redo, copy/paste, keyboard
  shortcuts, drag-from-toolbox.
- Multiple named, saved templates — selectable at print time.
- A signature capture step (software drawing, no hardware pad) feeding the
  Signature field, alongside the existing photo capture step.
- The existing "Print ID" flow (`IdCardPrintDialog`) extended, not replaced:
  template picker, signature capture (only when the chosen template uses a
  Signature field), and a live front/back preview using the real renderer.
- A Windows installer (Inno Setup) for the main dashboard build, mirroring
  the existing kiosk installer's structure.
- Fix (already shipped, ahead of this spec — see "Related fix already
  applied" below): the webcam capture dialog leaking the camera stream on
  web, discovered during this design conversation.

## Non-goals

- **Topaz hardware signature pad integration.** No real Topaz device is
  available to build or test against. The Signature field captures via a
  software drawing canvas; nothing in this design blocks wiring real
  hardware in later if a pad is acquired (the Signature *field type* and its
  stored-image contract don't change — only how the image gets captured
  would).
- **Fingerprint field type.** No fingerprint hardware exists anywhere in
  this app. Left out of the toolbox entirely (not even as an inert
  placeholder) — add later only if real hardware is acquired.
- **Replicating IDAssist's Data Entry and Report modules.** Student data
  entry/editing already exists (Student Records). This spec is scoped to
  the Design ID Layout editor and the print flow it feeds.
- **Cross-window OS-level clipboard copy/paste.** The editor's copy/paste is
  in-memory within the open editor session, not OS-clipboard-backed.
- **Group resize.** Multi-selected elements move together; resize handles
  only appear for a single selection.
- **Autosave.** Templates save on an explicit Save action.

## Architecture

### One element model, two renderers

A template's front and back are each a list of positioned elements. Every
element carries `{id, type, x, y, width, height, rotation, zIndex}` plus
type-specific fields. `x/y/width/height` are stored in **PDF point units**
(72pt/inch) against the CR-80 card's real physical size (3.375in × 2.125in =
243pt × 153pt) — this is the *only* canonical coordinate space element data
is stored in.

Two independent renderers consume the same element list:

1. **Editor canvas** (Flutter widgets) — the on-screen canvas the IT
   Technician edits directly. It applies a fixed on-screen zoom (e.g. 3×)
   for comfortable editing; element positions are still stored/edited in the
   canonical point space underneath (a text field showing "X: 24" always
   means 24 points, regardless of the current zoom).
2. **PDF renderer** (the `pdf` package, already a dependency) — walks the
   same element list and draws each element into a `pw.Positioned`/`pw.Stack`
   at its exact coordinates. This is what both the print job and the live
   print-preview consume.

Because both renderers read literally the same data, what's designed is
what prints — there's no separate "preview" representation that can drift
out of sync with the real output.

Element types:

| Type | Type-specific fields | Notes |
|---|---|---|
| `static_text` | `content`, `fontFamily`, `fontSize`, `color`, `alignment` | Fixed text (e.g. school name, reminders paragraph). |
| `image` | `storagePath` | An uploaded static image (e.g. logo). |
| `id_data` | `fieldKey`, `fontFamily`, `fontSize`, `color` | Bound to a student field — see Data Binding below. |
| `id_picture` | *(none — position/size only)* | The student's photo, resolved at print time. |
| `signature` | *(none — position/size only)* | The student's captured signature, resolved at print time. |
| `rectangle` / `rounded_rect` | `fillColor`, `strokeColor`, `strokeWidth`, `cornerRadius` (rounded only) | |
| `ellipse` | `fillColor`, `strokeColor`, `strokeWidth` | |
| `line` | `strokeColor`, `strokeWidth` | |

### Data binding (`id_data.fieldKey`)

`fieldKey` is one of: `first_name`, `middle_initial`, `last_name`,
`student_number`, `course`, `section`, `year_level`, `guardian_name`,
`guardian_contact_no`. These map onto `RfidStudentRow`'s existing fields
plus the new `guardian_contact_no` (see Data Model below).

## Data Model

### `id_card_templates` (new table)

```
id            uuid primary key default gen_random_uuid()
name          text not null
front_layout  jsonb not null default '[]'::jsonb
back_layout   jsonb not null default '[]'::jsonb
created_by    uuid references public.profiles(id) on delete set null
created_at    timestamptz not null default now()
updated_at    timestamptz not null default now()
```

RLS follows this codebase's established pattern: `IT_Technician`/`Admin` can
select/insert/update/delete `to authenticated`, plus the sibling `to anon`
policies (`using (true)`) this codebase already uses repeatedly for static
demo accounts (e.g. `add_rfid_assignment_requests_schema.sql`,
`add_audit_logs_anon_rls.sql`) — demo sessions hit Supabase as `anon`, never
`authenticated`.

### `students` — two new columns

- `guardian_contact_no text` — entered on the same registration form as the
  existing `guardian_name` field (no dependency on a linked parent-portal
  account; not every guardian has one, but the ID card needs this for every
  student).
- `signature_path text` — Storage object path of the student's captured
  signature, mirroring the existing `photo_path` column exactly (same
  private-bucket-with-signed-URL pattern as `add_student_photos_storage.sql`).

### New Storage buckets/paths

- A `signatures` path (or bucket) for captured student signatures,
  provisioned the same way `add_student_photos_storage.sql` provisioned the
  photos bucket.
- A `template_images` path/bucket for uploaded static images (logos) used by
  `image`-type elements.

## Editor UI

### Screen layout

Toolbox (left) → Canvas (center, with a Front/Back tab toggle above it) →
Properties panel (right) — approved during design discussion. Live
properties editing (no popup dialogs).

### Interactions

- **Selection**: click selects one element; shift-click, or dragging a
  selection box over empty canvas, multi-selects.
- **Move**: drag the selection; multiple selected elements move together,
  preserving relative offsets.
- **Resize**: corner/edge drag handles, shown only on a single selection.
- **Alignment guides**: while dragging, thin snap-lines appear when an
  edge/center comes within a small threshold of another element's
  edge/center or the canvas center/edges; the drag snaps to the line. Pure
  Dart — computed against the current element list, no package.
- **Undo/redo**: a capped (50-entry) stack of full front/back element-list
  snapshots, pushed after each discrete committed action (move finished,
  resize finished, add, delete, a property edit committed, paste). Front and
  back keep independent histories.
- **Copy/paste**: in-memory clipboard scoped to the open editor session;
  paste offsets the copy (+10, +10 pt) and selects it.
- **Toolbox → canvas**: real drag-and-drop (Flutter's `Draggable`/
  `DragTarget`), not click-to-add.
- **Keyboard shortcuts**: Ctrl+C, Ctrl+V, Ctrl+Z, Ctrl+Shift+Z, Delete.
- **Properties panel**: position/size (X/Y/W/H) always shown for the current
  single selection; plus the type-specific fields from the element-type
  table above. Multi-selection shows a combined bounding box with
  position/size fields disabled (no group-resize — see Non-goals).
- **Save**: explicit action; persists both `front_layout` and `back_layout`
  to the template row. An unsaved-changes indicator (dirty flag) warns
  before navigating away, but there is no autosave.

## Signature Capture

A new dialog, `SignatureCaptureDialog`, structurally mirrors the existing
`WebcamCaptureDialog` (Clear/Retake, "Use Signature" buttons) but draws
rather than streams a camera. Built on the `signature` package (pure-Dart
Flutter drawing-canvas widget — no native code, works identically on web and
Windows, same category of dependency as the `camera` plugin already in use).

Captured signatures upload to the new `signatures` path and are stored via
`students.signature_path`, exactly like photos — captured once, reused for
every future reprint without recapturing.

## Print Flow Integration

`IdCardPrintDialog` is extended, not replaced:

1. A template picker (the saved `id_card_templates`, defaulting to whichever
   template has the most recent `updated_at` — no separate "last used"
   tracking to build).
2. The existing photo capture/retake step, unchanged.
3. A signature capture/retake step — shown only if the selected template's
   *back* layout actually contains a `signature` element, so the dialog
   stays uncluttered for templates that don't use one.
4. A live front/back preview, rendered by the same PDF renderer described
   in Architecture, shown via the `printing` package's built-in multi-page
   `PdfPreview` widget (a natural fit for a 2-page front/back document).
5. Print — unchanged behavior: opens the OS print dialog against the CR-80
   format, so the IT Technician can consciously pick the card printer.

`lib/documents/student_id_card_pdf.dart`'s hardcoded renderer is replaced by
the shared template renderer described in Architecture — it now takes a
template's element lists plus the student's real data (name fields, photo
bytes, signature bytes) and produces the front+back PDF pages.

## Windows Installer

This codebase already has a working Inno Setup installer for the kiosk
build (`windows/installer/kiosk_installer.iss`, packaging
`lib/main_kiosk.dart`). A new `windows/installer/dashboard_installer.iss`
mirrors its structure exactly, packaging `lib/main.dart` (the main
dashboard, where this feature lives) instead:

- Same Start Menu shortcut / uninstaller / Programs & Features entry / (a
  new) desktop-shortcut task.
- Same `.env`-copied-next-to-the-exe handling — confirmed necessary:
  `lib/main.dart` resolves to the same `load_local_env_io.dart` file-based
  env loader on Windows that `main_kiosk.dart` uses (both go through the
  conditional `load_local_env.dart` export, which only differs between web
  and native, not between the two entrypoints).
- Built from `flutter build windows --release` (no `--target` override
  needed — `lib/main.dart` is the default entrypoint, unlike the kiosk
  build).

## Testing

- Signature-guard tests for the new repository methods (`id_card_templates`
  CRUD, `students.guardian_contact_no`/`signature_path` read/write paths).
- Widget tests for the editor's core interactions: add an element, select,
  move, resize, undo, redo, copy/paste — via simulated gesture sequences.
- The PDF renderer tested by asserting on the structure of its produced
  output (element count/positions map correctly from a given element list +
  data context), matching how this codebase already tests PDF-producing
  code.
- `flutter test -j 1` clean against the established baseline (all passing
  except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart`
  failure) after every task.

## Related fix already applied

While designing the signature-capture dialog (which mirrors the existing
webcam dialog's structure), a real bug surfaced in the webcam dialog itself:
`camera_web`'s `CameraController.dispose()` doesn't reliably release the
browser's camera stream (a documented upstream issue,
[flutter/flutter#126823](https://github.com/flutter/flutter/issues/126823)).
Left unreleased, the camera hardware stayed locked, so the *next* attempt to
open it failed with `CameraException(cameraNotReadable)` — this is what
surfaced as "captured photo doesn't show up." Fixed ahead of this spec
(commit `a06e90b`) by calling `pausePreview()` before `dispose()`, wrapped
defensively so a failed release can't leave the stream half-torn-down. The
new `SignatureCaptureDialog` doesn't touch a camera at all, so it isn't
subject to this issue, but is built following the same defensive-disposal
discipline regardless.

## Migration / Rollout Order

1. Schema: `id_card_templates` table + RLS, `students.guardian_contact_no`
   and `students.signature_path` columns, `signatures`/`template_images`
   storage provisioning — SQL shown for manual execution in the Supabase SQL
   Editor, never auto-run (this codebase's established convention).
2. Shared element model + repositories (template CRUD, signature
   upload/fetch) — no UI yet.
3. Editor UI (toolbox, canvas, properties panel, all interactions).
4. Signature capture dialog + registration-form `guardian_contact_no` field.
5. Print flow integration (template picker, signature step, live preview,
   renderer swap).
6. Windows installer script.
