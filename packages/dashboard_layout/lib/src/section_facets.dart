/// Parsing for the "<Program> <separator> <Year><Block>" section strings
/// used across the app's student data (e.g. "BSIT - 4B", "BSIT 3-A",
/// "BSCpE 4-B") — the two separator styles (space-hyphen-space with no gap
/// before the block letter, vs. space then hyphen before the block letter)
/// come from Registrar/Professor/Guidance's mock data vs. Discipline's own,
/// which predate this parser and were never reconciled to one format. The
/// pattern below tolerates both: letters, then any non-digits, then a
/// digit (year), then any non-letters, then a letter (block).
final _sectionPattern = RegExp(r'^([A-Za-z]+)\D*(\d)\D*([A-Za-z])');

/// The section's year digit ('1'-'4'), or null if [section] doesn't match
/// the expected shape.
String? sectionYearDigit(String section) =>
    _sectionPattern.firstMatch(section.trim())?.group(2);

/// The section's block letter, upper-cased (e.g. 'B'), or null if
/// [section] doesn't match the expected shape.
String? sectionBlockLetter(String section) =>
    _sectionPattern.firstMatch(section.trim())?.group(3)?.toUpperCase();

/// The section's leading program code (e.g. 'BSIT'), or null if [section]
/// doesn't match the expected shape.
String? sectionProgramCode(String section) =>
    _sectionPattern.firstMatch(section.trim())?.group(1)?.toUpperCase();

/// Fixed Section-block filter choices — every dashboard's Section filter
/// offers exactly these three, rather than every distinct section string
/// actually on file.
const List<String> kSectionBlocks = ['A', 'B', 'C'];

/// Fixed Year-level filter choices, in the same order as their digit
/// ('1'..'4') — see [yearDigitForLabel].
const List<String> kSectionYearLabels = ['1st', '2nd', '3rd', '4th'];

/// '1st' -> '1', ..., '4th' -> '4'.
String yearDigitForLabel(String label) =>
    '${kSectionYearLabels.indexOf(label) + 1}';

/// '1' -> '1st', ..., '4' -> '4th'. The inverse of [yearDigitForLabel].
String yearLabelForDigit(String digit) {
  final index = int.tryParse(digit);
  if (index == null || index < 1 || index > kSectionYearLabels.length) {
    return digit;
  }
  return kSectionYearLabels[index - 1];
}
