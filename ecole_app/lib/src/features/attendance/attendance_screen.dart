import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../academics/academics_providers.dart';
import '../schedule/schedule_providers.dart';
import 'attendance_providers.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});
  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  String? _sessionId;

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(selectedScheduleDayProvider);
    final sessions = ref.watch(sessionsForDayProvider).valueOrNull ?? [];
    final classes = {for (final c in (ref.watch(classesProvider(null)).valueOrNull ?? <ClassesData>[])) c.id: c};
    final subjects = {for (final s in (ref.watch(subjectsProvider).valueOrNull ?? <Subject>[])) s.id: s};
    final fmt = DateFormat('dd/MM HH:mm');
    final selected = sessions.firstWhereOrNull((s) => s.id == _sessionId);

    return Row(children: [
      SizedBox(width: 360, child: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          Expanded(child: Text('Séances du ${DateFormat('dd/MM/yyyy').format(day)}')),
          IconButton(icon: const Icon(Icons.calendar_today), onPressed: () async { final d = await showDatePicker(context: context, initialDate: day, firstDate: DateTime(2020), lastDate: DateTime(2100)); if (d!=null) ref.read(selectedScheduleDayProvider.notifier).state = DateTime(d.year,d.month,d.day); }),
        ])),
        Expanded(child: ListView.builder(itemCount: sessions.length, itemBuilder: (context,i){ final s=sessions[i]; return ListTile(
          selected: s.id==_sessionId,
          title: Text('${subjects[s.subjectId]?.name ?? s.title ?? 'Séance'} ${fmt.format(s.startAt)}'),
          subtitle: Text(classes[s.classId]?.name ?? 'Sans classe'),
          onTap: ()=>setState(()=>_sessionId=s.id),
        ); })),
        if (sessions.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Aucune séance ce jour. Créez-en dans "Cours & Emplois du temps".')),
      ])),
      const VerticalDivider(width: 1),
      Expanded(child: selected == null ? const Center(child: Text('Sélectionnez une séance pour faire l\'appel.')) : _AttendanceSheet(session: selected)),
    ]);
  }
}

class _AttendanceSheet extends ConsumerStatefulWidget {
  final CourseSession session;
  const _AttendanceSheet({required this.session});
  @override
  ConsumerState<_AttendanceSheet> createState() => _AttendanceSheetState();
}

class _AttendanceSheetState extends ConsumerState<_AttendanceSheet> {
  late Future<List<Student>> _studentsFuture;

  @override
  void initState() { super.initState(); _studentsFuture = ref.read(attendanceRepositoryProvider).studentsForClassSession(widget.session); }
  @override
  void didUpdateWidget(covariant _AttendanceSheet oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.session.id != widget.session.id) _studentsFuture = ref.read(attendanceRepositoryProvider).studentsForClassSession(widget.session); }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(attendanceForSessionProvider(widget.session.id)).valueOrNull ?? [];
    final byStudent = {for (final r in records) r.studentId: r.status};
    return FutureBuilder<List<Student>>(future: _studentsFuture, builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final students = snap.data!;
      if (students.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Aucun élève trouvé pour la classe de cette séance (vérifiez la classe et les inscriptions).')));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          Text('Appel / Présences', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          FilledButton.tonal(onPressed: () async { for (final s in students) { await ref.read(attendanceRepositoryProvider).setAttendance(sessionId: widget.session.id, studentId: s.id, status: 'present'); } }, child: const Text('Tous présents')),
        ])),
        Expanded(child: ListView.builder(itemCount: students.length, itemBuilder: (context,i){ final s=students[i]; final status = byStudent[s.id] ?? 'absent'; return ListTile(
          leading: CircleAvatar(child: Text(s.firstName.isNotEmpty?s.firstName[0]:'?')),
          title: Text('${s.lastName} ${s.firstName}'),
          subtitle: Text(s.matricule),
          trailing: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'present', label: Text('P')),
              ButtonSegment(value: 'absent', label: Text('A')),
              ButtonSegment(value: 'late', label: Text('R')),
              ButtonSegment(value: 'excused', label: Text('J')),
            ],
            selected: {status},
            showSelectedIcon: false,
            onSelectionChanged: (v) => ref.read(attendanceRepositoryProvider).setAttendance(sessionId: widget.session.id, studentId: s.id, status: v.first),
          ),
        ); })),
        const Padding(padding: EdgeInsets.all(12), child: Text('P=Présent, A=Absent, R=Retard, J=Justifié/Excusé')),
      ]);
    });
  }
}
