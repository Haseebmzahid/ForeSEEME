"""Replace only SDS Chapter 5; retain other package parts byte-for-byte."""
from copy import deepcopy
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import hashlib
import json
from lxml import etree
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_CELL_VERTICAL_ALIGNMENT

OUT = Path(__file__).resolve().parent
ROOT = OUT.parent.parent
SOURCE = Path(r'C:/Users/HP/Downloads/ForeSeeMe SDS final(SP23-BSE-034 & 040) (1).docx')
FINAL = OUT / 'ForeSeeMe_SDS_Chapter5_Revised.docx'
NS = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
flutter = json.loads((OUT / 'flutter-final-summary.json').read_text())
backend_root = etree.parse(str(OUT / 'backend-verified.xml'))
suites = backend_root.findall('.//testsuite')
backend = {k: sum(int(s.get(k, 0)) for s in suites) for k in ['tests', 'failures', 'errors', 'skipped']}
backend['passed'] = backend['tests'] - backend['failures'] - backend['errors'] - backend['skipped']
assert flutter['exit_code'] == 0
backend_ok = backend['failures'] == backend['errors'] == 0
doc = Document(SOURCE)
# Author into a temporary document using the source styles without editing them.
for child in list(doc.element.body):
    if child.tag != qn('w:sectPr'):
        doc.element.body.remove(child)


def paragraph(text, size=12, bold=False, style=None, before=0, after=7, keep=False):
    p = doc.add_paragraph(style=style)
    p.paragraph_format.space_before = Pt(before)
    p.paragraph_format.space_after = Pt(after)
    p.paragraph_format.line_spacing = 1.08
    p.paragraph_format.keep_with_next = keep
    p.paragraph_format.widow_control = True
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    r = p.add_run(text)
    r.font.name = 'Times New Roman'
    r.font.size = Pt(size)
    r.bold = bold
    r.font.color.rgb = RGBColor(0, 0, 0)
    return p


def heading(text, level=2, page=False):
    p = paragraph(text, size={1:18, 2:14, 3:12}[level], bold=True,
                  style=f'Heading {level}', before=10, after=8, keep=True)
    p.paragraph_format.page_break_before = page
    # Explicit numbers in text, no inherited automatic list numbering.
    num = p._p.get_or_add_pPr().find(qn('w:numPr'))
    if num is not None:
        p._p.pPr.remove(num)
    return p


def table(caption, headers, rows, widths):
    paragraph(caption, size=11, bold=True, before=5, after=5, keep=True)
    t = doc.add_table(rows=1, cols=len(headers))
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    for c,w in zip(t.columns,widths): c.width=Inches(w)
    for c,text,w in zip(t.rows[0].cells,headers,widths):
        c.text=text; c.width=Inches(w)
    for row in rows:
        cells=t.add_row().cells
        for c,text,w in zip(cells,row,widths): c.text=str(text); c.width=Inches(w)
    borders=OxmlElement('w:tblBorders')
    for edge in ['top','left','bottom','right','insideH','insideV']:
        b=OxmlElement('w:'+edge); b.set(qn('w:val'),'single'); b.set(qn('w:sz'),'4'); b.set(qn('w:color'),'D9D9D9'); borders.append(b)
    t._tbl.tblPr.append(borders)
    header=OxmlElement('w:tblHeader'); t.rows[0]._tr.get_or_add_trPr().append(header)
    for i,row in enumerate(t.rows):
        # Avoid breaking individual records across pages.
        trpr=row._tr.get_or_add_trPr(); trpr.append(OxmlElement('w:cantSplit'))
        for cell in row.cells:
            cell.vertical_alignment=WD_CELL_VERTICAL_ALIGNMENT.CENTER
            tcpr=cell._tc.get_or_add_tcPr()
            margins=OxmlElement('w:tcMar')
            for side in ['top','left','bottom','right']:
                m=OxmlElement('w:'+side); m.set(qn('w:w'),'80'); m.set(qn('w:type'),'dxa'); margins.append(m)
            tcpr.append(margins)
            if i==0:
                shade=OxmlElement('w:shd'); shade.set(qn('w:fill'),'E7E6E6'); tcpr.append(shade)
            for p in cell.paragraphs:
                p.paragraph_format.space_after=Pt(3); p.paragraph_format.space_before=Pt(3)
                p.paragraph_format.line_spacing=1.0
                p.paragraph_format.keep_with_next=False
                for r in p.runs:
                    r.font.name='Times New Roman'; r.font.size=Pt(9.5); r.bold=i==0; r.font.color.rgb=RGBColor(0,0,0)
    paragraph('',size=3,after=2)
    return t


