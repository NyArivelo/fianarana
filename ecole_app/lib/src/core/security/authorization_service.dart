import 'package:drift/drift.dart';

import '../database/app_database.dart';

class AuthorizationService {
  final AppDatabase db;
  AuthorizationService(this.db);

  Future<List<Role>> rolesForUser(String userId) async {
    final q = db.select(db.roles).join([
      innerJoin(db.userRoles, db.userRoles.roleId.equalsExp(db.roles.id)),
    ])..where(db.userRoles.userId.equals(userId) & db.roles.isDeleted.equals(false));
    final rows = await q.get();
    return rows.map((r) => r.readTable(db.roles)).toList();
  }

  Future<bool> isAdmin(String userId) async {
    final roles = await rolesForUser(userId);
    return roles.any((r) => r.name == 'Administrateur' || (r.scope == 'global' && r.isSystem));
  }

  Future<bool> hasScope(String userId, String scope) async {
    if (await isAdmin(userId)) return true;
    final roles = await rolesForUser(userId);
    return roles.any((r) => r.scope == scope);
  }

  /// Effective scope: 'global', 'caisse', or 'restricted'. Admin => global.
  Future<String> effectiveScope(String userId) async {
    final roles = await rolesForUser(userId);
    if (roles.any((r) => r.name == 'Administrateur' || r.scope == 'global')) return 'global';
    if (roles.any((r) => r.scope == 'caisse')) return 'caisse';
    if (roles.any((r) => r.scope == 'restricted')) return 'restricted';
    return 'global';
  }

  Future<Set<String>> permissionCodes(String userId) async {
    final q = db.select(db.permissions).join([
      innerJoin(db.rolePermissions, db.rolePermissions.permissionId.equalsExp(db.permissions.id)),
      innerJoin(db.userRoles, db.userRoles.roleId.equalsExp(db.rolePermissions.roleId)),
    ])..where(db.userRoles.userId.equals(userId));
    final rows = await q.get();
    return rows.map((r) => r.readTable(db.permissions).code).toSet();
  }

  Future<bool> hasPermission(String userId, String code) async {
    if (await isAdmin(userId)) return true;
    final codes = await permissionCodes(userId);
    return codes.contains(code);
  }

  Future<List<String>> assignedClassIds(String userId, {String? academicYearId}) async {
    final q = db.select(db.teacherAssignments)..where((t) => t.userId.equals(userId) & t.isDeleted.equals(false));
    if (academicYearId != null) q.where((t) => t.academicYearId.equals(academicYearId) | t.academicYearId.isNull());
    final rows = await q.get();
    return rows.map((r) => r.classId).toSet().toList();
  }
}
