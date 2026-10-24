import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/excel_brand.dart';

/// V8 welcome surface uses identity and authorised dates only; never
/// invents sales, prices, points or management KPI data.
class V8HomeHero extends StatelessWidget {
  const V8HomeHero({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'morning'
        : hour < 17 ? 'afternoon' : 'evening';
    return Container(
      key: const ValueKey('v8-home-hero'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [ExcelBrand.navDark, Color(0xFF174B51), Color(0xFF19624F)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        boxShadow: const [BoxShadow(
            color: Color(0x1812283E), blurRadius: 20, offset: Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.bolt_rounded, color: ExcelBrand.accent, size: 16),
          SizedBox(width: 6),
          Text('YOUR WORKSPACE  /  ERP V8',
            style: TextStyle(color: ExcelBrand.accent,
                fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.1)),
        ]),
        const SizedBox(height: 18),
        Text('Good $greeting,', style: text.titleMedium?.copyWith(
            color: const Color(0xFFBDE4D9), fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(app.employeeName, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: text.headlineMedium?.copyWith(
            color: Colors.white, fontWeight: FontWeight.w900,
            height: 1.1, letterSpacing: -.6)),
        const SizedBox(height: 12),
        Text('Your authorised work and records, in one workspace.',
          style: text.bodyMedium?.copyWith(color: const Color(0xFFE0F2ED))),
        const SizedBox(height: 18),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _V8HeroBadge(icon: Icons.badge_outlined,
              label: app.primaryDesignationLabel),
          _V8HeroBadge(icon: Icons.calendar_today_outlined,
              label: app.businessDate),
        ]),
      ]),
    );
  }
}

class _V8HeroBadge extends StatelessWidget {
  const _V8HeroBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: .18))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: ExcelBrand.accent, size: 15),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(
          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
    ]),
  );
}
