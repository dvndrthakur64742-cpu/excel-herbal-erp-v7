from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f'Expected patch target not found: {label}')


def require(path: Path, needles: list[str], label: str) -> None:
    text = path.read_text(encoding='utf-8')
    for item in needles:
        if item not in text:
            raise SystemExit(f'{label} invariant missing: {item}')


def forbid(path: Path, needles: list[str], label: str) -> None:
    text = path.read_text(encoding='utf-8')
    for item in needles:
        if item in text:
            raise SystemExit(f'{label} forbidden source still present: {item}')


def patch_shell() -> None:
    path = ROOT / 'lib/shell/app_shell.dart'
    text = path.read_text(encoding='utf-8')

    text = replace_once(
        text,
        """                _desktopTile(\n                  'erp_tools',\n                  'ERP Tools',\n                  Icons.construction_outlined,\n                ),""",
        """                if (app.erpToolsVisible)\n                  _desktopTile(\n                    'erp_tools',\n                    'ERP Tools',\n                    Icons.construction_outlined,\n                  ),""",
        'desktop ERP Tools visibility',
    )

    text = replace_once(
        text,
        """                  _drawerTile(\n                    app: app,\n                    id: 'erp_tools',\n                    label: 'ERP Tools',\n                    icon: Icons.tune_rounded,\n                  ),""",
        """                  if (app.erpToolsVisible)\n                    _drawerTile(\n                      app: app,\n                      id: 'erp_tools',\n                      label: 'ERP Tools',\n                      icon: Icons.tune_rounded,\n                    ),""",
        'mobile ERP Tools visibility',
    )

    text = replace_once(
        text,
        "if (const {'home', 'profile', 'erp_tools'}.contains(id)) return true;",
        """if (const {'home', 'profile'}.contains(id)) return true;\n    if (id == 'erp_tools') return app.erpToolsVisible;""",
        'route gate',
    )

    if "{'home', 'profile', 'erp_tools'}" in text:
        raise SystemExit('Unconditional ERP Tools route authority still present')
    path.write_text(text, encoding='utf-8')


def patch_erp_tools() -> None:
    path = ROOT / 'lib/screens/tools/erp_tools_screen.dart'
    text = path.read_text(encoding='utf-8')

    text = replace_once(
        text,
        """    final tabs = <(String, IconData, Widget)>[\n      ('Duty', Icons.location_on_outlined, _dutyTab(app)),\n      ('My Account', Icons.badge_outlined, _accountTab(app)),\n      ('Communication', Icons.notifications_outlined, _communicationTab(app)),""",
        """    final tabs = <(String, IconData, Widget)>[\n      if (app.can('workforce.attendance.self'))\n        ('Duty', Icons.location_on_outlined, _dutyTab(app)),\n      ('My Account', Icons.badge_outlined, _accountTab(app)),\n      if (app.can('communication.view'))\n        ('Communication', Icons.notifications_outlined, _communicationTab(app)),""",
        'ERP Tools tab authority',
    )

    text = text.replace(
        "tracker.active\n                                ? 'Tracking active'\n                                : 'Tracking stopped'",
        "BusinessFormat.status(tracker.dutyStatus)",
    )
    text = text.replace(
        "tracker.active ? 'ACTIVE' : 'OFF'",
        "BusinessFormat.status(tracker.dutyStatus).toUpperCase()",
    )
    text = text.replace(
        "'Start duty tracking after check-in to record today’s route.'",
        "'Check in first. Duty route tracking starts automatically inside the server-owned GPS window.'",
    )

    start_label = "label: const Text('Start')"
    sync_label = "label: const Text('Sync current location now')"
    if start_label in text or sync_label in text:
        start_at = text.rfind(
            "                const SizedBox(height: 16),",
            0,
            text.index(start_label),
        )
        if start_at < 0:
            raise SystemExit('Could not find GPS manual controls start boundary')
        sync_pos = text.index(sync_label)
        end_marker = "\n              ],\n            ),\n          ),\n          const SizedBox(height: 14),"
        end_at = text.find(end_marker, sync_pos)
        if end_at < 0:
            raise SystemExit('Could not find GPS manual controls end boundary')

        replacement = """                const SizedBox(height: 16),\n                Container(\n                  width: double.infinity,\n                  padding: const EdgeInsets.all(12),\n                  decoration: BoxDecoration(\n                    color: ExcelBrand.primarySoft,\n                    borderRadius: BorderRadius.circular(14),\n                  ),\n                  child: const Row(\n                    crossAxisAlignment: CrossAxisAlignment.start,\n                    children: [\n                      Icon(\n                        Icons.policy_outlined,\n                        size: 19,\n                        color: ExcelBrand.primaryDark,\n                      ),\n                      SizedBox(width: 8),\n                      Expanded(\n                        child: Text(\n                          'Duty GPS starts automatically from attendance/server policy and stops after checkout or the duty cutoff. There is no manual route Start/Stop.',\n                          style: TextStyle(fontWeight: FontWeight.w600),\n                        ),\n                      ),\n                    ],\n                  ),\n                ),\n                const SizedBox(height: 8),\n                SizedBox(\n                  width: double.infinity,\n                  child: OutlinedButton.icon(\n                    onPressed: tracker.sending\n                        ? null\n                        : () async {\n                            await ref.read(gpsTrackingProvider).sync();\n                            if (mounted) {\n                              _msg('Duty GPS status refreshed.');\n                            }\n                          },\n                    icon: tracker.sending\n                        ? const SizedBox(\n                            width: 16,\n                            height: 16,\n                            child: CircularProgressIndicator(strokeWidth: 2),\n                          )\n                        : const Icon(Icons.sync_rounded),\n                    label: const Text('Refresh duty GPS status'),\n                  ),\n                ),"""
        text = text[:start_at] + replacement + text[end_at:]

    path.write_text(text, encoding='utf-8')


