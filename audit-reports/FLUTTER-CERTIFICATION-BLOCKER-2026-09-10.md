# Flutter v7.4.0 Certification Blocker — updated 2026-09-11

## Current status

The requested ERP v7 hierarchy/reporting/GPS/Price Distribution/role-dashboard correction scope is source-complete on branch `v7-hierarchy-gps-reporting-dashboard`.

Flutter release certification is the only remaining gate: invariant checks -> branch-selector state-sync gate -> API-path/backend contract check -> `flutter pub get` -> `flutter analyze` -> `flutter test` -> debug APK -> SHA256 artifact -> device visual UAT.

## GitHub-hosted runner evidence

Controlled probes have now covered multiple hosted-runner pools plus later retries.

### Standard Linux runner probe

- Workflow run: `34486920153`
- Initial job: `102903441436`
- Runner label: `ubuntu-latest`
- Result: failure before job execution
- Job payload: `steps=null`
- Job logs: no log URL/blob

### Slim Linux runner probe

- Workflow run: `34498125506`
- Initial job: `102941721000`
- Runner label: `ubuntu-slim`
- Result: failure before job execution
- Job payload: `steps=null`
- Job logs: no log URL/blob

### Linux re-run attempts

- Workflow run: `34498125506`, new re-run job `102982204766`
- Workflow run: `34486920153`, later re-run job `103142773986`
- Both completed before their first workflow step
- Both returned `steps=null`
- No job log blob was created

### Current-head Linux certification probe — 2026-09-11

- Workflow run: `34562065875`
- Head commit: `bc44b59b68e773762f6566d77c72de1d9d5046cb`
- Job: `103146687546`
- Runner label: `ubuntu-latest`
- Result: failure before job execution
- Job payload: `steps=null`
- Job logs: no log URL/blob

This probe included the latest source-side stabilization gates, including the dedicated branch-selector state-sync verifier. No verifier, Flutter, Dart, Gradle, test, or APK command actually executed because the runner never started.

### Independent Windows runner probe — 2026-09-11

- Workflow run: `34562152455`
- Head commit: `66513cff1b5b63c9bd2bfc8a5c4ca6c552aa838f`
- Job: `103146936901`
- Runner label: `windows-latest`
- Result: failure before job execution
- Job payload: `steps=null`
- Job logs: no log URL/blob

The Windows probe demonstrates that the failure is not limited to the Ubuntu hosted-runner pool.

Because none of these jobs reached their first workflow step, the failures are not Flutter/Dart compile failures and are not test failures. They are evidence of a GitHub-hosted runner/account allocation gate before execution. The exact account-side billing/quota/policy cause is not exposed through the connected repository API and must not be guessed.

## Local build fallback evidence

The available execution container was also checked as a fallback build environment.

- OpenJDK 21 is available.
- Flutter executable: not installed.
- Dart executable: not installed.
- Android SDK/ADB: not installed.
- No usable Flutter SDK archive is present in the Project/Library files.
- A prior Flutter source bundle contains `.dart_tool` and build/test remnants but does not contain the Flutter SDK binaries required to analyze or compile the current app.
- A Flutter 3.47.2 Linux SDK archive was identified, but the available container download/network paths could not retrieve the approximately 1.5 GiB SDK bundle.
- Outbound shell DNS/package access is unavailable, so Flutter/Android SDK bootstrap cannot be completed from this container.
- No Dart parser/toolchain substitute capable of objectively replacing `flutter analyze` / `flutter test` is available in the container.

Therefore the current container cannot replace the unavailable GitHub-hosted runner for APK certification.

## Source-side release gates already sealed

The branch currently includes read-only gates for:

1. hierarchy/reporting/GPS/dashboard invariants;
2. branch-selector aggregate-scope/state synchronization;
3. Flutter API paths vs v7 backend RouteRegistry;
4. authority projection / zero-branch fail-closed behavior;
5. role projection boundaries;
6. backend `force_update` app-version policy compatibility.

The branch-selector state-sync gate has also been executed locally against its source fixture and passed.

## Repository safety state

After every controlled probe:

- temporary push trigger files were removed;
- certification workflow was restored to `workflow_dispatch` only;
- workflow permission remains `contents: read`;
- workflow performs no source commit/push or release mutation;
- canonical runner is restored to `ubuntu-latest`;
- v14 code/module/schema remains excluded from v7.

## Unlock condition

Once GitHub Actions hosted-runner allocation is available again, execute exactly one manual run of `.github/workflows/eh7-v740-stabilization-build.yml` on `v7-hierarchy-gps-reporting-dashboard`.

A successful certification requires all of the following:

1. hierarchy/reporting/GPS frontend invariant gate PASS;
2. branch-selector state-sync gate PASS;
3. Flutter API paths vs v7 backend RouteRegistry gate PASS;
4. Flutter 3.47.2 install PASS;
5. `flutter pub get` PASS;
6. `flutter analyze --no-fatal-infos --no-fatal-warnings` PASS;
7. `flutter test` PASS;
8. debug APK build `7.4.0+740` PASS;
9. APK SHA256 generated;
10. workflow artifact uploaded;
11. final mobile/tablet/desktop visual UAT completed.

Do not describe the APK as production-certified until these execution gates have actually run and passed.
