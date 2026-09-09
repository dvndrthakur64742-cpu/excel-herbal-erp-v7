from pathlib import Path

p = Path('ci/ia_connection_reset.py')
text = p.read_text()
old = '''replace_once(\n    p,\n    """      'home' => const HomeScreen(),""",\n    """      'home' => HomeScreen(\\n        openMyWork: () => setState(() => desktopRoute = 'my_work'),\\n      ),""",\n    'desktop home connection',\n)'''
new = '''replace_once(\n    p,\n    """    final child = switch (desktopRoute) {\\n      'home' => const HomeScreen(),""",\n    """    final child = switch (desktopRoute) {\\n      'home' => HomeScreen(\\n        openMyWork: () => setState(() => desktopRoute = 'my_work'),\\n      ),""",\n    'desktop home connection',\n)'''
if text.count(old) != 1:
    raise SystemExit(f'wrapper: expected desktop patch block once, found {text.count(old)}')
p.write_text(text.replace(old, new, 1))
exec(compile(p.read_text(), str(p), 'exec'))
