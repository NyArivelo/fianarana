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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

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
