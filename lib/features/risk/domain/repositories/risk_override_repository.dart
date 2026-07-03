import '../models/risk_override.dart';

/// Read + admin-write operations for the manual risk-override safety valve
/// (Sprint 5, Prompt 13).
///
/// Mirrors [RiskRepository]: a pure data interface with no business logic. Reads
/// (`getOverride`) are used by the risk surfaces to overlay an active override;
/// writes (`setOverride`/`clearOverride`) are used only by the guarded admin
/// surface and are enforced server-side by Firestore rules (an `admin` custom
/// claim) — a non-admin caller is denied by the rules, not by this interface.
abstract class RiskOverrideRepository {
  /// The stored override for [city] (`overrides/{city}`), or `null` if none has
  /// ever been written. Callers decide whether it is currently in force via
  /// [RiskOverride.isActive] (which also honours expiry).
  Future<RiskOverride?> getOverride(String city);

  /// Upsert the override for its city (idempotent per city — one active override
  /// per city; a new write supersedes the previous one).
  Future<void> setOverride(RiskOverride override);

  /// Clear the active override for [city] (sets `active = false`, preserving the
  /// record as an audit trail rather than deleting it).
  Future<void> clearOverride(String city);
}
