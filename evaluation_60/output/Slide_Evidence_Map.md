# Slide evidence map

Attached document: C:/Users/HP/Downloads/ForeSeeMe_final_compressed.docx. Repository-relative paths resolve from the ForeSeeMe checkout.

## Slide 1: ForeSeeMe

Attached report, title and approval pages; team statement in conversation.

Claim boundary and presenter guidance: Presenter: Muhammad Haseeb. Introduce both members and supervisor. State that the evaluation concerns implemented software and reproducible test evidence. Haseeb presents application and ML engineering. Saim presents testing, traceability and documentation. The team supplied this responsibility split, rather than a commit-level authorship audit. Transition to the user problem. Likely question: What does 60% mean? Answer: it is the evaluation stage, not a measured percentage of code or requirement completion.

## Slide 2: The preparedness gap

Attached report, Chapter 1 problem statement and proposed solution.

Claim boundary and presenter guidance: Presenter: Haseeb. Describe the intended users: residents of supported Pakistani cities, especially people managing chronic conditions and regular medication. Explain the project problem without asserting measured reductions in illness or adherence improvements. The report motivates combining regional awareness with everyday self-management. No user trial or clinical effectiveness study has been established. Likely question: Why combine these functions? Explain that profile and location context connect awareness to practical preparedness, while medication support is independently useful.

## Slide 3: One application, two connected workflows

Attached report Chapters 1–2; backend/ml/reports/MODEL_CARD.md.

Claim boundary and presenter guidance: Presenter: Haseeb. This is the second and final introduction slide. Explain the two main workflows. A health profile provides city and condition context. The regional dashboard reads city-level estimates, while medication tools manage a personal routine. Supported model cities are Islamabad, Rawalpindi, Lahore, Karachi and Peshawar. Risk categories are dengue, smog/respiratory and influenza environmental suitability. ForeSeeMe supports awareness and preparedness. It does not diagnose disease or forecast outbreaks. Transition to what changed after the previous evaluation.

## Slide 4: Previous evaluation and subsequent improvements

User clarification; docs/adr/ADR-001-risk-source-of-truth.md; attached report Chapters 4–5.

Claim boundary and presenter guidance: Presenter: Haseeb, with Saim explaining the final row. The team confirms that evaluators requested no improvements. Do not imply that architecture, UI or tests were responses to invented committee comments. The Good/OK assessment is a team-provided fact, not an attached signed feedback sheet. Subsequent improvements are engineering work selected by the team. An approved historical 30% snapshot has not been compared file by file, so avoid unsupported before/after completion percentages. Likely question: What did you change because of feedback? Answer that there were no requested corrections, then discuss continued development on its own merits.

## Slide 5: Implemented architecture

ADR-001; ADR-002; backend/app/jobs/compute_risk.py; dispatch_alerts.py; Flutter risk repositories.

Claim boundary and presenter guidance: Presenter: Haseeb. Explain presentation, domain and data boundaries in Flutter. Riverpod connects widgets to providers and repository interfaces. Firebase Auth handles identity and Firestore stores profiles, medication/adherence data, risk estimates and alerts. Backend acquisition and feature preparation feed the versioned scikit-learn artifact. Compute writes riskEstimates. Dispatch reads those estimates and user preferences, applies targeting/throttling/idempotency, then uses a messaging adapter. The app reads risk only from Firestore, never directly from /predict. Cloud scheduling and real FCM delivery remain deployment verification work. The diagram shows implemented code paths, with the cloud boundary explicitly marked pending. Likely question: Why batch inference? Answer consistent shared estimates and decoupled client operation, with freshness as the tradeoff.

## Slide 6: Implementation ownership and verification status

Team-provided contribution statement; attached report; docs/docs/DEPLOYMENT_STATUS.md.

Claim boundary and presenter guidance: Presenter: Haseeb introduces the work split, then Saim confirms his testing/documentation responsibilities. This allocation comes directly from the team. It does not claim exclusive authorship of every source file. Code presence and local passing tests establish different things from deployed operation. Avoid describing the 60% evaluation stage as measured implementation completeness. Saim will independently present the testing section and run tests during the demo.

## Slide 7: Haseeb: identity and health profile

Attached report §4.5.3 and §5.5.5; lib/features/auth; lib/features/health_profile.

Claim boundary and presenter guidance: Presenter: Haseeb. Show the health profile screenshot from report Chapter 4, Figure 4.5. Explain that this is a report-captured application screen, not a newly observed live session. Walk from registration through city/condition setup and guarded navigation. Open auth and profile repository interfaces if asked. Password recovery automation uses a fake repository, so it proves validation and state management, not email delivery. RTM entries include partial/unverified clauses. Likely question: Is Google OAuth tested end to end? Answer that the integration code exists but retained evidence does not verify live OAuth execution.

