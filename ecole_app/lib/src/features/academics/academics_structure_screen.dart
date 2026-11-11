import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../settings/settings_providers.dart';
import 'academics_providers.dart';

class AcademicsStructureTab extends ConsumerWidget {
  const AcademicsStructureTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Types d\'enseignement'),
              Tab(text: 'Niveaux'),
              Tab(text: 'Matières'),
              Tab(text: 'Classes'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _EducationTypesPane(),
                _LevelsPane(),
                _SubjectsPane(),
                _ClassesPane(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EducationTypesPane extends ConsumerWidget {
  const _EducationTypesPane();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(educationTypesProvider);
    return _CrudPane<EducationType>(
      title: 'Types d\'enseignement',
      items: items,
      columns: const ['Nom', 'Description'],
      cells: (e) => [e.name, e.description ?? ''],
      onAdd: () => _editEducationType(context, ref),
      onEdit: (e) => _editEducationType(context, ref, e),
      onDelete: (e) => ref.read(academicsRepositoryProvider).deleteEducationType(e.id),
    );
  }

  static Future<void> _editEducationType(BuildContext context, WidgetRef ref, [EducationType? e]) async {
    final name = TextEditingController(text: e?.name ?? '');
    final desc = TextEditingController(text: e?.description ?? '');
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(e == null ? 'Nouveau type' : 'Modifier le type'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom')),
        const SizedBox(height: 8),
        TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () async {
          if (name.text.trim().isEmpty) return;
          await ref.read(academicsRepositoryProvider).upsertEducationType(
            id: e?.id, name: name.text.trim(), description: desc.text.trim().isEmpty ? null : desc.text.trim());
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Enregistrer')),
      ],
    ));
  }
}

class _LevelsPane extends ConsumerWidget {
  const _LevelsPane();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(levelsProvider);
    final types = ref.watch(educationTypesProvider).valueOrNull ?? [];
    final typeNames = {for (final t in types) t.id: t.name};
    return _CrudPane<Level>(
      title: 'Niveaux',
      items: items,
      columns: const ['Ordre', 'Nom', 'Type'],
      cells: (l) => ['${l.orderIndex}', l.name, typeNames[l.educationTypeId] ?? '-'],
      onAdd: () => _editLevel(context, ref),
      onEdit: (l) => _editLevel(context, ref, l),
      onDelete: (l) => ref.read(academicsRepositoryProvider).deleteLevel(l.id),
    );
  }

  static Future<void> _editLevel(BuildContext context, WidgetRef ref, [Level? l]) async {
    final name = TextEditingController(text: l?.name ?? '');
    final order = TextEditingController(text: '${l?.orderIndex ?? 0}');
    String? typeId = l?.educationTypeId;
    final types = ref.read(educationTypesProvider).valueOrNull ?? [];
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setState) => AlertDialog(
      title: Text(l == null ? 'Nouveau niveau' : 'Modifier le niveau'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom')),
        const SizedBox(height: 8),
        TextField(controller: order, decoration: const InputDecoration(labelText: 'Ordre'), keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          initialValue: typeId,
          decoration: const InputDecoration(labelText: 'Type d\'enseignement'),
          items: [const DropdownMenuItem(value: null, child: Text('(Aucun)')),
            for (final t in types) DropdownMenuItem(value: t.id, child: Text(t.name))],
          onChanged: (v) => setState(() => typeId = v),
        ),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () async {
          if (name.text.trim().isEmpty) return;
          await ref.read(academicsRepositoryProvider).upsertLevel(
            id: l?.id, educationTypeId: typeId, name: name.text.trim(), orderIndex: int.tryParse(order.text) ?? 0);
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Enregistrer')),
      ],
    )));
  }
}

