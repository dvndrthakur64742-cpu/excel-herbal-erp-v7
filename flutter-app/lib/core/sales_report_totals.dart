import 'report_period.dart';

/// Analytics of the exact rows returned by the sales report. No extra API,
/// no extrapolation or assertion that gross is net revenue or cash received.
class SalesReportDay {
  const SalesReportDay(this.date, this.grossMinor, this.rows);
  final String date;
  final int grossMinor;
  final List<Map<String, dynamic>> rows;
}

class SalesReportTotals {
  const SalesReportTotals(this.grossMinor, this.paidMinor, this.outstandingMinor, this.days);
  final int grossMinor;
  final int paidMinor;
  final int outstandingMinor;
  final List<SalesReportDay> days;

  static int? _minor(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    final match = RegExp(r'^(-?)(\d{1,12})(?:\.(\d{1,2}))?$').firstMatch(raw);
    if (match == null) return null;
    final major = int.parse(match.group(2)!);
    final fraction = int.parse((match.group(3) ?? '').padRight(2, '0'));
    final minor = major * 100 + fraction;
    return match.group(1) == '-' ? -minor : minor;
  }

  static SalesReportTotals? read(List<Map<String, dynamic>> rows) {
    var gross = 0, paid = 0, outstanding = 0;
    final grouped = <String, List<Map<String, dynamic>>>{};
    final amounts = <String, int>{};
    final seen = <String>{};
    for (final row in rows) {
      final id = '${row['id'] ?? ''}';
      final date = '${row['business_date'] ?? ''}';
      final g = _minor(row['gross_amount']);
      final p = _minor(row['paid_amount']);
      final o = _minor(row['outstanding_amount']);
      if (id.isEmpty || !seen.add(id) || ReportPeriod.businessDay(date) == null ||
          g == null || p == null || o == null) return null;
      gross += g; paid += p; outstanding += o;
      // Keep arithmetic exact on Flutter Web's JS number representation.
      const safeLimit = 9007199254740991;
      if (gross.abs() > safeLimit || paid.abs() > safeLimit ||
          outstanding.abs() > safeLimit) return null;
      grouped.putIfAbsent(date, () => []).add(row);
      final dayTotal = (amounts[date] ?? 0) + g;
      if (dayTotal.abs() > safeLimit) return null;
      amounts[date] = dayTotal;
    }
    final dates = grouped.keys.toList()..sort((a,b) => b.compareTo(a));
    return SalesReportTotals(gross, paid, outstanding, [
      for (final date in dates) SalesReportDay(date, amounts[date]!, List.unmodifiable(grouped[date]!)),
    ]);
  }
}
