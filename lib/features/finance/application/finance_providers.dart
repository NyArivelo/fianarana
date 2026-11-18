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

final schedulesProvider = FutureProvider.family<List<ScheduleRow>, ({bool overdueOnly, String? status})>((ref, args) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(financeRepositoryProvider).listScheduleRows(
    actorUserId: userId,
    overdueOnly: args.overdueOnly,
    statusFilter: args.status,
  );
});

final financeReportProvider = FutureProvider<FinanceReport>((ref) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(financeRepositoryProvider).report(actorUserId: userId);
});

final ledgerProvider = FutureProvider.family<List<LedgerRow>,
    ({DateTime? from, DateTime? to, String? query, String? classId})>((ref, args) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(financeRepositoryProvider).ledger(
        actorUserId: userId,
        from: args.from,
        to: args.to,
        query: args.query,
        classId: args.classId,
      );
});
