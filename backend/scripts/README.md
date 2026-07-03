# Backend ops scripts

## `set_admin_claim.py` (Sprint 5, Prompt 13)

Grants or revokes the `admin` custom claim that gates the manual risk-override
safety valve. Custom claims can only be set by the Admin SDK (never a client), so
this is the trusted way to designate an operator. The claim is enforced in
`firestore.rules` (`overrides/{city}` writes) and used by the app to reveal the
guarded admin surface.

```bash
# grant (by uid or email):
GOOGLE_APPLICATION_CREDENTIALS=/path/sa.json python backend/scripts/set_admin_claim.py operator@example.com
# revoke:
GOOGLE_APPLICATION_CREDENTIALS=/path/sa.json python backend/scripts/set_admin_claim.py operator@example.com --revoke
```

The user must refresh their ID token (sign out/in) for the change to take effect;
the app force-refreshes the token when reading the claim. See
`docs/admin_override.md` for the full override design.

## `seed_risk_estimates.py`

Seeds ~8 sample `riskEstimates` documents (Lahore, Islamabad, Karachi, Peshawar
across two dates, varied Low/Medium/High) so the Sprint-3 dashboard has data to
render. Each document is validated against the frozen contract
(`app.schemas.RiskEstimateResponse`) before writing, and uses the
`{city}_{YYYY-MM-DD}` document-id convention from `docs/RISK_SCHEMA.md`.

Writes are **idempotent** (`set(..., merge=True)`), so re-running updates the
same documents instead of creating duplicates.

### Install

```bash
pip install -r backend/scripts/requirements.txt
```

### Run safely against a TEST project (recommended order)

> ⚠️ Only ever seed a **test/dev** Firebase project. `riskEstimates` is normally
> written by the backend service account; this script is a dev convenience.

**Option A — Firestore emulator (no credentials, safest):**

```bash
# Terminal 1: start the emulator
firebase emulators:start --only firestore

# Terminal 2: point the script at the emulator
export FIRESTORE_EMULATOR_HOST=localhost:8080
export FIREBASE_PROJECT_ID=demo-foreseeme      # any id; emulator doesn't verify
python backend/scripts/seed_risk_estimates.py
```

**Option B — real TEST project (service account):**

```bash
# Path to a service-account JSON for your TEST project. The JSON is git-ignored
# (see .gitignore) and MUST NEVER be committed.
export GOOGLE_APPLICATION_CREDENTIALS=/secure/path/foreseeme-test-sa.json
python backend/scripts/seed_risk_estimates.py
```

Expected log: 8 lines `seeded {City}_{YYYY-MM-DD} -> {Level} ({Disease})` then
`Done. 8 riskEstimates documents written/merged.`

### Configuration (environment only — no secrets in source, GOLDEN_RULES #7)

| Variable | Purpose |
|----------|---------|
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to the service-account JSON (real project). |
| `FIRESTORE_EMULATOR_HOST` | e.g. `localhost:8080`; use the emulator instead of a real project. |
| `FIREBASE_PROJECT_ID` / `GCLOUD_PROJECT` | Project id when using the emulator. |
| `MODEL_VERSION` | Stamped onto seeded docs (default `stub-0.0.0`). |

### Verify (acceptance)

1. After seeding, 8 documents appear in `riskEstimates` with `{city}_{date}` ids.
2. Confirm `git status` shows **no** service-account JSON staged.

---

## Security rules manual test (`riskEstimates`)

Once the `riskEstimates` rules block is deployed (see `firestore.rules`):

- **Read (authenticated) → allowed.** Sign in to the app/emulator and read a
  `riskEstimates` document — it returns data.
- **Write (any client) → denied.** Attempt a client write to
  `riskEstimates/{anyId}` — it fails with `PERMISSION_DENIED`. The backend
  service account (Admin SDK) bypasses rules and is unaffected.

### Optional: automated rules test with the emulator

If you wire up `@firebase/rules-unit-testing` (Node) later, assert:

```js
// authenticated read allowed
await assertSucceeds(authedDb.collection('riskEstimates').doc('Lahore_2026-06-28').get());
// any client write denied
await assertFails(authedDb.collection('riskEstimates').doc('Lahore_2026-06-28').set({ city: 'Lahore' }));
```

This toolchain is not currently set up in the repo; the manual test above is the
supported verification for this sprint.
