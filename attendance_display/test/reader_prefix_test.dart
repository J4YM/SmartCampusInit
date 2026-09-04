import 'package:attendance_display/reader_input_field.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strips a matching prefix and returns the UID', () {
    expect(stripReaderPrefix('#1234567890', '#'), '1234567890');
  });

  test('discards input without the expected prefix', () {
    expect(stripReaderPrefix('1234567890', '#'), isNull);
  });

  test('passes input through unchanged when no prefix is configured', () {
    expect(stripReaderPrefix('1234567890', ''), '1234567890');
  });
}
