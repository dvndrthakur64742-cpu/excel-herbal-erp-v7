# Flutter v7.4.0 Certification Blocker — 2026-09-10

## Current status

The requested ERP v7 hierarchy/reporting/GPS/Price Distribution/role-dashboard correction scope is source-complete on branch `v7-hierarchy-gps-reporting-dashboard`.

Flutter release certification is the only remaining gate: invariant checks -> API-path/backend contract check -> `flutter pub get` -> `flutter analyze` -> `flutter test` -> debug APK -> SHA256 artifact -> device visual UAT.

## GitHub-hosted runner evidence

Controlled probes were executed with different GitHub-hosted Linux runner labels, followed by a later re-run attempt.

### Standard runner probe

- Workflow run: `34486920153`
- Job: `102903441436`
- Runner label: `ubuntu-latest`
- Result: failure before job execution
- Job payload: `steps=null`
- Job logs: no log URL/blob

### Slim runner probe

- Workflow run: `34498125506`
- Initial job: `102941721000`
- Runner label: `ubuntu-slim`
- Result: failure before job execution
- Job payload: `steps=null`
- Job logs: no log URL/blob

### Later re-run attempt

- Workflow run: `34498125506`
- New job created by re-run: `102982204766`
- Result: failure before job execution
- Job payload after completion: `steps=null`
- Job logs: no log URL/blob
- Check-run metadata reports one annotation (`annotations_count=1`), but the connected repository API does not expose the annotation text endpoint.

Because none of these jobs reached their first workflow step, these failures are not Flutter/Dart compile failures and are not test failures. They indicate a GitHub-hosted runner allocation/account gate before execution. GitHub public status reported Actions operational on 2026-09-10, so no shared Actions incident was identified during the latest retry. The exact account-side billing/quota/policy cause is not exposed through the connected repository API and must not be guessed.

## Local build fallback evidence

The available execution container was also checked as a fallback build environment.

- OpenJDK 21 is available.
- Flutter executable: not installed.
- Dart executable: not installed.
- Android SDK/ADB: not installed.
- No usable Flutter SDK archive is present in the Project/Library files.
- A Flutter 3.47.2 Linux SDK archive was identified through the official/mirror release listings, but the available container download/network paths could not retrieve the ~1.5 GiB SDK bundle.
- Outbound shell DNS/package access is unavailable, so Flutter/Android SDK bootstrap cannot be completed from this container.

Therefore the current container cannot replace the unavailable GitHub-hosted runner for APK certification.

## Repository safety state

After the controlled probes:

- temporary push trigger files were removed;
- certification workflow was restored to `workflow_dispatch` only;
- workflow permission remains `contents: read`;
- workflow performs no source commit/push or release mutation;
- default runner is restored to `ubuntu-latest`;
- v14 code/module/schema remains excluded from v7.

## Unlock condition

Once GitHub Actions hosted-runner allocation is available again, execute exactly one manual run of `.github/workflows/eh7-v740-stabilization-build.yml` on `v7-hierarchy-gps-reporting-dashboard`.

A successful certification requires all of the following:

1. read-only frontend invariant gate PASS;
2. Flutter API paths vs v7 backend RouteRegistry gate PASS;
3. Flutter 3.47.2 install PASS;
4. `flutter pub get` PASS;
5. `flutter analyze` PASS;
6. `flutter test` PASS;
7. debug APK build `7.4.0+740` PASS;
8. APK SHA256 generated;
9. workflow artifact uploaded;
10. final mobile/tablet/desktop visual UAT completed.

Do not describe the APK as production-certified until these execution gates have actually run and passed.
