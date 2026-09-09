from pathlib import Path
import re

ROOT = Path('flutter-app')


def replace_once(path: Path, old: str, new: str):
    text = path.read_text()
    if old not in text:
        raise SystemExit(f'Missing expected block in {path}: {old[:80]!r}')
    text = text.replace(old, new, 1)
    path.write_text(text)

# Theme: tighter, more neutral, enterprise-first defaults.
path = ROOT / 'lib/theme/excel_brand.dart'
text = path.read_text()
repls = {
    'static const canvas = Color(0xFFF5F8F6);': 'static const canvas = Color(0xFFF7F8F7);',
    'toolbarHeight: 64,': 'toolbarHeight: 58,',
    'fontSize: 22,': 'fontSize: 20,',
    'borderRadius: BorderRadius.circular(20),': 'borderRadius: BorderRadius.circular(12),',
    'horizontal: 16,\n          vertical: 15,': 'horizontal: 13,\n          vertical: 12,',
    'BorderRadius.circular(15)': 'BorderRadius.circular(10)',
    'minTileHeight: 54,': 'minTileHeight: 48,',
    'borderRadius: BorderRadius.circular(14)': 'borderRadius: BorderRadius.circular(10)',
    'height: 72,': 'height: 64,',
    'size: 26,': 'size: 23,',
    'fontSize: 12,': 'fontSize: 11,',
    'minimumSize: const Size(48, 50),': 'minimumSize: const Size(44, 44),',
    'padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),': 'padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),',
    'shape: RoundedRectangleBorder(\n            borderRadius: BorderRadius.circular(14),\n          ),': 'shape: RoundedRectangleBorder(\n            borderRadius: BorderRadius.circular(10),\n          ),',
    'backgroundColor: primarySoft,\n        selectedColor: primarySoftStrong,': 'backgroundColor: const Color(0xFFF1F4F2),\n        selectedColor: primarySoft,',
    'color: primaryDark,\n          fontWeight: FontWeight.w700,': 'color: ink,\n          fontWeight: FontWeight.w700,',
    'shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),': 'shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),',
    'shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),': 'shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),',
}
for old, new in repls.items():
    if old not in text:
        raise SystemExit(f'Theme expectation missing: {old}')
    text = text.replace(old, new)
path.write_text(text)

# Compact branch selector used across modules.
path = ROOT / 'lib/widgets/branch_selector.dart'
text = path.read_text()
text = text.replace("labelText: 'Authorised Branch',\n        prefixIcon: Icon(Icons.store_outlined),", "labelText: 'Branch',\n        prefixIcon: Icon(Icons.store_outlined, size: 20),\n        isDense: true,\n        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),")
text = text.replace('return DropdownButtonFormField<int>(', 'return DropdownButtonFormField<int>(\n      isExpanded: true,')
path.write_text(text)

