import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

  static const _cr80WidthMm = 85.60;
  static const _cr80HeightMm = 53.98;
  static const _screenRatio = _cr80WidthMm / _cr80HeightMm;

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
            'CR80: 85.60 x 53.98 mm. Front and Back print together on one sheet.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _preview(front: true),
          const SizedBox(height: 14),
          _preview(front: false),
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
            'Print at 100% / Actual Size. Enable background graphics when the print dialog provides that option.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _preview({required bool front}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AspectRatio(
          aspectRatio: _screenRatio,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: ExcelBrand.border),
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 18,
                  offset: Offset(0, 8),
                  color: Color(0x18000000),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: front ? _frontPreview() : _backPreview(),
          ),
        ),
      ),
    );
  }

  Widget _frontPreview() {
    final photo = _photoUrl();
    return Column(
      children: [
        Container(
          height: 58,
          color: ExcelBrand.primary,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 40,
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
                  child: photo == null
                      ? const Icon(
                          Icons.person_rounded,
                          size: 58,
                          color: ExcelBrand.primaryDark,
                        )
                      : Image.network(
                          photo,
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
                        _value('full_name', fallback: 'Employee'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 21,
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
                      _screenLine('Employee Code', _value('employee_code')),
                      _screenLine('Branch', branchName),
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
    final mobile = _value('mobile');
    final joining = _value('joining_date');
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
                const SizedBox(height: 9),
                _screenLine('Employee Code', _value('employee_code')),
                if (mobile.isNotEmpty) _screenLine('Mobile', mobile),
                if (joining.isNotEmpty) _screenLine('Date of Joining', joining),
                _screenLine('Branch', branchName),
                const Spacer(),
                const Text(
                  'Company property - valid while employment is active',
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
                  data: _qrData(),
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

  Widget _screenLine(String label, String value) {
    final safe = value.trim().isEmpty ? '-' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$label: $safe',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Color(0xFF33463F)),
      ),
    );
  }

  Future<void> _print(BuildContext context) async {
    try {
      await Printing.layoutPdf(
        name: _fileName(),
        onLayout: _buildPdf,
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
      await Printing.sharePdf(bytes: bytes, filename: _fileName());
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('I-Card share could not start: $e')),
      );
    }
  }

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    final document = pw.Document();
    final logoData = await rootBundle.load('assets/branding/excel-herbal-logo.webp');
    final logo = pw.MemoryImage(logoData.buffer.asUint8List());
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
    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(12 * mm),
        build: (_) => pw.Center(
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              _pdfCard(front: true, logo: logo, photo: photo),
              pw.SizedBox(width: 8 * mm),
              _pdfCard(front: false, logo: logo, photo: photo),
            ],
          ),
        ),
      ),
    );
    return document.save();
  }

  pw.Widget _pdfCard({
    required bool front,
    required pw.ImageProvider logo,
    required pw.ImageProvider? photo,
  }) {
    const mm = PdfPageFormat.mm;
    return pw.Container(
      width: _cr80WidthMm * mm,
      height: _cr80HeightMm * mm,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColor.fromHex('#0B8F48'), width: .8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: front ? _pdfFront(logo, photo) : _pdfBack(),
    );
  }

  pw.Widget _pdfFront(pw.ImageProvider logo, pw.ImageProvider? photo) {
    return pw.Column(
      children: [
        pw.Container(
          height: 12 * PdfPageFormat.mm,
          width: double.infinity,
          color: PdfColor.fromHex('#0B8F48'),
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: pw.Row(
            children: [
              pw.Container(
                width: 17 * PdfPageFormat.mm,
                height: 9 * PdfPageFormat.mm,
                color: PdfColors.white,
                padding: const pw.EdgeInsets.all(2),
                child: pw.Image(logo, fit: pw.BoxFit.contain),
              ),
              pw.SizedBox(width: 5),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    'EXCEL HERBAL',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'EMPLOYEE IDENTITY CARD',
                    style: const pw.TextStyle(color: PdfColors.white, fontSize: 5.5),
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.all(7),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 21 * PdfPageFormat.mm,
                  height: 28 * PdfPageFormat.mm,
                  color: PdfColor.fromHex('#E8F5EE'),
                  child: photo == null
                      ? pw.Center(
                          child: pw.Text(
                            'PHOTO',
                            style: pw.TextStyle(
                              color: PdfColor.fromHex('#16643B'),
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        )
                      : pw.Image(photo, fit: pw.BoxFit.cover),
                ),
                pw.SizedBox(width: 7),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(
                        _value('full_name', fallback: 'Employee'),
                        maxLines: 2,
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#16352A'),
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        designation,
                        maxLines: 2,
                        style: pw.TextStyle(
                          fontSize: 7.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#0B6B38'),
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      _pdfLine('Employee Code', _value('employee_code')),
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
    final mobile = _value('mobile');
    final joining = _value('joining_date');
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
                _pdfLine('Employee Code', _value('employee_code')),
                if (mobile.isNotEmpty) _pdfLine('Mobile', mobile),
                if (joining.isNotEmpty) _pdfLine('Date of Joining', joining),
                _pdfLine('Branch', branchName),
                pw.Spacer(),
                pw.Text(
                  'Company property - valid while employment is active',
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
    final safe = value.trim().isEmpty ? '-' : value.trim();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Text(
        '$label: $safe',
        maxLines: 2,
        style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey900),
      ),
    );
  }

  String _qrData() {
    return 'EXCEL-HERBAL|EMPLOYEE|${_value('employee_code')}|${_value('full_name')}';
  }

  String _fileName() {
    final code = _value('employee_code', fallback: 'employee')
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

  String _value(String key, {String fallback = ''}) {
    final value = '${employee[key] ?? ''}'.trim();
    return value.isEmpty ? fallback : value;
  }
}
