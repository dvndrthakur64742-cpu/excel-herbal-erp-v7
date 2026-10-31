#!/usr/bin/env bash
set -euo pipefail

# Railway can restore Apache module links when the container starts. PHP's
# Apache image must run exactly one MPM; normalize it at runtime before the
# WordPress entrypoint starts Apache.
if command -v a2enmod >/dev/null 2>&1; then
  a2dismod mpm_event mpm_worker >/dev/null 2>&1 || true
  for module in /etc/apache2/mods-enabled/mpm_*.load; do
    [[ -e "$module" ]] || continue
    module_name="${module##*/}"
    module_name="${module_name%.load}"
    if [[ "$module_name" != "mpm_prefork" ]]; then
      rm -f "/etc/apache2/mods-enabled/${module_name}.load" "/etc/apache2/mods-enabled/${module_name}.conf"
    fi
  done
  a2enmod mpm_prefork >/dev/null 2>&1 || true
  active_mpm_count="$(find /etc/apache2/mods-enabled -maxdepth 1 -name 'mpm_*.load' -print | wc -l)"
  if [[ "$active_mpm_count" -ne 1 || ! -e /etc/apache2/mods-enabled/mpm_prefork.load ]]; then
    echo "FATAL Apache must have exactly one active MPM (mpm_prefork); found $active_mpm_count" >&2
    exit 68
  fi
  echo "EH7_APACHE_MPM active=mpm_prefork"
fi

