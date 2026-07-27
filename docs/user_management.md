# Admin User Management (Sprint M8.4)

*Implements SDS FR8.5 in a reduced, honestly-scoped form — see "Why this is
smaller than the SDS's mockup" below.*

## What it is

**Profile → Admin Panel → Users** (`/admin/users`, admins only): a read-only,
searchable, filterable directory of registered users — the fifth branch of
`AdminShell`, again requiring zero shell changes.

| SDS FR8.5 row | Status | How |
|---|---|---|
| Display User List | **Done** | `userDirectory` collection, admin-read |
| Search Users | **Done** | Client-side, name/email substring |
| Filter Users by Status | **Done** (2 of 3 statuses) | Active / Pending — see below |
| View User Details | **Done** | Read-only detail screen |
| User Status Indicator | **Done** | Colour + text pill (never colour alone) |
| Suspend/Block User | **CLI only** | `backend/scripts/set_user_status.py --disable` |
| Reactivate User | **CLI only** | `backend/scripts/set_user_status.py --enable` |
| Delete User | **CLI only** | `backend/scripts/delete_user.py --confirm` |
| Add New User | **Not built** | Users already self-register (Module 1); no admin-provisioning need identified |
| Admin Action Buttons / logging | N/A | No in-app write path exists to log |

## Why this is smaller than the SDS's mockup

The mockup-derived FR8.5 rows assume an admin panel that can enumerate *every*
Firebase Auth account and flip real account-level switches (suspend = actually
can't sign in; delete = actually gone). **None of that is reachable through
Firestore.** `listUsers()`, `updateUser(disabled=...)`, and `deleteUser()` are
Firebase Auth **Admin SDK** operations — there is no Firestore query or rule
that exposes them to a client, admin or not.

Building them in-app would require either:
- a new authenticated FastAPI endpoint calling the Admin SDK (this project's
  **first-ever client-facing backend surface** — today the backend only serves
  `/health` and the internal `/predict`; it also has no ID-token verification
  middleware at all), or
- a Firestore-only "blocked" flag that looks like a real control but doesn't
  actually revoke anything — the account keeps working exactly as before,
  which would actively mislead an admin who believes they've cut someone off.

Given that trade-off, this sprint ships:
1. A genuinely useful, low-risk **read-only directory** — a new,
   purpose-built Firestore collection (`userDirectory`), same risk profile as
   `overrides`/`jobHeartbeats`/`adminActivityLog`/`articles` before it: no
   change to the sensitive `users/{uid}` subtree (profile, medications,
   adherence logs stay untouched, owner-only).
2. **Real** suspend/reactivate/delete — via new operator scripts using the
   actual Admin SDK, mirroring the existing `set_admin_claim.py` pattern —
   genuinely enforced, just not an in-app button this sprint.

The bigger option (a real in-app admin API) remains available as a future,
separately-scoped decision if the team wants to invest in the backend
auth-middleware work it requires.

## Data model — `userDirectory/{uid}`

| Field | Type | Notes |
|---|---|---|
| `name` | string? | From the registration form's "Full Name" field. Absent for a Google-sign-in-only account (see gap below) |
| `email` | string | |
| `createdAt` | ISO-8601 UTC string | When the account registered |
| `status` | `"pending"` \| `"active"` | See below — **no `"blocked"` value; not modelled at all** |

**No "Blocked" status.** A status this UI cannot truthfully enforce would
mislead an admin — see above. `status` is derived from real state, never
admin-settable:
- `pending` — account created, health-profile setup not yet completed. The
  app's router blocks these users from everything except the setup flow, so
  this is a real, if usually short-lived, state.
- `active` — health-profile setup completed at least once.

## Where entries are written (best-effort side effects, not new repositories)

- **`AuthNotifier.signUp`** (`lib/features/auth/presentation/auth_notifier.dart`)
  calls `UserDirectoryRepository.register(...)` once, right after a successful
  email/password sign-up, using the same name/email already collected by the
  registration form.
- **`HealthProfileNotifier.saveProfile`** (the first-run path only — never
  `updateProfile`, the edit path) calls `markProfileActive(uid)` once profile
  setup succeeds.
- Both calls are **best-effort**: caught and swallowed on failure, exactly
  like `AdminOverrideController`'s activity-log calls (Sprint M8.2) — a
  directory hiccup must never turn a successful sign-up or profile save into
  a user-facing error.

**Known, documented gap**: Google Sign-In does not call `register()` — a
user who only ever signs in with Google won't appear in the directory until
(if) they complete health-profile setup, at which point `markProfileActive`
creates a minimal entry for them anyway (no name, `status: active` — see the
repository's defensive `createdAt` fallback). Detecting "is this a brand-new
Google account" cleanly needs `additionalUserInfo.isNewUser`, which the
existing `signInWithGoogle()` doesn't currently surface; deferred rather than
guessed at.

## Security rules

```
match /userDirectory/{uid} {
  allow read: if isAdmin();
  allow write: if request.auth != null && request.auth.uid == uid;
}
```
Same shape as every other user-owned collection: the account owner writes
their own entry; only an admin reads the collection. There is no admin WRITE
rule here — deliberately, since the only real "write" actions (suspend,
delete) don't go through Firestore at all.

## Operator scripts

- `backend/scripts/set_user_status.py <uid|email> (--disable|--enable)` —
  Firebase Auth's `disabled` flag; a disabled user is actually signed out and
  can't sign back in.
- `backend/scripts/delete_user.py <uid|email> --confirm [--purge-data]` —
  deletes the Auth account; `--confirm` is required (SDS: "Deletion must
  require confirmation"); `--purge-data` additionally, explicitly, removes
  their Firestore data (`users/{uid}` and every subcollection, plus their
  `userDirectory` entry) — two separate flags so the script never silently
  does more than asked.

Both mirror `backend/scripts/set_admin_claim.py`'s safe-init shape
(service-account or emulator, never hardcoded credentials).

## Tests

- `test/features/auth/user_directory_entry_test.dart` — JSON parsing,
  defensive defaults (missing name, missing/malformed `createdAt`).
- `test/features/auth/firestore_user_directory_repository_test.dart` —
  register, markProfileActive (including the unregistered/Google-only
  fallback case), ordering, the empty case.
- `test/features/auth/auth_notifier_test.dart`,
  `test/features/health_profile/health_profile_notifier_test.dart` — the
  best-effort retrofit: a directory failure never turns a successful sign-up
  or profile save into an error; a *failed* sign-up/save never attempts to
  write to the directory at all.
- `test/features/admin/admin_users_screen_test.dart`,
  `admin_user_detail_screen_test.dart` — the admin gate, empty vs
  filtered-empty states, search, status filter, detail navigation, read-only
  rendering.
- `test_rules/firestore_rules.test.mjs` — the `userDirectory` rule surface.

## Relation to other Module 8 work

See `docs/MODULE_8_AUDIT.md` §15. This closes the FR8.5 roadmap item, in the
reduced form documented above. Module 8's five sprints (M8.1 dashboard, M8.2
activity log, M8.3 content management, M8.4 this sprint) now cover every SDS
Module 8 requirement to some degree — the two intentionally-open items are
FR8.1's active-user counter (no data source built yet) and FR8.5's real
in-app suspend/delete (needs the backend-auth-API decision above).
