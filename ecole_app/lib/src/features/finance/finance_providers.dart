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
