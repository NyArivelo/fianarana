import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/students/data/students_repository.dart';

final studentsRepositoryProvider = Provider<StudentsRepository>((ref) {
  return StudentsRepository(ref.watch(appDatabaseProvider));
});

final classesProvider = FutureProvider((ref) {
  return ref.watch(studentsRepositoryProvider).allClasses();
});

final studentsListProvider = FutureProvider.family<List<StudentListItem>, ({String? query, String? classId})>((ref, args) {
  return ref.watch(studentsRepositoryProvider).list(query: args.query, classId: args.classId);
});

final studentDetailProvider = FutureProvider.family((ref, String id) {
  return ref.watch(studentsRepositoryProvider).getById(id);
});

final studentEnrollmentsProvider = FutureProvider.family((ref, String studentId) {
  return ref.watch(studentsRepositoryProvider).enrollmentsOf(studentId);
});

final studentGuardiansProvider = FutureProvider.family((ref, String studentId) {
  return ref.watch(studentsRepositoryProvider).guardiansOf(studentId);
});
