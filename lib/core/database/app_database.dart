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
    FeeStructures,
    StudentDiscounts,
    CreditNotes,
    DisciplineCases,
    DisciplineActions,
    Payments,
    PaymentSchedules,
    CashClosures,
    LibraryItems,
    LibraryLoans,
    Facilities,
    FacilityReservations,
    FacilityMaintenance,
    TimetableSessions,
    CalendarEvents,
    AuditLogs,
    AppSettings,
    BackupRecords,
    DocumentTemplates,
    TeacherAbsences,
    YearClosures,
    BulletinSnapshots,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // For tests / custom executor
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 8;

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
          if (from < 7) {
            await m.createTable(bulletinSnapshots);
          }
          if (from < 8) {
            // Catalogue de frais, remises/bourses, notes de crédit
            await m.createTable(feeStructures);
            await m.createTable(studentDiscounts);
            await m.createTable(creditNotes);
            await m.addColumn(payments, payments.feeStructureId);
            await m.addColumn(payments, payments.discountMga);
            await m.addColumn(payments, payments.scholarshipMga);
            await m.addColumn(payments, payments.creditNoteMga);
            await m.addColumn(payments, payments.netDueMga);
            await m.addColumn(payments, payments.discountReason);
            // Discipline
            await m.createTable(disciplineCases);
            await m.createTable(disciplineActions);
            // Locaux : réservations et maintenance
            await m.createTable(facilityReservations);
            await m.createTable(facilityMaintenance);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Helper to ensure UUID is set on insert companions externally when needed.
  static String ensureId(String? id) => (id == null || id.isEmpty) ? newUuid() : id;
}
