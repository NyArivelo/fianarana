import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../students/students_providers.dart';
import 'library_providers.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(length: 2, child: Column(children: const [
      TabBar(tabs: [Tab(text: 'Catalogue & Exemplaires'), Tab(text: 'Prêts / Retours')]),
      Expanded(child: TabBarView(children: [_CatalogTab(), _LoansTab()])),
    ]));
  }
}

class _CatalogTab extends ConsumerStatefulWidget {
  const _CatalogTab();
  @override
  ConsumerState<_CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends ConsumerState<_CatalogTab> {
  String? _selectedItemId;
  @override
  Widget build(BuildContext context) {
    final items = ref.watch(libraryItemsProvider);
    return Row(children: [
      Expanded(flex: 3, child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        Row(children: [
          Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher (titre, auteur, ISBN, catégorie)...'), onChanged: (v)=>ref.read(librarySearchProvider.notifier).state=v)),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: ()=>_editItem(context, ref), icon: const Icon(Icons.add), label: const Text('Nouvel ouvrage')),
        ]),
        const SizedBox(height: 12),
        Expanded(child: items.when(
          loading: ()=>const Center(child:CircularProgressIndicator()),
          error: (e,_)=>Center(child:Text('Erreur: $e')),
          data: (list){
            if (list.isEmpty) return const Center(child: Text('Aucun ouvrage dans le catalogue.'));
            return Card(child: ListView.separated(itemCount: list.length, separatorBuilder: (_, __)=>const Divider(height:1), itemBuilder: (context,i){
              final it = list[i];
              return ListTile(
                selected: it.id == _selectedItemId,
                title: Text(it.title),
                subtitle: Text([it.author, it.isbn, it.category].where((e)=>e!=null && e.isNotEmpty).join(' • ')),
                trailing: Wrap(spacing: 4, children: [
                  IconButton(icon: const Icon(Icons.edit_outlined), onPressed: ()=>_editItem(context, ref, it)),
                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: ()=>ref.read(libraryRepositoryProvider).deleteItem(it.id)),
                ]),
                onTap: ()=>setState(()=>_selectedItemId=it.id),
              );
            }));
          },
        )),
      ]))),
      const VerticalDivider(width: 1),
      Expanded(flex: 2, child: _selectedItemId == null ? const Center(child: Text('Sélectionnez un ouvrage pour gérer ses exemplaires.')) : _CopiesPanel(itemId: _selectedItemId!)),
    ]);
  }

  static Future<void> _editItem(BuildContext context, WidgetRef ref, [LibraryItem? item]) async {
    final title = TextEditingController(text: item?.title ?? '');
    final author = TextEditingController(text: item?.author ?? '');
    final isbn = TextEditingController(text: item?.isbn ?? '');
    final category = TextEditingController(text: item?.category ?? '');
    final publisher = TextEditingController(text: item?.publisher ?? '');
    final year = TextEditingController(text: item?.publicationYear ?? '');
    final desc = TextEditingController(text: item?.description ?? '');
    await showDialog(context: context, builder: (ctx)=>AlertDialog(
      title: Text(item==null?'Nouvel ouvrage':'Modifier l\'ouvrage'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Titre *')),
        TextField(controller: author, decoration: const InputDecoration(labelText: 'Auteur')),
        TextField(controller: isbn, decoration: const InputDecoration(labelText: 'ISBN')),
        TextField(controller: category, decoration: const InputDecoration(labelText: 'Catégorie')),
        TextField(controller: publisher, decoration: const InputDecoration(labelText: 'Éditeur')),
        TextField(controller: year, decoration: const InputDecoration(labelText: 'Année de publication')),
        TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
      ]))),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: () async {
        if (title.text.trim().isEmpty) return;
        await ref.read(libraryRepositoryProvider).upsertItem(id: item?.id, title: title.text.trim(), author: author.text.trim().isEmpty?null:author.text.trim(), isbn: isbn.text.trim().isEmpty?null:isbn.text.trim(), category: category.text.trim().isEmpty?null:category.text.trim(), publisher: publisher.text.trim().isEmpty?null:publisher.text.trim(), publicationYear: year.text.trim().isEmpty?null:year.text.trim(), description: desc.text.trim().isEmpty?null:desc.text.trim());
        if (ctx.mounted) Navigator.pop(ctx);
      }, child: const Text('Enregistrer'))],
    ));
  }
}

