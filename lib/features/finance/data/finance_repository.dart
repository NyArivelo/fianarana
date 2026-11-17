import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/affectation_scope.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_service.dart';

class PaymentRow {
  final String id;
  final String receipt;
  final String studentName;
  final String matricule;
  final String? classLabel;
  final String feeLabel;
  final int due;
  final int paid;
  final int balance;
  final DateTime? date;
  final String? method;
  final String? scheduleStatus;
  final String? closeStatus;

  PaymentRow({
    required this.id,
    required this.receipt,
    required this.studentName,
    required this.matricule,
    required this.classLabel,
    required this.feeLabel,
    required this.due,
    required this.paid,
    required this.balance,
    required this.date,
    required this.method,
    required this.scheduleStatus,
    required this.closeStatus,
  });
}

class UnauthorizedActionException implements Exception {
  final String permission;
  UnauthorizedActionException(this.permission);
  @override
  String toString() => 'Action non autorisée (permission requise: $permission)';
}

class FinanceRepository {
  final AppDatabase db;
  late final PermissionService _perm = PermissionService(db);
  late final AuditService _audit = AuditService(db);
  FinanceRepository(this.db);

  Future<void> _require(String? userId, String permission) async {
    if (userId == null || userId.isEmpty) return;
    if (!await _perm.userHasPermission(userId, permission)) {
      await _audit.log(userId: userId, module: 'Sécurité', targetObject: permission, description: 'Permission refusée: $permission', result: 'Échec');
      throw UnauthorizedActionException(permission);
    }
  }

  Future<bool> _isCashierScope(String? userId) async {
    if (userId == null || userId.isEmpty) return false;
    final u = await (db.select(db.users)..where((t) => t.id.equals(userId))).getSingleOrNull();
    return (u?.scopeType ?? '').toLowerCase().contains('caisse');
  }

