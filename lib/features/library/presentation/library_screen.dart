import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/database_provider.dart';

final _libraryItemsProvider = FutureProvider((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.libraryItems)..where((t)=>t.isDeleted.equals(false))).get();
});
final _libraryLoansProvider = FutureProvider((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.libraryLoans)..where((t)=>t.isDeleted.equals(false))).get();
});

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(_libraryItemsProvider);
    final loans = ref.watch(_libraryLoansProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Bibliothèque'), bottom: const TabBar(tabs: [Tab(text: 'Catalogue'), Tab(text: 'Prêts')])),
        body: TabBarView(children: [
          items.when(
            data: (rows)=>rows.isEmpty?const Center(child: Text('Catalogue vide (données de test: biblioth_que_locaux).')):SingleChildScrollView(child: DataTable(columns: const [
              DataColumn(label: Text('Code/ISBN')), DataColumn(label: Text('Titre')), DataColumn(label: Text('Auteur/Catégorie')), DataColumn(label: Text('Exemplaire')), DataColumn(label: Text('Disponibilité')),
            ], rows: rows.map((i)=>DataRow(cells:[DataCell(Text(i.codeOrIsbn ?? '-')), DataCell(Text(i.title)), DataCell(Text(i.authorOrCategory ?? '-')), DataCell(Text(i.copyCode ?? '-')), DataCell(Text(i.availability))])).toList())),
            loading: ()=>const Center(child: CircularProgressIndicator()), error: (e,_)=>Center(child: Text('$e')),
          ),
          loans.when(
            data: (rows)=>rows.isEmpty?const Center(child: Text('Aucun prêt.')):SingleChildScrollView(child: DataTable(columns: const [
              DataColumn(label: Text('Ouvrage')), DataColumn(label: Text('Emprunteur')), DataColumn(label: Text('Début')), DataColumn(label: Text('Échéance')), DataColumn(label: Text('Statut')),
            ], rows: rows.map((l)=>DataRow(cells:[DataCell(Text(l.itemId)), DataCell(Text(l.borrowerStudentId ?? l.borrowerRef ?? '-')), DataCell(Text('${l.startDate.year}-${l.startDate.month.toString().padLeft(2,'0')}-${l.startDate.day.toString().padLeft(2,'0')}')), DataCell(Text(l.dueDate==null?'-':'${l.dueDate!.year}-${l.dueDate!.month.toString().padLeft(2,'0')}-${l.dueDate!.day.toString().padLeft(2,'0')}')), DataCell(Text(l.status))])).toList())),
            loading: ()=>const Center(child: CircularProgressIndicator()), error: (e,_)=>Center(child: Text('$e')),
          ),
        ]),
      ),
    );
  }
}
