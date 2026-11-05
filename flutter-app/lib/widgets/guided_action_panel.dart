import 'package:flutter/material.dart';

/// A permission-scoped launcher. Never duplicates the transaction workflow.
class GuidedAction {
  const GuidedAction({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.onOpen,
    this.enabled = true,
    this.primary = false,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onOpen;
  final bool enabled;
  final bool primary;
}

class GuidedActionPanel extends StatelessWidget {
  const GuidedActionPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final List<GuidedAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final mainActions = actions.where((action) => action.primary);
            final secondaryActions = actions.where((action) => !action.primary);
            final featured = mainActions.isEmpty
                ? actions.take(1).toList(growable: false)
                : mainActions.toList(growable: false);
            final more = mainActions.isEmpty
                ? actions.skip(1).toList(growable: false)
                : secondaryActions.toList(growable: false);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 13),
                if (compact) ...[
                  ...featured.map(
                    (action) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ActionRow(action: action),
                    ),
                  ),
                  if (more.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 5),
                      leading: const Icon(Icons.grid_view_outlined),
                      title: Text('More tasks (${more.length})'),
                      children: [
                        for (final action in more)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ActionRow(action: action),
                          ),
                      ],
                    ),
                ] else
                  _ActionGrid(actions: actions),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.actions});

  final List<GuidedAction> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 960 ? 3 : 2;
          const space = 11.0;
          final width =
              (constraints.maxWidth - space * (columns - 1)) / columns;
          return Wrap(
            spacing: space,
            runSpacing: space,
            children: [
              for (final action in actions)
                SizedBox(
                  width: width,
                  child: _ActionRow(action: action),
                ),
            ],
          );
        },
      );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action});

  final GuidedAction action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = action.primary
        ? FilledButton.icon(
            onPressed: action.enabled ? action.onOpen : null,
            icon: const Icon(Icons.arrow_forward_rounded, size: 17),
            label: const Text('Start'),
          )
        : OutlinedButton.icon(
            onPressed: action.enabled ? action.onOpen : null,
            icon: const Icon(Icons.arrow_forward_rounded, size: 17),
            label: const Text('Open'),
          );
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: action.primary
            ? scheme.primaryContainer.withValues(alpha: .27)
            : scheme.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(action.icon, size: 21, color: scheme.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  action.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            action.enabled
                ? action.description
                : 'Select an authorised branch to continue.',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: button),
        ],
      ),
    );
  }
}
