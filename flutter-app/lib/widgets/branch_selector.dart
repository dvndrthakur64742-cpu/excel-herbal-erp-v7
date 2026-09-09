import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';

class BranchSelector extends ConsumerWidget {
  const BranchSelector({super.key});

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

    final selected = branches.any((branch) => branch.id == app.currentBranchId)
        ? app.currentBranchId
        : null;

    return DropdownButtonFormField<int>(
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
        if (value != null) {
          ref.read(appStateProvider.notifier).selectBranch(value);
        }
      },
    );
  }
}
