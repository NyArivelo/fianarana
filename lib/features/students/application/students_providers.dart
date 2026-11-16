import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/students/data/students_repository.dart';

final studentsRepositoryProvider = Provider<StudentsRepository>((ref) {
  return StudentsRepository(ref.watch(appDatabaseProvider));
});

final classesProvider = FutureProvider<List<ClassesData>>((ref) {
  return ref.watch(studentsRepositoryProvider).allClasses();
});

final studentsListProvider = FutureProvider.family<List<StudentListItem>, ({String? query, String? classId})>((ref, args) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(studentsRepositoryProvider).list(actorUserId: userId, query: args.query, classId: args.classId);
});

final studentDetailProvider = FutureProvider.family((ref, String id) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(studentsRepositoryProvider).getById(id, actorUserId: userId);
});

final studentEnrollmentsProvider = FutureProvider.family((ref, String studentId) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(studentsRepositoryProvider).enrollmentsOf(studentId, actorUserId: userId);
});

final studentGuardiansProvider = FutureProvider.family((ref, String studentId) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(studentsRepositoryProvider).guardiansOf(studentId, actorUserId: userId);
});
