import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/api_paths.dart';
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

  List<Map<String, dynamic>> get branches =>
      ((bootstrap?['branches'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  Map<String, dynamic> get me =>
      Map<String, dynamic>.from((bootstrap?['me'] as Map?) ?? const {});

  Map<String, dynamic> get company =>
      Map<String, dynamic>.from((bootstrap?['company'] as Map?) ?? const {});

  String get companyName => '${company['name'] ?? 'ERP Company'}'.trim().isEmpty
      ? 'ERP Company'
      : '${company['name']}'.trim();

  String get employeeName {
    final employee = Map<String, dynamic>.from(
      (me['employee'] as Map?) ?? const {},
    );
    final name = '${employee['full_name'] ?? ''}'.trim();
    return name.isEmpty ? 'ERP User' : name;
  }

  String get currentBranchName {
    if (currentBranchId == null) return 'All Authorised Branches';
    for (final branch in branches) {
      if (int.tryParse('${branch['id']}') == currentBranchId) {
        final name = '${branch['name'] ?? branch['code'] ?? ''}'.trim();
        if (name.isNotEmpty) return name;
      }
    }
    return 'Authorised Branch';
  }

  /// ERP business date is supplied by WordPress in its configured business
  /// timezone. Falling back to the device date keeps older backends usable.
  String get businessDate {
    final raw = '${bootstrap?['business_date'] ?? ''}'.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return raw;
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  String get businessMonthStart => '${businessDate.substring(0, 8)}01';

  List<String> get capabilities =>
      ((me['capabilities'] as List?) ?? const []).map((e) => '$e').toList();

  bool can(String capability) => capabilities.contains(capability);
  bool canAny(Iterable<String> wanted) => wanted.any(can);
  bool sectionVisible(String id) => sections.any((s) => '${s['id']}' == id);

  List<Map<String, dynamic>> get bottomNav =>
      (((bootstrap?['navigation'] as Map?)?['bottom_nav'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  bool get branchSelectorVisible =>
      branches.length > 1 && me['branch_selector_visible'] == true;

  bool get businessAccessBlocked =>
      ((me['branch_ids'] as List?) ?? const []).isEmpty;

  List<Map<String, dynamic>> get sections =>
      (((bootstrap?['navigation'] as Map?)?['sections'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

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
      final me = Map<String, dynamic>.from(data['me'] as Map);
      final ids = ((me['branch_ids'] as List?) ?? const [])
          .map((e) => int.parse('$e'))
          .toList();
      final assigned = int.tryParse('${me['assigned_branch_id'] ?? ''}');
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
    final ids = state.branches.map((e) => int.parse('${e['id']}')).toList();
    if (ids.contains(id)) {
      state = state.copyWith(currentBranchId: id, clearError: true);
    }
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
