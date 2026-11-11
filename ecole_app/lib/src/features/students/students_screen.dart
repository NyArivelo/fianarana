import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../../core/security/current_user_scope.dart';
import '../academics/academics_providers.dart';
import '../settings/settings_providers.dart';
import 'students_io.dart';
import 'students_providers.dart';

class StudentsScreen extends ConsumerStatefulWidget {
  const StudentsScreen({super.key});

  @override
  ConsumerState<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends ConsumerState<StudentsScreen> {
  String? _selectedStudentId;

  @override
  Widget build(BuildContext context) {
    final students = ref.watch(studentsProvider);
    final years = ref.watch(academicYearsProvider).valueOrNull ?? [];
    final filters = ref.watch(studentsFiltersProvider);
    final yearIdForClasses = filters.academicYearId ?? years.where((y) => y.isCurrent).firstOrNull?.id;
    final classes = ref.watch(classesProvider(yearIdForClasses)).valueOrNull ?? [];
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Rechercher (nom, prénom, matricule)...',
                        ),
                        onChanged: (v) => ref.read(studentsSearchProvider.notifier).state = v,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(onPressed: () => _exportStudents(context, ref), icon: const Icon(Icons.download), label: const Text('Exporter')),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(onPressed: () => _importStudents(context, ref), icon: const Icon(Icons.upload), label: const Text('Importer')),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _showStudentDialog(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Nouvel élève'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SizedBox(width: 180, child: DropdownButtonFormField<String?>(value: filters.status, isDense: true, decoration: const InputDecoration(labelText: 'Statut'), items: const [
                    DropdownMenuItem(value: null, child: Text('Tous statuts')),
                    DropdownMenuItem(value: 'active', child: Text('Actif')),
                    DropdownMenuItem(value: 'preinscription', child: Text('Préinscription')),
                    DropdownMenuItem(value: 'suspendu', child: Text('Suspendu')),
                    DropdownMenuItem(value: 'transfere', child: Text('Transféré/Radié')),
                    DropdownMenuItem(value: 'archive', child: Text('Archivé')),
                  ], onChanged: (v) => ref.read(studentsFiltersProvider.notifier).state = v == null ? filters.copyWith(clearStatus: true) : filters.copyWith(status: v))),
                  SizedBox(width: 180, child: DropdownButtonFormField<String?>(value: filters.gender, isDense: true, decoration: const InputDecoration(labelText: 'Genre'), items: const [
                    DropdownMenuItem(value: null, child: Text('Tous genres')),
                    DropdownMenuItem(value: 'M', child: Text('M')),
                    DropdownMenuItem(value: 'F', child: Text('F')),
                  ], onChanged: (v) => ref.read(studentsFiltersProvider.notifier).state = v == null ? filters.copyWith(clearGender: true) : filters.copyWith(gender: v))),
                  SizedBox(width: 200, child: DropdownButtonFormField<String?>(value: filters.academicYearId, isDense: true, decoration: const InputDecoration(labelText: 'Année'), items: [
                    const DropdownMenuItem(value: null, child: Text('Année courante/défaut')),
                    for (final y in years) DropdownMenuItem(value: y.id, child: Text(y.label)),
                  ], onChanged: (v) => ref.read(studentsFiltersProvider.notifier).state = v == null ? filters.copyWith(clearYear: true, clearClass: true) : filters.copyWith(academicYearId: v, clearClass: true))),
                  SizedBox(width: 220, child: DropdownButtonFormField<String?>(value: filters.classId, isDense: true, decoration: const InputDecoration(labelText: 'Classe'), items: [
                    const DropdownMenuItem(value: null, child: Text('Toutes classes')),
                    for (final c in classes) DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ], onChanged: (v) => ref.read(studentsFiltersProvider.notifier).state = v == null ? filters.copyWith(clearClass: true) : filters.copyWith(classId: v))),
                  if (filters.hasAny) TextButton.icon(onPressed: () => ref.read(studentsFiltersProvider.notifier).state = const StudentFilters(), icon: const Icon(Icons.clear), label: const Text('Réinitialiser filtres')),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: students.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Erreur: $e')),
                    data: (list) {
                      if (list.isEmpty) {
                        return const Center(child: Text('Aucun élève (ou hors portée/filtres).'));
                      }
                      return Card(
                        child: Column(children:[
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Align(alignment: Alignment.centerLeft, child: Text('${list.length} élève(s)'))),
                          const Divider(height: 1),
                          Expanded(child: ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (context, i) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final s = list[i];
                              final selected = s.id == _selectedStudentId;
                              return ListTile(
                                selected: selected,
                                leading: CircleAvatar(child: Text(s.firstName.isNotEmpty ? s.firstName[0] : '?')),
                                title: Text('${s.lastName} ${s.firstName}'),
                                subtitle: Text('Matricule: ${s.matricule} • ${s.status}${s.gender != null && s.gender!.isNotEmpty ? ' • ${s.gender}' : ''}'),
                                trailing: Wrap(spacing: 4, children: [
                                  IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _showStudentDialog(context, ref, s)),
                                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
                                    await ref.read(studentsRepositoryProvider).deleteStudent(s.id);
                                    if (_selectedStudentId == s.id) setState(() => _selectedStudentId = null);
                                  }),
                                ]),
                                onTap: () => setState(() => _selectedStudentId = s.id),
                              );
                            },
                          )),
                        ]),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 2,
          child: _selectedStudentId == null
              ? const Center(child: Text('Sélectionnez un élève pour voir le détail.'))
              : _StudentDetail(studentId: _selectedStudentId!),
        ),
      ],
    );
  }

  static Future<void> _exportStudents(BuildContext context, WidgetRef ref) async {
    final format = await showDialog<String>(context: context, builder: (ctx) => SimpleDialog(title: const Text('Exporter les élèves (complet)'), children: [
      SimpleDialogOption(onPressed: ()=>Navigator.pop(ctx,'csv'), child: const Text('CSV (.csv) - élèves + inscription + responsable')),
      SimpleDialogOption(onPressed: ()=>Navigator.pop(ctx,'xlsx'), child: const Text('Excel (.xlsx) - élèves + inscription + responsable')),
    ]));
    if (format == null) return;
    final scope = ref.read(currentUserScopeProvider).valueOrNull;
    final filters = ref.read(studentsFiltersProvider);
    final years = ref.read(academicYearsProvider).valueOrNull ?? [];
    final yearId = filters.academicYearId ?? years.where((y) => y.isCurrent).firstOrNull?.id;
    List<String>? allowed;
    if (scope != null && scope.scope == 'restricted') allowed = scope.allowedClassIds ?? [];
    final rows = await ref.read(studentsRepositoryProvider).exportRows(allowedClassIds: allowed, academicYearId: yearId);
    final path = await FilePicker.platform.saveFile(dialogTitle: 'Enregistrer', fileName: 'eleves_complet.$format', type: FileType.custom, allowedExtensions: [format]);
    if (path == null) return;
    if (format == 'csv') {
      await File(path).writeAsString(StudentsIO.toCsvFromRows(rows));
    } else {
      await File(path).writeAsBytes(StudentsIO.toXlsxFromRows(rows));
    }
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exporté: $path (${rows.length} lignes)')));
  }

  static Future<void> _importStudents(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv','xlsx']);
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    try {
      final rows = await StudentsIO.parseFile(path);
      final existing = await ref.read(studentsRepositoryProvider).existingMatricules();
      final seen = <String>{};
      final preview = <ImportPreviewRow>[];
      for (final r in rows) {
        final mat = (r['matricule'] ?? '').trim().toLowerCase();
        final first = (r['firstName'] ?? r['prenom'] ?? '').trim();
        final last = (r['lastName'] ?? r['nom'] ?? '').trim();
        if (mat.isEmpty || first.isEmpty || last.isEmpty) {
          preview.add(ImportPreviewRow(r, 'invalid', 'Matricule/nom/prénom manquant'));
        } else if (existing.contains(mat)) {
          preview.add(ImportPreviewRow(r, 'duplicate_db', 'Doublon en base (peut être mis à jour si option activée)'));
        } else if (seen.contains(mat)) {
          preview.add(ImportPreviewRow(r, 'duplicate_file', 'Doublon dans le fichier'));
        } else {
          seen.add(mat);
          preview.add(ImportPreviewRow(r, 'new', 'Prêt à importer'));
        }
      }
      if (!context.mounted) return;
      await showDialog(context: context, builder: (ctx) => _ImportPreviewDialog(preview: preview));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur import: $e')));
    }
  }

  static Future<void> _showStudentDialog(BuildContext context, WidgetRef ref, [Student? s]) async {
    final matricule = TextEditingController(text: s?.matricule ?? '');
    final first = TextEditingController(text: s?.firstName ?? '');
    final last = TextEditingController(text: s?.lastName ?? '');
    final gender = TextEditingController(text: s?.gender ?? '');
    final birthPlace = TextEditingController(text: s?.birthPlace ?? '');
    final notes = TextEditingController(text: s?.notes ?? '');
    String status = s?.status ?? 'active';
    DateTime? birthDate = s?.birthDate;
    final fmt = DateFormat('dd/MM/yyyy');
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) => AlertDialog(
        title: Text(s == null ? 'Nouvel élève' : 'Modifier l\'élève'),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: matricule, decoration: const InputDecoration(labelText: 'Matricule *')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: last, decoration: const InputDecoration(labelText: 'Nom *'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: first, decoration: const InputDecoration(labelText: 'Prénom *'))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: gender, decoration: const InputDecoration(labelText: 'Genre'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(
              onPressed: () async {
                final d = await showDatePicker(context: ctx, initialDate: birthDate ?? DateTime(2010,1,1), firstDate: DateTime(1990), lastDate: DateTime.now());
                if (d != null) setState(() => birthDate = d);
              },
              child: Text(birthDate == null ? 'Date de naissance' : 'Naissance: ${fmt.format(birthDate!)}'),
            )),
          ]),
          const SizedBox(height: 8),
          TextField(controller: birthPlace, decoration: const InputDecoration(labelText: 'Lieu de naissance')),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: status,
            decoration: const InputDecoration(labelText: 'Statut'),
            items: const [
              DropdownMenuItem(value: 'active', child: Text('Actif')),
              DropdownMenuItem(value: 'preinscription', child: Text('Préinscription')),
              DropdownMenuItem(value: 'suspendu', child: Text('Suspendu')),
              DropdownMenuItem(value: 'transfere', child: Text('Transféré/Radié')),
              DropdownMenuItem(value: 'archive', child: Text('Archivé')),
            ],
            onChanged: (v) => setState(() => status = v ?? 'active'),
          ),
          const SizedBox(height: 8),
          TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () async {
            if (matricule.text.trim().isEmpty || first.text.trim().isEmpty || last.text.trim().isEmpty) return;
            await ref.read(studentsRepositoryProvider).upsertStudent(
              id: s?.id, matricule: matricule.text.trim(), firstName: first.text.trim(), lastName: last.text.trim(),
              gender: gender.text.trim().isEmpty ? null : gender.text.trim(),
              birthDate: birthDate, birthPlace: birthPlace.text.trim().isEmpty ? null : birthPlace.text.trim(),
              status: status, notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
            );
            if (ctx.mounted) Navigator.pop(ctx);
          }, child: const Text('Enregistrer')),
        ],
      )),
    );
  }
}

