#!/usr/bin/env bash
# Ephemeral WordPress + MariaDB smoke test. Never touches a Railway or live DB.
set -euo pipefail
: "${GITHUB_SHA:?Commit SHA is required}"
db_name='eh7_ci_synthetic'
network="eh7-ci-${GITHUB_RUN_ID:-manual}"
db_container="eh7-ci-mariadb-${GITHUB_RUN_ID:-manual}"
wp_container="eh7-ci-wordpress-${GITHUB_RUN_ID:-manual}"
clean() {
  result=$?
  if [[ "$result" -ne 0 ]]; then
    echo '--- WordPress CI startup logs (final 70 lines) ---'
    docker logs --tail 70 "$wp_container" || true
    echo '--- MariaDB CI startup logs (final 25 lines) ---'
    docker logs --tail 25 "$db_container" || true
  fi
  docker rm -f "$wp_container" "$db_container" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
}
trap clean EXIT

docker network create "$network" >/dev/null
docker run -d --name "$db_container" --network "$network" \
  -e MARIADB_ROOT_PASSWORD=eh7_ci_root_only \
  -e MARIADB_DATABASE="$db_name" \
  -e MARIADB_USER=eh7_ci_user \
  -e MARIADB_PASSWORD=eh7_ci_db_only \
  mariadb:11.4 >/dev/null
for i in $(seq 1 50); do
  if docker exec "$db_container" mariadb-admin ping -h 127.0.0.1 -u root -peh7_ci_root_only --silent >/dev/null 2>&1; then break; fi
  sleep 2
done
docker exec "$db_container" mariadb-admin ping -h 127.0.0.1 -u root -peh7_ci_root_only --silent

docker run -d --name "$wp_container" --network "$network" \
  -p 127.0.0.1:18880:80 \
  -e WORDPRESS_DB_HOST="$db_container:3306" \
  -e WORDPRESS_DB_USER=eh7_ci_user \
  -e WORDPRESS_DB_PASSWORD=eh7_ci_db_only \
  -e WORDPRESS_DB_NAME="$db_name" \
  -e WP_ENVIRONMENT_TYPE=staging \
  -e RAILWAY_GIT_COMMIT_SHA="$GITHUB_SHA" \
  -e EH7_UAT_SITE_URL=https://wordpress-uat-production.up.railway.app \
  -e EH7_UAT_WP_ADMIN_LOGIN=eh7_ci_admin \
  -e EH7_UAT_ADMIN_PASSWORD=eh7_ci_admin_password_only \
  -e EH7_UAT_ADMIN_MOBILE=9000000001 \
  -e EH7_UAT_LIMITED_PASSWORD=eh7_ci_limited_password_only \
  -e EH7_UAT_LIMITED_MOBILE=9000000002 \
  eh7-uat:review >/dev/null

echo 'Waiting for WordPress migration and synthetic seed attestation...'
ready=0
for i in $(seq 1 60); do
  if docker logs "$wp_container" 2>&1 | grep -q 'PASS isolated_uat_bootstrap source_head='; then ready=1; break; fi
  if ! [[ "$(docker inspect -f '{{.State.Running}}' "$wp_container")" == true ]]; then break; fi
  sleep 3
done
if [[ "$ready" != 1 ]]; then echo 'FAIL: UAT WordPress synthetic bootstrap/migration did not complete' >&2; exit 1; fi

# Verify installed plugin version, full migration and synthetic-only source attestation.
docker exec "$wp_container" wp eval '
$version=\ExcelHerbal\ERP7\Database\Schema::VERSION;
if((string)get_option("eh7_schema_version","")!==$version){fwrite(STDERR,"SCHEMA MISMATCH\n");exit(1);}
$seed=\ExcelHerbal\ERP7\Administration\FreshUatBootstrap::status();
$safety=\ExcelHerbal\ERP7\Administration\StagingSafety::status();
if(($seed["seeded"]??false)!==true||($seed["synthetic_only"]??false)!==true||
   ($safety["sanitized"]??false)!==true){fwrite(STDERR,"UNSAFE UAT SEED\n");exit(1);}
global $wpdb;
foreach(["prepaid_sales_orders","prepaid_sales_order_lines","prepaid_sales_order_payments","distributor_price_slabs"] as $name){
 if($wpdb->get_var($wpdb->prepare("SHOW TABLES LIKE %s",$wpdb->prefix."eh7_".$name))!==$wpdb->prefix."eh7_".$name){
    fwrite(STDERR,"MISSING TABLE: ".$name."\n");exit(1);
 }
}
echo "PASS real WordPress activation, MariaDB migration, isolated synthetic seed\n";
' --path=/var/www/html --allow-root

# Test Apache URL rewriting via localhost; do not call the actual Railway host.
code="$(curl -sS -o /tmp/eh7-smoke-health.json -w '%{http_code}' \
  -H 'Host: wordpress-uat-production.up.railway.app' \
  --max-time 10 'http://127.0.0.1:18880/wp-json/excel-herbal-erp/v7/health')"
echo "Pretty REST URL HTTP status: $code"
if [[ "$code" != '200' ]]; then
  echo 'FAIL: WordPress pretty REST rewrite does not return HTTP 200' >&2
  head -c 650 /tmp/eh7-smoke-health.json || true
  exit 1
fi
node -e '
const fs=require("fs");
const x=JSON.parse(fs.readFileSync("/tmp/eh7-smoke-health.json","utf8"));
if(!x.ok)throw new Error("Health JSON is not ok");
if(!JSON.stringify(x).includes("7.3.10"))throw new Error("Old plugin health");
console.log("PASS pretty REST health JSON and 7.3.10 plugin");
'
echo 'PASS isolated Docker WordPress + MariaDB smoke test'
