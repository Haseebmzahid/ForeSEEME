# Admin activity log

The Logs tab reads Firestore newest first and supports action and date filters over the records loaded so far. Use **Load older actions** to extend the search. Each row shows the action, target, verified actor when available, timestamp, result, and a description. An empty collection shows “No administrative actions have been recorded yet.”

The admin service derives identity from a verified Firebase token. It generates an event ID, request correlation ID and timestamp and appends outcome events to `adminActivityLog`. The `createdAt` field retains its ISO UTC format for legacy ordering. `recordedAt` is the authoritative Firestore commit timestamp for new records. Every client is denied create, update and delete. Reads require the admin grant and a verified second factor.

Article and risk updates commit atomically with their success events. The service records safe failure codes for rejected domain operations. Authentication and malformed-body failures return structured errors before a validated target exists. Account updates reserve the target and append **started** before contacting Firebase Auth. Successful verification then commits the directory change and a success event. A transport or persistence failure returns an unconfirmed result, keeps the reservation when finalization did not commit, and emits a sanitized log with the correlation ID. Use the reconciliation process in the [engineering report](MODULE_8_FINALIZATION.md).

Historical entries from the earlier client writer remain visible and are labelled legacy client records. They should be evaluated as historical assertions. Firebase Admin SDK identities bypass Firestore rules, so database IAM and Cloud Audit Logs are part of the audit trust boundary.
