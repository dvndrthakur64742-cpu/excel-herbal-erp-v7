# ERP V7 + V15 Staging Source

This directory contains the WordPress plugin candidate **7.3.6-rc1**, sourced from:
`Excel-Herbal-ERP-V7-V15-Field-Sales-Integration-7.3.6-rc1-STAGING.zip`

Source ZIP SHA256:
`006b15dff3e4fc5a0f7a9e773c07aa061358a0aa8c86ee05e0100a85dbca7969`

## Development commands

From the repository root:

```bash
cd plugin/excel-herbal-erp-v7
bash tests/run.sh
python3 tests/static_checks.py
```

These cover PHP syntax, pure field-sales rules, existing regression checks, and static routes/contracts. Database-backed integration and live WordPress/Flutter behavior are **NOT covered** by this local test stage.

## Release controls
- Never deploy this staging candidate directly to production.
- Keep `main` protected by review and passing checks.
- Smoke test in isolated UAT with sanitized fixtures and a clean database.
- Review pending Railway project changes before any deployment.
- Avoid committing credentials, real employee/customer data, database dumps, or wp-config.php.
- A separately versioned Flutter client must support the new morning issue states: reviewed, approved, awaiting receipt.
- WPVibe verification required for actual production WordPress compatibility and migrations.

See `RELEASE-7.3.6-rc1.md` and `MIGRATION-AND-ROLLBACK.md` for scope and rollback precautions.
