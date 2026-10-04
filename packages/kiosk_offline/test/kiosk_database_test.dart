import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_offline/src/kiosk_database.dart';
import 'package:kiosk_offline/src/models.dart';

ReferenceData ref({List<OfflineStudent>? students}) => ReferenceData(
      students: students ??
          const [
            OfflineStudent(
              id: 's1',
              rfidUid: 'UID-1',
              fullName: 'Ana Cruz',
              studentNumber: '2024-0001',
              gradeSection: '1st Year - BSIT-1A',
              course: 'BS Information Technology',
            ),
            OfflineStudent(
              id: 's2',
              rfidUid: '',
              fullName: 'Ben Diaz',
              studentNumber: '2024-0002',
              gradeSection: '1st Year - BSIT-1A',
            ),
          ],
      staff: const [
        OfflineStaff(id: 'p1', rfidCardId: 'CARD-1', fullName: 'Sam Guard', role: 'Security'),
      ],
      offenses: const [OfflineOffense(id: 'o1', label: 'Late', category: 'Minor')],
      teachers: const [OfflineTeacher(id: 't1', fullName: 'Tess Lim')],
    );

void main() {
  late KioskDatabase db;
  setUp(() => db = KioskDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('reference data round-trips and lookups trim the uid', () async {
    await db.replaceReference(ref());
    expect((await db.studentByRfid('  UID-1 '))?.fullName, 'Ana Cruz');
    expect(await db.studentByRfid(''), isNull);
    expect(await db.studentByRfid('nope'), isNull);
    expect((await db.studentById('s2'))?.studentNumber, '2024-0002');
    expect((await db.staffByCard('CARD-1'))?.role, 'Security');
    expect((await db.offenses()).single.label, 'Late');
    expect((await db.teachers()).single.fullName, 'Tess Lim');
  });

  test('a student with no card is never matched by an empty uid', () async {
    await db.replaceReference(ref());
    expect(await db.studentByRfid(''), isNull);
  });

  test('replaceReference drops rows that are no longer on the server', () async {
    await db.replaceReference(ref());
    await db.replaceReference(ref(students: const [
      OfflineStudent(
        id: 's3',
        rfidUid: 'UID-3',
        fullName: 'Cy Eve',
        studentNumber: '2024-0003',
        gradeSection: '2nd Year - BSIT-2A',
      ),
    ]));
    expect(await db.studentByRfid('UID-1'), isNull);
    expect((await db.studentByRfid('UID-3'))?.fullName, 'Cy Eve');
    expect(await db.cachedStudentCount(), 1);
  });

  test('searchStudents matches the student-number prefix and honours limit', () async {
    await db.replaceReference(ref());
    final hits = await db.searchStudents('2024-000');
    expect(hits.map((s) => s.id), ['s1', 's2']);
    expect(await db.searchStudents('2024-000', limit: 1), hasLength(1));
    expect(await db.searchStudents('   '), isEmpty);
  });

  test('lastTapOnDay returns the latest tap for that student and day only', () async {
    final at = DateTime.parse('2026-10-05T08:00:00+08:00');
    await db.insertLocalTap(studentId: 's1', direction: 'in', tappedAt: at);
    await db.insertLocalTap(
      studentId: 's1',
      direction: 'out',
      tappedAt: at.add(const Duration(hours: 2)),
    );
    await db.insertLocalTap(
      studentId: 's2',
      direction: 'in',
      tappedAt: at.add(const Duration(hours: 3)),
    );
    final last = await db.lastTapOnDay('s1', '2026-10-05');
    expect(last?.direction, 'out');
    expect(await db.lastTapOnDay('s1', '2026-10-06'), isNull);
  });

  test('setLocalTapDirection and deleteLocalTap', () async {
    final at = DateTime.parse('2026-10-05T08:00:00+08:00');
    final id = await db.insertLocalTap(studentId: 's1', direction: 'in', tappedAt: at);
    await db.setLocalTapDirection(id, 'out');
    expect((await db.lastTapOnDay('s1', '2026-10-05'))?.direction, 'out');
    await db.deleteLocalTap(id);
    expect(await db.lastTapOnDay('s1', '2026-10-05'), isNull);
  });

  test('outbox returns pending rows oldest-first and skips rejected', () async {
    final now = DateTime.utc(2026, 10, 5);
    final a = await db.enqueue('tap', '{"n":1}', now);
    final b = await db.enqueue('tap', '{"n":2}', now);
    expect((await db.nextPending())?.id, a);
    await db.markRejected(a, 'nope');
    expect((await db.nextPending())?.id, b);
    expect(await db.pendingCount(), 1);
    expect(await db.rejectedCount(), 1);
    await db.recordAttempt(b, 'boom');
    final row = await db.nextPending();
    expect(row?.attempts, 1);
    expect(row?.lastError, 'boom');
    await db.deleteOutbox(b);
    expect(await db.nextPending(), isNull);
  });

  test('diagnostics lists pending and rejected rows with their errors', () async {
    final now = DateTime.utc(2026, 10, 5);
    final a = await db.enqueue('slip', '{}', now);
    await db.markRejected(a, 'bad slip');
    final b = await db.enqueue('tap', '{}', now);
    await db.recordAttempt(b, 'offline');
    final d = await db.diagnostics();
    expect(d.map((e) => (e.type, e.status, e.lastError)), [
      ('slip', 'rejected', 'bad slip'),
      ('tap', 'pending', 'offline'),
    ]);
  });

  test('meta get/set overwrites', () async {
    expect(await db.getMeta('k'), isNull);
    await db.setMeta('k', 'a');
    await db.setMeta('k', 'b');
    expect(await db.getMeta('k'), 'b');
  });
}
