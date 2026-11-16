import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/features/grades/application/grades_providers.dart';
import 'package:fianarana/features/grades/data/grades_repository.dart';
import 'package:fianarana/features/students/application/students_providers.dart';

class GradesScreen extends ConsumerStatefulWidget {
  const GradesScreen({super.key});

  @override
  ConsumerState<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends ConsumerState<GradesScreen> {
  String? _classId;
  String? _subjectId;

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classesProvider);
    final gradesAsync = ref.watch(gradesListProvider((classId: _classId, subjectId: _subjectId)));

    return Scaffold(
      appBar: AppBar(title: const Text('Évaluations & Notes')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              SizedBox(
                width: 260,
                child: classesAsync.when(
                  data: (classes) => DropdownButtonFormField<String?>(
                    value: _classId,
                    decoration: const InputDecoration(labelText: 'Classe'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Toutes')),
                      ...classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.label))),
                    ],
                    onChanged: (v) => setState(() => _classId = v),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Erreur: $e'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: gradesAsync.when(
                  data: (rows) {
                    final avg = GradesRepository.weightedAverage(rows);
                    return Wrap(spacing: 16, children: [
                      Chip(label: Text('Notes: ${rows.length}')),
                      Chip(label: Text('Moyenne pondérée (aperçu): ${avg == null ? '-' : avg.toStringAsFixed(2)} / 20')),
                    ]);
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: gradesAsync.when(
                data: (rows) => Card(
                  child: rows.isEmpty
                      ? const Center(child: Text('Aucune note (importez les données de test: 940 évaluations disponibles).'))
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Élève')),
                                DataColumn(label: Text('Matricule')),
                                DataColumn(label: Text('Classe')),
                                DataColumn(label: Text('Matière')),
                                DataColumn(label: Text('Évaluation')),
                                DataColumn(label: Text('Note')),
                                DataColumn(label: Text('Barème')),
                                DataColumn(label: Text('Coef')),
                                DataColumn(label: Text('Dispensé')),
                                DataColumn(label: Text('Statut')),
                              ],
                              rows: rows.take(300).map((r) => DataRow(cells: [
                                DataCell(Text(r.studentName)),
                                DataCell(Text(r.matricule)),
                                DataCell(Text(r.classLabel ?? '-')),
                                DataCell(Text(r.subjectName ?? r.subjectId ?? '-')),
                                DataCell(Text(r.label)),
                                DataCell(Text(r.isExempt ? 'Disp.' : (r.score?.toStringAsFixed(2) ?? '-'))),
                                DataCell(Text(r.maxScore.toStringAsFixed(0))),
                                DataCell(Text(r.coefficient.toStringAsFixed(2))),
                                DataCell(Icon(r.isExempt ? Icons.check_circle : Icons.remove_circle_outline, size: 18)),
                                DataCell(Text(r.validationStatus)),
                              ])).toList(),
                            ),
                          ),
                        ),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Erreur: $e\n(Vérifiez permission grades.read)')),
              ),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Saisie/édition en grille, conseils de classe et génération de bulletins PDF à compléter (services de calcul testés).'),
            ),
          ],
        ),
      ),
    );
  }
}
