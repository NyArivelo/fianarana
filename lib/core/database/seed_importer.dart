import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/password_hasher.dart';
import 'package:fianarana/core/security/rbac_seed.dart';

/// Importe les données de test (assets/seed/*.json, issues de donnees_de_test.xlsx)
/// dans la base SQLite. À exécuter lors de la première installation ou en mode bac à sable.
///
/// Note: les clés JSON conservent les en-têtes du fichier Excel (accents/espaces).
class SeedImporter {
  final AppDatabase db;
  SeedImporter(this.db);

  Future<List<Map<String, dynamic>>> _load(String path) async {
    final raw = await rootBundle.loadString(path);
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded.cast<Map>().map((e) => e.map((k, v) => MapEntry(k.toString(), v))).toList();
  }

  String _s(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return '';
  }

  int _i(Map<String, dynamic> m, List<String> keys, [int def = 0]) {
    final v = _s(m, keys);
    return int.tryParse(v) ?? def;
  }

  double _d(Map<String, dynamic> m, List<String> keys, [double def = 0]) {
    final v = _s(m, keys);
    return double.tryParse(v.replaceAll(',', '.')) ?? def;
  }

  bool _b(Map<String, dynamic> m, List<String> keys) {
    final v = m[keys.firstWhere((k) => m.containsKey(k), orElse: () => '')];
    if (v is bool) return v;
    final s = v?.toString().toLowerCase();
    return s == 'true' || s == '1' || s == 'oui';
  }

