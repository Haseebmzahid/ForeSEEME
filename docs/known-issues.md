# Known Issues & Technical Debt: ForeSeeMe

**Last Updated**: May 6, 2026  
**Total Open Issues**: 12  
**Critical**: 2 | Major: 4 | Minor: 6

## Critical Issues 🔴

### Issue #1: Adherence Status Save Not Persisting

**Status**: In Development  
**Severity**: Critical  
**Impact**: Users cannot confirm medication taken/skipped

**Description**:
When user taps medication status button (taken/skipped), no persistence occurs. State updates UI locally but doesn't save to Firestore.

**Root Cause**:
`AdherenceNotifier.updateStatus()` method incomplete. Missing:
- `FirestoreAdherenceLogRepository.logDose()` call
- Error handling
- UI feedback (loading/success)

**Current Behavior**:
```dart
// DailyCheckInScreen
onStatusTap: (status) {
  // Local state updates, but doesn't save
  ref.read(adherenceProvider.notifier).updateStatus(
    medicationId: med.id,
    status: status,  // taken/skipped
  );
}
```

**Expected Behavior**:
Button press → Save to Firestore → Show confirmation → Update UI

**Workaround**:
None currently. Users see UI update but data lost on app restart.

**Fix Timeline**: 2-3 days  
**Assigned To**: TBD

---

### Issue #2: Notifications Not Scheduled

**Status**: Not Started  
**Severity**: Critical  
**Impact**: Users receive no medication reminders

**Description**:
`LocalNotificationService` initialized but no reminders scheduled when medications added.

**Current Code**:
```dart
// In main.dart
await LocalNotificationService().initialize(); // ✓ Works

// In medication repository
await addMedication(...);  // ✗ No notification scheduled
```

**Missing**:
- `LocalNotificationService.scheduleNotification()`
- Integration on medication add
- Timezone handling
- Permission checks (Android 13+)

**Workaround**:
None. No reminders delivered to users.

**Fix Timeline**: 1-2 days  
**Assigned To**: TBD

---

## Major Issues 🟠

### Issue #3: Pagination Not Implemented for Large Medication Lists

**Status**: Open  
**Severity**: Major  
**Impact**: Performance degradation with 50+ medications

**Description**:
`getMedications()` returns entire list in memory. No pagination or virtualization implemented.

**Reproduction**:
1. Add 100 medications
2. Navigate to medication list
3. Observe 1-2 second delay, high memory usage

**Code**:
```dart
// FirestoreMedicationRepository
Stream<List<MedicationModel>> getMedications(String uid) {
  return _firestore
      .collection('users')
      .doc(uid)
      .collection('medications')
      .snapshots()  // ✗ No limit/pagination
      .map((snapshot) => snapshot.docs
          .map((doc) => MedicationModel.fromJson(doc.data()))
          .toList());
}
```

**Fix Options**:
1. Add `.limit(20)` for pagination
2. Implement ListView.builder with FutureBuilder
3. Use Riverpod AsyncValue for pagination state

**Estimated Impact**: Memory reduced 80%, load time <200ms  
**Priority**: Medium (low user medication count expected)

---

### Issue #4: No Error Recovery for Failed Firestore Operations

**Status**: Open  
**Severity**: Major  
**Impact**: Silent failures, users unaware of data not saved

**Description**:
When Firestore operations fail, errors logged but no user-facing recovery options.

**Example**:
```dart
// Current: Just throws
await repository.logDose(...);

// Needed: Show retry option
try {
  await repository.logDose(...);
} catch (e) {
  showErrorSnackBar(
    title: 'Failed to save',
    action: TextButton(label: 'Retry', onPressed: retry),
  );
}
```

**Impact Areas**:
- Medication add fails silently
- Adherence log fails silently
- Health profile save fails silently

**Fix**: Add error UI patterns to all mutation operations

---

### Issue #5: No Offline Support

**Status**: Open  
**Severity**: Major  
**Impact**: App cannot be used without internet

**Description**:
Real-time Firestore streams fail without internet. No local caching implemented.

**Current Behavior**:
```
User offline → Stream errors → App shows no data
```

**Required for Production**:
- Cache medication list locally
- Queue adherence logs while offline
- Sync when reconnected

**Estimated Effort**: 3-5 days  
**Priority**: Medium (MVP can assume connectivity)

---

### Issue #6: No Input Validation on Medication Reminders

**Status**: Open  
**Severity**: Major  
**Impact**: Invalid reminder times accepted

**Description**:
User can enter invalid times (e.g., 25:00, negative values) due to missing validation.

**Missing Validation**:
- Time format check
- Duplicate time check
- Time range (00:00 - 23:59)
- Maximum reminders per day (e.g., 5)

**Current Code**:
```dart
// MedicationFormScreen
final reminderTimes = <String>[];  // ✗ No validation
```

**Fix**: Add FormFieldValidator to time input

---

## Minor Issues 🟡

### Issue #7: Missing Loading State on Check-In Screen

**Status**: Open  
**Severity**: Minor  
**Impact**: Unclear if button press worked

