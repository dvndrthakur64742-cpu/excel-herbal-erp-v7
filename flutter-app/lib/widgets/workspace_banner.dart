import 'package:flutter/material.dart';
import '../theme/excel_brand.dart';

/// Compact shared workspace header; content remains above the fold.
class WorkspaceBanner extends StatelessWidget {
  const WorkspaceBanner({
    super.key, required this.eyebrow, required this.title,
    required this.subtitle, required this.icon, this.footer,
  });
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: ExcelBrand.primarySoft,
              borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: ExcelBrand.primaryDark, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(eyebrow, style: theme.textTheme.labelMedium?.copyWith(
              color: ExcelBrand.primaryDark, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: ExcelBrand.muted)),
          ])),
        ]),
        if (footer != null) ...[const SizedBox(height: 10), footer!],
      ]),
    );
  }
}
