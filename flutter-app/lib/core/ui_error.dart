import 'api_client.dart';

class UiError {
  UiError._();

  static String message(Object error) {
    if (error is ApiException) return _api(error);
    if (error is FormatException) {
      final text = error.message.trim();
      return text.isEmpty ? 'Check the entered value and try again.' : text;
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
      return 'Your session has expired. Please sign in again.';
    }
    if (error.statusCode == 403) {
      return 'Your role is not authorised for this action.';
    }

    switch (error.code) {
      case 'gps_invalid':
        return 'The GPS point could not be recorded. Please retry.';
      case 'gps_checkin_required':
        return 'Attendance check-in is required before duty GPS tracking can begin.';
      case 'gps_recorded_date_invalid':
      case 'gps_recorded_time_invalid':
        return 'The GPS point is outside the active duty window.';
      case 'branch_forbidden':
      case 'branch_access_required':
        return 'You do not have access to the selected branch.';
      case 'daily_duplicate':
        return 'A Daily Order already exists for this employee and date.';
      case 'database_conflict':
        return 'This record already exists.';
      case 'rate_limited':
        return 'Too many attempts were made. Please try again later.';
      case 'whole_pcs_required':
        return 'Enter the quantity in whole PCS.';
      case 'additional_request_pending':
        return 'Complete the pending Additional Stock request first.';
      default:
        final text = error.message.trim();
        return text.isEmpty
            ? 'The request could not be completed. Please try again.'
            : text;
    }
  }
}
