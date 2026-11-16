import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fianarana/features/students/application/students_providers.dart';

class StudentsScreen extends ConsumerStatefulWidget {
  const StudentsScreen({super.key});

  @override
  ConsumerState<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends ConsumerState<StudentsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _classId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classesProvider);
    final studentsAsync = ref.watch(studentsListProvider((query: _query, classId: _classId)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Élèves & Inscriptions'),
        actions: [
          FilledButton.icon(
            onPressed: () => context.go('/students/new'),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Nouvel élève'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Rechercher (nom, prénom, matricule)...',
                    ),
                    onSubmitted: (v) => setState(() => _query = v),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 260,
                  child: classesAsync.when(
                    data: (classes) => DropdownButtonFormField<String?>(
                      value: _classId,
                      decoration: const InputDecoration(labelText: 'Classe'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Toutes les classes')),
                        ...classes.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.label))),
                      ],
                      onChanged: (v) => setState(() => _classId = v),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Erreur classes: $e'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => setState(() => _query = _searchCtrl.text),
                  icon: const Icon(Icons.filter_alt),
                ),
                IconButton(
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() {
                      _query = '';
                      _classId = null;
                    });
                  },
                  icon: const Icon(Icons.clear),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: studentsAsync.when(
                data: (items) {
                  if (items.isEmpty) {
                    return const Center(child: Text('Aucun élève trouvé (vérifiez l\'import des données de test).'));
                  }
                  return Card(
                    child: SingleChildScrollView(
                      child: DataTable(
                        showCheckboxColumn: false,
                        columns: const [
                          DataColumn(label: Text('Matricule')),
                          DataColumn(label: Text('Nom')),
                          DataColumn(label: Text('Prénom')),
                          DataColumn(label: Text('Sexe')),
                          DataColumn(label: Text('Classe')),
                          DataColumn(label: Text('Statut')),
                        ],
                        rows: items.map((s) => DataRow(
                          onSelectChanged: (_) => context.go('/students/${s.id}'),
                          cells: [
                            DataCell(Text(s.matricule)),
                            DataCell(Text(s.lastName)),
                            DataCell(Text(s.firstName)),
                            DataCell(Text(s.sex ?? '-')),
                            DataCell(Text(s.classLabel ?? '-')),
                            DataCell(Text(s.status)),
                          ],
                        )).toList(),
                      ),
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('Erreur chargement élèves: $e\n(Vérifiez vos permissions: students.read)')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
