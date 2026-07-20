import 'package:share_plus/share_plus.dart';

/// Thin abstraction over the platform share sheet.
///
/// Mirrors [LauncherService]: keeps `share_plus` out of the presentation
/// layer (GOLDEN_RULES #1) so widgets watch a provider of this interface and
/// tests can substitute a fake to assert the exact shared text.
abstract class ShareService {
  /// Opens the platform share sheet with [text] (and an optional [subject],
  /// used as the email subject line on platforms that fall back to email).
  Future<void> shareText(String text, {String? subject});
}

/// Production [ShareService] backed by `share_plus`.
class SharePlusShareService implements ShareService {
  const SharePlusShareService();

  @override
  Future<void> shareText(String text, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }
}
