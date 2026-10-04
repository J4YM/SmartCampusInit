import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('native SQLite loads and runs a query', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final rows = db.select('select 1 as one');
    expect(rows.single['one'], 1);
  });
}
