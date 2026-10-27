# V8 Homepage Wrapper Fix — Development-only

2026-10-22 Lighthouse mobile audit of `https://office.excelherbal.in/` showed **accessibility 84/100** and **best practices 81/100**, while performance score was unavailable. The public root wrapper was `<html><head><title>Excel Herbal ERP v7</title>...`, missing `lang`; its actual iframe pointed to the correctly installed V8 Flutter web. The Flutter `web/index.html` already declares `lang="en"`.

New V8 FrontendShell generates a small branded `<html lang="en">` wrapper with an accessible iframe title and no-index policy. It only runs on the approved staging hostname/root with matching DB schema AND matching on-disk frontend source commit; on any mismatch it yields to the existing WordPress/legacy route, without altering records or disabling plugins. It does not claim a performance improvement without a real post-deployment Lighthouse remeasurement.

**Release note:** This code is NOT active on the current WordPress site until the new unified V8 plugin is separately staged, verified, and activated after backup/UAT checks.
