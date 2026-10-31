part of 'organization_screen.dart';

extension _OrganizationBranchesFeature on _OrganizationScreenState {
  Widget _branchesTab(AppState app) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (app.can('organization.branch.manage'))
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _createBranch,
              icon: const Icon(Icons.add_business),
              label: const Text('New Branch'),
            ),
          ),
        if (app.can('organization.branch.manage')) const SizedBox(height: 12),
        Text(
          'Authorised Branches',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        ...app.branches.map(
          (b) => Card(
            child: ListTile(
              leading: Icon(
                '${b['is_head_office']}' == '1'
                    ? Icons.corporate_fare
                    : Icons.store_outlined,
              ),
              title: Text('${b['name']}'),
              subtitle: Text('${b['code']}'),
              trailing: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (int.tryParse('${b['id']}') == app.currentBranchId)
                    const Chip(label: Text('Current')),
                  if (app.can('organization.branch.manage'))
                    TextButton.icon(
                      onPressed: () => _editBranch(
                        Map<String, dynamic>.from(b),
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      label: const Text('Edit'),
                    )
                  else
                    const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () => _openBranchDetail(Map<String, dynamic>.from(b)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openBranchDetail(Map<String, dynamic> branch) async {
    final title = '${branch['name'] ?? 'Branch'}';
    if (MediaQuery.sizeOf(context).width >= 820) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          child: SizedBox(
            width: 680,
            height: MediaQuery.sizeOf(context).height * .72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Branch Details',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: BusinessRecordDetailView(
                    row: branch,
                    title: title,
                    recordType: 'branch',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RecordDetailScreen(row: branch, title: title, recordType: 'branch'),
      ),
    );
  }

  Future<void> _editBranch(Map<String, dynamic> branch) async {
    final id = int.tryParse('${branch['id']}') ?? 0;
    if (id < 1) return;
    final code = TextEditingController(text: '${branch['code'] ?? ''}');
    final name = TextEditingController(text: '${branch['name'] ?? ''}');
    String? formError;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text('Edit Branch · ${branch['code'] ?? ''}'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: code,
                  decoration: const InputDecoration(labelText: 'Branch Code'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Branch Name'),
                ),
                if (formError != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formError!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (code.text.trim().isEmpty || name.text.trim().isEmpty) {
                  setLocal(
                    () => formError = 'Branch code aur name required hain.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) {
      code.dispose();
      name.dispose();
      return;
    }

    try {
      await ref.read(apiClientProvider).post(
        ApiPaths.branchUpdate(id),
        data: {
          'code': code.text.trim(),
          'name': name.text.trim(),
        },
      );
      await ref.read(appStateProvider.notifier).refreshBootstrap();
      if (mounted) {
        _setOrganizationState(() {
          refresh++;
          message = 'Branch details update ho gaye.';
        });
      }
    } catch (e) {
      if (mounted) {
        _setOrganizationState(() => message = UiError.message(e));
      }
    } finally {
      code.dispose();
      name.dispose();
    }
  }

  Future<void> _createBranch() async {
    final code = TextEditingController();
    final name = TextEditingController();
    var headOffice = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New Branch'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: code,
                  decoration: const InputDecoration(labelText: 'Branch Code'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Branch Name'),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: headOffice,
                  title: const Text('Head Office'),
                  onChanged: (v) => setLocal(() => headOffice = v == true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                code.text.trim().isNotEmpty && name.text.trim().isNotEmpty,
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    final payload = {
      'code': code.text.trim(),
      'name': name.text.trim(),
      'is_head_office': headOffice,
    };
    code.dispose();
    name.dispose();
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).post(ApiPaths.branches, data: payload);
      await ref.read(appStateProvider.notifier).refreshBootstrap();
      if (mounted)
        _setOrganizationState(
          () => message =
              'Branch create ho gaya; creator authority bootstrap ho gayi.',
        );
    } catch (e) {
      if (mounted) _setOrganizationState(() => message = UiError.message(e));
    }
  }

}
