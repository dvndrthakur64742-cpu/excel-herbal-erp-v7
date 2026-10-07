#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
SOURCE_HEAD="$(git rev-parse HEAD)"
OUT="$ROOT/dist/isolated-backup-restore"
TMP="$RUNNER_TEMP/eh7-isolated-restore-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
mkdir -p "$OUT" "$TMP"

NET="eh7-uat-net-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
DB="eh7-uat-db-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
WP="eh7-uat-wp-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
VOL="eh7-uat-vol-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
DB_NAME="wordpress"
DB_USER="eh7wp"
DB_PASS="Eh7Wp!$GITHUB_RUN_ID"
DB_ROOT_PASS="Eh7Root!$GITHUB_RUN_ID"
ADMIN_USER="uat-admin"
ADMIN_PASS="Eh7Admin!2026-$GITHUB_RUN_ID"
ADMIN_MOBILE="9000000001"
LIMITED_PASS="Eh7Field!2026-$GITHUB_RUN_ID"
LIMITED_MOBILE="9000000002"
BASE_URL="http://127.0.0.1:18080"
API="$BASE_URL/wp-json/excel-herbal-erp/v7"
FIXTURE="$TMP/fixture.png"
BACKUP="$OUT/isolated-wordpress-backup.sql"
EVIDENCE="$OUT/EVIDENCE.json"
PLUGIN="$TMP/excel-herbal-erp-v7"

cleanup() {
  docker rm -f "$WP" "$DB" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  docker volume rm "$VOL" >/dev/null 2>&1 || true
  rm -rf "$TMP" >/dev/null 2>&1 || true
}
trap cleanup EXIT

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}
need docker
need curl
need jq
need sha256sum

cp -a backend/excel-herbal-erp-v7 "$PLUGIN"
cat > "$PLUGIN/build-meta.php" <<PHP
<?php
if(!defined('ABSPATH'))exit;
define('EH7_SOURCE_HEAD','$SOURCE_HEAD');
define('EH7_DEPLOY_ENVIRONMENT','staging');
PHP

docker network create "$NET" >/dev/null
docker volume create "$VOL" >/dev/null

docker run -d --name "$DB" --network "$NET"   -e MARIADB_ROOT_PASSWORD="$DB_ROOT_PASS"   -e MARIADB_DATABASE="$DB_NAME"   -e MARIADB_USER="$DB_USER"   -e MARIADB_PASSWORD="$DB_PASS"   mariadb:11.8.9 >/dev/null

for i in $(seq 1 90); do
  if docker exec "$DB" mariadb-admin ping -uroot -p"$DB_ROOT_PASS" --silent >/dev/null 2>&1; then break; fi
  if [[ "$i" == "90" ]]; then
    docker logs "$DB" >&2 || true
    echo "MariaDB did not become ready." >&2
    exit 1
  fi
  sleep 1
done

docker run -d --name "$WP" --network "$NET" -p 18080:80   -v "$VOL:/var/www/html"   -e WORDPRESS_DB_HOST="$DB:3306"   -e WORDPRESS_DB_USER="$DB_USER"   -e WORDPRESS_DB_PASSWORD="$DB_PASS"   -e WORDPRESS_DB_NAME="$DB_NAME"   wordpress:php8.3-apache >/dev/null

for i in $(seq 1 90); do
  if docker exec "$WP" test -f /var/www/html/wp-config.php >/dev/null 2>&1; then break; fi
  if [[ "$i" == "90" ]]; then
    docker logs "$WP" >&2 || true
    echo "WordPress files did not become ready." >&2
    exit 1
  fi
  sleep 1
done

docker exec "$WP" mkdir -p /var/www/html/wp-content/plugins/excel-herbal-erp-v7
docker cp "$PLUGIN/." "$WP:/var/www/html/wp-content/plugins/excel-herbal-erp-v7"
docker exec "$WP" chown -R www-data:www-data /var/www/html/wp-content/plugins/excel-herbal-erp-v7

