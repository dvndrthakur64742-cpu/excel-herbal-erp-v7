# Excel Herbal ERP v7.4.0 — Final Role-by-Role UAT Matrix

Status: **BUILD/UAT acceptance plan — not production approval**

This matrix consolidates the existing automated CI, staging release gates, hierarchy/privacy model, and manual browser/device acceptance work. Production approval remains fail-closed in `release-gates/v7.4.0.json`.

## Authority model under test

Acceptance is based on **effective capability + authorised branch + reporting hierarchy**, not designation name alone.

- Designation supplies the baseline capability profile.
- Explicit roles/overrides may grant or deny capabilities.
- Branch authority limits where the capability can be exercised.
- Reporting hierarchy limits which employees may be listed, selected, viewed, or targeted.
- Backend authority is mandatory; hidden buttons are only defence-in-depth.
- Maker/checker actions must remain segregated even when one designation has both create and approve capabilities.

## Test identities

Use synthetic BUILD/UAT identities only.

| Identity | Effective authority to exercise | Primary purpose |
| --- | --- | --- |
| UAT Employee / FE | Base self-service capabilities | Self-only visibility and actions |
| UAT ASM/SM | Team supervision + hierarchy scope | Descendant-only team management |
| UAT BM | Branch operations | Full branch flow without cross-branch leakage |
| UAT HR Reviewer | HR view/review only | Candidate review without access/salary escalation |
| UAT HR Manager | HR manage + review | Candidate/joining/separation lifecycle |
| UAT Finance Maker | Transaction creation only | Maker/checker segregation |
| UAT Finance Approver | Approval/accounting permissions | Approval without unauthorised creation |
| UAT Regional/Executive | Multi-branch oversight | Authorised-branch read/review scope |
| UAT System Admin | All capabilities | Access-management and system-level controls |

Custom identities must be created from **effective capabilities**, not by assuming every designation has every row above.

## Automated acceptance gate

The normal `ERP correction verification` CI must be green on the exact PR head.

Required automated evidence:

- PHP lint + regression suite.
- Route/API contract checks.
- Disposable MariaDB 11.8.9 integration.
- Transaction rollback/commit/savepoint safety.
- Idempotency and concurrency tests.
- `integration_uat_smoke.php` full business smoke.
- Flutter dependency lockfile, Analyze, Tests and Production Web compile.
- Exact-head web SHA-256 manifest/candidate.

The UAT smoke must also prove segregation of duties:

- self-service Daily Order actor cannot approve its own request without approval authority;
- transfer creator without `inventory.transfer.receive` cannot receive the transfer;
- expense maker without `finance.expense.approve` cannot approve the expense;
- payroll generator without `payroll.approve` cannot approve the run;
- payroll generator without `payroll.pay` cannot pay the run.

## Manual browser UAT — role × workflow

Record PASS/FAIL, tested identity, branch, build SHA, timestamp, and screenshot/evidence for every row.

