import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/core/security/permission_providers.dart';
import 'package:fianarana/features/timetable/application/timetable_providers.dart';
import 'package:fianarana/features/timetable/data/timetable_repository.dart';

enum _TimetableMode { global, emploiTempsClasse, planningEnseignantes }
enum _TeacherPlanningView { parEnseignante, parClasse }

const _days = <String>['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];

const _defaultSlots = <({String start, String end})>[
  (start: '08:00', end: '09:00'),
  (start: '09:00', end: '10:00'),
  (start: '10:15', end: '11:15'),
  (start: '11:15', end: '12:15'),
  (start: '13:30', end: '14:30'),
  (start: '14:30', end: '15:30'),
  (start: '15:45', end: '16:45'),
];

class TimetableScreen extends ConsumerStatefulWidget {
  final String? initialClassId;
  final String? initialTeacherId;
  const TimetableScreen({super.key, this.initialClassId, this.initialTeacherId});

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends ConsumerState<TimetableScreen> {
  _TimetableMode _mode = _TimetableMode.global;
  _TeacherPlanningView _teacherView = _TeacherPlanningView.parEnseignante;
  String? _classId;
  String? _teacherId;
  String _agendaDay = 'Lundi';

  @override
  void initState() {
    super.initState();
    _classId = widget.initialClassId;
    _teacherId = widget.initialTeacherId;
    if (_teacherId != null) _mode = _TimetableMode.planningEnseignantes;
    if (_classId != null && _teacherId == null) _mode = _TimetableMode.emploiTempsClasse;
  }

  ({String? classId, String? teacherId, String? day}) get _filter {
    if (_mode == _TimetableMode.emploiTempsClasse) {
      return (classId: _classId, teacherId: null, day: null);
    }
    if (_mode == _TimetableMode.planningEnseignantes) {
      if (_teacherView == _TeacherPlanningView.parEnseignante) {
        return (classId: null, teacherId: _teacherId, day: null);
      }
      return (classId: _classId, teacherId: null, day: null);
    }
    return (classId: null, teacherId: null, day: _agendaDay);
  }

  void _invalidate() => ref.invalidate(timetableEntriesProvider);

  Future<void> _openSessionDialog({TimetableEntry? entry}) async {
    final auth = ref.read(authControllerProvider);
    final classes = await ref.read(timetableClassesProvider.future);
    final teachers = await ref.read(timetableTeachersProvider.future);
    final subjects = await ref.read(timetableSubjectsProvider.future);
    if (!mounted) return;

    String? classId = entry?.classId ?? (_mode == _TimetableMode.parClasse ? _classId : null);
    String? teacherId = entry?.teacherId ?? (_mode == _TimetableMode.parEnseignante ? _teacherId : null);
    String? subjectId = entry?.subjectId;
    String day = entry?.dayOfWeek ?? 'Lundi';
    final startCtrl = TextEditingController(text: entry?.startTime ?? '08:00');
    final endCtrl = TextEditingController(text: entry?.endTime ?? '09:00');
    final notesCtrl = TextEditingController(text: entry?.notes ?? '');
    var substitution = entry?.isSubstitution ?? false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(entry == null ? 'Nouvelle séance' : 'Modifier la séance'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String?>(
                  value: classId,
                  decoration: const InputDecoration(labelText: 'Classe'),
                  items: classes.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.label))).toList(),
                  onChanged: (v) => setDialogState(() => classId = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: subjectId,
                  decoration: const InputDecoration(labelText: 'Matière'),
                  items: subjects.map((s) => DropdownMenuItem<String?>(value: s.id, child: Text(s.name))).toList(),
                  onChanged: (v) => setDialogState(() => subjectId = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: teacherId,
                  decoration: const InputDecoration(labelText: 'Enseignante'),
                  items: teachers
                      .map((t) => DropdownMenuItem<String?>(value: t.id, child: Text('${t.lastName} ${t.firstName} — ${t.departmentOrSubject ?? ''}')))
                      .toList(),
                  onChanged: (v) => setDialogState(() => teacherId = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: day,
                  decoration: const InputDecoration(labelText: 'Jour'),
                  items: _days.map((d) => DropdownMenuItem<String>(value: d, child: Text(d))).toList(),
                  onChanged: (v) => setDialogState(() => day = v ?? 'Lundi'),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: startCtrl, decoration: const InputDecoration(labelText: 'Début (HH:mm)'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: endCtrl, decoration: const InputDecoration(labelText: 'Fin (HH:mm)'))),
                ]),
                const SizedBox(height: 8),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optionnel)')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: substitution,
                  title: const Text('Séance de remplacement'),
                  onChanged: (v) => setDialogState(() => substitution = v),
                ),
              ]),
            ),
          ),
          actions: [
            if (entry != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
                onPressed: () async {
                  try {
                    await ref.read(timetableRepositoryProvider).deleteSession(
                          entry.id,
                          actorUserId: auth.userId,
                          actorUsername: auth.username,
                        );
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erreur: $e')));
                    }
                  }
                },
                child: const Text('Supprimer'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final selectedClassId = classId;
    if (selectedClassId == null || selectedClassId.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sélectionnez une classe.')));
      return;
    }
    if (!_validTime(startCtrl.text) || !_validTime(endCtrl.text)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Horaires invalides. Format attendu: HH:mm.')));
      return;
    }
    try {
      await ref.read(timetableRepositoryProvider).upsertSession(
            id: entry?.id,
            classId: selectedClassId,
            subjectId: subjectId,
            teacherId: teacherId,
            roomId: entry?.roomId,
            dayOfWeek: day,
            startTime: startCtrl.text.trim(),
            endTime: endCtrl.text.trim(),
            isSubstitution: substitution,
            notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
            actorUserId: auth.userId,
            actorUsername: auth.username,
          );
      _invalidate();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Séance enregistrée.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  bool _validTime(String v) {
    final p = v.trim().split(':');
    if (p.length != 2) return false;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    return h != null && m != null && h >= 0 && h < 24 && m >= 0 && m < 60;
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(currentPermissionsProvider).valueOrNull ?? const <String>{};
    final canEdit = perms.contains('timetable.create') || perms.contains('timetable.update');
    final f = _filter;
    final entriesAsync = ref.watch(timetableEntriesProvider((classId: f.classId, teacherId: f.teacherId, day: f.day)));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Emplois du temps & planning'),
        actions: [
          FilledButton.icon(
            onPressed: canEdit ? () => _openSessionDialog() : null,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Nouvelle séance'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                 SegmentedButton<_TimetableMode>(
                  segments: const [
                    ButtonSegment(value: _TimetableMode.global, icon: Icon(Icons.public, size: 16), label: Text('Vue globale')),
                    ButtonSegment(value: _TimetableMode.emploiTempsClasse, icon: Icon(Icons.table_chart_outlined, size: 16), label: Text('Emploi du temps (classe)')),
                    ButtonSegment(value: _TimetableMode.planningEnseignantes, icon: Icon(Icons.person_outline, size: 16), label: Text('Planning enseignantes')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                if (_mode == _TimetableMode.emploiTempsClasse)
                  SizedBox(
                    width: 260,
                    height: 38,
                    child: ref.watch(timetableClassesProvider).when(
                          data: (classes) => DropdownButtonFormField<String?>(
                            value: _classId,
                            isDense: true,
                            decoration: const InputDecoration(labelText: 'Classe'),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('Sélectionner une classe')),
                              ...classes.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.label))),
                            ],
                            onChanged: (v) => setState(() => _classId = v),
                          ),
                          loading: () => const LinearProgressIndicator(),
                          error: (e, _) => Text('Erreur: $e'),
                        ),
                  ),
                if (_mode == _TimetableMode.planningEnseignantes) ...[
                  SegmentedButton<_TeacherPlanningView>(
                    segments: const [
                      ButtonSegment(value: _TeacherPlanningView.parEnseignante, icon: Icon(Icons.person_search_outlined, size: 16), label: Text('Par enseignante')),
                      ButtonSegment(value: _TeacherPlanningView.parClasse, icon: Icon(Icons.groups_2_outlined, size: 16), label: Text('Par classe')),
                    ],
                    selected: {_teacherView},
                    onSelectionChanged: (s) => setState(() => _teacherView = s.first),
                  ),
                  if (_teacherView == _TeacherPlanningView.parEnseignante)
                    SizedBox(
                      width: 300,
                      height: 38,
                      child: ref.watch(timetableTeachersProvider).when(
                            data: (teachers) => DropdownButtonFormField<String?>(
                              value: _teacherId,
                              isDense: true,
                              decoration: const InputDecoration(labelText: 'Enseignante'),
                              items: [
                                const DropdownMenuItem<String?>(value: null, child: Text('Toutes les enseignantes')),
                                ...teachers.map((t) => DropdownMenuItem<String?>(
                                      value: t.id,
                                      child: Text('${t.lastName} ${t.firstName}', overflow: TextOverflow.ellipsis),
                                    )),
                              ],
                              onChanged: (v) => setState(() => _teacherId = v),
                            ),
                            loading: () => const LinearProgressIndicator(),
                            error: (e, _) => Text('Erreur: $e'),
                          ),
                    ),
                  if (_teacherView == _TeacherPlanningView.parClasse)
                    SizedBox(
                      width: 260,
                      height: 38,
                      child: ref.watch(timetableClassesProvider).when(
                            data: (classes) => DropdownButtonFormField<String?>(
                              value: _classId,
                              isDense: true,
                              decoration: const InputDecoration(labelText: 'Classe'),
                              items: [
                                const DropdownMenuItem<String?>(value: null, child: Text('Sélectionner une classe')),
                                ...classes.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.label))),
                              ],
                              onChanged: (v) => setState(() => _classId = v),
                            ),
                            loading: () => const LinearProgressIndicator(),
                            error: (e, _) => Text('Erreur: $e'),
                          ),
                    ),
                ],
                if (_mode == _TimetableMode.global)
                  Wrap(spacing: 6, children: _days.map((d) {
                    final selected = d == _agendaDay;
                    return ChoiceChip(
                      label: Text(d),
                      selected: selected,
                      onSelected: (_) => setState(() => _agendaDay = d),
                    );
                  }).toList()),
