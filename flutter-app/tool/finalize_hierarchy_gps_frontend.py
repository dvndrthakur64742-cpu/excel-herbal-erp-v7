from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


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


def verify_current_frontend() -> None:
    shell = ROOT / 'lib/shell/app_shell.dart'
    tools = ROOT / 'lib/screens/tools/erp_tools_screen.dart'
    state = ROOT / 'lib/state/app_state.dart'
    reports = ROOT / 'lib/screens/reports/reports_screen.dart'
    designations = ROOT / 'lib/screens/organization/employee_designations_screen.dart'
    team = ROOT / 'lib/screens/organization/team_screen.dart'
    home = ROOT / 'lib/screens/home/home_screen.dart'
    authority_test = ROOT / 'test/authority_projection_test.dart'

    require(
        shell,
        [
            'if (app.erpToolsVisible)',
            "if (id == 'erp_tools') return app.erpToolsVisible;",
        ],
        'Shell',
    )
    forbid(shell, ["{'home', 'profile', 'erp_tools'}"], 'Shell')

    require(
        tools,
        [
            "if (app.can('workforce.attendance.self'))",
            'Refresh duty GPS status',
            'There is no manual route Start/Stop.',
            'BusinessFormat.status(tracker.dutyStatus)',
        ],
        'ERP Tools',
    )
    forbid(
        tools,
        [
            "label: const Text('Start')",
            "label: const Text('Stop')",
            "label: const Text('Sync current location now')",
            'ref.read(gpsTrackingProvider).stop()',
        ],
        'ERP Tools',
    )

    require(
        state,
        [
            'bool get managementDashboardVisible =>',
            "sectionVisible('team') && can('reports.view')",
            "if (id == 'erp_tools') return erpToolsVisible;",
            'additional_designations_authority_inherited',
        ],
        'AppState',
    )

    require(
        reports,
        [
            'final available = _availableReports(app);',
            'final activeType = available.any((item) => item.id == type)',
            "if (app.can('reports.view'))",
            "if (app.can('finance.accounting.view'))",
            "'price_distribution'",
            'Reporting category filters rows only. It never expands employee or branch authority.',
        ],
        'Reports',
    )

    require(
        designations,
        [
            'ApiPaths.employeeReportingManager(widget.employeeId)',
            "'reporting_employee_id': selected == 0 ? null : selected",
            "'reason': why",
            'The server blocks self-reporting, reporting cycles and managers outside your branch authority.',
            'Extra designations never inherit authority.',
        ],
        'Designation & Reporting',
    )

    require(
        team,
        [
            "if (app.can('workforce.attendance.manage'))",
            "'Hierarchy'",
            'Reporting Hierarchy Readiness',
            "'status': 'active'",
            "'limit': 200",
            "'organization.employee.manage'",
            'No manager is auto-assigned.',
            'Reporting Category and Additional Designations are not used to create authority.',
            'ApiPaths.gpsTeam',
            'ApiPaths.gpsRoute',
            'Route visibility follows the same reporting hierarchy and authorised branch scope as the team list.',
        ],
        'Team Operations',
    )

    require(
        home,
        [
            'app.managementDashboardVisible',
            'Report access is available, but Team management scope is not assigned.',
            'route lifecycle is automatic',
        ],
        'Home',
    )

    require(
        authority_test,
        [
            'additional designation never manufactures authority',
            'reporting category alone is grouping and never grants authority',
            'authority inheritance marker cannot manufacture client permissions',
            'reports-only role does not get management dashboard',
            'stale ERP Tools bottom-nav entry is hidden without tool authority',
            'zero branch authority blocks business access even with capabilities',
        ],
        'Authority regression tests',
    )


if __name__ == '__main__':
    verify_current_frontend()
    print('Hierarchy/reporting/GPS/dashboard frontend invariants: PASS')
