# Patched camera_web 0.3.5

A copy of `camera_web` 0.3.5 from pub.dev with ONE change, in
`lib/src/camera_web.dart` → `availableCameras()`:

Upstream opens every video input device while listing them, and a device that
cannot be opened (a virtual camera whose app isn't running, a Windows Hello IR
sensor, a camera another app holds exclusively — a `NotReadableError`) makes the
whole call throw `cameraNotReadable`. The user's real webcam was fine, but the
IT dashboard's "Capture Student Photo" dialog still failed with "Could not open
the camera". In this copy such a device is still listed (without a facing mode)
and the caller finds out if it opens when it actually tries it — see
`packages/rfid_management_module/lib/ui/webcam_capture_dialog.dart`, which now
tries each camera in turn.

Wired in through `dependency_overrides` in the root `pubspec.yaml`. Drop this
copy (and the override) if upstream ever stops letting one bad device abort the
listing.