heading('Chapter 5: Testing and Evaluation',1,page=True)
paragraph('ForeSeeMe was verified through executable Flutter and Python tests against the current repository. The testing focuses on medication timing, password recovery, risk-data contracts, preprocessing, and alert delivery safeguards. These areas were selected because incorrect state changes or invalid data can affect several features at once. The results reported here come from the recorded evaluation run of 15 October 2026; earlier manual pass totals are not used as current execution evidence.')
paragraph('The application uses a feature-first Flutter structure under lib/features, Riverpod for state, repository interfaces for persistence, and GoRouter for navigation. The backend contains a FastAPI inference service, scheduled computation and dispatch jobs, and ML preprocessing and training modules. Automated checks exercise these implementations with fake repositories, in-memory stores, synthetic inputs, and retained model fixtures. They do not write to production Firebase services.')
paragraph('Requirement references follow the feature tables in Chapter 2 of the SDS and the supplied updated SRS. For example, FR2.6 covers both calendar history and adherence reporting, so each mapping states the particular behaviour verified. A passing test establishes the stated scenario only; it does not establish complete satisfaction of every clause under a reused requirement ID.')

heading('5.1 Unit Testing')
paragraph('Unit tests verify domain decisions before screens and external services are involved. Existing Flutter tests cover adherence calculations, notification scheduling, risk parsing and freshness, resource prioritisation, and provider state. Backend unit tests cover schema validation, targeting, throttling, feature construction, source acquisition, and model evaluation helpers. The additions concentrate on exact dose-window boundaries, which were not directly isolated in the existing medication tests.')
paragraph('The new dose tests call DoseStateEngine.determineDoseState with an explicit clock. For an 08:00 dose, the implementation opens the action window at 07:30 and closes it at 10:00. Tests examine the exact limits and the preceding microsecond. The 30-minute lead and two-hour grace periods are current implementation policies, not numerical limits specified by FR2.2. Leap-day and midnight cases check that calendar restrictions remain effective across a date change.')
table('Table 5.1 Unit testing scope and remaining coverage', ['Area and implementation','Verification','Evidence and limit'],[
('DoseStateEngine; new tests','FSM-U01 through FSM-U09: action permissions, effective status, automatic missed flag, and stored completion interpretation.','9 executable tests passed. File A in Section 5.5.3.'),
('AdherenceAnalyticsService; existing tests','Prior-week dose-level rate and the same history fetch are checked in adherence_journey_test.dart.','Included in the final Flutter run. No clinical benefit claim follows from arithmetic correctness.'),
('Risk parsing and freshness; existing tests','Risk levels, missing attribution handling, UTC offsets and the exclusive nine-day stale boundary.','risk_estimate_model_test.dart and risk_staleness_test.dart; included in the final run. The nine-day UI policy differs from the 36-hour source freshness requirement ER1.1.'),
('Backend pure logic; existing tests','Schema limits, feature parity, condition consent, upward transitions, per-category throttle and idempotency.','backend/tests and backend/ml/tests; final outcome in Table 5.8.'),
('Remaining unit scenarios','Invalid reminder strings, overlapping medication windows, and explicit contract decisions on non-finite environmental values.','Not claimed verified by the new tests. Expected rejection or recovery behaviour needs an agreed specification before further assertions are added.')
],[1.5,2.7,2.3])

