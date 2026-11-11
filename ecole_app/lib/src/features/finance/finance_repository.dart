import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

class CashDayClosedException implements Exception {
  final String message;
  CashDayClosedException(this.message);
  @override
  String toString() => message;
}

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
    String? installmentId,
    required double amount,
    String method = 'cash',
    DateTime? paidAt,
    String? cashierUserId,
    String? note,
  }) async {
    final date = paidAt ?? DateTime.now();
    if (await isDayClosed(date, cashierUserId: cashierUserId) ||
        (cashierUserId == null && await isDayClosed(date))) {
      throw CashDayClosedException('Caisse clôturée pour cette journée : les écritures sont verrouillées.');
    }
    final receipt = await _nextReceiptNumber();
    await db.transaction(() async {
      await db.into(db.payments).insert(PaymentsCompanion.insert(
            id: _uuid.v4(),
            receiptNumber: receipt,
            studentId: studentId,
            enrollmentId: Value(enrollmentId),
            feeTypeId: Value(feeTypeId),
            installmentId: Value(installmentId),
            amount: amount,
            method: Value(method),
            paidAt: date,
            cashierUserId: Value(cashierUserId),
            note: Value(note),
          ));
      if (installmentId != null) {
        await _applyPaymentToInstallment(installmentId, amount);
      }
    });
  }

  Stream<double> watchTotalPaidToday({String? cashierUserId}) {
    final start = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final end = start.add(const Duration(days: 1));
    final q = db.selectOnly(db.payments)..addColumns([db.payments.amount.sum()]);
    var where = db.payments.isDeleted.equals(false) &
        db.payments.status.equals('valid') &
        db.payments.paidAt.isBiggerOrEqualValue(start) &
        db.payments.paidAt.isSmallerThanValue(end);
    if (cashierUserId != null) where = where & db.payments.cashierUserId.equals(cashierUserId);
    q.where(where);
    return q.watchSingle().map((row) => row.read(db.payments.amount.sum()) ?? 0.0);
  }

  // --- Payment plans & installments ---
  Stream<List<PaymentPlan>> watchPlansForStudent(String studentId) {
    return (db.select(db.paymentPlans)
          ..where((t) => t.studentId.equals(studentId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Stream<List<PaymentInstallment>> watchInstallments(String planId) {
    return (db.select(db.paymentInstallments)
          ..where((t) => t.planId.equals(planId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
        .watch();
  }

  Stream<List<PaymentInstallment>> watchAllInstallments({String status = 'all'}) {
    final q = db.select(db.paymentInstallments)..where((t) => t.isDeleted.equals(false));
    if (status != 'all') q.where((t) => t.status.equals(status));
    q.orderBy([(t) => OrderingTerm.asc(t.dueDate)]);
    return q.watch();
  }

  Future<void> createPaymentPlan({
    required String studentId,
    String? enrollmentId,
    String? feeTypeId,
    required String name,
    required double totalAmount,
    required int installmentsCount,
    required DateTime firstDueDate,
    int intervalDays = 30,
  }) async {
    final planId = _uuid.v4();
    final per = (totalAmount / installmentsCount);
    await db.transaction(() async {
      await db.into(db.paymentPlans).insert(PaymentPlansCompanion.insert(
            id: planId,
            studentId: studentId,
            enrollmentId: Value(enrollmentId),
            feeTypeId: Value(feeTypeId),
            name: name,
            totalAmount: totalAmount,
          ));
      double allocated = 0;
      for (var i = 1; i <= installmentsCount; i++) {
        final isLast = i == installmentsCount;
        final amt = isLast ? (totalAmount - allocated) : double.parse(per.toStringAsFixed(2));
        allocated += amt;
        final due = firstDueDate.add(Duration(days: intervalDays * (i - 1)));
        await db.into(db.paymentInstallments).insert(PaymentInstallmentsCompanion.insert(
              id: _uuid.v4(),
              planId: planId,
              sequence: Value(i),
              dueDate: due,
              amount: amt,
            ));
      }
    });
  }

  Future<void> refreshOverdueInstallments() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final rows = await (db.select(db.paymentInstallments)
          ..where((t) => t.isDeleted.equals(false) & t.status.isIn(['pending', 'partial'])))
        .get();
    for (final inst in rows) {
      if (inst.dueDate.isBefore(today) && inst.paidAmount < inst.amount) {
        await (db.update(db.paymentInstallments)..where((t) => t.id.equals(inst.id))).write(
          const PaymentInstallmentsCompanion(status: Value('overdue')),
        );
      }
    }
  }

  Future<void> _applyPaymentToInstallment(String installmentId, double amount) async {
    final inst = await (db.select(db.paymentInstallments)..where((t) => t.id.equals(installmentId))).getSingleOrNull();
    if (inst == null) return;
    final newPaid = inst.paidAmount + amount;
    String status = 'partial';
    if (newPaid >= inst.amount - 0.001) status = 'paid';
    await (db.update(db.paymentInstallments)..where((t) => t.id.equals(inst.id))).write(
      PaymentInstallmentsCompanion(paidAmount: Value(newPaid), status: Value(status), updatedAt: Value(DateTime.now())),
    );
    // update plan status if all paid
    final siblings = await (db.select(db.paymentInstallments)..where((t) => t.planId.equals(inst.planId))).get();
    if (siblings.every((s) => s.id == inst.id ? status == 'paid' : s.status == 'paid')) {
      await (db.update(db.paymentPlans)..where((t) => t.id.equals(inst.planId))).write(
        PaymentPlansCompanion(status: const Value('completed'), updatedAt: Value(DateTime.now())),
      );
    }
  }

  // --- Cash closures ---
  Stream<List<CashClosure>> watchCashClosures() {
    return (db.select(db.cashClosures)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.closureDate)]))
        .watch();
  }

  // --- Financial adjustments (remises / avoirs / bourses) ---
  Stream<List<FinancialAdjustment>> watchAdjustments({String? studentId}) {
    final q = db.select(db.financialAdjustments)..where((t) => t.isDeleted.equals(false));
    if (studentId != null && studentId.isNotEmpty) q.where((t) => t.studentId.equals(studentId));
    q.orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.createdAt)]);
    return q.watch();
  }

  Future<void> upsertAdjustment({
    String? id,
    required String studentId,
    String? enrollmentId,
    String? feeTypeId,
    required String type,
    required double amount,
    String? reason,
    DateTime? date,
    String status = 'active',
    String? note,
  }) async {
    final now = DateTime.now();
    if (id == null) {
      await db.into(db.financialAdjustments).insert(FinancialAdjustmentsCompanion.insert(
            id: _uuid.v4(),
            studentId: studentId,
            enrollmentId: Value(enrollmentId),
            feeTypeId: Value(feeTypeId),
            type: type,
            amount: amount,
            reason: Value(reason),
            date: date ?? now,
            status: Value(status),
            note: Value(note),
          ));
    } else {
      await (db.update(db.financialAdjustments)..where((t) => t.id.equals(id))).write(FinancialAdjustmentsCompanion(
            enrollmentId: Value(enrollmentId),
            feeTypeId: Value(feeTypeId),
            type: Value(type),
            amount: Value(amount),
            reason: Value(reason),
            date: Value(date ?? now),
            status: Value(status),
            note: Value(note),
            updatedAt: Value(now),
          ));
    }
  }

  Future<void> deleteAdjustment(String id) async {
    await (db.update(db.financialAdjustments)..where((t) => t.id.equals(id))).write(
      FinancialAdjustmentsCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())),
    );
  }

  Stream<double> watchTotalAdjustmentsForStudent(String studentId) {
    final q = db.selectOnly(db.financialAdjustments)..addColumns([db.financialAdjustments.amount.sum()]);
    q.where(db.financialAdjustments.isDeleted.equals(false) &
        db.financialAdjustments.status.equals('active') &
        db.financialAdjustments.studentId.equals(studentId));
    return q.watchSingle().map((row) => row.read(db.financialAdjustments.amount.sum()) ?? 0.0);
  }

  Stream<double> watchTotalPaidForStudent(String studentId) {
    final q = db.selectOnly(db.payments)..addColumns([db.payments.amount.sum()]);
    q.where(db.payments.isDeleted.equals(false) & db.payments.status.equals('valid') & db.payments.studentId.equals(studentId));
    return q.watchSingle().map((row) => row.read(db.payments.amount.sum()) ?? 0.0);
  }

  Future<double> expectedTotalForDate(DateTime date, {String? cashierUserId}) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final q = db.selectOnly(db.payments)..addColumns([db.payments.amount.sum()]);
    var where = db.payments.isDeleted.equals(false) &
        db.payments.status.equals('valid') &
        db.payments.paidAt.isBiggerOrEqualValue(start) &
        db.payments.paidAt.isSmallerThanValue(end);
    if (cashierUserId != null) where = where & db.payments.cashierUserId.equals(cashierUserId);
    q.where(where);
    final row = await q.getSingle();
    return row.read(db.payments.amount.sum()) ?? 0.0;
  }

  Future<bool> isDayClosed(DateTime date, {String? cashierUserId}) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final q = db.select(db.cashClosures)
      ..where((t) => t.isDeleted.equals(false) & t.closureDate.isBiggerOrEqualValue(start) & t.closureDate.isSmallerThanValue(end));
    if (cashierUserId != null) q.where((t) => t.cashierUserId.equals(cashierUserId));
    return (await q.get()).isNotEmpty;
  }

  Future<void> createCashClosure({
    required String cashierUserId,
    required DateTime date,
    required double countedAmount,
    String? note,
  }) async {
    final expected = await expectedTotalForDate(date, cashierUserId: cashierUserId);
    await db.into(db.cashClosures).insert(CashClosuresCompanion.insert(
          id: _uuid.v4(),
          cashierUserId: cashierUserId,
          closureDate: DateTime(date.year, date.month, date.day),
          expectedAmount: expected,
          countedAmount: countedAmount,
          difference: countedAmount - expected,
          note: Value(note),
        ));
  }
}
