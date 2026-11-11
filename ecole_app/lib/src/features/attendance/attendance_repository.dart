import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

class AttendanceRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  AttendanceRepository(this.db);

  Stream<List<AttendanceRecord>> watchForSession(String sessionId) {
    return (db.select(db.attendanceRecords)
          ..where((t) => t.sessionId.equals(sessionId) & t.isDeleted.equals(false)))
        .watch();
  }

  Future<void> setAttendance({required String sessionId, required String studentId, required String status, String? note}) async {
    final existing = await (db.select(db.attendanceRecords)
          ..where((t) => t.sessionId.equals(sessionId) & t.studentId.equals(studentId)))
        .getSingleOrNull();
    final now = DateTime.now();
    if (existing == null) {
      await db.into(db.attendanceRecords).insert(AttendanceRecordsCompanion.insert(
        id: _uuid.v4(), sessionId: sessionId, studentId: studentId, status: Value(status), note: Value(note)));
    } else {
      await (db.update(db.attendanceRecords)..where((t) => t.id.equals(existing.id))).write(
        AttendanceRecordsCompanion(status: Value(status), note: Value(note), updatedAt: Value(now)));
    }
  }

  Future<List<Student>> studentsForClassSession(CourseSession session) async {
    if (session.classId == null) return [];
    // students enrolled in class for academic year (if set) or any enrollment to class
    final q = db.select(db.students).join([
      innerJoin(db.enrollments, db.enrollments.studentId.equalsExp(db.students.id)),
    ]);
    var where = db.enrollments.classId.equals(session.classId!) & db.students.isDeleted.equals(false) & db.enrollments.isDeleted.equals(false);
    if (session.academicYearId != null) {
      where = where & db.enrollments.academicYearId.equals(session.academicYearId!);
    }
    q.where(where);
    final rows = await q.get();
    final map = <String, Student>{};
    for (final r in rows) {
      final s = r.readTable(db.students);
      map[s.id] = s;
    }
    final list = map.values.toList()..sort((a, b) => ('${a.lastName} ${a.firstName}').compareTo('${b.lastName} ${b.firstName}'));
    return list;
  }

  Stream<Map<String, int>> watchStatsForSession(String sessionId) {
    return watchForSession(sessionId).map((records) {
      final m = <String, int>{'present': 0, 'absent': 0, 'late': 0, 'excused': 0};
      for (final r in records) {
        m[r.status] = (m[r.status] ?? 0) + 1;
      }
      return m;
    });
  }
}
