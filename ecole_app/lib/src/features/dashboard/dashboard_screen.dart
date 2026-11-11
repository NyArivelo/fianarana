import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../settings/settings_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _selected = 0;

  static const _modules = <(IconData, String, String)>[
    (Icons.dashboard_outlined, 'Tableau de bord', 'Vue d\'ensemble de l\'établissement'),
    (Icons.school_outlined, 'Élèves & Inscriptions', 'Dossiers élèves, responsables, inscriptions et transferts'),
    (Icons.people_outline, 'Personnel & Enseignants', 'Fiches RH et affectations pédagogiques'),
    (Icons.calendar_month_outlined, 'Cours & Emplois du temps', 'Planification, séances et détection de conflits'),
    (Icons.fact_check_outlined, 'Présences & Absences', 'Appel, retards et justifications'),
    (Icons.grading_outlined, 'Notes & Bulletins', 'Évaluations, conseils de classe et publication'),
    (Icons.payments_outlined, 'Finances & Caisse', 'Frais, paiements, reçus et clôtures'),
    (Icons.local_library_outlined, 'Bibliothèque', 'Catalogue, prêts et quitus'),
    (Icons.description_outlined, 'Document Studio', 'Modèles et génération documentaire'),
    (Icons.settings_outlined, 'Paramètres', 'Établissement, années scolaires et sécurité'),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.currentUser;
    final module = _modules[_selected];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: MediaQuery.of(context).size.width > 1100,
            selectedIndex: _selected,
            onDestinationSelected: (i) => setState(() => _selected = i),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  const Icon(Icons.school, size: 32),
                  if (MediaQuery.of(context).size.width > 1100)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Gestion Scolaire',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    tooltip: 'Déconnexion',
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).logout(),
                    icon: const Icon(Icons.logout),
                  ),
                ),
              ),
            ),
            destinations: [
              for (final m in _modules)
                NavigationRailDestination(
                  icon: Icon(m.$1),
                  label: Text(m.$2),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(module.$2,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall),
                              const SizedBox(height: 4),
                              Text(module.$3),
                            ],
                          ),
                        ),
                        if (user != null)
                          Chip(
                            avatar: const Icon(Icons.person, size: 18),
                            label: Text(user.displayName),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: switch (_selected) {
                    0 => _HomeOverview(username: user?.displayName ?? ''),
                    9 => const SettingsScreen(),
                    _ => _ModulePlaceholder(title: module.$2),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeOverview extends StatelessWidget {
  final String username;
  const _HomeOverview({required this.username});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: ListView(
        children: [
          Text('Bienvenue${username.isNotEmpty ? ', $username' : ''} 👋',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Base applicative initialisée (Flutter Desktop + Drift/SQLite, UUID, Riverpod, go_router). '
            'Les modules ci-contre sont structurés et seront développés progressivement conformément au cahier des charges.',
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: const [
              _InfoCard(
                icon: Icons.security,
                title: 'Sécurité',
                subtitle:
                    'Authentification, hachage bcrypt, rôles/permissions (schéma), audit (journal).',
              ),
              _InfoCard(
                icon: Icons.storage,
                title: 'Base de données',
                subtitle:
                    'SQLite via Drift, clés primaires UUID, tables cœur (utilisateurs, élèves, finance...).',
              ),
              _InfoCard(
                icon: Icons.construction,
                title: 'En cours (Phase 1)',
                subtitle:
                    'Paramétrage établissement, CRUD élèves/inscriptions, notes, caisse, documents PDF.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _InfoCard(
      {required this.icon, required this.title, required this.subtitle});

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
              Icon(icon, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
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

class _ModulePlaceholder extends StatelessWidget {
  final String title;
  const _ModulePlaceholder({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.build_circle_outlined, size: 56),
            const SizedBox(height: 12),
            Text('Module « $title »',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Ce module est prévu dans l\'architecture et sera implémenté progressivement '
              '(modèle de données, services métier, permissions, écrans et tests).',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
