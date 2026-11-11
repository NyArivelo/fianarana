import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../academics/academics_providers.dart';
import '../settings/settings_providers.dart';
import 'schedule_providers.dart';

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(length: 2, child: Column(children: const [
      TabBar(tabs: [Tab(text: 'Emploi du temps / Séances'), Tab(text: 'Salles')]),
      Expanded(child: TabBarView(children: [_SessionsTab(), _RoomsTab()])),
    ]));
  }
}

class _SessionsTab extends ConsumerStatefulWidget {
  const _SessionsTab();
  @override
  ConsumerState<_SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends ConsumerState<_SessionsTab> {
  String? _classFilter;
  String? _roomFilter;

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(selectedScheduleDayProvider);
    final mode = ref.watch(scheduleViewModeProvider);
    final sessionsAsync = mode == 'week' ? ref.watch(sessionsForWeekProvider) : ref.watch(sessionsForDayProvider);
    final allClasses = ref.watch(classesProvider(null)).valueOrNull ?? <ClassesData>[];
    final classes = {for (final c in allClasses) c.id: c};
    final subjects = {for (final s in (ref.watch(subjectsProvider).valueOrNull ?? <Subject>[])) s.id: s};
    final allRooms = ref.watch(roomsProvider).valueOrNull ?? <Room>[];
    final rooms = {for (final r in allRooms) r.id: r};
    final fmtDay = DateFormat('EEEE dd/MM/yyyy', 'fr');
    final fmtTime = DateFormat('HH:mm');
    final weekStart = day.subtract(Duration(days: day.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final label = mode == 'week'
        ? 'Semaine du ${DateFormat('dd/MM').format(weekStart)} au ${DateFormat('dd/MM/yyyy').format(weekEnd)}'
        : fmtDay.format(day);
    final step = mode == 'week' ? 7 : 1;

    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => ref.read(selectedScheduleDayProvider.notifier).state = day.subtract(Duration(days: step))),
        TextButton(onPressed: () async {
          final d = await showDatePicker(context: context, initialDate: day, firstDate: DateTime(2020), lastDate: DateTime(2100));
          if (d != null) ref.read(selectedScheduleDayProvider.notifier).state = DateTime(d.year, d.month, d.day);
        }, child: Text(label)),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => ref.read(selectedScheduleDayProvider.notifier).state = day.add(Duration(days: step))),
        const SizedBox(width: 12),
        SegmentedButton<String>(segments: const [ButtonSegment(value: 'day', label: Text('Jour')), ButtonSegment(value: 'week', label: Text('Semaine'))], selected: {mode}, onSelectionChanged: (v) => ref.read(scheduleViewModeProvider.notifier).state = v.first),
        const SizedBox(width: 12),
        SizedBox(width: 180, child: DropdownButtonFormField<String?>(initialValue: _classFilter, isDense: true, decoration: const InputDecoration(labelText: 'Classe'), items: [const DropdownMenuItem(value: null, child: Text('Toutes')), for (final c in allClasses) DropdownMenuItem(value: c.id, child: Text(c.name))], onChanged: (v)=>setState(()=>_classFilter=v))),
        const SizedBox(width: 8),
        SizedBox(width: 160, child: DropdownButtonFormField<String?>(initialValue: _roomFilter, isDense: true, decoration: const InputDecoration(labelText: 'Salle'), items: [const DropdownMenuItem(value: null, child: Text('Toutes')), for (final r in allRooms) DropdownMenuItem(value: r.id, child: Text(r.name))], onChanged: (v)=>setState(()=>_roomFilter=v))),
        const Spacer(),
        FilledButton.icon(onPressed: () => _SessionsTabActions.editSession(context, ref, day), icon: const Icon(Icons.add), label: const Text('Nouvelle séance')),
      ]),
      const SizedBox(height: 8),
      Expanded(child: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) {
          final filtered = list.where((s) => (_classFilter == null || s.classId == _classFilter) && (_roomFilter == null || s.roomId == _roomFilter)).toList();
          if (filtered.isEmpty) return Center(child: Text(mode == 'week' ? 'Aucune séance cette semaine (filtres appliqués).' : 'Aucune séance pour ce jour (filtres appliqués).'));
          if (mode == 'week') {
            final byDay = <String, List<CourseSession>>{};
            for (final s in filtered) {
              final k = DateFormat('yyyy-MM-dd').format(s.startAt);
              byDay.putIfAbsent(k, () => []).add(s);
            }
            final keys = byDay.keys.toList()..sort();
            return ListView(children: [for (final k in keys) ...[
              Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(DateFormat('EEEE dd/MM/yyyy', 'fr').format(DateTime.parse(k)), style: const TextStyle(fontWeight: FontWeight.bold))),
              for (final s in byDay[k]!) _SessionsTabActions.sessionTile(context, ref, s, classes, subjects, rooms, fmtTime),
              const SizedBox(height: 4),
            ]]);
          }
          return ListView.separated(itemCount: filtered.length, separatorBuilder: (c, i) => const SizedBox(height: 8), itemBuilder: (context, i) => _SessionsTabActions.sessionTile(context, ref, filtered[i], classes, subjects, rooms, fmtTime));
        },
      )),
    ]));
  }
}

