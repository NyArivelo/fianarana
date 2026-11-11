import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../core/security/current_user_scope.dart';
import 'schedule_repository.dart';

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) => ScheduleRepository(ref.watch(appDatabaseProvider)));

final roomsProvider = StreamProvider<List<Room>>((ref) => ref.watch(scheduleRepositoryProvider).watchRooms());

final selectedScheduleDayProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

final scheduleViewModeProvider = StateProvider<String>((ref) => 'day'); // day | week

List<String>? _allowed(Ref ref) {
  final scope = ref.watch(currentUserScopeProvider).valueOrNull;
  if (scope != null && scope.scope == 'restricted') return scope.allowedClassIds ?? [];
  return null;
}

final sessionsForDayProvider = StreamProvider<List<CourseSession>>((ref) {
  final day = ref.watch(selectedScheduleDayProvider);
  return ref.watch(scheduleRepositoryProvider).watchSessions(day: day, allowedClassIds: _allowed(ref));
});

final sessionsForWeekProvider = StreamProvider<List<CourseSession>>((ref) {
  final day = ref.watch(selectedScheduleDayProvider);
  final start = day.subtract(Duration(days: day.weekday - 1)); // Monday
  final end = start.add(const Duration(days: 7));
  return ref.watch(scheduleRepositoryProvider).watchSessionsInRange(start, end, allowedClassIds: _allowed(ref));
});
