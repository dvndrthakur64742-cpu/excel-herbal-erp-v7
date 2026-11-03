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
  -e EH7_CI_ISOLATED=1 \
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
$field=$wpdb->get_row($wpdb->prepare("SELECT wp_user_id,mobile FROM ".$wpdb->prefix."eh7_employees WHERE employee_code=%s AND status=%s","UAT-FIELD","active"));
$fieldUser=$field?get_userdata((int)$field->wp_user_id):false;
$expectedMobile=$field?preg_replace("/\\D+/", "",(string)$field->mobile):"";
if(!$fieldUser||!preg_match("/^[0-9]{8,15}$/D",$expectedMobile)||
   (string)$fieldUser->user_login!==$expectedMobile||
   !in_array("subscriber",(array)$fieldUser->roles,true)){
   fwrite(STDERR,"SYNTHETIC MOBILE USERNAME / SUBSCRIBER MISMATCH\n");exit(1);
}
echo "PASS actual WordPress subscriber identity uses mobile number as username\n";
echo "PASS real WordPress activation, MariaDB migration, isolated synthetic seed\n";
' --path=/var/www/html --allow-root

# Disposable synthetic-only upgrade rehearsal. It refuses any non-CI site,
# verifies BOTH new evidence tables are empty, snapshots existing business
# rows, recreates new unique indexes, and repeats the migration idempotently.
docker cp uat/railway/ci-additive-upgrade-rehearsal.php \
  "$wp_container:/tmp/eh7-ci-additive-upgrade-rehearsal.php"
docker exec "$wp_container" wp eval-file \
  /tmp/eh7-ci-additive-upgrade-rehearsal.php \
  --path=/var/www/html --allow-root

# Exercise the real GPS evidence SQL and first-fix projection on the isolated
# synthetic WP/MariaDB database. Everything below is rolled back.
docker exec "$wp_container" wp eval '
global $wpdb;
$employee=$wpdb->get_row($wpdb->prepare(
 "SELECT id,company_id,assigned_branch_id FROM ".$wpdb->prefix."eh7_employees WHERE employee_code=%s AND status=%s",
 "UAT-FIELD","active"),ARRAY_A);
if(!$employee){fwrite(STDERR,"MISSING SYNTHETIC FIELD EMPLOYEE\n");exit(1);}
$company=(int)$employee["company_id"];
$branch=(int)$employee["assigned_branch_id"];
$eid=(int)$employee["id"];
$date=\ExcelHerbal\ERP7\Database\Db::today();
$start=gmdate("Y-m-d H:i:s",time()-600);
$pointTime=gmdate("Y-m-d H:i:s",time()-300);
$attendance=$wpdb->prefix."eh7_attendance";
$points=$wpdb->prefix."eh7_gps_points";
$wpdb->query("START TRANSACTION");
try{
 $r=$wpdb->get_row($wpdb->prepare(
  "SELECT id FROM {$attendance} WHERE company_id=%d AND employee_id=%d AND business_date=%s FOR UPDATE",
  $company,$eid,$date),ARRAY_A);
 if(!$r){
  $ok=$wpdb->insert($attendance,[
   "company_id"=>$company,"branch_id"=>$branch,"employee_id"=>$eid,
   "business_date"=>$date,"status"=>"present","check_in_at"=>$start,
   "created_at"=>$start]);
  if(!$ok)throw new \RuntimeException("Attendance test seed failed");
  $attendanceId=(int)$wpdb->insert_id;
 }else{
  $attendanceId=(int)$r["id"];
  $wpdb->update($attendance,["check_in_at"=>$start,"check_out_at"=>null,
   "check_in_lat"=>null,"check_in_lng"=>null],["id"=>$attendanceId]);
 }
 $gps=\ExcelHerbal\ERP7\Workforce\AttendanceGpsEvidence::class;
 if($gps::hasVerifiedMorningPoint($company,$branch,$eid,$date))
  throw new \RuntimeException("Stock request accepted without first GPS point");
 if(!$wpdb->insert($points,["company_id"=>$company,"branch_id"=>$branch,
  "employee_id"=>$eid,"attendance_id"=>$attendanceId,
  "latitude"=>31.701,"longitude"=>76.93,"recorded_at"=>$pointTime,
  "source"=>"duty","created_at"=>$pointTime]))
  throw new \RuntimeException("GPS point test seed failed");
 $pointId=(int)$wpdb->insert_id;
 $gps::captureFirstPoint($wpdb,$attendanceId,$company,$eid,31.701,76.93);
 if(!$gps::hasVerifiedMorningPoint($company,$branch,$eid,$date))
  throw new \RuntimeException("Matching GPS point did not unlock morning issue");
 $gps::captureFirstPoint($wpdb,$attendanceId,$company,$eid,32.1,77.2);
 $first=$wpdb->get_row($wpdb->prepare("SELECT check_in_lat,check_in_lng FROM {$attendance} WHERE id=%d",$attendanceId),ARRAY_A);
 if(abs((float)$first["check_in_lat"]-31.701)>.00001||abs((float)$first["check_in_lng"]-76.93)>.00001)
  throw new \RuntimeException("First GPS fix was unexpectedly overwritten");
 $wpdb->update($points,["branch_id"=>$branch+1000],["id"=>$pointId]);
 if($gps::hasVerifiedMorningPoint($company,$branch,$eid,$date))
  throw new \RuntimeException("Other-branch GPS point bypassed stock gate");
 echo "PASS real MariaDB GPS proof, first fix, and branch-isolated Morning Issue gate\n";
}catch(\Throwable $e){
 $wpdb->query("ROLLBACK");
 fwrite(STDERR,"FAIL GPS evidence WordPress UAT: ".$e->getMessage()."\n");
 exit(1);
}
$wpdb->query("ROLLBACK");
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
if(x?.data?.version!=="7.3.12-rc1" || x?.data?.schema!=="7.3.12-reward-register-3" || !x?.data?.schema_installed)throw new Error("Plugin/schema release health mismatch");
console.log("PASS pretty REST health JSON and 7.3.12 plugin/schema");
'
node uat/railway/ci-auth-smoke.mjs

