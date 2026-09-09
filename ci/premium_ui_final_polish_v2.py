from pathlib import Path

src = Path('ci/premium_ui_final_polish.py').read_text()
old = '''s = replace_once(s, '        run: openMyWork,', "        run: () => openMyWork('attendance'),", 'attendance deep link')
s = replace_once(s, '        run: openMyWork,', "        run: () => openMyWork('daily'),", 'create order deep link')
s = replace_once(s, '        run: openMyWork,', "        run: () => openMyWork('daily'),", 'evening deep link')
s = replace_once(s, '        run: openMyWork,', "        run: () => openMyWork('leave_visit'),", 'field visit deep link')
s = replace_once(s, '        run: openMyWork,', "        run: () => openMyWork('leave_visit'),", 'leave deep link')'''
new = '''for label, section in [
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
if old not in src:
    raise SystemExit('quick action replacement block not found')
src = src.replace(old, new, 1)
exec(compile(src, 'premium_ui_final_polish.py', 'exec'), {'__name__': '__main__'})
