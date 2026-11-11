import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import 'finance_repository.dart';

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  return FinanceRepository(ref.watch(appDatabaseProvider));
});

final feeTypesProvider = StreamProvider<List<FeeType>>((ref) {
  return ref.watch(financeRepositoryProvider).watchFeeTypes();
});

final paymentsProvider = StreamProvider<List<Payment>>((ref) {
  return ref.watch(financeRepositoryProvider).watchPayments();
});

final totalPaidTodayProvider = StreamProvider<double>((ref) {
  return ref.watch(financeRepositoryProvider).watchTotalPaidToday();
});

final paymentPlansProvider = StreamProvider.family<List<PaymentPlan>, String>((ref, studentId) {
  return ref.watch(financeRepositoryProvider).watchPlansForStudent(studentId);
});

final installmentsProvider = StreamProvider.family<List<PaymentInstallment>, String>((ref, planId) {
  return ref.watch(financeRepositoryProvider).watchInstallments(planId);
});

final allInstallmentsProvider = StreamProvider<List<PaymentInstallment>>((ref) {
  // best-effort refresh overdue
  ref.watch(financeRepositoryProvider).refreshOverdueInstallments();
  return ref.watch(financeRepositoryProvider).watchAllInstallments();
});

final cashClosuresProvider = StreamProvider<List<CashClosure>>((ref) {
  return ref.watch(financeRepositoryProvider).watchCashClosures();
});
