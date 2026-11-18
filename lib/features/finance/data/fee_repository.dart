import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_service.dart';

class UnauthorizedActionException implements Exception {
  final String permission;
  UnauthorizedActionException(this.permission);
  @override
  String toString() => 'Action non autorisée (permission requise: $permission)';
}

/// Calcule le net à payer après remise, bourse et note de crédit.
/// Le net ne peut jamais être négatif.
int computeNetDue({
  required int amountDueMga,
  int discountMga = 0,
  int scholarshipMga = 0,
  int creditNoteMga = 0,
}) {
  final deductions = (discountMga < 0 ? 0 : discountMga) +
      (scholarshipMga < 0 ? 0 : scholarshipMga) +
      (creditNoteMga < 0 ? 0 : creditNoteMga);
  final net = amountDueMga - deductions;
  return net < 0 ? 0 : net;
}

/// Calcule la remise effective à partir d'un pourcentage borné [0..100].
int computePercentDiscount({required int amountMga, required double percent}) {
  if (amountMga <= 0 || percent <= 0) return 0;
  final bounded = percent > 100 ? 100.0 : percent;
  return (amountMga * bounded / 100).round();
}

class FeeRepository {
  final AppDatabase db;
  late final PermissionService _perm = PermissionService(db);
  late final AuditService _audit = AuditService(db);

  FeeRepository(this.db);

  Future<void> _require(String? userId, String permission) async {
    if (userId == null || userId.isEmpty) return;
    if (!await _perm.userHasPermission(userId, permission)) {
      await _audit.log(
        userId: userId,
        module: 'Sécurité',
        targetObject: permission,
        description: 'Permission refusée: $permission',
        result: 'Échec',
      );
      throw UnauthorizedActionException(permission);
    }
  }

  Future<void> _trace(String? userId, String? username, String description) {
    return _audit.log(
      userId: userId,
      username: username,
      module: 'Finances',
      targetObject: 'Catalogue de frais',
      description: description,
      result: 'Succès',
    );
  }

  // --- Catalogue de frais ---

