import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../../core/security/current_user_scope.dart';
import '../students/students_providers.dart';
import 'discipline_providers.dart';

class DisciplineScreen extends ConsumerStatefulWidget {
  const DisciplineScreen({super.key});
  @override
  ConsumerState<DisciplineScreen> createState() => _DisciplineScreenState();
}

class _DisciplineScreenState extends ConsumerState<DisciplineScreen> {
  String? _selectedIncidentId;

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(currentUserScopeProvider).valueOrNull?.scope ?? 'global';
    if (scope != 'global') {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Accès restreint : le module Discipline est réservé aux utilisateurs de portée globale.')));
    }
    final incidents = ref.watch(incidentsProvider);
    final studentsList = ref.watch(studentsProvider).valueOrNull ?? <Student>[];
    final students = {for (final s in studentsList) s.id: s};
    final visibleIds = students.keys.toSet();
    final fmt = DateFormat('dd/MM/yyyy');
    final statusFilter = ref.watch(disciplineStatusFilterProvider);
    final studentFilter = ref.watch(disciplineStudentFilterProvider);
    return Row(children: [
      Expanded(flex: 3, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 320, child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher (type, description, lieu)...', isDense: true), onChanged: (v)=>ref.read(disciplineSearchProvider.notifier).state=v)),
          SizedBox(width: 170, child: DropdownButtonFormField<String?>(initialValue: statusFilter, isDense: true, decoration: const InputDecoration(labelText: 'Statut'), items: const [DropdownMenuItem(value: null, child: Text('Tous')), DropdownMenuItem(value: 'open', child: Text('Ouvert')), DropdownMenuItem(value: 'closed', child: Text('Clôturé'))], onChanged: (v)=>ref.read(disciplineStatusFilterProvider.notifier).state=v)),
          SizedBox(width: 260, child: DropdownButtonFormField<String?>(initialValue: studentFilter, isDense: true, decoration: const InputDecoration(labelText: 'Élève'), items: [
            const DropdownMenuItem(value: null, child: Text('Tous les élèves')),
            for (final s in studentsList) DropdownMenuItem(value: s.id, child: Text('${s.lastName} ${s.firstName} (${s.matricule})')),
          ], onChanged: (v)=>ref.read(disciplineStudentFilterProvider.notifier).state=v)),
          if (statusFilter != null || studentFilter != null || ref.watch(disciplineSearchProvider).trim().isNotEmpty)
            TextButton.icon(onPressed: () { ref.read(disciplineSearchProvider.notifier).state=''; ref.read(disciplineStatusFilterProvider.notifier).state=null; ref.read(disciplineStudentFilterProvider.notifier).state=null; }, icon: const Icon(Icons.clear), label: const Text('Réinitialiser')),
          FilledButton.icon(onPressed: ()=>_editIncident(context, ref), icon: const Icon(Icons.add), label: const Text('Nouvel incident')),
        ]),
        const SizedBox(height: 12),
        Expanded(child: incidents.when(
          loading: ()=>const Center(child:CircularProgressIndicator()),
          error: (e,_)=>Center(child:Text('Erreur: $e')),
          data: (list){
            final visibleList = list.where((inc) => visibleIds.isEmpty || visibleIds.contains(inc.studentId)).toList();
            if (visibleList.isEmpty) return const Center(child: Text('Aucun incident disciplinaire (ou hors portée/filtres).'));
            return Card(child: ListView.separated(itemCount: visibleList.length, separatorBuilder: (_, __)=>const Divider(height:1), itemBuilder: (context,i){
              final inc = visibleList[i];
              final st = students[inc.studentId];
              return ListTile(
                selected: inc.id == _selectedIncidentId,
                leading: Icon(inc.isConfidential ? Icons.lock_outline : Icons.report_outlined, color: inc.status=='open'?Colors.orange:Colors.grey),
                title: Text('${inc.incidentType} — ${st != null ? '${st.lastName} ${st.firstName}' : inc.studentId}'),
                subtitle: Text('${fmt.format(inc.incidentDate)} • ${inc.status}${inc.location!=null && inc.location!.isNotEmpty ? ' • ${inc.location}' : ''}\n${inc.description}', maxLines: 2, overflow: TextOverflow.ellipsis),
                isThreeLine: true,
                trailing: Wrap(spacing: 4, children: [
                  IconButton(icon: const Icon(Icons.edit_outlined), onPressed: ()=>_editIncident(context, ref, inc)),
                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: ()=>ref.read(disciplineRepositoryProvider).deleteIncident(inc.id)),
                ]),
                onTap: ()=>setState(()=>_selectedIncidentId=inc.id),
              );
            }));
          },
        )),
      ]))),
      const VerticalDivider(width: 1),
      Expanded(flex: 2, child: _selectedIncidentId == null ? const Center(child: Text('Sélectionnez un incident pour gérer les sanctions/suivi.')) : _IncidentActions(incidentId: _selectedIncidentId!)),
    ]);
  }

  static Future<void> _editIncident(BuildContext context, WidgetRef ref, [DisciplinaryIncident? inc]) async {
    final students = ref.read(studentsProvider).valueOrNull ?? [];
    if (students.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun élève disponible.'))); return; }
    String studentId = inc?.studentId ?? students.first.id;
    DateTime date = inc?.incidentDate ?? DateTime.now();
    final type = TextEditingController(text: inc?.incidentType ?? '');
    final desc = TextEditingController(text: inc?.description ?? '');
    final location = TextEditingController(text: inc?.location ?? '');
    final reportedBy = TextEditingController(text: inc?.reportedBy ?? '');
    String status = inc?.status ?? 'open';
    bool confidential = inc?.isConfidential ?? true;
    final fmt = DateFormat('dd/MM/yyyy');
    await showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder:(ctx,setState)=>AlertDialog(
      title: Text(inc==null?'Nouvel incident':'Modifier l\'incident'),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: studentId, decoration: const InputDecoration(labelText: 'Élève'), items: [for (final s in students) DropdownMenuItem(value: s.id, child: Text('${s.lastName} ${s.firstName} (${s.matricule})'))], onChanged: (v)=>setState(()=>studentId=v??studentId)),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () async { final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100)); if (d!=null) setState(()=>date=d); }, child: Text('Date: ${fmt.format(date)}')),
        const SizedBox(height: 8),
        TextField(controller: type, decoration: const InputDecoration(labelText: 'Type d\'incident (ex: retard répété, indiscipline, violence...)')),
        const SizedBox(height: 8),
        TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description'), maxLines: 3),
        const SizedBox(height: 8),
        TextField(controller: location, decoration: const InputDecoration(labelText: 'Lieu')),
        const SizedBox(height: 8),
        TextField(controller: reportedBy, decoration: const InputDecoration(labelText: 'Signalé par')),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(initialValue: status, decoration: const InputDecoration(labelText: 'Statut'), items: const [DropdownMenuItem(value: 'open', child: Text('Ouvert')), DropdownMenuItem(value: 'closed', child: Text('Clôturé'))], onChanged: (v)=>setState(()=>status=v??'open')),
        CheckboxListTile(contentPadding: EdgeInsets.zero, value: confidential, onChanged: (v)=>setState(()=>confidential=v??true), title: const Text('Dossier confidentiel'), controlAffinity: ListTileControlAffinity.leading),
      ]))),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: () async {
        if (type.text.trim().isEmpty || desc.text.trim().isEmpty) return;
        await ref.read(disciplineRepositoryProvider).upsertIncident(id: inc?.id, studentId: studentId, incidentDate: date, incidentType: type.text.trim(), description: desc.text.trim(), location: location.text.trim().isEmpty?null:location.text.trim(), reportedBy: reportedBy.text.trim().isEmpty?null:reportedBy.text.trim(), status: status, isConfidential: confidential);
        if (ctx.mounted) Navigator.pop(ctx);
      }, child: const Text('Enregistrer'))],
    )));
  }
}

