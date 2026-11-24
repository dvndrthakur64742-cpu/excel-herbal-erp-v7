/**
 * Verify real WordPress REST denied-data response in isolated synthetic UAT.
 *
 * Permission errors must be HTTP 403, carry a precise business error code,
 * and NEVER include a data field with payroll/stock/employee information.
 */
export function assertForbiddenReply(response, expectedCode, label) {
  if (!response || response.code !== 403 ||
    response.body?.ok !== false ||
    response.body?.error?.code !== expectedCode ||
    Object.hasOwn(response.body || {}, 'data')) {
    throw new Error('Forbidden route not denied safely: ' + label);
  }
}
