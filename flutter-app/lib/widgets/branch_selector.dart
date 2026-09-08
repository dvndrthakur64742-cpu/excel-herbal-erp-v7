import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';

class BranchSelector extends ConsumerWidget {
  const BranchSelector({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    if (!app.branchSelectorVisible) return const SizedBox.shrink();
    return DropdownButtonFormField<int>(
      initialValue: app.currentBranchId,
      decoration: const InputDecoration(
        labelText: 'Authorised Branch',
        prefixIcon: Icon(Icons.store_outlined),
      ),
      items: app.branches
          .map(
            (b) => DropdownMenuItem<int>(
              value: int.parse('${b['id']}'),
              child: Text('${b['name']}'),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) ref.read(appStateProvider.notifier).selectBranch(v);
      },
    );
  }
}
