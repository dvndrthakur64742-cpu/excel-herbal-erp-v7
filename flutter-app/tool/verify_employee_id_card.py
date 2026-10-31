from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
profile = (ROOT / 'lib/screens/home/profile_screen.dart').read_text(encoding='utf-8')
card = (ROOT / 'lib/screens/home/employee_id_card_screen.dart').read_text(encoding='utf-8')

checks = {
    'profile exposes I-card action': 'View / Print Employee I-Card' in profile,
    'profile uses actual photo fallback': "profile_photo_url" in profile and 'Image.network' in profile,
    'CR80 width locked': '_cr80WidthMm = 85.60' in card,
    'CR80 height locked': '_cr80HeightMm = 53.98' in card,
    'A4 safe margin locked': '12 * mm' in card,
    'front/back gap locked': '8 * mm' in card,
    'print supported': 'Printing.layoutPdf' in card,
    'share supported': 'Printing.sharePdf' in card,
    'QR identity supported': 'Barcode.qrCode()' in card and 'QrImageView' in card,
    'brand logo used': 'assets/branding/excel-herbal-logo.webp' in card,
    'no UAT badge': 'UAT BUILD' not in card,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'} - {name}")
if failed:
    raise SystemExit('Employee I-card contract failed: ' + ', '.join(failed))
print(f'Employee I-card contract PASS ({len(checks)}/{len(checks)}).')
