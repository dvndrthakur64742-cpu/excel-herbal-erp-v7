# Excel Herbal ERP V7 — Free Windows-native developer setup

**Reviewed on:** 2026-11-02; **PC:** Windows 11 Pro, i3-8100 (4 cores), 16 GB RAM, 512 GB SATA SSD divided into C:/D:/E:. The C: partition had ~3.2 GB free; D: ~180 GB, E: ~169 GB. BIOS virtualization was reported disabled, and WSL, Docker, PHP and Flutter were absent. Git, Node.js, VS Code and Android Studio/SDK were present. This makes a **native** Windows stack a better first step than installing WSL2/Docker/Android Emulator.

## Free software and storage layout

| Role | Free tool | Suggested path |
| --- | --- | --- |
| Source + versioning | Existing Git for Windows / VS Code | `D:\ERP7-Development` (already cloned; old C: checkout retained) |
| PHP/Apache/MariaDB | [Official XAMPP for Windows](https://www.apachefriends.org/download.html) | `D:\xampp` |
| Local synthetic WordPress | [WordPress](https://wordpress.org/download/) and [WP-CLI](https://make.wordpress.org/cli/handbook/guides/installing/) | `D:\xampp\htdocs\erp-uat` |
| Flutter SDK | [Official Flutter installer / VS Code extension](https://docs.flutter.dev/install) | `D:\tools\flutter` |
| Android testing | Existing Android Studio SDK plus a USB Android phone | Prefer a real phone over an emulator on this 4-core PC |
| Local exports and backups | Windows file storage, no cloud bill | `E:\ERP-Backups` |
| Automated CI | GitHub Actions, existing PR workflows | Public repository; keep only **synthetic** data and no credentials |

XAMPP's official Windows bundles may ship an older PHP than production. It is a **local-only developer stack**, never public hosting. The existing GitHub CI checks PHP 8.2 and 8.3, WordPress/MariaDB transactions, and Flutter, and remains the release gate. Official XAMPP warns its default install is **not hardened for production**; configure it for loopback-only access before any login or sample data.

### Phase A — what has been prepared automatically
1. Clean GitHub clone created at `D:\ERP7-Development`. Nothing deleted from `C:\Users\intel\ERP7-Development`.
2. `uat/windows/doctor.ps1` reports exact readiness and missing tools, without changing system settings.
3. `uat/windows/run-tests.ps1` runs native PHP lint when installed, Node recovery-safety contract tests, and Flutter tests when installed.
4. `.vscode/tasks.json` provides **Terminal → Run Task → ERP: Quick Tests**, or `Ctrl+Shift+B` if remapped. In VS Code, **Terminal → Run Test Task** runs the default quick suite.
5. GitHub PR already triggers the three CI workflows automatically; no paid server needed for that. GitHub Actions usage is free for standard hosted runners on public repos under GitHub's current rules. Private repo usage is quota-limited.

### Phase B — install required native runtimes (requires user interaction)
1. Preserve a backup; **free C: disk space to at least 10–15 GB without automatically deleting personal files**. Download/install programs and project caches on D:, not C:.
2. Download XAMPP **only from Apache Friends**, and choose `D:\xampp`. Start only **Apache and MySQL/MariaDB** from its control panel. No FileZilla, Mercury, Tomcat, public tunnel or port forwarding.
3. **Before allowing other devices on the network**, edit `D:\xampp\apache\conf\httpd.conf`: bind the HTTP listener to `127.0.0.1:18880` (replace its old `Listen 80` line) and set `ServerName 127.0.0.1:18880`. Disable any unneeded public SSL listener on `:443`. In `D:\xampp\mysql\bin\my.ini`, bind MariaDB to `127.0.0.1` under `[mysqld]`. Verify using `Get-NetTCPConnection -State Listen`; never expose DB port 3306 to the LAN. Secure MariaDB root and create a **separate** local-only ERP database user with a strong unique password.
4. Download WordPress from WordPress.org and install a **new synthetic-only site** in `D:\xampp\htdocs\erp-uat` using the local MariaDB. Its web URL will be `http://127.0.0.1:18880/erp-uat` and `wp-admin` under the same prefix. Never import WordPress or employee backups from `office.excelherbal.in`.
5. In `wp-config.php`, set `WP_ENVIRONMENT_TYPE` to `staging` and `DISALLOW_FILE_EDIT` to `true`. Keep `WP_DEBUG_DISPLAY` false and use a local-only debug log. Include the Git HEAD SHA as `EH7_SOURCE_HEAD` after checking the exact release's safety requirements. Connect only this reviewed V7 plugin under `wp-content/plugins`; do not activate V15 on a new UAT clone.
6. Install the free Flutter SDK from flutter.dev in `D:\tools\flutter`. Use the **existing Android SDK** with Flutter; a USB Android phone is preferable to a 16-GB-RAM emulator. Use a separate PowerShell terminal session with `$env:PUB_CACHE='D:\ERP-Caches\pub'; $env:GRADLE_USER_HOME='D:\ERP-Caches\gradle'` when building to keep caches off C:.
7. Verify the WordPress REST health endpoint, startup, synthetic user login, stock/discount/payment/settlement and branch role isolation. Each successful test is recorded in [issue #29](https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/issues/29). **Do not claim real UAT passed merely because native tools were installed.**

### Phase C — everyday fast workflow

From a PowerShell terminal in `D:\ERP7-Development`:

```powershell
# Hardware/tool readiness (no system changes)
powershell -NoProfile -ExecutionPolicy Bypass -File .\uat\windows\doctor.ps1

# Fast pre-commit checks: Node security contracts + PHP lint if PHP exists
powershell -NoProfile -ExecutionPolicy Bypass -File .\uat\windows\run-tests.ps1 -Mode quick

# Once Flutter SDK is on D:
powershell -NoProfile -ExecutionPolicy Bypass -File .\uat\windows\run-tests.ps1 -Mode flutter

# All checks (once toolchain installed)
powershell -NoProfile -ExecutionPolicy Bypass -File .\uat\windows\run-tests.ps1 -Mode all
```

Commit in small batches. Let GitHub Actions automatically run the full PHP/MariaDB, isolated WordPress and Flutter gates on the same PR. **Only reviewed, green commits** become installable staging candidates; live deployment remains separately approved.

### Automation and cost controls

- Use VS Code tasks for one-click tests; GitHub Actions for cross-version and real MariaDB integration.
- Store WordPress test credentials **only locally**, not in a public GitHub repository, issue or CI log.
- Back up the **synthetic UAT database** plus plugin release artifacts to E:, and test restore before migration. Windows Task Scheduler can run locally after backup jobs are audited; the PC must be powered on.
- No Railway paid upgrade, new cloud server, Docker Desktop license, domain or remote-tunnel service is required for **local development**.
- **Limitations:** a localhost site is not visible publicly or on a different phone without an explicitly secured networking plan; production still requires existing live hosting, tested migration and release approval. The currently prepared `uat/local/compose.yml` requires Docker and is not the preferred path while BIOS virtualization remains unavailable.

### Running the actual local ERP employee login smoke

The local site has been created using **WordPress 7.1.4 / PHP 8.3.36 / MariaDB 10.11** at `http://127.0.0.1:18880/erp-uat`. Only synthetic users may be used. Before running, check that the official WordPress package hash matches, the ERP staging health is sanitized/seeded, and the exact source Git SHA is pinned in `wp-config.php`.

The operator's synthetic local credentials are kept in `D:\ERP-Local-Secrets\local-uat-app.json` (outside Git and with user-only filesystem ACLs). The script reads the file without printing secrets or tokens; do **not** upload or paste it. Never use live/real employee credentials.

```powershell
cd D:\ERP7-Development
node .\uat\windows\local-auth-smoke.mjs
```

Or open VS Code **Terminal → Run Task → ERP: Local Synthetic Login UAT**. Tests include localhost-only health and source verification, denial of anonymous/wrong-password access, synthetic mobile login and Flutter bootstrap, refresh-token rotation and replay denial, logout, administrator branch-scoped sales/payment lookups, and final session cleanup. **Executed on the authorized Windows PC (2026-11-02):** all localhost synthetic-login checks passed on the pinned local source `2e40eba61d97ef26b543c631682d0701af75b3bd`: incorrect login/anonymous denial, login, bootstrap, refresh rotation, token replay rejection, logout/revocation, branch-scoped sales/Cash/UPI and session cleanup. The development branch has since advanced; never silently substitute its head for the pinned local UAT release.

**Source pin caution:** New GitHub commits are not automatically the locally deployed PHP source. `git pull` can alter the plugin's junction target. Before updating the local UAT checkout, back up its synthetic database, review migrations and intentionally update `EH7_SOURCE_HEAD` and staging markers for the new tested commit. Do not bypass the source-match guard or import production records.

### Start the localhost ERP with one VS Code task

In VS Code, open the reviewed D: workspace, then **Terminal → Run Task → ERP: Start Local ERP**. This calls `uat/windows/start-native-uat.ps1`. It checks that existing Apache and MariaDB ports belong to the localhost-only D: binaries; starts them if stopped; verifies the live localhost ERP staging/synthetic/source-matched health endpoint; then opens the local WordPress admin page. **Script passed an actual Windows localhost test on 2026-11-02** using `-NoBrowser`. It does not start Windows services or expose ports to the LAN.

The local UAT is on `http://127.0.0.1:18880/erp-uat/wp-admin/` and is accessible only from the same Windows PC. The script checks the application's existing configured source marker, not that the current GitHub branch is deployed. After any Git pull, review the exact commit and migration/marker compatibility before starting again.

### Source-accurate Windows UAT checkpoint (2026-11-04)

**Do not equate a green WordPress Health source flag with the loaded plugin's Git source.**
The Windows plugin mount is a junction to `D:\ERP7-UAT-Pinned\plugin\excel-herbal-erp-v7`,
separate from the working tree at `D:\ERP7-Development`. The launcher now reads
the *mounted checkout's* real Git SHA and fails closed if it differs from the
WordPress `EH7_SOURCE_HEAD` / Health marker. This check is required before
source-certified Login, Sales or Payroll acceptance.

A read-only audit found mounted Git `3faa0f213f58e17a12927a042a21abd3e870d729`,
whereas the WordPress Health marker was still
`2e40eba61d97ef26b543c631682d0701af75b3bd`. The latter is an ancestor
of the former, not the current checked-out source. The new development branch
is newer still. The mismatch is **not** repaired by editing a marker or by
pretending earlier dummy login tests prove the current build.

Before a reviewed source migration, create an **actual local synthetic database
checkpoint** with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uat\windows\backup-native-uat.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\uat\windows\backup-native-uat.ps1
```

The tool refuses non-loopback WordPress/MariaDB listeners, non-synthetic health,
active sessions, nonlocal database targets, dirty/mislinked plugin checkouts and
missing E: backup storage. It intentionally permits a stale source marker
**only for a backup**, and records both distinct SHA values in a manifest.
The dump, its SHA256, WordPress config and release-blocking manifest stay in a
private `E:\ERP-Backups\eh7-synthetic-checkpoint-*` folder. Never upload
these files to GitHub or share the config/SQL because they contain local secrets.
Temporary MariaDB client options are deleted even after failure.

**Local checkpoint evidence:** the synthetic database `eh7_local_uat` was
successfully dumped to E:, 253744 bytes, with a manifest and hash verification.
The checkpoint was not restored into an isolated clone, so this is **not**
restore approval or authorization to deploy. Leave the original localhost UAT
unchanged until migration impact, schema, synthetic identity pins and verified
rollback have been reviewed. Office WordPress was not touched.


### Verified disposable MariaDB restore rehearsal (2026-11-04)

To verify that a synthetic localhost checkpoint is restorable, not merely
hash-valid, run these commands on the authorized Windows PC:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uat\windows\restore-native-uat.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\uat\windows\restore-native-uat.ps1
~~~

The tool reads a local-only administrator password from user-restricted
D: secrets without printing or committing it. It confirms sanitized, idle
synthetic WordPress, exact E: checkpoint path, dump SHA-256/size, original
DB identity and SQL without cross-database switching. It creates a NEW
random database with prefix eh7_restore_, without IF NOT EXISTS.
Existing databases are never overwritten. The original eh7_local_uat is
only read, never restored over. It compares the complete table inventory
and COUNT(*) of every table, checks original counts are unchanged, and
verifies WordPress Health source marker is still unchanged. Temporary
credentials are deleted. Failed isolated imports are preserved for
manual investigation (never automatically DROP a database).

Actual Windows evidence: E:\ERP-Backups\eh7-synthetic-checkpoint-20261103-195121
was restored into eh7_restore_5ec7b1894f7a and 97/97 WordPress+ERP
table row counts matched the original, with no count discrepancies.
The private restore-rehearsal.json confirms isolated_restore_verified=true
and production_restore_verified=false. The original local WordPress
source mismatch is STILL BLOCKED for software acceptance.

This proves isolated synthetic database import and table-count parity,
not the complete Hostinger site/files/restore, financial transactions,
the latest GitHub code release, or production-readiness. Updating
EH7_SOURCE_HEAD or plugin migrations requires separate isolated
WordPress/Flutter acceptance and authorized user identity verification.
Existing restore-rehearsal reports cannot be overwritten.
