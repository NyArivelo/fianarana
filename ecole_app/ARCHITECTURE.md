# Architecture & état d'avancement

Application de gestion scolaire **Desktop mono-établissement** (Windows/Linux/macOS), développée de façon incrémentale.

## Stack
- **Flutter Desktop** (Dart 3.10 / Flutter 3.38)
- **Base de données** : SQLite via **Drift** (`lib/src/core/database/`), fichier local `ecole.sqlite` (app support `ecole_app/`), `PRAGMA foreign_keys = ON`
- **Clés primaires** : **UUID v4** (texte) + colonnes d'audit/suppression logique (`AuditColumns` / `isDeleted`, `deletedAt`)
- **Gestion d'état / DI** : **Riverpod**
- **Routage** : **go_router** (garde auth / première installation)
- **Sécurité** : hachage **bcrypt** (mots de passe), PIN de session hashé, audit (`AuditLogs`)
- **PDF/impression** : `pdf` / `printing` ; **import/export** : `csv`, `excel`, `file_picker` ; **sauvegarde** : `archive` + manifeste SHA-256

## Structure
- `lib/src/core/` : base Drift (tables, migrations, provider), sécurité/RBAC (`authorization_service`, `current_user_scope`), services transverses (préférences, sauvegarde/restauration auto & manuelle).
- `lib/src/features/` : modules (`auth`, `setup`, `dashboard`, `settings`, `academics`, `students`, `staff`, `schedule`, `attendance`, `grades`, `finance`, `documents`, `discipline`, `library`, `admin`).
- `lib/src/shared/` : composants partagés.

## Schéma Drift (version **11**, migrations incrémentales `onUpgrade`)
- **Sécurité/RH** : `Users` (dont `pinHash`), `Roles`, `Permissions`, `RolePermissions`, `UserRoles`, `AuditLogs`, `StaffMembers`, `TeacherAssignments`.
- **Établissement/pédagogie** : `SchoolSettings`, `AcademicYears`, `Periods`, `EducationTypes`, `Levels`, `Classes`, `Subjects`, `Rooms`.
- **Élèves** : `Students`, `Guardians`, `StudentGuardians`, `Enrollments` (statuts + quitus financier/bibliothèque + transfert).
- **Cours/présences** : `CourseSessions` (récurrences/conflits), `AttendanceRecords`.
- **Évaluations** : `Evaluations`, `Grades`, `CouncilDecisions` (verrouillage de période).
- **Finances** : `FeeTypes`, `Payments` (reçus numérotés), `CashClosures`, `PaymentPlans`, `PaymentInstallments`, `FinancialAdjustments` (remises/avoirs/bourses).
- **Documents** : `DocumentTemplates` (modèles de studio).
- **Discipline** : `DisciplinaryIncidents`, `DisciplinaryActions`.
- **Bibliothèque** : `LibraryItems`, `LibraryCopies`, `LibraryLoans`.
- **Locaux & équipements** : `EquipmentItems`, `RoomReservations`.

