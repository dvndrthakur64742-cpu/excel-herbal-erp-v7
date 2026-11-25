import 'report_period.dart';

enum StockInsightKind { negative, expired, expiresToday, upcoming, missingExpiry, unverified, current }

class StockInsight {
  const StockInsight(this.row, this.kind, this.days);
  final Map<String, dynamic> row;
  final StockInsightKind kind;
  final int? days;

  static StockInsight classify(Map<String, dynamic> row, DateTime day, int horizon) {
    final quantity = num.tryParse('${row['quantity'] ?? ''}');
    if (quantity == null || !quantity.isFinite) return StockInsight(row, StockInsightKind.unverified, null);
    if (quantity < 0) return StockInsight(row, StockInsightKind.negative, null);
    final tracking = '${row['expiry_tracking'] ?? ''}';
    final raw = '${row['expires_on'] ?? ''}';
    final expiry = ReportPeriod.businessDay(raw);
    if (expiry == null) {
      if (raw.isNotEmpty || (tracking != '0' && tracking != 'false' && tracking != '1' && tracking != 'true'))
        return StockInsight(row, StockInsightKind.unverified, null);
      if (tracking == '1' || tracking == 'true')
        return StockInsight(row, StockInsightKind.missingExpiry, null);
      return StockInsight(row, StockInsightKind.current, null);
    }
    // Calendar dates, independent of device DST or UTC offset.
    final days = DateTime.utc(expiry.year, expiry.month, expiry.day)
      .difference(DateTime.utc(day.year, day.month, day.day)).inDays;
    final kind = days < 0 ? StockInsightKind.expired
        : days == 0 ? StockInsightKind.expiresToday
        : days <= horizon ? StockInsightKind.upcoming : StockInsightKind.current;
    return StockInsight(row, kind, days);
  }
}
