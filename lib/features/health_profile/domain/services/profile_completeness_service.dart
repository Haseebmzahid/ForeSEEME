/// How complete a user's ForeSeeMe profile is.
///
/// The Profile Hub prototype (`docs/Design/ForeSeeMe Profile Hub (1).html`)
/// shows a completeness ring, a `% READY` chip and a three-row breakdown. No
/// such figure existed in the app, and the prototype's own numbers are design
/// placeholders — so rather than display an invented value this service derives
/// one from facts the app already stores.
///
/// Every check below is a **real, verifiable property of stored data**. Nothing
/// is estimated, weighted by guesswork, or padded to make the ring look fuller.
/// A check is either satisfied by data on file or it is not.
///
/// Pure Dart by Golden Rule 2 — no Flutter, no Firebase, no Riverpod. The
/// presentation layer feeds it values it already watches and renders the result.
library;

/// One named group of checks, drawn as a labelled row in the expanded card.
class ProfileCompletenessComponent {
  const ProfileCompletenessComponent({
    required this.label,
    required this.satisfied,
    required this.total,
  });

  /// Row label, e.g. `Conditions`.
  final String label;

  /// How many of this component's checks are satisfied by stored data.
  final int satisfied;

  /// How many checks the component contains. Always > 0.
  final int total;

  /// 0–100, rounded. The row's track fill and trailing figure.
  int get percent => total == 0 ? 0 : ((satisfied / total) * 100).round();

  /// Whether every check in this component is satisfied.
  bool get isComplete => satisfied >= total;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileCompletenessComponent &&
          other.label == label &&
          other.satisfied == satisfied &&
          other.total == total;

  @override
  int get hashCode => Object.hash(label, satisfied, total);

  @override
  String toString() =>
      'ProfileCompletenessComponent($label, $satisfied/$total)';
}

/// The overall score plus the components it was built from.
class ProfileCompleteness {
  const ProfileCompleteness({required this.components});

  /// Ordered as the card renders them.
  final List<ProfileCompletenessComponent> components;

  /// Nothing on file at all — every check unsatisfied.
  bool get isEmpty => components.every((c) => c.satisfied == 0);

  /// 0–100, rounded. Weighted by **check count**, not by component, so a
  /// component with more checks contributes proportionally more. This is the
  /// number the ring arc, the `% READY` chip and the card figure all show.
  int get percent {
    final total = components.fold<int>(0, (sum, c) => sum + c.total);
    if (total == 0) return 0;
    final satisfied = components.fold<int>(0, (sum, c) => sum + c.satisfied);
    return ((satisfied / total) * 100).round();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileCompleteness &&
          _listEquals(other.components, components);

  @override
  int get hashCode => Object.hashAll(components);

  static bool _listEquals(
    List<ProfileCompletenessComponent> a,
    List<ProfileCompletenessComponent> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'ProfileCompleteness($percent%, $components)';
}

/// Scores a profile from data the app already holds.
///
/// The three components mirror the prototype's three breakdown rows. Their
/// *checks* are this app's, not the prototype's: the prototype listed
/// "Allergies", which ForeSeeMe does not model at all, so that row is carried by
/// a component the app can actually answer for.
class ProfileCompletenessService {
  const ProfileCompletenessService();

  /// Builds the score.
  ///
  /// [hasProfile] is whether a health-profile document exists at all; when it
  /// is false the health component reads zero regardless of the other
  /// arguments, because there is nothing on file to read.
  ///
  /// A caveat worth stating plainly: an **empty** `chronicConditions` list is
  /// indistinguishable from "the user never answered", because the stored
  /// model records only the list itself. The check is therefore
  /// "conditions recorded", and a genuinely condition-free user will sit one
  /// check short. That is an honest limitation of the current contract, not a
  /// judgement about the user's health — closing it would need a new field
  /// (e.g. `conditionsConfirmedAt`), which is out of scope here.
  ProfileCompleteness score({
    required String? displayName,
    required String? photoUrl,
    required bool hasProfile,
    required String? city,
    required List<String> chronicConditions,
    required int activeMedicationCount,
    required int medicationsWithRemindersCount,
  }) {
    bool present(String? value) => value != null && value.trim().isNotEmpty;

    final identity = <bool>[
      present(displayName),
      present(photoUrl),
    ];

    final health = <bool>[
      hasProfile && present(city),
      hasProfile && chronicConditions.isNotEmpty,
    ];

    final medication = <bool>[
      activeMedicationCount > 0,
      medicationsWithRemindersCount > 0,
    ];

    ProfileCompletenessComponent component(String label, List<bool> checks) =>
        ProfileCompletenessComponent(
          label: label,
          satisfied: checks.where((c) => c).length,
          total: checks.length,
        );

    return ProfileCompleteness(
      components: [
        component('Identity', identity),
        component('Conditions', health),
        component('Medications', medication),
      ],
    );
  }
}
