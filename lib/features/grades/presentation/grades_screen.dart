import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import 'package:fianarana/core/widgets/app_ui.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/grades/application/council_providers.dart';
import 'package:fianarana/features/grades/application/grades_providers.dart';
import 'package:fianarana/features/grades/data/grades_repository.dart';
import 'package:fianarana/features/grades/services/bulletin_service.dart';
import 'package:fianarana/features/students/application/students_providers.dart';
import 'package:fianarana/features/timetable/application/timetable_providers.dart';

class GradesScreen extends ConsumerStatefulWidget {
  const GradesScreen({super.key});

  @override
  ConsumerState<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends ConsumerState<GradesScreen> {
  String? _classId;
  String? _subjectId;
  String _statusFilter = 'Tous';
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _generateBulletin(GradeRow row) async {
    final all = await ref.read(
        gradesListProvider((classId: _classId, subjectId: _subjectId)).future);
    final studentRows = all.where((g) => g.studentId == row.studentId).toList();
    final avg = GradesRepository.weightedAverage(studentRows);
    final data = BulletinStudentData(
      fullName: row.studentName,
      matricule: row.matricule,
      classLabel: row.classLabel,
      periodLabel: 'Période sélectionnée',
      subjects: studentRows
          .map((g) => BulletinSubjectLine(
                subject: g.subjectName ?? g.label,
                score: g.score,
                maxScore: g.maxScore,
                coefficient: g.coefficient,
                isExempt: g.isExempt,
                observation: g.observation,
              ))
          .toList(),
      average: avg,
    );
    final bytes = await BulletinService().generateStudentBulletin(data,
        establishmentName: 'Établissement (paramètres à lier)');
    await Printing.layoutPdf(
        onLayout: (_) async => bytes, name: 'bulletin_${row.matricule}.pdf');
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
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${row.subjectName ?? row.label} • ${row.label}'),
            const SizedBox(height: 8),
            TextField(
                controller: scoreCtrl,
                decoration: InputDecoration(
                    labelText: 'Note / ${row.maxScore.toStringAsFixed(0)}'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true)),
            TextField(
                controller: obsCtrl,
                decoration: const InputDecoration(labelText: 'Observation')),
            const SizedBox(height: 8),
            ValueListenableBuilder<String>(
                valueListenable: status,
                builder: (c, v, _) => DropdownButtonFormField<String>(
                      initialValue: v,
                      decoration: const InputDecoration(labelText: 'Statut'),
                      items: const [
                        DropdownMenuItem(
                            value: 'Brouillon', child: Text('Brouillon')),
                        DropdownMenuItem(
                            value: 'Validée', child: Text('Validée')),
                      ],
                      onChanged: (nv) => status.value = nv ?? v,
                    )),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer')),
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
              observation:
                  obsCtrl.text.trim().isEmpty ? null : obsCtrl.text.trim(),
              validationStatus: status.value,
              actorUserId: auth.userId,
              actorUsername: auth.username,
            );
        ref.invalidate(gradesListProvider);
        _snack('Note mise à jour.');
      } catch (e) {
        _snack('Erreur : $e');
      }
    }
  }

  Future<void> _newGrade() async {
    final auth = ref.read(authControllerProvider);
    final students = await ref.read(studentsRepositoryProvider).list(
          actorUserId: auth.userId,
          classId: _classId,
          limit: 500,
        );
    final subjects = await ref.read(timetableSubjectsProvider.future);
    final periods = await ref.read(periodsProvider.future);
    if (!mounted) return;
    if (students.isEmpty) {
      _snack('Aucun élève pour cette sélection.');
      return;
    }

    String? studentId = students.first.id;
    String? classId = _classId ?? students.first.classId;
    String? subjectId = subjects.isNotEmpty ? subjects.first.id : null;
    String? periodId = periods.isNotEmpty ? periods.first.id : null;
    final labelCtrl = TextEditingController(text: 'Devoir');
    final scoreCtrl = TextEditingController();
    final maxCtrl = TextEditingController(text: '20');
    final coefCtrl = TextEditingController(text: '1');
    var status = 'Brouillon';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nouvelle évaluation'),
          content: SizedBox(
            width: 540,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: studentId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Élève'),
                items: students
                    .map((s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(
                              '${s.matricule} — ${s.fullName}${s.classLabel == null ? '' : ' (${s.classLabel})'}',
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setDialogState(() {
                    studentId = v;
                    classId = students.firstWhere((s) => s.id == v).classId;
                  });
                },
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: subjectId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Matière'),
                    items: subjects
                        .map((s) => DropdownMenuItem<String?>(
                            value: s.id, child: Text(s.name)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => subjectId = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: periodId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Période'),
                    items: periods
                        .map((p) => DropdownMenuItem<String?>(
                            value: p.id, child: Text(p.name)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => periodId = v),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Libellé (ex: Devoir surveillé n°1)')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                      controller: scoreCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Note')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                      controller: maxCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Barème')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                      controller: coefCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Coefficient')),
                ),
              ]),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Statut'),
                items: const [
                  DropdownMenuItem(
                      value: 'Brouillon', child: Text('Brouillon')),
                  DropdownMenuItem(value: 'Validée', child: Text('Validée')),
                ],
                onChanged: (v) =>
                    setDialogState(() => status = v ?? 'Brouillon'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true || studentId == null) return;
    final label = labelCtrl.text.trim();
    if (label.isEmpty) {
      _snack('Le libellé est obligatoire.');
      return;
    }
    try {
      await ref.read(gradesRepositoryProvider).upsertGrade(
            studentId: studentId!,
            classId: classId,
            subjectId: subjectId,
            periodId: periodId,
            label: label,
            score: double.tryParse(scoreCtrl.text.replaceAll(',', '.')),
            maxScore: double.tryParse(maxCtrl.text.replaceAll(',', '.')) ?? 20,
            coefficient:
                double.tryParse(coefCtrl.text.replaceAll(',', '.')) ?? 1,
            validationStatus: status,
            actorUserId: auth.userId,
            actorUsername: auth.username,
          );
      ref.invalidate(gradesListProvider);
      _snack('Évaluation enregistrée.');
    } catch (e) {
      _snack('Erreur : $e');
    }
  }

  Future<void> _validate(GradeRow row) async {
    final auth = ref.read(authControllerProvider);
    try {
      await ref.read(gradesRepositoryProvider).setValidation(
            gradeId: row.id,
            status: row.validationStatus == 'Validée' ? 'Brouillon' : 'Validée',
            actorUserId: auth.userId,
            actorUsername: auth.username,
          );
      ref.invalidate(gradesListProvider);
      _snack(row.validationStatus == 'Validée'
          ? 'Note repassée en brouillon.'
          : 'Note validée.');
    } catch (e) {
      _snack('Erreur validation : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final classesAsync = ref.watch(classesProvider);
    final gradesAsync =
        ref.watch(gradesListProvider((classId: _classId, subjectId: null)));

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF020617)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Évaluations & Notes'),
        actions: [
          OutlinedButton.icon(
            onPressed: () => context.go('/grades/councils'),
            icon: const Icon(Icons.groups_outlined, size: 16),
            label: const Text('Conseils & périodes'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _newGrade,
            icon: const Icon(Icons.add_chart_outlined, size: 16),
            label: const Text('Nouvelle note'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          gradesAsync.maybeWhen(
            data: (rows) {
              final avg = GradesRepository.weightedAverage(rows);
              final validated =
                  rows.where((r) => r.validationStatus == 'Validée').length;
              final drafts =
                  rows.where((r) => r.validationStatus != 'Validée').length;
              final exempt = rows.where((r) => r.isExempt).length;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                AppStatCard(
                  icon: Icons.grading_outlined,
                  label: 'Notes',
                  value: '${rows.length}',
                  hint: _classId == null
                      ? 'Toutes les classes'
                      : 'Classe sélectionnée',
                  tone: AppTone.info,
                ),
                AppStatCard(
                  icon: Icons.percent_outlined,
                  label: 'Moyenne pondérée',
                  value: avg == null ? '—' : '${avg.toStringAsFixed(2)} / 20',
                  tone: avg != null && avg >= 10
                      ? AppTone.success
                      : AppTone.warning,
                ),
                AppStatCard(
                  icon: Icons.verified_outlined,
                  label: 'Validées',
                  value: '$validated',
                  tone: AppTone.success,
                ),
                AppStatCard(
                  icon: Icons.edit_note_outlined,
                  label: 'Brouillons',
                  value: '$drafts',
                  tone: drafts > 0 ? AppTone.warning : AppTone.neutral,
                ),
                AppStatCard(
                  icon: Icons.block_outlined,
                  label: 'Dispensés',
                  value: '$exempt',
                  tone: AppTone.neutral,
                ),
              ]);
            },
            orElse: () => const SizedBox(height: 64),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  SizedBox(
                    width: 230,
                    child: classesAsync.when(
                      data: (classes) {
                        return DropdownButtonFormField<String?>(
                          initialValue: _classId,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Classe'),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('Toutes')),
                            ...classes.map((c) => DropdownMenuItem(
                                value: c.id, child: Text(c.label))),
                          ],
                          onChanged: (v) => setState(() {
                            _classId = v;
                            _subjectId = null;
                          }),
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Erreur : $e'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 210,
                    child: gradesAsync.maybeWhen(
                      data: (rows) {
                        final subjects = <String, String>{};
                        for (final row in rows) {
                          if (row.subjectId != null &&
                              row.subjectName != null) {
                            subjects[row.subjectId!] = row.subjectName!;
                          }
                        }
                        return DropdownButtonFormField<String?>(
                          initialValue: _subjectId,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Matière'),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('Toutes')),
                            ...subjects.entries.map((e) => DropdownMenuItem(
                                value: e.key, child: Text(e.value))),
                          ],
                          onChanged: (v) => setState(() => _subjectId = v),
                        );
                      },
                      orElse: () => const LinearProgressIndicator(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 240,
                    height: 38,
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 18),
                        hintText: 'Élève ou matricule...',
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _query = '');
                                },
                              ),
                      ),
                      onChanged: (v) =>
                          setState(() => _query = v.trim().toLowerCase()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<String>(
                      initialValue: _statusFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Statut'),
                      items: const ['Tous', 'Brouillon', 'Validée']
                          .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _statusFilter = v ?? 'Tous'),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            gradesAsync.maybeWhen(
              data: (rows) =>
                  AppBadge('${rows.length} note(s)', tone: AppTone.neutral),
              orElse: () => const SizedBox.shrink(),
            ),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: gradesAsync.when(
              data: (rows) {
                final filtered = rows.where((r) {
                  if (_subjectId != null && r.subjectId != _subjectId)
                    return false;
                  if (_statusFilter != 'Tous' &&
                      r.validationStatus != _statusFilter) {
                    return false;
                  }
                  if (_query.isEmpty) return true;
                  return r.studentName.toLowerCase().contains(_query) ||
                      r.matricule.toLowerCase().contains(_query);
                }).toList();
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: filtered.isEmpty
                      ? AppEmptyState(
                          icon: Icons.grading_outlined,
                          title: rows.isEmpty
                              ? 'Aucune note'
                              : 'Aucune note dans ce filtre',
                          message: rows.isEmpty
                              ? 'Importez les données de test (940 évaluations) ou saisissez une note.'
                              : null,
                          action: rows.isEmpty
                              ? FilledButton(
                                  onPressed: _newGrade,
                                  child: const Text('Nouvelle note'))
                              : null,
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Élève')),
                                DataColumn(label: Text('Classe')),
                                DataColumn(label: Text('Matière')),
                                DataColumn(label: Text('Évaluation')),
                                DataColumn(label: Text('Note')),
                                DataColumn(label: Text('Barème')),
                                DataColumn(label: Text('Coef')),
                                DataColumn(label: Text('Statut')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: filtered.map((r) {
                                final ratio = r.maxScore == 0 || r.score == null
                                    ? null
                                    : r.score! / r.maxScore * 20;
                                return DataRow(cells: [
                                  DataCell(Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(r.studentName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      Text(r.matricule,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              fontFamily: 'monospace')),
                                    ],
                                  )),
                                  DataCell(Text(r.classLabel ?? '-')),
                                  DataCell(Text(
                                      r.subjectName ?? r.subjectId ?? '-')),
                                  DataCell(Text(r.label)),
                                  DataCell(r.isExempt
                                      ? const AppBadge('Dispensé',
                                          tone: AppTone.warning,
                                          icon: Icons.block_outlined)
                                      : AppBadge(
                                          r.score == null
                                              ? '—'
                                              : '${r.score!.toStringAsFixed(2)}/${r.maxScore.toStringAsFixed(0)}',
                                          tone: ratio == null
                                              ? AppTone.neutral
                                              : (ratio >= 10
                                                  ? AppTone.success
                                                  : AppTone.danger),
                                        )),
                                  DataCell(Text(r.maxScore.toStringAsFixed(0))),
                                  DataCell(
                                      Text(r.coefficient.toStringAsFixed(2))),
                                  DataCell(AppBadge(
                                    r.validationStatus,
                                    tone: r.validationStatus == 'Validée'
                                        ? AppTone.success
                                        : AppTone.warning,
                                    icon: r.validationStatus == 'Validée'
                                        ? Icons.verified_outlined
                                        : Icons.edit_note_outlined,
                                  )),
                                  DataCell(Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Modifier',
                                          icon: const Icon(Icons.edit_outlined,
                                              size: 18),
                                          onPressed: () => _quickEdit(r),
                                        ),
                                        IconButton(
                                          tooltip:
                                              r.validationStatus == 'Validée'
                                                  ? 'Repasser en brouillon'
                                                  : 'Valider la note',
                                          icon: Icon(
                                            r.validationStatus == 'Validée'
                                                ? Icons.undo_outlined
                                                : Icons.check_circle_outline,
                                            size: 18,
                                          ),
                                          onPressed: () => _validate(r),
                                        ),
                                        IconButton(
                                          tooltip: 'Bulletin PDF',
                                          icon: const Icon(
                                              Icons.picture_as_pdf_outlined,
                                              size: 18),
                                          onPressed: () => _generateBulletin(r),
                                        ),
                                      ])),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Text(
                      'Erreur chargement notes : $e\n(Vérifiez la permission grades.read)')),
            ),
          ),
        ]),
      ),
    );
  }
}
