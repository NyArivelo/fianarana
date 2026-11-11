import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../academics/academics_providers.dart';
import '../admin/admin_providers.dart';
import '../settings/settings_providers.dart';
import 'staff_providers.dart';

class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});
  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffListProvider);
    return Row(children: [
      Expanded(flex: 3, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher (nom, prénom, spécialité, email)...'), onChanged: (v)=>ref.read(staffSearchProvider.notifier).state=v)),
          const SizedBox(width: 8),
          SizedBox(width: 180, child: DropdownButtonFormField<String?>(initialValue: ref.watch(staffTypeFilterProvider), isDense: true, decoration: const InputDecoration(labelText: 'Type'), items: const [
            DropdownMenuItem(value: null, child: Text('Tous')),
            DropdownMenuItem(value: 'teacher', child: Text('Enseignant')),
            DropdownMenuItem(value: 'direction', child: Text('Direction')),
            DropdownMenuItem(value: 'admin_staff', child: Text('Administratif')),
            DropdownMenuItem(value: 'other', child: Text('Autre')),
          ], onChanged: (v)=>ref.read(staffTypeFilterProvider.notifier).state=v)),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: ()=>_editStaff(context, ref), icon: const Icon(Icons.add), label: const Text('Nouveau')),
        ]),
        const SizedBox(height: 12),
        Expanded(child: staffAsync.when(
          loading: ()=>const Center(child:CircularProgressIndicator()),
          error: (e,_)=>Center(child:Text('Erreur: $e')),
          data: (list){
            if (list.isEmpty) return const Center(child: Text('Aucun membre du personnel.'));
            return Card(child: ListView.separated(itemCount: list.length, separatorBuilder: (_, __)=>const Divider(height:1), itemBuilder: (context,i){
              final s = list[i];
              final sel = s.id == _selectedId;
              return ListTile(
                selected: sel,
                leading: CircleAvatar(child: Text(s.firstName.isNotEmpty ? s.firstName[0] : '?')),
                title: Text('${s.lastName} ${s.firstName}'),
                subtitle: Text('${_typeLabel(s.staffType)}${s.specialty != null && s.specialty!.isNotEmpty ? ' • ${s.specialty}' : ''}${s.userId != null ? ' • compte lié' : ''}'),
                trailing: Wrap(spacing: 4, children: [
                  IconButton(icon: const Icon(Icons.edit_outlined), onPressed: ()=>_editStaff(context, ref, s)),
                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { await ref.read(staffRepositoryProvider).deleteStaff(s.id); if (_selectedId==s.id) setState(()=>_selectedId=null); }),
                ]),
                onTap: ()=>setState(()=>_selectedId=s.id),
              );
            }));
          },
        )),
      ]))),
      const VerticalDivider(width: 1),
      Expanded(flex: 2, child: _selectedId == null ? const Center(child: Text('Sélectionnez un membre pour voir le détail et les affectations.')) : _StaffDetail(staffId: _selectedId!)),
    ]);
  }

  static String _typeLabel(String t) => const {'teacher':'Enseignant','direction':'Direction','admin_staff':'Administratif','other':'Autre'}[t] ?? t;

  static Future<void> _editStaff(BuildContext context, WidgetRef ref, [StaffMember? s]) async {
    final first = TextEditingController(text: s?.firstName ?? '');
    final last = TextEditingController(text: s?.lastName ?? '');
    final specialty = TextEditingController(text: s?.specialty ?? '');
    final phone = TextEditingController(text: s?.phone ?? '');
    final email = TextEditingController(text: s?.email ?? '');
    final contractType = TextEditingController(text: s?.contractType ?? '');
    final notes = TextEditingController(text: s?.notes ?? '');
    final docs = TextEditingController(text: s?.documentsNote ?? '');
    String type = s?.staffType ?? 'teacher';
    String? userId = s?.userId;
    DateTime? start = s?.contractStart;
    DateTime? end = s?.contractEnd;
    final users = ref.read(adminUsersProvider).valueOrNull ?? [];
    final fmt = DateFormat('dd/MM/yyyy');
    await showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder:(ctx,setState)=>AlertDialog(
      title: Text(s==null ? 'Nouveau membre du personnel' : 'Modifier le membre'),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [Expanded(child: TextField(controller: last, decoration: const InputDecoration(labelText:'Nom *'))), const SizedBox(width:8), Expanded(child: TextField(controller: first, decoration: const InputDecoration(labelText:'Prénom *')))]),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'Type / fonction'), items: const [
          DropdownMenuItem(value: 'teacher', child: Text('Enseignant')),
          DropdownMenuItem(value: 'direction', child: Text('Direction')),
          DropdownMenuItem(value: 'admin_staff', child: Text('Personnel administratif')),
          DropdownMenuItem(value: 'other', child: Text('Autre')),
        ], onChanged: (v)=>setState(()=>type=v??'teacher')),
        const SizedBox(height: 8),
        TextField(controller: specialty, decoration: const InputDecoration(labelText: 'Spécialité(s)')),
        const SizedBox(height: 8),
        Row(children:[Expanded(child: TextField(controller: phone, decoration: const InputDecoration(labelText:'Téléphone'))), const SizedBox(width:8), Expanded(child: TextField(controller: email, decoration: const InputDecoration(labelText:'Email')))]),
        const SizedBox(height: 8),
        TextField(controller: contractType, decoration: const InputDecoration(labelText: 'Type de contrat / documents contractuels (réf.)')),
        const SizedBox(height: 8),
        Row(children:[
          Expanded(child: OutlinedButton(onPressed: () async { final d=await showDatePicker(context: ctx, initialDate: start ?? DateTime.now(), firstDate: DateTime(1990), lastDate: DateTime(2100)); if(d!=null) setState(()=>start=d); }, child: Text(start==null?'Début contrat': 'Début: ${fmt.format(start!)}'))),
          const SizedBox(width:8),
          Expanded(child: OutlinedButton(onPressed: () async { final d=await showDatePicker(context: ctx, initialDate: end ?? DateTime.now(), firstDate: DateTime(1990), lastDate: DateTime(2100)); if(d!=null) setState(()=>end=d); }, child: Text(end==null?'Fin contrat': 'Fin: ${fmt.format(end!)}'))),
        ]),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(initialValue: userId, decoration: const InputDecoration(labelText: 'Compte utilisateur lié (évite doublon)'), items: [const DropdownMenuItem(value: null, child: Text('(Aucun)')), for (final u in users) DropdownMenuItem(value: u.id, child: Text('${u.displayName} (${u.username})'))], onChanged: (v)=>setState(()=>userId=v)),
        const SizedBox(height: 8),
        TextField(controller: notes, decoration: const InputDecoration(labelText:'Notes RH'), maxLines: 2),
        TextField(controller: docs, decoration: const InputDecoration(labelText:'Documents contractuels (références/chemins)'), maxLines: 2),
      ]))),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: () async {
        if (first.text.trim().isEmpty || last.text.trim().isEmpty) return;
        await ref.read(staffRepositoryProvider).upsertStaff(id: s?.id, firstName: first.text.trim(), lastName: last.text.trim(), staffType: type, specialty: specialty.text.trim().isEmpty?null:specialty.text.trim(), phone: phone.text.trim().isEmpty?null:phone.text.trim(), email: email.text.trim().isEmpty?null:email.text.trim(), contractType: contractType.text.trim().isEmpty?null:contractType.text.trim(), contractStart: start, contractEnd: end, userId: userId, notes: notes.text.trim().isEmpty?null:notes.text.trim(), documentsNote: docs.text.trim().isEmpty?null:docs.text.trim());
        if (ctx.mounted) Navigator.pop(ctx);
      }, child: const Text('Enregistrer'))],
    )));
  }
}

