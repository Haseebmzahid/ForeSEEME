import 'package:cloud_firestore/cloud_firestore.dart';

class ArticleBookmarks {
  const ArticleBookmarks({
    this.ids = const {},
    this.pending = false,
    this.cached = false,
  });

  final Set<String> ids;
  final bool pending;
  final bool cached;
}

class FirestoreArticleBookmarks {
  const FirestoreArticleBookmarks(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      _firestore
          .collection('users')
          .doc(uid)
          .collection('profile')
          .doc(uid)
          .collection('bookmarks');

  Stream<ArticleBookmarks> watch(String uid) => _collection(uid)
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => ArticleBookmarks(
          ids: Set.unmodifiable(snapshot.docs.map((doc) => doc.id)),
          pending: snapshot.metadata.hasPendingWrites,
          cached: snapshot.metadata.isFromCache,
        ),
      );

  Future<void> setSaved(
    String uid,
    String articleId, {
    required bool saved,
  }) {
    final bookmark = _collection(uid).doc(articleId);
    return saved
        ? bookmark.set({
            'articleId': articleId,
            'savedAt': FieldValue.serverTimestamp(),
          })
        : bookmark.delete();
  }
}
