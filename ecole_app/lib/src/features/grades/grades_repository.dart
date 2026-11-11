import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

class GradesRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  GradesRepository(this.db);

  Stream<List<Evaluation>> watchEvaluations({String? classId, String? periodId}) {
    final q = db.select(db.evaluations)..where((t) => t.isDeleted.equals(false));
    if (classId != null) q.where((t) => t.classId.equals(classId));
    if (periodId != null) q.where((t) => t.periodId.equals(periodId));
    q.orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return q.watch();
  }

  Future<String> upsertEvaluation({String? id, String? academicYearId, String? periodId, required String classId, required String subjectId, required String title, double coefficient = 1, double maxScore = 20, DateTime? date}) async {
    final now = DateTime.now();
    if (id == null) {
      final nid = _uuid.v4();
      await db.into(db.evaluations).insert(EvaluationsCompanion.insert(id: nid, academicYearId: Value(academicYearId), periodId: Value(periodId), classId: classId, subjectId: subjectId, title: title, coefficient: Value(coefficient), maxScore: Value(maxScore), date: Value(date)));
      return nid;
    } else {
      await (db.update(db.evaluations)..where((t) => t.id.equals(id))).write(EvaluationsCompanion(academicYearId: Value(academicYearId), periodId: Value(periodId), classId: Value(classId), subjectId: Value(subjectId), title: Value(title), coefficient: Value(coefficient), maxScore: Value(maxScore), date: Value(date), updatedAt: Value(now)));
      return id;
    }
  }

  Stream<List<Grade>> watchGradesForEvaluation(String evaluationId) {
    return (db.select(db.grades)..where((t) => t.evaluationId.equals(evaluationId) & t.isDeleted.equals(false))).watch();
  }

  Future<void> setGrade({required String evaluationId, required String studentId, double? score, bool isAbsent = false, bool isExempt = false, String? comment}) async {
    final existing = await (db.select(db.grades)..where((t) => t.evaluationId.equals(evaluationId) & t.studentId.equals(studentId))).getSingleOrNull();
    final now = DateTime.now();
    if (existing == null) {
      await db.into(db.grades).insert(GradesCompanion.insert(id: _uuid.v4(), evaluationId: evaluationId, studentId: studentId, score: Value(score), isAbsent: Value(isAbsent), isExempt: Value(isExempt), comment: Value(comment)));
    } else {
      await (db.update(db.grades)..where((t) => t.id.equals(existing.id))).write(GradesCompanion(score: Value(score), isAbsent: Value(isAbsent), isExempt: Value(isExempt), comment: Value(comment), updatedAt: Value(now)));
    }
  }

  Future<List<Student>> studentsForClass(String classId, {String? academicYearId}) async {
    final q = db.select(db.students).join([innerJoin(db.enrollments, db.enrollments.studentId.equalsExp(db.students.id))]);
    var where = db.enrollments.classId.equals(classId) & db.students.isDeleted.equals(false) & db.enrollments.isDeleted.equals(false);
    if (academicYearId != null) where = where & db.enrollments.academicYearId.equals(academicYearId);
    q.where(where);
    final rows = await q.get();
    final map = <String, Student>{};
    for (final r in rows) { final s = r.readTable(db.students); map[s.id] = s; }
    final list = map.values.toList()..sort((a,b)=>('${a.lastName} ${a.firstName}').compareTo('${b.lastName} ${b.firstName}'));
    return list;
  }

  /// Returns subject averages for a student in a class/period: list of {subjectName, averageOn20, coef}
  Future<List<Map<String, dynamic>>> bulletinLines({required String studentId, required String classId, String? periodId, String? academicYearId}) async {
    final evalQ = db.select(db.evaluations)..where((t) => t.classId.equals(classId) & t.isDeleted.equals(false));
    if (periodId != null) evalQ.where((t) => t.periodId.equals(periodId));
    if (academicYearId != null) evalQ.where((t) => t.academicYearId.equals(academicYearId));
    final evals = await evalQ.get();
    final bySubject = <String, List<Evaluation>>{};
    for (final e in evals) { bySubject.putIfAbsent(e.subjectId, () => []).add(e); }
    final subjects = {for (final s in await (db.select(db.subjects)..where((t)=>t.isDeleted.equals(false))).get()) s.id: s};
    final result = <Map<String, dynamic>>[];
    for (final entry in bySubject.entries) {
      double weightedSum = 0; double weightTotal = 0;
      for (final ev in entry.value) {
        final g = await (db.select(db.grades)..where((t)=>t.evaluationId.equals(ev.id) & t.studentId.equals(studentId))).getSingleOrNull();
        if (g == null || g.isExempt) continue; // exempt = neutralized
        double? normalized;
        if (g.isAbsent) { normalized = 0; } // simple policy
        else if (g.score != null && ev.maxScore > 0) { normalized = (g.score! / ev.maxScore) * 20.0; }
        if (normalized != null) { weightedSum += normalized * ev.coefficient; weightTotal += ev.coefficient; }
      }
      if (weightTotal > 0) {
        final subj = subjects[entry.key];
        result.add({'subject': subj?.name ?? entry.key, 'average': weightedSum / weightTotal, 'coef': subj?.defaultCoefficient ?? 1.0});
      }
    }
    result.sort((a,b)=>(a['subject'] as String).compareTo(b['subject'] as String));
    return result;
  }
}
