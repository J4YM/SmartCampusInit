import '../pages/dashboard/discipline_officer_dashboard_page.dart'
    show OffenseOption;

/// Behavioral categories that sit alongside the severity levels
/// (`Minor`, `Major_A`..`Major_D`) — see `handbook_offenses.behavior_category`.
enum BehaviorCategory {
  academicIntegrity('Academic_Integrity', 'Academic Integrity'),
  attendanceTardiness('Attendance_Tardiness', 'Attendance / Tardiness'),
  uniformDressCode('Uniform_Dress_Code', 'Uniform / Dress Code'),
  propertyDamage('Property_Damage', 'Property / Facility Damage'),
  disruptiveConduct('Disruptive_Conduct', 'Behavioral / Disruptive Conduct'),
  digitalDevicePolicy('Digital_Device_Policy', 'Digital / Device Policy'),
  other('Other', 'Other');

  const BehaviorCategory(this.dbValue, this.label);

  /// The value stored in the database.
  final String dbValue;
  final String label;

  static BehaviorCategory? fromDb(String? value) {
    for (final c in values) {
      if (c.dbValue == value) return c;
    }
    return null;
  }
}

/// Suggests a behavior category and handbook offenses from the free text a
/// reporter wrote (incident notes, description). Suggestions only: the
/// Discipline Officer always makes the final choice.
class ViolationSuggester {
  const ViolationSuggester._();

  /// Keyword stems per category. A word matches when it starts with a stem, so
  /// "cheating", "cheat" and "cheated" all hit `cheat`.
  static const Map<BehaviorCategory, List<String>> _keywords = {
    BehaviorCategory.academicIntegrity: [
      'cheat', 'plagiar', 'copied', 'copying', 'exam', 'quiz', 'forg',
      'falsif', 'academic', 'answer', 'dishonest', 'crib',
    ],
    BehaviorCategory.attendanceTardiness: [
      'late', 'tardy', 'tardi', 'absen', 'cutting', 'truan', 'skipp',
      'no show', 'missed class', 'leave early',
    ],
    BehaviorCategory.uniformDressCode: [
      'uniform', 'dress', 'haircut', 'hair', 'id ', 'identification',
      'attire', 'cap', 'slipper', 'shorts', 'earring', 'tattoo',
    ],
    BehaviorCategory.propertyDamage: [
      'vandal', 'damag', 'destroy', 'broke', 'broken', 'deface', 'graffiti',
      'property', 'facilit', 'steal', 'stole', 'theft', 'projector', 'chair',
    ],
    BehaviorCategory.disruptiveConduct: [
      'disrespect', 'disrupt', 'fight', 'bully', 'noise', 'noisy', 'rude',
      'shout', 'insubordinat', 'misbehav', 'harass', 'threat', 'argu',
      'punch', 'swear', 'curse', 'unruly',
    ],
    BehaviorCategory.digitalDevicePolicy: [
      'phone', 'gadget', 'device', 'online', 'internet', 'social media',
      'cyber', 'website', 'software', 'digital', 'game', 'gaming', 'laptop',
      'tiktok', 'facebook', 'youtube',
    ],
  };

  static const _stopWords = {
    'the', 'and', 'was', 'were', 'for', 'with', 'that', 'this', 'from',
    'inside', 'during', 'student', 'without', 'when', 'into', 'his', 'her',
    'has', 'had', 'not', 'are', 'any', 'all', 'or', 'of', 'in', 'on', 'to',
    'a', 'an', 'is', 'be', 'by', 'at', 'as', 'it', 'he', 'she', 'they',
  };

  static String _normalize(String text) =>
      ' ${text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')} '
          .replaceAll(RegExp(r'\s+'), ' ');

  static List<String> _words(String text) => [
        for (final w in _normalize(text).trim().split(' '))
          if (w.length > 1 && !_stopWords.contains(w)) w,
      ];

  /// The behavior category whose keywords appear most often in [text], or
  /// null when none match. Ties go to the category listed first.
  static BehaviorCategory? suggestBehaviorCategory(String text) {
    if (text.trim().isEmpty) return null;
    final normalized = _normalize(text);
    final words = _words(text);

    BehaviorCategory? best;
    var bestScore = 0;
    for (final entry in _keywords.entries) {
      var score = 0;
      for (final stem in entry.value) {
        if (stem.contains(' ') || stem.endsWith(' ')) {
          // Phrase or whole-token stem: match in the normalized text.
          if (normalized.contains(' $stem') || normalized.contains(stem)) {
            score++;
          }
        } else {
          for (final w in words) {
            if (w.startsWith(stem)) score++;
          }
        }
      }
      if (score > bestScore) {
        bestScore = score;
        best = entry.key;
      }
    }
    return best;
  }

  static String _stem(String w) => w.length > 4 ? w.substring(0, 4) : w;

  /// Up to [limit] handbook offenses that best match [text], best first.
  /// Scores word-stem overlap with the offense wording, plus a bonus when the
  /// offense belongs to the category suggested from the same text.
  static List<OffenseOption> suggestOffenses(
    String text,
    List<OffenseOption> options, {
    int limit = 3,
  }) {
    if (text.trim().isEmpty) return const [];
    final textStems = {for (final w in _words(text)) _stem(w)};
    final category = suggestBehaviorCategory(text);

    final scored = <(OffenseOption, double)>[];
    for (final o in options) {
      final offenseStems = {for (final w in _words(o.label)) _stem(w)};
      var score = offenseStems.intersection(textStems).length.toDouble();
      if (score == 0) continue;
      if (category != null && o.behaviorCategory == category.dbValue) {
        score += 1.5;
      }
      scored.add((o, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final s in scored.take(limit)) s.$1];
  }
}
