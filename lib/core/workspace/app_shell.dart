import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/search/presentation/global_search_dialog.dart';

/// Coquille commune à tous les modules authentifiés : en-tête, navigation
/// latérale, zone de contenu et barre d'état. Conforme à la maquette
/// `design.html` (header global + sidebar + statut).
class AppShell extends ConsumerWidget {
  final Widget child;
  final String location;
  const AppShell({super.key, required this.child, required this.location});

  static const _brand = Color(0xFF2563EB);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      body: Column(children: [
        _header(context, ref, auth, isDark, border),
        Expanded(
          child: Row(children: [
            _sidebar(context, isDark, border),
            Expanded(
              child: Container(
                color: isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
                child: child,
              ),
            ),
          ]),
        ),
        _statusBar(isDark, border),
      ]),
    );
  }

  Widget _header(BuildContext context, WidgetRef ref, AuthState auth, bool isDark, Color border) {
    return Container(
      height: 49,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF1E40AF)]),
          ),
          child: const Icon(Icons.school, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            Text('Fianarana — Gestion scolaire',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF0F172A))),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF172554) : const Color(0xFFDBEAFE),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFBFDBFE)),
              ),
              child: Text('2026-2027',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8))),
            ),
          ]),
          Text('Installation locale • SQLite Drift (UUID)',
              style: TextStyle(fontSize: 10, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
        ]),
        const Spacer(),
        SizedBox(
          width: 340,
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
                const Icon(Icons.search, size: 15, color: _brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Rechercher un élève, matricule, classe... (Ctrl+F)',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
                ),
              ]),
            ),
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF052E2B) : const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isDark ? const Color(0xFF065F46) : const Color(0xFFA7F3D0)),
          ),
          child: Row(children: [
            Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('Base locale',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857))),
          ]),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Verrouiller (Ctrl+L)',
          onPressed: () => ref.read(authControllerProvider.notifier).lock(),
          icon: const Icon(Icons.lock_outline, size: 18),
        ),
        Container(width: 1, height: 24, color: border, margin: const EdgeInsets.symmetric(horizontal: 4)),
        CircleAvatar(
          radius: 13,
          backgroundColor: _brand,
          child: Text(
            (auth.fullName ?? auth.username ?? 'U').characters.first.toUpperCase(),
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(auth.fullName ?? auth.username ?? 'Utilisateur',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF0F172A))),
          Text(auth.scopeType ?? 'Session', style: const TextStyle(fontSize: 10, color: _brand)),
        ]),
        IconButton(
          tooltip: 'Déconnexion',
          onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          icon: const Icon(Icons.logout, size: 18),
        ),
      ]),
    );
  }

  Widget _sidebar(BuildContext context, bool isDark, Color border) {
    return Container(
      width: 228,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(right: BorderSide(color: border)),
      ),
      child: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(8), children: [
            _sideLabel('Pilotage & Scolarité'),
            _navItem(context, icon: Icons.dashboard_rounded, label: 'Tableau de bord', route: '/'),
            _navItem(context, icon: Icons.people_outline, label: 'Élèves & Inscriptions', route: '/students'),
            _navItem(context, icon: Icons.fact_check_outlined, label: 'Présences & Discipline', route: '/attendance'),
            _navItem(context, icon: Icons.grading_outlined, label: 'Évaluations & Notes', route: '/grades'),
            _navItem(context, icon: Icons.calendar_month_outlined, label: 'Emplois du temps', route: '/timetable'),
            _navItem(context, icon: Icons.event_note_outlined, label: 'Calendrier & éphéméride', route: '/calendar'),
            const SizedBox(height: 6),
            _sideLabel('Administration & Ressources'),
            _navItem(context, icon: Icons.payments_outlined, label: 'Finances & Caisse', route: '/finance'),
            _navItem(context, icon: Icons.badge_outlined, label: 'Personnel & RH', route: '/staff'),
            _navItem(context, icon: Icons.menu_book_outlined, label: 'Bibliothèque & Quitus', route: '/library'),
            _navItem(context, icon: Icons.meeting_room_outlined, label: 'Locaux & équipements', route: '/facilities'),
            _navItem(context, icon: Icons.settings_outlined, label: 'Paramètres', route: '/settings'),
          ]),
        ),
        Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF172554).withValues(alpha: 0.4) : const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFBFDBFE)),
          ),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.storage, size: 14, color: Color(0xFF2563EB)),
              SizedBox(width: 6),
              Text('Sauvegarde & base', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
            SizedBox(height: 4),
            Text('SQLite Drift locale • Sauvegarde .zip', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Ctrl+W fermer', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
            Text('v1.1', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
          ]),
        ),
      ]),
    );
  }

  Widget _statusBar(bool isDark, Color border) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(top: BorderSide(color: border)),
      ),
      child: Row(children: const [
        Icon(Icons.circle, size: 8, color: Color(0xFF2563EB)),
        SizedBox(width: 6),
        Text('SQLite 3 (Drift) — Clés primaires UUID v4 — Base locale', style: TextStyle(fontSize: 11)),
        SizedBox(width: 16),
        Text('Ctrl+F recherche • Ctrl+L verrouiller • Ctrl+W fermer', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        Spacer(),
        Text('Prêt', style: TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _sideLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Color(0xFF94A3B8))),
      );

  bool _isSelected(String route) {
    if (route == '/') return location == '/';
    return location == route || location.startsWith('$route/');
  }

  Widget _navItem(BuildContext context, {required IconData icon, required String label, required String route}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = _isSelected(route);
    final selBg = isDark ? const Color(0xFF172554).withValues(alpha: 0.7) : const Color(0xFFEFF6FF);
    final selFg = isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8);
    final fg = selected ? selFg : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569));
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(color: selected ? selBg : Colors.transparent, borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.go(route),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            Icon(icon, size: 17, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: fg)),
            ),
          ]),
        ),
      ),
    );
  }
}