class _SessionsTabActions {
  static Widget sessionTile(BuildContext context, WidgetRef ref, CourseSession s, Map<String, ClassesData> classes, Map<String, Subject> subjects, Map<String, Room> rooms, DateFormat fmtTime) {
    final day = DateTime(s.startAt.year, s.startAt.month, s.startAt.day);
    return Card(child: ListTile(
      title: Text('${s.title ?? subjects[s.subjectId]?.name ?? 'Séance'} • ${fmtTime.format(s.startAt)}-${fmtTime.format(s.endAt)}'),
      subtitle: Text([
        if (classes[s.classId] != null) 'Classe: ${classes[s.classId]!.name}',
        if (s.teacherName != null && s.teacherName!.isNotEmpty) 'Ens.: ${s.teacherName}',
        if (rooms[s.roomId] != null) 'Salle: ${rooms[s.roomId]!.name}',
        'Type: ${s.courseType}', 'Statut: ${s.status}',
      ].join(' • ')),
      trailing: Wrap(spacing: 4, children: [
        IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => editSession(context, ref, day, s)),
        IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => ref.read(scheduleRepositoryProvider).deleteSession(s.id)),
      ]),
    ));
  }

  static Future<void> editSession(BuildContext context, WidgetRef ref, DateTime day, [CourseSession? s]) async {
    final years = ref.read(academicYearsProvider).valueOrNull ?? [];
    final yearId = s?.academicYearId ?? years.where((y) => y.isCurrent).firstOrNull?.id ?? (years.isNotEmpty ? years.first.id : null);
    String? classId = s?.classId;
    String? subjectId = s?.subjectId;
    String? roomId = s?.roomId;
    String courseType = s?.courseType ?? 'regular';
    final title = TextEditingController(text: s?.title ?? '');
    final teacher = TextEditingController(text: s?.teacherName ?? '');
    final repeatWeeks = TextEditingController(text: '1');
    bool repeat = false;
    TimeOfDay start = TimeOfDay.fromDateTime(s?.startAt ?? DateTime(day.year, day.month, day.day, 8, 0));
    TimeOfDay end = TimeOfDay.fromDateTime(s?.endAt ?? DateTime(day.year, day.month, day.day, 10, 0));
    DateTime date = s?.startAt ?? day;
    final subjects = ref.read(subjectsProvider).valueOrNull ?? [];
    final rooms = ref.read(roomsProvider).valueOrNull ?? [];

    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final classes = ref.watch(classesProvider(yearId)).valueOrNull ?? [];
      return AlertDialog(
        title: Text(s == null ? 'Nouvelle séance' : 'Modifier la séance'),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Titre (optionnel)')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () async { final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100)); if (d!=null) setState(()=>date=d); }, child: Text(DateFormat('dd/MM/yyyy').format(date)))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () async { final t = await showTimePicker(context: ctx, initialTime: start); if (t!=null) setState(()=>start=t); }, child: Text('Début ${start.format(ctx)}'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () async { final t = await showTimePicker(context: ctx, initialTime: end); if (t!=null) setState(()=>end=t); }, child: Text('Fin ${end.format(ctx)}'))),
          ]),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: classId,
            decoration: const InputDecoration(labelText: 'Classe'),
            items: [const DropdownMenuItem(value: null, child: Text('(Aucune)')), for (final c in classes) DropdownMenuItem(value: c.id, child: Text(c.name))],
            onChanged: (v) => setState(() => classId = v),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: subjectId,
            decoration: const InputDecoration(labelText: 'Matière'),
            items: [const DropdownMenuItem(value: null, child: Text('(Aucune)')), for (final sub in subjects) DropdownMenuItem(value: sub.id, child: Text(sub.name))],
            onChanged: (v) => setState(() => subjectId = v),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: roomId,
            decoration: const InputDecoration(labelText: 'Salle'),
            items: [const DropdownMenuItem(value: null, child: Text('(Aucune)')), for (final r in rooms) DropdownMenuItem(value: r.id, child: Text(r.name))],
            onChanged: (v) => setState(() => roomId = v),
          ),
          const SizedBox(height: 8),
          TextField(controller: teacher, decoration: const InputDecoration(labelText: 'Enseignant')),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: courseType,
            decoration: const InputDecoration(labelText: 'Type de cours'),
            items: const [
              DropdownMenuItem(value: 'regular', child: Text('Régulier')),
              DropdownMenuItem(value: 'evening', child: Text('Cours du soir')),
              DropdownMenuItem(value: 'weekend', child: Text('Week-end')),
              DropdownMenuItem(value: 'intensive', child: Text('Intensif')),
            ],
            onChanged: (v) => setState(() => courseType = v ?? 'regular'),
          ),
          if (s == null) ...[
            const SizedBox(height: 8),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: repeat, onChanged: (v)=>setState(()=>repeat = v ?? false), title: const Text('Répéter chaque semaine (récurrence)')),
            if (repeat) TextField(controller: repeatWeeks, decoration: const InputDecoration(labelText: 'Nombre de semaines'), keyboardType: TextInputType.number),
          ],
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () async {
            final startAt = DateTime(date.year, date.month, date.day, start.hour, start.minute);
            final endAt = DateTime(date.year, date.month, date.day, end.hour, end.minute);
            if (!endAt.isAfter(startAt)) return;
            if (s == null && repeat) {
              final weeks = (int.tryParse(repeatWeeks.text) ?? 1).clamp(1, 52);
              final n = await ref.read(scheduleRepositoryProvider).createRecurringSessions(
                academicYearId: yearId, classId: classId, subjectId: subjectId, roomId: roomId,
                teacherName: teacher.text.trim().isEmpty ? null : teacher.text.trim(),
                title: title.text.trim().isEmpty ? null : title.text.trim(), courseType: courseType,
                firstStartAt: startAt, firstEndAt: endAt, weeks: weeks);
              if (ctx.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$n séances créées (récurrence hebdomadaire).')));
                Navigator.pop(ctx);
              }
              return;
            }
            final conflicts = await ref.read(scheduleRepositoryProvider).detectConflicts(
              excludeId: s?.id, roomId: roomId, classId: classId, teacherName: teacher.text, startAt: startAt, endAt: endAt);
            if (conflicts.isNotEmpty && ctx.mounted) {
              final proceed = await showDialog<bool>(context: ctx, builder: (c2) => AlertDialog(
                title: const Text('Conflits détectés'),
                content: Text(conflicts.map((c) => '• ${c.message}').join('\n')),
                actions: [TextButton(onPressed: ()=>Navigator.pop(c2,false), child: const Text('Annuler')), FilledButton(onPressed: ()=>Navigator.pop(c2,true), child: const Text('Enregistrer quand même'))],
              ));
              if (proceed != true) return;
            }
            await ref.read(scheduleRepositoryProvider).upsertSession(
              id: s?.id, academicYearId: yearId, classId: classId, subjectId: subjectId, roomId: roomId,
              teacherName: teacher.text.trim().isEmpty ? null : teacher.text.trim(),
              title: title.text.trim().isEmpty ? null : title.text.trim(), courseType: courseType,
              startAt: startAt, endAt: endAt);
            if (ctx.mounted) Navigator.pop(ctx);
          }, child: const Text('Enregistrer')),
        ],
      );
    }));
  }
}

