# Architecture & État d'avancement (Phase 0 / début Phase 1)

## Stack mise en place
- **Flutter Desktop** (Windows, Linux, macOS) — Dart 3.10 / Flutter 3.38
- **Base de données** : SQLite via **Drift** (`lib/src/core/database/`)
- **Clés primaires** : **UUID v4** (texte) pour toutes les entités principales (`UuidPrimaryKey`)
- **Gestion d'état / DI** : **Riverpod**
- **Routage** : **go_router** (garde d'authentification / première installation)
- **Sécurité** : hachage des mots de passe **bcrypt** (`PasswordHasher`), journal d'audit (`AuditLogs`)

## Structure des dossiers
- `lib/src/core/` : base de données (tables Drift, provider), sécurité, utilitaires, (à venir: routing/theme/services transverses)
- `lib/src/features/` : modules fonctionnels (`auth`, `setup`, `dashboard`, `students`, `staff`, `academics`, `finance`, `documents`…)
- `lib/src/shared/` : widgets et services partagés

## Schéma Drift (fondations)
Tables créées (UUID, colonnes d'audit/suppression logique) : `Users`, `Roles`, `Permissions`, `RolePermissions`, `UserRoles`, `AuditLogs`, `SchoolSettings`, `AcademicYears`, `Periods`, `EducationTypes`, `Levels`, `Classes`, `Subjects`, `Students`, `Guardians`, `StudentGuardians`, `Enrollments`, `FeeTypes`, `Payments`, `CashClosures`.
> Le schéma doit être enrichi progressivement pour couvrir l'ensemble du cahier des charges (emplois du temps/séances, notes/évaluations/conseils, discipline, bibliothèque, locaux, plans de paiement, corbeille avancée, etc.).

## Fonctionnalités implémentées (par étapes)

### Socle (Phase 0 / initial)
- **Assistant de première installation** : création du compte Administrateur initial si aucun utilisateur n'existe.
- **Authentification** : connexion identifiant/mot de passe, vérification bcrypt, désactivation/compte inactif, verrouillage temporaire après tentatives répétées, mise à jour `lastLoginAt`, audit des connexions (succès/échec).
- **Application shell Desktop** : navigation latérale (NavigationRail), tableau de bord, déconnexion, thème clair/sombre (Material 3).

### Étape 1 — Paramétrage établissement
- Fiche établissement (nom, adresse, contacts, devise, fuseau horaire, formats date/heure, mentions légales) avec persistance en base.
- Gestion des **années scolaires** (création/modification, année en cours) et des **périodes** (ajout, clôture/réouverture, suppression logique).

### Étape 2 — Structure pédagogique
- CRUD de base : **types d'enseignement**, **niveaux**, **matières** (code/coefficient), **classes** rattachées à l'année scolaire (et niveau/capacité).

### Étape 3 — CRUD élèves, responsables, inscriptions
- Liste/recherche des élèves, création/modification/archivage (suppression logique), fiche détail.
- **Responsables légaux** : création et liaison à l'élève (gestion de base des liens).
- **Inscriptions** : création par année scolaire/classe avec statut (préinscription, validée, etc.).

### Étape 4 — Finances (base)
- **Types de frais** (catalogue/montant par défaut).
- **Paiements/encaissements** : sélection élève/frais/mode, génération d'un **numéro de reçu** (`REC-YYYYMMDD-XXXX`), enregistrement du caissier, journal des paiements et total encaissé du jour.

### Étape 5 — Documents (Document Studio de base)
- Génération/aperçu/impression PDF natif (`pdf`/`printing`) : **reçu de paiement** (à partir d'un encaissement) et **certificat de scolarité** (à partir d'un élève), avec informations établissement.

## Décisions & limites actuelles (important)
- **RBAC granulaire & portée** : tables et amorce présentes ; l'application fine des permissions (ressource/action/scope) dans tous les services/écrans reste à généraliser.
- **Élèves/inscriptions** : CRUD de base opérationnel ; restent à faire (cahier des charges) la procédure complète de transfert/quitus (financier + bibliothèque) avec certificat de radiation, recherche/filtres avancés, import/export CSV/XLSX avec prévisualisation/dédoublonnage, historique complet et pièces jointes (fichiers locaux + hash, sans BLOB).
- **Structure pédagogique** : entités de base gérées ; restent affectations détaillées/historiques, programmes, etc.
- **Finances** : catalogue, encaissements, reçus et journal de base ; restent échéanciers/plans de paiement, alertes d'impayés, avoirs/remises/bourses avancés, journal/clôture de caisse (Z) complète par caissier/mode, numérotation paramétrable.
- **Document Studio** : génération PDF native de reçus/certificats ; reste le studio complet de modèles configurables, moteur de formules sécurisé (sans `eval`), bulletins/factures/cartes, etc.
- **Non implémentés à ce stade** : emploi du temps/séances & conflits, présences, notes/conseils/bulletins complets, discipline, bibliothèque, locaux/équipements, sauvegarde/restauration, MDI multi-onglets, raccourcis globaux, verrouillage rapide/PIN, corbeille UI & rétention, export d'audit signé, auto-update/migrations incrémentales avancées, mode bac à sable, etc.
- **Migrations** : `schemaVersion = 1` avec `onCreate` ; stratégie de migration incrémentale à compléter à chaque évolution de schéma. `flutter analyze` : sans erreur.

## Commandes utiles
- Dépendances : `flutter pub get`
- Génération Drift : `dart run build_runner build`
- Analyse statique : `flutter analyze`
- Lancement (Windows) : `flutter run -d windows`

## Prochaines étapes recommandées (Phase 1)
1. Paramétrage établissement & années scolaires/périodes (UI + services).
2. CRUD Élèves, responsables, inscriptions (avec statuts) et recherche/filtres.
3. Structure pédagogique (types, niveaux, classes, matières) et affectations.
4. Emplois du temps/séances, présences (saisie rapide), notes et bulletins PDF de base.
5. Encaissements/frais/journal de caisse, reçus numérotés et clôture.
6. Sauvegarde/restauration locale (.zip) et durcissement permissions/audit.
