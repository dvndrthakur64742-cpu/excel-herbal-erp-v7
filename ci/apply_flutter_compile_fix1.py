from pathlib import Path

org = Path('work/flutter/excel_herbal_erp/lib/screens/organization/organization_screen.dart')
perf = Path('work/flutter/excel_herbal_erp/lib/screens/performance/performance_screen.dart')

org_text = org.read_text()
old_org = """      final payload = {\n        'assigned_branch_id': app.currentBranchId,\n        'employee_code': code.text.trim(),\n        'full_name': name.text.trim(),\n        'designation_code': designationCode,\n        'role_ids': if (roleId != null) [roleId],\n        if (reportingId != null) 'reporting_employee_id': reportingId,\n        if (mobile.text.trim().isNotEmpty) 'mobile': mobile.text.trim(),\n        if (email.text.trim().isNotEmpty) 'email': email.text.trim(),\n        'monthly_salary': double.tryParse(salary.text) ?? 0,\n        'joining_date': joining.text.trim(),\n      };\n"""
new_org = """      final payload = <String, dynamic>{\n        'assigned_branch_id': app.currentBranchId,\n        'employee_code': code.text.trim(),\n        'full_name': name.text.trim(),\n        'designation_code': designationCode,\n        'monthly_salary': double.tryParse(salary.text) ?? 0,\n        'joining_date': joining.text.trim(),\n      };\n      if (roleId != null) payload['role_ids'] = <int>[roleId!];\n      if (reportingId != null) payload['reporting_employee_id'] = reportingId;\n      if (mobile.text.trim().isNotEmpty) payload['mobile'] = mobile.text.trim();\n      if (email.text.trim().isNotEmpty) payload['email'] = email.text.trim();\n"""
if old_org not in org_text:
    raise SystemExit('organization compile-fix target not found; refusing silent patch')
org.write_text(org_text.replace(old_org, new_org, 1))

perf_text = perf.read_text()
needle = "import '../../core/providers.dart';\n"
insert = "import '../../core/providers.dart';\nimport '../../state/app_state.dart';\n"
if "import '../../state/app_state.dart';" not in perf_text:
    if needle not in perf_text:
        raise SystemExit('performance import anchor not found; refusing silent patch')
    perf_text = perf_text.replace(needle, insert, 1)
perf.write_text(perf_text)

print('PASS applied Flutter compile fix1: organization payload + performance app state import')