heading('5.2 Functional Testing')
paragraph('Functional checks assert outcomes visible to a user or an API consumer. Password recovery was strengthened because invalid input should be stopped before an authentication request, and a request already in progress should not be submitted twice. The widget tests render the real ForgotPasswordScreen with a fake AuthRepository. This exercises the screen and PasswordResetController together while keeping actual accounts and email delivery outside the test.')
paragraph('Two cases run the same correction workflow in light and dark themes. A malformed email shows validation feedback and produces no repository call. Correcting it to a valid address with surrounding spaces submits the trimmed address and displays the neutral success screen. A separate test controls completion with a Completer: the field becomes disabled while sending, keyboard resubmission produces no second request, and a simulated network failure restores the editable form with an error message. No arbitrary waiting period is needed for this asynchronous request.')
table('Table 5.2 Functional verification scenarios', ['Scenario','Expected and observed outcome','Method and evidence'],[
('FSM-W01-light and FSM-W01-dark','Malformed address is rejected; corrected input submits once as evaluator@example.com and shows Check your inbox. Both passed.','Automated widgets; File B; flutter-added.jsonl and flutter-final.jsonl.'),
('FSM-W02','One request while pending; input disabled; network error restores editable form. Passed.','Automated widget and controller integration; File B; controlled fake response.'),
('FSM-B01 through FSM-B08','Malformed, missing and wrongly typed API data return 422 with the expected error location/type; inference receives no call. Passed.','FastAPI TestClient with a recording model; File C.'),
('FSM-B09 and FSM-B10','Weeks 1 and 53, temperature 80 and AQI 0 are accepted unchanged by the model seam. Passed.','API boundary integration; File C; boundary response fields asserted.'),
('Device-dependent checks','Actual reset-email delivery and expiry, Google OAuth, OS reminders, notification permissions, map gestures and push delivery.','No new manual device run performed. Historical SDS observations are not counted as verified in this run.')
],[1.4,2.8,2.3])

heading('5.3 Business Rules Testing')
paragraph('Decision-oriented tests vary the conditions that allow a dose action or alert. The table separates requirement rules from implementation policies. This matters because the SRS specifies read-only history and recorded dose outcomes, but does not prescribe the precise action window used by the current implementation.')
table('Table 5.3 Business rule decisions and evidence', ['Source and condition','Expected decision','Verification and boundary'],[
('FR2.2; pending dose before / at opening','No action before 07:30; both taken and skip actions enabled at 07:30.','FSM-U01/U02 passed. Fixed 08:00 schedule; opening is the current 30-minute policy.'),
('FR2.2; pending dose before / at deadline','Actionable until just before 10:00; missed and locked at 10:00.','FSM-U03/U04 passed. Two-hour grace is implementation policy.'),
('FR2.4 and FR2.5; resolved outcome','Taken remains completed; an early confirmed skip remains Skipped; a confirmation at the deadline is Missed.','FSM-U05/U08/U09 passed. Status decisions tested; actual Firestore timestamp writes are outside these isolated tests.'),
('FR2.6; selected calendar day','Past pending dose is read-only; future-day dose remains locked even during the previous evening lead window.','FSM-U06/U07 passed. Leap-day month transition included.'),
('ER1.3; upward risk + matching condition + consent + token','A qualifying user can be targeted; absent consent or no upward transition suppresses delivery.','Existing test_e2e_pipeline.py tests for delivery, opt-out and no transition; final backend run.'),
('ER1.3; repeated event / rolling 24 hours','Repeat dispatch key is skipped; recent same-category delivery throttles another send.','Existing test_repeated_runs_produce_no_spam and test_throttle.py. Fake ledger tests do not prove deployed concurrency or Firestore security.'),
('FR6.6; invalid request body','Reject before inference; valid closed boundaries reach the model unchanged.','FSM-B01 through FSM-B10 passed. The three-second normal-load clause is unverified; no load benchmark was run.')
],[2.0,2.25,2.25])

heading('5.4 Integration Testing')
paragraph('Integration tests check the seams that carry data between components. The repository already contains backend tests that drive prediction, attribution, persistence and dispatch over an in-memory store. Flutter tests under test/integration consume fake Firestore documents through real repositories, providers and widgets. Although some filenames include e2e, these are component and contract integration tests. They do not launch a deployed backend and mobile application together.')
table('Table 5.4 Integration scope and limitations', ['Interaction','Executable implementation','Evidence and scope'],[
('Form → controller → authentication repository','File B, including FSM-W01-light/dark and FSM-W02.','Passed under flutter_test. Fake AuthRepository; no Firebase Auth call or email delivery.'),
('HTTP body → schema → inference → response','File C, FSM-B01 through FSM-B10.','Passed in TestClient. Real validation and routing; recording wrapper delegates accepted requests to StubRiskModel. These additions do not measure RF accuracy.'),
('Compute → store → dispatch → inbox','backend/tests/test_e2e_pipeline.py and test_e2e_dispatch.py.','Part of final backend run. Real job logic with in-memory storage and fake delivery; no production FCM send.'),
('Stored estimate → provider → explanation; delivered alert → inbox','test/integration/pipeline_e2e_test.dart and alert_pipeline_e2e_test.dart.','Passed in final Flutter run. FakeFirebaseFirestore; validates client composition and document shapes.'),
('Installed application → native OS / live services','No integration_test dependency or device suite currently configured.','Not executed. No connected Android device; Android licences incomplete; Windows native C++ toolchain absent. An emulator definition alone is not a running test device.')
],[1.65,2.35,2.5])
paragraph('A higher-fidelity follow-up requires a dedicated Firebase emulator project, accepted Android SDK licences, a running Android device or emulator, and the integration_test SDK dependency. It should cover a medication save, check-in persistence and notification tap with test accounts and emulator data. Native alarm timing, permission prompts and actual FCM delivery must be observed separately. No result is assigned to this unimplemented device suite.')

