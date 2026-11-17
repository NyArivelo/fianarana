import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';

class AffectationScope {
  final AppDatabase db;
  AffectationScope(this.db);

  /// Retourne les classIds autorisés pour l'utilisateur si sa portée est "Affectations".
  /// Retourne null si aucune restriction par affectation ne doit s'appliquer (Globale, admin, ou non applicable).
  Future<List<String>?> allowedClassIdsForUser(String? userId) async {
    if (userId == null || userId.isEmpty) return null;
    final user = await (db.select(db.users)..where((t) => t.id.equals(userId))).getSingleOrNull();
    if (user == null) return null;
    if (user.scopeType != 'Affectations') return null;

    // Administrateur => pas de restriction
    final admin = await (db.select(db.roles).join([
      innerJoin(db.userRoles, db.userRoles.roleId.equalsExp(db.roles.id)),
    ])
          ..where(db.userRoles.userId.equals(userId) & db.roles.name.equals('Administrateur')))
        .getSingleOrNull();
    if (admin != null) return null;

    final staff = await (db.select(db.staffMembers)
          ..where((t) => t.userId.equals(userId) & t.isDeleted.equals(false)))
        .getSingleOrNull();
    if (staff == null) {
      // Portée affectations sans rattachement personnel connu: restriction stricte (aucune classe)
      return const <String>[];
    }

    final assigns = await (db.select(db.teacherAssignments)
          ..where((t) => t.staffId.equals(staff.id) & t.isDeleted.equals(false)))
        .get();
    final ids = assigns.map((a) => a.classId).whereType<String>().toSet().toList();
    return ids;
  }
}