class _CopiesPanel extends ConsumerWidget {
  final String itemId;
  const _CopiesPanel({required this.itemId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copies = ref.watch(copiesForItemProvider(itemId));
    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Text('Exemplaires physiques', style: Theme.of(context).textTheme.titleMedium), const Spacer(), FilledButton.icon(onPressed: ()=>_editCopy(context, ref, itemId), icon: const Icon(Icons.add), label: const Text('Ajouter exemplaire'))]),
      const SizedBox(height: 8),
      Expanded(child: copies.when(
        loading: ()=>const Center(child:CircularProgressIndicator()),
        error: (e,_)=>Center(child:Text('Erreur: $e')),
        data: (list){
          if (list.isEmpty) return const Center(child: Text('Aucun exemplaire. Ajoutez des exemplaires pour gérer les prêts.'));
          return ListView.builder(itemCount: list.length, itemBuilder: (context,i){
            final c = list[i];
            return ListTile(
              title: Text('Code: ${c.copyCode}'),
              subtitle: Text('Statut: ${c.status}${c.locationNote!=null && c.locationNote!.isNotEmpty ? ' • ${c.locationNote}' : ''}'),
              trailing: Wrap(spacing: 4, children: [
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: ()=>_editCopy(context, ref, itemId, c)),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: ()=>ref.read(libraryRepositoryProvider).deleteCopy(c.id)),
              ]),
            );
          });
        },
      )),
    ]));
  }

  static Future<void> _editCopy(BuildContext context, WidgetRef ref, String itemId, [LibraryCopy? c]) async {
    final code = TextEditingController(text: c?.copyCode ?? '');
    final loc = TextEditingController(text: c?.locationNote ?? '');
    String status = c?.status ?? 'available';
    await showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder:(ctx,setState)=>AlertDialog(
      title: Text(c==null?'Nouvel exemplaire':'Modifier l\'exemplaire'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: code, decoration: const InputDecoration(labelText: 'Code exemplaire / code-barres *')),
        DropdownButtonFormField<String>(initialValue: status, decoration: const InputDecoration(labelText: 'Statut'), items: const [DropdownMenuItem(value:'available', child: Text('Disponible')), DropdownMenuItem(value:'borrowed', child: Text('Emprunté')), DropdownMenuItem(value:'lost', child: Text('Perdu')), DropdownMenuItem(value:'damaged', child: Text('Endommagé'))], onChanged: (v)=>setState(()=>status=v??'available')),
        TextField(controller: loc, decoration: const InputDecoration(labelText: 'Emplacement / note')),
      ])),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: () async { if (code.text.trim().isEmpty) return; await ref.read(libraryRepositoryProvider).upsertCopy(id: c?.id, itemId: itemId, copyCode: code.text.trim(), status: status, locationNote: loc.text.trim().isEmpty?null:loc.text.trim()); if (ctx.mounted) Navigator.pop(ctx); }, child: const Text('Enregistrer'))],
    )));
  }
}

