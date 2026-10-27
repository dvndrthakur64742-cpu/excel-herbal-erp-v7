import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/excel_brand.dart';

/// Fresh Command Center hero: only authorised identity/date, no fake KPIs.
class V8HomeHero extends StatelessWidget {
  const V8HomeHero({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'morning' : hour < 17 ? 'afternoon' : 'evening';
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720;
      return Container(
        key: const ValueKey('v8-home-hero'),
        width: double.infinity,
        padding: EdgeInsets.all(wide ? 28 : 20),
        decoration: BoxDecoration(
          color: ExcelBrand.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ExcelBrand.border),
          boxShadow: const [
            BoxShadow(color: Color(0x091D2340), blurRadius: 22,
                offset: Offset(0, 6)),
          ],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8,
                  decoration: const BoxDecoration(
                    color: ExcelBrand.primary, shape: BoxShape.circle,
                  )),
                const SizedBox(width: 9),
                const Flexible(child: Text(
                  'YOUR DAY  /  EXCEL HERBAL',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ExcelBrand.primaryDark,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1, fontSize: 10,
                  ),
                )),
              ]),
              const SizedBox(height: 18),
              Text('Good $greeting,',
                style: text.titleMedium?.copyWith(
                  color: ExcelBrand.muted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(app.employeeName,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: text.headlineMedium?.copyWith(
                  color: ExcelBrand.ink, fontWeight: FontWeight.w900,
                  height: 1.1, letterSpacing: -.6)),
              const SizedBox(height: 11),
              Text(
                'Your daily work, approvals and records — all in one place.',
                style: text.bodyMedium?.copyWith(
                  color: ExcelBrand.muted, height: 1.4)),
              const SizedBox(height: 18),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _HeroTag(icon: Icons.badge_outlined,
                  label: app.primaryDesignationLabel),
                _HeroTag(icon: Icons.event_outlined,
                  label: app.businessDate),
              ]),
            ],
          )),
          if (wide) ...[
            const SizedBox(width: 22),
            Container(
              key: const ValueKey('v8-home-artwork'),
              width: 205, height: 165,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: ExcelBrand.primarySoft,
                borderRadius: BorderRadius.circular(18)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.blur_on_rounded,
                      color: ExcelBrand.primary, size: 26),
                    Spacer(),
                    Icon(Icons.arrow_outward_rounded,
                      color: ExcelBrand.primaryDark, size: 18),
                  ]),
                  const Spacer(),
                  Container(
                    height: 8, width: 112,
                    decoration: BoxDecoration(
                      color: ExcelBrand.primarySoftStrong,
                      borderRadius: BorderRadius.circular(5)),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 8, width: 152,
                    decoration: BoxDecoration(
                      color: ExcelBrand.primarySoftStrong,
                      borderRadius: BorderRadius.circular(5)),
                  ),
                  const SizedBox(height: 12),
                  const Text('ONE WORKSPACE',
                    style: TextStyle(fontSize: 10, letterSpacing: 1,
                      fontWeight: FontWeight.w900,
                      color: ExcelBrand.primaryDark)),
                ],
              ),
            ),
          ],
        ]),
      );
    });
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: ExcelBrand.canvas,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: ExcelBrand.border),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: ExcelBrand.primary),
      const SizedBox(width: 7),
      Text(label, style: const TextStyle(
        color: ExcelBrand.sidebarText, fontSize: 12,
        fontWeight: FontWeight.w700)),
    ]),
  );
}
