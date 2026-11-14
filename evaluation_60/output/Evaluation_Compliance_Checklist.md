# ForeSeeMe evaluation compliance checklist
Evaluation: 23 October 2026. Deck: 26 slides, with slides 25–26 as backup. Names and institution follow the supplied final report. This is the 60% evaluation stage, not a measured completion percentage.

| Committee requirement | Slides | Evidence and readiness |
|---|---|---|
| Project, members, supervisor, department/university | 1 | Supplied report front matter; official logo extracted from that report |
| Introduction limited to 1–2 slides | 2–3 | Problem, target users and solution; no numerical health-effect claim |
| SDS / 30% feedback and response | 4 | Team reports Good/OK, with no requested corrections. Subsequent work explicitly distinguished from committee feedback |
| Individual implementation and contribution | 6–13, 14–20 | Haseeb: application/backend/ML. Saim: testing/documentation. Team-reported split |
| Module purpose and technical implementation | 5, 7–13 | Native architecture diagram, source paths and report implementation screens |
| Each member live demonstration | 21, 25 | Haseeb app demo; Saim executable tests and RTM trace. Requires rehearsal and device/account |
| Unit testing | 14–15 | Actual dose-state boundary cases |
| Functional testing | 14–15 | Recovery widget scenarios with controlled dependencies |
| Business rules testing | 8, 14–16 | Dose action/deadline rules and API validation |
| Integration testing | 14, 17, 20 | Host repository/provider/backend integration; explicitly not device E2E |
| Justification of testing techniques | 14 | Determinism, UI behavior, contracts and pipeline composition |
| Test cases, expected/actual and pass/fail | 15–16, 18 | Script identifiers and retained results; matched assertions summarized |
| Failed tests and current status | 18, 20 | Completed full runs have zero failures. Interrupted runs have no reliable final count. Skips and operational gaps disclosed |
| Mandatory automation strategy and frameworks | 14, 17 | flutter_test, fake_cloud_firestore, pytest and TestClient |
| Implemented core features selected for automation | 14–16, 19 | Medication decisions, recovery and prediction API boundary |
| Positive and negative scenarios | 15–16 | Exact opening/deadline, invalid fields, corrected forms, valid ISO week endpoints |
| Actual automated identifiers | 15–16, 19 | FSM IDs resolve to source and reports. B08 function spelling explicitly shown |
| Execution evidence / live run | 17–18, 21, 25 | Retained full-run JSONL/JUnit; fresh targeted evidence in evidence/; runnable PowerShell script |
| Executed / passed / failed counts | 18 | Retained 882 Flutter + 666 backend passes. Four skipped golden-suite placeholders excluded from executed count |
| FR-to-test RTM | 19, 26 | Supplied report §5.5.5; partial clauses and legacy-ID conflicts disclosed |
| AI/ML technique, rationale, data, results | 12–13 | Implemented Random Forest environmental-index surrogate; detailed preparation and split in notes |
| Remaining modules / integrations / challenges | 20, 22 | Cloud/device verification, requirement reconciliation and acceptance work |
| Concise readable slides and purposeful visuals | Throughout | Report screenshots, native diagrams/tables; all slides rendered and visually inspected |
| Individual technical defense preparation | Notes throughout | Separate Technical_Defense_Preparation.md |
| Conclusion and Q&A | 23–24 | Verified foundation and next release gate |

## Readiness boundaries

- Full runs are retained evidence from 15 October; fresh targeted rehearsal on 21 October passed 20 Flutter and 10 backend tests. These overlap the full suites and are not added to their totals.
- The four Flutter skipped records are suite placeholders. No individual golden-test skip count is inferred.
- Real device/cloud acceptance, requirement latency and clinical/scientific incidence validation are not established.
- No specific prior committee corrections exist according to the team, so none are invented.
- The supplied report mixes legacy requirement labels and historical design statements. The deck uses explicit partial mappings and the implemented model card where implementation differs.
- PowerPoint package, geometry, fonts, native tables and re-import passed validation. Visual inspection used rendered slides, not a native PowerPoint presentation session.
