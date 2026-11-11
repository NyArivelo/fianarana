import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

class LibraryRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  LibraryRepository(this.db);

  // Catalog
  Stream<List<LibraryItem>> watchItems({String query = ''}) {
    final q = db.select(db.libraryItems)..where((t)=>t.isDeleted.equals(false));
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim()}%';
      q.where((t)=>t.title.like(like) | t.author.like(like) | t.isbn.like(like) | t.category.like(like));
    }
    q.orderBy([(t)=>OrderingTerm.asc(t.title)]);
    return q.watch();
  }

  Future<String> upsertItem({String? id, required String title, String? author, String? isbn, String? category, String? publisher, String? publicationYear, String? description}) async {
    final now = DateTime.now();
    if (id == null) {
      final nid = _uuid.v4();
      await db.into(db.libraryItems).insert(LibraryItemsCompanion.insert(id: nid, title: title, author: Value(author), isbn: Value(isbn), category: Value(category), publisher: Value(publisher), publicationYear: Value(publicationYear), description: Value(description)));
      return nid;
    }
    await (db.update(db.libraryItems)..where((t)=>t.id.equals(id))).write(LibraryItemsCompanion(title: Value(title), author: Value(author), isbn: Value(isbn), category: Value(category), publisher: Value(publisher), publicationYear: Value(publicationYear), description: Value(description), updatedAt: Value(now)));
    return id;
  }

  Future<void> deleteItem(String id) async {
    await (db.update(db.libraryItems)..where((t)=>t.id.equals(id))).write(LibraryItemsCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())));
  }

  // Copies
  Stream<List<LibraryCopy>> watchCopies(String itemId) {
    return (db.select(db.libraryCopies)..where((t)=>t.itemId.equals(itemId) & t.isDeleted.equals(false))..orderBy([(t)=>OrderingTerm.asc(t.copyCode)])).watch();
  }

  Future<void> upsertCopy({String? id, required String itemId, required String copyCode, String status = 'available', String? locationNote}) async {
    final now = DateTime.now();
    if (id == null) {
      await db.into(db.libraryCopies).insert(LibraryCopiesCompanion.insert(id: _uuid.v4(), itemId: itemId, copyCode: copyCode, status: Value(status), locationNote: Value(locationNote)));
    } else {
      await (db.update(db.libraryCopies)..where((t)=>t.id.equals(id))).write(LibraryCopiesCompanion(copyCode: Value(copyCode), status: Value(status), locationNote: Value(locationNote), updatedAt: Value(now)));
    }
  }

  Future<void> deleteCopy(String id) async {
    await (db.update(db.libraryCopies)..where((t)=>t.id.equals(id))).write(LibraryCopiesCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())));
  }

  // Loans
  Stream<List<LibraryLoan>> watchLoans({String? studentId, String? status}) {
    final q = db.select(db.libraryLoans)..where((t)=>t.isDeleted.equals(false));
    if (studentId != null && studentId.isNotEmpty) q.where((t)=>t.studentId.equals(studentId));
    if (status != null && status.isNotEmpty) q.where((t)=>t.status.equals(status));
    q.orderBy([(t)=>OrderingTerm.desc(t.loanDate)]);
    return q.watch();
  }

  Future<void> refreshOverdue() async {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final active = await (db.select(db.libraryLoans)..where((t)=>t.isDeleted.equals(false) & t.status.equals('active'))).get();
    for (final l in active) {
      if (l.dueDate.isBefore(today)) {
        await (db.update(db.libraryLoans)..where((t)=>t.id.equals(l.id))).write(const LibraryLoansCompanion(status: Value('overdue')));
      }
    }
  }

  Future<void> borrow({required String copyId, required String studentId, required DateTime dueDate, String? notes}) async {
    final now = DateTime.now();
    await db.transaction(() async {
      await db.into(db.libraryLoans).insert(LibraryLoansCompanion.insert(id: _uuid.v4(), copyId: copyId, studentId: studentId, loanDate: now, dueDate: dueDate, status: const Value('active'), notes: Value(notes)));
      await (db.update(db.libraryCopies)..where((t)=>t.id.equals(copyId))).write(LibraryCopiesCompanion(status: const Value('borrowed'), updatedAt: Value(now)));
    });
  }

  Future<void> returnLoan(String loanId, {String copyStatus = 'available', String? notes}) async {
    final loan = await (db.select(db.libraryLoans)..where((t)=>t.id.equals(loanId))).getSingle();
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.libraryLoans)..where((t)=>t.id.equals(loanId))).write(LibraryLoansCompanion(status: const Value('returned'), returnDate: Value(now), notes: Value(notes ?? loan.notes), updatedAt: Value(now)));
      await (db.update(db.libraryCopies)..where((t)=>t.id.equals(loan.copyId))).write(LibraryCopiesCompanion(status: Value(copyStatus), updatedAt: Value(now)));
    });
  }

  Future<bool> hasUnreturnedLoans(String studentId) async {
    final rows = await (db.select(db.libraryLoans)..where((t)=>t.studentId.equals(studentId) & t.isDeleted.equals(false) & t.status.isIn(['active','overdue']))).get();
    return rows.isNotEmpty;
  }

  Stream<List<LibraryLoan>> watchActiveLoansForStudent(String studentId) {
    return (db.select(db.libraryLoans)..where((t)=>t.studentId.equals(studentId) & t.isDeleted.equals(false) & t.status.isIn(['active','overdue']))).watch();
  }
}
