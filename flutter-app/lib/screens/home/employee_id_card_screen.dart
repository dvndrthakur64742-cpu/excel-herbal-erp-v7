import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/excel_brand.dart';

class EmployeeIdCardScreen extends StatelessWidget {
  const EmployeeIdCardScreen({
    super.key,
    required this.employee,
    required this.branchName,
    required this.designation,
  });

  final Map<String, dynamic> employee;
  final String branchName;
  final String designation;

  static const double _cardRatio = 85.60 / 53.98;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Employee I-Card')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Excel Herbal Employee Identity Card',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'CR80 physical size 85.60 × 53.98 mm. Print keeps Front + Back together on one sheet.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          _screenCard(front: true),
          const SizedBox(height: 14),
          _screenCard(front: false),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => _print(context),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print Front + Back'),
              ),
              OutlinedButton.icon(
                onPressed: () => _share(context),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share PDF'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Printing guidance: use 100% / Actual Size and enable background graphics where the print dialog provides that option.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _screenCard({required bool front}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AspectRatio(
          aspectRatio: _cardRatio,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ExcelBrand.border),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 18,
                  offset: Offset(0, 8),
                  color: Color(0x18000000),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: front ? _frontPreview() : _backPreview(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _frontPreview() {
    final name = _text(employee['full_name'], fallback: 'Employee');
    final code = _text(employee['employee_code']);
    final photoUrl = _photoUrl();
    return Column(
      children: [
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: ExcelBrand.primary,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 38,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.asset(
                  'assets/branding/excel-herbal-logo.webp',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'EXCEL HERBAL',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .6,
                      ),
                    ),
                    Text(
                      'EMPLOYEE IDENTITY CARD',
                      style: TextStyle(
                        color: Color(0xFFDDF5E7),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 92,
                  height: 112,
                  decoration: BoxDecoration(
                    color: ExcelBrand.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ExcelBrand.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: photoUrl == null
                      ? const Icon(
                          Icons.person_rounded,
                          size: 58,
                          color: ExcelBrand.primaryDark,
                        )
                      : Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.person_rounded,
                            size: 58,
                            color: ExcelBrand.primaryDark,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF16352A),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        designation,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ExcelBrand.primaryDark,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _previewLine('Employee Code', code),
                      _previewLine('Branch', branchName),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _backPreview() {
    final qrData = _qrData();
    final mobile = _text(employee['mobile']);
    final joining = _text(employee['joining_date']);
    final code = _text(employee['employee_code']);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Employee Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF16352A),
                  ),
                ),
                const SizedBox(height: 10),
                _previewLine('Employee Code', code),
                if (mobile.isNotEmpty) _previewLine('Mobile', mobile),
                if (joining.isNotEmpty) _previewLine('Date of Joining', joining),
                _previewLine('Branch', branchName),
                const Spacer(),
                const Text(
                  'Company property • Valid while employment is active',
                  style: TextStyle(fontSize: 10, color: ExcelBrand.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 112,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                QrImageView(
                  data: qrData,
                  size: 104,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                ),
                const SizedBox(height: 5),
                const Text(
                  'Identity reference',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, color: ExcelBrand.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewLine(String label, String value) {
    final safe = value.trim().isEmpty ? '—' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 12, color: Color(0xFF33463F)),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(text: safe),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Future<void> _print(BuildContext context) async {
    try {
      await Printing.layoutPdf(
        name: _fileName(),
        onLayout: (format) => _buildPdf(format),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('I-Card print could not start: $e')),
      );
    }
  }

  Future<void> _share(BuildContext context) async {
    try {
      final bytes = await _buildPdf(PdfPageFormat.a4);
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: _fileName(),
          ),
        ],
        text: 'Excel Herbal Employee I-Card',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('I-Card share could not start: $e')),
      );
    }
  }

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    final doc = pw.Document();
    pw.ImageProvider? photo;
    final photoUrl = _photoUrl();
    if (photoUrl != null) {
      try {
        photo = await networkImage(photoUrl);
      } catch (_) {
        photo = null;
      }
    }

    const mm = PdfPageFormat.mm;
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(12 * mm),
        build: (_) => pw.Center(
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              _pdfCard(front: true, photo: photo),
              pw.SizedBox(width: 8 * mm),
              _pdfCard(front: false, photo: photo),
            ],
          ),
        ),
      ),
    );
    return doc.save();
  }

  pw.Widget _pdfCard({
    required bool front,
    required pw.ImageProvider? photo,
  }) {
    const mm = PdfPageFormat.mm;
    return pw.Container(
      width: 85.60 * mm,
      height: 53.98 * mm,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColor.fromHex('#0B8F48'), width: .8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
      ),
      clipBehavior: pw.Clip.hardEdge,
      child: front ? _pdfFront(photo) : _pdfBack(),
    );
  }

  pw.Widget _pdfFront(pw.ImageProvider? photo) {
    final name = _text(employee['full_name'], fallback: 'Employee');
    final code = _text(employee['employee_code']);
    return pw.Column(
      children: [
        pw.Container(
          height: 12 * PdfPageFormat.mm,
          width: double.infinity,
          color: PdfColor.fromHex('#0B8F48'),
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                'EXCEL HERBAL',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'EMPLOYEE IDENTITY CARD',
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 6),
              ),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 21 * PdfPageFormat.mm,
                  height: 28 * PdfPageFormat.mm,
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#E8F5EE'),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                  ),
                  child: photo == null
                      ? pw.Center(
                          child: pw.Text(
                            'PHOTO',
                            style: pw.TextStyle(
                              color: PdfColor.fromHex('#16643B'),
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        )
                      : pw.Image(photo, fit: pw.BoxFit.cover),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(
                        name,
                        maxLines: 2,
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#16352A'),
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        designation,
                        maxLines: 2,
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#0B6B38'),
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      _pdfLine('Employee Code', code),
                      _pdfLine('Branch', branchName),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfBack() {
    final code = _text(employee['employee_code']);
    final mobile = _text(employee['mobile']);
    final joining = _text(employee['joining_date']);
    return pw.Padding(
      padding: const pw.EdgeInsets.all(9),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  'Employee Details',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#16352A'),
                  ),
                ),
                pw.SizedBox(height: 6),
                _pdfLine('Employee Code', code),
                if (mobile.isNotEmpty) _pdfLine('Mobile', mobile),
                if (joining.isNotEmpty) _pdfLine('Date of Joining', joining),
                _pdfLine('Branch', branchName),
                pw.Spacer(),
                pw.Text(
                  'Company property • Valid while employment is active',
                  style: const pw.TextStyle(fontSize: 5.5, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: _qrData(),
                width: 25 * PdfPageFormat.mm,
                height: 25 * PdfPageFormat.mm,
              ),
              pw.SizedBox(height: 3),
              pw.Text('Identity reference', style: const pw.TextStyle(fontSize: 5)),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfLine(String label, String value) {
    final safe = value.trim().isEmpty ? '—' : value.trim();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.RichText(
        text: pw.TextSpan(
          style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey900),
          children: [
            pw.TextSpan(
              text: '$label: ',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.TextSpan(text: safe),
          ],
        ),
        maxLines: 2,
      ),
    );
  }

  String _qrData() {
    final code = _text(employee['employee_code']);
    final name = _text(employee['full_name']);
    return 'EXCEL-HERBAL|EMPLOYEE|$code|$name';
  }

  String _fileName() {
    final code = _text(employee['employee_code'], fallback: 'employee')
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
    return 'Excel-Herbal-I-Card-$code.pdf';
  }

  String? _photoUrl() {
    for (final key in const [
      'profile_photo_url',
      'photo_url',
      'employee_photo_url',
      'photo',
    ]) {
      final value = '${employee[key] ?? ''}'.trim();
      if (value.startsWith('https://') || value.startsWith('http://')) {
        return value;
      }
    }
    return null;
  }

  String _text(dynamic value, {String fallback = ''}) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? fallback : text;
  }
}
