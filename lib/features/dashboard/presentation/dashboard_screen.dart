import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fianarana/core/workspace/tab_workspace.dart';
import 'package:fianarana/core/workspace/workspace_shell.dart';
import 'package:fianarana/features/attendance/presentation/attendance_screen.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/facilities/presentation/facilities_screen.dart';
import 'package:fianarana/features/finance/presentation/finance_screen.dart';
import 'package:fianarana/features/grades/presentation/grades_screen.dart';
import 'package:fianarana/features/library/presentation/library_screen.dart';
import 'package:fianarana/features/search/presentation/global_search_dialog.dart';
import 'package:fianarana/features/settings/presentation/settings_screen.dart';
import 'package:fianarana/features/staff/presentation/staff_screen.dart';
import 'package:fianarana/features/students/presentation/students_screen.dart';
import 'package:fianarana/features/timetable/presentation/timetable_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  void _open(WidgetRef ref, BuildContext context, String id, String title, String route, Widget screen) {
    openModuleTab(ref, id: id, title: title, route: route, builder: (_) => screen);
    context.go(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(49),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF1E40AF)])),
              child: const Icon(Icons.school, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Row(children: [
                Text('Fianarana — Gestion scolaire', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF0F172A))),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: isDark ? const Color(0xFF172554) : const Color(0xFFDBEAFE), borderRadius: BorderRadius.circular(4), border: Border.all(color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFBFDBFE))),
                  child: Text('2026-2027', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8))),
                ),
              ]),
              Text('Installation locale • SQLite Drift (UUID)', style: TextStyle(fontSize: 10, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
            ]),
            const Spacer(),
            SizedBox(
              width: 360,
              height: 32,
              child: InkWell(
                onTap: () => showGlobalSearch(context),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: border),
                  ),
                  child: Row(children: [
                    const Icon(Icons.search, size: 15, color: Color(0xFF2563EB)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Rechercher un élève, matricule, classe... (Ctrl+F)', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)))),
                  ]),
                ),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: isDark ? const Color(0xFF052E2B) : const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8), border: Border.all(color: isDark ? const Color(0xFF065F46) : const Color(0xFFA7F3D0))),
              child: Row(children: [
                Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('Base locale', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857))),
              ]),
            ),
            const SizedBox(width: 8),
            IconButton(onPressed: () => ref.read(authControllerProvider.notifier).lock(), icon: const Icon(Icons.lock_outline, size: 18)),
            Container(width: 1, height: 24, color: border, margin: const EdgeInsets.symmetric(horizontal: 4)),
            CircleAvatar(radius: 13, backgroundColor: const Color(0xFF2563EB), child: Text((auth.fullName ?? auth.username ?? 'U').characters.first.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
            const SizedBox(width: 6),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(auth.fullName ?? auth.username ?? 'Utilisateur', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF0F172A))),
              Text(auth.scopeType ?? 'Session', style: const TextStyle(fontSize: 10, color: Color(0xFF2563EB))),
            ]),
            IconButton(onPressed: () => ref.read(authControllerProvider.notifier).logout(), icon: const Icon(Icons.logout, size: 18)),
          ]),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(children: [
              // Sidebar
              Container(
                width: 228,
                decoration: BoxDecoration(color: isDark ? const Color(0xFF0F172A) : Colors.white, border: Border(right: BorderSide(color: border))),
                child: Column(children: [
                  Expanded(child: ListView(padding: const EdgeInsets.all(8), children: [
                    _sideLabel('Pilotage & Scolarité'),
                    _navItem(context, icon: Icons.dashboard_rounded, label: 'Tableau de bord', selected: true, onTap: () {}),
                    _navItem(context, icon: Icons.people_outline, label: 'Élèves & Inscriptions', badge: '325', onTap: () => _open(ref, context, 'tab-students','Élèves','/students', const StudentsScreen())),
                    _navItem(context, icon: Icons.fact_check_outlined, label: 'Présences & Discipline', onTap: () => _open(ref, context, 'tab-attendance','Présences','/attendance', const AttendanceScreen())),
                    _navItem(context, icon: Icons.grading_outlined, label: 'Évaluations & Notes', onTap: () => _open(ref, context, 'tab-grades','Notes','/grades', const GradesScreen())),
                    _navItem(context, icon: Icons.calendar_month_outlined, label: 'Emplois du temps', onTap: () => _open(ref, context, 'tab-timetable','Emploi du temps','/timetable', const TimetableScreen())),
                    const SizedBox(height: 6),
                    _sideLabel('Administration & Ressources'),
                    _navItem(context, icon: Icons.payments_outlined, label: 'Finances & Caisse', onTap: () => _open(ref, context, 'tab-finance','Finances','/finance', const FinanceScreen())),
                    _navItem(context, icon: Icons.badge_outlined, label: 'Personnel & RH', badge: '21', onTap: () { openModuleTab(ref,id:'tab-staff',title:'Personnel',route:'/staff',builder:(_)=>const StaffScreen()); context.go('/staff'); }),
                    _navItem(context, icon: Icons.menu_book_outlined, label: 'Bibliothèque & Quitus', onTap: () { openModuleTab(ref,id:'tab-library',title:'Bibliothèque',route:'/library',builder:(_)=>const LibraryScreen()); context.go('/library'); }),
                    _navItem(context, icon: Icons.meeting_room_outlined, label: 'Locaux & équipements', onTap: () { openModuleTab(ref,id:'tab-facilities',title:'Locaux',route:'/facilities',builder:(_)=>const FacilitiesScreen()); context.go('/facilities'); }),
                    _navItem(context, icon: Icons.settings_outlined, label: 'Paramètres', onTap: () => _open(ref, context, 'tab-settings','Paramètres','/settings', const SettingsScreen())),
                  ])),
                  Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF172554).withOpacity(0.4) : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFBFDBFE)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                      Row(children: [Icon(Icons.storage, size: 14, color: Color(0xFF2563EB)), SizedBox(width: 6), Text('Sauvegarde & base', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))]),
                      SizedBox(height: 4),
                      Text('SQLite Drift locale • Sauvegarde .zip', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
                      Text('Raccourcis: Ctrl+W fermer', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                      Text('v1.1', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                    ]),
                  ),
                ]),
              ),
              // Main content
              Expanded(
                child: Container(
                  color: isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Tableau de bord de l\'établissement', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF0F172A))),
                          const SizedBox(height: 4),
                          Text('Synthèse en temps réel — Gestion scolaire locale (modules, données et sécurité).', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
                        ])),
                        FilledButton.icon(onPressed: () => _open(ref, context, 'tab-students','Élèves','/students', const StudentsScreen()), icon: const Icon(Icons.person_add_alt_1, size: 16), label: const Text('Nouvelle inscription')),
                      ]),
                      const SizedBox(height: 16),
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        _kpi(context, 'Élèves inscrits', '325', Icons.people_outline, const Color(0xFF2563EB), 'Données seed importées'),
                        _kpi(context, 'Classes actives', '11', Icons.layers_outlined, const Color(0xFF7C3AED), '3ème à Terminale'),
                        _kpi(context, 'Évaluations', '940', Icons.grading_outlined, const Color(0xFF059669), 'Notes & bulletins'),
                        _kpi(context, 'Transactions', '325', Icons.payments_outlined, const Color(0xFFD97706), 'Paiements & caisse'),
                      ]),
                      const SizedBox(height: 16),
                      Wrap(spacing: 12, runSpacing: 12, children: const [
                        _StatusCard(title: 'Élèves & Inscriptions', subtitle: 'Dossiers, édition, responsables, inscriptions, transfert/quitus (base).', icon: Icons.people_outline),
                        _StatusCard(title: 'Présences & Discipline', subtitle: 'Consultation, filtres et saisie rapide des appels/événements.', icon: Icons.fact_check_outlined),
                        _StatusCard(title: 'Notes & Conseils', subtitle: 'Évaluations, moyenne pondérée, conseils/décisions, verrouillage période, bulletins PDF.', icon: Icons.grading_outlined),
                        _StatusCard(title: 'Finances & Caisse', subtitle: 'Encaissements, reçus PDF, clôture Z, échéanciers/relances, export CSV.', icon: Icons.payments_outlined),
                        _StatusCard(title: 'Emplois du temps', subtitle: 'Séances planifiées et détection de conflits enseignant/classe/salle.', icon: Icons.calendar_month_outlined),
                        _StatusCard(title: 'Personnel & RH', subtitle: 'Gestion du personnel/enseignants, affectations (données seed).', icon: Icons.badge_outlined),
                        _StatusCard(title: 'Bibliothèque & Locaux', subtitle: 'Catalogue, prêts/quitus, locaux et équipements.', icon: Icons.menu_book_outlined),
                        _StatusCard(title: 'Sécurité & Audit', subtitle: 'RBAC/permissions, audit hashé, verrouillage/PIN, inactivité, sauvegarde/corbeille.', icon: Icons.policy_outlined),
                      ]),
                    ],
                  ),
                ),
              ),
            ]),
          ),
          // Status bar
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: isDark ? const Color(0xFF0F172A) : Colors.white, border: Border(top: BorderSide(color: border))),
            child: Row(children: const [
              Icon(Icons.circle, size: 8, color: Color(0xFF2563EB)),
              SizedBox(width: 6),
              Text('SQLite 3 (Drift) — Clés primaires UUID v4 — Base locale', style: TextStyle(fontSize: 11)),
              SizedBox(width: 16),
              Text('Ctrl+F recherche • Ctrl+L verrouiller • Ctrl+W fermer', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              Spacer(),
              Text('Prêt', style: TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _sideLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
    child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Color(0xFF94A3B8))),
  );

  Widget _navItem(BuildContext context, {required IconData icon, required String label, String? badge, bool selected = false, required VoidCallback onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selBg = isDark ? const Color(0xFF172554).withOpacity(0.7) : const Color(0xFFEFF6FF);
    final selFg = isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8);
    final fg = selected ? selFg : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569));
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(color: selected ? selBg : Colors.transparent, borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            Icon(icon, size: 17, color: fg),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: fg))),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(999)),
                child: Text(badge, style: TextStyle(fontSize: 10, color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569))),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _kpi(BuildContext context, String label, String value, IconData icon, Color color, String hint) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(width: 230, child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
      ),
      child: Row(children: [
        Container(width: 38, height: 38, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF0F172A))),
          Text(hint, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
        ])),
      ]),
    ));
  }
}

class _StatusCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  const _StatusCard({required this.title, required this.subtitle, required this.icon});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 320,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: const Color(0xFF2563EB).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: const Color(0xFF2563EB), size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF0F172A))),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          ])),
        ]),
      ),
    );
  }
}
