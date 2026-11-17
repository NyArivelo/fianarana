import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/security/audit_service.dart';

class DeletedEntry {
  final String entity;
  final String id;
  final String label;
  final DateTime? deletedAt;
  DeletedEntry(this.entity, this.id, this.label, this.deletedAt);
}

/// Corbeille : suppression logique (isDeleted) exhaustive sur les entités métier,
/// rétention configurable, restauration/purge avec traçabilité.
class RecycleBinService {
  final AppDatabase db;
  late final AuditService _audit = AuditService(db);
  RecycleBinService(this.db);

  static const allEntityTypes = <String>[
    'Établissements',
    'Années scolaires',
    'Périodes',
    'Rôles',
    'Permissions',
    'Utilisateurs',
    'Niveaux',
    'Classes',
    'Matières',
    'Responsables',
    'Élèves',
    'Liens élève-responsable',
    'Inscriptions',
    'Personnel',
    'Affectations enseignants',
    'Évaluations/Notes',
    'Conseils de classe',
    'Décisions conseil',
    'Présences/Discipline',
    'Paiements',
    'Échéanciers',
    'Clôtures de caisse',
    'Ressources bibliothèque',
    'Prêts bibliothèque',
    'Locaux/Équipements',
    'Séances emploi du temps',
    'Événements calendrier',
    'Sauvegardes',
    'Modèles documents',
    'Absences enseignants',
    'Clôtures annuelles',
    'Snapshots bulletins',
  ];

