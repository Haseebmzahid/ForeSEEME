/// A received push message, reduced to what in-app handling needs.
///
/// SDK-free (no firebase_messaging type leaks into presentation). [data] is the
/// engine's payload (`type`, `deepLink`, `category`, `city`, `riskLevel`,
/// `riskEstimateId`); [title]/[body] come from the notification.
class IncomingAlert {
  final Map<String, String> data;
  final String? title;
  final String? body;
  final String? messageId;

  const IncomingAlert({
    required this.data,
    this.title,
    this.body,
    this.messageId,
  });
}
