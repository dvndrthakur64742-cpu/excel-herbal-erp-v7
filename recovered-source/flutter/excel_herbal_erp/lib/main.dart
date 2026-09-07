import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_config.dart';
import 'screens/auth/login_screen.dart';
import 'shell/app_shell.dart';
import 'state/app_state.dart';

void main() => runApp(const ProviderScope(child: ExcelHerbalApp()));

class ExcelHerbalApp extends ConsumerWidget {
  const ExcelHerbalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final home = app.loading
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : app.bootstrapRecoveryRequired
            ? const _BootstrapRecoveryScreen()
            : app.authenticated
                ? (app.businessAccessBlocked ? const _BranchAccessBlockedScreen() : const AppShell())
                : const LoginScreen();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Excel Herbal ERP',
      theme: ThemeData(
        useMaterial3: true,
        inputDecorationTheme:
            const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      builder: (context, child) {
        if (!AppConfig.isUat || child == null) return child ?? const SizedBox();
        return Banner(
          message: 'UAT',
          location: BannerLocation.topEnd,
          child: child,
        );
      },
      home: home,
    );
  }
}


class _BootstrapRecoveryScreen extends ConsumerWidget {
  const _BootstrapRecoveryScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
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
                      const Icon(Icons.cloud_off_outlined, size: 56),
                      const SizedBox(height: 16),
                      Text('ERP temporarily unavailable', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(app.error ?? 'Server se response nahi mila.', textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      const Text('Aapka login safe rakha gaya hai. Network/server theek hone par Retry karein.', textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: () => ref.read(appStateProvider.notifier).refreshBootstrap(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => ref.read(appStateProvider.notifier).logout(),
                            icon: const Icon(Icons.logout),
                            label: const Text('Logout'),
                          ),
                        ],
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
    final employee = Map<String, dynamic>.from((app.me['employee'] as Map?) ?? const {});
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
                      Text('Business Access Blocked', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text('${employee['full_name'] ?? 'Employee'} has no active authorised branch.', textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      const Text('Ask an authorised administrator to assign the primary branch or an additional branch authority. Roles do not expand branch authority.', textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => ref.read(appStateProvider.notifier).logout(),
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
