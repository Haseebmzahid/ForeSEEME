# Business Logic: ForeSeeMe

## Core Domain Model

### Entities & Relationships

```
User (Firebase Auth)
  ├── uid (unique identifier)
  ├── email
  └── displayName

HealthProfile
  ├── uid (belongs to User)
  ├── city
  └── chronicConditions[]

Medication
  ├── id (auto-generated)
  ├── uid (belongs to User)
  ├── name
  ├── dosage
  ├── type (enum: pill, syrup)
  ├── frequency (enum: onceDaily, twiceDaily, thriceDaily)
  ├── reminderTimes[] (HH:mm format)
  └── isActive (soft delete flag)

AdherenceLog
  ├── id (deterministic: {medId}_{date}_{time})
  ├── uid (belongs to User)
  ├── medicationId (references Medication)
  ├── date (YYYY-MM-DD)
  ├── status (enum: pending, taken, skipped)
  └── confirmedAt (timestamp of user confirmation)
```

## Feature: Medication Management

### Workflow 1: Add New Medication

**Preconditions:**
- User authenticated
- Health profile completed

**Steps:**
1. User navigates to "Add Medication"
2. Fills form:
   - Medication name
   - Dosage (e.g., "500mg")
   - Type: pill or syrup
   - Frequency: once/twice/thrice daily
   - Reminder times (matches frequency):
     - Once daily: 1 time (e.g., 08:00)
     - Twice daily: 2 times (e.g., 08:00, 20:00)
     - Thrice daily: 3 times (e.g., 08:00, 14:00, 20:00)
3. Validates:
   - Name not empty
   - Dosage valid format
   - Reminder times in ascending order
   - Reminder times valid (00:00-23:59)
4. Creates MedicationModel
5. Saves to Firestore: `users/{uid}/medications/{autoId}`
6. Returns to medication list
7. Real-time stream updates show new medication

**Postconditions:**
- Medication visible in daily check-in
- Notifications scheduled for reminder times
- Medication active by default

### Workflow 2: View Medications

**Preconditions:**
- User authenticated

**Steps:**
1. Open Daily Check-In Screen
2. Stream watches `medicationsStreamProvider` for active medications
3. Filter: `where(isActive == true)`
4. Display grouped by time of day:
   - Morning: 6:00-11:59
   - Afternoon: 12:00-16:59
   - Evening: 17:00-23:59
5. For each medication, fetch today's adherence log
6. Show status badge:
   - Pending: Not yet taken/skipped
   - Taken: User confirmed taken
   - Skipped: User confirmed skipped
7. Show action buttons (active dates only)

**Real-time Behavior:**
- When medication added: appears immediately
- When medication deactivated: disappears from list
- When adherence status changes: badge updates

### Workflow 3: Deactivate Medication

**Preconditions:**
- Medication exists
- User owns medication

**Steps:**
1. User selects medication (menu or long-press)
2. Taps "Deactivate" or "Stop Taking"
3. Confirmation dialog
4. Calls `FirestoreMedicationRepository.deactivateMedication()`
5. Sets `isActive = false` in Firestore
6. (NOT deleted - historical data preserved for adherence analysis)
7. Medication removed from active list
8. Adherence logs retained (for reports)

**Rationale:**
- Soft delete preserves historical adherence data
- Users can't accidentally lose medication history
- Future reports can show "medications I've taken" across time

## Feature: Daily Check-In (Adherence Tracking)

### Workflow 1: View Today's Doses

**Preconditions:**
- User authenticated
- User has active medications

**Steps:**
1. Open Daily Check-In Screen
2. Default to today's date
3. Fetch active medications (stream)
4. For each medication:
   - For each reminderTime:
     - Create "dose" = (medication, time, status)
5. Group doses by time slot (morning/afternoon/evening)
6. Fetch adherence logs for today: `where(date == today)`
7. Match logs to doses by medicationId + time
8. Determine status:
   - If log exists: use log.status
   - If no log: status = pending
9. Display:
   - Morning section (if has doses)
   - Afternoon section (if has doses)
   - Evening section (if has doses)
   - Empty state (if no medications)

### Workflow 2: Mark Dose as Taken

**Preconditions:**
- Today's date (or future date if allowed by business rules)
- Dose in pending status
- Medication exists in Firestore

**Steps:**
1. User taps "Taken" button on medication card
2. Validation:
   - Is date in past? Block update (read-only)
   - Is medication still active? Verify
   - Is dose already taken/skipped? Allow toggle
