import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
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
    final facilities = await (db.select(db.facilities)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
    final sessions = await (db.select(db.timetableSessions)
          ..where((t) => t.isDeleted.equals(false) & t.roomId.isNotNull()))
        .get();
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
}
