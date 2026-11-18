import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/permission_service.dart';

/// Permissions granulaires de base (ressource.action) et rôles initiaux.
/// À enrichir au fil des modules. Données de test/initialisation de la sécurité.
class RbacSeed {
  final AppDatabase db;
  RbacSeed(this.db);

  static const modules = <String, List<String>>{
    'students': ['read', 'create', 'update', 'archive', 'validate', 'export', 'print', 'delete'],
    'enrollments': ['read', 'create', 'update', 'validate', 'archive'],
    'grades': ['read', 'create', 'update', 'validate', 'reject', 'publish', 'export', 'print'],
    'attendance': ['read', 'create', 'update', 'export'],
    'discipline': ['read', 'create', 'update', 'validate', 'close', 'print'],
    'finance': ['read', 'create', 'update', 'validate', 'cancel', 'export', 'print', 'close_cash_desk'],
    'fees': ['read', 'create', 'update', 'delete'],
    'library': ['read', 'create', 'update', 'validate'],
    'staff': ['read', 'create', 'update', 'archive'],
    'timetable': ['read', 'create', 'update', 'delete'],
    'calendar': ['read', 'create', 'update', 'delete'],
    'facilities': ['read', 'create', 'update', 'delete'],
    'settings': ['read', 'update'],
    'security': ['read', 'update', 'export'],
    'documents': ['read', 'create', 'update', 'publish', 'export', 'print', 'delete'],
    'audit': ['read', 'export'],
    'backups': ['read', 'create', 'restore'],
    'recycle': ['read', 'restore', 'purge'],
    'users': ['read', 'create', 'update'],
    'roles': ['read', 'update'],
  };

  Future<void> ensureDefaults() async {
    final permService = PermissionService(db);
    for (final entry in modules.entries) {
      for (final action in entry.value) {
        final code = '${entry.key}.$action';
        await permService.ensurePermission('perm-$code', code, entry.key, action);
      }
    }

    Future<String> ensureRole(String name, String desc, {bool system = false}) async {
      final existing = await (db.select(db.roles)..where((r) => r.name.equals(name))).getSingleOrNull();
      if (existing != null) return existing.id;
      final id = newUuid();
      await db.into(db.roles).insert(RolesCompanion.insert(
        id: Value(id),
        name: name,
        description: Value(desc),
        isSystem: Value(system),
      ));
      return id;
    }

    Future<void> grant(String roleId, List<String> codes) async {
      for (final code in codes) {
        final p = await (db.select(db.permissions)..where((x) => x.code.equals(code))).getSingleOrNull();
        if (p == null) continue;
        await db.into(db.rolePermissions).insertOnConflictUpdate(RolePermissionsCompanion.insert(roleId: roleId, permissionId: p.id));
      }
    }

    final adminId = await ensureRole('Administrateur', 'Accès complet', system: true);
    final directionId = await ensureRole('Direction', 'Pilotage pédagogique et validation');
    final secretariatId = await ensureRole('Secrétariat', 'Gestion élèves et inscriptions');
    final caisseId = await ensureRole('Économat/Caisse', 'Gestion financière et caisse');
    final enseignantId = await ensureRole('Enseignant', 'Accès pédagogique restreint aux affectations');
    final biblioId = await ensureRole('Bibliothécaire', 'Gestion bibliothèque');
    final surveillantId = await ensureRole('Surveillant', 'Présences et discipline');

    // Admin: toutes permissions (aussi géré en code, mais on rattache)
    final allPerms = await db.select(db.permissions).get();
    await grant(adminId, allPerms.map((e) => e.code).toList());

    await grant(directionId, [
      'students.read','students.export','students.print',
      'enrollments.read','enrollments.validate',
      'grades.read','grades.validate','grades.reject','grades.publish','grades.export','grades.print',
      'attendance.read','attendance.export',
      'discipline.read','discipline.validate','discipline.close','discipline.print',
      'finance.read','finance.export','fees.read',
      'timetable.read','calendar.read','facilities.read','staff.read','library.read',
      'documents.read','documents.publish','documents.export','documents.print',
      'audit.read','audit.export','security.read','settings.read','backups.read',
    ]);
    await grant(secretariatId, [
      'students.read','students.create','students.update','students.export','students.print',
      'enrollments.read','enrollments.create','enrollments.update','enrollments.validate',
      'timetable.read','calendar.read','staff.read','library.read','facilities.read',
      'discipline.read','fees.read',
      'documents.read','documents.create','documents.print','documents.export',
      'settings.read',
    ]);
    await grant(caisseId, [
      'students.read','enrollments.read',
      'finance.read','finance.create','finance.update','finance.validate','finance.cancel','finance.export','finance.print','finance.close_cash_desk',
      'fees.read','fees.create','fees.update','fees.delete',
      'discipline.read',
      'documents.read','documents.create','documents.print',
      'settings.read',
    ]);
    await grant(enseignantId, [
      'students.read','grades.read','grades.create','grades.update','attendance.read','attendance.create','attendance.update',
      'discipline.read','discipline.create',
      'timetable.read','calendar.read','documents.read','settings.read',
    ]);
    await grant(biblioId, ['library.read','library.create','library.update','library.validate','students.read','facilities.read','documents.read','settings.read']);
    await grant(surveillantId, ['attendance.read','attendance.create','attendance.update','students.read','timetable.read','calendar.read','settings.read',
      'discipline.read','discipline.create','discipline.update','discipline.validate','discipline.close','discipline.print']);
  }
}
