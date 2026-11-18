import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/discipline/data/discipline_repository.dart';

final disciplineRepositoryProvider = Provider<DisciplineRepository>((ref) {
  return DisciplineRepository(ref.watch(appDatabaseProvider));
});

final disciplineCasesProvider = FutureProvider.family<List<DisciplineCaseRow>, ({String? status, String? query})>((ref, args) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(disciplineRepositoryProvider).listCases(
        actorUserId: userId,
        statusFilter: args.status,
        query: args.query,
      );
});

final disciplineStatsProvider = FutureProvider<Map<String, int>>((ref) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(disciplineRepositoryProvider).stats(actorUserId: userId);
});

final disciplineActionsProvider = FutureProvider.family<List<DisciplineAction>, String>((ref, caseId) {
  return ref.watch(disciplineRepositoryProvider).listActions(caseId);
});
