# Privacy & Authority Architecture Correction

Status: BUILD/UAT only. No production deployment or live-data mutation is part of this correction.

## Implemented in the backend

- Basic employee visibility is separated from contact, salary and login metadata.
- Salary history/change/review use dedicated salary capabilities instead of generic payroll run permissions.
- Team GPS uses a dedicated GPS-view capability instead of attendance-management authority.
- Employee private-document list/download/manage permissions are separated.
- Employee peer access is bounded by reporting hierarchy as well as branch authority.
- Only SYSADMIN/ADMIN aliases retain implicit company-wide branch scope; senior business designations are bounded by effective branch authority.

## Canonical access chain

Designation defaults -> assigned role(s) -> explicit employee grant/deny -> branch authority -> reporting hierarchy -> action capability -> sensitive-field capability.

Existing APIs and workflows are reused; this does not introduce a second role, HR, attendance, document or payroll engine.
