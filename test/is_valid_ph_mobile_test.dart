import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/data/guidance_counselor_repository.dart';

void main() {
  test('accepts the three PH mobile shapes, ignoring punctuation', () {
    expect(isValidPhMobile('09171234567'), isTrue);
    expect(isValidPhMobile('9171234567'), isTrue);
    expect(isValidPhMobile('639171234567'), isTrue);
    expect(isValidPhMobile('+63 917 123 4567'), isTrue);
    expect(isValidPhMobile('0917-123-4567'), isTrue);
  });

  test('rejects empty, short, landline and foreign numbers', () {
    expect(isValidPhMobile(null), isFalse);
    expect(isValidPhMobile(''), isFalse);
    expect(isValidPhMobile('N/A'), isFalse);
    expect(isValidPhMobile('0917123456'), isFalse);
    expect(isValidPhMobile('(044) 123-4567'), isFalse);
    expect(isValidPhMobile('+1 415 555 2671'), isFalse);
  });
}
