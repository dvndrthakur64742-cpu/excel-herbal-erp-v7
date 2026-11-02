# Local Windows UAT — Attendance, GPS and Morning Stock (2026-11-02)

**Status:** Completed for the *first stock-request and independent-review slice* on isolated synthetic localhost, **not** the full inventory issue-to-sale workflow.

## Provenance and isolation

- Windows-native localhost: `http://127.0.0.1:18880/erp-uat/` — WordPress 7.1.4, PHP 8.3.36, MariaDB 10.11, plugin 7.3.10-rc2.
- **Tested/local deployed commit:** `2e40eba61d97ef26b543c631682d0701af75b3bd`. GitHub development branch has newer source. **Do not assume latest branch features are already local.**
- WordPress timezone changed on **local synthetic site only** from UTC to **Asia/Kolkata**. This matters: the scheduled GPS window is business-local 10:30–17:00. The plugin remains timezone-configurable; this test is Excel Herbal-specific, not a hardcoded global policy.
- Verified `staging`, synthetic seed, source marker and sanitizer before writes. The pre-stock-change local MariaDB dump and WordPress configuration snapshot were placed under `E:\ERP-Backups\eh7-local-post-login-before-stock-20261102`.
- No old employee, branch or product imports; no Railway changes, production office WordPress writes, or customer information. Geographic coordinates were **synthetic fixture values**, not a real employee tracking event.

## Live local backend acceptance evidence

| Check | Result |
| --- | --- |
| WordPress timezone `Asia/Kolkata`; 10:30–17:00 attendance window active at test time | **PASS** |
| Admin creates one dummy product and commercial revision; employee auto-attendance schedules without manual punch | **PASS** |
| Initial morning stock request **without GPS** rejected using `daily_attendance_required` and no daily cycle created | **PASS** |
| First **synthetic** duty GPS point matched to same attendance/company/branch/employee; first lat/lng projected | **PASS** |
| After GPS, employee can create request and submit cycle to `stock_requested` | **PASS** |
| Employee cannot review own stock request | **PASS** |
| Separate synthetic administrator can review request | **PASS** |
| Reviewer **cannot final-approve same request**; `maker_checker_required` and no issue ledger lines | **PASS** |
| Seven local Node safety checks and PHP syntax checks of 113 backend PHP files | **PASS** |

Final read-only local state: one dummy product, one GPS fixture point, one daily cycle, initial request **`reviewed`** and cycle **`stock_requested`**, **zero issued stock lines**, staging sanitized and synthetic seed remains valid.

The safety tests were executed through the actual PHP service classes on the isolated local WordPress/MariaDB database. They are **not** a claim that the Flutter/Android UI, BM's distinct identity, warehouse custody, cash/UPI collection or entire commercial business process has passed.

## Next focused acceptance slice

1. Create **independent synthetic SM/ASM and BM approver identities** with valid hierarchy and capabilities (current fresh UAT has only `SYSADMIN` and `EMPLOYEE` designations), then test REST maker → reviewer → approver. Never bypass maker-checker to fast-forward.
2. Seed *synthetic-only* branch inventory through the legitimate stock-opening/purchase route. Validate issue allocations, non-negative stock, employee acceptance and duplicate-event rejection.
3. Complete prepaid Cash/UPI receipt → invoice gating → evening returns and ledger settlement with branch-bound audit.
4. Run the same chain through Flutter Web and an authorized Android test device. Retain exact source commit and backup/restore gate before any promotion.

## Safety note

Do not simply `git pull` the D: checkout: the plugin directory is a junction to that working tree, and newer source must be reviewed together with migrations, backups and the `EH7_SOURCE_HEAD` / sanitizer marker before running on the persistent localhost database.
