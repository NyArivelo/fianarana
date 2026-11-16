import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_service.dart';

class UnauthorizedActionException implements Exception {
  final String permission;
  UnauthorizedActionException(this.permission);
  @override
  String toString() => 'Action non autorisée (permission requise: $permission)';
}

class StaffRepository {
  final AppDatabase db;
  late final AuditService _audit = AuditService(db);
  late final PermissionService _perm = PermissionService(db);
  StaffRepository(this.db);

  Future<void> _require(String? userId, String permission) async {
    if (userId == null || userId.isEmpty) return;
    if (!await _perm.userHasPermission(userId, permission)) throw UnauthorizedActionException(permission);
  }

  Future<List<StaffMember>> list({String? actorUserId, String? query}) async {
    await _require(actorUserId, 'staff.read');
    final q = db.select(db.staffMembers)..where((t) => t.isDeleted.equals(false));
    if (query != null && query.trim().isNotEmpty) {
      final s = '%${query.trim()}%';
      q.where((t) => t.lastName.like(s) | t.firstName.like(s) | t.staffNumber.like(s) | t.functionTitle.like(s));
    }
    q.orderBy([(t)=>OrderingTerm.asc(t.lastName)]);
    return q.get();
  }

  Future<String> upsert({String? id, required String staffNumber, required String lastName, required String firstName, String? sex, String? functionTitle, String? department, String? contractType, String? phone, String status = 'Actif', String? actorUserId, String? actorUsername}) async {
    await _require(actorUserId, id == null ? 'staff.create' : 'staff.update');
    final sid = id ?? newUuid();
    await db.into(db.staffMembers).insertOnConflictUpdate(StaffMembersCompanion.insert(
      id: sid,
      staffNumber: staffNumber,
      lastName: lastName,
      firstName: firstName,
      sex: Value(sex),
      functionTitle: Value(functionTitle),
      departmentOrSubject: Value(department),
      contractType: Value(contractType),
      phone: Value(phone),
      status: Value(status),
      updatedAt: Value(DateTime.now()),
    ));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Personnel', targetObject: sid, description: '${id==null?"Création":"Mise à jour"} personnel $staffNumber $lastName $firstName', result: 'Succès');
    return sid;
  }

  Future<void> archive(String id, {String? actorUserId, String? actorUsername}) async {
    await _require(actorUserId, 'staff.archive');
    await (db.update(db.staffMembers)..where((t)=>t.id.equals(id))).write(StaffMembersCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now()), updatedAt: Value(DateTime.now())));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Personnel', targetObject: id, description: 'Archivage/suppression logique personnel', result: 'Succès');
  }
}
