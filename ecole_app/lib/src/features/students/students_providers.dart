import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../core/security/current_user_scope.dart';
import '../settings/settings_providers.dart';
import 'students_repository.dart';

class StudentFilters {
  final String? status;
  final String? classId;
  final String? gender;
  final String? academicYearId;
  const StudentFilters({this.status, this.classId, this.gender, this.academicYearId});

  StudentFilters copyWith({String? status, String? classId, String? gender, String? academicYearId, bool clearClass = false, bool clearStatus = false, bool clearGender = false, bool clearYear = false}) {
    return StudentFilters(
      status: clearStatus ? null : (status ?? this.status),
      classId: clearClass ? null : (classId ?? this.classId),
      gender: clearGender ? null : (gender ?? this.gender),
      academicYearId: clearYear ? null : (academicYearId ?? this.academicYearId),
    );
  }

  bool get hasAny => (status != null && status!.isNotEmpty) || (classId != null && classId!.isNotEmpty) || (gender != null && gender!.isNotEmpty) || (academicYearId != null && academicYearId!.isNotEmpty);
}

final studentsRepositoryProvider = Provider<StudentsRepository>((ref) {
  return StudentsRepository(ref.watch(appDatabaseProvider));
});

final studentsSearchProvider = StateProvider<String>((ref) => '');
final studentsFiltersProvider = StateProvider<StudentFilters>((ref) => const StudentFilters());

final studentsProvider = StreamProvider<List<Student>>((ref) {
  final q = ref.watch(studentsSearchProvider);
  final filters = ref.watch(studentsFiltersProvider);
  final scope = ref.watch(currentUserScopeProvider).valueOrNull;
  final years = ref.watch(academicYearsProvider).valueOrNull ?? [];
  final defaultYearId = years.where((y) => y.isCurrent).firstOrNull?.id;
  final yearId = filters.academicYearId ?? defaultYearId;
  List<String>? allowed;
  if (scope != null && scope.scope == 'restricted') {
    allowed = scope.allowedClassIds ?? [];
  }
  return ref.watch(studentsRepositoryProvider).watchStudents(
        query: q,
        allowedClassIds: allowed,
        academicYearId: yearId,
        status: filters.status,
        classId: filters.classId,
        gender: filters.gender,
      );
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
