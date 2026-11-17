import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/seed_importer.dart';
import 'package:fianarana/features/calendar/data/calendar_repository.dart';
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
}
