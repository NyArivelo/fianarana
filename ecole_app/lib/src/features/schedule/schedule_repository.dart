import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

class Conflict {
  final String type; // room, class, teacher
  final String message;
  Conflict(this.type, this.message);
}

class ScheduleRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  ScheduleRepository(this.db);

  // Rooms
  Stream<List<Room>> watchRooms() => (db.select(db.rooms)
        ..where((t) => t.isDeleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();

  Future<void> upsertRoom({String? id, required String name, String? location, int? capacity}) async {
    final now = DateTime.now();
    if (id == null) {
      await db.into(db.rooms).insert(RoomsCompanion.insert(
          id: _uuid.v4(), name: name, location: Value(location), capacity: Value(capacity)));
    } else {
      await (db.update(db.rooms)..where((t) => t.id.equals(id))).write(RoomsCompanion(
          name: Value(name), location: Value(location), capacity: Value(capacity), updatedAt: Value(now)));
    }
  }

  // Sessions
  Stream<List<CourseSession>> watchSessions({DateTime? day, List<String>? allowedClassIds}) {
    final q = db.select(db.courseSessions)..where((t) => t.isDeleted.equals(false));
    if (day != null) {
      final start = DateTime(day.year, day.month, day.day);
      final end = start.add(const Duration(days: 1));
      q.where((t) => t.startAt.isBiggerOrEqualValue(start) & t.startAt.isSmallerThanValue(end));
    }
    if (allowedClassIds != null) {
      if (allowedClassIds.isEmpty) return Stream.value(<CourseSession>[]);
      q.where((t) => t.classId.isIn(allowedClassIds));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.startAt)]);
    return q.watch();
  }

  Stream<List<CourseSession>> watchSessionsInRange(DateTime from, DateTime to, {List<String>? allowedClassIds}) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    final q = db.select(db.courseSessions)
      ..where((t) => t.isDeleted.equals(false) & t.startAt.isBiggerOrEqualValue(start) & t.startAt.isSmallerThanValue(end));
    if (allowedClassIds != null) {
      if (allowedClassIds.isEmpty) return Stream.value(<CourseSession>[]);
      q.where((t) => t.classId.isIn(allowedClassIds));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.startAt)]);
    return q.watch();
  }

  Future<List<Conflict>> detectConflicts({
    String? excludeId,
    String? roomId,
    String? classId,
    String? teacherName,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    final conflicts = <Conflict>[];
    final q = db.select(db.courseSessions)
      ..where((t) => t.isDeleted.equals(false) & t.status.isNotIn(['cancelled']) & t.startAt.isSmallerThanValue(endAt) & t.endAt.isBiggerThanValue(startAt));
    if (excludeId != null) q.where((t) => t.id.equals(excludeId).not());
    final overlapping = await q.get();
    for (final s in overlapping) {
      if (roomId != null && s.roomId == roomId) {
        conflicts.add(Conflict('room', 'Conflit de salle avec "${s.title ?? 'séance'}" (${_fmt(s)})'));
      }
      if (classId != null && s.classId == classId) {
        conflicts.add(Conflict('class', 'Conflit de classe avec "${s.title ?? 'séance'}" (${_fmt(s)})'));
      }
      if (teacherName != null && teacherName.trim().isNotEmpty && s.teacherName != null &&
          s.teacherName!.trim().toLowerCase() == teacherName.trim().toLowerCase()) {
        conflicts.add(Conflict('teacher', 'Conflit enseignant avec "${s.title ?? 'séance'}" (${_fmt(s)})'));
      }
    }
    return conflicts;
  }

  String _fmt(CourseSession s) {
    final t1 = '${s.startAt.hour.toString().padLeft(2, '0')}:${s.startAt.minute.toString().padLeft(2, '0')}';
    final t2 = '${s.endAt.hour.toString().padLeft(2, '0')}:${s.endAt.minute.toString().padLeft(2, '0')}';
    return '$t1-$t2';
  }

  Future<void> upsertSession({
    String? id,
    String? academicYearId,
    String? classId,
    String? subjectId,
    String? roomId,
    String? teacherName,
    String? title,
    String courseType = 'regular',
    required DateTime startAt,
    required DateTime endAt,
    String status = 'planned',
    String? notes,
  }) async {
    final now = DateTime.now();
    if (id == null) {
      await db.into(db.courseSessions).insert(CourseSessionsCompanion.insert(
            id: _uuid.v4(),
            academicYearId: Value(academicYearId),
            classId: Value(classId),
            subjectId: Value(subjectId),
            roomId: Value(roomId),
            teacherName: Value(teacherName),
            title: Value(title),
            courseType: Value(courseType),
            startAt: startAt,
            endAt: endAt,
            status: Value(status),
            notes: Value(notes),
          ));
    } else {
      await (db.update(db.courseSessions)..where((t) => t.id.equals(id))).write(CourseSessionsCompanion(
        academicYearId: Value(academicYearId), classId: Value(classId), subjectId: Value(subjectId), roomId: Value(roomId),
        teacherName: Value(teacherName), title: Value(title), courseType: Value(courseType),
        startAt: Value(startAt), endAt: Value(endAt), status: Value(status), notes: Value(notes), updatedAt: Value(now),
      ));
    }
  }

  Future<int> createRecurringSessions({
    String? academicYearId,
    String? classId,
    String? subjectId,
    String? roomId,
    String? teacherName,
    String? title,
    String courseType = 'regular',
    required DateTime firstStartAt,
    required DateTime firstEndAt,
    required int weeks,
  }) async {
    int created = 0;
    await db.transaction(() async {
      for (int i = 0; i < weeks; i++) {
        final startAt = firstStartAt.add(Duration(days: 7 * i));
        final endAt = firstEndAt.add(Duration(days: 7 * i));
        await db.into(db.courseSessions).insert(CourseSessionsCompanion.insert(
          id: _uuid.v4(), academicYearId: Value(academicYearId), classId: Value(classId), subjectId: Value(subjectId),
          roomId: Value(roomId), teacherName: Value(teacherName), title: Value(title), courseType: Value(courseType),
          startAt: startAt, endAt: endAt,
        ));
        created++;
      }
    });
    return created;
  }

  Future<void> deleteSession(String id) async {
    await (db.update(db.courseSessions)..where((t) => t.id.equals(id))).write(
      CourseSessionsCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())));
  }
}
