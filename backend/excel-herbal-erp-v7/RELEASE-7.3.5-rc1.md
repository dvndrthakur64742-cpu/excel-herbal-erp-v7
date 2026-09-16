# ERP 7.3.5-rc1 — business logic correction candidate

Status: source patch / staging candidate. NOT production certified or deployed.
Based on the supplied v7.3.4 HR lifecycle candidate. Original production data has not been accessed or modified.

## Implemented

- Corrected full-month scheduled-working-day denominator for joining, separation, partial periods and branch allocations. Employee branch history must be unambiguous. Whole-month allocation uses cumulative cent rounding.
- Company weekly offs and company holidays determine the denominator; branch-specific holidays are paid eligible days. This is a documented working-day policy, not calendar-day/fixed-30 payroll. One payroll request must remain within one calendar month.
- Paid/unpaid leave types are explicit company configuration. Unknown approved leave types and attendance/leave conflicts stop generation rather than silently paying them.
- Same-branch overlapping payroll periods rejected. Payroll generation, salary approval, draft discard and transfer writes share a company lock. Backdated transfers intersecting generated employee payroll are blocked; concurrent transfer branch changes are detected.
- Approved effective-date salary revisions with independent checker and protected self-salary changes. Direct changes to existing employee monthly_salary must use the revision workflow. Initial employee creation still records onboarding salary.
- Migration records today's salary as a baseline from the migration date (or future joining date), NOT an invented historical salary. Prior salary needs an independently approved revision. Future-dated salary revisions are deliberately unsupported in this candidate.
- Historical salary is used in calculations and the fixed_salary snapshot; calculation inputs are stored in payroll_items.calculation_json.
- Payroll adjustment editors cannot approve the payroll they edited. Prior values are audited; deductions above earnings are rejected instead of silently clipping net salary to zero.
- Legacy draft approval is blocked. New discard action removes only unposted drafts and archives their contents in the audit trail. Regenerate with a new idempotency key. Already approved/paid payroll is NOT recalculated or corrected by this release.
- Employee edits are transactional and log old/new values. Joining date changes are blocked after payroll exists.
- Fixed missing DesignationDefaults import in OrganizationService, affecting employee creation/joining.
- New HR document uploads are AES-256-GCM encrypted in a private database table. Download requires an authorized, active ERP identity and active document status. No public WordPress attachment is created for new uploads. Direct linking of public media as employee documents is disabled.
- WordPress Tools > ERP Payroll Controls provides salary request/review, leave treatment configuration and legacy draft discard. WordPress login must map to an ERP employee with the relevant payroll/branch permissions; WordPress administrator status alone is not enough.
- Additive API endpoints. All 203 prior route definitions retained; 211 total.

## Companion Setup Assistant 1.7.1

Install the corrected assistant in staging first if the old assistant is installed. It checks the installed backend header before activation/upgrade alignment, and blocks downgrading backend/schema/web to bundled 7.1.11. On ERP >=7.3.4, the old assistant's write actions are intentionally read-only to prevent bypassing current business workflows. Its bundled old backend/web are retained but are not deployed over a newer backend.

## Mandatory staging validation before production

