import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter_test/flutter_test.dart';

DisciplineCaseModel _case({
  String? status = 'Pending',
  bool isClassified = true,
  DateTime? expiredAt,
  DateTime? archivedAt,
  bool suggested = false,
  List<String> evidence = const [],
}) =>
    DisciplineCaseModel(
      id: 'v1',
      studentName: 'Jane Doe',
      studentNumber: '2024-0001',
      programGradeSection: 'BSIT 3-A',
      violationType: 'Improper uniform',
      submittedBy: 'Prof',
      submitterRole: '',
      incidentDateTime: DateTime(2026, 1, 1),
      description: '',
      status: status,
      isClassified: isClassified,
      expiredAt: expiredAt,
      archivedAt: archivedAt,
      suggestedEscalation: suggested,
      evidencePaths: evidence,
    );

void main() {
  group('CaseStage', () {
    test('unclassified pending report is "reported"', () {
      expect(_case(isClassified: false).stage, CaseStage.reported);
    });

    test('classified pending report is "classified"', () {
      expect(_case().stage, CaseStage.classified);
    });

    test('legacy rows with null status read as classified', () {
      expect(_case(status: null).stage, CaseStage.classified);
    });

    test('Under_Investigation is "withGuidance"', () {
      expect(_case(status: 'Under_Investigation').stage, CaseStage.withGuidance);
    });

    test('Investigation_Complete is "investigationComplete"', () {
      expect(_case(status: 'Investigation_Complete').stage,
          CaseStage.investigationComplete);
    });

    test('Resolved is "sanctioned" even if somehow unclassified', () {
      expect(_case(status: 'Resolved', isClassified: false).stage,
          CaseStage.sanctioned);
    });
  });

  group('sanction rules', () {
    test('canSanction only when classified or investigation complete', () {
      expect(_case(isClassified: false).canSanction, isFalse);
      expect(_case().canSanction, isTrue);
      expect(_case(status: 'Investigation_Complete').canSanction, isTrue);
      expect(_case(status: 'Under_Investigation').canSanction, isFalse);
      expect(_case(status: 'Resolved').canSanction, isFalse);
    });

    test('with-guidance cases can be sanctioned only via override', () {
      expect(_case(status: 'Under_Investigation').canOverrideSanction, isTrue);
      expect(_case().canOverrideSanction, isFalse);
    });
  });

  group('expiry marker', () {
    test('expired and still active shows isExpired', () {
      expect(_case(expiredAt: DateTime(2026, 1, 5)).isExpired, isTrue);
    });

    test('legacy auto-archived expired rows are not "expired" markers', () {
      expect(
        _case(expiredAt: DateTime(2026, 1, 5), archivedAt: DateTime(2026, 1, 5))
            .isExpired,
        isFalse,
      );
    });

    test('a case the officer already escalated is no longer "expired"', () {
      for (final status in ['Under_Investigation', 'Investigation_Complete']) {
        expect(_case(status: status, expiredAt: DateTime(2026, 1, 5)).isExpired,
            isFalse,
            reason: status);
      }
    });

    test('a legacy row with no status and an expiry still counts as expired',
        () {
      expect(_case(status: null, expiredAt: DateTime(2026, 1, 5)).isExpired,
          isTrue);
    });

    test('resolved cases are never expired', () {
      expect(
        _case(status: 'Resolved', expiredAt: DateTime(2026, 1, 5)).isExpired,
        isFalse,
      );
    });
  });

  test('json round-trips the lifecycle fields', () {
    final original = _case(suggested: true, evidence: const ['a/b.jpg']);
    final copy = DisciplineCaseModel.fromJson(original.toJson());
    expect(copy.suggestedEscalation, isTrue);
    expect(copy.evidencePaths, ['a/b.jpg']);
    expect(copy.isClassified, isTrue);
  });
}