**Description**:
No loading indicator while saving dose status. User unsure if tap registered.

**Fix**: Add CircularProgressIndicator on button while saving

---

### Issue #8: Home Screen Placeholder

**Status**: Open  
**Severity**: Minor  
**Impact**: Confusing UX after login

**Description**:
Post-login screen shows "Home" text. Needs proper dashboard.

**Requires**:
- Summary stats (adherence %)
- Next medications
- Quick navigation

---

### Issue #9: No User Logout Confirmation

**Status**: Open  
**Severity**: Minor  
**Impact**: Accidental logouts possible

**Description**:
Logout button doesn't confirm. User may tap accidentally.

**Fix**: Show confirmation dialog before logout

---

### Issue #10: Adherence History Not Viewable

**Status**: Open  
**Severity**: Minor  
**Impact**: Users cannot see past adherence

**Description**:
No screen to view adherence history. Only current day shown.

**Planned Screen**: AdherenceHistoryScreen with calendar picker

---

### Issue #11: Medication Edit Screen Not Implemented

**Status**: Open  
**Severity**: Minor  
**Impact**: Cannot modify medication details

**Description**:
Can add and delete, but not edit existing medications.

**Planned Screens**:
- Edit name, dosage, frequency
- Modify reminder times
- Reactivate deactivated medications

---

### Issue #12: No Analytics or Crash Reporting

**Status**: Open  
**Severity**: Minor  
**Impact**: Cannot diagnose production issues

**Description**:
Firebase Crashlytics and Analytics not configured.

**Setup Needed**:
```bash
flutterfire configure  # Enable Crashlytics
```

---

## Technical Debt 📋

### Debt Item #1: Zero Test Coverage

**Current**: 0% code coverage  
**Target**: 60%+ for critical paths

**Needed**:
- Unit tests: auth, repositories, notifiers
- Widget tests: key screens
- Integration tests: end-to-end flows

**Estimated Effort**: 2-3 weeks

---

### Debt Item #2: No CI/CD Pipeline

**Current**: Manual build/test  
**Target**: Automated GitHub Actions

**Missing**:
- Automated testing on PR
- Automated builds on merge
- Automated release on tag

---

### Debt Item #3: Database Migration Strategy

**Current**: Ad-hoc schema changes  
**Target**: Documented migration process

**Needed**:
- Versioning system
- Backward compatibility handling
- Data migration scripts

---

## Security Issues ⚠️

### Potential: Firebase Security Rules Not Validated

**Status**: Under Review  
**Severity**: Medium

**Description**:
Security rules implemented but not penetration tested.

**Recommended**:
- Run Firebase Emulator Suite locally
- Test unauthorized access scenarios
- Audit rule logic quarterly

---

## Performance Issues ⚡

### Potential: Slow Firestore Queries

**Status**: Not Measured

**Description**:
No query performance metrics collected.

**Needed**:
- Add Firestore profiling
- Monitor query latencies
- Optimize indexes if needed

---

## Accessibility Issues ♿

### Partial: Limited Accessibility Features

**Status**: Partial  
**Current**: Basic semantic labels on buttons

**Missing**:
- Screen reader descriptions
- High contrast mode support
- Text scaling support
- Keyboard navigation

---

## Browser/Platform Issues

### Android Specific

**Issue**: Permission handling for Android 13+ notifications
- Needed: Runtime permission request
- Current: No permission check

**Issue**: App crashes on Android 10 due to file access
- Status: Not reproduced yet
- Workaround: None

---

### iOS Specific

**Issue**: Build warning: "Target 'Runner' has frameworks with missing linker inputs"
- Severity: Low
- Status: Non-critical, builds successfully

**Issue**: LocalNotifications not vibrating on iOS
- Severity: Minor
- Workaround: Sound-only notifications

---

## Environment-Specific Issues

### Development

- Flutter 3.10.0 required (not earlier versions)
- Dart Analysis occasionally hangs on first load

### Testing

- Emulator performance degradation with many medications
- Firebase Emulator not properly syncing times

### Production

- Not yet deployed, will monitor after release

---

## Reporting New Issues

**Format**:
```
Title: [Component] Brief description
Status: Open/In Progress/Closed
Severity: Critical/Major/Minor
Description: Detailed explanation
Reproduction: Steps to reproduce
Expected: What should happen
Actual: What happens instead
Workaround: If available
Fix: Proposed solution
Timeline: Estimated fix time
```

**Report To**: GitHub Issues (future) or project Slack channel

---

## Resolution Timeline

| Issue | Est. Fix | Priority |
|-------|----------|----------|
| #1 Adherence Save | 3 days | P0 (Critical) |
| #2 Notifications | 2 days | P0 (Critical) |
| #3 Pagination | 3 days | P1 (High) |
| #4 Error Recovery | 4 days | P1 (High) |
| #5 Offline Support | 1 week | P2 (Medium) |
| Others | 2-3 days | P2-P3 |

**Target**: All P0 issues resolved before release candidate.
