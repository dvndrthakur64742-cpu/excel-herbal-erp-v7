import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/api_paths.dart';
import '../core/app_config.dart';
import '../core/bootstrap_projection.dart';
import '../core/providers.dart';
import '../core/secure_session.dart';
import '../core/ui_error.dart';

class AppState {
  const AppState({
    this.loading = true,
    this.authenticated = false,
    this.bootstrap,
    this.currentBranchId,
    this.error,
  });

  final bool loading;
  final bool authenticated;
  final Map<String, dynamic>? bootstrap;
  final int? currentBranchId;
  final String? error;

  BootstrapProjection get projection => BootstrapProjection.fromMap(bootstrap);

  List<Map<String, dynamic>> get branches =>
      projection.branches.map((branch) => branch.raw).toList(growable: false);

  Map<String, dynamic> get me => projection.identity.raw;

  Map<String, dynamic> get employee => projection.identity.employee.raw;

  Map<String, dynamic> get company => projection.company.raw;

  String get companyName => projection.company.name;

  String get employeeName {
    final name = projection.identity.employee.fullName;
    return name.isEmpty ? 'ERP User' : name;
  }

  String get primaryDesignationCode =>
      projection.identity.employee.designationCode;

  String get primaryDesignationName {
    final name = projection.identity.employee.designationName;
    return name.isNotEmpty ? name : primaryDesignationCode;
  }

  String get primaryDesignationLabel {
    final name = primaryDesignationName;
    final code = primaryDesignationCode;
    if (name.isEmpty) return '—';
    if (code.isEmpty || name.toUpperCase() == code.toUpperCase()) return name;
    return '$name ($code)';
  }

  /// Reporting category is a dashboard/reporting grouping only. It must never
  /// be treated as a permission or branch-authority source on the client.
  String get reportingCategory =>
      projection.identity.employee.reportingCategory;

