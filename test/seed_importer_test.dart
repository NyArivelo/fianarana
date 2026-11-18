import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/seed_importer.dart';
import 'package:fianarana/features/auth/data/auth_repository.dart';
import 'package:fianarana/features/calendar/data/calendar_repository.dart';
import 'package:fianarana/features/facilities/data/facilities_repository.dart';
import 'package:fianarana/features/finance/data/finance_repository.dart';
import 'package:fianarana/features/library/data/library_repository.dart';
import 'package:fianarana/features/timetable/data/timetable_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('les données de test alimentent le planning et le calendrier', () async {
    final summary = await SeedImporter(db).importAll();
    expect(summary, contains('emploi_du_temps='));

    final sessions = await (db.select(db.timetableSessions)
          ..where((t) => t.isDeleted.equals(false)))
        .get();
    expect(sessions.length, greaterThan(200),
        reason: 'emploi du temps complet attendu (11 classes)');

    final assignments = await db.select(db.teacherAssignments).get();
    expect(assignments.length, greaterThan(50));

    final events = await db.select(db.calendarEvents).get();
    expect(events, isNotEmpty);
    expect(events.where((e) => e.isEphemeris), isNotEmpty);
    expect(events.where((e) => e.classId != null), isNotEmpty);

    final entries = await TimetableRepository(db).listEntries();
    expect(entries.length, sessions.length);
    expect(entries.every((e) => e.classLabel != null), isTrue);
    expect(entries.every((e) => e.teacherName != null), isTrue);
    expect(TimetableRepository(db).detectConflicts(entries), isEmpty);

    final byClass = await TimetableRepository(db).listEntries(classId: sessions.first.classId);
    expect(byClass.every((e) => e.classId == sessions.first.classId), isTrue);

    final calendar = CalendarRepository(db);
    final ephemeris = await calendar.list(isEphemeris: true);
    expect(ephemeris, isNotEmpty);
    final classEvents = await calendar.list(classId: sessions.first.classId);
    expect(classEvents, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('frais, discipline et réservations disposent de données de test', () async {
    final summary = await SeedImporter(db).importAll();
    expect(summary, contains('frais_discipline_locaux='));

    final fees = await (db.select(db.feeStructures)..where((t) => t.isDeleted.equals(false))).get();
    expect(fees.length, greaterThanOrEqualTo(3));
    expect(fees.any((f) => f.amountMga > 0), isTrue);

    final discounts = await (db.select(db.studentDiscounts)..where((t) => t.isDeleted.equals(false))).get();
    expect(discounts, isNotEmpty);
    expect(discounts.any((d) => d.percent > 0 || d.amountMga > 0), isTrue);

    final creditNotes = await (db.select(db.creditNotes)..where((t) => t.isDeleted.equals(false))).get();
    expect(creditNotes, isNotEmpty);

    // Grand livre comptable dérivé des encaissements.
    final ledgerRepo = FinanceRepository(db);
    final ledger = await ledgerRepo.ledger();
    expect(ledger, isNotEmpty);
    for (final row in ledger) {
      expect(row.reductions, row.discount + row.scholarship + row.creditNote);
      expect(row.netDue, row.grossDue - row.reductions);
      expect(row.balance, row.netDue - row.paid);
      expect(row.receipt, isNotEmpty);
      expect(row.studentName.trim(), isNotEmpty);
      expect(row.matricule, isNotEmpty);
    }
    expect(ledger.any((r) => r.classLabel != null), isTrue);

    // Filtre par classe : classe du paiement ou de l'inscription de l'élève.
    final ledgerPayments = await (db.select(db.payments)..where((t) => t.isDeleted.equals(false))).get();
    final classOf = {for (final p in ledgerPayments) p.id: p.classId};
    final withClass = ledger.firstWhere((r) => r.classLabel != null);
    final enrollment = await (db.select(db.enrollments)
          ..where((e) => e.isDeleted.equals(false) & e.studentId.equals(withClass.studentId)))
        .getSingle();
    final filteredClass = await (db.select(db.classes)..where((c) => c.id.equals(enrollment.classId!))).getSingle();
    final byClass = await ledgerRepo.ledger(classId: filteredClass.id);
    expect(byClass, isNotEmpty);
    expect(byClass.any((r) => r.id == withClass.id), isTrue);
    final enrolledStudentIds = (await (db.select(db.enrollments)
              ..where((e) => e.isDeleted.equals(false) & e.classId.equals(filteredClass.id)))
            .get())
        .map((e) => e.studentId)
        .toSet();
    expect(byClass.every((r) => classOf[r.id] == filteredClass.id || enrolledStudentIds.contains(r.studentId)), isTrue);

    final searchToken = ledger.first.matricule;
    final searched = await ledgerRepo.ledger(query: searchToken);
    expect(searched, isNotEmpty);
    expect(searched.every((r) => r.matricule == searchToken || r.studentName.toLowerCase().contains(searchToken.toLowerCase()) ||
        r.receipt == searchToken || r.feeLabel.toLowerCase().contains(searchToken.toLowerCase())), isTrue);

    final dates = ledger.map((r) => r.date).toList()..sort();
    final inRange = await ledgerRepo.ledger(from: dates.first, to: dates.last);
    expect(inRange.length, ledger.length);
    final outsideRange = await ledgerRepo.ledger(
        from: dates.last.add(const Duration(days: 1)), to: dates.last.add(const Duration(days: 2)));
    expect(outsideRange, isEmpty);

    final cases = await (db.select(db.disciplineCases)..where((t) => t.isDeleted.equals(false))).get();
    expect(cases, isNotEmpty);
    expect(cases.any((c) => c.status != 'Clos'), isTrue);
    final actions = await (db.select(db.disciplineActions)..where((t) => t.isDeleted.equals(false))).get();
    expect(actions.where((a) => a.status == 'À faire'), isNotEmpty);
    expect(actions.where((a) => a.status == 'Exécutée'), isNotEmpty);

    final reservations = await (db.select(db.facilityReservations)..where((t) => t.isDeleted.equals(false))).get();
    expect(reservations, isNotEmpty);
    expect(reservations.every((r) => r.endDate.isAfter(r.startDate)), isTrue);
    final maintenance = await (db.select(db.facilityMaintenance)..where((t) => t.isDeleted.equals(false))).get();
    expect(maintenance, isNotEmpty);

    // Permissions granulaires des nouveaux modules et affectation aux rôles.
    final permissions = await db.select(db.permissions).get();
    expect(permissions.any((p) => p.code == 'discipline.create'), isTrue);
    expect(permissions.any((p) => p.code == 'discipline.validate'), isTrue);
    expect(permissions.any((p) => p.code == 'fees.read'), isTrue);
    expect(permissions.any((p) => p.code == 'fees.update'), isTrue);
    final surveillant = await (db.select(db.roles)..where((r) => r.name.equals('Surveillant'))).getSingleOrNull();
    expect(surveillant, isNotNull);
    final surveillantPerms = await (db.select(db.rolePermissions)
          ..where((rp) => rp.roleId.equals(surveillant!.id)))
        .get();
    final permCodes = {for (final p in permissions) p.id: p.code};
    expect(surveillantPerms.any((rp) => permCodes[rp.permissionId] == 'discipline.create'), isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('bibliothèque, quitus et locaux exploitent les données de test', () async {    await SeedImporter(db).importAll();

    final library = LibraryRepository(db);
    final catalogue = await library.listCatalogue();
    expect(catalogue, isNotEmpty);
    expect(catalogue.where((c) => c.isBorrowed), isNotEmpty);
    expect(catalogue.where((c) => !c.isBorrowed), isNotEmpty);

    final stats = await library.stats();
    expect(stats.totalItems, catalogue.length);
    expect(stats.overdue, greaterThanOrEqualTo(1),
        reason: 'un prêt du jeu de test est échu');

    final loans = await library.listLoans();
    expect(loans, isNotEmpty);
    expect(loans.every((l) => l.itemTitle.isNotEmpty), isTrue);

    final quitus = await library.quitusRows();
    expect(quitus, isNotEmpty);
    expect(quitus.every((q) => q.activeLoans > 0), isTrue);
    expect(quitus.any((q) => !q.libraryOk), isTrue,
        reason: 'un quitus bibliothèque doit être bloqué par le retard');

    final facilities = await FacilitiesRepository(db).list();
    expect(facilities, isNotEmpty);
    expect(facilities.every((f) => (f.facility.capacity ?? 0) > 0), isTrue,
        reason: 'la capacité doit être extraite de « 35 places »');
    final facilityStats = FacilitiesRepository(db).stats(facilities);
    expect(facilityStats.totalCapacity, greaterThan(0));
    expect(facilityStats.weeklySessions, greaterThan(0));

    // Retour d'un prêt : l'exemplaire redevient disponible et le quitus est levé.
    final overdueLoan = loans.firstWhere((l) => l.overdue);
    await library.returnLoan(
      loanId: overdueLoan.loan.id,
      itemId: overdueLoan.loan.itemId,
    );
    final after = await library.listCatalogue();
    final returnedItem =
        after.firstWhere((c) => c.item.id == overdueLoan.loan.itemId);
    expect(returnedItem.isBorrowed, isFalse);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('l’import conserve le mot de passe de l’administrateur initial', () async {
    final auth = AuthRepository(db);
    await auth.createInitialAdmin(
      username: 'admin.sys',
      fullName: 'Administrateur personnalisé',
      password: 'MotDePasseInitial8!',
    );

    await SeedImporter(db).importAll();

    expect(await auth.authenticate('admin.sys', 'MotDePasseInitial8!'), isNotNull);
    expect(await auth.authenticate('admin.sys', 'Password123!'), isNull);
  });
}
