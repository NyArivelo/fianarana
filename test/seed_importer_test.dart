import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/seed_importer.dart';
import 'package:fianarana/features/calendar/data/calendar_repository.dart';
import 'package:fianarana/features/facilities/data/facilities_repository.dart';
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

    final sessions = await db.select(db.timetableSessions).get();
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

  test('bibliothèque, quitus et locaux exploitent les données de test', () async {
    await SeedImporter(db).importAll();

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
}
