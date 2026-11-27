/// A sanction proposed to the Discipline Officer from the student handbook.
/// Always a suggestion: the officer can change every part of it.
class SanctionSuggestion {
  const SanctionSuggestion({
    required this.type,
    required this.description,
    required this.reason,
    this.days,
    this.escalated = false,
  });

  /// `warning`, `community_service`, `suspension`, `non_readmission`,
  /// `dismissal` or `other` (the `sanctions.sanction_type` values).
  final String type;

  /// The sanction text that fills the form.
  final String description;

  /// Where the suggestion came from, shown to the officer.
  final String reason;

  /// Length in days for a suspension or community service (null otherwise).
  final int? days;

  /// True when the handbook penalty was raised because this is a repeat
  /// offense.
  final bool escalated;

  bool get hasPeriod => type == 'suspension' || type == 'community_service';
}

/// Suggests a sanction from the offense's handbook penalty text
/// (`handbook_offenses.penalty_info`) and how many times the student has
/// committed this kind of offense. A repeat offense is escalated one step per
/// repetition, as the handbook's progressive discipline does; a third Major
/// offense only *mentions* a non-readmission or dismissal review, it never
/// picks one.
class SanctionSuggester {
  const SanctionSuggester._();

  /// Longest suspension or service period the suggestion will propose.
  static const maxDays = 15;

  static const _typeNames = {
    'warning': 'Warning',
    'community_service': 'Community service',
    'suspension': 'Suspension',
    'non_readmission': 'Non-readmission',
    'dismissal': 'Dismissal',
    'other': 'Sanction',
  };

  static const _numberWords = {
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
  };

  /// [category] is `handbook_offenses.category` (`Minor`, `Major_A`..`Major_D`);
  /// [offenseNumber] is 1 for a first offense, 2 for a second, and so on
  /// within the Minor or Major group. Returns null when there is neither
  /// handbook text nor a category to go on.
  static SanctionSuggestion? suggest({
    String? handbookPenalty,
    String? category,
    int? offenseNumber,
  }) {
    final text = (handbookPenalty ?? '').trim();
    if (text.isEmpty && (category == null || category.isEmpty)) return null;

    final isMajor = (category ?? '').toLowerCase().startsWith('major');
    final n = offenseNumber ?? 1;

    var type = text.isEmpty ? _defaultType(category) : _typeFromText(text);
    var days = (type == 'suspension' || type == 'community_service')
        ? (_daysFromText(text) ?? _defaultDays(type, category))
        : null;

    final base = text.isEmpty ? _defaultText(type) : text;
    final source = text.isEmpty
        ? 'No handbook penalty is recorded for this offense, so this is the '
            'usual response for a ${isMajor ? 'Major' : 'Minor'} offense.'
        : 'Suggested from the student handbook penalty for this offense: '
            '"$text".';

    // Dismissal and non-readmission are never escalated further.
    if (n <= 1 || type == 'dismissal' || type == 'non_readmission') {
      return SanctionSuggestion(
        type: type,
        description: _withPeriod(base, type, days),
        reason: source,
        days: days,
      );
    }

    final ord = _ordinal(n);
    if (!isMajor) {
      if (n == 2) {
        return SanctionSuggestion(
          type: type,
          description:
              '$base Repeat offense ($ord Minor): written warning with parent notice.',
          reason: '$source This is the $ord Minor offense on record, so a '
              'parent notice is added.',
          days: days,
          escalated: true,
        );
      }
      // 3rd and later Minor offense.
      final wasSuspension = type == 'suspension';
      final newDays = wasSuspension ? _cap((days ?? 1) + 1) : 1;
      return SanctionSuggestion(
        type: 'suspension',
        description: 'Suspension for $newDays ${_dayWord(newDays)}. Repeat '
            'offense ($ord Minor). Handbook penalty: $base',
        reason: '$source This is the $ord Minor offense on record, so the '
            'sanction is raised to a suspension.',
        days: newDays,
        escalated: true,
      );
    }

    // Major offense, 2nd or later.
    final wasSuspension = type == 'suspension';
    final baseDays =
        wasSuspension ? (days ?? 1) : _defaultDays('suspension', category);
    final newDays = _cap(wasSuspension ? baseDays * n : baseDays * (n - 1));
    final review = n >= 3
        ? ' Consider a non-readmission or dismissal review with the '
            'Discipline Board.'
        : '';
    type = 'suspension';
    days = newDays;
    return SanctionSuggestion(
      type: type,
      description: 'Suspension for $newDays ${_dayWord(newDays)}. Repeat '
          'offense ($ord Major). Handbook penalty: $base',
      reason: '$source This is the $ord Major offense on record, so the '
          'sanction is raised to a $newDays-day suspension.$review',
      days: newDays,
      escalated: true,
    );
  }

  static String _typeFromText(String text) {
    final t = text.toLowerCase();
    final possible = t.contains('possible') || t.contains('review');
    if (t.contains('dismissal') ||
        ((t.contains('expulsion') || t.contains('expel')) && !possible)) {
      return 'dismissal';
    }
    if (t.contains('non-readmission') ||
        t.contains('non readmission') ||
        t.contains('not be readmitted')) {
      return 'non_readmission';
    }
    if (t.contains('suspen')) return 'suspension';
    if (t.contains('community service') ||
        t.contains('clean-up') ||
        t.contains('clean up') ||
        t.contains('cleanup')) {
      return 'community_service';
    }
    const otherWords = [
      'probation',
      'conference',
      'confiscat',
      'counsel',
      'restitution',
      'referral',
      'failing',
    ];
    if (otherWords.any(t.contains)) return 'other';
    if (t.contains('warning')) return 'warning';
    return 'other';
  }

  static String _defaultType(String? category) {
    final c = (category ?? '').toLowerCase();
    if (c == 'major_b' || c == 'major_c' || c == 'major_d') return 'suspension';
    return 'warning';
  }

  static String _defaultText(String type) => switch (type) {
        'suspension' => 'Suspension per the student handbook.',
        'warning' => 'Warning per the student handbook.',
        _ => 'Sanction per the student handbook.',
      };

  static int? _daysFromText(String text) {
    final t = text.toLowerCase();
    final digits = RegExp(r'(\d+)\s*-?\s*day').firstMatch(t);
    if (digits != null) return _cap(int.parse(digits.group(1)!));
    for (final entry in _numberWords.entries) {
      if (RegExp('${entry.key}\\s*-?\\s*day').hasMatch(t)) {
        return _cap(entry.value);
      }
    }
    return null;
  }

  static int _defaultDays(String type, String? category) {
    if (type == 'community_service') return 1;
    switch ((category ?? '').toLowerCase()) {
      case 'major_b':
      case 'major_c':
        return 3;
      case 'major_d':
        return 5;
      default:
        return 1;
    }
  }

  static int _cap(int days) => days < 1 ? 1 : (days > maxDays ? maxDays : days);

  static String _dayWord(int n) => n == 1 ? 'day' : 'days';

  /// Adds the period to the text when the handbook did not already state one.
  static String _withPeriod(String base, String type, int? days) {
    if (days == null) return base;
    if (RegExp(r'\d+\s*-?\s*day|\b(one|two|three|four|five|six|seven|eight|nine|ten)\s*-?\s*day',
            caseSensitive: false)
        .hasMatch(base)) {
      return base;
    }
    return '$base (${_typeNames[type] ?? 'Sanction'}: $days ${_dayWord(days)})';
  }

  static String _ordinal(int n) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }
}
