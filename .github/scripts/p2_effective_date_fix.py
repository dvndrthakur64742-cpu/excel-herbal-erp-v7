from pathlib import Path

p = Path('flutter-app/lib/screens/organization/organization_screen.dart')
s = p.read_text()
old = """                  data: {\n                    ...commercial.toPayload(),\n                    'effective_from': '${effectiveDate.text.trim()} 00:00:00',\n                    'reason': reason.text.trim(),\n                  },"""
new = """                  data: {\n                    ...commercial.toPayload(),\n                    if (effectiveDate.text.trim() != app.businessDate)\n                      'effective_from': '${effectiveDate.text.trim()} 00:00:00',\n                    'reason': reason.text.trim(),\n                  },"""
if old not in s:
    raise SystemExit('effective_from payload pattern not found')
p.write_text(s.replace(old, new, 1))
