import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/database_provider.dart';

final _facilitiesProvider = FutureProvider((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.facilities)..where((t)=>t.isDeleted.equals(false))).get();
});

class FacilitiesScreen extends ConsumerWidget {
  const FacilitiesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(_facilitiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Locaux & équipements')),
      body: Padding(padding: const EdgeInsets.all(16), child: list.when(
        data: (rows)=>rows.isEmpty?const Center(child: Text('Aucun local/équipement (données de test: biblioth_que_locaux).')):Card(child: SingleChildScrollView(child: DataTable(columns: const [
          DataColumn(label: Text('Domaine')), DataColumn(label: Text('Code')), DataColumn(label: Text('Nom')), DataColumn(label: Text('Catégorie')), DataColumn(label: Text('Capacité')), DataColumn(label: Text('Statut')),
        ], rows: rows.map((f)=>DataRow(cells:[DataCell(Text(f.domain)), DataCell(Text(f.code ?? '-')), DataCell(Text(f.name)), DataCell(Text(f.category ?? '-')), DataCell(Text('${f.capacity ?? '-'}')), DataCell(Text(f.status))])).toList()))),
        loading: ()=>const Center(child: CircularProgressIndicator()),
        error: (e,_)=>Center(child: Text('$e')),
      )),
    );
  }
}
