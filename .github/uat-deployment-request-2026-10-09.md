# Controlled BUILD/UAT deployment request — 2026-10-09

This non-runtime record authorizes one controlled UAT deployment attempt through the existing ERP correction verification workflow on the `codex/erp735-document-integration` branch.

- Previous verified source head: `32397e9c627b367702d6a8044b2030ac02ee2866`
- Previous CI: `37924615652` — PHP/MariaDB and Flutter/Web verification **SUCCESS**
- Target: `https://office.excelherbal.in` (BUILD/UAT only)
- Requested changes: deploy the code fixing the WordPress portable ZIP entries and Daily Order > Continue Closing decimal PCS normalization
- After deploy: require backend and web source markers to match the *new triggered commit*, verify main.dart.js and SHA256SUMS.txt, and smoke-test the order closing screen and daily-order integrity
- Release gates: remain fail-closed; no production approval, merge, schema/data migration, or permission bypass. The staging-safety and host-hardening findings must be recorded, not circumvented.
- The job may require WordPress administrator sign-in on the authorized self-hosted Windows runner.

This file is metadata only. It does not alter ERP runtime logic, permissions, or production configuration.
