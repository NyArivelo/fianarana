import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthState {
  final bool isAuthenticated;
  final String? userId;
  final String? username;
  final String? fullName;
  final String? scopeType;
  final String? error;

  const AuthState({
    this.isAuthenticated = false,
    this.userId,
    this.username,
    this.fullName,
    this.scopeType,
    this.error,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    String? userId,
    String? username,
    String? fullName,
    String? scopeType,
    String? error,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      scopeType: scopeType ?? this.scopeType,
      error: error,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController() : super(const AuthState());

  Future<bool> login({required String username, required String password}) async {
    // TODO: implémenter vérification réelle via DB + hash (Argon2id/bcrypt)
    // Comptes de démonstration alignés sur les données de test (mot de passe à définir en seed sécurisé)
    if (username.isNotEmpty && password.isNotEmpty) {
      state = AuthState(
        isAuthenticated: true,
        userId: 'demo',
        username: username,
        fullName: username,
        scopeType: 'Globale',
      );
      return true;
    }
    state = state.copyWith(error: 'Identifiants invalides');
    return false;
  }

  void logout() {
    state = const AuthState();
  }

  void lock() {
    // TODO: conserver les onglets et demander PIN (Ctrl+L)
    state = const AuthState();
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController();
});
