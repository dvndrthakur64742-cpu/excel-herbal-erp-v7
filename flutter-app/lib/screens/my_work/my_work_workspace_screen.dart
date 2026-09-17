import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shell/shell_layout.dart';
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

  // MyWorkScreen still owns a legacy 820px Daily Order table switch. Until
  // that large workflow file is split, keep tablet widths below that switch
  // so the shell and the business list do not disagree about layout mode.
  static const double _tabletCardWidth = 819;

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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screen = MyWorkScreen(
                initialSection: initialSection,
                initialAction: initialAction,
              );
              if (ShellLayout.isDesktopWidth(constraints.maxWidth) ||
                  constraints.maxWidth < 820) {
                return screen;
              }
              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: _tabletCardWidth,
                  height: constraints.maxHeight,
                  child: screen,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
