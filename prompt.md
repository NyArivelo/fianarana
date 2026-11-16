CAHIER DES CHARGES COMPLET
Application Desktop de gestion scolaire
Version : 1.1

Technologies principales : Flutter, Dart, SQLite (via Drift)

Langue principale : français

Plateformes cibles : Windows, Linux et macOS (Systèmes Desktop uniquement)

Type de déploiement initial : une installation monoposte/locale correspond à un seul établissement scolaire

Méthode de développement : progressive, modulaire, testée et versionnée avec Git

PARTIE I — MISSION ET OBJECTIFS
1. Rôle de l'IA
Tu es une équipe complète d'ingénierie logicielle composée d'un architecte logiciel senior, d'un développeur Flutter/Dart Desktop expérimenté, d'un spécialiste des bases de données relationnelles, d'un expert en sécurité informatique, d'un concepteur UX/UI Desktop, d'un ingénieur QA et d'un spécialiste de la génération documentaire.

Ta mission est de concevoir et développer une véritable application de gestion scolaire pour ordinateurs de bureau, robuste, maintenable, sécurisée, évolutive et utilisable en production.

Tu dois :

Analyser l'ensemble du cahier des charges avant de commencer.

Identifier les ambiguïtés, les dépendances et les risques techniques.

Proposer une architecture cohérente orientée Desktop.

Développer l'application progressivement, module par module.

Écrire du code réellement fonctionnel, pas seulement des exemples ou des maquettes.

Créer et maintenir une base de données cohérente utilisant des UUID pour toutes les entités principales.

Tester les règles métier et les fonctionnalités.

Utiliser Git avec des commits réguliers et explicites.

Documenter les décisions techniques et les procédures d'installation.

Préserver les données et la compatibilité lors des migrations.

Signaler honnêtement toute fonctionnalité non terminée ou impossible à valider.

Ne prétends jamais qu'une fonctionnalité est terminée si elle n'est pas implémentée et testée.

2. Objectif général
Développer un logiciel Desktop permettant de centraliser et de gérer les activités pédagogiques, administratives, financières et logistiques d'un établissement scolaire.

L'application doit pouvoir gérer notamment :

Les utilisateurs, rôles et permissions.

La structure pédagogique de l'établissement.

Les élèves, leurs inscriptions et leurs transferts (départs/quitus).

Les parents ou responsables légaux.

Les enseignants et les autres membres du personnel.

Les niveaux, classes, groupes, matières et programmes.

Les cours ordinaires, du soir, du week-end et les formations intensives.

Les calendriers scolaires, séances, emplois du temps et salles.

Les absences, retards, évaluations, conseils de classe, notes et résultats.

La discipline et le suivi des décisions.

Les finances, paiements, échéanciers, journaux de caisse, frais et reçus.

La bibliothèque et les prêts.

Les locaux, équipements, réservations et maintenances.

Les activités parascolaires et événements.

Les notifications et communications.

Les rapports et statistiques.

La création, l'importation, la personnalisation et la génération de documents administratifs et pédagogiques.

L'objectif est de fournir une solution intégrée et ergonomique sur grands écrans, et non une collection de modules indépendants.

3. Principes fondamentaux obligatoires
3.1 Un seul établissement par installation (Plateforme Desktop)
Une installation correspond à un établissement scolaire unique sur un ordinateur de bureau ou un réseau local.

Ne pas construire une plateforme multi-établissements ou un SaaS cloud dans lequel plusieurs écoles seraient mélangées dans une même base de données.

En revanche, un établissement peut gérer plusieurs types d'enseignement :

Préscolaire.

Primaire.

Collège.

Lycée.

Enseignement technique et professionnel.

Université ou enseignement supérieur.

Formations continues.

Cours du soir.

Cours du week-end.

Formations intensives ou ponctuelles.

Autres catégories définies par l'administrateur.

Ces catégories doivent être configurables. Ne pas imposer une hiérarchie unique incompatible avec tous les systèmes éducatifs.