heading('5.5 Automated Testing')
heading('5.5.1 Automated Testing Strategy',3)
paragraph('Automation combines three layers. Pure unit tests give precise feedback on calculations and boundary decisions. Flutter widget tests drive visible state and interactions with external dependencies replaced at repository boundaries. Backend API and in-memory integration tests check validation, model and document contracts, dispatch targeting and repeated-run safeguards. The full existing suites are retained so that focused additions cannot conceal regressions elsewhere.')
paragraph('Medication windows and password recovery were selected for new Flutter coverage because they govern whether an action can be performed safely and whether errors leave the interface usable. Backend additions verify that invalid input is stopped at the HTTP boundary rather than merely testing Pydantic models in isolation. Existing feature-parity and alert pipeline tests were reused instead of duplicating their assertions. Every new test has an identifier embedded in its name or parameter ID. No production source, dependency configuration, model behaviour or database schema was changed.')
paragraph('The default Flutter run excludes four golden suites through dart_test.yaml because image comparison depends on the rendering environment. These skips remain visible in the totals. Tests in test/integration execute under flutter_test on the host and require no device. Manual usability, real email expiry, OS scheduling, live service availability and epidemiological validity are outside the automated result claims in this chapter.')

heading('5.5.2 Automation Tools and Environment',3)
table('Table 5.5 Automated testing tools and environment', ['Tool or component','Version observed','Purpose and environment'],[
('Flutter / Dart','3.44.4 / 3.12.2','Host unit, widget and component integration tests; Windows x64; app pubspec version 1.0.0+1.'),
('flutter_test','SDK bundled','Existing test runner and widget binding; no extra Flutter package added.'),
('fake_cloud_firestore','4.1.1 declared in pubspec.yaml','In-memory Firestore seam in existing tests. This is a declared dependency version constraint, not a newly installed tool.'),
('Python / pytest','3.13.7 / 9.0.3','Actual local runtime and test runner. CI specifies Python 3.12; backend requirements pin pytest 8.3.4. This local version difference is disclosed.'),
('FastAPI / Pydantic','0.138.1 / 2.13.4','TestClient routing and request/response schema validation; no HTTP server deployment.'),
('pandas / NumPy / scikit-learn','2.3.3 / 2.3.5 / 1.7.2','Existing preprocessing, frozen data, model and feature-parity checks.'),
('Operating system','Windows 11; build 26300.9711 reported by Flutter','Repository root: D:\\FYP ForeSeeMe\\fyp_foreseeme. Flutter SDK at C:\\flutter; Python at C:\\Python313\\python.exe.'),
('Device prerequisites','Android SDK 36.1.0; Java 21.0.8','One emulator definition, no connected Android device. Licences incomplete; Windows Visual Studio C++ workload absent. See flutter-doctor.log and device inventory.')
],[1.5,1.6,3.4])

