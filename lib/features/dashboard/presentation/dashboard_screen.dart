import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fianarana/features/auth/application/auth_controller.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau de bord - Fianarana'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: Text(auth.fullName ?? auth.username ?? 'Utilisateur')),
          ),
          IconButton(
            tooltip: 'Verrouiller (Ctrl+L à implémenter)',
            onPressed: () => ref.read(authControllerProvider.notifier).lock(),
            icon: const Icon(Icons.lock_outline),
          ),
          IconButton(
            tooltip: 'Déconnexion',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: 0,
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), label: Text('Accueil')),
              NavigationRailDestination(icon: Icon(Icons.people_outline), label: Text('Élèves')),
              NavigationRailDestination(icon: Icon(Icons.fact_check_outlined), label: Text('Présences')),
              NavigationRailDestination(icon: Icon(Icons.payments_outlined), label: Text('Finances')),
              NavigationRailDestination(icon: Icon(Icons.settings_outlined), label: Text('Paramètres')),
            ],
            onDestinationSelected: (i) {
              switch (i) {
                case 1:
                  context.go('/students');
                  break;
                case 2:
                  context.go('/attendance');
                  break;
                case 3:
                  context.go('/finance');
                  break;
                default:
                  break;
              }
            },
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  Text(
                    'Fondations initialisées (Phase 0 / début MVP)',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _StatusCard(
                        title: 'Architecture',
                        subtitle: 'Flutter Desktop + Drift (UUID v4) + Riverpod + go_router',
                        icon: Icons.account_tree_outlined,
                      ),
                      _StatusCard(
                        title: 'Authentification & installation',
                        subtitle: 'Bootstrap/setup, création admin initial, connexion DB + bcrypt, verrouillage échecs',
                        icon: Icons.security_outlined,
                      ),
                      _StatusCard(
                        title: 'RBAC & Audit',
                        subtitle: 'Permissions granulaires/scope (services), rôles initiaux, journal d\'audit hashé',
                        icon: Icons.policy_outlined,
                      ),
                      _StatusCard(
                        title: 'Élèves & Inscriptions',
                        subtitle: 'Liste/recherche, fiche, création, responsables, statuts, procédure transfert/quitus (base)',
                        icon: Icons.people_outline,
                      ),
                      _StatusCard(
                        title: 'Données de test',
                        subtitle: 'Import seed: établissement, 325 élèves, classes, personnel, notes, finances, présences, audit...',
                        icon: Icons.dataset_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Prochaines étapes recommandées'),
                          SizedBox(height: 8),
                          Text('• Générer le code Drift (build_runner) et connecter la base SQLite locale'),
                          Text('• Implémenter le service d’authentification (hachage Argon2id/bcrypt, rôles, permissions, audit)'),
                          Text('• Créer l’assistant de première installation et le paramétrage établissement'),
                          Text('• Développer les modules Élèves/Inscriptions, Cours/Présences, Notes/Bulletins, Finances/Caisse'),
                          Text('• Ajouter à chaque fonctionnalité ses données de test et scénarios de validation'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  const _StatusCard({required this.title, required this.subtitle, required this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
