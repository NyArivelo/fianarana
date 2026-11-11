import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

class FacilitiesRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  FacilitiesRepository(this.db);

  Stream<List<Room>> watchRooms() => (db.select(db.rooms)
        ..where((t) => t.isDeleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();

  Future<void> upsertRoom({String? id, required String name, String? location, int? capacity}) async {
    final now = DateTime.now();
    if (id == null) {
      await db.into(db.rooms).insert(RoomsCompanion.insert(
          id: _uuid.v4(), name: name, location: Value(location), capacity: Value(capacity)));
    } else {
      await (db.update(db.rooms)..where((t) => t.id.equals(id))).write(RoomsCompanion(
          name: Value(name), location: Value(location), capacity: Value(capacity), updatedAt: Value(now)));
    }
  }

  Future<void> deleteRoom(String id) async {
    await (db.update(db.rooms)..where((t) => t.id.equals(id))).write(
      RoomsCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())));
  }

  Stream<List<EquipmentItem>> watchEquipment({String? roomId}) {
    final q = db.select(db.equipmentItems)..where((t) => t.isDeleted.equals(false));
    if (roomId != null && roomId.isNotEmpty) q.where((t) => t.roomId.equals(roomId));
    q.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.watch();
  }

  Future<void> upsertEquipment({
    String? id,
    required String name,
    String? category,
    String? serialNumber,
    String? roomId,
    String status = 'ok',
    int quantity = 1,
    DateTime? purchaseDate,
    String? notes,
  }) async {
    final now = DateTime.now();
    if (id == null) {
      await db.into(db.equipmentItems).insert(EquipmentItemsCompanion.insert(
            id: _uuid.v4(),
            name: name,
            category: Value(category),
            serialNumber: Value(serialNumber),
            roomId: Value(roomId),
            status: Value(status),
            quantity: Value(quantity),
            purchaseDate: Value(purchaseDate),
            notes: Value(notes),
          ));
    } else {
      await (db.update(db.equipmentItems)..where((t) => t.id.equals(id))).write(EquipmentItemsCompanion(
            name: Value(name),
            category: Value(category),
            serialNumber: Value(serialNumber),
            roomId: Value(roomId),
            status: Value(status),
            quantity: Value(quantity),
            purchaseDate: Value(purchaseDate),
            notes: Value(notes),
            updatedAt: Value(now),
          ));
    }
  }

  Future<void> deleteEquipment(String id) async {
    await (db.update(db.equipmentItems)..where((t) => t.id.equals(id))).write(
      EquipmentItemsCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())));
  }

  Stream<List<RoomReservation>> watchReservations({String? roomId}) {
    final q = db.select(db.roomReservations)..where((t) => t.isDeleted.equals(false));
    if (roomId != null && roomId.isNotEmpty) q.where((t) => t.roomId.equals(roomId));
    q.orderBy([(t) => OrderingTerm.desc(t.startAt)]);
    return q.watch();
  }

  Future<String?> upsertReservation({
    String? id,
    required String roomId,
    required String title,
    String? reservedFor,
    required DateTime startAt,
    required DateTime endAt,
    String status = 'reserved',
    String? notes,
  }) async {
    if (!endAt.isAfter(startAt)) return 'L\'heure de fin doit être après le début.';
    if (status == 'reserved') {
      final existing = await (db.select(db.roomReservations)
            ..where((t) => t.isDeleted.equals(false) & t.roomId.equals(roomId) & t.status.equals('reserved')))
          .get();
      for (final r in existing) {
        if (id != null && r.id == id) continue;
        final overlap = startAt.isBefore(r.endAt) && endAt.isAfter(r.startAt);
        if (overlap) return 'Conflit: la salle est déjà réservée (${r.title}).';
      }
      final sessions = await (db.select(db.courseSessions)
            ..where((t) => t.isDeleted.equals(false) & t.roomId.equals(roomId) & t.status.isNotIn(['cancelled']) & t.startAt.isSmallerThanValue(endAt) & t.endAt.isBiggerThanValue(startAt)))
          .get();
      if (sessions.isNotEmpty) {
        final s = sessions.first;
        final t1 = '${s.startAt.hour.toString().padLeft(2, '0')}:${s.startAt.minute.toString().padLeft(2, '0')}';
        final t2 = '${s.endAt.hour.toString().padLeft(2, '0')}:${s.endAt.minute.toString().padLeft(2, '0')}';
        return 'Conflit: une séance occupe déjà la salle (${s.title ?? 'séance'} $t1-$t2).';
      }
    }
    final now = DateTime.now();
    if (id == null) {
      await db.into(db.roomReservations).insert(RoomReservationsCompanion.insert(
            id: _uuid.v4(),
            roomId: roomId,
            title: title,
            reservedFor: Value(reservedFor),
            startAt: startAt,
            endAt: endAt,
            status: Value(status),
            notes: Value(notes),
          ));
    } else {
      await (db.update(db.roomReservations)..where((t) => t.id.equals(id))).write(RoomReservationsCompanion(
            roomId: Value(roomId),
            title: Value(title),
            reservedFor: Value(reservedFor),
            startAt: Value(startAt),
            endAt: Value(endAt),
            status: Value(status),
            notes: Value(notes),
            updatedAt: Value(now),
          ));
    }
    return null;
  }

  Future<void> deleteReservation(String id) async {
    await (db.update(db.roomReservations)..where((t) => t.id.equals(id))).write(
      RoomReservationsCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())));
  }
}
