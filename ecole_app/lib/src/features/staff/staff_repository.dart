import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

class StaffRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  StaffRepository(this.db);

  Stream<List<StaffMember>> watchStaff({String query = '', String? type}) {
    final q = db.select(db.staffMembers)..where((t) => t.isDeleted.equals(false));
    if (type != null && type.isNotEmpty) q.where((t) => t.staffType.equals(type));
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim()}%';
      q.where((t) => t.firstName.like(like) | t.lastName.like(like) | t.specialty.like(like) | t.email.like(like));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.lastName), (t) => OrderingTerm.asc(t.firstName)]);
    return q.watch();
  }

  Future<String> upsertStaff({
    String? id,
    required String firstName,
    required String lastName,
    String staffType = 'teacher',
    String? specialty,
    String? phone,
    String? email,
    String? contractType,
    DateTime? contractStart,
    DateTime? contractEnd,
    String? userId,
    String? notes,
    String? documentsNote,
  }) async {
    final now = DateTime.now();
    if (id == null) {
      final nid = _uuid.v4();
      await db.into(db.staffMembers).insert(StaffMembersCompanion.insert(
        id: nid,
        firstName: firstName,
        lastName: lastName,
        staffType: Value(staffType),
        specialty: Value(specialty),
        phone: Value(phone),
        email: Value(email),
        contractType: Value(contractType),
        contractStart: Value(contractStart),
        contractEnd: Value(contractEnd),
        userId: Value(userId),
        notes: Value(notes),
        documentsNote: Value(documentsNote),
      ));
      return nid;
    } else {
      await (db.update(db.staffMembers)..where((t) => t.id.equals(id))).write(StaffMembersCompanion(
        firstName: Value(firstName),
        lastName: Value(lastName),
        staffType: Value(staffType),
        specialty: Value(specialty),
        phone: Value(phone),
        email: Value(email),
        contractType: Value(contractType),
        contractStart: Value(contractStart),
        contractEnd: Value(contractEnd),
        userId: Value(userId),
        notes: Value(notes),
        documentsNote: Value(documentsNote),
        updatedAt: Value(now),
      ));
      return id;
    }
  }

  Future<void> deleteStaff(String id) async {
    await (db.update(db.staffMembers)..where((t) => t.id.equals(id))).write(
      StaffMembersCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())),
    );
  }

  Stream<List<TeacherAssignment>> watchAssignmentsForUser(String userId) {
    return (db.select(db.teacherAssignments)..where((t) => t.userId.equals(userId) & t.isDeleted.equals(false))).watch();
  }

  Future<void> addAssignment({required String userId, required String classId, String? subjectId, String? academicYearId}) async {
    await db.into(db.teacherAssignments).insert(TeacherAssignmentsCompanion.insert(
      id: _uuid.v4(), userId: userId, classId: classId, subjectId: Value(subjectId), academicYearId: Value(academicYearId),
    ));
  }

  Future<void> removeAssignment(String id) async {
    await (db.update(db.teacherAssignments)..where((t) => t.id.equals(id))).write(
      TeacherAssignmentsCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())),
    );
  }
}
