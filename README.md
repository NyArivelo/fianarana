# Fianarana — Gestion scolaire Desktop

Application Desktop de gestion scolaire (installation locale monoposte, un établissement) développée avec **Flutter/Dart** et **SQLite via Drift**.

## État actuel

- Phase 0 + MVP fonctionnel : authentification/RBAC, élèves/inscriptions, présences, notes/conseils/bulletins, finances/caisse, bibliothèque, locaux, personnel.
- Shell Desktop commun : en-tête global, navigation latérale persistante, barre d'état, thème clair/sombre, recherche globale (Ctrl+F), verrouillage (Ctrl+L).
- **Emplois du temps** : vues globale (agenda par jour), par classe et par enseignante, détection des conflits enseignant/classe/salle, création/modification/suppression de séances.
- **Calendrier scolaire** : calendrier mensuel par classe (avec événements d'établissement) et **éphéméride globale**, création/modification d'événements.
- **Élèves** : liste maître-détail, filtres (recherche/classe/statut), soldes MGA, quitus financier et bibliothèque, export CSV, ouverture du dossier complet.
- **Personnel** : fiches enseignantes/administration, accès direct au planning individuel.
- Données de test enrichies : 237 séances hebdomadaires, 94 affectations enseignantes, 36 événements de calendrier/éphéméride (`assets/seed/`).
- Cible : Windows, Linux, macOS.
- Base locale : SQLite (Drift), avec chemins relatifs pour les fichiers médias (pas de BLOB).

## Stack technique

- Flutter Desktop / Dart
- SQLite via Drift
- Riverpod (état/DI)
- go_router (routage)
- pdf / printing (documents)
- bcrypt/argon2id (hachage mots de passe — à finaliser selon support plateforme)

## Structure

- `lib/core/` : base de données, sécurité, thème, routage, utilitaires
- `lib/features/` : modules fonctionnels (auth, paramètres, élèves, etc.)
- `assets/seed/` : données de test extraites
- `donnees_de_test.xlsx` : jeu de données source fourni

## Données de test

Le fichier `donnees_de_test.xlsx` est inclus et exporté en JSON dans `assets/seed/` (établissement, 325 élèves, 11 classes, personnel, notes, finances, présences, bibliothèque, audit, etc.).  
À chaque fonctionnalité créée, des données de test correspondantes doivent être ajoutées/mises à jour (seed).

- `emploi_du_temps.json` : planning hebdomadaire complet (237 séances, 11 classes) sans conflit.
- `affectations_enseignants.json` : 94 affectations classe/matière/enseignante.
- `calendrier_scolaire.json` : 36 événements (rentrée, vacances, examens, réunions, sorties, éphéméride globale).
- Réimport possible depuis **Paramètres → Données de test → Réimporter** (compte administrateur).

- **Assistant de première installation** (`/setup`) : crée le compte administrateur initial et peut importer automatiquement toutes les données de test en base SQLite.
- **Comptes seed (après import)** : identifiants issus du fichier (ex. `admin.sys`, `dir.general`, `caisse.01`, etc.). Mot de passe de test initial : `Password123!` (PIN seed importé si présent). **À changer en production.**

## Prérequis de développement

- Flutter SDK (canal stable) avec support Desktop
- Dart SDK
- Outils de build natifs par plateforme (Visual Studio Build Tools pour Windows, etc.)

## Commandes (quand Flutter est installé)

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows # ou linux / macos
```

## Notes

- Cette initialisation pose les fondations (schéma et architecture). L'exécution complète nécessite le SDK Flutter Desktop.
- Les clés primaires sont des UUID v4 pour toutes les entités principales.
- Les suppressions seront implémentées en suppression logique (corbeille) conformément au cahier des charges.
