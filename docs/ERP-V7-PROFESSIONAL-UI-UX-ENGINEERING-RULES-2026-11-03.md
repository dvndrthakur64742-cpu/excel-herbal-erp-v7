# Excel Herbal ERP — Professional UI/UX and Engineering Rules

Effective: 3 November 2026. Workspace: D:/ERP7-Development. Reference: appfixer.ai.studio for inspiration only; no copied UI, assets, code or branding.

## Mandatory workflow
1. **One source of truth.** Use the existing GitHub V7 development branch in D:/ERP7-Development. Check status, pull safely, modify shared components, test, commit only intended files and use CI. Do not start another ERP product or duplicate environment.
2. **Visual access first.** Fix the current Office ERP login/startup error, verify authenticated employee home, and reconcile Flutter/backend versions. A CI build or review ZIP is not a deployed user interface.
3. **Protected production.** Before any Office deployment require full files+database backup, tested restore, rollback, staging version checks, V7/V15 data ownership, authorized production approval. Do not activate the inactive V15 plugin or reset live records to force tests.
4. **One Excel Herbal design system.** Use shared ExcelBrand colors, typography, spacing, cards, inputs, buttons, navigation, loading/error/empty states. Use the reference site only as a benchmark for professional visual polish and user flows.
5. **Responsive, accessible UX.** Check 320/360/390px phones, 768px tablets, 960px navigation breakpoint, 1366px desktops, keyboard use, 200% text scale, screen reader labels, visible focus and at least 48px action targets.
6. **Every button must work.** No placeholders, decorative fake counts, silent exceptions or unverified success. All operations need loading, empty, validation, permissions, network failure, new-request retry, success and denied states.
7. **Business rules are authoritative.** Cash/UPI verified before invoicing; branch/Head Office discount authority; physical stock receipts; GPS attendance exceptions reviewed by Head Office; independent maker-checker for HR/payroll/rewards; audit and idempotency. Do not invent payouts or promotions.
8. **Backend owns permissions.** Client visibility never grants employee/branch/hierarchy authority. Reject unsupported endpoints and all unapproved financial or HR posting operations.
9. **Tests decide completion.** Node static UX checks + Windows quick QA + Flutter analyzer/widget/layout tests + PHP contracts + disposable MariaDB transaction tests + isolated WordPress. Unmet tests are release blockers, not warning labels.
10. **Separate delivery states.** Track source implemented, CI passed, role-based UAT passed and live deployed independently. API route parity and screenshot availability are not ERP completion percentages.
11. **English first in the application**, human-readable business labels and no raw internal IDs.
12. **Shared components before screen duplication.** Changes to one shared widget must benefit all screens and have regression tests.

## First implementation under these rules
- Shared AsyncPanel replaces eager already-started Future values with a lazy loader callback. Retry starts a new request and parent rebuild does not make duplicate network calls.
- 42 screen callsites migrated across Finance, HR, Sales, Inventory, Attendance, Reporting, Administration, Communication, Purchase and Performance.
- A Node gate rejects new AsyncPanel callsites that do not use fresh loaders; Flutter widget tests check retry and reload behavior.
- Zero live WordPress or financial data changes are permitted in this tranche.

## Definition of done by workstream
| Priority | Area | User acceptance proof |
|---|---|---|
| P0 | Login, startup, branch shell | Login, reconnect, expired session and accurate branch/role UI on phone and desktop |
| P1 | My Work, attendance, daily stock | Morning request, manager review, stock issue/receipt, evening close with correct pending/approved/denied states |
| P1 | Sales, purchase, inventory | Search, validate, reserve/receipt, prepaid approval, exact stock ledger and reversal |
| P1 | Organization / HR | Correct employee and branch scopes, reporting hierarchy, permissions and reviewer actions |
| P2 | Payroll, rewards, finance | Exact salary arithmetic, independent approvals and journals, reward payout never presumed paid |
| P2 | Reports, communication, admin | Usable filters, errors, audits, notifications, table/card responsive behavior |

A feature is not finished until an authorized user completes its end-to-end task against a compatible backend and the technical gates pass. Office deployment stays blocked without restore rehearsal and approval.
