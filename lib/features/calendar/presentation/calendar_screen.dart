import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/calendar/application/calendar_providers.dart';
import 'package:fianarana/features/calendar/data/calendar_repository.dart';

const _categories = <String>[
  'Rentrée',
  'Vacances',
  'Jour férié',
  'Examen',
  'Réunion',
  'Événement',
  'Sortie',
  'Éphéméride',
];

const _categoryColors = <String, Color>{
  'Rentrée': Color(0xFF2563EB),
  'Vacances': Color(0xFFF59E0B),
  'Jour férié': Color(0xFFEF4444),
  'Examen': Color(0xFF7C3AED),
  'Réunion': Color(0xFF0891B2),
  'Événement': Color(0xFF059669),
  'Sortie': Color(0xFFDB2777),
  'Éphéméride': Color(0xFF0EA5E9),
};

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

enum _EphemerisGrouping { bimestriel, trimestriel, annuel }

class _CalendarScreenState extends ConsumerState<CalendarScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String? _classId;
  DateTime? _selectedDay;
  _EphemerisGrouping _ephemerisGrouping = _EphemerisGrouping.trimestriel;

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  DateTime get _rangeStart => DateTime(_month.year, _month.month, 1);
  DateTime get _rangeEnd => DateTime(_month.year, _month.month + 1, 0);

  void _previousMonth() => setState(() {
        _month = DateTime(_month.year, _month.month - 1, 1);
        _selectedDay = null;
      });

  void _nextMonth() => setState(() {
        _month = DateTime(_month.year, _month.month + 1, 1);
        _selectedDay = null;
      });

  Future<void> _openEventDialog({CalendarEntry? entry, bool ephemeris = false, DateTime? initialDate}) async {
    final auth = ref.read(authControllerProvider);
    final classes = await ref.read(calendarClassesProvider.future);
    if (!mounted) return;
    String? classId = entry?.event.classId ?? (ephemeris ? null : _classId);
    String category = entry?.event.category ?? (ephemeris ? 'Éphéméride' : 'Événement');
    var isEphemeris = entry?.event.isEphemeris ?? ephemeris;
    var allDay = entry?.event.allDay ?? true;
    DateTime start = entry?.event.startDate ?? initialDate ?? DateTime.now();
    DateTime? end = entry?.event.endDate;
    final titleCtrl = TextEditingController(text: entry?.event.title ?? '');
    final startTimeCtrl = TextEditingController(text: entry?.event.startTime ?? '08:00');
    final endTimeCtrl = TextEditingController(text: entry?.event.endTime ?? '10:00');
    final locationCtrl = TextEditingController(text: entry?.event.location ?? '');
    final descCtrl = TextEditingController(text: entry?.event.description ?? '');

    String fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(entry == null ? (ephemeris ? 'Nouvel éphéméride' : 'Nouvel événement') : 'Modifier l\'événement'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Titre')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Catégorie'),
                  items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setDialogState(() {
                    category = v ?? 'Événement';
                    if (category == 'Éphéméride') isEphemeris = true;
                  }),
                ),
                const SizedBox(height: 8),
                if (!ephemeris && !isEphemeris)
                  DropdownButtonFormField<String?>(
                    value: classId,
                    decoration: const InputDecoration(labelText: 'Classe (vide = établissement)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Tout l\'établissement')),
                      ...classes.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.label))),
                    ],
                    onChanged: (v) => setDialogState(() => classId = v),
                  ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: start,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) setDialogState(() => start = picked);
                      },
                      icon: const Icon(Icons.event, size: 16),
                      label: Text('Début: ${fmt(start)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: end ?? start,
                          firstDate: start,
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) setDialogState(() => end = picked);
                      },
                      icon: const Icon(Icons.event_available, size: 16),
                      label: Text(end == null ? 'Fin (optionnel)' : 'Fin: ${fmt(end!)}'),
                    ),
                  ),
                  if (end != null)
                    IconButton(onPressed: () => setDialogState(() => end = null), icon: const Icon(Icons.clear, size: 16)),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Journée entière'),
                  value: allDay,
                  onChanged: (v) => setDialogState(() => allDay = v),
                ),
                if (!allDay)
                  Row(children: [
                    Expanded(child: TextField(controller: startTimeCtrl, decoration: const InputDecoration(labelText: 'Début (HH:mm)'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: endTimeCtrl, decoration: const InputDecoration(labelText: 'Fin (HH:mm)'))),
                  ]),
                const SizedBox(height: 8),
                TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Lieu (optionnel)')),
                const SizedBox(height: 8),
                TextField(controller: descCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Description (optionnel)')),
                if (ephemeris || isEphemeris)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Cet événement sera classé dans l\'éphéméride globale.',
                        style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.primary)),
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
                    await ref.read(calendarRepositoryProvider).delete(
                          entry.event.id,
                          actorUserId: auth.userId,
                          actorUsername: auth.username,
                        );
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erreur: $e')));
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
    if (titleCtrl.text.trim().isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Le titre est obligatoire.')));
      return;
    }
    try {
      await ref.read(calendarRepositoryProvider).upsert(
            id: entry?.event.id,
            classId: (ephemeris || isEphemeris) ? null : classId,
            title: titleCtrl.text.trim(),
            category: category,
            startDate: start,
            endDate: end,
            allDay: allDay,
            startTime: allDay ? null : startTimeCtrl.text.trim(),
            endTime: allDay ? null : endTimeCtrl.text.trim(),
            location: locationCtrl.text.trim().isEmpty ? null : locationCtrl.text.trim(),
            description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
            colorHex: _hexOf(_categoryColors[category] ?? const Color(0xFF2563EB)),
            isEphemeris: ephemeris || isEphemeris || category == 'Éphéméride',
            actorUserId: auth.userId,
            actorUsername: auth.username,
          );
      ref.invalidate(calendarEventsProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Événement enregistré.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Calendrier scolaire & éphéméride'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.calendar_month_outlined, size: 17), text: 'Calendrier par classe'),
            Tab(icon: Icon(Icons.auto_awesome_outlined, size: 17), text: 'Éphéméride globale'),
          ],
        ),
        actions: [
          FilledButton.icon(
            onPressed: () => _openEventDialog(initialDate: _selectedDay ?? _month),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Nouvel événement'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _classCalendarTab(context),
          _ephemerisTab(context),
        ],
      ),
    );
  }

  Widget _classCalendarTab(BuildContext context) {
    final entriesAsync = ref.watch(calendarEventsProvider((
      classId: _classId,
      includeGlobal: true,
      isEphemeris: false,
      from: _rangeStart,
      to: _rangeEnd,
    )));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _monthToolbar(
          context,
          onAdd: () => _openEventDialog(initialDate: _selectedDay ?? _month),
          extra: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 220,
              child: ref.watch(calendarClassesProvider).when(
                    data: (classes) => DropdownButtonFormField<String?>(
                      value: _classId,
                      isDense: true,
                      decoration: const InputDecoration(labelText: 'Classe'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Toutes les classes')),
                        ...classes.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.label))),
                      ],
                      onChanged: (v) => setState(() {
                        _classId = v;
                        _selectedDay = null;
                      }),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Erreur: $e'),
                  ),
            ),
            const SizedBox(width: 8),
          ]),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: entriesAsync.when(
            data: (entries) => LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1050;
              final calendar = _monthGrid(context, entries);
              final list = _eventList(context, entries, title: 'Événements du mois');
              if (wide) {
                return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(flex: 3, child: calendar),
                  const SizedBox(width: 12),
                  SizedBox(width: 380, child: list),
                ]);
              }
              return Column(children: [
                Expanded(child: calendar),
                const SizedBox(height: 12),
                SizedBox(height: 250, child: list),
              ]);
            }),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Erreur calendrier: $e')),
          ),
        ),
      ]),
    );
  }

  Widget _ephemerisTab(BuildContext context) {
    final entriesAsync = ref.watch(calendarEventsProvider((
      classId: null,
      includeGlobal: true,
      isEphemeris: true,
      from: null,
      to: null,
    )));
    final periodsAsync = ref.watch(calendarPeriodsProvider);
    final yearAsync = ref.watch(activeSchoolYearProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: entriesAsync.when(
        data: (entries) {
          final periods = periodsAsync.valueOrNull ?? const <Period>[];
          final year = yearAsync.valueOrNull;
          final groups = _buildEphemerisGroups(entries, periods, year);
          return Column(children: [
            _ephemerisBanner(context, entries, year),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_EphemerisGrouping>(
                segments: const [
                  ButtonSegment(value: _EphemerisGrouping.bimestriel, icon: Icon(Icons.view_week_outlined, size: 16), label: Text('Bimestriel')),
                  ButtonSegment(value: _EphemerisGrouping.trimestriel, icon: Icon(Icons.view_agenda_outlined, size: 16), label: Text('Trimestriel')),
                  ButtonSegment(value: _EphemerisGrouping.annuel, icon: Icon(Icons.calendar_view_month_outlined, size: 16), label: Text('Annuel')),
                ],
                selected: {_ephemerisGrouping},
                onSelectionChanged: (s) => setState(() => _ephemerisGrouping = s.first),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('Aucun éphéméride enregistré.'))
                  : ListView.builder(
                      itemCount: groups.length,
                      itemBuilder: (context, i) {
                        final g = groups[i];
                        final isDark = Theme.of(context).brightness == Brightness.dark;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                              child: Row(children: [
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(g.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                  Text(g.subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                ])),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                                  child: Text('${g.entries.length} date(s)', style: const TextStyle(fontSize: 10, color: Color(0xFF0284C7), fontWeight: FontWeight.w600)),
                                ),
                              ]),
                            ),
                            const Divider(height: 1),
                            if (g.entries.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(14),
                                child: Text('Aucune date dans cette période.', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                              )
                            else
                              ...g.entries.map((e) => Padding(
                                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
                                    child: _ephemerisTile(context, e),
                                  )),
                            const SizedBox(height: 6),
                          ]),
                        );
                      },
                    ),
            ),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur éphéméride: $e')),
      ),
    );
  }

  List<EphemerisPeriodGroup> _buildEphemerisGroups(List<CalendarEntry> entries, List<Period> periods, SchoolYear? year) {
    final sorted = [...entries]..sort((a, b) => a.event.startDate.compareTo(b.event.startDate));
    DateTime d(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
    bool inRange(DateTime date, DateTime start, DateTime end) {
      final dd = d(date);
      return !dd.isBefore(d(start)) && !dd.isAfter(d(end));
    }

    if (_ephemerisGrouping == _EphemerisGrouping.annuel) {
      final start = year?.startDate ?? (sorted.isNotEmpty ? sorted.first.event.startDate : DateTime(DateTime.now().year, 1, 1));
      final end = year?.endDate ?? (sorted.isNotEmpty ? sorted.last.event.startDate : DateTime(DateTime.now().year, 12, 31));
      return [EphemerisPeriodGroup(
        label: 'Éphéméride annuel',
        subtitle: '${year?.label ?? 'Année scolaire'} • ${_dateLabel(start)} → ${_dateLabel(end)}',
        start: start, end: end, entries: sorted,
      )];
    }

    // Construire des périodes de référence (trimestres) si possible, sinon fallback sur l'année.
    final basePeriods = periods.where((p) => p.startDate != null && p.endDate != null).toList();
    if (basePeriods.isEmpty) {
      final start = year?.startDate ?? DateTime(DateTime.now().year, 1, 1);
      final end = year?.endDate ?? DateTime(DateTime.now().year, 12, 31);
      return [EphemerisPeriodGroup(label: 'Année scolaire', subtitle: '${_dateLabel(start)} → ${_dateLabel(end)}', start: start, end: end, entries: sorted)];
    }

    if (_ephemerisGrouping == _EphemerisGrouping.trimestriel) {
      return basePeriods.map((p) {
        final start = p.startDate!;
        final end = p.endDate!;
        final list = sorted.where((e) => inRange(e.event.startDate, start, end)).toList();
        return EphemerisPeriodGroup(label: p.name, subtitle: '${_dateLabel(start)} → ${_dateLabel(end)}', start: start, end: end, entries: list);
      }).toList();
    }

    // Bimestriel: découper chaque trimestre en 2 bimestres
    final groups = <EphemerisPeriodGroup>[];
    var idx = 1;
    for (final p in basePeriods) {
      final start = d(p.startDate!);
      final end = d(p.endDate!);
      final totalDays = end.difference(start).inDays + 1;
      final split = start.add(Duration(days: (totalDays / 2).ceil() - 1));
      final b1End = split.isAfter(end) ? end : split;
      final b2Start = b1End.add(const Duration(days: 1)).isAfter(end) ? end : b1End.add(const Duration(days: 1));
      final ranges = <({DateTime s, DateTime e})>[
        (s: start, e: b1End),
        (s: b2Start.isAfter(end) ? end : b2Start, e: end),
      ];
      for (var i = 0; i < ranges.length; i++) {
        final r = ranges[i];
        final label = 'Bimestre $idx';
        final subtitle = '${p.name} (${i + 1}/2) • ${_dateLabel(r.s)} → ${_dateLabel(r.e)}';
        groups.add(EphemerisPeriodGroup(
          label: label,
          subtitle: subtitle,
          start: r.s,
          end: r.e,
          entries: sorted.where((e) => inRange(e.event.startDate, r.s, r.e)).toList(),
        ));
        idx++;
      }
    }
    return groups;
  }

  Widget _ephemerisBanner(BuildContext context, List<CalendarEntry> entries, SchoolYear? year) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Éphéméride de l\'établissement', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('${entries.length} dates à célébrer ou à commémorer — ${year?.label ?? 'année scolaire 2026-2027'} (vue ${_ephemerisGrouping.name}).',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 11)),
          ]),
        ),
        FilledButton.tonalIcon(
          onPressed: () => _openEventDialog(ephemeris: true),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Ajouter'),
        ),
      ]),
    );
  }

  Widget _ephemerisTile(BuildContext context, CalendarEntry entry) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _eventColor(entry);
    final e = entry.event;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 52,
          child: Column(children: [
            Text('${e.startDate.day}'.padLeft(2, '0'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            Text(_shortMonth(e.startDate), style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            if (e.description != null) Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(e.description!, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            ),
          ]),
        ),
        IconButton(
          tooltip: 'Modifier',
          onPressed: () => _openEventDialog(entry: entry, ephemeris: true),
          icon: const Icon(Icons.edit_outlined, size: 16),
        ),
      ]),
    );
  }

  Widget _monthToolbar(BuildContext context, {required VoidCallback onAdd, Widget? extra}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(children: [
        IconButton(onPressed: _previousMonth, icon: const Icon(Icons.chevron_left)),
        SizedBox(
          width: 190,
          child: Text(
            _monthLabel(_month),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(onPressed: _nextMonth, icon: const Icon(Icons.chevron_right)),
        TextButton(
          onPressed: () => setState(() {
            _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
            _selectedDay = null;
          }),
          child: const Text("Aujourd'hui"),
        ),
        const Spacer(),
        if (extra != null) extra,
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Événement'),
        ),
      ]),
    );
  }

  Widget _monthGrid(BuildContext context, List<CalendarEntry> entries) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final first = DateTime(_month.year, _month.month, 1);
    final offset = (first.weekday - 1) % 7; // lundi = 0
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final totalCells = ((offset + daysInMonth + 6) ~/ 7) * 7;
    final rows = totalCells ~/ 7;
    final now = DateTime.now();
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(children: [
        Container(
          height: 34,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0B1220) : const Color(0xFFF8FAFC),
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Row(children: [
            for (final d in ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'])
              Expanded(child: Center(child: Text(d, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))))),
          ]),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final rowHeight = constraints.maxHeight / rows;
            return Column(children: [
              for (var week = 0; week < rows; week++)
                SizedBox(
                  height: rowHeight,
                  child: Row(children: [
                    for (var d = 0; d < 7; d++)
                      Expanded(
                        child: _dayCell(
                          context,
                          dayNumber: week * 7 + d - offset + 1,
                          daysInMonth: daysInMonth,
                          entries: entries,
                          now: now,
                          isLastCol: d == 6,
                          isLastRow: week == rows - 1,
                          border: border,
                        ),
                      ),
                  ]),
                ),
            ]);
          }),
        ),
      ]),
    );
  }

  Widget _dayCell(
    BuildContext context, {
    required int dayNumber,
    required int daysInMonth,
    required List<CalendarEntry> entries,
    required DateTime now,
    required bool isLastCol,
    required bool isLastRow,
    required Color border,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final valid = dayNumber >= 1 && dayNumber <= daysInMonth;
    final date = DateTime(_month.year, _month.month, dayNumber);
    final dayEntries = valid ? entries.where((e) => _covers(e.event, date)).toList() : const <CalendarEntry>[];
    final isToday = valid && _sameDay(date, now);
    final selected = valid && _selectedDay != null && _sameDay(date, _selectedDay!);
    return InkWell(
      onTap: valid ? () => setState(() => _selectedDay = date) : null,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF2563EB).withValues(alpha: 0.08)
              : (isToday && isDark ? const Color(0xFF172554).withValues(alpha: 0.35) : null),
          border: Border(
            left: isLastCol ? BorderSide.none : BorderSide(color: border, width: 0.6),
            bottom: isLastRow ? BorderSide.none : BorderSide(color: border, width: 0.6),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (valid)
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isToday ? const Color(0xFF2563EB) : null,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$dayNumber',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    color: isToday ? Colors.white : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 2),
          Expanded(
            child: ClipRect(
              child: Column(children: dayEntries.take(3).map((e) {
                final color = _eventColor(e);
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 1.5),
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    e.event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600, color: color),
                  ),
                );
              }).toList()),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _eventList(BuildContext context, List<CalendarEntry> entries, {required String title}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final filtered = _selectedDay == null
        ? entries
        : entries.where((e) => _covers(e.event, _selectedDay!)).toList();
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
          child: Row(children: [
            Expanded(
              child: Text(
                _selectedDay == null ? title : 'Le ${_dateLabel(_selectedDay!)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            if (_selectedDay != null)
              IconButton(
                tooltip: 'Voir tout le mois',
                onPressed: () => setState(() => _selectedDay = null),
                icon: const Icon(Icons.close, size: 16),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('${filtered.length}', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Aucun événement.', style: TextStyle(color: Color(0xFF94A3B8))))
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => _eventTile(context, filtered[i]),
                ),
        ),
      ]),
    );
  }

  Widget _eventTile(BuildContext context, CalendarEntry entry) {
    final color = _eventColor(entry);
    final e = entry.event;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => _openEventDialog(entry: entry),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0B1220) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(e.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (!entry.isGlobal)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFF7C3AED).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                child: Text(entry.classLabel ?? 'Classe', style: const TextStyle(fontSize: 9, color: Color(0xFF7C3AED))),
              ),
          ]),
          const SizedBox(height: 3),
          Text(
            '${_dateRange(e)}${e.allDay ? '' : ' • ${e.startTime ?? ''}-${e.endTime ?? ''}'}${e.location == null ? '' : ' • ${e.location}'}',
            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ]),
      ),
    );
  }

  Color _eventColor(CalendarEntry entry) {
    final hex = entry.event.colorHex;
    if (hex != null && hex.startsWith('#') && hex.length == 7) {
      final value = int.tryParse(hex.substring(1), radix: 16);
      if (value != null) return Color(0xFF000000 | value);
    }
    return _categoryColors[entry.event.category] ?? const Color(0xFF2563EB);
  }

  bool _covers(CalendarEvent e, DateTime day) {
    final start = DateTime(e.startDate.year, e.startDate.month, e.startDate.day);
    final end = e.endDate == null ? start : DateTime(e.endDate!.year, e.endDate!.month, e.endDate!.day);
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  String _dateRange(CalendarEvent e) {
    if (e.endDate == null || _sameDay(e.startDate, e.endDate!)) return _dateLabel(e.startDate);
    return '${_dateLabel(e.startDate)} → ${_dateLabel(e.endDate!)}';
  }

  String _dateLabel(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _monthLabel(DateTime d) {
    const months = [
      'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
      'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  String _shortMonth(DateTime d) {
    const months = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin', 'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc'];
    return months[d.month - 1];
  }

  String _hexOf(Color c) => '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}
