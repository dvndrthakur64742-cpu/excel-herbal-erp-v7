import 'package:flutter/material.dart';
import '../theme/excel_brand.dart';

/// Single, quiet desktop context strip. No invented business data.
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
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        color: ExcelBrand.surface,
        border: Border(bottom: BorderSide(color: ExcelBrand.border)),
      ),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: ExcelBrand.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.space_dashboard_outlined,
              color: ExcelBrand.primaryDark, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('WORKSPACE  /  ' + activeRoute.toUpperCase(),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(
                color: ExcelBrand.sidebarMuted,
                fontWeight: FontWeight.w800, letterSpacing: .7,
              )),
            const SizedBox(height: 2),
            Text('Excel Herbal Command Center',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: text.titleMedium?.copyWith(
                color: ExcelBrand.ink, fontWeight: FontWeight.w800,
                letterSpacing: -.2,
              )),
          ],
        )),
        if (branch.trim().isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: ExcelBrand.canvas,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: ExcelBrand.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.location_on_outlined,
                    color: ExcelBrand.primary, size: 16),
                const SizedBox(width: 5),
                Flexible(child: Text(branch,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(
                    color: ExcelBrand.sidebarText, fontWeight: FontWeight.w700,
                  ))),
              ]),
            ),
          ),
        if (onOpenActions != null) ...[
          const SizedBox(width: 10),
          FilledButton.icon(
            key: const ValueKey('v8-create-action'),
            onPressed: onOpenActions,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('New action'),
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
    padding: const EdgeInsets.fromLTRB(16, 18, 10, 18),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: ExcelBrand.border)),
    ),
    child: Row(children: [
      Container(
        width: 43, height: 43,
        decoration: BoxDecoration(
          color: ExcelBrand.primarySoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.eco_outlined,
            color: ExcelBrand.primaryDark, size: 24),
      ),
      const SizedBox(width: 11),
      const Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EXCEL HERBAL', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: ExcelBrand.ink,
              fontWeight: FontWeight.w900, fontSize: 14)),
          SizedBox(height: 4),
          Text('COMMAND CENTER  /  V8',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: ExcelBrand.sidebarMuted,
              fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: .6)),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: ExcelBrand.primarySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('V8', style: TextStyle(
        color: ExcelBrand.primaryDark, fontWeight: FontWeight.w900,
        fontSize: 12,
      )),
    ),
    const SizedBox(width: 9),
    Flexible(child: Text(title, maxLines: 1,
        overflow: TextOverflow.ellipsis)),
  ]);
}