3.2 Architecture modulaire et Clés Primaires UUID
Chaque domaine fonctionnel doit être organisé dans un module identifiable.
Les modules doivent communiquer par des interfaces et des services métier explicites.Toutes les entités de la base de données doivent utiliser des UUID (v4) comme clés primaires au lieu de simples identifiants auto-incrémentés, afin d'anticiper toute évolution vers une synchronisation multi-postes ou serveur distant sans risque de collision de données.

3.3 Sécurité intégrée
Les permissions doivent être vérifiées dans les services métier et les opérations sensibles, pas uniquement dans l'interface.

3.4 Traçabilité
Les modifications sensibles doivent pouvoir être retracées : auteur, date, opération, objet concerné et résultat, dans les limites des données qu'il est nécessaire de conserver.

3.5 Stockage local optimisé et évolution
SQLite (géré via Drift en Dart) constitue la base de données du déploiement local.
Les fichiers médias volumineux (photos des élèves, pièces jointes, justificatifs, scans PDF) ne doivent pas être stockés sous forme de BLOB dans SQLite. Ils seront stockés dans un dossier local structuré sur le disque de l'application, et la base de données ne conservera que le chemin relatif sécurisé et son empreinte (hash).

3.6 Documents personnalisables et rendu PDF natif
Les bulletins et documents administratifs doivent pouvoir être générés à partir de modèles réutilisables et configurables (en s'appuyant prioritairement sur le rendu natif Dart pdf/printing).

3.7 Qualité et ergonomie Desktop
Le code doit être lisible, testé, documenté et soumis à l'analyse statique. L'interface utilisateur doit être spécialement optimisée pour un usage Desktop (raccourcis clavier, saisie rapide en tableau style tableur, navigation multi-fenêtres ou onglets si pertinent).

PARTIE II — UTILISATEURS, RÔLES ET SÉCURITÉ
4. Authentification
Mettre en place un système d'authentification adapté à un logiciel Desktop.

Fonctionnalités :

Connexion par identifiant et mot de passe.

Hachage sécurisé des mots de passe (utilisation d'Argon2id ou bcrypt).

Déconnexion et verrouillage automatique de session en cas d'inactivité.

Changement de mot de passe.

Réinitialisation par un administrateur.

Désactivation et réactivation d'un compte.

Blocage ou ralentissement des tentatives de connexion répétées.

Protection contre les accès non autorisés.

Enregistrement des événements de sécurité pertinents.

Assistant de première installation (création du compte Administrateur initial).

5. Gestion dynamique des utilisateurs
L'administrateur doit pouvoir :

Créer un utilisateur.

Modifier son profil.

Activer ou désactiver son compte.

Réinitialiser ses accès.

Attribuer plusieurs rôles à un même utilisateur.

Retirer un rôle.

Consulter les journaux d'activité selon ses permissions.

Éviter les doublons entre le compte utilisateur et la fiche professionnelle d'une même personne.

6. Gestion dynamique des rôles
Fournir des rôles initiaux (Administrateur, Direction, Secrétariat, Économat/Caisse, Enseignant, Bibliothécaire, Surveillant).

L'administrateur doit pouvoir créer, renommer, modifier et attribuer des rôles. Il faut empêcher la suppression ou la désactivation accidentelle du dernier administrateur actif.

7. Système de permissions granulaires
Définir des permissions explicites associées aux ressources et actions (students.read, grades.validate, finance.close_cash_desk, etc.).

Distinguer pour chaque module : Lire, Créer, Modifier, Archiver, Valider, Rejeter, Publier, Annuler, Exporter, Imprimer, Supprimer.

8. Sécurité métier et confidentialité
Les contrôles d'accès doivent être faits dans les services applicatifs. Protéger strictement les données sensibles (dossiers disciplinaires, données financières, fiches RH, notes non publiées).

9. Journal d'audit
Enregistrer l'historique complet des actions sensibles (UUID de l'événement, horodatage UTC, utilisateur, module, objet ciblé, nature du changement, motif).

PARTIE III — PARAMÉTRAGE DE L'ÉTABLISSEMENT
10. Fiche de l'établissement
Saisie des informations de l'établissement : Nom, adresse, téléphone, courriel, logo (fichier local), devise, fuseau horaire, formats de date/heure, mentions légales pour les documents.

11. Paramètres généraux
Configuration des années scolaires, périodes, règles de notation, barèmes, arrondis, jours d'ouverture, règles d'archivage, numérotation automatique des factures et reçus.

PARTIE IV — STRUCTURE PÉDAGOGIQUE
12. Types d'enseignement et parcours
Configuration dynamique : Types d'enseignement, cycles, niveaux, promotions, filières, spécialités, matières, coefficients.

13. Années scolaires et périodes
Gestion des ouvertures/clôtures de périodes (trimestres, semestres). La clôture d'une période verrouille les notes et bulletins contre toute modification non autorisée.

14. Classes, groupes et matières
Gestion des affectations d'élèves et des enseignants aux classes et matières avec conservation de l'historique d'affectation.

PARTIE V — ÉLÈVES, INSCRIPTIONS ET TRANSFERTS
15. Dossier individuel de l'élève
Fiche complète avec UUID, matricule unique, identité, photo (fichier local), responsables légaux, historique médical/scolaire, pièces jointes numérisées.

16. Responsables légaux et contacts
Gestion des parents/tuteurs avec possibilité d'associer un responsable à plusieurs enfants (fratries) sans duplication de fiche.

17. Inscriptions, réinscriptions et suivi annuel
Gestion des statuts d'inscription (préinscription, validée, suspendue, abandon, réintégrée).

18. Procédure de transfert et certificats de sortie (Nouveau)
Lorsqu'un élève quitte l'établissement en cours d'année :

Procédure de validation préalable par le service financier (quitus de scolarité/frais régularisés).

Quitus de la bibliothèque (restitution de tous les ouvrages empruntés).

Génération automatique du Certificat de Radiation / Certificat de Sortie.

Changement du statut de l'élève vers "Transféré/Radiation" avec conservation intégrale de l'historique pour archives.

19. Recherche et importation Desktop
Interface optimisée avec filtres rapides, grille de recherche interactive, import/export CSV et XLSX avec prévisualisation et détection des doublons.

PARTIE VI — PERSONNEL ET ENSEIGNANTS
20. Dossiers du personnel & Affectations
Gestion de la fiche RH du personnel, spécialités, documents contractuels et affectations pédagogiques aux classes et cours.

PARTIE VII — COURS, SÉANCES ET CALENDRIER
21. Planification et Récurrences
Gestion des cours réguliers, cours du soir, cours du week-end et stages intensifs. Distinction stricte entre le cours théorique planifié et l'occurrence datée (séance réelle).

22. Emploi du temps et détection de conflits
Vues Desktop quotidiennes, hebdomadaires et mensuelles par classe, enseignant ou salle. Détection automatique des chevauchements de salles, d'enseignants ou de groupes.

PARTIE VIII — PRÉSENCES, ABSENCES ET RETARDS
23. Saisie rapide de l'appel
Interface de saisie accélérée pour l'appel (optimisée clavier). Suivi des absences, justifications, retards et statistiques.

PARTIE IX — ÉVALUATIONS, CONSEILS DE CLASSE ET BULLETINS
24. Saisie et calcul des notes
Saisie sous forme de grille tableur. Calculs automatisés des moyennes pondérées, des rangs et des mentions via des services métier dédiés et testés.

25. Conseils de classe et délibérations (Nouveau)
Module dédié à la préparation et au déroulement des conseils de classe.

Saisie des appréciations globales du conseil, des décisions d'orientation (passage, redoublement, avertissement travail, félicitations).

Procédure de verrouillage de période : Une fois la délibération validée, les notes et moyennes de la période concernée sont gelées. Aucune modification de note n'est possible sans une procédure explicite de déverrouillage réservée à la Direction et tracée en audit.

26. Bulletins et Relevés
Génération sécurisée des bulletins de notes. Un bulletin imprimé ou exporté conserve l'image exacte des données au moment de sa publication.

PARTIE X — DISCIPLINE ET SUIVI DES INCIDENTS
27. Dossiers disciplinaires
Gestion confidentielle des incidents, convocations, commissions disciplinaires, sanctions (retenues, exclusions temporaires) et suivi d'exécution des décisions.

PARTIE XI — FINANCES, ÉCONOMAT ET CAISSE
28. Catalogue des frais et Grilles tarifaires
Définition des frais de scolarité, inscriptions, cantine, transport, examens.

29. Échelonnements et plans de paiement (Nouveau)
Définition d'échéanciers de paiement personnalisés ou par classe (ex: paiement en 3 ou 10 tranches).

Suivi automatisé des échéances à venir, dues ou en retard.

Génération d'alertes de relance pour les impayés.

30. Enregistrement des paiements et Reçus
Gestion des paiements partiels, avoirs, remises et bourses. Génération d'un reçu numéroté pour chaque encaissement.

31. Journal et clôture de caisse quotidienne (Nouveau)
Journal de caisse : Suivi en temps réel des encaissements par caissier et par mode de paiement (espèces, chèque, virement).

Clôture de caisse (Z de caisse) : Procédure de fin de journée permettant à un agent de caisse de comptabiliser ses espèces, valider son solde avec le responsable et verrouiller les écritures de la journée.

PARTIE XII — BIBLIOTHÈQUE
32. Gestion du catalogue et emprunts
Gestion des notices bibliographiques et des exemplaires physiques. Prêts, retours, gestion des retards et blocage automatique du quitus en cas de livre non restitué.

PARTIE XIII — LOCAUX, ÉQUIPEMENTS ET ACTIVITÉS
33. Gestion des espaces et matériels
Réservation des salles (informatique, laboratoires, terrains) et inventaire du matériel avec suivi des maintenances.

PARTIE XIV — MODULE CENTRAL DE DOCUMENTS : DOCUMENT STUDIO
34. Conception et rendu documentaire Desktop
Module central pour tous les types de documents (bulletins, certificats, factures, reçus, cartes scolaires).

Conception privilégiant le rendu PDF natif Flutter/Dart pour garantir une fidélité visuelle parfaite à 100% sur Windows, Linux et macOS.

Moteur de calcul et de formules sécurisé sans exécution de code arbitraire (eval interdit).

Prévisualisation instantanée à l'écran et impression directe via le système d'exploitation.

PARTIE XV — ARCHITECTURE TECHNIQUE DESKTOP
35. Stack technique validée
Framework : Flutter (Cible : Windows, Linux, macOS Desktop).

Langage : Dart.

Base de données : SQLite via Drift (gestion des requêtes, migrations et typage fort).

Gestion d'état & DI : Riverpod.

Routage : go_router.

Génération PDF & Impression : Packages natifs pdf et printing.

Hachage sécurité : Argon2id ou bcrypt.

36. Ergonomie Desktop (UX/UI)
Grilles de données (DataGrid) supportant les raccourcis clavier (Navigation par flèches, Tab, Entrée pour validation).

Prise en charge du thème clair / sombre.

Menu latéral de navigation escamotable (NavigationRail / Drawer Desktop).

Support des résolutions HD et 4K avec adaptation responsive de la mise en page.

37. Sauvegarde, Restauration et Export
Sauvegarde manuelle et automatique programmée de la base SQLite et du dossier des pièces jointes sous forme d'une archive compressée .zip.

Restauration contrôlée avec contrôle d'intégrité avant écriture.

PARTIE XVI — PLAN DE DÉVELOPPEMENT PRIORISÉ
38. Phase 0 : Conception & Architecture de Base (En cours)
Validation définitive de la stack (Flutter Desktop + Drift SQLite + Riverpod).

Définition du schéma relationnel Drift avec des clés primaires UUID.

Structuration de l'architecture des dossiers du projet.

39. Phase 1 : MVP (Produit Minimum Viable)
Authentification & Gestion des utilisateurs/rôles/permissions.

Paramétrage de l'établissement et de la structure pédagogique.

Dossiers Élèves, Inscriptions et Responsables légaux.

Saisie des Cours, Emplois du temps et Présences.

Saisie des Notes, Conseils de classe et Bulletins de base (PDF).

Encaissement des frais de scolarité, Journal de caisse et Reçus.

Sauvegarde / Restauration locale.

PARTIE XXVIII — ERGONOMIE ET GESTION DESKTOP AVANCÉE
113. Interface Multi-Onglets (MDI - Multi-Document Interface)
L'application doit intégrer un système de navigation par onglets de travail au sein du même espace de bureau.

Un utilisateur (notamment au secrétariat ou à l'économat) doit pouvoir ouvrir simultanément plusieurs dossiers ou modules (ex: la fiche d'un élève, son échéancier de paiement et l'emploi du temps de sa classe) sans perdre la saisie en cours dans les autres onglets.

Chaque onglet doit conserver son propre état de saisie et proposer une option de fermeture rapide.

114. Raccourcis Clavier Globaux et Locaux
L'interface Desktop doit être entièrement utilisable au clavier pour les tâches à haute fréquence.

Raccourcis globaux obligatoire :

Ctrl + F (ou Cmd + F) : Ouverture du module de recherche rapide globale (Search Bar instantanée).

Ctrl + N : Création d'un nouvel enregistrement dans le module actif.

Ctrl + S : Sauvegarde/Validation du formulaire actif.

Ctrl + W : Fermeture de l'onglet actif.

Échap : Annulation/Fermeture des fenêtres modales.

Dans les grilles de saisie (DataGrids des notes, présences et paiements), la navigation par flèches directionnelles et la validation par Entrée ou Tabulation doivent permettre une saisie continue sans reprise de la souris.

115. Sécurité des Sessions sur Poste Partagé
Verrouillage rapide de session (Ctrl + L) : Un agent doit pouvoir verrouiller l'application sans fermer ses onglets en cours.

Changement rapide d'utilisateur (Quick Switch) : Prise en charge de la saisie d'un code PIN individuel à 4 ou 6 chiffres pour déverrouiller la session ou basculer sur un autre compte utilisateur sur le même ordinateur.

Déconnexion ou verrouillage automatique configurable après une période d'inactivité (ex: 5 minutes).

116. Corbeille et Rétention des Données (Suppression Logique)
Toute suppression effectuée par un utilisateur habilité (élève, classe, facture, note) ne doit pas être immédiatement détruite physiquement dans la base SQLite.

Les éléments supprimés sont déplacés vers une Corbeille administrative accessible uniquement aux comptes ayant le rôle Administrateur.

Rétention des données supprimées pendant un délai configurable (par défaut 30 jours) avant purge définitive, avec possibilité de restauration en un clic.

117. Restriction des Accès par Portée (Scope)
Les permissions granulaires doivent inclure une notion de portée applicative (Scope) :

Portée Établissement (Globale) : Accès à l'ensemble des classes/données (Direction, Secrétariat général).

Portée Restreinte (Affectations) : Un enseignant ne peut accéder qu'aux classes, matières et élèves auxquels il est explicitement affecté pour l'année en cours.

Portée Caisse : Un caissier ne voit que ses propres encaissements et son propre journal de caisse de la journée.

118. Inaltérabilité et Exportation Signée des Logs d'Audit
En cas de contrôle ou de litige financier/disciplinaire, l'administrateur doit pouvoir exporter une période du journal d'audit au format JSON/CSV accompagné d'une empreinte numérique (Hash SHA-256) garantissant que le fichier journal n'a pas été altéré après son exportation.

PARTIE XXIX — MAINTENABILITÉ ET CONFORMITÉ D'EXPLOITATION
119. Système de Mise à Jour Logique (Auto-Update Desktop)
L'application doit intégrer un service en arrière-plan capable de vérifier la disponibilité d'une nouvelle version (via un serveur d'API ou un dépôt de distributions sécurisé).

L'administrateur doit être notifié lorsqu'un correctif ou une évolution est disponible.

Le processus de mise à jour doit exécuter automatiquement les scripts de migration de schéma SQLite (Drift) au premier redémarrage après mise à jour, sans risque de perte de données.

120. Environnement de Formation et Mode Bac à Sable (Sandbox)
Lors de l'installation ou via les paramètres administratifs, l'application doit proposer un mode "Démonstration / Bac à Sable".

Ce mode permet d'injecter un jeu complet de données fictives (établissements, enseignants, classes, élèves, grilles de notes et comptabilité pré-remplies) pour former les nouveaux agents administratifs sans altérer la base de production.

Basculement instantané entre la base de production et la base d'entraînement via l'écran de connexion.

121. Flexibilité des Pièces d'État Civil et Conformité Régionale
Les formulaires d'inscription des élèves et des responsables doivent intégrer des champs configurables s'adaptant aux normes administratives du pays ou de la région (ex: numéro d'acte de naissance, numéro d'identification nationale, identifiants administratifs régionaux).

Les champs obligatoires et les formats de validation d'état civil doivent être paramétrables dans la fiche de l'établissement.

1. Gestion des cas particuliers d'évaluation (Pédagogie avancée)
Évaluations par compétences (Socle commun) : En plus de la notation chiffrée (ex: 0 à 20), intégrer la possibilité d'évaluer par niveau de maîtrise / compétences (Non acquis, En cours d'acquisition, Acquis, Expert).

Gestion des dispenses et neutralisation : Prise en charge explicite des élèves dispensés d'une matière (ex: EPS). La matière est neutralisée (le coefficient est exclu du calcul de la moyenne de l'élève) au lieu de mettre un zéro qui fausserait son bulletin.

2. Clôture d'année et Coffre-Fort d'Archivage Légale
Assistant de clôture annuelle : Génération d'une archive scellée et en lecture seule de l'année scolaire écoulée (bulletins définitifs, registres de notes, journaux de caisse). Cela permet de répondre aux obligations légales de conservation des archives sur plusieurs années tout en remettant à zéro la base de travail pour la nouvelle rentrée.

3. Gestion des Emplois du Temps et Remplacements d'Urgence
Module de gestion des absences des enseignants & remplacements : Lorsqu'un professeur est absent, pouvoir enregistrer l'absence et réaffecter temporairement une séance ou planifier un cours de rattrapage en détectant automatiquement les créneaux et salles libres.

4. Import / Export de données et Sauvegarde Automatisée
Sauvegarde automatique silencieuse au démarrage/fermeture : Création automatique d'une copie de sauvegarde locale horodatée de la base SQLite et des fichiers médias lors de la fermeture de l'application ou selon une fréquence paramétrable (ex: chaque soir à 18h).

Modèles d'importation guidés (Templates CSV/Excel) : Génération de fichiers modèles téléchargeables (pour l'import des élèves, des enseignants, ou des notes) afin de guider les utilisateurs et éviter les erreurs de colonnes lors des imports massifs.

5. Personnalisation de l'Interface et Accessibilité (Desktop)
Gestion des polices et tailles d'affichage (Scaling UI) : Permettre le redimensionnement dynamique de la taille du texte et des éléments de l'interface pour s'adapter aux différents écrans (PC portables vs grands écrans de bureau) et assurer le confort visuel des agents administratifs.

jointes:
a chaque fois que tu cree une fonctionnalite, ajoute les donnees de test correpondant