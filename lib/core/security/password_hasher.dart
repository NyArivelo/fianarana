import 'package:bcrypt/bcrypt.dart';

/// Service de hachage des mots de passe.
/// Préférence cahier des charges: Argon2id ou bcrypt.
/// Implémentation initiale: bcrypt (pur Dart, compatible multi-plateformes).
class PasswordHasher {
  String hash(String password) {
    return BCrypt.hashpw(password, BCrypt.gensalt());
  }

  bool verify(String password, String hash) {
    try {
      return BCrypt.checkpw(password, hash);
    } catch (_) {
      return false;
    }
  }
}

final passwordHasher = PasswordHasher();
