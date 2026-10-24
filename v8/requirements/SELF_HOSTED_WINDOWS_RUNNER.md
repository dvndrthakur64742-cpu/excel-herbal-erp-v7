# V8 Windows Self-hosted Runner — verified prerequisites (2026-10-19)

## Current evidence (GitHub Actions, not assumptions)
- Runner: DESKTOP-IBELGI9, Windows, connected. Checkout succeeds.
- Run 39208438581 failed on `shivammathur/setup-php@v2`: `pwsh` not present.
- Run 39208617517 failed: Windows PowerShell execution policy forbids loading generated `.ps1` scripts.
- Run 39208722545 used Windows `cmd` without policy changes, and definitively failed: `PHP CLI not on PATH`.
- Existing hosted `ubuntu-latest` test matrix still failed before runner allocation.
- No evidence of PHP regression test execution on self-hosted Windows, no MariaDB CI PASS.

## Supported remediation — owner action required on runner host
1. Install PHP 8.3 or 8.4 x64 CLI from official Windows PHP builds: https://windows.php.net/download/.
2. Add the directory containing `php.exe` to PATH *for the account running GitHub Actions runner*.
3. Open a new CMD (under the runner account where possible) and run `php -v`.
4. Restart the GitHub runner process/service so it picks up the changed PATH.
5. Push a change to this trusted development branch, or manually run the self-hosted workflow once available.

The self-hosted workflow intentionally does **not** download/install software or change the Windows execution policy. It uses `cmd` and verifies PHP before running eight V8 unit suites.

### Security guardrails
- Workflow targets **self-hosted Windows only**, triggered by push to the trusted V8 branch or manual dispatch; no arbitrary pull_request event.
- Checkout is read-only and uses `persist-credentials: false`.
- No deploy, DB mutation, privileged commands, global PATH changes or software installer in CI.
- Do not treat the Windows self-hosted unit workflow as MariaDB UAT or production approval.
- GitHub-hosted MariaDB integration checks remain separately required; a Windows self-hosted runner does not support GitHub Actions service containers like a Linux runner with Docker.

## Current development level
V8 remains approximately **15% estimated** overall completion. Local PHP regression tests: 192/192 PASS on a separate environment (PHP 8.4); runner-specific tests: blocked until PHP CLI is available. Real canonical journal/stock posting and WordPress API integration remain unimplemented.
