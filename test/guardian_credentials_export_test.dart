import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/pages/dashboard/guardian_credentials_export.dart';
import 'package:registrar_module/pages/dashboard/import_students_dialog.dart';

void main() {
  const credentials = [
    ImportGuardianCredential(
      guardianName: 'Dela Cruz, Maria',
      email: 'maria@example.com',
      temporaryPassword: 'Abc234xyzK',
      students: ['2026-0001 Juan Dela Cruz', '2026-0002 Ana Dela Cruz'],
    ),
    ImportGuardianCredential(
      email: 'solo@example.com',
      temporaryPassword: 'Qwe987rtyM',
    ),
  ];

  test('CSV has one row per guardian and quotes embedded commas', () {
    final lines = buildGuardianCredentialsCsv(credentials).trim().split('\n');
    expect(lines.first,
        'Guardian,Email (username),Temporary password,Children');
    expect(lines, hasLength(3));
    expect(lines[1], contains('"Dela Cruz, Maria"'));
    expect(lines[1], contains('Abc234xyzK'));
    expect(lines[1], contains('2026-0001 Juan Dela Cruz; 2026-0002 Ana Dela Cruz'));
    expect(lines[2], startsWith(',solo@example.com,Qwe987rtyM'));
  });

  test('PDF builds as a valid document', () async {
    final bytes = await buildGuardianCredentialsPdf(credentials);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
