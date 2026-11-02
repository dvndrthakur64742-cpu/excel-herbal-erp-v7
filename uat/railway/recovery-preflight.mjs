/**
 * Railway persistent-UAT recovery gate.
 * Reads sanitized, read-only Railway inventory snapshots; no Railway API calls,
 * mutation, deployment, credentials, or production WordPress access.
 */
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const EXPECTED_PROJECT = 'Excel Herbal ERP - Isolated UAT';
const EXPECTED_REPO = 'dvndrthakur64742-cpu/excel-herbal-erp-v7';
const EXPECTED_BRANCH = 'feature/v7-v15-staging-source-ci-20261031';

export function checkRecovery(inventory, stagedChanges, health) {
  const errors = [];
  const warnings = [];
  const reject = (code) => { if (!errors.includes(code)) errors.push(code); };
  if (inventory?.project?.name !== EXPECTED_PROJECT) reject('wrong_project');
  if (!inventory?.environment?.id || inventory?.environment?.id !== health?.environment?.id) {
    reject('environment_mismatch');
  }
  const services = Array.isArray(inventory?.services) ? inventory.services : [];
  const wp = services.find((x) => x.name === 'WordPress-UAT');
  const db = services.find((x) => x.name === 'MariaDB');
  if (!wp) reject('wordpress_service_missing');
  if (!db) reject('database_service_missing');
  if (wp) {
    if (wp.source?.repo !== EXPECTED_REPO) reject('wrong_source_repo');
    if (wp.source?.branch !== EXPECTED_BRANCH) reject('wrong_source_branch');
    if (wp.state !== 'live') reject('wordpress_staged_or_not_live');
    if (!wp.latestDeployment || wp.latestDeployment.status !== 'SUCCESS') {
      reject('wordpress_deployment_not_successful');
    }
  }
  if (db) {
    const volume = Array.isArray(db.volumeMounts) && db.volumeMounts.some(
      (v) => v.mountPath === '/var/lib/mysql' && Boolean(v.volumeId)
    );
    if (!volume) reject('database_volume_not_mounted');
  }

  // We never accept a staged deployment with unknown changes; it can delete
  // services or silently switch the GitHub branch away from the reviewed PR.
  if (inventory?.staged?.changeCount > 0 ||
      stagedChanges?.staged?.changeCount > 0 ||
      stagedChanges?.destructive === true ||
      (Array.isArray(stagedChanges?.resources) && stagedChanges.resources.length > 0)) {
    reject('unreviewed_staged_patch');
  }
  if (stagedChanges?.destructive === true ||
      stagedChanges?.resources?.some((item) => item.action === 'delete')) {
    reject('destructive_staged_patch');
  }
  const live = Array.isArray(health?.services) ? health.services : [];
  for (const [name, service] of [['WordPress-UAT', wp], ['MariaDB', db]]) {
    const state = live.find((item) => item.serviceId === service?.id);
    if (!state || state.state !== 'online') reject(name === 'MariaDB' ? 'database_offline' : 'wordpress_offline');
  }
  // The provider inventory does not attest application database sanitization
  // or Git SHA equality. Those require authenticated WordPress health and
  // synthetic Flutter smoke tests AFTER the target is healthy.
  warnings.push('source_sha_and_synthetic_seed_must_be_verified_via_authenticated_uat');
  warnings.push('backup_restore_and_user_login_uat_still_required');
  return { readyForLoginUat: errors.length === 0, errors, warnings };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const flags = Object.fromEntries(process.argv.slice(2).reduce((acc, val, i, args) => {
    if (val.startsWith('--') && args[i + 1]) acc.push([val.slice(2), args[i + 1]]);
    return acc;
  }, []));
  if (!flags.inventory || !flags.staged || !flags.health) {
    process.stderr.write('Usage: node uat/railway/recovery-preflight.mjs --inventory inventory.json --staged changes.json --health status.json\n');
    process.exit(2);
  }
  const read = (file) => JSON.parse(readFileSync(file, 'utf8'));
  try {
    const output = checkRecovery(read(flags.inventory), read(flags.staged), read(flags.health));
    process.stdout.write(JSON.stringify(output, null, 2) + '\n');
    process.exit(output.readyForLoginUat ? 0 : 1);
  } catch {
    // Never print snapshot contents: they might contain resource metadata.
    process.stderr.write('Recovery preflight could not parse one or more snapshots.\n');
    process.exit(2);
  }
}
