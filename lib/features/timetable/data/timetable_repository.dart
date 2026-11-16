import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_service.dart';

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

  Future<List<TimetableSession>> list({String? actorUserId, String? classId, String? teacherId, String? day}) async {
    await _require(actorUserId, 'settings.read'); // emploi du temps: lecture planification (à affiner)
    final q = db.select(db.timetableSessions)..where((t) => t.isDeleted.equals(false));
    if (classId != null && classId.isNotEmpty) q.where((t) => t.classId.equals(classId));
    if (teacherId != null && teacherId.isNotEmpty) q.where((t) => t.teacherId.equals(teacherId));
    if (day != null && day.isNotEmpty) q.where((t) => t.dayOfWeek.equals(day));
    return q.get();
  }

  int _toMin(String hhmm) {
    final p = hhmm.split(':');
    if (p.length != 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  bool _overlap(TimetableSession a, TimetableSession b) {
    if (a.dayOfWeek != b.dayOfWeek) return false;
    final a1 = _toMin(a.startTime), a2 = _toMin(a.endTime);
    final b1 = _toMin(b.startTime), b2 = _toMin(b.endTime);
    return a1 < b2 && b1 < a2;
  }

  /// Détection automatique des conflits (enseignant, classe, salle) sur les séances chargées.
  List<TimetableConflict> detectConflicts(List<TimetableSession> sessions) {
    final conflicts = <TimetableConflict>[];
    for (var i = 0; i < sessions.length; i++) {
      for (var j = i + 1; j < sessions.length; j++) {
        final a = sessions[i], b = sessions[j];
        if (!_overlap(a, b)) continue;
        if (a.teacherId != null && a.teacherId == b.teacherId) {
          conflicts.add(TimetableConflict('enseignant', 'Conflit enseignant sur ${a.dayOfWeek} ${a.startTime}-${a.endTime}', a.id, b.id));
        }
        if (a.classId != null && a.classId == b.classId) {
          conflicts.add(TimetableConflict('classe', 'Conflit classe sur ${a.dayOfWeek} ${a.startTime}-${a.endTime}', a.id, b.id));
        }
        if (a.roomId != null && a.roomId == b.roomId) {
          conflicts.add(TimetableConflict('salle', 'Conflit salle sur ${a.dayOfWeek} ${a.startTime}-${a.endTime}', a.id, b.id));
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
      id: sid,
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
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Emploi du temps', targetObject: sid, description: 'Création/mise à jour séance $dayOfWeek $startTime-$endTime', result: 'Succès');
    return sid;
  }
}
