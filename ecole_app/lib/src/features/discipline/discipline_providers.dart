import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import 'discipline_repository.dart';

final disciplineRepositoryProvider = Provider<DisciplineRepository>((ref) => DisciplineRepository(ref.watch(appDatabaseProvider)));

final disciplineSearchProvider = StateProvider<String>((ref) => '');
final disciplineStatusFilterProvider = StateProvider<String?>((ref) => null);
final disciplineStudentFilterProvider = StateProvider<String?>((ref) => null);

final incidentsProvider = StreamProvider<List<DisciplinaryIncident>>((ref) {
  return ref.watch(disciplineRepositoryProvider).watchIncidents(
    studentId: ref.watch(disciplineStudentFilterProvider),
    status: ref.watch(disciplineStatusFilterProvider),
    query: ref.watch(disciplineSearchProvider),
  );
});

final actionsForIncidentProvider = StreamProvider.family<List<DisciplinaryAction>, String>((ref, incidentId) {
  return ref.watch(disciplineRepositoryProvider).watchActions(incidentId);
});