const SizedBox(height: 12),
          Expanded(
            child: entriesAsync.when(
              data: (entries) {
                final repo = ref.watch(timetableRepositoryProvider);
                final conflicts = repo.detectConflicts(entries);
                return Column(children: [
                  _summaryBar(context, entries, conflicts),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _mode == _TimetableMode.global
                        ? _agendaView(context, entries)
                        : (_mode == _TimetableMode.planningEnseignantes && _teacherView == _TeacherPlanningView.parClasse)
                            ? _teacherPlanningByClassView(context, entries)
                            : _weeklyGrid(context, entries),
                  ),
                ]);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erreur chargement emploi du temps: $e')),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _summaryBar(BuildContext context, List<TimetableEntry> entries, List<TimetableConflict> conflicts) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final classes = entries.map((e) => e.classId).whereType<String>().toSet().length;
    final teachers = entries.map((e) => e.teacherId).whereType<String>().toSet().length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: conflicts.isEmpty ? border : const Color(0xFFFCA5A5)),
      ),
      child: Row(children: [
        const Icon(Icons.event_note_outlined, size: 16, color: Color(0xFF2563EB)),
        const SizedBox(width: 8),
        Text('${entries.length} séances', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(width: 14),
        Text('$classes classe(s) • $teachers enseignante(s)', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        const Spacer(),
        if (conflicts.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(999)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle_outline, size: 13, color: Color(0xFF059669)),
              SizedBox(width: 4),
              Text('Aucun conflit', style: TextStyle(fontSize: 11, color: Color(0xFF047857), fontWeight: FontWeight.w600)),
            ]),
          )
        else
          Tooltip(
            message: conflicts.map((c) => '• ${c.message}').take(12).join('\n'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.warning_amber_rounded, size: 13, color: Color(0xFFDC2626)),
                const SizedBox(width: 4),
                Text('${conflicts.length} conflit(s)', style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C), fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
      ]),
    );
  }

  // --- Vue globale: agenda par jour ---
  Widget _agendaView(BuildContext context, List<TimetableEntry> entries) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final dayEntries = entries.where((e) => e.dayOfWeek == _agendaDay).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    if (dayEntries.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Center(child: Text('Aucune séance le $_agendaDay.', style: const TextStyle(color: Color(0xFF64748B)))),
      );
    }
    final grouped = <String, List<TimetableEntry>>{};
    for (final e in dayEntries) {
      grouped.putIfAbsent(e.startTime, () => []).add(e);
    }
    final starts = grouped.keys.toList()..sort();
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: starts.length,
        itemBuilder: (context, i) {
          final start = starts[i];
          final list = grouped[start]!;
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 58,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(start, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2563EB))),
                    Text(list.first.endTime, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                  ]),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(spacing: 6, runSpacing: 6, children: list.map((e) => _sessionChip(context, e, wide: true)).toList()),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _sessionChip(BuildContext context, TimetableEntry e, {bool wide = false}) {
    final color = _subjectColor(e.subjectName);
    return InkWell(
      onTap: () => _openSessionDialog(entry: e),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: wide ? 215 : double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(e.subjectName ?? 'Matière',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
                  overflow: TextOverflow.ellipsis),
            ),
            if (e.isSubstitution) const Icon(Icons.swap_horiz, size: 12, color: Color(0xFFD97706)),
          ]),
          const SizedBox(height: 1),
          Text('${e.classLabel ?? '-'} • ${e.teacherName ?? 'Enseignante ?'}',
              style: const TextStyle(fontSize: 10, color: Color(0xFF475569)), overflow: TextOverflow.ellipsis),
          if (e.roomLabel != null)
            Text(e.roomLabel!, style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8)), overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  // --- Vue hebdomadaire (classe ou enseignante) ---
  Widget _weeklyGrid(BuildContext context, List<TimetableEntry> entries) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final slots = <({String start, String end})>{..._defaultSlots};
    for (final e in entries) {
      slots.add((start: e.startTime, end: e.endTime));
    }
    final ordered = slots.toList()..sort((a, b) => a.start.compareTo(b.start));

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final totalWidth = constraints.maxWidth < 1120 ? 1120.0 : constraints.maxWidth;
        const timeCol = 66.0;
        final dayWidth = (totalWidth - timeCol) / _days.length;
        return Scrollbar(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                child: Column(children: [
                  Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0B1220) : const Color(0xFFF8FAFC),
                      border: Border(bottom: BorderSide(color: border)),
                    ),
                    child: Row(children: [
                      const SizedBox(width: timeCol, child: Center(child: Text('Heure', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))))),
                      ..._days.map((d) => SizedBox(
                            width: dayWidth,
                            child: Center(child: Text(d, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                          )),
                    ]),
                  ),
                  ...ordered.map((slot) => Container(
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border))),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                            width: timeCol,
                            height: 92,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(children: [
                                Text(slot.start, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                Text(slot.end, style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
                              ]),
                            ),
                          ),
                          ..._days.map((d) {
                            final cell = entries.where((e) => e.dayOfWeek == d && e.startTime == slot.start).toList();
                            return Container(
                              width: dayWidth,
                              height: 92,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                border: Border(left: BorderSide(color: border)),
                                color: cell.isEmpty ? null : _subjectColor(cell.first.subjectName).withValues(alpha: 0.03),
                              ),
                              child: SingleChildScrollView(
                                child: Column(children: cell.map((e) => Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: _sessionChip(context, e),
                                    )).toList()),
                              ),
                            );
                          }),
                        ]),
                      )),
                ]),
              ),
            ),
          ),
        );
      }),
    );
  }


  /// Planning des enseignantes par classe: séances groupées par enseignante.
  Widget _teacherPlanningByClassView(BuildContext context, List<TimetableEntry> entries) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    if (_classId == null) {
      return Container(
        decoration: BoxDecoration(color: isDark ? const Color(0xFF0F172A) : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
        child: const Center(child: Text('Sélectionnez une classe pour afficher le planning des enseignantes.', style: TextStyle(color: Color(0xFF64748B)))),
      );
    }
    if (entries.isEmpty) {
      return Container(
        decoration: BoxDecoration(color: isDark ? const Color(0xFF0F172A) : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
        child: const Center(child: Text('Aucune séance pour cette classe.', style: TextStyle(color: Color(0xFF64748B)))),
      );
    }
    final byTeacher = <String, List<TimetableEntry>>{};
    for (final e in entries) {
      final key = (e.teacherName == null || e.teacherName!.isEmpty) ? 'Enseignante non définie' : e.teacherName!;
      byTeacher.putIfAbsent(key, () => []).add(e);
    }
    final teachers = byTeacher.keys.toList()..sort();
    return ListView.builder(
      itemCount: teachers.length,
      itemBuilder: (context, i) {
        final name = teachers[i];
        final list = [...byTeacher[name]!]..sort((a, b) {
          final da = _days.indexOf(a.dayOfWeek), db = _days.indexOf(b.dayOfWeek);
          final c = da.compareTo(db);
          return c != 0 ? c : a.startTime.compareTo(b.startTime);
        });
        final subjects = list.map((e) => e.subjectName).whereType<String>().toSet().join(', ');
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: isDark ? const Color(0xFF0F172A) : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            leading: CircleAvatar(radius: 14, backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.12), child: const Icon(Icons.person, size: 16, color: Color(0xFF2563EB))),
            title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: Text(' séance(s) • ', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: list.map((e) {
                final color = _subjectColor(e.subjectName);
                return InkWell(
                  onTap: () => _openSessionDialog(entry: e),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 240,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: color, width: 3))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.subjectName ?? 'Matière', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
                      const SizedBox(height: 2),
                      Text(' • -', style: const TextStyle(fontSize: 10, color: Color(0xFF334155))),
                      if (e.roomLabel != null) Text(e.roomLabel!, style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
                    ]),
                  ),
                );
              }).toList()),
            ],
          ),
        );
      },
    );
  }

  Color _subjectColor(String? subject) {
    const palette = [
      Color(0xFF2563EB),
      Color(0xFF7C3AED),
      Color(0xFF059669),
      Color(0xFFD97706),
      Color(0xFFDB2777),
      Color(0xFF0891B2),
      Color(0xFF4F46E5),
      Color(0xFF65A30D),
      Color(0xFFDC2626),
    ];
    if (subject == null) return palette.first;
    return palette[subject.hashCode.abs() % palette.length];
  }
}
