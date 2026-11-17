import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/affectation_scope.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_service.dart';

/// Ligne du catalogue : ouvrage + prêt actif éventuel.
class LibraryCatalogueRow {
  final LibraryItem item;
  final String? loanId;
  final String? borrowerName;
  final String? borrowerMatricule;
  final DateTime? dueDate;
  final bool overdue;

  const LibraryCatalogueRow({
    required this.item,
    this.loanId,
    this.borrowerName,
    this.borrowerMatricule,
    this.dueDate,
    this.overdue = false,
  });

  bool get isBorrowed => loanId != null;

  String get statusLabel {
    if (!isBorrowed) return 'Disponible';
    if (overdue) return 'En retard';
    return 'Emprunté';
  }
}

/// Prêt enrichi (ouvrage, élève, classe, retard).
class LibraryLoanRow {
  final LibraryLoan loan;
  final String itemTitle;
  final String? copyCode;
  final String? borrowerName;
  final String? borrowerMatricule;
  final String? classLabel;
  final bool overdue;

  const LibraryLoanRow({
    required this.loan,
    required this.itemTitle,
    this.copyCode,
    this.borrowerName,
    this.borrowerMatricule,
    this.classLabel,
    this.overdue = false,
  });

  bool get isReturned => loan.returnDate != null;
}

/// Synthèse d'un élève pour le contrôle des quitus.
class LibraryQuitusRow {
  final String studentId;
  final String matricule;
  final String fullName;
  final String? classLabel;
  final int balanceMga;
  final int activeLoans;
  final int overdueLoans;
  final DateTime? nextDueDate;

  const LibraryQuitusRow({
    required this.studentId,
    required this.matricule,
    required this.fullName,
    this.classLabel,
    required this.balanceMga,
    required this.activeLoans,
    required this.overdueLoans,
    this.nextDueDate,
  });

  bool get financeOk => balanceMga <= 0;
  bool get libraryOk => overdueLoans == 0;
  bool get certificateReady => financeOk && libraryOk;
}

class LibraryStats {
  final int totalItems;
  final int available;
  final int borrowed;
  final int overdue;
  final int activeLoans;

  const LibraryStats({
    required this.totalItems,
    required this.available,
    required this.borrowed,
    required this.overdue,
    required this.activeLoans,
  });

  factory LibraryStats.empty() =>
      const LibraryStats(totalItems: 0, available: 0, borrowed: 0, overdue: 0, activeLoans: 0);
}

class UnauthorizedActionException implements Exception {
  final String permission;
  UnauthorizedActionException(this.permission);
  @override
  String toString() => 'Action non autorisée (permission requise: $permission)';
}

class LibraryRepository {
  final AppDatabase db;
  late final AuditService _audit = AuditService(db);
  late final PermissionService _perm = PermissionService(db);

  LibraryRepository(this.db);

