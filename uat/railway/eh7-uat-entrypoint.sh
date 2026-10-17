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
  EH7_SOURCE_HEAD
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
if [[ ! "$EH7_SOURCE_HEAD" =~ ^[0-9a-fA-F]{40}$ ]]; then
  echo "FATAL EH7_SOURCE_HEAD must be an exact 40-character commit SHA" >&2
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

wp plugin activate excel-herbal-erp-v7 --path=/var/www/html --allow-root >/dev/null

uat_seeded="$(wp eval 'echo (\ExcelHerbal\ERP7\Administration\FreshUatBootstrap::status()["seeded"]??false)?"1":"0";' --path=/var/www/html --allow-root)"
if [[ "$uat_seeded" != "1" ]]; then
  wp eval-file "$plugin_dir/tools/fresh-uat-bootstrap.php" --path=/var/www/html --allow-root
fi

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