wpcli() {
  docker run --rm --network "$NET" --volumes-from "$WP"     -e WORDPRESS_DB_HOST="$DB:3306"     -e WORDPRESS_DB_USER="$DB_USER"     -e WORDPRESS_DB_PASSWORD="$DB_PASS"     -e WORDPRESS_DB_NAME="$DB_NAME"     wordpress:cli wp "$@" --path=/var/www/html
}

wpcli core install   --url="$BASE_URL"   --title="EH7 Isolated Recovery UAT"   --admin_user="$ADMIN_USER"   --admin_password="$ADMIN_PASS"   --admin_email="uat@example.invalid"   --skip-email

wpcli option update permalink_structure '/%postname%/'
wpcli rewrite flush --hard
wpcli plugin activate excel-herbal-erp-v7

docker run --rm --network "$NET" --volumes-from "$WP"   -e WORDPRESS_DB_HOST="$DB:3306"   -e WORDPRESS_DB_USER="$DB_USER"   -e WORDPRESS_DB_PASSWORD="$DB_PASS"   -e WORDPRESS_DB_NAME="$DB_NAME"   -e EH7_UAT_WP_ADMIN_LOGIN="$ADMIN_USER"   -e EH7_UAT_ADMIN_PASSWORD="$ADMIN_PASS"   -e EH7_UAT_ADMIN_MOBILE="$ADMIN_MOBILE"   -e EH7_UAT_LIMITED_PASSWORD="$LIMITED_PASS"   -e EH7_UAT_LIMITED_MOBILE="$LIMITED_MOBILE"   -e EH7_UAT_COMPANY_NAME="EH7 Isolated Restore UAT"   -e EH7_UAT_BRANCH_NAME="Isolated UAT Branch"   wordpress:cli wp eval-file   /var/www/html/wp-content/plugins/excel-herbal-erp-v7/tools/fresh-uat-bootstrap.php   --path=/var/www/html > "$OUT/bootstrap.json"

for i in $(seq 1 45); do
  code="$(curl -sS -o "$TMP/health.json" -w '%{http_code}' "$API/health" || true)"
  if [[ "$code" == "200" ]]; then break; fi
  if [[ "$i" == "45" ]]; then
    docker logs "$WP" >&2 || true
    echo "ERP health did not become ready; HTTP $code" >&2
    cat "$TMP/health.json" >&2 || true
    exit 1
  fi
  sleep 1
done

jq -e --arg sha "$SOURCE_HEAD" '
  .ok == true and
  .data.source_head == $sha and
  .data.environment == "staging" and
  .data.schema_installed == true and
  .data.uat_bootstrap.seeded == true and
  .data.uat_bootstrap.synthetic_only == true
' "$TMP/health.json" >/dev/null

# Distinct synthetic limited-role bearer boundaries.
NO_TOKEN_STATUS="$(curl -sS -o "$TMP/no-token.json" -w '%{http_code}' "$API/me")"
[[ "$NO_TOKEN_STATUS" == "401" ]]
INVALID_TOKEN_STATUS="$(curl -sS -o "$TMP/invalid-token.json" -w '%{http_code}' -H 'Authorization: Bearer definitely-invalid-token' "$API/me")"
[[ "$INVALID_TOKEN_STATUS" == "401" ]]

LIMITED_LOGIN="$(curl -fsS -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg mobile "$LIMITED_MOBILE" --arg password "$LIMITED_PASS" \
    '{mobile:$mobile,password:$password,device:"Isolated limited-role UAT",device_id:"isolated-limited-role"}')" \
  "$API/auth/login")"
LIMITED_TOKEN="$(printf '%s' "$LIMITED_LOGIN" | jq -er '.data.access_token')"
curl -fsS -H "Authorization: Bearer $LIMITED_TOKEN" "$API/me" | jq -e '.ok == true' >/dev/null
LIMITED_FORBIDDEN_STATUS="$(curl -sS -o "$TMP/limited-forbidden.json" -w '%{http_code}' \
  -H "Authorization: Bearer $LIMITED_TOKEN" "$API/administration/diagnostics")"
