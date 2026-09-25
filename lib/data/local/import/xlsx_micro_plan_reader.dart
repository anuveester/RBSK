import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:referredline/domain/services/micro_plan/micro_plan_models.dart';
import 'package:xml/xml.dart';

/// The file could not be read as an Excel .xlsx workbook.
class XlsxReadException implements Exception {
  const XlsxReadException(this.message);

  final String message;

  @override
  String toString() => 'XlsxReadException: $message';
}

/// Reads an .xlsx file into plain grids for the Micro Plan parser.
///
/// Deliberately small: only what the parser needs — cell values (shared and
/// inline strings, numbers, booleans, and the cached result of formula
/// cells), which numbers are dates (from the cell's number format), and
/// merged ranges. Styles, images and comments are ignored.
///
/// Every step mirrors tool/micro_plan/xlsx_ref.py, which was checked cell by
/// cell against openpyxl on the real 2025-26 workbook.
class XlsxMicroPlanReader {
  const XlsxMicroPlanReader();

  /// Excel's built-in number formats that show dates (14–22, 45–47).
  static final Set<int> _builtInDateFormats = {
    for (var id = 14; id <= 22; id++) id,
    45,
    46,
    47,
  };

  static final RegExp _cellRef = RegExp(r'^([A-Z]+)(\d+)$');
  static final RegExp _integer = RegExp(r'^-?\d+$');
  static final RegExp _quoted = RegExp('"[^"]*"');
  static final RegExp _bracketed = RegExp(r'\[[^\]]*\]');
  static final RegExp _escaped = RegExp(r'\\.');
  static final RegExp _dateLetters = RegExp('[dmyhs]', caseSensitive: false);

  List<MicroPlanSheetInput> read(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      throw const XlsxReadException(
        'This file is not an Excel .xlsx workbook.',
      );
    }

    final workbook = _xml(archive, 'xl/workbook.xml');
    final relations = _xml(archive, 'xl/_rels/workbook.xml.rels');
    if (workbook == null || relations == null) {
      throw const XlsxReadException(
        'This file is not an Excel .xlsx workbook.',
      );
    }

    final workbookPr = _first(workbook.rootElement, 'workbookPr');
    final date1904 = const {
      '1',
      'true',
    }.contains(workbookPr?.getAttribute('date1904'));

    final targets = <String, String>{
      for (final rel in _all(relations.rootElement, 'Relationship'))
        rel.getAttribute('Id') ?? '': rel.getAttribute('Target') ?? '',
    };

    final sharedStrings = [
      for (final si in _children(
        _xml(archive, 'xl/sharedStrings.xml')?.rootElement,
        'si',
      ))
        _textOf(si),
    ];
    final dateStyles = _dateStyles(_xml(archive, 'xl/styles.xml'));