class _StudentDetail extends ConsumerWidget {
  final String studentId;
  const _StudentDetail({required this.studentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guardians = ref.watch(studentGuardiansProvider(studentId));
    final enrollments = ref.watch(enrollmentsProvider(studentId));
    final years = ref.watch(academicYearsProvider).valueOrNull ?? [];
    final classes = ref.watch(classesProvider(null)).valueOrNull ?? [];
    final yearNames = {for (final y in years) y.id: y.label};
    final classNames = {for (final c in classes) c.id: c.name};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Responsables légaux', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        guardians.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Erreur: $e'),
          data: (list) => Column(children: [
            for (final g in list)
              ListTile(
                dense: true,
                leading: const Icon(Icons.person_outline),
                title: Text('${g.lastName} ${g.firstName}'),
                subtitle: Text([g.relation, g.phone, g.email].where((e) => e != null && e.isNotEmpty).join(' • ')),
                trailing: IconButton(icon: const Icon(Icons.link_off), tooltip: 'Retirer', onPressed: () => ref.read(studentsRepositoryProvider).unlinkGuardian(studentId, g.id)),
              ),
            if (list.isEmpty) const Text('Aucun responsable lié.'),
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(
              onPressed: () => _addGuardian(context, ref, studentId),
              icon: const Icon(Icons.add), label: const Text('Ajouter / lier un responsable'))),
          ]),
        ),
        const Divider(height: 32),
        Text('Inscriptions', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        enrollments.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Erreur: $e'),
          data: (list) => Column(children: [
            for (final e in list)
              ListTile(
                dense: true,
                leading: const Icon(Icons.assignment_ind_outlined),
                title: Text('${yearNames[e.academicYearId] ?? e.academicYearId} — ${classNames[e.classId] ?? 'Sans classe'}'),
                subtitle: Text('Statut: ${e.status}'),
              ),
            if (list.isEmpty) const Text('Aucune inscription.'),
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(
              onPressed: () => _addEnrollment(context, ref, studentId),
              icon: const Icon(Icons.add), label: const Text('Nouvelle inscription'))),
          ]),
        ),
      ],
    );
  }

  static Future<void> _addGuardian(BuildContext context, WidgetRef ref, String studentId) async {
    final first = TextEditingController();
    final last = TextEditingController();
    final phone = TextEditingController();
    final relation = TextEditingController();
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Nouveau responsable'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: last, decoration: const InputDecoration(labelText: 'Nom')),
        const SizedBox(height: 8),
        TextField(controller: first, decoration: const InputDecoration(labelText: 'Prénom')),
        const SizedBox(height: 8),
        TextField(controller: phone, decoration: const InputDecoration(labelText: 'Téléphone')),
        const SizedBox(height: 8),
        TextField(controller: relation, decoration: const InputDecoration(labelText: 'Lien (père, mère, tuteur...)')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () async {
          if (first.text.trim().isEmpty || last.text.trim().isEmpty) return;
          final gid = await ref.read(studentsRepositoryProvider).upsertGuardian(
            firstName: first.text.trim(), lastName: last.text.trim(),
            phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
            relation: relation.text.trim().isEmpty ? null : relation.text.trim());
          await ref.read(studentsRepositoryProvider).linkGuardian(studentId, gid, primary: true);
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Créer et lier')),
      ],
    ));
  }

  static Future<void> _addEnrollment(BuildContext context, WidgetRef ref, String studentId) async {
    final years = ref.read(academicYearsProvider).valueOrNull ?? [];
    if (years.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Créez d\'abord une année scolaire.')));
      return;
    }
    String yearId = years.where((y) => y.isCurrent).firstOrNull?.id ?? years.first.id;
    String? classId;
    String status = 'preinscription';
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final classes = ref.watch(classesProvider(yearId)).valueOrNull ?? [];
      return AlertDialog(
        title: const Text('Nouvelle inscription'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: yearId,
            decoration: const InputDecoration(labelText: 'Année scolaire'),
            items: [for (final y in years) DropdownMenuItem(value: y.id, child: Text(y.label))],
            onChanged: (v) { if (v != null) setState(() { yearId = v; classId = null; }); },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: classId,
            decoration: const InputDecoration(labelText: 'Classe'),
            items: [const DropdownMenuItem(value: null, child: Text('(Sans classe)')),
              for (final c in classes) DropdownMenuItem(value: c.id, child: Text(c.name))],
            onChanged: (v) => setState(() => classId = v),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: status,
            decoration: const InputDecoration(labelText: 'Statut'),
            items: const [
              DropdownMenuItem(value: 'preinscription', child: Text('Préinscription')),
              DropdownMenuItem(value: 'validee', child: Text('Validée')),
              DropdownMenuItem(value: 'suspendue', child: Text('Suspendue')),
            ],
            onChanged: (v) => setState(() => status = v ?? 'preinscription'),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () async {
            await ref.read(studentsRepositoryProvider).upsertEnrollment(
              studentId: studentId, academicYearId: yearId, classId: classId, status: status);
            if (ctx.mounted) Navigator.pop(ctx);
          }, child: const Text('Enregistrer')),
        ],
      );
    }));
  }
}

