import 'package:capstone_dashboard/ui/discipline_officer_connected_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Good Moral Student List loads 5 rows a page on a phone, 25 elsewhere',
      () {
    // context.cardPageSize is 5 below the phone breakpoint, 10 at or above it.
    expect(studentDirectoryPageSizeFor(5), 5);
    expect(studentDirectoryPageSizeFor(10), 25);
  });
}
