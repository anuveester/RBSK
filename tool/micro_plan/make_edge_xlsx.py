"""Tiny hand-written .xlsx covering reader edge cases the real file lacks:
rich-text and inline strings, booleans, a custom and a built-in date format,
an ISO date cell, a stale value inside a merged range, cells without an r=
attribute, a prefixed (x:) namespace, and trailing formatted-but-empty rows.
Usage: python make_edge_xlsx.py <out.xlsx>"""
import sys, zipfile
M = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
P = 'http://schemas.openxmlformats.org/package/2006/relationships'
wb = (f'<?xml version="1.0" encoding="UTF-8"?><x:workbook xmlns:x="{M}" xmlns:r="{R}">'
      '<x:sheets><x:sheet name="APRIL25" sheetId="1" r:id="rId7"/></x:sheets></x:workbook>')
rels = (f'<?xml version="1.0"?><Relationships xmlns="{P}">'
        '<Relationship Id="rId7" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/data.xml"/>'
        '</Relationships>')
sst = (f'<?xml version="1.0"?><sst xmlns="{M}" count="2" uniqueCount="2">'
       '<si><t xml:space="preserve"> LAGON </t></si>'
       '<si><r><t>JAKHAURA-</t></r><r><rPr><b/></rPr><t>1+2</t></r><rPh sb="0" eb="1"><t>IGNORED</t></rPh></si>'
       '</sst>')
styles = (f'<?xml version="1.0"?><styleSheet xmlns="{M}"><numFmts count="1">'
          '<numFmt numFmtId="164" formatCode="d/m/yyyy;@"/></numFmts>'
          '<cellXfs count="4"><xf numFmtId="0"/><xf numFmtId="164"/><xf numFmtId="14"/>'
          '<xf numFmtId="165"/></cellXfs></styleSheet>')
sheet = (f'<?xml version="1.0"?><x:worksheet xmlns:x="{M}"><x:sheetData>'
         '<x:row r="1"><x:c r="A1" t="s"><x:v>0</x:v></x:c><x:c r="B1" t="s"><x:v>1</x:v></x:c>'
         '<x:c r="C1" t="inlineStr"><x:is><x:t>INLINE &amp; TEXT</x:t></x:is></x:c>'
         '<x:c r="D1" t="b"><x:v>1</x:v></x:c><x:c r="E1"><x:v>9370301901</x:v></x:c>'
         '<x:c r="F1"><x:v>2.5</x:v></x:c></x:row>'
         '<x:row r="2"><x:c r="A2" s="1"><x:v>45661</x:v></x:c><x:c r="B2" s="2"><x:v>45748.5</x:v></x:c>'
         '<x:c r="C2" t="d"><x:v>2025-04-13T00:00:00</x:v></x:c><x:c r="D2" s="3"><x:v>7</x:v></x:c>'
         '<x:c r="E2" t="str"><x:f>UPPER(X)</x:f><x:v>TUESDAY</x:v></x:c></x:row>'
         '<x:row r="3"><x:c r="A3"><x:v>1</x:v></x:c><x:c><x:v>2</x:v></x:c><x:c><x:v>3</x:v></x:c></x:row>'
         '<x:row r="4"><x:c r="M4" t="str"><x:v>STALE</x:v></x:c></x:row>'
         '<x:row r="6" s="5" customFormat="1"><x:c r="A6" s="1"/></x:row>'
         '<x:row r="9"><x:c r="B9" t="s"/></x:row>'
         '</x:sheetData><x:mergeCells count="1"><x:mergeCell ref="M3:M4"/></x:mergeCells></x:worksheet>')
z = zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED)
for name, data in [('xl/workbook.xml', wb), ('xl/_rels/workbook.xml.rels', rels),
                   ('xl/sharedStrings.xml', sst), ('xl/styles.xml', styles),
                   ('xl/worksheets/data.xml', sheet)]:
    z.writestr(name, data)
z.close()
