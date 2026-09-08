from pathlib import Path

root = Path('flutter-app')
my_work = root / 'lib/screens/my_work/my_work_screen.dart'
text = my_work.read_text()

# Pure Daily Order arithmetic helper import.
anchor = "import '../../core/business_format.dart';\n"
if "daily_order_math.dart" not in text:
    if anchor not in text:
        raise SystemExit('business_format import anchor not found')
    text = text.replace(anchor, anchor + "import '../../core/daily_order_math.dart';\n", 1)

start = text.index('  Future<void> _editEvening(int id) async {')
end = text.index('  Future<void> _finalPost(int id) async {', start)
evening = text[start:end]

old = """    final note = TextEditingController(text: '${evening['notes'] ?? ''}');
    String? mode;
"""
new = """    final note = TextEditingController(text: '${evening['notes'] ?? ''}');
    var wholesaleEnabled = customer.text.trim().isNotEmpty ||
        lines.any(
          (line) =>
              (num.tryParse('${line['wholesale_quantity'] ?? 0}') ?? 0) > 0,
        );
    String? mode;
"""
if old not in evening:
    raise SystemExit('wholesale seed anchor not found')
evening = evening.replace(old, new, 1)

old = """                      children: [
                        Container(
                          padding: const EdgeInsets.all(13),
"""
new = """                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Wholesale sale?',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 8),
                              SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment<bool>(
                                    value: false,
                                    icon: Icon(Icons.close_rounded),
                                    label: Text('No'),
                                  ),
                                  ButtonSegment<bool>(
                                    value: true,
                                    icon: Icon(Icons.storefront_outlined),
                                    label: Text('Yes'),
                                  ),
                                ],
                                selected: {wholesaleEnabled},
                                onSelectionChanged: (selection) {
                                  setLocal(
                                    () => wholesaleEnabled = selection.first,
                                  );
                                },
                              ),
                              const SizedBox(height: 6),
                              Text(
                                wholesaleEnabled
                                    ? 'Wholesale Qty aur Wholesale Rate product-wise enter karein.'
                                    : 'Wholesale No: sirf Return Qty enter karein.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(13),
"""
if old not in evening:
    raise SystemExit('wholesale choice insertion anchor not found')
evening = evening.replace(old, new, 1)

old = "                          final wh = WholePcs.parseOrZero(wholesale[key]!.text);\n"
new = """                          final wh = wholesaleEnabled
                              ? WholePcs.parseOrZero(wholesale[key]!.text)
                              : 0;
"""
if evening.count(old) != 1:
    raise SystemExit(f'expected one UI wholesale parse, found {evening.count(old)}')
evening = evening.replace(old, new, 1)
evening = evening.replace(
    "                          final calculated = issued - ret - wh;\n"
    "                          final sold = calculated < 0 ? 0 : calculated;\n",
    "                          final sold = DailyOrderMath.retailSold(\n"
    "                            issued,\n"
    "                            ret,\n"
    "                            wh,\n"
    "                          );\n",
    1,
)

old = """                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        if (constraints.maxWidth < 520) {
"""
new = """                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        if (!wholesaleEnabled) {
                                          return returnField();
                                        }
                                        if (constraints.maxWidth < 520) {
"""
if old not in evening:
    raise SystemExit('responsive wholesale anchor not found')
evening = evening.replace(old, new, 1)

old = """                        const SizedBox(height: 2),
                        TextField(
                          controller: customer,
                          decoration: const InputDecoration(
                            labelText: 'Wholesale Customer',
                            hintText: 'Wholesale sale ho tab required',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: note,
"""
new = """                        const SizedBox(height: 2),
                        if (wholesaleEnabled) ...[
                          TextField(
                            controller: customer,
                            decoration: const InputDecoration(
                              labelText: 'Wholesale Customer',
                              hintText: 'Wholesale customer name required',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextField(
                          controller: note,
"""
if old not in evening:
    raise SystemExit('wholesale customer anchor not found')
evening = evening.replace(old, new, 1)

old = """        final wh = WholePcs.parseOrZero(wholesale[key]!.text);
        final issued = double.tryParse('${l['issued_quantity']}') ?? 0;
        final retailRate = double.tryParse('${l['retail_rate']}') ?? 0;
        final whRate = double.tryParse(wholesaleRate[key]!.text) ?? 0;
"""
new = """        final wh = wholesaleEnabled
            ? WholePcs.parseOrZero(wholesale[key]!.text)
            : 0;
        final issued = double.tryParse('${l['issued_quantity']}') ?? 0;
        final retailRate = double.tryParse('${l['retail_rate']}') ?? 0;
        final whRate = wholesaleEnabled
            ? (double.tryParse(wholesaleRate[key]!.text) ?? 0)
            : 0;
"""
if old not in evening:
    raise SystemExit('payload wholesale anchor not found')
evening = evening.replace(old, new, 1)

old = """      if (anyWholesale && customer.text.trim().isEmpty) {
        throw Exception('Wholesale customer name required.');
      }
"""
new = """      if (wholesaleEnabled && !anyWholesale) {
        throw Exception(
          'Wholesale Yes select kiya hai. Kam se kam ek Wholesale Qty enter karein.',
        );
      }
      if (wholesaleEnabled && customer.text.trim().isEmpty) {
        throw Exception('Wholesale customer name required.');
      }
"""
if old not in evening:
    raise SystemExit('wholesale validation anchor not found')
evening = evening.replace(old, new, 1)
evening = evening.replace(
    "'wholesale_customer_name': customer.text.trim(),",
    "'wholesale_customer_name': wholesaleEnabled ? customer.text.trim() : '',",
    1,
)
text = text[:start] + evening + text[end:]

