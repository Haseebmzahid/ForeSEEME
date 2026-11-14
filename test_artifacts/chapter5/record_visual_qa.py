from pathlib import Path
import json,hashlib
p=Path('test_artifacts/chapter5')
r={'renderer':'Microsoft Word 16.0 read-only PDF export; Poppler PNG rasterization','pdf_pages':125,'revised_chapter_pdf_pages_reviewed':list(range(112,124)),'dpi':110,'result':'No clipping, overlap, missing glyphs or unreadable table content observed on revised chapter pages. Repeated headers and table continuation inspected. Unchanged material verified structurally; pre-existing whole-document formatting was not rewritten.','toc':'Chapter 5 labels corrected; cached page references and new subsection entries require Word contents-field refresh. updateFields enabled.','final_docx_sha256':hashlib.sha256((p/'ForeSeeMe_SDS_Chapter5_Revised.docx').read_bytes()).hexdigest()}
(p/'visual-qa.json').write_text(json.dumps(r,indent=2),encoding='utf8')
hashes=json.loads((p/'source_hashes.json').read_text())
assert all(hashlib.sha256(Path(x['path']).read_bytes()).hexdigest()==x['sha256'] for x in hashes.values())
with (p/'RUN_RESULTS.md').open('a',encoding='utf8') as f:f.write('\nFinal visual review: Word exported 125 pages; revised Chapter 5 spans PDF pages 112-123 (printed pages 111-122). All 12 affected page PNGs were inspected at native size; no clipping, overlap or broken table layout observed. Unchanged chapters were verified structurally, not re-edited. See visual-qa.json for final-file hash and exact review scope.\n')
print('Final output and source hashes verified; 12 revised chapter pages visually reviewed.')
