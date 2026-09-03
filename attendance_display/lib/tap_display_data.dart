class TapDisplayData {
  const TapDisplayData({
    required this.name,
    required this.section,
    required this.photoSignedUrl,
    required this.direction,
  });

  final String name;
  final String section;
  final String? photoSignedUrl;

  /// 'in' or 'out' — mirrors `rfid_tap_events.tap_direction`.
  final String direction;
}

TapDisplayData formatTapDisplayData({
  required String firstName,
  required String lastName,
  required String sectionName,
  required String? photoSignedUrl,
  required String direction,
}) {
  final name = '${firstName.trim()} ${lastName.trim()}'.trim();
  return TapDisplayData(
    name: name.isEmpty ? 'Unregistered card' : name,
    section: sectionName.trim(),
    photoSignedUrl: photoSignedUrl,
    direction: direction,
  );
}
