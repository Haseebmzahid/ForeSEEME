# Technical defense preparation
Use these answers within their evidence boundary. Haseeb leads architecture/application/ML questions, Saim leads verification and documentation. Both should understand the complete path.

1. **What does ForeSeeMe estimate?**
   City-week environmental suitability for dengue, smog/respiratory and influenza, expressed as Low/Medium/High with confidence. It supports preparedness. It does not estimate an individual's diagnosis or predict outbreak case counts. Source: MODEL_CARD.md.

2. **What does 60% mean here?**
   The committee evaluation stage. We have not measured 60% code completion or 60% requirement satisfaction. We show implemented artifacts and explicit verification gaps.

3. **What did the earlier evaluators ask you to fix?**
   The team received Good/OK remarks and no specific corrections. Subsequent implementation and testing improvements were team-led. There is no fabricated feedback-to-action story.

4. **Who did what?**
   Muhammad Haseeb leads Flutter implementation, backend/AI/ML and PPT preparation. Saim Zulfiqar leads testing and documentation. This is the team's stated allocation, not exclusive file-level authorship established by a commit audit.

5. **Why Flutter and Riverpod?**
   Flutter provides the shared mobile UI. Riverpod manages state, dependency injection and reactive repository data. Feature-scoped presentation/domain/data code separates UI behavior from external I/O, making controlled testing practical.

6. **Why Firestore as the risk source?**
   ADR-001 selects a single shared collection, riskEstimates. Backend compute writes estimates and Flutter reads them. This avoids conflicting client prediction paths and decouples UI from inference uptime. The tradeoff is freshness, which needs visible timestamps and stale-data handling.

7. **Does the mobile client call /predict?**
   No. The endpoint belongs to the internal backend inference surface. The app consumes Firestore risk records. The prediction endpoint's tests do not imply that the client directly calls it.

8. **How does medication timing work?**
   DoseStateEngine evaluates date, scheduled time, recorded status and the action/deadline window. The implemented policy uses a 30-minute lead and two-hour grace. These numerical windows are implementation choices rather than numeric SRS clauses. Taken outcomes remain completed; future calendar days are guarded and past days read-only.

9. **What proves notification delivery?**
   Current tests prove scheduling/targeting and messaging-adapter behavior under controlled dependencies. They do not prove device permissions, alarm timing or real FCM delivery. Physical-device and deployed-service acceptance are remaining work.

10. **How do alerts avoid duplicates?**
    Dispatch logic applies risk-transition eligibility, user consent/context, estimate-specific idempotency and category throttling. Existing pipeline tests exercise repeated estimates. A controlled test is a software guarantee within that seam, not evidence that a production scheduler has run.

11. **What automation tools are used?**
    flutter_test for unit/widget/host integration cases, fake_cloud_firestore for selected repository checks, pytest for backend/ML tests, and FastAPI TestClient for API behavior. CI YAML configures both stacks. We do not claim a remote CI pass without an actual run record.

12. **How many tests passed?**
    Retained 15 October complete runs: 882 Flutter and 666 backend tests, totaling 1,548 executed passes with zero failures. Four Flutter skipped golden-suite placeholders are separate. Fresh 21 October targeted rehearsal: 20 Flutter plus 10 API passes. Those overlap the full suites, so they are not added.

13. **Are those 1,548 requirements or manual cases?**
    No. They are framework-level executed test cases across different components and granularities. They do not measure code coverage, requirement satisfaction or clinical effectiveness. The separate documentation catalogue is not added to the count.

14. **Show one positive and one negative case.**
    FSM-U02 verifies the exact opening boundary allows actions. FSM-U01 verifies one microsecond earlier stays locked. For the API, FSM-B01-null-aqi rejects invalid input with HTTP 422 and zero model calls, while FSM-B09-first-iso-week accepts week 1 and calls the stub once unchanged.

