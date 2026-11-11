import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

class StudentsRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  StudentsRepository(this.db);

  Stream<List<Student>> watchStudents({
    String query = '',
    List<String>? allowedClassIds,
    String? academicYearId,
    String? status,
    String? classId,
    String? gender,
  }) {
    if (allowedClassIds != null || (classId != null && classId.isNotEmpty)) {
      if (allowedClassIds != null && allowedClassIds.isEmpty) return Stream.value(<Student>[]);
      final jq = db.select(db.students).join([innerJoin(db.enrollments, db.enrollments.studentId.equalsExp(db.students.id))]);
      var where = db.students.isDeleted.equals(false) & db.enrollments.isDeleted.equals(false);
      if (academicYearId != null) where = where & db.enrollments.academicYearId.equals(academicYearId);
      if (allowedClassIds != null) where = where & db.enrollments.classId.isIn(allowedClassIds);
      if (classId != null && classId.isNotEmpty) where = where & db.enrollments.classId.equals(classId);
      if (status != null && status.isNotEmpty) where = where & db.students.status.equals(status);
      if (gender != null && gender.isNotEmpty) where = where & db.students.gender.equals(gender);
      if (query.trim().isNotEmpty) {
        final like = '%${query.trim()}%';
        where = where & (db.students.firstName.like(like) | db.students.lastName.like(like) | db.students.matricule.like(like));
      }
      jq.where(where);
      jq.orderBy([OrderingTerm.asc(db.students.lastName), OrderingTerm.asc(db.students.firstName)]);
      return jq.watch().map((rows) {
        final map = <String, Student>{};
        for (final r in rows) { final s = r.readTable(db.students); map[s.id] = s; }
        return map.values.toList();
      });
    }
    final q = db.select(db.students)..where((t) => t.isDeleted.equals(false));
    if (status != null && status.isNotEmpty) q.where((t) => t.status.equals(status));
    if (gender != null && gender.isNotEmpty) q.where((t) => t.gender.equals(gender));
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

  Future<void> updateEnrollmentQuitus({required String enrollmentId, String? quitusFinancial, String? quitusLibrary}) async {
    await (db.update(db.enrollments)..where((t) => t.id.equals(enrollmentId))).write(EnrollmentsCompanion(
      quitusFinancial: quitusFinancial != null ? Value(quitusFinancial) : const Value.absent(),
      quitusLibrary: quitusLibrary != null ? Value(quitusLibrary) : const Value.absent(),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> transferEnrollment({
    required String enrollmentId,
    required String studentId,
    String? reason,
    DateTime? transferDate,
    bool markStudentTransferred = true,
  }) async {
    final now = DateTime.now();
    await (db.update(db.enrollments)..where((t) => t.id.equals(enrollmentId))).write(EnrollmentsCompanion(
      status: const Value('transfere'),
      transferDate: Value(transferDate ?? now),
      transferReason: Value(reason),
      updatedAt: Value(now),
    ));
    if (markStudentTransferred) {
      await (db.update(db.students)..where((t) => t.id.equals(studentId))).write(StudentsCompanion(
        status: const Value('transfere'),
        updatedAt: Value(now),
      ));
    }
  }

  Future<List<Student>> allStudents({List<String>? allowedClassIds, String? academicYearId}) async {
    if (allowedClassIds != null) {
      if (allowedClassIds.isEmpty) return [];
      final jq = db.select(db.students).join([innerJoin(db.enrollments, db.enrollments.studentId.equalsExp(db.students.id))]);
      var where = db.students.isDeleted.equals(false) & db.enrollments.isDeleted.equals(false) & db.enrollments.classId.isIn(allowedClassIds);
      if (academicYearId != null) where = where & db.enrollments.academicYearId.equals(academicYearId);
      jq.where(where);
      jq.orderBy([OrderingTerm.asc(db.students.lastName), OrderingTerm.asc(db.students.firstName)]);
      final rows = await jq.get();
      final map = <String, Student>{};
      for (final r in rows) { final s = r.readTable(db.students); map[s.id] = s; }
      return map.values.toList();
    }
    return (db.select(db.students)..where((t) => t.isDeleted.equals(false))..orderBy([(t)=>OrderingTerm.asc(t.lastName),(t)=>OrderingTerm.asc(t.firstName)])).get();
  }

  Future<Student?> findByMatricule(String matricule) async {
    final m = matricule.trim().toLowerCase();
    final rows = await (db.select(db.students)..where((t) => t.isDeleted.equals(false))).get();
    for (final s in rows) {
      if (s.matricule.trim().toLowerCase() == m) return s;
    }
    return null;
  }

  Future<Set<String>> existingMatricules() async {
    final rows = await db.select(db.students).get();
    return rows.map((s) => s.matricule.trim().toLowerCase()).toSet();
  }

  Future<Map<String, dynamic>> importStudentsAdvanced(List<Map<String, String>> rows, {bool updateExisting = false, String? defaultAcademicYearId}) async {
    int created = 0, updated = 0, guardiansLinked = 0, enrollments = 0, skipped = 0;
    for (final r in rows) {
      final matricule = (r['matricule'] ?? '').trim();
      final first = (r['firstName'] ?? r['prenom'] ?? '').trim();
      final last = (r['lastName'] ?? r['nom'] ?? '').trim();
      if (matricule.isEmpty || first.isEmpty || last.isEmpty) { skipped++; continue; }
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
      final existing = await findByMatricule(matricule);
      String studentId;
      if (existing != null) {
        if (!updateExisting) { skipped++; continue; }
        studentId = await upsertStudent(
          id: existing.id,
          matricule: matricule,
          firstName: first,
          lastName: last,
          gender: (r['gender'] ?? r['genre'] ?? '').trim().isEmpty ? existing.gender : (r['gender'] ?? r['genre'])!.trim(),
          birthDate: birthDate ?? existing.birthDate,
          birthPlace: (r['birthPlace'] ?? r['lieu_naissance'] ?? '').trim().isEmpty ? existing.birthPlace : (r['birthPlace'] ?? r['lieu_naissance'])!.trim(),
          status: (r['status'] ?? r['statut'] ?? existing.status).trim(),
          notes: (r['notes'] ?? '').trim().isEmpty ? existing.notes : r['notes']!.trim(),
        );
        updated++;
      } else {
        studentId = await upsertStudent(
          matricule: matricule,
          firstName: first,
          lastName: last,
          gender: (r['gender'] ?? r['genre'] ?? '').trim().isEmpty ? null : (r['gender'] ?? r['genre'])!.trim(),
          birthDate: birthDate,
          birthPlace: (r['birthPlace'] ?? r['lieu_naissance'] ?? '').trim().isEmpty ? null : (r['birthPlace'] ?? r['lieu_naissance'])!.trim(),
          status: (r['status'] ?? r['statut'] ?? 'active').trim(),
          notes: (r['notes'] ?? '').trim().isEmpty ? null : r['notes']!.trim(),
        );
        created++;
      }

      // Guardian (optional)
      final gFirst = (r['guardianFirstName'] ?? r['responsable_prenom'] ?? r['guardian_first_name'] ?? '').trim();
      final gLast = (r['guardianLastName'] ?? r['responsable_nom'] ?? r['guardian_last_name'] ?? '').trim();
      if (gFirst.isNotEmpty && gLast.isNotEmpty) {
        final gPhone = (r['guardianPhone'] ?? r['responsable_telephone'] ?? r['guardian_phone'] ?? '').trim();
        final gRelation = (r['guardianRelation'] ?? r['responsable_lien'] ?? r['guardian_relation'] ?? '').trim();
        final gEmail = (r['guardianEmail'] ?? r['responsable_email'] ?? r['guardian_email'] ?? '').trim();
        final gid = await upsertGuardian(firstName: gFirst, lastName: gLast, phone: gPhone.isEmpty ? null : gPhone, relation: gRelation.isEmpty ? null : gRelation, email: gEmail.isEmpty ? null : gEmail);
        await linkGuardian(studentId, gid, primary: true);
        guardiansLinked++;
      }

      // Enrollment (optional)
      final className = (r['className'] ?? r['classe'] ?? '').trim();
      final yearLabel = (r['academicYear'] ?? r['annee'] ?? '').trim();
      if (className.isNotEmpty || yearLabel.isNotEmpty) {
        String? yearId = defaultAcademicYearId;
        if (yearLabel.isNotEmpty) {
          final ys = await (db.select(db.academicYears)..where((t) => t.isDeleted.equals(false))).get();
          for (final y in ys) { if (y.label.toLowerCase() == yearLabel.toLowerCase()) { yearId = y.id; break; } }
        }
        if (yearId != null) {
          String? classId;
          if (className.isNotEmpty) {
            final cs = await (db.select(db.classes)..where((t) => t.isDeleted.equals(false) & t.academicYearId.equals(yearId!))).get();
            for (final c in cs) { if (c.name.toLowerCase() == className.toLowerCase()) { classId = c.id; break; } }
          }
          await upsertEnrollment(studentId: studentId, academicYearId: yearId, classId: classId, status: (r['enrollmentStatus'] ?? r['statut_inscription'] ?? 'preinscription').trim());
          enrollments++;
        }
      }
    }
    return {'created': created, 'updated': updated, 'guardiansLinked': guardiansLinked, 'enrollments': enrollments, 'skipped': skipped};
  }

  Future<int> importStudents(List<Map<String, String>> rows) async {
    final res = await importStudentsAdvanced(rows);
    return (res['created'] as int) + (res['updated'] as int);
  }

  /// Returns export rows including enrollment (year/class) and primary guardian when available.
  Future<List<Map<String, String>>> exportRows({List<String>? allowedClassIds, String? academicYearId}) async {
    final students = await allStudents(allowedClassIds: allowedClassIds, academicYearId: academicYearId);
    final years = {for (final y in await (db.select(db.academicYears)..where((t)=>t.isDeleted.equals(false))).get()) y.id: y.label};
    final classes = {for (final c in await (db.select(db.classes)..where((t)=>t.isDeleted.equals(false))).get()) c.id: c.name};
    final out = <Map<String, String>>[];
    String fmt(DateTime d) => '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    for (final s in students) {
      final enrolls = await (db.select(db.enrollments)..where((t)=>t.studentId.equals(s.id) & t.isDeleted.equals(false))..orderBy([(t)=>OrderingTerm.desc(t.enrolledAt)])).get();
      final e = academicYearId != null ? enrolls.where((x)=>x.academicYearId==academicYearId).firstOrNull ?? (enrolls.isNotEmpty?enrolls.first:null) : (enrolls.isNotEmpty?enrolls.first:null);
      final guardians = await guardiansForStudent(s.id);
      final g = guardians.isNotEmpty ? guardians.first : null;
      out.add({
        'matricule': s.matricule,
        'lastName': s.lastName,
        'firstName': s.firstName,
        'gender': s.gender ?? '',
        'birthDate': s.birthDate != null ? fmt(s.birthDate!) : '',
        'birthPlace': s.birthPlace ?? '',
        'status': s.status,
        'notes': s.notes ?? '',
        'academicYear': e != null ? (years[e.academicYearId] ?? '') : '',
        'className': e?.classId != null ? (classes[e!.classId!] ?? '') : '',
        'enrollmentStatus': e?.status ?? '',
        'guardianLastName': g?.lastName ?? '',
        'guardianFirstName': g?.firstName ?? '',
        'guardianPhone': g?.phone ?? '',
        'guardianRelation': g?.relation ?? '',
        'guardianEmail': g?.email ?? '',
      });
    }
    return out;
  }
}
