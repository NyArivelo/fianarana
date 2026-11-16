import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';

/// Vérification des permissions dans les services métier (pas uniquement UI).
/// Convention: "<module>.<action>" ex: students.read, grades.validate, finance.close_cash_desk
class PermissionService {
  final AppDatabase db;
  PermissionService(this.db);

  Future<bool> userHasPermission(String userId, String permissionCode) async {
    // Administrateur (rôle système) => accès complet
    final admin = await (db.select(db.roles).join([
      innerJoin(db.userRoles, db.userRoles.roleId.equalsExp(db.roles.id)),
    ])
          ..where(db.userRoles.userId.equals(userId) & db.roles.name.equals('Administrateur')))
        .getSingleOrNull();
    if (admin != null) return true;

    final row = await (db.select(db.permissions).join([
      innerJoin(db.rolePermissions, db.rolePermissions.permissionId.equalsExp(db.permissions.id)),
      innerJoin(db.userRoles, db.userRoles.roleId.equalsExp(db.rolePermissions.roleId)),
    ])
          ..where(db.userRoles.userId.equals(userId) & db.permissions.code.equals(permissionCode)))
        .getSingleOrNull();
    return row != null;
  }

  Future<Set<String>> permissionsOf(String userId) async {
    final admin = await (db.select(db.roles).join([
      innerJoin(db.userRoles, db.userRoles.roleId.equalsExp(db.roles.id)),
    ])
          ..where(db.userRoles.userId.equals(userId) & db.roles.name.equals('Administrateur')))
        .getSingleOrNull();
    if (admin != null) {
      final all = await db.select(db.permissions).get();
      return all.map((p) => p.code).toSet();
    }
    final rows = await (db.select(db.permissions).join([
      innerJoin(db.rolePermissions, db.rolePermissions.permissionId.equalsExp(db.permissions.id)),
      innerJoin(db.userRoles, db.userRoles.roleId.equalsExp(db.rolePermissions.roleId)),
    ])
          ..where(db.userRoles.userId.equals(userId)))
        .get();
    return rows.map((r) => r.readTable(db.permissions).code).toSet();
  }

  /// Contrôle de portée (scope) applicative.
  /// - Globale: accès établissement
  /// - Affectations: restreint aux affectations (à résoudre par module, ex. enseignants/classes)
  /// - Caisse: limité aux opérations du caissier
  bool scopeAllows({
    required String userScopeType,
    required String requiredScope,
    String? userScopeRefId,
    String? resourceOwnerId,
  }) {
    if (userScopeType == 'Globale') return true;
    if (userScopeType == requiredScope) {
      if (userScopeRefId == null || resourceOwnerId == null) return true;
      return userScopeRefId == resourceOwnerId;
    }
    return false;
  }

  Future<void> ensurePermission(String id, String code, String module, String action, [String? description]) async {
    await db.into(db.permissions).insertOnConflictUpdate(PermissionsCompanion.insert(
      id: id,
      code: code,
      module: module,
      action: action,
      description: Value(description),
    ));
  }
}
