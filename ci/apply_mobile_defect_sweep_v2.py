from pathlib import Path
import re

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


# 1) Branch selector: tolerate transient branch-context/list mismatch.
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

# 2) Quick Action -> My Work must open inside a real Material/Scaffold surface.
rel = 'lib/shell/app_shell.dart'
text = read(rel)
anchor = "      case 'expense_entry':"
pos = text.find(anchor)
if pos < 0:
    raise SystemExit('Quick-action switch anchor missing')
old = """    if (screen != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen!));
    }"""
block_pos = text.find(old, pos)
if block_pos < 0:
    raise SystemExit('Quick-action push block missing after action switch')
new = """    if (screen != null) {
      final routedScreen = screen is MyWorkScreen
          ? Scaffold(
              appBar: AppBar(title: const Text('My Work')),
              body: SafeArea(child: screen),
            )
          : screen;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => routedScreen),
      );
    }"""
text = text[:block_pos] + new + text[block_pos + len(old):]
write(rel, text)

# 3) My Work: compact feedback + phone-safe Daily Order editor.
rel = 'lib/screens/my_work/my_work_screen.dart'
text = read(rel)
old = """            child: Text(
              text,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),"""
new = """            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),"""
text = replace_once(text, old, new, 'feedback banner')

anchor = "title: const Text('Create Daily Order'),"
pos = text.find(anchor)
if pos < 0:
    raise SystemExit('Create Daily Order dialog missing')
end = text.find("      if (mode == null) {", pos)
if end < 0:
    raise SystemExit('Create Daily Order post-dialog marker missing')
segment = text[pos:end]
segment = replace_once(
    segment,
    """title: const Text('Create Daily Order'),
            content: SizedBox(""",
    """title: const Text('Create Daily Order'),
            insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            content: SizedBox(""",
    'daily dialog inset',
)
segment = replace_once(
    segment,
    """                      DropdownButtonFormField<int>(
                        initialValue: selectedEmployee,""",
    """                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        menuMaxHeight: 360,
                        initialValue: selectedEmployee,""",
    'employee selector expansion',
)
segment = segment.replace("child: const Text('Save Draft')", "child: const Text('Draft')", 1)
segment = segment.replace("child: const Text('Create & Submit')", "child: const Text('Submit')", 1)

start = segment.find("                    ...products.map((p) {")
stop_marker = "                    }),\n"
stop = segment.find(stop_marker, start)
if start < 0 or stop < 0:
    raise SystemExit('Daily Order product editor region missing')
stop += len(stop_marker)
compact_products = r'''                    ...products.map((p) {
                      final id = int.parse('${p['id']}');
                      final price = p['sale_price'] == null
                          ? ''
                          : '₹${p['sale_price']}';
                      final points = p['points'] == null
                          ? ''
                          : '${p['points']} pts';
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

# 4) Inventory: eliminate narrow-dialog dropdown overflows and raw decimals.
rel = 'lib/screens/inventory/inventory_screen.dart'
text = read(rel)
if "import '../../core/business_format.dart';" not in text:
    text = replace_once(
        text,
        "import '../../core/api_paths.dart';\n",
        "import '../../core/api_paths.dart';\nimport '../../core/business_format.dart';\n",
        'BusinessFormat import',
    )
selector_count = text.count('initialValue: lineId,')
if selector_count != 2:
    raise SystemExit(f'Expected 2 inventory stock selectors, found {selector_count}')
text = text.replace(
    'initialValue: lineId,',
    "isExpanded: true,\n                      menuMaxHeight: 360,\n                      initialValue: lineId,",
)
label_pattern = re.compile(
    r"child:\s*Text\(\s*'\$\{stock\[i\]\['product_name'\]\} · Batch \$\{stock\[i\]\['batch_no'\] \?\? '-'\} · Qty \$\{stock\[i\]\['quantity'\]\}',\s*\),"
)
label_replacement = """child: Text(
                            '${stock[i]['product_name']} · Batch ${stock[i]['batch_no'] ?? '-'} · ${BusinessFormat.quantity(stock[i]['quantity'])} PCS',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),"""
text, label_count = label_pattern.subn(label_replacement, text)
if label_count != 2:
    raise SystemExit(f'Expected 2 inventory item labels, found {label_count}')
text = replace_once(
    text,
    """builder: (context, setLocal) => AlertDialog(
            title: const Text('New Stock Transfer'),""",
    """builder: (context, setLocal) => AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            title: const Text('New Stock Transfer'),""",
    'transfer dialog inset',
)
text = replace_once(
    text,
    """builder: (context, setLocal) => AlertDialog(
            title: const Text('Stock Adjustment Request'),""",
    """builder: (context, setLocal) => AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            title: const Text('Stock Adjustment Request'),""",
    'adjustment dialog inset',
)
write(rel, text)

# 5) Reports: narrow phones get a stable selector; desktop rail stays unchanged.
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
          menuMaxHeight: 360,
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

print('Applied mobile UAT defect sweep v2.')
