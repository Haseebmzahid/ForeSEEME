/// Pure, deterministic mapping from {user conditions × current risk driver} to a
/// recommendation selection key (Sprint 4, Prompt 6).
///
/// Mirrors the frozen contract maps in `docs/alert_dispatch_design.md` §5 and the
/// backend `targeting.py` (condition→category, disease→driver,
/// disease→categories, category priority) — do NOT redesign them here. Unlike
/// the dispatch engine, this runs for the *current* risk (no transition needed):
/// the dashboard card advises on today's risk, not only on a rise.
///
/// Framework-free (no Flutter, no Firebase): a pure function over data, fully
/// unit-testable. The result feeds [RecommendationRepository.lookup].
library;

/// Chronic condition (`kChronicConditions`) → notification/preference category.
const Map<String, String> kConditionCategory = {
  'Asthma': 'respiratory',
  'Heart Disease': 'cardiovascular',
  'Hypertension': 'cardiovascular',
  'Diabetes': 'cardiovascular',
};

/// Disease (`riskEstimates.disease`) → the condition categories its driver makes
/// vulnerable.
const Map<String, Set<String>> kDiseaseCategories = {
  'Smog': {'respiratory', 'cardiovascular'},
  'Respiratory Illness': {'respiratory'},
  'Influenza': {'respiratory'},
  'Heat-Related Illness': {'cardiovascular'},
  'Dengue': <String>{}, // vector-borne: no in-scope chronic-condition driver
};

/// Disease → human risk-driver label (the recommendation lookup's `driver`).
const Map<String, String> kDiseaseDriver = {
  'Smog': 'Air quality',
  'Respiratory Illness': 'Air quality',
  'Influenza': 'Respiratory',
  'Heat-Related Illness': 'Heat',
  'Dengue': 'Vector-borne',
};

/// Deterministic tie-break when a user matches more than one category.
const List<String> kCategoryPriority = ['respiratory', 'cardiovascular'];

/// Fallback driver when a disease is unknown (matches backend `driver_for_disease`).
const String kDefaultDriver = 'Air quality';

/// The `(category, driver)` selection key for a recommendation lookup.
///
/// [category] is `null` when the user has no chronic condition made vulnerable by
/// the current [driver]'s disease — the caller then resolves to the cited default.
class RecommendationKey {
  final String? category;
  final String driver;

  const RecommendationKey({required this.category, required this.driver});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecommendationKey &&
          other.category == category &&
          other.driver == driver;

  @override
  int get hashCode => Object.hash(category, driver);

  @override
  String toString() => 'RecommendationKey(${category ?? '*'}, $driver)';
}

/// The condition categories a user with [conditions] belongs to.
Set<String> userCategories(List<String> conditions) => {
  for (final c in conditions)
    if (kConditionCategory.containsKey(c)) kConditionCategory[c]!,
};

/// Resolves the `(category, driver)` key for the current [disease] and the user's
/// [conditions].
///
/// - `driver` comes from the disease ([kDefaultDriver] if unknown).
/// - `category` is the highest-priority category shared by the user's conditions
///   and the disease's vulnerable categories, or `null` when they do not
///   intersect (→ the caller uses the cited default).
RecommendationKey resolveKey(List<String> conditions, String disease) {
  final driver = kDiseaseDriver[disease] ?? kDefaultDriver;
  final matched = userCategories(
    conditions,
  ).intersection(kDiseaseCategories[disease] ?? const {});
  for (final category in kCategoryPriority) {
    if (matched.contains(category)) {
      return RecommendationKey(category: category, driver: driver);
    }
  }
  return RecommendationKey(category: null, driver: driver);
}
