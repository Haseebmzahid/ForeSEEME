import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';

/// Admin-only write path for the Resource Center's article library
/// (Sprint M8.3, SDS FR8.3). Kept separate from the read-only
/// [ResourceRepository] — mirrors the risk feature's split between
/// [RiskRepository] (read) and [RiskOverrideRepository] (admin write) — since
/// only the admin surface ever writes here; every other consumer only reads.
///
/// Enforced server-side by `firestore.rules` to the `admin` claim; a
/// non-admin caller is denied by the rules, not by this interface.
abstract class ResourceContentRepository {
  /// Create or update (upsert by [ResourceArticle.id]) an article. Deliberately
  /// no `deleteArticle` — the SDS's FR8.3 mockup rows only ask for create and
  /// update ("Manage Health Articles", "Publish Content"); this sprint does not
  /// build a delete UI (an operator can still remove a document directly via
  /// the Firebase Console, which the `admin` claim's Firestore write access
  /// already permits — no additional rule is needed for that).
  Future<void> saveArticle(ResourceArticle article);
}
