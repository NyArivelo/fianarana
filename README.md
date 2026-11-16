# Fianarana — Gestion scolaire Desktop

Application Desktop de gestion scolaire (installation locale monoposte, un établissement) développée avec **Flutter/Dart** et **SQLite via Drift**.

## État actuel (initialisation)

- Phase 0 démarrée : structure du projet, schéma de base de données Drift (UUID v4), modèles de base et données de test.
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

Le fichier `donnees_de_test.xlsx` est inclus. À chaque fonctionnalité créée, des données de test correspondantes doivent être ajoutées/mises à jour (seed).

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
