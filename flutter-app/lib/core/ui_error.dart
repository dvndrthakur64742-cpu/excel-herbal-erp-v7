import 'api_client.dart';

class UiError {
  UiError._();

  static String message(Object error) {
    if (error is ApiException) return _api(error);
    if (error is FormatException) {
      final text = '${error.message}'.trim();
      return text.isEmpty ? 'Entered value check karein.' : text;
    }

    var text = error.toString().trim();
    text = text.replaceFirst(RegExp(r'^(Exception|FormatException):\s*'), '');
    if (text.isEmpty) return 'Something went wrong. Please try again.';

    final lower = text.toLowerCase();
    if (lower.contains('socket') ||
        lower.contains('connection') ||
        lower.contains('timeout')) {
      return 'Network connection unavailable. Please try again.';
    }
    if (lower.contains('dioexception') ||
        lower.contains('stack trace') ||
        lower.contains('null check operator') ||
        lower.contains('typeerror') ||
        lower.contains('nosuchmethod')) {
      return 'This section could not be completed. Please retry once.';
    }

    // Business validation exceptions created by the app are intentionally short
    // and useful to the operator. Technical exception text is filtered above.
    return text.length <= 220
        ? text
        : 'This action could not be completed. Please try again.';
  }

  static String? reference(Object error) {
    if (error is! ApiException) return null;
    final value = error.requestId?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String _api(ApiException error) {
    if (error.statusCode == 401) {
      return 'Session expire ho gayi hai. Dobara sign in karein.';
    }
    if (error.statusCode == 403) {
      return 'Aapke role ko is action ki permission nahi hai.';
    }

    switch (error.code) {
      case 'gps_invalid':
        return 'GPS point sync nahi hua. Retry karein.';
      case 'gps_checkin_required':
        return 'Duty GPS tracking se pehle check-in required hai.';
      case 'gps_recorded_date_invalid':
      case 'gps_recorded_time_invalid':
        return 'GPS point active duty window ke bahar hai.';
      case 'branch_forbidden':
      case 'branch_access_required':
        return 'Selected branch ke liye access available nahi hai.';
      case 'daily_duplicate':
        return 'Is employee aur date ke liye Daily Order pehle se bana hua hai.';
      case 'database_conflict':
        return 'Ye record pehle se maujood hai.';
      case 'rate_limited':
        return 'Bahut zyada attempts hue. Thodi der baad retry karein.';
      case 'whole_pcs_required':
        return 'Quantity whole PCS mein enter karein.';
      case 'additional_request_pending':
        return 'Pending Additional Stock request pehle complete karein.';
      default:
        final text = error.message.trim();
        return text.isEmpty
            ? 'Request complete nahi ho saka. Please try again.'
            : text;
    }
  }
}