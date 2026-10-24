import 'package:flutter/material.dart';
import '../theme/excel_brand.dart';

/// Compact global context: module screens retain their own functional titles.
class V8WorkspaceContextBar extends StatelessWidget {
  const V8WorkspaceContextBar({
    super.key, required this.branch, required this.activeRoute, this.onOpenActions,
  });
  final String branch;
  final String activeRoute;
  final VoidCallback? onOpenActions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey('v8-workspace-context-bar'),
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(color: ExcelBrand.surface,
          border: Border(bottom: BorderSide(color: ExcelBrand.border))),
      child: Row(children: [
        const Icon(Icons.grid_view_rounded,
            color: ExcelBrand.primaryDark, size: 19),
        const SizedBox(width: 10),
        Expanded(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('EXCEL HERBAL  /  V8',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(
                  letterSpacing: 1.3, fontWeight: FontWeight.w800,
                  color: ExcelBrand.muted)),
            const SizedBox(height: 2),
            Text(activeRoute, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: text.titleSmall?.copyWith(
                  color: ExcelBrand.ink, fontWeight: FontWeight.w800)),
          ],
        )),
        if (branch.trim().isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 175),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: ExcelBrand.canvas,
                border: Border.all(color: ExcelBrand.border)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.location_on_outlined,
                    color: ExcelBrand.primaryDark, size: 16),
                const SizedBox(width: 5),
                Flexible(child: Text(branch, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(
                        color: ExcelBrand.ink, fontWeight: FontWeight.w700))),
              ]),
            ),
          ),
        if (onOpenActions != null) ...[
          const SizedBox(width: 9),
          FilledButton.tonalIcon(
            key: const ValueKey('v8-create-action'),
            onPressed: onOpenActions,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create / Record'),
          ),
        ],
      ]),
    );
  }
}

class V8SidebarBrand extends StatelessWidget {
  const V8SidebarBrand({super.key});
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('v8-desktop-sidebar-brand'),
    padding: const EdgeInsets.fromLTRB(17, 20, 10, 20),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: ExcelBrand.navRaised))),
    child: Row(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [ExcelBrand.accent, ExcelBrand.primary]),
          borderRadius: BorderRadius.circular(13)),
        child: const Icon(Icons.spa_rounded, color: ExcelBrand.navDark),
      ),
      const SizedBox(width: 11),
      const Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EXCEL HERBAL', maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900,
                fontSize: 14)),
          SizedBox(height: 4),
          Text('ERP V8 • WORKSPACE', maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: ExcelBrand.navMuted,
                fontSize: 10, fontWeight: FontWeight.w800,
                letterSpacing: .6)),
        ],
      )),
    ]),
  );
}

class V8MobileTitle extends StatelessWidget {
  const V8MobileTitle({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      key: const ValueKey('v8-mobile-brand'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
          color: ExcelBrand.primarySoft,
          borderRadius: BorderRadius.circular(7)),
      child: const Text('V8', style: TextStyle(
          color: ExcelBrand.primaryDark, fontWeight: FontWeight.w900,
          fontSize: 12)),
    ),
    const SizedBox(width: 9),
    Flexible(child: Text(title, maxLines: 1,
        overflow: TextOverflow.ellipsis)),
  ]);
}
