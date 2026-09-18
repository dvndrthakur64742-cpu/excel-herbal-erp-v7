"""Source checks only. This is not a PHP parser, linter, or runtime test."""
import re,json,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
def balanced(path):
 s=path.read_text();stack=[];i=0
 while i<len(s):
  if s.startswith('//',i) or s[i]=='#':
   end=s.find('\n',i);i=len(s) if end<0 else end+1;continue
  if s.startswith('/*',i):
   end=s.find('*/',i+2);assert end>=0,(path,'unclosed comment');i=end+2;continue
  if s[i] in "'\"`":
   quote=s[i];i+=1
   while i<len(s):
    if s[i]=='\\':i+=2;continue
    if s[i]==quote:i+=1;break
    i+=1
   else:raise AssertionError((path,'unclosed string'))
   continue
  c=s[i]
  if c in '([{':stack.append(c)
  elif c in ')]}':assert stack and stack.pop()=={')':'(',']':'[','}':'{'}[c],(path,'unbalanced delimiter',i)
  i+=1
 assert not stack,(path,'unclosed delimiters')
files=list((root/'src').rglob('*.php'))+[root/'excel-herbal-erp-v7.php']+list((root/'tests').glob('*.php'))
for p in files:balanced(p)
print(f'PASS lexical delimiter scan: {len(files)} PHP files (NOT PHP lint)')
s=(root/'src/Http/RouteRegistry.php').read_text()
rows=re.findall(r"\['(GET|POST)','([^']+)','([^']+)',(true|false)\]",s)
assert len(rows)==len(set((r[0],r[1]) for r in rows)),'duplicate routes'
api=(root/'src/Http/Api.php').read_text()+(root/'src/Http/ApiDispatch.php').read_text()
assert all("'"+handler+"'=>" in api for _,_,handler,_ in rows),'missing dispatch handler'
dispatch=(root/'src/Http/ApiDispatch.php').read_text()
dispatch_defs=set(re.findall(r"function\s+([A-Za-z0-9_]+)\s*\(",dispatch))
dispatch_calls=set(re.findall(r"self::([A-Za-z0-9_]+)\s*\(",dispatch))
assert dispatch_calls<=dispatch_defs,('dispatcher self-call helper missing',sorted(dispatch_calls-dispatch_defs))
print(f'PASS {len(rows)} unique route definitions and dispatch mappings')
contract=json.loads((root/'API-CONTRACT-7.3.5.json').read_text())
assert len(contract['routes'])==len(rows)
print('PASS generated contract count and JSON')
fixtures=json.loads((root/'tests/payroll-fixtures.json').read_text());assert len(fixtures)==21
print('PASS 21 fixture records parse; PHP execution NOT performed by this script')
if len(sys.argv)>1:
 base=Path(sys.argv[1]);old=set(re.findall(r"\['(GET|POST)','([^']+)','([^']+)',(true|false)\]",(base/'src/Http/RouteRegistry.php').read_text()))
 assert old<=set(rows),'existing route lost';print(f'PASS all {len(old)} original routes retained')
if len(sys.argv)>2:balanced(Path(sys.argv[2]));print('PASS setup assistant lexical delimiter scan (NOT PHP lint)')
