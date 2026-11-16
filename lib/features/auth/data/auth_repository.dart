import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/password_hasher.dart';

class AuthUser {
  final String id;
  final String username;
  final String fullName;
  final String? email;
  final String scopeType;
  final bool isActive;

  const AuthUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.email,
    required this.scopeType,
    required this.isActive,
  });
}

class AuthRepository {
  final AppDatabase db;
  late final AuditService _audit = AuditService(db);
  AuthRepository(this.db);

  Future<AuthUser?> authenticate(String username, String password) async {
    final user = await (db.select(db.users)
          ..where((u) => u.username.equals(username) & u.isDeleted.equals(false)))
        .getSingleOrNull();
    if (user == null) {
      await _audit.log(module: 'Sécurité', targetObject: 'Session', description: 'Tentative de connexion échouée (utilisateur inconnu: $username)', result: 'Échec');
      return null;
    }
    if (!user.isActive || (user.lockedUntil != null && user.lockedUntil!.isAfter(DateTime.now()))) {
      await _audit.log(userId: user.id, username: user.username, module: 'Sécurité', targetObject: 'Session', description: 'Connexion refusée (compte inactif ou verrouillé)', result: 'Échec');
      return null;
    }
    if (!passwordHasher.verify(password, user.passwordHash)) {
      await _registerFailedLogin(user);
      await _audit.log(userId: user.id, username: user.username, module: 'Sécurité', targetObject: 'Session', description: 'Connexion échouée (mot de passe invalide)', result: 'Échec');
      return null;
    }
    await (db.update(db.users)..where((u) => u.id.equals(user.id))).write(
      UsersCompanion(
        lastLoginAt: Value(DateTime.now().toUtc()),
        failedLoginCount: const Value(0),
        lockedUntil: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _audit.log(userId: user.id, username: user.username, module: 'Sécurité', targetObject: 'Session', description: 'Connexion réussie', result: 'Succès');
    return AuthUser(
      id: user.id,
      username: user.username,
      fullName: user.fullName,
      email: user.email,
      scopeType: user.scopeType,
      isActive: user.isActive,
    );
  }

  Future<void> _registerFailedLogin(User user) async {
    final count = user.failedLoginCount + 1;
    final lock = count >= 5 ? DateTime.now().add(const Duration(minutes: 15)) : null;
    await (db.update(db.users)..where((u) => u.id.equals(user.id))).write(
      UsersCompanion(
        failedLoginCount: Value(count),
        lockedUntil: Value(lock),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<bool> hasAnyUser() async {
    final row = await (db.selectOnly(db.users)..addColumns([db.users.id.count()])).getSingle();
    return (row.read(db.users.id.count()) ?? 0) > 0;
  }

  Future<void> createInitialAdmin({
    required String username,
    required String fullName,
    required String password,
    String? email,
  }) async {
    final now = DateTime.now();
    final adminRoleId = AppDatabase.ensureId(null);
    final userId = AppDatabase.ensureId(null);
    await db.transaction(() async {
      await db.into(db.roles).insertOnConflictUpdate(RolesCompanion.insert(
        id: adminRoleId,
        name: 'Administrateur',
        description: const Value('Accès complet au système'),
        isSystem: const Value(true),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      await db.into(db.users).insert(UsersCompanion.insert(
        id: userId,
        username: username,
        fullName: fullName,
        email: Value(email),
        passwordHash: passwordHasher.hash(password),
        scopeType: const Value('Globale'),
        isActive: const Value(true),
        mustChangePassword: const Value(false),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      await db.into(db.userRoles).insert(UserRolesCompanion.insert(
        userId: userId,
        roleId: adminRoleId,
      ));
    });
    await _audit.log(userId: userId, username: username, module: 'Sécurité', targetObject: userId, description: 'Création du compte Administrateur initial', result: 'Succès');
  }
}
