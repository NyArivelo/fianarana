import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fianarana/features/students/application/students_providers.dart';

class GlobalSearchDialog extends ConsumerStatefulWidget {
  const GlobalSearchDialog({super.key});
  @override
  ConsumerState<GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends ConsumerState<GlobalSearchDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final results = _q.trim().isEmpty ? const AsyncValue.data(<dynamic>[]) : ref.watch(studentsListProvider((query: _q, classId: null, status: null)));
    return AlertDialog(
      title: const Text('Recherche rapide (Ctrl+F)'),
      content: SizedBox(
        width: 700,
        height: 420,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher un élève (nom, prénom, matricule)...'),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 12),
          Expanded(child: results.when(
            data: (items) => items.isEmpty
                ? Center(child: Text(_q.trim().isEmpty ? 'Tapez pour rechercher.' : 'Aucun résultat.'))
                : ListView.builder(itemCount: items.length, itemBuilder: (c,i){
                    final s = items[i] as dynamic;
                    return ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text('${s.lastName} ${s.firstName} (${s.matricule})'),
                      subtitle: Text('${s.classLabel ?? "-"} • ${s.status}'),
                      onTap: () { Navigator.pop(context); context.go('/students/${s.id}'); },
                    );
                  }),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e,_) => Center(child: Text('$e')),
          )),
        ]),
      ),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Fermer (Échap)'))],
    );
  }
}

Future<void> showGlobalSearch(BuildContext context) {
  return showDialog(context: context, builder: (_) => const GlobalSearchDialog());
}
