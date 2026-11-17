import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:fianarana/core/database/tables.dart';
import 'package:fianarana/core/database/uuid.dart';

part 'app_database.g.dart';

File sandboxMarkerFile(Directory dbFolder) => File(p.join(dbFolder.path, 'use_sandbox.flag'));

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final dbFolder = Directory(p.join(dir.path, 'fianarana'));
    if (!dbFolder.existsSync()) {
      dbFolder.createSync(recursive: true);
    }
    final useSandbox = sandboxMarkerFile(dbFolder).existsSync();
    final dbName = useSandbox ? 'fianarana_sandbox.sqlite' : 'fianarana.sqlite';
    final file = File(p.join(dbFolder.path, dbName));
    return NativeDatabase.createInBackground(file);
  });
}

@DriftDatabase(
  tables: [
    Establishments,
    SchoolYears,
    Periods,
    Roles,
    Permissions,
    RolePermissions,
    Users,
    UserRoles,
    Levels,
    Classes,
    Subjects,
    Guardians,
    Students,
    StudentGuardians,
    Enrollments,
    StaffMembers,
    TeacherAssignments,
    Evaluations,
    ClassCouncils,
    CouncilDecisions,
    AttendanceEvents,
    Payments,
    PaymentSchedules,
    CashClosures,
    LibraryItems,
    LibraryLoans,
    Facilities,
    TimetableSessions,
    CalendarEvents,
    AuditLogs,
    AppSettings,
    BackupRecords,
    DocumentTemplates,
    TeacherAbsences,
    YearClosures,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // For tests / custom executor
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(classCouncils);
            await m.createTable(councilDecisions);
          }
          if (from < 3) {
            await m.createTable(paymentSchedules);
          }
          if (from < 4) {
            await m.createTable(timetableSessions);
            await m.createTable(backupRecords);
          }
          if (from < 5) {
            await m.createTable(calendarEvents);
          }
          if (from < 6) {
            // Nouvelles tables
            await m.createTable(documentTemplates);
            await m.createTable(teacherAbsences);
            await m.createTable(yearClosures);
            // Nouvelles colonnes (évaluations compétences, état civil élève)
            await m.addColumn(evaluations, evaluations.masteryLevel);
            await m.addColumn(evaluations, evaluations.competencyCode);
            await m.addColumn(students, students.birthCertificateNumber);
            await m.addColumn(students, students.nationalIdNumber);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Helper to ensure UUID is set on insert companions externally when needed.
  static String ensureId(String? id) => (id == null || id.isEmpty) ? newUuid() : id;
}
