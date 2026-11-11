import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import 'facilities_repository.dart';

final facilitiesRepositoryProvider = Provider<FacilitiesRepository>((ref) {
  return FacilitiesRepository(ref.watch(appDatabaseProvider));
});

final facilitiesRoomsProvider = StreamProvider<List<Room>>((ref) {
  return ref.watch(facilitiesRepositoryProvider).watchRooms();
});

final equipmentProvider = StreamProvider<List<EquipmentItem>>((ref) {
  return ref.watch(facilitiesRepositoryProvider).watchEquipment();
});

final reservationsProvider = StreamProvider<List<RoomReservation>>((ref) {
  return ref.watch(facilitiesRepositoryProvider).watchReservations();
});
