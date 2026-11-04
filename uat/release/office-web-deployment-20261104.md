# Office Web deployment — 2026-11-04

Authorized through the existing Hostinger File Manager session.

- Office root identified as public_html/office (main company website left untouched).
- wp-config.php WP_ENVIRONMENT_TYPE changed from staging to production. ERP health verified environment=production and office_environment_mismatch=false.
- Reviewed GitHub artifact 13319932040, source 3b67814a9608aaea0a78d6c957d710354dbad1bd, original ZIP SHA256 b191274da3b27c84a816d220d61270c1337a6dd4cb2fc32520f24873db8ec701.
- Original ZIP CRC and manifest hashes checked before packaging. Office API target confirmed; UAT hostname and UAT BUILD string absent.
- Deployed to wp-content/uploads/eh7-web-3b67814/. index.html base href adjusted for that folder. Compiled JavaScript unchanged. Original review metadata/checksum files omitted from deployment because index differs.
- Added an external-to-WordPress-markers .htaccess block: RewriteEngine On; RewriteRule ^$ wp-content/uploads/eh7-web-3b67814/index.html [L]. Existing WordPress rules retained.
- Browser confirmed https://office.excelherbal.in/ stays at root and serves the new green ERP Workspace frontend. Existing authorized admin session restored successfully. Dashboard and Sales customer-list read-only navigation loaded.
- Previous frontend remains intact at wp-content/uploads/eh7-flutter-web/. Frontend rollback: restore only the root rewrite target to wp-content/uploads/eh7-flutter-web/index.html. Environment rollback, if necessary, is the original staging constant.
- No database migration, record edits, payments, payroll or stock actions performed.

## Limits
This is source 3b67814, not login-help commit 34fce25. Login-help/autofill changes still require Flutter CI and a later build. Fresh employee password login, role/device UAT, mobile layouts, transaction acceptance and full DB recovery were not certified by this deployment. Root mapping does not redirect old bookmarked asset URLs; users should use the short root URL.