  Future<List<PaymentRow>> listPayments({String? actorUserId, String? query, int limit = 500}) async {
    await _require(actorUserId, 'finance.read');
    final cashierOnly = await _isCashierScope(actorUserId);
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    if (scopeClasses != null && scopeClasses.isEmpty) return const <PaymentRow>[];
    final p = db.payments;
    final s = db.students;
    final c = db.classes;
    final j = db.select(p).join([
      innerJoin(s, s.id.equalsExp(p.studentId)),
      leftOuterJoin(c, c.id.equalsExp(p.classId)),
    ]);
    j.where(p.isDeleted.equals(false));
    if (cashierOnly) j.where(p.cashierUserId.equals(actorUserId!));
    if (scopeClasses != null) j.where(p.classId.isIn(scopeClasses));
    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      j.where(p.receiptNumber.like(q) | s.lastName.like(q) | s.firstName.like(q) | s.matricule.like(q));
    }
    j.orderBy([OrderingTerm.desc(p.paymentDate)]);
    j.limit(limit);
    final rows = await j.get();
    return rows.map((r) {
      final pay = r.readTable(p);
      final st = r.readTable(s);
      final cl = r.readTableOrNull(c);
      return PaymentRow(
        id: pay.id,
        receipt: pay.receiptNumber,
        studentName: '${st.lastName} ${st.firstName}',
        matricule: st.matricule,
        classLabel: cl?.label,
        feeLabel: pay.feeLabel,
        due: pay.amountDueMga,
        paid: pay.amountPaidMga,
        balance: pay.balanceMga,
        date: pay.paymentDate,
        method: pay.paymentMethod,
        scheduleStatus: pay.scheduleStatus,
        closeStatus: pay.cashCloseStatus,
      );
    }).toList();
  }

  Future<Map<String, int>> totals({String? actorUserId}) async {
    await _require(actorUserId, 'finance.read');
    final cashierOnly = await _isCashierScope(actorUserId);
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    if (scopeClasses != null && scopeClasses.isEmpty) return {'count': 0, 'due': 0, 'paid': 0, 'balance': 0};
    final q = db.select(db.payments)..where((t) => t.isDeleted.equals(false));
    if (cashierOnly) q.where((t) => t.cashierUserId.equals(actorUserId!));
    if (scopeClasses != null) q.where((t) => t.classId.isIn(scopeClasses));
    final rows = await q.get();
    var due = 0, paid = 0, bal = 0;
    for (final r in rows) {
      if (r.isDeleted) continue;
      due += r.amountDueMga;
      paid += r.amountPaidMga;
      bal += r.balanceMga;
    }
    return {'due': due, 'paid': paid, 'balance': bal, 'count': rows.where((r)=>!r.isDeleted).length};
  }

  Future<String> _nextReceiptNumber() async {
    final rows = await db.select(db.payments).get();
    var maxN = 0;
    for (final r in rows) {
      final m = RegExp(r'(\d+)$').firstMatch(r.receiptNumber);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > maxN) maxN = n;
      }
    }
    final next = maxN + 1;
    return 'REC-${DateTime.now().year}-${next.toString().padLeft(4, '0')}';
  }

  /// Encaissement: enregistre un paiement et génère un reçu numéroté.
  Future<String> recordPayment({
    required String studentId,
    String? classId,
    required String feeLabel,
    required int amountDueMga,
    required int amountPaidMga,
    DateTime? paymentDate,
    String? paymentMethod,
    String? scheduleStatus,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'finance.create');
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    if (scopeClasses != null) {
      String? effectiveClassId = classId;
      if (effectiveClassId == null || effectiveClassId.isEmpty) {
        final enr = await (db.select(db.enrollments)..where((t)=>t.studentId.equals(studentId) & t.isDeleted.equals(false))..orderBy([(t)=>OrderingTerm.desc(t.updatedAt)])).get();
        if (enr.isNotEmpty) effectiveClassId = enr.first.classId;
      }
      if (effectiveClassId == null || !scopeClasses.contains(effectiveClassId)) {
        throw StateError('Action non autorisée (portée affectations)');
      }
      classId = effectiveClassId;
    }
    final id = newUuid();
    final receipt = await _nextReceiptNumber();
    final balance = (amountDueMga - amountPaidMga).clamp(0, 1 << 30);
    final now = paymentDate ?? DateTime.now();
    await db.into(db.payments).insert(PaymentsCompanion.insert(
      id: Value(id),
      receiptNumber: receipt,
      studentId: studentId,
      classId: Value(classId),
      feeLabel: feeLabel,
      amountDueMga: Value(amountDueMga),
      amountPaidMga: Value(amountPaidMga),
      balanceMga: Value(balance),
      paymentDate: Value(now),
      paymentMethod: Value(paymentMethod),
      scheduleStatus: Value(scheduleStatus),
      cashierUserId: Value(actorUserId),
      cashCloseStatus: const Value('Ouvert'),
    ));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Finances', targetObject: receipt, description: 'Encaissement $amountPaidMga MGA ($feeLabel) élève $studentId', result: 'Succès', metadata: {'paymentId': id});
    return receipt;
  }

  Future<List<CashClosure>> listClosures({String? actorUserId, int limit = 50}) async {
    await _require(actorUserId, 'finance.read');
    final cashierOnly = await _isCashierScope(actorUserId);
    final q = db.select(db.cashClosures)..where((t) => t.isDeleted.equals(false));
    if (cashierOnly) q.where((t) => t.cashierUserId.equals(actorUserId!));
    q..orderBy([(t) => OrderingTerm.desc(t.closureDate)])..limit(limit);
    return q.get();
  }

  Future<List<PaymentSchedule>> listSchedules({String? actorUserId, bool overdueOnly = false}) async {
    await _require(actorUserId, 'finance.read');
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    if (scopeClasses != null && scopeClasses.isEmpty) return const <PaymentSchedule>[];
    final q = db.select(db.paymentSchedules)..where((t) => t.isDeleted.equals(false));
    if (scopeClasses != null) q.where((t) => t.classId.isIn(scopeClasses));
    if (overdueOnly) {
      q.where((t) => t.status.equals('En retard') | t.status.equals('Dû'));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.dueDate)]);
    return q.get();
  }

  Future<int> countOverdueSchedules({String? actorUserId}) async {
    await _require(actorUserId, 'finance.read');
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    if (scopeClasses != null && scopeClasses.isEmpty) return 0;
    final q = db.select(db.paymentSchedules)..where((t) => t.status.equals('En retard') & t.isDeleted.equals(false));
    if (scopeClasses != null) q.where((t) => t.classId.isIn(scopeClasses));
    final rows = await q.get();
    return rows.length;
  }

  /// Clôture de caisse (Z) journalière pour le caissier.
  Future<String> closeCashDesk({
    required String cashierUserId,
    DateTime? date,
    int totalCash = 0,
    int totalCheck = 0,
    int totalTransfer = 0,
    int totalMobileMoney = 0,
    String? notes,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'finance.close_cash_desk');
    final id = newUuid();
    final d = date ?? DateTime.now();
    await db.transaction(() async {
      await db.into(db.cashClosures).insert(CashClosuresCompanion.insert(
        id: Value(id),
        cashierUserId: cashierUserId,
        closureDate: d,
        totalCash: Value(totalCash),
        totalCheck: Value(totalCheck),
        totalTransfer: Value(totalTransfer),
        totalMobileMoney: Value(totalMobileMoney),
        status: const Value('Clôturé'),
        validatedByUserId: Value(actorUserId),
        notes: Value(notes),
      ));
      // marquer les paiements du jour/ouverts comme clôturés (simplifié)
      final start = DateTime(d.year, d.month, d.day);
      final end = start.add(const Duration(days: 1));
      await (db.update(db.payments)
            ..where((p) => p.cashCloseStatus.equals('Ouvert') & p.paymentDate.isBetweenValues(start, end)))
          .write(const PaymentsCompanion(cashCloseStatus: Value('Clôturé (Z-Caisse)')));
    });
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Finances', targetObject: id, description: 'Clôture de caisse (Z) caissier $cashierUserId', result: 'Succès');
    return id;
  }
}
