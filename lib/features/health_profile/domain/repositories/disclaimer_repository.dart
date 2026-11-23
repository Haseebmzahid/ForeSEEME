/// Increment when the accepted wording changes, and deploy its rules first.
const currentDisclaimerVersion = 'v1';

abstract interface class DisclaimerRepository {
  Future<bool> hasAccepted(String uid, String version);
  Future<void> accept(String uid, String version);
}
