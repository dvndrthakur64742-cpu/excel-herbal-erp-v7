from pathlib import Path

ROOT = Path('flutter-app')


def read(rel):
    return (ROOT / rel).read_text()


def write(rel, text):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 match, found {count}')
    return text.replace(old, new, 1)


# 1) BranchSelector must never build with a selected value missing from items.
write('lib/widgets/branch_selector.dart', r'''import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';

class BranchSelector extends ConsumerWidget {
  const BranchSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    if (!app.branchSelectorVisible) return const SizedBox.shrink();

    final branches = <({int id, String name})>[];
    for (final branch in app.branches) {
      final id = int.tryParse('${branch['id']}');
      if (id == null) continue;
      branches.add((id: id, name: '${branch['name'] ?? 'Branch'}'));
    }
    if (branches.isEmpty) return const SizedBox.shrink();

    final selected = branches.any((branch) => branch.id == app.currentBranchId)
        ? app.currentBranchId
        : null;

    return DropdownButtonFormField<int>(
      isExpanded: true,
      menuMaxHeight: 360,
      initialValue: selected,
      decoration: const InputDecoration(
        labelText: 'Branch',
        prefixIcon: Icon(Icons.store_outlined, size: 20),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: [
        for (final branch in branches)
          DropdownMenuItem<int>(
            value: branch.id,
            child: Text(
              branch.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        if (value != null) {
          ref.read(appStateProvider.notifier).selectBranch(value);
        }
      },
    );
  }
}
''')

# 2) My Work quick actions need a real route surface, not a transparent/black page.
rel = 'lib/shell/app_shell.dart'
text = read(rel)
old = """    if (screen != null) {\n      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen!));\n    }"""
new = """    if (screen != null) {\n      final routedScreen = screen is MyWorkScreen\n          ? Scaffold(\n              appBar: AppBar(title: const Text('My Work')),\n              body: SafeArea(child: screen),\n            )\n          : screen;\n      Navigator.of(context).push(\n        MaterialPageRoute(builder: (_) => routedScreen),\n      );\n    }"""
text = replace_once(text, old, new, 'standalone My Work route')
write(rel, text)

# 3) Daily Order banners and create dialog must stay compact at phone widths.
rel = 'lib/screens/my_work/my_work_screen.dart'
text = read(rel)
old = """            child: Text(\n              text,\n              style: TextStyle(\n                color: fg,\n                fontWeight: FontWeight.w600,\n                height: 1.3,\n              ),\n            ),"""
new = """            child: Text(\n              text,\n              maxLines: 3,\n              overflow: TextOverflow.ellipsis,\n              style: TextStyle(\n                color: fg,\n                fontSize: 13,\n                fontWeight: FontWeight.w600,\n                height: 1.3,\n              ),\n            ),"""
text = replace_once(text, old, new, 'feedback banner typography')

anchor = "title: const Text('Create Daily Order'),"
pos = text.find(anchor)
if pos < 0:
    raise SystemExit('Create Daily Order dialog anchor missing')
end = text.find("      if (mode == null) {", pos)
if end < 0:
    raise SystemExit('Create Daily Order dialog end missing')
segment = text[pos:end]
segment = replace_once(
    segment,
    """title: const Text('Create Daily Order'),\n            content: SizedBox(""",
    """title: const Text('Create Daily Order'),\n            insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),\n            content: SizedBox(""",
    'Create Daily Order inset padding',
)
segment = replace_once(
    segment,
    """                      DropdownButtonFormField<int>(\n                        initialValue: selectedEmployee,""",
    """                      DropdownButtonFormField<int>(\n                        isExpanded: true,\n                        menuMaxHeight: 360,\n                        initialValue: selectedEmployee,""",
    'employee dropdown expansion',
)
start = segment.find("                    ...products.map((p) {")
stop_marker = "                    }),\n"
stop = segment.find(stop_marker, start)
if start < 0 or stop < 0:
    raise SystemExit('Create Daily Order product list region missing')
