import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_service.dart';

class StaffRepository {
  final AppDatabase db;
  late final AuditService _audit = AuditService(db);
  late final PermissionService _perm = PermissionService(db);
  StaffRepository(this.db);

  Future<void> _require(String? userId, String permission) async {
    if (userId == null || userId.isEmpty) return;
    if (!await _perm.userHasPermission(userId, permission)) {
      throw StateError('Action non autorisée ($permission)');
    }
  }

  Future<List<StaffMember>> listStaff({String? actorUserId, String? query}) async {
    await _require(actorUserId, 'staff.read');
    final q = db.select(db.staffMembers)..where((t) => t.isDeleted.equals(false));
    if (query != null && query.trim().isNotEmpty) {
      final s = '%${query.trim()}%';
      q.where((t) => t.lastName.like(s) | t.firstName.like(s) | t.staffNumber.like(s));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.lastName), (t) => OrderingTerm.asc(t.firstName)]);
    return q.get();
  }

  Future<String> upsertStaff({
    String? id,
    required String staffNumber,
    required String lastName,
    required String firstName,
    String? sex,
    String? functionTitle,
    String? departmentOrSubject,
    String? contractType,
    String? phone,
    String status = 'Actif',
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, id == null ? 'staff.create' : 'staff.update');
    final sid = id ?? newUuid();
    await db.into(db.staffMembers).insertOnConflictUpdate(StaffMembersCompanion.insert(
      id: Value(sid),
      staffNumber: staffNumber,
      lastName: lastName,
      firstName: firstName,
      sex: Value(sex),
      functionTitle: Value(functionTitle),
      departmentOrSubject: Value(departmentOrSubject),
      contractType: Value(contractType),
      phone: Value(phone),
      status: Value(status),
    ));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Personnel', targetObject: sid, description: 'Personnel enregistré: $staffNumber $lastName $firstName', result: 'Succès');
    return sid;
  }

  Future<List<TeacherAbsence>> listAbsences({String? actorUserId, String? teacherId}) async {
    await _require(actorUserId, 'staff.read');
    final q = db.select(db.teacherAbsences)..where((t) => t.isDeleted.equals(false));
    if (teacherId != null && teacherId.isNotEmpty) q.where((t) => t.teacherId.equals(teacherId));
    q.orderBy([(t) => OrderingTerm.desc(t.startDate)]);
    return q.get();
  }

  Future<List<TimetableSession>> sessionsForTeacher(String teacherId) {
    return (db.select(db.timetableSessions)..where((t) => t.teacherId.equals(teacherId) & t.isDeleted.equals(false))).get();
  }

  Future<List<FacilitiesData>> availableRooms() {
    return (db.select(db.facilities)..where((t) => t.isDeleted.equals(false))).get();
  }

  /// Déclare une absence enseignant et (optionnel) planifie un remplacement/rattrapage en créant une séance de substitution.
  Future<String> declareAbsenceAndReplacement({
    required String teacherId,
    required DateTime startDate,
    required DateTime endDate,
    String? reason,
    String? substituteTeacherId,
    String? sessionId,
    String? replacementClassId,
    String? replacementSubjectId,
    String? replacementRoomId,
    String? replacementDay,
    String? replacementStart,
    String? replacementEnd,
    DateTime? replacementDate,
    String? notes,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'staff.update');
    final id = newUuid();
    await db.transaction(() async {
      String? createdSessionId;
      if (substituteTeacherId != null && replacementDay != null && replacementStart != null && replacementEnd != null) {
        createdSessionId = newUuid();
        await db.into(db.timetableSessions).insert(TimetableSessionsCompanion.insert(
          id: Value(createdSessionId),
          classId: Value(replacementClassId),
          subjectId: Value(replacementSubjectId),
          teacherId: Value(substituteTeacherId),
          roomId: Value(replacementRoomId),
          dayOfWeek: replacementDay,
          startTime: replacementStart,
          endTime: replacementEnd,
          recurrence: const Value('Ponctuelle'),
          date: Value(replacementDate),
          isSubstitution: const Value(true),
          notes: Value('Remplacement/rattrapage: ${notes ?? reason ?? ''}'),
        ));
      }
      await db.into(db.teacherAbsences).insert(TeacherAbsencesCompanion.insert(
        id: Value(id),
        teacherId: teacherId,
        startDate: startDate,
        endDate: endDate,
        reason: Value(reason),
        status: Value(substituteTeacherId != null ? 'Remplacée' : 'Déclarée'),
        sessionId: Value(sessionId ?? createdSessionId),
        substituteTeacherId: Value(substituteTeacherId),
        notes: Value(notes),
      ));
    });
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Personnel', targetObject: id, description: 'Absence enseignant déclarée${substituteTeacherId != null ? ' avec remplacement/rattrapage' : ''}', result: 'Succès');
    return id;
  }
}
