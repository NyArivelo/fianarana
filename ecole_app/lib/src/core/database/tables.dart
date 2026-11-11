import 'package:drift/drift.dart';
import 'uuid_table.dart';

// --- Security & Users ---
class Users extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get username => text().unique()();
  TextColumn get passwordHash => text()();
  TextColumn get displayName => text()();
  TextColumn get email => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get mustChangePassword =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastLoginAt => dateTime().nullable()();
  IntColumn get failedLoginAttempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get lockedUntil => dateTime().nullable()();
}

class Roles extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get name => text().unique()();
  TextColumn get description => text().nullable()();
  TextColumn get scope => text().withDefault(const Constant('global'))(); // global, restricted, caisse
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
}

class Permissions extends Table with UuidPrimaryKey {
  TextColumn get code => text().unique()(); // e.g. students.read
  TextColumn get module => text()();
  TextColumn get action => text()();
  TextColumn get description => text().nullable()();
}

class RolePermissions extends Table {
  TextColumn get roleId => text().references(Roles, #id)();
  TextColumn get permissionId => text().references(Permissions, #id)();
  @override
  Set<Column> get primaryKey => {roleId, permissionId};
}

class UserRoles extends Table {
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get roleId => text().references(Roles, #id)();
  @override
  Set<Column> get primaryKey => {userId, roleId};
}

class AuditLogs extends Table with UuidPrimaryKey {
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get userId => text().nullable()();
  TextColumn get username => text().nullable()();
  TextColumn get module => text()();
  TextColumn get action => text()();
  TextColumn get targetType => text().nullable()();
  TextColumn get targetId => text().nullable()();
  TextColumn get details => text().nullable()(); // JSON
  TextColumn get result => text().withDefault(const Constant('success'))();
}

// --- School & Settings ---
class SchoolSettings extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get logoPath => text().nullable()();
  TextColumn get motto => text().nullable()();
  TextColumn get timezone => text().withDefault(const Constant('UTC'))();
  TextColumn get dateFormat => text().withDefault(const Constant('dd/MM/yyyy'))();
  TextColumn get timeFormat => text().withDefault(const Constant('HH:mm'))();
  TextColumn get legalMentions => text().nullable()();
  BoolColumn get isConfigured => boolean().withDefault(const Constant(false))();
}

class AcademicYears extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get label => text()(); // e.g. 2025-2026
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  BoolColumn get isCurrent => boolean().withDefault(const Constant(false))();
  BoolColumn get isClosed => boolean().withDefault(const Constant(false))();
}

class Periods extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get academicYearId => text().references(AcademicYears, #id)();
  TextColumn get name => text()(); // Trimestre 1, Semestre 1...
  IntColumn get orderIndex => integer().withDefault(const Constant(1))();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get isClosed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get closedBy => text().nullable()();
}

// --- Pedagogical structure ---
class EducationTypes extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
}

class Levels extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get educationTypeId =>
      text().nullable().references(EducationTypes, #id)();
  TextColumn get name => text()();
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();
}

class Classes extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get academicYearId => text().references(AcademicYears, #id)();
  TextColumn get levelId => text().nullable().references(Levels, #id)();
  TextColumn get name => text()();
  IntColumn get capacity => integer().nullable()();
}

class Subjects extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get name => text()();
  TextColumn get code => text().nullable()();
  RealColumn get defaultCoefficient =>
      real().withDefault(const Constant(1.0))();
}

// --- People ---
class Students extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get matricule => text().unique()();
  TextColumn get firstName => text()();
  TextColumn get lastName => text()();
  TextColumn get gender => text().nullable()();
  DateTimeColumn get birthDate => dateTime().nullable()();
  TextColumn get birthPlace => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get notes => text().nullable()();
}

class Guardians extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get firstName => text()();
  TextColumn get lastName => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get relation => text().nullable()();
}