# Detail fallback: Retail Sold = Issued - Return - Wholesale.
old = """                          final returned =
                              num.tryParse(
                                '${l['return_quantity'] ?? l['return_qty'] ?? 0}',
                              ) ??
                              0;
                          final issued =
                              num.tryParse('${l['issued_quantity'] ?? 0}') ?? 0;
                          final soldRaw = l['sold_quantity'] ?? l['sold_qty'];
                          final calculatedSold = issued - returned;
                          final sold = soldRaw == null
                              ? (calculatedSold > 0 ? calculatedSold : 0)
                              : (num.tryParse('$soldRaw') ??
                                    (calculatedSold > 0 ? calculatedSold : 0));
"""
new = """                          final returned =
                              num.tryParse(
                                '${l['return_quantity'] ?? l['return_qty'] ?? 0}',
                              ) ??
                              0;
                          final wholesaleSold =
                              num.tryParse('${l['wholesale_quantity'] ?? 0}') ??
                              0;
                          final issued =
                              num.tryParse('${l['issued_quantity'] ?? 0}') ?? 0;
                          final soldRaw = l['sold_quantity'] ?? l['sold_qty'];
                          final sold = soldRaw == null
                              ? DailyOrderMath.retailSold(
                                  issued,
                                  returned,
                                  wholesaleSold,
                                )
                              : (num.tryParse('$soldRaw') ??
                                    DailyOrderMath.retailSold(
                                      issued,
                                      returned,
                                      wholesaleSold,
                                    ));
"""
if old not in text:
    raise SystemExit('daily detail fallback anchor not found')
text = text.replace(old, new, 1)
old_label = "'Sold ${BusinessFormat.quantity(sold)} · Return ${BusinessFormat.quantity(returned)}',"
new_label = "'Retail ${BusinessFormat.quantity(sold)} · Wholesale ${BusinessFormat.quantity(wholesaleSold)} · Return ${BusinessFormat.quantity(returned)}',"
if old_label not in text:
    raise SystemExit('daily detail label anchor not found')
text = text.replace(old_label, new_label, 1)
my_work.write_text(text)

(root / 'lib/core/daily_order_math.dart').write_text(r'''abstract final class DailyOrderMath {
  static double retailSold(num issued, num returned, num wholesale) {
    final value = issued.toDouble() - returned.toDouble() - wholesale.toDouble();
    return value > 0 ? value : 0;
  }

  static bool quantitiesFit(num issued, num returned, num wholesale) =>
      returned >= 0 &&
      wholesale >= 0 &&
      returned.toDouble() + wholesale.toDouble() <= issued.toDouble() + 0.0001;

  static bool wholesaleRateValid(
    num wholesaleQty,
    num wholesaleRate,
    num retailRate,
  ) {
    if (wholesaleQty <= 0) return true;
    return wholesaleRate > 0 &&
        wholesaleRate.toDouble() <= retailRate.toDouble() + 0.005;
  }

  static double totalAmount(
    num retailSold,
    num retailRate,
    num wholesaleQty,
    num wholesaleRate,
  ) =>
      retailSold.toDouble() * retailRate.toDouble() +
      wholesaleQty.toDouble() * wholesaleRate.toDouble();

  static bool depositMatches(num entered, num expected) =>
      (entered.toDouble() - expected.toDouble()).abs() <= 0.005;
}
''')

(root / 'test/daily_order_math_test.dart').write_text(r'''import 'package:flutter_test/flutter_test.dart';

import '../lib/core/daily_order_math.dart';

void main() {
  test('retail sold excludes returns and wholesale', () {
    expect(DailyOrderMath.retailSold(10, 2, 3), 5);
    expect(DailyOrderMath.retailSold(10, 2, 0), 8);
  });

  test('retail sold never becomes negative', () {
    expect(DailyOrderMath.retailSold(5, 4, 3), 0);
  });

  test('return plus wholesale cannot exceed issued', () {
    expect(DailyOrderMath.quantitiesFit(10, 2, 8), isTrue);
    expect(DailyOrderMath.quantitiesFit(10, 3, 8), isFalse);
  });

  test('wholesale rate validation', () {
    expect(DailyOrderMath.wholesaleRateValid(2, 90, 100), isTrue);
    expect(DailyOrderMath.wholesaleRateValid(2, 110, 100), isFalse);
    expect(DailyOrderMath.wholesaleRateValid(2, 0, 100), isFalse);
    expect(DailyOrderMath.wholesaleRateValid(0, 0, 100), isTrue);
  });

  test('retail plus wholesale amount is calculated', () {
    expect(DailyOrderMath.totalAmount(5, 100, 2, 80), 660);
  });

  test('deposit equality uses rounding tolerance', () {
    expect(DailyOrderMath.depositMatches(1000, 1000.004), isTrue);
    expect(DailyOrderMath.depositMatches(1000, 1000.01), isFalse);
  });
}
''')

# GitHub Actions artifact quota must not prevent Release publication.
workflow = Path('.github/workflows/eh7-v740-stabilization-build.yml')
wf = workflow.read_text()
needle = """      - name: Upload workflow artifact
        uses: actions/upload-artifact@v4
"""
replacement = """      - name: Upload workflow artifact
        continue-on-error: true
        uses: actions/upload-artifact@v4
"""
if 'continue-on-error: true\n        uses: actions/upload-artifact@v4' not in wf:
    if needle not in wf:
        raise SystemExit('artifact upload workflow anchor not found')
    wf = wf.replace(needle, replacement, 1)
workflow.write_text(wf)
