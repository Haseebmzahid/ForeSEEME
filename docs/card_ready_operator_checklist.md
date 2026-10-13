# ForeSeeMe operator input checklist

Preparation date: 2026-10-12 (America/Los_Angeles). No secret values are recorded here.
Do not copy this file over backend/deploy/config.env. Review that ignored file privately.

- [ ] Authorized billing account ID and approval to link it to foreseeme-83587.
- [ ] Reviewed existing image reference in us-central1-docker.pkg.dev/foreseeme-83587, pinned to an actual sha256 digest; release provenance, Linux runtime compatibility, current code/model inclusion, and image pull access. No digest has been verified.
- [ ] Runtime identity: risk-jobs-sa@foreseeme-83587.iam.gserviceaccount.com. For separately authorized recurrence only, scheduler identity: scheduler-invoker-sa@foreseeme-83587.iam.gserviceaccount.com. Confirm intended names against reviewed settings. Neither appeared in the historical readable account list; revalidate before release. One-time requires no Scheduler API, identity, configuration or bindings.
- [ ] Separately authorized prerequisite setup for missing service accounts/IAM, if these identities are retained. Do not substitute the existing Firebase Admin SDK account automatically.
- [ ] Existing operator Python environment with backend requirements and usable operator ADC. Local CLI Python is 3.13; image Python is 3.12. Dependency availability, ADC Firestore access and effective actAs/write permissions remain unverified. No installation is part of preparation.
- [ ] Historically missing compute configuration: FIRESTORE_AUTH_MODE=attached; VERIFY_TIMEOUT_SECONDS=900; VERIFY_MAX_AGE_SECONDS=900; VERIFY_MIN_WRITTEN=5; RISK_DATA_DELAY_DAYS=5; RISK_WEATHER_MAX_TRAILING_GAP_DAYS=0; RISK_AQI_MAX_TRAILING_GAP_DAYS=0. Revalidate privately before release. One-time always requires all configured cities and at least five fresh documents, even if the shared example minimum is 1. Only the recurring path permits degraded partial output at that lower threshold.
- [ ] Preserve RISK_LOOKBACK_WEEKS=12 and LOG_LEVEL=INFO; no emulator/key-file override; project foreseeme-83587 and region us-central1.
- [ ] Evaluation city, supported platform/device, Firebase user access, evaluation dates and stop date. Cities: Islamabad, Rawalpindi, Lahore, Karachi, Peshawar.
- [ ] Cadence: one manual verified execution for a short evaluation; only if recurring evaluation is needed, weekly `0 0 * * 1` in UTC. Approve daily execution only if daily changes are an explicit evaluation goal. Do not enable dispatch alerts.
- [ ] Initial resource trial: 1 CPU, 512Mi, 600s, one task, zero retries. Memory and timeout sufficiency are unproven; review measured execution before recurrence.
- [ ] Budget/free-tier sharing, Firestore location, image size/retention and log retention. Actual cost cannot be estimated yet.

Dispatch is outside this evaluation. Its local config also lacks FIRESTORE_AUTH_MODE, VERIFY_TIMEOUT_SECONDS and VERIFY_MAX_AGE_SECONDS. Do not run either dispatch controller or grant its FCM role for this preparation.
