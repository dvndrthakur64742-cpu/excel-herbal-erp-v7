from pathlib import Path
import re


def read(path: str) -> tuple[Path, str]:
    p = Path(path)
    return p, p.read_text()


def replace_once(s: str, old: str, new: str, label: str) -> str:
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return s.replace(old, new, 1)


def replace_regex_once(s: str, pattern: str, new: str, label: str) -> str:
    out, count = re.subn(pattern, new, s, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 regex match, found {count}")
    return out


# 1) Global enterprise density / less consumer-card styling.
p, s = read('flutter-app/lib/theme/excel_brand.dart')
repls = [
    ('visualDensity: VisualDensity.standard,', 'visualDensity: VisualDensity.compact,', 'density'),
    ('toolbarHeight: 64,', 'toolbarHeight: 58,', 'toolbar'),
    ('fontSize: 22,', 'fontSize: 20,', 'appbar title size'),
    ('borderRadius: BorderRadius.circular(20),\n          side: const BorderSide(color: border),', 'borderRadius: BorderRadius.circular(14),\n          side: const BorderSide(color: border),', 'card radius'),
    ('horizontal: 16,\n          vertical: 15,', 'horizontal: 14,\n          vertical: 12,', 'input padding'),
    ('minTileHeight: 54,', 'minTileHeight: 48,', 'tile height'),
    ('contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),', 'contentPadding: const EdgeInsets.symmetric(horizontal: 12),', 'tile padding'),
    ('shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),\n        iconColor: muted,', 'shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),\n        iconColor: muted,', 'tile radius'),
    ('height: 72,', 'height: 66,', 'nav height'),
    ('size: 26,', 'size: 24,', 'nav icon'),
    ('minimumSize: const Size(48, 50),\n          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),', 'minimumSize: const Size(44, 44),\n          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),', 'filled button density'),
    ('minimumSize: const Size(48, 50),\n          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),', 'minimumSize: const Size(44, 44),\n          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),', 'outlined button density'),
    ('shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),', 'shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),', 'dialog radius'),
    ('shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),\n      ),\n      progressIndicatorTheme:', 'shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),\n      ),\n      progressIndicatorTheme:', 'snackbar radius'),
]
for old, new, label in repls:
    s = replace_once(s, old, new, label)
# Input and button radius occurrences are intentionally narrowed to their theme sections.
s = s.replace('BorderRadius.circular(15)', 'BorderRadius.circular(12)')
s = s.replace('BorderRadius.circular(14)', 'BorderRadius.circular(11)', 2)
p.write_text(s)

# 2) Reports: remove duplicate live Stock report; Inventory is canonical stock workspace.
p, s = read('flutter-app/lib/screens/reports/reports_screen.dart')
s = replace_once(
    s,
    "      if (type != 'stock' && type != 'trial') 'from': app.businessMonthStart,\n      if (type != 'stock') 'to': app.businessDate,",
    "      if (type != 'trial') 'from': app.businessMonthStart,\n      'to': app.businessDate,",
    'reports query',
)
s = replace_regex_once(
    s,
    r"                    type == 'stock'\n                        \? 'Live stock'\n                        : type == 'trial'\n                        \? BusinessFormat\.date\(app\.businessDate\)\n                        : '\$\{BusinessFormat\.date\(app\.businessMonthStart\)\} – \$\{BusinessFormat\.date\(app\.businessDate\)\}',",
    "                    type == 'trial'\n                        ? BusinessFormat.date(app.businessDate)\n                        : '${BusinessFormat.date(app.businessMonthStart)} – ${BusinessFormat.date(app.businessDate)}',",
    'reports period pill',
)
s = replace_regex_once(
    s,
    r"\n                ButtonSegment\(\n                  value: 'stock',\n                  icon: Icon\(Icons\.inventory_2_outlined\),\n                  label: Text\('Stock'\),\n                \),",
    '',
    'remove stock segment',
)
s = replace_regex_once(
    s,
    r"\n    'stock' => const _ReportConfig\(\n      path: ApiPaths\.reportsStock,\n      recordType: 'stock',\n      subtitle: 'Selected branch ka current available stock\.',\n      emptyMessage: 'Selected branch me stock record nahi mila\.',\n    \),",
    '',
    'remove stock config',
)
s = s.replace('Supplier bills, paid amount aur outstanding ka summary.', 'Supplier bills, payments and outstanding balances.')
s = s.replace('Is period me koi purchase record nahi hai.', 'No purchase records for the selected period.')
s = s.replace('Posted journals aur accounting movement.', 'Posted journals and accounting movements.')
s = s.replace('Is period me finance record nahi hai.', 'No finance records for the selected period.')
s = s.replace('Business date tak ledger debit-credit balance.', 'Ledger debit and credit balance as of the business date.')
s = s.replace('Trial Balance empty hai.', 'No Trial Balance entries available.')
s = s.replace('Sales, collection aur outstanding ka current month view.', 'Sales, collections and outstanding balances for the current period.')
s = s.replace('Is period me koi sales record nahi hai.', 'No sales records for the selected period.')
p.write_text(s)

# 3) Quick Actions: compact action command palette instead of oversized cards.
p, s = read('flutter-app/lib/screens/home/actions_screen.dart')
s = replace_once(
    s,
    "          'Sirf aapke role aur permission ke authorised actions yahan dikhte hain.',",
    "          'Role-based shortcuts for the actions you can perform now.',",
    'actions subtitle',
)
s = replace_once(s, 'padding: const EdgeInsets.all(16),', 'padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),', 'actions padding')
s = replace_once(s, 'maxCrossAxisExtent: 240,\n              mainAxisExtent: 116,\n              crossAxisSpacing: 10,\n              mainAxisSpacing: 10,', 'maxCrossAxisExtent: 320,\n              mainAxisExtent: 72,\n              crossAxisSpacing: 8,\n              mainAxisSpacing: 8,', 'actions grid density')
old = """              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: action.run,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(
                            color: ExcelBrand.primarySoft,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            action.icon,
                            size: 20,
                            color: ExcelBrand.primaryDark,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          action.label,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );"""
new = """              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: action.run,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: ExcelBrand.primarySoft,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            action.icon,
                            size: 18,
                            color: ExcelBrand.primaryDark,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            action.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: ExcelBrand.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              );"""
s = replace_once(s, old, new, 'actions card')
p.write_text(s)

# 4) Generic records: compact enterprise rows across Inventory/Reports/Sales/Purchase/etc.
p, s = read('flutter-app/lib/widgets/records_list.dart')
s = replace_once(
    s,
    "  Widget _mobileCards(BuildContext context) => ListView.separated(\n    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),\n    itemCount: widget.rows.length,\n    separatorBuilder: (_, __) => const SizedBox(height: 10),",
    "  Widget _mobileCards(BuildContext context) => ListView.separated(\n    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),\n    itemCount: widget.rows.length,\n    separatorBuilder: (_, __) => const SizedBox(height: 6),",
    'records list mobile density',
)
start = s.index('class _BusinessCard extends StatelessWidget')
end = s.index('\n_RecordVisual? _recordVisual', start)
new_business_card = r'''class _BusinessCard extends StatelessWidget {
  const _BusinessCard({
    required this.row,
    required this.title,
    required this.fields,
    required this.onTap,
    this.recordType,
    this.onAction,
  });

  final Map<String, dynamic> row;
  final String title;
  final List<MapEntry<String, dynamic>> fields;
  final String? recordType;
  final VoidCallback onTap;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final status = row['status'];
    final reference = _reference(row);
    final visual = _recordVisual(recordType, row);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (visual != null) ...[
                Container(
                  key: ValueKey('${recordType ?? 'record'}-leading-icon'),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: visual.tint(scheme),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(visual.icon, size: 19, color: scheme.primary),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (status != null) ...[
                          const SizedBox(width: 6),
                          _StatusPill(BusinessFormat.status(status)),
                        ],
                      ],
                    ),
                    if (reference != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        reference,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (fields.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          for (final field in fields) _FieldValue(field: field),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              onAction == null
                  ? const Icon(Icons.chevron_right_rounded, size: 20)
                  : IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Actions',
                      onPressed: onAction,
                      icon: const Icon(Icons.more_vert_rounded, size: 20),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  String? _reference(Map<String, dynamic> row) {
    for (final key in const ['reference', 'entry_no', 'sale_no', 'bill_no']) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty) {
        return '${BusinessFormat.label(key)}: $value';
      }
    }
    return null;
  }
}
'''
s = s[:start] + new_business_card + s[end:]
s = replace_once(s, 'constraints: const BoxConstraints(minWidth: 92, maxWidth: 160),', 'constraints: const BoxConstraints(minWidth: 78, maxWidth: 132),', 'field constraints')
s = replace_once(s, '        const SizedBox(height: 2),', '        const SizedBox(height: 1),', 'field spacing')
s = replace_once(s, '          style: Theme.of(context).textTheme.bodyMedium\n              ?.copyWith(fontWeight: FontWeight.w600),', '          style: Theme.of(context).textTheme.bodySmall?.copyWith(\n            color: Theme.of(context).colorScheme.onSurface,\n            fontWeight: FontWeight.w700,\n          ),', 'field value style')
s = replace_once(s, 'padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),', 'padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),', 'status pill density')
p.write_text(s)

# 5) Mobile drawer: bottom navigation owns workspace. Drawer owns modules/tools only.
p, s = read('flutter-app/lib/shell/app_shell.dart')
s = replace_once(s, "final width = (MediaQuery.sizeOf(context).width * .9).clamp(300.0, 390.0);", "final width = (MediaQuery.sizeOf(context).width * .86).clamp(292.0, 360.0);", 'drawer width')
s = s.replace('BorderRadius.horizontal(right: Radius.circular(26))', 'BorderRadius.horizontal(right: Radius.circular(20))', 1)
s = replace_once(s, 'padding: const EdgeInsets.fromLTRB(18, 16, 12, 18),', 'padding: const EdgeInsets.fromLTRB(16, 12, 10, 14),', 'drawer header padding')
s = replace_once(s, 'bottomRight: Radius.circular(26),', 'bottomRight: Radius.circular(20),', 'drawer header radius')
s = replace_once(s, 'width: 142,\n                        height: 54,', 'width: 118,\n                        height: 42,', 'drawer logo size')
s = replace_once(s, 'borderRadius: BorderRadius.circular(14),\n                        ),\n                        child: Image.asset(', 'borderRadius: BorderRadius.circular(10),\n                        ),\n                        child: Image.asset(', 'drawer logo radius')
s = replace_once(s, 'const SizedBox(height: 16),', 'const SizedBox(height: 10),', 'drawer header gap')
s = replace_once(s, 'width: 48,\n                        height: 48,', 'width: 40,\n                        height: 40,', 'drawer avatar size')
workspace_pattern = r"\n                  _drawerSectionLabel\('WORKSPACE'\),.*?\n                  if \(moduleSections\.isNotEmpty\) \.\.\.\["
s = replace_regex_once(s, workspace_pattern, "\n                  if (moduleSections.isNotEmpty) ...[", 'remove duplicated workspace drawer items')
s = s.replace("_drawerSectionLabel('BUSINESS MODULES')", "_drawerSectionLabel('MODULES')")
p.write_text(s)

# 6) Module top chrome density: branch selector/action areas.
for path in [
    'flutter-app/lib/screens/inventory/inventory_screen.dart',
    'flutter-app/lib/screens/sales/sales_screen.dart',
]:
    p, s = read(path)
    s = s.replace(
        'const Padding(padding: EdgeInsets.all(16), child: BranchSelector()),',
        'const Padding(\n              padding: EdgeInsets.fromLTRB(12, 10, 12, 8),\n              child: BranchSelector(),\n            ),',
        1,
    )
    s = s.replace('padding: const EdgeInsets.symmetric(horizontal: 16),', 'padding: const EdgeInsets.symmetric(horizontal: 12),', 1)
    p.write_text(s)

# 7) My Work: denser top and attendance action zone, no giant button band.
p, s = read('flutter-app/lib/screens/my_work/my_work_screen.dart')
s = replace_once(s, 'padding: EdgeInsets.fromLTRB(16, 12, 16, 0),\n            child: BranchSelector(),', 'padding: EdgeInsets.fromLTRB(12, 10, 12, 0),\n            child: BranchSelector(),', 'mywork branch density')
s = replace_once(s, "padding: const EdgeInsets.all(16),\n      children: [", "padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),\n      children: [", 'attendance padding')
s = replace_once(s, '        const SizedBox(height: 12),\n        Wrap(\n          spacing: 10,\n          runSpacing: 10,', '        const SizedBox(height: 8),\n        Wrap(\n          spacing: 8,\n          runSpacing: 8,', 'attendance buttons spacing')
p.write_text(s)

# Safety assertions.
reports = Path('flutter-app/lib/screens/reports/reports_screen.dart').read_text()
if "value: 'stock'" in reports or "ApiPaths.reportsStock" in reports:
    raise SystemExit('Reports Stock duplication still present')
shell = Path('flutter-app/lib/shell/app_shell.dart').read_text()
drawer_start = shell.index('Drawer _mobileDrawer')
drawer_end = shell.index('String _currentBranchLabel', drawer_start)
drawer = shell[drawer_start:drawer_end]
for duplicate in ["label: 'Home'", "label: 'My Work'", "label: 'Quick Actions'", "label: 'Tasks'"]:
    if duplicate in drawer:
        raise SystemExit(f'Mobile drawer duplicate still present: {duplicate}')

print('Premium UI dedupe patch applied successfully.')
