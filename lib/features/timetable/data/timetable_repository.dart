import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_service.dart';

/// Vue détaillée d'une séance (jointures lisibles pour l'interface).
class TimetableEntry {
  final String id;
  final String? classId;
  final String? classLabel;
  final String? classRoom;
  final String? subjectId;
  final String? subjectName;
  final String? teacherId;
  final String? teacherName;
  final String? roomId;
  final String? roomLabel;
  final String dayOfWeek;
  final String startTime;
  final String endTime;
  final String recurrence;
  final bool isSubstitution;
  final String? notes;

  const TimetableEntry({
    required this.id,
    required this.classId,
    required this.classLabel,
    required this.classRoom,
    required this.subjectId,
    required this.subjectName,
    required this.teacherId,
    required this.teacherName,
    required this.roomId,
    required this.roomLabel,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.recurrence,
    required this.isSubstitution,
    required this.notes,
  });
}

class TimetableConflict {
  final String type; // enseignant, classe, salle
  final String message;
  final String sessionA;
  final String sessionB;
  TimetableConflict(this.type, this.message, this.sessionA, this.sessionB);
}

class UnauthorizedActionException implements Exception {
  final String permission;
  UnauthorizedActionException(this.permission);
  @override
  String toString() => 'Action non autorisée (permission requise: $permission)';
}

class TimetableRepository {
  final AppDatabase db;
  late final AuditService _audit = AuditService(db);
  late final PermissionService _perm = PermissionService(db);
  TimetableRepository(this.db);

  Future<void> _require(String? userId, String permission) async {
    if (userId == null || userId.isEmpty) return;
    if (!await _perm.userHasPermission(userId, permission)) throw UnauthorizedActionException(permission);
  }

  Future<List<TimetableEntry>> listEntries({
    String? actorUserId,
    String? classId,
    String? teacherId,
    String? day,
  }) async {
    await _require(actorUserId, 'settings.read');
    final s = db.timetableSessions;
    final c = db.classes;
    final sub = db.subjects;
    final t = db.staffMembers;
    final r = db.facilities;

    final query = db.select(s).join([
      leftOuterJoin(c, c.id.equalsExp(s.classId)),
      leftOuterJoin(sub, sub.id.equalsExp(s.subjectId)),
      leftOuterJoin(t, t.id.equalsExp(s.teacherId)),
      leftOuterJoin(r, r.id.equalsExp(s.roomId)),
    ]);
    query.where(s.isDeleted.equals(false));
    if (classId != null && classId.isNotEmpty) query.where(s.classId.equals(classId));
    if (teacherId != null && teacherId.isNotEmpty) query.where(s.teacherId.equals(teacherId));
    if (day != null && day.isNotEmpty) query.where(s.dayOfWeek.equals(day));
    query.orderBy([
      OrderingTerm.asc(s.dayOfWeek),
      OrderingTerm.asc(s.startTime),
      OrderingTerm.asc(c.label),
    ]);

    final rows = await query.get();
    return rows.map((row) {
      final session = row.readTable(db.timetableSessions);
      final cl = row.readTableOrNull(db.classes);
      final subject = row.readTableOrNull(db.subjects);
      final teacher = row.readTableOrNull(db.staffMembers);
      final room = row.readTableOrNull(db.facilities);
      return TimetableEntry(
        id: session.id,
        classId: session.classId,
        classLabel: cl?.label,
        classRoom: cl?.room,
        subjectId: session.subjectId,
        subjectName: subject?.name,
        teacherId: session.teacherId,
        teacherName: teacher == null ? null : '${teacher.lastName} ${teacher.firstName}',
        roomId: session.roomId,
        roomLabel: room?.name ?? cl?.room,
        dayOfWeek: session.dayOfWeek,
        startTime: session.startTime,
        endTime: session.endTime,
        recurrence: session.recurrence,
        isSubstitution: session.isSubstitution,
        notes: session.notes,
      );
    }).toList();
  }

  Future<List<TimetableSession>> list({String? actorUserId, String? classId, String? teacherId, String? day}) async {
    await _require(actorUserId, 'settings.read');
    final q = db.select(db.timetableSessions)..where((t) => t.isDeleted.equals(false));
    if (classId != null && classId.isNotEmpty) q.where((t) => t.classId.equals(classId));
    if (teacherId != null && teacherId.isNotEmpty) q.where((t) => t.teacherId.equals(teacherId));
    if (day != null && day.isNotEmpty) q.where((t) => t.dayOfWeek.equals(day));
    return q.get();
  }

