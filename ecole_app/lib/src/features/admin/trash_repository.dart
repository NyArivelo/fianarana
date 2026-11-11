import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

class TrashItem {
  final String entityType;
  final String id;
  final String label;
  final DateTime? deletedAt;
  final String? extra;
  TrashItem({required this.entityType, required this.id, required this.label, this.deletedAt, this.extra});
}

class TrashRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  TrashRepository(this.db);

  Future<List<TrashItem>> listAll() async {
    final items = <TrashItem>[];
    Future<void> addStudents() async {
      for (final r in await (db.select(db.students)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'student', id: r.id, label: '${r.lastName} ${r.firstName} (${r.matricule})', deletedAt: r.deletedAt, extra: r.status));
      }
    }
    Future<void> addGuardians() async {
      for (final r in await (db.select(db.guardians)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'guardian', id: r.id, label: '${r.lastName} ${r.firstName}', deletedAt: r.deletedAt));
      }
    }
    Future<void> addEnrollments() async {
      for (final r in await (db.select(db.enrollments)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'enrollment', id: r.id, label: 'Inscription ${r.id.substring(0,8)}', deletedAt: r.deletedAt, extra: r.status));
      }
    }
    Future<void> addClasses() async {
      for (final r in await (db.select(db.classes)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'class', id: r.id, label: r.name, deletedAt: r.deletedAt));
      }
    }
    Future<void> addSubjects() async {
      for (final r in await (db.select(db.subjects)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'subject', id: r.id, label: r.name, deletedAt: r.deletedAt));
      }
    }
    Future<void> addLevels() async {
      for (final r in await (db.select(db.levels)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'level', id: r.id, label: r.name, deletedAt: r.deletedAt));
      }
    }
    Future<void> addEduTypes() async {
      for (final r in await (db.select(db.educationTypes)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'educationType', id: r.id, label: r.name, deletedAt: r.deletedAt));
      }
    }
    Future<void> addRooms() async {
      for (final r in await (db.select(db.rooms)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'room', id: r.id, label: r.name, deletedAt: r.deletedAt));
      }
    }
    Future<void> addFeeTypes() async {
      for (final r in await (db.select(db.feeTypes)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'feeType', id: r.id, label: r.name, deletedAt: r.deletedAt));
      }
    }
    Future<void> addSessions() async {
      for (final r in await (db.select(db.courseSessions)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'session', id: r.id, label: r.title ?? 'Séance ${r.startAt}', deletedAt: r.deletedAt, extra: r.status));
      }
    }
    Future<void> addEvals() async {
      for (final r in await (db.select(db.evaluations)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'evaluation', id: r.id, label: r.title, deletedAt: r.deletedAt));
      }
    }
    Future<void> addPayments() async {
      for (final r in await (db.select(db.payments)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'payment', id: r.id, label: '${r.receiptNumber} (${r.amount})', deletedAt: r.deletedAt, extra: r.status));
      }
    }
    Future<void> addPlans() async {
      for (final r in await (db.select(db.paymentPlans)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'paymentPlan', id: r.id, label: r.name, deletedAt: r.deletedAt, extra: r.status));
      }
    }
    Future<void> addAssignments() async {
      for (final r in await (db.select(db.teacherAssignments)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'teacherAssignment', id: r.id, label: 'Affectation ${r.id.substring(0,8)}', deletedAt: r.deletedAt));
      }
    }
    Future<void> addYears() async {
      for (final r in await (db.select(db.academicYears)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'academicYear', id: r.id, label: r.label, deletedAt: r.deletedAt));
      }
    }
    Future<void> addPeriods() async {
      for (final r in await (db.select(db.periods)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'period', id: r.id, label: r.name, deletedAt: r.deletedAt));
      }
    }
    Future<void> addStaff() async {
      for (final r in await (db.select(db.staffMembers)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'staffMember', id: r.id, label: '${r.lastName} ${r.firstName}', deletedAt: r.deletedAt, extra: r.staffType));
      }
    }
    Future<void> addDisciplineIncidents() async {
      for (final r in await (db.select(db.disciplinaryIncidents)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'disciplinaryIncident', id: r.id, label: '${r.incidentType} (${r.incidentDate.toIso8601String().substring(0,10)})', deletedAt: r.deletedAt, extra: r.status));
      }
    }
    Future<void> addDisciplineActions() async {
      for (final r in await (db.select(db.disciplinaryActions)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'disciplinaryAction', id: r.id, label: '${r.actionType} (${r.executionStatus})', deletedAt: r.deletedAt));
      }
    }
    Future<void> addLibraryItems() async {
      for (final r in await (db.select(db.libraryItems)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'libraryItem', id: r.id, label: r.title, deletedAt: r.deletedAt));
      }
    }
    Future<void> addLibraryCopies() async {
      for (final r in await (db.select(db.libraryCopies)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'libraryCopy', id: r.id, label: r.copyCode, deletedAt: r.deletedAt, extra: r.status));
      }
    }
    Future<void> addLibraryLoans() async {
      for (final r in await (db.select(db.libraryLoans)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'libraryLoan', id: r.id, label: 'Prêt ${r.id.substring(0,8)}', deletedAt: r.deletedAt, extra: r.status));
      }
    }
    Future<void> addDocumentTemplates() async {
      for (final r in await (db.select(db.documentTemplates)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'documentTemplate', id: r.id, label: r.name, deletedAt: r.deletedAt, extra: r.category));
      }
    }
    Future<void> addFinancialAdjustments() async {
      for (final r in await (db.select(db.financialAdjustments)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'financialAdjustment', id: r.id, label: '${r.type} ${r.amount}', deletedAt: r.deletedAt, extra: r.status));
      }
    }
    Future<void> addEquipmentItems() async {
      for (final r in await (db.select(db.equipmentItems)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'equipmentItem', id: r.id, label: r.name, deletedAt: r.deletedAt, extra: r.status));
      }
    }
    Future<void> addRoomReservations() async {
      for (final r in await (db.select(db.roomReservations)..where((t) => t.isDeleted.equals(true))).get()) {
        items.add(TrashItem(entityType: 'roomReservation', id: r.id, label: r.title, deletedAt: r.deletedAt, extra: r.status));
      }
    }
    await Future.wait([addStudents(), addGuardians(), addEnrollments(), addClasses(), addSubjects(), addLevels(), addEduTypes(), addRooms(), addFeeTypes(), addSessions(), addEvals(), addPayments(), addPlans(), addAssignments(), addYears(), addPeriods(), addStaff(), addDisciplineIncidents(), addDisciplineActions(), addLibraryItems(), addLibraryCopies(), addLibraryLoans(), addDocumentTemplates(), addFinancialAdjustments(), addEquipmentItems(), addRoomReservations()]);
    items.sort((a,b)=> (b.deletedAt ?? DateTime(2000)).compareTo(a.deletedAt ?? DateTime(2000)));
    return items;
  }

  Future<void> restore(TrashItem item) async {
    final now = DateTime.now();
    switch (item.entityType) {
      case 'student': await (db.update(db.students)..where((t)=>t.id.equals(item.id))).write(StudentsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now), status: const Value('active'))); break;
      case 'guardian': await (db.update(db.guardians)..where((t)=>t.id.equals(item.id))).write(GuardiansCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'enrollment': await (db.update(db.enrollments)..where((t)=>t.id.equals(item.id))).write(EnrollmentsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'class': await (db.update(db.classes)..where((t)=>t.id.equals(item.id))).write(ClassesCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'subject': await (db.update(db.subjects)..where((t)=>t.id.equals(item.id))).write(SubjectsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'level': await (db.update(db.levels)..where((t)=>t.id.equals(item.id))).write(LevelsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'educationType': await (db.update(db.educationTypes)..where((t)=>t.id.equals(item.id))).write(EducationTypesCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'room': await (db.update(db.rooms)..where((t)=>t.id.equals(item.id))).write(RoomsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'feeType': await (db.update(db.feeTypes)..where((t)=>t.id.equals(item.id))).write(FeeTypesCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'session': await (db.update(db.courseSessions)..where((t)=>t.id.equals(item.id))).write(CourseSessionsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'evaluation': await (db.update(db.evaluations)..where((t)=>t.id.equals(item.id))).write(EvaluationsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'payment': await (db.update(db.payments)..where((t)=>t.id.equals(item.id))).write(PaymentsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'paymentPlan': await (db.update(db.paymentPlans)..where((t)=>t.id.equals(item.id))).write(PaymentPlansCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'teacherAssignment': await (db.update(db.teacherAssignments)..where((t)=>t.id.equals(item.id))).write(TeacherAssignmentsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'academicYear': await (db.update(db.academicYears)..where((t)=>t.id.equals(item.id))).write(AcademicYearsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'period': await (db.update(db.periods)..where((t)=>t.id.equals(item.id))).write(PeriodsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'staffMember': await (db.update(db.staffMembers)..where((t)=>t.id.equals(item.id))).write(StaffMembersCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'disciplinaryIncident': await (db.update(db.disciplinaryIncidents)..where((t)=>t.id.equals(item.id))).write(DisciplinaryIncidentsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'disciplinaryAction': await (db.update(db.disciplinaryActions)..where((t)=>t.id.equals(item.id))).write(DisciplinaryActionsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'libraryItem': await (db.update(db.libraryItems)..where((t)=>t.id.equals(item.id))).write(LibraryItemsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'libraryCopy': await (db.update(db.libraryCopies)..where((t)=>t.id.equals(item.id))).write(LibraryCopiesCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'libraryLoan': await (db.update(db.libraryLoans)..where((t)=>t.id.equals(item.id))).write(LibraryLoansCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'documentTemplate': await (db.update(db.documentTemplates)..where((t)=>t.id.equals(item.id))).write(DocumentTemplatesCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'financialAdjustment': await (db.update(db.financialAdjustments)..where((t)=>t.id.equals(item.id))).write(FinancialAdjustmentsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'equipmentItem': await (db.update(db.equipmentItems)..where((t)=>t.id.equals(item.id))).write(EquipmentItemsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      case 'roomReservation': await (db.update(db.roomReservations)..where((t)=>t.id.equals(item.id))).write(RoomReservationsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now))); break;
      default: throw Exception('Type non supporté: ${item.entityType}');
    }
    await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(id: _uuid.v4(), timestamp: DateTime.now().toUtc(), module: 'trash', action: 'restore', targetType: Value(item.entityType), targetId: Value(item.id), details: Value(item.label)));
  }

  Future<void> purge(TrashItem item) async {
    switch (item.entityType) {
      case 'student': await (db.delete(db.students)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'guardian': await (db.delete(db.guardians)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'enrollment': await (db.delete(db.enrollments)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'class': await (db.delete(db.classes)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'subject': await (db.delete(db.subjects)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'level': await (db.delete(db.levels)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'educationType': await (db.delete(db.educationTypes)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'room': await (db.delete(db.rooms)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'feeType': await (db.delete(db.feeTypes)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'session': await (db.delete(db.courseSessions)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'evaluation': await (db.delete(db.evaluations)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'payment': await (db.delete(db.payments)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'paymentPlan': await (db.delete(db.paymentPlans)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'teacherAssignment': await (db.delete(db.teacherAssignments)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'academicYear': await (db.delete(db.academicYears)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'period': await (db.delete(db.periods)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'staffMember': await (db.delete(db.staffMembers)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'disciplinaryIncident': await (db.delete(db.disciplinaryIncidents)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'disciplinaryAction': await (db.delete(db.disciplinaryActions)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'libraryItem': await (db.delete(db.libraryItems)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'libraryCopy': await (db.delete(db.libraryCopies)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'libraryLoan': await (db.delete(db.libraryLoans)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'documentTemplate': await (db.delete(db.documentTemplates)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'financialAdjustment': await (db.delete(db.financialAdjustments)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'equipmentItem': await (db.delete(db.equipmentItems)..where((t)=>t.id.equals(item.id))).go(); break;
      case 'roomReservation': await (db.delete(db.roomReservations)..where((t)=>t.id.equals(item.id))).go(); break;
      default: throw Exception('Type non supporté: ${item.entityType}');
    }
    await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(id: _uuid.v4(), timestamp: DateTime.now().toUtc(), module: 'trash', action: 'purge', targetType: Value(item.entityType), targetId: Value(item.id), details: Value(item.label)));
  }

  Future<int> purgeOlderThanDays(int days) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final all = await listAll();
    int count = 0;
    for (final it in all) {
      if (it.deletedAt != null && it.deletedAt!.isBefore(cutoff)) {
        try { await purge(it); count++; } catch (_) {}
      }
    }
    return count;
  }
}
