import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/affectation_scope.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_service.dart';
import 'package:fianarana/features/finance/data/fee_repository.dart';

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
  final int netDue;
  final int discount;
  final int scholarship;
  final int creditNote;
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
    this.netDue = 0,
    this.discount = 0,
    this.scholarship = 0,
    this.creditNote = 0,
    required this.date,
    required this.method,
    required this.scheduleStatus,
    required this.closeStatus,
  });
}

/// Ligne du grand livre : compte élève (brut dû, réductions, net, encaissé).
class LedgerRow {
  final String id;
  final String receipt;
  final String studentId;
  final String studentName;
  final String matricule;
  final String? classLabel;
  final String feeLabel;
  final DateTime date;
  final int grossDue;
  final int discount;
  final int scholarship;
  final int creditNote;
  final int netDue;
  final int paid;
  final int balance;

  const LedgerRow({
    required this.id,
    required this.receipt,
    required this.studentId,
    required this.studentName,
    required this.matricule,
    required this.classLabel,
    required this.feeLabel,
    required this.date,
    required this.grossDue,
    required this.discount,
    required this.scholarship,
    required this.creditNote,
    required this.netDue,
    required this.paid,
    required this.balance,
  });

  int get reductions => discount + scholarship + creditNote;
  bool get isSettled => balance <= 0;
}

class ScheduleRow {
  final PaymentSchedule schedule;
  final String? studentName;
  final String? matricule;
  final String? classLabel;
  ScheduleRow({required this.schedule, this.studentName, this.matricule, this.classLabel});
}

