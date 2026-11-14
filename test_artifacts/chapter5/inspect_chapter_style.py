from docx import Document
p=r'C:/Users/HP/Downloads/ForeSeeMe SDS final(SP23-BSE-034 & 040) (1).docx'
d=Document(p)
for i,e in enumerate(d.element.body):
 if 1039<=i<=1057:
  from docx.text.paragraph import Paragraph
  if e.tag.endswith('}p'):
   q=Paragraph(e,d);print(i,q.text,q.style.name,[(r.font.name,r.font.size.pt if r.font.size else None,r.bold) for r in q.runs[:3]])