  /// Extrait la première valeur numérique d'un libellé (« 35 places » → 35).
  int? _capacity(Map<String, dynamic> m, List<String> keys) {
    final s = _s(m, keys);
    final match = RegExp(r'\d+').firstMatch(s);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  DateTime? _dt(Map<String, dynamic> m, List<String> keys) {
    final v = _s(m, keys);
    if (v.isEmpty) return null;
    return DateTime.tryParse(v);
  }

  Future<String> importAll() async {
    final counts = <String, int>{};
    await db.transaction(() async {
      counts['etablissement'] = await _importEstablishment();
      counts['utilisateurs_roles'] = await _importUsersRoles();
      counts['classes_matieres'] = await _importClassesSubjects();
      counts['personnel'] = await _importStaff();
      counts['affectations_enseignants'] = await _importTeacherAssignments();
      counts['responsables'] = await _importGuardians();
      counts['eleves_inscriptions'] = await _importStudents();
      counts['evaluations'] = await _importEvaluations();
      counts['presences_discipline'] = await _importAttendance();
      counts['finances'] = await _importFinance();
      counts['echeanciers'] = await _importPaymentSchedules();
      counts['bibliotheque_locaux'] = await _importLibraryFacilities();
      counts['emploi_du_temps'] = await _importTimetable();
      counts['calendrier_scolaire'] = await _importCalendarEvents();
      counts['audit'] = await _importAudit();
    });
    counts['conseils_classe'] = await _importCouncils();
    counts['decisions_conseil'] = await _importCouncilDecisions();
    counts['corbeille_test'] = await _importRecycleBinTestData();
    counts['donnees_test_fonctions'] = await _importFeatureTestData();
    // RBAC/permissions de base (donn�es de test s�curit�) + trace d'import
    await RbacSeed(db).ensureDefaults();
    await AuditService(db).log(
      module: 'Syst�me',
      targetObject: 'Base de donn�es',
      description: 'Import des donn�es de test termin�',
      result: 'Succ�s',
      metadata: counts,
    );
    return counts.entries.map((e) => '${e.key}=${e.value}').join(', ');
  }


  Future<int> _importFeatureTestData() async {
    // Donn�es de test compl�mentaires pour les fonctionnalit�s livr�es (idempotent).
    var n = 0;
    Future<void> upsert(TableInfo tbl, Insertable row) async { await db.into(tbl).insertOnConflictUpdate(row); n++; }

    final anyStudent = await (db.select(db.students)..where((t) => t.isDeleted.equals(false))..limit(1)).getSingleOrNull();
    final anyClass = await (db.select(db.classes)..where((t) => t.isDeleted.equals(false))..limit(1)).getSingleOrNull();
    final anyPeriod = await (db.select(db.periods)..where((t) => t.isDeleted.equals(false))..limit(1)).getSingleOrNull();
    final anyStaff = await (db.select(db.staffMembers)..where((t) => t.isDeleted.equals(false))..limit(1)).getSingleOrNull();
    final anyYear = await (db.select(db.schoolYears)..where((t) => t.isDeleted.equals(false))..limit(1)).getSingleOrNull();
    final anyUser = await (db.select(db.users)..where((t) => t.isDeleted.equals(false))..limit(1)).getSingleOrNull();

    // Snapshot de bulletin publi� (P0.4) - test de r�impression depuis version fig�e
    if (anyStudent != null) {
      final snap = jsonEncode({
        'student': {'id': anyStudent.id, 'name': '${anyStudent.lastName} ${anyStudent.firstName}', 'matricule': anyStudent.matricule, 'classId': anyClass?.id, 'classLabel': anyClass?.label},
        'periodId': anyPeriod?.id,
        'periodLabel': anyPeriod?.name ?? 'P�riode (test)',
        'subjects': [
          {'subject': 'Math�matiques', 'score': 14.0, 'maxScore': 20.0, 'coefficient': 2.0, 'isExempt': false},
          {'subject': 'Fran�ais', 'score': 12.5, 'maxScore': 20.0, 'coefficient': 2.0, 'isExempt': false},
        ],
        'average': 13.25,
        'mention': 'Assez bien',
        'generatedAt': DateTime.now().toIso8601String(),
        'establishmentName': '�tablissement scolaire (test)',
        'note': 'Snapshot de test (donn�es fig�es)',
      });
      await upsert(db.bulletinSnapshots, BulletinSnapshotsCompanion.insert(
        id: const Value('test-bulletin-snapshot-1'),
        studentId: anyStudent.id,
        classId: Value(anyClass?.id),
        periodId: Value(anyPeriod?.id),
        docType: const Value('bulletin'),
        snapshotJson: snap,
        publishedAt: DateTime.now().subtract(const Duration(days: 1)),
        publishedByUserId: Value(anyUser?.id),
        status: const Value('Publi�'),
        hashSha256: Value(sha256.convert(utf8.encode(snap)).toString()),
      ));
    }

    // Absence enseignant (test)
    if (anyStaff != null) {
      await upsert(db.teacherAbsences, TeacherAbsencesCompanion.insert(
        id: const Value('test-teacher-absence-1'),
        teacherId: anyStaff.id,
        startDate: DateTime.now().add(const Duration(days: 1)),
        endDate: DateTime.now().add(const Duration(days: 1)),
        reason: const Value('Absence test (donn�e de d�monstration)'),
        status: const Value('D�clar�e'),
        notes: const Value('Entr�e de test pour module absences/remplacements'),
      ));
    }

    // Cl�ture de caisse (test)
    if (anyUser != null) {
      await upsert(db.cashClosures, CashClosuresCompanion.insert(
        id: const Value('test-cash-closure-1'),
        cashierUserId: anyUser.id,
        closureDate: DateTime.now(),
        totalCash: const Value(50000),
        totalCheck: const Value(0),
        totalTransfer: const Value(25000),
        totalMobileMoney: const Value(10000),
        status: const Value('Cl�tur�'),
        notes: const Value('Cl�ture de caisse de test (donn�e de d�monstration)'),
      ));
    }

    // Mod�le Document Studio de test
    await upsert(db.documentTemplates, DocumentTemplatesCompanion.insert(
      id: const Value('test-doc-template-1'),
      name: 'Attestation de test (Document Studio)',
      docType: 'attestation',
      pageFormat: const Value('A4'),
      contentJson: jsonEncode({
        'title': 'ATTESTATION (TEST)',
        'header': '{{etablissement.nom}}',
        'body': 'Ceci est un mod�le de test.\n�l�ve : {{eleve.nom}} ({{eleve.matricule}})\nClasse : {{eleve.classe}}',
        'footer': 'Document de test - {{date.jour}}',
      }),
      description: const Value('Mod�le de test pour valider Document Studio'),
      isDefault: const Value(false),
      isActive: const Value(true),
    ));

    // Cl�ture annuelle (test archivage)
    if (anyYear != null) {
      await upsert(db.yearClosures, YearClosuresCompanion.insert(
        id: const Value('test-year-closure-1'),
        schoolYearId: anyYear.id,
        closedAt: DateTime.now().subtract(const Duration(days: 30)),
        closedByUserId: Value(anyUser?.id),
        status: const Value('Cl�tur�e (test)'),
        summaryJson: Value(jsonEncode({'note': 'Cl�ture annuelle de test', 'students': 0, 'sealed': false})),
      ));
    }

    return n;
  }

  Future<int> _importRecycleBinTestData() async {
    // Donn�es de test corbeille (suppression logique) pour plusieurs types d'entit�s.
    final delAt = DateTime.now().subtract(const Duration(days: 2));
    var n = 0;
    final anyStudent = await (db.select(db.students)..limit(1)).getSingleOrNull();
    final anyClass = await (db.select(db.classes)..limit(1)).getSingleOrNull();
    final anyStaff = await (db.select(db.staffMembers)..limit(1)).getSingleOrNull();
    final anySubject = await (db.select(db.subjects)..limit(1)).getSingleOrNull();
    final anyYear = await (db.select(db.schoolYears)..limit(1)).getSingleOrNull();
    final anyPeriod = await (db.select(db.periods)..limit(1)).getSingleOrNull();
    final anyItem = await (db.select(db.libraryItems)..limit(1)).getSingleOrNull();

    Future<void> soft(TableInfo tbl, Insertable row) async { await db.into(tbl).insertOnConflictUpdate(row); n++; }

    if (anyStudent != null) {
      await soft(db.students, StudentsCompanion.insert(id: const Value('rb-student-1'), matricule: 'RB-STU-001', lastName: 'TEST-CORBEILLE', firstName: 'Eleve', isDeleted: const Value(true), deletedAt: Value(delAt)));
      if (anyClass != null) {
        await soft(db.enrollments, EnrollmentsCompanion.insert(id: const Value('rb-enroll-1'), studentId: 'rb-student-1', classId: Value(anyClass.id), status: const Value('Archiv�e (test corbeille)'), isDeleted: const Value(true), deletedAt: Value(delAt)));
      }
      await soft(db.attendanceEvents, AttendanceEventsCompanion.insert(id: const Value('rb-att-1'), category: 'Appel', studentId: anyStudent.id, date: DateTime.now(), status: 'Absent (test corbeille)', isDeleted: const Value(true), deletedAt: Value(delAt)));
      await soft(db.payments, PaymentsCompanion.insert(id: const Value('rb-pay-1'), receiptNumber: 'RB-REC-001', studentId: anyStudent.id, feeLabel: 'Paiement test corbeille', isDeleted: const Value(true), deletedAt: Value(delAt)));
      if (anyPeriod != null) {
        await soft(db.evaluations, EvaluationsCompanion.insert(id: const Value('rb-eval-1'), studentId: anyStudent.id, periodId: Value(anyPeriod.id), subjectId: Value(anySubject?.id), classId: Value(anyClass?.id), label: 'Note test corbeille', isDeleted: const Value(true), deletedAt: Value(delAt)));
      }
      await soft(db.guardians, GuardiansCompanion.insert(id: const Value('rb-guard-1'), lastName: 'TEST-CORBEILLE', firstName: 'Responsable', isDeleted: const Value(true), deletedAt: Value(delAt)));
    }
    if (anyClass != null) {
      await soft(db.classes, ClassesCompanion.insert(id: const Value('rb-class-1'), label: 'CLASSE-TEST-CORBEILLE', isDeleted: const Value(true), deletedAt: Value(delAt)));
      if (anyPeriod != null) {
        await soft(db.classCouncils, ClassCouncilsCompanion.insert(id: const Value('rb-council-1'), classId: anyClass.id, periodId: anyPeriod.id, status: const Value('Test corbeille'), isDeleted: const Value(true), deletedAt: Value(delAt)));
        await soft(db.councilDecisions, CouncilDecisionsCompanion.insert(id: const Value('rb-decision-1'), councilId: 'rb-council-1', studentId: anyStudent?.id ?? 'rb-student-1', decision: const Value('D�cision test corbeille'), isDeleted: const Value(true), deletedAt: Value(delAt)));
      }
    }
    if (anyStaff != null) {
      await soft(db.staffMembers, StaffMembersCompanion.insert(id: const Value('rb-staff-1'), staffNumber: 'RB-RH-001', lastName: 'TEST-CORBEILLE', firstName: 'Personnel', isDeleted: const Value(true), deletedAt: Value(delAt)));
      await soft(db.teacherAbsences, TeacherAbsencesCompanion.insert(id: const Value('rb-abs-1'), teacherId: anyStaff.id, startDate: DateTime.now(), endDate: DateTime.now(), reason: const Value('Absence test corbeille'), isDeleted: const Value(true), deletedAt: Value(delAt)));
      if (anyClass != null) {
        await soft(db.teacherAssignments, TeacherAssignmentsCompanion.insert(id: const Value('rb-assign-1'), staffId: anyStaff.id, classId: anyClass.id, subjectId: Value(anySubject?.id), schoolYearId: Value(anyYear?.id), isDeleted: const Value(true), deletedAt: Value(delAt)));
      }
      await soft(db.timetableSessions, TimetableSessionsCompanion.insert(id: const Value('rb-tt-1'), classId: Value(anyClass?.id), teacherId: Value(anyStaff.id), dayOfWeek: 'Lundi', startTime: '00:00', endTime: '00:30', notes: const Value('S�ance test corbeille'), isDeleted: const Value(true), deletedAt: Value(delAt)));
    }
    if (anySubject != null) {
      await soft(db.subjects, SubjectsCompanion.insert(id: const Value('rb-subj-1'), code: 'RB-MAT', name: 'Mati�re test corbeille', isDeleted: const Value(true), deletedAt: Value(delAt)));
    }
    await soft(db.levels, LevelsCompanion.insert(id: const Value('rb-level-1'), name: 'Niveau test corbeille', isDeleted: const Value(true), deletedAt: Value(delAt)));
    if (anyYear != null) {
      final est = await (db.select(db.establishments)..limit(1)).getSingleOrNull();
      if (est != null) {
        await soft(db.schoolYears, SchoolYearsCompanion.insert(id: const Value('rb-year-1'), establishmentId: est.id, code: 'RB-YEAR', label: 'Ann�e test corbeille', startDate: DateTime(2000,1,1), endDate: DateTime(2000,12,31), isDeleted: const Value(true), deletedAt: Value(delAt)));
      }
      await soft(db.periods, PeriodsCompanion.insert(id: const Value('rb-period-1'), schoolYearId: anyYear.id, name: 'P�riode test corbeille', isDeleted: const Value(true), deletedAt: Value(delAt)));
    }
    await soft(db.paymentSchedules, PaymentSchedulesCompanion.insert(id: const Value('rb-sched-1'), studentId: anyStudent?.id ?? 'rb-student-1', label: '�ch�ance test corbeille', isDeleted: const Value(true), deletedAt: Value(delAt)));
    await soft(db.libraryItems, LibraryItemsCompanion.insert(id: const Value('rb-lib-1'), title: 'Document test corbeille', isDeleted: const Value(true), deletedAt: Value(delAt)));
    await soft(db.libraryLoans, LibraryLoansCompanion.insert(id: const Value('rb-loan-1'), itemId: anyItem?.id ?? 'rb-lib-1', startDate: DateTime.now(), status: const Value('Test corbeille'), isDeleted: const Value(true), deletedAt: Value(delAt)));
    await soft(db.facilities, FacilitiesCompanion.insert(id: const Value('rb-fac-1'), domain: 'Salle', name: 'Local test corbeille', isDeleted: const Value(true), deletedAt: Value(delAt)));
    await soft(db.calendarEvents, CalendarEventsCompanion.insert(id: const Value('rb-cal-1'), title: '�v�nement test corbeille', startDate: DateTime.now(), isDeleted: const Value(true), deletedAt: Value(delAt)));
    await soft(db.documentTemplates, DocumentTemplatesCompanion.insert(id: const Value('rb-doc-1'), name: 'Mod�le test corbeille', docType: 'autre', isDeleted: const Value(true), deletedAt: Value(delAt)));
    if (anyStudent != null) {
      await soft(db.bulletinSnapshots, BulletinSnapshotsCompanion.insert(id: const Value('rb-bull-1'), studentId: anyStudent.id, snapshotJson: '{"test":"corbeille"}', publishedAt: DateTime.now(), isDeleted: const Value(true), deletedAt: Value(delAt)));
    }
    final anyLink = await (db.select(db.studentGuardians)..limit(1)).getSingleOrNull();
    if (anyLink != null) {
      await soft(db.studentGuardians, StudentGuardiansCompanion.insert(id: const Value('rb-link-1'), studentId: anyLink.studentId, guardianId: anyLink.guardianId, isDeleted: const Value(true), deletedAt: Value(delAt)));
    }
    return n;
  }

  Future<int> _importEstablishment() async {
    final rows = await _load('assets/seed/param_tres__tablissement.json');
    var n = 0;
    String? estId;
    String? yearId;
    for (final r in rows) {
      final type = _s(r, ['Type_Entité', 'Type_Entite', 'Type']);
      final id = _s(r, ['UUID_Entité', 'UUID_Entite', 'UUID']);
      if (id.isEmpty) continue;
      if (type.toLowerCase().contains('tablissement') || type.toLowerCase().contains('etablissement')) {
        estId = id;
        await db.into(db.establishments).insertOnConflictUpdate(EstablishmentsCompanion.insert(
          id: Value(id),
          code: _s(r, ['Code']).isEmpty ? 'ETAB-01' : _s(r, ['Code']),
          name: _s(r, ['Libellé', 'Libelle', 'Nom']),
          address: Value(_s(r, ['Valeur_1', 'Adresse'])),
          motto: const Value(null),
          timezone: const Value('Indian/Antananarivo'),
          currency: const Value('MGA'),
          status: Value(_s(r, ['Statut']).isEmpty ? 'Actif' : _s(r, ['Statut'])),
        ));
        n++;
      } else if (type.toLowerCase().contains('ann')) {
        yearId = id;
        await db.into(db.schoolYears).insertOnConflictUpdate(SchoolYearsCompanion.insert(
          id: Value(id),
          establishmentId: estId ?? 'establishment',
          code: _s(r, ['Code']),
          label: _s(r, ['Libellé', 'Libelle']),
          startDate: _dt(r, ['Valeur_1']) ?? DateTime(2026, 9, 7),
          endDate: _dt(r, ['Valeur_2']) ?? DateTime(2027, 6, 30),
          status: Value(_s(r, ['Statut']).isEmpty ? 'En cours' : _s(r, ['Statut'])),
        ));
        n++;
      } else if (type.toLowerCase().contains('riode') || type.toLowerCase().contains('periode') || type.toLowerCase().contains('trimestre')) {
        await db.into(db.periods).insertOnConflictUpdate(PeriodsCompanion.insert(
          id: Value(id),
          schoolYearId: yearId ?? '',
          name: _s(r, ['Libellé', 'Libelle', 'Code']),
          sequence: Value(_i(r, ['Valeur_1', 'Ordre'], 1)),
          startDate: Value(_dt(r, ['Valeur_1'])),
          endDate: Value(_dt(r, ['Valeur_2'])),
          isClosed: Value(_s(r, ['Statut']).toLowerCase().contains('clot')),
        ));
        n++;
      }
    }
    return n;
  }

  Future<int> _importUsersRoles() async {
    final rows = await _load('assets/seed/utilisateurs_r_les.json');
    final roleCache = <String, String>{}; // name -> id
    var n = 0;
    final defaultPass = passwordHasher.hash('Password123!'); // mot de passe de test
    for (final r in rows) {
      final userId = _s(r, ['UUID_Utilisateur', 'UUID']);
      final username = _s(r, ['Identifiant', 'Username']);
      if (userId.isEmpty || username.isEmpty) continue;
      final roleName = _s(r, ['Rôle_Principal', 'Role_Principal', 'Role']).isEmpty ? 'Utilisateur' : _s(r, ['Rôle_Principal', 'Role_Principal', 'Role']);
      var roleId = roleCache[roleName];
      if (roleId == null) {
        roleId = 'role-${roleName.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), "-")}';
        roleCache[roleName] = roleId;
        await db.into(db.roles).insertOnConflictUpdate(RolesCompanion.insert(
          id: Value(roleId),
          name: roleName,
          description: const Value(null),
          isSystem: Value(roleName == 'Administrateur'),
        ));
      }
      final pin = _s(r, ['PIN_QuickSwitch', 'PIN']);
      final failed = _i(r, ['Echecs_Connexion', 'failedLoginCount'], 0);
      final lockedUntil = _dt(r, ['Verrouille_Jusqu', 'lockedUntil']);
      await db.into(db.users).insertOnConflictUpdate(UsersCompanion.insert(
        id: Value(userId),
        username: username,
        fullName: _s(r, ['Nom_Complet', 'Nom']),
        email: Value(_s(r, ['Email']).isEmpty ? null : _s(r, ['Email'])),
        passwordHash: defaultPass,
        pinHash: Value(pin.isEmpty ? null : passwordHasher.hash(pin)),
        isActive: Value(_b(r, ['Compte_Actif']) || _s(r, ['Compte_Actif']).isEmpty),
        scopeType: Value(_s(r, ['Portée_Scope', 'Portee_Scope']).isEmpty ? 'Globale' : _s(r, ['Portée_Scope', 'Portee_Scope'])),
        lastLoginAt: Value(_dt(r, ['Dernière_Connexion_UTC', 'Derniere_Connexion_UTC'])),
        failedLoginCount: Value(failed),
        lockedUntil: Value(lockedUntil),
      ));
      await db.into(db.userRoles).insertOnConflictUpdate(UserRolesCompanion.insert(userId: userId, roleId: roleId));
      n++;
    }
    return n;
  }

  Future<int> _importClassesSubjects() async {
    final rows = await _load('assets/seed/classes_mati_res.json');
    var n = 0;
    final levelIds = <String, String>{};
    for (final r in rows) {
      final id = _s(r, ['UUID_Entité', 'UUID_Entite', 'UUID']);
      final cat = _s(r, ['Catégorie', 'Categorie']).toLowerCase();
      if (id.isEmpty) continue;
      if (cat.contains('classe')) {
        final levelName = _s(r, ['Niveau_Ou_Domaine', 'Niveau']);
        final levelKey = '$levelName|${_s(r, ['Série_Ou_Code', 'Serie_Ou_Code'])}';
        var levelId = levelIds[levelKey];
        if (levelId == null) {
          levelId = 'lvl-${levelKey.hashCode.abs()}';
          levelIds[levelKey] = levelId;
          await db.into(db.levels).insertOnConflictUpdate(LevelsCompanion.insert(
            id: Value(levelId),
            name: levelName.isEmpty ? 'Niveau' : levelName,
            cycle: Value(_s(r, ['Niveau_Ou_Domaine'])),
            track: Value(_s(r, ['Série_Ou_Code', 'Serie_Ou_Code'])),
          ));
        }
        await db.into(db.classes).insertOnConflictUpdate(ClassesCompanion.insert(
          id: Value(id),
          levelId: Value(levelId),
          label: _s(r, ['Libellé', 'Libelle']),
          capacity: Value(_i(r, ['Capacité_Ou_Coef_Sec2', 'Capacite_Ou_Coef_Sec2'], 0)),
          room: Value(_s(r, ['Salle_Ou_Classes_Cibles']).isEmpty ? null : _s(r, ['Salle_Ou_Classes_Cibles'])),
        ));
        n++;
      } else if (cat.contains('mati')) {
        final code = _s(r, ['Série_Ou_Code', 'Serie_Ou_Code', 'Code']).isEmpty ? id.substring(0, 8) : _s(r, ['Série_Ou_Code', 'Serie_Ou_Code', 'Code']);
        await db.into(db.subjects).insertOnConflictUpdate(SubjectsCompanion.insert(
          id: Value(id),
          code: code,
          name: _s(r, ['Libellé', 'Libelle', 'Nom']),
          coefficientSec2: Value(_d(r, ['Capacité_Ou_Coef_Sec2', 'Capacite_Ou_Coef_Sec2'], 1)),
          coefficientSec3: Value(_d(r, ['Effectif_Ou_Coef_Sec3'], 1)),
          domain: Value(_s(r, ['Niveau_Ou_Domaine'])),
        ));
        n++;
      } else if (cat.contains('niveau')) {
        await db.into(db.levels).insertOnConflictUpdate(LevelsCompanion.insert(
          id: Value(id),
          name: _s(r, ['Libellé', 'Libelle', 'Niveau']),
          cycle: Value(_s(r, ['Niveau_Ou_Domaine'])),
          track: Value(_s(r, ['Série_Ou_Code', 'Serie_Ou_Code'])),
        ));
        n++;
      }
    }
    return n;
  }

  Future<int> _importStaff() async {
    final rows = await _load('assets/seed/personnel_enseignants.json');
    var n = 0;
    for (final r in rows) {
      final id = _s(r, ['UUID_Personnel', 'UUID']);
      if (id.isEmpty) continue;
      await db.into(db.staffMembers).insertOnConflictUpdate(StaffMembersCompanion.insert(
        id: Value(id),
        userId: Value(_s(r, ['UUID_Utilisateur_Lié', 'UUID_Utilisateur_Lie']).isEmpty ? null : _s(r, ['UUID_Utilisateur_Lié', 'UUID_Utilisateur_Lie'])),
        staffNumber: _s(r, ['Matricule_RH', 'Matricule']),
        lastName: _s(r, ['Nom']),
        firstName: _s(r, ['Prénom', 'Prenom']),
        sex: Value(_s(r, ['Sexe']).isEmpty ? null : _s(r, ['Sexe'])),
        functionTitle: Value(_s(r, ['Fonction'])),
        departmentOrSubject: Value(_s(r, ['Matière_Ou_Service', 'Matiere_Ou_Service'])),
        contractType: Value(_s(r, ['Type_Contrat'])),
        phone: Value(_s(r, ['Téléphone', 'Telephone'])),
        status: Value(_s(r, ['Statut']).isEmpty ? 'Actif' : _s(r, ['Statut'])),
      ));
      n++;
    }
    return n;
  }

  Future<int> _importTeacherAssignments() async {
    final rows = await _load('assets/seed/affectations_enseignants.json');
    final years = await db.select(db.schoolYears).get();
    final activeYearId = years.isNotEmpty ? years.first.id : null;
    var n = 0;
    for (final r in rows) {
      final id = _s(r, ['UUID_Affectation', 'UUID']);
      final staffId = _s(r, ['UUID_Personnel']);
      final classId = _s(r, ['UUID_Classe']);
      if (id.isEmpty || staffId.isEmpty || classId.isEmpty) continue;
      final subjectId = _s(r, ['UUID_Matiere']);
      await db.into(db.teacherAssignments).insertOnConflictUpdate(TeacherAssignmentsCompanion.insert(
        id: Value(id),
        staffId: staffId,
        classId: classId,
        subjectId: Value(subjectId.isEmpty ? null : subjectId),
        schoolYearId: Value(activeYearId),
      ));
      n++;
    }
    return n;
  }

  Future<int> _importGuardians() async {
    final rows = await _load('assets/seed/responsables_l_gaux.json');
    var n = 0;
    for (final r in rows) {
      final id = _s(r, ['UUID_Responsable', 'UUID']);
      if (id.isEmpty) continue;
      await db.into(db.guardians).insertOnConflictUpdate(GuardiansCompanion.insert(
        id: Value(id),
        lastName: _s(r, ['Nom']),
        firstName: _s(r, ['Prénom', 'Prenom']),
        relationship: Value(_s(r, ['Lien_Parenté', 'Lien_Parente'])),
        phone: Value(_s(r, ['Téléphone', 'Telephone'])),
        email: Value(_s(r, ['Email'])),
        address: Value(_s(r, ['Adresse'])),
        occupation: Value(_s(r, ['Profession'])),
        nationalId: Value(_s(r, ['CIN_Identifiant_National', 'CIN'])),
      ));
      n++;
    }
    return n;
  }

  Future<int> _importStudents() async {
    final rows = await _load('assets/seed/_l_ves_inscriptions.json');
    var n = 0;
    // déduire année scolaire active si possible
    final years = await db.select(db.schoolYears).get();
    final activeYearId = years.isNotEmpty ? years.first.id : null;
    for (final r in rows) {
      final id = _s(r, ['UUID_Élève', 'UUID_Eleve', 'UUID']);
      if (id.isEmpty) continue;
      await db.into(db.students).insertOnConflictUpdate(StudentsCompanion.insert(
        id: Value(id),
        matricule: _s(r, ['Matricule']),
        lastName: _s(r, ['Nom']),
        firstName: _s(r, ['Prénom', 'Prenom']),
        sex: Value(_s(r, ['Sexe'])),
        birthDate: Value(_dt(r, ['Date_Naissance'])),
        birthPlace: Value(_s(r, ['Lieu_Naissance'])),
        status: Value(_s(r, ['Statut_Inscription']).isEmpty ? 'Actif' : 'Actif'),
        photoPath: Value(_s(r, ['Chemin_Photo_Relatif'])),
        photoHash: Value(_s(r, ['Hash_Photo_SHA256'])),
        medicalNotes: Value(_s(r, ['Observations_Médicales_Suivi', 'Observations_Medicales_Suivi'])),
      ));
      final classId = _s(r, ['UUID_Classe']);
      if (classId.isNotEmpty) {
        await db.into(db.enrollments).insertOnConflictUpdate(EnrollmentsCompanion.insert(
          id: Value('enr-$id'),
          studentId: id,
          schoolYearId: Value(activeYearId),
          classId: Value(classId),
          status: Value(_s(r, ['Statut_Inscription']).isEmpty ? 'Validée' : _s(r, ['Statut_Inscription'])),
        ));
      }
      final guardianId = _s(r, ['UUID_Responsable']);
      if (guardianId.isNotEmpty) {
        await db.into(db.studentGuardians).insertOnConflictUpdate(StudentGuardiansCompanion.insert(
          studentId: id,
          guardianId: guardianId,
          isPrimary: const Value(true),
        ));
      }
      n++;
    }
    return n;
  }

  Future<int> _importEvaluations() async {
    final rows = await _load('assets/seed/_valuations_notes.json');
    var n = 0;
    for (final r in rows) {
      final id = _s(r, ['UUID_Note', 'UUID']);
      final studentId = _s(r, ['UUID_Élève', 'UUID_Eleve']);
      if (id.isEmpty || studentId.isEmpty) continue;
      await db.into(db.evaluations).insertOnConflictUpdate(EvaluationsCompanion.insert(
        id: Value(id),
        studentId: studentId,
        periodId: Value(_s(r, ['UUID_Période', 'UUID_Periode']).isEmpty ? null : _s(r, ['UUID_Période', 'UUID_Periode'])),
        subjectId: Value(_s(r, ['UUID_Matière', 'UUID_Matiere']).isEmpty ? null : _s(r, ['UUID_Matière', 'UUID_Matiere'])),
        label: _s(r, ['Évaluation', 'Evaluation', 'Type']).isEmpty ? 'Évaluation' : _s(r, ['Évaluation', 'Evaluation', 'Type']),
        score: Value(_d(r, ['Note_Chiffrée', 'Note_Chiffree', 'Note'], 0)),
        maxScore: Value(_d(r, ['Barème', 'Bareme'], 20)),
        coefficient: Value(_d(r, ['Coef_Matière', 'Coef_Matiere', 'Coefficient'], 1)),
        isExempt: Value(_b(r, ['Est_Dispensé', 'Est_Dispense'])),
        observation: Value(_s(r, ['Observation']).isEmpty ? null : _s(r, ['Observation'])),
        validationStatus: Value(_s(r, ['Statut_Validation']).isEmpty ? 'Brouillon' : _s(r, ['Statut_Validation'])),
      ));
      n++;
    }
    return n;
  }

  Future<int> _importAttendance() async {
    final rows = await _load('assets/seed/pr_sences_discipline.json');
    var n = 0;
    for (final r in rows) {
      final id = _s(r, ['UUID_Événement', 'UUID_Evenement', 'UUID']);
      final studentId = _s(r, ['UUID_Élève', 'UUID_Eleve']);
      if (id.isEmpty || studentId.isEmpty) continue;
      await db.into(db.attendanceEvents).insertOnConflictUpdate(AttendanceEventsCompanion.insert(
        id: Value(id),
        category: _s(r, ['Catégorie', 'Categorie']).isEmpty ? 'Appel / Présence' : _s(r, ['Catégorie', 'Categorie']),
        studentId: studentId,
        date: _dt(r, ['Date']) ?? DateTime.now(),
        slotOrFacts: Value(_s(r, ['Créneau_Ou_Faits', 'Creneau_Ou_Faits'])),
        status: _s(r, ['Type_Statut', 'Statut']).isEmpty ? 'Présent' : _s(r, ['Type_Statut', 'Statut']),
        justificationOrSanction: Value(_s(r, ['Justification_Ou_Sanction'])),
        details: Value(_s(r, ['Détails_Suivi', 'Details_Suivi'])),
        authorUserId: Value(_s(r, ['UUID_Auteur']).isEmpty ? null : _s(r, ['UUID_Auteur'])),
      ));
      n++;
    }
    return n;
  }

  Future<int> _importFinance() async {
    final rows = await _load('assets/seed/finances_paiements.json');
    var n = 0;
    for (final r in rows) {
      final id = _s(r, ['UUID_Transaction', 'UUID']);
      final studentId = _s(r, ['UUID_Élève', 'UUID_Eleve']);
      if (id.isEmpty || studentId.isEmpty) continue;
      await db.into(db.payments).insertOnConflictUpdate(PaymentsCompanion.insert(
        id: Value(id),
        receiptNumber: _s(r, ['Numéro_Reçu', 'Numero_Recu', 'Recu']).isEmpty ? 'REC-$n' : _s(r, ['Numéro_Reçu', 'Numero_Recu', 'Recu']),
        studentId: studentId,
        feeLabel: _s(r, ['Libellé_Frais', 'Libelle_Frais']).isEmpty ? 'Frais' : _s(r, ['Libellé_Frais', 'Libelle_Frais']),
        amountDueMga: Value(_i(r, ['Montant_Dû_MGA', 'Montant_Du_MGA'], 0)),
        amountPaidMga: Value(_i(r, ['Montant_Payé_MGA', 'Montant_Paye_MGA'], 0)),
        balanceMga: Value(_i(r, ['Reste_à_Payer_MGA', 'Reste_a_Payer_MGA'], 0)),
        paymentDate: Value(_dt(r, ['Date_Paiement'])),
        paymentMethod: Value(_s(r, ['Mode_Paiement'])),
        scheduleStatus: Value(_s(r, ['Statut_Échéancier', 'Statut_Echeancier'])),
        cashierUserId: Value(_s(r, ['UUID_Caissier']).isEmpty ? null : _s(r, ['UUID_Caissier'])),
        cashCloseStatus: Value(_s(r, ['État_Clôture_Caisse', 'Etat_Cloture_Caisse'])),
      ));
      n++;
    }
    return n;
  }

  Future<int> _importLibraryFacilities() async {
    final rows = await _load('assets/seed/biblioth_que_locaux.json');
    var n = 0;
    for (final r in rows) {
      final id = _s(r, ['UUID_Entité', 'UUID_Entite', 'UUID']);
      final domain = _s(r, ['Domaine']);
      if (id.isEmpty) continue;
      if (domain.toLowerCase().contains('biblio')) {
        await db.into(db.libraryItems).insertOnConflictUpdate(LibraryItemsCompanion.insert(
            id: Value(id),
          domain: Value(domain.isEmpty ? 'Bibliothèque' : domain),
          codeOrIsbn: Value(_s(r, ['Code_Ou_ISBN'])),
          title: _s(r, ['Désignation_Ou_Titre', 'Designation_Ou_Titre', 'Titre']).isEmpty ? 'Document' : _s(r, ['Désignation_Ou_Titre', 'Designation_Ou_Titre', 'Titre']),
          authorOrCategory: Value(_s(r, ['Catégorie_Ou_Auteur', 'Categorie_Ou_Auteur'])),
          copyCode: Value(_s(r, ['Exemplaire_Ou_Capacité', 'Exemplaire_Ou_Capacite'])),
          availability: Value(_s(r, ['Disponibilité', 'Disponibilite']).isEmpty ? 'Disponible' : _s(r, ['Disponibilité', 'Disponibilite'])),
        ));
        // créer prêt si emprunteur présent
        final borrower = _s(r, ['UUID_Emprunteur']);
        if (borrower.isNotEmpty) {
          await db.into(db.libraryLoans).insertOnConflictUpdate(LibraryLoansCompanion.insert(
              id: Value('loan-$id'),
            itemId: id,
            borrowerStudentId: Value(borrower),
            borrowerRef: Value(_s(r, ['Ref_Emprunteur_Ou_Cycle'])),
            startDate: _dt(r, ['Date_Début', 'Date_Debut']) ?? DateTime.now(),
            dueDate: Value(_dt(r, ['Date_Échéance', 'Date_Echeance'])),
            status: Value(_s(r, ['Statut_Opérationnel', 'Statut_Operationnel']).isEmpty ? 'En cours' : _s(r, ['Statut_Opérationnel', 'Statut_Operationnel'])),
          ));
        }
        n++;
      } else {
        await db.into(db.facilities).insertOnConflictUpdate(FacilitiesCompanion.insert(
            id: Value(id),
          domain: domain.isEmpty ? 'Local' : domain,
          code: Value(_s(r, ['Code_Ou_ISBN'])),
          name: _s(r, ['Désignation_Ou_Titre', 'Designation_Ou_Titre']).isEmpty ? 'Espace' : _s(r, ['Désignation_Ou_Titre', 'Designation_Ou_Titre']),
          category: Value(_s(r, ['Catégorie_Ou_Auteur', 'Categorie_Ou_Auteur'])),
          capacity: Value(_capacity(r, ['Exemplaire_Ou_Capacité', 'Exemplaire_Ou_Capacite'])),
          status: Value(_s(r, ['Statut_Opérationnel', 'Statut_Operationnel']).isEmpty ? 'Disponible' : _s(r, ['Statut_Opérationnel', 'Statut_Operationnel'])),
        ));
        n++;
      }
    }
    return n;
  }

  Future<int> _importAudit() async {
    final rows = await _load('assets/seed/journal_audit.json');
    var n = 0;
    for (final r in rows) {
      final id = _s(r, ['UUID_Audit', 'UUID']);
      if (id.isEmpty) continue;
      await db.into(db.auditLogs).insertOnConflictUpdate(AuditLogsCompanion.insert(
        id: id,
        timestampUtc: _dt(r, ['Horodatage_UTC'])?.toUtc() ?? DateTime.now().toUtc(),
        userId: Value(_s(r, ['UUID_Utilisateur']).isEmpty ? null : _s(r, ['UUID_Utilisateur'])),
        username: Value(_s(r, ['Identifiant_User'])),
        module: _s(r, ['Module']).isEmpty ? 'Système' : _s(r, ['Module']),
        targetObject: Value(_s(r, ['Objet_Ciblé', 'Objet_Cible'])),
        description: _s(r, ['Description_Opération', 'Description_Operation']).isEmpty ? 'Événement' : _s(r, ['Description_Opération', 'Description_Operation']),
        result: Value(_s(r, ['Résultat', 'Resultat']).isEmpty ? 'Succès' : _s(r, ['Résultat', 'Resultat'])),
        hashSha256: Value(_s(r, ['Empreinte_SHA256'])),
      ));
      n++;
    }
    return n;
  }

  Future<int> _importCouncils() async {
    try {
      final rows = await _load('assets/seed/conseils_classe.json');
      var n = 0;
      for (final r in rows) {
        final id = _s(r, ['UUID_Conseil', 'UUID']);
        if (id.isEmpty) continue;
        await db.into(db.classCouncils).insertOnConflictUpdate(ClassCouncilsCompanion.insert(
          id: Value(id),
          classId: _s(r, ['UUID_Classe']),
          periodId: _s(r, ['UUID_Periode']),
          councilDate: Value(_dt(r, ['Date_Conseil'])),
          status: Value(_s(r, ['Statut']).isEmpty ? 'Préparation' : _s(r, ['Statut'])),
          globalAppreciation: Value(_s(r, ['Appreciation_Globale'])),
        ));
        n++;
      }
      return n;
    } catch (_) {
      return 0; // fichier optionnel
    }
  }

  Future<int> _importCouncilDecisions() async {
    try {
      final rows = await _load('assets/seed/decisions_conseil.json');
      var n = 0;
      for (final r in rows) {
        final id = _s(r, ['UUID_Decision', 'UUID']);
        if (id.isEmpty) continue;
        await db.into(db.councilDecisions).insertOnConflictUpdate(CouncilDecisionsCompanion.insert(
          id: Value(id),
          councilId: _s(r, ['UUID_Conseil']),
          studentId: _s(r, ['UUID_Eleve']),
          decision: Value(_s(r, ['Decision'])),
          appreciation: Value(_s(r, ['Appreciation'])),
          average: Value(_d(r, ['Moyenne'], 0)),
          rank: Value(_i(r, ['Rang'], 0)),
          mention: Value(_s(r, ['Mention'])),
        ));
        n++;
      }
      return n;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _importPaymentSchedules() async {
    try {
      final rows = await _load('assets/seed/echeanciers_paiement.json');
      var n = 0;
      for (final r in rows) {
        final id = _s(r, ['UUID_Echeance', 'UUID']);
        final studentId = _s(r, ['UUID_Eleve']);
        if (id.isEmpty || studentId.isEmpty) continue;
        await db.into(db.paymentSchedules).insertOnConflictUpdate(PaymentSchedulesCompanion.insert(
          id: Value(id),
          studentId: studentId,
          classId: Value(_s(r, ['UUID_Classe']).isEmpty ? null : _s(r, ['UUID_Classe'])),
          label: _s(r, ['Libelle']).isEmpty ? 'Échéance' : _s(r, ['Libelle']),
          totalAmountMga: Value(_i(r, ['Montant_Total_MGA'], 0)),
          installmentCount: Value(_i(r, ['Nombre_Tranches'], 1)),
          dueDate: Value(_dt(r, ['Date_Echeance'])),
          amountDueMga: Value(_i(r, ['Montant_Du_MGA'], 0)),
          amountPaidMga: Value(_i(r, ['Montant_Paye_MGA'], 0)),
          status: Value(_s(r, ['Statut']).isEmpty ? 'À venir' : _s(r, ['Statut'])),
        ));
        n++;
      }
      return n;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _importCalendarEvents() async {
    final rows = await _load('assets/seed/calendrier_scolaire.json');
    final years = await db.select(db.schoolYears).get();
    final activeYearId = years.isNotEmpty ? years.first.id : null;
    var n = 0;
    for (final r in rows) {
      final id = _s(r, ['UUID_Evenement', 'UUID']);
      if (id.isEmpty) continue;
      final classId = _s(r, ['UUID_Classe']);
      final start = _dt(r, ['Date_Debut']);
      if (start == null) continue;
      await db.into(db.calendarEvents).insertOnConflictUpdate(CalendarEventsCompanion.insert(
        id: Value(id),
        schoolYearId: Value(activeYearId),
        classId: Value(classId.isEmpty ? null : classId),
        title: _s(r, ['Titre']),
        category: Value(_s(r, ['Categorie']).isEmpty ? 'Événement' : _s(r, ['Categorie'])),
        startDate: start,
        endDate: Value(_dt(r, ['Date_Fin'])),
        allDay: Value(r['Journee_Entiere'] is bool ? r['Journee_Entiere'] as bool : _b(r, ['Journee_Entiere'])),
        startTime: Value(_s(r, ['Heure_Debut']).isEmpty ? null : _s(r, ['Heure_Debut'])),
        endTime: Value(_s(r, ['Heure_Fin']).isEmpty ? null : _s(r, ['Heure_Fin'])),
        location: Value(_s(r, ['Lieu']).isEmpty ? null : _s(r, ['Lieu'])),
        description: Value(_s(r, ['Description']).isEmpty ? null : _s(r, ['Description'])),
        colorHex: Value(_s(r, ['Couleur']).isEmpty ? null : _s(r, ['Couleur'])),
        isEphemeris: Value(r['Est_Ephemeride'] is bool ? r['Est_Ephemeride'] as bool : _b(r, ['Est_Ephemeride'])),
        visibility: Value(_s(r, ['Visibilite']).isEmpty ? 'Établissement' : _s(r, ['Visibilite'])),
        status: Value(_s(r, ['Statut']).isEmpty ? 'Publié' : _s(r, ['Statut'])),
      ));
      n++;
    }
    return n;
  }

  Future<int> _importTimetable() async {
    try {
      final rows = await _load('assets/seed/emploi_du_temps.json');
      var n = 0;
      for (final r in rows) {
        final id = _s(r, ['UUID_Session', 'UUID']);
        if (id.isEmpty) continue;
        await db.into(db.timetableSessions).insertOnConflictUpdate(TimetableSessionsCompanion.insert(
          id: Value(id),
          classId: Value(_s(r, ['UUID_Classe']).isEmpty ? null : _s(r, ['UUID_Classe'])),
          subjectId: Value(_s(r, ['UUID_Matiere']).isEmpty ? null : _s(r, ['UUID_Matiere'])),
          teacherId: Value(_s(r, ['UUID_Enseignant']).isEmpty ? null : _s(r, ['UUID_Enseignant'])),
          roomId: Value(_s(r, ['UUID_Salle']).isEmpty ? null : _s(r, ['UUID_Salle'])),
          dayOfWeek: _s(r, ['Jour']).isEmpty ? 'Lundi' : _s(r, ['Jour']),
          startTime: _s(r, ['Heure_Debut']).isEmpty ? '08:00' : _s(r, ['Heure_Debut']),
          endTime: _s(r, ['Heure_Fin']).isEmpty ? '10:00' : _s(r, ['Heure_Fin']),
          recurrence: Value(_s(r, ['Recurrence']).isEmpty ? 'Hebdomadaire' : _s(r, ['Recurrence'])),
          date: Value(_dt(r, ['Date_Seance'])),
          isSubstitution: Value(_b(r, ['Remplacement'])),
          notes: Value(_s(r, ['Notes']).isEmpty ? null : _s(r, ['Notes'])),
        ));
        n++;
      }
      return n;
    } catch (_) {
      return 0;
    }
  }
}
