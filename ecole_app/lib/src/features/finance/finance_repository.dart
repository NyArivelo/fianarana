import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

class FinanceRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  FinanceRepository(this.db);

  // Fee types
  Stream<List<FeeType>> watchFeeTypes() => (db.select(db.feeTypes)
        ..where((t) => t.isDeleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();

  Future<void> upsertFeeType({String? id, required String name, String? description, double amount = 0}) async {
    final now = DateTime.now();
    if (id == null) {
      await db.into(db.feeTypes).insert(FeeTypesCompanion.insert(
          id: _uuid.v4(), name: name, description: Value(description), defaultAmount: Value(amount)));
    } else {
      await (db.update(db.feeTypes)..where((t) => t.id.equals(id))).write(FeeTypesCompanion(
          name: Value(name), description: Value(description), defaultAmount: Value(amount), updatedAt: Value(now)));
    }
  }

  Future<void> deleteFeeType(String id) async {
    await (db.update(db.feeTypes)..where((t) => t.id.equals(id))).write(
      FeeTypesCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())));
  }

  // Payments
  Stream<List<Payment>> watchPayments({int limit = 200}) {
    return (db.select(db.payments)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.paidAt)])
          ..limit(limit))
        .watch();
  }

  Future<String> _nextReceiptNumber() async {
    final today = DateFormat('yyyyMMdd').format(DateTime.now());
    final prefix = 'REC-$today-';
    final rows = await (db.select(db.payments)..where((t) => t.receiptNumber.like('$prefix%'))).get();
    final next = rows.length + 1;
    return '$prefix${next.toString().padLeft(4, '0')}';
  }

  Future<void> addPayment({
    required String studentId,
    String? enrollmentId,
    String? feeTypeId,
    required double amount,
    String method = 'cash',
    DateTime? paidAt,
    String? cashierUserId,
    String? note,
  }) async {
    final receipt = await _nextReceiptNumber();
    await db.into(db.payments).insert(PaymentsCompanion.insert(
          id: _uuid.v4(),
          receiptNumber: receipt,
          studentId: studentId,
          enrollmentId: Value(enrollmentId),
          feeTypeId: Value(feeTypeId),
          amount: amount,
          method: Value(method),
          paidAt: paidAt ?? DateTime.now(),
          cashierUserId: Value(cashierUserId),
          note: Value(note),
        ));
  }

  Stream<double> watchTotalPaidToday() {
    final start = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final end = start.add(const Duration(days: 1));
    final q = db.selectOnly(db.payments)
      ..addColumns([db.payments.amount.sum()])
      ..where(db.payments.isDeleted.equals(false) &
          db.payments.status.equals('valid') &
          db.payments.paidAt.isBiggerOrEqualValue(start) &
          db.payments.paidAt.isSmallerThanValue(end));
    return q.watchSingle().map((row) => row.read(db.payments.amount.sum()) ?? 0.0);
  }
}
