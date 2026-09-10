import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Keeps GPS duty tracking aligned with attendance while the authenticated ERP
/// shell exists. There is intentionally no employee-controlled route switch.
class GpsTrackingCoordinator extends ConsumerStatefulWidget {
  const GpsTrackingCoordinator({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<GpsTrackingCoordinator> createState() =>
      _GpsTrackingCoordinatorState();
}

class _GpsTrackingCoordinatorState
    extends ConsumerState<GpsTrackingCoordinator>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(gpsTrackingProvider).sync());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(gpsTrackingProvider).sync());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ref.read(gpsTrackingProvider).stop(status: 'signed_out');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
