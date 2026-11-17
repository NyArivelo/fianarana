import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/widgets/app_ui.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/core/security/permission_providers.dart';
import 'package:fianarana/features/grades/application/council_providers.dart';
import 'package:fianarana/features/grades/application/grades_providers.dart';
import 'package:fianarana/features/grades/data/grades_repository.dart';
import 'package:fianarana/features/students/application/students_providers.dart';
import 'package:fianarana/features/students/data/students_repository.dart';

class CouncilsScreen extends ConsumerStatefulWidget {
  const CouncilsScreen({super.key});

  @override
  ConsumerState<CouncilsScreen> createState() => _CouncilsScreenState();
}

class _CouncilsScreenState extends ConsumerState<CouncilsScreen> {
  String? _classId;
  String? _periodId;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createCouncil() async {
    if (_classId == null || _periodId == null) {
      _snack('Sélectionnez une classe et une période.');
      return;
    }
    final auth = ref.read(authControllerProvider);
    try {
      await ref.read(gradesRepositoryProvider).upsertCouncil(
            classId: _classId!,
            periodId: _periodId!,
            councilDate: DateTime.now(),
            status: 'Préparation',
            actorUserId: auth.userId,
            actorUsername: auth.username,
          );
      ref.invalidate(councilsProvider);
      _snack('Conseil de classe créé.');
    } catch (e) {
      _snack('Erreur : $e');
    }
  }

  Future<void> _lockPeriod() async {
    if (_periodId == null) { _snack('Sélectionnez une période.'); return; }
    final auth = ref.read(authControllerProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verrouiller la période'),
        content: const Text('Après délibération, les notes et moyennes de la période seront gelées. Continuer ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Verrouiller')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(gradesRepositoryProvider).lockPeriod(periodId: _periodId!, actorUserId: auth.userId, actorUsername: auth.username);
      ref.invalidate(periodsProvider);
      _snack('Période verrouillée.');
    } catch (e) { _snack('Erreur : $e'); }
  }

