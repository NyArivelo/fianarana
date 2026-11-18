import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/security/permission_providers.dart';
import 'package:fianarana/core/utils/csv_export.dart';
import 'package:fianarana/core/widgets/app_ui.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/discipline/application/discipline_providers.dart';
import 'package:fianarana/features/discipline/data/discipline_repository.dart';
import 'package:fianarana/features/students/application/students_providers.dart';

/// Module discipline : incidents, convocations, commissions, sanctions
/// et suivi d'exécution des décisions.
class DisciplineScreen extends ConsumerStatefulWidget {
  const DisciplineScreen({super.key});

  @override
  ConsumerState<DisciplineScreen> createState() => _DisciplineScreenState();
}

class _DisciplineScreenState extends ConsumerState<DisciplineScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _status = 'Tous';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  ({String? id, String? username}) get _actor {
    final auth = ref.read(authControllerProvider);
    return (id: auth.userId, username: auth.username);
  }

  bool get _canCreate =>
      (ref.watch(currentPermissionsProvider).valueOrNull ?? const <String>{}).contains('discipline.create');
  bool get _canUpdate =>
      (ref.watch(currentPermissionsProvider).valueOrNull ?? const <String>{}).contains('discipline.update');
  bool get _canClose =>
      (ref.watch(currentPermissionsProvider).valueOrNull ?? const <String>{}).contains('discipline.close');

  void _refresh() {
    ref.invalidate(disciplineCasesProvider);
    ref.invalidate(disciplineStatsProvider);
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    try {
      await action();
      _refresh();
      if (success != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cases = ref.watch(disciplineCasesProvider((status: _status, query: _query)));
    final stats = ref.watch(disciplineStatsProvider).valueOrNull ?? const <String, int>{};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discipline & suivi des sanctions'),
        actions: [
          IconButton(
            tooltip: 'Exporter CSV',
            icon: const Icon(Icons.download_outlined),
            onPressed: () {
              final rows = cases.valueOrNull ?? const <DisciplineCaseRow>[];
              CsvExport.export(
                filename: 'discipline_export.csv',
                headers: const ['Élève', 'Matricule', 'Classe', 'Date', 'Catégorie', 'Gravité', 'Statut', 'Sanction', 'Faits'],
                rows: rows.map((r) => [
                  r.studentName, r.matricule, r.classLabel ?? '',
                  '${r.disciplineCase.incidentDate.year}-${r.disciplineCase.incidentDate.month.toString().padLeft(2, '0')}-${r.disciplineCase.incidentDate.day.toString().padLeft(2, '0')}',
                  r.disciplineCase.category, r.disciplineCase.severity,
                  r.disciplineCase.status, r.disciplineCase.sanction ?? '', r.disciplineCase.facts,
                ]).toList(),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 10, runSpacing: 10, children: [
            AppStatCard(icon: Icons.folder_outlined, label: 'Dossiers', value: '${stats['total'] ?? 0}', width: 150),
            AppStatCard(icon: Icons.folder_open_outlined, label: 'Ouverts', value: '${stats['ouverts'] ?? 0}',
                tone: (stats['ouverts'] ?? 0) > 0 ? AppTone.warning : AppTone.success, width: 150),
            AppStatCard(icon: Icons.gavel_outlined, label: 'Cas graves', value: '${stats['graves'] ?? 0}',
                tone: (stats['graves'] ?? 0) > 0 ? AppTone.danger : AppTone.success, width: 150),
            AppStatCard(icon: Icons.pending_actions_outlined, label: 'Actions à faire', value: '${stats['actions_a_faire'] ?? 0}',
                tone: (stats['actions_a_faire'] ?? 0) > 0 ? AppTone.info : AppTone.success, width: 170),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  labelText: 'Rechercher (élève, matricule, faits)',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          }),
                ),
                onSubmitted: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Statut'),
                items: const ['Tous', 'Ouvert', 'En cours', 'Traité', 'Clos']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _status = v ?? 'Tous'),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _canCreate ? () => _editCase(null) : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Ouvrir un dossier'),
            ),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: cases.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erreur : $e')),
              data: (rows) => rows.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.verified_user_outlined,
                      title: 'Aucun dossier de discipline',
                      message: 'Les incidents, convocations et sanctions apparaîtront ici.',
                    )
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, i) => _caseTile(rows[i]),
                    ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _caseTile(DisciplineCaseRow row) {
    final c = row.disciplineCase;
    final tone = c.severity == 'Grave' || c.severity == 'Très grave'
        ? AppTone.danger
        : c.severity == 'Moyenne'
            ? AppTone.warning
            : AppTone.info;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          child: Text('${c.category.isEmpty ? '?' : c.category.substring(0, 1).toUpperCase()}'
              '${c.severity.isEmpty ? '?' : c.severity.substring(0, 1).toUpperCase()}'),
        ),
        title: Row(children: [
          Expanded(child: Text('${row.studentName} — ${row.matricule}',
              style: const TextStyle(fontWeight: FontWeight.w600))),
          AppBadge(c.severity, tone: tone),
          const SizedBox(width: 6),
          AppBadge(c.status,
              tone: c.status == 'Clos'
                  ? AppTone.success
                  : c.status == 'Ouvert'
                      ? AppTone.warning
                      : AppTone.info),
          if (row.pendingActions > 0) ...[
            const SizedBox(width: 6),
            AppBadge('${row.pendingActions} action(s)', tone: AppTone.danger),
          ],
        ]),
        subtitle: Text('${c.category} • ${formatDateFr(c.incidentDate)} • ${row.classLabel ?? "Classe non renseignée"}\n'
            '${c.facts}${c.sanction == null ? '' : '\nSanction : ${c.sanction}'}'),
        isThreeLine: true,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Détail / suivi',
            icon: const Icon(Icons.visibility_outlined, size: 18),
            onPressed: () => _showCase(row),
          ),
          IconButton(
            tooltip: 'Modifier',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: _canUpdate ? () => _editCase(c) : null,
          ),
          IconButton(
            tooltip: 'Archiver',
            icon: const Icon(Icons.archive_outlined, size: 18),
            onPressed: _canUpdate
                ? () => _run(
                      () => ref.read(disciplineRepositoryProvider).archiveCase(
                            id: c.id,
                            actorUserId: _actor.id,
                            actorUsername: _actor.username,
                          ),
                      success: 'Dossier archivé.',
                    )
                : null,
          ),
        ]),
        onTap: () => _showCase(row),
      ),
    );
  }

  Future<void> _showCase(DisciplineCaseRow row) async {
    final c = row.disciplineCase;
    await showDialog(
      context: context,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final actions = ref.watch(disciplineActionsProvider(c.id));
        return AlertDialog(
          title: Text('Dossier — ${row.studentName}'),
          content: SizedBox(
            width: 760,
            height: 520,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                AppBadge(c.category),
                AppBadge(c.severity, tone: c.severity == 'Grave' ? AppTone.danger : AppTone.warning),
                AppBadge(c.status, tone: c.status == 'Clos' ? AppTone.success : AppTone.info),
                AppBadge(c.sanction == null ? 'Sans sanction' : 'Sanction : ${c.sanction}',
                    tone: c.sanctionExecuted ? AppTone.success : AppTone.warning),
              ]),
              const SizedBox(height: 8),
              Text('Faits : ${c.facts}'),
              Text('Date : ${formatDateFr(c.incidentDate)} • Classe : ${row.classLabel ?? "-"}'),
              if (c.convocationDate != null) Text('Convocation : ${formatDateFr(c.convocationDate)}'),
              if (c.commissionDate != null) Text('Commission : ${formatDateFr(c.commissionDate)}'),
              if (c.decision != null) Text('Décision : ${c.decision}'),
              if (c.notes != null) Text('Notes : ${c.notes}'),
              const Divider(),
              Row(children: [
                const Text('Suivi d\'exécution', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _canUpdate ? () => _addAction(c.id, ctx) : null,
                  icon: const Icon(Icons.add_task_outlined, size: 16),
                  label: const Text('Ajouter une action'),
                ),
              ]),
              Expanded(
                child: actions.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Erreur : $e'),
                  data: (list) => list.isEmpty
                      ? const Center(child: Text('Aucune action enregistrée.'))
                      : ListView(
                          children: list.map((a) => ListTile(
                            dense: true,
                            leading: Icon(
                              a.status == 'Exécutée' ? Icons.check_circle_outline : Icons.radio_button_unchecked,
                              color: a.status == 'Exécutée' ? Colors.green : null,
                            ),
                            title: Text(a.actionType),
                            subtitle: Text([
                              if (a.description != null) a.description!,
                              if (a.dueDate != null) 'Échéance : ${formatDateFr(a.dueDate)}',
                              if (a.executedAt != null) 'Exécutée le ${formatDateFr(a.executedAt)}',
                            ].join(' • ')),
                            trailing: a.status == 'Exécutée'
                                ? null
                                : TextButton(
                                    onPressed: _canUpdate
                                        ? () async {
                                            await _run(() => ref.read(disciplineRepositoryProvider).executeAction(
                                                  actionId: a.id,
                                                  actorUserId: _actor.id,
                                                  actorUsername: _actor.username,
                                                ));
                                            ref.invalidate(disciplineActionsProvider(c.id));
                                          }
                                        : null,
                                    child: const Text('Marquer exécutée'),
                                  ),
                          )).toList(),
                        ),
                ),
              ),
            ]),
          ),
          actions: [
            if (c.sanction != null && !c.sanctionExecuted)
              TextButton.icon(
                onPressed: _canUpdate
                    ? () async {
                        await _run(() => ref.read(disciplineRepositoryProvider).markSanctionExecuted(
                              id: c.id,
                              actorUserId: _actor.id,
                              actorUsername: _actor.username,
                            ), success: 'Sanction marquée exécutée.');
                        if (ctx.mounted) Navigator.pop(ctx);
                      }
                    : null,
                icon: const Icon(Icons.verified_outlined, size: 16),
                label: const Text('Sanction exécutée'),
              ),
            if (c.status != 'Clos')
              FilledButton.icon(
                onPressed: _canClose
                    ? () async {
                        await _run(() => ref.read(disciplineRepositoryProvider).closeCase(
                              id: c.id,
                              actorUserId: _actor.id,
                              actorUsername: _actor.username,
                            ), success: 'Dossier clos.');
                        if (ctx.mounted) Navigator.pop(ctx);
                      }
                    : null,
                icon: const Icon(Icons.lock_outline, size: 16),
                label: const Text('Clore le dossier'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
          ],
        );
      }),
    );
  }

  Future<void> _addAction(String caseId, BuildContext dialogContext) async {
    final type = TextEditingController(text: 'Convocation');
    final desc = TextEditingController();
    var due = DateTime.now().add(const Duration(days: 7));
    final ok = await showDialog<bool>(
      context: dialogContext,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: const Text('Nouvelle action de suivi'),
        content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: type.text,
            decoration: const InputDecoration(labelText: 'Type d\'action'),
            items: const ['Convocation', 'Entretien', 'Commission', 'Sanction', 'Notification parents', 'Suivi']
                .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setD(() => type.text = v ?? type.text),
          ),
          const SizedBox(height: 8),
          TextField(controller: desc, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final p = await showDatePicker(context: ctx, initialDate: due, firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (p != null) setD(() => due = p);
            },
            icon: const Icon(Icons.event_outlined, size: 16),
            label: Text('Échéance : ${formatDateFr(due)}'),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ajouter')),
        ],
      )),
    );
    if (ok != true) return;
    await _run(() => ref.read(disciplineRepositoryProvider).addAction(
          caseId: caseId,
          actionType: type.text,
          description: desc.text,
          dueDate: due,
          actorUserId: _actor.id,
          actorUsername: _actor.username,
        ), success: 'Action ajoutée.');
    ref.invalidate(disciplineActionsProvider(caseId));
  }

  Future<void> _editCase(DisciplineCase? existing) async {
    final students = await ref.read(studentsListProvider((query: null, classId: null, status: 'Actif')).future);
    if (!mounted) return;
    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun élève actif : importez les données de test ou créez un élève.')));
      return;
    }
    String? studentId = existing?.studentId ?? students.first.id;
    String? classId = existing?.classId ?? students.first.classId;
    var category = existing?.category ?? 'Incident';
    var severity = existing?.severity ?? 'Moyenne';
    var status = existing?.status ?? 'Ouvert';
    var incidentDate = existing?.incidentDate ?? DateTime.now();
    var convocation = existing?.convocationDate;
    var commission = existing?.commissionDate;
    final facts = TextEditingController(text: existing?.facts ?? '');
    final decision = TextEditingController(text: existing?.decision ?? '');
    final sanction = TextEditingController(text: existing?.sanction ?? '');
    final notes = TextEditingController(text: existing?.notes ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: Text(existing == null ? 'Ouvrir un dossier de discipline' : 'Modifier le dossier'),
        content: SizedBox(
          width: 780,
          height: 560,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: studentId,
              decoration: const InputDecoration(labelText: 'Élève *'),
              isExpanded: true,
              items: students.map((s) => DropdownMenuItem(
                value: s.id,
                child: Text('${s.fullName} — ${s.matricule}${s.classLabel == null ? '' : ' (${s.classLabel})'}',
                    overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (v) => setD(() {
                studentId = v;
                classId = students.firstWhere((s) => s.id == v).classId;
              }),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Catégorie'),
                items: const ['Incident', 'Indiscipline', 'Absence répétée', 'Retard répété', 'Violence', 'Tricherie', 'Autre']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => setD(() => category = v ?? category),
              )),
              const SizedBox(width: 8),
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: severity,
                decoration: const InputDecoration(labelText: 'Gravité'),
                items: const ['Faible', 'Moyenne', 'Grave', 'Très grave']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => setD(() => severity = v ?? severity),
              )),
              const SizedBox(width: 8),
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Statut'),
                items: const ['Ouvert', 'En cours', 'Traité', 'Clos']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => setD(() => status = v ?? status),
              )),
            ]),
            const SizedBox(height: 8),
            TextField(controller: facts, maxLines: 4, decoration: const InputDecoration(labelText: 'Faits constatés *')),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final p = await showDatePicker(context: ctx, initialDate: incidentDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (p != null) setD(() => incidentDate = p);
                },
                icon: const Icon(Icons.event_outlined, size: 16),
                label: Text('Incident : ${formatDateFr(incidentDate)}'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final p = await showDatePicker(context: ctx, initialDate: convocation ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (p != null) setD(() => convocation = p);
                },
                icon: const Icon(Icons.person_outlined, size: 16),
                label: Text(convocation == null ? 'Convocation' : 'Convoqué : ${formatDateFr(convocation)}'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final p = await showDatePicker(context: ctx, initialDate: commission ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (p != null) setD(() => commission = p);
                },
                icon: const Icon(Icons.groups_outlined, size: 16),
                label: Text(commission == null ? 'Commission' : 'Commission : ${formatDateFr(commission)}'),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(controller: decision, decoration: const InputDecoration(labelText: 'Décision / avis de la commission')),
            const SizedBox(height: 8),
            TextField(controller: sanction, decoration: const InputDecoration(labelText: 'Sanction prononcée')),
            const SizedBox(height: 8),
            TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes internes')),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      )),
    );
    if (ok != true || studentId == null) return;
    if (facts.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Les faits constatés sont obligatoires.')));
      }
      return;
    }
    await _run(() => ref.read(disciplineRepositoryProvider).saveCase(
          id: existing?.id,
          studentId: studentId!,
          classId: classId,
          incidentDate: incidentDate,
          category: category,
          severity: severity,
          facts: facts.text,
          status: status,
          convocationDate: convocation,
          commissionDate: commission,
          decision: decision.text.isEmpty ? null : decision.text,
          sanction: sanction.text.isEmpty ? null : sanction.text,
          notes: notes.text.isEmpty ? null : notes.text,
          actorUserId: _actor.id,
          actorUsername: _actor.username,
        ), success: existing == null ? 'Dossier ouvert.' : 'Dossier mis à jour.');
  }
}