heading('5.5.3 Automated Test Cases',3)
paragraph('The following script keys keep the tables readable. Paths are relative to the repository root. File A: test/features/medication/dose_state_boundaries_test.dart. File B: test/features/auth/forgot_password_screen_test.dart. File C: backend/tests/test_api_validation_boundary.py. File B extends an existing fixture and preserves its eight original tests. The new contribution is nine dose unit tests, three widget cases and ten backend parameterised or standalone cases: 22 additional executable cases.')
paragraph('Preconditions for File A are a pending 08:00 dose on 29 February 2028, unless the row states another status or date. Explicit DateTime values eliminate wall-clock dependence. File B uses a fake authentication repository and synthetic email addresses. File C uses a valid Lahore city-level request as a base and changes one field at a time; no personal health record is supplied.')
unit_rows=[
('FSM-U01','07:30 minus 1 microsecond','Upcoming; both actions disabled; no automatic missed flag.'),
('FSM-U02','Exactly 07:30','Actionable; both actions enabled; current dose true.'),
('FSM-U03','10:00 minus 1 microsecond','Taken allowed; current dose true; no auto-miss.'),
('FSM-U04','Exactly 10:00, pending','Missed; both actions disabled; auto-miss true.'),
('FSM-U05','Taken status at 12:00','Completed; effective taken; no automatic overwrite.'),
('FSM-U06','View 29 February from 1 March','Read-only; effective missed; no action or write request.'),
('FSM-U07','1 March 00:10 viewed at 29 February 23:50','Future date; both actions disabled despite lead window.'),
('FSM-U08','Missed status confirmed at 09:59, viewed next day','Displayed as Skipped; action disabled.'),
('FSM-U09','Missed status confirmed at 10:00','Displayed as Missed; no repeated auto-miss request.')]
table('Table 5.6 New Flutter automated test cases', ['Test ID','Input or interaction','Expected and actual result','File'],
[(i,s,e+' Passed.', 'A') for i,s,e in unit_rows]+[
('FSM-W01-light','Malformed then corrected padded email; light theme','Validation blocks first request; corrected trimmed email succeeds. Passed.','B'),
('FSM-W01-dark','Same correction in dark theme','Same observable validation and success behaviour. Passed.','B'),
('FSM-W02','Pending completion, keyboard resubmit, network failure','One request; field disabled then re-enabled with error. Passed.','B')], [1.0,1.8,3.25,.45])
backend_rows=[
('FSM-B01','aqi = null','422; float_type at body.aqi; zero inference calls.'),
('FSM-B02','temperature = warm','422; float_parsing at body.temperature; zero calls.'),
('FSM-B03','weekOfYear = 26.5','422; int_from_float at body.weekOfYear; zero calls.'),
('FSM-B04','city = []','422; string_type at body.city; zero calls.'),
('FSM-B05','Omit city','422; missing at body.city; zero calls.'),
('FSM-B06','Omit rainfall','422; missing at body.rainfall; zero calls.'),
('FSM-B07','Omit weekOfYear','422; missing at body.weekOfYear; zero calls.'),
('FSM-B08','Incomplete JSON body','422; json_invalid; zero inference calls.'),
('FSM-B09','week 1; temperature 80; AQI 0','200; one call with unchanged boundaries; valid response.'),
('FSM-B10','week 53; temperature 80; AQI 0','200; one call with unchanged boundaries; valid response.')]
table('Table 5.7 New backend automated test cases', ['Test ID','Input or scenario','Expected and actual result','File'],[(i,s,e+' Passed.','C') for i,s,e in backend_rows],[1,1.8,3.25,.45])
paragraph('In File C, FSM-B01 through FSM-B07 and FSM-B09/B10 appear as pytest parameter IDs. FSM-B08 is named test_FSM_B08_malformed_json_never_reaches_inference; the underscore spelling is the Python function equivalent of the displayed ID. In File B, the theme loop expands FSM-W01 into the two distinct names shown above. The machine-readable reports retain these names.')