  Future<List<DeletedEntry>> listDeleted({String? entityFilter}) async {
    final out = <DeletedEntry>[];
    Future<void> add(String entity, Future<List<DeletedEntry>> Function() loader) async {
      if (entityFilter != null && entityFilter.isNotEmpty && entityFilter != 'Tous' && entityFilter != entity) return;
      out.addAll(await loader());
    }

    await add('Établissements', () async => (await (db.select(db.establishments)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Établissements', e.id, '${e.code} - ${e.name}', e.deletedAt)).toList());
    await add('Années scolaires', () async => (await (db.select(db.schoolYears)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Années scolaires', e.id, '${e.code} - ${e.label}', e.deletedAt)).toList());
    await add('Périodes', () async => (await (db.select(db.periods)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Périodes', e.id, e.name, e.deletedAt)).toList());
    await add('Rôles', () async => (await (db.select(db.roles)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Rôles', e.id, e.name, e.deletedAt)).toList());
    await add('Permissions', () async => (await (db.select(db.permissions)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Permissions', e.id, e.code, e.deletedAt)).toList());
    await add('Utilisateurs', () async => (await (db.select(db.users)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Utilisateurs', e.id, '${e.username} - ${e.fullName}', e.deletedAt)).toList());
    await add('Niveaux', () async => (await (db.select(db.levels)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Niveaux', e.id, e.name, e.deletedAt)).toList());
    await add('Classes', () async => (await (db.select(db.classes)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Classes', e.id, e.label, e.deletedAt)).toList());
    await add('Matières', () async => (await (db.select(db.subjects)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Matières', e.id, '${e.code} - ${e.name}', e.deletedAt)).toList());
    await add('Responsables', () async => (await (db.select(db.guardians)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Responsables', e.id, '${e.lastName} ${e.firstName}', e.deletedAt)).toList());
    await add('Élèves', () async => (await (db.select(db.students)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Élèves', e.id, '${e.matricule} ${e.lastName} ${e.firstName}', e.deletedAt)).toList());
    await add('Liens élève-responsable', () async => (await (db.select(db.studentGuardians)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Liens élève-responsable', e.id, 'Lien ${e.studentId.substring(0, e.studentId.length > 8 ? 8 : e.studentId.length)}…', e.deletedAt)).toList());
    await add('Inscriptions', () async => (await (db.select(db.enrollments)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Inscriptions', e.id, e.status, e.deletedAt)).toList());
    await add('Personnel', () async => (await (db.select(db.staffMembers)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Personnel', e.id, '${e.staffNumber} ${e.lastName} ${e.firstName}', e.deletedAt)).toList());
    await add('Affectations enseignants', () async => (await (db.select(db.teacherAssignments)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Affectations enseignants', e.id, 'Affectation ${e.id.substring(0, e.id.length > 8 ? 8 : e.id.length)}…', e.deletedAt)).toList());
    await add('Évaluations/Notes', () async => (await (db.select(db.evaluations)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Évaluations/Notes', e.id, e.label, e.deletedAt)).toList());
    await add('Conseils de classe', () async => (await (db.select(db.classCouncils)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Conseils de classe', e.id, 'Conseil ${e.status}', e.deletedAt)).toList());
    await add('Décisions conseil', () async => (await (db.select(db.councilDecisions)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Décisions conseil', e.id, e.decision ?? 'Décision', e.deletedAt)).toList());
    await add('Présences/Discipline', () async => (await (db.select(db.attendanceEvents)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Présences/Discipline', e.id, '${e.category} - ${e.status}', e.deletedAt)).toList());
    await add('Paiements', () async => (await (db.select(db.payments)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Paiements', e.id, e.receiptNumber, e.deletedAt)).toList());
    await add('Échéanciers', () async => (await (db.select(db.paymentSchedules)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Échéanciers', e.id, e.label, e.deletedAt)).toList());
    await add('Clôtures de caisse', () async => (await (db.select(db.cashClosures)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Clôtures de caisse', e.id, 'Clôture ${e.status}', e.deletedAt)).toList());
    await add('Ressources bibliothèque', () async => (await (db.select(db.libraryItems)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Ressources bibliothèque', e.id, e.title, e.deletedAt)).toList());
    await add('Prêts bibliothèque', () async => (await (db.select(db.libraryLoans)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Prêts bibliothèque', e.id, e.status, e.deletedAt)).toList());
    await add('Locaux/Équipements', () async => (await (db.select(db.facilities)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Locaux/Équipements', e.id, e.name, e.deletedAt)).toList());
    await add('Séances emploi du temps', () async => (await (db.select(db.timetableSessions)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Séances emploi du temps', e.id, '${e.dayOfWeek} ${e.startTime}-${e.endTime}', e.deletedAt)).toList());
    await add('Événements calendrier', () async => (await (db.select(db.calendarEvents)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Événements calendrier', e.id, e.title, e.deletedAt)).toList());
    await add('Sauvegardes', () async => (await (db.select(db.backupRecords)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Sauvegardes', e.id, e.filePath.split(RegExp(r'[\\/]')).last, e.deletedAt)).toList());
    await add('Modèles documents', () async => (await (db.select(db.documentTemplates)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Modèles documents', e.id, '${e.name} (${e.docType})', e.deletedAt)).toList());
    await add('Absences enseignants', () async => (await (db.select(db.teacherAbsences)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Absences enseignants', e.id, e.status, e.deletedAt)).toList());
    await add('Clôtures annuelles', () async => (await (db.select(db.yearClosures)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Clôtures annuelles', e.id, e.status, e.deletedAt)).toList());
    await add('Snapshots bulletins', () async => (await (db.select(db.bulletinSnapshots)..where((t) => t.isDeleted.equals(true))).get())
        .map((e) => DeletedEntry('Snapshots bulletins', e.id, '${e.docType} (${e.status})', e.deletedAt)).toList());

    out.sort((a, b) => (b.deletedAt ?? DateTime(0)).compareTo(a.deletedAt ?? DateTime(0)));
    return out;
  }

  Future<void> restore(String entity, String id, {String? actorUserId, String? actorUsername}) async {
    final now = DateTime.now();
    switch (entity) {
      case 'Établissements':
        await (db.update(db.establishments)..where((t) => t.id.equals(id))).write(EstablishmentsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Années scolaires':
        await (db.update(db.schoolYears)..where((t) => t.id.equals(id))).write(SchoolYearsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Périodes':
        await (db.update(db.periods)..where((t) => t.id.equals(id))).write(PeriodsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Rôles':
        await (db.update(db.roles)..where((t) => t.id.equals(id))).write(RolesCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Permissions':
        await (db.update(db.permissions)..where((t) => t.id.equals(id))).write(PermissionsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Utilisateurs':
        await (db.update(db.users)..where((t) => t.id.equals(id))).write(UsersCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Niveaux':
        await (db.update(db.levels)..where((t) => t.id.equals(id))).write(LevelsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Classes':
        await (db.update(db.classes)..where((t) => t.id.equals(id))).write(ClassesCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Matières':
        await (db.update(db.subjects)..where((t) => t.id.equals(id))).write(SubjectsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Responsables':
        await (db.update(db.guardians)..where((t) => t.id.equals(id))).write(GuardiansCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Élèves':
        await (db.update(db.students)..where((t) => t.id.equals(id))).write(StudentsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Liens élève-responsable':
        await (db.update(db.studentGuardians)..where((t) => t.id.equals(id))).write(StudentGuardiansCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Inscriptions':
        await (db.update(db.enrollments)..where((t) => t.id.equals(id))).write(EnrollmentsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Personnel':
        await (db.update(db.staffMembers)..where((t) => t.id.equals(id))).write(StaffMembersCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Affectations enseignants':
        await (db.update(db.teacherAssignments)..where((t) => t.id.equals(id))).write(TeacherAssignmentsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Évaluations/Notes':
      case 'Notes': // compat
        await (db.update(db.evaluations)..where((t) => t.id.equals(id))).write(EvaluationsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Conseils de classe':
        await (db.update(db.classCouncils)..where((t) => t.id.equals(id))).write(ClassCouncilsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Décisions conseil':
        await (db.update(db.councilDecisions)..where((t) => t.id.equals(id))).write(CouncilDecisionsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Présences/Discipline':
        await (db.update(db.attendanceEvents)..where((t) => t.id.equals(id))).write(AttendanceEventsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Paiements':
        await (db.update(db.payments)..where((t) => t.id.equals(id))).write(PaymentsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Échéanciers':
        await (db.update(db.paymentSchedules)..where((t) => t.id.equals(id))).write(PaymentSchedulesCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Clôtures de caisse':
        await (db.update(db.cashClosures)..where((t) => t.id.equals(id))).write(CashClosuresCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Ressources bibliothèque':
        await (db.update(db.libraryItems)..where((t) => t.id.equals(id))).write(LibraryItemsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Prêts bibliothèque':
        await (db.update(db.libraryLoans)..where((t) => t.id.equals(id))).write(LibraryLoansCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Locaux/Équipements':
        await (db.update(db.facilities)..where((t) => t.id.equals(id))).write(FacilitiesCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Séances emploi du temps':
        await (db.update(db.timetableSessions)..where((t) => t.id.equals(id))).write(TimetableSessionsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Événements calendrier':
        await (db.update(db.calendarEvents)..where((t) => t.id.equals(id))).write(CalendarEventsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Sauvegardes':
        await (db.update(db.backupRecords)..where((t) => t.id.equals(id))).write(BackupRecordsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Modèles documents':
        await (db.update(db.documentTemplates)..where((t) => t.id.equals(id))).write(DocumentTemplatesCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Absences enseignants':
        await (db.update(db.teacherAbsences)..where((t) => t.id.equals(id))).write(TeacherAbsencesCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Clôtures annuelles':
        await (db.update(db.yearClosures)..where((t) => t.id.equals(id))).write(YearClosuresCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      case 'Snapshots bulletins':
        await (db.update(db.bulletinSnapshots)..where((t) => t.id.equals(id))).write(BulletinSnapshotsCompanion(isDeleted: const Value(false), deletedAt: const Value(null), updatedAt: Value(now)));
        break;
      default:
        throw StateError('Type de corbeille inconnu : $entity');
    }
    await _audit.log(
        userId: actorUserId,
        username: actorUsername,
        module: 'Corbeille',
        targetObject: '$entity:$id',
        description: 'Restauration élément',
        result: 'Succès');
  }

  Future<int> purgeOlderThan(Duration retention) async {
    final cutoff = DateTime.now().subtract(retention);
    var n = 0;
    n += await (db.delete(db.establishments)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.schoolYears)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.periods)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.roles)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.permissions)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.users)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.levels)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.classes)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.subjects)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.guardians)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.students)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.studentGuardians)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.enrollments)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.staffMembers)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.teacherAssignments)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.evaluations)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.classCouncils)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.councilDecisions)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.attendanceEvents)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.payments)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.paymentSchedules)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.cashClosures)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.libraryItems)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.libraryLoans)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.facilities)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.timetableSessions)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.calendarEvents)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.backupRecords)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.documentTemplates)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.teacherAbsences)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.yearClosures)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    n += await (db.delete(db.bulletinSnapshots)..where((t) => t.isDeleted.equals(true) & t.deletedAt.isSmallerThanValue(cutoff))).go();
    return n;
  }
}
