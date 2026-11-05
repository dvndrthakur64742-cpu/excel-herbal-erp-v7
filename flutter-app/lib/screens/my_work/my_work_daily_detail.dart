part of 'my_work_screen.dart';

extension _MyWorkDailyDetailImpl on _MyWorkScreenState {
  Future<void> _showDailyImpl(int id) async {
    try {
      final d = await _MyWorkDaily(this)._dailyDetail(id);
      if (!mounted) return;
      final cycle = Map<String, dynamic>.from((d['cycle'] as Map?) ?? const {});
      final requests = ((d['requests'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final evening = d['evening'] is Map
          ? Map<String, dynamic>.from(d['evening'] as Map)
          : null;

      final app = ref.read(appStateProvider);
      final branchId = int.tryParse('${cycle['branch_id'] ?? ''}');
      final employeeId = int.tryParse('${cycle['employee_id'] ?? ''}');
      var branchName = 'Authorised Branch';
      for (final b in app.branches) {
        if (int.tryParse('${b['id']}') == branchId) {
          branchName = '${b['name'] ?? branchName}';
          break;
        }
      }
      var employeeName = '${cycle['employee_name'] ?? ''}'.trim();
      var employeeCode = '${cycle['employee_code'] ?? ''}'.trim();
      if (employeeName.isEmpty && employeeId != null) {
        try {
          final employees = (await ref.read(apiClientProvider).get(
            ApiPaths.employees,
            query: {
              if (branchId != null) 'branch_id': branchId,
            },
          ) as List)
              .map((e) => Map<String, dynamic>.from(e as Map));
          for (final e in employees) {
            if (int.tryParse('${e['id']}') == employeeId) {
              employeeName = '${e['full_name'] ?? e['name'] ?? ''}'.trim();
              employeeCode = '${e['employee_code'] ?? ''}'.trim();
              break;
            }
          }
        } catch (_) {}
      }
      if (employeeName.isEmpty) employeeName = 'Employee';
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .82,
          maxChildSize: .96,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daily Order #$id',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          BusinessFormat.date(cycle['business_date']),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  _MyWorkDaily(this)._orderStatusChip('${cycle['status']}'),
                ],
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _MyWorkDaily(this)._dailyInfoRow(
                        context,
                        Icons.person_outline,
                        'Employee',
                        employeeCode.isEmpty
                            ? employeeName
                            : '$employeeName · $employeeCode',
                      ),
                      const Divider(height: 18),
                      _MyWorkDaily(this)._dailyInfoRow(
                        context,
                        Icons.store_outlined,
                        'Branch',
                        branchName,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Order Requests',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...requests.map((r) {
                final lines = ((r['lines'] as List?) ?? const [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
                final issuedLines =
                    ((r['issued_lines'] as List?) ?? const [])
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _MyWorkDaily(this)._requestTypeText('${r['type']}'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Text(
                                BusinessFormat.status(r['status']),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          for (var i = 0; i < lines.length; i++) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      BusinessFormat.displayName(
                                        '${lines[i]['product_name'] ?? 'Product'}',
                                      ),
                                      style:
                                          Theme.of(context).textTheme.bodyLarge,
                                    ),
                                  ),
                                  Text(
                                    BusinessFormat.quantity(
                                      num.tryParse(
                                            '${lines[i]['quantity'] ?? 0}',
                                          ) ??
                                          0,
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                            if (i != lines.length - 1) const Divider(height: 1),
                          ],
                          if (issuedLines.isNotEmpty) ...[
                            const Divider(height: 24),
                            Row(
                              children: [
                                const Icon(
                                  Icons.inventory_2_outlined,
                                  size: 18,
                                  color: ExcelBrand.primaryDark,
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  'Issued Stock',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            for (var i = 0; i < issuedLines.length; i++) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 7),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            BusinessFormat.displayName(
                                              '${issuedLines[i]['product_name'] ?? 'Product'}',
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          if ('${issuedLines[i]['batch_no'] ?? ''}'
                                              .trim()
                                              .isNotEmpty)
                                            Text(
                                              'Batch ${issuedLines[i]['batch_no']}',
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
                                    const SizedBox(width: 12),
                                    Text(
                                      '${BusinessFormat.quantity(issuedLines[i]['quantity'])} PCS',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: ExcelBrand.primaryDark,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              if (i != issuedLines.length - 1)
                                const Divider(height: 1),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
              if (evening != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Evening Closing',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          BusinessFormat.status(evening['status']),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        ...(((evening['lines'] as List?) ?? const []).map((e) {
                          final l = Map<String, dynamic>.from(e as Map);
                          final returned = num.tryParse(
                                '${l['return_quantity'] ?? l['return_qty'] ?? 0}',
                              ) ??
                              0;
                          final wholesaleSold =
                              num.tryParse('${l['wholesale_quantity'] ?? 0}') ??
                                  0;
                          final issued =
                              num.tryParse('${l['issued_quantity'] ?? 0}') ?? 0;
                          final soldRaw = l['sold_quantity'] ?? l['sold_qty'];
                          final sold = soldRaw == null
                              ? DailyOrderMath.retailSold(
                                  issued,
                                  returned,
                                  wholesaleSold,
                                )
                              : (num.tryParse('$soldRaw') ??
                                  DailyOrderMath.retailSold(
                                    issued,
                                    returned,
                                    wholesaleSold,
                                  ));
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    BusinessFormat.displayName(
                                      '${l['product_name'] ?? 'Product'}',
                                    ),
                                  ),
                                ),
                                Text(
                                  'Retail ${BusinessFormat.quantity(sold)} · Wholesale ${BusinessFormat.quantity(wholesaleSold)} · Return ${BusinessFormat.quantity(returned)}',
                                ),
                              ],
                            ),
                          );
                        })),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) _setFeatureState(() => message = UiError.message(e));
    }
  }

  Widget _dailyInfoRowImpl(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) =>
      Row(
        children: [
          Icon(icon, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      );

  String _requestTypeTextImpl(String type) => switch (type) {
        'initial' => 'Morning Order',
        'additional' => 'Additional Order',
        'replacement' => 'Replacement Order',
        _ => BusinessFormat.displayName(type.replaceAll('_', ' ')),
      };

}