  Future<List<ClassesData>> allClasses() {
    return (db.select(db.classes)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.label)]))
        .get();
  }

  Future<List<StaffMember>> allTeachers() {
    return (db.select(db.staffMembers)
          ..where((t) => t.isDeleted.equals(false) & t.functionTitle.like('%enseign%'))
          ..orderBy([(t) => OrderingTerm.asc(t.lastName)]))
        .get();
  }

  Future<List<Subject>> allSubjects() {
    return (db.select(db.subjects)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<List<TeacherAssignment>> assignmentsOf({String? classId, String? staffId}) {
    final q = db.select(db.teacherAssignments)..where((t) => t.isDeleted.equals(false));
    if (classId != null && classId.isNotEmpty) q.where((t) => t.classId.equals(classId));
    if (staffId != null && staffId.isNotEmpty) q.where((t) => t.staffId.equals(staffId));
    return q.get();
  }

  int _toMin(String hhmm) {
    final p = hhmm.split(':');
    if (p.length != 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  bool _overlap(TimetableEntry a, TimetableEntry b) {
    if (a.dayOfWeek != b.dayOfWeek) return false;
    final a1 = _toMin(a.startTime), a2 = _toMin(a.endTime);
    final b1 = _toMin(b.startTime), b2 = _toMin(b.endTime);
    return a1 < b2 && b1 < a2;
  }

  /// Détection automatique des conflits (enseignant, classe, salle).
  List<TimetableConflict> detectConflicts(List<TimetableEntry> sessions) {
    final conflicts = <TimetableConflict>[];
    for (var i = 0; i < sessions.length; i++) {
      for (var j = i + 1; j < sessions.length; j++) {
        final a = sessions[i], b = sessions[j];
        if (!_overlap(a, b)) continue;
        if (a.teacherId != null && a.teacherId == b.teacherId) {
          conflicts.add(TimetableConflict(
            'enseignant',
            'Conflit enseignant ${a.dayOfWeek} ${a.startTime}-${a.endTime} (${a.teacherName ?? '?'})',
            a.id,
            b.id,
          ));
        }
        if (a.classId != null && a.classId == b.classId) {
          conflicts.add(TimetableConflict(
            'classe',
            'Conflit classe ${a.dayOfWeek} ${a.startTime}-${a.endTime} (${a.classLabel ?? '?'})',
            a.id,
            b.id,
          ));
        }
        if (a.roomId != null && a.roomId == b.roomId) {
          conflicts.add(TimetableConflict(
            'salle',
            'Conflit salle ${a.dayOfWeek} ${a.startTime}-${a.endTime} (${a.roomLabel ?? '?'})',
            a.id,
            b.id,
          ));
        }
      }
    }
    return conflicts;
  }

  Future<String> upsertSession({
    String? id,
    String? classId,
    String? subjectId,
    String? teacherId,
    String? roomId,
    required String dayOfWeek,
    required String startTime,
    required String endTime,
    String recurrence = 'Hebdomadaire',
    DateTime? date,
    bool isSubstitution = false,
    String? notes,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'settings.update');
    final sid = id ?? newUuid();
    await db.into(db.timetableSessions).insertOnConflictUpdate(TimetableSessionsCompanion.insert(
          id: Value(sid),
          classId: Value(classId),
          subjectId: Value(subjectId),
          teacherId: Value(teacherId),
          roomId: Value(roomId),
          dayOfWeek: dayOfWeek,
          startTime: startTime,
          endTime: endTime,
          recurrence: Value(recurrence),
          date: Value(date),
          isSubstitution: Value(isSubstitution),
          notes: Value(notes),
          updatedAt: Value(DateTime.now()),
        ));
    await _audit.log(
      userId: actorUserId,
      username: actorUsername,
      module: 'Emploi du temps',
      targetObject: sid,
      description: 'Création/mise à jour séance $dayOfWeek $startTime-$endTime',
      result: 'Succès',
    );
    return sid;
  }

  Future<void> deleteSession(String id, {String? actorUserId, String? actorUsername}) async {
    await _require(actorUserId, 'settings.update');
    await (db.update(db.timetableSessions)..where((t) => t.id.equals(id))).write(
      TimetableSessionsCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())),
    );
    await _audit.log(
      userId: actorUserId,
      username: actorUsername,
      module: 'Emploi du temps',
      targetObject: id,
      description: 'Suppression (corbeille) d\'une séance',
      result: 'Succès',
    );
  }
}
