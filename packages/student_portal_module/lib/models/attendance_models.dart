import 'package:flutter/material.dart';

import '../theme/student_portal_colors.dart';

/// Mirrors a Postgres `attendance_status` enum on a future
/// `attendance_records` table.
enum AttendanceStatus { present, absent, late, excused }

extension AttendanceStatusX on AttendanceStatus {
  String get label {
    switch (this) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.late:
        return 'Late';
      case AttendanceStatus.excused:
        return 'Excused';
    }
  }

  Color foreground(BuildContext context) {
    switch (this) {
      case AttendanceStatus.present:
        return StudentPortalColors.presentFg(context);
      case AttendanceStatus.absent:
        return StudentPortalColors.absentFg(context);
      case AttendanceStatus.late:
        return StudentPortalColors.lateFg(context);
      case AttendanceStatus.excused:
        return StudentPortalColors.excusedFg(context);
    }
  }

  Color background(BuildContext context) {
    switch (this) {
      case AttendanceStatus.present:
        return StudentPortalColors.presentBg(context);
      case AttendanceStatus.absent:
        return StudentPortalColors.absentBg(context);
      case AttendanceStatus.late:
        return StudentPortalColors.lateBg(context);
      case AttendanceStatus.excused:
        return StudentPortalColors.excusedBg(context);
    }
  }

  /// Same icon glyph Professor Dashboard's Attendance table uses per
  /// status, so a status reads identically across the whole app.
  IconData get icon {
    switch (this) {
      case AttendanceStatus.present:
        return Icons.check_circle_rounded;
      case AttendanceStatus.absent:
        return Icons.cancel_rounded;
      case AttendanceStatus.late:
        return Icons.watch_later_rounded;
      case AttendanceStatus.excused:
        return Icons.info_rounded;
    }
  }

  static AttendanceStatus fromDbValue(String value) {
    switch (value) {
      case 'absent':
        return AttendanceStatus.absent;
      case 'late':
        return AttendanceStatus.late;
      case 'excused':
        return AttendanceStatus.excused;
      case 'present':
      default:
        return AttendanceStatus.present;
    }
  }
}

/// One subject's attendance mark for one calendar day. Supabase-shaped —
/// `fromJson`/`toJson` map onto a future `attendance_records` table keyed by
/// (student_id, subject_id, session_date).
class AttendanceEntry {
  const AttendanceEntry({
    required this.date,
    required this.subjectId,
    required this.subjectName,
    required this.status,
    this.timeIn,
    this.remarks,
  });

  final DateTime date;
  final String subjectId;
  final String subjectName;
  final AttendanceStatus status;

  /// Free-text time-in label as recorded by RFID tap-in, e.g. "7:58 AM".
  /// `null` for an absent/excused entry with no tap recorded.
  final String? timeIn;
  final String? remarks;

  factory AttendanceEntry.fromJson(Map<String, dynamic> json) {
    return AttendanceEntry(
      date: DateTime.parse(json['session_date'] as String),
      subjectId: json['subject_id'] as String,
      subjectName: json['subject_name'] as String,
      status: AttendanceStatusX.fromDbValue(json['status'] as String),
      timeIn: json['time_in'] as String?,
      remarks: json['remarks'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_date': date.toIso8601String(),
      'subject_id': subjectId,
      'subject_name': subjectName,
      'status': status.name,
      'time_in': timeIn,
      'remarks': remarks,
    };
  }
}

/// A student's enrolled subject — just enough to drive the subject filter
/// chips on the Attendance tab.
class SubjectModel {
  const SubjectModel({
    required this.id,
    required this.name,
    required this.instructor,
  });

  final String id;
  final String name;
  final String instructor;
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Worst-status-wins rollup for a day with more than one class — absent
/// outranks late, which outranks excused, which outranks present, so a
/// problem status is never hidden behind a green mark. Used by the month
/// grid to collapse every subject's status into one mark per day.
AttendanceStatus? aggregateStatus(List<AttendanceEntry> dayEntries) {
  if (dayEntries.isEmpty) return null;
  const order = [
    AttendanceStatus.absent,
    AttendanceStatus.late,
    AttendanceStatus.excused,
    AttendanceStatus.present,
  ];
  for (final status in order) {
    if (dayEntries.any((e) => e.status == status)) return status;
  }
  return dayEntries.first.status;
}