    final sheetsElement = _first(workbook.rootElement, 'sheets');
    final sheets = <MicroPlanSheetInput>[];
    for (final sheet in _children(sheetsElement, 'sheet')) {
      final relationId = sheet.attributes
          .where((a) => a.name.local == 'id' && a.name.prefix != null)
          .map((a) => a.value)
          .firstOrNull;
      var target = targets[relationId] ?? '';
      if (target.startsWith('/')) target = target.substring(1);
      if (!target.startsWith('xl/')) target = 'xl/$target';
      final document = _xml(archive, target);
      if (document == null) {
        throw XlsxReadException(
          'Sheet "${sheet.getAttribute('name')}" is missing from the file.',
        );
      }
      sheets.add(
        _readSheet(
          sheet.getAttribute('name') ?? '',
          document.rootElement,
          sharedStrings,
          dateStyles,
          date1904,
        ),
      );
    }
    return sheets;
  }

  MicroPlanSheetInput _readSheet(
    String name,
    XmlElement worksheet,
    List<String> sharedStrings,
    Set<int> dateStyles,
    bool date1904,
  ) {
    // Row number (1-based) → column index (0-based) → value.
    final rows = <int, Map<int, Object?>>{};
    var nextRow = 1;
    for (final row in _all(worksheet, 'row')) {
      final rowNumber = int.tryParse(row.getAttribute('r') ?? '') ?? nextRow;
      nextRow = rowNumber + 1;
      final cells = rows.putIfAbsent(rowNumber, () => {});
      var nextColumn = 0;
      for (final cell in _children(row, 'c')) {
        final ref = cell.getAttribute('r');
        final column = ref == null ? nextColumn : _position(ref).column;
        nextColumn = column + 1;
        cells[column] = _cellValue(cell, sharedStrings, dateStyles, date1904);
      }
    }

    final merges = <MicroPlanMerge>[];
    for (final merge in _children(_first(worksheet, 'mergeCells'), 'mergeCell')) {
      final parts = (merge.getAttribute('ref') ?? '').split(':');
      if (parts.length != 2) continue;
      final start = _position(parts[0]);
      final end = _position(parts[1]);
      merges.add(
        MicroPlanMerge(
          firstRow: start.row,
          lastRow: end.row,
          firstColumn: start.column + 1,
          lastColumn: end.column + 1,
        ),
      );
    }

    // Only the top-left cell of a merged range has a value; Excel keeps
    // stale cached values in the covered cells, which it never shows.
    for (final m in merges) {
      for (var r = m.firstRow; r <= m.lastRow; r++) {
        final cells = rows[r];
        if (cells == null) continue;
        for (var c = m.firstColumn - 1; c < m.lastColumn; c++) {
          final isTopLeft = r == m.firstRow && c == m.firstColumn - 1;
          if (!isTopLeft && cells.containsKey(c)) cells[c] = null;
        }
      }
    }

    // Trailing rows that are formatted but blank are dropped.
    var lastFilledRow = 0;
    for (final entry in rows.entries) {
      final filled = entry.value.values.any((v) => v != null && v != '');
      if (filled && entry.key > lastFilledRow) lastFilledRow = entry.key;
    }

    final grid = <List<Object?>>[];
    for (var r = 1; r <= lastFilledRow; r++) {
      final cells = rows[r] ?? const <int, Object?>{};
      var width = 0;
      for (final entry in cells.entries) {
        if (entry.value != null && entry.key + 1 > width) {
          width = entry.key + 1;
        }
      }
      grid.add([for (var c = 0; c < width; c++) cells[c]]);
    }

    return MicroPlanSheetInput(name: name, rows: grid, merges: merges);
  }

  Object? _cellValue(
    XmlElement cell,
    List<String> sharedStrings,
    Set<int> dateStyles,
    bool date1904,
  ) {
    final type = cell.getAttribute('t');
    final raw = _first(cell, 'v')?.innerText;
    switch (type) {
      case 's':
        final index = int.tryParse(raw ?? '');
        if (index == null || index < 0 || index >= sharedStrings.length) {
          return null;
        }
        return sharedStrings[index];
      case 'inlineStr':
        final inline = _first(cell, 'is');
        return inline == null ? null : _textOf(inline);
      case 'str':
      case 'e':
        return raw;
      case 'b':
        return raw == null ? null : raw == '1';
      case 'd':
        return raw == null || raw.isEmpty ? null : DateTime.tryParse(raw);
    }
    if (raw == null || raw.isEmpty) return null;
    final num number = _integer.hasMatch(raw)
        ? int.parse(raw)
        : double.parse(raw);
    final style = int.tryParse(cell.getAttribute('s') ?? '') ?? 0;
    if (dateStyles.contains(style)) {
      return _serialToDate(number.toDouble(), date1904);
    }
    return number;
  }

  /// Style indexes (positions in `cellXfs`) whose number format is a date.
  Set<int> _dateStyles(XmlDocument? styles) {
    if (styles == null) return const {};
    final customFormats = <int, String>{
      for (final format in _children(
        _first(styles.rootElement, 'numFmts'),
        'numFmt',
      ))
        int.tryParse(format.getAttribute('numFmtId') ?? '') ?? -1:
            format.getAttribute('formatCode') ?? '',
    };
    final result = <int>{};
    final formats = _children(_first(styles.rootElement, 'cellXfs'), 'xf');
    var index = 0;
    for (final xf in formats) {
      final id = int.tryParse(xf.getAttribute('numFmtId') ?? '') ?? 0;
      final code = customFormats[id];
      if (_builtInDateFormats.contains(id) ||
          (code != null && _isDateFormatCode(code))) {
        result.add(index);
      }
      index++;
    }
    return result;
  }

  static bool _isDateFormatCode(String code) {
    final visible = code
        .replaceAll(_quoted, '')
        .replaceAll(_bracketed, '')
        .replaceAll(_escaped, '');
    return _dateLetters.hasMatch(visible);
  }

  static DateTime _serialToDate(double serial, bool date1904) {
    final DateTime base;
    if (date1904) {
      base = DateTime.utc(1904);
    } else if (serial < 60) {
      base = DateTime.utc(1899, 12, 31);
    } else {
      base = DateTime.utc(1899, 12, 30);
    }
    return base.add(Duration(milliseconds: (serial * 86400000).round()));
  }

  /// Plain `<t>`, or the `<t>` of each `<r>` run; phonetic `<rPh>` skipped.
  static String _textOf(XmlElement element) {
    final buffer = StringBuffer();
    for (final child in element.childElements) {
      if (child.name.local == 't') {
        buffer.write(child.innerText);
      } else if (child.name.local == 'r') {
        buffer.write(_first(child, 't')?.innerText ?? '');
      }
    }
    return buffer.toString();
  }

  /// "B14" → row 14, column 1 (0-based).
  static ({int row, int column}) _position(String ref) {
    final match = _cellRef.firstMatch(ref.trim().toUpperCase());
    if (match == null) {
      throw XlsxReadException('Unexpected cell reference "$ref".');
    }
    var column = 0;
    for (final unit in match.group(1)!.codeUnits) {
      column = column * 26 + (unit - 64);
    }
    return (row: int.parse(match.group(2)!), column: column - 1);
  }

  static XmlDocument? _xml(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null) return null;
    final bytes = file.readBytes();
    if (bytes == null) return null;
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    try {
      return XmlDocument.parse(text);
    } on XmlException {
      throw XlsxReadException('Part "$path" of the file is damaged.');
    }
  }

  /// Direct children with this local name (any namespace prefix).
  static Iterable<XmlElement> _children(XmlElement? parent, String local) =>
      parent == null
      ? const <XmlElement>[]
      : parent.childElements.where((e) => e.name.local == local);

  static XmlElement? _first(XmlElement? parent, String local) =>
      _children(parent, local).firstOrNull;

  /// All descendants with this local name, in document order.
  static Iterable<XmlElement> _all(XmlElement root, String local) =>
      root.descendantElements.where((e) => e.name.local == local);
}
