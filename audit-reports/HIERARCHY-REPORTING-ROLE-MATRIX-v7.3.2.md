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
- Reports Centre filters operational reports behind `reports.view` and Trial Balance behind `finance.accounting.view`, preventing dead/forbidden report options for accounting-only users.

## v7.3.2 backend consistency correction

The hierarchy engine already classified `AGM` / `ASSISTANT_GENERAL_MANAGER` as `REGIONAL`, but v7.3.1 designation capability defaults omitted AGM. v7.3.2 adds AGM to the same least-privilege monitoring capability profile as the Regional management family while preserving explicitly-authorised-branch scope. AGM is not promoted to all-company branch authority.

## Live deployment verification

The connected office runtime is now running **Excel Herbal ERP 7 Clean Core v7.3.2**.

Verified live contract:
- `/health` reports `version=7.3.2`, `api_contract=7.3.2-contract-1` and the existing `7.3.0-hierarchy-gps-reporting-1` schema.
- `/bootstrap` reports the same `7.3.2-contract-1` feature contract.
- Price Distribution returns exactly: `sale_price`, `ho_amount`, `bm_profit`, `salary_fund`, `expense`, `points`.
- GPS Team returns server-owned duty state and explicitly reports `manual_start_allowed=false` and `manual_stop_allowed=false`.
- Fake/out-of-authority branches are rejected with `403 branch_forbidden` by both Price Distribution and GPS Team.
- Invalid reporting-category filters are rejected with `422 reporting_category_invalid`.

## Live hierarchy-data readiness

The hierarchy engine is active, but the current reporting-manager master data is not complete. Across the seven active branches inspected, **17 active ASM/SM employees currently have no `reporting_employee_id` link**. This is a business-data setup gap, not an authority bypass.

No reporting manager was guessed or auto-assigned. The Flutter Designation & Reporting workspace exposes Reporting Manager separately from Reporting Category. Manager changes are explicit only and use the existing backend endpoint, which requires an audit reason and blocks self-reporting, reporting cycles, inactive/nonexistent managers, and managers outside effective branch authority.

## Frontend correction checkpoint

- ERP Tools is no longer unconditionally exposed; route, desktop sidebar, drawer, and defensive bottom-navigation filtering use `erpToolsVisible`.
- Duty GPS has no manual Start/Stop UI; status refresh does not create a manual route lifecycle.
- Reporting Manager is managed separately from Reporting Category and Multiple Designations.
- Price Distribution retains exactly six business fields: Sale Price, HO Amount, BM Profit, Salary Fund, Expense, Points.
- Reports Centre options are capability-filtered and selects the first authorised report when the previous/default type is not allowed.
- Automated authority-projection tests cover additional-designation non-escalation, reports-only dashboard isolation, stale ERP Tools navigation filtering and zero-branch blocking.
- The pre-Flutter Python gate is read-only; CI no longer patches or commits source during a build.

## Certification status

Backend v7.3.2 static package QA:
- PHP lint: 51/51 PASS
- v7.3.2 correction invariants: 13/13 PASS
- source manifest: 77/77 PASS
- fresh-extract ZIP integrity: PASS

Flutter compiler/APK certification remains pending. GitHub Actions runs are currently failing before a runner starts (`steps=null`, no log blob), while GitHub's public Actions status is operational. This is not evidence of a Dart compile failure and must not be treated as a compile PASS either.
