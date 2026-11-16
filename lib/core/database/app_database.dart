import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:fianarana/core/database/tables.dart';
import 'package:fianarana/core/database/uuid.dart';

part 'app_database.g.dart';

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final dbFolder = Directory(p.join(dir.path, 'fianarana'));
    if (!dbFolder.existsSync()) {
      dbFolder.createSync(recursive: true);
    }
    final file = File(p.join(dbFolder.path, 'fianarana.sqlite'));
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
    AuditLogs,
    AppSettings,
    BackupRecords,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // For tests / custom executor
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 4;

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
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Helper to ensure UUID is set on insert companions externally when needed.
  static String ensureId(String? id) => (id == null || id.isEmpty) ? newUuid() : id;
}
