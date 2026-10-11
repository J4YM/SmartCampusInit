import 'package:capstone_dashboard/data/admin_approval_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// The staff search words go straight into a PostgREST `or(...)` filter, so
/// anything that would end or split it has to be stripped first.
void main() {
  final terms = AdminApprovalRepository.staffSearchTerms;

  test('splits a name into words', () {
    expect(terms('  Juan   Dela Cruz '), ['Juan', 'Dela', 'Cruz']);
  });

  test('empty or missing search has no terms', () {
    expect(terms(null), isEmpty);
    expect(terms(''), isEmpty);
    expect(terms('   '), isEmpty);
  });

  test('characters that would break the filter are dropped', () {
    expect(terms('a,b'), ['ab']);
    expect(terms('(x)'), ['x']);
    expect(terms('"quoted"'), ['quoted']);
    expect(terms(r'back\slash'), ['backslash']);
    expect(terms('star*'), ['star']);
  });

  test('an underscore (common in emails) becomes a wildcard', () {
    expect(terms('juan_dela'), ['juan%dela']);
  });

  test('a word with nothing to match on is ignored', () {
    expect(terms('%'), isEmpty);
    expect(terms('_ ,,'), isEmpty);
    expect(terms('juan ()'), ['juan']);
  });

  test('at most five words are used', () {
    expect(terms('a b c d e f g'), ['a', 'b', 'c', 'd', 'e']);
  });
}
