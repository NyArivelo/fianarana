import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/features/auth/application/auth_providers.dart';
import 'package:fianarana/features/auth/data/auth_repository.dart';

class AuthState {
  final bool isAuthenticated;
  final bool isLocked;
  final bool isLoading;
  final String? userId;
  final String? username;
  final String? fullName;
  final String? scopeType;
  final String? error;

  const AuthState({
    this.isAuthenticated = false,
    this.isLocked = false,
    this.isLoading = false,
    this.userId,
    this.username,
    this.fullName,
    this.scopeType,
    this.error,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLocked,
    bool? isLoading,
    String? userId,
    String? username,
    String? fullName,
    String? scopeType,
    String? error,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLocked: isLocked ?? this.isLocked,
      isLoading: isLoading ?? this.isLoading,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      scopeType: scopeType ?? this.scopeType,
      error: error,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  final AuthRepository _repo;
  AuthController(this._repo) : super(const AuthState());

  Future<bool> login({required String username, required String password}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _repo.authenticate(username, password);
      if (user == null) {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: false,
          error: 'Identifiant ou mot de passe invalide, ou compte inactif/verrouillé.',
        );
        return false;
      }
      state = AuthState(
        isAuthenticated: true,
        isLocked: false,
        isLoading: false,
        userId: user.id,
        username: user.username,
        fullName: user.fullName,
        scopeType: user.scopeType,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Erreur de connexion: $e');
      return false;
    }
  }

  void logout() {
    state = const AuthState();
  }

  /// Changement rapide d'utilisateur (Quick Switch): authentifie un autre compte et remplace la session.
  Future<bool> switchUser({required String username, required String password}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _repo.authenticate(username, password);
      if (user == null) {
        state = state.copyWith(isLoading: false, error: 'Identifiants invalides pour le changement d\'utilisateur.');
        return false;
      }
      state = AuthState(
        isAuthenticated: true,
        isLocked: false,
        isLoading: false,
        userId: user.id,
        username: user.username,
        fullName: user.fullName,
        scopeType: user.scopeType,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Erreur changement d\'utilisateur: $e');
      return false;
    }
  }

  /// Verrouillage rapide (Ctrl+L): conserve l'identité/session logique, demande déverrouillage.
  void lock() {
    if (state.isAuthenticated) {
      state = state.copyWith(isLocked: true);
    }
  }

  /// Déverrouillage par mot de passe (base).
  Future<bool> unlockWithPassword(String password) async {
    final username = state.username;
    if (username == null) return false;
    final user = await _repo.authenticate(username, password);
    if (user == null) return false;
    state = state.copyWith(isLocked: false, error: null);
    return true;
  }

  /// Déverrouillage rapide par PIN (4-6 chiffres) si configuré pour l'utilisateur.
  Future<bool> unlockWithPin(String pin) async {
    final userId = state.userId;
    if (userId == null) return false;
    final ok = await _repo.verifyPin(userId, pin);
    if (!ok) return false;
    state = state.copyWith(isLocked: false, error: null);
    return true;
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return AuthController(repo);
});
