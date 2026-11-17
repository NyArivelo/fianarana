import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/affectation_scope.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_service.dart';

class StudentListItem {
  final String id;
  final String matricule;
  final String lastName;
  final String firstName;
  final String? sex;
  final String? classLabel;
  final String? classId;
  final String status;
  final int balanceMga;

  StudentListItem({
    required this.id,
    required this.matricule,
    required this.lastName,
    required this.firstName,
    required this.sex,
    required this.classLabel,
    required this.classId,
    required this.status,
    this.balanceMga = 0,
  });

  String get fullName => '$lastName $firstName';
}

/// Synthèse d'un dossier élève pour la fiche maître-détail.
class StudentOverview {
  final Student student;
  final Enrollment? enrollment;
  final String? classLabel;
  final int balanceMga;
  final List<Guardian> guardians;
  final int activeLoans;
  final int overdueLoans;

  const StudentOverview({
    required this.student,
    required this.enrollment,
    required this.classLabel,
    required this.balanceMga,
    required this.guardians,
    required this.activeLoans,
    required this.overdueLoans,
  });
}

class UnauthorizedActionException implements Exception {
  final String permission;
  UnauthorizedActionException(this.permission);
  @override
  String toString() => 'Action non autorisée (permission requise: $permission)';
}

class StudentsRepository {
  final AppDatabase db;
  late final AuditService _audit = AuditService(db);
  late final PermissionService _perm = PermissionService(db);
  StudentsRepository(this.db);

  Future<void> _require(String? userId, String permission) async {
    if (userId == null || userId.isEmpty) return; // bootstrap/contexte système
    final ok = await _perm.userHasPermission(userId, permission);
    if (!ok) {
      await _audit.log(userId: userId, module: 'Sécurité', targetObject: permission, description: 'Permission refusée: $permission', result: 'Échec');
      throw UnauthorizedActionException(permission);
    }
  }

  Future<List<StudentListItem>> list({
    String? actorUserId,
    String? query,
    String? classId,
    String? status,
    int limit = 400,
  }) async {
    await _require(actorUserId, 'students.read');
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    if (scopeClasses != null) {
      if (scopeClasses.isEmpty) return const <StudentListItem>[];
      if (classId != null && classId.isNotEmpty && !scopeClasses.contains(classId)) return const <StudentListItem>[];
    }
    final s = db.students;
    final e = db.enrollments;
    final c = db.classes;

    final join = db.select(s).join([
      leftOuterJoin(e, e.studentId.equalsExp(s.id) & e.isDeleted.equals(false)),
      leftOuterJoin(c, c.id.equalsExp(e.classId)),
    ]);
    join.where(s.isDeleted.equals(false));
    if (classId != null && classId.isNotEmpty) {
      join.where(e.classId.equals(classId));
    } else if (scopeClasses != null) {
      join.where(e.classId.isIn(scopeClasses));
    }
    if (status != null && status.isNotEmpty) {
      join.where(e.status.equals(status) | s.status.equals(status));
    }
    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      join.where(s.lastName.like(q) | s.firstName.like(q) | s.matricule.like(q));
    }
    join.orderBy([OrderingTerm.asc(s.lastName), OrderingTerm.asc(s.firstName)]);
    join.limit(limit);

