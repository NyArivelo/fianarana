import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import 'attendance_repository.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) => AttendanceRepository(ref.watch(appDatabaseProvider)));

final attendanceForSessionProvider = StreamProvider.family<List<AttendanceRecord>, String>((ref, sessionId) {
  return ref.watch(attendanceRepositoryProvider).watchForSession(sessionId);
});
