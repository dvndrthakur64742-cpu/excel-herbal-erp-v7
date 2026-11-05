import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'secure_session.dart';
import 'gps_tracking_service.dart';

final secureStorageProvider = Provider((ref) => const FlutterSecureStorage());
final secureSessionProvider = Provider(
  (ref) => SecureSession(ref.watch(secureStorageProvider)),
);
final apiClientProvider = Provider(
  (ref) => ApiClient(ref.watch(secureSessionProvider)),
);

final gpsTrackingProvider = ChangeNotifierProvider<GpsTrackingService>(
  (ref) => GpsTrackingService(ref.watch(apiClientProvider)),
);
