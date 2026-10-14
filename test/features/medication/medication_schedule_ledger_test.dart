import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fyp_foreseeme/features/medication/data/services/medication_schedule_ledger.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/notification_content.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/notification_identity.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/notification_scheduler.dart';
import 'package:fyp_foreseeme/features/medication/presentation/services/medication_deep_link_router.dart';

class PlatformFake
    implements NotificationScheduler, MedicationNotificationInventory {
  final entries = <int, MedicationPendingNotification>{};
  final times = <int, DateTime>{};
  final cancelled = <int>[];
  int shown = 0;
  @override
  Future<List<MedicationPendingNotification>> pending() async =>
      entries.values.toList();
  @override
  Future<void> cancel(int notificationId) async {
    cancelled.add(notificationId);
    entries.remove(notificationId);
    times.remove(notificationId);
  }

  @override
  Future<void> scheduleDaily({
    required int notificationId,
    required NotificationContent content,
    required DateTime time,
  }) async {
    entries[notificationId] = MedicationPendingNotification(
      notificationId,
      content.payload,
    );
    times[notificationId] = time;
  }

  @override
  Future<void> scheduleOnce({
    required int notificationId,
    required NotificationContent content,
    required DateTime time,
  }) => scheduleDaily(
    notificationId: notificationId,
    content: content,
    time: time,
  );
  @override
  Future<void> showNow({
    required int notificationId,
    required NotificationContent content,
  }) async {
    shown++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late PlatformFake platform;
  late DateTime now;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    platform = PlatformFake();
    now = DateTime(2026, 6, 30, 8);
  });
  MedicationScheduleLedger ledger({
    String uid = 'u1',
    int Function(String)? hash,
  }) => MedicationScheduleLedger(
    preferences: prefs,
    platform: platform,
    inventory: platform,
    uid: uid,
    clock: () => now,
    hash: hash ?? medicationNotificationId,
  );
  NotificationContent content(
    String med,
    String slot, {
    String uid = 'u1',
    String kind = 'primary',
    String occurrence = 'daily',
  }) => NotificationContent(
    category: NotificationCategory.action,
    title: 'unchanged',
    body: 'unchanged',
    payload: 'action',
    identity: medicationEventKey(uid, kind, med, slot, occurrence),
  );
  Future<void> daily(
    MedicationScheduleLedger target,
    String med,
    String slot, {
    String uid = 'u1',
    int hour = 9,
  }) => target.scheduleDaily(
    notificationId: 1,
    content: content(med, slot, uid: uid),
    time: DateTime(2026, 6, 30, hour),
  );

  test(
    'IDs are stable across calls, isolates and separate Dart executions',
    () async {
      final key = medicationEventKey('u1', 'primary', 'm1', '0', 'daily');
      final expected = medicationNotificationId(key);
      expect(medicationNotificationId(key), expected);
      expect(await Isolate.run(() => medicationNotificationId(key)), expected);
      // Run the pure production identity file in two fresh SDK processes.
      final sdk =
          jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
              as Map;
      final flutter = (sdk['packages'] as List).firstWhere(
        (p) => p['name'] == 'flutter',
      );
      final root = Directory.fromUri(
        Uri.parse(flutter['rootUri'] as String),
      ).parent.parent;
      final dart =
          '${root.path}/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}';
      final probe = File(
        '${Directory.systemTemp.path}/foreseeme_identity_${DateTime.now().microsecondsSinceEpoch}.dart',
      );
      final source = File(
        'lib/features/medication/domain/services/notification_identity.dart',
      ).absolute.uri;
      await probe.writeAsString(
        "import '$source'; void main() { print(medicationNotificationId(${jsonEncode(key)})); }",
      );
      try {
        for (var i = 0; i < 2; i++) {
          final result = await Process.run(dart, [probe.path]);
          expect(result.exitCode, 0, reason: '${result.stderr}');
          expect('${result.stdout}'.trim(), '$expected');
        }
      } finally {
        await probe.delete();
      }
    },
  );

  test(
    'simultaneous reminders and categories survive forced collisions',
    () async {
      final target = ledger(hash: (_) => -10);
      await daily(target, 'm1', '0');
      await daily(target, 'm2', '0');
      await target.scheduleOnce(
        notificationId: 1,
        content: content(
          'm1',
          '0',
          kind: 'motivational',
          occurrence: '2026-06-30T09:20:00',
        ),
        time: DateTime(2026, 6, 30, 9, 20),
      );
      await target.reconcile(() => true);
      expect(platform.entries.keys.toSet(), {-10, -11, -12});
    },
  );

  test(
    'restart and repeated reconciliation reuse IDs and replace changed times',
    () async {
      var target = ledger();
      await daily(target, 'm1', '0');
      await target.reconcile(() => true);
      final id = platform.entries.keys.single;
      target = ledger();
      await daily(target, 'm1', '0', hour: 10);
      await target.reconcile(() => true);
      expect(platform.entries.keys, [id]);
      expect(platform.times[id]!.hour, 10);
      platform.entries.clear(); // OS alarm missing but ledger remains.
      await target.reconcile(() => true);
      expect(platform.entries.keys, [id]);
    },
  );

  test(
    'slot reduction, archive and deletion remove every obsolete owned alarm',
    () async {
      var target = ledger();
      await daily(target, 'm1', '0');
      await daily(target, 'm1', '1');
      await target.reconcile(() => true);
      target = ledger();
      await daily(target, 'm1', '0');
      await target.reconcile(() => true);
      expect(platform.entries, hasLength(1));
      await target.cancelMedication('m1');
      expect(platform.entries, isEmpty);
      target = ledger();
      await daily(target, 'm2', '0');
      await target.reconcile(() => true);
      await ledger().reconcile(() => true);
      expect(platform.entries, isEmpty);
    },
  );

  test('startup/resume prunes expired one-offs and never catches up', () async {
    var target = ledger();
    await target.scheduleOnce(
      notificationId: 1,
      content: content('m1', '0', kind: 'recovery', occurrence: 'today'),
      time: DateTime(2026, 6, 30, 9, 45),
    );
    await target.reconcile(() => true);
    now = DateTime(2026, 7, 10, 12);
    target = ledger();
    await target.pruneExpiredAndLegacy();
    await target.scheduleOnce(
      notificationId: 1,
      content: content('m1', '0', kind: 'recovery', occurrence: 'today'),
      time: DateTime(2026, 6, 30, 9, 45),
    );
    await target.reconcile(() => true);
    expect(platform.entries, isEmpty);
    expect(platform.shown, 0);
    await daily(target, 'm1', '0');
    await target.reconcile(() => true);
    expect(platform.times.values.single, DateTime(2026, 7, 11, 9));
  });

  test(
    'legacy migration preserves unrelated payloads and other users',
    () async {
      platform.entries[100] = const MedicationPendingNotification(
        100,
        'action',
      );
      platform.entries[101] = const MedicationPendingNotification(
        101,
        '/risk-details',
      );
      platform.entries[102] = const MedicationPendingNotification(
        102,
        'unrelated',
      );
      final other = ledger(uid: 'u2');
      await daily(other, 'm1', '0', uid: 'u2');
      await other.reconcile(() => true);
      final otherId = platform.entries.keys.firstWhere((id) => id < 0);
      final target = ledger();
      await target.pruneExpiredAndLegacy();
      await target.reconcile(() => true);
      expect(platform.cancelled, contains(100));
      expect(platform.entries.keys.toSet(), {101, 102, otherId});
    },
  );

  test(
    'new refresh invalidates older reads and queue recovers from failures',
    () async {
      final queue = MedicationRefreshQueue();
      final gate = Completer<void>();
      final started = Completer<void>();
      final commits = <String>[];
      final first = queue.run((current) async {
        started.complete();
        await gate.future;
        if (current()) commits.add('old');
      });
      await started.future;
      final second = queue.run((current) async {
        if (current()) commits.add('new');
      });
      gate.complete();
      await Future.wait([first, second]);
      expect(commits, ['new']);
      await expectLater(
        queue.run((_) async => throw StateError('test')),
        throwsStateError,
      );
      await queue.run((_) async {
        commits.add('recovered');
      });
      expect(commits.last, 'recovered');
    },
  );

  test(
    'mission claims suppress concurrent duplicates and survive restart per user',
    () async {
      final claims = MissionCelebrationClaims(prefs);
      final results = await Future.wait(
        List.generate(8, (_) => claims.claim('u1', now)),
      );
      expect(results.where((v) => v), hasLength(1));
      expect(await MissionCelebrationClaims(prefs).claim('u1', now), false);
      expect(await claims.claim('u2', now), true);
      expect(await claims.claim('u1', now.add(const Duration(days: 1))), true);
    },
  );

  test(
    'legacy mission suppression is retained without deleting old data',
    () async {
      await prefs.setString(MissionCelebrationClaims.legacyKey, '2026-6-30');
      expect(await MissionCelebrationClaims(prefs).claim('u1', now), false);
      expect(prefs.getString(MissionCelebrationClaims.legacyKey), '2026-6-30');
    },
  );

  test(
    'lost ledger adopts owned pending identity and cancels extra copies',
    () async {
      var target = ledger();
      await daily(target, 'm1', '0');
      await target.reconcile(() => true);
      final original = platform.entries.values.single;
      platform.entries[-123] = MedicationPendingNotification(
        -123,
        original.payload,
      );
      await prefs.remove(MedicationScheduleLedger.storageKey);
      target = ledger();
      await daily(target, 'm1', '0');
      await target.reconcile(() => true);
      expect(platform.entries.keys, [original.id]);
      expect(platform.cancelled, contains(-123));
    },
  );

  test(
    'immediate IDs are persisted, serialized and disjoint from scheduled IDs',
    () async {
      final ids = await Future.wait(
        List.generate(
          8,
          (_) => MedicationImmediateIds.allocate(prefs, 'u1:mission:2026-6-30'),
        ),
      );
      expect(ids.toSet(), hasLength(1));
      expect(ids.first, lessThan(-0x40000000));
      expect(
        await MedicationImmediateIds.allocate(prefs, 'u1:mission:2026-6-30'),
        ids.first,
      );
      expect(
        await MedicationImmediateIds.allocate(prefs, 'u1:milestone:7'),
        isNot(ids.first),
      );
    },
  );

  test(
    'owned payload routes unchanged category and malformed payload is safe',
    () async {
      final target = ledger();
      await daily(target, 'm1', '0');
      await target.reconcile(() => true);
      expect(
        MedicationDeepLinkRouter.resolve(
          platform.entries.values.single.payload,
        ),
        '/check-in',
      );
      expect(MedicationDeepLinkRouter.resolve('{broken'), '/home');
    },
  );
}
