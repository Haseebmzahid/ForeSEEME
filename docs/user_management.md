# Admin user management

The Users tab reads `userDirectory` and supports name/email search, Active/Pending/Blocked filters and minimal account details. Pending and Active describe onboarding. Blocked reflects Firebase Authentication's disabled state and takes precedence. The directory omits medication, adherence, health information and messaging tokens. Owner onboarding writes cannot set the server-owned disabled flag, access other directory entries, or add arbitrary fields.

An authorized, recently signed-in administrator can suspend, reactivate or delete ordinary accounts. Suspension disables sign-in and revokes refresh tokens. Reactivation verifies that Firebase Auth re-enabled the account. An issued ID token can remain usable until expiration where revocation is not checked, including existing direct Firestore sessions. The HTTPS admin API verifies revocation on every request. Firebase documents ID tokens as lasting about one hour. [Firebase session management](https://firebase.google.com/docs/auth/admin/manage-sessions)

Deleting an account requires explicit confirmation and the `retain_firestore` retention decision. The service removes Firebase Auth and the directory projection, and keeps a server-side marker against stale backfills. Associated Firestore records and subcollections are retained. A request for Firestore data erasure requires its own inventory, retention decision and separately authorized recursive procedure.

## Backfill

Run from `backend`, using the intended Firebase project and an authorized runtime identity:

```sh
python -m app.jobs.account_metrics --backfill
python -m app.jobs.account_metrics --backfill --apply
```

The first command previews changes. The second writes missing records and metadata, leaves existing valid names and onboarding status intact, and reports updated, skipped and failed counts. Re-running it is safe. Where the onboarding status is missing, the backfill checks the existing profile document with an empty field mask. An existing profile marks the account Active. Absent profiles remain Pending. Schedule periodic backfills or rerun after importing users or adding external sign-in accounts. The backfill uses the profile document’s existence only. It receives no health fields and grants no client access to that subtree. Account changes performed in the Firebase Console or legacy CLI can leave the projection out of sync. Prefer the audited API. Review and reconcile external changes before relying on the directory state.

## Invitations

Enable the invitation control in Flutter with `--dart-define=ADMIN_INVITATIONS_ENABLED=true` after configuring and testing `ADMIN_INVITATION_API_KEY` on the admin service. Use a Firebase project API key restricted to Identity Toolkit and configured for the environment. Review the project's password-reset email template and authorized domains. The service creates an ordinary Auth account with a cryptographically random initial credential, then asks Firebase to send its password-reset email. Only the recipient chooses a usable password. Credentials and action codes never enter the app or audit trail.

A positive result means Firebase accepted the email request. When delivery is unconfirmed, reenter the same address to retry against the same account. Existing accounts outside the invitation workflow are protected from provisioning or resets. A stopped or ambiguous operation has a reservation and requires the reconciliation procedure in the [engineering report](MODULE_8_FINALIZATION.md). Staging must verify the actual sender, template, quotas and reset link before the invitation control is enabled. [Firebase Auth REST password reset](https://firebase.google.com/docs/reference/rest/auth#section-send-password-reset-email)
