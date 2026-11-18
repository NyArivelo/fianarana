import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/affectation_scope.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_service.dart';

/// Local ou équipement enrichi du nombre de séances hebdomadaires.
class FacilityRow {
  final Facility facility;
  final int weeklySessions;

  const FacilityRow({required this.facility, required this.weeklySessions});

  String get kind {
    final name = facility.name.toLowerCase();
    if (name.contains('salle')) return 'Salles';
    if (name.contains('labo')) return 'Laboratoires';
    return 'Équipements';
  }

  String? get assignedClass {
    final category = facility.category;
    if (category == null) return null;
    final match = RegExp(r'\(([^)]+)\)').firstMatch(category);
    return match?.group(1);
  }
}

class FacilityStats {
  final int total;
  final int totalCapacity;
  final int functional;
  final int weeklySessions;

  const FacilityStats({
    required this.total,
    required this.totalCapacity,
    required this.functional,
    required this.weeklySessions,
  });

  factory FacilityStats.empty() =>
      const FacilityStats(total: 0, totalCapacity: 0, functional: 0, weeklySessions: 0);
}

class UnauthorizedActionException implements Exception {
  final String permission;
  UnauthorizedActionException(this.permission);
  @override
  String toString() => 'Action non autorisée (permission requise: $permission)';
}

class FacilitiesRepository {
  final AppDatabase db;
  late final AuditService _audit = AuditService(db);
  late final PermissionService _perm = PermissionService(db);

  FacilitiesRepository(this.db);

  Future<void> _require(String? userId, String permission) async {
    if (userId == null || userId.isEmpty) return;
    if (!await _perm.userHasPermission(userId, permission)) {
      await _audit.log(
        userId: userId,
        module: 'Sécurité',
        targetObject: permission,
        description: 'Permission refusée: $permission',
        result: 'Échec',
      );
      throw UnauthorizedActionException(permission);
    }
  }

  Future<List<FacilityRow>> list({String? actorUserId}) async {
    await _require(actorUserId, 'library.read');
    // Portée affectations : limiter aux locaux utilisés par les séances des classes/enseignant autorisés
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    Set<String>? allowedRoomIds;
    if (scopeClasses != null) {
      String? scopeStaffId;
      if (actorUserId != null && actorUserId.isNotEmpty) {
        final st = await (db.select(db.staffMembers)
              ..where((t) => t.userId.equals(actorUserId) & t.isDeleted.equals(false)))
            .getSingleOrNull();
        scopeStaffId = st?.id;
      }
      if (scopeClasses.isEmpty && scopeStaffId == null) {
        return const <FacilityRow>[];
      }
      final q = db.select(db.timetableSessions)
        ..where((t) => t.isDeleted.equals(false) & t.roomId.isNotNull());
      if (scopeStaffId != null && scopeClasses.isNotEmpty) {
        q.where((t) => t.classId.isIn(scopeClasses) | t.teacherId.equals(scopeStaffId!));
      } else if (scopeStaffId != null) {
        q.where((t) => t.teacherId.equals(scopeStaffId!));
      } else {
        q.where((t) => t.classId.isIn(scopeClasses));
      }
      final scopedSessions = await q.get();
      allowedRoomIds = scopedSessions.map((s) => s.roomId).whereType<String>().toSet();
    }

    final allowedRoomIdsList = allowedRoomIds?.toList() ?? const <String>[];

    final fq = db.select(db.facilities)..where((t) => t.isDeleted.equals(false));
    if (allowedRoomIds != null) {
      if (allowedRoomIds!.isEmpty) return const <FacilityRow>[];
      fq.where((t) => t.id.isIn(allowedRoomIdsList));
    }
    fq.orderBy([(t) => OrderingTerm.asc(t.name)]);
    final facilities = await fq.get();

    final sq = db.select(db.timetableSessions)..where((t) => t.isDeleted.equals(false) & t.roomId.isNotNull());
    if (allowedRoomIds != null) {
      sq.where((t) => t.roomId.isIn(allowedRoomIdsList));
    }
    final sessions = await sq.get();
    final counts = <String, int>{};
    for (final s in sessions) {
      if (s.roomId == null) continue;
      counts[s.roomId!] = (counts[s.roomId!] ?? 0) + 1;
    }
    return facilities
        .map((f) => FacilityRow(facility: f, weeklySessions: counts[f.id] ?? 0))
        .toList();
  }