  Future<void> _require(String? userId, String permission) async {
    if (userId == null || userId.isEmpty) return; // bootstrap/contexte système
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

  bool _isOverdue(DateTime? dueDate, DateTime now) =>
      dueDate != null && dueDate.isBefore(DateTime(now.year, now.month, now.day));

  Future<List<LibraryCatalogueRow>> listCatalogue({String? actorUserId}) async {
    await _require(actorUserId, 'library.read');
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    final scopedStudentIds = await _studentIdsInClasses(scopeClasses);
    final i = db.libraryItems;
    final l = db.libraryLoans;
    final s = db.students;
    final join = db.select(i).join([
      leftOuterJoin(
        l,
        l.itemId.equalsExp(i.id) &
            l.isDeleted.equals(false) &
            l.returnDate.isNull(),
      ),
      leftOuterJoin(s, s.id.equalsExp(l.borrowerStudentId)),
    ]);
    join.where(i.isDeleted.equals(false));
    join.orderBy([OrderingTerm.asc(i.title)]);

    final now = DateTime.now();
    final rows = await join.get();
    return rows.map((r) {
      final item = r.readTable(i);
      final loan = r.readTableOrNull(l);
      final student = r.readTableOrNull(s);
      final borrowerInScope = scopedStudentIds == null || (loan?.borrowerStudentId != null && scopedStudentIds.contains(loan!.borrowerStudentId));
      final showBorrower = loan != null && borrowerInScope;
      return LibraryCatalogueRow(
        item: item,
        loanId: showBorrower ? loan.id : null,
        borrowerName: showBorrower && student != null ? '${student.lastName} ${student.firstName}' : null,
        borrowerMatricule: showBorrower ? student?.matricule : null,
        dueDate: showBorrower ? loan.dueDate : null,
        overdue: showBorrower && _isOverdue(loan.dueDate, now),
      );
    }).toList();
  }

  Future<List<LibraryLoanRow>> listLoans({String? actorUserId}) async {
    await _require(actorUserId, 'library.read');
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    final scopedStudentIds = await _studentIdsInClasses(scopeClasses);
    if (scopeClasses != null && scopedStudentIds.isEmpty) return const <LibraryLoanRow>[];
    final l = db.libraryLoans;
    final i = db.libraryItems;
    final s = db.students;
    final join = db.select(l).join([
      innerJoin(i, i.id.equalsExp(l.itemId)),
      leftOuterJoin(s, s.id.equalsExp(l.borrowerStudentId)),
    ]);
    join.where(l.isDeleted.equals(false));
    if (scopedStudentIds != null) {
      join.where(l.borrowerStudentId.isIn(scopedStudentIds));
    }
    join.orderBy([OrderingTerm.asc(l.returnDate), OrderingTerm.asc(l.dueDate)]);
    final rows = await join.get();

    final classByStudent = await _classLabelsByStudent();
    final now = DateTime.now();
    return rows.map((r) {
      final loan = r.readTable(l);
      final item = r.readTable(i);
      final student = r.readTableOrNull(s);
      return LibraryLoanRow(
        loan: loan,
        itemTitle: item.title,
        copyCode: item.copyCode,
        borrowerName: student == null ? loan.borrowerRef : '${student.lastName} ${student.firstName}',
        borrowerMatricule: student?.matricule ?? loan.borrowerRef,
        classLabel: loan.borrowerStudentId == null ? null : classByStudent[loan.borrowerStudentId],
        overdue: loan.returnDate == null && _isOverdue(loan.dueDate, now),
      );
    }).toList();
  }

  Future<Set<String>?> _studentIdsInClasses(Set<String>? scopeClasses) async {
    if (scopeClasses == null) return null;
    if (scopeClasses.isEmpty) return <String>{};
    final rows = await (db.select(db.enrollments)
          ..where((e) => e.isDeleted.equals(false) & e.classId.isIn(scopeClasses)))
        .get();
    return rows.map((e) => e.studentId).toSet();
  }

  Future<LibraryStats> stats({String? actorUserId}) async {
    await _require(actorUserId, 'library.read');
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    final scopedStudentIds = await _studentIdsInClasses(scopeClasses);
    final items = await (db.select(db.libraryItems)
          ..where((t) => t.isDeleted.equals(false)))
        .get();
    final q = db.select(db.libraryLoans)..where((t) => t.isDeleted.equals(false) & t.returnDate.isNull());
    if (scopedStudentIds != null) {
      if (scopedStudentIds.isEmpty) {
        return LibraryStats(totalItems: items.length, available: items.length, borrowed: 0, overdue: 0, activeLoans: 0);
      }
      q.where((t) => t.borrowerStudentId.isIn(scopedStudentIds));
    }
    final loans = await q.get();
    final now = DateTime.now();
    final overdue = loans.where((l) => _isOverdue(l.dueDate, now)).length;
    final borrowed = loans.length;
    return LibraryStats(
      totalItems: items.length,
      available: (items.length - borrowed).clamp(0, 1 << 30),
      borrowed: borrowed,
      overdue: overdue,
      activeLoans: borrowed,
    );
  }

  /// Élèves avec prêts actifs (ou tous si [includeAll]).
  Future<List<LibraryQuitusRow>> quitusRows({
    String? actorUserId,
    bool includeAll = false,
  }) async {
    await _require(actorUserId, 'students.read');
    final scopeClasses = await AffectationScope(db).allowedClassIdsForUser(actorUserId);
    final scopedStudentIds = await _studentIdsInClasses(scopeClasses);
    if (scopeClasses != null && scopedStudentIds.isEmpty) return const <LibraryQuitusRow>[];
    final q = db.select(db.students)..where((t) => t.isDeleted.equals(false));
    if (scopedStudentIds != null) q.where((t) => t.id.isIn(scopedStudentIds));
    q.orderBy([(t) => OrderingTerm.asc(t.lastName)]);
    final students = await q.get();
    if (students.isEmpty) return const [];

    final classByStudent = await _classLabelsByStudent();
    final ids = students.map((s) => s.id).toList();

    final payments = await (db.select(db.payments)
          ..where((p) => p.studentId.isIn(ids) & p.isDeleted.equals(false)))
        .get();
    final balances = <String, int>{};
    for (final p in payments) {
      balances[p.studentId] =
          (balances[p.studentId] ?? 0) + p.amountDueMga - p.amountPaidMga;
    }

    final loans = await (db.select(db.libraryLoans)
          ..where((l) =>
              l.borrowerStudentId.isIn(ids) &
              l.isDeleted.equals(false) &
              l.returnDate.isNull()))
        .get();
    final now = DateTime.now();
    final activeByStudent = <String, int>{};
    final overdueByStudent = <String, int>{};
    final nextDueByStudent = <String, DateTime>{};
    for (final loan in loans) {
      final studentId = loan.borrowerStudentId;
      if (studentId == null) continue;
      activeByStudent[studentId] = (activeByStudent[studentId] ?? 0) + 1;
      if (_isOverdue(loan.dueDate, now)) {
        overdueByStudent[studentId] = (overdueByStudent[studentId] ?? 0) + 1;
      }
      final due = loan.dueDate;
      if (due != null && studentId.isNotEmpty) {
        final current = nextDueByStudent[studentId];
        if (current == null || due.isBefore(current)) nextDueByStudent[studentId] = due;
      }
    }

    final rows = <LibraryQuitusRow>[];
    for (final s in students) {
      final active = activeByStudent[s.id] ?? 0;
      final overdue = overdueByStudent[s.id] ?? 0;
      if (!includeAll && active == 0) continue;
      rows.add(LibraryQuitusRow(
        studentId: s.id,
        matricule: s.matricule,
        fullName: '${s.lastName} ${s.firstName}',
        classLabel: classByStudent[s.id],
        balanceMga: balances[s.id] ?? 0,
        activeLoans: active,
        overdueLoans: overdue,
        nextDueDate: nextDueByStudent[s.id],
      ));
    }
    rows.sort((a, b) {
      if (a.overdueLoans != b.overdueLoans) return b.overdueLoans.compareTo(a.overdueLoans);
      return a.fullName.compareTo(b.fullName);
    });
    return rows;
  }

  Future<Map<String, String>> _classLabelsByStudent() async {
    final e = db.enrollments;
    final c = db.classes;
    final join = db.select(e).join([
      innerJoin(c, c.id.equalsExp(e.classId)),
    ]);
    join.where(e.isDeleted.equals(false));
    final rows = await join.get();
    final map = <String, String>{};
    for (final r in rows) {
      final enrollment = r.readTable(e);
      final cl = r.readTableOrNull(c);
      if (cl != null) map.putIfAbsent(enrollment.studentId, () => cl.label);
    }
    return map;
  }

  /// Enregistre le retour d'un ouvrage et libère l'exemplaire.
  Future<void> returnLoan({
    required String loanId,
    required String itemId,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'library.update');
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.libraryLoans)..where((t) => t.id.equals(loanId))).write(
        LibraryLoansCompanion(
          returnDate: Value(now),
          status: const Value('Retourné'),
          updatedAt: Value(now),
        ),
      );
      await (db.update(db.libraryItems)..where((t) => t.id.equals(itemId))).write(
        LibraryItemsCompanion(
          availability: const Value('Disponible'),
          updatedAt: Value(now),
        ),
      );
    });
    await _audit.log(
      userId: actorUserId,
      username: actorUsername,
      module: 'Bibliothèque',
      targetObject: loanId,
      description: 'Retour d\'ouvrage enregistré',
      result: 'Succès',
    );
  }

  /// Crée un prêt et marque l'exemplaire comme emprunté.
  Future<String> createLoan({
    required String itemId,
    required String studentId,
    required DateTime dueDate,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'library.create');
    final id = newUuid();
    final now = DateTime.now();
    await db.transaction(() async {
      await db.into(db.libraryLoans).insert(LibraryLoansCompanion.insert(
        id: Value(id),
        itemId: itemId,
        borrowerStudentId: Value(studentId),
        startDate: now,
        dueDate: Value(dueDate),
        status: const Value('En cours'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      await (db.update(db.libraryItems)..where((t) => t.id.equals(itemId))).write(
        LibraryItemsCompanion(
          availability: const Value('Emprunté'),
          updatedAt: Value(now),
        ),
      );
    });
    await _audit.log(
      userId: actorUserId,
      username: actorUsername,
      module: 'Bibliothèque',
      targetObject: id,
      description: 'Nouveau prêt d\'ouvrage',
      result: 'Succès',
    );
    return id;
  }

  /// Ajoute un ouvrage au catalogue.
  Future<String> addItem({
    required String title,
    String? codeOrIsbn,
    String? authorOrCategory,
    String? copyCode,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'library.create');
    final id = newUuid();
    await db.into(db.libraryItems).insert(LibraryItemsCompanion.insert(
      id: Value(id),
      domain: const Value('Bibliothèque'),
      codeOrIsbn: Value(codeOrIsbn),
      title: title,
      authorOrCategory: Value(authorOrCategory),
      copyCode: Value(copyCode),
      availability: const Value('Disponible'),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    ));
    await _audit.log(
      userId: actorUserId,
      username: actorUsername,
      module: 'Bibliothèque',
      targetObject: id,
      description: 'Ajout ouvrage: $title',
      result: 'Succès',
    );
    return id;
  }
}
