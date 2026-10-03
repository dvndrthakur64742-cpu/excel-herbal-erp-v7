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
              return LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 820) {
                    return Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: DataTable(
                            showBottomBorder: true,
                            headingRowHeight: 46,
                            dataRowMinHeight: 50,
                            columns: const [
                              DataColumn(label: Text('Order')),
                              DataColumn(label: Text('Employee')),
                              DataColumn(label: Text('Business Date')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Action')),
                            ],
                            rows: [
                              for (final r in rows)
                                DataRow(
                                  onSelectChanged: (_) =>
                                      _MyWorkDaily(this)._showDaily(int.parse('${r['id']}')),
                                  cells: [
                                    DataCell(Text('#${r['id']}')),
                                    DataCell(Text(_MyWorkDaily(this)._dailyEmployeeLabel(r))),
                                    DataCell(
                                      Text('${r['business_date'] ?? '—'}'),
                                    ),
                                    DataCell(Text(_dailyRowStatusText(r))),
                                    DataCell(
                                      _dailyActionsImpl(
                                        r,
                                        app,
                                        int.parse('${r['id']}'),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      final id = int.parse('${r['id']}');
                      final name =
                          '${r['employee_name'] ?? 'Employee #${r['employee_id']}'}';
                      final code = '${r['employee_code'] ?? ''}'.trim();
                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _MyWorkDaily(this)._showDaily(id),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Daily Order #$id',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                          _dailyRowStatusChip(r),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        code.isEmpty ? name : '$name · $code',
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${r['branch_name'] ?? 'Authorised Branch'} · ${BusinessFormat.date(r['business_date'])}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                _dailyActionsImpl(r, app, id),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
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

  String _statusTextImpl(String status) {
    const map = {
      'morning_draft': 'Draft',
      'stock_requested': 'Approval Pending',
      'approved': 'Issue Pending',
      'issued': 'Evening Pending',
      'evening_draft': 'Evening Draft',
      'evening_submitted': 'Final Post Pending',
      'completed': 'Completed',
      'cancelled': 'Cancelled',
    };
    return map[status] ?? status;
  }

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

  String _dailyRowStatusText(Map<String, dynamic> row) {
    final status = '${row['status'] ?? ''}';
    final additionalStatus = '${row['additional_request_status'] ?? ''}';
    if (status == 'issued' && additionalStatus == 'submitted') {
      return 'Additional Approval Pending';
    }
    if (status == 'issued' && additionalStatus == 'approved') {
      return 'Additional Issue Pending';
    }
    return _MyWorkDaily(this)._statusText(status);
  }

  Widget _dailyRowStatusChip(Map<String, dynamic> row) {
    final status = '${row['status'] ?? ''}';
    final label = _dailyRowStatusText(row);
    if (label != 'Additional Approval Pending' &&
        label != 'Additional Issue Pending') {
      return _MyWorkDaily(this)._orderStatusChip(status);
    }
    const background = Color(0xFFFFF0D8);
    const foreground = Color(0xFF8A5700);
    final icon = label == 'Additional Issue Pending'
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
    if (status == 'evening_draft') return 'evening_edit';
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

    if (status == 'evening_draft' && primary != 'evening_edit') {
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
