import 'package:drift/drift.dart';

/// Base mixin-like pattern: all main entities use UUID v4 primary keys.
mixin UuidPrimaryKey on Table {
  TextColumn get id => text().clientDefault(() => '')(); // set via UUID in app layer/companion
  @override
  Set<Column> get primaryKey => {id};
}

mixin AuditColumns on Table {
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

class Establishments extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get code => text().unique()();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get logoPath => text().nullable()();
  TextColumn get motto => text().nullable()();
  TextColumn get timezone => text().withDefault(const Constant('Indian/Antananarivo'))();
  TextColumn get currency => text().withDefault(const Constant('MGA'))();
  TextColumn get dateFormat => text().withDefault(const Constant('dd/MM/yyyy'))();
  TextColumn get timeFormat => text().withDefault(const Constant('HH:mm'))();
  TextColumn get legalMentions => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('Actif'))();
}

class SchoolYears extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get establishmentId => text().references(Establishments, #id)();
  TextColumn get code => text()();
  TextColumn get label => text()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  TextColumn get status => text().withDefault(const Constant('En cours'))(); // En cours, Clôturée, Planifiée
  @override
  List<Set<Column>> get uniqueKeys => [{establishmentId, code}];
}

class Periods extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get schoolYearId => text().references(SchoolYears, #id)();
  TextColumn get name => text()(); // Trimestre 1, Semestre 1...
  IntColumn get sequence => integer().withDefault(const Constant(1))();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get isClosed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get closedByUserId => text().nullable()();
}

class Roles extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get name => text().unique()();
  TextColumn get description => text().nullable()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
}

class Permissions extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get code => text().unique()(); // e.g. students.read
  TextColumn get module => text()();
  TextColumn get action => text()(); // read/create/update/archive/validate/reject/publish/cancel/export/print/delete
  TextColumn get description => text().nullable()();
}

class RolePermissions extends Table {
  TextColumn get roleId => text().references(Roles, #id)();
  TextColumn get permissionId => text().references(Permissions, #id)();
  @override
  Set<Column> get primaryKey => {roleId, permissionId};
}

class Users extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get username => text().unique()();
  TextColumn get fullName => text()();
  TextColumn get email => text().nullable()();
  TextColumn get passwordHash => text()();
  TextColumn get pinHash => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastLoginAt => dateTime().nullable()();
  IntColumn get failedLoginCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lockedUntil => dateTime().nullable()();
  TextColumn get scopeType => text().withDefault(const Constant('Globale'))(); // Globale, Affectations, Caisse
  TextColumn get scopeRefId => text().nullable()();
  BoolColumn get mustChangePassword => boolean().withDefault(const Constant(false))();
}

class UserRoles extends Table {
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get roleId => text().references(Roles, #id)();
  @override
  Set<Column> get primaryKey => {userId, roleId};
}

// --- Academic structure ---
class Levels extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get name => text()(); // 3ème, 2nde...
  TextColumn get cycle => text().nullable()(); // Secondaire de niveau 2/3 etc.
  TextColumn get track => text().nullable()(); // Tronc commun, Série L/S
  IntColumn get sequence => integer().withDefault(const Constant(0))();
}

class Classes extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get schoolYearId => text().nullable().references(SchoolYears, #id)();
  TextColumn get levelId => text().nullable().references(Levels, #id)();
  TextColumn get code => text().nullable()();
  TextColumn get label => text()(); // 3ème 1
  IntColumn get capacity => integer().nullable()();
  TextColumn get room => text().nullable()();
}

class Subjects extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get code => text().unique()();
  TextColumn get name => text()();
  RealColumn get coefficientSec2 => real().withDefault(const Constant(1.0))();
  RealColumn get coefficientSec3 => real().withDefault(const Constant(1.0))();
  TextColumn get domain => text().nullable()();
}

// --- People ---
class Guardians extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get lastName => text()();
  TextColumn get firstName => text()();
  TextColumn get relationship => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get occupation => text().nullable()();
  TextColumn get nationalId => text().nullable()(); // CIN / ID
}

