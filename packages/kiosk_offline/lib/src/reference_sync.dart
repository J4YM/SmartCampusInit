import 'kiosk_database.dart';
import 'kiosk_remote.dart';

/// Keeps the local reference cache (students, staff, offenses, teachers)
/// fresh. Always a full, atomic replace so deletions and reassigned cards
/// disappear too.
class ReferenceSync {
  ReferenceSync({
    required KioskDatabase db,
    required KioskRemote remote,
    DateTime Function()? now,
    this.interval = const Duration(minutes: 5),
  })  : _db = db,
        _remote = remote,
        _now = now ?? DateTime.now;

  static const _metaKey = 'reference_synced_at';

  final KioskDatabase _db;
  final KioskRemote _remote;
  final DateTime Function() _now;
  final Duration interval;

  Future<bool> refreshIfDue({bool force = false}) async {
    if (!force) {
      final raw = await _db.getMeta(_metaKey);
      final last = raw == null ? null : DateTime.tryParse(raw);
      if (last != null && _now().difference(last) < interval) return false;
    }
    return refresh();
  }

  /// Returns true when the cache was replaced. Never throws; on any failure
  /// (or a suspicious empty result) the existing cache is kept.
  Future<bool> refresh() async {
    try {
      final data = await _remote.fetchReferenceData();
      if (data.students.isEmpty && await _db.cachedStudentCount() > 0) {
        return false;
      }
      await _db.replaceReference(data);
      await _db.setMeta(_metaKey, _now().toUtc().toIso8601String());
      return true;
    } catch (_) {
      return false;
    }
  }
}
