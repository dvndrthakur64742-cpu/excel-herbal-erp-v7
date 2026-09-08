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

    return Scaffold(
      appBar: AppBar(title: const Text('Reports Centre')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: BranchSelector(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    config.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: ExcelBrand.primarySoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    type == 'stock'
                        ? 'Live stock'
                        : type == 'trial'
                            ? BusinessFormat.date(app.businessDate)
                            : '${BusinessFormat.date(app.businessMonthStart)} – ${BusinessFormat.date(app.businessDate)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: ExcelBrand.primaryDark,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'sales',
                  icon: Icon(Icons.point_of_sale_outlined),
                  label: Text('Sales'),
                ),
                ButtonSegment(
                  value: 'purchase',
                  icon: Icon(Icons.local_shipping_outlined),
                  label: Text('Purchase'),
                ),
                ButtonSegment(
                  value: 'stock',
                  icon: Icon(Icons.inventory_2_outlined),
                  label: Text('Stock'),
                ),
                ButtonSegment(
                  value: 'finance',
                  icon: Icon(Icons.account_balance_outlined),
                  label: Text('Finance'),
                ),
                ButtonSegment(
                  value: 'trial',
                  icon: Icon(Icons.balance_outlined),
                  label: Text('Trial Balance'),
                ),
              ],
              selected: {type},
              onSelectionChanged: (value) =>
                  setState(() => type = value.first),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: needsBranch && app.currentBranchId == null
                ? const _BranchRequired()
                : AsyncPanel(
                    key: ValueKey(
                        '$type-${app.currentBranchId}-${app.businessDate}'),
                    future: api.get(config.path, query: query),
                    emptyMessage: config.emptyMessage,
                    builder: (context, data) => RecordsList(
                      recordType: config.recordType,
                      rows: ((data as List?) ?? const [])
                          .map((e) => Map<String, dynamic>.from(e as Map))
                          .toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  _ReportConfig _config(String value) => switch (value) {
        'purchase' => const _ReportConfig(
            path: ApiPaths.reportsPurchase,
            recordType: 'purchase',
            subtitle: 'Supplier bills, paid amount aur outstanding ka summary.',
            emptyMessage: 'Is period me koi purchase record nahi hai.'),
        'stock' => const _ReportConfig(
            path: ApiPaths.reportsStock,
            recordType: 'stock',
            subtitle: 'Selected branch ka current available stock.',
            emptyMessage: 'Selected branch me stock record nahi mila.'),
        'finance' => const _ReportConfig(
            path: ApiPaths.reportsFinance,
            recordType: 'finance',
            subtitle: 'Posted journals aur accounting movement.',
            emptyMessage: 'Is period me finance record nahi hai.'),
        'trial' => const _ReportConfig(
            path: ApiPaths.trialBalance,
            recordType: 'trial_balance',
            subtitle: 'Business date tak ledger debit-credit balance.',
            emptyMessage: 'Trial Balance empty hai.'),
        _ => const _ReportConfig(
            path: ApiPaths.reportsSales,
            recordType: 'sales',
            subtitle: 'Sales, collection aur outstanding ka current month view.',
            emptyMessage: 'Is period me koi sales record nahi hai.'),
      };
}

class _ReportConfig {
  const _ReportConfig({
    required this.path,
    required this.recordType,
    required this.subtitle,
    required this.emptyMessage,
  });

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
                'Authorised Branch select karein',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 5),
              Text(
                'Report sirf selected authorised branch ka data dikhayega.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}
