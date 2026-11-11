import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../core/security/current_user_scope.dart';
import 'academics_repository.dart';

final academicsRepositoryProvider = Provider<AcademicsRepository>((ref) {
  return AcademicsRepository(ref.watch(appDatabaseProvider));
});

final educationTypesProvider = StreamProvider<List<EducationType>>((ref) {
  return ref.watch(academicsRepositoryProvider).watchEducationTypes();
});

final levelsProvider = StreamProvider<List<Level>>((ref) {
  return ref.watch(academicsRepositoryProvider).watchLevels();
});

final subjectsProvider = StreamProvider<List<Subject>>((ref) {
  return ref.watch(academicsRepositoryProvider).watchSubjects();
});

final classesProvider = StreamProvider.family<List<ClassesData>, String?>((ref, yearId) {
  final scope = ref.watch(currentUserScopeProvider).valueOrNull;
  final all = ref.watch(academicsRepositoryProvider).watchClasses(academicYearId: yearId);
  if (scope != null && scope.scope == 'restricted') {
    final allowed = scope.allowedClassIds ?? const <String>[];
    return all.map((list) => list.where((c) => allowed.contains(c.id)).toList());
  }
  return all;
});