class _ImportPreviewDialog extends ConsumerStatefulWidget {
  final List<ImportPreviewRow> preview;
  const _ImportPreviewDialog({required this.preview});
  @override
  ConsumerState<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends ConsumerState<_ImportPreviewDialog> {
  late List<bool> _selected;
  bool _updateExisting = false;
  @override
  void initState() { super.initState(); _selected = widget.preview.map((r)=>r.status=='new').toList(); }

  @override
  Widget build(BuildContext context) {
    final news = widget.preview.where((r)=>r.status=='new').length;
    final dups = widget.preview.where((r)=>r.status.startsWith('duplicate')).length;
    final invalid = widget.preview.where((r)=>r.status=='invalid').length;
    return AlertDialog(
      title: const Text('Prévisualisation import élèves (complet)'),
      content: SizedBox(width: 900, height: 560, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
        Text('Total: ${widget.preview.length} • Nouveaux: $news • Doublons: $dups • Invalides: $invalid'),
        const SizedBox(height: 4),
        const Text('Colonnes supportées: matricule, lastName/nom, firstName/prenom, gender/genre, birthDate/date_naissance, birthPlace/lieu_naissance, status/statut, notes, academicYear/annee, className/classe, enrollmentStatus/statut_inscription, guardianLastName/responsable_nom, guardianFirstName/responsable_prenom, guardianPhone/responsable_telephone, guardianRelation/responsable_lien, guardianEmail/responsable_email'),
        CheckboxListTile(contentPadding: EdgeInsets.zero, value: _updateExisting, onChanged: (v){
          setState((){
            _updateExisting = v ?? false;
            _selected = widget.preview.map((r)=> r.status=='new' || (_updateExisting && r.status=='duplicate_db')).toList();
          });
        }, title: const Text('Mettre à jour les doublons existants (matricule) + lier responsable/inscription si fournis'), controlAffinity: ListTileControlAffinity.leading),
        const SizedBox(height: 4),
        Expanded(child: ListView.builder(itemCount: widget.preview.length, itemBuilder: (context,i){ final r = widget.preview[i]; final canImport = r.status=='new' || (_updateExisting && r.status=='duplicate_db'); return CheckboxListTile(value: _selected[i], onChanged: canImport ? (v)=>setState(()=>_selected[i]=v??false) : null, title: Text('${r.data['matricule'] ?? ''} - ${r.data['lastName'] ?? r.data['nom'] ?? ''} ${r.data['firstName'] ?? r.data['prenom'] ?? ''}'), subtitle: Text('${r.status}: ${r.message}${(r.data['className'] ?? r.data['classe'] ?? '').isNotEmpty ? ' • classe: ${r.data['className'] ?? r.data['classe']}' : ''}${(r.data['guardianLastName'] ?? r.data['responsable_nom'] ?? '').isNotEmpty ? ' • responsable: ${r.data['guardianLastName'] ?? r.data['responsable_nom']}' : ''}'), dense: true, controlAffinity: ListTileControlAffinity.leading); })),
      ])),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: () async {
          final rows = <Map<String,String>>[];
          for (int i=0;i<widget.preview.length;i++){ if (_selected[i]) { final st = widget.preview[i].status; if (st=='new' || (_updateExisting && st=='duplicate_db')) rows.add(widget.preview[i].data); } }
          final years = ref.read(academicYearsProvider).valueOrNull ?? [];
          final defaultYearId = years.where((y) => y.isCurrent).firstOrNull?.id ?? (years.isNotEmpty ? years.first.id : null);
          final res = await ref.read(studentsRepositoryProvider).importStudentsAdvanced(rows, updateExisting: _updateExisting, defaultAcademicYearId: defaultYearId);
          if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import: ${res['created']} créé(s), ${res['updated']} mis à jour, ${res['enrollments']} inscription(s), ${res['guardiansLinked']} responsable(s) lié(s), ${res['skipped']} ignoré(s).'))); }
        }, child: const Text('Importer la sélection')),
      ],
    );
  }
}