[[ "$LIMITED_FORBIDDEN_STATUS" == "403" ]]
jq -e '.error.code == "permission_denied"' "$TMP/limited-forbidden.json" >/dev/null
curl -fsS -X POST -H "Authorization: Bearer $LIMITED_TOKEN" "$API/auth/logout" >/dev/null
LIMITED_POST_LOGOUT_STATUS="$(curl -sS -o "$TMP/limited-post-logout.json" -w '%{http_code}' \
  -H "Authorization: Bearer $LIMITED_TOKEN" "$API/me")"
[[ "$LIMITED_POST_LOGOUT_STATUS" == "401" ]]

printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=' | base64 -d > "$FIXTURE"
FIXTURE_SHA="$(sha256sum "$FIXTURE" | awk '{print $1}')"

login() {
  curl -fsS -H 'Content-Type: application/json'     -d "$(jq -nc --arg mobile "$ADMIN_MOBILE" --arg password "$ADMIN_PASS"       '{mobile:$mobile,password:$password,device:"Isolated restore UAT",device_id:"isolated-restore-uat"}')"     "$API/auth/login"
}

LOGIN_JSON="$(login)"
TOKEN="$(printf '%s' "$LOGIN_JSON" | jq -er '.data.access_token')"
ME_JSON="$(curl -fsS -H "Authorization: Bearer $TOKEN" "$API/me")"
EMPLOYEE_ID="$(printf '%s' "$ME_JSON" | jq -er '.data.employee.id')"

UPLOAD_JSON="$(curl -fsS   -H "Authorization: Bearer $TOKEN"   -H "X-Idempotency-Key: isolated-doc-$GITHUB_RUN_ID"   -F 'document_type=RESTORE_FIXTURE'   -F 'title=Isolated backup restore private document fixture'   -F "file=@$FIXTURE;type=image/png;filename=isolated-restore-fixture.png"   "$API/organization/employees/$EMPLOYEE_ID/documents/upload")"
DOC_ID="$(printf '%s' "$UPLOAD_JSON" | jq -er '.data.id')"
printf '%s' "$UPLOAD_JSON" | jq -e '.ok == true and .data.attachment_id == 0 and .data.requires_auth == true' >/dev/null

curl -fsS -D "$TMP/pre.headers" -o "$TMP/pre.png"   -H "Authorization: Bearer $TOKEN"   "$API/organization/employees/$EMPLOYEE_ID/documents/$DOC_ID/download"
grep -Eiq '^X-EH7-Private-Document:[[:space:]]*1' "$TMP/pre.headers"
PRE_SHA="$(sha256sum "$TMP/pre.png" | awk '{print $1}')"
[[ "$PRE_SHA" == "$FIXTURE_SHA" ]]

curl -fsS -X POST -H "Authorization: Bearer $TOKEN" "$API/auth/logout" >/dev/null

KEY_HASH_BEFORE="$(docker exec "$DB" mariadb -uroot -p"$DB_ROOT_PASS" -N -B "$DB_NAME"   -e "SELECT SHA2(option_value,256) FROM wp_options WHERE option_name='eh7_document_key' LIMIT 1;" | tr -d '\r')"
[[ "$KEY_HASH_BEFORE" =~ ^[0-9A-Fa-f]{64}$ ]]

docker exec "$DB" mariadb-dump -uroot -p"$DB_ROOT_PASS"   --single-transaction --quick --skip-lock-tables   --default-character-set=utf8mb4 --databases "$DB_NAME" > "$BACKUP"
[[ -s "$BACKUP" ]]
BACKUP_BYTES="$(wc -c < "$BACKUP" | tr -d ' ')"
[[ "$BACKUP_BYTES" -gt 1024 ]]
BACKUP_SHA="$(sha256sum "$BACKUP" | awk '{print $1}')"

docker exec "$DB" mariadb -uroot -p"$DB_ROOT_PASS" -e "DROP DATABASE $DB_NAME;"
docker exec -i "$DB" mariadb -uroot -p"$DB_ROOT_PASS" < "$BACKUP"

