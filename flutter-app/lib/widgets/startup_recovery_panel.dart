import 'package:flutter/material.dart';

/// Recoverable, non-posting startup state. Scrolling keeps Retry and Logout
/// accessible on small phones and with enlarged accessibility text.
class StartupRecoveryPanel extends StatelessWidget {
  const StartupRecoveryPanel({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onLogout,
    this.supportReference,
  });

  final String message;
  final String? supportReference;
  final VoidCallback onRetry;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reference = supportReference?.trim();
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: viewport.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.sync_problem_rounded,
                              size: 48,
                              color: theme.colorScheme.error,
                              semanticLabel: 'Startup verification failed',
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'ERP startup temporarily unavailable',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 12),
                            Text(message, textAlign: TextAlign.center),
                            if (reference != null && reference.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SelectableText(
                                'Support reference: $reference',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(height: 12),
                            const Text(
                              'Business posting is paused until the server date and startup contract are valid. Navigation will resume after a successful retry.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 22),
                            FilledButton.icon(
                              onPressed: onRetry,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Retry startup'),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: onLogout,
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
          ),
        ),
      ),
    );
  }
}