class _RoomsTab extends ConsumerWidget {
  const _RoomsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsProvider);
    return Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      Row(children: [Text('Salles', style: Theme.of(context).textTheme.titleMedium), const Spacer(), FilledButton.icon(onPressed: () => _editRoom(context, ref), icon: const Icon(Icons.add), label: const Text('Ajouter'))]),
      const SizedBox(height: 12),
      Expanded(child: rooms.when(loading: ()=>const Center(child:CircularProgressIndicator()), error:(e,_)=>Center(child:Text('Erreur: $e')), data:(list)=> list.isEmpty? const Center(child:Text('Aucune salle.')) : ListView.builder(itemCount:list.length,itemBuilder:(context,i){ final r=list[i]; return ListTile(title:Text(r.name), subtitle:Text([r.location, r.capacity!=null?'Cap: ${r.capacity}':null].whereType<String>().join(' • ')), trailing:IconButton(icon:const Icon(Icons.edit_outlined), onPressed:()=>_editRoom(context,ref,r))); }))),
    ]));
  }
  static Future<void> _editRoom(BuildContext context, WidgetRef ref, [Room? r]) async {
    final name = TextEditingController(text: r?.name ?? '');
    final loc = TextEditingController(text: r?.location ?? '');
    final cap = TextEditingController(text: r?.capacity?.toString() ?? '');
    await showDialog(context: context, builder: (ctx)=>AlertDialog(title: Text(r==null?'Nouvelle salle':'Modifier la salle'), content: SizedBox(width:400, child: Column(mainAxisSize:MainAxisSize.min, children:[
      TextField(controller:name, decoration: const InputDecoration(labelText:'Nom')),
      TextField(controller:loc, decoration: const InputDecoration(labelText:'Emplacement')),
      TextField(controller:cap, decoration: const InputDecoration(labelText:'Capacité'), keyboardType: TextInputType.number),
    ])), actions:[TextButton(onPressed:()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed:() async { if(name.text.trim().isEmpty) return; await ref.read(scheduleRepositoryProvider).upsertRoom(id:r?.id, name:name.text.trim(), location: loc.text.trim().isEmpty?null:loc.text.trim(), capacity:int.tryParse(cap.text)); if(ctx.mounted) Navigator.pop(ctx); }, child: const Text('Enregistrer'))]));
  }
}