  Future<void> _unlockPeriod() async {
    if (_periodId == null) { _snack('Sélectionnez une période.'); return; }
    final auth = ref.read(authControllerProvider);
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déverrouillage exceptionnel'),
        content: TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Motif (obligatoire, audité)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Déverrouiller')),
        ],
      ),
    );
    if (ok != true || reasonCtrl.text.trim().isEmpty) return;
    try {
      await ref.read(gradesRepositoryProvider).unlockPeriod(periodId: _periodId!, reason: reasonCtrl.text.trim(), actorUserId: auth.userId, actorUsername: auth.username);
      ref.invalidate(periodsProvider);
      _snack('Période déverrouillée (action auditée).');
    } catch (e) { _snack('Erreur : $e'); }
  }

  Future<void> _manageCouncil(ClassCouncil council) async {
    final auth = ref.read(authControllerProvider);
    String status = council.status;
    final appCtrl = TextEditingController(text: council.globalAppreciation ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
            title: const Text('Workflow du conseil'),
            content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: status,
                decoration: const InputDecoration(labelText: 'Statut du conseil'),
                items: const ['Préparation', 'En délibération', 'Validé', 'Clôturé']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setD(() => status = v ?? status),
              ),
              const SizedBox(height: 8),
              TextField(controller: appCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Appréciation générale du conseil')),
              const SizedBox(height: 8),
              const Text('Conseil: enregistrez les décisions individuelles puis validez/clôturez le conseil.', style: TextStyle(fontSize: 12)),
            ])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
            ],
          )),
    );
    if (ok != true) return;
    try {
      await ref.read(gradesRepositoryProvider).upsertCouncil(
        id: council.id,
        classId: council.classId,
        periodId: council.periodId,
        councilDate: council.councilDate ?? DateTime.now(),
        status: status,
        globalAppreciation: appCtrl.text.trim().isEmpty ? null : appCtrl.text.trim(),
        actorUserId: auth.userId,
        actorUsername: auth.username,
      );
      ref.invalidate(councilsProvider);
      _snack('Conseil mis à jour.');
    } catch (e) { _snack('Erreur : $e'); }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final classesAsync = ref.watch(classesProvider);
    final periodsAsync = ref.watch(periodsProvider);
    final councilsAsync = ref.watch(councilsProvider((classId: _classId, periodId: _periodId)));
    final perms = ref.watch(currentPermissionsProvider).valueOrNull ?? const <String>{};
    final canManage = perms.contains('grades.validate') || perms.contains('grades.create') || perms.contains('grades.update') || perms.contains('grades.publish');

    final classLabels = <String, String>{for (final c in classesAsync.valueOrNull ?? const <ClassesData>[]) c.id: c.label};
    final periods = periodsAsync.valueOrNull ?? const <Period>[];
    final periodLabels = {for (final p in periods) p.id: p.name};

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Conseils de classe & périodes'),
        actions: [
          OutlinedButton.icon(onPressed: canManage ? _unlockPeriod : null, icon: const Icon(Icons.lock_open, size: 16), label: const Text('Déverrouiller')),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: canManage ? _lockPeriod : null, icon: const Icon(Icons.lock_outline, size: 16), label: const Text('Verrouiller période')),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SizedBox(width: 230, child: classesAsync.when(
              data: (classes) => DropdownButtonFormField<String?>(value: _classId, isExpanded: true, decoration: const InputDecoration(labelText: 'Classe'),
                items: [const DropdownMenuItem(value: null, child: Text('Toutes')), ...classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.label)))],
                onChanged: (v) => setState(() => _classId = v)),
              loading: () => const LinearProgressIndicator(), error: (e, _) => Text('$e'))),
            const SizedBox(width: 8),
            SizedBox(width: 260, child: periodsAsync.when(
              data: (list) => DropdownButtonFormField<String?>(value: _periodId, isExpanded: true, decoration: const InputDecoration(labelText: 'Période'),
                items: [const DropdownMenuItem(value: null, child: Text('Toutes')), ...list.map((p) => DropdownMenuItem(value: p.id, child: Text('${p.name}${p.isClosed ? " (verrouillée)" : ""}')))],
                onChanged: (v) => setState(() => _periodId = v)),
              loading: () => const LinearProgressIndicator(), error: (e, _) => Text('$e'))),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: canManage ? _createCouncil : null, icon: const Icon(Icons.add, size: 16), label: const Text('Nouveau conseil')),
            const Spacer(),
            AppBadge('${councilsAsync.valueOrNull?.length ?? 0} conseil(s)', tone: AppTone.info),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: councilsAsync.when(
              data: (list) => list.isEmpty
                  ? AppEmptyState(icon: Icons.groups_outlined, title: 'Aucun conseil de classe',
                      message: 'Importez les données de test ou créez un conseil pour la classe et la période sélectionnées.',
                      action: FilledButton(onPressed: canManage ? _createCouncil : null, child: const Text('Créer un conseil')))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final council = list[index];
                        final closed = council.status.toLowerCase().contains('clôt') || council.status.toLowerCase().contains('clot') || council.status.toLowerCase().contains('valid');
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            leading: Container(width: 34, height: 34, decoration: BoxDecoration(color: appToneColors(context, AppTone.info).background, borderRadius: BorderRadius.circular(9)),
                              child: Icon(Icons.groups_outlined, size: 18, color: appToneColors(context, AppTone.info).foreground)),
                            title: Text('Conseil — ${classLabels[council.classId] ?? council.classId}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            subtitle: Text('${periodLabels[council.periodId] ?? council.periodId}${council.councilDate == null ? '' : ' — ${formatDateFr(council.councilDate)}'}', style: const TextStyle(fontSize: 11)),
                            trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              AppBadge(council.status, tone: closed ? AppTone.success : AppTone.warning, icon: closed ? Icons.lock_outline : Icons.edit_note_outlined),
                              IconButton(tooltip: 'Gérer le conseil (statut/appréciation)', icon: const Icon(Icons.settings_outlined, size: 18), onPressed: canManage ? () => _manageCouncil(council) : null),
                            ]),
                            children: [
                              if (council.globalAppreciation != null)
                                Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: Align(alignment: Alignment.centerLeft,
                                  child: Text('Appréciation générale : ${council.globalAppreciation}', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: theme.colorScheme.onSurfaceVariant)))),
                              _DecisionsPanel(councilId: council.id, classId: council.classId, classLabel: classLabels[council.classId]),
                            ],
                          ),
                        );
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erreur : $e\n(Vérifiez la permission grades.read)')),
            ),
          ),
        ]),
      ),
    );
  }
}

