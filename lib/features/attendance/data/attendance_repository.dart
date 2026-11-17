import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/affectation_scope.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_service.dart';

class AttendanceRow {
  final String id;
  final DateTime date;
  final String studentName;
  final String matricule;
  final String? classLabel;
  final String status;
  final String category;
  final String? slot;
  final String? justification;
  final String? details;

  AttendanceRow({
    required this.id,
    required this.date,
    required this.studentName,
    required this.matricule,
    required this.classLabel,
    required this.status,
    required this.category,
    required this.slot,
    required this.justification,
    required this.details,
  });
}

class UnauthorizedActionException implements Exception {
  final String permission;
  UnauthorizedActionException(this.permission);
  @override
  String toString() => 'Action non autorisée (permission requise: $permission)';
}

class AttendanceRepository {
  final AppDatabase db;
  late final AuditService _audit = AuditService(db);
  late final PermissionService _perm = PermissionService(db);
  AttendanceRepository(this.db);

  Future<void> _require(String? userId, String permission) async {
    if (userId == null || userId.isEmpty) return;
    if (!await _perm.userHasPermission(userId, permission)) {
      await _audit.log(userId: userId, module: 'Sécurité', targetObject: permission, description: 'Permission refusée: $permission', result: 'Échec');
      throw UnauthorizedActionException(permission);
    }
  }

  Future<List<AttendanceRow>> list({String? actorUserId, String? classId, DateTime? date, int limit = 200}) async {
    await _require(actorUserId, 'attendance.read');
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    if (scopeClasses != null) {
      if (scopeClasses.isEmpty) return const <AttendanceRow>[];
      if (classId != null && classId.isNotEmpty && !scopeClasses.contains(classId)) return const <AttendanceRow>[];
    }
    final a = db.attendanceEvents;
    final s = db.students;
    final c = db.classes;
    final j = db.select(a).join([
      innerJoin(s, s.id.equalsExp(a.studentId)),
      leftOuterJoin(c, c.id.equalsExp(a.classId)),
    ]);
    j.where(a.isDeleted.equals(false));
    if (classId != null && classId.isNotEmpty) {
      j.where(a.classId.equals(classId));
    } else if (scopeClasses != null) {
      j.where(a.classId.isIn(scopeClasses));
    }
    if (date != null) {
      final start = DateTime(date.year, date.month, date.day);
      final end = start.add(const Duration(days: 1));
      j.where(a.date.isBetweenValues(start, end));
    }
    j.orderBy([OrderingTerm.desc(a.date)]);
    j.limit(limit);
    final rows = await j.get();
    return rows.map((r) {
      final ev = r.readTable(a);
      final st = r.readTable(s);
      final cl = r.readTableOrNull(c);
      return AttendanceRow(
        id: ev.id,
        date: ev.date,
        studentName: '${st.lastName} ${st.firstName}',
        matricule: st.matricule,
        classLabel: cl?.label,
        status: ev.status,
        category: ev.category,
        slot: ev.slotOrFacts,
        justification: ev.justificationOrSanction,
        details: ev.details,
      );
    }).toList();
  }

  Future<void> record({
    required String studentId,
    String? classId,
    required DateTime date,
    required String status,
    String category = 'Appel / Présence',
    String? slotOrFacts,
    String? justification,
    String? details,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'attendance.create');
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    if (scopeClasses != null) {
      String? effectiveClassId = classId;
      if (effectiveClassId == null || effectiveClassId.isEmpty) {
        final enr = await (db.select(db.enrollments)..where((t)=>t.studentId.equals(studentId) & t.isDeleted.equals(false))..orderBy([(t)=>OrderingTerm.desc(t.updatedAt)])).get();
        if (enr.isNotEmpty) effectiveClassId = enr.first.classId;
      }
      if (effectiveClassId == null || !scopeClasses.contains(effectiveClassId)) {
        throw StateError('Action non autorisée (portée affectations)');
      }
      classId = effectiveClassId;
    }
    final id = newUuid();
    await db.into(db.attendanceEvents).insert(AttendanceEventsCompanion.insert(
      id: Value(id),
      category: category,
      studentId: studentId,
      classId: Value(classId),
      date: date,
      slotOrFacts: Value(slotOrFacts),
      status: status,
      justificationOrSanction: Value(justification),
      details: Value(details),
      authorUserId: Value(actorUserId),
    ));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Présences', targetObject: id, description: 'Saisie présence/événement: $status pour élève $studentId', result: 'Succès');
  }

  /// Enregistre l'appel d'une classe pour une date donnée.
  ///
  /// Les identifiants sont déterministes (`appel-<classe>-<date>-<élève>`),
  /// ce qui permet de refaire l'appel sans créer de doublons.
  Future<int> recordAppel({
    required String classId,
    required DateTime date,
    required Map<String, String> statusByStudent,
    String? slotOrFacts,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'attendance.create');
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    if (scopeClasses != null && !scopeClasses.contains(classId)) {
      throw StateError('Action non autorisée (portée affectations)');
    }
    if (statusByStudent.isEmpty) return 0;
    final dayKey = '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final at = DateTime(date.year, date.month, date.day, 8);
    await db.transaction(() async {
      for (final entry in statusByStudent.entries) {
        await db.into(db.attendanceEvents).insertOnConflictUpdate(
          AttendanceEventsCompanion.insert(
            id: Value('appel-$classId-$dayKey-${entry.key}'),
            category: 'Appel / Présence',
            studentId: entry.key,
            classId: Value(classId),
            date: at,
            slotOrFacts: Value(slotOrFacts),
            status: entry.value,
            authorUserId: Value(actorUserId),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    });
    await _audit.log(
      userId: actorUserId,
      username: actorUsername,
      module: 'Présences',
      targetObject: classId,
      description: 'Appel enregistré ($dayKey): ${statusByStudent.length} élève(s)',
      result: 'Succès',
      metadata: {'date': dayKey, 'effectif': statusByStudent.length},
    );
    return statusByStudent.length;
  }

  Future<List<Student>> studentsOfClass(String classId) async {
    final rows = await db.select(db.students).join([
      innerJoin(db.enrollments, db.enrollments.studentId.equalsExp(db.students.id)),
    ])
      ..where(db.enrollments.classId.equals(classId) & db.students.isDeleted.equals(false) & db.enrollments.isDeleted.equals(false));
    final res = await rows.get();
    return res.map((r) => r.readTable(db.students)).toList();
  }
}
