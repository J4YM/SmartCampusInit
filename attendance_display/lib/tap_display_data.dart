import 'package:kiosk/kiosk_module.dart' show formatTapDateTime;

export 'package:kiosk/kiosk_module.dart' show formatTapDateTime;

class TapDisplayData {
  const TapDisplayData({
    required this.name,
    required this.section,
    required this.photoSignedUrl,
    required this.direction,
    this.tappedAt,
    this.recognized = true,
  });

  final String name;
  final String section;
  final String? photoSignedUrl;

  /// 'in' or 'out' — mirrors `rfid_tap_events.tap_direction`.
  final String direction;

  /// When the card was tapped (`rfid_tap_events.tapped_at`), shown on the card.
  final DateTime? tappedAt;

  /// False when the card belongs to no student: the screen shows an error
  /// instead of a welcome.
  final bool recognized;
}

TapDisplayData formatTapDisplayData({
  required String firstName,
  required String lastName,
  required String sectionName,
  required String? photoSignedUrl,
  required String direction,
  DateTime? tappedAt,
}) {
  final name = '${firstName.trim()} ${lastName.trim()}'.trim();
  return TapDisplayData(
    name: name.isEmpty ? 'Unregistered card' : name,
    section: sectionName.trim(),
    photoSignedUrl: photoSignedUrl,
    direction: direction,
    tappedAt: tappedAt,
    recognized: name.isNotEmpty,
  );
}
