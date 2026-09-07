from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
reg=(ROOT/'backend/excel-herbal-erp-v7/src/Http/RouteRegistry.php').read_text()
api=(ROOT/'backend/excel-herbal-erp-v7/src/Http/Api.php').read_text()
dart=(ROOT/'flutter/excel_herbal_erp/lib/core/api_paths.dart').read_text()
routes=re.findall(r"\['(GET|POST)','([^']+)','([^']+)',(?:true|false)\]",reg)
assert routes, 'no routes parsed'
handlers=[h for _,_,h in routes]
assert len(handlers)==len(set(handlers)), 'duplicate handler keys'
for h in handlers:
    assert f"'{h}'" in api, f'handler not dispatched: {h}'

def norm_backend(path:str)->str:
    return re.sub(r"\(\?P<[^>]+>\\\\d\+\)",'{id}',path)

def norm_front(path:str)->str:
    return re.sub(r"\$[A-Za-z_][A-Za-z0-9_]*",'{id}',path)

backend={norm_backend(p) for _,p,_ in routes}
static=set(re.findall(r"='([^']+)'",dart))
dynamic=set(norm_front(p) for p in re.findall(r"static String \w+\([^)]*\)=>'([^']+)'",dart))
frontend=static|dynamic
missing=sorted(p for p in frontend if p not in backend)
assert not missing, f'Flutter paths missing backend routes: {missing}'
assert '/inventory/transfers/{id}/cancel' in backend
assert '/finance/bank-reconciliations/{id}' in backend
print(f'PASS backend handler mapping {len(routes)}/{len(routes)}')
print(f'PASS Flutter API paths {len(frontend)}/{len(frontend)} including dynamic routes')