  List<Map<String, dynamic>> get additionalDesignations =>
      ((employee['additional_designations'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);

  bool get additionalDesignationAuthorityInherited =>
      employee['additional_designations_authority_inherited'] == true;

  bool get businessAccessBlocked => projection.identity.branchIds.isEmpty;

  /// A management summary is only appropriate when the server projected the
  /// Team workspace and the actor also has report authority. reports.view by
  /// itself (for example an accounting-only role) does not imply team scope.
  bool get managementDashboardVisible =>
      sectionVisible('team') && can('reports.view');

  /// This business-facing workspace contains self-service, communication and
  /// employee-login management only. Technical administration capabilities do
  /// not make the workspace visible by themselves.
  bool get erpToolsVisible => canAny(const [
        'workforce.attendance.self',
        'workforce.leave.self',
        'workforce.field_visit.self',
        'communication.view',
        'organization.employee.manage',
      ]);

  String get currentBranchName {
    if (businessAccessBlocked) return 'No Authorised Branch';
    if (currentBranchId == null) return 'All Authorised Branches';
    for (final branch in projection.branches) {
      if (branch.id == currentBranchId) return branch.label;
    }
    return 'Authorised Branch';
  }

  /// Server-projected ERP business date in WordPress business timezone.
  /// Invalid calendar dates are rejected instead of silently normalised.
  String? get serverBusinessDate {
    final raw = '${bootstrap?['business_date'] ?? ''}'.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return null;
    final parsed = DateTime.tryParse('${raw}T00:00:00Z');
    if (parsed == null) return null;
    final normalized =
        '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
    return normalized == raw ? raw : null;
  }

  bool get usingFallbackBusinessDate => serverBusinessDate == null;

  /// Production must never post ERP transactions using an untrusted device
  /// date. Local-date fallback is deliberately limited to build/UAT mode.
  String get businessDate {
    final projected = serverBusinessDate;
    if (projected != null) return projected;
    if (AppConfig.isProduction) {
      throw StateError('ERP server business date is unavailable or invalid.');
    }
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  String get businessMonthStart => '${businessDate.substring(0, 8)}01';
  List<String> get capabilities => projection.identity.capabilities;

  /// No branch authority means no business capability may be exercised on the
  /// client. The raw server projection remains inspectable through
  /// [capabilities], but UI permission checks fail closed until a branch is
  /// authorised. `erp.access` is retained only for the authenticated shell.
  bool can(String capability) {
    if (businessAccessBlocked && capability != 'erp.access') return false;
    return capabilities.contains(capability);
  }

  bool canAny(Iterable<String> wanted) => wanted.any(can);
  bool sectionVisible(String id) => sections.any((s) => '${s['id']}' == id);

  /// Navigation is server-projected, but capability filters are repeated here
  /// defensively so a stale bootstrap/navigation cache cannot expose a tool
  /// entry that the current actor is not allowed to open.
  List<Map<String, dynamic>> get bottomNav {
    if (businessAccessBlocked) {
      return const [
        {'id': 'home', 'label': 'Home'},
        {'id': 'profile', 'label': 'Profile'},
      ];
    }
    final items =
        (((bootstrap?['navigation'] as Map?)?['bottom_nav'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    return items.where((item) {
      final id = '${item['id']}';
      if (id == 'erp_tools') return erpToolsVisible;
      return true;
    }).toList(growable: false);
  }

  bool get branchSelectorVisible =>
      projection.branches.length > 1 &&
      projection.identity.branchSelectorVisible;

  List<Map<String, dynamic>> get sections {
    final projected =
        (((bootstrap?['navigation'] as Map?)?['sections'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    if (!businessAccessBlocked) return projected;
    return projected
        .where((section) => '${section['id']}' == 'home')
        .toList(growable: false);
  }

  AppState copyWith({
    bool? loading,
    bool? authenticated,
    Map<String, dynamic>? bootstrap,
    int? currentBranchId,
    String? error,
    bool clearError = false,
  }) => AppState(
    loading: loading ?? this.loading,
    authenticated: authenticated ?? this.authenticated,
    bootstrap: bootstrap ?? this.bootstrap,
    currentBranchId: currentBranchId ?? this.currentBranchId,
    error: clearError ? null : (error ?? this.error),
  );
}

class AppController extends StateNotifier<AppState> {
  AppController(this.api, this.session) : super(const AppState()) {
    initialize();
  }

  final ApiClient api;
  final SecureSession session;

  Future<void> initialize() async {
    final token = await session.accessToken();
    if (token == null || token.isEmpty) {
      state = const AppState(loading: false);
      return;
    }
    await refreshBootstrap();
  }

  Future<void> login(String mobile, String password) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await api.login(mobile, password);
      await refreshBootstrap();
    } catch (e) {
      state = AppState(loading: false, error: UiError.message(e));
    }
  }

  Future<void> refreshBootstrap() async {
    try {
      final data = Map<String, dynamic>.from(
        await api.get(ApiPaths.bootstrap) as Map,
      );
      final projection = BootstrapProjection.fromMap(data);
      final ids = projection.identity.branchIds;
      final assigned = projection.identity.assignedBranchId;
      final current =
          state.currentBranchId != null && ids.contains(state.currentBranchId)
          ? state.currentBranchId
          : (ids.length == 1
                ? ids.first
                : (assigned != null && ids.contains(assigned)
                      ? assigned
                      : null));
      state = AppState(
        loading: false,
        authenticated: true,
        bootstrap: data,
        currentBranchId: current,
      );
    } on ApiException catch (e) {
      // 403 means authenticated but not authorised for that resource. It must
      // never destroy a valid employee session.
      if (e.statusCode == 401) {
        await session.clear();
        state = AppState(loading: false, error: UiError.message(e));
        return;
      }
      final token = await session.accessToken();
      state = state.copyWith(
        loading: false,
        authenticated: state.authenticated || (token?.isNotEmpty ?? false),
        error: UiError.message(e),
      );
    } catch (e) {
      final token = await session.accessToken();
      state = state.copyWith(
        loading: false,
        authenticated: state.authenticated || (token?.isNotEmpty ?? false),
        error: UiError.message(e),
      );
    }
  }

  void selectBranch(int id) {
    final ids = state.projection.branches.map((branch) => branch.id).toSet();
    if (ids.contains(id)) {
      state = state.copyWith(currentBranchId: id, clearError: true);
    }
  }

  /// Clears only the current branch selection. Authorised branch IDs remain
  /// server-projected in bootstrap and are never expanded.
  void selectAllAuthorisedBranches() {
    if (!state.branchSelectorVisible || state.businessAccessBlocked) return;
    state = AppState(
      loading: state.loading,
      authenticated: state.authenticated,
      bootstrap: state.bootstrap,
      currentBranchId: null,
      error: null,
    );
  }

  Future<void> logout() async {
    await api.logout();
    state = const AppState(loading: false);
  }
}

final appStateProvider = StateNotifierProvider<AppController, AppState>(
  (ref) => AppController(
    ref.watch(apiClientProvider),
    ref.watch(secureSessionProvider),
  ),
);