1. Back up plugin files AND the complete database; prove restore. Keep an independent backup of the document key option `eh7_document_key` with the database. Losing the key makes encrypted documents unreadable.
2. Use PHP 8.1+ with OpenSSL and fileinfo, InnoDB transaction support and a current compatible WordPress environment. For 10 MB private uploads, provision PHP upload limits and MySQL max_allowed_packet with adequate headroom (at least 32 MB recommended for this representation). Database growth must be monitored because documents are stored as base64 ciphertext.
3. Run `bash tests/run.sh`. This requires PHP; it has NOT run in the authoring environment.
4. Install on a staging copy; confirm schema `7.3.5-business-fixes-1`. New tables: salary_revisions, payroll_editors, private_documents. New columns: payroll_runs.calculation_version, payroll_items.calculation_json, both HR document tables.private_file_id. Inspect migration errors and verify baseline/key creation.
5. Confirm historical salary via request and independent approval. Configure exact paid/unpaid leave type names. Confirm working-day payroll policy matches the business before enabling corrected generation.
6. Discard and regenerate appropriate unposted legacy drafts. Review already approved/paid historical payroll separately with Accounts; do not delete or overwrite journals.
7. Exercise 21 payroll calculator cases and 3 service guard cases. Also run real MySQL concurrency tests for two overlapping generation requests, two transfer requests, transfer vs generation and salary approval vs generation. Controlled test doubles do not prove database concurrency behavior.
8. Test WordPress admin forms, actor/branch restrictions, REST auth/idempotency, migration twice, failed SQL rollback, new document upload/download, revoked users and inactive documents. Restore encrypted files and encryption key together in a recovery drill.
9. Test Flutter compatibility. Document URLs now need bearer/nonce-authenticated download and return binary content; Flutter must fetch with authorization and open a local/blob file. The latest Flutter source was not supplied and has NOT been updated. Legacy document URL can be null with migration_required=true.
10. Validate a pilot branch with HR and Accounts before production deployment.

## Legacy documents — unresolved exposure, explicit migration required

Existing WordPress media originals, thumbnails, CDN copies and previously shared links are NOT automatically removed. Their old public URLs may remain accessible. Listings suppress those URLs and flag migration_required, which does NOT revoke existing links.

Inventory all candidate/employee attachments and any other references. Authorized administrators should download/verify originals, re-upload through the private endpoints, compare the retrieved content to the original, then retire old document records. Delete original media and generated sizes/CDN copies only after checking other usages and obtaining the organization's deletion authorization. Re-test old URLs without login. This migration requires the actual hosting/media environment and cannot be completed from the supplied ZIP alone.

## API additions

Namespace: /wp-json/excel-herbal-erp/v7
Authenticated writes require X-Idempotency-Key, as before.

- GET/POST /payroll/policy — POST {"leave_types":{"CL":true,"LWP":false},"reason":"Approved leave treatment"}. GET requires payroll approve and all active branch authority; POST additionally access management.
- GET/POST /payroll/employees/{id}/salary-revisions — POST {"monthly_salary":30000,"effective_from":"2026-09-01","reason":"Verified salary opening record"}. Requires payroll generation and employee branch scope.
- POST /payroll/salary-revisions/{id}/review — {"approve":true} or false. Independent payroll approver in employee branch.
- POST /payroll/runs/{id}/discard — {"reason":"Regenerate legacy payroll draft"}. Only unposted draft, payroll generation permission.
- GET /organization/employees/{id}/documents/{document_id}/download — authorized employee document access.
- GET /organization/candidates/{id}/documents/{document_id}/download — authorized HR document access.

Full API metadata: API-CONTRACT-7.3.5.json.

## Verification actually completed here

- Source lexical delimiter scan: 58 PHP files, plus setup assistant. This is NOT PHP lint or syntax certification.
- Route uniqueness and dispatch mapping: 211 routes; all 203 original routes retained.
- Contract JSON and 21 fixture records parse successfully.
- Simple static class references resolve to local classes after the missing import fix.
- ZIP integrity and SHA-256 manifests checked during packaging.

NOT RUN: PHP lint, PHP regression execution, WordPress boot/migrations, real MySQL tests, browser/UI tests, restore drill, penetration/load tests. PHP was unavailable; package installation was blocked by the environment. No PASS claim is made for these.

## Beyond this correction candidate

No new end-to-end CRM, purchase-order/GRN system, manufacturing, advanced compensation/incentive engine, offline Flutter sync or performance optimization is claimed. Those require specific business rules, current client source and staging data. Several findings were coverage questions, not confirmed missing features; they have not been replaced with speculative modules.
