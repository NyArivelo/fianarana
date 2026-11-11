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

class _SessionsTab extends ConsumerWidget {
  const _SessionsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(selectedScheduleDayProvider);
    final sessions = ref.watch(sessionsForDayProvider);
    final classes = {for (final c in (ref.watch(classesProvider(null)).valueOrNull ?? <ClassesData>[])) c.id: c};
    final subjects = {for (final s in (ref.watch(subjectsProvider).valueOrNull ?? <Subject>[])) s.id: s};
    final rooms = {for (final r in (ref.watch(roomsProvider).valueOrNull ?? <Room>[])) r.id: r};
    final fmtDay = DateFormat('EEEE dd/MM/yyyy', 'fr');
    final fmtTime = DateFormat('HH:mm');
    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => ref.read(selectedScheduleDayProvider.notifier).state = day.subtract(const Duration(days: 1))),
        TextButton(onPressed: () async {
          final d = await showDatePicker(context: context, initialDate: day, firstDate: DateTime(2020), lastDate: DateTime(2100));
          if (d != null) ref.read(selectedScheduleDayProvider.notifier).state = DateTime(d.year, d.month, d.day);
        }, child: Text(fmtDay.format(day))),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => ref.read(selectedScheduleDayProvider.notifier).state = day.add(const Duration(days: 1))),
        const Spacer(),
        FilledButton.icon(onPressed: () => _editSession(context, ref, day), icon: const Icon(Icons.add), label: const Text('Nouvelle séance')),
      ]),
      const SizedBox(height: 8),
      Expanded(child: sessions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) => list.isEmpty ? const Center(child: Text('Aucune séance pour ce jour.')) : ListView.separated(
          itemCount: list.length,
          separatorBuilder: (c, i) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final s = list[i];
            return Card(child: ListTile(
              title: Text('${s.title ?? subjects[s.subjectId]?.name ?? 'Séance'} • ${fmtTime.format(s.startAt)}-${fmtTime.format(s.endAt)}'),
              subtitle: Text([
                if (classes[s.classId] != null) 'Classe: ${classes[s.classId]!.name}',
                if (s.teacherName != null && s.teacherName!.isNotEmpty) 'Ens.: ${s.teacherName}',
                if (rooms[s.roomId] != null) 'Salle: ${rooms[s.roomId]!.name}',
                'Type: ${s.courseType}', 'Statut: ${s.status}',
              ].join(' • ')),
              trailing: Wrap(spacing: 4, children: [
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editSession(context, ref, day, s)),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => ref.read(scheduleRepositoryProvider).deleteSession(s.id)),
              ]),
            ));
          },
        ),
      )),
    ]));
  }

  static Future<void> _editSession(BuildContext context, WidgetRef ref, DateTime day, [CourseSession? s]) async {
    final years = ref.read(academicYearsProvider).valueOrNull ?? [];
    final yearId = s?.academicYearId ?? years.where((y) => y.isCurrent).firstOrNull?.id ?? (years.isNotEmpty ? years.first.id : null);
    String? classId = s?.classId;
    String? subjectId = s?.subjectId;
    String? roomId = s?.roomId;
    String courseType = s?.courseType ?? 'regular';
    final title = TextEditingController(text: s?.title ?? '');
    final teacher = TextEditingController(text: s?.teacherName ?? '');
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
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () async {
            final startAt = DateTime(date.year, date.month, date.day, start.hour, start.minute);
            final endAt = DateTime(date.year, date.month, date.day, end.hour, end.minute);
            if (!endAt.isAfter(startAt)) return;
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
