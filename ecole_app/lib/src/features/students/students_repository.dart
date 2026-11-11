import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

class StudentsRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  StudentsRepository(this.db);

  Stream<List<Student>> watchStudents({String query = ''}) {
    final q = db.select(db.students)..where((t) => t.isDeleted.equals(false));
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim()}%';
      q.where((t) =>
          t.firstName.like(like) |
          t.lastName.like(like) |
          t.matricule.like(like));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.lastName), (t) => OrderingTerm.asc(t.firstName)]);
    return q.watch();
  }

  Future<Student?> getStudent(String id) =>
      (db.select(db.students)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<String> upsertStudent({
    String? id,
    required String matricule,
    required String firstName,
    required String lastName,
    String? gender,
    DateTime? birthDate,
    String? birthPlace,
    String? status,
    String? notes,
  }) async {
    final now = DateTime.now();
    if (id == null) {
      final newId = _uuid.v4();
      await db.into(db.students).insert(StudentsCompanion.insert(
            id: newId,
            matricule: matricule,
            firstName: firstName,
            lastName: lastName,
            gender: Value(gender),
            birthDate: Value(birthDate),
            birthPlace: Value(birthPlace),
            status: Value(status ?? 'active'),
            notes: Value(notes),
          ));
      return newId;
    } else {
      await (db.update(db.students)..where((t) => t.id.equals(id))).write(
        StudentsCompanion(
          matricule: Value(matricule),
          firstName: Value(firstName),
          lastName: Value(lastName),
          gender: Value(gender),
          birthDate: Value(birthDate),
          birthPlace: Value(birthPlace),
          status: Value(status ?? 'active'),
          notes: Value(notes),
          updatedAt: Value(now),
        ),
      );
      return id;
    }
  }

  Future<void> deleteStudent(String id) async {
    await (db.update(db.students)..where((t) => t.id.equals(id))).write(
      StudentsCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now()), status: const Value('archived')));
  }

  // Guardians
  Stream<List<Guardian>> watchGuardians() => (db.select(db.guardians)
        ..where((t) => t.isDeleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.lastName)]))
      .watch();

  Future<List<Guardian>> guardiansForStudent(String studentId) async {
    final q = db.select(db.guardians).join([
      innerJoin(db.studentGuardians, db.studentGuardians.guardianId.equalsExp(db.guardians.id)),
    ])..where(db.studentGuardians.studentId.equals(studentId));
    final rows = await q.get();
    return rows.map((r) => r.readTable(db.guardians)).toList();
  }

  Stream<List<Guardian>> watchGuardiansForStudent(String studentId) {
    final q = db.select(db.guardians).join([
      innerJoin(db.studentGuardians, db.studentGuardians.guardianId.equalsExp(db.guardians.id)),
    ])..where(db.studentGuardians.studentId.equals(studentId));
    return q.watch().map((rows) => rows.map((r) => r.readTable(db.guardians)).toList());
  }

  Future<String> upsertGuardian({
    String? id,
    required String firstName,
    required String lastName,
    String? phone,
    String? email,
    String? address,
    String? relation,
  }) async {
    final now = DateTime.now();
    if (id == null) {
      final newId = _uuid.v4();
      await db.into(db.guardians).insert(GuardiansCompanion.insert(
            id: newId, firstName: firstName, lastName: lastName,
            phone: Value(phone), email: Value(email), address: Value(address), relation: Value(relation)));
      return newId;
    } else {
      await (db.update(db.guardians)..where((t) => t.id.equals(id))).write(GuardiansCompanion(
        firstName: Value(firstName), lastName: Value(lastName), phone: Value(phone), email: Value(email),
        address: Value(address), relation: Value(relation), updatedAt: Value(now)));
      return id;
    }
  }

  Future<void> linkGuardian(String studentId, String guardianId, {bool primary = false}) async {
    await db.into(db.studentGuardians).insertOnConflictUpdate(StudentGuardiansCompanion.insert(
      studentId: studentId, guardianId: guardianId, isPrimary: Value(primary)));
  }

  Future<void> unlinkGuardian(String studentId, String guardianId) async {
    await (db.delete(db.studentGuardians)
          ..where((t) => t.studentId.equals(studentId) & t.guardianId.equals(guardianId)))
        .go();
  }

  // Enrollments
  Stream<List<Enrollment>> watchEnrollmentsForStudent(String studentId) {
    return (db.select(db.enrollments)
          ..where((t) => t.studentId.equals(studentId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.enrolledAt)]))
        .watch();
  }

  Future<void> upsertEnrollment({
    String? id,
    required String studentId,
    required String academicYearId,
    String? classId,
    String status = 'preinscription',
  }) async {
    final now = DateTime.now();
    if (id == null) {
      await db.into(db.enrollments).insert(EnrollmentsCompanion.insert(
            id: _uuid.v4(),
            studentId: studentId,
            academicYearId: academicYearId,
            classId: Value(classId),
            status: Value(status),
          ));
    } else {
      await (db.update(db.enrollments)..where((t) => t.id.equals(id))).write(EnrollmentsCompanion(
        academicYearId: Value(academicYearId), classId: Value(classId), status: Value(status), updatedAt: Value(now)));
    }
  }

  Future<void> setEnrollmentStatus(String id, String status) async {
    await (db.update(db.enrollments)..where((t) => t.id.equals(id))).write(
      EnrollmentsCompanion(status: Value(status), updatedAt: Value(DateTime.now())));
  }

  Future<List<Student>> allStudents() async {
    return (db.select(db.students)..where((t) => t.isDeleted.equals(false))..orderBy([(t)=>OrderingTerm.asc(t.lastName),(t)=>OrderingTerm.asc(t.firstName)])).get();
  }

  Future<Set<String>> existingMatricules() async {
    final rows = await db.select(db.students).get();
    return rows.map((s) => s.matricule.trim().toLowerCase()).toSet();
  }

  Future<int> importStudents(List<Map<String, String>> rows) async {
    int count = 0;
    for (final r in rows) {
      final matricule = (r['matricule'] ?? '').trim();
      final first = (r['firstName'] ?? r['prenom'] ?? '').trim();
      final last = (r['lastName'] ?? r['nom'] ?? '').trim();
      if (matricule.isEmpty || first.isEmpty || last.isEmpty) continue;
      DateTime? birthDate;
      final bd = (r['birthDate'] ?? r['date_naissance'] ?? '').trim();
      if (bd.isNotEmpty) {
        birthDate = DateTime.tryParse(bd);
        if (birthDate == null && bd.contains('/')) {
          final parts = bd.split('/');
          if (parts.length == 3) {
            birthDate = DateTime.tryParse('${parts[2]}-${parts[1].padLeft(2,'0')}-${parts[0].padLeft(2,'0')}');
          }
        }
      }
      await upsertStudent(
        matricule: matricule,
        firstName: first,
        lastName: last,
        gender: (r['gender'] ?? r['genre'] ?? '').trim().isEmpty ? null : (r['gender'] ?? r['genre'])!.trim(),
        birthDate: birthDate,
        birthPlace: (r['birthPlace'] ?? r['lieu_naissance'] ?? '').trim().isEmpty ? null : (r['birthPlace'] ?? r['lieu_naissance'])!.trim(),
        status: (r['status'] ?? r['statut'] ?? 'active').trim(),
        notes: (r['notes'] ?? '').trim().isEmpty ? null : r['notes']!.trim(),
      );
      count++;
    }
    return count;
  }
}