def verify_current_frontend() -> None:
    shell = ROOT / 'lib/shell/app_shell.dart'
    tools = ROOT / 'lib/screens/tools/erp_tools_screen.dart'
    state = ROOT / 'lib/state/app_state.dart'
    reports = ROOT / 'lib/screens/reports/reports_screen.dart'
    designations = ROOT / 'lib/screens/organization/employee_designations_screen.dart'
    team = ROOT / 'lib/screens/organization/team_screen.dart'
    home = ROOT / 'lib/screens/home/home_screen.dart'

    require(shell, [
        'if (app.erpToolsVisible)',
        "if (id == 'erp_tools') return app.erpToolsVisible;",
    ], 'Shell')
    forbid(shell, ["{'home', 'profile', 'erp_tools'}"], 'Shell')

    require(tools, [
        "if (app.can('workforce.attendance.self'))",
        'Refresh duty GPS status',
        'There is no manual route Start/Stop.',
        'BusinessFormat.status(tracker.dutyStatus)',
    ], 'ERP Tools')
    forbid(tools, [
        "label: const Text('Start')",
        "label: const Text('Stop')",
        "label: const Text('Sync current location now')",
        'ref.read(gpsTrackingProvider).stop()',
    ], 'ERP Tools')

    require(state, [
        'bool get managementDashboardVisible =>',
        "sectionVisible('team') && can('reports.view')",
        "if (id == 'erp_tools') return erpToolsVisible;",
        'additional_designations_authority_inherited',
    ], 'AppState')

    require(reports, [
        "if (app.can('reports.view'))",
        "if (app.can('finance.accounting.view'))",
        "'price_distribution'",
        'Reporting category filters rows only. It never expands employee or branch authority.',
    ], 'Reports')

    require(designations, [
        "ApiPaths.employeeReportingManager(widget.employeeId)",
        "'reporting_employee_id': selected == 0 ? null : selected",
        "'reason': why",
        'The server blocks self-reporting, reporting cycles and managers outside your branch authority.',
        'Extra designations never inherit authority.',
    ], 'Designation & Reporting')

    require(team, [
        "if (app.can('workforce.attendance.manage'))",
        'ApiPaths.gpsTeam',
        'ApiPaths.gpsRoute',
        'Route visibility follows the same reporting hierarchy and authorised branch scope as the team list.',
    ], 'Team Operations')

    require(home, [
        'app.managementDashboardVisible',
        'Report access is available, but Team management scope is not assigned.',
        'route lifecycle is automatic',
    ], 'Home')


if __name__ == '__main__':
    patch_shell()
    patch_erp_tools()
    verify_current_frontend()
    print('Hierarchy/reporting/GPS/dashboard frontend invariants: PASS')
