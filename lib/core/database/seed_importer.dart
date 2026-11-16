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
      counts['responsables'] = await _importGuardians();
      counts['eleves_inscriptions'] = await _importStudents();
      counts['evaluations'] = await _importEvaluations();
      counts['presences_discipline'] = await _importAttendance();
      counts['finances'] = await _importFinance();
      counts['bibliotheque_locaux'] = await _importLibraryFacilities();
      counts['audit'] = await _importAudit();
    });
    // RBAC/permissions de base (données de test sécurité) + trace d'import
    await RbacSeed(db).ensureDefaults();
    await AuditService(db).log(
      module: 'Système',
      targetObject: 'Base de données',
      description: 'Import des données de test terminé',
      result: 'Succès',
      metadata: counts,
    );
    return counts.entries.map((e) => '${e.key}=${e.value}').join(', ');
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
          id: id,
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
          id: id,
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
          id: id,
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
          id: roleId,
          name: roleName,
          description: const Value(null),
          isSystem: Value(roleName == 'Administrateur'),
        ));
      }
      final pin = _s(r, ['PIN_QuickSwitch', 'PIN']);
      await db.into(db.users).insertOnConflictUpdate(UsersCompanion.insert(
        id: userId,
        username: username,
        fullName: _s(r, ['Nom_Complet', 'Nom']),
        email: Value(_s(r, ['Email']).isEmpty ? null : _s(r, ['Email'])),
        passwordHash: defaultPass,
        pinHash: Value(pin.isEmpty ? null : passwordHasher.hash(pin)),
        isActive: Value(_b(r, ['Compte_Actif']) || _s(r, ['Compte_Actif']).isEmpty),
        scopeType: Value(_s(r, ['Portée_Scope', 'Portee_Scope']).isEmpty ? 'Globale' : _s(r, ['Portée_Scope', 'Portee_Scope'])),
        lastLoginAt: Value(_dt(r, ['Dernière_Connexion_UTC', 'Derniere_Connexion_UTC'])),
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
            id: levelId,
            name: levelName.isEmpty ? 'Niveau' : levelName,
            cycle: Value(_s(r, ['Niveau_Ou_Domaine'])),
            track: Value(_s(r, ['Série_Ou_Code', 'Serie_Ou_Code'])),
          ));
        }
        await db.into(db.classes).insertOnConflictUpdate(ClassesCompanion.insert(
          id: id,
          levelId: Value(levelId),
          label: _s(r, ['Libellé', 'Libelle']),
          capacity: Value(_i(r, ['Capacité_Ou_Coef_Sec2', 'Capacite_Ou_Coef_Sec2'], 0)),
          room: Value(_s(r, ['Salle_Ou_Classes_Cibles']).isEmpty ? null : _s(r, ['Salle_Ou_Classes_Cibles'])),
        ));
        n++;
      } else if (cat.contains('mati')) {
        final code = _s(r, ['Série_Ou_Code', 'Serie_Ou_Code', 'Code']).isEmpty ? id.substring(0, 8) : _s(r, ['Série_Ou_Code', 'Serie_Ou_Code', 'Code']);
        await db.into(db.subjects).insertOnConflictUpdate(SubjectsCompanion.insert(
          id: id,
          code: code,
          name: _s(r, ['Libellé', 'Libelle', 'Nom']),
          coefficientSec2: Value(_d(r, ['Capacité_Ou_Coef_Sec2', 'Capacite_Ou_Coef_Sec2'], 1)),
          coefficientSec3: Value(_d(r, ['Effectif_Ou_Coef_Sec3'], 1)),
          domain: Value(_s(r, ['Niveau_Ou_Domaine'])),
        ));
        n++;
      } else if (cat.contains('niveau')) {
        await db.into(db.levels).insertOnConflictUpdate(LevelsCompanion.insert(
          id: id,
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
        id: id,
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

  Future<int> _importGuardians() async {
    final rows = await _load('assets/seed/responsables_l_gaux.json');
    var n = 0;
    for (final r in rows) {
      final id = _s(r, ['UUID_Responsable', 'UUID']);
      if (id.isEmpty) continue;
      await db.into(db.guardians).insertOnConflictUpdate(GuardiansCompanion.insert(
        id: id,
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
        id: id,
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
          id: 'enr-$id',
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
        id: id,
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
        id: id,
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
        id: id,
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
          id: id,
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
            id: 'loan-$id',
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
          id: id,
          domain: domain.isEmpty ? 'Local' : domain,
          code: Value(_s(r, ['Code_Ou_ISBN'])),
          name: _s(r, ['Désignation_Ou_Titre', 'Designation_Ou_Titre']).isEmpty ? 'Espace' : _s(r, ['Désignation_Ou_Titre', 'Designation_Ou_Titre']),
          category: Value(_s(r, ['Catégorie_Ou_Auteur', 'Categorie_Ou_Auteur'])),
          capacity: Value(_i(r, ['Exemplaire_Ou_Capacité', 'Exemplaire_Ou_Capacite'], 0)),
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
}
