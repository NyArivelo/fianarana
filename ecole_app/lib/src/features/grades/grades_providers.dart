import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../core/security/current_user_scope.dart';
import 'grades_repository.dart';

final gradesRepositoryProvider = Provider<GradesRepository>((ref) => GradesRepository(ref.watch(appDatabaseProvider)));

final evaluationsProvider = StreamProvider.family<List<Evaluation>, ({String? classId, String? periodId})>((ref, arg) {
  final scope = ref.watch(currentUserScopeProvider).valueOrNull;
  final stream = ref.watch(gradesRepositoryProvider).watchEvaluations(classId: arg.classId, periodId: arg.periodId);
  if (scope != null && scope.scope == 'restricted') {
    final allowed = scope.allowedClassIds ?? const <String>[];
    return stream.map((list) => list.where((e) => allowed.contains(e.classId)).toList());
  }
  return stream;
});

final gradesForEvaluationProvider = StreamProvider.family<List<Grade>, String>((ref, evalId) {
  return ref.watch(gradesRepositoryProvider).watchGradesForEvaluation(evalId);
});

final councilDecisionsProvider = StreamProvider.family<List<CouncilDecision>, ({String periodId, String classId})>((ref, arg) {
  final scope = ref.watch(currentUserScopeProvider).valueOrNull;
  if (scope != null && scope.scope == 'restricted') {
    final allowed = scope.allowedClassIds ?? const <String>[];
    if (!allowed.contains(arg.classId)) return Stream.value(const <CouncilDecision>[]);
  }
  return ref.watch(gradesRepositoryProvider).watchCouncilDecisions(periodId: arg.periodId, classId: arg.classId);
});
