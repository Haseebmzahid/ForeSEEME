import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fyp_foreseeme/features/resources/data/repositories/static_resource_repository.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/emergency_contact.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/domain/repositories/resource_repository.dart';

/// The production [ResourceRepository] since Sprint M8.3 (SDS FR8.3): reads
/// the admin-editable `articles` collection so a published edit is genuinely,
/// immediately visible — the point of the CMS.
///
/// **Graceful degradation**: the bundled [StaticResourceRepository] catalogue
/// is the guaranteed baseline. Firestore content replaces it when the
/// collection has documents; otherwise — an unseeded project, *or* a failed
/// read — the bundled catalogue is served.
///
/// Falling back on a read *error* too is a deliberate change (Aug 2026). The
/// original version degraded only on an empty collection and let errors
/// propagate, on the reasoning that a genuine failure should not be masked.
/// In practice that reasoning was wrong for this particular collection, and it
/// is what produced an empty Resource Center reading "0 VERIFIED GUIDES":
/// `resourceArticlesProvider` flattens an `AsyncError` to `const []`, so any
/// denied read, or any cold start offline with nothing cached, wiped the
/// catalogue — every category included — with no error surface to explain it.
///
/// The distinction that matters: `articles` is a **public, read-only,
/// non-personal** library that already ships inside the binary. There is no
/// user data to get wrong and nothing stale to mislead anyone with, so serving
/// the bundled copy is strictly better than serving nothing. Personal or
/// risk-bearing reads (`riskEstimates`, medication, the health profile) keep
/// propagating their errors — this is not a precedent for those.
class FirestoreResourceRepository implements ResourceRepository {
  final FirebaseFirestore? _firestoreOverride;

  const FirestoreResourceRepository({FirebaseFirestore? firestore})
    : _firestoreOverride = firestore;

  /// Resolved lazily, not in the constructor: [emergencyContact] never needs
  /// Firestore at all, so a caller that only reads the (synchronous, always
  /// available) emergency contact — via `emergencyContactProvider`, a plain
  /// `Provider` that isn't error-caught the way a `FutureProvider` is — must
  /// never be forced to touch `FirebaseFirestore.instance` (and fail if
  /// Firebase isn't initialised, e.g. in a widget test that never overrides
  /// this repository) just because it exists on the same class as [articles].
  FirebaseFirestore get _firestore => _firestoreOverride ?? FirebaseFirestore.instance;

  static const String collectionPath = 'articles';

  @override
  EmergencyContact emergencyContact() => kRescue1122;

  @override
  Future<List<ResourceArticle>> articles() async {
    try {
      final snapshot = await _firestore.collection(collectionPath).get();
      if (snapshot.docs.isEmpty) {
        return const StaticResourceRepository().articles();
      }
      return snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.of(doc.data());
        // The CMS stamps creation time in the same field that the
        // verified catalogue uses for the source's publication date.
        final authority = ResourceAuthorityX.fromJson(
          data['authority'] as String?,
        );
        if (data['verified'] != true ||
            !authority.isTrusted ||
            data['lastVerifiedAt'] is! String ||
            DateTime.tryParse(data['lastVerifiedAt'] as String) == null) {
          data.remove('publishedAt');
        }
        return ResourceArticle.fromJson(data, id: doc.id);
      }).toList();
    } on Exception {
      // See the class doc: a reader who cannot reach the live library still
      // gets the trusted catalogue that shipped with the app, rather than a
      // Resource Center with nothing in it.
      return const StaticResourceRepository().articles();
    }
  }
}