class _DecisionsPanel extends ConsumerWidget {
  final String councilId;
  final String classId;
  final String? classLabel;
  const _DecisionsPanel({required this.councilId, required this.classId, this.classLabel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decisionsAsync = ref.watch(councilDecisionsProvider(councilId));
    final studentsAsync = ref.watch(studentsListProvider((query: null, classId: classId, status: null)));
    final repo = ref.watch(gradesRepositoryProvider);
    final auth = ref.watch(authControllerProvider);
    final students = studentsAsync.valueOrNull ?? const <StudentListItem>[];
    final names = {for (final s in students) s.id: s.fullName};

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          decisionsAsync.when(
            data: (d) => Text('Décisions individuelles (${d.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            loading: () => const Text('Décisions individuelles...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            error: (_, __) => const Text('Décisions individuelles', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          TextButton.icon(onPressed: () => _editDecision(context, ref, repo, auth, students, null), icon: const Icon(Icons.add, size: 16), label: const Text('Ajouter')),
        ]),
        decisionsAsync.when(
          data: (decisions) {
            if (decisions.isEmpty) {
              return Text('Aucune décision enregistrée pour ce conseil.', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant));
            }
            return Column(children: [
              for (final d in decisions)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(radius: 13, child: Text((names[d.studentId] ?? '?').characters.first.toUpperCase(), style: const TextStyle(fontSize: 11))),
                  title: Text(names[d.studentId] ?? d.studentId, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  subtitle: Text('${d.decision ?? "-"}${d.mention == null ? '' : ' • ${d.mention}'}${d.average == null ? '' : ' • moyenne ${d.average!.toStringAsFixed(2)}'}${d.rank == null ? '' : ' • rang ${d.rank}'}', style: const TextStyle(fontSize: 11)),
                  trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (d.appreciation != null) SizedBox(width: 220, child: Text(d.appreciation!, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: const TextStyle(fontSize: 10))),
                    IconButton(tooltip: 'Modifier', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _editDecision(context, ref, repo, auth, students, d)),
                  ]),
                ),
            ]);
          },
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Erreur décisions : $e'),
        ),
      ]),
    );
  }

  Future<void> _editDecision(BuildContext context, WidgetRef ref, GradesRepository repo, AuthState auth, List<StudentListItem> students, CouncilDecision? existing) async {
    if (students.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun élève inscrit dans cette classe.'))); return; }
    var studentId = existing?.studentId ?? students.first.id;
    var decision = existing?.decision ?? 'Passage';
    String? mention = existing?.mention;
    final averageCtrl = TextEditingController(text: existing?.average?.toString() ?? '');
    final rankCtrl = TextEditingController(text: existing?.rank?.toString() ?? '');
    final appreciationCtrl = TextEditingController(text: existing?.appreciation ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
            title: Text(existing == null ? 'Décision de conseil${classLabel == null ? '' : ' — $classLabel'}' : 'Modifier la décision'),
            content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(value: studentId, isExpanded: true, decoration: const InputDecoration(labelText: 'Élève'),
                items: students.map((s) => DropdownMenuItem(value: s.id, child: Text('${s.matricule} — ${s.fullName}', overflow: TextOverflow.ellipsis))).toList(),
                onChanged: existing == null ? (v) => setDialogState(() => studentId = v ?? studentId) : null),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: DropdownButtonFormField<String>(value: decision, decoration: const InputDecoration(labelText: 'Décision'),
                  items: const ['Passage','Redoublement','Félicitations','Encouragements','Tableau d\'honneur','Avertissement travail','Avertissement conduite','Blâme','Exclusion temporaire','Orientation']
                      .map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (v) => setDialogState(() => decision = v ?? decision))),
                const SizedBox(width: 8),
                Expanded(child: DropdownButtonFormField<String?>(value: mention, decoration: const InputDecoration(labelText: 'Mention'),
                  items: const [null,'Excellent','Très bien','Bien','Assez bien','Passable','Insuffisant'].map((m) => DropdownMenuItem<String?>(value: m, child: Text(m ?? '—'))).toList(),
                  onChanged: (v) => setDialogState(() => mention = v))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: averageCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Moyenne /20'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: rankCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rang'))),
              ]),
              const SizedBox(height: 8),
              TextField(controller: appreciationCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Appréciation du conseil')),
            ]))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
            ],
          )),
    );
    if (ok != true) return;
    try {
      await repo.upsertDecision(
        id: existing?.id,
        councilId: councilId,
        studentId: studentId,
        decision: decision,
        appreciation: appreciationCtrl.text.trim().isEmpty ? null : appreciationCtrl.text.trim(),
        average: double.tryParse(averageCtrl.text.replaceAll(',', '.')),
        rank: int.tryParse(rankCtrl.text.trim()),
        mention: mention,
        actorUserId: auth.userId,
        actorUsername: auth.username,
      );
      ref.invalidate(councilDecisionsProvider(councilId));
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Décision enregistrée.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }
}
