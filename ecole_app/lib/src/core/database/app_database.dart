import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Users,
    Roles,
    Permissions,
    RolePermissions,
    UserRoles,
    AuditLogs,
    SchoolSettings,
    AcademicYears,
    Periods,
    EducationTypes,
    Levels,
    Classes,
    Subjects,
    Students,
    Guardians,
    StudentGuardians,
    Enrollments,
    FeeTypes,
    Payments,
    CashClosures,
    PaymentPlans,
    PaymentInstallments,
    Rooms,
    CourseSessions,
    AttendanceRecords,
    Evaluations,
    Grades,
    CouncilDecisions,
    TeacherAssignments,
    StaffMembers,
    DisciplinaryIncidents,
    DisciplinaryActions,
    LibraryItems,
    LibraryCopies,
    LibraryLoans,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(paymentPlans);
            await m.createTable(paymentInstallments);
            await m.addColumn(payments, payments.installmentId);
          }
          if (from < 3) {
            await m.createTable(rooms);
            await m.createTable(courseSessions);
            await m.createTable(attendanceRecords);
          }
          if (from < 4) {
            await m.createTable(evaluations);
            await m.createTable(grades);
          }
          if (from < 5) {
            await m.createTable(councilDecisions);
          }
          if (from < 6) {
            await m.addColumn(roles, roles.scope);
          }
          if (from < 7) {
            await m.createTable(teacherAssignments);
          }
          if (from < 8) {
            await m.addColumn(users, users.pinHash);
          }
          if (from < 9) {
            await m.createTable(staffMembers);
          }
          if (from < 10) {
            await m.createTable(disciplinaryIncidents);
            await m.createTable(disciplinaryActions);
            await m.createTable(libraryItems);
            await m.createTable(libraryCopies);
            await m.createTable(libraryLoans);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(dir.path, 'ecole_app'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    final file = File(p.join(dbDir.path, 'ecole.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
