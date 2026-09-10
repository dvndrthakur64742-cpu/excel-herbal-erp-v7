import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'api_client.dart';
import 'api_paths.dart';
import 'ui_error.dart';

class GpsTrackingService extends ChangeNotifier {
  GpsTrackingService(this.api);

  final ApiClient api;
  Timer? _pointTimer;
  Timer? _scheduleTimer;
  Timer? _stopTimer;
  bool _active = false;
  bool _armed = false;
  bool _sending = false;
  String _dutyStatus = 'unknown';
  String? _lastError;
  DateTime? _lastSentAt;

  bool get active => _active;
  bool get armed => _armed;
  bool get sending => _sending;
  String get dutyStatus => _dutyStatus;
  String? get lastError => _lastError;
  DateTime? get lastSentAt => _lastSentAt;
  bool get permissionBlocked => _dutyStatus == 'permission_blocked';
  bool get locationDisabled => _dutyStatus == 'location_disabled';

  /// Synchronises route tracking with the server-owned attendance/GPS policy.
  /// There is deliberately no user-controlled route start/stop state: an
  /// active attendance starts tracking at the duty window and checkout/5 PM
  /// stops it automatically.
  Future<void> start() async {
    Map<String, dynamic>? attendance;
    try {
      final data = await api.get(ApiPaths.attendanceToday);
      if (data is Map) attendance = Map<String, dynamic>.from(data);
    } catch (e) {
      _lastError = UiError.message(e);
      _dutyStatus = 'unavailable';
      notifyListeners();
      return;
    }

    if (attendance == null || attendance.isEmpty) {
      stop(status: 'not_checked_in');
      return;
    }

    final status = '${attendance['gps_status'] ?? 'unknown'}';
    _dutyStatus = status;
    _lastError = null;

    switch (status) {
      case 'active':
        await _activate(attendance);
        return;
      case 'scheduled':
        _armForWindow(attendance);
        return;
      case 'checked_out':
      case 'auto_stopped':
      case 'not_checked_in':
        stop(status: status);
        return;
      default:
        stop(status: status);
    }
  }

  Future<void> sync() => start();

  Future<void> _activate(Map<String, dynamic> attendance) async {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _armed = true;
    if (!_active) {
      final permissionReady = await _ensurePermission();
      if (!permissionReady) {
        _active = false;
        _pointTimer?.cancel();
        _pointTimer = null;
        _scheduleAutoStop(attendance);
        notifyListeners();
        return;
      }
      _active = true;
      _dutyStatus = 'active';
      notifyListeners();
      await sendNow();
      if (_active) {
        _pointTimer?.cancel();
        _pointTimer = Timer.periodic(
          const Duration(minutes: 5),
          (_) => unawaited(sendNow()),
        );
      }
    }
    _scheduleAutoStop(attendance);
  }

  void _armForWindow(Map<String, dynamic> attendance) {
    _pointTimer?.cancel();
    _pointTimer = null;
    _active = false;
    _armed = true;
    _dutyStatus = 'scheduled';
    _scheduleTimer?.cancel();

    final startsAt = DateTime.tryParse(
      '${attendance['gps_window_start_utc'] ?? ''}',
    )?.toLocal();
    if (startsAt == null) {
      _lastError = 'GPS duty schedule unavailable.';
      _armed = false;
      notifyListeners();
      return;
    }
    final delay = startsAt.difference(DateTime.now());
    if (delay <= Duration.zero) {
      unawaited(start());
    } else {
      _scheduleTimer = Timer(delay, () => unawaited(start()));
    }
    _scheduleAutoStop(attendance);
    notifyListeners();
  }

  void _scheduleAutoStop(Map<String, dynamic> attendance) {
    _stopTimer?.cancel();
    final stopsAt = DateTime.tryParse(
      '${attendance['gps_window_stop_utc'] ?? ''}',
    )?.toLocal();
    if (stopsAt == null) return;
    final delay = stopsAt.difference(DateTime.now());
    if (delay <= Duration.zero) {
      stop(status: 'auto_stopped');
      return;
    }
    _stopTimer = Timer(delay, () => stop(status: 'auto_stopped'));
  }

  /// Internal/system lifecycle stop only. UI must never expose a manual route
  /// Start/Stop business action; checkout/server policy owns the route state.
  void stop({String status = 'stopped'}) {
    // Legacy UI may still call stop() without a server-owned reason. Refuse to
    // turn tracking off in that case so an employee cannot bypass duty GPS.
    if (status == 'stopped') {
      _lastError =
          'Duty GPS is automatic. It stops only after checkout or the 5 PM duty cutoff.';
      notifyListeners();
      return;
    }
    _pointTimer?.cancel();
    _scheduleTimer?.cancel();
    _stopTimer?.cancel();
    _pointTimer = null;
    _scheduleTimer = null;
    _stopTimer = null;
    _active = false;
    _armed = false;
    _sending = false;
    _dutyStatus = status;
    notifyListeners();
  }

  Future<void> sendNow() async {
    if (!_active || _sending) return;
    _sending = true;
    notifyListeners();
    try {
      const settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      );
      final position = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );
      await api.post(
        ApiPaths.gpsPoints,
        data: {
          'lat': position.latitude,
          'lng': position.longitude,
          'accuracy': position.accuracy,
          'source': kIsWeb ? 'duty_web' : 'duty',
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      _lastSentAt = DateTime.now();
      _lastError = null;
    } catch (e) {
      _lastError = UiError.message(e);
      if (e is ApiException &&
          const {
            'gps_checkin_required',
            'gps_window_closed',
            'gps_recorded_date_invalid',
          }.contains(e.code)) {
        stop(
          status: e.code == 'gps_window_closed'
              ? 'auto_stopped'
              : 'not_checked_in',
        );
        return;
      }
      if (e is ApiException && e.code == 'gps_window_not_started') {
        _active = false;
        _pointTimer?.cancel();
        _pointTimer = null;
        unawaited(start());
      }
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<bool> _ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _dutyStatus = 'location_disabled';
      _lastError = 'Device location is off. Turn on Location for duty GPS.';
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _dutyStatus = 'permission_blocked';
      _lastError = permission == LocationPermission.deniedForever
          ? 'Location permission is blocked in device settings.'
          : 'Location permission is required for duty GPS.';
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _pointTimer?.cancel();
    _scheduleTimer?.cancel();
    _stopTimer?.cancel();
    super.dispose();
  }
}
