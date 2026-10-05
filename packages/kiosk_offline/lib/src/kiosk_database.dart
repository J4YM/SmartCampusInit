import 'package:drift/drift.dart';

import 'models.dart';
import 'tap_rules.dart';

part 'kiosk_database.g.dart';

@DataClassName('CachedStudentRow')
class CachedStudents extends Table {
  TextColumn get id => text()();
  TextColumn get rfidUid => text()();
  TextColumn get fullName => text()();
  TextColumn get studentNumber => text()();
  TextColumn get gradeSection => text()();
  TextColumn get course => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CachedStaffRow')
class CachedStaff extends Table {
  TextColumn get id => text()();
  TextColumn get rfidCardId => text()();
  TextColumn get fullName => text()();
  TextColumn get role => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CachedOffenseRow')
class CachedOffenses extends Table {
  TextColumn get id => text()();
  TextColumn get label => text()();
  TextColumn get category => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CachedTeacherRow')
class CachedTeachers extends Table {
  TextColumn get id => text()();
  TextColumn get fullName => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// This kiosk's own taps for known students — the input to the offline rules.
@DataClassName('LocalTapRow')
class LocalTaps extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get studentId => text()();
  TextColumn get direction => text()();
  DateTimeColumn get tappedAt => dateTime()();
  TextColumn get schoolDay => text()();
}

/// Writes waiting to reach the server. Drained in `id` order.
@DataClassName('OutboxRow')
class OutboxEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// `'tap'` or `'slip'`.
  TextColumn get type => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// `'pending'` or `'rejected'`.
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get lastError => text().nullable()();
}

@DataClassName('SyncMetaRow')
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [
  CachedStudents,
  CachedStaff,
  CachedOffenses,
  CachedTeachers,
  LocalTaps,
  OutboxEntries,
  SyncMeta,
])
class KioskDatabase extends _$KioskDatabase {
  KioskDatabase(super.e);

  @override
  int get schemaVersion => 1;

  // ---- reference cache ----------------------------------------------------

  OfflineStudent _student(CachedStudentRow r) => OfflineStudent(
        id: r.id,
        rfidUid: r.rfidUid,
        fullName: r.fullName,
        studentNumber: r.studentNumber,
        gradeSection: r.gradeSection,
        course: r.course,
      );

