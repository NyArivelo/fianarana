import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/staff/data/staff_repository.dart';

final _staffRepoProvider = Provider((ref) => StaffRepository(ref.watch(appDatabaseProvider)));
final _staffListProvider = FutureProvider.family((ref, String? q) {
  final uid = ref.watch(authControllerProvider).userId;
  return ref.watch(_staffRepoProvider).list(actorUserId: uid, query: q);
});

class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});
  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  String? _q;

  Future<void> _addOrEdit([dynamic s]) async {
    final auth = ref.read(authControllerProvider);
    final num = TextEditingController(text: s?.staffNumber ?? '');
    final ln = TextEditingController(text: s?.lastName ?? '');
    final fn = TextEditingController(text: s?.firstName ?? '');
    final fct = TextEditingController(text: s?.functionTitle ?? '');
    final dep = TextEditingController(text: s?.departmentOrSubject ?? '');
    final phone = TextEditingController(text: s?.phone ?? '');
    final ok = await showDialog<bool>(context: context, builder: (ctx)=>AlertDialog(
      title: Text(s==null?'Nouveau personnel':'Modifier personnel'),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: num, decoration: const InputDecoration(labelText: 'Matricule RH')),
        TextField(controller: ln, decoration: const InputDecoration(labelText: 'Nom')),
        TextField(controller: fn, decoration: const InputDecoration(labelText: 'Prénom')),
        TextField(controller: fct, decoration: const InputDecoration(labelText: 'Fonction')),
        TextField(controller: dep, decoration: const InputDecoration(labelText: 'Matière/Service')),
        TextField(controller: phone, decoration: const InputDecoration(labelText: 'Téléphone')),
      ]))),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('Annuler')), FilledButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('Enregistrer'))],
    ));
    if (ok == true) {
      try {
        await ref.read(_staffRepoProvider).upsert(id: s?.id, staffNumber: num.text.trim(), lastName: ln.text.trim(), firstName: fn.text.trim(), functionTitle: fct.text.trim(), department: dep.text.trim(), phone: phone.text.trim(), actorUserId: auth.userId, actorUsername: auth.username);
        ref.invalidate(_staffListProvider);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_staffListProvider(_q));
    return Scaffold(
      appBar: AppBar(title: const Text('Personnel & enseignants'), actions: [FilledButton.icon(onPressed: ()=>_addOrEdit(), icon: const Icon(Icons.person_add), label: const Text('Nouveau')), const SizedBox(width: 8)]),
      body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher personnel...'), onSubmitted: (v)=>setState(()=>_q=v.trim().isEmpty?null:v)),
        const SizedBox(height: 12),
        Expanded(child: list.when(
          data: (rows)=>Card(child: rows.isEmpty?const Center(child: Text('Aucun personnel (données de test importables).')):SingleChildScrollView(child: DataTable(columns: const [
            DataColumn(label: Text('Matricule')), DataColumn(label: Text('Nom')), DataColumn(label: Text('Prénom')), DataColumn(label: Text('Fonction')), DataColumn(label: Text('Matière/Service')), DataColumn(label: Text('Téléphone')), DataColumn(label: Text('Statut')), DataColumn(label: Text('Actions')),
          ], rows: rows.map((s)=>DataRow(cells:[
            DataCell(Text(s.staffNumber)), DataCell(Text(s.lastName)), DataCell(Text(s.firstName)), DataCell(Text(s.functionTitle ?? '-')), DataCell(Text(s.departmentOrSubject ?? '-')), DataCell(Text(s.phone ?? '-')), DataCell(Text(s.status)),
            DataCell(IconButton(icon: const Icon(Icons.edit), onPressed: ()=>_addOrEdit(s))),
          ])).toList()))),
          loading: ()=>const Center(child: CircularProgressIndicator()),
          error: (e,_)=>Center(child: Text('Erreur: $e')),
        )),
      ])),
    );
  }
}
