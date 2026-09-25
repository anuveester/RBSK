"""Anonymised copy of the real Micro Plan .xlsx, for the reader test.

Keeps Excel's own XML (styles, shared strings, merged cells, date formats,
formula cached values) so the Dart reader is tested on a real Excel file,
but removes personal data exactly as gen_fixture.py does:
- rows 6-11 (staff names and mobile numbers) are emptied;
- from row 14, contact person (K) becomes "CONTACT PERSON" and contact
  number (L) keeps its length with every digit replaced by 5 (0 stays 0);
- everything right of column N is emptied;
- comments, drawings, images, printer settings and document properties are
  left out, and unused shared strings are dropped.
Usage: python anonymise_xlsx.py <real.xlsx> <out.xlsx>
"""
import re
import sys
import zipfile

SRC, OUT = sys.argv[1], sys.argv[2]
STAFF_ROWS = range(6, 12)
FIRST_DATA_ROW = 14
LAST_COL = 14  # N
CELL = re.compile(r'<c r="([A-Z]+)(\d+)"([^>]*?)(/>|>(.*?)</c>)', re.S)
SI = re.compile(r'<si>(.*?)</si>', re.S)


def col_number(letters):
    n = 0
    for ch in letters:
        n = n * 26 + (ord(ch) - 64)
    return n


def xml_text(si_inner):
    parts = re.findall(r'<t(?: [^>]*)?>(.*?)</t>', si_inner, re.S)
    return ''.join(parts)


z = zipfile.ZipFile(SRC)
sst_xml = z.read('xl/sharedStrings.xml').decode('utf-8')
old_strings = SI.findall(sst_xml)  # raw inner XML of each <si>
new_strings = []  # raw inner XML
index_of = {}


def string_ref(inner_xml):
    if inner_xml not in index_of:
        index_of[inner_xml] = len(new_strings)
        new_strings.append(inner_xml)
    return index_of[inner_xml]


def plain(text):
    return '<t>' + text + '</t>'


def attrs_without_type(attrs):
    return re.sub(r'\s+t="[^"]*"', '', attrs)


def rewrite_cell(m):
    letters, row, attrs, _, inner = m.groups()
    row, col = int(row), col_number(letters)
    ref = f'<c r="{letters}{row}"'
    base = attrs_without_type(attrs)
    t = re.search(r't="([^"]*)"', attrs)
    t = t.group(1) if t else None
    v = re.search(r'<v>(.*?)</v>', inner or '', re.S)
    v = v.group(1) if v else None
    if inner is None or (v is None and t != 'inlineStr'):
        return m.group(0) if t != 's' else ref + base + '/>'
    if row in STAFF_ROWS or col > LAST_COL:
        return ref + base + '/>'
    if row >= FIRST_DATA_ROW and col == 11:  # K: contact person
        return f'{ref}{base} t="s"><v>{string_ref(plain("CONTACT PERSON"))}</v></c>'
    if row >= FIRST_DATA_ROW and col == 12:  # L: contact number
        if t == 's':
            text = xml_text(old_strings[int(v)])
            return f'{ref}{base} t="s"><v>{string_ref(plain(re.sub(r"[0-9]", "5", text)))}</v></c>'
        if t in ('str', None) and re.fullmatch(r'-?\d+(\.0+)?', v or ''):
            digits = str(abs(int(float(v))))
            new = '0' if int(float(v)) == 0 else '5' * len(digits)
            return f'{ref}{base}><v>{new}</v></c>'
        return f'{ref}{base} t="str"><v>{re.sub(r"[0-9]", "5", v)}</v></c>'
    if t == 's':
        # Keep formula-free shared strings, re-indexed.
        return f'{ref}{base} t="s"><v>{string_ref(old_strings[int(v)])}</v></c>'
    # Numbers, dates, booleans, formulas (keep <f> and cached <v> as is).
    return m.group(0)


rels = z.read('xl/_rels/workbook.xml.rels').decode('utf-8')
keep_rels = [r for r in re.findall(r'<Relationship [^>]*/>', rels)
             if re.search(r'/(worksheet|styles|sharedStrings)"', r)]
sheet_targets = re.findall(r'Target="(worksheets/[^"]+)"', ''.join(keep_rels))

out = zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED)
for target in sheet_targets:
    xml = z.read('xl/' + target).decode('utf-8')
    head, sep, rest = xml.partition('<sheetData>')
    data, sep2, tail = rest.partition('</sheetData>')
    if not sep:  # self-closing sheetData
        out.writestr('xl/' + target, xml)
        continue
    data = CELL.sub(rewrite_cell, data)
    tail = re.sub(r'<(drawing|legacyDrawing|legacyDrawingHF|picture)\b[^>]*/>', '', tail)
    tail = re.sub(r'\s+r:id="[^"]*"', '', tail)
    out.writestr('xl/' + target, head + '<sheetData>' + data + '</sheetData>' + tail)

open_tag = re.search(r'<sst[^>]*>', sst_xml).group(0)
open_tag = re.sub(r'\s+(count|uniqueCount)="\d+"', '', open_tag)
open_tag = open_tag[:-1] + f' count="{len(new_strings)}" uniqueCount="{len(new_strings)}">'
prolog = sst_xml[:sst_xml.index('<sst')]
out.writestr('xl/sharedStrings.xml',
             prolog + open_tag + ''.join(f'<si>{s}</si>' for s in new_strings) + '</sst>')

out.writestr('xl/workbook.xml', z.read('xl/workbook.xml'))
out.writestr('xl/styles.xml', z.read('xl/styles.xml'))
out.writestr('xl/_rels/workbook.xml.rels',
             rels[:rels.index('<Relationships')] +
             '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
             + ''.join(keep_rels) + '</Relationships>')
out.writestr('_rels/.rels',
             '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
             '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
             '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
             '</Relationships>')
ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
      + ''.join(f'<Override PartName="/xl/{t}" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
                for t in sheet_targets)
      + '</Types>')
out.writestr('[Content_Types].xml', ct)
out.close()
print('ok', len(new_strings), 'strings kept of', len(old_strings))
