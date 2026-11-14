from zipfile import ZipFile
from lxml import etree
from pathlib import Path
p=Path(r'C:/Users/HP/Downloads/ForeSeeMe_SRS_Updated(1) (1).docx')
with ZipFile(p) as z: root=etree.fromstring(z.read('word/document.xml'))
ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
lines=[' '.join(e.xpath('.//w:t/text()',namespaces=ns)) for e in root.find('w:body',ns)]
Path('test_artifacts/chapter5/srs_extract.txt').write_text('\n'.join(lines),encoding='utf8')
print('\n'.join(s for s in lines if any(x in s for x in ['FR2.','FR6.','ER1.','FR1.7','FR-2','FR-6'])))
