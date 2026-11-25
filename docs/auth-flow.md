# ForeSeeMe authentication and health profile

## Registration and login

Registration requires a full name, a valid email address and a matching password
and confirmation. The form shows the eight-character minimum before submission.
Firebase Authentication enforces email uniqueness and stores credentials. Name is
stored on the Firebase Auth user. The existing owner-scoped admin directory
receives a best-effort pending entry.

Login accepts the registered email and password. Login and registration mask
passwords by default and expose a visibility toggle. While an authentication
request is active, both submission methods are disabled. Credential failures use
the same response for an unknown email, a disabled account and a wrong password.
The Google button uses the same Firebase OAuth flow on both screens and bundles
the official icon for offline rendering. Firebase's verification state
determines activation for both providers. Existing enrolled second factors
continue through the Firebase MFA resolver. [Google sign-in branding assets](https://developers.google.com/identity/branding-guidelines)

Phone-plus-password is tracked in the [Module 1 phone-login decision](MODULE_1_PHONE_LOGIN_DECISION.md).

## Verification and routing

1. After successful email registration, ForeSeeMe requests a Firebase
   verification email. A send failure leaves the account available for retry.
2. GoRouter sends pending accounts, including pending accounts restored by
   Firebase on mobile launch, to `/verify-email`. The screen explains how to
   open the link, supports resend and check, and rechecks on app resume.
3. Resend attempts are limited to once per minute per account for the running app,
   including failed requests. Firebase also applies its service quotas.
4. Checking reloads the Firebase user. Riverpod observes `userChanges()`. A
   verified Firebase Auth record must have a corresponding verified Firebase ID
   token before GoRouter continues to onboarding or the usual signed-in flow.
5. Verified accounts with no supported city go to health-profile onboarding.
   Existing profile confirmation, notification permission and medical disclaimer
   routes remain part of the flow. Verified accounts with complete onboarding
   continue to their intended route or the dashboard.

Signed-out users can access login, registration and password recovery. Pending
accounts can access password recovery and sign out through the existing global
session-revocation flow. Login and verification expose the Resource Center's
bundled emergency phone contact without requiring a session. The full Resource
Center retains its existing route and Firestore access requirements. Web auth
retains the existing non-persistent Firebase setting.

## Password recovery

ForeSeeMe requests a Firebase-managed password-reset email. User feedback is
neutral when a request is accepted or the account is absent or disabled. The
Firebase-hosted action handler accepts a valid code and rejects invalid, reused
and expired codes. Firebase's service determines expiry. The checked-in
configuration and public Firebase APIs expose no reset-code TTL setting and
provide no verified numerical duration for this project. The SRS's approximate
30-minute example should be reconciled with the observed staging lifetime before
recording a numeric release policy. Check the Firebase Authentication email
provider, email templates and action-handler domain in the release environment.
Firebase automatically revokes existing refresh tokens on password reset.
Backend endpoints check Firebase revocation. An already issued ID token has
its own expiry, and the app returns to its normal verification and onboarding
gates when the user signs in again. Check propagation across devices in staging.
[Firebase session management](https://firebase.google.com/docs/auth/admin/manage-sessions)

For backend account-enumeration behavior, confirm Identity Platform Email
Enumeration Protection in the target environment. [Firebase Auth REST API](https://firebase.google.com/docs/reference/rest/auth#section-confirm-password-reset) [Identity Platform configuration](https://docs.cloud.google.com/identity-platform/docs/reference/rest/v2/Config)

## Health profile and alert targeting

Profile writes are scoped to the current Firebase UID at
`users/{uid}/profile/{uid}`. The profile stores `uid`, `city`, the existing
`chronicConditions` list, optional `customConditions` and a server
`lastUpdated` timestamp. The form shares the app's supported-city and predefined
condition sources. A city is required and condition selection is optional.
Users can add or remove up to five custom labels of up to 64 characters each.
The form trims and collapses whitespace and rejects case-insensitive duplicates,
including predefined labels. A missing custom field reads as an empty list.
Leaving an edited form prompts before discarding; save and continue explicitly
commits onboarding.

The write batch merge-sets the parent `users/{uid}` document and the profile,
preserving notification preferences and unrelated profile fields. Dispatch reads
the latest stored city from the same profile path on each user scan. A legacy
profile without a parent becomes discoverable through this path on the next
profile save. There is no bulk migration. Dispatch receives custom labels on
`TargetUser.custom_conditions`. Its eligibility, categories, severity,
consent and push behavior continue to use the existing predefined mapping.
Using custom labels for eligibility requires an approved medical vocabulary and
category mapping.

Firestore uses Firebase's verified-email claim for profile, private user data,
disclaimer, dashboard risk and alert access in addition to the existing session
cutoff check. Profile rules constrain the UID, supported city, allowed fields,
server timestamp and custom list contents. Directory, notification registration
and logout-receipt restrictions retain their existing architecture.
FCM registration waits for the token-confirmed account in the client, and the
registration endpoint independently requires the verified-email claim. An
authenticated user can still unregister during logout cleanup. Deploy the
client, registration API and Firestore rules together after staging acceptance.

## Verification

See the [Module 1 final acceptance report](MODULE_1_FINAL_ACCEPTANCE_REPORT.md)
for the release review, requirement matrix, fresh test results and open gates.

### Previous implementation verification

The November 24, 2026 full Flutter run passed 967 tests with four opt-in golden
suites skipped. The health-profile screen suite passed all 15 tests after the
final discard-guard change. Dart analysis reported no issues.

The combined backend and ML run passed 756 tests with four emulator-only tests
skipped and one dependency deprecation warning. All four skipped tests passed
when run with both emulators, with the same dependency warning.

The demo emulators passed 118 Firestore rule checks and four SDK journeys
covering email registration and verification, profile creation and re-login,
password reset, and mock Google onboarding and restoration. The journey
requires loopback emulator hosts and uses synthetic accounts. It does not send
email.

```text
firebase emulators:exec --only auth,firestore --project demo-foreseeme "node test_rules/firestore_rules.test.mjs && node test_rules/module1_journey.test.mjs"
```

Use a staging device for platform Google OAuth, Firebase email delivery,
return-from-browser behavior, native restart, the emergency dialer, and the
FCM activation transition. A Firebase-hosted staging reset also needs a timed
expiry check. The emulator journey checks invalid and used codes.
