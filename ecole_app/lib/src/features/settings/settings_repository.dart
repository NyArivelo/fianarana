import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

class SettingsRepository {
  final AppDatabase db;
  final _uuid = const Uuid();

  SettingsRepository(this.db);

  // --- School settings ---
  Future<SchoolSetting?> getSchoolSetting() {
    return (db.select(db.schoolSettings)..limit(1)).getSingleOrNull();
  }

  Stream<SchoolSetting?> watchSchoolSetting() {
    return (db.select(db.schoolSettings)..limit(1)).watchSingleOrNull();
  }

  Future<void> saveSchoolSetting({
    String? id,
    required String name,
    String? address,
    String? phone,
    String? email,
    String? logoPath,
    String? motto,
    String? timezone,
    String? dateFormat,
    String? timeFormat,
    String? legalMentions,
  }) async {
    final existing = await getSchoolSetting();
    final now = DateTime.now();
    if (existing == null && id == null) {
      await db.into(db.schoolSettings).insert(SchoolSettingsCompanion.insert(
            id: _uuid.v4(),
            name: name,
            address: Value(address),
            phone: Value(phone),
            email: Value(email),
            logoPath: Value(logoPath),
            motto: Value(motto),
            timezone: Value(timezone ?? 'UTC'),
            dateFormat: Value(dateFormat ?? 'dd/MM/yyyy'),
            timeFormat: Value(timeFormat ?? 'HH:mm'),
            legalMentions: Value(legalMentions),
            isConfigured: const Value(true),
          ));
    } else {
      final targetId = id ?? existing!.id;
      await (db.update(db.schoolSettings)
            ..where((t) => t.id.equals(targetId)))
          .write(SchoolSettingsCompanion(
        name: Value(name),
        address: Value(address),
        phone: Value(phone),
        email: Value(email),
        logoPath: Value(logoPath),
        motto: Value(motto),
        timezone: Value(timezone ?? 'UTC'),
        dateFormat: Value(dateFormat ?? 'dd/MM/yyyy'),
        timeFormat: Value(timeFormat ?? 'HH:mm'),
        legalMentions: Value(legalMentions),
        isConfigured: const Value(true),
        updatedAt: Value(now),
      ));
    }
  }

  // --- Academic years ---
  Stream<List<AcademicYear>> watchAcademicYears() {
    return (db.select(db.academicYears)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.startDate)]))
        .watch();
  }

  Future<void> upsertAcademicYear({
    String? id,
    required String label,
    required DateTime startDate,
    required DateTime endDate,
    bool isCurrent = false,
  }) async {
    await db.transaction(() async {
      if (isCurrent) {
        await (db.update(db.academicYears))
            .write(const AcademicYearsCompanion(isCurrent: Value(false)));
      }
      final now = DateTime.now();
      if (id == null) {
        await db.into(db.academicYears).insert(AcademicYearsCompanion.insert(
              id: _uuid.v4(),
              label: label,
              startDate: startDate,
              endDate: endDate,
              isCurrent: Value(isCurrent),
            ));
      } else {
        await (db.update(db.academicYears)..where((t) => t.id.equals(id)))
            .write(AcademicYearsCompanion(
          label: Value(label),
          startDate: Value(startDate),
          endDate: Value(endDate),
          isCurrent: Value(isCurrent),
          updatedAt: Value(now),
        ));
      }
    });
  }

  Future<void> setCurrentYear(String id) async {
    await db.transaction(() async {
      await (db.update(db.academicYears))
          .write(const AcademicYearsCompanion(isCurrent: Value(false)));
      await (db.update(db.academicYears)..where((t) => t.id.equals(id))).write(
        AcademicYearsCompanion(
            isCurrent: const Value(true), updatedAt: Value(DateTime.now())),
      );
    });
  }

  // --- Periods ---
  Stream<List<Period>> watchPeriods(String academicYearId) {
    return (db.select(db.periods)
          ..where((t) =>
              t.academicYearId.equals(academicYearId) &
              t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
        .watch();
  }

  Future<void> upsertPeriod({
    String? id,
    required String academicYearId,
    required String name,
    required int orderIndex,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final now = DateTime.now();
    if (id == null) {
      await db.into(db.periods).insert(PeriodsCompanion.insert(
            id: _uuid.v4(),
            academicYearId: academicYearId,
            name: name,
            orderIndex: Value(orderIndex),
            startDate: Value(startDate),
            endDate: Value(endDate),
          ));
    } else {
      await (db.update(db.periods)..where((t) => t.id.equals(id))).write(
        PeriodsCompanion(
          name: Value(name),
          orderIndex: Value(orderIndex),
          startDate: Value(startDate),
          endDate: Value(endDate),
          updatedAt: Value(now),
        ),
      );
    }
  }

  Future<void> setPeriodClosed(String id, bool closed) async {
    await (db.update(db.periods)..where((t) => t.id.equals(id))).write(
      PeriodsCompanion(
        isClosed: Value(closed),
        closedAt: Value(closed ? DateTime.now() : null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deletePeriod(String id) async {
    await (db.update(db.periods)..where((t) => t.id.equals(id))).write(
      PeriodsCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())),
    );
  }
}
