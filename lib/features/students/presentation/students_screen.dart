import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fianarana/core/utils/csv_export.dart';
import 'package:fianarana/core/utils/xlsx_export.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/students/application/students_providers.dart';
import 'package:fianarana/features/students/data/students_repository.dart';
import 'package:fianarana/features/students/services/student_import_service.dart';

const _statuses = <String>[
  'Validée',
  'Préinscription',
  'Suspendue',
  'Transféré/Radiation',
  'Actif',
];

class StudentsScreen extends ConsumerStatefulWidget {
  const StudentsScreen({super.key});

  @override
  ConsumerState<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends ConsumerState<StudentsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _classId;
  String? _status;
  String? _selectedId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _mga(int v) {
    final s = v.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${v < 0 ? '-' : ''}${buf.toString()} MGA';
  }

  Future<void> _exportCsv(List<StudentListItem> items) async {
    final file = await CsvExport.export(
      filename: 'eleves_${DateTime.now().millisecondsSinceEpoch}.csv',
      headers: const ['Matricule', 'Nom', 'Prénom', 'Sexe', 'Classe', 'Statut', 'Solde MGA'],
      rows: items
          .map((s) => <String?>[s.matricule, s.lastName, s.firstName, s.sex, s.classLabel, s.status, '${s.balanceMga}'])
          .toList(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export CSV: ${file.path}')));
  }

  Future<void> _exportXlsx(List<StudentListItem> items) async {
    final file = await XlsxExport.export(
      filename: 'eleves_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      sheetName: 'Eleves',
      headers: const ['Matricule', 'Nom', 'Prénom', 'Sexe', 'Classe', 'Statut', 'Solde MGA'],
      rows: items
          .map((s) => <String?>[s.matricule, s.lastName, s.firstName, s.sex, s.classLabel, s.status, '${s.balanceMga}'])
          .toList(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export XLSX: ${file.path}')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final classesAsync = ref.watch(classesProvider);
    final studentsAsync = ref.watch(studentsListProvider((query: _query, classId: _classId, status: _status)));

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Élèves & Inscriptions'),
        actions: [
          FilledButton.icon(
            onPressed: () => context.go('/students/new'),
            icon: const Icon(Icons.person_add_alt_1, size: 16),
            label: const Text('Inscrire un élève'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _toolbar(context, classesAsync, studentsAsync),
            const SizedBox(height: 12),
            Expanded(
              child: studentsAsync.when(
                data: (items) {
                  final selectedId = _selectedId ?? (items.isNotEmpty ? items.first.id : null);
                  return LayoutBuilder(builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 1100;
                    final list = _studentList(context, items, selectedId);
                    final detail = _detailPanel(context, selectedId);
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: list),
                          const SizedBox(width: 12),
                          SizedBox(width: 370, child: detail),
                        ],
                      );
                    }
                    return Column(children: [
                      Expanded(child: list),
                      const SizedBox(height: 12),
                      SizedBox(height: 280, child: detail),
                    ]);
                  });
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Erreur chargement élèves: $e\n(Vérifiez vos permissions: students.read)'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context, AsyncValue classesAsync, AsyncValue<List<StudentListItem>> studentsAsync) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            height: 38,
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Nom, prénom ou matricule...',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            width: 210,
            height: 38,
            child: classesAsync.when(
              data: (classes) => DropdownButtonFormField<String?>(
                value: _classId,
                isDense: true,
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
          SizedBox(
            width: 190,
            height: 38,
            child: DropdownButtonFormField<String?>(
              value: _status,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Statut'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Tous les statuts')),
                ..._statuses.map((s) => DropdownMenuItem<String?>(value: s, child: Text(s))),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
          IconButton(
            tooltip: 'Réinitialiser les filtres',
            onPressed: () {
              _searchCtrl.clear();
              setState(() {
                _query = '';
                _classId = null;
                _status = null;
              });
            },
            icon: const Icon(Icons.filter_alt_off_outlined, size: 20),
          ),
          OutlinedButton.icon(
            onPressed: () => _importStudents(),
            icon: const Icon(Icons.upload_file_outlined, size: 16),
            label: const Text('Importer (CSV/XLSX)'),
          ),
          OutlinedButton.icon(
            onPressed: studentsAsync.maybeWhen(data: (items) => items.isEmpty ? null : () => _exportCsv(items), orElse: () => null),
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('Export CSV'),
          ),
          OutlinedButton.icon(
            onPressed: studentsAsync.maybeWhen(data: (items) => items.isEmpty ? null : () => _exportXlsx(items), orElse: () => null),
            icon: const Icon(Icons.grid_on_outlined, size: 16),
            label: const Text('Export XLSX'),
          ),
        ],
      ),
    );
  }

  Widget _studentList(BuildContext context, List<StudentListItem> items, String? selectedId) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Row(children: [
            Text('Dossiers élèves', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('${items.length} affiché(s)', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('Aucun élève ne correspond aux filtres.'))
              : Scrollbar(
                  child: SingleChildScrollView(
                    child: SizedBox(
                      width: double.infinity,
                      child: DataTable(
                        showCheckboxColumn: false,
                        columnSpacing: 18,
                        columns: const [
                          DataColumn(label: Text('Matricule')),
                          DataColumn(label: Text('Nom & prénom')),
                          DataColumn(label: Text('Classe')),
                          DataColumn(label: Text('Statut')),
                          DataColumn(label: Text('Solde'), numeric: true),
                        ],
                        rows: items.map((s) {
                          final selected = s.id == selectedId;
                          return DataRow(
                            selected: selected,
                            color: WidgetStateProperty.resolveWith((states) {
                              if (selected) {
                                return isDark ? const Color(0xFF172554).withValues(alpha: 0.7) : const Color(0xFFEFF6FF);
                              }
                              return null;
                            }),
                            onSelectChanged: (_) => setState(() => _selectedId = s.id),
                            cells: [
                              DataCell(Text(s.matricule, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF2563EB)))),
                              DataCell(Text('${s.lastName} ${s.firstName}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                              DataCell(_classChip(context, s.classLabel)),
                              DataCell(_statusBadge(context, s.status)),
                              DataCell(Text(
                                _mga(s.balanceMga),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: s.balanceMga > 0 ? FontWeight.w600 : FontWeight.w500,
                                  color: s.balanceMga > 0 ? const Color(0xFFD97706) : const Color(0xFF059669),
                                ),
                              )),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            Text('Base locale SQLite — 325 élèves importés (données de test)', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
            const Spacer(),
            Text('UUID v4', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
          ]),
        ),
      ]),
    );
  }

  Widget _detailPanel(BuildContext context, String? studentId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final overviewAsync = studentId == null ? null : ref.watch(studentOverviewProvider(studentId));
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: overviewAsync == null
          ? const Center(child: Text('Sélectionnez un élève pour afficher sa fiche.'))
          : overviewAsync.when(
              data: (o) {
                final s = o.student;
                final initials = '${s.lastName.isNotEmpty ? s.lastName[0] : ''}${s.firstName.isNotEmpty ? s.firstName[0] : ''}';
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFF2563EB),
                        child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${s.lastName} ${s.firstName}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                          Text('${s.matricule} • ${o.classLabel ?? '-'}', style: const TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontFamily: 'monospace')),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('UUID: ${s.id}', style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8), fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 10),
                    _statusBadge(context, o.enrollment?.status ?? s.status),
                    const Divider(height: 22),
                    _infoRow(context, 'Sexe', s.sex ?? '-'),
                    _infoRow(context, 'Naissance', s.birthDate == null ? '-' : _date(s.birthDate!)),
                    _infoRow(context, 'Lieu de naissance', s.birthPlace ?? '-'),
                    _infoRow(context, 'Responsable(s)', o.guardians.isEmpty ? '-' : o.guardians.map((g) => '${g.lastName} ${g.firstName}').join(', ')),
                    const Divider(height: 22),
                    _infoRow(context, 'Quitus économat', o.balanceMga <= 0 ? 'Régularisé' : _mga(o.balanceMga),
                        valueColor: o.balanceMga <= 0 ? const Color(0xFF059669) : const Color(0xFFD97706)),
                    _infoRow(context, 'Quitus bibliothèque', o.overdueLoans == 0 ? 'Aucun retard' : '${o.overdueLoans} ouvrage(s) en retard',
                        valueColor: o.overdueLoans == 0 ? const Color(0xFF059669) : const Color(0xFFDC2626)),
                    _infoRow(context, 'Prêts en cours', '${o.activeLoans}'),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => context.go('/students/${s.id}'),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Ouvrir le dossier complet'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => context.go('/timetable'),
                        icon: const Icon(Icons.calendar_month_outlined, size: 16),
                        label: const Text("Voir l'emploi du temps"),
                      ),
                    ),
                  ]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(12), child: Text('Erreur fiche: $e'))),
            ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)))),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: valueColor),
          ),
        ),
      ]),
    );
  }

  Widget _classChip(BuildContext context, String? label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label ?? '-', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }

  Widget _statusBadge(BuildContext context, String status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    late Color bg, fg, bd;
    switch (status) {
      case 'Validée':
      case 'Actif':
        bg = isDark ? const Color(0xFF052E2B) : const Color(0xFFECFDF5);
        fg = isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857);
        bd = isDark ? const Color(0xFF065F46) : const Color(0xFFA7F3D0);
      case 'Préinscription':
        bg = isDark ? const Color(0xFF172554) : const Color(0xFFEFF6FF);
        fg = isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8);
        bd = isDark ? const Color(0xFF1E3A8A) : const Color(0xFFBFDBFE);
      case 'Suspendue':
        bg = isDark ? const Color(0xFF3F2E05) : const Color(0xFFFFFBEB);
        fg = isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309);
        bd = isDark ? const Color(0xFF78350F) : const Color(0xFFFDE68A);
      default:
        bg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
        fg = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);
        bd = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: bd)),
      child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _importStudents() async {
    final pick = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'xlsx', 'xls']);
    if (pick == null || pick.files.single.path == null) return;
    final file = File(pick.files.single.path!);
    final auth = ref.read(authControllerProvider);
    final repo = ref.read(studentsRepositoryProvider);
    try {
      final service = StudentImportService();
      final raw = await service.parseFile(file);
      final existing = await repo.list(actorUserId: auth.userId, limit: 2000);
      final existingMats = existing.map((e) => e.matricule).toSet();
      final classes = await repo.allClasses();
      final classByLabel = {for (final c in classes) c.label.toLowerCase(): c.id};
      final rows = service.toRows(raw, existingMats);
      if (!mounted) return;
      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucune ligne valide trouvée dans le fichier.')));
        return;
      }
      final selected = List<bool>.filled(rows.length, false);
      for (var i = 0; i < rows.length; i++) {
        selected[i] = rows[i].error == null && !rows[i].duplicateMatricule;
      }
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
          title: const Text('Import élèves (prévisualisation & détection des doublons)'),
          content: SizedBox(width: 920, height: 520, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${rows.length} ligne(s) détectée(s). Les doublons/erreurs sont exclus par défaut.', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Expanded(child: SingleChildScrollView(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
              columns: const [DataColumn(label: Text('Importer')), DataColumn(label: Text('Matricule')), DataColumn(label: Text('Nom')), DataColumn(label: Text('Prénom')), DataColumn(label: Text('Classe')), DataColumn(label: Text('État'))],
              rows: List.generate(rows.length, (i) {
                final r = rows[i];
                final ok = r.error == null && !r.duplicateMatricule;
                return DataRow(cells: [
                  DataCell(Checkbox(value: selected[i], onChanged: ok ? (v)=>setD(()=>selected[i]=v??false) : null)),
                  DataCell(Text(r.matricule)),
                  DataCell(Text(r.lastName)),
                  DataCell(Text(r.firstName)),
                  DataCell(Text(r.classLabel ?? '-')),
                  DataCell(Text(r.error ?? (ok ? 'Prêt' : 'Ignoré'), style: TextStyle(fontSize: 11, color: ok ? const Color(0xFF059669) : const Color(0xFFDC2626)))),
                ]);
              }),
            )))),
          ])),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton.icon(onPressed: () async {
              var imported = 0; var failed = 0;
              for (var i = 0; i < rows.length; i++) {
                if (!selected[i]) continue;
                final r = rows[i];
                try {
                  DateTime? bd;
                  if (r.birthDate != null && r.birthDate!.isNotEmpty) bd = DateTime.tryParse(r.birthDate!);
                  final classId = r.classLabel == null ? null : classByLabel[r.classLabel!.toLowerCase()];
                  await repo.createStudent(
                    matricule: r.matricule,
                    lastName: r.lastName,
                    firstName: r.firstName,
                    sex: r.sex,
                    birthDate: bd,
                    birthPlace: r.birthPlace,
                    birthCertificateNumber: r.birthCertificateNumber,
                    nationalIdNumber: r.nationalIdNumber,
                    classId: classId,
                    status: r.status,
                    actorUserId: auth.userId,
                    actorUsername: auth.username,
                  );
                  imported++;
                } catch (_) { failed++; }
              }
              ref.invalidate(studentsListProvider);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import terminé: $imported importé(s), $failed échec(s).')));
            }, icon: const Icon(Icons.playlist_add_check, size: 16), label: const Text('Importer la sélection')),
          ],
        )),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur import: $e')));
    }
  }

}