## Slide 8: Haseeb: medication and daily check-in

Attached report §4.5.5 and §5.5; dose_state_engine.dart; medication_notification_orchestrator_test.dart.

Claim boundary and presenter guidance: Presenter: Haseeb. Use the Chapter 4 check-in screenshot to explain dose groups and actions. Discuss DoseStateEngine and repository/notifier separation. The current implementation uses a 30-minute lead and two-hour grace. These durations are implementation policy, not numeric SRS requirements. Saim demonstrates exact boundary assertions later. Do not claim that isolated state tests establish Firestore timestamp writes or native alarm timing. In the live demo use a non-personal medication record and a time appropriate to the evaluation, with safe synthetic details. Likely question: What happens at the deadline? Pending becomes missed and actions close; a previously taken dose remains completed.

## Slide 9: Haseeb: regional risk and explanations

Attached report §4.5.6; docs/RISK_SCHEMA.md; docs/adr/ADR-001-risk-source-of-truth.md; risk_map_test.dart.

Claim boundary and presenter guidance: Presenter: Haseeb. Show the Regional Risk Map captured in report Figure 4.8. Explain data selection and marker appearance separately from live map behavior. Backend estimates carry modelVersion, confidence and model-derived attributions. Deterministic text templates render explanations without an LLM. A stored or seeded value is not a newly computed current risk. Point out city/week timestamps and stale-data behavior. Do not infer continuous geographic disease surveillance from map visualization. Likely question: Does the phone call the model? No, Firestore is the only client risk source.

## Slide 10: Haseeb: resources and practical guidance

Attached report §4.5.7–4.5.8; docs/content_safety_policy.md; lib/features/resources.

Claim boundary and presenter guidance: Presenter: Haseeb. Show report Figure 4.9, the Resource Center. Explain stored article content, search and priority decisions. Nearby hospital screens are also documented, but available screenshot values must not be represented as fresh service results. Guidance uses controlled content rather than generated medical advice. Relevant tests include resource_center_test.dart, firestore_resource_repository_test.dart and nearby_hospitals_test.dart. Likely question: How do you keep information safe? Cite the content policy, controlled sources and deterministic content. Do not claim clinical review unless the team can produce it.

## Slide 11: Haseeb: alerts and operational controls

backend/app/jobs/dispatch_alerts.py; backend/tests/test_e2e_pipeline.py; lib/features/alerts; lib/features/admin; deployment readiness report.

Claim boundary and presenter guidance: Presenter: Haseeb. Explain the implemented backend dispatch path and Flutter inbox handling. Risk change, vulnerability and consent determine eligibility. The same estimate should not repeatedly notify. Show test_repeated_runs_produce_no_spam if challenged. Admin modules include content, users, override/activity and status components in source and tests. This slide summarizes code paths, not a deployed-service demonstration. Existing documents contain older deployment assumptions; the current deployment report explicitly leaves cloud responses and device delivery unvalidated. Likely question: Is push working on hardware? Answer that hardware delivery remains a release gate, while adapters and control logic have automated coverage.

## Slide 12: Haseeb: implemented ML pipeline

backend/ml/reports/MODEL_CARD.md; training_log.md; label_methodology.md; backend/ml/training/train.py.

Claim boundary and presenter guidance: Presenter: Haseeb. The model is implemented, not merely proposed. Explain the bounded data window 5 August 2022 to 28 June 2026, 36 features, temporal train/test split of 735/260 city-week rows, and TimeSeriesSplit tuning. Random Forest suits nonlinear interactions in this modest tabular dataset. Scaling is part of the saved common pipeline, although trees themselves do not need standardization. Most importantly, labels derive from an environmental index using input determinants; they are not observed disease incidence. The attachment executive summary refers to incidence training, but the model card and artifact describe the narrower implemented scope. State this discrepancy explicitly if asked. Serving uses rf-1.0.0, with batch results stored in Firestore.

## Slide 13: ML results measure fidelity to the index

backend/ml/reports/evaluation_report.md §1; MODEL_CARD.md.

Claim boundary and presenter guidance: Presenter: Haseeb. These are retained evaluation results, not a fresh training run. All models use the same held-out city-week block. Because the labels derive from related environmental inputs, accuracy measures fidelity to the index and does not establish disease forecasting effectiveness. Discuss dengue Medium-class F1 of 0.69 and influenza High-class precision of 0.62 if asked. Calibration and seasonality checks appear in the reports, but the baseline model-card ECE and later sigmoid assessment must not be confused with a verified deployed calibrated artifact. We deliberately present unambiguous held-out values. The model excludes immunity, mobility, vaccination and vector control. No clinical effectiveness claim is supported.

