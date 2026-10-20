import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_version_gate.dart';
import 'core/preview_read_only_policy.dart';
import 'core/gps_tracking_coordinator.dart';
import 'core/providers.dart';
import 'screens/auth/login_screen.dart';
import 'shell/app_shell.dart';
import 'state/app_state.dart';
import 'theme/excel_brand.dart';

void main() {
  ErrorWidget.builder = (details) => Container(
    color: ExcelBrand.canvas,
    alignment: Alignment.center,
    padding: const EdgeInsets.all(28),
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: ExcelBrand.primarySoft,
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Icon(
              Icons.error_outline_rounded,
              size: 30,
              color: ExcelBrand.primaryDark,
            ),
          ),
        ),
        SizedBox(height: 16),
        Text(
          'This section could not load',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: ExcelBrand.ink,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Return to the previous screen and retry the action. Technical details have been hidden from the business screen.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.4, color: ExcelBrand.muted),
        ),
      ],
    ),
  );
  runApp(const ProviderScope(child: ExcelHerbalApp()));
}

class ExcelHerbalApp extends ConsumerWidget {
  const ExcelHerbalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final home = app.loading
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : app.authenticated
        ? (!app.bootstrapReady
              ? const _BootstrapRecoveryScreen()
              : app.businessAccessBlocked
              ? const _BranchAccessBlockedScreen()
              : PreviewReadOnlyPolicy.enabled
              ? const AppShell()
              : const GpsTrackingCoordinator(child: AppShell()))
        : const LoginScreen();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Excel Herbal ERP',
      theme: ExcelBrand.lightTheme(),
      home: AppVersionGate(api: ref.watch(apiClientProvider), child: home),
      builder: (context, child) {
        if (!PreviewReadOnlyPolicy.enabled) return child ?? const SizedBox.shrink();
        return Column(
          children: [
            Material(
              color: const Color(0xFF7A3B10),
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
                    child: Text(
                      'EXCEL HERBAL V8 PREVIEW • READ ONLY • NO FINANCIAL POSTING',
                      style: const TextStyle(
                        color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        );
      },
    );
  }
}

class _BootstrapRecoveryScreen extends ConsumerWidget {
  const _BootstrapRecoveryScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final reason =
        app.bootstrapCompatibilityError ??
        app.error ??
        'Required ERP startup information is temporarily unavailable.';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sync_problem_rounded, size: 56),
                      const SizedBox(height: 16),
                      Text(
                        'ERP startup temporarily unavailable',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      Text(reason, textAlign: TextAlign.center),
                      const SizedBox(height: 10),
                      const Text(
                        'Business posting is paused until the server date and startup contract are valid. Navigation will resume after a successful retry.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: () => ref
                            .read(appStateProvider.notifier)
                            .retryBootstrap(),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry startup'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () =>
                            ref.read(appStateProvider.notifier).logout(),
                        icon: const Icon(Icons.logout),
                        label: const Text('Logout'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BranchAccessBlockedScreen extends ConsumerWidget {
  const _BranchAccessBlockedScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final employee = Map<String, dynamic>.from(
      (app.me['employee'] as Map?) ?? const {},
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.block_outlined, size: 56),
                      const SizedBox(height: 16),
                      Text(
                        'Business Access Blocked',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${employee['full_name'] ?? 'Employee'} has no active authorised branch.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ask an authorised administrator to assign the primary branch or an additional branch authority. Roles do not expand branch authority.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () =>
                            ref.read(appStateProvider.notifier).logout(),
                        icon: const Icon(Icons.logout),
                        label: const Text('Logout'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
