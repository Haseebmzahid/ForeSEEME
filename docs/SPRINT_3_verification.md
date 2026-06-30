# Sprint 3 — Verification & Exit Criteria

What is **automated/green** vs what is **manual on a physical device**, plus the
device e2e script and screenshot checklist.

## Automated status (CI-green)

| Area | Evidence |
|---|---|
| Sprint 3 Flutter tests | **94 passing** (`flutter test`), incl. risk/resources/alerts/accessibility/integration |
| Sprint 2 backend untouched | **141 passing** (`cd backend && pytest`) |
| Static analysis | `flutter analyze` — no issues |
| Risk data flow (integration) | `test/integration/risk_view_slice_test.dart` — one feed → card + trend + all-cities + Resource Center prominence |
| Colorblind-safe encoding | `test/accessibility/colorblind_audit_test.dart` (+ per-widget tests) |
| Empty / error / staleness states | risk card, map, hospitals state tests |
| Places caching + quota guard | `test/features/resources/nearby_hospitals_test.dart` |
| FCM token capture + prefs round-trip | `test/features/alerts/*` (fake FCM + fake_cloud_firestore) |
| Firestore rules | deployed to `foreseeme-83587` + **verified active** via Rules API (riskEstimates read; users owner self-write) |
| Composite index | `firestore.indexes.json` deployed + verified `READY` |

## Manual — physical device e2e (exit pass)

> Run with the keys configured:
> `flutter run --dart-define-from-file=dart_defines.json`

1. **Login** → dashboard.
2. **Dashboard risk card** shows the user's city live risk: level (label + icon +
   colour), disease, confidence, and the low-confidence grey treatment when
   applicable. (With current data, the **trend** badge reads "Insufficient data"
   until ≥ 2 weekly estimates accumulate — by design.)
3. **Risk Details / trend** — direction badge present; insufficient handled.
4. **National Risk Map** (Risk Map quick action) — five cities as colored zones;
   tap a city → detail sheet; legend visible.
5. **Resource Center** — sourced guides with visible citations; **emergency dial**
   opens the dialer on `tel:1122`; on **High** risk the **Nearby Hospitals** entry
   is prominent → cached Places list with Call / Directions.
6. **Notifications** (Profile → Notifications) — grant permission (token persisted
   to `users/{uid}.fcmToken`); set **preferences** (persist + reload). **No alert
   is sent.**
7. **Offline** — disable network, reopen: risk card shows cached data; a stale
   estimate shows the "may be out of date" hint.
8. **Accessibility** — run the greyscale/TalkBack sweep in
   `docs/sprint3-accessibility-audit.md`.

## Manual — pre-release infra (your console steps)

- [ ] **Restrict the Maps/Places key** in Cloud Console: Android app
      (`com.example.fyp_foreseeme` + SHA-1) for the SDK; **Places API (New)**
      enabled for the REST key; remove unused API access. Quotas set.
- [ ] Confirm the key is not in any tracked file (it lives in git-ignored
      `android/local.properties` + `dart_defines.json`; the same value is also the
      committed Firebase key — restriction is the safeguard).

## Screenshots

The approved design references are the PNGs in `docs/ui sprint 3/` (Home
Dashboard, Risk Details, National Risk Map, Resource Center, Nearby Hospitals,
Notification Preferences, Permission, Empty/Offline/Loading). Capture device
screenshots of the running build for each and attach them to the sprint review;
they were not captured here because this environment has no attached device.

## Carried to Sprint 4

The FCM **dispatch engine** (targeting by city + vulnerability, 24h throttle,
audit log) consuming the captured tokens + `notificationPreferences`.
