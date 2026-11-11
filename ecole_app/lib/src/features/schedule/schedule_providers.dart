import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import 'schedule_repository.dart';

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) => ScheduleRepository(ref.watch(appDatabaseProvider)));

final roomsProvider = StreamProvider<List<Room>>((ref) => ref.watch(scheduleRepositoryProvider).watchRooms());

final selectedScheduleDayProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

final sessionsForDayProvider = StreamProvider<List<CourseSession>>((ref) {
  final day = ref.watch(selectedScheduleDayProvider);
  return ref.watch(scheduleRepositoryProvider).watchSessions(day: day);
});
