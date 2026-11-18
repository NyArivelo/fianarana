import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/affectation_scope.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_service.dart';

class UnauthorizedActionException implements Exception {
  final String permission;
  UnauthorizedActionException(this.permission);
  @override
  String toString() => 'Action non autorisée (permission requise: $permission)';
}

/// Une sanction ne peut être exécutée que si le dossier est instruit.
bool canExecuteSanction(String caseStatus) =>
    caseStatus == 'En cours' || caseStatus == 'Traité';

/// Un dossier ne peut être clos que s'il est traité (décision rendue).
bool canCloseCase(String caseStatus) =>
    caseStatus == 'Traité' || caseStatus == 'En cours';

class DisciplineCaseRow {
  final DisciplineCase disciplineCase;
  final String studentName;
  final String matricule;
  final String? classLabel;
  final int pendingActions;

  const DisciplineCaseRow({
    required this.disciplineCase,
    required this.studentName,
    required this.matricule,
    required this.classLabel,
    required this.pendingActions,
  });
}

class DisciplineRepository {
  final AppDatabase db;
  late final PermissionService _perm = PermissionService(db);
  late final AuditService _audit = AuditService(db);

  DisciplineRepository(this.db);

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
      module: 'Discipline',
      targetObject: 'Dossier de discipline',
      description: description,
      result: 'Succès',
    );
  }

  Future<List<DisciplineCaseRow>> listCases({
    String? actorUserId,
    String? statusFilter,
    String? query,
  }) async {
    await _require(actorUserId, 'discipline.read');
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    if (scopeClasses != null && scopeClasses.isEmpty) return const [];
    final d = db.disciplineCases;
    final s = db.students;
    final c = db.classes;
    final j = db.select(d).join([
      innerJoin(s, s.id.equalsExp(d.studentId)),
      leftOuterJoin(c, c.id.equalsExp(d.classId)),
    ])..where(d.isDeleted.equals(false));
    if (scopeClasses != null) j.where(d.classId.isIn(scopeClasses));
    if (statusFilter != null && statusFilter.isNotEmpty && statusFilter != 'Tous') {
      j.where(d.status.equals(statusFilter));
    }
    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      j.where(s.lastName.like(q) | s.firstName.like(q) | s.matricule.like(q) | d.facts.like(q));
    }
    j.orderBy([OrderingTerm.desc(d.incidentDate)]);
    final rows = await j.get();

    final actions = await (db.select(db.disciplineActions)
          ..where((t) => t.isDeleted.equals(false) & t.status.equals('À faire')))
        .get();
    final pending = <String, int>{};
    for (final a in actions) {
      pending[a.caseId] = (pending[a.caseId] ?? 0) + 1;
    }
    return rows.map((r) {
      final dc = r.readTable(d);
      final st = r.readTable(s);
      final cl = r.readTableOrNull(c);
      return DisciplineCaseRow(
        disciplineCase: dc,
        studentName: '${st.lastName} ${st.firstName}',
        matricule: st.matricule,
        classLabel: cl?.label,
        pendingActions: pending[dc.id] ?? 0,
      );
    }).toList();
  }

  Future<List<DisciplineAction>> listActions(String caseId) {
    return (db.select(db.disciplineActions)
          ..where((t) => t.caseId.equals(caseId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<String> saveCase({
    String? id,
    required String studentId,
    String? classId,
    required DateTime incidentDate,
    String category = 'Incident',
    String severity = 'Moyenne',
    required String facts,
    String status = 'Ouvert',
    DateTime? convocationDate,
    DateTime? commissionDate,
    String? decision,
    String? sanction,
    DateTime? sanctionStartDate,
    DateTime? sanctionEndDate,
    String? notes,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, id == null ? 'discipline.create' : 'discipline.update');
    if (facts.trim().isEmpty) throw ArgumentError('Les faits doivent être renseignés.');
    final now = DateTime.now();
    if (id == null || id.isEmpty) {
      final caseId = newUuid();
      await db.into(db.disciplineCases).insert(DisciplineCasesCompanion.insert(
        id: Value(caseId),
        studentId: studentId,
        classId: Value(classId),
        incidentDate: incidentDate,
        category: Value(category),
        severity: Value(severity),
        facts: facts.trim(),
        reportedByUserId: Value(actorUserId),
        status: Value(status),
        convocationDate: Value(convocationDate),
        commissionDate: Value(commissionDate),
        decision: Value(decision),
        sanction: Value(sanction),
        sanctionStartDate: Value(sanctionStartDate),
        sanctionEndDate: Value(sanctionEndDate),
        notes: Value(notes),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      await _trace(actorUserId, actorUsername, 'Ouverture dossier discipline $category ($severity)');
      return caseId;
    }
    await (db.update(db.disciplineCases)..where((t) => t.id.equals(id))).write(
      DisciplineCasesCompanion(
        studentId: Value(studentId),
        classId: Value(classId),
        incidentDate: Value(incidentDate),
        category: Value(category),
        severity: Value(severity),
        facts: Value(facts.trim()),
        status: Value(status),
        convocationDate: Value(convocationDate),
        commissionDate: Value(commissionDate),
        decision: Value(decision),
        sanction: Value(sanction),
        sanctionStartDate: Value(sanctionStartDate),
        sanctionEndDate: Value(sanctionEndDate),
        notes: Value(notes),
        updatedAt: Value(now),
      ),
    );
    await _trace(actorUserId, actorUsername, 'Mise à jour dossier discipline $id');
    return id;
  }

  Future<String> addAction({
    required String caseId,
    required String actionType,
    String? description,
    DateTime? dueDate,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'discipline.update');
    final id = newUuid();
    final now = DateTime.now();
    await db.into(db.disciplineActions).insert(DisciplineActionsCompanion.insert(
      id: Value(id),
      caseId: caseId,
      actionType: actionType,
      description: Value(description),
      dueDate: Value(dueDate),
      status: const Value('À faire'),
      actorUserId: Value(actorUserId),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    await _trace(actorUserId, actorUsername, 'Action discipline ajoutée: $actionType');
    return id;
  }

  Future<void> executeAction({
    required String actionId,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'discipline.update');
    final now = DateTime.now();
    await (db.update(db.disciplineActions)..where((t) => t.id.equals(actionId))).write(
      DisciplineActionsCompanion(
        status: const Value('Exécutée'),
        executedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await _trace(actorUserId, actorUsername, 'Action discipline exécutée $actionId');
  }

  Future<void> closeCase({
    required String id,
    String? decision,
    String? sanction,
    bool sanctionExecuted = false,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'discipline.close');
    final row = await (db.select(db.disciplineCases)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) throw StateError('Dossier introuvable.');
    if (!canCloseCase(row.status)) {
      throw StateError('Le dossier doit être traité avant clôture.');
    }
    final now = DateTime.now();
    await (db.update(db.disciplineCases)..where((t) => t.id.equals(id))).write(
      DisciplineCasesCompanion(
        status: const Value('Clos'),
        decision: Value(decision ?? row.decision),
        sanction: Value(sanction ?? row.sanction),
        sanctionExecuted: Value(sanctionExecuted),
        closedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await _trace(actorUserId, actorUsername, 'Clôture dossier discipline $id');
  }

  Future<void> markSanctionExecuted({
    required String id,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'discipline.update');
    final row = await (db.select(db.disciplineCases)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) throw StateError('Dossier introuvable.');
    if (!canExecuteSanction(row.status)) {
      throw StateError('La sanction ne peut être exécutée qu\'après instruction du dossier.');
    }
    final now = DateTime.now();
    await (db.update(db.disciplineCases)..where((t) => t.id.equals(id))).write(
      DisciplineCasesCompanion(
        sanctionExecuted: const Value(true),
        updatedAt: Value(now),
      ),
    );
    await _trace(actorUserId, actorUsername, 'Sanction exécutée $id');
  }

  Future<void> archiveCase({
    required String id,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'discipline.update');
    final now = DateTime.now();
    await (db.update(db.disciplineCases)..where((t) => t.id.equals(id))).write(
      DisciplineCasesCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await _trace(actorUserId, actorUsername, 'Archivage dossier discipline $id');
  }

  Future<Map<String, int>> stats({String? actorUserId}) async {
    final rows = await listCases(actorUserId: actorUserId);
    return {
      'total': rows.length,
      'ouverts': rows.where((r) => r.disciplineCase.status == 'Ouvert').length,
      'en_cours': rows.where((r) => r.disciplineCase.status == 'En cours').length,
      'graves': rows.where((r) => r.disciplineCase.severity == 'Grave' || r.disciplineCase.severity == 'Très grave').length,
      'actions_a_faire': rows.fold<int>(0, (sum, r) => sum + r.pendingActions),
    };
  }
}
