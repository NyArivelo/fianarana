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
    final students = await (db.select(db.students)
          ..where((t) => t.isDeleted.equals(true)))
        .get();
    for (final s in students) {
      out.add(DeletedEntry('Élèves', s.id,
          '${s.matricule} ${s.lastName} ${s.firstName}', s.deletedAt));
    }
    final payments = await (db.select(db.payments)
          ..where((t) => t.isDeleted.equals(true)))
        .get();
    for (final p in payments) {
      out.add(DeletedEntry('Paiements', p.id, p.receiptNumber, p.deletedAt));
    }
    final evals = await (db.select(db.evaluations)
          ..where((t) => t.isDeleted.equals(true)))
        .get();
    for (final e in evals) {
      out.add(DeletedEntry('Notes', e.id, e.label, e.deletedAt));
    }
    final enrolls = await (db.select(db.enrollments)
          ..where((t) => t.isDeleted.equals(true)))
        .get();
    for (final e in enrolls) {
      out.add(DeletedEntry('Inscriptions', e.id, e.status, e.deletedAt));
    }
    final classes = await (db.select(db.classes)
          ..where((t) => t.isDeleted.equals(true)))
        .get();
    for (final c in classes) {
      out.add(DeletedEntry('Classes', c.id, c.label, c.deletedAt));
    }
    out.sort((a, b) =>
        (b.deletedAt ?? DateTime(0)).compareTo(a.deletedAt ?? DateTime(0)));
    return out;
  }

  Future<void> restore(String entity, String id,
      {String? actorUserId, String? actorUsername}) async {
    switch (entity) {
      case 'Élèves':
        await (db.update(db.students)..where((t) => t.id.equals(id)))
            .write(StudentsCompanion(
          isDeleted: const Value(false),
          deletedAt: const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ));
        break;
      case 'Paiements':
        await (db.update(db.payments)..where((t) => t.id.equals(id)))
            .write(PaymentsCompanion(
          isDeleted: const Value(false),
          deletedAt: const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ));
        break;
      case 'Notes':
        await (db.update(db.evaluations)..where((t) => t.id.equals(id)))
            .write(EvaluationsCompanion(
          isDeleted: const Value(false),
          deletedAt: const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ));
        break;
      case 'Inscriptions':
        await (db.update(db.enrollments)..where((t) => t.id.equals(id)))
            .write(EnrollmentsCompanion(
          isDeleted: const Value(false),
          deletedAt: const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ));
        break;
      case 'Classes':
        await (db.update(db.classes)..where((t) => t.id.equals(id)))
            .write(ClassesCompanion(
          isDeleted: const Value(false),
          deletedAt: const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ));
        break;
    }
    await _audit.log(
        userId: actorUserId,
        username: actorUsername,
        module: 'Corbeille',
        targetObject: '$entity:$id',
        description: 'Restauration élément',
        result: 'Succès');
  }

  Future<int> purgeOlderThan(Duration retention) async {
    final cutoff = DateTime.now().subtract(retention);
    var n = 0;
    n += await (db.delete(db.students)
          ..where((t) =>
              t.isDeleted.equals(true) &
              t.deletedAt.isSmallerThanValue(cutoff)))
        .go();
    n += await (db.delete(db.payments)
          ..where((t) =>
              t.isDeleted.equals(true) &
              t.deletedAt.isSmallerThanValue(cutoff)))
        .go();
    n += await (db.delete(db.evaluations)
          ..where((t) =>
              t.isDeleted.equals(true) &
              t.deletedAt.isSmallerThanValue(cutoff)))
        .go();
    n += await (db.delete(db.enrollments)
          ..where((t) =>
              t.isDeleted.equals(true) &
              t.deletedAt.isSmallerThanValue(cutoff)))
        .go();
    n += await (db.delete(db.classes)
          ..where((t) =>
              t.isDeleted.equals(true) &
              t.deletedAt.isSmallerThanValue(cutoff)))
        .go();
    return n;
  }
}
