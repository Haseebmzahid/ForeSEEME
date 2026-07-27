import 'package:fyp_foreseeme/features/resources/domain/models/emergency_contact.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';

/// Read interface for the Health Resource Center's article library.
///
/// Until Sprint M8.3 this content shipped statically with the app; it is now
/// Firestore-backed (SDS FR8.3, admin-editable via [ResourceContentRepository])
/// — [articles] is `Future`-returning for that reason, mirroring
/// [RiskRepository]'s one-shot Firestore reads (not a live [Stream]: articles
/// change rarely, on an admin edit, not in real time). [StaticResourceRepository]
/// still implements this interface as a fixed, dependency-free fallback/fixture.
abstract class ResourceRepository {
  /// The curated, sourced self-care guides.
  Future<List<ResourceArticle>> articles();

  /// The primary emergency contact for one-tap dialing.
  EmergencyContact emergencyContact();
}
