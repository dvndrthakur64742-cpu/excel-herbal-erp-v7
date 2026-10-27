import 'package:flutter/material.dart';

import '../theme/excel_brand.dart';

/// A compact Command Center header for the ORIGINAL, authorised ERP records.
/// It intentionally shows scope, not calculated totals or approval claims.
class V8ModuleBanner extends StatelessWidget {
  const V8ModuleBanner({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    required this.context,
  });

  final String eyebrow;
  final String title;
  final String description;
  final IconData icon;
  final List<String> context;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scope = this.context.where((item) => item.trim().isNotEmpty).toList();
    return Container(
      key: const ValueKey('v8-module-banner'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: ExcelBrand.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ExcelBrand.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x091D2340),
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ExcelBrand.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: ExcelBrand.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ExcelBrand.primaryDark,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleLarge?.copyWith(
                    color: ExcelBrand.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: ExcelBrand.muted),
                ),
              ],
            ),
          ),
        ]),
        if (scope.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [for (final item in scope) _ScopePill(value: item)],
          ),
        ],
      ]),
    );
  }
}

class _ScopePill extends StatelessWidget {
  const _ScopePill({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: ExcelBrand.canvas,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: ExcelBrand.border),
        ),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: ExcelBrand.sidebarText,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}
