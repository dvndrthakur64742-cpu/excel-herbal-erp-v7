# Excel Herbal ERP V7

Clean V7 greenfield source repository. Canonical runtime: clean EH7 backend + Flutter client. Old V4/V5/V6 runtime code is not part of this repository.

## ERP V7 progress and current status

**Automated development checks (live GitHub Actions badges):**

[![PHP and MariaDB](https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/actions/workflows/erp-v7-quality.yml/badge.svg?event=pull_request)](https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/actions/workflows/erp-v7-quality.yml)
[![Flutter UAT](https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/actions/workflows/erp-v7-flutter.yml/badge.svg?event=pull_request)](https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/actions/workflows/erp-v7-flutter.yml)
[![WordPress UAT](https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/actions/workflows/erp-v7-uat-image.yml/badge.svg?event=pull_request)](https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/actions/workflows/erp-v7-uat-image.yml)

**[Open the live development progress tracker (Issue #29)](https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/issues/29)**

| Gate | Current status |
| --- | --- |
| Source development | [Draft PR #28](https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/pull/28) — ongoing |
| PHP / MariaDB / Flutter / isolated WordPress CI | Latest verified development commit passed |
| Persistent Railway UAT | **Blocked / offline** — destructive staged patch must not be applied |
| Live office ERP | **Earlier version; new changes not deployed** |

**Code Complete ≠ UAT Verified ≠ Live Deployed.** The progress tracker links to the latest checked evidence and the approved two-stage implementation plan. Never treat a passing synthetic CI check as an employee login or production release sign-off.

