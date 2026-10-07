import 'package:flutter_test/flutter_test.dart';
import 'package:student_portal_module/models/student_risk_snapshot.dart';

void main() {
  test('parses a stored risk_assessments row', () {
    final s = StudentRiskSnapshot.fromRow({
      'risk_level': 'High',
      'dropout_probability': 0.72,
      'computed_at': '2026-10-01T08:00:00Z',
      'key_factors': [
        {'factor': 'Attendance rate', 'value': '62%', 'severity': 'High'},
        {'factor': 'No value'},
      ],
      'recommendations': ['Meet the counselor'],
    });
    expect(s.riskLevel, 'High');
    expect(s.dropoutProbability, 0.72);
    expect(s.keyFactors, ['Attendance rate: 62% (High)', 'No value']);
    expect(s.recommendations, ['Meet the counselor']);
  });

  test('tolerates a batch row with only reasoning text', () {
    final s = StudentRiskSnapshot.fromRow({
      'risk_level': 'Low',
      'dropout_probability': 0.1,
      'computed_at': '2026-10-01T08:00:00Z',
      'key_factors': [],
      'risk_reasoning': 'Stable attendance',
    });
    expect(s.keyFactors, isEmpty);
    expect(s.riskReasoning, 'Stable attendance');
  });
}
