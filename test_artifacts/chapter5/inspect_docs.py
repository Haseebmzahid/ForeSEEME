from pathlib import Path
from zipfile import ZipFile
from lxml import etree
import hashlib
out=Path('test_artifacts/chapter5')
for label,name in [('template','Final Report Template_FA_26(BSSE Program) (1).docx'),('sds','ForeSeeMe SDS final(SP23-BSE-034 & 040) (1).docx')]:
 p=Path('C:/Users/HP/Downloads')/name
 with ZipFile(p) as z: root=etree.fromstring(z.read('word/document.xml'))
 ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
 lines=[f'{i}: '+ ' '.join(e.xpath('.//w:t/text()',namespaces=ns)) for i,e in enumerate(root.find('w:body',ns))]
 (out/(label+'_extract.txt')).write_text('\n'.join(lines),encoding='utf-8')
 print(label,len(lines),hashlib.sha256(p.read_bytes()).hexdigest())
 print('\n'.join(x for x in lines if any(s in x.lower() for s in ['5.1','5.2','5.3','5.4','5.5','5.6','chapter 5','automated testing'])))