class FinanceReport {
  final int totalDue;
  final int totalPaid;
  final int totalBalance;
  final int paymentsCount;
  final int overdueSchedules;
  final int dueSchedules;
  final Map<String, int> paidByMethod;
  FinanceReport({
    required this.totalDue,
    required this.totalPaid,
    required this.totalBalance,
    required this.paymentsCount,
    required this.overdueSchedules,
    required this.dueSchedules,
    required this.paidByMethod,
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
        netDue: pay.netDueMga > 0 ? pay.netDueMga : pay.amountDueMga,
        discount: pay.discountMga,
        scholarship: pay.scholarshipMga,
        creditNote: pay.creditNoteMga,
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
      due += r.netDueMga > 0 ? r.netDueMga : r.amountDueMga;
      paid += r.amountPaidMga;
      bal += r.balanceMga;
    }
    return {'due': due, 'paid': paid, 'balance': bal, 'count': rows.length};
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

  Future<String> recordPayment({
    required String studentId,
    String? classId,
    required String feeLabel,
    required int amountDueMga,
    required int amountPaidMga,
    int discountMga = 0,
    int scholarshipMga = 0,
    int creditNoteMga = 0,
    String? discountReason,
    String? feeStructureId,
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
    final netDue = computeNetDue(
      amountDueMga: amountDueMga,
      discountMga: discountMga,
      scholarshipMga: scholarshipMga,
      creditNoteMga: creditNoteMga,
    );
    final balance = (netDue - amountPaidMga).clamp(0, 1 << 30);
    final now = paymentDate ?? DateTime.now();
    await db.into(db.payments).insert(PaymentsCompanion.insert(
      id: Value(id),
      receiptNumber: receipt,
      studentId: studentId,
      classId: Value(classId),
      feeLabel: feeLabel,
      feeStructureId: Value(feeStructureId),
      amountDueMga: Value(amountDueMga),
      discountMga: Value(discountMga),
      scholarshipMga: Value(scholarshipMga),
      creditNoteMga: Value(creditNoteMga),
      netDueMga: Value(netDue),
      discountReason: Value(discountReason),
      amountPaidMga: Value(amountPaidMga),
      balanceMga: Value(balance),
      paymentDate: Value(now),
      paymentMethod: Value(paymentMethod),
      scheduleStatus: Value(scheduleStatus),
      cashierUserId: Value(actorUserId),
      cashCloseStatus: const Value('Ouvert'),
    ));
    await _audit.log(
      userId: actorUserId,
      username: actorUsername,
      module: 'Finances',
      targetObject: receipt,
      description: 'Encaissement $amountPaidMga MGA ($feeLabel) élève $studentId'
          '${discountMga + scholarshipMga + creditNoteMga > 0 ? ' — remises ${discountMga + scholarshipMga + creditNoteMga} MGA' : ''}',
      result: 'Succès',
      metadata: {'paymentId': id, 'netDue': netDue},
    );
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

  // --- Échéanciers & relances ---

  Future<List<ScheduleRow>> listScheduleRows({String? actorUserId, bool overdueOnly = false, String? statusFilter}) async {
    await _require(actorUserId, 'finance.read');
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    if (scopeClasses != null && scopeClasses.isEmpty) return const <ScheduleRow>[];
    final ps = db.paymentSchedules;
    final s = db.students;
    final c = db.classes;
    final j = db.select(ps).join([
      leftOuterJoin(s, s.id.equalsExp(ps.studentId)),
      leftOuterJoin(c, c.id.equalsExp(ps.classId)),
    ])..where(ps.isDeleted.equals(false));
    if (scopeClasses != null) j.where(ps.classId.isIn(scopeClasses));
    if (overdueOnly) {
      j.where(ps.status.like('%retard%') | ps.status.equals('Dû') | ps.status.equals('Du'));
    }
    if (statusFilter != null && statusFilter.isNotEmpty && statusFilter != 'Tous') {
      j.where(ps.status.equals(statusFilter));
    }
    j.orderBy([OrderingTerm.asc(ps.dueDate), OrderingTerm.asc(ps.label)]);
    final rows = await j.get();
    return rows.map((r) {
      final sch = r.readTable(ps);
      final st = r.readTableOrNull(s);
      final cl = r.readTableOrNull(c);
      return ScheduleRow(
        schedule: sch,
        studentName: st == null ? null : '${st.lastName} ${st.firstName}',
        matricule: st?.matricule,
        classLabel: cl?.label,
      );
    }).toList();
  }

  Future<List<PaymentSchedule>> listSchedules({String? actorUserId, bool overdueOnly = false}) async {
    final rows = await listScheduleRows(actorUserId: actorUserId, overdueOnly: overdueOnly);
    return rows.map((r) => r.schedule).toList();
  }

  Future<int> countOverdueSchedules({String? actorUserId}) async {
    await _require(actorUserId, 'finance.read');
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    if (scopeClasses != null && scopeClasses.isEmpty) return 0;
    final q = db.select(db.paymentSchedules)..where((t) => (t.status.equals('En retard') | t.status.like('%retard%')) & t.isDeleted.equals(false));
    if (scopeClasses != null) q.where((t) => t.classId.isIn(scopeClasses));
    final rows = await q.get();
    return rows.length;
  }

  String _computeScheduleStatus({required int due, required int paid, DateTime? dueDate, String? currentStatus}) {
    if (paid >= due && due > 0) return 'Payé';
    final now = DateTime.now();
    final isOver = dueDate != null && DateTime(dueDate.year, dueDate.month, dueDate.day).isBefore(DateTime(now.year, now.month, now.day));
    if (isOver && paid < due) {
      if ((currentStatus ?? '').toLowerCase().contains('relanc')) return 'En retard (relancé)';
      return 'En retard';
    }
    if (paid > 0 && paid < due) return 'Partiel';
    return dueDate == null ? 'À venir' : (isOver ? 'Dû' : 'À venir');
  }

  Future<String> saveSchedule({
    String? id,
    required String studentId,
    String? classId,
    required String label,
    required int amountDueMga,
    int amountPaidMga = 0,
    int installmentCount = 1,
    int? totalAmountMga,
    DateTime? dueDate,
    String? status,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'finance.update');
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
    final sid = id ?? newUuid();
    final computedStatus = status ?? _computeScheduleStatus(due: amountDueMga, paid: amountPaidMga, dueDate: dueDate);
    final now = DateTime.now();
    await db.into(db.paymentSchedules).insertOnConflictUpdate(PaymentSchedulesCompanion.insert(
      id: Value(sid),
      studentId: studentId,
      classId: Value(classId),
      label: label,
      totalAmountMga: Value(totalAmountMga ?? amountDueMga),
      installmentCount: Value(installmentCount),
      dueDate: Value(dueDate),
      amountDueMga: Value(amountDueMga),
      amountPaidMga: Value(amountPaidMga),
      status: Value(computedStatus),
      updatedAt: Value(now),
      createdAt: Value(now),
    ));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Finances', targetObject: sid, description: '${id == null ? "Création" : "Mise à jour"} échéancier "$label" élève $studentId', result: 'Succès');
    return sid;
  }

  Future<void> updateScheduleStatus(String scheduleId, String status, {String? actorUserId, String? actorUsername}) async {
    await _require(actorUserId, 'finance.update');
    await (db.update(db.paymentSchedules)..where((t) => t.id.equals(scheduleId))).write(PaymentSchedulesCompanion(status: Value(status), updatedAt: Value(DateTime.now())));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Finances', targetObject: scheduleId, description: 'Statut échéancier mis à jour: $status', result: 'Succès');
  }

  Future<void> markRelance(String scheduleId, {String? actorUserId, String? actorUsername}) async {
    await _require(actorUserId, 'finance.update');
    final row = await (db.select(db.paymentSchedules)..where((t) => t.id.equals(scheduleId))).getSingleOrNull();
    if (row == null) return;
    final status = row.amountPaidMga >= row.amountDueMga ? 'Payé' : 'En retard (relancé)';
    await (db.update(db.paymentSchedules)..where((t) => t.id.equals(scheduleId))).write(PaymentSchedulesCompanion(status: Value(status), updatedAt: Value(DateTime.now())));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Finances', targetObject: scheduleId, description: 'Relance enregistrée pour échéancier', result: 'Succès');
  }

  /// Cohérence: recalcule le statut des échéanciers selon dates/montants.
  Future<int> refreshScheduleStatuses({String? actorUserId, String? actorUsername}) async {
    await _require(actorUserId, 'finance.update');
    final rows = await (db.select(db.paymentSchedules)..where((t) => t.isDeleted.equals(false))).get();
    var n = 0;
    for (final r in rows) {
      final computed = _computeScheduleStatus(due: r.amountDueMga, paid: r.amountPaidMga, dueDate: r.dueDate, currentStatus: r.status);
      if (computed != r.status) {
        await (db.update(db.paymentSchedules)..where((t) => t.id.equals(r.id))).write(PaymentSchedulesCompanion(status: Value(computed), updatedAt: Value(DateTime.now())));
        n++;
      }
    }
    if (n > 0) {
      await _audit.log(userId: actorUserId, username: actorUsername, module: 'Finances', targetObject: 'payment_schedules', description: 'Recalcul statuts échéanciers ($n mis à jour)', result: 'Succès');
    }
    return n;
  }

  Future<int> countOverdue() async => countOverdueSchedules();

  // --- Caisse / rapports ---

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
      final start = DateTime(d.year, d.month, d.day);
      final end = start.add(const Duration(days: 1));
      await (db.update(db.payments)
            ..where((p) => p.cashCloseStatus.equals('Ouvert') & p.paymentDate.isBetweenValues(start, end)))
          .write(const PaymentsCompanion(cashCloseStatus: Value('Clôturé (Z-Caisse)')));
    });
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Finances', targetObject: id, description: 'Clôture de caisse (Z) caissier $cashierUserId', result: 'Succès');
    return id;
  }

