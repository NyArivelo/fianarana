import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/grades/application/grades_providers.dart';
import 'package:fianarana/features/grades/data/grades_repository.dart';
import 'package:fianarana/features/grades/services/bulletin_service.dart';
import 'package:fianarana/features/students/application/students_providers.dart';

class GradesScreen extends ConsumerStatefulWidget {
  const GradesScreen({super.key});

  @override
  ConsumerState<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends ConsumerState<GradesScreen> {
  String? _classId;
  String? _subjectId;

  Future<void> _generateBulletin(GradeRow row) async {
    final all = await ref.read(gradesListProvider((classId: _classId, subjectId: _subjectId)).future);
    final studentRows = all.where((g) => g.studentId == row.studentId).toList();
    final avg = GradesRepository.weightedAverage(studentRows);
    final data = BulletinStudentData(
      fullName: row.studentName,
      matricule: row.matricule,
      classLabel: row.classLabel,
      periodLabel: 'Période sélectionnée',
      subjects: studentRows.map((g) => BulletinSubjectLine(
        subject: g.subjectName ?? g.label,
        score: g.score,
        maxScore: g.maxScore,
        coefficient: g.coefficient,
        isExempt: g.isExempt,
        observation: g.observation,
      )).toList(),
      average: avg,
    );
    final bytes = await BulletinService().generateStudentBulletin(data, establishmentName: 'Établissement (paramètres à lier)');
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'bulletin_${row.matricule}.pdf');
  }

  Future<void> _quickEdit(GradeRow row) async {
    final auth = ref.read(authControllerProvider);
    final scoreCtrl = TextEditingController(text: row.score?.toString() ?? '');
    final obsCtrl = TextEditingController(text: row.observation ?? '');
    final status = ValueNotifier<String>(row.validationStatus);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Saisie/édition note - ${row.studentName}'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${row.subjectName ?? row.label} • ${row.label}'),
          const SizedBox(height: 8),
          TextField(controller: scoreCtrl, decoration: InputDecoration(labelText: 'Note / ${row.maxScore.toStringAsFixed(0)}'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
          TextField(controller: obsCtrl, decoration: const InputDecoration(labelText: 'Observation')),
          const SizedBox(height: 8),
          ValueListenableBuilder<String>(valueListenable: status, builder: (c, v, _) => DropdownButtonFormField<String>(
            value: v,
            decoration: const InputDecoration(labelText: 'Statut'),
            items: const [DropdownMenuItem(value: 'Brouillon', child: Text('Brouillon')), DropdownMenuItem(value: 'Validée', child: Text('Validée'))],
            onChanged: (nv) => status.value = nv ?? v,
          )),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(gradesRepositoryProvider).upsertGrade(
          id: row.id,
          studentId: row.studentId,
          classId: null,
          subjectId: row.subjectId,
          label: row.label,
          score: double.tryParse(scoreCtrl.text.replaceAll(',', '.')),
          maxScore: row.maxScore,
          coefficient: row.coefficient,
          isExempt: row.isExempt,
          observation: obsCtrl.text.trim().isEmpty ? null : obsCtrl.text.trim(),
          validationStatus: status.value,
          actorUserId: auth.userId,
          actorUsername: auth.username,
        );
        ref.invalidate(gradesListProvider);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note mise à jour')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classesProvider);
    final gradesAsync = ref.watch(gradesListProvider((classId: _classId, subjectId: _subjectId)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Évaluations & Notes'),
        actions: [
          OutlinedButton.icon(onPressed: () => context.go('/grades/councils'), icon: const Icon(Icons.groups_outlined), label: const Text('Conseils & périodes')),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              SizedBox(
                width: 260,
                child: classesAsync.when(
                  data: (classes) {
                    final list = classes ?? const [];
                    return DropdownButtonFormField<String?>(
                      initialValue: _classId,
                      decoration: const InputDecoration(labelText: 'Classe'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Toutes')),
                        ...list.map((c) => DropdownMenuItem(value: c.id, child: Text(c.label))),
                      ],
                      onChanged: (v) => setState(() => _classId = v),
                    );
                  },
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
                                DataColumn(label: Text('Actions')),
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
                                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _quickEdit(r)),
                                  IconButton(icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: () => _generateBulletin(r)),
                                ])),
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
              child: Text('Fonctions: édition rapide de note, génération bulletin PDF (aperçu/impression). Conseils de classe, verrouillage de période et grille tableur avancée: fondations services ajoutées, UI dédiée à compléter.'),
            ),
          ],
        ),
      ),
    );
  }
}
