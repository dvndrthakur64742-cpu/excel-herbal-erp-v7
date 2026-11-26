import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Read-only print layout. Never silently drops columns or truncates records.
/// Wide reports are split into column groups with a common source row number.
abstract final class ReportPrintDocument {
  static const maxRows = 1000;
  static const maxColumns = 32;
  static const columnsPerPage = 7;
  static const maxCellLength = 180;

  static String printable(String text) => text
      .replaceAll('₹', 'INR ')
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('·', ' / ')
      .replaceAll('’', "'")
      .replaceAll('‘', "'")
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ');

  static String? limitation({
    required String title,
    required String scope,
    required List<String> columns,
    required List<List<String>> rows,
  }) {
    if (rows.isEmpty || columns.isEmpty) return 'No records to print.';
    if (rows.length > maxRows || columns.length > maxColumns) {
      return 'PDF supports up to 1,000 rows and 32 columns. Narrow the report or use Excel / CSV.';
    }
    if (rows.any((row) => row.length != columns.length)) {
      return 'Report columns do not match the saved records.';
    }
    for (final value in [title, scope, ...columns, for (final row in rows) ...row]) {
      final text = printable(value);
      if (text.length > maxCellLength) {
        return 'Some report text is too long for the print layout. Use Excel / CSV.';
      }
      // Built-in PDF fonts cannot faithfully render all writing systems.
      // Do not print missing glyphs or silently transliterate business records.
      if (text.runes.any((r) => r < 32 || r > 126)) {
        return 'Some text requires a Unicode font not bundled with the printer. Use Excel / CSV.';
      }
    }
    return null;
  }

  static List<List<int>> columnGroups(int count) => [
    for (var start = 0; start < count; start += columnsPerPage)
      [for (var i = start; i < count && i < start + columnsPerPage; i++) i],
  ];

  static Future<Uint8List> build({
    required String title,
    required String scope,
    required List<String> columns,
    required List<List<String>> rows,
    String? note,
  }) async {
    final error = limitation(title: title, scope: scope, columns: columns, rows: rows);
    if (error != null) throw FormatException(error);
    final doc = pw.Document();
    final groups = columnGroups(columns.length);
    for (var group = 0; group < groups.length; group++) {
      final indexes = groups[group];
      final first = indexes.first + 1;
      final last = indexes.last + 1;
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        maxPages: 200,
        header: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.green800, width: 1.5)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('EXCEL HERBAL ERP', style: pw.TextStyle(
                color: PdfColors.green800, fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text(printable(title), style: pw.TextStyle(
                fontSize: 17, fontWeight: pw.FontWeight.bold)),
              pw.Text(printable(scope), style: const pw.TextStyle(fontSize: 9)),
              pw.Text('${rows.length} records | Columns $first-$last of ${columns.length}',
                style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Excel Herbal ERP | Saved record export', style: const pw.TextStyle(fontSize: 8)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8)),
          ]),
        ),
        build: (_) => [
          if (note != null) pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(printable(note), style: const pw.TextStyle(fontSize: 9)),
          ),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: .4),
            columnWidths: {0: const pw.FixedColumnWidth(35)},
            children: [
              pw.TableRow(
                repeat: true,
                decoration: const pw.BoxDecoration(color: PdfColors.green100),
                children: [
                  _cell('Row', bold: true),
                  for (final i in indexes) _cell(columns[i], bold: true),
                ],
              ),
              for (var row = 0; row < rows.length; row++)
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: row.isEven ? PdfColors.white : PdfColors.grey100),
                  children: [
                    _cell('${row + 1}'),
                    for (final i in indexes) _cell(rows[row][i]),
                  ],
                ),
            ],
          ),
        ],
      ));
    }
    return doc.save();
  }

  static pw.Widget _cell(String value, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Text(printable(value), style: pw.TextStyle(
      fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
  );
}