class _SubjectsPane extends ConsumerWidget {
  const _SubjectsPane();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(subjectsProvider);
    return _CrudPane<Subject>(
      title: 'Matières',
      items: items,
      columns: const ['Code', 'Nom', 'Coefficient'],
      cells: (s) => [s.code ?? '', s.name, s.defaultCoefficient.toStringAsFixed(2)],
      onAdd: () => _editSubject(context, ref),
      onEdit: (s) => _editSubject(context, ref, s),
      onDelete: (s) => ref.read(academicsRepositoryProvider).deleteSubject(s.id),
    );
  }

  static Future<void> _editSubject(BuildContext context, WidgetRef ref, [Subject? s]) async {
    final name = TextEditingController(text: s?.name ?? '');
    final code = TextEditingController(text: s?.code ?? '');
    final coef = TextEditingController(text: (s?.defaultCoefficient ?? 1.0).toString());
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(s == null ? 'Nouvelle matière' : 'Modifier la matière'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom')),
        const SizedBox(height: 8),
        TextField(controller: code, decoration: const InputDecoration(labelText: 'Code')),
        const SizedBox(height: 8),
        TextField(controller: coef, decoration: const InputDecoration(labelText: 'Coefficient par défaut'), keyboardType: TextInputType.number),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () async {
          if (name.text.trim().isEmpty) return;
          await ref.read(academicsRepositoryProvider).upsertSubject(
            id: s?.id, name: name.text.trim(), code: code.text.trim().isEmpty ? null : code.text.trim(),
            coefficient: double.tryParse(coef.text.replaceAll(',', '.')) ?? 1.0);
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Enregistrer')),
      ],
    ));
  }
}

class _ClassesPane extends ConsumerWidget {
  const _ClassesPane();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final years = ref.watch(academicYearsProvider).valueOrNull ?? [];
    final currentYear = years.where((y) => y.isCurrent).firstOrNull ?? (years.isNotEmpty ? years.first : null);
    final classes = ref.watch(classesProvider(currentYear?.id));
    final levels = ref.watch(levelsProvider).valueOrNull ?? [];
    final levelNames = {for (final l in levels) l.id: l.name};
    if (currentYear == null) {
      return const Center(child: Text('Créez d\'abord une année scolaire (Paramètres).'));
    }
    return _CrudPane<ClassesData>(
      title: 'Classes (${currentYear.label})',
      items: classes,
      columns: const ['Nom', 'Niveau', 'Capacité'],
      cells: (c) => [c.name, levelNames[c.levelId] ?? '-', c.capacity?.toString() ?? '-'],
      onAdd: () => _editClass(context, ref, currentYear),
      onEdit: (c) => _editClass(context, ref, currentYear, c),
      onDelete: (c) => ref.read(academicsRepositoryProvider).deleteClass(c.id),
    );
  }

  static Future<void> _editClass(BuildContext context, WidgetRef ref, AcademicYear year, [ClassesData? c]) async {
    final name = TextEditingController(text: c?.name ?? '');
    final cap = TextEditingController(text: c?.capacity?.toString() ?? '');
    String? levelId = c?.levelId;
    final levels = ref.read(levelsProvider).valueOrNull ?? [];
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setState) => AlertDialog(
      title: Text(c == null ? 'Nouvelle classe' : 'Modifier la classe'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom de la classe')),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          initialValue: levelId,
          decoration: const InputDecoration(labelText: 'Niveau'),
          items: [const DropdownMenuItem(value: null, child: Text('(Aucun)')),
            for (final l in levels) DropdownMenuItem(value: l.id, child: Text(l.name))],
          onChanged: (v) => setState(() => levelId = v),
        ),
        const SizedBox(height: 8),
        TextField(controller: cap, decoration: const InputDecoration(labelText: 'Capacité'), keyboardType: TextInputType.number),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () async {
          if (name.text.trim().isEmpty) return;
          await ref.read(academicsRepositoryProvider).upsertClass(
            id: c?.id, academicYearId: year.id, levelId: levelId, name: name.text.trim(),
            capacity: int.tryParse(cap.text));
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Enregistrer')),
      ],
    )));
  }
}

class _CrudPane<T> extends StatelessWidget {
  final String title;
  final AsyncValue<List<T>> items;
  final List<String> columns;
  final List<String> Function(T) cells;
  final VoidCallback onAdd;
  final void Function(T) onEdit;
  final void Function(T) onDelete;
  const _CrudPane({required this.title, required this.items, required this.columns, required this.cells, required this.onAdd, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Ajouter')),
        ]),
        const SizedBox(height: 12),
        Expanded(child: items.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur: $e')),
          data: (list) {
            if (list.isEmpty) return const Center(child: Text('Aucun élément.'));
            return SingleChildScrollView(
              child: DataTable(
                columns: [for (final c in columns) DataColumn(label: Text(c)), const DataColumn(label: Text('Actions'))],
                rows: [for (final item in list) DataRow(cells: [
                  for (final v in cells(item)) DataCell(Text(v)),
                  DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => onEdit(item)),
                    IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => onDelete(item)),
                  ])),
                ])],
              ),
            );
          },
        )),
      ]),
    );
  }
}
