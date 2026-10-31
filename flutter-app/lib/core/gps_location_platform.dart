import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

typedef GpsFix = ({
  double latitude,
  double longitude,
  double accuracy,
});

abstract interface class GpsLocationPlatform {
  Future<bool> isLocationServiceEnabled();

  Future<LocationPermission> checkPermission();

  Future<LocationPermission> requestPermission();

  Future<GpsFix> currentFix();

  /// True when Android can keep location updates flowing through a visible
  /// foreground-service notification while the app is backgrounded.
  bool get supportsBackgroundTracking;

  Stream<GpsFix> watchPositions();
}

class GeolocatorGpsLocationPlatform implements GpsLocationPlatform {
  const GeolocatorGpsLocationPlatform();

  @override
  bool get supportsBackgroundTracking =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() =>
      Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Stream<GpsFix> watchPositions() {
    final LocationSettings settings;
    if (supportsBackgroundTracking) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(minutes: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Excel Herbal ERP · Duty GPS',
          notificationText: 'Duty route tracking is active from 10:30 AM to 5:00 PM.',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
    }
    return Geolocator.getPositionStream(locationSettings: settings).map(
      (position) => (
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      ),
    );
  }

  @override
  Future<GpsFix> currentFix() async {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 20),
    );
    final position = await Geolocator.getCurrentPosition(
      locationSettings: settings,
    );
    return (
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );
  }
}
