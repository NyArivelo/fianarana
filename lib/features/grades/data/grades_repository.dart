import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/affectation_scope.dart';
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
  final String? masteryLevel;
  final String? competencyCode;
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
    required this.masteryLevel,
    required this.competencyCode,
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
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    if (scopeClasses != null) {
      if (scopeClasses.isEmpty) return const <GradeRow>[];
      if (classId != null && classId.isNotEmpty && !scopeClasses.contains(classId)) return const <GradeRow>[];
    }
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
    if (classId != null && classId.isNotEmpty) {
      j.where(e.classId.equals(classId));
    } else if (scopeClasses != null) {
      j.where(e.classId.isIn(scopeClasses));
    }
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
        masteryLevel: ev.masteryLevel,
        competencyCode: ev.competencyCode,
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
    String? masteryLevel,
    String? competencyCode,
    String? observation,
    String validationStatus = 'Brouillon',
    String? actorUserId,
    String? actorUsername,
  }) async {
    final perm = id == null ? 'grades.create' : 'grades.update';
    await _require(actorUserId, perm);
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
    final now = DateTime.now();
    final gid = id ?? newUuid();
    await db.into(db.evaluations).insertOnConflictUpdate(EvaluationsCompanion.insert(
      id: Value(gid),
      studentId: studentId,
      classId: Value(classId),
      subjectId: Value(subjectId),
      periodId: Value(periodId),
      label: label,
      score: Value(score),
      maxScore: Value(maxScore),
      coefficient: Value(coefficient),
      isExempt: Value(isExempt),
      masteryLevel: Value(masteryLevel),
      competencyCode: Value(competencyCode),
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
    // empêcher modification si période verrouillée
    final grade = await (db.select(db.evaluations)..where((t) => t.id.equals(gradeId))).getSingleOrNull();
    if (grade == null) throw StateError('Note introuvable');
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    if (scopeClasses != null) {
      String? effectiveClassId = grade.classId;
      if (effectiveClassId == null || effectiveClassId.isEmpty) {
        final enr = await (db.select(db.enrollments)..where((t)=>t.studentId.equals(grade.studentId) & t.isDeleted.equals(false))..orderBy([(t)=>OrderingTerm.desc(t.updatedAt)])).get();
        if (enr.isNotEmpty) effectiveClassId = enr.first.classId;
      }
      if (effectiveClassId == null || !scopeClasses.contains(effectiveClassId)) {
        throw StateError('Action non autorisée (portée affectations)');
      }
    }
    if (grade.periodId != null) {
      await _ensurePeriodUnlocked(grade.periodId!);
    }
    await (db.update(db.evaluations)..where((t) => t.id.equals(gradeId))).write(
      EvaluationsCompanion(validationStatus: Value(status), updatedAt: Value(DateTime.now())),
    );
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Notes', targetObject: gradeId, description: 'Validation note: $status', result: 'Succès');
  }

  Future<void> _ensurePeriodUnlocked(String periodId) async {
    final p = await (db.select(db.periods)..where((t) => t.id.equals(periodId))).getSingleOrNull();
    if (p != null && p.isClosed) {
      throw StateError('Période clôturée/verrouillée: modification interdite sans déverrouillage autorisé.');
    }
  }

  /// Verrouillage de période après délibération (Direction uniquement via permission).
  Future<void> lockPeriod({required String periodId, String? actorUserId, String? actorUsername}) async {
    await _require(actorUserId, 'grades.publish'); // validation/publication conseil
    final now = DateTime.now();
    await (db.update(db.periods)..where((t) => t.id.equals(periodId))).write(PeriodsCompanion(
      isClosed: const Value(true),
      closedAt: Value(now),
      closedByUserId: Value(actorUserId),
      updatedAt: Value(now),
    ));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Notes', targetObject: periodId, description: 'Verrouillage de période après délibération', result: 'Succès');
  }

  Future<void> unlockPeriod({required String periodId, required String reason, String? actorUserId, String? actorUsername}) async {
    await _require(actorUserId, 'security.update'); // réservé Direction/Admin via attribution
    final now = DateTime.now();
    await (db.update(db.periods)..where((t) => t.id.equals(periodId))).write(PeriodsCompanion(
      isClosed: const Value(false),
      closedAt: const Value(null),
      updatedAt: Value(now),
    ));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Notes', targetObject: periodId, description: 'Déverrouillage exceptionnel de période', result: 'Succès', metadata: {'reason': reason});
  }

  Future<List<Period>> listPeriods() => (db.select(db.periods)..where((t)=>t.isDeleted.equals(false))..orderBy([(t)=>OrderingTerm.asc(t.sequence)])).get();

  Future<String> upsertCouncil({
    String? id,
    required String classId,
    required String periodId,
    DateTime? councilDate,
    String status = 'Préparation',
    String? globalAppreciation,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'grades.validate');
    final cid = id ?? newUuid();
    await db.into(db.classCouncils).insertOnConflictUpdate(ClassCouncilsCompanion.insert(
      id: Value(cid),
      classId: classId,
      periodId: periodId,
      councilDate: Value(councilDate),
      status: Value(status),
      globalAppreciation: Value(globalAppreciation),
      updatedAt: Value(DateTime.now()),
    ));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Conseil de classe', targetObject: cid, description: 'Mise à jour conseil de classe ($status)', result: 'Succès');
    return cid;
  }

  Future<void> upsertDecision({
    String? id,
    required String councilId,
    required String studentId,
    String? decision,
    String? appreciation,
    double? average,
    int? rank,
    String? mention,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'grades.validate');
    final did = id ?? newUuid();
    await db.into(db.councilDecisions).insertOnConflictUpdate(CouncilDecisionsCompanion.insert(
      id: Value(did),
      councilId: councilId,
      studentId: studentId,
      decision: Value(decision),
      appreciation: Value(appreciation),
      average: Value(average),
      rank: Value(rank),
      mention: Value(mention),
      updatedAt: Value(DateTime.now()),
    ));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Conseil de classe', targetObject: did, description: 'Décision conseil: ${decision ?? "appréciation"} pour élève $studentId', result: 'Succès');
  }

  Future<List<ClassCouncil>> listCouncils({String? classId, String? periodId}) {
    final q = db.select(db.classCouncils)..where((t) => t.isDeleted.equals(false));
    if (classId != null) q.where((t) => t.classId.equals(classId));
    if (periodId != null) q.where((t) => t.periodId.equals(periodId));
    return (q..orderBy([(t)=>OrderingTerm.desc(t.updatedAt)])).get();
  }

  Future<List<CouncilDecision>> decisionsOf(String councilId) {
    return (db.select(db.councilDecisions)..where((t) => t.councilId.equals(councilId) & t.isDeleted.equals(false))).get();
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
