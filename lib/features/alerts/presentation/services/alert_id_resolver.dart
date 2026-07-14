/// Reconstructs a `userAlerts` document id from an inbound FCM payload
/// (Sprint 6A, Milestone S6A-01).
///
/// The backend's dispatch engine derives the frozen idempotency key
/// `{uid}__{riskEstimateId}__{category}` (`dispatch_alerts.dispatch_key`) and
/// writes the inbox document under that exact id (`write_user_alert`). The same
/// `riskEstimateId`/`category` values are marshalled verbatim into the FCM
/// `data` payload (`alerting/messaging.build_notification`), so the id is
/// losslessly reconstructable client-side — no extra Firestore read is needed
/// to find "which alert was this push about".
///
/// Pure `data → id?` mapping, mirroring [AlertDeepLinkRouter]: no Firebase, no
/// side effects, fully unit-testable. Returns `null` when the payload lacks the
/// fields needed to build the key, so a caller can no-op rather than write to a
/// guessed id.
class AlertIdResolver {
  AlertIdResolver._();

  /// Resolves the `userAlerts/{uid}/items/{id}` document id for the owner
  /// [uid] from a push payload's [data], or `null` if [data] doesn't carry a
  /// resolvable `riskEstimateId`/`category` pair.
  static String? resolve(Map<String, String> data, {required String uid}) {
    final riskEstimateId = data['riskEstimateId'];
    final category = data['category'];
    if (riskEstimateId == null || riskEstimateId.isEmpty) return null;
    if (category == null || category.isEmpty) return null;
    return '${uid}__${riskEstimateId}__$category';
  }
}