class Students extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get matricule => text().unique()();
  TextColumn get lastName => text()();
  TextColumn get firstName => text()();
  TextColumn get sex => text().nullable()();
  DateTimeColumn get birthDate => dateTime().nullable()();
  TextColumn get birthPlace => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('Actif'))(); // Actif, Transféré/Radiation, etc.
  TextColumn get photoPath => text().nullable()();
  TextColumn get photoHash => text().nullable()();
  TextColumn get medicalNotes => text().nullable()();
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
  TextColumn get schoolYearId => text().nullable().references(SchoolYears, #id)();
  TextColumn get classId => text().nullable().references(Classes, #id)();
  TextColumn get status => text().withDefault(const Constant('Validée'))(); // Préinscription, Validée, Suspendue...
  DateTimeColumn get enrollmentDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get exitDate => dateTime().nullable()();
  TextColumn get exitReason => text().nullable()();
  BoolColumn get financeClearance => boolean().withDefault(const Constant(false))();
  BoolColumn get libraryClearance => boolean().withDefault(const Constant(false))();
}

class StaffMembers extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get userId => text().nullable().references(Users, #id)();
  TextColumn get staffNumber => text().unique()();
  TextColumn get lastName => text()();
  TextColumn get firstName => text()();
  TextColumn get sex => text().nullable()();
  TextColumn get functionTitle => text().nullable()(); // Enseignante, Caissier...
  TextColumn get departmentOrSubject => text().nullable()();
  TextColumn get contractType => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('Actif'))();
}

