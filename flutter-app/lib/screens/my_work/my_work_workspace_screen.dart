import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_state.dart';
import '../../widgets/module_workspace.dart';
import 'my_work_screen.dart';

class MyWorkWorkspaceScreen extends ConsumerWidget {
  const MyWorkWorkspaceScreen({
    super.key,
    this.initialSection = 'attendance',
    this.initialAction,
  });

  final String initialSection;
  final String? initialAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final branch = app.currentBranchName.trim();
    final contextLabel = app.businessAccessBlocked
        ? 'No Authorised Branch'
        : branch.isEmpty
            ? 'Authorised workspace'
            : branch;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: ModuleWorkspaceHeader(
            title: 'My Work',
            subtitle:
                'Attendance, daily orders, leave and field visits in one workspace.',
            icon: Icons.work_outline_rounded,
            contextLabel: contextLabel,
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: MyWorkScreen(
            initialSection: initialSection,
            initialAction: initialAction,
          ),
        ),
      ],
    );
  }
}
