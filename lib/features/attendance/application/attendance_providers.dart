import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/attendance/data/attendance_repository.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(ref.watch(appDatabaseProvider));
});

final attendanceListProvider = FutureProvider.family<List<AttendanceRow>, ({String? classId, DateTime? date})>((ref, args) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(attendanceRepositoryProvider).list(actorUserId: userId, classId: args.classId, date: args.date);
});