15. **Why is the API model replaced in validation tests?**
    RecordingModel isolates request validation from ML inference. Invalid input must never reach predict, while valid boundary input must reach it once. Separate model tests/artifacts establish other behaviors. These route tests do not measure Random Forest accuracy or the three-second requirement.

16. **What is the RTM mapping and its limitation?**
    FR1.7 maps to FSM-W01-light, FSM-W01-dark and FSM-W02. They verify recovery input and request states, not actual email/link expiry. FR6.6 maps to API boundary cases, without proving every clause. Report §5.5.5 is the detailed matrix. Legacy hyphenated IDs and reused UI IDs require clause-level reconciliation.

17. **Are your integration tests mobile end-to-end tests?**
    No. Existing Flutter test/integration files execute as host widget/provider compositions. Native integration_test device coverage is not implemented/executed in the retained evidence. Backend integration tests similarly use controlled fixtures/adapters for specified boundaries.

18. **Were any tests failed or skipped?**
    Completed retained full runs have zero failures. Four Flutter suite placeholders were intentionally skipped. Some earlier diagnostic attempts were interrupted without reliable results, and a historical deadline regression in a focused deployment correction was fixed. We do not treat incomplete attempts as passes or sum focused suites into the complete results.

19. **What is the dataset?**
    Open-Meteo ERA5 weather and CAMS air quality for Islamabad, Rawalpindi, Lahore, Karachi and Peshawar. The retained model card gives 5 August 2022–28 June 2026, weekly preparation and 735 training / 260 test city-week rows. Disease-incidence records are not the training labels of the implemented artifact.

20. **Why Random Forest?**
    It handles nonlinear relationships and interactions in modest tabular environmental data. Each disease has a saved scikit-learn pipeline with median imputation, scaling and a class-balanced RandomForestClassifier. Scaling is a shared pipeline step, not a requirement of decision trees. TimeSeriesSplit supports chronological tuning.

21. **What are the features and leakage controls?**
    The model card documents 36 engineered features, including weather/AQI, 1–4-week lags, rolling means, seasonal anomalies, cyclic week and city encodings. The test block is the most recent temporal block, not a shuffled sample. Inspect feature_dictionary.md and preprocessing code for exact feature construction rather than inventing an input list.

22. **Why are accuracy scores high?**
    Labels derive from the environmental index and its input determinants. The model is a surrogate of that index, so accuracy largely describes index fidelity. Retained accuracies are 0.854 dengue, 0.954 smog and 0.908 influenza. They do not establish outbreak prediction or clinical validity.

23. **Why use ML instead of the deterministic index directly?**
    The index is a valid baseline and the committee can challenge the extra model complexity. The current implementation investigates a supervised approximation with probabilities and tree-derived contributions. No comparative evidence proves ML improves health outcomes or outperforms the index operationally. A formal index-versus-model comparison and stronger independent labels would strengthen the justification.

24. **What are confidence and explanations?**
    Confidence derives from model class output, not a personal disease probability. Stored feature attributions use tree-path contributions, rendered with deterministic templates. No LLM/NLP medical reasoning is claimed. Feature contribution is not causality. The reports discuss calibration, but baseline metrics and a later sigmoid assessment must not be conflated with a verified deployed calibrated artifact.

25. **Your report says historical disease incidence. Why does the deck say suitability?**
    That report statement reflects a broader design narrative. The versioned artifact, label methodology and model card establish the narrower implemented scope. We use those for implementation claims and list document/requirement reconciliation as outstanding work. We do not disguise the discrepancy.

26. **What remains for release?**
    Billing and deployed compute/dispatch verification, physical-device alarms/FCM/OAuth/reset checks, security and load/latency acceptance, requirements/provider/ID reconciliation, and user evaluation. The roadmap is a proposed release-gate sequence; no unsupported final completion date is promised.

27. **What if the live demo fails?**
    Preserve the actual failure and identify its boundary. Show dated retained raw results and report-captured UI, then run the independent deterministic seam if possible. Never label fallback screenshots or old results as a successful current live run.
