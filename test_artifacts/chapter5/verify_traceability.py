from pathlib import Path
from lxml import etree
import json,re
from zipfile import ZipFile
base=Path('test_artifacts/chapter5')
f=json.loads((base/'flutter-final-summary.json').read_text())
new=[r for r in f['inventory'] if 'FSM-' in r['name']]
assert len(new)==12 and all(r['result']=='success' for r in new)
b=etree.parse(str(base/'backend-verified.xml'))
newb=[r for r in b.findall('.//testcase') if 'test_api_validation_boundary' in r.get('classname','')]
assert len(newb)==10 and all(len(r)==0 for r in newb)
with ZipFile(base/'ForeSeeMe_SDS_Chapter5_Revised.docx') as z:
 root=etree.fromstring(z.read('word/document.xml'))
 text=' '.join(root.xpath('//*[local-name()="t"]/text()'))
 for i in range(1,10): assert f'FSM-U{i:02}' in text
 for key in ['FSM-W01-light','FSM-W01-dark','FSM-W02']+[f'FSM-B{i:02}' for i in range(1,11)]: assert key in text
 for heading in ['5.1 Unit Testing','5.2 Functional Testing','5.3 Business Rules Testing','5.4 Integration Testing','5.5.1 Automated Testing Strategy','5.5.2 Automation Tools and Environment','5.5.3 Automated Test Cases','5.5.4 Automated Test Execution and Results','5.5.5 Requirement Traceability for Automated Testing','5.6 Testing Summary and Environment']: assert heading in text
 assert 'All 162 test cases passed' not in text
report={'new_flutter_cases_verified':12,'new_backend_cases_verified':10,'all_new_ids_present_in_document':True,'all_required_headings_present':True,'new_cases':new,'backend_cases':[r.get('name') for r in newb]}
(base/'traceability-verification.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('22 new executable cases passed and every ID appears in the revised Chapter 5. Required headings verified.')
