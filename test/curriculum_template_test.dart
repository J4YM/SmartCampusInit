import 'dart:io';

import 'package:capstone_dashboard/data/curriculum_import/curriculum_file_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the shipped sample curriculum CSV parses cleanly', () {
    final text =
        File('sample_data/curriculum/curriculum_upload_template.csv').readAsStringSync();
    final parsed = parseCurriculumRows(parseCsvText(text))!;
    expect(parsed.errors, isEmpty);
    expect(parsed.rows, hasLength(274));
    expect(parsed.rows.map((r) => r.program).toSet(), hasLength(5));
  });
}
