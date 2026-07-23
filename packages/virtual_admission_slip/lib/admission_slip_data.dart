/// Values bound at runtime. Defaults are visible placeholders (not sample data).
class AdmissionSlipData {
  const AdmissionSlipData({
    this.studentName = '{{studentName}}',
    this.studentNumber = '{{studentNumber}}',
    this.gradeSection = '{{gradeSection}}',
    this.slipId = '{{slipId}}',
    this.violationCode = '{{violationCode}}',
    this.violationDescription = '{{violationDescription}}',
    this.issueDateTime = '{{issueDateTime}}',
    this.validUntil = '{{validUntil}}',
    this.timeRemaining = '{{timeRemaining}}',
  });

  final String studentName;
  final String studentNumber;
  final String gradeSection;
  final String slipId;
  final String violationCode;
  final String violationDescription;
  final String issueDateTime;
  final String validUntil;
  final String timeRemaining;
}
