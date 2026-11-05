# Excel Herbal ERP V7 — 7.3.8-rc2 (Privacy & Access Controls)

## Scope (staging only)
Builds on 7.3.8-rc1 role/hierarchy safeguards with **granular sensitive-data capabilities**:
- `organization.employee.contact.view`
- `organization.employee.document.download`
- `organization.hr.document.download`
- `workforce.gps.team.view`
- `payroll.salary.view`, `payroll.salary.manage`, `payroll.salary.approve`

Role policy is fail closed: existing non-system roles do **not** silently inherit these new capabilities. Company administrators must explicitly grant them following branch/role review. Designated SYSADMIN receives them through existing system administrator defaults.

## Protected endpoints and data
- Employee list now masks phone, email and salary when corresponding explicit permission is absent.
- Employee and HR candidate private-document downloads require both existing branch/role checks and new document download permission.
- Peer GPS route and team-map access require `workforce.gps.team.view` in addition to the existing team attendance authority.
- Salary history, revision request and independent approval enforce their matching granular capabilities, on top of existing payroll permissions.
- Security tests use synthetic employees to check branch restrictions, privacy masking and denied access without salary/GPS permissions.

## Remaining release blockers
- Historical Flutter 7.4.0 source was imported from another branch; the previous integration audit still had 22 failing tests after 7.3.8-rc1. The current candidate requires a new full test run; old tests expecting automatically scheduled attendance **conflict with approved GPS check-in/check-out rules** and must be rewritten against the approved business policy, not implemented blindly.
- Railway UAT still runs an older plugin with routing/host-hardening issues and a destructive staged service change.
- Distributor price slabs, all-channel 100% verified prepayment, HO GPS exception workflow and end-to-end Flutter employee login are not yet verified as complete.

There are **no database schema migrations**, automatic employee/account changes or Production deployments in this candidate. Before live rollout, validate role grants on synthetic UAT; otherwise non-system managers may correctly receive 403 for sensitive screens until explicit roles are configured.