  Future<OfflineStudent?> studentByRfid(String uid) async {
    final key = uid.trim();
    if (key.isEmpty) return null;
    final row = await (select(cachedStudents)
          ..where((t) => t.rfidUid.equals(key))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _student(row);
  }

  Future<OfflineStudent?> studentById(String id) async {
    final row = await (select(cachedStudents)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _student(row);
  }

  Future<List<OfflineStudent>> searchStudents(
    String numberPrefix, {
    int limit = 8,
  }) async {
    final q = numberPrefix.trim();
    if (q.isEmpty) return const [];
    final rows = await (select(cachedStudents)
          ..where((t) => t.studentNumber.like('$q%'))
          ..orderBy([(t) => OrderingTerm.asc(t.studentNumber)])
          ..limit(limit))
        .get();
    return rows.map(_student).toList();
  }

  Future<OfflineStaff?> staffByCard(String cardId) async {
    final key = cardId.trim();
    if (key.isEmpty) return null;
    final row = await (select(cachedStaff)
          ..where((t) => t.rfidCardId.equals(key))
          ..limit(1))
        .getSingleOrNull();
    return row == null
        ? null
        : OfflineStaff(
            id: row.id,
            rfidCardId: row.rfidCardId,
            fullName: row.fullName,
            role: row.role,
          );
  }

  Future<List<OfflineOffense>> offenses() async {
    final rows = await (select(cachedOffenses)
          ..orderBy([(t) => OrderingTerm.asc(t.label)]))
        .get();
    return [
      for (final r in rows)
        OfflineOffense(id: r.id, label: r.label, category: r.category),
    ];
  }

  Future<List<OfflineTeacher>> teachers() async {
    final rows = await select(cachedTeachers).get();
    return [for (final r in rows) OfflineTeacher(id: r.id, fullName: r.fullName)];
  }

  Future<int> cachedStudentCount() async {
    final c = cachedStudents.id.count();
    final q = selectOnly(cachedStudents)..addColumns([c]);
    return (await q.getSingle()).read(c) ?? 0;
  }

  /// Atomically replaces every cache table with [data].
  Future<void> replaceReference(ReferenceData data) async {
    await transaction(() async {
      await delete(cachedStudents).go();
      await delete(cachedStaff).go();
      await delete(cachedOffenses).go();
      await delete(cachedTeachers).go();
      await batch((b) {
        b.insertAll(cachedStudents, [
          for (final s in data.students)
            CachedStudentsCompanion.insert(
              id: s.id,
              rfidUid: s.rfidUid.trim(),
              fullName: s.fullName,
              studentNumber: s.studentNumber,
              gradeSection: s.gradeSection,
              course: Value(s.course),
            ),
        ]);
        b.insertAll(cachedStaff, [
          for (final s in data.staff)
            CachedStaffCompanion.insert(
              id: s.id,
              rfidCardId: s.rfidCardId.trim(),
              fullName: s.fullName,
              role: s.role,
            ),
        ]);
        b.insertAll(cachedOffenses, [
          for (final o in data.offenses)
            CachedOffensesCompanion.insert(
              id: o.id,
              label: o.label,
              category: Value(o.category),
            ),
        ]);
        b.insertAll(cachedTeachers, [
          for (final t in data.teachers)
            CachedTeachersCompanion.insert(id: t.id, fullName: t.fullName),
        ]);
      });
    });
  }

  // ---- meta ---------------------------------------------------------------

  Future<String?> getMeta(String key) async {
    final row = await (select(syncMeta)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setMeta(String key, String value) => into(syncMeta)
      .insertOnConflictUpdate(SyncMetaCompanion.insert(key: key, value: value));

  // ---- local taps ---------------------------------------------------------

  Future<int> insertLocalTap({
    required String studentId,
    required String direction,
    required DateTime tappedAt,
  }) =>
      into(localTaps).insert(LocalTapsCompanion.insert(
        studentId: studentId,
        direction: direction,
        tappedAt: tappedAt,
        schoolDay: schoolDayOf(tappedAt),
      ));

  Future<LocalTapRow?> lastTapOnDay(String studentId, String schoolDay) =>
      (select(localTaps)
            ..where((t) =>
                t.studentId.equals(studentId) & t.schoolDay.equals(schoolDay))
            ..orderBy([(t) => OrderingTerm.desc(t.tappedAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<void> setLocalTapDirection(int id, String direction) =>
      (update(localTaps)..where((t) => t.id.equals(id)))
          .write(LocalTapsCompanion(direction: Value(direction)));

  Future<void> deleteLocalTap(int id) =>
      (delete(localTaps)..where((t) => t.id.equals(id))).go();

  // ---- outbox -------------------------------------------------------------

  Future<int> enqueue(String type, String payloadJson, DateTime now) =>
      into(outboxEntries).insert(OutboxEntriesCompanion.insert(
        type: type,
        payload: payloadJson,
        createdAt: now,
      ));

  Future<OutboxRow?> nextPending() => (select(outboxEntries)
        ..where((t) => t.status.equals('pending'))
        ..orderBy([(t) => OrderingTerm.asc(t.id)])
        ..limit(1))
      .getSingleOrNull();

  Future<void> deleteOutbox(int id) =>
      (delete(outboxEntries)..where((t) => t.id.equals(id))).go();

  Future<void> recordAttempt(int id, String error) async {
    final row = await (select(outboxEntries)..where((t) => t.id.equals(id)))
        .getSingle();
    await (update(outboxEntries)..where((t) => t.id.equals(id))).write(
      OutboxEntriesCompanion(
        attempts: Value(row.attempts + 1),
        lastError: Value(error),
      ),
    );
  }

  Future<void> markRejected(int id, String message) =>
      (update(outboxEntries)..where((t) => t.id.equals(id))).write(
        OutboxEntriesCompanion(
          status: const Value('rejected'),
          lastError: Value(message),
        ),
      );

  Future<int> _count(String status) async {
    final c = outboxEntries.id.count();
    final q = selectOnly(outboxEntries)
      ..addColumns([c])
      ..where(outboxEntries.status.equals(status));
    return (await q.getSingle()).read(c) ?? 0;
  }

  /// Rows the server refused, oldest first — what gets reported for review.
  Future<List<OutboxRow>> rejectedEntries() => (select(outboxEntries)
        ..where((t) => t.status.equals('rejected'))
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .get();

  Future<int> pendingCount() => _count('pending');
  Future<int> rejectedCount() => _count('rejected');

  Future<List<OutboxDiagnostic>> diagnostics() async {
    final rows = await (select(outboxEntries)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    return [
      for (final r in rows)
        OutboxDiagnostic(
          id: r.id,
          type: r.type,
          status: r.status,
          attempts: r.attempts,
          createdAt: r.createdAt,
          lastError: r.lastError,
        ),
    ];
  }
}
