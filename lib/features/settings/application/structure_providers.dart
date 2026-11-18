import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/core/services/establishment_service.dart';
import 'package:fianarana/features/settings/data/structure_repository.dart';

final structureRepositoryProvider = Provider<StructureRepository>((ref) {
  return StructureRepository(ref.watch(appDatabaseProvider));
});

final schoolYearsProvider = FutureProvider<List<SchoolYear>>((ref) {
  return ref.watch(structureRepositoryProvider).listYears();
});

final periodsProvider = FutureProvider.family<List<Period>, String?>((ref, yearId) {
  return ref.watch(structureRepositoryProvider).listPeriods(schoolYearId: yearId);
});

final levelsProvider = FutureProvider<List<Level>>((ref) {
  return ref.watch(structureRepositoryProvider).listLevels();
});

final classesStructureProvider = FutureProvider.family<List<ClassesData>, String?>((ref, yearId) {
  return ref.watch(structureRepositoryProvider).listClasses(schoolYearId: yearId);
});

final subjectsProvider = FutureProvider<List<Subject>>((ref) {
  return ref.watch(structureRepositoryProvider).listSubjects();
});

/// Établissement courant (réutilise le service central).
final currentEstablishmentProvider = FutureProvider<EstablishmentInfo>((ref) {
  return ref.watch(establishmentServiceProvider).currentOrDefault();
});
