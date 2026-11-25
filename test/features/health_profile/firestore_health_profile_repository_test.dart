import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/features/health_profile/data/repositories/firestore_health_profile_repository.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/constants/conditions_constants.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/models/health_profile_model.dart';

void main() {
  test('legacy profiles and missing fields remain readable', () {
    final profile = HealthProfileModel.fromJson('fixture', {'city': 'Lahore'});
    expect(profile.city, 'Lahore');
    expect(profile.chronicConditions, isEmpty);
    expect(profile.customConditions, isEmpty);
  });

  test('normalized custom labels reject duplicates and predefined choices', () {
    final label = normalizeCustomCondition('  Sleep\t  apnea  ');
    expect(label, 'Sleep apnea');
    expect(validateCustomCondition(label, []), isNull);
    expect(validateCustomCondition(label, ['sleep apnea']), isNotNull);
    expect(validateCustomCondition('ASTHMA', []), isNotNull);
    expect(validateCustomCondition('', []), isNotNull);
    expect(validateCustomCondition('a' * 65, []), isNotNull);
  });

  test('save and edit preserve parent preferences and unrelated profile fields', () async {
    final firestore = FakeFirebaseFirestore();
    final repository = FirestoreHealthProfileRepository(firestore: firestore);
    final parent = firestore.doc('users/fixture');
    await parent.set({'notificationPreferences': {'lowRiskUpdates': true}});
    final document = firestore.doc('users/fixture/profile/fixture');
    await document.set({'legacyField': 'preserve'});
    final saved = await repository.saveProfile(HealthProfileModel(
      uid: 'fixture',
      city: 'Lahore',
      chronicConditions: const ['Asthma', 'Diabetes'],
      customConditions: const ['Custom label'],
      lastUpdated: DateTime.utc(2026),
    ));
    saved.fold((error) => throw error, (_) {});

    final updated = await repository.updateProfile('fixture', city: 'Karachi');
    updated.fold((error) => throw error, (_) {});
    final reopened = FirestoreHealthProfileRepository(firestore: firestore);
    final persisted = (await reopened.getProfile('fixture')).fold(
      (error) => throw error, (profile) => profile!,
    );
    expect(persisted.city, 'Karachi');
    expect(persisted.chronicConditions, ['Asthma', 'Diabetes']);
    expect(persisted.customConditions, ['Custom label']);
    expect((await document.get()).data()?['legacyField'], 'preserve');
    expect((await parent.get()).data()?['notificationPreferences'], {'lowRiskUpdates': true});

    final cleared = await reopened.updateProfile(
      'fixture', conditions: [], customConditions: [],
    );
    cleared.fold((error) => throw error, (_) {});
    expect((await document.get()).data()?['chronicConditions'], isEmpty);
    expect((await document.get()).data()?['customConditions'], isEmpty);
  });
}
