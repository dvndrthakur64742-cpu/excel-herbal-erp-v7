import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';

class BranchSelector extends ConsumerWidget {
  const BranchSelector({super.key, this.allowAllAuthorised = false});

  final bool allowAllAuthorised;

  static const double _compactBreakpoint = 600;
  static const double _maxFieldWidth = 420;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    if (!app.branchSelectorVisible) return const SizedBox.shrink();

    final branches = <({int id, String name})>[];
    for (final branch in app.branches) {
      final id = int.tryParse('${branch['id']}');
      if (id == null) continue;
      branches.add((id: id, name: '${branch['name'] ?? 'Branch'}'));
    }
    if (branches.isEmpty) return const SizedBox.shrink();

    final selectedBranchExists =
        branches.any((branch) => branch.id == app.currentBranchId);
    final selected = selectedBranchExists
        ? app.currentBranchId
        : (allowAllAuthorised ? -1 : null);

    final field = DropdownButtonFormField<int>(
      key: ValueKey('${allowAllAuthorised}_${app.currentBranchId}'),
      isExpanded: true,
      menuMaxHeight: 360,
      initialValue: selected,
      decoration: const InputDecoration(
        labelText: 'Branch',
        prefixIcon: Icon(Icons.store_outlined, size: 20),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: [
        if (allowAllAuthorised)
          const DropdownMenuItem<int>(
            value: -1,
            child: Text('All Authorised Branches'),
          ),
        for (final branch in branches)
          DropdownMenuItem<int>(
            value: branch.id,
            child: Text(
              branch.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        if (value == -1 && allowAllAuthorised) {
          ref.read(appStateProvider.notifier).selectAllAuthorisedBranches();
          return;
        }
        if (value != null) {
          ref.read(appStateProvider.notifier).selectBranch(value);
        }
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _compactBreakpoint) return field;
        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxFieldWidth),
            child: field,
          ),
        );
      },
    );
  }
}
