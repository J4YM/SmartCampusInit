/// A student's own most recent dropout-risk assessment, as already stored in
/// `risk_assessments` by the Guidance Counselor/Admin side. Read-only here:
/// the student never triggers the ML model, this only displays its latest
/// saved result.
class StudentRiskSnapshot {
  const StudentRiskSnapshot({
    required this.riskLevel,
    required this.dropoutProbability,
    required this.computedAt,
    this.keyFactors = const [],
    this.recommendations = const [],
    this.riskReasoning,
  });

  /// `Low` / `Medium` / `High` / `Critical` (the Postgres enum's labels).
  final String riskLevel;

  /// 0.0–1.0.
  final double dropoutProbability;
  final DateTime computedAt;

  /// Human-readable factor lines, e.g. "Attendance rate: 62% (High)".
  final List<String> keyFactors;
  final List<String> recommendations;

  /// Fallback summary used when [keyFactors] is empty (batch-analysed rows
  /// only store a reasoning string).
  final String? riskReasoning;

  factory StudentRiskSnapshot.fromRow(Map<String, dynamic> row) {
    final factors = <String>[];
    for (final raw in (row['key_factors'] as List<dynamic>? ?? const [])) {
      if (raw is Map) {
        final name = raw['factor']?.toString() ?? '';
        if (name.isEmpty) continue;
        final value = raw['value']?.toString();
        final severity = raw['severity']?.toString();
        final detail = [
          if (value != null && value.isNotEmpty) value,
          if (severity != null && severity.isNotEmpty) '($severity)',
        ].join(' ');
        factors.add(detail.isEmpty ? name : '$name: $detail');
      } else if (raw != null) {
        factors.add(raw.toString());
      }
    }
    return StudentRiskSnapshot(
      riskLevel: row['risk_level'] as String? ?? 'Low',
      dropoutProbability: (row['dropout_probability'] as num?)?.toDouble() ?? 0,
      computedAt:
          DateTime.tryParse(row['computed_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
      keyFactors: factors,
      recommendations: [
        for (final r in (row['recommendations'] as List<dynamic>? ?? const []))
          if (r != null) r.toString(),
      ],
      riskReasoning: row['risk_reasoning'] as String?,
    );
  }
}
