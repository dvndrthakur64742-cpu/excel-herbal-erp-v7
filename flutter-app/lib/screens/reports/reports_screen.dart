import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../core/providers.dart';
import '../../state/app_state.dart';
import '../../theme/excel_brand.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/records_list.dart';
import '../../widgets/module_workspace.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String type = 'sales';

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final config = _config(type);
    final needsBranch = type != 'trial';

    final query = <String, dynamic>{
      if (app.currentBranchId != null) 'branch_id': app.currentBranchId,
      if (type != 'stock' && type != 'trial') 'from': app.businessMonthStart,
      if (type != 'stock') 'to': app.businessDate,
    };
    final scopeLabel = type == 'stock'
        ? 'Live stock'
        : type == 'trial'
            ? BusinessFormat.date(app.businessDate)
            : '${BusinessFormat.date(app.businessMonthStart)} – ${BusinessFormat.date(app.businessDate)}';
    final reportView = needsBranch && app.currentBranchId == null
        ? const _BranchRequired()
        : AsyncPanel(
            key: ValueKey(
              '$type-${app.currentBranchId}-${app.businessDate}',
            ),
            future: api.get(config.path, query: query),
            emptyMessage: config.emptyMessage,
            builder: (context, data) => RecordsList(
              recordType: config.recordType,
              rows: ((data as List?) ?? const [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList(),
            ),
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: ModuleWorkspaceHeader(
                title: 'Reports Centre',
                subtitle:
                    'Operational, inventory and financial reporting workspace.',
                icon: Icons.analytics_outlined,
                contextLabel: scopeLabel,
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: BranchSelector(),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final content = Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 7),
                        child: ModuleSectionHeader(
                          title: config.title,
                          subtitle: config.subtitle,
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              scopeLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: reportView),
                    ],
                  );
                  if (constraints.maxWidth >= 900) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            child: SizedBox(
                              width: 220,
                              child: _reportRail(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: content),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: [
                      const SizedBox(height: 8),
                      _mobileReportSelector(),
                      Expanded(child: content),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileReportSelector() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          menuMaxHeight: 360,
          initialValue: type,
          decoration: const InputDecoration(
            labelText: 'Report view',
            prefixIcon: Icon(Icons.analytics_outlined, size: 20),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'sales', child: Text('Sales Summary')),
            DropdownMenuItem(
                value: 'purchase', child: Text('Purchase Summary')),
            DropdownMenuItem(value: 'stock', child: Text('Stock Position')),
            DropdownMenuItem(value: 'finance', child: Text('Finance Movement')),
            DropdownMenuItem(value: 'trial', child: Text('Trial Balance')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => type = value);
          },
        ),
      );

  Widget _reportRail() {
    const values = ['sales', 'purchase', 'stock', 'finance', 'trial'];
    return NavigationRail(
      selectedIndex: values.indexOf(type),
      extended: true,
      minExtendedWidth: 220,
      backgroundColor: Colors.transparent,
      onDestinationSelected: (index) => setState(() => type = values[index]),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.point_of_sale_outlined),
          label: Text('Sales'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.local_shipping_outlined),
          label: Text('Purchase'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.inventory_2_outlined),
          label: Text('Stock'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.account_balance_outlined),
          label: Text('Finance'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.balance_outlined),
          label: Text('Trial Balance'),
        ),
      ],
    );
  }

  _ReportConfig _config(String value) => switch (value) {
        'purchase' => const _ReportConfig(
            title: 'Purchase Summary',
            path: ApiPaths.reportsPurchase,
            recordType: 'purchase',
            subtitle: 'Supplier billing, payments and outstanding summary.',
            emptyMessage: 'No purchase activity for the selected period.',
          ),
        'stock' => const _ReportConfig(
            title: 'Stock Position',
            path: ApiPaths.reportsStock,
            recordType: 'stock',
            subtitle: 'Current stock position for the selected branch.',
            emptyMessage: 'No stock records for the selected branch.',
          ),
        'finance' => const _ReportConfig(
            title: 'Finance Movement',
            path: ApiPaths.reportsFinance,
            recordType: 'finance',
            subtitle: 'Posted journals and accounting movement summary.',
            emptyMessage: 'No finance activity for the selected period.',
          ),
        'trial' => const _ReportConfig(
            title: 'Trial Balance',
            path: ApiPaths.trialBalance,
            recordType: 'trial_balance',
            subtitle:
                'Ledger debit and credit balances as of the business date.',
            emptyMessage: 'No Trial Balance data is available.',
          ),
        _ => const _ReportConfig(
            title: 'Sales Summary',
            path: ApiPaths.reportsSales,
            recordType: 'sales',
            subtitle:
                'Current-month sales, collections and outstanding summary.',
            emptyMessage: 'No sales activity for the selected period.',
          ),
      };
}

class _ReportConfig {
  const _ReportConfig({
    required this.title,
    required this.path,
    required this.recordType,
    required this.subtitle,
    required this.emptyMessage,
  });

  final String title;
  final String path;
  final String recordType;
  final String subtitle;
  final String emptyMessage;
}

class _BranchRequired extends StatelessWidget {
  const _BranchRequired();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: ExcelBrand.primarySoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.store_outlined,
                  color: ExcelBrand.primaryDark,
                  size: 30,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Select an authorised branch',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 5),
              Text(
                'Reports are scoped to the selected authorised branch.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}
