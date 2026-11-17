import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/utils/csv_export.dart';
import 'package:fianarana/core/utils/xlsx_export.dart';
import 'package:fianarana/core/widgets/app_ui.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/core/security/permission_providers.dart';
import 'package:fianarana/features/finance/application/finance_providers.dart';
import 'package:fianarana/features/finance/data/finance_repository.dart';
import 'package:fianarana/features/students/application/students_providers.dart';

class SchedulesScreen extends ConsumerStatefulWidget {
  const SchedulesScreen({super.key});

  @override
  ConsumerState<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends ConsumerState<SchedulesScreen> {
  bool _overdueOnly = false;
  String _status = 'Tous';

  Future<void> _refreshStatuses() async {
    final auth = ref.read(authControllerProvider);
    final n = await ref.read(financeRepositoryProvider).refreshScheduleStatuses(
        actorUserId: auth.userId, actorUsername: auth.username);
    ref.invalidate(schedulesProvider);
    ref.invalidate(financeReportProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(n == 0 ? 'Statuts déjà cohérents.' : '$n échéancier(s) mis à jour.')));
    }
  }

  Future<void> _markRelance(ScheduleRow row) async {
    final auth = ref.read(authControllerProvider);
    await ref.read(financeRepositoryProvider).markRelance(row.schedule.id,
        actorUserId: auth.userId, actorUsername: auth.username);
    ref.invalidate(schedulesProvider);
    ref.invalidate(financeReportProvider);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Relance enregistrée.')));
  }

  Future<void> _edit(ScheduleRow? row) async {
    final auth = ref.read(authControllerProvider);
    final repo = ref.read(financeRepositoryProvider);
    // Liste élèves (scopée)
    final students = await ref.read(studentsRepositoryProvider).list(actorUserId: auth.userId, limit: 500);
    String? studentId = row?.schedule.studentId ?? (students.isNotEmpty ? students.first.id : null);
    final labelCtrl = TextEditingController(text: row?.schedule.label ?? 'Écolage');
    final dueCtrl = TextEditingController(text: '${row?.schedule.amountDueMga ?? 0}');
    final paidCtrl = TextEditingController(text: '${row?.schedule.amountPaidMga ?? 0}');
    DateTime? dueDate = row?.schedule.dueDate;
    String status = row?.schedule.status ?? 'À venir';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
            title: Text(row == null ? 'Nouvel échéancier' : 'Modifier l\'échéancier'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<String>(
                    value: studentId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Élève'),
                    items: students
                        .map((s) => DropdownMenuItem(value: s.id, child: Text('${s.matricule} - ${s.fullName}', overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: row == null ? (v) => setD(() => studentId = v) : null,
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: labelCtrl, decoration: const InputDecoration(labelText: 'Libellé (ex: Écolage tranche 2)')),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(controller: dueCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Montant dû (MGA)'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: paidCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Montant payé (MGA)'))),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: Text(dueDate == null ? 'Échéance : non définie' : 'Échéance : ${dueDate!.year}-${dueDate!.month.toString().padLeft(2, '0')}-${dueDate!.day.toString().padLeft(2, '0')}')),
                    TextButton(onPressed: () async { final d = await showDatePicker(context: ctx, firstDate: DateTime(2020), lastDate: DateTime(2035), initialDate: dueDate ?? DateTime.now()); if (d != null) setD(()=>dueDate=d); }, child: const Text('Choisir date')),
                  ]),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: status,
                    decoration: const InputDecoration(labelText: 'Statut'),
                    items: const ['À venir', 'Dû', 'Partiel', 'En retard', 'En retard (relancé)', 'Payé']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setD(() => status = v ?? status),
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
            ],
          )),
    );
    if (ok == true && studentId != null) {
      try {
        await repo.saveSchedule(
          id: row?.schedule.id,
          studentId: studentId!,
          classId: row?.schedule.classId,
          label: labelCtrl.text.trim().isEmpty ? 'Échéance' : labelCtrl.text.trim(),
          amountDueMga: int.tryParse(dueCtrl.text.trim()) ?? 0,
          amountPaidMga: int.tryParse(paidCtrl.text.trim()) ?? 0,
          dueDate: dueDate,
          status: status,
          actorUserId: auth.userId,
          actorUsername: auth.username,
        );
        ref.invalidate(schedulesProvider);
        ref.invalidate(financeReportProvider);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Échéancier enregistré.')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }


  Future<void> _exportSchedules(List<ScheduleRow> rows) async {
    try {
      final choice = await showDialog<String>(context: context, builder: (ctx)=>SimpleDialog(title: const Text('Exporter les échéanciers'), children: [
        SimpleDialogOption(onPressed: ()=>Navigator.pop(ctx,'csv'), child: const ListTile(leading: Icon(Icons.description_outlined), title: Text('Exporter en CSV'))),
        SimpleDialogOption(onPressed: ()=>Navigator.pop(ctx,'xlsx'), child: const ListTile(leading: Icon(Icons.grid_on_outlined), title: Text('Exporter en Excel (XLSX)'))),
      ]));
      if (choice == null) return;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final headers = const ['Eleve', 'Matricule', 'Classe', 'Libelle', 'Echeance', 'Du_MGA', 'Paye_MGA', 'Reste_MGA', 'Statut', 'Derniere_relance'];
      final data = rows.map((r) {
        final sch = r.schedule;
        final reste = (sch.amountDueMga - sch.amountPaidMga).clamp(0, 1 << 30);
        final due = sch.dueDate == null ? '' : '${sch.dueDate!.year}-${sch.dueDate!.month.toString().padLeft(2, '0')}-${sch.dueDate!.day.toString().padLeft(2, '0')}';
        final rel = sch.lastReminderAt == null ? '' : sch.lastReminderAt!.toIso8601String();
        return <String?>[
          r.studentName ?? '',
          r.matricule ?? '',
          r.classLabel ?? '',
          sch.label,
          due,
          '${sch.amountDueMga}',
          '${sch.amountPaidMga}',
          '$reste',
          sch.status,
          rel,
        ];
      }).toList();
      final file = choice == 'xlsx'
          ? await XlsxExport.export(filename: 'echeanciers_$ts.xlsx', sheetName: 'Echeanciers', headers: headers, rows: data)
          : await CsvExport.export(filename: 'echeanciers_$ts.csv', headers: headers, rows: data);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export ${choice.toUpperCase()} : ${file.path}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur export : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(schedulesProvider((overdueOnly: _overdueOnly, status: _status)));
    final perms = ref.watch(currentPermissionsProvider).valueOrNull ?? const <String>{};
    final canManage = perms.contains('finance.create') || perms.contains('finance.update') || perms.contains('finance.validate');
    final canExport = perms.contains('finance.export');
    final reportAsync = ref.watch(financeReportProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Échéanciers & relances')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            reportAsync.maybeWhen(
              data: (r) => Wrap(spacing: 10, runSpacing: 10, children: [
                AppStatCard(icon: Icons.warning_amber_outlined, label: 'En retard', value: '${r.overdueSchedules}', tone: r.overdueSchedules > 0 ? AppTone.danger : AppTone.success),
                AppStatCard(icon: Icons.event_busy_outlined, label: 'Dus / en retard', value: '${r.dueSchedules}', tone: r.dueSchedules > 0 ? AppTone.warning : AppTone.success),
                AppStatCard(icon: Icons.account_balance_wallet_outlined, label: 'Reste global', value: formatMga(r.totalBalance), tone: r.totalBalance > 0 ? AppTone.danger : AppTone.success),
              ]),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _overdueOnly,
                  onChanged: (v) => setState(() => _overdueOnly = v),
                  title: const Text('Uniquement impayés / en retard'),
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(labelText: 'Statut'),
                  items: const ['Tous', 'À venir', 'Dû', 'Partiel', 'En retard', 'En retard (relancé)', 'Payé']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => _status = v ?? 'Tous'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: canManage ? _refreshStatuses : null, icon: const Icon(Icons.sync, size: 16), label: const Text('Recalculer statuts')),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: canManage ? () => _edit(null) : null, icon: const Icon(Icons.add, size: 16), label: const Text('Nouvel échéancier')),
              const SizedBox(width: 8),
              listAsync.maybeWhen(data: (rows)=>OutlinedButton.icon(onPressed: (canExport && rows.isNotEmpty) ? () => _exportSchedules(rows) : null, icon: const Icon(Icons.download_outlined, size: 16), label: const Text('Exporter')), orElse: ()=>const SizedBox.shrink()),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: listAsync.when(
                data: (rows) => Card(
                  clipBehavior: Clip.antiAlias,
                  child: rows.isEmpty
                      ? const Center(child: Text('Aucun échéancier pour ce filtre. (Données de test disponibles via import des seeds.)'))
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Élève')),
                                DataColumn(label: Text('Classe')),
                                DataColumn(label: Text('Libellé')),
                                DataColumn(label: Text('Échéance')),
                                DataColumn(label: Text('Dû (MGA)')),
                                DataColumn(label: Text('Payé (MGA)')),
                                DataColumn(label: Text('Reste')),
                                DataColumn(label: Text('Statut')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: rows.map((r) {
                                final sch = r.schedule;
                                final reste = (sch.amountDueMga - sch.amountPaidMga).clamp(0, 1 << 30);
                                final late = sch.status.toLowerCase().contains('retard') || sch.status == 'Dû';
                                return DataRow(cells: [
                                  DataCell(Text(r.studentName ?? r.matricule ?? sch.studentId)),
                                  DataCell(Text(r.classLabel ?? '-')),
                                  DataCell(Text(sch.label)),
                                  DataCell(Text(sch.dueDate == null ? '-' : '${sch.dueDate!.year}-${sch.dueDate!.month.toString().padLeft(2, '0')}-${sch.dueDate!.day.toString().padLeft(2, '0')}')),
                                  DataCell(Text('${sch.amountDueMga}')),
                                  DataCell(Text('${sch.amountPaidMga}')),
                                  DataCell(Text('$reste', style: TextStyle(color: reste > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.w600))),
                                  DataCell(AppBadge(sch.status, tone: sch.status == 'Payé' ? AppTone.success : (late ? AppTone.danger : AppTone.warning))),
                                  DataCell(Wrap(spacing: 4, children: [
                                    IconButton(tooltip: 'Modifier', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: canManage ? () => _edit(r) : null),
                                    if (late && sch.amountPaidMga < sch.amountDueMga)
                                      IconButton(tooltip: 'Marquer relancé', icon: const Icon(Icons.notifications_active_outlined, size: 18), onPressed: canManage ? () => _markRelance(r) : null),
                                  ])),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Erreur: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