stop += len(stop_marker)
compact_products = r'''                    ...products.map((p) {
                      final id = int.parse('${p['id']}');
                      final price = p['sale_price'] == null
                          ? ''
                          : '₹${p['sale_price']}';
                      final points = p['points'] == null ? '' : '${p['points']} pts';
                      final meta = [price, points]
                          .where((value) => value.isNotEmpty)
                          .join(' · ');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${p['name']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    if (meta.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        meta,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 92,
                                child: TextField(
                                  controller: qty[id],
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [WholePcs.positiveFormatter],
                                  textAlign: TextAlign.right,
                                  decoration: const InputDecoration(
                                    hintText: '0',
                                    suffixText: 'PCS',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
'''
segment = segment[:start] + compact_products + segment[stop:]
text = text[:pos] + segment + text[end:]
write(rel, text)

# 4) Inventory selectors: no debug overflow, bounded menus, whole-PCS labels.
rel = 'lib/screens/inventory/inventory_screen.dart'
text = read(rel)
import_anchor = "import '../../core/api_paths.dart';\n"
if "import '../../core/business_format.dart';" not in text:
    text = replace_once(
        text,
        import_anchor,
        import_anchor + "import '../../core/business_format.dart';\n",
        'inventory BusinessFormat import',
    )
text = text.replace(
    """                    DropdownButtonFormField<int>(\n                      initialValue: lineId,""",
    """                    DropdownButtonFormField<int>(\n                      isExpanded: true,\n                      menuMaxHeight: 360,\n                      initialValue: lineId,""",
)
if text.count('menuMaxHeight: 360') < 2:
    raise SystemExit('Expected both inventory stock selectors to become bounded')
old_label = """child: Text(\n                            '${stock[i]['product_name']} · Batch ${stock[i]['batch_no'] ?? '-'} · Qty ${stock[i]['quantity']}',\n                          ),"""
new_label = """child: Text(\n                            '${stock[i]['product_name']} · Batch ${stock[i]['batch_no'] ?? '-'} · ${BusinessFormat.quantity(stock[i]['quantity'])} PCS',\n                            maxLines: 1,\n                            overflow: TextOverflow.ellipsis,\n                          ),"""
count = text.count(old_label)
if count != 2:
    raise SystemExit(f'inventory stock item labels: expected 2, found {count}')
text = text.replace(old_label, new_label)
text = replace_once(
    text,
    """builder: (context, setLocal) => AlertDialog(\n            title: const Text('New Stock Transfer'),""",
    """builder: (context, setLocal) => AlertDialog(\n            insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),\n            title: const Text('New Stock Transfer'),""",
    'transfer dialog inset',
)
text = replace_once(
    text,
    """builder: (context, setLocal) => AlertDialog(\n            title: const Text('Stock Adjustment Request'),""",
    """builder: (context, setLocal) => AlertDialog(\n            insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),\n            title: const Text('Stock Adjustment Request'),""",
    'adjustment dialog inset',
)
write(rel, text)

# 5) Reports narrow phones should use a stable dropdown rather than a clipped segmented row.
rel = 'lib/screens/reports/reports_screen.dart'
text = read(rel)
start = text.find("  Widget _mobileReportSelector() => SingleChildScrollView(")
end = text.find("  Widget _reportRail() {", start)
if start < 0 or end < 0:
    raise SystemExit('Reports mobile selector region missing')
selector = r'''  Widget _mobileReportSelector() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: type,
          decoration: const InputDecoration(
            labelText: 'Report view',
            prefixIcon: Icon(Icons.analytics_outlined, size: 20),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'sales', child: Text('Sales Summary')),
            DropdownMenuItem(value: 'purchase', child: Text('Purchase Summary')),
            DropdownMenuItem(value: 'stock', child: Text('Stock Position')),
            DropdownMenuItem(value: 'finance', child: Text('Finance Movement')),
            DropdownMenuItem(value: 'trial', child: Text('Trial Balance')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => type = value);
          },
        ),
      );

'''
text = text[:start] + selector + text[end:]
write(rel, text)

print('Applied mobile defect sweep.')
