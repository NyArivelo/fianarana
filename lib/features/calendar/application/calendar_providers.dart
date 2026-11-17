import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/calendar/data/calendar_repository.dart';

final calendarRepositoryProvider = Provider<CalendarRepository>((ref) => CalendarRepository(ref.watch(appDatabaseProvider)));

final calendarClassesProvider = FutureProvider<List<ClassesData>>((ref) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(calendarRepositoryProvider).allClasses(actorUserId: userId);
});

final calendarPeriodsProvider = FutureProvider<List<Period>>((ref) async {
  final repo = ref.watch(calendarRepositoryProvider);
  final year = await repo.activeSchoolYear();
  return repo.listPeriods(schoolYearId: year?.id);
});

final activeSchoolYearProvider = FutureProvider<SchoolYear?>((ref) {
  return ref.watch(calendarRepositoryProvider).activeSchoolYear();
});

/// Événements filtrés par classe, par fenêtre de dates et par type.
final calendarEventsProvider = FutureProvider.family<List<CalendarEntry>, ({
  String? classId,
  bool includeGlobal,
  bool? isEphemeris,
  DateTime? from,
  DateTime? to,
})>((ref, args) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(calendarRepositoryProvider).list(
        actorUserId: userId,
        classId: args.classId,
        includeGlobal: args.includeGlobal,
        isEphemeris: args.isEphemeris,
        from: args.from,
        to: args.to,
      );
});
