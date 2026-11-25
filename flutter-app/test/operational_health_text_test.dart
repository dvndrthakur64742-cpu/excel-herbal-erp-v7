import 'package:excel_herbal_erp/core/operational_health_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only healthy diagnostics and recent scheduler show healthy', () {
    expect(OperationalHealthText.title('healthy', 'recent'), 'System healthy');
    expect(OperationalHealthText.needsAttention('attention', 'recent'), isTrue);
    for (final status in ['not_scheduled','stale','overdue','clock_mismatch','unverified',null]) {
      expect(OperationalHealthText.needsAttention('healthy', status), isTrue);
      expect(OperationalHealthText.title('healthy', status), isNot('System healthy'));
    }
    expect(OperationalHealthText.title('unknown','recent'), 'System health unverified');
  });
  test('missing count is distinct from real zero', () {
    expect(OperationalHealthText.metric(null), 'Unavailable');
    expect(OperationalHealthText.metric(0), '0');
  });
  test('partial approval sources are not a verified empty queue', () {
    expect(OperationalHealthText.approvalEmpty(2), contains('could not be fully verified'));
    expect(OperationalHealthText.approvalEmpty(0), contains('loaded sources'));
    expect(OperationalHealthText.approvalCount(3, 1), contains('incomplete'));
  });
}
