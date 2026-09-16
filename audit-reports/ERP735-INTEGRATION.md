# ERP 7.3.5 correction integration

This branch builds on v740-business-completion at 91a26d7985a64560e980220e1023cb2f59d10b78, not the old archive-only main branch. The current office site is a development environment, per the owner.

Changes:
- Add the supplied 7.3.5-rc1 backend source and its 24 PHP regression cases under backend/excel-herbal-erp-v7.
- Add independent GitHub-hosted verification so the existing queued Windows self-hosted workflow is not the only way to test.
- Download private employee and candidate documents with the existing authenticated API client, validate the origin and route before sending credentials, use binary responses, refresh once on 401, and share/save bytes without putting tokens in a URL.
- Preserve legacy 7.3.4 public document handling; show a migration message where the backend flags old records.
- Add destination-validation and filename tests.

No website deployment, database migration, merge, salary update, document deletion or production release occurs in this workflow.

Known boundaries:
- Salary revisions in this backend candidate use /payroll/employees/{id}/salary-revisions. Existing proposed advanced compensation screens refer to /payroll/salary-structures and rewards/promotions contracts. These are different features: adding this backend does not implement those advanced contracts. Use the backend WordPress Payroll Controls page for the correction workflow until Flutter salary controls are integrated.
- Live WordPress integration, database concurrency, upload/download on real devices, restoration, and business policy acceptance remain required.
- Existing reports in backend/ describe the pre-CI candidate; GitHub checks for the exact commit are authoritative for actual execution results.