3. Generate deterministic log ID:
   ```
   logId = "{medId}_{YYYY-MM-DD}_{HHmm}"
   // Example: "med123_2025-05-02_0800"
   ```
4. Create AdherenceLogModel:
   - id: logId
   - medicationId: medId
   - uid: userId
   - date: dateOnly (YYYY-MM-DD)
   - status: "taken"
   - confirmedAt: DateTime.now()
5. Upsert to Firestore (deterministic ID enables overwrite)
6. Firestore write: `users/{uid}/adherence_logs/{logId}`
7. Stream re-emits with new log
8. UI updates badge to "Taken" (green)
9. Show success toast

**Side Effects:**
- Local notification dismissed (if shown)
- Adherence streak counter incremented

### Workflow 3: Mark Dose as Skipped

**Similar to "Mark as Taken"**
- Status: "skipped"
- Badge: orange/pending color
- Streak: NOT incremented

### Workflow 4: Toggle Status (Past Date)

**Preconditions:**
- Date is NOT in past (business rule check)
- Can toggle between taken/skipped/pending

**Steps:**
1. User taps status badge (current/future dates only)
2. Show option menu: Taken, Skipped, Pending
3. User selects new status
4. Generate same logId
5. Update status in Firestore
6. If status == "pending": DELETE the adherence log (null confirmedAt)
7. Stream updates UI

### Workflow 5: Navigate Dates

**Preconditions:**
- None

**Steps:**
1. See date navigation bar (15 date chips)
2. Chips show: date + weekday abbreviation
3. Current date highlighted (blue background)
4. Past dates: clickable (read-only display)
5. Future dates: clickable (editable doses)
6. Tap date chip:
   - Updates selected date
   - Re-queries adherence logs for new date
   - Displays doses for that date
7. Auto-scroll: Today is centered in view

**Business Rules:**
- Can view past dates (analysis, history)
- Can edit future dates (pre-plan adherence)
- Cannot edit past dates (immutable history)

## Feature: Health Profile

### Workflow 1: Setup Profile (Onboarding)

**Preconditions:**
- User just registered
- User has NOT yet completed health profile
- Router redirects to `/health-profile?isEditMode=false`

**Steps:**
1. Display HealthProfileScreen (setup mode)
2. Title: "Let's Set Up Your Profile"
3. Show form:
   - City dropdown (preset: Lahore, Islamabad, Karachi, Rawalpindi, Peshawar)
   - Chronic conditions multi-select checkboxes
     (e.g., Diabetes, Hypertension, Asthma, etc.)
4. Validation:
   - City must be selected
   - At least one condition must be selected
5. User taps "Continue"
6. Call `HealthProfileNotifier.saveProfile()`
7. Creates HealthProfileModel:
   - uid: userId
   - city: selectedCity
   - chronicConditions: selectedConditions[]
   - lastUpdated: serverTimestamp
8. Save to Firestore: `users/{uid}/profile/data`
9. Router redirects to `/home`
10. User can now use app

**Postconditions:**
- Profile stored in Firestore
- Data used for future air quality feature
- Can be edited from settings

### Workflow 2: Edit Profile (Settings)

**Preconditions:**
- User authenticated
- User navigates to Settings → Edit Profile
- Router passes `extra: {isEditMode: true}`

**Steps:**
1. HealthProfileScreen loads in edit mode
2. Pre-populate form:
   - City: current city
   - Conditions: currently selected conditions (checked)
3. Title: "Edit Your Profile"
4. User modifies fields
5. Taps "Save"
6. Same validation rules
7. Call `HealthProfileNotifier.updateProfile()`
8. Calls repository.updateProfile() with merge: true
9. Firestore partial update (only changed fields updated)
10. lastUpdated updated to serverTimestamp
11. Router pops back to settings
12. Success toast shown

## Feature: Local Notifications (Reminders)

### Workflow 1: Schedule Medication Reminders

