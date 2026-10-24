part of 'my_work_screen.dart';

extension _MyWorkDailyOverviewImpl on _MyWorkScreenState {
  Widget _dailyImpl() {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Daily Orders',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Search full Daily Order history',
                icon: const Icon(Icons.manage_search_rounded),
                onPressed: _searchDailyHistoryImpl,
              ),
              if (app.can('daily_order.self') || app.can('daily_order.others'))
                FilledButton.icon(
                  onPressed: app.currentBranchId == null || _dailyOrderOpening
                      ? null
                      : _MyWorkDaily(this)._newDailyOrder,
                  icon: _dailyOrderOpening
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(_dailyOrderOpening ? 'Opening...' : 'New Order'),
                ),
            ],
          ),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _feedbackBanner(message!),
            ),
          ),
        Expanded(
          child: AsyncPanel(
            key: ValueKey('daily-${app.currentBranchId}-$refresh'),
            future: _MyWorkDaily(this)._dailyRows(app, api),
            emptyMessage: 'Daily Order nahi mila.',
            builder: (context, data) {
              final rows = (data as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
              final filtered = V8DailyOrderStages.visible(
                rows, _dailyQueueStage);
              return Column(children: [
                V8DailyOrderBoard(
                  rows: rows,
                  selectedStage: _dailyQueueStage,
                  onStageChanged: (stage) =>
                      _setFeatureState(() => _dailyQueueStage = stage),
                ),
                Expanded(child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (filtered.isEmpty) {
                      return const Center(child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No loaded orders at this stage. '
                          'Choose All or search the full Daily Order history.',
                          textAlign: TextAlign.center),
                      ));
                    }
                    if (constraints.maxWidth >= 1060) {
                      return GridView.builder(
                        padding: const EdgeInsets.all(14),
                        itemCount: filtered.length,
                        gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 11,
                            crossAxisSpacing: 11,
                            mainAxisExtent: 235),
                        itemBuilder: (_, i) => _v8DailyCard(filtered[i], app),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => SizedBox(
                        height: 230,
                        child: _v8DailyCard(filtered[i], app)),
                    );
                  },
                )),
              ]);
            },
          ),
        ),
      ],
    );
  }


  Widget _v8DailyCard(Map<String, dynamic> row, AppState app) {
    final id = int.parse('${row['id']}');
    return V8DailyOrderCard(
      id: id,
      employee: _MyWorkDaily(this)._dailyEmployeeLabel(row),
      branch: '${row['branch_name'] ?? app.currentBranchName}',
      businessDate: BusinessFormat.date(row['business_date']),
      statusBadge: _dailyRowStatusChip(row),
      action: _dailyActionsImpl(row, app, id),
      onOpen: () => _MyWorkDaily(this)._showDaily(id),
    );
  }

  Future<void> _searchDailyHistoryImpl() async {
    final api = ref.read(apiClientProvider);
    final app = ref.read(appStateProvider);
    final query = TextEditingController();
    final from = TextEditingController();
    final to = TextEditingController();
    String status = '';
    int page = 1;
    const pageSize = 25;

    Future<Map<String, dynamic>> fetchPage() async {
      return Map<String, dynamic>.from(
        await api.get(
          ApiPaths.dailyHistorySearch,
          query: {
            if (app.currentBranchId != null) 'branch_id': app.currentBranchId,
            'page': page,
            'page_size': pageSize,
            if (query.text.trim().isNotEmpty) 'query': query.text.trim(),
            if (status.isNotEmpty) 'status': status,
            if (from.text.trim().isNotEmpty) 'date_from': from.text.trim(),
            if (to.text.trim().isNotEmpty) 'date_to': to.text.trim(),
          },
        ) as Map,
      );
    }

    Future<Map<String, dynamic>> current = fetchPage();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, update) {
            void applyFilters() => update(() {
              page = 1;
              current = fetchPage();
            });
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              title: const Text('Find Daily Orders'),
              content: SizedBox(
                width: MediaQuery.sizeOf(dialogContext).width > 820
                    ? 760
                    : MediaQuery.sizeOf(dialogContext).width - 56,
                height: MediaQuery.sizeOf(dialogContext).height * .68,
                child: Column(
                  children: [
                    Flexible(
                      flex: 1,
                      child: SingleChildScrollView(
                        child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 205,
                            child: TextField(
                              controller: query,
                              onSubmitted: (_) => applyFilters(),
                              decoration: const InputDecoration(
                                labelText: 'Order ID / Employee',
                                isDense: true,
                                prefixIcon: Icon(Icons.search),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: DropdownButtonFormField<String>(
                              initialValue: status,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Status', isDense: true),
                              items: const [
                                DropdownMenuItem(value: '', child: Text('All statuses')),
                                DropdownMenuItem(value: 'morning_draft', child: Text('Draft')),
                                DropdownMenuItem(value: 'stock_requested', child: Text('Pending approval')),
                                DropdownMenuItem(value: 'approved', child: Text('Approved')),
                                DropdownMenuItem(value: 'issued', child: Text('Issued')),
                                DropdownMenuItem(value: 'evening_draft', child: Text('Evening draft')),
                                DropdownMenuItem(value: 'evening_submitted', child: Text('Closing review')),
                                DropdownMenuItem(value: 'completed', child: Text('Completed')),
                                DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                                DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                              ],
                              onChanged: (value) { status = value ?? ''; applyFilters(); },
                            ),
                          ),
                          SizedBox(
                            width: 132,
                            child: TextField(
                              controller: from,
                              keyboardType: TextInputType.datetime,
                              onSubmitted: (_) => applyFilters(),
                              decoration: const InputDecoration(labelText: 'From YYYY-MM-DD', isDense: true),
                            ),
                          ),
                          SizedBox(
                            width: 132,
                            child: TextField(
                              controller: to,
                              keyboardType: TextInputType.datetime,
                              onSubmitted: (_) => applyFilters(),
                              decoration: const InputDecoration(labelText: 'To YYYY-MM-DD', isDense: true),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: applyFilters,
                            icon: const Icon(Icons.filter_alt_outlined),
                            label: const Text('Search'),
                          ),
                        ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      flex: 2,
                      child: FutureBuilder<Map<String, dynamic>>(
                        future: current,
                        builder: (context, result) {
                          if (result.hasError) {
                            return Center(child: Text('Search failed: ${UiError.message(result.error!)}'));
                          }
                          if (!result.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final data = result.data!;
                          final items = ((data['items'] as List?) ?? const [])
                              .whereType<Map>()
                              .map((row) => Map<String, dynamic>.from(row))
                              .toList();
                          final total = (data['total'] as num?)?.toInt() ?? 0;
                          final hasMore = data['has_more'] == true;
                          return Column(
                            children: [
                              Expanded(
                                child: items.isEmpty
                                    ? const Center(child: Text('No matching authorised orders.'))
                                    : ListView.separated(
                                        itemCount: items.length,
                                        separatorBuilder: (_, __) => const Divider(height: 1),
                                        itemBuilder: (context, i) {
                                          final row = items[i];
                                          final orderId = int.tryParse('${row['id']}') ?? 0;
                                          return ListTile(
                                            title: Text('#$orderId · ${row['employee_name'] ?? 'Employee'}'),
                                            subtitle: Text('${BusinessFormat.date(row['business_date'])} · ${_dailyRowStatusText(row)}'),
                                            trailing: const Icon(Icons.chevron_right),
                                            onTap: orderId == 0 ? null : () {
                                              Navigator.pop(dialogContext);
                                              _MyWorkDaily(this)._showDaily(orderId);
                                            },
                                          );
                                        },
                                      ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(child: Text('$total total · Page $page', maxLines: 1)),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Previous page',
                                        onPressed: page <= 1 ? null : () => update(() {
                                          page--;
                                          current = fetchPage();
                                        }),
                                        icon: const Icon(Icons.chevron_left),
                                      ),
                                      IconButton(
                                        tooltip: 'Next page',
                                        onPressed: !hasMore ? null : () => update(() {
                                          page++;
                                          current = fetchPage();
                                        }),
                                        icon: const Icon(Icons.chevron_right),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
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
    } finally {
      query.dispose();
      from.dispose();
      to.dispose();
    }
  }

  Future<List<Map<String, dynamic>>> _dailyRowsImpl(
    AppState app,
    dynamic api,
  ) async {
    final rows = (await api.get(
      ApiPaths.dailyCycles,
      query: {
        if (app.currentBranchId != null) 'branch_id': app.currentBranchId,
      },
    ) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final branchNames = <int, String>{
      for (final b in app.branches)
        if (int.tryParse('${b['id']}') != null)
          int.parse('${b['id']}'): '${b['name'] ?? 'Branch'}',
    };
    final employeeNames = <int, Map<String, dynamic>>{};
    try {
      final employees = (await api.get(
        ApiPaths.employees,
        query: {
          if (app.currentBranchId != null) 'branch_id': app.currentBranchId,
        },
      ) as List)
          .map((e) => Map<String, dynamic>.from(e as Map));
      for (final e in employees) {
        final id = int.tryParse('${e['id']}');
        if (id != null) employeeNames[id] = e;
      }
    } catch (_) {
      final me = Map<String, dynamic>.from(
        (app.me['employee'] as Map?) ?? const {},
      );
      final id = int.tryParse('${me['id'] ?? ''}');
      if (id != null) employeeNames[id] = me;
    }

    for (final row in rows) {
      final employeeId = int.tryParse('${row['employee_id'] ?? ''}');
      final branchId = int.tryParse('${row['branch_id'] ?? ''}');
      if (employeeId != null && employeeNames[employeeId] != null) {
        final e = employeeNames[employeeId]!;
        row['employee_name'] ??= e['full_name'] ?? e['name'];
        row['employee_code'] ??= e['employee_code'];
      }
      if (branchId != null) row['branch_name'] ??= branchNames[branchId];
    }
    return rows;
  }

  String _dailyEmployeeLabelImpl(Map<String, dynamic> row) {
    final name = '${row['employee_name'] ?? 'Employee #${row['employee_id']}'}';
    final code = '${row['employee_code'] ?? ''}'.trim();
    return code.isEmpty ? name : '$name · $code';
  }

  String _statusTextImpl(String status) =>
      DailyOrderWorkflow.statusLabel(status);

  Widget _orderStatusChipImpl(String status) {
    Color background;
    Color foreground;
    IconData icon;
    switch (status) {
      case 'completed':
        background = const Color(0xFFDFF3E6);
        foreground = ExcelBrand.primaryDark;
        icon = Icons.check_circle_outline_rounded;
        break;
      case 'approved':
      case 'issued':
      case 'stock_requested':
      case 'evening_submitted':
        background = const Color(0xFFFFF0D8);
        foreground = const Color(0xFF8A5700);
        icon = Icons.schedule_rounded;
        break;
      case 'cancelled':
        background = const Color(0xFFFFE6E6);
        foreground = const Color(0xFF9B3030);
        icon = Icons.cancel_outlined;
        break;
      default:
        background = const Color(0xFFF0F3F1);
        foreground = ExcelBrand.muted;
        icon = Icons.edit_note_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            _MyWorkDaily(this)._statusText(status),
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _dailyRowStatusText(Map<String, dynamic> row) =>
      DailyOrderWorkflow.orderStatusLabel(row);

  Widget _dailyRowStatusChip(Map<String, dynamic> row) {
    final status = '${row['status'] ?? ''}';
    final label = _dailyRowStatusText(row);
    if (!label.contains('Additional Approval Pending') &&
        !label.contains('Additional Issue Pending')) {
      return _MyWorkDaily(this)._orderStatusChip(status);
    }
    const background = Color(0xFFFFF0D8);
    const foreground = Color(0xFF8A5700);
    final icon = label.contains('Additional Issue Pending')
        ? Icons.inventory_2_outlined
        : Icons.task_alt_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: foreground,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  int? _currentEmployeeId(AppState app) {
    final me = Map<String, dynamic>.from(
      (app.me['employee'] as Map?) ?? const {},
    );
    return int.tryParse('${me['id'] ?? ''}');
  }

  String? _dailyPrimaryActionImpl(
    Map<String, dynamic> row,
    AppState app,
  ) {
    final status = '${row['status'] ?? ''}';
    final initialRequestStatus = '${row['initial_request_status'] ?? ''}';
    final initialRequesterId =
        int.tryParse('${row['initial_requested_by'] ?? ''}');
    final additionalRequestStatus =
        '${row['additional_request_status'] ?? ''}';
    final additionalRequesterId =
        int.tryParse('${row['additional_requested_by'] ?? ''}');
    final currentEmployeeId = _currentEmployeeId(app);

    if (DailyOrderWorkflow.canSubmitDraft(status, app.capabilities)) {
      return 'submit';
    }
    if (status == 'stock_requested' &&
        DailyOrderWorkflow.canApproveRequest(
          initialRequestStatus,
          app.capabilities,
          requesterId: initialRequesterId,
          currentEmployeeId: currentEmployeeId,
        )) {
      return 'approve';
    }
    if (status == 'approved' &&
        DailyOrderWorkflow.canIssueRequest(
          initialRequestStatus,
          app.capabilities,
          requesterId: initialRequesterId,
          currentEmployeeId: currentEmployeeId,
        )) {
      return 'issue';
    }
    if (status == 'issued' &&
        DailyOrderWorkflow.canApproveRequest(
          additionalRequestStatus,
          app.capabilities,
          requesterId: additionalRequesterId,
          currentEmployeeId: currentEmployeeId,
        )) {
      return 'approve';
    }
    if (status == 'issued' &&
        DailyOrderWorkflow.canIssueRequest(
          additionalRequestStatus,
          app.capabilities,
          requesterId: additionalRequesterId,
          currentEmployeeId: currentEmployeeId,
        )) {
      return 'issue';
    }
    if (status == 'issued' &&
        additionalRequestStatus.isEmpty &&
        DailyOrderWorkflow.canOperateOwnOrder(app.capabilities)) {
      return 'evening';
    }
    if (status == 'evening_draft' &&
        DailyOrderWorkflow.canOperateOwnOrder(app.capabilities)) {
      return 'evening_edit';
    }
    if (status == 'evening_submitted' && app.can('daily_order.review')) {
      return 'final_post';
    }
    return null;
  }

  String _dailyActionLabelImpl(String action, {bool additional = false}) =>
      switch (action) {
        'submit' => 'Submit for Approval',
        'approve' => additional ? 'Approve Additional' : 'Approve Order',
        'issue' => additional ? 'Issue Additional Stock' : 'Issue Stock',
        'evening' => 'Start Closing',
        'evening_edit' => 'Continue Closing',
        'final_post' => 'Final Post',
        _ => 'Open',
      };

  Widget _dailyActionsImpl(
    Map<String, dynamic> row,
    AppState app,
    int id,
  ) {
    final primary = _dailyPrimaryActionImpl(row, app);
    final isAdditionalAction =
        '${row['status'] ?? ''}' == 'issued' &&
        '${row['additional_request_status'] ?? ''}'.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (primary != null)
          FilledButton.tonalIcon(
            onPressed: () => _MyWorkDaily(this)._dailyAction(id, primary),
            icon: Icon(
              primary == 'issue'
                  ? Icons.inventory_2_outlined
                  : primary == 'approve'
                      ? Icons.task_alt_rounded
                      : primary == 'submit'
                          ? Icons.send_rounded
                          : primary == 'evening' || primary == 'evening_edit'
                              ? Icons.nightlight_round
                              : primary == 'final_post'
                                  ? Icons.verified_outlined
                                  : Icons.arrow_forward_rounded,
              size: 18,
            ),
            label: Text(
              _dailyActionLabelImpl(primary, additional: isAdditionalAction),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: () => _MyWorkDaily(this)._dailyAction(id, 'view'),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('View'),
          ),
        PopupMenuButton<String>(
          tooltip: 'More actions',
          onSelected: (v) => _MyWorkDaily(this)._dailyAction(id, v),
          itemBuilder: (_) => _dailyMenuImpl(row, app),
        ),
      ],
    );
  }

  List<PopupMenuEntry<String>> _dailyMenuImpl(
    Map<String, dynamic> row,
    AppState app,
  ) {
    final status = '${row['status'] ?? ''}';
    final initialRequestStatus = '${row['initial_request_status'] ?? ''}';
    final initialRequesterId =
        int.tryParse('${row['initial_requested_by'] ?? ''}');
    final additionalRequestStatus =
        '${row['additional_request_status'] ?? ''}';
    final additionalRequesterId =
        int.tryParse('${row['additional_requested_by'] ?? ''}');
    final currentEmployeeId = _currentEmployeeId(app);
    final primary = _dailyPrimaryActionImpl(row, app);
    final out = <PopupMenuEntry<String>>[
      const PopupMenuItem(value: 'view', child: Text('View Details')),
    ];

    if (status == 'morning_draft' &&
        DailyOrderWorkflow.canOperateOwnOrder(app.capabilities)) {
      out.add(const PopupMenuItem(
        value: 'edit_draft',
        child: Text('Edit Draft'),
      ));
    }
    if (const {'morning_draft', 'stock_requested'}.contains(status) &&
        DailyOrderWorkflow.canOperateOwnOrder(app.capabilities)) {
      out.add(const PopupMenuItem(
        value: 'cancel_cycle',
        child: Text('Cancel Order (reason required)'),
      ));
    }
    if (status == 'cancelled' &&
        DailyOrderWorkflow.canOperateOwnOrder(app.capabilities)) {
      out.add(const PopupMenuItem(
        value: 'reopen_draft',
        child: Text('Reopen as Draft'),
      ));
    }
    if (status == 'stock_requested' &&
        DailyOrderWorkflow.canApproveRequest(
          initialRequestStatus,
          app.capabilities,
          requesterId: initialRequesterId,
          currentEmployeeId: currentEmployeeId,
        )) {
      out.add(const PopupMenuItem(
        value: 'reject',
        child: Text('Reject Order (reason required)'),
      ));
    }

    if (primary != 'submit' &&
        DailyOrderWorkflow.canSubmitDraft(status, app.capabilities)) {
      out.add(
        const PopupMenuItem(value: 'submit', child: Text('Submit Order')),
      );
    }
    if (primary != 'approve' &&
        status == 'stock_requested' &&
        DailyOrderWorkflow.canApproveRequest(
          initialRequestStatus,
          app.capabilities,
          requesterId: initialRequesterId,
          currentEmployeeId: currentEmployeeId,
        )) {
      out.add(const PopupMenuItem(value: 'approve', child: Text('Approve')));
    }
    if (primary != 'issue' &&
        status == 'approved' &&
        DailyOrderWorkflow.canIssueRequest(
          initialRequestStatus,
          app.capabilities,
          requesterId: initialRequesterId,
          currentEmployeeId: currentEmployeeId,
        )) {
      out.add(const PopupMenuItem(value: 'issue', child: Text('Issue Stock')));
    }

    if (status == 'issued') {
      if (DailyOrderWorkflow.canApproveRequest(
        additionalRequestStatus, app.capabilities,
        requesterId: additionalRequesterId,
        currentEmployeeId: currentEmployeeId,
      )) {
        out.add(const PopupMenuItem(
          value: 'reject',
          child: Text('Reject Additional Request'),
        ));
      }
      if (const {'draft', 'submitted', 'approved'}.contains(additionalRequestStatus) &&
          DailyOrderWorkflow.canOperateOwnOrder(app.capabilities)) {
        out.add(const PopupMenuItem(
          value: 'cancel_additional',
          child: Text('Cancel Pending Additional'),
        ));
      }
      if (primary != 'approve' &&
          DailyOrderWorkflow.canApproveRequest(
            additionalRequestStatus,
            app.capabilities,
            requesterId: additionalRequesterId,
            currentEmployeeId: currentEmployeeId,
          )) {
        out.add(
          const PopupMenuItem(
            value: 'approve',
            child: Text('Approve Additional'),
          ),
        );
      }
      if (primary != 'issue' &&
          DailyOrderWorkflow.canIssueRequest(
            additionalRequestStatus,
            app.capabilities,
            requesterId: additionalRequesterId,
            currentEmployeeId: currentEmployeeId,
          )) {
        out.add(
          const PopupMenuItem(
            value: 'issue',
            child: Text('Issue Additional Stock'),
          ),
        );
      }
      if (additionalRequestStatus.isEmpty &&
          DailyOrderWorkflow.canOperateOwnOrder(app.capabilities)) {
        out.add(
          const PopupMenuItem(
            value: 'additional',
            child: Text('Additional Requirement'),
          ),
        );
        if (primary != 'evening') {
          out.add(
            const PopupMenuItem(
              value: 'evening',
              child: Text('Start Evening Closing'),
            ),
          );
        }
      }
    }

    if (status == 'evening_draft' &&
        DailyOrderWorkflow.canOperateOwnOrder(app.capabilities) &&
        primary != 'evening_edit') {
      out.add(
        const PopupMenuItem(
          value: 'evening_edit',
          child: Text('Edit Evening Closing'),
        ),
      );
    }
    if (status == 'evening_submitted' &&
        app.can('daily_order.review') &&
        primary != 'final_post') {
      out.add(
        const PopupMenuItem(value: 'final_post', child: Text('Final Post')),
      );
    }
    return out;
  }

}
