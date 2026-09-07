#!/usr/bin/env python3
from pathlib import Path
import re, sys
root=Path(__file__).resolve().parents[1]/'flutter/excel_herbal_erp'
lib=root/'lib'
errors=[]
files=list(lib.rglob('*.dart'))
for p in files:
    text=p.read_text()
    # Local relative imports must exist.
    for m in re.finditer(r"import\s+['\"]([^'\"]+)['\"]", text):
        target=m.group(1)
        if target.startswith('package:') or target.startswith('dart:'): continue
        resolved=(p.parent/target).resolve()
        if not resolved.exists(): errors.append(f'{p.relative_to(root)} missing import {target}')
    # Simple lexical balance outside quoted strings/comments is intentionally conservative.
    stripped=re.sub(r"//.*?$|/\*.*?\*/|'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"",'',text,flags=re.M|re.S)
    for a,b,name in [('(',')','parentheses'),('[',']','brackets'),('{','}','braces')]:
        n=0
        for ch in stripped:
            if ch==a:n+=1
            elif ch==b:n-=1
            if n<0: errors.append(f'{p.relative_to(root)} unbalanced {name}'); break
        if n!=0: errors.append(f'{p.relative_to(root)} unbalanced {name}: {n}')
required=[
 'android/settings.gradle.kts','android/build.gradle.kts','android/app/build.gradle.kts',
 'android/app/src/main/AndroidManifest.xml','android/app/src/main/kotlin/in/excelherbal/erp/MainActivity.kt',
 'analysis_options.yaml','pubspec.yaml'
]
for rel in required:
    if not (root/rel).exists(): errors.append(f'missing build file: {rel}')
manifest=(root/'android/app/src/main/AndroidManifest.xml').read_text()
for permission in ['INTERNET','ACCESS_FINE_LOCATION','ACCESS_COARSE_LOCATION']:
    if permission not in manifest: errors.append(f'Android permission missing: {permission}')
pubspec=(root/'pubspec.yaml').read_text()
if 'go_router:' in pubspec:
    errors.append('unused go_router dependency should not be present')
gradle=(root/'android/app/build.gradle.kts').read_text()
if 'signingConfigs.getByName("debug")' in gradle:
    errors.append('release build must not use debug signing key')
if 'key.properties' not in gradle:
    errors.append('approved release signing gate missing from Android build')
if 'usesCleartextTraffic="false"' not in manifest:
    errors.append('Android cleartext traffic must remain disabled')
app_config=(lib/'core/app_config.dart').read_text()
prod='https://office.excelherbal.in/wp-json/excel-herbal-erp/v7'
if prod not in app_config:
    errors.append('canonical production V7 API constant missing')
if f"defaultValue: '{prod}'" in app_config:
    errors.append('compiler/UAT default must not point to production API')
if 'https://uat.invalid/wp-json/excel-herbal-erp/v7' not in app_config:
    errors.append('safe non-production compiler/UAT default missing')
bootstrap_script=root.parents[1]/'tool/bootstrap_android_wrapper.sh'
if not bootstrap_script.exists():
    errors.append('Android Gradle wrapper bootstrap script missing')
verify_script=root.parents[1]/'tool/verify_flutter.sh'
if not verify_script.exists():
    errors.append('Flutter compiler gate script missing')
else:
    verify=verify_script.read_text()
    if 'EH7_ALLOW_PRODUCTION_API' not in verify:
        errors.append('compiler gate does not block accidental production API use')

if errors:
    print('\n'.join('FAIL '+e for e in errors)); sys.exit(1)
print(f'PASS Flutter static integrity: {len(files)} Dart files, local imports, secure Android scaffold and release-signing gate')