heading('5.5.4 Automated Test Execution and Results',3)
paragraph('Commands below were run from the repository root unless a backend working directory is stated. The final Flutter execution used flutter test --no-pub --reporter json. From backend, the final complete Python command was python -m pytest -q --basetemp=../test_artifacts/chapter5/pytest-verified-temp --junitxml=../test_artifacts/chapter5/backend-verified.xml. Output was redirected to the report files named below. The --no-pub flag reused the resolved Flutter dependencies; it did not install or change them.')
table('Table 5.8 Latest verified automated execution results', ['Suite','Total','Passed','Failed','Errors','Skipped','Exit'],[
('Flutter full suite',flutter['total'],flutter['counts'].get('success',0),flutter['counts'].get('failure',0),flutter['counts'].get('error',0),flutter['counts'].get('skipped',0),0),
('Backend full suite',backend['tests'],backend['passed'],backend['failures'],backend['errors'],backend['skipped'],0 if backend_ok else 1),
('Combined reported entries',flutter['total']+backend['tests'],flutter['counts'].get('success',0)+backend['passed'],backend['failures'],backend['errors'],flutter['counts'].get('skipped',0)+backend['skipped'],'0 / 0' if backend_ok else 'See suites')
],[2,.75,.75,.75,.75,.75,.75])
paragraph('Flutter totals exclude hidden loading entries. They comprise 882 executed tests and four skipped suite placeholders emitted by the runner for golden files. The value 886 therefore counts reported entries; it does not establish how many individual golden tests would be collected if those suites were enabled. Backend totals come from testsuite attributes in the final JUnit XML. Targeted runs overlap these full-suite cases and are not added again: the two-file Flutter run passed 20 cases, comprising nine new unit cases, three new widget cases and eight retained widget tests; the new backend file passed ten cases.')
paragraph('Representative evidence is retained in test_artifacts/chapter5/flutter-final.jsonl, flutter-final-summary.json, backend-verified.log and backend-verified.xml. The targeted reports are flutter-added.jsonl and backend-added-verified.xml. The final Flutter stream ends with {"success":true,"type":"done"}; the summary records 882 successful and four skipped cases. Test IDs can be searched directly in these files. No illustrative screenshot is used as execution evidence.')
paragraph('For example, FSM-U04 asserts state == DoseAvailabilityState.missed, effectiveStatus == AdherenceStatus.missed, shouldAutoMarkMissed == true and both action permissions == false. FSM-B08 posts an incomplete JSON object, asserts HTTP 422 and json_invalid, then checks model.requests == []. These assertions link the reported outcomes to observable contracts rather than a check that execution did not crash.')
paragraph('Failure analysis: the first sandboxed backend attempt produced setup errors and at least one failure indicator before being interrupted; it did not produce a completed report and has no reliable final count. Other diagnostic attempts also stalled. Writable task-local temporary paths and a normal-permission run were used to obtain the final report. The new backend file passed in that environment. These interrupted attempts are preserved as incomplete evidence, not merged into the verified totals. No assertion or production implementation was changed to raise the pass rate.')
if backend_ok:
    paragraph('The final backend suite has no unresolved failed or errored tests. FastAPI TestClient reports a Starlette deprecation warning about httpx; it is a dependency warning, not a test failure. Any additional warning details remain in backend-verified.log. Passing model and feature-parity checks establish software consistency on the retained fixtures, not independent epidemiological validity or performance against observed disease outbreaks.')
else:
    paragraph('The final backend report contains unresolved failures or errors. Their exact node IDs and tracebacks are listed in backend-verified.log and backend-verified.xml. Production code remains unchanged; the affected requirements cannot be marked fully verified.')
paragraph('Reproducibility: use the repository CI configuration as the baseline toolchain (Flutter 3.44.4 and Python 3.12). In a clean evaluation environment, resolve Flutter dependencies with flutter pub get, then run flutter test --reporter json. In an isolated Python environment, install backend/requirements.txt, change directory to backend and run python -m pytest -q. Retained ML fixtures and the model artifact must be present for the complete backend suite. The local execution used Python 3.13.7 and pytest 9.0.3, so an evaluation using the pinned versions is a separate run, not evidence already obtained here.')
paragraph('To reproduce the exact local commands and output redirection, use RUN_RESULTS.md in the evidence folder. An evaluator can first run flutter test --no-pub test/features/medication/dose_state_boundaries_test.dart test/features/auth/forgot_password_screen_test.dart --reporter json and, from backend, python -m pytest tests/test_api_validation_boundary.py -q. These target the new contribution while preserving the full-suite commands as the regression gate. No production account, Firebase credential or destructive database operation is required.')

