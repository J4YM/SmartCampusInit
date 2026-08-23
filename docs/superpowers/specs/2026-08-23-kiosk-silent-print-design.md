# Kiosk Silent Print + Slide-Down Animation — Design Spec

Date: 2026-08-23

## Purpose

The kiosk's "Confirm & Print" action currently calls `printAdmissionSlip`,
which opens the OS/browser's native print dialog and waits for the student
(or whoever is at the kiosk) to manually confirm printing. On the physical
kiosk — a Windows desktop build with a dedicated thermal printer as the
system default — this manual step is unwanted: the slip should print
automatically, with no dialog, and the on-screen flow should read as a
single uninterrupted animation rather than a UI the student has to operate.

## Non-goals

- No changes to the plain "Confirm" (no print) button's behavior.
- No changes to any print path outside the kiosk (`printAdmissionSlip` has
  exactly one call site today, the kiosk host — confirmed via grep).
- No new package dependency — `printing: ^5.14.3` (already a dependency)
  supports silent direct-to-printer output via `Printing.directPrintPdf`
  on desktop platforms.
- Not testable end-to-end without real printer hardware, same as every
  other native-integration path in this codebase — verification here is a
  widget test of the state machine plus a manual check on the kiosk.
- This path only works in the compiled Windows desktop build
  (`flutter run -d windows` / `flutter build windows`), not in a browser —
  `Printing.directPrintPdf`/`listPrinters` are guarded by a
  `Printing.info()` capability check and no-op safely (logged, not shown
  to the student) when unsupported.

## Architecture

**Printing moves from the host into the widget.** Today
`capstone_kiosk_scan_host.dart`'s `onConfirmAndPrint` callback does both
the database write and the print call. `onConfirmAndPrint` keeps its
existing meaning of "submit to the database" (identical to `onConfirm`) —
the print action itself moves inside `AdmissionSlipPreviewScreen`, which
already holds `widget.data` and needs to own the animation timing anyway.

**New function**, `lib/documents/admission_slip_pdf.dart`:

```dart
Future<void> silentPrintAdmissionSlip(AdmissionSlipData data) async {
  try {
    final info = await Printing.info();
    if (!info.canListPrinters || !info.canDirectPrint) {
      debugPrint('Silent print unavailable on this platform.');
      return;
    }
    final printers = await Printing.listPrinters();
    final printer = printers.firstWhere(
      (p) => p.isDefault,
      orElse: () => printers.isEmpty ? throw StateError('No printers found.') : printers.first,
    );
    final bytes = await buildAdmissionSlipPdf(data);
    await Printing.directPrintPdf(
      printer: printer,
      onLayout: (_) async => bytes,
      name: 'Admission Slip ${data.slipId}',
    );
  } catch (e) {
    debugPrint('Silent print failed: $e');
  }
}
```

Never throws — every failure path (unsupported platform, no printers,
`directPrintPdf` throwing) is caught and only `debugPrint`'d, per the
"log quietly, never show the student" decision.

## State machine

`AdmissionSlipStatus` (in `admission_slip_generated_view.dart`) gains two
values after `submitting`, used only by the "Confirm & Print" path:

- `printing` — entered once the DB write (`onConfirmAndPrint`) resolves.
  The `_SlipCard` plays a slide-down + fade-out animation (`AnimatedSlide`
  from `Offset.zero` to `Offset(0, 1.2)` + `AnimatedOpacity` to 0, ~700ms).
  `silentPrintAdmissionSlip(widget.data)` fires concurrently, not awaited
  by the animation itself.
- `printed` — entered once **both** the animation duration has elapsed
  and the print call has resolved (whichever finishes last), so the
  message never appears before the card has visibly finished sliding
  away. Shows "Printed successfully. Kindly get your printed admission
  slip." Starts a 4-second `Timer` that calls `widget.onDone` — no tap
  needed.

`submitted` (the plain "Confirm" path's terminal state, with its existing
manual "Done" button) and `error` (a failed *database* write) are
unchanged.

## Testing

One widget test in `packages/virtual_admission_slip/test/` (new file):
pump `AdmissionSlipPreviewScreen` with a fake `onConfirmAndPrint` that
resolves immediately, tap "Confirm & Print", and assert the status
transitions `submitting` → `printing` → (after the animation + timer)
`printed` → `onDone` is called — using `tester.pump(duration)` to advance
past the animation and the 4-second auto-return timer rather than a real
printer. No mock is needed for `silentPrintAdmissionSlip` itself since it
already never throws and degrades to a no-op off the Windows platform
(the test runs in the default test environment, which reports
`Printing.info()` as unsupported — confirm this during implementation and
add a narrow seam to inject/skip the print call in tests only if that
assumption turns out wrong).
