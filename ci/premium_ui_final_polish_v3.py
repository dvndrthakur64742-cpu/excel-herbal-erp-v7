from pathlib import Path

src = Path('ci/premium_ui_final_polish.py').read_text()

quick_old = '''s = replace_once(s, '        run: openMyWork,', "        run: () => openMyWork('attendance'),", 'attendance deep link')
s = replace_once(s, '        run: openMyWork,', "        run: () => openMyWork('daily'),", 'create order deep link')
s = replace_once(s, '        run: openMyWork,', "        run: () => openMyWork('daily'),", 'evening deep link')
s = replace_once(s, '        run: openMyWork,', "        run: () => openMyWork('leave_visit'),", 'field visit deep link')
s = replace_once(s, '        run: openMyWork,', "        run: () => openMyWork('leave_visit'),", 'leave deep link')'''
quick_new = '''for label, section in [
    ('Check-In / Out', 'attendance'),
    ('Create Daily Order', 'daily'),
    ('Evening Closing', 'daily'),
    ('Field Visit', 'leave_visit'),
    ('Apply Leave', 'leave_visit'),
]:
    old_action = f"""        label: '{label}',\n        icon:"""
    start = s.index(old_action)
    end = s.index('      ));', start)
    block = s[start:end]
    block = replace_once(
        block,
        '        run: openMyWork,',
        f"        run: () => openMyWork('{section}'),",
        f'{label} deep link',
    )
    s = s[:start] + block + s[end:]'''
if quick_old not in src:
    raise SystemExit('quick action replacement block not found')
src = src.replace(quick_old, quick_new, 1)

desktop_old = '''s = replace_once(s, "      'my_work' => const MyWorkScreen(),", "      'my_work' => MyWorkScreen(initialSection: desktopMyWorkSection),", 'desktop mywork screen')'''
desktop_new = '''desktop_scope_start = s.index('  Widget _desktopContent(AppState app)')
desktop_scope_end = s.index('  Drawer _mobileDrawer', desktop_scope_start)
desktop_scope = s[desktop_scope_start:desktop_scope_end]
desktop_scope = replace_once(
    desktop_scope,
    "      'my_work' => const MyWorkScreen(),",
    "      'my_work' => MyWorkScreen(initialSection: desktopMyWorkSection),",
    'desktop mywork screen',
)
s = s[:desktop_scope_start] + desktop_scope + s[desktop_scope_end:]'''
if desktop_old not in src:
    raise SystemExit('desktop mywork replacement source not found')
src = src.replace(desktop_old, desktop_new, 1)

mobile_old = '''s = replace_once(s, "        'my_work' => const MyWorkScreen(),", "        'my_work' => MyWorkScreen(initialSection: mobileMyWorkSection),", 'mobile mywork screen')'''
mobile_new = '''mobile_scope_start = s.index('  Widget _mobilePage(AppState app, String id)')
mobile_scope_end = s.index('  Widget _bottomNav(', mobile_scope_start)
mobile_scope = s[mobile_scope_start:mobile_scope_end]
mobile_scope = replace_once(
    mobile_scope,
    "        'my_work' => const MyWorkScreen(),",
    "        'my_work' => MyWorkScreen(initialSection: mobileMyWorkSection),",
    'mobile mywork screen',
)
s = s[:mobile_scope_start] + mobile_scope + s[mobile_scope_end:]'''
if mobile_old not in src:
    raise SystemExit('mobile mywork replacement source not found')
src = src.replace(mobile_old, mobile_new, 1)

exec(compile(src, 'premium_ui_final_polish.py', 'exec'), {'__name__': '__main__'})
