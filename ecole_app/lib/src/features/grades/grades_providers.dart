import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import 'grades_repository.dart';

final gradesRepositoryProvider = Provider<GradesRepository>((ref) => GradesRepository(ref.watch(appDatabaseProvider)));

final evaluationsProvider = StreamProvider.family<List<Evaluation>, ({String? classId, String? periodId})>((ref, arg) {
  return ref.watch(gradesRepositoryProvider).watchEvaluations(classId: arg.classId, periodId: arg.periodId);
});

final gradesForEvaluationProvider = StreamProvider.family<List<Grade>, String>((ref, evalId) {
  return ref.watch(gradesRepositoryProvider).watchGradesForEvaluation(evalId);
});