class StudentGuardians extends Table {
  TextColumn get studentId => text().references(Students, #id)();
  TextColumn get guardianId => text().references(Guardians, #id)();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {studentId, guardianId};
}

class Enrollments extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get studentId => text().references(Students, #id)();
  TextColumn get academicYearId => text().references(AcademicYears, #id)();
  TextColumn get classId => text().nullable().references(Classes, #id)();
  TextColumn get status => text().withDefault(const Constant('preinscription'))();
  DateTimeColumn get enrolledAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get quitusFinancial => text().withDefault(const Constant('pending'))();
  TextColumn get quitusLibrary => text().withDefault(const Constant('pending'))();
  DateTimeColumn get transferDate => dateTime().nullable()();
  TextColumn get transferReason => text().nullable()();
}

// --- Finance basics ---
class FeeTypes extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  RealColumn get defaultAmount => real().withDefault(const Constant(0.0))();
}

class Payments extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get receiptNumber => text().unique()();
  TextColumn get studentId => text().references(Students, #id)();
  TextColumn get enrollmentId => text().nullable().references(Enrollments, #id)();
  TextColumn get feeTypeId => text().nullable().references(FeeTypes, #id)();
  TextColumn get installmentId =>
      text().nullable().references(PaymentInstallments, #id)();
  RealColumn get amount => real()();
  TextColumn get method => text().withDefault(const Constant('cash'))();
  DateTimeColumn get paidAt => dateTime()();
  TextColumn get cashierUserId => text().nullable().references(Users, #id)();
  TextColumn get status => text().withDefault(const Constant('valid'))();
  TextColumn get note => text().nullable()();
}

class CashClosures extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get cashierUserId => text().references(Users, #id)();
  DateTimeColumn get closureDate => dateTime()();
  RealColumn get expectedAmount => real()();
  RealColumn get countedAmount => real()();
  RealColumn get difference => real()();
  TextColumn get note => text().nullable()();
}

// --- Payment schedules / installments ---
class PaymentPlans extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get studentId => text().references(Students, #id)();
  TextColumn get enrollmentId => text().nullable().references(Enrollments, #id)();
  TextColumn get feeTypeId => text().nullable().references(FeeTypes, #id)();
  TextColumn get name => text()();
  RealColumn get totalAmount => real()();
  TextColumn get status => text().withDefault(const Constant('active'))(); // active, completed, cancelled
}

class PaymentInstallments extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get planId => text().references(PaymentPlans, #id)();
  IntColumn get sequence => integer().withDefault(const Constant(1))();
  DateTimeColumn get dueDate => dateTime()();
  RealColumn get amount => real()();
  RealColumn get paidAmount => real().withDefault(const Constant(0.0))();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending, partial, paid, overdue
}

// --- Timetable & Attendance ---
class Rooms extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get name => text()();
  TextColumn get location => text().nullable()();
  IntColumn get capacity => integer().nullable()();
}

class CourseSessions extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get academicYearId => text().nullable().references(AcademicYears, #id)();
  TextColumn get classId => text().nullable().references(Classes, #id)();
  TextColumn get subjectId => text().nullable().references(Subjects, #id)();
  TextColumn get roomId => text().nullable().references(Rooms, #id)();
  TextColumn get teacherName => text().nullable()();
  TextColumn get title => text().nullable()();
  TextColumn get courseType => text().withDefault(const Constant('regular'))(); // regular, evening, weekend, intensive
  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime()();
  TextColumn get status => text().withDefault(const Constant('planned'))(); // planned, done, cancelled
  TextColumn get notes => text().nullable()();
}

class AttendanceRecords extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get sessionId => text().references(CourseSessions, #id)();
  TextColumn get studentId => text().references(Students, #id)();
  TextColumn get status => text().withDefault(const Constant('present'))(); // present, absent, late, excused
  TextColumn get note => text().nullable()();
}

// --- Evaluations & Grades ---
class Evaluations extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get academicYearId => text().nullable().references(AcademicYears, #id)();
  TextColumn get periodId => text().nullable().references(Periods, #id)();
  TextColumn get classId => text().references(Classes, #id)();
  TextColumn get subjectId => text().references(Subjects, #id)();
  TextColumn get title => text()();
  RealColumn get coefficient => real().withDefault(const Constant(1.0))();
  RealColumn get maxScore => real().withDefault(const Constant(20.0))();
  DateTimeColumn get date => dateTime().nullable()();
}

class Grades extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get evaluationId => text().references(Evaluations, #id)();
  TextColumn get studentId => text().references(Students, #id)();
  RealColumn get score => real().nullable()();
  BoolColumn get isAbsent => boolean().withDefault(const Constant(false))();
  BoolColumn get isExempt => boolean().withDefault(const Constant(false))(); // dispense/neutralized
  TextColumn get comment => text().nullable()();
}

class CouncilDecisions extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get periodId => text().references(Periods, #id)();
  TextColumn get classId => text().references(Classes, #id)();
  TextColumn get studentId => text().references(Students, #id)();
  TextColumn get appreciation => text().nullable()();
  TextColumn get decision => text().nullable()(); // passage, redoublement, avertissement, felicitations, etc.
}
