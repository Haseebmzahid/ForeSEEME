from pypdf import PdfReader
from pathlib import Path
p=Path('test_artifacts/chapter5')
d=PdfReader(p/'sds-review.pdf')
for i,page in enumerate(d.pages):
 s=page.extract_text()
 if '5.1 Unit Testing' in s and i>30: print('START',i+1)
 if '5.6 Testing Summary' in s and i>30: print('END',i+1)
 if i>95: print(i+1,s[:95].replace('\n',' | '))