## Slide 14: Saim: testing strategy

Attached report Chapter 5; pubspec.yaml; backend/requirements.txt; test and backend/tests directories.

Claim boundary and presenter guidance: Presenter: Saim. Explain your role in test selection, documentation and requirement traceability. flutter_test, fake_cloud_firestore, pytest and FastAPI TestClient are present in project code. Functional behavior is verified by automated widget scenarios, not an invented manual acceptance campaign. Tests under test/integration are host widget/provider integrations, not mobile integration_test runs. Unit checks make boundary decisions reproducible. Fake services isolate external failures and make negative cases controllable. Their limitation is that native plugins and deployed services remain outside these seams. Likely question: Why not only manual testing? Explain repeatability, exact boundary conditions and regression detection.

## Slide 15: Saim: positive and negative UI / rule cases

test/features/medication/dose_state_boundaries_test.dart; test/features/auth/forgot_password_screen_test.dart; flutter-final.jsonl.

Claim boundary and presenter guidance: Presenter: Saim. These actual names occur in scripts and retained Flutter results. FSM-U01 is a negative boundary case, FSM-U02 a positive boundary case and FSM-U04 a deadline transition. FSM-W01 expands into two test cases because of the light/dark theme loop. FSM-W02 uses a controlled Completer to keep a request pending, prevent duplicate submission and release a simulated network failure. The recorded actual result is assertion agreement in the retained 15 October run. Show exact test source rather than treating the table as a new execution. Numeric action windows are implementation policies. Likely question: What defect does this catch? Off-by-one boundaries and duplicate recovery requests, without asserting that these specific bugs occurred in production.

## Slide 16: Saim: API validation before inference

backend/tests/test_api_validation_boundary.py; backend-verified.xml; attached report §5.5.3.

Claim boundary and presenter guidance: Presenter: Saim. All shown cases passed in the retained backend execution. FSM-B IDs other than B08 are pytest parameter IDs. B08 appears as the exact function name displayed, with underscores. Explain the RecordingModel dependency: invalid requests must never reach inference, while accepted boundary values must reach it once unchanged. This is route/schema behavior using a stub model, not evidence of Random Forest prediction quality or load performance. The full file has ten cases. FR6.6 provides the API requirement, but its three-second latency clause is not proven by these tests. Likely question: Why check call count? It proves validation occurs before inference, not merely that an error response exists.

## Slide 17: Automated testing workflow

Attached report §5.5; .github/workflows/ci.yml; test_artifacts/chapter5/RUN_RESULTS.md.

Claim boundary and presenter guidance: Presenter: Saim. Walk through one concrete requirement: FR1.7 maps to the recovery widget cases, whose names appear in Flutter JSONL and the RTM. CI YAML runs Flutter analyze/test and backend lint/pytest on pull requests and main pushes. A configured workflow is not evidence that a particular remote CI run succeeded. Local evidence is retained separately. Baseline CI uses Flutter 3.44.4 and Python 3.12; the recorded local backend used Python 3.13.7 and pytest 9.0.3. Prepare the toolchain before entering the room. The demonstration uses existing tests and never changes assertions to obtain a pass.

## Slide 18: Retained execution evidence: 15 October

test_artifacts/chapter5/RUN_RESULTS.md; flutter-final-summary.json; backend-verified.xml.

Claim boundary and presenter guidance: Presenter: Saim. State the date before the count. Parse the raw reports if the committee wants evidence: Flutter JSONL contains loading and suite events that must not inflate test counts. The four skipped suite entries are golden placeholders, not a verified number of skipped individual test cases. The 20 targeted Flutter and 10 targeted backend passes overlap full-suite counts and must not be added again. Both full suites exited zero. Earlier backend diagnostic attempts were interrupted and do not have reliable final counts. The warning concerns TestClient/httpx deprecation. Do not claim code coverage or requirement completion percentages from test counts. A fresh targeted rehearsal, if available, is reported separately in the supporting pack.

## Slide 19: Requirement traceability: selected real mappings

Attached report Chapter 2 and §5.5.5; actual FSM scripts and retained reports.

Claim boundary and presenter guidance: Presenter: Saim. Show the detailed RTM in report §5.5.5 for the complete mapping and scope notes. The requirement labels are shortened here, while IDs remain exact. The report contains duplicate IDs across UI-derived clauses and legacy hyphenated labels, so cite the specific clause and test file. FR2.2 mapping is explicitly partial and includes supporting state-engine policy checks, not proof of every daily schedule clause. FR1.7 includes reset-link expiry that widget tests do not cover. FR6.6 requires a trained-model interface and a latency target, whereas the displayed boundary tests isolate a stub. Do not infer full requirement satisfaction. The supporting evidence map preserves scripts and report references.

