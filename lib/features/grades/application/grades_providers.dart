import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/grades/data/grades_repository.dart';

final gradesRepositoryProvider = Provider<GradesRepository>((ref) => GradesRepository(ref.watch(appDatabaseProvider)));

final gradesListProvider = FutureProvider.family<List<GradeRow>, ({String? classId, String? subjectId})>((ref, args) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(gradesRepositoryProvider).list(actorUserId: userId, classId: args.classId, subjectId: args.subjectId);
});
