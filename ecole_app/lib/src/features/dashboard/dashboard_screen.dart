import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/current_user_scope.dart';
import '../../core/services/app_preferences.dart';
import '../attendance/attendance_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/lock_screen.dart';
import '../documents/documents_screen.dart';
import '../facilities/facilities_screen.dart';
import '../finance/finance_screen.dart';
import '../grades/grades_screen.dart';
import '../discipline/discipline_screen.dart';
import '../library/library_screen.dart';
import '../schedule/schedule_screen.dart';
import '../settings/settings_screen.dart';
import '../staff/staff_screen.dart';
import '../students/students_screen.dart';

class _WorkspaceTab {
  final int moduleIndex;
  final String title;
  final IconData icon;
  final Widget child;
  _WorkspaceTab({required this.moduleIndex, required this.title, required this.icon, required this.child});
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final List<_WorkspaceTab> _tabs = [];
  int _activeTab = 0;
  Timer? _inactivityTimer;

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
    (Icons.gavel_outlined, 'Discipline', 'Incidents, sanctions et suivi'),
    (Icons.meeting_room_outlined, 'Locaux & équipements', 'Salles, inventaire et réservations'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openModule(0);
      _resetInactivityTimer();
    });
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }

  Set<int> _allowedIndices(String scope) => <int>{
        0, 1, 3, 4, 5, 8, 9,
        if (scope == 'global' || scope == 'caisse') 6,
        if (scope == 'global') 2,
        if (scope == 'global') 7,
        if (scope == 'global') 10,
        if (scope == 'global') 11,
      };

  Widget _buildModuleWidget(int idx, String username) {
    return switch (idx) {
      0 => _HomeOverview(username: username),
      1 => const StudentsScreen(),
      2 => const StaffScreen(),
      3 => const ScheduleScreen(),
      4 => const AttendanceScreen(),
      5 => const GradesScreen(),
      6 => const FinanceScreen(),
      7 => const LibraryScreen(),
      8 => const DocumentsScreen(),
      9 => const SettingsScreen(),
      10 => const DisciplineScreen(),
      11 => const FacilitiesScreen(),
      _ => _ModulePlaceholder(title: _modules[idx].$2),
    };
  }

  void _openModule(int moduleIndex) {
    final existing = _tabs.indexWhere((t) => t.moduleIndex == moduleIndex);
    if (existing != -1) {
      setState(() => _activeTab = existing);
      return;
    }
    final user = ref.read(authControllerProvider).currentUser;
    final tab = _WorkspaceTab(
      moduleIndex: moduleIndex,
      title: _modules[moduleIndex].$2,
      icon: _modules[moduleIndex].$1,
      child: _buildModuleWidget(moduleIndex, user?.displayName ?? ''),
    );
    setState(() {
      _tabs.add(tab);
      _activeTab = _tabs.length - 1;
    });
  }

  void _closeTab(int index) {
    if (_tabs.isEmpty) return;
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        _activeTab = 0;
      } else if (_activeTab >= _tabs.length) {
        _activeTab = _tabs.length - 1;
      } else if (index < _activeTab) {
        _activeTab -= 1;
      }
    });
  }

  void _closeActiveTab() {
    if (_tabs.isEmpty) return;
    _closeTab(_activeTab);
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    final auth = ref.read(authControllerProvider);
    if (auth.currentUser == null || auth.locked) return;
    final minutes = ref.read(appPreferencesProvider).inactivityLockMinutes;
    if (minutes <= 0) return;
    _inactivityTimer = Timer(Duration(minutes: minutes), () {
      if (!mounted) return;
      final a = ref.read(authControllerProvider);
      if (a.currentUser != null && !a.locked) {
        ref.read(authControllerProvider.notifier).lock();
      }
    });
  }

  void _onUserActivity() {
    _resetInactivityTimer();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.currentUser;
    final scope = ref.watch(currentUserScopeProvider).valueOrNull?.scope ?? 'global';
    ref.listen(appPreferencesProvider, (_, __) => _resetInactivityTimer());
    final allowed = _allowedIndices(scope);
    _tabs.removeWhere((t) => !allowed.contains(t.moduleIndex));
    if (_tabs.isEmpty) {
      _openModule(0);
    }
    if (_activeTab >= _tabs.length) _activeTab = _tabs.length - 1;

    final visibleIndices = [for (int i = 0; i < _modules.length; i++) if (allowed.contains(i)) i];
    final activeModuleIndex = _tabs.isNotEmpty ? _tabs[_activeTab].moduleIndex : 0;
    final selectedVisibleIndex = visibleIndices.indexOf(activeModuleIndex);

    return Listener(
      onPointerDown: (_) => _onUserActivity(),
      onPointerMove: (_) => _onUserActivity(),
      onPointerSignal: (_) => _onUserActivity(),
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyL, control: true): () {
            if (!auth.locked && auth.currentUser != null) ref.read(authControllerProvider.notifier).lock();
          },
          const SingleActivator(LogicalKeyboardKey.keyW, control: true): _closeActiveTab,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            // Best-effort: close topmost dialog/modal if any
            final nav = Navigator.maybeOf(context);
            if (nav != null && nav.canPop()) nav.pop();
          },
        },
        child: Focus(
          autofocus: true,
          child: Stack(children: [
            Scaffold(
              body: Row(
                children: [
                  NavigationRail(
                    extended: MediaQuery.of(context).size.width > 1100,
                    selectedIndex: selectedVisibleIndex == -1 ? null : selectedVisibleIndex,
                    onDestinationSelected: (i) => _openModule(visibleIndices[i]),
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          const Icon(Icons.school, size: 32),
                          if (MediaQuery.of(context).size.width > 1100)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('Gestion Scolaire', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                    ),
                    trailing: Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(tooltip: 'Verrouiller (Ctrl+L)', onPressed: () => ref.read(authControllerProvider.notifier).lock(), icon: const Icon(Icons.lock_outline)),
                            IconButton(tooltip: 'Déconnexion', onPressed: () => ref.read(authControllerProvider.notifier).logout(), icon: const Icon(Icons.logout)),
                          ]),
                        ),
                      ),
                    ),
                    destinations: [
                      for (final i in visibleIndices)
                        NavigationRailDestination(icon: Icon(_modules[i].$1), label: Text(_modules[i].$2)),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Material(
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        child: SizedBox(
                          height: 40,
                          child: Row(children: [
                            Expanded(child: _tabs.isEmpty ? const SizedBox.shrink() : ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _tabs.length,
                              itemBuilder: (context, i) {
                                final t = _tabs[i];
                                final active = i == _activeTab;
                                return InkWell(
                                  onTap: () => setState(() => _activeTab = i),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: active ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 2))),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(t.icon, size: 16),
                                      const SizedBox(width: 6),
                                      Text(t.title, style: TextStyle(fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                                      const SizedBox(width: 6),
                                      InkWell(onTap: () => _closeTab(i), child: const Icon(Icons.close, size: 16)),
                                    ]),
                                  ),
                                );
                              },
                            )),
                            if (user != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Chip(avatar: const Icon(Icons.person, size: 18), label: Text('${user.displayName} ($scope)')),
                              ),
                          ]),
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: _tabs.isEmpty
                            ? const SizedBox.shrink()
                            : IndexedStack(index: _activeTab, children: [for (final t in _tabs) t.child]),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
            if (auth.locked) const LockScreen(),
          ]),
        ),
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
          Text('Bienvenue${username.isNotEmpty ? ', $username' : ''} 👋', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Espace de travail Desktop (MDI) : ouvrez plusieurs modules en onglets via le menu latéral, conservez vos saisies en changeant d\'onglet. '
            'Raccourcis : Ctrl+L verrouiller, Ctrl+W fermer l\'onglet actif, Échap fermer une fenêtre modale.',
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: const [
              _InfoCard(icon: Icons.tab, title: 'Multi-onglets (MDI)', subtitle: 'Plusieurs modules ouverts simultanément, état conservé par onglet.'),
              _InfoCard(icon: Icons.lock_clock, title: 'Verrouillage de session', subtitle: 'Verrouillage rapide (Ctrl+L), auto-verrouillage après inactivité, déverrouillage par mot de passe/PIN et changement rapide d\'utilisateur.'),
              _InfoCard(icon: Icons.security, title: 'Sécurité & portée', subtitle: 'RBAC/portées, audit, corbeille, sauvegardes et contrôles d\'accès étendus.'),
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
  const _InfoCard({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(subtitle),
            ])),
          ]),
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.build_circle_outlined, size: 56),
          const SizedBox(height: 12),
          Text('Module « $title »', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Ce module est prévu dans l\'architecture et sera implémenté progressivement (modèle de données, services métier, permissions, écrans et tests).', textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
