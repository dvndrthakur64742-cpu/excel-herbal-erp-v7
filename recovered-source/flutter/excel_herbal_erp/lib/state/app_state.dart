import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../core/api_paths.dart';
import '../core/providers.dart';
import '../core/secure_session.dart';

class AppState {
  const AppState({this.loading = true, this.authenticated = false, this.bootstrap, this.currentBranchId, this.error});
  final bool loading;
  final bool authenticated;
  final Map<String, dynamic>? bootstrap;
  final int? currentBranchId;
  final String? error;

  List<Map<String, dynamic>> get branches => ((bootstrap?['branches'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  Map<String, dynamic> get me => Map<String, dynamic>.from((bootstrap?['me'] as Map?) ?? const {});
  List<String> get capabilities => ((me['capabilities'] as List?) ?? const []).map((e) => '$e').toList();
  bool can(String capability) => capabilities.contains(capability);
  bool get branchSelectorVisible => branches.length > 1 && me['branch_selector_visible'] == true;
  bool get businessAccessBlocked => bootstrap != null && ((me['branch_ids'] as List?) ?? const []).isEmpty;
  bool get bootstrapRecoveryRequired => authenticated && !loading && bootstrap == null && error != null;
  List<Map<String, dynamic>> get sections => (((bootstrap?['navigation'] as Map?)?['sections'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  AppState copyWith({bool? loading, bool? authenticated, Map<String, dynamic>? bootstrap, int? currentBranchId, String? error, bool clearError = false}) =>
      AppState(loading: loading ?? this.loading, authenticated: authenticated ?? this.authenticated, bootstrap: bootstrap ?? this.bootstrap, currentBranchId: currentBranchId ?? this.currentBranchId, error: clearError ? null : (error ?? this.error));
}

class AppController extends StateNotifier<AppState> {
  AppController(this.api, this.session) : super(const AppState()) { initialize(); }
  final ApiClient api;
  final SecureSession session;

  Future<void> initialize() async {
    final token = await session.accessToken();
    if (token == null || token.isEmpty) { state = const AppState(loading: false); return; }
    state = const AppState(loading: true, authenticated: true);
    await refreshBootstrap();
  }

  Future<void> login(String mobile, String password) async {
    state = state.copyWith(loading: true, clearError: true);
    try { await api.login(mobile, password); state = const AppState(loading: true, authenticated: true); await refreshBootstrap(); }
    catch (e) { state = AppState(loading: false, error: e.toString()); }
  }

  Future<void> refreshBootstrap() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final data = Map<String, dynamic>.from(await api.get(ApiPaths.bootstrap) as Map);
      final me = Map<String, dynamic>.from(data['me'] as Map);
      final ids = ((me['branch_ids'] as List?) ?? const []).map((e) => int.parse('$e')).toList();
      final assigned = int.tryParse('${me['assigned_branch_id'] ?? ''}');
      final current = state.currentBranchId != null && ids.contains(state.currentBranchId)
          ? state.currentBranchId
          : (ids.length == 1 ? ids.first : (assigned != null && ids.contains(assigned) ? assigned : null));
      state = AppState(loading: false, authenticated: true, bootstrap: data, currentBranchId: current);
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await session.clear();
        state = AppState(loading: false, error: e.toString());
      } else {
        state = AppState(loading: false, authenticated: true, bootstrap: state.bootstrap, currentBranchId: state.currentBranchId, error: e.toString());
      }
    } catch (e) {
      state = AppState(loading: false, authenticated: true, bootstrap: state.bootstrap, currentBranchId: state.currentBranchId, error: e.toString());
    }
  }

  void selectBranch(int id) {
    final ids = state.branches.map((e) => int.parse('${e['id']}')).toList();
    if (ids.contains(id)) state = state.copyWith(currentBranchId: id, clearError: true);
  }

  Future<void> logout() async { await api.logout(); state = const AppState(loading: false); }
}

final appStateProvider = StateNotifierProvider<AppController, AppState>((ref) => AppController(ref.watch(apiClientProvider), ref.watch(secureSessionProvider)));