class TeacherAssignments extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get staffId => text().references(StaffMembers, #id)();
  TextColumn get classId => text().references(Classes, #id)();
  TextColumn get subjectId => text().nullable().references(Subjects, #id)();
  TextColumn get schoolYearId => text().nullable().references(SchoolYears, #id)();
}

// --- Evaluations ---
class Evaluations extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get studentId => text().references(Students, #id)();
  TextColumn get periodId => text().nullable().references(Periods, #id)();
  TextColumn get subjectId => text().nullable().references(Subjects, #id)();
  TextColumn get classId => text().nullable().references(Classes, #id)();
  TextColumn get label => text()(); // DS1, Composition...
  RealColumn get score => real().nullable()();
  RealColumn get maxScore => real().withDefault(const Constant(20.0))();
  RealColumn get coefficient => real().withDefault(const Constant(1.0))();
  BoolColumn get isExempt => boolean().withDefault(const Constant(false))();
  TextColumn get observation => text().nullable()();
  TextColumn get validationStatus => text().withDefault(const Constant('Brouillon'))(); // Brouillon, Validée
}

/// Conseils de classe / délibérations par classe et période.
class ClassCouncils extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get classId => text().references(Classes, #id)();
  TextColumn get periodId => text().references(Periods, #id)();
  DateTimeColumn get councilDate => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('Préparation'))(); // Préparation, Validé, Verrouillé
  TextColumn get globalAppreciation => text().nullable()();
  TextColumn get validatedByUserId => text().nullable()();
  DateTimeColumn get validatedAt => dateTime().nullable()();
}

/// Décisions individuelles de conseil de classe.
class CouncilDecisions extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get councilId => text().references(ClassCouncils, #id)();
  TextColumn get studentId => text().references(Students, #id)();
  TextColumn get decision => text().nullable()(); // Passage, Redoublement, Avertissement travail, Félicitations...
  TextColumn get appreciation => text().nullable()();
  RealColumn get average => real().nullable()();
  IntColumn get rank => integer().nullable()();
  TextColumn get mention => text().nullable()();
}

// --- Attendance & Discipline ---
class AttendanceEvents extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get category => text()(); // Appel / Présence, Discipline
  TextColumn get studentId => text().references(Students, #id)();
  TextColumn get classId => text().nullable().references(Classes, #id)();
  DateTimeColumn get date => dateTime()();
  TextColumn get slotOrFacts => text().nullable()();
  TextColumn get status => text()(); // Présent, Absent, Retard, Incident...
  TextColumn get justificationOrSanction => text().nullable()();
  TextColumn get details => text().nullable()();
  TextColumn get authorUserId => text().nullable().references(Users, #id)();
}

// --- Finance ---
class Payments extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get receiptNumber => text().unique()();
  TextColumn get studentId => text().references(Students, #id)();
  TextColumn get classId => text().nullable().references(Classes, #id)();
  TextColumn get feeLabel => text()();
  IntColumn get amountDueMga => integer().withDefault(const Constant(0))();
  IntColumn get amountPaidMga => integer().withDefault(const Constant(0))();
  IntColumn get balanceMga => integer().withDefault(const Constant(0))();
  DateTimeColumn get paymentDate => dateTime().nullable()();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get scheduleStatus => text().nullable()();
  TextColumn get cashierUserId => text().nullable().references(Users, #id)();
  TextColumn get cashCloseStatus => text().nullable()();
}

/// Échéanciers / plans de paiement
class PaymentSchedules extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get studentId => text().references(Students, #id)();
  TextColumn get classId => text().nullable().references(Classes, #id)();
  TextColumn get label => text()();
  IntColumn get totalAmountMga => integer().withDefault(const Constant(0))();
  IntColumn get installmentCount => integer().withDefault(const Constant(1))();
  DateTimeColumn get dueDate => dateTime().nullable()();
  IntColumn get amountDueMga => integer().withDefault(const Constant(0))();
  IntColumn get amountPaidMga => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('À venir'))(); // À venir, Dû, En retard, Payé
}

class CashClosures extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get cashierUserId => text().references(Users, #id)();
  DateTimeColumn get closureDate => dateTime()();
  IntColumn get totalCash => integer().withDefault(const Constant(0))();
  IntColumn get totalCheck => integer().withDefault(const Constant(0))();
  IntColumn get totalTransfer => integer().withDefault(const Constant(0))();
  IntColumn get totalMobileMoney => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('Ouvert'))(); // Ouvert, Clôturé
  TextColumn get validatedByUserId => text().nullable().references(Users, #id)();
  TextColumn get notes => text().nullable()();
}

// --- Library & Facilities ---
class LibraryItems extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get domain => text().withDefault(const Constant('Bibliothèque'))();
  TextColumn get codeOrIsbn => text().nullable()();
  TextColumn get title => text()();
  TextColumn get authorOrCategory => text().nullable()();
  TextColumn get copyCode => text().nullable()();
  TextColumn get availability => text().withDefault(const Constant('Disponible'))();
}

class LibraryLoans extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get itemId => text().references(LibraryItems, #id)();
  TextColumn get borrowerStudentId => text().nullable().references(Students, #id)();
  TextColumn get borrowerRef => text().nullable()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get returnDate => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('En cours'))(); // En cours, Retourné, En retard
}

class Facilities extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get domain => text()(); // Salle, Matériel
  TextColumn get code => text().nullable()();
  TextColumn get name => text()();
  TextColumn get category => text().nullable()();
  IntColumn get capacity => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('Disponible'))();
}

// --- Timetabling / Sessions (emploi du temps) ---
class TimetableSessions extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get classId => text().nullable().references(Classes, #id)();
  TextColumn get subjectId => text().nullable().references(Subjects, #id)();
  TextColumn get teacherId => text().nullable().references(StaffMembers, #id)();
  TextColumn get roomId => text().nullable().references(Facilities, #id)();
  TextColumn get dayOfWeek => text()(); // Lundi..Samedi
  TextColumn get startTime => text()(); // HH:mm
  TextColumn get endTime => text()(); // HH:mm
  TextColumn get recurrence => text().withDefault(const Constant('Hebdomadaire'))();
  DateTimeColumn get date => dateTime().nullable()(); // occurrence datée
  BoolColumn get isSubstitution => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
}

// --- Audit log ---
class AuditLogs extends Table {
  TextColumn get id => text()(); // UUID
  DateTimeColumn get timestampUtc => dateTime()();
  TextColumn get userId => text().nullable()();
  TextColumn get username => text().nullable()();
  TextColumn get module => text()();
  TextColumn get targetObject => text().nullable()();
  TextColumn get description => text()();
  TextColumn get result => text().withDefault(const Constant('Succès'))();
  TextColumn get hashSha256 => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();
  @override
  Set<Column> get primaryKey => {key};
}

class BackupRecords extends Table with UuidPrimaryKey, AuditColumns {
  TextColumn get filePath => text()();
  DateTimeColumn get createdAtBackup => dateTime()();
  TextColumn get type => text().withDefault(const Constant('manuel'))(); // manuel, auto, fermeture
  TextColumn get checksum => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('ok'))();
}
