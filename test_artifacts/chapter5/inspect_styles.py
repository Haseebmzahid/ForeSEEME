from zipfile import ZipFile
from pathlib import Path
from docx import Document
p=Path(r'C:/Users/HP/Downloads/ForeSeeMe SDS final(SP23-BSE-034 & 040) (1).docx')
with ZipFile(p) as z: print('SDS archive integrity:',z.testzip())
d=Document(p)
for s in d.sections: print('section',s.page_width.inches,s.page_height.inches,s.top_margin.inches,s.bottom_margin.inches,s.left_margin.inches,s.right_margin.inches)
for name in ['Normal','Heading 1','Heading 2','Heading 3']:
 s=d.styles[name]; print(name,s.font.name,s.font.size.pt if s.font.size else None,s.paragraph_format.line_spacing)
