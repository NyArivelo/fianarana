import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:fianarana/core/utils/xlsx_export.dart';
import 'package:fianarana/features/attendance/services/attendance_import_service.dart';

import 'package:fianarana/core/utils/csv_export.dart';
import 'package:fianarana/core/widgets/app_ui.dart';
import 'package:fianarana/features/attendance/application/attendance_providers.dart';
import 'package:fianarana/features/attendance/data/attendance_repository.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/core/security/permission_providers.dart';
import 'package:fianarana/features/students/application/students_providers.dart';

const _appelStatuses = <String>['Présent', 'Absent', 'Retard', 'Incident'];

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  String? _classId;
  DateTime? _date;
  String _statusFilter = 'Tous';
  String _categoryFilter = 'Tous';
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _invalidate() => ref.invalidate(attendanceListProvider);

  // ---------------------------------------------------------------------------
  // Appel de classe
  // ---------------------------------------------------------------------------

  Future<void> _openAppel() async {
    final classes = await ref.read(classesProvider.future);
    if (classes.isEmpty) {
      _snack('Aucune classe disponible.');
      return;
    }
    var classId = _classId ?? classes.first.id;
    var date = _date ?? DateTime.now();
    var students = await ref.read(attendanceRepositoryProvider).studentsOfClass(classId);
    if (!mounted) return;
    if (students.isEmpty) {
      _snack('Aucun élève inscrit dans cette classe.');
      return;
    }

    // Pré-remplissage depuis un appel déjà saisi pour la classe et la date.
    final existing = await ref
        .read(attendanceRepositoryProvider)
        .list(actorUserId: ref.read(authControllerProvider).userId, classId: classId, date: date);
    final statuses = <String, String>{
      for (final s in students) s.id: 'Présent',
    };
    for (final row in existing.where((r) => r.category.contains('Appel'))) {
      final match = students.where((s) => s.matricule == row.matricule);
      for (final s in match) {
        statuses[s.id] = row.status;
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> reloadForClass(String newClassId) async {
            final list =
                await ref.read(attendanceRepositoryProvider).studentsOfClass(newClassId);
            if (!ctx.mounted) return;
            setDialogState(() {
              classId = newClassId;
              students = list;
              statuses
                ..clear()
                ..addEntries(list.map((s) => MapEntry(s.id, 'Présent')));
            });
          }

          final presents = statuses.values.where((v) => v == 'Présent').length;
          final absents = statuses.values.where((v) => v == 'Absent').length;
          final retards = statuses.values.where((v) => v == 'Retard').length;
          final incidents = statuses.values.where((v) => v == 'Incident').length;

          return AlertDialog(
            title: const Text('Faire l\'appel'),
            content: SizedBox(
              width: 640,
              height: 520,
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: classId,
                      decoration: const InputDecoration(labelText: 'Classe'),
                      items: classes
                          .map((c) => DropdownMenuItem(value: c.id, child: Text(c.label)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) reloadForClass(v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) setDialogState(() => date = picked);
                    },
                    icon: const Icon(Icons.date_range, size: 16),
                    label: Text(formatDateFr(date)),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  AppBadge('$presents présent(s)', tone: AppTone.success),
                  const SizedBox(width: 6),
                  AppBadge('$absents absent(s)', tone: AppTone.danger),
                  const SizedBox(width: 6),
                  AppBadge('$retards retard(s)', tone: AppTone.warning),
                  const SizedBox(width: 6),
                  AppBadge('$incidents incident(s)', tone: AppTone.info),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => setDialogState(() {
                      for (final s in students) {
                        statuses[s.id] = 'Présent';
                      }
                    }),
                    icon: const Icon(Icons.done_all, size: 16),
                    label: const Text('Tout présent'),
                  ),
                ]),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Saisie rapide : cliquez un statut ou utilisez Tab/Entrée pour naviguer (tableur).',
                        style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  ),
                ),
                Expanded(
                  child: FocusTraversalGroup(
                    child: ListView.separated(
                      itemCount: students.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final student = students[index];
                        final current = statuses[student.id] ?? 'Présent';
                        Color cFor(String st) => switch (st) {
                              'Présent' => const Color(0xFF059669),
                              'Absent' => const Color(0xFFDC2626),
                              'Retard' => const Color(0xFFD97706),
                              _ => const Color(0xFF2563EB),
                            };
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            SizedBox(
                              width: 92,
                              child: Text(student.matricule,
                                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                            ),
                            Expanded(
                              child: Text('${student.lastName} ${student.firstName}',
                                  style: const TextStyle(fontSize: 12)),
                            ),
                            Wrap(
                              spacing: 4,
                              children: _appelStatuses.map((st) {
                                final selected = current == st;
                                final c = cFor(st);
                                return ChoiceChip(
                                  label: Text(st, style: TextStyle(fontSize: 11, color: selected ? Colors.white : c, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
                                  selected: selected,
                                  selectedColor: c,
                                  backgroundColor: c.withValues(alpha: 0.08),
                                  side: BorderSide(color: c.withValues(alpha: selected ? 0.0 : 0.35)),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  onSelected: (_) => setDialogState(() => statuses[student.id] = st),
                                );
                              }).toList(),
                            ),
                          ]),
                        );
                      },
                    ),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.save_outlined, size: 16),
                label: Text('Enregistrer l\'appel (${students.length})'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true) return;
    try {
      final count = await ref.read(attendanceRepositoryProvider).recordAppel(
            classId: classId,
            date: date,
            statusByStudent: statuses,
            actorUserId: ref.read(authControllerProvider).userId,
            actorUsername: ref.read(authControllerProvider).username,
          );
      _invalidate();
      _snack('Appel enregistré : $count élève(s) — ${formatDateFr(date)}.');
    } catch (e) {
      _snack('Erreur appel : $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Événement / discipline
  // ---------------------------------------------------------------------------

  Future<void> _openEvent() async {
    final auth = ref.read(authControllerProvider);
    final students = await ref.read(studentsRepositoryProvider).list(
          actorUserId: auth.userId,
          classId: _classId,
          limit: 500,
        );
    if (!mounted) return;
    if (students.isEmpty) {
      _snack('Sélectionnez une classe contenant des élèves.');
      return;
    }
    String? studentId = students.first.id;
    String category = 'Discipline';
    String status = 'Incident';
    final slotCtrl = TextEditingController(text: 'Journée');
    final justCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Saisir un événement'),
          content: SizedBox(
            width: 520,
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
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) => studentId = v,
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Catégorie'),
                    items: const ['Discipline', 'Appel / Présence', 'Santé', 'Autorisation']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => category = v ?? 'Discipline'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Statut'),
                    items: const [
                      'Incident',
                      'Absent',
                      'Retard',
                      'Exclusion temporaire',
                      'Justifié',
                    ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) => setDialogState(() => status = v ?? 'Incident'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: slotCtrl,
                decoration: const InputDecoration(
                    labelText: 'Créneau ou faits (ex: Cours de mathématiques)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: justCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Justification / sanction / suivi'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true || studentId == null) return;
    try {
      await ref.read(attendanceRepositoryProvider).record(
            studentId: studentId!,
            classId: _classId,
            date: _date ?? DateTime.now(),
            status: status,
            category: category,
            slotOrFacts: slotCtrl.text.trim().isEmpty ? null : slotCtrl.text.trim(),
            justification:
                justCtrl.text.trim().isEmpty ? null : justCtrl.text.trim(),
            actorUserId: auth.userId,
            actorUsername: auth.username,
          );
      _invalidate();
      _snack('Événement enregistré.');
    } catch (e) {
      _snack('Erreur événement : $e');
    }
  }


  Future<void> _editEvent(AttendanceRow row) async {
    final auth = ref.read(authControllerProvider);
    final canUpdate = (ref.read(currentPermissionsProvider).valueOrNull ?? const <String>{}).contains('attendance.update');
    if (!canUpdate) { _snack('Action non autorisée (attendance.update).'); return; }
    String status = row.status;
    final slotCtrl = TextEditingController(text: row.slot ?? '');
    final justCtrl = TextEditingController(text: row.justification ?? row.details ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: const Text('Suivi / mise à jour événement'),
        content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(contentPadding: EdgeInsets.zero, title: Text(row.studentName), subtitle: Text('${row.matricule} • ${formatDateIso(row.date)} • ${row.category}')),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(value: status, decoration: const InputDecoration(labelText: 'Statut / suite'), items: const ['Présent','Absent','Retard','Incident','Justifié','Avertissement','Exclusion','En cours','Résolu','Clôturé'].map((e)=>DropdownMenuItem(value:e, child: Text(e))).toList(), onChanged: (v)=>setD(()=>status=v??status)),
          const SizedBox(height: 8),
          TextField(controller: slotCtrl, decoration: const InputDecoration(labelText: 'Créneau / faits')),
          const SizedBox(height: 8),
          TextField(controller: justCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Justification / sanction / suivi')),
        ])),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('Annuler')),
          FilledButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('Enregistrer')),
        ],
      )),
    );
    if (ok != true) return;
    try {
      await ref.read(attendanceRepositoryProvider).updateEvent(
        id: row.id,
        status: status,
        justification: justCtrl.text.trim().isEmpty ? null : justCtrl.text.trim(),
        slotOrFacts: slotCtrl.text.trim().isEmpty ? null : slotCtrl.text.trim(),
        actorUserId: auth.userId,
        actorUsername: auth.username,
      );
      _invalidate();
      _snack('Événement mis à jour.');
    } catch (e) {
      _snack('Erreur mise à jour : $e');
    }
  }

  Future<void> _export(List<AttendanceRow> rows) async {
    final choice = await showDialog<String>(context: context, builder: (ctx)=>SimpleDialog(title: const Text('Exporter présences/discipline'), children: [
      SimpleDialogOption(onPressed: ()=>Navigator.pop(ctx,'csv'), child: const ListTile(leading: Icon(Icons.description_outlined), title: Text('Exporter en CSV'))),
      SimpleDialogOption(onPressed: ()=>Navigator.pop(ctx,'xlsx'), child: const ListTile(leading: Icon(Icons.grid_on_outlined), title: Text('Exporter en Excel (XLSX)'))),
    ]));
    if (choice == null) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final headers = const ['Date','Matricule','Eleve','Classe','Categorie','Statut','Creneau','Justification'];
    final data = rows.map((r) => <String?>[
          formatDateIso(r.date),
          r.matricule,
          r.studentName,
          r.classLabel,
          r.category,
          r.status,
          r.slot,
          r.justification ?? r.details,
        ]).toList();
    final file = choice == 'xlsx'
        ? await XlsxExport.export(filename: 'presences_$ts.xlsx', sheetName: 'Presences', headers: headers, rows: data)
        : await CsvExport.export(filename: 'presences_$ts.csv', headers: headers, rows: data);
    _snack('Export ${choice.toUpperCase()} : ${file.path}');
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final classesAsync = ref.watch(classesProvider);
    final listAsync = ref.watch(attendanceListProvider((classId: _classId, date: _date)));
    final perms = ref.watch(currentPermissionsProvider).valueOrNull ?? const <String>{};
    final canCreate = perms.contains('attendance.create');
    final canUpdate = perms.contains('attendance.update');
    final canExport = perms.contains('attendance.export');

    return Scaffold(
      backgroundColor:
          theme.brightness == Brightness.dark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Présences & Discipline'),
        actions: [
          OutlinedButton.icon(
            onPressed: _downloadAttendanceTemplate,
            icon: const Icon(Icons.description_outlined, size: 16),
            label: const Text('Modèle import'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: canCreate ? _importAttendance : null,
            icon: const Icon(Icons.upload_file_outlined, size: 16),
            label: const Text('Importer'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: canCreate ? _openEvent : null,
            icon: const Icon(Icons.edit_note_outlined, size: 16),
            label: const Text('Événement'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: canCreate ? _openAppel : null,
            icon: const Icon(Icons.playlist_add_check, size: 16),
            label: const Text("Faire l'appel"),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          listAsync.maybeWhen(
            data: (rows) {
              final scoped = rows;
              final presents =
                  scoped.where((r) => r.status == 'Présent').length;
              final absents = scoped.where((r) => r.status == 'Absent').length;
              final retards = scoped.where((r) => r.status == 'Retard').length;
              final incidents = scoped.where((r) => r.status == 'Incident').length;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                AppStatCard(
                  icon: Icons.fact_check_outlined,
                  label: 'Événements',
                  value: '${scoped.length}',
                  hint: 'Période filtrée',
                  tone: AppTone.info,
                ),
                AppStatCard(
                  icon: Icons.check_circle_outline,
                  label: 'Présents',
                  value: '$presents',
                  tone: AppTone.success,
                ),
                AppStatCard(
                  icon: Icons.cancel_outlined,
                  label: 'Absents',
                  value: '$absents',
                  tone: absents > 0 ? AppTone.danger : AppTone.neutral,
                ),
                AppStatCard(
                  icon: Icons.schedule_outlined,
                  label: 'Retards',
                  value: '$retards',
                  tone: retards > 0 ? AppTone.warning : AppTone.neutral,
                ),
                AppStatCard(
                  icon: Icons.report_outlined,
                  label: 'Incidents',
                  value: '$incidents',
                  tone: incidents > 0 ? AppTone.warning : AppTone.neutral,
                ),
              ]);
            },
            orElse: () => const SizedBox(height: 64),
          ),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(
              width: 230,
              child: classesAsync.when(
                data: (classes) {
                  final list = classes;
                  return DropdownButtonFormField<String?>(
                    initialValue: _classId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Classe'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Toutes')),
                      ...list.map((c) => DropdownMenuItem(value: c.id, child: Text(c.label))),
                    ],
                    onChanged: (v) => setState(() => _classId = v),
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Erreur : $e'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                );
                if (picked != null) setState(() => _date = picked);
              },
              icon: const Icon(Icons.date_range, size: 16),
              label: Text(_date == null ? 'Toutes les dates' : formatDateFr(_date)),
            ),
            if (_date != null)
              IconButton(
                tooltip: 'Retirer le filtre date',
                onPressed: () => setState(() => _date = null),
                icon: const Icon(Icons.clear, size: 18),
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
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: canExport
                  ? listAsync.maybeWhen(
                      data: (rows) => rows.isEmpty ? null : () => _export(rows),
                      orElse: () => null,
                    )
                  : null,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Exporter'),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final status in const ['Tous', 'Présent', 'Absent', 'Retard', 'Incident'])
              ChoiceChip(
                label: Text(status),
                selected: _statusFilter == status,
                onSelected: (_) => setState(() => _statusFilter = status),
              ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: listAsync.when(
              data: (rows) {
                final filtered = rows.where((r) {
                  final okStatus = _statusFilter == 'Tous' || r.status == _statusFilter;
                  if (!okStatus) return false;
                  if (_query.isEmpty) return true;
                  return r.studentName.toLowerCase().contains(_query) ||
                      r.matricule.toLowerCase().contains(_query);
                }).toList();
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: filtered.isEmpty
                      ? AppEmptyState(
                          icon: Icons.fact_check_outlined,
                          title: rows.isEmpty
                              ? 'Aucun événement de présence'
                              : 'Aucun événement dans ce filtre',
                          message: rows.isEmpty
                              ? 'Lancez « Faire l\'appel » pour une classe, ou importez les données de test.'
                              : null,
                          action: rows.isEmpty
                              ? FilledButton(
                                  onPressed: _openAppel,
                                  child: const Text('Faire l\'appel'),
                                )
                              : null,
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Date')),
                                DataColumn(label: Text('Matricule')),
                                DataColumn(label: Text('Élève')),
                                DataColumn(label: Text('Classe')),
                                DataColumn(label: Text('Catégorie')),
                                DataColumn(label: Text('Statut')),
                                DataColumn(label: Text('Créneau / faits')),
                                DataColumn(label: Text('Justification')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: filtered.map((r) {
                                final tone = switch (r.status) {
                                  'Présent' || 'Justifié' => AppTone.success,
                                  'Absent' => AppTone.danger,
                                  'Retard' => AppTone.warning,
                                  'Incident' => AppTone.info,
                                  _ => AppTone.neutral,
                                };
                                return DataRow(cells: [
                                  DataCell(Text(formatDateIso(r.date))),
                                  DataCell(Text(r.matricule,
                                      style: const TextStyle(
                                          fontSize: 10, fontFamily: 'monospace'))),
                                  DataCell(Text(r.studentName,
                                      style: const TextStyle(fontWeight: FontWeight.w600))),
                                  DataCell(Text(r.classLabel ?? '-')),
                                  DataCell(Text(r.category)),
                                  DataCell(AppBadge(r.status, tone: tone)),
                                  DataCell(Text(r.slot ?? '-')),
                                  DataCell(Text(r.justification ?? r.details ?? '-')),
                                  DataCell(IconButton(icon: const Icon(Icons.edit_note_outlined, size: 18), tooltip: 'Suivi / modifier', onPressed: canUpdate ? () => _editEvent(r) : null)),
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
                      'Erreur chargement présences : $e\n(Vérifiez la permission attendance.read)')),
            ),
          ),
        ]),
      ),
    );
  }
}
