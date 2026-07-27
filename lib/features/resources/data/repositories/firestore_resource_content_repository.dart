import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/domain/repositories/resource_content_repository.dart';

/// Firestore implementation of [ResourceContentRepository].
///
/// Writes the same `articles` collection [FirestoreResourceRepository] reads,
/// keyed by [ResourceArticle.id] (a title-derived slug assigned once at
/// creation — see `AdminArticleFormController` — and never changed by an
/// edit, so bookmarks and deep links to an article stay valid across edits).
class FirestoreResourceContentRepository implements ResourceContentRepository {
  final FirebaseFirestore _firestore;

  FirestoreResourceContentRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collectionPath = 'articles';

  @override
  Future<void> saveArticle(ResourceArticle article) async {
    await _firestore
        .collection(collectionPath)
        .doc(article.id)
        .set(article.toJson());
  }
}
