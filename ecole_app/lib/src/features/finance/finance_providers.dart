import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../core/security/authorization_service.dart';
import '../auth/auth_controller.dart';
import '../students/students_providers.dart';
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

final adjustmentsProvider = StreamProvider<List<FinancialAdjustment>>((ref) {
  return ref.watch(financeRepositoryProvider).watchAdjustments();
});

final adjustmentsForStudentProvider = StreamProvider.family<List<FinancialAdjustment>, String>((ref, studentId) {
  return ref.watch(financeRepositoryProvider).watchAdjustments(studentId: studentId);
});

final studentFinanceSummaryProvider = FutureProvider<List<({Student student, double planned, double paid, double adjustments, double balance, int overdueCount})>>((ref) async {
  final students = ref.watch(studentsProvider).valueOrNull ?? [];
  final plans = await ref.watch(financeRepositoryProvider).db.select(ref.watch(financeRepositoryProvider).db.paymentPlans).get();
  final inst = await ref.watch(financeRepositoryProvider).db.select(ref.watch(financeRepositoryProvider).db.paymentInstallments).get();
  final pays = await ref.watch(financeRepositoryProvider).db.select(ref.watch(financeRepositoryProvider).db.payments).get();
  final adjs = await ref.watch(financeRepositoryProvider).db.select(ref.watch(financeRepositoryProvider).db.financialAdjustments).get();
  final activePlans = plans.where((p)=>!p.isDeleted && p.status!='cancelled').toList();
  final activeInst = inst.where((i)=>!i.isDeleted).toList();
  final activePays = pays.where((p)=>!p.isDeleted && p.status=='valid').toList();
  final activeAdjs = adjs.where((a)=>!a.isDeleted && a.status=='active').toList();
  final out = <({Student student, double planned, double paid, double adjustments, double balance, int overdueCount})>[];
  for (final s in students) {
    final planned = activePlans.where((p)=>p.studentId==s.id).fold<double>(0,(a,p)=>a+p.totalAmount);
    final paid = activePays.where((p)=>p.studentId==s.id).fold<double>(0,(a,p)=>a+p.amount);
    final adjustments = activeAdjs.where((a)=>a.studentId==s.id).fold<double>(0,(a,x)=>a+x.amount);
    final overdueCount = activeInst.where((i){
      final plan = activePlans.where((p)=>p.id==i.planId && p.studentId==s.id).toList();
      return plan.isNotEmpty && i.status=='overdue';
    }).length;
    final balance = (planned - adjustments) - paid;
    if (planned > 0 || paid > 0 || adjustments > 0 || overdueCount > 0) {
      out.add((student: s, planned: planned, paid: paid, adjustments: adjustments, balance: balance, overdueCount: overdueCount));
    }
  }
  out.sort((a,b){ final bo = b.balance.compareTo(a.balance); return bo != 0 ? bo : b.overdueCount.compareTo(a.overdueCount); });
  return out;
});
