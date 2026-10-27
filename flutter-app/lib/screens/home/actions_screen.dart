import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shell/workspace_action_catalog.dart';
import '../../state/app_state.dart';
import '../../theme/excel_brand.dart';

class ActionsScreen extends ConsumerWidget {
  const ActionsScreen({
    super.key,
    required this.openConnectedAction,
  });

  final void Function(String actionId) openConnectedAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final actions = WorkspaceActionCatalog.visible(app.can);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Quick Actions', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 5),
        Text(
          'Only actions authorised for your role and permissions are shown here.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: ExcelBrand.muted),
        ),
        const SizedBox(height: 16),
        if (actions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('No quick actions are available for your role.'),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 240,
              mainAxisExtent: 116,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: actions.length,
            itemBuilder: (_, i) {
              final action = actions[i];
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  // The Shell re-checks current RBAC before it opens a screen.
                  onTap: () => openConnectedAction(action.id),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(
                            color: ExcelBrand.primarySoft,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(action.icon, size: 20,
                              color: ExcelBrand.primaryDark),
                        ),
                        const Spacer(),
                        Text(action.label,
                            style: Theme.of(context).textTheme.titleSmall),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
