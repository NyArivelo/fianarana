import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import 'auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(appDatabaseProvider));
});

class AuthState {
  final bool initialized;
  final bool needsSetup;
  final User? currentUser;
  final bool loading;
  final String? error;

  const AuthState({
    this.initialized = false,
    this.needsSetup = false,
    this.currentUser,
    this.loading = false,
    this.error,
  });

  AuthState copyWith({
    bool? initialized,
    bool? needsSetup,
    User? currentUser,
    bool clearUser = false,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return AuthState(
      initialized: initialized ?? this.initialized,
      needsSetup: needsSetup ?? this.needsSetup,
      currentUser: clearUser ? null : (currentUser ?? this.currentUser),
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  final AuthService _service;

  AuthController(this._service) : super(const AuthState());

  Future<void> initialize() async {
    state = state.copyWith(loading: true, clearError: true);
    final hasUser = await _service.hasAnyUser();
    state = state.copyWith(
      initialized: true,
      needsSetup: !hasUser,
      loading: false,
    );
  }

  Future<bool> bootstrap({
    required String username,
    required String password,
    required String displayName,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _service.ensureBootstrapAdmin(
        username: username,
        password: password,
        displayName: displayName,
      );
      state = state.copyWith(needsSetup: false, loading: false);
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(loading: true, clearError: true);
    final res = await _service.login(username, password);
    if (res.success) {
      state = state.copyWith(loading: false, currentUser: res.user);
      return true;
    }
    state = state.copyWith(loading: false, error: res.message);
    return false;
  }

  void logout() {
    state = state.copyWith(clearUser: true);
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref.watch(authServiceProvider));
});