    final rows = await join.get();
    // dédupliquer par élève (garder la première inscription trouvée)
    final seen = <String>{};
    final items = <StudentListItem>[];
    for (final r in rows) {
      final st = r.readTable(s);
      if (!seen.add(st.id)) continue;
      final cl = r.readTableOrNull(c);
      final enr = r.readTableOrNull(e);
      items.add(StudentListItem(
        id: st.id,
        matricule: st.matricule,
        lastName: st.lastName,
        firstName: st.firstName,
        sex: st.sex,
        classLabel: cl?.label,
        classId: enr?.classId,
        status: enr?.status ?? st.status,
      ));
    }
    await _attachBalances(items);
    return items;
  }

  Future<void> _attachBalances(List<StudentListItem> items) async {
    if (items.isEmpty) return;
    final ids = items.map((e) => e.id).toList();
    final rows = await (db.select(db.payments)
          ..where((p) => p.studentId.isIn(ids) & p.isDeleted.equals(false)))
        .get();
    final balances = <String, int>{};
    for (final p in rows) {
      balances[p.studentId] = (balances[p.studentId] ?? 0) + p.amountDueMga - p.amountPaidMga;
    }
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final balance = balances[item.id];
      if (balance != null) {
        items[i] = StudentListItem(
          id: item.id,
          matricule: item.matricule,
          lastName: item.lastName,
          firstName: item.firstName,
          sex: item.sex,
          classLabel: item.classLabel,
          classId: item.classId,
          status: item.status,
          balanceMga: balance,
        );
      }
    }
  }

  /// Fiche synthétique (classe, solde, responsables, prêts bibliothèque).
  Future<StudentOverview> overview(String studentId, {String? actorUserId}) async {
    final student = await getById(studentId, actorUserId: actorUserId);
    if (student == null) throw StateError('Élève introuvable: $studentId');
    final enrollment = await (db.select(db.enrollments)
          ..where((t) => t.studentId.equals(studentId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.enrollmentDate)])
          ..limit(1))
        .getSingleOrNull();
    String? classLabel;
    final enrollmentClassId = enrollment?.classId;
    if (enrollmentClassId != null) {
      final cl = await (db.select(db.classes)..where((t) => t.id.equals(enrollmentClassId))).getSingleOrNull();
      classLabel = cl?.label;
    }
    final payments = await (db.select(db.payments)
          ..where((p) => p.studentId.equals(studentId) & p.isDeleted.equals(false)))
        .get();
    final balance = payments.fold<int>(0, (sum, p) => sum + p.amountDueMga - p.amountPaidMga);
    final guardians = await guardiansOf(studentId, actorUserId: actorUserId);
    final loans = await (db.select(db.libraryLoans)
          ..where((l) =>
              l.borrowerStudentId.equals(studentId) &
              l.isDeleted.equals(false) &
              l.returnDate.isNull()))
        .get();
    final now = DateTime.now();
    final overdue = loans.where((l) => l.dueDate != null && l.dueDate!.isBefore(now)).length;
    return StudentOverview(
      student: student,
      enrollment: enrollment,
      classLabel: classLabel,
      balanceMga: balance,
      guardians: guardians,
      activeLoans: loans.length,
      overdueLoans: overdue,
    );
  }

  Future<Student?> getById(String id, {String? actorUserId}) async {
    await _require(actorUserId, 'students.read');
    return (db.select(db.students)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<List<Enrollment>> enrollmentsOf(String studentId, {String? actorUserId}) async {
    await _require(actorUserId, 'students.read');
    return (db.select(db.enrollments)..where((t) => t.studentId.equals(studentId) & t.isDeleted.equals(false))).get();
  }

  Future<List<Guardian>> guardiansOf(String studentId, {String? actorUserId}) async {
    await _require(actorUserId, 'students.read');
    final rows = await db.select(db.guardians).join([
      innerJoin(db.studentGuardians, db.studentGuardians.guardianId.equalsExp(db.guardians.id)),
    ])
      ..where(db.studentGuardians.studentId.equals(studentId) & db.guardians.isDeleted.equals(false));
    final res = await rows.get();
    return res.map((r) => r.readTable(db.guardians)).toList();
  }

  Future<List<ClassesData>> allClasses() {
    return (db.select(db.classes)..where((t) => t.isDeleted.equals(false))..orderBy([(t) => OrderingTerm.asc(t.label)])).get();
  }

  Future<String> createStudent({
    required String matricule,
    required String lastName,
    required String firstName,
    String? sex,
    DateTime? birthDate,
    String? birthPlace,
    String? birthCertificateNumber,
    String? nationalIdNumber,
    String? classId,
    String? status,
    String? medicalNotes,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'students.create');
    final id = newUuid();
    final now = DateTime.now();
    final stStatus = (status == null || status.trim().isEmpty) ? 'Actif' : status.trim();
    await db.transaction(() async {
      await db.into(db.students).insert(StudentsCompanion.insert(
        id: Value(id),
        matricule: matricule,
        lastName: lastName,
        firstName: firstName,
        sex: Value(sex),
        birthDate: Value(birthDate),
        birthPlace: Value(birthPlace),
        birthCertificateNumber: Value(birthCertificateNumber),
        nationalIdNumber: Value(nationalIdNumber),
        medicalNotes: Value(medicalNotes),
        status: Value(stStatus),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      if (classId != null && classId.isNotEmpty) {
        await db.into(db.enrollments).insert(EnrollmentsCompanion.insert(
          id: Value(newUuid()),
          studentId: id,
          classId: Value(classId),
          status: Value(stStatus == 'Actif' ? 'Validée' : stStatus),
          enrollmentDate: Value(now),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
      }
    });
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Élèves', targetObject: id, description: 'Création élève $matricule $lastName $firstName', result: 'Succès');
    return id;
  }

  Future<void> updateEnrollmentStatus({
    required String enrollmentId,
    required String status,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'enrollments.update');
    await (db.update(db.enrollments)..where((t) => t.id.equals(enrollmentId))).write(
      EnrollmentsCompanion(status: Value(status), updatedAt: Value(DateTime.now())),
    );
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Inscriptions', targetObject: enrollmentId, description: 'Mise à jour statut inscription: $status', result: 'Succès');
  }

  Future<void> updateStudent({
    required String studentId,
    required String matricule,
    required String lastName,
    required String firstName,
    String? sex,
    DateTime? birthDate,
    String? birthPlace,
    String? birthCertificateNumber,
    String? nationalIdNumber,
    String? medicalNotes,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'students.update');
    await (db.update(db.students)..where((t) => t.id.equals(studentId))).write(StudentsCompanion(
      matricule: Value(matricule),
      lastName: Value(lastName),
      firstName: Value(firstName),
      sex: Value(sex),
      birthDate: Value(birthDate),
      birthPlace: Value(birthPlace),
      birthCertificateNumber: Value(birthCertificateNumber),
      nationalIdNumber: Value(nationalIdNumber),
      medicalNotes: Value(medicalNotes),
      updatedAt: Value(DateTime.now()),
    ));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Élèves', targetObject: studentId, description: 'Mise à jour élève $matricule $lastName $firstName', result: 'Succès');
  }

  /// Procédure de transfert/radiation (vérifications quitus à renforcer côté service métier)
  Future<void> transferStudent({
    required String studentId,
    required String enrollmentId,
    required String reason,
    bool financeClearance = false,
    bool libraryClearance = false,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'students.update');
    if (!financeClearance || !libraryClearance) {
      throw StateError('Quitus financier et bibliothèque requis avant transfert/radiation.');
    }
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.enrollments)..where((t) => t.id.equals(enrollmentId))).write(
        EnrollmentsCompanion(
          status: const Value('Transféré/Radiation'),
          exitDate: Value(now),
          exitReason: Value(reason),
          financeClearance: const Value(true),
          libraryClearance: const Value(true),
          updatedAt: Value(now),
        ),
      );
      await (db.update(db.students)..where((t) => t.id.equals(studentId))).write(
        StudentsCompanion(status: const Value('Transféré/Radiation'), updatedAt: Value(now)),
      );
    });
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Élèves', targetObject: studentId, description: 'Transfert/radiation élève ($reason) avec quitus validés', result: 'Succès');
  }
}
