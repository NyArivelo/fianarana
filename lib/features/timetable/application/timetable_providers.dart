import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/timetable/data/timetable_repository.dart';

final timetableRepositoryProvider = Provider<TimetableRepository>((ref) => TimetableRepository(ref.watch(appDatabaseProvider)));

/// Séances détaillées filtrées (classe / enseignante / jour).
final timetableEntriesProvider = FutureProvider.family<List<TimetableEntry>, ({String? classId, String? teacherId, String? day})>((ref, args) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(timetableRepositoryProvider).listEntries(
        actorUserId: userId,
        classId: args.classId,
        teacherId: args.teacherId,
        day: args.day,
      );
});

final timetableClassesProvider = FutureProvider<List<ClassesData>>((ref) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(timetableRepositoryProvider).allClasses(actorUserId: userId);
});

final timetableTeachersProvider = FutureProvider<List<StaffMember>>((ref) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(timetableRepositoryProvider).allTeachers(actorUserId: userId);
});

final timetableSubjectsProvider = FutureProvider<List<Subject>>((ref) {
  return ref.watch(timetableRepositoryProvider).allSubjects();
});

/// Conservé pour compatibilité avec les écrans existants.
final timetableSessionsProvider = FutureProvider((ref) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(timetableRepositoryProvider).list(actorUserId: userId);
});
