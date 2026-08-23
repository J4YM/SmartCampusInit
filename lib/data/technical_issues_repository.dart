import 'package:supabase_flutter/supabase_flutter.dart';

class TechnicalIssuesRepositoryException implements Exception {
  TechnicalIssuesRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

enum TechnicalIssueCategory { offlineDevice, offlineKiosk, classroomPc, other }

extension TechnicalIssueCategoryDb on TechnicalIssueCategory {
  String get dbValue {
    switch (this) {
      case TechnicalIssueCategory.offlineDevice:
        return 'offline_device';
      case TechnicalIssueCategory.offlineKiosk:
        return 'offline_kiosk';
      case TechnicalIssueCategory.classroomPc:
        return 'classroom_pc';
      case TechnicalIssueCategory.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case TechnicalIssueCategory.offlineDevice:
        return 'Offline device/reader';
      case TechnicalIssueCategory.offlineKiosk:
        return 'Offline kiosk';
      case TechnicalIssueCategory.classroomPc:
        return 'Classroom PC problem';
      case TechnicalIssueCategory.other:
        return 'Other';
    }
  }
}

TechnicalIssueCategory technicalIssueCategoryFromDb(String value) {
  switch (value) {
    case 'offline_device':
      return TechnicalIssueCategory.offlineDevice;
    case 'offline_kiosk':
      return TechnicalIssueCategory.offlineKiosk;
    case 'classroom_pc':
      return TechnicalIssueCategory.classroomPc;
    default:
      return TechnicalIssueCategory.other;
  }
}

enum TechnicalIssueStatus { open, inProgress, resolved }

extension TechnicalIssueStatusDb on TechnicalIssueStatus {
  String get dbValue {
    switch (this) {
      case TechnicalIssueStatus.open:
        return 'open';
      case TechnicalIssueStatus.inProgress:
        return 'in_progress';
      case TechnicalIssueStatus.resolved:
        return 'resolved';
    }
  }

  String get label {
    switch (this) {
      case TechnicalIssueStatus.open:
        return 'Open';
      case TechnicalIssueStatus.inProgress:
        return 'In Progress';
      case TechnicalIssueStatus.resolved:
        return 'Resolved';
    }
  }
}

TechnicalIssueStatus technicalIssueStatusFromDb(String value) {
  switch (value) {
    case 'in_progress':
      return TechnicalIssueStatus.inProgress;
    case 'resolved':
      return TechnicalIssueStatus.resolved;
    default:
      return TechnicalIssueStatus.open;
  }
}

class TechnicalIssueReport {
  const TechnicalIssueReport({
    required this.id,
    required this.category,
    required this.description,
    required this.location,
    required this.reportedBy,
    required this.reportedByRole,
    required this.status,
    required this.createdAt,
    required this.resolvedAt,
    required this.resolvedBy,
  });

  final String id;
  final TechnicalIssueCategory category;
  final String description;
  final String? location;
  final String reportedBy;
  final String reportedByRole;
  final TechnicalIssueStatus status;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;

  factory TechnicalIssueReport.fromSupabase(Map<String, dynamic> row) {
    return TechnicalIssueReport(
      id: row['id'] as String,
      category: technicalIssueCategoryFromDb(row['category'] as String),
      description: row['description'] as String,
      location: row['location'] as String?,
      reportedBy: row['reported_by'] as String,
      reportedByRole: row['reported_by_role'] as String,
      status: technicalIssueStatusFromDb(row['status'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
      resolvedAt: row['resolved_at'] == null
          ? null
          : DateTime.parse(row['resolved_at'] as String),
      resolvedBy: row['resolved_by'] as String?,
    );
  }
}

class TechnicalIssueComment {
  const TechnicalIssueComment({
    required this.id,
    required this.reportId,
    required this.authorId,
    required this.authorRole,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String reportId;
  final String authorId;
  final String authorRole;
  final String message;
  final DateTime createdAt;

  factory TechnicalIssueComment.fromSupabase(Map<String, dynamic> row) {
    return TechnicalIssueComment(
      id: row['id'] as String,
      reportId: row['report_id'] as String,
      authorId: row['author_id'] as String,
      authorRole: row['author_role'] as String,
      message: row['message'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

/// Reads/writes `technical_issue_reports` and `technical_issue_comments` —
/// see supabase/add_it_technician_schema.sql. Reporting and commenting go
/// through `report_technical_issue`/`add_technical_issue_comment` (which
/// also insert the routing `notifications` row in the same transaction);
/// status changes are a plain update, matching how
/// [RfidReaderRepository.setReaderActive] handles simple state changes.
class TechnicalIssuesRepository {
  TechnicalIssuesRepository(this._client);

  final SupabaseClient _client;

  static const _reportSelect =
      'id, category, description, location, reported_by, reported_by_role, status, created_at, resolved_at, resolved_by';

  Future<List<TechnicalIssueReport>> fetchReports({
    TechnicalIssueStatus? status,
  }) async {
    var query = _client.from('technical_issue_reports').select(_reportSelect);
    if (status != null) {
      query = query.eq('status', status.dbValue);
    }
    final rows = await query.order('created_at', ascending: false);
    return (rows as List<dynamic>)
        .map((e) => TechnicalIssueReport.fromSupabase(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TechnicalIssueComment>> fetchComments(String reportId) async {
    final rows = await _client
        .from('technical_issue_comments')
        .select('id, report_id, author_id, author_role, message, created_at')
        .eq('report_id', reportId)
        .order('created_at');
    return (rows as List<dynamic>)
        .map((e) => TechnicalIssueComment.fromSupabase(e as Map<String, dynamic>))
        .toList();
  }

  Future<TechnicalIssueReport> report({
    required TechnicalIssueCategory category,
    required String description,
    required String reporterId,
    required String reporterRole,
    String? location,
  }) async {
    try {
      final rows = await _client.rpc('report_technical_issue', params: {
        'p_category': category.dbValue,
        'p_description': description,
        'p_reporter_id': reporterId,
        'p_reporter_role': reporterRole,
        if (location != null && location.isNotEmpty) 'p_location': location,
      });
      final row = rows is List ? rows.first as Map<String, dynamic> : rows as Map<String, dynamic>;
      return TechnicalIssueReport.fromSupabase(row);
    } on PostgrestException catch (e) {
      throw TechnicalIssuesRepositoryException(e.message);
    }
  }

  Future<TechnicalIssueComment> addComment({
    required String reportId,
    required String message,
    required String authorId,
    required String authorRole,
  }) async {
    try {
      final rows = await _client.rpc('add_technical_issue_comment', params: {
        'p_report_id': reportId,
        'p_message': message,
        'p_author_id': authorId,
        'p_author_role': authorRole,
      });
      final row = rows is List ? rows.first as Map<String, dynamic> : rows as Map<String, dynamic>;
      return TechnicalIssueComment.fromSupabase(row);
    } on PostgrestException catch (e) {
      throw TechnicalIssuesRepositoryException(e.message);
    }
  }

  Future<void> updateStatus({
    required String id,
    required TechnicalIssueStatus status,
    String? resolvedBy,
  }) async {
    try {
      await _client.from('technical_issue_reports').update({
        'status': status.dbValue,
        'resolved_at': status == TechnicalIssueStatus.resolved
            ? DateTime.now().toIso8601String()
            : null,
        'resolved_by': status == TechnicalIssueStatus.resolved ? resolvedBy : null,
      }).eq('id', id);
    } on PostgrestException catch (e) {
      throw TechnicalIssuesRepositoryException(e.message);
    }
  }
}
