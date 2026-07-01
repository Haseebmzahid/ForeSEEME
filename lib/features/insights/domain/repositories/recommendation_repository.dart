import '../models/health_recommendation.dart';

/// Abstract interface for the verified recommendation content library
/// (Sprint 4, Prompt 6).
///
/// Pure lookup — **no generation** (Rule 11). Mirrors the backend
/// `recommendation_lookup.lookup`: selection is by `(category, driver)` and the
/// lookup is **total** (any key resolves to a row, falling back to the cited
/// default), so a caller never has to handle a null/empty advisory.
abstract class RecommendationRepository {
  /// Returns the cited advisory for `(category, driver)`, or the safe cited
  /// default when no row matches. Never returns null.
  HealthRecommendation lookup(String category, String driver);
}
