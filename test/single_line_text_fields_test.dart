import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard: a TextField that fills its height with `expands: true` has to have
/// `maxLines: null`, and Flutter then defaults its keyboard type to
/// *multiline* — so pressing Enter in a search box or form field inserted a
/// newline. Every single-line (vertically centred) field of that shape must
/// therefore say `keyboardType` explicitly. Multiline text areas
/// (`textAlignVertical: TextAlignVertical.top`) are exempt.
void main() {
  test('every single-line expanding TextField sets its keyboard type', () {
    final offenders = <String>[];
    for (final root in ['packages', 'lib']) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (path.contains('/test/') ||
            path.contains('/build/') ||
            path.contains('/.dart_tool/')) {
          continue;
        }
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].trim() != 'expands: true,') continue;
          // Look at the field's own leading arguments.
          final window = lines.sublist(
              i, i + 12 > lines.length ? lines.length : i + 12);
          final centred =
              window.any((l) => l.contains('TextAlignVertical.center'));
          final typed = window.any((l) => l.contains('keyboardType:'));
          if (centred && !typed) offenders.add('$path:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'single-line fields without keyboardType: $offenders');
  });
}
