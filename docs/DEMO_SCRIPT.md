# ForeSeeMe — Live Demo Runbook (Sprint 5, Prompt 17)

*A tight, rehearsable script that shows a real, explainable, proactive, safe system —
and proves the spam-safety guarantee live. Total runtime ~10–12 min. Every step is a real
execution path; nothing is staged or mocked for show.*

**Golden rule for the defense:** say the honest framing out loud *before* you're asked —
"this estimates environmental suitability, not clinical risk." It is a scoring strength,
not a weakness.

---

## 0. Pre-flight (do before the room)

1. `flutter analyze` → **zero issues**; `flutter test` → green.
2. `cd backend && pytest -q` → green (this is your safety net; see Act 2 fallback).
3. App installed on device/emulator, signed in as a demo user whose health profile marks a
   **respiratory (asthma)** condition and whose **notification preferences enable
   respiratory/high-risk alerts** in a modelled city (e.g. Lahore).
4. Have `docs/SPRINT_5_EVALUATION.md` open for the honest-limitations slide.
5. Optional: a second, **opted-out** user to show targeting.

---

## Act 1 — The proactive loop, live (predict → … → explain) (~4 min)

**Narrate the loop as you go:** predict → attribute → store → dispatch → receive → inbox →
explain.

1. **Seed / run the compute job** so Lahore transitions **Medium → High** for smog
   (respiratory). Show that it writes a `riskEstimates` doc **carrying `attributions`** —
   this is the genuine, model-derived explanation, not a narration.
2. **Run the dispatch job.** Show the console/audit log: exactly **one** send to the asthma
   user; the `userAlerts` inbox doc is written.
3. **On the device:** the push notification arrives *without the user opening the app*. Tap
   it → deep-links to the relevant resource; the **alert inbox** shows it, unread badge
   clears on read.
4. **Open Risk Details → "Why this estimate?"** Show the real top drivers (e.g. *Temperature,
   rising*) in the backend's order, and the **confidence explanation** ("strong — the model
   clearly favoured High…"). Point out: this text is a deterministic template over stored
   model numbers, not generated.

> If live FCM delivery is flaky on the network, **do not improvise** — cut to Act 2's test,
> which proves the same delivery path deterministically, then return to show the inbox/
> explanation UI from seeded data.

---

## Act 2 — The spam-safety guarantee (the money shot) (~2 min)

The core risk of a proactive health app is alert fatigue. Prove it can't happen.

1. **Run the end-to-end pipeline test live:**
   ```
   cd backend
   pytest tests/test_e2e_pipeline.py::test_repeated_runs_produce_no_spam -q
   ```
   Narrate: "The scheduler fires the *same* estimate five times; the guarantee is exactly
   **one** delivery." → **1 passed.**
2. **Show why:** open `dispatch_alerts.py` `dispatch_key` (idempotency keyed to the specific
   estimate) + the 24h throttle. Re-runs report `skipped_idempotent`.
3. **Targeting, one line:**
   ```
   pytest tests/test_e2e_pipeline.py::test_opted_out_user_receives_nothing \
          tests/test_e2e_pipeline.py::test_no_transition_sends_nothing -q
   ```
   → opted-out user gets nothing; steady High→High (no rise) sends nothing.

Full engine coverage (optional, for depth):
`pytest tests/test_e2e_dispatch.py -q` → 4 passed (multi-city, repeated runs, throttle,
token pruning).

---

## Act 3 — Explainability & transparency (~2 min)

1. Re-open **"Why this estimate?"** and the **Confidence** card; note icon+label
   accessibility (not colour-only).
2. Open the **Model Transparency** page: data provenance (Open-Meteo ERA5 + CAMS AQI, 5
   cities), label methodology, and the explicit "environmental risk, not outbreak/clinical
   prediction" statement.
3. One sentence on honesty: "Accuracy is high because labels derive from the model's own
   features — the real evidence is calibration and seasonality, in the model card."

---

## Act 4 — Safety, staleness & unhappy paths (~1.5 min)

1. Point out the **non-diagnostic disclaimer** persistent on the risk surface.
2. Show a **stale** estimate → "This estimate may be out of date" label (a health app must
   never show old risk as current).
3. Show **offline** (cached + indicator) and an **empty** state — premium apps are judged on
   unhappy paths.
4. On a High estimate, show the **one-tap emergency** affordance (reuses Sprint 3 contact).

---

## Act 5 — Operator override (safety valve) (~1 min)

1. As an admin, apply a manual override for a city (records author + reason + timestamp in
   `overrides`).
2. Show the app renders a **prominent, labelled** override banner above the model detail —
   never silent. Non-admins are denied by Firestore rules.

---

## Close (~30s)

"So: a real weekly ML pipeline, genuine explanations, a proactive loop that's provably
spam-safe, wrapped in honest, non-diagnostic framing. It estimates environmental
suitability — not clinical risk — and it tells the user that everywhere. The honest ceiling
is itself the engineering claim."

---

## Fallbacks & talking points

- **Live delivery flaky?** Lean on Act 2's deterministic tests; they *are* the proof of the
  delivery contract.
- **"Why not deep learning?"** A single, legible RF is the right choice when the product's
  value is transparency; a second model chasing accuracy on proxy labels trades legibility
  for a meaningless gain (`SPRINT_5_AUDIT.md` §5).
- **"Is it deployable to patients?"** No, by design (environmental proxy) — and stating that
  plainly is a maturity signal (`SPRINT_5_EVALUATION.md` §9).
- **Screenshots to capture for the report:** see `docs/screenshots_checklist.md`.
