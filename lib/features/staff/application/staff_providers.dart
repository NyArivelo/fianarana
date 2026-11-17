import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/staff/data/staff_repository.dart';

final staffRepositoryProvider = Provider<StaffRepository>((ref) => StaffRepository(ref.watch(appDatabaseProvider)));

final staffListProvider = FutureProvider<List<StaffMember>>((ref) {
  final auth = ref.watch(authControllerProvider);
  return ref.watch(staffRepositoryProvider).listStaff(actorUserId: auth.userId);
});

final teacherAbsencesProvider = FutureProvider<List<TeacherAbsence>>((ref) {
  final auth = ref.watch(authControllerProvider);
  return ref.watch(staffRepositoryProvider).listAbsences(actorUserId: auth.userId);
});
