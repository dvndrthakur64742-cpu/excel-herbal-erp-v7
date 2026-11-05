# Excel Herbal ERP V7 — 7.3.9-rc1 (Employee Picker API Integration)

## New authenticated GET endpoints
- `/performance/target-employees` — performance managers only
- `/communication/target-employees` — communication managers only
- `/daily/target-employees` — only self for daily.self, visible team for daily.others
- `/organization/hr/employee-choices` — HR manage/review, optional purpose=reporting|separation|candidate
- `/administration/acting-employees` — delegation manage
- `/administration/access-employees` — access manage, excludes own identity, reserved accounts filtered
- `/payroll/salary-employees` — granular salary view/manage/approve

All endpoints accept optional `branch_id`. They enforce the actor's company, role and effective branch/reporting hierarchy on the server. Empty authorised scope returns an empty array; selecting an unauthorised branch returns 403.

## Privacy
The shared `EmployeeChoiceService` returns only id, employee_code, full_name, designation_code, assigned_branch_id and reporting_employee_id. No mobile, email, salary, credentials or GPS coordinates appear in picker responses.

## QA
A synthetic regression verifies scoped projections, access-denied branches, self-only selection and all seven authenticated routes / dispatch bindings. Existing PHP 8.2/8.3 lint and regression suite must remain green.

## Security / release
No schema migrations or existing employee/customer data edits. Release candidate still requires isolated Railway UAT with verified source head, authenticated employee login, Flutter PHP compatibility gate, business rules and rollback before Production.