  /// Rapport/cohérence financier (vue synthèse).
  /// Grand livre détaillé : toutes les écritures de compte élève sur une période.
  Future<List<LedgerRow>> ledger({
    String? actorUserId,
    DateTime? from,
    DateTime? to,
    String? query,
    String? classId,
  }) async {
    await _require(actorUserId, 'finance.read');
    final cashierOnly = await _isCashierScope(actorUserId);
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    if (scopeClasses != null && scopeClasses.isEmpty) return const <LedgerRow>[];

    final p = db.payments;
    final s = db.students;
    final c = db.classes;

    Future<Set<String>> studentsEnrolledIn(Iterable<String> classIds) async {
      final ids = classIds.toSet();
      if (ids.isEmpty) return const <String>{};
      final rows = await (db.select(db.enrollments)
            ..where((e) => e.isDeleted.equals(false) & e.classId.isIn(ids)))
          .get();
      return rows.map((e) => e.studentId).toSet();
    }

    final j = db.select(p).join([
      innerJoin(s, s.id.equalsExp(p.studentId)),
      leftOuterJoin(c, c.id.equalsExp(p.classId)),
    ])..where(p.isDeleted.equals(false));
    if (cashierOnly) j.where(p.cashierUserId.equals(actorUserId!));
    if (scopeClasses != null) {
      final scopeStudents = await studentsEnrolledIn(scopeClasses);
      j.where(p.classId.isIn(scopeClasses) | p.studentId.isIn(scopeStudents));
    }
    if (classId != null && classId.isNotEmpty) {
      final classStudents = await studentsEnrolledIn({classId});
      j.where(p.classId.equals(classId) | p.studentId.isIn(classStudents));
    }
    if (from != null) j.where(p.paymentDate.isBiggerOrEqualValue(from));
    if (to != null) j.where(p.paymentDate.isSmallerOrEqualValue(to));
    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      j.where(p.receiptNumber.like(q) |
          s.lastName.like(q) |
          s.firstName.like(q) |
          s.matricule.like(q) |
          p.feeLabel.like(q));
    }
    j.orderBy([OrderingTerm.asc(p.paymentDate), OrderingTerm.asc(p.receiptNumber)]);
    final rows = await j.get();