## Slide 20: Failures, skips and coverage limits

RUN_RESULTS.md; attached report §5.5.5–5.7; docs/deployment_readiness_report.md.

Claim boundary and presenter guidance: Presenter: Saim. Explain that no failed test remains in the completed recorded full runs, while incomplete diagnostic runs cannot be relabeled as successful. A historical deployment correction report records one deadline regression failure that was fixed and covered by focused tests, but its counts are not added to the full-suite total. Native device end-to-end tests are not implemented/executed as an integration_test suite. The tests cannot establish every requirement clause or cloud identity, IAM, source freshness and hardware delivery behavior. Legacy ID inconsistencies and provider changes require requirements reconciliation. This is a technical test boundary, not a claim that the code is defect-free.

## Slide 21: Live demonstration: application and automation

User committee guidelines; prepared demo plan; actual test paths.

Claim boundary and presenter guidance: Presenters: Haseeb and Saim. Rehearse using the separate live demonstration plan. Use a dedicated demo account and synthetic records. Haseeb owns application navigation and architecture explanation. Saim owns the automation execution and requirement trace. Full suites may take several minutes, so start them before the talk if useful and demonstrate targeted files live. Do not promise a fresh city estimate or native push unless deployment and permissions have been verified before the evaluation. If a network or device fails, explain the failing boundary, show retained report screenshots and execute isolated tests. A fallback screenshot is report evidence, not a substitute labeled as a successful live demo.

## Slide 22: Remaining work: release gates

docs/docs/DEPLOYMENT_STATUS.md; backend/deploy/README.md; report §5.7; proposed milestone sequencing.

Claim boundary and presenter guidance: Presenter: Haseeb explains deployment and model work. Saim explains validation and requirement closure. This is a proposed sequence, not a team-approved dated schedule beyond the 23 October evaluation. Cloud billing and deployment are pending according to the repository. Mitigate environment drift with an isolated pinned environment. Mitigate upstream data gaps with freshness gates and stale-data UX. Mitigate alert duplication with idempotency tests and device checks. Mitigate scope mismatch through explicit approval of environmental suitability and provider changes. Do not claim a 100% completion date that the team has not supplied.

## Slide 23: Implemented foundation and the next milestone

Attached report Chapters 4–5; MODEL_CARD.md; RUN_RESULTS.md.

Claim boundary and presenter guidance: Presenter: Haseeb, followed by Saim for the verification sentence. Summarize what the evidence actually establishes. Application screenshots and code support implementation claims. The model artifact and reports support the narrower environmental-index surrogate. The test reports support selected software behaviors in controlled environments. The next milestone is deployed/device verification rather than an invented new ML capability. Invite the committee to inspect a requirement, test or implementation path. Avoid saying that the number of tests proves a percentage of completion.

## Slide 24: Questions and technical discussion

Team contribution statement.

Claim boundary and presenter guidance: Both presenters. Haseeb answers architecture, Flutter, pipeline and model questions. Saim answers test design, results, IDs, traceability and limitations. Each should still explain the end-to-end system. Keep the report, test scripts, JSONL/JUnit output and model card open. If asked for unsupported effectiveness, state the evidence boundary and proposed validation. Backup slides contain execution commands and evidence references.

## Slide 25: Backup: reproducible test commands

RUN_RESULTS.md; actual test scripts; prepared Run-Demo-Tests.ps1.

Claim boundary and presenter guidance: Presenter: Saim. Commands are executable references, not claims that this slide executed them. Prepare Flutter dependencies and an isolated backend environment before evaluation. Complete backend runs require retained model/data fixtures. Record output, exit codes, timestamp and tool versions. Use a new writable pytest basetemp for each retained run. The separate PowerShell runner writes fresh output files and avoids overwriting historical evidence. With no working physical Android device, host tests remain valid within their scope but do not become device E2E evidence.

## Slide 26: Backup: evidence the committee can inspect

All supplied and repository evidence as named.

Claim boundary and presenter guidance: Both presenters. This evidence index is for committee inspection and handoff. The separate evidence map links each slide to local source artifacts. Screenshots are extracted unchanged from the attached report and are not generated UI. No terminal screenshot is fabricated; raw machine-readable results and a live targeted run are the execution evidence. The feedback statement is explicitly team-provided because no feedback form exists. The support pack lists remaining readiness artifacts.
