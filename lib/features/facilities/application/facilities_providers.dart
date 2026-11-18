import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/facilities/data/facilities_repository.dart';

final facilitiesRepositoryProvider = Provider<FacilitiesRepository>((ref) {
  return FacilitiesRepository(ref.watch(appDatabaseProvider));
});

final facilitiesListProvider = FutureProvider<List<FacilityRow>>((ref) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(facilitiesRepositoryProvider).list(actorUserId: userId);
});

final facilityReservationsProvider = FutureProvider<List<FacilityReservation>>((ref) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(facilitiesRepositoryProvider).listReservations(actorUserId: userId);
});

final facilityMaintenanceProvider = FutureProvider<List<FacilityMaintenanceData>>((ref) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(facilitiesRepositoryProvider).listMaintenance(actorUserId: userId);
});
