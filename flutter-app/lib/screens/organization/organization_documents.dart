part of 'organization_screen.dart';

extension _OrganizationDocumentsFeature on _OrganizationScreenState {
  Future<void> _employeeDocuments(int employeeId, String employeeName) async {
    if (!await OverlayTransition.closeAndSettle(context) || !mounted) return;
    final app = ref.read(appStateProvider);
    await _showPrivateDocuments(
      title: '$employeeName · Private Documents',
      listPath: ApiPaths.employeeDocuments(employeeId),
      uploadPath: ApiPaths.employeeDocumentUpload(employeeId),
      deactivatePath: (documentId) =>
          ApiPaths.employeeDocumentDeactivate(employeeId, documentId),
      canManage: app.can('organization.employee.manage'),
    );
  }

  Future<void> _showPrivateDocuments({
    required String title,
    required String listPath,
    required String uploadPath,
    required String Function(int documentId) deactivatePath,
    required bool canManage,
  }) async {
    final api = ref.read(apiClientProvider);

    Future<List<Map<String, dynamic>>> load() async =>
        (await api.get(listPath) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

    var future = load();
    String? localMessage;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> upload() async {
            try {
              final picked = await FilePicker.platform.pickFiles(
                allowMultiple: false,
                type: FileType.custom,
                allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
                withData: true,
              );
              if (picked == null || picked.files.isEmpty) return;
              final file = picked.files.single;
              final bytes = file.bytes;
              if (bytes == null || bytes.isEmpty) {
                throw const FormatException('The selected file could not be read.');
              }
              if (bytes.length > 10 * 1024 * 1024) {
                throw const FormatException('Document size must not exceed 10 MB.');
              }

              var documentType = 'other';
              final documentTitle = TextEditingController(text: file.name);
              final metaOk = await showDialog<bool>(
                context: dialogContext,
                builder: (context) => StatefulBuilder(
                  builder: (context, setMeta) => AlertDialog(
                    title: const Text('Document Details'),
                    content: SizedBox(
                      width: 460,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: documentType,
                            decoration: const InputDecoration(
                              labelText: 'Document Type',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'identity',
                                child: Text('Identity'),
                              ),
                              DropdownMenuItem(
                                value: 'education',
                                child: Text('Education'),
                              ),
                              DropdownMenuItem(
                                value: 'employment',
                                child: Text('Employment'),
                              ),
                              DropdownMenuItem(
                                value: 'salary',
                                child: Text('Salary / Compensation'),
                              ),
                              DropdownMenuItem(
                                value: 'other',
                                child: Text('Other'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setMeta(() => documentType = value);
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: documentTitle,
                            decoration:
                                const InputDecoration(labelText: 'Title'),
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
                          documentTitle.text.trim().isNotEmpty,
                        ),
                        child: const Text('Upload'),
                      ),
                    ],
                  ),
                ),
              );
              final titleValue = documentTitle.text.trim();
              documentTitle.dispose();
              if (metaOk != true) return;

              await api.uploadBytes(
                uploadPath,
                bytes: bytes,
                filename: file.name,
                fields: {
                  'document_type': documentType,
                  'title': titleValue,
                },
              );
              setLocal(() {
                localMessage = 'Private document uploaded securely.';
                future = load();
              });
            } catch (e) {
              setLocal(() => localMessage = UiError.message(e));
            }
          }

          Future<void> open(Map<String, dynamic> row) async {
            try {
              await openErpDocument(api, row);
            } catch (e) {
              setLocal(() => localMessage = UiError.message(e));
            }
          }

          Future<void> deactivate(Map<String, dynamic> row) async {
            final id = int.tryParse('${row['id']}');
            if (id == null) return;
            final confirmed = await showDialog<bool>(
              context: dialogContext,
              builder: (context) => AlertDialog(
                title: const Text('Deactivate Document'),
                content: Text(
                  'Deactivate "${row['title'] ?? 'this document'}"? The audit record will be retained.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Deactivate'),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;
            try {
              await api.post(deactivatePath(id), data: const {});
              setLocal(() {
                localMessage = 'Document deactivated; audit history retained.';
                future = load();
              });
            } catch (e) {
              setLocal(() => localMessage = UiError.message(e));
            }
          }

          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 720,
              height: 460,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (localMessage != null) ...[
                    ModuleMessageBanner(message: localMessage!),
                    const SizedBox(height: 8),
                  ],
                  if (canManage)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: upload,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Upload Private Document'),
                      ),
                    ),
                  if (canManage) const SizedBox(height: 8),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: future,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(UiError.message(snapshot.error!)),
                          );
                        }
                        final rows = snapshot.data ?? const [];
                        if (rows.isEmpty) {
                          return const Center(
                            child: Text('No active private documents.'),
                          );
                        }
                        return ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final row = rows[index];
                            return ListTile(
                              leading:
                                  const Icon(Icons.description_outlined),
                              title: Text('${row['title'] ?? 'Document'}'),
                              subtitle: Text(
                                '${row['document_type'] ?? 'document'} · ${row['created_at'] ?? ''}',
                              ),
                              onTap: () => open(row),
                              trailing: canManage
                                  ? PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'open') open(row);
                                        if (value == 'deactivate') {
                                          deactivate(row);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'open',
                                          child: Text('Open / Share'),
                                        ),
                                        PopupMenuItem(
                                          value: 'deactivate',
                                          child: Text('Deactivate'),
                                        ),
                                      ],
                                    )
                                  : IconButton(
                                      tooltip: 'Open / Share',
                                      onPressed: () => open(row),
                                      icon: const Icon(
                                        Icons.open_in_new_outlined,
                                      ),
                                    ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }
}
