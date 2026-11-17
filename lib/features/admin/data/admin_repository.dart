import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/password_hasher.dart';
import 'package:fianarana/core/security/permission_service.dart';

class AdminRepository {
  final AppDatabase db;
  late final AuditService _audit = AuditService(db);
  late final PermissionService _perm = PermissionService(db);
  AdminRepository(this.db);

  Future<void> _require(String? userId, String permission) async {
    if (userId == null || userId.isEmpty) return;
    if (!await _perm.userHasPermission(userId, permission)) throw StateError('Action non autorisée ($permission)');
  }

  Future<List<User>> listUsers({String? actorUserId}) async {
    await _require(actorUserId, 'users.read');
    return (db.select(db.users)..where((t)=>t.isDeleted.equals(false))..orderBy([(t)=>OrderingTerm.asc(t.username)])).get();
  }

  Future<List<Role>> listRoles({String? actorUserId}) async {
    await _require(actorUserId, 'roles.read');
    return (db.select(db.roles)..where((t)=>t.isDeleted.equals(false))..orderBy([(t)=>OrderingTerm.asc(t.name)])).get();
  }

  Future<List<String>> roleIdsOfUser(String userId) async {
    final rows = await (db.select(db.userRoles)..where((t)=>t.userId.equals(userId))).get();
    return rows.map((r)=>r.roleId).toList();
  }

  Future<void> setUserRoles(String userId, List<String> roleIds, {String? actorUserId, String? actorUsername}) async {
    await _require(actorUserId, 'roles.update');
    await db.transaction(() async {
      await (db.delete(db.userRoles)..where((t)=>t.userId.equals(userId))).go();
      for (final rid in roleIds) {
        await db.into(db.userRoles).insert(UserRolesCompanion.insert(userId: userId, roleId: rid));
      }
    });
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Administration', targetObject: userId, description: 'Mise à jour des rôles utilisateur', result: 'Succès');
  }

  Future<void> upsertUser({
    String? id,
    required String username,
    required String fullName,
    String? email,
    String? password,
    String? pin,
    bool isActive = true,
    String scopeType = 'Globale',
    bool mustChangePassword = false,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, id == null ? 'users.create' : 'users.update');
    final uid = id ?? newUuid();
    final existing = id == null ? null : await (db.select(db.users)..where((t)=>t.id.equals(id))).getSingleOrNull();
    await db.into(db.users).insertOnConflictUpdate(UsersCompanion.insert(
      id: Value(uid),
      username: username,
      fullName: fullName,
      email: Value(email),
      passwordHash: (password != null && password.isNotEmpty) ? passwordHasher.hash(password) : (existing?.passwordHash ?? passwordHasher.hash('Password123!')),
      pinHash: Value((pin != null && pin.isNotEmpty) ? passwordHasher.hash(pin) : existing?.pinHash),
      isActive: Value(isActive),
      scopeType: Value(scopeType),
      mustChangePassword: Value(mustChangePassword),
      failedLoginCount: const Value(0),
      lockedUntil: const Value(null),
    ));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Administration', targetObject: uid, description: 'Utilisateur enregistré: $username', result: 'Succès');
  }

  Future<void> toggleActive(String userId, bool active, {String? actorUserId, String? actorUsername}) async {
    await _require(actorUserId, 'users.update');
    // empêcher désactivation du dernier admin actif? simple check
    if (!active) {
      final admins = await db.customSelect("SELECT COUNT(*) c FROM users u JOIN user_roles ur ON ur.user_id=u.id JOIN roles r ON r.id=ur.role_id WHERE r.name='Administrateur' AND u.is_active=1 AND u.is_deleted=0").getSingle();
      final userRoles = await roleIdsOfUser(userId);
      final roles = await listRoles();
      final isAdmin = roles.any((r)=>userRoles.contains(r.id) && r.name=='Administrateur');
      if (isAdmin && (admins.read<int>('c') <= 1)) {
        throw StateError('Impossible de désactiver le dernier administrateur actif.');
      }
    }
    await (db.update(db.users)..where((t)=>t.id.equals(userId))).write(UsersCompanion(isActive: Value(active), updatedAt: Value(DateTime.now())));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Administration', targetObject: userId, description: active ? 'Compte réactivé' : 'Compte désactivé', result: 'Succès');
  }

  Future<void> resetPassword(String userId, String newPassword, {String? actorUserId, String? actorUsername}) async {
    await _require(actorUserId, 'users.update');
    await (db.update(db.users)..where((t)=>t.id.equals(userId))).write(UsersCompanion(passwordHash: Value(passwordHasher.hash(newPassword)), mustChangePassword: const Value(true), failedLoginCount: const Value(0), lockedUntil: const Value(null), updatedAt: Value(DateTime.now())));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Administration', targetObject: userId, description: 'Réinitialisation du mot de passe', result: 'Succès');
  }

  Future<List<Permission>> listPermissions({String? actorUserId}) async {
    await _require(actorUserId, 'roles.read');
    return (db.select(db.permissions)..where((t)=>t.isDeleted.equals(false))..orderBy([(t)=>OrderingTerm.asc(t.module), (t)=>OrderingTerm.asc(t.code)])).get();
  }

  Future<Set<String>> permissionIdsOfRole(String roleId) async {
    final rows = await (db.select(db.rolePermissions)..where((t)=>t.roleId.equals(roleId))).get();
    return rows.map((r)=>r.permissionId).toSet();
  }

  Future<void> setRolePermissions(String roleId, Set<String> permissionIds, {String? actorUserId, String? actorUsername}) async {
    await _require(actorUserId, 'roles.update');
    await db.transaction(() async {
      await (db.delete(db.rolePermissions)..where((t)=>t.roleId.equals(roleId))).go();
      for (final pid in permissionIds) {
        await db.into(db.rolePermissions).insert(RolePermissionsCompanion.insert(roleId: roleId, permissionId: pid));
      }
    });
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Administration', targetObject: roleId, description: 'Mise à jour des permissions du rôle', result: 'Succès');
  }
}
