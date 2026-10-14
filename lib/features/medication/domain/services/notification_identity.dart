import 'dart:convert';

/// A reproducible hash, never Dart's execution-dependent Object.hash.
/// Negative IDs reserve a separate space from the positive risk-alert IDs.
int medicationNotificationId(String key) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(key)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return -1 - (hash & 0x3fffffff);
}

String medicationEventKey(
  String uid,
  String kind,
  String event,
  String slot,
  String occurrence,
) => jsonEncode([uid, kind, event, slot, occurrence]);
