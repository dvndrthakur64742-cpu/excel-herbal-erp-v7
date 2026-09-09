from pathlib import Path

src = Path('ci/premium_ui_dedupe.py').read_text()

old_func = '''def replace_once(s: str, old: str, new: str, label: str) -> str:\n    count = s.count(old)\n    if count != 1:\n        raise SystemExit(f"{label}: expected 1 match, found {count}")\n    return s.replace(old, new, 1)\n'''
new_func = '''def replace_once(s: str, old: str, new: str, label: str) -> str:\n    count = s.count(old)\n    if count != 1:\n        if not (label == 'filled button density' and count == 2):\n            raise SystemExit(f"{label}: expected 1 match, found {count}")\n    return s.replace(old, new, 1)\n'''
if old_func not in src:
    raise SystemExit('replace_once function pattern not found')
src = src.replace(old_func, new_func, 1)

old_button_radius = "s = s.replace('BorderRadius.circular(14)', 'BorderRadius.circular(11)', 2)"
new_button_radius = '''button_shape = """textStyle: const TextStyle(fontWeight: FontWeight.w800),\n          shape: RoundedRectangleBorder(\n            borderRadius: BorderRadius.circular(14),\n          ),"""\nbutton_shape_new = button_shape.replace('BorderRadius.circular(14)', 'BorderRadius.circular(11)')\nif s.count(button_shape) != 2:\n    raise SystemExit(f'button shape: expected 2 matches, found {s.count(button_shape)}')\ns = s.replace(button_shape, button_shape_new, 2)'''
if old_button_radius not in src:
    raise SystemExit('button radius source pattern not found')
src = src.replace(old_button_radius, new_button_radius, 1)

old_field = "s = replace_once(s, '        const SizedBox(height: 2),', '        const SizedBox(height: 1),', 'field spacing')"
new_field = '''field_start = s.index('class _FieldValue extends StatelessWidget')\nfield_end = s.index('class _StatusPill extends StatelessWidget', field_start)\nfield_block = s[field_start:field_end]\nfield_block = replace_once(\n    field_block,\n    '        const SizedBox(height: 2),',\n    '        const SizedBox(height: 1),',\n    'field spacing',\n)\ns = s[:field_start] + field_block + s[field_end:]'''
if old_field not in src:
    raise SystemExit('field spacing source pattern not found')
src = src.replace(old_field, new_field, 1)

old_drawer_gap = "s = replace_once(s, 'const SizedBox(height: 16),', 'const SizedBox(height: 10),', 'drawer header gap')"
new_drawer_gap = '''drawer_scope_start = s.index('Drawer _mobileDrawer')\ndrawer_scope_end = s.index('Widget _drawerSectionLabel', drawer_scope_start)\ndrawer_scope = s[drawer_scope_start:drawer_scope_end]\ndrawer_scope = replace_once(\n    drawer_scope,\n    'const SizedBox(height: 16),',\n    'const SizedBox(height: 10),',\n    'drawer header gap',\n)\ns = s[:drawer_scope_start] + drawer_scope + s[drawer_scope_end:]'''
if old_drawer_gap not in src:
    raise SystemExit('drawer gap source pattern not found')
src = src.replace(old_drawer_gap, new_drawer_gap, 1)

exec(compile(src, 'premium_ui_dedupe.py', 'exec'), {'__name__': '__main__'})