# Shared mobile records: compact list rows instead of oversized consumer cards.
path = ROOT / 'lib/widgets/records_list.dart'
text = path.read_text()
text = text.replace("padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),", "padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),", 1)
text = text.replace('separatorBuilder: (_, __) => const SizedBox(height: 10),', 'separatorBuilder: (_, __) => const SizedBox(height: 6),', 1)
text = text.replace('return ordered.take(4).toList();', 'return ordered.take(3).toList();')
start = text.index('class _BusinessCard extends StatelessWidget {')
end = text.index('\n_RecordVisual? _recordVisual', start)
new_card = '''class _BusinessCard extends StatelessWidget {
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
          padding: const EdgeInsets.fromLTRB(11, 9, 7, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (visual != null) ...[
                Container(
                  key: ValueKey('${recordType ?? 'record'}-leading-icon'),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: visual.tint(scheme),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(visual.icon, size: 17, color: scheme.primary),
                ),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
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
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 10,
                        runSpacing: 3,
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
                  ? Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant)
                  : SizedBox(
                      width: 34,
                      height: 34,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: 'Actions',
                        onPressed: onAction,
                        icon: const Icon(Icons.more_vert_rounded, size: 20),
                      ),
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
text = text[:start] + new_card + text[end:]
text = text.replace('Color tint(ColorScheme scheme) => scheme.primary.withOpacity(alpha);', 'Color tint(ColorScheme scheme) => scheme.primary.withValues(alpha: alpha);')
field_start = text.index('class _FieldValue extends StatelessWidget {')
field_end = text.index('\nclass _StatusPill', field_start)
new_field = '''class _FieldValue extends StatelessWidget {
  const _FieldValue({required this.field});
  final MapEntry<String, dynamic> field;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${BusinessFormat.label(field.key)}: ',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            TextSpan(
              text: BusinessFormat.value(field.key, field.value),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
'''
text = text[:field_start] + new_field + text[field_end:]
text = text.replace('padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),', 'padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),')
text = text.replace('color: Theme.of(context).colorScheme.secondaryContainer,', 'color: Theme.of(context).colorScheme.surfaceContainerHigh,')
path.write_text(text)

# Home: remove oversized green hero; use a restrained operational summary card.
path = ROOT / 'lib/screens/home/home_screen.dart'
text = path.read_text()
start = text.index('  Widget _welcomeHero(')
end = text.index('  Widget _workspaceCards(', start)
new_hero = '''  Widget _welcomeHero(
    BuildContext context,
    AppState app,
    Map<String, dynamic> employee,
  ) {
    final designation = _designation(app);
    final name = '${employee['full_name'] ?? 'Employee'}'.trim();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.business_center_outlined,
                    color: scheme.onPrimaryContainer,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Good ${_dayPart()}',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${app.branches.length} branches',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _CompactContext(
                    label: 'Branch',
                    value: _branchName(app),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CompactContext(
                    label: 'Role',
                    value: designation,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

'''
text = text[:start] + new_hero + text[end:]
# Append helper before _HeroMetric if absent.
marker = 'class _HeroMetric extends StatelessWidget {'
if marker not in text:
    raise SystemExit('Home helper insertion marker missing')
helper = '''class _CompactContext extends StatelessWidget {
  const _CompactContext({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
      ),
      const SizedBox(height: 1),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    ],
  );
}

'''
text = text.replace(marker, helper + marker, 1)
path.write_text(text)

# App shell: make mobile drawer significantly denser and less brand-heavy.
path = ROOT / 'lib/shell/app_shell.dart'
text = path.read_text()
repls = {
    'padding: const EdgeInsets.fromLTRB(18, 16, 12, 18),': 'padding: const EdgeInsets.fromLTRB(16, 12, 10, 13),',
    'bottomRight: Radius.circular(26),': 'bottomRight: Radius.circular(18),',
    'width: 142,\n                        height: 54,': 'width: 116,\n                        height: 42,',
    'borderRadius: BorderRadius.circular(14),': 'borderRadius: BorderRadius.circular(9),',
    'const SizedBox(height: 16),': 'const SizedBox(height: 10),',
    'width: 48,\n                        height: 48,': 'width: 40,\n                        height: 40,',
    'borderRadius: BorderRadius.circular(15),': 'borderRadius: BorderRadius.circular(10),',
    'fontSize: 17,': 'fontSize: 15,',
    'padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),': 'padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),',
}
for old, new in repls.items():
    if old not in text:
        raise SystemExit(f'App shell expectation missing: {old}')
    text = text.replace(old, new, 1)
text = text.replace('Colors.white.withOpacity(.16)', 'Colors.white.withValues(alpha: .16)')
text = text.replace('Colors.white.withOpacity(.28)', 'Colors.white.withValues(alpha: .28)')
text = text.replace('Colors.white.withOpacity(.78)', 'Colors.white.withValues(alpha: .78)')
path.write_text(text)

# Reports: tighten layout and replace casual mixed-language helper text with professional copy.
path = ROOT / 'lib/screens/reports/reports_screen.dart'
text = path.read_text()
text = text.replace('padding: EdgeInsets.fromLTRB(16, 14, 16, 10),', 'padding: EdgeInsets.fromLTRB(12, 10, 12, 6),')
text = text.replace('padding: const EdgeInsets.symmetric(horizontal: 16),', 'padding: const EdgeInsets.symmetric(horizontal: 12),')
text = text.replace('const SizedBox(height: 12),', 'const SizedBox(height: 8),', 1)
text = text.replace("padding: const EdgeInsets.symmetric(horizontal: 16),", "padding: const EdgeInsets.symmetric(horizontal: 12),", 1)
copy = {
    'Supplier bills, paid amount aur outstanding ka summary.': 'Supplier billing, payments and outstanding summary.',
    'Is period me koi purchase record nahi hai.': 'No purchase activity for the selected period.',
    'Selected branch ka current available stock.': 'Current stock position for the selected branch.',
    'Selected branch me stock record nahi mila.': 'No stock records for the selected branch.',
    'Posted journals aur accounting movement.': 'Posted journals and accounting movement summary.',
    'Is period me finance record nahi hai.': 'No finance activity for the selected period.',
    'Business date tak ledger debit-credit balance.': 'Ledger debit and credit balances as of the business date.',
    'Trial Balance empty hai.': 'No Trial Balance data is available.',
    'Sales, collection aur outstanding ka current month view.': 'Current-month sales, collections and outstanding summary.',
    'Is period me koi sales record nahi hai.': 'No sales activity for the selected period.',
    'Authorised Branch select karein': 'Select an authorised branch',
    'Report sirf selected authorised branch ka data dikhayega.': 'Reports are scoped to the selected authorised branch.',
}
for old, new in copy.items():
    if old not in text:
        raise SystemExit(f'Reports copy expectation missing: {old}')
    text = text.replace(old, new)
path.write_text(text)

# My Work: denser branch/tab header and attendance controls.
path = ROOT / 'lib/screens/my_work/my_work_screen.dart'
text = path.read_text()
text = text.replace('padding: EdgeInsets.fromLTRB(16, 12, 16, 0),', 'padding: EdgeInsets.fromLTRB(12, 8, 12, 0),', 1)
text = text.replace("padding: const EdgeInsets.all(16),\n      children: [", "padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),\n      children: [", 1)
text = text.replace('const SizedBox(height: 12),\n        Wrap(\n          spacing: 10,\n          runSpacing: 10,', 'const SizedBox(height: 8),\n        Wrap(\n          spacing: 8,\n          runSpacing: 8,', 1)
path.write_text(text)

print('Premium UI density patch applied.')