required=(
  EH7_UAT_SITE_URL
  EH7_UAT_WP_ADMIN_LOGIN
  EH7_UAT_ADMIN_PASSWORD
  EH7_UAT_ADMIN_MOBILE
  EH7_UAT_LIMITED_PASSWORD
  EH7_UAT_LIMITED_MOBILE
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "FATAL missing required UAT variable: $name" >&2
    exit 64
  fi
done

if [[ "${WP_ENVIRONMENT_TYPE:-}" != "staging" ]]; then
  echo "FATAL isolated UAT requires WP_ENVIRONMENT_TYPE=staging" >&2
  exit 65
fi
# Railway provides the exact deployed Git commit for GitHub deployments.
# Do not rely on the old EH7_SOURCE_HEAD variable, which can remain pinned
# to a previous UAT candidate after a source change.
if [[ ! "${RAILWAY_GIT_COMMIT_SHA:-}" =~ ^[0-9a-fA-F]{40}$ ]]; then
  echo "FATAL UAT requires GitHub deployment with RAILWAY_GIT_COMMIT_SHA" >&2
  exit 66
fi
export EH7_SOURCE_HEAD="${RAILWAY_GIT_COMMIT_SHA,,}"
if [[ "${EH7_UAT_SITE_URL}" != "https://wordpress-uat-production.up.railway.app" ]]; then
  echo "FATAL UAT is locked to the explicitly isolated Railway host" >&2
  exit 66
fi

/usr/local/bin/docker-entrypoint.sh "$@" &
apache_pid=$!
trap 'kill "$apache_pid" 2>/dev/null || true' TERM INT EXIT

plugin_dir=/var/www/html/wp-content/plugins/excel-herbal-erp-v7
for attempt in $(seq 1 90); do
  if [[ -f /var/www/html/wp-load.php && -f "$plugin_dir/excel-herbal-erp-v7.php" ]]; then
    break
  fi
  if ! kill -0 "$apache_pid" 2>/dev/null; then
    wait "$apache_pid"
    exit $?
  fi
  sleep 2
done

if [[ ! -f "$plugin_dir/excel-herbal-erp-v7.php" ]]; then
  echo "FATAL WordPress/plugin files were not initialized into the persistent web root" >&2
  exit 67
fi

cat > "$plugin_dir/build-meta.php" <<PHP
<?php
if(!defined('ABSPATH'))exit;
define('EH7_SOURCE_HEAD','${EH7_SOURCE_HEAD}');
define('EH7_DEPLOY_ENVIRONMENT','staging');
PHP
chown www-data:www-data "$plugin_dir/build-meta.php"

for attempt in $(seq 1 90); do
  if wp db check --path=/var/www/html --allow-root >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$apache_pid" 2>/dev/null; then
    wait "$apache_pid"
    exit $?
  fi
  sleep 2
done
wp db check --path=/var/www/html --allow-root >/dev/null

if ! wp core is-installed --path=/var/www/html --allow-root >/dev/null 2>&1; then
  wp core install \
    --path=/var/www/html \
    --url="$EH7_UAT_SITE_URL" \
    --title="${EH7_UAT_SITE_TITLE:-Excel Herbal ERP Isolated UAT}" \
    --admin_user="$EH7_UAT_WP_ADMIN_LOGIN" \
    --admin_password="$EH7_UAT_ADMIN_PASSWORD" \
    --admin_email="${EH7_UAT_ADMIN_EMAIL:-uat-admin@example.invalid}" \
    --skip-email \
    --allow-root
fi

wp option update home "$EH7_UAT_SITE_URL" --path=/var/www/html --allow-root >/dev/null
wp option update siteurl "$EH7_UAT_SITE_URL" --path=/var/www/html --allow-root >/dev/null
wp option update blog_public 0 --path=/var/www/html --allow-root >/dev/null
# WordPress REST "pretty" routes require Apache mod_rewrite and a valid
# .htaccess; do not rely solely on the legacy ?rest_route= fallback.
cat > /var/www/html/.htaccess <<'HTACCESS'
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
HTACCESS
chown www-data:www-data /var/www/html/.htaccess
wp option update permalink_structure '/%postname%/' --path=/var/www/html --allow-root >/dev/null

wp plugin activate excel-herbal-erp-v7 --path=/var/www/html --allow-root >/dev/null
# Fail if the new plugin did not complete its additive schema migration.
wp eval '
if((string)get_option("eh7_schema_version","")!==\ExcelHerbal\ERP7\Database\Schema::VERSION){
  fwrite(STDERR,"FATAL ERP database schema migration incomplete\n");exit(70);
}
if(wp_get_environment_type()!=="staging" || !defined("DISALLOW_FILE_EDIT") || DISALLOW_FILE_EDIT!==true){
  fwrite(STDERR,"FATAL staging WordPress hardening constants missing\n");exit(70);
}
' --path=/var/www/html --allow-root

uat_seed_mode="$(wp eval '
$u=\ExcelHerbal\ERP7\Administration\FreshUatBootstrap::status();
if(($u["seeded"]??false)===true){echo "seeded";}
elseif(($u["synthetic_only"]??false)===true && ($u["admin_employee_present"]??false)===true
 && ($u["limited_employee_present"]??false)===true && !empty($u["seeded_at"])
 && preg_match("/^[a-f0-9]{40}$/i",(string)get_option("eh7_uat_seed_source_head",""))){
  echo "rotate_synthetic_marker";
}elseif((\ExcelHerbal\ERP7\Setup\SetupService::status()["initialized"]??false)!==true){
  echo "fresh";
}else{echo "unsafe";}
' --path=/var/www/html --allow-root)"
case "$uat_seed_mode" in
  seeded) echo "PASS existing synthetic UAT seed remains valid" ;;
  rotate_synthetic_marker)
    # Preserve pre-existing synthetic users, branches and credentials. A new
    # Git SHA is not a reason to rerun first-install seed and reset passwords.
    wp eval '
    \ExcelHerbal\ERP7\Administration\FreshUatBootstrap::assertSafeTarget();
    $u=\ExcelHerbal\ERP7\Administration\FreshUatBootstrap::status();
    if(($u["synthetic_only"]??false)!==true || ($u["admin_employee_present"]??false)!==true
      || ($u["limited_employee_present"]??false)!==true || empty($u["seeded_at"]))exit(71);
    update_option("eh7_uat_seed_source_head",EH7_SOURCE_HEAD,false);
    echo "PASS existing synthetic UAT seed re-attested for current source\n";
    ' --path=/var/www/html --allow-root
    ;;
  fresh)
    wp eval-file "$plugin_dir/tools/fresh-uat-bootstrap.php" --path=/var/www/html --allow-root
    ;;
  *)
    echo "FATAL isolated UAT contains initialized non-synthetic or unverifiable data; refusing to reseed" >&2
    exit 71
    ;;
esac
wp rewrite flush --hard --path=/var/www/html --allow-root >/dev/null

wp eval-file "$plugin_dir/tools/staging-sanitize.php" --path=/var/www/html --allow-root

wp eval '
$u=\ExcelHerbal\ERP7\Administration\FreshUatBootstrap::status();
$s=\ExcelHerbal\ERP7\Administration\StagingSafety::status();
if(($u["seeded"]??false)!==true||($u["synthetic_only"]??false)!==true||($u["source_head_match"]??false)!==true){fwrite(STDERR,"Fresh UAT attestation failed\n");exit(71);}
if(($s["sanitized"]??false)!==true||($s["source_head_match"]??false)!==true||($s["search_indexing_disabled"]??false)!==true){fwrite(STDERR,"Staging safety attestation failed\n");exit(72);}
echo "PASS isolated_uat_bootstrap source_head=".EH7_SOURCE_HEAD."\n";
' --path=/var/www/html --allow-root

trap - TERM INT EXIT
wait "$apache_pid"
