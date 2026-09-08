from pathlib import Path

script = Path('ci/p0_logic_stabilize.py')
text = script.read_text(encoding='utf-8')
old = '''swap(FIN, "              'business_date': _today(),", "              'business_date': app.businessDate,", expected=2)'''
new = '''swap(FIN, "              'business_date': _today(),", "              'business_date': app.businessDate,")
swap(
    FIN,
    "            data: {'branch_id': app.currentBranchId, 'business_date': _today()},",
    "            data: {'branch_id': app.currentBranchId, 'business_date': app.businessDate},",
)'''
if text.count(old) != 1:
    raise RuntimeError('Expected finance business-date assertion was not found exactly once')
text = text.replace(old, new, 1)
script.write_text(text, encoding='utf-8')
exec(compile(text, str(script), 'exec'), {'__name__': '__main__', '__file__': str(script)})

# Trigger marker: corrected finance date assertion.
