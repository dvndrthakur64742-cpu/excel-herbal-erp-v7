# ERP v7 Hierarchy / Reporting Role Matrix — v7.3.2 checkpoint

Date: 2026-09-10

## Authority principles

- Primary designation + explicit roles/overrides + effective branch authority determine permissions.
- `reporting_employee_id` determines the actual recursive reporting tree used by ASM/SM employee visibility.
- `reporting_designation_code` is the current schema name for the optional Reporting Category override. Reporting Category is grouping only and never grants authority.
- Additional/Temporary Designations are responsibility labels only; authority inheritance is always false.
- GPS Team and GPS Route use the same hierarchy/branch privacy boundary as employee visibility.
- Price Distribution uses the actor's existing employee/branch scope; category filters cannot expand scope.
- v14 code/module/schema is not merged.

## Default role matrix

| Profile | Employee visibility | Home management overview | GPS Team | Price Distribution | Trial Balance |
|---|---|---:|---:|---:|---:|
| Field employee | Self only | No | No | No | No |
| ASM | Self + recursive reporting descendants inside authorised branches | Yes | Yes | Yes | No |
| SM | Self + recursive reporting descendants inside authorised branches | Yes | Yes | Yes | No |
| BM | All active employees in own branch | Yes | Yes | Yes | No |
| RM / RC | All active employees in explicitly authorised branches | Yes | Yes | Yes | Yes |
| AGM (v7.3.2) | All active employees in explicitly authorised branches | Yes | Yes | Yes | Yes |
| ZI | All active company employees; actor receives all active company branches | Yes | Yes | Yes | Yes |
| CM / MD | All active company employees; actor receives all active company branches | Yes | Yes | Yes | Yes |
| System Admin | All active company employees and branches | Yes | Yes | Yes | Yes |
| Accounting-only capability profile | No Team scope unless separately granted | No | No | No unless `reports.view` is also granted | Yes with `finance.accounting.view` |

Notes:
- The matrix describes designation defaults. Explicit roles and employee capability overrides may add or remove capabilities, but they do not bypass branch or hierarchy scope checks.
- Home management overview additionally requires both a projected Team workspace and `reports.view`.
- Reports Centre now filters operational reports behind `reports.view` and Trial Balance behind `finance.accounting.view`, preventing dead/forbidden report options for accounting-only users.

## v7.3.2 backend consistency correction

The hierarchy engine already classified `AGM` / `ASSISTANT_GENERAL_MANAGER` as `REGIONAL`, but v7.3.1 designation capability defaults omitted AGM. v7.3.2 adds AGM to the same least-privilege monitoring capability profile as the Regional management family while preserving explicitly-authorised-branch scope. AGM is not promoted to all-company branch authority.

## Live data readiness observation

The live v7.3.1 runtime is healthy, but reporting-manager master data is not yet fully configured. The branch audit found the active ASM/SM employees inspected currently have blank `reporting_employee_id` links. This is a business-data setup gap, not a hierarchy-engine bypass.

The Flutter Designation & Reporting workspace now exposes Reporting Manager separately from Reporting Category. Manager changes are explicit only and use the existing backend endpoint, which requires an audit reason and blocks self-reporting, cycles, inactive/nonexistent managers, and managers outside effective branch authority. No reporting manager is auto-assigned.

## Frontend correction checkpoint

- ERP Tools is no longer unconditionally exposed; route, desktop sidebar, drawer, and defensive bottom-navigation filtering use `erpToolsVisible`.
- Duty GPS has no manual Start/Stop UI; status refresh does not create a manual route lifecycle.
- Reporting Manager is managed separately from Reporting Category and Multiple Designations.
- Price Distribution retains exactly six business fields: Sale Price, HO Amount, BM Profit, Salary Fund, Expense, Points.
- Reports Centre options are capability-filtered.

## Certification status

Backend v7.3.2 static package QA:
- PHP lint: 51/51 PASS
- v7.3.2 correction invariants: 13/13 PASS
- source manifest: 77/77 PASS
- fresh-extract ZIP integrity: PASS

Flutter compiler/APK certification is still pending because current GitHub Actions runs are failing before runner steps begin. This must not be interpreted as a Dart compile failure or a compile PASS.
