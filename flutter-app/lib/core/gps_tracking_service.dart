import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'api_client.dart';
import 'gps_location_platform.dart';
import 'api_paths.dart';
import 'ui_error.dart';

abstract interface class GpsApiTransport {
  Future<dynamic> get(String path);

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? data,
  });
}

class _ApiClientGpsTransport implements GpsApiTransport {
  const _ApiClientGpsTransport(this.api);

  final ApiClient api;

  @override
  Future<dynamic> get(String path) => api.get(path);

  @override
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? data,
  }) =>
      api.post(path, data: data);
}

class GpsTrackingService extends ChangeNotifier {
  GpsTrackingService(
    ApiClient api, {
    GpsLocationPlatform? location,
  })  : _api = _ApiClientGpsTransport(api),
        _location = location ?? const GeolocatorGpsLocationPlatform();

  @visibleForTesting
  GpsTrackingService.forTest({
    required GpsApiTransport api,
    required GpsLocationPlatform location,
  })  : _api = api,
        _location = location;

  final GpsApiTransport _api;
  final GpsLocationPlatform _location;
  Timer? _pointTimer;
  Timer? _scheduleTimer;
  Timer? _stopTimer;
  StreamSubscription<GpsFix>? _positionSubscription;
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
      final data = await _api.get(ApiPaths.attendanceToday);
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
      bool permissionReady;
      try {
        permissionReady = await _ensurePermission();
      } catch (e) {
        // Browser/device geolocation APIs can throw when unavailable or blocked
        // (for example, a browser permission API failure). Keep attendance intact,
        // expose the real GPS failure in the UI, and allow an explicit retry.
        _active = false;
        _pointTimer?.cancel();
        _pointTimer = null;
        _dutyStatus = 'unavailable';
        _lastError = 'Unable to check device location permission: ${UiError.message(e)}';
        _scheduleAutoStop(attendance);
        notifyListeners();
        return;
      }
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
      if (_active && _location.supportsBackgroundTracking) {
        // Android's foreground location service keeps collecting fixes while
        // the employee switches apps or locks the screen. Upload no more than
        // one point per five minutes to preserve the agreed route cadence.
        await _positionSubscription?.cancel();
        _positionSubscription = _location.watchPositions().listen(
          (position) {
            if (!_active || _sending) return;
            final last = _lastSentAt;
            if (last != null &&
                DateTime.now().difference(last) < const Duration(minutes: 5)) {
              return;
            }
            unawaited(_sendPosition(position));
          },
          onError: (Object error, StackTrace stackTrace) {
            _lastError = 'Background GPS stream error: ${UiError.message(error)}';
            // Fall back to foreground polling if the native stream terminates;
            // the error remains visible so the operator can diagnose gaps.
            _pointTimer?.cancel();
            _pointTimer = Timer.periodic(
              const Duration(minutes: 5),
              (_) => unawaited(sendNow()),
            );
            notifyListeners();
          },
        );
      } else if (_active) {
        // Web/browser tracking is foreground-only; browsers may throttle
        // location and timers when a tab is backgrounded.
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
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = null;
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
      final position = await _location.currentFix();
      await _api.post(
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

  Future<void> _sendPosition(GpsFix position) async {
    if (!_active || _sending) return;
    _sending = true;
    notifyListeners();
    try {
      await _api.post(
        ApiPaths.gpsPoints,
        data: {
          'lat': position.latitude,
          'lng': position.longitude,
          'accuracy': position.accuracy,
          'source': 'duty',
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
      }
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<bool> _ensurePermission() async {
    final serviceEnabled = await _location.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _dutyStatus = 'location_disabled';
      _lastError =
          'Device location is off. Turn on Location, then tap Retry for duty GPS.';
      return false;
    }

    var permission = await _location.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _location.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _dutyStatus = 'permission_blocked';
      _lastError = permission == LocationPermission.deniedForever
          ? 'Location permission is blocked. Allow location for this site in browser or device settings, then tap Retry.'
          : 'Location permission is required for duty GPS. Allow it when prompted, then tap Retry.';
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _pointTimer?.cancel();
    _scheduleTimer?.cancel();
    _stopTimer?.cancel();
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = null;
    super.dispose();
  }
}
