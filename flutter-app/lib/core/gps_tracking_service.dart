import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'api_client.dart';
import 'api_paths.dart';
import 'ui_error.dart';

class GpsTrackingService extends ChangeNotifier {
  GpsTrackingService(this.api);

  final ApiClient api;
  Timer? _timer;
  bool _active = false;
  bool _sending = false;
  String? _lastError;
  DateTime? _lastSentAt;

  bool get active => _active;
  bool get sending => _sending;
  String? get lastError => _lastError;
  DateTime? get lastSentAt => _lastSentAt;

  Future<void> start() async {
    if (_active) return;
    await _ensurePermission();
    _active = true;
    _lastError = null;
    notifyListeners();
    await sendNow();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => sendNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _active = false;
    _sending = false;
    notifyListeners();
  }

  Future<void> sendNow() async {
    if (!_active || _sending) return;
    _sending = true;
    notifyListeners();
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await api.post(
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
      if ('$e'.contains('gps_checkin_required')) stop();
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<void> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission required.');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
