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
  final bool locked;
  final bool loading;
  final String? error;

  const AuthState({
    this.initialized = false,
    this.needsSetup = false,
    this.currentUser,
    this.locked = false,
    this.loading = false,
    this.error,
  });

  AuthState copyWith({
    bool? initialized,
    bool? needsSetup,
    User? currentUser,
    bool clearUser = false,
    bool? locked,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return AuthState(
      initialized: initialized ?? this.initialized,
      needsSetup: needsSetup ?? this.needsSetup,
      currentUser: clearUser ? null : (currentUser ?? this.currentUser),
      locked: locked ?? this.locked,
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
      state = state.copyWith(loading: false, currentUser: res.user, locked: false);
      return true;
    }
    state = state.copyWith(loading: false, error: res.message);
    return false;
  }

  void lock() {
    if (state.currentUser != null) {
      state = state.copyWith(locked: true, clearError: true);
    }
  }

  Future<bool> unlockWithPassword(String password) async {
    final user = state.currentUser;
    if (user == null) return false;
    final ok = await _service.verifyPassword(user.id, password);
    if (ok) {
      state = state.copyWith(locked: false, clearError: true);
      return true;
    }
    state = state.copyWith(error: 'Mot de passe invalide.');
    return false;
  }

  Future<bool> unlockWithPin(String pin) async {
    final user = state.currentUser;
    if (user == null) return false;
    final ok = await _service.verifyPin(user.id, pin);
    if (ok) {
      state = state.copyWith(locked: false, clearError: true);
      return true;
    }
    state = state.copyWith(error: 'Code PIN invalide.');
    return false;
  }

  Future<bool> quickSwitchWithPin(String username, String pin) async {
    final res = await _service.loginWithPin(username, pin);
    if (res.success) {
      state = state.copyWith(currentUser: res.user, locked: false, clearError: true);
      return true;
    }
    state = state.copyWith(error: res.message);
    return false;
  }

  void logout() {
    state = state.copyWith(clearUser: true, locked: false);
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref.watch(authServiceProvider));
});
