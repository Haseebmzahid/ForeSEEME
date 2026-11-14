import json
from pathlib import Path
for name in ['flutter-baseline','flutter-added','flutter-final']:
 p=Path('test_artifacts/chapter5')/(name+'.jsonl')
 events=[]
 for s in p.read_text(encoding='utf-8-sig').splitlines():
  try: events.append(json.loads(s))
  except ValueError: pass
 tests={e['test']['id']:e['test'] for e in events if e.get('type')=='testStart'}
 done=[e for e in events if e.get('type')=='testDone' and not tests.get(e['testID'],{}).get('name','').startswith('loading ')]
 from collections import Counter
 print(name,Counter('skipped' if e['skipped'] else e['result'] for e in done),'finished',any(e.get('type')=='done' for e in events))
 print('errors',sum(e.get('type')=='error' for e in events))
