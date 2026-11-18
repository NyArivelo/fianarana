import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/finance/data/fee_repository.dart';

final feeRepositoryProvider = Provider<FeeRepository>((ref) {
  return FeeRepository(ref.watch(appDatabaseProvider));
});

final feeStructuresProvider = FutureProvider.family<List<FeeStructure>, String?>((ref, yearId) {
  return ref.watch(feeRepositoryProvider).listFees(schoolYearId: yearId);
});

final studentDiscountsProvider = FutureProvider.family<List<StudentDiscount>, String?>((ref, studentId) {
  return ref.watch(feeRepositoryProvider).listDiscounts(studentId: studentId);
});

final creditNotesProvider = FutureProvider.family<List<CreditNote>, String?>((ref, studentId) {
  return ref.watch(feeRepositoryProvider).listCreditNotes(studentId: studentId);
});

final allCreditNotesProvider = FutureProvider<List<CreditNote>>((ref) {
  return ref.watch(feeRepositoryProvider).listCreditNotes();
});

final allDiscountsProvider = FutureProvider<List<StudentDiscount>>((ref) {
  return ref.watch(feeRepositoryProvider).listDiscounts();
});

final financeActorProvider = Provider<({String? id, String? username})>((ref) {
  final auth = ref.watch(authControllerProvider);
  return (id: auth.userId, username: auth.username);
});
