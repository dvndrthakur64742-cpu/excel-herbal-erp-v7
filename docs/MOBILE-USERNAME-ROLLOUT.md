# Excel Herbal ERP V7 — Mobile-number usernames (staging only)

## Approved requirement
ERP employee login uses registered mobile + password. Newly created WordPress **subscriber** identities must use the employee's normalized mobile number as `user_login`, not an `eh7_...` technical username.

## Staging implementation
- `OrganizationEmployeeService::createWordPressUser` creates a subscriber with numeric normalized mobile `user_login` and the existing password setup flow.
- It refuses mobile usernames already claimed by any existing WordPress account (`wp_mobile_username_in_use`, HTTP 409). It **never** links or overwrites the other WordPress account to work around the collision.
- It rejects invalid mobile numbers, and checks existing email collisions.
- This applies both to **new employee onboarding** and **reprovisioning a broken missing WordPress account** through the audited credential workflow.
- Existing WordPress accounts retain their usernames and user IDs. **No automatic account rename, password reset, or bulk repair.** The REST mobile-login endpoint already uses ERP employee mobile lookup; it does not depend on the WordPress account's `user_login`.
- Synthetic unit assertions are included in `tests/employee_mobile_username.php` and required by `tests/run.sh`.

## Important release gates
1. Back up WordPress + `eh7_*` data and verify restoration.
2. On an **isolated, sanitized UAT database**, exercise a new mobile-number subscriber, duplicate/mobile collision (including pre-existing WordPress users), missing-account repair and unchanged existing employee logins.
3. Check all previous employee accounts against actual WP user IDs and verify branch + hierarchy authority before any individual repair.
4. Validate the Flutter mobile login, refresh, bootstrap, logout and second-device behavior.
5. Only after passing UAT and approval, deploy the same source-commit artifact and confirm versions. This commit is **not deployed**.

## Non-goals
- No backwards-incompatible WordPress username migration. Any future change to existing WP usernames needs a separate reviewed one-to-one mapping, validation of external plugins and a tested rollback.
- No mass password creation/delivery, unsafe WordPress user reassignment or automatic repair of current production employee records.
