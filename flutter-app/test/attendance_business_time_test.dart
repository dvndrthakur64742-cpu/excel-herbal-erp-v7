import 'package:excel_herbal_erp/core/date_time_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance renders UTC storage in India business time', () {
    expect(DateTimeText.business('2026-11-25 05:00:00', 'Asia/Kolkata'),
        '25-11-2026 10:30:00 IST');
    expect(DateTimeText.business('2026-11-25T03:30:00Z', 'Asia/Kolkata'),
        '25-11-2026 09:00:00 IST');
    expect(DateTimeText.business('2026-11-25T19:00:00+05:30', 'Asia/Kolkata'),
        '25-11-2026 19:00:00 IST');
  });
  test('business time crosses the calendar boundary correctly', () {
    expect(DateTimeText.business('2026-11-25 20:00:00', 'Asia/Kolkata'),
        '26-11-2026 01:30:00 IST');
  });
  test('unsupported zones display explicit UTC rather than invented offset', () {
    expect(DateTimeText.business('2026-11-25 05:00:00', 'Europe/London'),
        '25-11-2026 05:00:00 UTC');
    expect(DateTimeText.business('2026-11-25 05:00:00', ''),
        '25-11-2026 05:00:00 UTC');
  });
  test('missing and malformed timestamps are not fabricated', () {
    expect(DateTimeText.business(null, 'Asia/Kolkata'), '-');
    expect(DateTimeText.business('invalid', 'Asia/Kolkata'), 'Unverified time');
    expect(DateTimeText.business('2026-11-25', 'Asia/Kolkata'), 'Unverified time');
  });
}
