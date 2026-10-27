# Employee 360 workspace — development batch, 24 October 2026

Replaces the profile's horizontal twelve-tab navigation with five permission-filtered groups. Existing API consumers, read-only records, controller indices, finance shortcuts and server authority remain canonical.

| Group | Canonical views | Default view |
| --- | --- | --- |
| Overview | Summary | Summary |
| Operations | Sales, Stock, Stock Requests, Daily Reconciliation | Sales |
| Finance | Finance Review, Person Ledger, Cash Control, Cash Responsibility, Journal Lines | Finance Review |
| People | Attendance | Attendance |
| GPS | GPS Route | GPS Route |

Finance exists only when the server profile exposes the ledger AND the actor has `finance.accounting.view`. GPS still requires `workforce.gps.team.view`. Journal Lines is the display label for the existing limited employee-tagged journal excerpt; it is not an additional ledger. No payroll/audit destination is invented without a working source screen.

At 840px and wider, a scrollable side panel exposes groups and the selected group's records. Below 840px, two bounded selectors replace horizontal scrolling. Selected destinations follow the original controller, including Finance Review callbacks; resizing preserves the current view. Swiping between unrelated registers is disabled. Permission changes recreate the controller through the existing permission-dependent screen key.

## Acceptance and remaining scope

Automated widget tests cover five widths (360, 390, 768, 840, 1366), 150% text, direct Finance Review opening, contextual ledger navigation, resizing, mobile selection, and removal of protected destinations. Existing API/scope contracts remain in the test suite. These are synthetic UI checks, not Office authentication or physical-phone acceptance.

This is the first profile-navigation implementation, not completion of the full role-based app shell or a signed-off visual redesign. Remaining: app-wide screen ownership and role workspaces, full profile content layout, authenticated role/device UAT, GPS backend compatibility and independently verified financial settlement. The prior 31.5/100 audit score is not automatically increased by this code change.

No financial schema, business writer, Office data or deployment is changed. Rollback is a source revert and rebuild; no database rollback is needed for this UI-only batch.
