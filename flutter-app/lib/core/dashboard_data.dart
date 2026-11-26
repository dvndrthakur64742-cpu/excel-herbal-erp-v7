import 'business_format.dart';

/// KPI input validation shared by Home's read-only summary.
abstract final class DashboardData {
  static int? openCount(dynamic raw) {
    if (raw is! Map || raw['total'] is! int || raw['page'] != 1 ||
        raw['page_size'] != 1 || raw['has_more'] is! bool || raw['items'] is! List) return null;
    final count=raw['total'] as int;
    final items=raw['items'] as List;
    if (count<0 || count>9007199254740991 ||
        raw['has_more']!=(count>1) || items.length!=(count>0?1:0) ||
        items.any((r)=>r is! Map)) return null;
    return count;
  }
  static num? points(List<Map<String,dynamic>> rows) {
    num sum=0;
    for(final row in rows) {
      final value=BusinessFormat.number(row['points']);
      if(value==null || !value.isFinite) return null;
      sum+=value;
      if(!sum.isFinite || sum.abs()>9007199254740991) return null;
    }
    return sum;
  }
}