**When:**
- After medication added
- On app startup (for today's medications)

**Steps:**
1. Get active medications
2. For each medication:
   - For each reminderTime:
     - Calculate next occurrence:
       - If time not yet passed today: schedule today
       - Else: schedule tomorrow
     - Create notification:
       - Title: "{medicationName} time"
       - Body: "Take {dosage} of {name}"
       - Payload: {medicationId, time}
3. Schedule timezone-aware notification
4. Show notification at exact reminder time

**Example:**
```
Medication: Metformin 500mg
Reminder times: [08:00, 20:00]
Today: 2025-05-02 (current time 07:30)

Schedule 1: 2025-05-02 08:00 → Notify now + 30min
Schedule 2: 2025-05-02 20:00 → Notify in 12.5 hours
Next day: 2025-05-03 08:00 → Notify tomorrow 8:00
```

### Workflow 2: User Taps Notification

**Steps:**
1. User receives notification at reminder time
2. User taps notification
3. App opens (or brought to foreground)
4. Navigate to Daily Check-In Screen
5. Auto-select today's date
6. Scroll to medication that was reminded
7. User can immediately mark taken/skipped

## Feature: Adherence Insights (Future)

### Planned Workflows

1. **View Adherence Summary**
   - This week: % of doses taken
   - This month: % of doses taken
   - Trends: improvement/decline

2. **Adherence Streak**
   - Consecutive days with all doses taken
   - Motivational badge at milestone (7 days, 30 days)

3. **Export Adherence Report**
   - PDF with medication list + adherence %
   - Sharable with doctor/healthcare provider

## Business Rules & Constraints

### Medication Rules

1. **Reminder Time Validation**
   - Must be valid 24-hour format: HH:mm (00:00-23:59)
   - Must be unique within medication
   - Must be in ascending order
   - Count must match frequency.expectedReminderCount

2. **Soft Delete Policy**
   - Never permanently delete medications
   - Only set isActive = false
   - Preserves adherence history for analysis

3. **Frequency Constraints**
   - onceDaily: 1 reminder time
   - twiceDaily: 2 reminder times
   - thriceDaily: 3 reminder times

### Adherence Rules

1. **Date-only Logs**
   - Adherence logs stored by date only (YYYY-MM-DD)
   - Enables efficient date-range queries
   - Prevents timezone issues

2. **Deterministic Log IDs**
   - Format: {medId}_{date}_{time}
   - Prevents duplicates for same dose
   - Enables upsert semantics

3. **Past Date Immutability**
   - Past dates: read-only (view only)
   - Current date: editable
   - Future dates: editable

4. **Status Transitions**
   - pending → taken (mark taken)
   - pending → skipped (mark skipped)
   - taken ← → skipped (toggle)
   - any → pending (delete log)

### Health Profile Rules

1. **Single Profile Per User**
   - One document: `users/{uid}/profile/data`
   - No multiple profiles

2. **City Selection**
   - Must be from preset list
   - Currently: Pakistani cities (air quality context)
   - Future: expand to other regions

3. **Chronic Conditions**
   - At least one required
   - No duplicates
   - Preset list (Diabetes, Hypertension, Asthma, etc.)

## Error Scenarios & Recovery

### Network Disconnection

**Scenario:** User marks dose taken but network fails

**Current Behavior:**
- Write fails
- User sees error message
- Can retry manually

**Future Enhancement:**
- Queue write locally
- Sync when connection restored
- Show "synced" status

### Medication Deleted While In Progress

**Scenario:** Another device deactivates medication, user tries to mark dose

**Behavior:**
- Dose still appears (cached medication)
- User marks taken
- Write fails (medication not found)
- Show error: "Medication no longer active"
- Remove from list on refresh

### Duplicate Adherence Logs

**Scenario:** User rapid-clicks "Taken" button twice

**Prevention:**
- Deterministic log ID
- Firestore upsert overwrites instead of duplicates
- Button disabled during write

## Data Consistency

### Eventual Consistency

Due to real-time stream architecture:
- Changes sync within ~100ms (Firestore typical latency)
- UI immediately reflects user action
- Firestore eventually confirms

### Cross-Device Consistency

**Scenario:** User has app open on two devices, marks dose taken on device A

**Flow:**
1. Device A marks taken → Firestore update
2. Firestore updates document
3. Device B's stream listener receives update
4. Device B automatically updates UI
5. No user action needed on device B

## Key Metrics (For Analytics - Future)

1. **Adherence Rate** = (taken doses / total expected doses) × 100%
2. **Adherence Streak** = consecutive days with 100% adherence
3. **Missed Doses** = skipped + pending (overdue)
4. **Medication Persistence** = days medication remain active

## Known Business Logic Gaps

- [ ] Medication interactions checking
- [ ] Dosage recommendations
- [ ] Refill reminders
- [ ] Doctor communication
- [ ] Caregiver notifications
- [ ] Insurance integration
- [ ] Prescription expiry tracking
