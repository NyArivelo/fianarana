import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import 'students_repository.dart';

final studentsRepositoryProvider = Provider<StudentsRepository>((ref) {
  return StudentsRepository(ref.watch(appDatabaseProvider));
});

final studentsSearchProvider = StateProvider<String>((ref) => '');

final studentsProvider = StreamProvider<List<Student>>((ref) {
  final q = ref.watch(studentsSearchProvider);
  return ref.watch(studentsRepositoryProvider).watchStudents(query: q);
});

final studentGuardiansProvider = StreamProvider.family<List<Guardian>, String>((ref, studentId) {
  return ref.watch(studentsRepositoryProvider).watchGuardiansForStudent(studentId);
});

final enrollmentsProvider = StreamProvider.family<List<Enrollment>, String>((ref, studentId) {
  return ref.watch(studentsRepositoryProvider).watchEnrollmentsForStudent(studentId);
});

final allGuardiansProvider = StreamProvider<List<Guardian>>((ref) {
  return ref.watch(studentsRepositoryProvider).watchGuardians();
});
