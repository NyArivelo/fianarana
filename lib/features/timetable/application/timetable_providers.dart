import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/timetable/data/timetable_repository.dart';

final timetableRepositoryProvider = Provider<TimetableRepository>((ref) => TimetableRepository(ref.watch(appDatabaseProvider)));

final timetableSessionsProvider = FutureProvider((ref) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(timetableRepositoryProvider).list(actorUserId: userId);
});
