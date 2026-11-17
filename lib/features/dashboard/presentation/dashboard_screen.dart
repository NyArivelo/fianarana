import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fianarana/features/calendar/application/calendar_providers.dart';
import 'package:fianarana/features/students/application/students_providers.dart';
import 'package:fianarana/features/timetable/application/timetable_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final students = ref.watch(studentsListProvider((query: null, classId: null, status: null)));
    final classes = ref.watch(classesProvider);
    final timetable = ref.watch(timetableEntriesProvider((classId: null, teacherId: null, day: null)));
    final upcoming = ref.watch(calendarEventsProvider((
      classId: null,
      includeGlobal: true,
      isEphemeris: null,
      from: now,
      to: now.add(const Duration(days: 45)),
    )));

    String count<T>(AsyncValue<List<T>> value) => value.maybeWhen(data: (v) => '${v.length}', orElse: () => '—');

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Tableau de bord de l'établissement",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF0F172A))),
              const SizedBox(height: 4),
              Text('Synthèse en temps réel — Gestion scolaire locale (modules, données et sécurité).',
                  style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
            ]),
          ),
          FilledButton.icon(
            onPressed: () => context.go('/students/new'),
            icon: const Icon(Icons.person_add_alt_1, size: 16),
            label: const Text('Nouvelle inscription'),
          ),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _kpi(context, 'Élèves inscrits', count(students), Icons.people_outline, const Color(0xFF2563EB), 'Dossiers actifs en base'),
          _kpi(context, 'Classes actives', count(classes), Icons.layers_outlined, const Color(0xFF7C3AED), '3ème à Terminale'),
          _kpi(context, 'Séances / semaine', count(timetable), Icons.calendar_month_outlined, const Color(0xFF059669), 'Emplois du temps classes'),
          _kpi(context, 'Événements à venir', count(upcoming), Icons.event_note_outlined, const Color(0xFFD97706), 'Calendrier & éphéméride'),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _quickCard(context, title: 'Élèves & Inscriptions', subtitle: 'Liste maître-détail, filtres, soldes, export CSV, dossiers complets.',
              icon: Icons.people_outline, route: '/students'),
          _quickCard(context, title: 'Emplois du temps', subtitle: 'Vues globale, par classe et par enseignante, conflits, création de séances.',
              icon: Icons.calendar_month_outlined, route: '/timetable'),
          _quickCard(context, title: 'Calendrier & éphéméride', subtitle: 'Calendrier scolaire par classe et éphéméride globale de l\'année.',
              icon: Icons.event_note_outlined, route: '/calendar'),
          _quickCard(context, title: 'Présences & Discipline', subtitle: 'Consultation, filtres et saisie rapide des appels/événements.',
              icon: Icons.fact_check_outlined, route: '/attendance'),
          _quickCard(context, title: 'Notes & Conseils', subtitle: 'Évaluations, moyennes pondérées, conseils de classe, verrouillage, bulletins PDF.',
              icon: Icons.grading_outlined, route: '/grades'),
          _quickCard(context, title: 'Finances & Caisse', subtitle: 'Encaissements, reçus PDF, clôture Z, échéanciers/relances, export CSV.',
              icon: Icons.payments_outlined, route: '/finance'),
          _quickCard(context, title: 'Personnel & RH', subtitle: 'Personnel/enseignants, affectations et accès direct au planning.',
              icon: Icons.badge_outlined, route: '/staff'),
          _quickCard(context, title: 'Bibliothèque & Locaux', subtitle: 'Catalogue, prêts/quitus, locaux et équipements.',
              icon: Icons.menu_book_outlined, route: '/library'),
        ]),
      ],
    );
  }

  Widget _kpi(BuildContext context, String label, String value, IconData icon, Color color, String hint) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 230,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF0F172A))),
              Text(hint, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _quickCard(BuildContext context, {required String title, required String subtitle, required IconData icon, required String route}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 320,
      child: InkWell(
        onTap: () => context.go(route),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: const Color(0xFF2563EB).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: const Color(0xFF2563EB), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF0F172A))),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              ]),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF94A3B8)),
          ]),
        ),
      ),
    );
  }
}
