import 'package:flutter/material.dart';
import '../theme/excel_brand.dart';

/// Visual identity only. Displays real selected branch and server business
/// date; no fabricated inventory figures or extra write actions.
class V8InventoryBanner extends StatelessWidget {
  const V8InventoryBanner({
    super.key, required this.branch, required this.businessDate,
  });

  final String branch;
  final String businessDate;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey('v8-inventory-banner'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(17, 15, 17, 17),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [ExcelBrand.navDark, Color(0xFF184D57)],
          begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('STOCK OPERATIONS / V8',
          style: TextStyle(color: ExcelBrand.accent, fontSize: 11,
            fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        const SizedBox(height: 5),
        Text('Inventory control',
          style: text.titleLarge?.copyWith(
            color: Colors.white, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        const Text('Stock · Transfers · Adjustments · Quarantine',
          style: TextStyle(color: Color(0xFFE0EDF3), fontSize: 12)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _V8ScopePill(icon: Icons.store_outlined, value: branch),
          _V8ScopePill(icon: Icons.event_outlined, value: businessDate),
        ]),
      ]),
    );
  }
}

class _V8ScopePill extends StatelessWidget {
  const _V8ScopePill({required this.icon, required this.value});
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(999)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: ExcelBrand.accent, size: 15),
      const SizedBox(width: 5),
      Text(value, style: const TextStyle(color: Colors.white,
        fontSize: 12, fontWeight: FontWeight.w700)),
    ]),
  );
}
