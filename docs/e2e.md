# End-to-End Pipeline Tests (Sprint 5, Prompt 16)

This document describes the end-to-end (e2e) coverage that proves the full
proactive loop:

> **predict → attribute → store → dispatch → receive → inbox → explain**, plus
> the **staleness** signal and the **repeated-run spam** guard.

The e2e suite is deliberately split across the two runtimes that own different
legs of the loop. Each leg is exercised against the *real* production code path
(the actual jobs, repositories, providers and widgets) over a single shared
in-memory store seeded with the exact document shapes the frozen contracts
define — never mocks of the code under test, and never fabricated data.

## Why the split

The loop crosses a process boundary: the Python backend **produces** risk
estimates and **dispatches** alerts; the Flutter app **consumes** the stored
estimate and the delivered alert. The store (`riskEstimates`,
`userAlerts/{uid}/items`) is the contract seam between them. Testing that seam
honestly means driving each side against the *same* document shapes:

- **Backend legs** — predict → attribute → store → dispatch → inbox — run fully
  in-memory (no Firebase, no emulator), so they are deterministic and belong in
  the CI gate (`docs/ci.md`).
- **Flutter read legs** — store → read → explain, receive → inbox, and the
  user-facing staleness label — run as widget/provider tests over a
  `FakeFirebaseFirestore` seeded with the backend's exact output.

Staleness is proven on the Flutter side only, because it is a *user-facing*
signal (an old estimate must be labelled, never shown as current); the backend
has no notion of it.

## Coverage map

| Loop leg | Test | Assertion |
|---|---|---|
| predict → attribute → store, dispatch-readable | `backend/tests/test_e2e_pipeline.py::test_compute_risk_output_carries_attributions_and_is_dispatch_readable` | the real `compute_risk.run_and_report` writes a contract-valid `riskEstimates` body carrying genuine `attributions` (`method == tree_path_contributions`, explaining the same predicted class), and `dispatch_alerts` reads exactly that body back through the store seam |
| store → dispatch → inbox (delivery) | `backend/tests/test_e2e_pipeline.py::test_full_loop_delivers_exactly_one_inbox_alert` | a vulnerable, consenting user on a Medium→High transition gets exactly one audited send and one inbox doc whose shape matches the frozen contract (`read == false`, `riskEstimateId`, cited `recommendation.sourceUrl`, `deepLink`) |
| repeated-run spam guard | `backend/tests/test_e2e_pipeline.py::test_repeated_runs_produce_no_spam` | firing the same estimate five times still yields **one** delivery; subsequent runs report `skipped_idempotent` |
| targeting / consent | `backend/tests/test_e2e_pipeline.py::test_opted_out_user_receives_nothing` | a user with respiratory consent withdrawn receives nothing |
| transition-triggering | `backend/tests/test_e2e_pipeline.py::test_no_transition_sends_nothing` | steady High→High produces no send (no upward transition) |
| multi-city/user dispatch, 24h throttle, token pruning | `backend/tests/test_e2e_dispatch.py` | only vulnerable consenting users on a transition are alerted; repeated runs and a second within-24h event produce zero extra sends; an invalid token is pruned once |
| store → read → **explain** | `test/integration/pipeline_e2e_test.dart` → *"stored estimate + attributions is read and EXPLAINED"* | the real Risk Details read path renders the stored risk and, inside the `ExplanationPanel`, explains the genuine top driver (`Temperature`, rising) in the backend's order — never recomputed, never fabricated |
| receive → inbox | `test/integration/pipeline_e2e_test.dart` → *"the delivered alert surfaces in the owner inbox"* | the dispatched `userAlerts` doc surfaces in the owner's inbox stream, tied to the same `riskEstimateId`, with a correct unread count |
| **staleness** (user-facing) | `test/integration/pipeline_e2e_test.dart` → *"a STALE estimate is labelled, not shown as current"* | an estimate older than `kRiskStaleAfter` renders the "This estimate may be out of date" label beside the headline |
| receive → inbox → mark-read → deep-link | `test/integration/alert_pipeline_e2e_test.dart` | delivered alert is user-scoped, unread→read persists back to Firestore, and an inbox tap fires the engagement hook and deep-links to `/resources` |

## Running the suite

Backend (in-memory, no emulator — part of the CI gate):

```bash
cd backend
pytest tests/test_e2e_pipeline.py tests/test_e2e_dispatch.py -q
```

Flutter read legs (widget/provider tests over a fake Firestore):

```bash
flutter test test/integration/pipeline_e2e_test.dart \
             test/integration/alert_pipeline_e2e_test.dart
```

Both run offline and deterministically, so they gate merges in CI alongside the
rest of `flutter test` / `pytest` (see `docs/ci.md`).

## Emulator variant (optional, manual)

The in-memory backend tests substitute a `PipelineStore` for Firestore at the
repository seam, which is sufficient to prove contract compatibility across the
store boundary without external dependencies. A heavier, optional validation can
run the same jobs against the **Firebase Local Emulator Suite** with a dedicated
test project:

1. `firebase emulators:start --only firestore`
2. Point the jobs' repositories at the emulator (`FIRESTORE_EMULATOR_HOST`).
3. Run `compute_risk` then `dispatch_alerts`, and assert the emulator's
   `riskEstimates` / `userAlerts` documents match the same shapes asserted above.

This variant is intentionally **not** in the CI gate: it needs the emulator
runtime and is slower and flakier than the in-memory path, which already proves
the contract. It exists as a manual, higher-fidelity check before a release.

## Honest scope

These tests prove the *system integration* — that every leg of the loop consumes
the previous leg's real output and that the spam/consent/transition/staleness
guards hold end-to-end. They do **not** validate the *epidemiological* accuracy
of the risk index (an environmental proxy, per the model card and
`docs/SPRINT_5_AUDIT.md` §9); that is out of scope for Sprint 5 and named as a
known limitation, not silently implied.