heading('5.5.5 Requirement Traceability for Automated Testing',3)
paragraph('The matrix uses actual FR and ER identifiers from the source requirement tables. Its status refers only to the mapped scenario. It does not imply that related untested clauses, such as email-link expiry or inference latency under load, passed. Existing tests are identified by their native function or case names rather than by invented automation IDs.')
table('Table 5.9 Requirement traceability for the new automated cases', ['Requirement and source','Implemented feature','Automated IDs','File','Outcome and qualification'],[
('FR2.2; SDS/SRS Module 2, M5','Dose status and action window','FSM-U01, FSM-U02, FSM-U03, FSM-U04','A','Passed; window lengths are current implementation policies.'),
('FR2.4; Module 2, M5','Taken completion retained','FSM-U05','A','Passed for state engine; persistence timestamp not exercised here.'),
('FR2.6; Module 2, M5','Read-only calendar history and future-day guard','FSM-U06, FSM-U07','A','Passed; leap-day transition and midnight lead window.'),
('FR2.5; Module 2, M5','Skipped versus automatic missed outcome','FSM-U08, FSM-U09','A','Passed for status interpretation; separate logging/analytics coverage remains relevant.'),
('FR1.7; Module 1, M2','Password recovery validation and correction','FSM-W01-light, FSM-W01-dark','B','Passed; real reset-email delivery and link expiry unverified.'),
('FR1.7; Module 1, M2','Single in-flight recovery request and recoverable error','FSM-W02','B','Passed with fake authentication repository.'),
('FR6.6; Module 6','Reject invalid request values before inference','FSM-B01, FSM-B02, FSM-B03, FSM-B04','C','Passed; no model invocation for invalid body fields.'),
('FR6.6; Module 6','Reject missing required request fields','FSM-B05, FSM-B06, FSM-B07','C','Passed; validation error location and missing type asserted.'),
('FR6.6; Module 6','Reject malformed JSON before inference','FSM-B08','C','Passed; function spelling uses FSM_B08.'),
('FR6.6; Module 6','Accept closed numeric and ISO-week boundaries','FSM-B09, FSM-B10','C','Passed with stub model seam; three-second latency requirement unverified.')
],[1.35,1.35,1.3,.45,2.05])
table('Table 5.10 Existing regression evidence and unresolved requirement clauses', ['Requirement','Existing executable reference or gap','Status and scope'],[
('FR5.4; feature engineering','backend/tests/test_feature_parity.py::test_frozen_inputs_reproduce_every_model_feature (train/test parameters)','Final backend report; train/serve feature consistency against frozen precursor.'),
('FR6.2 and FR6.6; classification/API','backend/tests/test_api.py::test_predict_returns_real_contract_body','Final backend report; promoted artifact response contract, not measured normal-load latency.'),
('ER1.3; eligible user alert','backend/tests/test_e2e_pipeline.py::test_full_loop_delivers_exactly_one_inbox_alert','Final backend report; synthetic consenting user, in-memory store and fake send.'),
('ER1.3; repeat suppression','backend/tests/test_e2e_pipeline.py::test_repeated_runs_produce_no_spam','Final backend report; repeated estimate produces one delivery in the fake pipeline.'),
('ER1.3; consent withdrawal','backend/tests/test_e2e_pipeline.py::test_opted_out_user_receives_nothing','Final backend report; no delivery after withdrawal.'),
('FR3.4; risk explanation','test/integration/pipeline_e2e_test.dart; native case contains stored estimate + attributions is read and EXPLAINED','Passed in Flutter final run; stored attribution rendering with fake Firestore.'),
('FR7.2; owner inbox and routing','test/integration/alert_pipeline_e2e_test.dart','Passed in Flutter final run; owner-scoped inbox, read update and deep link over fakes.'),
('FR2.6; adherence percentage','test/features/medication/adherence_journey_test.dart; computes the prior-week dose-level rate from the same 30-day fetch','Passed in Flutter final run; arithmetic and repository composition.'),
('FR9.2; Firestore rule enforcement','test_rules/firestore_rules.test.mjs exists but is outside Flutter and pytest suites.','Not executed here; fake Firestore repository tests do not enforce deployed security rules.'),
('FR5.2, FR6.1, FR6.3; source and scientific criteria','Requirements describe disease-incidence data, >40% missing-row rejection and deployment F1 threshold.','No complete compliance claim. Current environmental proxy training and its guards need separate reconciliation with these clauses.'),
('ER1.1 and FR6.4; acquisition and fallback','Existing compute_risk_freshness tests cover incomplete/latest inputs; source configuration uses Open-Meteo.','Partial evidence only. SRS names OpenWeatherMap and 36-hour flagging/fallback; equivalence requires an approved requirement update or further verification.'),
('Unresolved IDs and mappings','Earlier Chapter 5 used hyphenated IDs such as FR-5.1 for theme switching; Chapter 2 defines FR5.1 as CSV ingestion.','No theme requirement ID invented. Native theme tests run, but a reliable requirement mapping remains unresolved.')
],[1.3,3.05,2.15])

