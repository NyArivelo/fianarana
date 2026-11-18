import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_service.dart';
import 'package:fianarana/core/services/establishment_service.dart';

class UnauthorizedActionException implements Exception {
  final String permission;
  UnauthorizedActionException(this.permission);
  @override
  String toString() => 'Action non autorisée (permission requise: $permission)';
}

/// Référentiel pédagogique : années scolaires, périodes, niveaux,
/// classes et matières (avec coefficients). CRUD complet + audit.
class StructureRepository {
  final AppDatabase db;
  late final PermissionService _perm = PermissionService(db);
  late final AuditService _audit = AuditService(db);

  StructureRepository(this.db);

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

  Future<void> _trace(String? userId, String? username, String description) {
    return _audit.log(
      userId: userId,
      username: username,
      module: 'Structure',
      targetObject: 'Référentiel pédagogique',
      description: description,
      result: 'Succès',
    );
  }

  // --- Années scolaires ---

  Future<List<SchoolYear>> listYears() {
    return (db.select(db.schoolYears)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.startDate)]))
        .get();
  }

  Future<String> saveYear({
    String? id,
    required String code,
    required String label,
    required DateTime startDate,
    required DateTime endDate,
    String status = 'En cours',
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, id == null ? 'settings.update' : 'settings.update');
    if (endDate.isBefore(startDate)) {
      throw ArgumentError('La date de fin doit suivre la date de début.');
    }
    final establishment = await EstablishmentService(db).current();
    if (establishment == null) {
      throw StateError('Aucun établissement configuré.');
    }
    final now = DateTime.now();
    if (id == null || id.isEmpty) {
      final yearId = newUuid();
      await db.into(db.schoolYears).insert(SchoolYearsCompanion.insert(
        id: Value(yearId),
        establishmentId: establishment.id,
        code: code.trim(),
        label: label.trim(),
        startDate: startDate,
        endDate: endDate,
        status: Value(status),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      await _trace(actorUserId, actorUsername, 'Création année scolaire ${label.trim()}');
      return yearId;
    }
    await (db.update(db.schoolYears)..where((t) => t.id.equals(id))).write(
      SchoolYearsCompanion(
        code: Value(code.trim()),
        label: Value(label.trim()),
        startDate: Value(startDate),
        endDate: Value(endDate),
        status: Value(status),
        updatedAt: Value(now),
      ),
    );
    await _trace(actorUserId, actorUsername, 'Modification année scolaire ${label.trim()}');
    return id;
  }

  // --- Périodes ---

  Future<List<Period>> listPeriods({String? schoolYearId}) {
    final q = db.select(db.periods)..where((t) => t.isDeleted.equals(false));
    if (schoolYearId != null && schoolYearId.isNotEmpty) {
      q.where((t) => t.schoolYearId.equals(schoolYearId));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.sequence)]);
    return q.get();
  }

  Future<String> savePeriod({
    String? id,
    required String schoolYearId,
    required String name,
    int sequence = 1,
    DateTime? startDate,
    DateTime? endDate,
    bool isClosed = false,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'settings.update');
    final now = DateTime.now();
    if (id == null || id.isEmpty) {
      final periodId = newUuid();
      await db.into(db.periods).insert(PeriodsCompanion.insert(
        id: Value(periodId),
        schoolYearId: schoolYearId,
        name: name.trim(),
        sequence: Value(sequence),
        startDate: Value(startDate),
        endDate: Value(endDate),
        isClosed: Value(isClosed),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      await _trace(actorUserId, actorUsername, 'Création période ${name.trim()}');
      return periodId;
    }
    await (db.update(db.periods)..where((t) => t.id.equals(id))).write(
      PeriodsCompanion(
        schoolYearId: Value(schoolYearId),
        name: Value(name.trim()),
        sequence: Value(sequence),
        startDate: Value(startDate),
        endDate: Value(endDate),
        isClosed: Value(isClosed),
        updatedAt: Value(now),
      ),
    );
    await _trace(actorUserId, actorUsername, 'Modification période ${name.trim()}');
    return id;
  }

  Future<void> togglePeriodClosed({
    required String id,
    required bool isClosed,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'settings.update');
    final now = DateTime.now();
    await (db.update(db.periods)..where((t) => t.id.equals(id))).write(
      PeriodsCompanion(
        isClosed: Value(isClosed),
        closedAt: Value(isClosed ? now : null),
        closedByUserId: Value(isClosed ? actorUserId : null),
        updatedAt: Value(now),
      ),
    );
    await _trace(actorUserId, actorUsername,
        isClosed ? 'Clôture période $id' : 'Réouverture période $id');
  }

  // --- Niveaux (cycle / filière) ---

  Future<List<Level>> listLevels() {
    return (db.select(db.levels)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
        .get();
  }

  Future<String> saveLevel({
    String? id,
    required String name,
    String? cycle,
    String? track,
    int sequence = 0,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'settings.update');
    final now = DateTime.now();
    if (id == null || id.isEmpty) {
      final levelId = newUuid();
      await db.into(db.levels).insert(LevelsCompanion.insert(
        id: Value(levelId),
        name: name.trim(),
        cycle: Value(cycle),
        track: Value(track),
        sequence: Value(sequence),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      await _trace(actorUserId, actorUsername, 'Création niveau ${name.trim()}');
      return levelId;
    }
    await (db.update(db.levels)..where((t) => t.id.equals(id))).write(
      LevelsCompanion(
        name: Value(name.trim()),
        cycle: Value(cycle),
        track: Value(track),
        sequence: Value(sequence),
        updatedAt: Value(now),
      ),
    );
    await _trace(actorUserId, actorUsername, 'Modification niveau ${name.trim()}');
    return id;
  }

  // --- Classes ---

  Future<List<ClassesData>> listClasses({String? schoolYearId}) {
    final q = db.select(db.classes)..where((t) => t.isDeleted.equals(false));
    if (schoolYearId != null && schoolYearId.isNotEmpty) {
      q.where((t) => t.schoolYearId.equals(schoolYearId));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.label)]);
    return q.get();
  }

  Future<String> saveClass({
    String? id,
    String? schoolYearId,
    String? levelId,
    String? code,
    required String label,
    int? capacity,
    String? room,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'settings.update');
    final now = DateTime.now();
    if (id == null || id.isEmpty) {
      final classId = newUuid();
      await db.into(db.classes).insert(ClassesCompanion.insert(
        id: Value(classId),
        schoolYearId: Value(schoolYearId),
        levelId: Value(levelId),
        code: Value(code),
        label: label.trim(),
        capacity: Value(capacity),
        room: Value(room),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      await _trace(actorUserId, actorUsername, 'Création classe ${label.trim()}');
      return classId;
    }
    await (db.update(db.classes)..where((t) => t.id.equals(id))).write(
      ClassesCompanion(
        schoolYearId: Value(schoolYearId),
        levelId: Value(levelId),
        code: Value(code),
        label: Value(label.trim()),
        capacity: Value(capacity),
        room: Value(room),
        updatedAt: Value(now),
      ),
    );
    await _trace(actorUserId, actorUsername, 'Modification classe ${label.trim()}');
    return id;
  }

  // --- Matières ---

  Future<List<Subject>> listSubjects() {
    return (db.select(db.subjects)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<String> saveSubject({
    String? id,
    required String code,
    required String name,
    double coefficientSec2 = 1,
    double coefficientSec3 = 1,
    String? domain,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'settings.update');
    final now = DateTime.now();
    if (id == null || id.isEmpty) {
      final subjectId = newUuid();
      await db.into(db.subjects).insert(SubjectsCompanion.insert(
        id: Value(subjectId),
        code: code.trim(),
        name: name.trim(),
        coefficientSec2: Value(coefficientSec2),
        coefficientSec3: Value(coefficientSec3),
        domain: Value(domain),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      await _trace(actorUserId, actorUsername, 'Création matière ${name.trim()}');
      return subjectId;
    }
    await (db.update(db.subjects)..where((t) => t.id.equals(id))).write(
      SubjectsCompanion(
        code: Value(code.trim()),
        name: Value(name.trim()),
        coefficientSec2: Value(coefficientSec2),
        coefficientSec3: Value(coefficientSec3),
        domain: Value(domain),
        updatedAt: Value(now),
      ),
    );
    await _trace(actorUserId, actorUsername, 'Modification matière ${name.trim()}');
    return id;
  }

  // --- Suppression logique (corbeille) ---

  Future<void> archive({
    required String entity,
    required String id,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'settings.update');
    final now = DateTime.now();
    switch (entity) {
      case 'school_year':
        await (db.update(db.schoolYears)..where((t) => t.id.equals(id)))
            .write(SchoolYearsCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now)));
        break;
      case 'period':
        await (db.update(db.periods)..where((t) => t.id.equals(id)))
            .write(PeriodsCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now)));
        break;
      case 'level':
        await (db.update(db.levels)..where((t) => t.id.equals(id)))
            .write(LevelsCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now)));
        break;
      case 'class':
        await (db.update(db.classes)..where((t) => t.id.equals(id)))
            .write(ClassesCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now)));
        break;
      case 'subject':
        await (db.update(db.subjects)..where((t) => t.id.equals(id)))
            .write(SubjectsCompanion(isDeleted: const Value(true), deletedAt: Value(now), updatedAt: Value(now)));
        break;
      default:
        throw ArgumentError('Entité inconnue: $entity');
    }
    await _trace(actorUserId, actorUsername, 'Archivage $entity $id');
  }
}
