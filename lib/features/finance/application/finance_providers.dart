import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/finance/data/finance_repository.dart';

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  return FinanceRepository(ref.watch(appDatabaseProvider));
});

final paymentsProvider = FutureProvider.family<List<PaymentRow>, String?>((ref, query) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(financeRepositoryProvider).listPayments(actorUserId: userId, query: query);
});

final financeTotalsProvider = FutureProvider((ref) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(financeRepositoryProvider).totals(actorUserId: userId);
});

final cashClosuresProvider = FutureProvider((ref) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(financeRepositoryProvider).listClosures(actorUserId: userId);
});

final schedulesProvider = FutureProvider.family((ref, bool overdueOnly) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(financeRepositoryProvider).listSchedules(actorUserId: userId, overdueOnly: overdueOnly);
});
