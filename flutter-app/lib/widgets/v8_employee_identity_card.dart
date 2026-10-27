import 'package:flutter/material.dart';

import '../theme/excel_brand.dart';

/// Existing Employee 360 identity projection; no ledger/cash claims.
class V8EmployeeIdentityCard extends StatelessWidget {
  const V8EmployeeIdentityCard({super.key, required this.employee});

  final Map<String, dynamic> employee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final name = '${employee['full_name'] ?? ''}'.trim();
    final code = '${employee['employee_code'] ?? ''}'.trim();
    final designation = '${employee['designation_code'] ?? ''}'.trim();
    final status = '${employee['status'] ?? ''}'.trim();
    return Container(
      key: const ValueKey('v8-employee-identity'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 17),
      decoration: BoxDecoration(
        color: ExcelBrand.surface,
        border: Border.all(color: ExcelBrand.border),
        borderRadius: BorderRadius.circular(18)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 48, height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ExcelBrand.primarySoft,
            borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.badge_outlined,
              size: 27, color: ExcelBrand.primaryDark),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('EMPLOYEE PROFILE / V8',
              style: TextStyle(color: ExcelBrand.primaryDark,
                  fontSize: 10, letterSpacing: 1.2,
                  fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(name.isNotEmpty ? name : 'Employee',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 9),
            Wrap(spacing: 7, runSpacing: 7, children: [
              if (code.isNotEmpty) _IdentityToken('Code $code'),
              if (designation.isNotEmpty) _IdentityToken('Role $designation'),
              if (status.isNotEmpty) _IdentityToken('Status $status'),
            ]),
          ],
        )),
      ]),
    );
  }
}

class _IdentityToken extends StatelessWidget {
  const _IdentityToken(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: ExcelBrand.canvas,
      border: Border.all(color: ExcelBrand.border)),
    child: Text(text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: ExcelBrand.ink, fontWeight: FontWeight.w700)),
  );
}
