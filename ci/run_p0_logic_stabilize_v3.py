from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parents[1]

# Apply the already safety-checked P0 patch with corrected finance assertion.
runpy.run_path(str(ROOT / 'ci/run_p0_logic_stabilize_v2.py'), run_name='__main__')

TODAY_HELPER = """
  static String _today() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
"""
MONTH_HELPER = """
  static String _monthStart() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-01';
  }
"""

# These helpers become unused once all transaction periods use AppState.businessDate.
for rel, remove_today, remove_month in [
    ('flutter-app/lib/screens/finance/finance_screen.dart', True, True),
    ('flutter-app/lib/screens/home/home_screen.dart', True, True),
    ('flutter-app/lib/screens/my_work/my_work_screen.dart', True, False),
    ('flutter-app/lib/screens/organization/organization_screen.dart', True, False),
    ('flutter-app/lib/screens/performance/performance_screen.dart', True, True),
]:
    path = ROOT / rel
    text = path.read_text(encoding='utf-8')
    if remove_today:
        if text.count(TODAY_HELPER) != 1:
            raise RuntimeError(f'{rel}: expected exactly one obsolete _today helper')
        text = text.replace(TODAY_HELPER, '', 1)
    if remove_month:
        if text.count(MONTH_HELPER) != 1:
            raise RuntimeError(f'{rel}: expected exactly one obsolete _monthStart helper')
        text = text.replace(MONTH_HELPER, '', 1)
    path.write_text(text, encoding='utf-8')

print('Removed obsolete device-date helpers from P0 screens')
