import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/security/password_hasher.dart';

class AuthResult {
  final bool success;
  final String? message;
  final User? user;

  const AuthResult({required this.success, this.message, this.user});

  factory AuthResult.ok(User user) => AuthResult(success: true, user: user);
  factory AuthResult.fail(String message) =>
      AuthResult(success: false, message: message);
}

class AuthService {
  final AppDatabase db;
  final _uuid = const Uuid();

  AuthService(this.db);

  Future<bool> hasAnyUser() async {
    final count = await (db.selectOnly(db.users)
          ..addColumns([db.users.id.count()]))
        .map((row) => row.read(db.users.id.count()) ?? 0)
        .getSingle();
    return count > 0;
  }

  Future<void> ensureBootstrapAdmin({
    required String username,
    required String password,
    required String displayName,
  }) async {
    if (await hasAnyUser()) return;

    final adminRoleId = _uuid.v4();
    final adminUserId = _uuid.v4();

    await db.transaction(() async {
      await db.into(db.roles).insert(RolesCompanion.insert(
            id: adminRoleId,
            name: 'Administrateur',
            description: const Value('Accès complet au système'),
            isSystem: const Value(true),
          ));

      await db.into(db.users).insert(UsersCompanion.insert(
            id: adminUserId,
            username: username,
            passwordHash: PasswordHasher.hash(password),
            displayName: displayName,
            isActive: const Value(true),
          ));

      await db.into(db.userRoles).insert(UserRolesCompanion.insert(
            userId: adminUserId,
            roleId: adminRoleId,
          ));

      await _audit(
        userId: adminUserId,
        username: username,
        module: 'auth',
        action: 'bootstrap_admin_created',
        targetType: 'user',
        targetId: adminUserId,
        details: 'Création du compte administrateur initial',
      );
    });
  }

  Future<AuthResult> login(String username, String password) async {
    final user = await (db.select(db.users)
          ..where((u) => u.username.equals(username)))
        .getSingleOrNull();

    if (user == null) {
      return AuthResult.fail('Identifiant ou mot de passe invalide.');
    }
    if (!user.isActive) {
      return AuthResult.fail('Ce compte est désactivé.');
    }
    if (user.lockedUntil != null && user.lockedUntil!.isAfter(DateTime.now())) {
      return AuthResult.fail('Compte temporairement verrouillé. Réessayez plus tard.');
    }

    final ok = PasswordHasher.verify(password, user.passwordHash);
    if (!ok) {
      final attempts = user.failedLoginAttempts + 1;
      final lock = attempts >= 5
          ? DateTime.now().add(const Duration(minutes: 15))
          : null;
      await (db.update(db.users)..where((u) => u.id.equals(user.id))).write(
        UsersCompanion(
          failedLoginAttempts: Value(attempts),
          lockedUntil: Value(lock),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _audit(
        userId: user.id,
        username: user.username,
        module: 'auth',
        action: 'login_failed',
        targetType: 'user',
        targetId: user.id,
        details: 'Tentative échouée ($attempts)',
        result: 'failure',
      );
      return AuthResult.fail('Identifiant ou mot de passe invalide.');
    }

    await (db.update(db.users)..where((u) => u.id.equals(user.id))).write(
      UsersCompanion(
        failedLoginAttempts: const Value(0),
        lockedUntil: const Value(null),
        lastLoginAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _audit(
      userId: user.id,
      username: user.username,
      module: 'auth',
      action: 'login_success',
      targetType: 'user',
      targetId: user.id,
    );

    final fresh = await (db.select(db.users)
          ..where((u) => u.id.equals(user.id)))
        .getSingle();
    return AuthResult.ok(fresh);
  }

  Future<bool> verifyPassword(String userId, String password) async {
    final user = await (db.select(db.users)..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (user == null) return false;
    return PasswordHasher.verify(password, user.passwordHash);
  }

  Future<bool> verifyPin(String userId, String pin) async {
    final user = await (db.select(db.users)..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (user == null || user.pinHash == null || user.pinHash!.isEmpty) return false;
    return PasswordHasher.verify(pin, user.pinHash!);
  }

  Future<void> setPin(String userId, String? pin) async {
    await (db.update(db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(pinHash: Value(pin == null || pin.isEmpty ? null : PasswordHasher.hash(pin)), updatedAt: Value(DateTime.now())),
    );
  }

  Future<AuthResult> loginWithPin(String username, String pin) async {
    final user = await (db.select(db.users)..where((u) => u.username.equals(username))).getSingleOrNull();
    if (user == null) return AuthResult.fail('Utilisateur introuvable.');
    if (!user.isActive) return AuthResult.fail('Ce compte est désactivé.');
    if (user.pinHash == null || user.pinHash!.isEmpty) return AuthResult.fail('Aucun code PIN défini pour ce compte.');
    final ok = PasswordHasher.verify(pin, user.pinHash!);
    if (!ok) {
      await _audit(userId: user.id, username: user.username, module: 'auth', action: 'quick_switch_failed', targetType: 'user', targetId: user.id, result: 'failure');
      return AuthResult.fail('Code PIN invalide.');
    }
    await (db.update(db.users)..where((u) => u.id.equals(user.id))).write(
      UsersCompanion(lastLoginAt: Value(DateTime.now()), updatedAt: Value(DateTime.now()), failedLoginAttempts: const Value(0), lockedUntil: const Value(null)),
    );
    await _audit(userId: user.id, username: user.username, module: 'auth', action: 'quick_switch_success', targetType: 'user', targetId: user.id);
    final fresh = await (db.select(db.users)..where((u) => u.id.equals(user.id))).getSingle();
    return AuthResult.ok(fresh);
  }

  Future<List<User>> usersWithPin() async {
    return (db.select(db.users)..where((u) => u.isDeleted.equals(false) & u.isActive.equals(true) & u.pinHash.isNotNull())).get();
  }

  Future<void> _audit({
    String? userId,
    String? username,
    required String module,
    required String action,
    String? targetType,
    String? targetId,
    String? details,
    String result = 'success',
  }) async {
    await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
          id: _uuid.v4(),
          timestamp: DateTime.now().toUtc(),
          userId: Value(userId),
          username: Value(username),
          module: module,
          action: action,
          targetType: Value(targetType),
          targetId: Value(targetId),
          details: Value(details),
          result: Value(result),
        ));
  }
}
