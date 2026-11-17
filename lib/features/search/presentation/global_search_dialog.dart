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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 24),
      alignment: Alignment.topCenter,
      child: Container(
        width: 720,
        height: 460,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(children: [
              const Icon(Icons.search, color: Color(0xFF2563EB), size: 18),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Rechercher un élève, matricule, classe...', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, isDense: true),
                onChanged: (v) => setState(() => _q = v),
              )),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)), child: const Text('Échap', style: TextStyle(fontSize: 10, color: Color(0xFF64748B)))),
              IconButton(onPressed: ()=>Navigator.pop(context), icon: const Icon(Icons.close, size: 18)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: results.when(
            data: (items) => items.isEmpty
                ? Center(child: Text(_q.trim().isEmpty ? 'Tapez pour rechercher dans les dossiers élèves...' : 'Aucun résultat.', style: const TextStyle(color: Color(0xFF64748B))))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c,i){
                      final s = items[i] as dynamic;
                      return ListTile(
                        leading: CircleAvatar(radius: 14, backgroundColor: const Color(0xFF2563EB).withOpacity(0.1), child: const Icon(Icons.person_outline, size: 16, color: Color(0xFF2563EB))),
                        title: Text('${s.lastName} ${s.firstName} (${s.matricule})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text('${s.classLabel ?? "-"} • ${s.status}', style: const TextStyle(fontSize: 11)),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Color(0xFF94A3B8)),
                        onTap: () { Navigator.pop(context); context.go('/students/${s.id}'); },
                      );
                    }),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e,_) => Center(child: Text('$e')),
          )),
        ]),
      ),
    );
  }
}

Future<void> showGlobalSearch(BuildContext context) {
  return showDialog(context: context, builder: (_) => const GlobalSearchDialog());
}
