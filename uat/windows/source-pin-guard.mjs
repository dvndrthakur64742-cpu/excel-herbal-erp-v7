/**
 * Verify that a localhost WordPress UAT points at the actual Git checkout,
 * not just a stale, self-consistent option/config marker.
 * Pure function: no filesystem, network, credential or data mutation.
 */
export function assertLocalUatSourcePin({credentialSha, gitSha, health}) {
  const valid = (s) => typeof s === 'string' && /^[a-f0-9]{40}$/i.test(s);
  if (!valid(credentialSha) || !valid(gitSha) || !valid(health?.source_head)) {
    throw new Error('Invalid local ERP source SHA; UAT refused');
  }
  if (credentialSha.toLowerCase() !== gitSha.toLowerCase() ||
      health.source_head.toLowerCase() !== gitSha.toLowerCase()) {
    throw new Error(
      'Local ERP source mismatch: checkout, synthetic identity pin and ' +
      'WordPress marker differ; back up, review migration and repin before UAT',
    );
  }
  if (health.environment !== 'staging' ||
      health.uat_bootstrap?.synthetic_only !== true ||
      health.uat_bootstrap?.seeded !== true ||
      health.uat_bootstrap?.source_head_match !== true ||
      health.staging_safety?.sanitized !== true ||
      health.staging_safety?.source_head_match !== true) {
    throw new Error('Unverified source or unsanitized localhost ERP; UAT refused');
  }
}
