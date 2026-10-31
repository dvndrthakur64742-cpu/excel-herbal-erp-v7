import 'package:flutter/material.dart';

import '../core/ui_error.dart';
import '../theme/excel_brand.dart';

class AsyncPanel extends StatefulWidget {
  const AsyncPanel({
    super.key,
    required this.future,
    required this.builder,
    this.emptyMessage = 'This section has no records to show.',
    this.reloadToken,
  });

  final Future<dynamic> future;
  final Widget Function(BuildContext, dynamic) builder;
  final String emptyMessage;
  final Object? reloadToken;

  @override
  State<AsyncPanel> createState() => _AsyncPanelState();
}

class _AsyncPanelState extends State<AsyncPanel> {
  late Future<dynamic> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.future;
  }

  @override
  void didUpdateWidget(covariant AsyncPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) _future = widget.future;
  }

  void _retry() => setState(() => _future = widget.future);

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const _LoadingState();
      }
      if (snapshot.hasError) {
        return _ErrorState(error: snapshot.error!, onRetry: _retry);
      }
      final data = snapshot.data;
      if (data is List && data.isEmpty) {
        return _EmptyState(message: widget.emptyMessage);
      }
      return widget.builder(context, data);
    },
  );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'Loading content',
    child: const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: SizedBox.square(
          dimension: 30,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: ExcelBrand.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inbox_outlined,
                color: ExcelBrand.primaryDark,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No records yet',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final reference = UiError.reference(error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: ExcelBrand.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.refresh_rounded,
                  size: 30,
                  color: ExcelBrand.primaryDark,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Unable to load this section',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 7),
              Text(
                UiError.message(error),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (reference != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Support ref: $reference',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