class _LoansTab extends ConsumerWidget {
  const _LoansTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loanDetailsProvider);
    final students = {for (final s in (ref.watch(studentsProvider).valueOrNull ?? <Student>[])) s.id: s};
    final fmt = DateFormat('dd/MM/yyyy');
    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Prêts, retours et retards', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        FilledButton.icon(onPressed: ()=>_borrowDialog(context, ref), icon: const Icon(Icons.add), label: const Text('Nouveau prêt')),
      ]),
      const SizedBox(height: 8),
      const Text('Les prêts en retard sont marqués automatiquement. Le quitus bibliothèque d\'un élève est bloqué tant qu\'un prêt est actif/en retard.'),
      const SizedBox(height: 8),
      Expanded(child: loans.when(
        loading: ()=>const Center(child:CircularProgressIndicator()),
        error: (e,_)=>Center(child:Text('Erreur: $e')),
        data: (list){
          if (list.isEmpty) return const Center(child: Text('Aucun prêt enregistré.'));
          return ListView.builder(itemCount: list.length, itemBuilder: (context,i){
            final d = list[i];
            final l = d.loan;
            final st = students[l.studentId];
            final isActive = l.status == 'active' || l.status == 'overdue';
            return Card(child: ListTile(
              leading: Icon(isActive ? (l.status=='overdue'?Icons.warning:Icons.menu_book) : Icons.assignment_turned_in, color: l.status=='overdue'?Colors.red:(isActive?Colors.orange:Colors.green)),
              title: Text('${st!=null?'${st.lastName} ${st.firstName}':l.studentId} — ${d.itemTitle}'),
              subtitle: Text('Exemplaire: ${d.copyCode} • Emprunt: ${fmt.format(l.loanDate)} • Échéance: ${fmt.format(l.dueDate)} • Statut: ${l.status}${l.returnDate!=null ? ' • Retour: ${fmt.format(l.returnDate!)}' : ''}'),
              isThreeLine: true,
              trailing: isActive ? FilledButton.tonal(onPressed: ()=>_returnDialog(context, ref, l), child: const Text('Retour')) : null,
            ));
          });
        },
      )),
    ]));
  }

  static Future<void> _borrowDialog(BuildContext context, WidgetRef ref) async {
    final students = ref.read(studentsProvider).valueOrNull ?? [];
    final items = ref.read(libraryItemsProvider).valueOrNull ?? [];
    if (students.isEmpty || items.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajoutez au moins un élève et un ouvrage/exemplaire.'))); return; }
    String studentId = students.first.id;
    String? itemId = items.first.id;
    String? copyId;
    DateTime due = DateTime.now().add(const Duration(days: 14));
    final fmt = DateFormat('dd/MM/yyyy');
    await showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder:(ctx,setState){
      final copies = itemId == null ? <LibraryCopy>[] : (ref.watch(copiesForItemProvider(itemId!)).valueOrNull ?? []).where((c)=>c.status=='available').toList();
      copyId = (copyId != null && copies.any((c)=>c.id==copyId)) ? copyId : (copies.isNotEmpty ? copies.first.id : null);
      return AlertDialog(
        title: const Text('Nouveau prêt'),
        content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(initialValue: studentId, decoration: const InputDecoration(labelText: 'Élève'), items: [for (final s in students) DropdownMenuItem(value: s.id, child: Text('${s.lastName} ${s.firstName} (${s.matricule})'))], onChanged: (v)=>setState(()=>studentId=v??studentId)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(initialValue: itemId, decoration: const InputDecoration(labelText: 'Ouvrage'), items: [for (final it in items) DropdownMenuItem(value: it.id, child: Text(it.title))], onChanged: (v)=>setState(()=>itemId=v)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(initialValue: copyId, decoration: const InputDecoration(labelText: 'Exemplaire disponible'), items: [for (final c in copies) DropdownMenuItem(value: c.id, child: Text('${c.copyCode} (${c.status})'))], onChanged: (v)=>setState(()=>copyId=v)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () async { final d = await showDatePicker(context: ctx, initialDate: due, firstDate: DateTime.now(), lastDate: DateTime(2100)); if (d!=null) setState(()=>due=d); }, child: Text('Échéance: ${fmt.format(due)}')),
          if (copies.isEmpty) const Padding(padding: EdgeInsets.only(top:8), child: Text('Aucun exemplaire disponible pour cet ouvrage.', style: TextStyle(color: Colors.red))),
        ])),
        actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: copyId==null?null:() async { await ref.read(libraryRepositoryProvider).borrow(copyId: copyId!, studentId: studentId, dueDate: due); if (ctx.mounted) Navigator.pop(ctx); }, child: const Text('Enregistrer le prêt'))],
      );
    }));
  }

  static Future<void> _returnDialog(BuildContext context, WidgetRef ref, LibraryLoan loan) async {
    String copyStatus = 'available';
    await showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder:(ctx,setState)=>AlertDialog(
      title: const Text('Retour de prêt'),
      content: DropdownButtonFormField<String>(initialValue: copyStatus, decoration: const InputDecoration(labelText: 'État de l\'exemplaire après retour'), items: const [DropdownMenuItem(value:'available', child: Text('Disponible (bon état)')), DropdownMenuItem(value:'damaged', child: Text('Endommagé')), DropdownMenuItem(value:'lost', child: Text('Perdu'))], onChanged: (v)=>setState(()=>copyStatus=v??'available')),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: () async { await ref.read(libraryRepositoryProvider).returnLoan(loan.id, copyStatus: copyStatus); if (ctx.mounted) Navigator.pop(ctx); }, child: const Text('Valider le retour'))],
    )));
  }
}
