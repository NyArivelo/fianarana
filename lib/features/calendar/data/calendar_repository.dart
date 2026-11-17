import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_service.dart';

/// Événement de calendrier enrichi du libellé de classe.
class CalendarEntry {
  final CalendarEvent event;
  final String? classLabel;
  const CalendarEntry(this.event, this.classLabel);

  bool get isGlobal => event.classId == null;
  bool get isEphemeris => event.isEphemeris;
}

/// Regroupement d'éphémérides par période (bimestriel / trimestriel / annuel).
class EphemerisPeriodGroup {
  final String label;
  final String subtitle;
  final DateTime start;
  final DateTime end;
  final List<CalendarEntry> entries;
  const EphemerisPeriodGroup({
    required this.label,
    required this.subtitle,
    required this.start,
    required this.end,
    required this.entries,
  });
}

class CalendarRepository {
  final AppDatabase db;
  late final AuditService _audit = AuditService(db);
  late final PermissionService _perm = PermissionService(db);
  CalendarRepository(this.db);

  Future<void> _require(String? userId, String permission) async {
    if (userId == null || userId.isEmpty) return;
    if (!await _perm.userHasPermission(userId, permission)) {
      throw UnauthorizedActionException(permission);
    }
  }

  /// Liste les événements. `classId` null => tous. `isEphemeris` permet de
  /// distinguer le calendrier scolaire de l'éphéméride globale.
  Future<List<CalendarEntry>> list({
    String? actorUserId,
    String? classId,
    bool includeGlobal = true,
    bool? isEphemeris,
    DateTime? from,
    DateTime? to,
  }) async {
    await _require(actorUserId, 'settings.read');
    final e = db.calendarEvents;
    final c = db.classes;
    final query = db.select(e).join([leftOuterJoin(c, c.id.equalsExp(e.classId))]);
    query.where(e.isDeleted.equals(false));
    query.where(e.status.equals('Publié'));
    if (isEphemeris != null) query.where(e.isEphemeris.equals(isEphemeris));
    if (classId != null && classId.isNotEmpty) {
      final predicate = includeGlobal ? (e.classId.isNull() | e.classId.equals(classId)) : e.classId.equals(classId);
      query.where(predicate);
    } else if (!includeGlobal) {
      query.where(e.classId.isNull());
    }
    if (from != null) {
      query.where(e.startDate.isBiggerOrEqualValue(DateTime(from.year, from.month, from.day)));
    }
    if (to != null) {
      final end = DateTime(to.year, to.month, to.day, 23, 59, 59);
      query.where(e.startDate.isSmallerOrEqualValue(end));
    }
    query.orderBy([
      OrderingTerm.asc(e.startDate),
      OrderingTerm.asc(e.startTime),
      OrderingTerm.asc(e.title),
    ]);
    final rows = await query.get();
    return rows.map((row) {
      final event = row.readTable(db.calendarEvents);
      final cl = row.readTableOrNull(db.classes);
      return CalendarEntry(event, cl?.label);
    }).toList();
  }

  Future<List<ClassesData>> allClasses() {
    return (db.select(db.classes)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.label)]))
        .get();
  }

  Future<String> upsert({
    String? id,
    String? classId,
    required String title,
    String category = 'Événement',
    required DateTime startDate,
    DateTime? endDate,
    bool allDay = true,
    String? startTime,
    String? endTime,
    String? location,
    String? description,
    String? colorHex,
    bool isEphemeris = false,
    String visibility = 'Établissement',
    String status = 'Publié',
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'settings.update');
    final eventId = id ?? newUuid();
    final now = DateTime.now();
    final schoolYears = await db.select(db.schoolYears).get();
    final schoolYearId = schoolYears.isNotEmpty ? schoolYears.first.id : null;
    await db.into(db.calendarEvents).insertOnConflictUpdate(CalendarEventsCompanion.insert(
          id: Value(eventId),
          schoolYearId: Value(schoolYearId),
          classId: Value(classId),
          title: title,
          category: Value(category),
          startDate: DateTime(startDate.year, startDate.month, startDate.day),
          endDate: Value(endDate == null ? null : DateTime(endDate.year, endDate.month, endDate.day)),
          allDay: Value(allDay),
          startTime: Value(allDay ? null : startTime),
          endTime: Value(allDay ? null : endTime),
          location: Value(location),
          description: Value(description),
          colorHex: Value(colorHex),
          isEphemeris: Value(isEphemeris),
          visibility: Value(visibility),
          status: Value(status),
          updatedAt: Value(now),
          createdAt: Value(now),
        ));
    await _audit.log(
      userId: actorUserId,
      username: actorUsername,
      module: 'Calendrier scolaire',
      targetObject: eventId,
      description: 'Enregistrement événement « $title » ($category)',
      result: 'Succès',
    );
    return eventId;
  }

  Future<void> delete(String id, {String? actorUserId, String? actorUsername}) async {
    await _require(actorUserId, 'settings.update');
    await (db.update(db.calendarEvents)..where((t) => t.id.equals(id))).write(
      CalendarEventsCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())),
    );
    await _audit.log(
      userId: actorUserId,
      username: actorUsername,
      module: 'Calendrier scolaire',
      targetObject: id,
      description: 'Suppression (corbeille) d\'un événement',
      result: 'Succès',
    );
  }

  /// Périodes scolaires (trimestres), pour l'éphéméride.
  Future<List<Period>> listPeriods({String? schoolYearId}) async {
    final q = db.select(db.periods)..where((t) => t.isDeleted.equals(false));
    if (schoolYearId != null && schoolYearId.isNotEmpty) {
      q.where((t) => t.schoolYearId.equals(schoolYearId));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.sequence)]);
    return q.get();
  }

  Future<SchoolYear?> activeSchoolYear() async {
    final q = db.select(db.schoolYears)..where((t) => t.isDeleted.equals(false));
    q.orderBy([(t) => OrderingTerm.desc(t.startDate)]);
    final years = await q.get();
    for (final y in years) {
      if (y.status.toLowerCase().contains('cours')) return y;
    }
    return years.isEmpty ? null : years.first;
  }
}

class UnauthorizedActionException implements Exception {
  final String permission;
  UnauthorizedActionException(this.permission);
  @override
  String toString() => 'Action non autorisée (permission requise: $permission)';
}
