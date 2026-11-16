import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/security/permission_service.dart';
import 'package:fianarana/core/security/audit_service.dart';

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

  Future<List<PaymentRow>> listPayments({String? actorUserId, String? query, int limit = 300}) async {
    await _require(actorUserId, 'finance.read');
    final p = db.payments;
    final s = db.students;
    final c = db.classes;
    final j = db.select(p).join([
      innerJoin(s, s.id.equalsExp(p.studentId)),
      leftOuterJoin(c, c.id.equalsExp(p.classId)),
    ]);
    j.where(p.isDeleted.equals(false));
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
    final rows = await db.select(db.payments).get();
    var due = 0, paid = 0, bal = 0;
    for (final r in rows) {
      if (r.isDeleted) continue;
      due += r.amountDueMga;
      paid += r.amountPaidMga;
      bal += r.balanceMga;
    }
    return {'due': due, 'paid': paid, 'balance': bal, 'count': rows.where((r)=>!r.isDeleted).length};
  }
}
