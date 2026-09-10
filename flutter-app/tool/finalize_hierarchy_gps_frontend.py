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
    branch_selector = ROOT / 'lib/widgets/branch_selector.dart'
    designations = ROOT / 'lib/screens/organization/employee_designations_screen.dart'
    team = ROOT / 'lib/screens/organization/team_screen.dart'
    home = ROOT / 'lib/screens/home/home_screen.dart'
    profile = ROOT / 'lib/screens/home/profile_screen.dart'
    login = ROOT / 'lib/screens/auth/login_screen.dart'
    ui_error = ROOT / 'lib/core/ui_error.dart'
    administration = ROOT / 'lib/screens/administration/administration_screen.dart'
    authority_test = ROOT / 'test/authority_projection_test.dart'
    role_matrix_test = ROOT / 'test/role_projection_matrix_test.dart'

    require(
        shell,
        [
            'if (app.erpToolsVisible)',
            "if (id == 'erp_tools') return app.erpToolsVisible;",
            "'assets/branding/excel-herbal-logo.webp'",
            "'My Account & Duty'",
            "'WORKSPACE TOOLS'",
        ],
        'Shell',
    )
    forbid(
        shell,
        [
            "{'home', 'profile', 'erp_tools'}",
            "label: 'ERP Tools'",
            "'TOOLS & CONTROL'",
        ],
        'Shell',
    )

    require(
        tools,
        [
            "if (app.can('workforce.attendance.self'))",
            "title: const Text('My Account & Duty')",
            "if (app.can('organization.employee.manage'))",
            "('Team Access', Icons.manage_accounts_outlined, _teamAccessTab())",
            'Refresh duty GPS status',
            'There is no manual route Start/Stop.',
            'BusinessFormat.status(tracker.dutyStatus)',
            "'branch_id': app.currentBranchId",
        ],
        'Account & Duty',
    )
    forbid(
        tools,
        [
            "title: const Text('ERP Tools')",
            "label: const Text('Start')",
            "label: const Text('Stop')",
            "label: const Text('Sync current location now')",
            'ref.read(gpsTrackingProvider).stop()',
            'Backend Diagnostics',
            'App Version Policy',
            'ApiPaths.diagnostics',
            'ApiPaths.maintenanceCleanup',
            'ApiPaths.appVersionPolicy',
            'PackageInfo.fromPlatform()',
            'Ye holiday',
            'Is device par bhi',
            'housekeeping run karega',
            'secure channel se batayein',
            'sessions logout ho jayenge',
            'characters rakhein',
        ],
        'Account & Duty',
    )

    require(
        state,
        [
            'bool get businessAccessBlocked =>',
            "if (businessAccessBlocked && capability != 'erp.access') return false;",
            'if (businessAccessBlocked) {',
            "{'id': 'home', 'label': 'Home'},",
            "{'id': 'profile', 'label': 'Profile'},",
            'if (!businessAccessBlocked) return projected;',
            ".where((section) => '${section['id']}' == 'home')",
            'bool get managementDashboardVisible =>',
            "sectionVisible('team') && can('reports.view')",
            "if (id == 'erp_tools') return erpToolsVisible;",
            'additional_designations_authority_inherited',
            "'organization.employee.manage',",
            'void selectAllAuthorisedBranches()',
            'if (!state.branchSelectorVisible || state.businessAccessBlocked) return;',
            'currentBranchId: null,',
        ],
        'AppState',
    )
    forbid(
        state,
        [
            "'administration.access.manage',\n        'administration.audit.view',",
        ],
        'AppState workspace visibility',
    )

    require(
        branch_selector,
        [
            'this.allowAllAuthorised = false',
            'final bool allowAllAuthorised;',
            "child: Text('All Authorised Branches')",
            'selectAllAuthorisedBranches()',
            'if (value == -1 && allowAllAuthorised)',
        ],
        'Branch selector',
    )

    require(
        reports,
        [
            'final available = _availableReports(app);',
            'final activeType = available.any((item) => item.id == type)',
            "!const {'trial', 'price_distribution'}.contains(activeType)",
            'BranchSelector(allowAllAuthorised: !needsBranch)',
            "if (app.currentBranchId != null) 'branch_id': app.currentBranchId",
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
            "final active = _isActive(row['active']);",
            "if (id <= 0 || !_isActive(row['active'])) return;",
            "final text = '$value'.trim().toLowerCase();",
            "return text == '1' || text == 'true';",
            'Enter at least 5 characters for the audit reason.',
            'errorText: reasonError',
            'Field Executive/ASM/SM hierarchy visibility can remain incomplete',
        ],
        'Designation & Reporting',
    )
    forbid(
        designations,
        [
            "row['active'] != 0",
            "row['active'] == 0",
            'Reporting-manager reason minimum 5 characters hona chahiye.',
        ],
        'Designation & Reporting',
    )

    require(
        team,
        [
            "if (app.can('workforce.attendance.manage'))",
            "'Hierarchy'",
            'Reporting Hierarchy Readiness',
            "'FIELD_EXECUTIVE'",
            "'ASM'",
            "'SM'",
            "row['reporting_category']",
            "'status': 'active'",
            "'limit': 200",
            "'organization.employee.manage'",
            'No manager is auto-assigned.',
            'Reporting Category is used only to classify readiness; it never creates authority.',
            'Additional Designations also do not create authority.',
            'No attendance records for the selected period.',
            'Select an authorised branch to continue.',
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
        profile,
        [
            "label: 'Primary Designation'",
            "label: 'Reporting Category'",
            "label: 'Reporting Manager'",
            'Reporting group only. It does not increase role permissions or branch authority.',
            'These are responsibility/display assignments only; they do not inherit authority.',
            "label: const Text('Sign out')",
        ],
        'Profile',
    )
    forbid(
        profile,
        [
            'permission/branch authority नहीं बढ़ती।',
            "label: const Text('Logout')",
        ],
        'Profile',
    )

    require(
        login,
        [
            'String? validationError;',
            'final error = validationError ?? app.error;',
            "validationError = 'Enter your mobile number.'",
            "validationError = 'Enter your password.'",
            "'assets/branding/excel-herbal-logo.webp'",
            "const Text('SIGN IN')",
        ],
        'Login',
    )
    forbid(
        login,
        [
            'UiError.message(Exception(app.error!))',
            "import '../../core/ui_error.dart';",
        ],
        'Login',
    )

    require(
        ui_error,
        [
            'Your session has expired. Please sign in again.',
            'Your role is not authorised for this action.',
            'You do not have access to the selected branch.',
            'Attendance check-in is required before duty GPS tracking can begin.',
            'Too many attempts were made. Please try again later.',
        ],
        'UI errors',
    )
    forbid(
        ui_error,
        [
            'check karein',
            'Dobara sign in karein',
            'permission nahi hai',
            'sync nahi hua',
            'access available nahi hai',
            'pehle se bana hua hai',
            'Thodi der baad retry karein',
        ],
        'UI errors',
    )

    require(
        administration,
        [
            "import '../../widgets/branch_selector.dart';",
            'child: BranchSelector()',
            'Select an authorised branch to manage access.',
            'Primary designation defaults apply automatically.',
            'Individual Grant/Deny overrides are unavailable for this employee access record.',
            'Access change reason must contain at least 5 characters.',
            "message = 'Saved successfully.';",
        ],
        'Administration',
    )
    forbid(
        administration,
        [
            'Koi reversal request nahi hai.',
            'Authorised branch select karein.',
            'journal aur audit chain backend se reverse honge',
            'Ye stock, outstanding',
            'backend v7.1.7 alignment',
            'minimum 5 characters hona chahiye',
            "message = 'Done: $r';",
        ],
        'Administration',
    )

    require(
        authority_test,
        [
            'additional designation never manufactures authority',
            'reporting category alone is grouping and never grants authority',
            'authority inheritance marker cannot manufacture client permissions',
            'reports-only role does not get management dashboard',
            'stale ERP Tools bottom-nav entry is hidden without tool authority',
            'technical admin caps alone do not expose account duty workspace',
            'aggregate branch scope remains limited to authorised branch ids',
            'zero branch authority blocks business access even with capabilities',
            "expect(state.can('reports.view'), isFalse);",
            "expect(state.sections.map((e) => e['id']), ['home']);",
            "expect(state.bottomNav.map((e) => e['id']), ['home', 'profile']);",
        ],
        'Authority regression tests',
    )

    require(
        role_matrix_test,
        [
            'field employee remains self-service only',
            "for (final role in const ['ASM', 'SM'])",
            'branch manager gets branch management overview without system admin',
            "for (final role in const ['RM', 'RC', 'AGM', 'ZI'])",
            "for (final role in const ['CM', 'MD'])",
            'system admin can project administration without changing hierarchy rules',
            'accounting-only profile gets accounting but no team dashboard',
            'zero authorised branches blocks business access for every role',
            "expect(state.can('reports.view'), isFalse);",
            "expect(state.sectionVisible('administration'), isFalse);",
            "expect(state.bottomNav.map((e) => e['id']), ['home', 'profile']);",
        ],
        'Role projection matrix tests',
    )


if __name__ == '__main__':
    verify_current_frontend()
    print('Hierarchy/reporting/GPS/dashboard frontend invariants: PASS')