  FacilityStats stats(List<FacilityRow> rows) {
    return FacilityStats(
      total: rows.length,
      totalCapacity: rows.fold<int>(0, (sum, r) => sum + (r.facility.capacity ?? 0)),
      functional: rows
          .where((r) => !r.facility.status.toLowerCase().contains('maintenance'))
          .length,
      weeklySessions: rows.fold<int>(0, (sum, r) => sum + r.weeklySessions),
    );
  }

  Future<String> save({
    String? id,
    required String domain,
    required String name,
    String? code,
    String? category,
    int? capacity,
    required String status,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, id == null ? 'library.create' : 'library.update');
    final now = DateTime.now();
    final facilityId = id ?? newUuid();
    if (id == null) {
      await db.into(db.facilities).insert(FacilitiesCompanion.insert(
        id: Value(facilityId),
        domain: domain,
        code: Value(code),
        name: name,
        category: Value(category),
        capacity: Value(capacity),
        status: Value(status),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
    } else {
      await (db.update(db.facilities)..where((t) => t.id.equals(id))).write(
        FacilitiesCompanion(
          domain: Value(domain),
          code: Value(code),
          name: Value(name),
          category: Value(category),
          capacity: Value(capacity),
          status: Value(status),
          updatedAt: Value(now),
        ),
      );
    }
    await _audit.log(
      userId: actorUserId,
      username: actorUsername,
      module: 'Locaux',
      targetObject: facilityId,
      description: id == null ? 'Création local/équipement: $name' : 'Modification local/équipement: $name',
      result: 'Succès',
    );
    return facilityId;
  }

  // --- Réservations ---

  Future<List<FacilityReservation>> listReservations({
    String? facilityId,
    String? actorUserId,
    bool upcomingOnly = false,
  }) async {
    await _require(actorUserId, 'facilities.read');
    final q = db.select(db.facilityReservations)..where((t) => t.isDeleted.equals(false));
    if (facilityId != null && facilityId.isNotEmpty) {
      q.where((t) => t.facilityId.equals(facilityId));
    }
    if (upcomingOnly) {
      q.where((t) => t.endDate.isBiggerOrEqualValue(DateTime.now()));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.startDate)]);
    return q.get();
  }

  /// Vérifie qu'aucune réservation validée ne chevauche le créneau demandé.
  Future<bool> hasReservationConflict({
    required String facilityId,
    required DateTime startDate,
    required DateTime endDate,
    String? ignoreReservationId,
    String? actorUserId,
  }) async {
    final rows = await listReservations(facilityId: facilityId, actorUserId: actorUserId);
    return rows.any((r) =>
        r.id != ignoreReservationId &&
        (r.status == 'Validée' || r.status == 'Demandée') &&
        reservationsOverlap(startDate, endDate, r.startDate, r.endDate));
  }

