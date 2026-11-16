import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_service.dart';

class GradeRow {
  final String id;
  final String studentId;
  final String studentName;
  final String matricule;
  final String? classLabel;
  final String? subjectName;
  final String? subjectId;
  final String label;
  final double? score;
  final double maxScore;
  final double coefficient;
  final bool isExempt;
  final String validationStatus;
  final String? observation;

  GradeRow({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.matricule,
    required this.classLabel,
    required this.subjectName,
    required this.subjectId,
    required this.label,
    required this.score,
    required this.maxScore,
    required this.coefficient,
    required this.isExempt,
    required this.validationStatus,
    required this.observation,
  });
}

class UnauthorizedActionException implements Exception {
  final String permission;
  UnauthorizedActionException(this.permission);
  @override
  String toString() => 'Action non autorisée (permission requise: $permission)';
}

class GradesRepository {
  final AppDatabase db;
  late final AuditService _audit = AuditService(db);
  late final PermissionService _perm = PermissionService(db);
  GradesRepository(this.db);

  Future<void> _require(String? userId, String permission) async {
    if (userId == null || userId.isEmpty) return;
    if (!await _perm.userHasPermission(userId, permission)) {
      await _audit.log(userId: userId, module: 'Sécurité', targetObject: permission, description: 'Permission refusée: $permission', result: 'Échec');
      throw UnauthorizedActionException(permission);
    }
  }

  Future<List<GradeRow>> list({String? actorUserId, String? classId, String? subjectId, int limit = 500}) async {
    await _require(actorUserId, 'grades.read');
    final e = db.evaluations;
    final s = db.students;
    final c = db.classes;
    final sub = db.subjects;
    final j = db.select(e).join([
      innerJoin(s, s.id.equalsExp(e.studentId)),
      leftOuterJoin(c, c.id.equalsExp(e.classId)),
      leftOuterJoin(sub, sub.id.equalsExp(e.subjectId)),
    ]);
    j.where(e.isDeleted.equals(false));
    if (classId != null && classId.isNotEmpty) j.where(e.classId.equals(classId));
    if (subjectId != null && subjectId.isNotEmpty) j.where(e.subjectId.equals(subjectId));
    j.orderBy([OrderingTerm.asc(s.lastName), OrderingTerm.asc(e.label)]);
    j.limit(limit);
    final rows = await j.get();
    return rows.map((r) {
      final ev = r.readTable(e);
      final st = r.readTable(s);
      final cl = r.readTableOrNull(c);
      final sb = r.readTableOrNull(sub);
      return GradeRow(
        id: ev.id,
        studentId: st.id,
        studentName: '${st.lastName} ${st.firstName}',
        matricule: st.matricule,
        classLabel: cl?.label,
        subjectName: sb?.name ?? sb?.code,
        subjectId: ev.subjectId,
        label: ev.label,
        score: ev.score,
        maxScore: ev.maxScore,
        coefficient: ev.coefficient,
        isExempt: ev.isExempt,
        validationStatus: ev.validationStatus,
        observation: ev.observation,
      );
    }).toList();
  }

  Future<String> upsertGrade({
    String? id,
    required String studentId,
    String? classId,
    String? subjectId,
    String? periodId,
    required String label,
    double? score,
    double maxScore = 20,
    double coefficient = 1,
    bool isExempt = false,
    String? observation,
    String validationStatus = 'Brouillon',
    String? actorUserId,
    String? actorUsername,
  }) async {
    final perm = id == null ? 'grades.create' : 'grades.update';
    await _require(actorUserId, perm);
    final now = DateTime.now();
    final gid = id ?? newUuid();
    await db.into(db.evaluations).insertOnConflictUpdate(EvaluationsCompanion.insert(
      id: gid,
      studentId: studentId,
      classId: Value(classId),
      subjectId: Value(subjectId),
      periodId: Value(periodId),
      label: label,
      score: Value(score),
      maxScore: Value(maxScore),
      coefficient: Value(coefficient),
      isExempt: Value(isExempt),
      observation: Value(observation),
      validationStatus: Value(validationStatus),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Notes', targetObject: gid, description: '${id == null ? "Création" : "Mise à jour"} note $label pour élève $studentId', result: 'Succès');
    return gid;
  }

  Future<void> setValidation({required String gradeId, required String status, String? actorUserId, String? actorUsername}) async {
    await _require(actorUserId, 'grades.validate');
    await (db.update(db.evaluations)..where((t) => t.id.equals(gradeId))).write(
      EvaluationsCompanion(validationStatus: Value(status), updatedAt: Value(DateTime.now())),
    );
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Notes', targetObject: gradeId, description: 'Validation note: $status', result: 'Succès');
  }

  /// Moyenne simple pondérée sur une liste (ignore dispensés et notes nulles).
  static double? weightedAverage(Iterable<GradeRow> rows) {
    double sum = 0;
    double coef = 0;
    for (final r in rows) {
      if (r.isExempt || r.score == null || r.maxScore <= 0) continue;
      final normalized = (r.score! / r.maxScore) * 20.0;
      sum += normalized * r.coefficient;
      coef += r.coefficient;
    }
    if (coef == 0) return null;
    return (sum / coef);
  }
}
