/// Predefined list of chronic health conditions shown in the Health Profile form.
/// Keep this in sync with any Firestore validation rules.
const List<String> kChronicConditions = [
  'Asthma',
  'Diabetes',
  'Hypertension',
  'Heart Disease',
  'None',
];

const int kMaxCustomConditions = 5;
const int kMaxCustomConditionLength = 64;

String normalizeCustomCondition(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

String? validateCustomCondition(String value, Iterable<String> existing) {
  if (value.isEmpty) return 'Enter a condition name.';
  if (value.length > kMaxCustomConditionLength ||
      value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    return 'Use up to $kMaxCustomConditionLength characters without control characters.';
  }
  final key = value.toLowerCase();
  if ([...kChronicConditions, ...existing].any(
    (condition) => normalizeCustomCondition(condition).toLowerCase() == key,
  )) {
    return 'This condition is already listed.';
  }
  if (existing.length >= kMaxCustomConditions) {
    return 'You can add up to $kMaxCustomConditions custom conditions.';
  }
  return null;
}