KEY_HASH_AFTER="$(docker exec "$DB" mariadb -uroot -p"$DB_ROOT_PASS" -N -B "$DB_NAME"   -e "SELECT SHA2(option_value,256) FROM wp_options WHERE option_name='eh7_document_key' LIMIT 1;" | tr -d '\r')"
[[ "$KEY_HASH_AFTER" == "$KEY_HASH_BEFORE" ]]

POST_HEALTH="$(curl -fsS "$API/health")"
printf '%s' "$POST_HEALTH" | jq -e --arg sha "$SOURCE_HEAD" '
  .ok == true and
  .data.source_head == $sha and
  .data.environment == "staging" and
  .data.schema_installed == true and
  .data.uat_bootstrap.seeded == true
' >/dev/null

LOGIN_JSON="$(login)"
TOKEN="$(printf '%s' "$LOGIN_JSON" | jq -er '.data.access_token')"
curl -fsS -D "$TMP/post.headers" -o "$TMP/post.png"   -H "Authorization: Bearer $TOKEN"   "$API/organization/employees/$EMPLOYEE_ID/documents/$DOC_ID/download"
grep -Eiq '^X-EH7-Private-Document:[[:space:]]*1' "$TMP/post.headers"
POST_SHA="$(sha256sum "$TMP/post.png" | awk '{print $1}')"
[[ "$POST_SHA" == "$FIXTURE_SHA" ]]

DEACTIVATE="$(curl -fsS -X POST   -H "Authorization: Bearer $TOKEN"   -H 'Content-Type: application/json'   -H "X-Idempotency-Key: isolated-doc-deactivate-$GITHUB_RUN_ID"   -d '{}'   "$API/organization/employees/$EMPLOYEE_ID/documents/$DOC_ID/deactivate")"
printf '%s' "$DEACTIVATE" | jq -e '.ok == true and .data.status == "inactive"' >/dev/null

HTTP_AFTER_DEACTIVATE="$(curl -sS -o "$TMP/inactive.json" -w '%{http_code}'   -H "Authorization: Bearer $TOKEN"   "$API/organization/employees/$EMPLOYEE_ID/documents/$DOC_ID/download")"
[[ "$HTTP_AFTER_DEACTIVATE" == "404" ]]
jq -e '.error.code == "document_not_found"' "$TMP/inactive.json" >/dev/null
curl -fsS -X POST -H "Authorization: Bearer $TOKEN" "$API/auth/logout" >/dev/null

jq -n   --arg source_head "$SOURCE_HEAD"   --arg backup_sha256 "$BACKUP_SHA"   --argjson backup_bytes "$BACKUP_BYTES"   --arg fixture_sha256 "$FIXTURE_SHA"   --argjson employee_id "$EMPLOYEE_ID"   --argjson document_id "$DOC_ID"   '{
    schema_version:1,
    gate:"host_backup_restore",
    status:"passed",
    environment:"fresh-isolated-wordpress-mariadb",
    source_head:$source_head,
    database:"MariaDB 11.8.9",
    wordpress_container:"wordpress:php8.3-apache",
    backup:{sha256:$backup_sha256,bytes:$backup_bytes,single_transaction:true},
    synthetic_seed:true,
    private_document:{
      employee_id:$employee_id,
      document_id:$document_id,
      fixture_sha256:$fixture_sha256,
      pre_backup_download_hash_match:true,
      encryption_key_hash_restored:true,
      post_restore_download_hash_match:true,
      deactivation_verified:true,
      inactive_download_rejected:true
    },
    auth_boundaries:{
      missing_token_401:true,
      invalid_token_401:true,
      distinct_limited_login_200:true,
      distinct_limited_forbidden_403:true,
      limited_logout_revocation_401:true
    },
    checks:{
      exact_head_plugin:true,
      staging_environment:true,
      schema_installed:true,
      fresh_uat_seeded:true,
      database_dump:true,
      database_drop:true,
      database_restore:true,
      document_key_recovery:true,
      authenticated_private_document_after_restore:true
    }
  }' > "$EVIDENCE"

cat "$EVIDENCE"
echo "PASS isolated WordPress+MariaDB backup/restore and document-key recovery"