# Credential changes run only after synthetic user HTTP login tests complete.
# These WP users and data live in this disposable CI container, not Railway/live.
docker exec "$wp_container" wp eval '
global $wpdb;
$t=$wpdb->prefix."eh7_employees";
$r=$wpdb->get_row($wpdb->prepare(
 "SELECT id,company_id,assigned_branch_id,wp_user_id FROM {$t} WHERE employee_code=%s AND status=%s",
 "UAT-FIELD","active"),ARRAY_A);
if(!$r||!($user=get_userdata((int)$r["wp_user_id"]))) {
 fwrite(STDERR,"SYNTHETIC LOGIN TEST USER MISSING\n");exit(1);
}
$actor=new \ExcelHerbal\ERP7\Security\Actor(
 99999,99999,(int)$r["company_id"],(int)$r["assigned_branch_id"],
 [(int)$r["assigned_branch_id"]],
 [\ExcelHerbal\ERP7\Security\Capabilities::EMP_MANAGE,
  \ExcelHerbal\ERP7\Security\Capabilities::ACCESS_MANAGE],
 "SYSADMIN");
$before=(string)$user->user_pass;
try {
 \ExcelHerbal\ERP7\Organization\OrganizationEmployeeService::setEmployeeCredentials(
  $actor,(int)$r["id"],["password"=>"ci-test-password-after-identity"]);
 fwrite(STDERR,"UNVERIFIED CREDENTIAL CHANGE ACCEPTED\n");exit(1);
} catch (\ExcelHerbal\ERP7\Domain\DomainException $e) {
 if($e->codeKey!=="employee_identity_confirmation_required"){
  fwrite(STDERR,"WRONG IDENTITY CONFIRMATION FAILURE\n");exit(1);
 }
}
clean_user_cache((int)$r["wp_user_id"]);
if((string)get_userdata((int)$r["wp_user_id"])->user_pass!==$before){
 fwrite(STDERR,"UNVERIFIED CREDENTIAL CHANGE MUTATED PASSWORD\n");exit(1);
}
$result=\ExcelHerbal\ERP7\Organization\OrganizationEmployeeService::setEmployeeCredentials(
 $actor,(int)$r["id"],[
 "password"=>"ci-test-password-after-identity",
 "identity_verified"=>true,
 "verification_method"=>"in_person",
 "verification_reference"=>"CI-VERIFY-123"]);
if(empty($result["password_updated"])){
 fwrite(STDERR,"VERIFIED CREDENTIAL CHANGE FAILED\n");exit(1);
}
clean_user_cache((int)$r["wp_user_id"]);
$user=get_userdata((int)$r["wp_user_id"]);
if(!$user||!wp_check_password("ci-test-password-after-identity",(string)$user->user_pass,(int)$user->ID)){
 fwrite(STDERR,"VERIFIED CREDENTIAL PASSWORD NOT UPDATED\n");exit(1);
}
$log=$wpdb->get_var($wpdb->prepare(
 "SELECT context_json FROM ".$wpdb->prefix."eh7_audit_log WHERE company_id=%d AND entity_id=%s AND action=%s ORDER BY id DESC LIMIT 1",
 (int)$r["company_id"],(string)$r["id"],"employee.login_credentials_reset"));
$context=json_decode((string)$log,true);
if(!is_array($context)||($context["verification_method"]??"")!=="in_person"||
  ($context["verification_reference"]??"")!=="CI-VERIFY-123"){
 fwrite(STDERR,"CREDENTIAL VERIFICATION AUDIT NOT RECORDED\n");exit(1);
}
echo "PASS real WordPress individual identity acknowledgement, password reset, and audit reference\n";
' --path=/var/www/html --allow-root

echo 'PASS isolated Docker WordPress + MariaDB smoke test'
