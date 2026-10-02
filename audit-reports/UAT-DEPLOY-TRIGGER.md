# Controlled UAT Deployment Trigger

Previous certified head: `9758b8482880fac0a0b0aacc0b745a8a6167586e`

Purpose: trigger the existing BUILD/UAT deployment workflow after automated verification.

Environment scope: BUILD/UAT only. No production/live deployment requested.

Triggered on: 2026-10-01


## Controlled UAT deployment request — 0ad13c810093

- Source head before trigger: `0ad13c810093bd65a2584526a29d2d855c189d87`
- Target: `https://office.excelherbal.in` (BUILD/UAT only)
- Purpose: deploy exact current branch head, then run authenticated runtime screen smoke and evidence capture.
- Production release/merge is explicitly out of scope.
