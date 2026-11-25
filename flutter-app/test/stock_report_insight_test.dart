import 'package:excel_herbal_erp/core/stock_report_insight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 11, 25);
  StockInsightKind kind(String quantity, Object? expiry, Object? tracking, [int horizon = 30]) =>
      StockInsight.classify({'quantity': quantity, 'expires_on': expiry, 'expiry_tracking': tracking}, today, horizon).kind;

  test('expiry classifications use business dates and inclusive horizon', () {
    expect(kind('2','2026-11-24',1), StockInsightKind.expired);
    expect(kind('2','2026-11-25',1), StockInsightKind.expiresToday);
    expect(kind('2','2026-12-25',1), StockInsightKind.upcoming);
    expect(kind('2','2026-12-26',1), StockInsightKind.current);
    expect(kind('2','2026-12-03',1,7), StockInsightKind.current);
  });
  test('missing metadata and invalid quantity never look healthy', () {
    expect(kind('2',null,1), StockInsightKind.missingExpiry);
    expect(kind('2',null,0), StockInsightKind.current);
    expect(kind('2',null,null), StockInsightKind.unverified);
    expect(kind('2','2026-02-30',1), StockInsightKind.unverified);
    expect(kind('bad',null,0), StockInsightKind.unverified);
    expect(kind('-2','2026-11-24',1), StockInsightKind.negative);
  });
}