heading('5.6 Testing Summary and Environment')
paragraph(f'The final Flutter run recorded {flutter["counts"].get("success",0)} passed cases and {flutter["counts"].get("skipped",0)} intentionally skipped golden-suite entries. The final backend run recorded {backend["passed"]} passed, {backend["failures"]} failed, {backend["errors"]} errored and {backend["skipped"]} skipped cases. These framework counts are reported separately because the suites cover different components and test granularities. The combined total of 1,552 reported entries includes 1,548 executed and passed tests plus four skipped golden-suite placeholders; it is not a percentage of requirements satisfied.')
paragraph('The new contribution strengthens boundary decisions and recovery paths without changing production behaviour. Execution evidence, script IDs and requirement mappings make the work inspectable during evaluation. The repository remained on main, no existing test was removed, and no commit or push was performed. Original source documents were retained unchanged; the revised SDS is a separate file.')
paragraph('The host environment is Windows 11 with Flutter 3.44.4, Dart 3.12.2, Python 3.13.7 and pytest 9.0.3. Tests use in-memory services and retained fixtures. Native integration, live Firebase rules, real push and alarm delivery, load limits, and requirement clauses not exercised by a reliable test remain unverified. The current test outcomes therefore support software behaviour within the documented seams while leaving device, deployment and scientific validation as explicit follow-up work.')

# Compose the revised package from the original, replacing only the intended body.
with ZipFile(SOURCE) as zin:
    source_xml=etree.fromstring(zin.read('word/document.xml'))
    body=source_xml.find('w:body',NS)
    children=list(body)
    def text(e): return ''.join(e.xpath('.//w:t/text()',namespaces=NS))
    start=next(i for i,e in enumerate(children) if text(e).strip()=='Chapter 5: Testing and Evaluation')
    end=next(i for i,e in enumerate(children[start+1:],start+1) if text(e).strip().replace(' ','')=='6.References')
    new_nodes=[deepcopy(e) for e in doc.element.body if e.tag!=qn('w:sectPr')]
    for e in children[start:end]: body.remove(e)
    for offset,e in enumerate(new_nodes): body.insert(start+offset,e)
    # Preserve existing TOC field entries, correct just the renamed Chapter 5 titles.
    for e in list(body)[:start]:
        for t in e.xpath('.//w:t',namespaces=NS):
            if t.text=='5.5 Testing Summary and Evaluation': t.text='5.5 Automated Testing'
            elif t.text=='5.6 Testing Environment': t.text='5.6 Testing Summary and Environment'
    changed=etree.tostring(source_xml,xml_declaration=True,encoding='UTF-8',standalone=True)
    settings=etree.fromstring(zin.read('word/settings.xml'))
    update=settings.find('w:updateFields',NS)
    if update is None: update=etree.SubElement(settings,qn('w:updateFields'))
    update.set(qn('w:val'),'true')
    with ZipFile(FINAL,'w',ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            data=changed if item.filename=='word/document.xml' else etree.tostring(settings,xml_declaration=True,encoding='UTF-8',standalone=True) if item.filename=='word/settings.xml' else zin.read(item.filename)
            zout.writestr(item,data)
    # A chapter-only file for fallback layout inspection; never substituted for SDS.
    # QA renders the complete revised package directly.

# Verify preserved package parts and unaffected body content before delivery.
with ZipFile(SOURCE) as a, ZipFile(FINAL) as b:
    assert a.namelist()==b.namelist()
    diffs=[n for n in a.namelist() if a.read(n)!=b.read(n)]
    assert set(diffs)<= {'word/document.xml','word/settings.xml'}
    final_body=etree.fromstring(b.read('word/document.xml')).find('w:body',NS)
    fc=list(final_body)
    assert [etree.tostring(e,method='c14n',exclusive=True) for e in children[end:]] == [etree.tostring(e,method='c14n',exclusive=True) for e in fc[start+len(new_nodes):]]
    # Prefix may differ only in the two Chapter 5 TOC labels above.
    for old,new in zip(children[:start],fc[:start]):
        expected=deepcopy(old)
        for t in expected.xpath('.//w:t',namespaces=NS):
            if t.text=='5.5 Testing Summary and Evaluation': t.text='5.5 Automated Testing'
            elif t.text=='5.6 Testing Environment': t.text='5.6 Testing Summary and Environment'
        assert etree.tostring(expected,method='c14n',exclusive=True)==etree.tostring(new,method='c14n',exclusive=True)
    assert b.testzip() is None
hashes=json.loads((OUT/'source_hashes.json').read_text())
for item in hashes.values(): assert hashlib.sha256(Path(item['path']).read_bytes()).hexdigest()==item['sha256']
report={'changed_package_parts':diffs,'original_hashes_unchanged':True,'unaffected_body_preserved':True,'flutter':flutter['counts'],'backend':backend,'new_cases':22}
(OUT/'document-verification.json').write_text(json.dumps(report,indent=2))
print(FINAL)
print(json.dumps(report,indent=2))