class _IncidentActions extends ConsumerWidget {
  final String incidentId;
  const _IncidentActions({required this.incidentId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(actionsForIncidentProvider(incidentId));
    final fmt = DateFormat('dd/MM/yyyy');
    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Text('Sanctions / décisions / suivi', style: Theme.of(context).textTheme.titleMedium), const Spacer(), FilledButton.icon(onPressed: ()=>_editAction(context, ref, incidentId), icon: const Icon(Icons.add), label: const Text('Ajouter'))]),
      const SizedBox(height: 8),
      Expanded(child: actions.when(
        loading: ()=>const Center(child:CircularProgressIndicator()),
        error: (e,_)=>Center(child:Text('Erreur: $e')),
        data: (list){
          if (list.isEmpty) return const Center(child: Text('Aucune action/sanction enregistrée (convocation, retenue, exclusion temporaire, etc.).'));
          return ListView.builder(itemCount: list.length, itemBuilder: (context,i){
            final a = list[i];
            return Card(child: ListTile(
              title: Text('${a.actionType} • ${a.executionStatus}'),
              subtitle: Text([
                if (a.decisionDate!=null) 'Décision: ${fmt.format(a.decisionDate!)}',
                if (a.startDate!=null || a.endDate!=null) 'Période: ${a.startDate!=null?fmt.format(a.startDate!):'?'} → ${a.endDate!=null?fmt.format(a.endDate!):'?'}',
                if (a.notes!=null && a.notes!.isNotEmpty) 'Notes: ${a.notes}',
                if (a.followUpNotes!=null && a.followUpNotes!.isNotEmpty) 'Suivi: ${a.followUpNotes}',
              ].join('\n')),
              isThreeLine: true,
              trailing: Wrap(spacing: 4, children: [
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: ()=>_editAction(context, ref, incidentId, a)),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: ()=>ref.read(disciplineRepositoryProvider).deleteAction(a.id)),
              ]),
            ));
          });
        },
      )),
    ]));
  }

  static Future<void> _editAction(BuildContext context, WidgetRef ref, String incidentId, [DisciplinaryAction? a]) async {
    final type = TextEditingController(text: a?.actionType ?? 'convocation');
    final notes = TextEditingController(text: a?.notes ?? '');
    final follow = TextEditingController(text: a?.followUpNotes ?? '');
    DateTime? decision = a?.decisionDate;
    DateTime? start = a?.startDate;
    DateTime? end = a?.endDate;
    String exec = a?.executionStatus ?? 'planned';
    final fmt = DateFormat('dd/MM/yyyy');
    await showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder:(ctx,setState)=>AlertDialog(
      title: Text(a==null?'Nouvelle action/sanction':'Modifier l\'action'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: type.text.isEmpty?'convocation':type.text, decoration: const InputDecoration(labelText: 'Type'), items: const [
          DropdownMenuItem(value: 'convocation', child: Text('Convocation')),
          DropdownMenuItem(value: 'avertissement', child: Text('Avertissement')),
          DropdownMenuItem(value: 'retenue', child: Text('Retenue')),
          DropdownMenuItem(value: 'exclusion_temporaire', child: Text('Exclusion temporaire')),
          DropdownMenuItem(value: 'blame', child: Text('Blâme')),
          DropdownMenuItem(value: 'autre', child: Text('Autre')),
        ], onChanged: (v){ if(v!=null) setState(()=>type.text=v); }),
        const SizedBox(height: 8),
        Row(children:[
          Expanded(child: OutlinedButton(onPressed: () async { final d=await showDatePicker(context: ctx, initialDate: decision ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100)); if(d!=null) setState(()=>decision=d); }, child: Text(decision==null?'Date décision':'Décision: ${fmt.format(decision!)}'))),
        ]),
        const SizedBox(height: 8),
        Row(children:[
          Expanded(child: OutlinedButton(onPressed: () async { final d=await showDatePicker(context: ctx, initialDate: start ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100)); if(d!=null) setState(()=>start=d); }, child: Text(start==null?'Début':'Début: ${fmt.format(start!)}'))),
          const SizedBox(width:8),
          Expanded(child: OutlinedButton(onPressed: () async { final d=await showDatePicker(context: ctx, initialDate: end ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100)); if(d!=null) setState(()=>end=d); }, child: Text(end==null?'Fin':'Fin: ${fmt.format(end!)}'))),
        ]),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(initialValue: exec, decoration: const InputDecoration(labelText: 'Exécution'), items: const [
          DropdownMenuItem(value: 'planned', child: Text('Planifiée')),
          DropdownMenuItem(value: 'in_progress', child: Text('En cours')),
          DropdownMenuItem(value: 'done', child: Text('Exécutée')),
          DropdownMenuItem(value: 'cancelled', child: Text('Annulée')),
        ], onChanged: (v)=>setState(()=>exec=v??'planned')),
        const SizedBox(height: 8),
        TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes / décision'), maxLines: 2),
        TextField(controller: follow, decoration: const InputDecoration(labelText: 'Suivi d\'exécution'), maxLines: 2),
      ]))),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: () async {
        await ref.read(disciplineRepositoryProvider).upsertAction(id: a?.id, incidentId: incidentId, actionType: type.text.trim().isEmpty?'convocation':type.text.trim(), decisionDate: decision, startDate: start, endDate: end, notes: notes.text.trim().isEmpty?null:notes.text.trim(), executionStatus: exec, followUpNotes: follow.text.trim().isEmpty?null:follow.text.trim());
        if (ctx.mounted) Navigator.pop(ctx);
      }, child: const Text('Enregistrer'))],
    )));
  }
}
