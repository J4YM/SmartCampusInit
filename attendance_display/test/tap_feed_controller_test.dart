import 'package:attendance_display/tap_display_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats a resolved tap into display data', () {
    final data = formatTapDisplayData(
      firstName: 'Juan',
      lastName: 'Dela Cruz',
      sectionName: 'BSIT - 3B',
      photoSignedUrl: 'https://example.com/signed/photo.jpg',
      direction: 'in',
    );

    expect(data.name, 'Juan Dela Cruz');
    expect(data.section, 'BSIT - 3B');
    expect(data.photoSignedUrl, 'https://example.com/signed/photo.jpg');
    expect(data.direction, 'in');
  });

  test('falls back to a generic label when the card is unregistered', () {
    final data = formatTapDisplayData(
      firstName: '',
      lastName: '',
      sectionName: '',
      photoSignedUrl: null,
      direction: 'in',
    );

    expect(data.name, 'Unregistered card');
    expect(data.photoSignedUrl, isNull);
  });
}