  Future<List<FeeStructure>> listFees({String? schoolYearId}) {
    final q = db.select(db.feeStructures)..where((t) => t.isDeleted.equals(false));
    if (schoolYearId != null && schoolYearId.isNotEmpty) {
      q.where((t) => t.schoolYearId.equals(schoolYearId));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.label)]);
    return q.get();
  }

  Future<String> saveFee({
    String? id,
    String? schoolYearId,
    String? levelId,
    required String code,
    required String label,
    String category = 'Scolarité',
    required int amountMga,
    int installmentCount = 1,
    DateTime? dueDate,
    bool isMandatory = true,
    String status = 'Actif',
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, id == null ? 'fees.create' : 'fees.update');
    if (amountMga < 0) throw ArgumentError('Le montant ne peut pas être négatif.');
    final now = DateTime.now();
    if (id == null || id.isEmpty) {
      final feeId = newUuid();
      await db.into(db.feeStructures).insert(FeeStructuresCompanion.insert(
        id: Value(feeId),
        schoolYearId: Value(schoolYearId),
        levelId: Value(levelId),
        code: code.trim(),
        label: label.trim(),
        category: Value(category),
        amountMga: Value(amountMga),
        installmentCount: Value(installmentCount),
        dueDate: Value(dueDate),
        isMandatory: Value(isMandatory),
        status: Value(status),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      await _trace(actorUserId, actorUsername, 'Création frais ${label.trim()} ($amountMga MGA)');
      return feeId;
    }
    await (db.update(db.feeStructures)..where((t) => t.id.equals(id))).write(
      FeeStructuresCompanion(
        schoolYearId: Value(schoolYearId),
        levelId: Value(levelId),
        code: Value(code.trim()),
        label: Value(label.trim()),
        category: Value(category),
        amountMga: Value(amountMga),
        installmentCount: Value(installmentCount),
        dueDate: Value(dueDate),
        isMandatory: Value(isMandatory),
        status: Value(status),
        updatedAt: Value(now),
      ),
    );
    await _trace(actorUserId, actorUsername, 'Modification frais ${label.trim()}');
    return id;
  }

  Future<void> archiveFee({
    required String id,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'fees.delete');
    final now = DateTime.now();
    await (db.update(db.feeStructures)..where((t) => t.id.equals(id))).write(
      FeeStructuresCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await _trace(actorUserId, actorUsername, 'Archivage frais $id');
  }

  // --- Bourses / remises ---

  Future<List<StudentDiscount>> listDiscounts({String? studentId}) {
    final q = db.select(db.studentDiscounts)..where((t) => t.isDeleted.equals(false));
    if (studentId != null && studentId.isNotEmpty) {
      q.where((t) => t.studentId.equals(studentId));
    }
    q.orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return q.get();
  }

  Future<String> saveDiscount({
    String? id,
    required String studentId,
    String? schoolYearId,
    required String label,
    String type = 'Remise',
    int amountMga = 0,
    double percent = 0,
    String? reason,
    DateTime? validFrom,
    DateTime? validTo,
    String status = 'Actif',
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, id == null ? 'fees.create' : 'fees.update');
    if (amountMga < 0 || percent < 0) {
      throw ArgumentError('Le montant et le pourcentage doivent être positifs.');
    }
    final now = DateTime.now();
    if (id == null || id.isEmpty) {
      final discountId = newUuid();
      await db.into(db.studentDiscounts).insert(StudentDiscountsCompanion.insert(
        id: Value(discountId),
        studentId: studentId,
        schoolYearId: Value(schoolYearId),
        label: label.trim(),
        type: Value(type),
        amountMga: Value(amountMga),
        percent: Value(percent),
        reason: Value(reason),
        validFrom: Value(validFrom),
        validTo: Value(validTo),
        status: Value(status),
        approvedByUserId: Value(actorUserId),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      await _trace(actorUserId, actorUsername, 'Octroi $type ${label.trim()} à $studentId');
      return discountId;
    }
    await (db.update(db.studentDiscounts)..where((t) => t.id.equals(id))).write(
      StudentDiscountsCompanion(
        studentId: Value(studentId),
        schoolYearId: Value(schoolYearId),
        label: Value(label.trim()),
        type: Value(type),
        amountMga: Value(amountMga),
        percent: Value(percent),
        reason: Value(reason),
        validFrom: Value(validFrom),
        validTo: Value(validTo),
        status: Value(status),
        approvedByUserId: Value(actorUserId),
        updatedAt: Value(now),
      ),
    );
    await _trace(actorUserId, actorUsername, 'Modification $type ${label.trim()}');
    return id;
  }

  Future<void> archiveDiscount({
    required String id,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'fees.delete');
    final now = DateTime.now();
    await (db.update(db.studentDiscounts)..where((t) => t.id.equals(id))).write(
      StudentDiscountsCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await _trace(actorUserId, actorUsername, 'Archivage remise $id');
  }

  // --- Notes de crédit ---

  Future<List<CreditNote>> listCreditNotes({String? studentId}) {
    final q = db.select(db.creditNotes)..where((t) => t.isDeleted.equals(false));
    if (studentId != null && studentId.isNotEmpty) {
      q.where((t) => t.studentId.equals(studentId));
    }
    q.orderBy([(t) => OrderingTerm.desc(t.issuedDate)]);
    return q.get();
  }

  Future<String> issueCreditNote({
    required String studentId,
    String? receiptNumber,
    required int amountMga,
    required String reason,
    DateTime? issuedDate,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'fees.create');
    if (amountMga <= 0) throw ArgumentError('Le montant doit être supérieur à zéro.');
    final id = newUuid();
    final now = DateTime.now();
    await db.into(db.creditNotes).insert(CreditNotesCompanion.insert(
      id: Value(id),
      studentId: studentId,
      receiptNumber: Value(receiptNumber),
      amountMga: Value(amountMga),
      reason: reason.trim(),
      issuedDate: Value(issuedDate ?? now),
      status: const Value('Émise'),
      approvedByUserId: Value(actorUserId),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    await _trace(actorUserId, actorUsername, 'Note de crédit $amountMga MGA pour $studentId');
    return id;
  }

  Future<void> cancelCreditNote({
    required String id,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'fees.update');
    final now = DateTime.now();
    await (db.update(db.creditNotes)..where((t) => t.id.equals(id))).write(
      CreditNotesCompanion(
        status: const Value('Annulée'),
        updatedAt: Value(now),
      ),
    );
    await _trace(actorUserId, actorUsername, 'Annulation note de crédit $id');
  }
}