| ID | Role | Workflow | Expected acceptance |
| --- | --- | --- | --- |
| AUTH-01 | Any active user | Valid login → bootstrap | Login succeeds; business date/timezone/API contract present |
| AUTH-02 | Any | Wrong password/token | 401; no authenticated ERP data rendered |
| AUTH-03 | Any | Logout/revoke | Token unusable afterwards |
| AUTH-04 | Limited user | Protected action without capability | 403; session remains authenticated |
| BR-01 | Single-branch user | Branch selector/navigation | Only authorised branch data visible |
| BR-02 | Multi-branch manager | Switch authorised branches | Data/actions follow selected authorised branch |
| BR-03 | Any limited user | Crafted request to unauthorised branch | Backend 403 |
| EMP-01 | FE/Employee | Home/Profile/My Work | Only self-service sections/actions visible |
| EMP-02 | FE/Employee | Attendance check-in/out | Own attendance only; valid business date |
| EMP-03 | FE/Employee | Leave/field visit | Own requests only |
| EMP-04 | FE/Employee | Daily Order | Own cycle only; cannot approve/issue/final-post own request |
| TEAM-01 | ASM/SM | Team employee lists | Only self + reporting descendants inside authorised branches |
| TEAM-02 | ASM/SM | Crafted hidden employee ID | Backend rejects hierarchy bypass |
| TEAM-03 | ASM/SM | Daily Order Others | Eligible hierarchy picker; hidden employees absent |
| BM-01 | BM | Sales counter sale | Stock cannot oversell; invalid paid amount remains in dialog |
| BM-02 | BM | Customer receipt | Receipt cannot exceed outstanding amount |
| BM-03 | BM | Purchase bill | Required batch/cost validation remains in dialog |
| BM-04 | BM | Supplier payment | Payment cannot exceed outstanding bill |
| BM-05 | BM | Stock transfer | Create/pack/dispatch/receive state machine enforced |
| BM-06 | BM | Cross-branch transfer outside authority | Backend 403 |
| BM-07 | BM | Expense create + approve own expense | Own approval rejected by maker/checker rule |
| HR-01 | HR Manager | Candidate register | HR designation master loads without EMP_VIEW dependency |
| HR-02 | HR Reviewer | Candidate review | Review allowed only with HR_REVIEW; mutations outside capability hidden/403 |
| HR-03 | HR Manager | Confirm joining | Reporting manager picker hierarchy-scoped |
| HR-04 | HR Manager | Salary field | Visible/sent only with `payroll.salary.manage` |
| HR-05 | HR Manager | Employee creation | Extra security Role hidden unless `administration.access.manage` |
| HR-06 | HR Manager | Employee creation | Login is **not** auto-provisioned; credentials issued separately |
| HR-07 | HR Manager | Separation | Only manageable hierarchy employees selectable; direct-ID bypass rejected |
| HR-08 | HR document admin | Private HR document | Authenticated download only; deactivate/revoke blocks later download |
| FIN-01 | Finance Maker | Expense create | Create succeeds; maker cannot approve without approval capability |
| FIN-02 | Finance Approver | Expense decision | Approval creates balanced journal |
| FIN-03 | Finance role | Bank reconciliation line | Invalid debit/credit/date stays in dialog; valid line imports |
| FIN-04 | Period manager | Close accounting period | Invalid range stays in dialog; closed period blocks later postings |
| FIN-05 | Finance/Accounts | Reversal flow | Maker/checker and source linkage preserved |
| PAY-01 | Payroll Generator | Generate payroll | Draft run created; generator cannot approve without PAYROLL_APPROVE |
| PAY-02 | Payroll Approver | Approve payroll | Approved only once; no self-escalation |
| PAY-03 | Payroll Payer | Pay payroll | Payment account/date valid; posted journal balanced |
| PERF-01 | Performance Manager | Create target | Employee picker reporting-hierarchy scoped |
| PERF-02 | Performance Manager | Approve target | Direct hidden employee targeting rejected |
| COMM-01 | Communication Manager | Task/notification employee picker | Reporting-hierarchy scoped without EMP_VIEW dependency |
| COMM-02 | Communication Manager | Task list/reassign | Hidden employees/tasks outside hierarchy not exposed |
| ACT-01 | Delegation Manager | Acting Duty | Delegate/delegator must be inside reporting authority |
| ACT-02 | Delegation Manager | Revoke delegation/unavailability | Direct-ID hierarchy bypass rejected |
| ACCESS-01 | Access Manager | Employee access picker | Only manageable employees exposed |
| ACCESS-02 | Access Manager | Capability grant/deny | Cannot use UI/API to escalate beyond designed authority |
| ACCESS-03 | Non-access HR/manager | Role/access controls | Security role controls absent and backend rejects access mutation |
| REPORT-01 | Reports/Accounts | Sales/Purchase/Stock/Finance snapshot | Totals reconcile with controlled transactions |
| REPORT-02 | Accounts | Trial Balance | Total debit = total credit |
| REPORT-03 | Accounts | Receivables/Payables | Match controlled outstanding transactions |
| UX-01 | All roles | Long names/statuses/empty states | No raw backend codes, IDs, escaped interpolation, or overflow blocking actions |
| UX-02 | All transaction roles | Invalid form input | Dialog stays open, inline error shown, entered data preserved |

## Physical/mobile UAT

These remain manual/external release gates and are not replaced by browser CI.

| ID | Test | Required result |
| --- | --- | --- |
| MOB-01 | Physical Android install/login | Controlled staging API only |
| MOB-02 | Location off / denied / denied forever | Clear blocked state; no fake check-in |
| MOB-03 | Permission granted + check-in | GPS point accepted and duty tracking starts |
| MOB-04 | Background/resume | Tracking/sync remains correct |
| MOB-05 | Checkout / cutoff / logout | Duty tracking stops as designed |

## External release-gate evidence still required

The following are **not** considered passed merely because code CI is green:

1. Fresh isolated UAT backup + restore + matching `eh7_document_key` recovery.
2. Explicit staging environment hardening/preflight.
3. Real HTTPS Bearer login/refresh/401/403/revoke smoke.
4. Physical Android GPS pilot.
5. Real multipart private HR document upload/download/revocation.
6. Accounts/operations report reconciliation.
7. Operational owner + HR + Accounts sign-off.

Use the existing workflows/templates under `.github/workflows`, `.github/scripts`, and `release-gates/templates`. Do not change `production_approved` until all required manual gates have real evidence.

## Execution order

1. Exact-head CI green.
2. Employee self-service and hierarchy-negative cases.
3. ASM/SM/BM browser flows.
4. HR lifecycle and private-data checks.
5. Sales/Purchase/Inventory/Finance maker-checker flows.
6. Payroll/Performance/Communication/Delegation/Access checks.
7. Accounts report reconciliation.
8. Isolated UAT backup/auth/document/Android external gates.
9. Sign-off.
10. Only then consider PR finalisation and any production approval separately.

## Exit criteria

Final UAT is complete only when:

- every applicable matrix row is PASS;
- every expected-denial row returns the intended 401/403/409 without leaking protected data;
- no negative stock or unbalanced posted journal exists;
- no role can see/select/modify an employee outside effective hierarchy/branch authority;
- manual release gates have evidence attached;
- known limitations are documented and accepted by the sign-off roles.
