import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../core/security/authorization_service.dart';
import '../auth/auth_controller.dart';
import 'finance_repository.dart';

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  return FinanceRepository(ref.watch(appDatabaseProvider));
});

final authorizationServiceProvider = Provider<AuthorizationService>((ref) => AuthorizationService(ref.watch(appDatabaseProvider)));

final currentFinanceScopeProvider = FutureProvider<String>((ref) async {
  final user = ref.watch(authControllerProvider).currentUser;
  if (user == null) return 'restricted';
  return ref.watch(authorizationServiceProvider).effectiveScope(user.id);
});

final feeTypesProvider = StreamProvider<List<FeeType>>((ref) {
  return ref.watch(financeRepositoryProvider).watchFeeTypes();
});

final paymentsProvider = StreamProvider<List<Payment>>((ref) {
  final scope = ref.watch(currentFinanceScopeProvider).valueOrNull;
  final user = ref.watch(authControllerProvider).currentUser;
  final all = ref.watch(financeRepositoryProvider).watchPayments();
  if (scope == 'caisse' && user != null) {
    return all.map((list) => list.where((p) => p.cashierUserId == user.id).toList());
  }
  return all;
});

final totalPaidTodayProvider = StreamProvider<double>((ref) {
  final scope = ref.watch(currentFinanceScopeProvider).valueOrNull;
  final user = ref.watch(authControllerProvider).currentUser;
  if (scope == 'caisse' && user != null) {
    return ref.watch(financeRepositoryProvider).watchTotalPaidToday(cashierUserId: user.id);
  }
  return ref.watch(financeRepositoryProvider).watchTotalPaidToday();
});

final paymentPlansProvider = StreamProvider.family<List<PaymentPlan>, String>((ref, studentId) {
  return ref.watch(financeRepositoryProvider).watchPlansForStudent(studentId);
});

final installmentsProvider = StreamProvider.family<List<PaymentInstallment>, String>((ref, planId) {
  return ref.watch(financeRepositoryProvider).watchInstallments(planId);
});

final allInstallmentsProvider = StreamProvider<List<PaymentInstallment>>((ref) {
  ref.watch(financeRepositoryProvider).refreshOverdueInstallments();
  return ref.watch(financeRepositoryProvider).watchAllInstallments();
});

final cashClosuresProvider = StreamProvider<List<CashClosure>>((ref) {
  final scope = ref.watch(currentFinanceScopeProvider).valueOrNull;
  final user = ref.watch(authControllerProvider).currentUser;
  final all = ref.watch(financeRepositoryProvider).watchCashClosures();
  if (scope == 'caisse' && user != null) {
    return all.map((list) => list.where((c) => c.cashierUserId == user.id).toList());
  }
  return all;
});
