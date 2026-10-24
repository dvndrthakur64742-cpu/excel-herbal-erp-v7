import 'package:flutter/material.dart';
import '../theme/excel_brand.dart';

/// Shared V8 module identity over ORIGINAL authorised ERP records.
/// No derived balances or parallel business state. Not an action form.
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
  Widget build(BuildContext viewContext) {
    final type = Theme.of(viewContext).textTheme;
    return Container(
      key: const ValueKey('v8-module-banner'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [ExcelBrand.navDark, Color(0xFF184957)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 21, color: ExcelBrand.accent),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eyebrow.toUpperCase(),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ExcelBrand.accent, fontSize: 10,
                  fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(title,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: type.titleMedium?.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w900)),
            ],
          )),
        ]),
        const SizedBox(height: 7),
        Text(description, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: type.bodySmall?.copyWith(color: const Color(0xFFE2EBF0))),
        if (context.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 7, runSpacing: 7, children: [
            for (final item in context)
              if (item.trim().isNotEmpty) _ScopePill(value: item),
          ]),
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
    constraints: const BoxConstraints(maxWidth: 250),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: Colors.white.withValues(alpha: .13),
      border: Border.all(color: Colors.white.withValues(alpha: .15)),
    ),
    child: Text(value,
      maxLines: 1, overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white,
        fontSize: 11, fontWeight: FontWeight.w700)),
  );
}