class _StaffDetail extends ConsumerWidget {
  final String staffId;
  const _StaffDetail({required this.staffId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffList = ref.watch(staffListProvider).valueOrNull ?? [];
    final staff = staffList.firstWhereOrNull((s) => s.id == staffId);
    if (staff == null) return const Center(child: Text('Membre introuvable (ou filtré).'));
    final users = ref.watch(adminUsersProvider).valueOrNull ?? [];
    final linked = users.firstWhereOrNull((u)=>u.id==staff.userId);
    final fmt = DateFormat('dd/MM/yyyy');
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('${staff.lastName} ${staff.firstName}', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text('${_StaffScreenState._typeLabel(staff.staffType)}${staff.specialty!=null && staff.specialty!.isNotEmpty ? ' • ${staff.specialty}' : ''}'),
      const SizedBox(height: 8),
      if (staff.phone!=null && staff.phone!.isNotEmpty) Text('Téléphone: ${staff.phone}'),
      if (staff.email!=null && staff.email!.isNotEmpty) Text('Email: ${staff.email}'),
      if (staff.contractType!=null && staff.contractType!.isNotEmpty) Text('Contrat: ${staff.contractType}'),
      if (staff.contractStart!=null || staff.contractEnd!=null) Text('Période: ${staff.contractStart!=null?fmt.format(staff.contractStart!):'?'} → ${staff.contractEnd!=null?fmt.format(staff.contractEnd!):'?'}'),
      Text('Compte lié: ${linked != null ? '${linked.displayName} (${linked.username})' : 'aucun'}'),
      if (staff.notes!=null && staff.notes!.isNotEmpty) ...[const SizedBox(height:8), Text('Notes: ${staff.notes}')],
      if (staff.documentsNote!=null && staff.documentsNote!.isNotEmpty) ...[const SizedBox(height:4), Text('Documents: ${staff.documentsNote}')],
      const Divider(height: 24),
      Text('Affectations pédagogiques', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      if (staff.userId == null)
        const Text('Liez un compte utilisateur à ce membre pour gérer ses affectations (classes/matières/année) utilisées par la portée restreinte.')
      else
        _AssignmentsSection(userId: staff.userId!),
    ]);
  }
}

class _AssignmentsSection extends ConsumerWidget {
  final String userId;
  const _AssignmentsSection({required this.userId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(staffRepositoryProvider).db;
    final assignments = ref.watch(StreamProvider<List<TeacherAssignment>>((ref)=> (db.select(db.teacherAssignments)..where((t)=>t.userId.equals(userId))..where((t)=>t.isDeleted.equals(false))).watch()));
    final years = ref.watch(academicYearsProvider).valueOrNull ?? [];
    final yearId = years.where((y)=>y.isCurrent).firstOrNull?.id ?? (years.isNotEmpty?years.first.id:null);
    final classes = ref.watch(classesProvider(yearId)).valueOrNull ?? [];
    final subjects = ref.watch(subjectsProvider).valueOrNull ?? [];
    final classNames = {for (final c in classes) c.id: c.name};
    final subjectNames = {for (final s in subjects) s.id: s.name};
    return assignments.when(
      loading: ()=>const LinearProgressIndicator(),
      error: (e,_)=>Text('Erreur: $e'),
      data: (list)=> Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FilledButton.tonalIcon(onPressed: ()=>_add(context, ref, yearId), icon: const Icon(Icons.add), label: const Text('Ajouter affectation')),
        const SizedBox(height: 8),
        if (list.isEmpty) const Text('Aucune affectation.') else ...[
          for (final a in list) ListTile(dense: true, title: Text(classNames[a.classId] ?? a.classId), subtitle: Text([if(a.subjectId!=null) subjectNames[a.subjectId] ?? a.subjectId, if(a.academicYearId!=null) 'Année: ${a.academicYearId}'].whereType<String>().join(' • ')), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: ()=>ref.read(staffRepositoryProvider).removeAssignment(a.id))),
        ],
      ]),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref, String? yearId) async {
    final classes = ref.read(classesProvider(yearId)).valueOrNull ?? [];
    final subjects = ref.read(subjectsProvider).valueOrNull ?? [];
    if (classes.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucune classe disponible.'))); return; }
    String classId = classes.first.id;
    String? subjectId;
    await showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder:(ctx,setState)=>AlertDialog(
      title: const Text('Nouvelle affectation pédagogique'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: classId, items: [for (final c in classes) DropdownMenuItem(value: c.id, child: Text(c.name))], onChanged: (v)=>setState(()=>classId=v??classId), decoration: const InputDecoration(labelText: 'Classe')),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(initialValue: subjectId, items: [const DropdownMenuItem(value: null, child: Text('(Matière - optionnel)')), for (final s in subjects) DropdownMenuItem(value: s.id, child: Text(s.name))], onChanged: (v)=>setState(()=>subjectId=v), decoration: const InputDecoration(labelText: 'Matière')),
      ])),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: () async { await ref.read(staffRepositoryProvider).addAssignment(userId: userId, classId: classId, subjectId: subjectId, academicYearId: yearId); if (ctx.mounted) Navigator.pop(ctx); }, child: const Text('Ajouter'))],
    )));
  }
}
