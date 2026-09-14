# ERP 7 Acting Duty / Delegation / Fallback Authority Contract v1

This contract extends the current ERP 7 hierarchy without changing the permanent identity model.

## Non-negotiable identity rules

- Primary designation remains the permanent authority-bearing designation.
- Reporting category remains grouping only and never grants authority.
- Extra/temporary designation remains display/work-assignment only and never grants authority by itself.
- Reporting Manager remains a permanent reporting relationship; delegation must not rewrite it.
- Delegation must not write employee roles, capability overrides, branch-authority rows, designation rows, or reporting-manager rows.

## Delegation grant

Every grant must contain:

- delegator employee id;
- delegate employee id;
- exactly one branch id;
- exactly one action/capability code;
- start datetime;
- end datetime;
- mandatory business reason;
- active/revoked state;
- created by / created at;
- revoked by / revoked at / revoke reason when cancelled.

The delegator must own the exact action in the exact branch at creation time. Runtime use must also fail closed if the delegator no longer owns that authority.

Self-delegation is forbidden. The delegate must be an active employee. Overlapping active grants from the same delegator for the same branch/action are forbidden.

## Runtime exercise

A delegated action is allowed only when all of these remain true:

1. grant is active;
2. current timestamp is inside the grant window;
3. acting employee is the exact delegate;
4. requested branch is the exact delegated branch;
5. requested action is the exact delegated action;
6. delegate is still an active employee;
7. delegator still has the underlying branch/action authority;
8. maker-checker separation is preserved;
9. normal transaction/business guards still pass.

A delegation for `daily.final_post` does not grant `daily.issue`, finance, stock, reports, employee-management, or generic branch access.

## Automatic fallback

Automatic fallback is separate from explicit delegation.

It can activate only when the primary authority is genuinely unavailable according to server-owned attendance/leave/manual-unavailability state. A manual `available` flag must never override an attendance/approved-leave block.

Automatic fallback:

- stays inside the same branch;
- considers only employees who already own the exact action through permanent authority;
- excludes unavailable employees;
- excludes the transaction maker when maker-checker applies;
- selects the highest eligible senior authority deterministically;
- creates no role, designation, branch authority, reporting-manager or capability mutation.

Cross-branch automatic fallback is forbidden. Cross-branch acting authority requires an explicit time-bound exact-action delegation.

## Required backend persistence

Recommended canonical table: `eh7_acting_delegations`.

Minimum logical columns:

- `id`
- `company_id`
- `delegator_employee_id`
- `delegate_employee_id`
- `branch_id`
- `action_code`
- `starts_at`
- `ends_at`
- `reason`
- `status` (`active`, `revoked`, `expired`)
- `created_by`
- `created_at`
- `revoked_by`
- `revoked_at`
- `revoke_reason`

Recommended indexes:

- company + delegate + status + starts_at + ends_at;
- company + delegator + branch + action + status;
- company + branch + action + status.

## Required REST contract

The canonical backend should expose server-filtered routes equivalent to:

- `GET /administration/delegations`
- `POST /administration/delegations`
- `POST /administration/delegations/{id}/revoke`
- `GET /administration/authority-status` for explainable current authority/fallback diagnostics.

Creation/revocation must require a dedicated authority-management capability and an authorised branch. Listing must be scope-filtered; ordinary employees may see only their own active/incoming delegation summary when needed by the UI.

## Audit requirements

Create, revoke, reject, and delegated-use events must be audit logged with:

- delegation id;
- delegator;
- delegate;
- branch;
- action;
- transaction/source id when applicable;
- reason;
- effective window;
- actor actually performing the mutation.

## UI rules

- Administration may manage acting duty only when the backend advertises the delegation routes/capability.
- Employee/Profile may show `Acting Duty` as informational state only.
- UI must never locally convert a temporary designation into authority.
- UI must display the exact action, branch and expiry; never label delegation as generic `Branch Access`.

## Current implementation stage

The Flutter-side policy engine and regression tests lock these fail-closed rules before backend mutation wiring. Backend deployment must use the current canonical ERP 7 source; an older backend package or legacy implementation must not be merged over the live v7.3.2 runtime.
