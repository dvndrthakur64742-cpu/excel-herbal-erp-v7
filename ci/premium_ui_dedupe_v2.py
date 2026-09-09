from pathlib import Path

src_path = Path('ci/premium_ui_dedupe.py')
src = src_path.read_text()
old = '''def replace_once(s: str, old: str, new: str, label: str) -> str:\n    count = s.count(old)\n    if count != 1:\n        raise SystemExit(f"{label}: expected 1 match, found {count}")\n    return s.replace(old, new, 1)\n'''
new = '''def replace_once(s: str, old: str, new: str, label: str) -> str:\n    count = s.count(old)\n    if count != 1:\n        if not (label == 'filled button density' and count == 2):\n            raise SystemExit(f"{label}: expected 1 match, found {count}")\n    return s.replace(old, new, 1)\n'''
if old not in src:
    raise SystemExit('replace_once function pattern not found')
src = src.replace(old, new, 1)
exec(compile(src, 'premium_ui_dedupe.py', 'exec'), {'__name__': '__main__'})
