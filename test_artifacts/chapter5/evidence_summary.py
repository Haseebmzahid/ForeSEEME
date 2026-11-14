from pathlib import Path
import json
from collections import Counter
out=Path('test_artifacts/chapter5')
def flutter(name):
 events=[]
 for line in (out/(name+'.jsonl')).read_text(encoding='utf-8-sig').splitlines():
  try: events.append(json.loads(line))
  except ValueError: pass
 tests={e['test']['id']:e['test'] for e in events if e.get('type')=='testStart'}
 done=[e for e in events if e.get('type')=='testDone' and not tests[e['testID']]['name'].startswith('loading ')]
 counts=Counter('skipped' if e['skipped'] else e['result'] for e in done)
 assert any(e.get('type')=='done' and e['success'] for e in events)
 inventory=[{'name':tests[e['testID']]['name'],'file':tests[e['testID']].get('root_url') or tests[e['testID']].get('url'),'result':'skipped' if e['skipped'] else e['result']} for e in done]
 return dict(counts=counts,total=len(done),exit_code=0,inventory=inventory)
for name in ['flutter-final','flutter-added']:
 result=flutter(name)
 (out/(name+'-summary.json')).write_text(json.dumps(result,indent=2),encoding='utf8')
 print(name,result['counts'],result['total'])
