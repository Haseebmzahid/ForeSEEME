from zipfile import ZipFile
from lxml import etree
p='test_artifacts/chapter5/ForeSeeMe_SDS_Chapter5_Revised.docx'
with ZipFile(p) as z:r=etree.fromstring(z.read('word/document.xml'))
ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
for t in r.xpath('//w:body/*[position()<200]//w:t',namespaces=ns):
 if t.text and ('5.5' in t.text or 'Testing Summary' in t.text or 'Testing Environment' in t.text): print(repr(t.text))
