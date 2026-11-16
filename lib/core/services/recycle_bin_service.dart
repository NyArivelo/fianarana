import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/security/audit_service.dart';

class DeletedEntry {
  final String entity;
  final String id;
  final String label;
  final DateTime? deletedAt;
  DeletedEntry(this.entity, this.id, this.label, this.deletedAt);
}

/// Corbeille: suppression logique (isDeleted) avec rétention et restauration.
/// Implémentation fondation sur les principales entités métier.
class RecycleBinService {
  final AppDatabase db;
  late final AuditService _audit = AuditService(db);
  RecycleBinService(this.db);

  Future<List<DeletedEntry>> listDeleted() async {
    final out = <DeletedEntry>[];
    final students = await (db.select(db.students)..where((t) => t.isDeleted.equals(true))).get();
    for (final s in students) { out.add(DeletedEntry('Élèves', s.id, '${s.matricule} ${s.lastName} ${s.firstName}', s.deletedAt)); }
    final payments = await (db.select(db.payments)..where((t) => t.isDeleted.equals(true))).get();
    for (final p in payments) { out.add(DeletedEntry('Paiements', p.id, p.receiptNumber, p.deletedAt)); }
    final evals = await (db.select(db.evaluations)..where((t) => t.isDeleted.equals(true))).get();
    for (final e in evals) { out.add(DeletedEntry('Notes', e.id, e.label, e.deletedAt)); }
    out.sort((a,b) => (b.deletedAt ?? DateTime(0)).compareTo(a.deletedAt ?? DateTime(0)));
    return out;
  }

  Future<void> restore(String entity, String id, {String? actorUserId, String? actorUsername}) async {
    Future<void> upd<T extends Table, D>(TableInfo<T, D> t, GeneratedColumn<String> idCol, GeneratedColumn<bool> delCol, GeneratedColumn<DateTime> updCol, GeneratedColumn<DateTime?> delAtCol) async {
      await (db.update(t)..where((_) => idCol.equals(id))).write(RawValuesInsertable({
        delCol.$name: const Variable(false),
        delAtCol.$name: const Variable<DateTime?>(null),
        updCol.$name: Variable(DateTime.now()),
      }));
    }
    switch (entity) {
      case 'Élèves': await upd(db.students, db.students.id, db.students.isDeleted, db.students.updatedAt, db.students.deletedAt); break;
      case 'Paiements': await upd(db.payments, db.payments.id, db.payments.isDeleted, db.payments.updatedAt, db.payments.deletedAt); break;
      case 'Notes': await upd(db.evaluations, db.evaluations.id, db.evaluations.isDeleted, db.evaluations.updatedAt, db.evaluations.deletedAt); break;
    }
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Corbeille', targetObject: '$entity:$id', description: 'Restauration élément', result: 'Succès');
  }

  Future<int> purgeOlderThan(Duration retention) async {
    final cutoff = DateTime.now().subtract(retention);
    var n = 0;
    n += await (db.delete(db.students)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.payments)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.evaluations)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    return n;
  }
}
