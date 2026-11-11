import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import 'staff_repository.dart';

final staffRepositoryProvider = Provider<StaffRepository>((ref) => StaffRepository(ref.watch(appDatabaseProvider)));

final staffSearchProvider = StateProvider<String>((ref) => '');
final staffTypeFilterProvider = StateProvider<String?>((ref) => null);

final staffListProvider = StreamProvider<List<StaffMember>>((ref) {
  return ref.watch(staffRepositoryProvider).watchStaff(query: ref.watch(staffSearchProvider), type: ref.watch(staffTypeFilterProvider));
});
