import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/features/timetable/application/timetable_providers.dart';

class TimetableScreen extends ConsumerWidget {
  const TimetableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(timetableSessionsProvider);
    final repo = ref.watch(timetableRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Emplois du temps & conflits')),
      body: sessionsAsync.when(
        data: (sessions) {
          final conflicts = repo.detectConflicts(sessions);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (conflicts.isNotEmpty)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Conflits détectés: ${conflicts.length}', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        ...conflicts.take(10).map((c) => Text('• [${c.type}] ${c.message}')),
                        if (conflicts.length > 10) Text('...'),
                      ]),
                    ),
                  ),
                if (conflicts.isEmpty)
                  const Card(child: ListTile(leading: Icon(Icons.check_circle_outline), title: Text('Aucun conflit détecté sur les séances chargées'))),
                const SizedBox(height: 12),
                Expanded(
                  child: Card(
                    child: sessions.isEmpty
                        ? const Center(child: Text('Aucune séance (données de test disponibles: emploi_du_temps).'))
                        : SingleChildScrollView(
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Jour')),
                                DataColumn(label: Text('Début')),
                                DataColumn(label: Text('Fin')),
                                DataColumn(label: Text('Classe')),
                                DataColumn(label: Text('Matière')),
                                DataColumn(label: Text('Enseignant')),
                                DataColumn(label: Text('Récurrence')),
                                DataColumn(label: Text('Remplacement')),
                                DataColumn(label: Text('Notes')),
                              ],
                              rows: sessions.map((s) => DataRow(cells: [
                                DataCell(Text(s.dayOfWeek)),
                                DataCell(Text(s.startTime)),
                                DataCell(Text(s.endTime)),
                                DataCell(Text(s.classId ?? '-')),
                                DataCell(Text(s.subjectId ?? '-')),
                                DataCell(Text(s.teacherId ?? '-')),
                                DataCell(Text(s.recurrence)),
                                DataCell(Icon(s.isSubstitution ? Icons.swap_horiz : Icons.remove, size: 18)),
                                DataCell(Text(s.notes ?? '-')),
                              ])).toList(),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
      ),
    );
  }
}
