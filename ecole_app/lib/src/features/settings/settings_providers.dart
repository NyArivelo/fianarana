import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import 'settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(appDatabaseProvider));
});

final schoolSettingProvider = StreamProvider<SchoolSetting?>((ref) {
  return ref.watch(settingsRepositoryProvider).watchSchoolSetting();
});

final academicYearsProvider = StreamProvider<List<AcademicYear>>((ref) {
  return ref.watch(settingsRepositoryProvider).watchAcademicYears();
});

final periodsProvider =
    StreamProvider.family<List<Period>, String>((ref, academicYearId) {
  return ref.watch(settingsRepositoryProvider).watchPeriods(academicYearId);
});
