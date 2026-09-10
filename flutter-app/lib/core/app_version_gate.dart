import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';
import 'api_paths.dart';

class AppVersionGate extends StatefulWidget {
  const AppVersionGate({super.key, required this.api, required this.child});
  final ApiClient api;
  final Widget child;

  @override
  State<AppVersionGate> createState() => _AppVersionGateState();
}

class _AppVersionGateState extends State<AppVersionGate> {
  Future<Map<String, dynamic>?>? _policy;

  @override
  void initState() {
    super.initState();
    _policy = _load();
  }

  Future<Map<String, dynamic>?> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber) ?? 0;
      final data = await widget.api.get(
        ApiPaths.appVersionPolicy,
        query: {'client_build': build},
        authenticated: false,
      );
      return Map<String, dynamic>.from((data as Map?) ?? const {});
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _policy,
      builder: (context, snapshot) {
        final policy = snapshot.data;
        // v7 backend contract uses force_update. update_required remains a
        // compatibility fallback for any older policy projection.
        final required = policy?['force_update'] == true ||
            policy?['update_required'] == true;
        if (!required) return widget.child;
        final message = '${policy?['message'] ?? 'App update required.'}';
        final url = '${policy?['update_url'] ?? ''}'.trim();
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
                          const Icon(Icons.system_update_alt_rounded, size: 56),
                          const SizedBox(height: 16),
                          Text(
                            'Update Required',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(message, textAlign: TextAlign.center),
                          const SizedBox(height: 18),
                          if (url.isNotEmpty)
                            FilledButton.icon(
                              onPressed: () async {
                                final uri = Uri.tryParse(url);
                                if (uri != null) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              },
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Update App'),
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
      },
    );
  }
}
