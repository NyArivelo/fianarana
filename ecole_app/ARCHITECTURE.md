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

## Fonctionnalités implémentées (MVP initial)
- **Assistant de première installation** : création du compte Administrateur initial si aucun utilisateur n'existe.
- **Authentification** : connexion identifiant/mot de passe, vérification bcrypt, désactivation/compte inactif, verrouillage temporaire après tentatives répétées, mise à jour `lastLoginAt`, audit des connexions (succès/échec).
- **Application shell Desktop** : navigation latérale (NavigationRail) avec modules prévus, écran tableau de bord, déconnexion, thème clair/sombre (Material 3).

## Décisions & limites actuelles
- Rôles/permissions : tables et amorce de modèle présentes ; l'application fine des permissions dans les services/écrans reste à généraliser (RBAC granulaire par ressource/action/portée).
- Stockage des fichiers médias : non encore câblé (prévu : dossier local structuré + chemin relatif + hash, pas de BLOB).
- Documents/PDF : dépendances `pdf`/`printing` ajoutées, **Document Studio** et génération de bulletins/reçus/certificats à implémenter.
- Sauvegarde/restauration, import/export CSV/XLSX, multi-onglets (MDI), raccourcis globaux, PIN/verrouillage rapide, corbeille UI, sandbox : **non implémentés** à ce stade.
- Migrations : `schemaVersion = 1` avec `onCreate`; stratégie de migration incrémentale à compléter à chaque évolution de schéma.

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
