import 'package:fyp_foreseeme/features/resources/domain/models/emergency_contact.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';

/// Read interface for the Health Resource Center's static content.
///
/// Content ships with the app (no backend); this abstraction mirrors the other
/// features' repositories and keeps the screen testable with a fake library.
abstract class ResourceRepository {
  /// The curated, sourced self-care guides.
  List<ResourceArticle> articles();

  /// The primary emergency contact for one-tap dialing.
  EmergencyContact emergencyContact();
}
