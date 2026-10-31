# Excel Herbal ERP V7 — 7.3.8-rc1 (Staging / Security Hardening)

Base: V7/V15 field-sales staging candidate 7.3.7-rc1.

## Changes
- Explicit branch scope enforced for ZI/CM/MD and other senior designations, rather than silently granting whole-company visibility by title. Company-wide access remains available to designated system administrators.
- Access managers cannot change their own access or manage staff outside their hierarchy/branch.
- Reserved system administrator role codes cannot be created, freely reassigned or have their capabilities edited via regular role management.
- Role and direct capability grants cannot exceed the acting administrator's own effective capabilities.
- Reporting-manager updates check that both target and proposed manager are visible within the actor's authorised reporting hierarchy.
- Employee account provisioning is **opt-in** on creation. Existing WordPress accounts and employee links remain unchanged.
- New and edited monthly salary inputs reject non-numeric, negative, infinite and excessive values; existing salary changes continue to require the independent salary-revision workflow.
- Account Ledger API contract explicitly requires a positive account ID plus valid from/to dates.
- Automated synthetic PHP permission-scope and API-contract regression checks added.
- Plugin version 7.3.8-rc1, API contract 7.3.8-contract-1, with Git commit stamped into the CI-built review artifact.

## Migration impact
No database table or data migration. No employee credentials are reset or newly provisioned. Changes affect authorization and input validation only, so all role-based workflows must be tested on isolated synthetic UAT before release.

## Remaining blockers
The Flutter client was imported from a later, different branch and **24 cross-module compatibility tests were failing before this candidate**. A new run is required to measure any improvements. The GPS legacy tests reference an automatic 10:30–17:00 duty model, which conflicts with the approved GPS check-in/check-out and HO exception policy and must be reconciled, not rubber-stamped.

Railway UAT still runs a different older plugin and has unreviewed staged changes including a destructive service deletion. No Railway deployment or live WordPress changes were performed.

Do not deploy to production until Flutter/PHP integration, synthetic UAT login, business postings, backup and release gates all pass.
