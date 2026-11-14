from pathlib import Path
from zipfile import ZipFile
from lxml import etree
import hashlib, json
out=Path('test_artifacts/chapter5')
files={'template':Path(r'C:/Users/HP/Downloads/Final Report Template_FA_26(BSSE Program) (1).docx'),'sds':Path(r'C:/Users/HP/Downloads/ForeSeeMe SDS final(SP23-BSE-034 & 040) (1).docx'),'srs':Path(r'C:/Users/HP/Downloads/ForeSeeMe_SRS_Updated(1) (1).docx')}
record={k:{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for k,p in files.items()}
(out/'source_hashes.json').write_text(json.dumps(record,indent=2))
(out/'artifact.md').write_text('''# Chapter 5 editing contract
Reference SDS: see source_hashes.json. Official report template controls section structure only; its media image62.jpeg has a pre-existing CRC error. Source SDS is an intact archive.
Editable slot: word/document.xml body children 1039 through 1362 (Chapter 5 until References). Chapter 5 TOC entries may be updated only to reflect new headings. All other body children and all package parts except document.xml and settings.xml are preserve-only.
Layout: source SDS two portrait Letter sections 8.5 x 11 inches, margins 1 inch on every side. Preserve section geometry, headers, footers, images, relationships, numbering and styles. New chapter follows source direct typography: Times New Roman; chapter title 18 pt; level 2 heading 14 pt; level 3 heading 12 pt; body 12 pt. Use readable tables with 9.5 pt text and repeating headers within 6.5 inch content width. New subsection paragraphs carry direct formatting without changing shared styles.
Required order: 5.1 Unit Testing; 5.2 Functional Testing; 5.3 Business Rules Testing; 5.4 Integration Testing; 5.5 Automated Testing with 5.5.1 strategy, 5.5.2 tools and environment, 5.5.3 automated test cases, 5.5.4 execution and results, 5.5.5 traceability; 5.6 Testing Summary and Environment. Table numbers 5.1 through 5.10 local to revised chapter.
Verification: compare preserved package entries byte-for-byte and all unaffected body nodes canonically; original source hashes unchanged. Bundled render_docx.py fails because no bundled LibreOffice exists; use installed Word read-only PDF export as fallback, then rasterize affected pages. Field caches may be stale; set updateFields on open. Never refresh or save the original.
''',encoding='utf8')
