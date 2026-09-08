import 'api_client.dart';

class UiError {
  UiError._();

  static String message(Object error) {
    if (error is ApiException) {
      return _api(error);
    }
    if (error is FormatException) {
      final text = '${error.message}'.trim();
      return text.isEmpty ? 'Please check the entered value.' : text;
    }

    var text = error.toString().trim();
    text = text.replaceFirst(RegExp(r'^(Exception|FormatException):\s*'), '');
    if (text.isEmpty) return 'Something went wrong. Please try again.';
    if (text.toLowerCase().contains('socket') ||
        text.toLowerCase().contains('connection') ||
        text.toLowerCase().contains('timeout')) {
      return 'Network connection unavailable. Please try again.';
    }
    return text;
  }

  static String _api(ApiException error) {
    switch (error.code) {
      case 'gps_invalid':
        return 'GPS point could not be synced. Please retry once.';
      case 'gps_checkin_required':
        return 'Check-in is required before duty GPS tracking can start.';
      case 'gps_recorded_date_invalid':
      case 'gps_recorded_time_invalid':
        return 'This GPS point is outside today’s active duty window.';
      case 'branch_forbidden':
        return 'This action is not available for the selected branch.';
      case 'daily_duplicate':
        return 'A Daily Order already exists for this employee and date.';
      case 'database_conflict':
        return 'This record already exists.';
      case 'rate_limited':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        final text = error.message.trim();
        return text.isEmpty ? 'Request could not be completed. Please try again.' : text;
    }
  }
}
