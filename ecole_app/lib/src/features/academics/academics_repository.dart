import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

class AcademicsRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  AcademicsRepository(this.db);

  // Education types
  Stream<List<EducationType>> watchEducationTypes() => (db.select(db.educationTypes)
        ..where((t) => t.isDeleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();

  Future<void> upsertEducationType({String? id, required String name, String? description}) async {
    final now = DateTime.now();
    if (id == null) {
      await db.into(db.educationTypes).insert(EducationTypesCompanion.insert(
            id: _uuid.v4(), name: name, description: Value(description)));
    } else {
      await (db.update(db.educationTypes)..where((t) => t.id.equals(id))).write(
        EducationTypesCompanion(name: Value(name), description: Value(description), updatedAt: Value(now)));
    }
  }

  Future<void> deleteEducationType(String id) async {
    await (db.update(db.educationTypes)..where((t) => t.id.equals(id))).write(
      EducationTypesCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())));
  }

  // Levels
  Stream<List<Level>> watchLevels() => (db.select(db.levels)
        ..where((t) => t.isDeleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.orderIndex), (t) => OrderingTerm.asc(t.name)]))
      .watch();

  Future<void> upsertLevel({String? id, String? educationTypeId, required String name, int orderIndex = 0}) async {
    final now = DateTime.now();
    if (id == null) {
      await db.into(db.levels).insert(LevelsCompanion.insert(
            id: _uuid.v4(), name: name, educationTypeId: Value(educationTypeId), orderIndex: Value(orderIndex)));
    } else {
      await (db.update(db.levels)..where((t) => t.id.equals(id))).write(LevelsCompanion(
          name: Value(name), educationTypeId: Value(educationTypeId), orderIndex: Value(orderIndex), updatedAt: Value(now)));
    }
  }

  Future<void> deleteLevel(String id) async {
    await (db.update(db.levels)..where((t) => t.id.equals(id))).write(
      LevelsCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())));
  }

  // Subjects
  Stream<List<Subject>> watchSubjects() => (db.select(db.subjects)
        ..where((t) => t.isDeleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();

  Future<void> upsertSubject({String? id, required String name, String? code, double coefficient = 1.0}) async {
    final now = DateTime.now();
    if (id == null) {
      await db.into(db.subjects).insert(SubjectsCompanion.insert(
            id: _uuid.v4(), name: name, code: Value(code), defaultCoefficient: Value(coefficient)));
    } else {
      await (db.update(db.subjects)..where((t) => t.id.equals(id))).write(SubjectsCompanion(
          name: Value(name), code: Value(code), defaultCoefficient: Value(coefficient), updatedAt: Value(now)));
    }
  }

  Future<void> deleteSubject(String id) async {
    await (db.update(db.subjects)..where((t) => t.id.equals(id))).write(
      SubjectsCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())));
  }

  // Classes
  Stream<List<ClassesData>> watchClasses({String? academicYearId}) {
    final q = db.select(db.classes)..where((t) => t.isDeleted.equals(false));
    if (academicYearId != null) q.where((t) => t.academicYearId.equals(academicYearId));
    q.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.watch();
  }

  Future<void> upsertClass({String? id, required String academicYearId, String? levelId, required String name, int? capacity}) async {
    final now = DateTime.now();
    if (id == null) {
      await db.into(db.classes).insert(ClassesCompanion.insert(
            id: _uuid.v4(), academicYearId: academicYearId, levelId: Value(levelId), name: name, capacity: Value(capacity)));
    } else {
      await (db.update(db.classes)..where((t) => t.id.equals(id))).write(ClassesCompanion(
          academicYearId: Value(academicYearId), levelId: Value(levelId), name: Value(name), capacity: Value(capacity), updatedAt: Value(now)));
    }
  }

  Future<void> deleteClass(String id) async {
    await (db.update(db.classes)..where((t) => t.id.equals(id))).write(
      ClassesCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())));
  }
}
