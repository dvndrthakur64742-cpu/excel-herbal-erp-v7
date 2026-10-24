import 'package:flutter/material.dart';

import '../theme/excel_brand.dart';
import 'v8_employee_identity_card.dart';

/// Employee 360 read-only source projection. Never derives a balance from
/// paginated rows, and does not infer Cash/UPI receipt evidence from sales.
class V8EmployeeOverview extends StatelessWidget {
  const V8EmployeeOverview({
    super.key,
    required this.employee,
    required this.months,
    required this.stock,
  });

  final Map<String, dynamic> employee;
  final List<Map<String, dynamic>> months;
  final List<Map<String, dynamic>> stock;

  @override
  Widget build(BuildContext context) {
    final styles = Theme.of(context).textTheme;
    return ListView(
      key: const ValueKey('v8-employee-overview'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        V8EmployeeIdentityCard(employee: employee),
        const SizedBox(height: 17),
        _SectionHeading(
          icon: Icons.insights_rounded,
          title: 'Monthly Sales & Points',
          subtitle: 'Posted monthly activity · sales INR, points and attendance are separate measures',
        ),
        const SizedBox(height: 10),
        if (months.isEmpty)
          const _EmptyState(
            text: 'No posted monthly activity in this period.')
        else
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 1000 ? 3 : width >= 580 ? 2 : 1;
            const gap = 10.0;
            final cellWidth = (width - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final record in months)
                  SizedBox(
                    width: cellWidth,
                    child: _MonthActivityCard(record: record),
                  ),
              ],
            );
          }),
        const SizedBox(height: 21),
        _SectionHeading(
          icon: Icons.inventory_2_outlined,
          title: 'Employee-held stock',
          subtitle: 'Recorded positive stock custody · not a physical stock count',
        ),
        const SizedBox(height: 10),
        if (stock.isEmpty)
          const _EmptyState(text: 'No positive employee-custodied stock.')
        else
          for (final record in stock.take(15))
            Card(
              key: ValueKey('v8-stock-item-${record['product_id']}-${record['batch_key']}'),
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.inventory_2_outlined,
                      size: 20, color: ExcelBrand.primaryDark),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${record['product_name'] ?? record['sku'] ?? 'Product'}',
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: styles.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(
                        'Branch ${record['branch_id'] ?? '-'} · Batch ${record['batch_key'] ?? 0}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: styles.bodySmall),
                    ],
                  )),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 100),
                    child: Text(
                      '${record['quantity'] ?? 0} PCS',
                      maxLines: 2,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: styles.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ExcelBrand.primaryDark),
                    ),
                  ),
                ]),
              ),
            ),
        if (stock.length > 15)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text('Showing 15 of ${stock.length} recorded stock balances.',
              style: styles.bodySmall),
          ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ExcelBrand.canvas,
            border: Border.all(color: ExcelBrand.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline_rounded,
                color: ExcelBrand.primaryDark, size: 20),
            const SizedBox(width: 9),
            const Expanded(child: Text(
              'Cash remittance is not independently verified here. '
              'Sales and Cash/UPI settlements do not prove that field cash was deposited '
              'with the branch. No employee outstanding balance is inferred.',
            )),
          ]),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon, required this.title, required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: ExcelBrand.primaryDark, size: 21),
    const SizedBox(width: 9),
    Expanded(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(subtitle,
          style: Theme.of(context).textTheme.bodySmall),
      ],
    )),
  ]);
}

class _MonthActivityCard extends StatelessWidget {
  const _MonthActivityCard({required this.record});
  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    final styles = Theme.of(context).textTheme;
    return Card(
      key: ValueKey('v8-month-${record['month']}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${record['month'] ?? ''}', maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: ExcelBrand.primaryDark)),
            const SizedBox(height: 10),
            Wrap(spacing: 14, runSpacing: 9, children: [
              _Measure(label: 'Posted sales · INR',
                  value: '${record['sales_amount'] ?? '0.00'}'),
              _Measure(label: 'Performance points',
                  value: '${record['points'] ?? '0.00'}'),
              _Measure(label: 'Days present',
                  value: '${record['days_present'] ?? 0}'),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Measure extends StatelessWidget {
  const _Measure({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 80, maxWidth: 185),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: 3),
      Text(value, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900)),
    ]),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: ExcelBrand.surface,
      border: Border.all(color: ExcelBrand.border),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Text(text),
  );
}
