import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fyp_foreseeme/features/resources/data/repositories/static_resource_repository.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/emergency_contact.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/domain/repositories/resource_repository.dart';

/// The production [ResourceRepository] since Sprint M8.3 (SDS FR8.3): reads
/// the admin-editable `articles` collection so a published edit is genuinely,
/// immediately visible — the point of the CMS.
///
/// **Graceful degradation**: if the collection has never been seeded (zero
/// documents — a fresh/unseeded project, not an error), this falls back to
/// [StaticResourceRepository]'s curated content rather than showing an empty
/// Resource Center. This mirrors the backend's own established precedent
/// (`app/predict.py` falling back to `StubRiskModel` when no model artifact is
/// present) — the same graceful-degradation principle, applied client-side. A
/// genuine read error (e.g. offline with nothing cached) is NOT masked this
/// way; it propagates as an [AsyncError] the same as any other Firestore read
/// failure in this app.
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
    final snapshot = await _firestore.collection(collectionPath).get();
    if (snapshot.docs.isEmpty) {
      return const StaticResourceRepository().articles();
    }
    return snapshot.docs
        .map((doc) => ResourceArticle.fromJson(doc.data(), id: doc.id))
        .toList();
  }
}
