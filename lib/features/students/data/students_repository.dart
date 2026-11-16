import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
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

  StudentListItem({
    required this.id,
    required this.matricule,
    required this.lastName,
    required this.firstName,
    required this.sex,
    required this.classLabel,
    required this.classId,
    required this.status,
  });

  String get fullName => '$lastName $firstName';
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

  Future<List<StudentListItem>> list({String? actorUserId, String? query, String? classId, int limit = 200}) async {
    await _require(actorUserId, 'students.read');
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
    return items;
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

  Future<List<Class>> allClasses() {
    return (db.select(db.classes)..where((t) => t.isDeleted.equals(false))..orderBy([(t) => OrderingTerm.asc(t.label)])).get();
  }

  Future<String> createStudent({
    required String matricule,
    required String lastName,
    required String firstName,
    String? sex,
    DateTime? birthDate,
    String? birthPlace,
    String? classId,
    String? medicalNotes,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'students.create');
    final id = newUuid();
    final now = DateTime.now();
    await db.transaction(() async {
      await db.into(db.students).insert(StudentsCompanion.insert(
        id: id,
        matricule: matricule,
        lastName: lastName,
        firstName: firstName,
        sex: Value(sex),
        birthDate: Value(birthDate),
        birthPlace: Value(birthPlace),
        medicalNotes: Value(medicalNotes),
        status: const Value('Actif'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      if (classId != null && classId.isNotEmpty) {
        await db.into(db.enrollments).insert(EnrollmentsCompanion.insert(
          id: newUuid(),
          studentId: id,
          classId: Value(classId),
          status: const Value('Validée'),
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
