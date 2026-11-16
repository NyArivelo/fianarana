# Architecture initiale (Phase 0)

## Stack

- Flutter Desktop (Windows/Linux/macOS), Dart
- Base locale: SQLite via Drift (`lib/core/database`)
- État/DI: Riverpod
- Routage: go_router
- Documents: pdf/printing (prévu)

## Principes appliqués

- **UUID v4** pour toutes les entités principales (tables Drift).
- **Suppression logique** prévue (`isDeleted`, `deletedAt`) sur les entités principales.
- **Médias hors BLOB**: stockage fichiers local + chemin relatif + hash en base.
- **Sécurité métier**: à appliquer dans les services (pas seulement UI).
- **Audit**: table `audit_logs` avec horodatage UTC, acteur, module, objet, résultat, hash.

## Structure des dossiers

- `lib/core/database/` : tables Drift, connexion, seed, UUID
- `lib/core/routing/` : configuration go_router
- `lib/core/theme/` : thèmes clair/sombre Desktop
- `lib/features/auth/` : authentification (UI + contrôleur; service sécurisé à compléter)
- `lib/features/dashboard/` : tableau de bord initial
- `assets/seed/` : jeux de données de test JSON dérivés de `donnees_de_test.xlsx`

## Données de test

Source: `donnees_de_test.xlsx` (325 élèves, 11 classes, 21 enseignantes, paiements, notes, présences, bibliothèque, audit, etc.).  
Export JSON: `assets/seed/*.json`.  
Règle: **à chaque fonctionnalité créée, ajouter les données de test correspondantes** (seed/mise à jour).

## Prochaines étapes

1. Générer le code Drift (`dart run build_runner build`) avec SDK Flutter/Dart.
2. Implémenter services: auth (hachage bcrypt/argon2id), RBAC permissions/scope, audit.
3. Assistant première installation (création admin, établissement, année scolaire).
4. Modules MVP: élèves/inscriptions, structure pédagogique, présences, notes/conseils/bulletins, finances/caisse, sauvegarde/restauration.
5. Document Studio (PDF natif), corbeille, multi-onglets, raccourcis clavier, verrouillage/PIN.
