/// Shared query contract for the read-only GPS route endpoint.
///
/// The REST request validator accepts 'from' and 'to' only as YYYY-MM-DD.
/// The backend expands those dates to UTC bounds in the WordPress business
/// timezone, so clients must not convert a business day to device-local UTC.
class GpsRouteQuery {
  const GpsRouteQuery._();

  static final RegExp _dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static Map<String, Object> forBusinessDate(
    String businessDate, {
    int? employeeId,
  }) {
    final parsed = _dateOnly.hasMatch(businessDate)
        ? DateTime.tryParse(businessDate)
        : null;
    final normalized = parsed == null
        ? ''
        : '${parsed.year.toString().padLeft(4, '0')}-'
            '${parsed.month.toString().padLeft(2, '0')}-'
            '${parsed.day.toString().padLeft(2, '0')}';
    if (parsed == null || businessDate != normalized) {
      throw FormatException('Invalid ERP business date.', businessDate);
    }
    if (employeeId != null && employeeId <= 0) {
      throw ArgumentError.value(employeeId, 'employeeId', 'Must be positive');
    }
    return <String, Object>{
      if (employeeId != null) 'employee_id': employeeId,
      'from': businessDate,
      'to': businessDate,
    };
  }
}
