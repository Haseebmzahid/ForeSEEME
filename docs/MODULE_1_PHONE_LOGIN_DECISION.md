# Module 1 phone-login technical decision

**Status** · Phone plus password is not implemented. Supervisor approval is pending.

## Specification conflict

SRS §2.6 Module 1 requires an “Enter Email or Phone” identifier with a password.
The same module registers users with email and password or Google OAuth. It
defines no phone enrollment, ownership verification, linking or recovery
process. ForeSeeMe has no primary phone credential or verified phone-to-account
index. The existing administrator SMS factor is a second factor for already
authenticated Firebase accounts.

## Firebase capability

Firebase's password sign-in endpoint requires an email address. Firebase phone
sign-in verifies a phone number via an SMS challenge and issues the session from
that proof. Linking a Firebase phone credential to an existing user can preserve
the UID, but it leaves the two credential types and their sign-in methods
distinct. Neither endpoint accepts a phone number as the identifier for an
existing Firebase email password. [Identity Platform password sign-in API](https://docs.cloud.google.com/identity-platform/docs/reference/rest/v1/accounts/signInWithPassword) [Identity Platform phone sign-in](https://docs.cloud.google.com/identity-platform/docs/sign-in-user-phone)

## Options for approval

| Option | Scope, security and maintenance |
| --- | --- |
| Retain email/password and Google | Approve changing the password-login identifier requirement to email. Uses the existing sign-in, recovery, Firebase UID, and session controls. |
| Add linked phone OTP | Approve phone OTP as a separate primary method and define how a verified email user enrolls and links a phone. Requires account collision handling, phone change and recovery, lost and recycled number policy, region restrictions, abuse protection, SMS cost management and a decision about email activation for phone users. |
| Retain literal phone plus password | Approve a separate architecture project. Evaluate a managed identity provider that natively supports verified phone aliases with a password, with a supported Firebase federation path for stable UIDs and claims. This needs an approved provider, threat model, account linking, credential lifecycle, recovery, privacy review, migration plan and testing against Firestore, MFA, session revocation and device registration. Feasibility within the current app is unproven. |

A public phone-to-email mapping would expose account identifiers and allow
enumeration of enrolled phone numbers. A private
broker resolving phone numbers and handling password submissions would expand
the credential trust boundary and require a separately owned, rate-limited
authentication service. ForeSeeMe's existing Admin SDK, Firebase rules and
client APIs do not provide this as a supported phone/password flow.

## Requested supervisor decision

Record written approval that the release accepts **email/password and Google**
and revise FR1.5's identifier wording from “Email or Phone” to “Email” through
the normal SRS/SDS review. If phone sign-in remains mandatory, approve either
the linked OTP requirement and enrollment design or a separately scoped
phone/password architecture evaluation with the deliverables above. Track
FR1.5 phone login as open until that decision is recorded and any required
implementation is verified. This decision report leaves the SRS and SDS as
issued.

The Module 1 source release covers email/password and Google. The phone
portion of FR1.5 remains open until the supervisor records the decision.
