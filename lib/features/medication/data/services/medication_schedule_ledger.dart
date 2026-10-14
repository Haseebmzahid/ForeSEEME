import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/notification_content.dart';
import '../../domain/services/notification_identity.dart';
import '../../domain/services/notification_scheduler.dart';

class MedicationPendingNotification {
  final int id;
  final String? payload;
  const MedicationPendingNotification(this.id, this.payload);
}

abstract interface class MedicationNotificationInventory {
  Future<List<MedicationPendingNotification>> pending();
}

/// One queue covers read/derive/reconcile, including archive cancellation.
/// A newer request invalidates older reads before they commit platform work.
class MedicationRefreshQueue {
  Future<void> _tail = Future.value();
  int _version = 0;

  Future<void> run(Future<void> Function(bool Function()) work) {
    final version = ++_version;
    final result = _tail.then((_) => work(() => version == _version));
    _tail = result.catchError((Object _) {});
    return result;
  }
}

class MissionCelebrationClaims {
  final SharedPreferences preferences;
  Future<void> _tail = Future.value();
  MissionCelebrationClaims(this.preferences);
  static const legacyKey = 'notif_mission_complete_celebrated_date';

  Future<bool> claim(String uid, DateTime now) {
    final result = _tail.then((_) async {
      final date = '${now.year}-${now.month}-${now.day}';
      final key = '${legacyKey}_$uid';
      final prior =
          preferences.getString(key) ?? preferences.getString(legacyKey);
      if (prior == date) {
        if (!preferences.containsKey(key) &&
            !await preferences.setString(key, date)) {
          throw StateError('Celebration migration failed');
        }
        return false;
      }
      if (!await preferences.setString(key, date)) {
        throw StateError('Celebration claim failed');
      }
      return true;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

/// Immediate celebrations use a disjoint negative range from scheduled alarms.
/// Keep allocations across restarts so two categories can never replace each other.
class MedicationImmediateIds {
  static Future<void> _tail = Future.value();
  static Future<int> allocate(SharedPreferences preferences, String key) {
    final result = _tail.then((_) async {
      const storage = 'medication_immediate_ids_v1';
      final ids =
          jsonDecode(preferences.getString(storage) ?? '{}')
              as Map<String, dynamic>;
      final existing = ids[key] as int?;
      if (existing != null) return existing;
      var id = medicationNotificationId(key) - 0x40000000;
      while (ids.values.contains(id)) {
        id = id == -0x80000000 ? -0x40000001 : id - 1;
      }
      ids[key] = id;
      if (!await preferences.setString(storage, jsonEncode(ids))) {
        throw StateError(
          'Immediate notification identity could not be persisted',
        );
      }
      return id;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

/// Builds a desired schedule without touching Android. Reconciliation owns all
/// platform mutations; persisted allocation resolves even deliberate hash collisions.
class MedicationScheduleLedger implements NotificationScheduler {
  final SharedPreferences preferences;
  final NotificationScheduler platform;
  final MedicationNotificationInventory inventory;
  final String uid;
  final DateTime Function() clock;
  final int Function(String) hash;
  final Map<String, _Request> _desired = {};
  static const storageKey = 'medication_notification_ledger_v1';
  static const legacyCategories = {
    'action',
    'recovery',
    'celebration',
    'reflection',
    'coaching',
  };

  MedicationScheduleLedger({
    required this.preferences,
    required this.platform,
    required this.inventory,
    required this.uid,
    required this.clock,
    this.hash = medicationNotificationId,
  });

  Map<String, dynamic> _read() =>
      jsonDecode(preferences.getString(storageKey) ?? '{}')
          as Map<String, dynamic>;

  Map<String, dynamic>? _ownedPayload(MedicationPendingNotification item) {
    try {
      final data = jsonDecode(item.payload ?? '') as Map<String, dynamic>;
      return data['owner'] == 'medication_v1' && data['uid'] == uid
          ? data
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(Map<String, dynamic> entries) async {
    if (!await preferences.setString(storageKey, jsonEncode(entries))) {
      throw StateError('Medication schedule ledger could not be persisted');
    }
  }

  @override
  Future<void> scheduleDaily({
    required int notificationId,
    required NotificationContent content,
    required DateTime time,
  }) async {
    final now = clock();
    var future = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (!future.isAfter(now)) {
      future = DateTime(
        now.year,
        now.month,
        now.day + 1,
        time.hour,
        time.minute,
      );
    }
    _desired[content.identity ?? '$uid:daily:$notificationId'] = _Request(
      content,
      future,
      true,
    );
  }

  @override
  Future<void> scheduleOnce({
    required int notificationId,
    required NotificationContent content,
    required DateTime time,
  }) async {
    if (time.isAfter(clock())) {
      _desired[content.identity ?? '$uid:once:$notificationId'] = _Request(
        content,
        time,
        false,
      );
    }
  }

  @override
  Future<void> cancel(int notificationId) async {
    // Absence from the complete desired set cancels the prior owned alarm.
  }

  @override
  Future<void> showNow({
    required int notificationId,
    required NotificationContent content,
  }) => platform.showNow(notificationId: notificationId, content: content);

  /// Run before slow Firestore/analytics reads. Legacy category-only payloads
  /// are medication-owned but cannot identify a user; migrate them selectively.
  Future<void> pruneExpiredAndLegacy() async {
    final entries = _read();
    final pending = await inventory.pending();
    for (final item in pending) {
      if (legacyCategories.contains(item.payload)) {
        await platform.cancel(item.id);
      }
      final data = _ownedPayload(item);
      if (data != null &&
          data['daily'] == false &&
          !DateTime.parse(data['time'] as String).isAfter(clock())) {
        await platform.cancel(item.id);
      }
    }
    for (final key in entries.keys.toList()) {
      final entry = entries[key] as Map<String, dynamic>;
      if (entry['uid'] == uid &&
          entry['daily'] == false &&
          !DateTime.parse(entry['time'] as String).isAfter(clock())) {
        await platform.cancel(entry['id'] as int);
        entries.remove(key);
      }
    }
    await _save(entries);
  }

  Future<void> cancelMedication(String medicationId) async {
    final entries = _read();
    for (final item in await inventory.pending()) {
      final data = _ownedPayload(item);
      if (data != null &&
          (jsonDecode(data['identity'] as String) as List)[2] == medicationId) {
        await platform.cancel(item.id);
      }
    }
    for (final key in entries.keys.toList()) {
      final entry = entries[key] as Map<String, dynamic>;
      final identity = jsonDecode(key) as List<dynamic>;
      if (entry['uid'] == uid && identity[2] == medicationId) {
        await platform.cancel(entry['id'] as int);
        entries.remove(key);
      }
    }
    await _save(entries);
  }

  Future<void> reconcile(bool Function() current) async {
    if (!current()) return;
    _desired.removeWhere(
      (_, request) => !request.daily && !request.time.isAfter(clock()),
    );
    final entries = _read();
    final pending = await inventory.pending();
    if (!current()) return;
    for (final item in pending) {
      final data = _ownedPayload(item);
      if (data != null && !_desired.containsKey(data['identity'])) {
        await platform.cancel(item.id);
      } else if (data != null) {
        final key = data['identity'] as String;
        final prior = entries[key];
        if (prior == null) {
          entries[key] = {
            'id': item.id,
            'uid': uid,
            'daily': data['daily'],
            'time': data['time'],
          };
        } else if (prior['id'] != item.id) {
          await platform.cancel(item.id);
        }
      }
    }
    final ownedIds = entries.values.map((e) => e['id'] as int).toSet();
    final occupied = {...ownedIds, ...pending.map((p) => p.id)};
    for (final key in entries.keys.toList()) {
      final entry = entries[key] as Map<String, dynamic>;
      if (entry['uid'] == uid && !_desired.containsKey(key)) {
        await platform.cancel(entry['id'] as int);
        entries.remove(key);
      }
    }
    for (final item in _desired.entries) {
      if (!current()) break;
      final request = item.value;
      if (!request.daily && !request.time.isAfter(clock())) {
        final expiredId = entries[item.key]?['id'] as int?;
        if (expiredId != null) await platform.cancel(expiredId);
        entries.remove(item.key);
        continue;
      }
      final existingId = entries[item.key]?['id'] as int?;
      var id = existingId ?? hash(item.key);
      if (existingId == null) {
        while (occupied.contains(id)) {
          id = id == -0x40000000 ? -1 : id - 1;
        }
        occupied.add(id);
      }
      // Write ahead so interruption/failure cannot leave an unowned alarm.
      entries[item.key] = {
        'id': id,
        'uid': uid,
        'daily': request.daily,
        'time': request.time.toIso8601String(),
      };
      await _save(entries);
      if (!current()) break;
      final content = request.content;
      final wrapped = NotificationContent(
        category: content.category,
        title: content.title,
        body: content.body,
        payload: jsonEncode({
          'owner': 'medication_v1',
          'uid': uid,
          'identity': item.key,
          'category': content.payload,
          'time': request.time.toIso8601String(),
          'daily': request.daily,
        }),
      );
      if (request.daily) {
        await platform.scheduleDaily(
          notificationId: id,
          content: wrapped,
          time: request.time,
        );
      } else {
        await platform.scheduleOnce(
          notificationId: id,
          content: wrapped,
          time: request.time,
        );
      }
    }
    await _save(entries);
  }
}

class _Request {
  final NotificationContent content;
  final DateTime time;
  final bool daily;
  const _Request(this.content, this.time, this.daily);
}