  Future<String> saveReservation({
    String? id,
    required String facilityId,
    required String title,
    String? purpose,
    required DateTime startDate,
    required DateTime endDate,
    String status = 'Demandée',
    String? notes,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, id == null ? 'facilities.create' : 'facilities.update');
    if (!endDate.isAfter(startDate)) {
      throw ArgumentError('La fin de réservation doit suivre le début.');
    }
    if (status == 'Validée' &&
        await hasReservationConflict(
          facilityId: facilityId,
          startDate: startDate,
          endDate: endDate,
          ignoreReservationId: id,
          actorUserId: actorUserId,
        )) {
      throw StateError('Conflit de réservation sur ce créneau.');
    }
    final now = DateTime.now();
    if (id == null || id.isEmpty) {
      final reservationId = newUuid();
      await db.into(db.facilityReservations).insert(FacilityReservationsCompanion.insert(
        id: Value(reservationId),
        facilityId: facilityId,
        title: title.trim(),
        purpose: Value(purpose),
        startDate: startDate,
        endDate: endDate,
        requestedByUserId: Value(actorUserId),
        status: Value(status),
        notes: Value(notes),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      await _audit.log(
        userId: actorUserId,
        username: actorUsername,
        module: 'Locaux',
        targetObject: reservationId,
        description: 'Réservation $status: ${title.trim()}',
        result: 'Succès',
      );
      return reservationId;
    }
    await (db.update(db.facilityReservations)..where((t) => t.id.equals(id))).write(
      FacilityReservationsCompanion(
        facilityId: Value(facilityId),
        title: Value(title.trim()),
        purpose: Value(purpose),
        startDate: Value(startDate),
        endDate: Value(endDate),
        status: Value(status),
        notes: Value(notes),
        updatedAt: Value(now),
      ),
    );
    await _audit.log(
      userId: actorUserId,
      username: actorUsername,
      module: 'Locaux',
      targetObject: id,
      description: 'Modification réservation: ${title.trim()} ($status)',
      result: 'Succès',
    );
    return id;
  }

  Future<void> cancelReservation({
    required String id,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'facilities.update');
    final now = DateTime.now();
    await (db.update(db.facilityReservations)..where((t) => t.id.equals(id))).write(
      FacilityReservationsCompanion(
        status: const Value('Annulée'),
        updatedAt: Value(now),
      ),
    );
    await _audit.log(
      userId: actorUserId,
      username: actorUsername,
      module: 'Locaux',
      targetObject: id,
      description: 'Annulation réservation $id',
      result: 'Succès',
    );
  }

  // --- Maintenance ---

  Future<List<FacilityMaintenanceData>> listMaintenance({
    String? facilityId,
    String? actorUserId,
  }) async {
    await _require(actorUserId, 'facilities.read');
    final q = db.select(db.facilityMaintenance)..where((t) => t.isDeleted.equals(false));
    if (facilityId != null && facilityId.isNotEmpty) {
      q.where((t) => t.facilityId.equals(facilityId));
    }
    q.orderBy([(t) => OrderingTerm.desc(t.startDate)]);
    return q.get();
  }

  Future<String> saveMaintenance({
    String? id,
    required String facilityId,
    String type = 'Corrective',
    required String description,
    required DateTime startDate,
    DateTime? endDate,
    int costMga = 0,
    String? provider,
    String status = 'Planifiée',
    String? notes,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, id == null ? 'facilities.create' : 'facilities.update');
    final now = DateTime.now();
    if (id == null || id.isEmpty) {
      final maintenanceId = newUuid();
      await db.into(db.facilityMaintenance).insert(FacilityMaintenanceCompanion.insert(
        id: Value(maintenanceId),
        facilityId: facilityId,
        type: Value(type),
        description: description.trim(),
        startDate: startDate,
        endDate: Value(endDate),
        costMga: Value(costMga),
        provider: Value(provider),
        status: Value(status),
        notes: Value(notes),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      await _audit.log(
        userId: actorUserId,
        username: actorUsername,
        module: 'Locaux',
        targetObject: maintenanceId,
        description: 'Maintenance $type planifiée: ${description.trim()}',
        result: 'Succès',
      );
      return maintenanceId;
    }
    await (db.update(db.facilityMaintenance)..where((t) => t.id.equals(id))).write(
      FacilityMaintenanceCompanion(
        facilityId: Value(facilityId),
        type: Value(type),
        description: Value(description.trim()),
        startDate: Value(startDate),
        endDate: Value(endDate),
        costMga: Value(costMga),
        provider: Value(provider),
        status: Value(status),
        notes: Value(notes),
        updatedAt: Value(now),
      ),
    );
    await _audit.log(
      userId: actorUserId,
      username: actorUsername,
      module: 'Locaux',
      targetObject: id,
      description: 'Modification maintenance: ${description.trim()} ($status)',
      result: 'Succès',
    );
    return id;
  }

  Future<void> completeMaintenance({
    required String id,
    int? costMga,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'facilities.update');
    final now = DateTime.now();
    await (db.update(db.facilityMaintenance)..where((t) => t.id.equals(id))).write(
      FacilityMaintenanceCompanion(
        status: const Value('Terminée'),
        endDate: Value(now),
        costMga: costMga == null ? const Value.absent() : Value(costMga),
        updatedAt: Value(now),
      ),
    );
    await _audit.log(
      userId: actorUserId,
      username: actorUsername,
      module: 'Locaux',
      targetObject: id,
      description: 'Maintenance terminée $id',
      result: 'Succès',
    );
  }
}

/// Deux créneaux se chevauchent si l'un commence avant la fin de l'autre.
bool reservationsOverlap(DateTime startA, DateTime endA, DateTime startB, DateTime endB) {
  return startA.isBefore(endB) && startB.isBefore(endA);
}
