import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/staff/application/staff_providers.dart';
import 'package:fianarana/features/timetable/application/timetable_providers.dart';

class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});
  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _addOrEdit([StaffMember? s]) async {
    final auth = ref.read(authControllerProvider);
    final repo = ref.read(staffRepositoryProvider);
    final num = TextEditingController(text: s?.staffNumber ?? '');
    final ln = TextEditingController(text: s?.lastName ?? '');
    final fn = TextEditingController(text: s?.firstName ?? '');
    final fct = TextEditingController(text: s?.functionTitle ?? '');
    final dep = TextEditingController(text: s?.departmentOrSubject ?? '');
    final phone = TextEditingController(text: s?.phone ?? '');
    final ok = await showDialog<bool>(context: context, builder: (ctx)=>AlertDialog(
      title: Text(s == null ? 'Nouveau personnel' : 'Modifier personnel'),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: num, decoration: const InputDecoration(labelText: 'Matricule RH')),
        const SizedBox(height: 8), TextField(controller: ln, decoration: const InputDecoration(labelText: 'Nom')),
        const SizedBox(height: 8), TextField(controller: fn, decoration: const InputDecoration(labelText: 'Prénom')),
        const SizedBox(height: 8), TextField(controller: fct, decoration: const InputDecoration(labelText: 'Fonction')),
        const SizedBox(height: 8), TextField(controller: dep, decoration: const InputDecoration(labelText: 'Matière/Service')),
        const SizedBox(height: 8), TextField(controller: phone, decoration: const InputDecoration(labelText: 'Téléphone')),
      ]))),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('Annuler')), FilledButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('Enregistrer'))],
    ));
    if (ok == true) {
      try {
        await repo.upsertStaff(id: s?.id, staffNumber: num.text.trim(), lastName: ln.text.trim(), firstName: fn.text.trim(), functionTitle: fct.text.trim(), departmentOrSubject: dep.text.trim(), phone: phone.text.trim(), actorUserId: auth.userId, actorUsername: auth.username);
        ref.invalidate(staffListProvider);
        ref.invalidate(timetableTeachersProvider);
      } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'))); }
    }
  }

  Future<void> _declareAbsence() async {
    final auth = ref.read(authControllerProvider);
    final repo = ref.read(staffRepositoryProvider);
    final teachers = await repo.listStaff(actorUserId: auth.userId);
    final classes = await ref.read(timetableClassesProvider.future);
    final subjects = await ref.read(timetableSubjectsProvider.future);
    final rooms = await repo.availableRooms();
    if (!mounted) return;
    String? teacherId = teachers.isNotEmpty ? teachers.first.id : null;
    String? substituteId;
    String? classId; String? subjectId; String? roomId;
    DateTime start = DateTime.now();
    DateTime end = DateTime.now();
    String day = 'Lundi';
    final startT = TextEditingController(text: '08:00');
    final endT = TextEditingController(text: '10:00');
    final reason = TextEditingController(text: 'Absence enseignant');
    final ok = await showDialog<bool>(context: context, builder: (ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title: const Text('Absence enseignant & remplacement/rattrapage'),
      content: SizedBox(width: 640, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children:[
        DropdownButtonFormField<String>(value: teacherId, decoration: const InputDecoration(labelText: 'Enseignant absent'), items: teachers.map((t)=>DropdownMenuItem(value:t.id, child: Text('${t.lastName} ${t.firstName}'))).toList(), onChanged: (v)=>setD(()=>teacherId=v)),
        Row(children:[Expanded(child: OutlinedButton(onPressed: () async { final d=await showDatePicker(context: ctx, initialDate: start, firstDate: DateTime(2020), lastDate: DateTime(2100)); if(d!=null) setD(()=>start=d); }, child: Text('Début ${start.day}/${start.month}'))), const SizedBox(width:8), Expanded(child: OutlinedButton(onPressed: () async { final d=await showDatePicker(context: ctx, initialDate: end, firstDate: DateTime(2020), lastDate: DateTime(2100)); if(d!=null) setD(()=>end=d); }, child: Text('Fin ${end.day}/${end.month}')))]),
        TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motif')),
        const Divider(height: 20),
        const Align(alignment: Alignment.centerLeft, child: Text('Remplacement / cours de rattrapage (optionnel)', style: TextStyle(fontWeight: FontWeight.w600))),
        DropdownButtonFormField<String?>(value: substituteId, decoration: const InputDecoration(labelText: 'Enseignant remplaçant'), items: [const DropdownMenuItem<String?>(value:null, child: Text('Aucun (déclarer seulement)')), ...teachers.map((t)=>DropdownMenuItem<String?>(value:t.id, child: Text('${t.lastName} ${t.firstName}')))], onChanged: (v)=>setD(()=>substituteId=v)),
        DropdownButtonFormField<String?>(value: classId, decoration: const InputDecoration(labelText: 'Classe'), items: [const DropdownMenuItem<String?>(value:null, child: Text('-')), ...classes.map((c)=>DropdownMenuItem<String?>(value:c.id, child: Text(c.label)))], onChanged: (v)=>setD(()=>classId=v)),
        DropdownButtonFormField<String?>(value: subjectId, decoration: const InputDecoration(labelText: 'Matière'), items: [const DropdownMenuItem<String?>(value:null, child: Text('-')), ...subjects.map((s)=>DropdownMenuItem<String?>(value:s.id, child: Text(s.name)))], onChanged: (v)=>setD(()=>subjectId=v)),
        DropdownButtonFormField<String?>(value: roomId, decoration: const InputDecoration(labelText: 'Salle (créneaux/salles à vérifier)'), items: [const DropdownMenuItem<String?>(value:null, child: Text('-')), ...rooms.map((r)=>DropdownMenuItem<String?>(value:r.id, child: Text(r.name)))], onChanged: (v)=>setD(()=>roomId=v)),
        Row(children:[Expanded(child: DropdownButtonFormField<String>(value: day, decoration: const InputDecoration(labelText: 'Jour'), items: const ['Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi'].map((d)=>DropdownMenuItem(value:d, child: Text(d))).toList(), onChanged: (v)=>setD(()=>day=v??day))), const SizedBox(width:8), Expanded(child: TextField(controller: startT, decoration: const InputDecoration(labelText: 'Début HH:mm'))), const SizedBox(width:8), Expanded(child: TextField(controller: endT, decoration: const InputDecoration(labelText: 'Fin HH:mm')))]),
      ]))),
      actions:[TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('Annuler')), FilledButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('Enregistrer'))],
    )));
    if (ok == true && teacherId != null) {
      try {
        await repo.declareAbsenceAndReplacement(
          teacherId: teacherId!,
          startDate: start, endDate: end, reason: reason.text.trim(),
          substituteTeacherId: substituteId, replacementClassId: classId, replacementSubjectId: subjectId, replacementRoomId: roomId,
          replacementDay: (substituteId!=null)?day:null, replacementStart: (substituteId!=null)?startT.text.trim():null, replacementEnd: (substituteId!=null)?endT.text.trim():null,
          replacementDate: start, actorUserId: auth.userId, actorUsername: auth.username,
        );
        ref.invalidate(teacherAbsencesProvider);
        ref.invalidate(timetableEntriesProvider);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Absence enregistrée (remplacement/rattrapage créé si renseigné). Vérifiez les conflits dans l\'emploi du temps.')));
      } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'))); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text('Personnel & RH'), bottom: TabBar(controller: _tab, tabs: const [Tab(text: 'Personnel'), Tab(text: 'Absences & remplacements')])),
      body: TabBarView(controller: _tab, children: [_staffTab(context), _absencesTab(context)]),
    );
  }

  Widget _staffTab(BuildContext context) {
    final list = ref.watch(staffListProvider);
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children:[FilledButton.icon(onPressed: ()=>_addOrEdit(), icon: const Icon(Icons.person_add_alt_1, size:16), label: const Text('Nouveau')), const Spacer()])),
      Expanded(child: list.when(
        data: (rows) => rows.isEmpty ? const Center(child: Text('Aucun membre du personnel.')) : ListView.builder(itemCount: rows.length, itemBuilder: (c,i){ final s=rows[i]; final teacher=(s.functionTitle??'').toLowerCase().contains('enseign'); return ListTile(
          leading: CircleAvatar(child: Text(s.lastName.isNotEmpty?s.lastName[0]:'?')),
          title: Text('${s.lastName} ${s.firstName} (${s.staffNumber})'),
          subtitle: Text('${s.functionTitle ?? '-'} • ${s.departmentOrSubject ?? '-'}'),
          trailing: Wrap(spacing:4, children:[ if(teacher) IconButton(tooltip:'Planning', onPressed: ()=>context.go('/timetable?teacher=${s.id}'), icon: const Icon(Icons.calendar_month_outlined)), IconButton(onPressed: ()=>_addOrEdit(s), icon: const Icon(Icons.edit_outlined)) ]),
        ); }),
        loading: ()=>const Center(child: CircularProgressIndicator()),
        error: (e,_)=>Center(child: Text('Erreur: $e')),
      )),
    ]);
  }

  Widget _absencesTab(BuildContext context) {
    final abs = ref.watch(teacherAbsencesProvider);
    final staff = ref.watch(staffListProvider).valueOrNull ?? const <StaffMember>[];
    String nameOf(String id) {
      for (final s in staff) { if (s.id==id) return '${s.lastName} ${s.firstName}'; }
      return id;
    }
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children:[
        FilledButton.icon(onPressed: _declareAbsence, icon: const Icon(Icons.event_busy_outlined, size:16), label: const Text('Déclarer absence / remplacement')),
        const SizedBox(width: 12),
        const Expanded(child: Text('Gestion des absences enseignants et réaffectation/rattrapage (séance de substitution). Vérifiez les conflits de créneaux/salles dans l\'emploi du temps.', style: TextStyle(fontSize: 12))),
      ])),
      Expanded(child: abs.when(
        data: (rows) => rows.isEmpty ? const Center(child: Text('Aucune absence enregistrée.')) : ListView.builder(itemCount: rows.length, itemBuilder: (c,i){ final a=rows[i]; return ListTile(
          leading: const Icon(Icons.person_off_outlined),
          title: Text('Absent: ${nameOf(a.teacherId)}  •  ${a.status}'),
          subtitle: Text('${a.startDate.day}/${a.startDate.month}/${a.startDate.year} → ${a.endDate.day}/${a.endDate.month}/${a.endDate.year}${a.substituteTeacherId!=null ? '  •  Remplaçant: ${nameOf(a.substituteTeacherId!)}' : ''}${a.reason!=null ? '  •  ${a.reason}' : ''}'),
        ); }),
        loading: ()=>const Center(child: CircularProgressIndicator()),
        error: (e,_)=>Center(child: Text('Erreur: $e')),
      )),
    ]);
  }
}