    // Complète la classe depuis l'inscription de l'élève quand le paiement
    // ne porte pas directement de classe (données historiques/import).
    final missingStudentIds = <String>{};
    for (final r in rows) {
      if (r.readTableOrNull(c) == null) {
        missingStudentIds.add(r.readTable(s).id);
      }
    }
    final classByStudent = <String, String>{};
    if (missingStudentIds.isNotEmpty) {
      final enr = db.enrollments;
      final enrQuery = db.select(enr).join([
        innerJoin(c, c.id.equalsExp(enr.classId)),
      ])
        ..where(enr.isDeleted.equals(false) & enr.studentId.isIn(missingStudentIds))
        ..orderBy([OrderingTerm.desc(enr.enrollmentDate)]);
      for (final row in await enrQuery.get()) {
        classByStudent.putIfAbsent(row.readTable(enr).studentId, () => row.readTable(c).label);
      }
    }

    return rows.map((r) {
      final pay = r.readTable(p);
      final st = r.readTable(s);
      final cl = r.readTableOrNull(c);
      final net = pay.netDueMga > 0 ? pay.netDueMga : pay.amountDueMga;
      return LedgerRow(
        id: pay.id,
        receipt: pay.receiptNumber,
        studentId: st.id,
        studentName: '${st.lastName} ${st.firstName}',
        matricule: st.matricule,
        classLabel: cl?.label ?? classByStudent[st.id],
        feeLabel: pay.feeLabel,
        date: pay.paymentDate ?? pay.createdAt,
        grossDue: pay.amountDueMga,
        discount: pay.discountMga,
        scholarship: pay.scholarshipMga,
        creditNote: pay.creditNoteMga,
        netDue: net,
        paid: pay.amountPaidMga,
        balance: pay.balanceMga,
      );
    }).toList();
  }

  Future<FinanceReport> report({String? actorUserId}) async {
    final t = await totals(actorUserId: actorUserId);
    final allSchedules = await listScheduleRows(actorUserId: actorUserId);
    int overdue = 0, dueCount = 0;
    for (final r in allSchedules) {
      final st = r.schedule.status.toLowerCase();
      if (st.contains('retard')) overdue++;
      if (st == 'dû' || st == 'du' || st.contains('retard')) dueCount++;
    }
    // encaissé par mode (sur paiements visibles)
    final cashierOnly = await _isCashierScope(actorUserId);
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    final q = db.select(db.payments)..where((p) => p.isDeleted.equals(false));
    if (cashierOnly) q.where((p) => p.cashierUserId.equals(actorUserId!));
    if (scopeClasses != null) {
      if (scopeClasses.isEmpty) {
        return FinanceReport(totalDue: 0, totalPaid: 0, totalBalance: 0, paymentsCount: 0, overdueSchedules: overdue, dueSchedules: dueCount, paidByMethod: const {});
      }
      q.where((p) => p.classId.isIn(scopeClasses));
    }
    final pays = await q.get();
    final byMethod = <String, int>{};
    for (final p in pays) {
      final m = (p.paymentMethod == null || p.paymentMethod!.trim().isEmpty) ? 'Autre' : p.paymentMethod!;
      byMethod[m] = (byMethod[m] ?? 0) + p.amountPaidMga;
    }
    return FinanceReport(
      totalDue: t['due'] ?? 0,
      totalPaid: t['paid'] ?? 0,
      totalBalance: t['balance'] ?? 0,
      paymentsCount: t['count'] ?? 0,
      overdueSchedules: overdue,
      dueSchedules: dueCount,
      paidByMethod: byMethod,
    );
  }
}