## Fonctionnalités implémentées
- **Auth & session** : bootstrap admin, connexion bcrypt, verrouillage après tentatives, audit ; espace **MDI** à onglets de modules (état conservé), verrouillage rapide `Ctrl+L`, fermeture onglet `Ctrl+W`, `Échap` (fermeture modale best-effort), auto-verrouillage après inactivité configurable, écran de verrouillage (mot de passe/PIN, changement rapide par identifiant+PIN).
- **Établissement & structure** : fiche établissement, années scolaires & périodes (clôture/réouverture), types/niveaux/matières/classes/salles.
- **Élèves & inscriptions** : CRUD élèves/responsables/inscriptions, recherche & filtres avancés (statut/genre/année/classe, respect de la portée), import/export **CSV/XLSX** complet (élève+inscription+responsable) avec modèle, prévisualisation/dédoublonnage et option de mise à jour, **transfert/quitus** (financier/bibliothèque, date/motif) avec génération de **certificat de radiation/sortie** PDF et conservation de l'historique.
- **Personnel** : fiches RH (`StaffMembers`), liaison compte utilisateur, gestion des **affectations pédagogiques** (`TeacherAssignments`).
- **Emploi du temps & présences** : séances (récurrences), détection de conflits, vues jour/semaine, appel/présences-absences-retards.
- **Notes & bulletins** : évaluations/notes, verrouillage/déverrouillage de période (audité), décisions de conseil, bulletin/rang enrichis (PDF).
- **Finances** : types de frais, encaissements/reçus `REC-YYYYMMDD-XXXX`, total journalier, plans/échéances, **clôture de caisse (Z)** avec blocage d'écriture du jour clôturé ; **ajustements** (remises/avoirs/bourses/réductions) et vue **impayés & soldes** (solde élève = planifié - ajustements actifs - paiements validés, alertes d'échéances en retard).
- **Documents / Document Studio** : génération/aperçu/impression PDF (reçus, certificats de scolarité, certificats de transfert/radiation, bulletins) ; **studio de modèles** (CRUD, catégories, aperçu contexte élève/paiement) avec **moteur de placeholders et formules sécurisé** (sans `eval`, expressions arithmétiques contrôlées `={{ ... }}`) et génération PDF depuis modèle.
- **Discipline** (base, portée globale) : incidents (confidentiel, statut ouvert/clôturé) et actions/sanctions (convocation, avertissement, retenue, exclusion temporaire, blâme…) avec suivi d'exécution ; recherche, filtres statut/élève.
- **Bibliothèque** (base, portée globale) : catalogue, exemplaires, prêts/retours, marquage automatique des retards, recherche/filtres (élève/statut actif-en retard-retourné, recherche élève/ouvrage/exemplaire) ; **quitus bibliothèque bloqué** en cas de prêts actifs/en retard.
- **Locaux & équipements** (base, portée globale) : gestion des salles/locaux, inventaire des équipements (état/affectation salle/quantité), **réservations de salles** avec détection de conflits.
- **Administration & sûreté** : RBAC/portées (`global|restricted|caisse`) et affectations enseignants, filtrage des données/écrans selon portée+classes autorisées, utilisateurs/rôles, export d'audit JSON signé (SHA-256), **corbeille** (liste/restauration/purge, purge par rétention, auditée) pour les principales entités dont discipline/bibliothèque, **sauvegarde/restauration** ZIP (DB+WAL/SHM+`attachments/`, manifeste SHA-256, contrôle d'intégrité) avec sauvegarde auto au démarrage et en cycle de vie.
- **Préférences** : échelle UI/texte et paramètres de verrouillage/sauvegarde auto persistés.

## Limites actuelles (périmètre partiel)
- **RBAC** : contrôle de permissions granulaire (ressource/action/scope) non appliqué exhaustivement dans tous les services/actions ; visibilité Discipline/Bibliothèque limitée à la portée globale.
- **Modules de base (non exhaustifs)** : Personnel/Discipline/Bibliothèque/Locaux & équipements fonctionnels mais à compléter (ex. rattachement contexte classe/année, reporting/statistiques, historique détaillé, liens emplois du temps/réservations avancés).
- **Cahier des charges restant / à approfondir** : studio documentaire encore basique (variables/contextes et mises en page limitées), pièces jointes locales hashées, règles financières avancées (numérotation paramétrable, facturation/avoirs comptables complets, politiques d'impayés), archivage de fin d'année, mise à jour automatique/sandbox, liens profonds MDI et raccourcis/navigation clavier étendus.
- **Tests** : pas de couverture automatisée complète ; validation principalement manuelle. `flutter analyze` sans erreur (infos/dépréciations mineures préexistantes possibles).

## Commandes utiles
- `flutter pub get` — dépendances
- `dart run build_runner build` — génération Drift
- `flutter analyze` — analyse statique
- `flutter run -d windows` — lancement Desktop Windows
