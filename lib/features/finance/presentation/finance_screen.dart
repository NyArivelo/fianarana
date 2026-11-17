import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import 'dart:convert';

import 'package:fianarana/core/utils/csv_export.dart';
import 'package:fianarana/core/utils/xlsx_export.dart';
import 'package:fianarana/core/widgets/app_ui.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/core/security/permission_providers.dart';
import 'package:fianarana/features/documents/application/document_providers.dart';
import 'package:fianarana/features/documents/services/document_studio_pdf_service.dart';
import 'package:fianarana/features/finance/application/finance_providers.dart';
import 'package:fianarana/features/finance/data/finance_repository.dart';
import 'package:fianarana/features/finance/services/receipt_service.dart';
import 'package:fianarana/features/students/application/students_providers.dart';

class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  final _search = TextEditingController();
  String? _query;
  String _method = 'Tous';
  bool _todayOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _newPayment() async {
    final auth = ref.read(authControllerProvider);
    final students = await ref
        .read(studentsRepositoryProvider)
        .list(actorUserId: auth.userId, limit: 500);
    if (!mounted) return;
    final studentIdCtrl = ValueNotifier<String?>(null);
    final feeCtrl = TextEditingController(text: 'Écolage');
    final dueCtrl = TextEditingController(text: '0');
    final paidCtrl = TextEditingController(text: '0');
    String method = 'Espèces';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvel encaissement'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Élève'),
              isExpanded: true,
              items: students
                  .map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text('${s.matricule} - ${s.fullName}',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => studentIdCtrl.value = v,
            ),
            const SizedBox(height: 8),
            TextField(
                controller: feeCtrl,
                decoration: const InputDecoration(labelText: 'Libellé des frais')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: dueCtrl,
                      decoration: const InputDecoration(labelText: 'Montant dû (MGA)'),
                      keyboardType: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: paidCtrl,
                      decoration: const InputDecoration(labelText: 'Montant payé (MGA)'),
                      keyboardType: TextInputType.number)),
            ]),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: method,
              decoration: const InputDecoration(labelText: 'Mode de paiement'),
              items: const ['Espèces', 'Mobile Money', 'Chèque', 'Virement']
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => method = v ?? 'Espèces',
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer & générer reçu')),
        ],
      ),
    );
    if (ok == true && studentIdCtrl.value != null) {
      try {
        final receipt = await ref.read(financeRepositoryProvider).recordPayment(
              studentId: studentIdCtrl.value!,
              feeLabel: feeCtrl.text.trim().isEmpty ? 'Frais' : feeCtrl.text.trim(),
              amountDueMga: int.tryParse(dueCtrl.text.trim()) ?? 0,
              amountPaidMga: int.tryParse(paidCtrl.text.trim()) ?? 0,
              paymentMethod: method,
              actorUserId: auth.userId,
              actorUsername: auth.username,
            );
        ref.invalidate(paymentsProvider);
        ref.invalidate(financeTotalsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Paiement enregistré. Reçu : $receipt')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Erreur encaissement : $e')));
        }
      }
    }
  }

  Future<void> _closeCashDesk() async {
    final auth = ref.read(authControllerProvider);
    final cashCtrl = TextEditingController(text: '0');
    final mmCtrl = TextEditingController(text: '0');
    final chkCtrl = TextEditingController(text: '0');
    final trCtrl = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clôture de caisse (Z)'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: cashCtrl,
                decoration: const InputDecoration(labelText: 'Total espèces (MGA)'),
                keyboardType: TextInputType.number),
            TextField(
                controller: mmCtrl,
                decoration: const InputDecoration(labelText: 'Total Mobile Money (MGA)'),
                keyboardType: TextInputType.number),
            TextField(
                controller: chkCtrl,
                decoration: const InputDecoration(labelText: 'Total chèques (MGA)'),
                keyboardType: TextInputType.number),
            TextField(
                controller: trCtrl,
                decoration: const InputDecoration(labelText: 'Total virements (MGA)'),
                keyboardType: TextInputType.number),
            const SizedBox(height: 8),
            const Text('Les paiements ouverts du jour seront marqués clôturés.'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clôturer')),
        ],
      ),
    );
    if (ok == true && auth.userId != null) {
      try {
        await ref.read(financeRepositoryProvider).closeCashDesk(
              cashierUserId: auth.userId!,
              totalCash: int.tryParse(cashCtrl.text) ?? 0,
              totalMobileMoney: int.tryParse(mmCtrl.text) ?? 0,
              totalCheck: int.tryParse(chkCtrl.text) ?? 0,
              totalTransfer: int.tryParse(trCtrl.text) ?? 0,
              actorUserId: auth.userId,
              actorUsername: auth.username,
            );
        ref.invalidate(paymentsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Caisse clôturée (Z)')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Erreur clôture : $e')));
        }
      }
    }
  }

  Future<void> _export(List<PaymentRow> rows) async {
    final choice = await showDialog<String>(context: context, builder: (ctx)=>SimpleDialog(title: const Text('Exporter les transactions'), children: [
      SimpleDialogOption(onPressed: ()=>Navigator.pop(ctx,'csv'), child: const ListTile(leading: Icon(Icons.description_outlined), title: Text('Exporter en CSV'))),
      SimpleDialogOption(onPressed: ()=>Navigator.pop(ctx,'xlsx'), child: const ListTile(leading: Icon(Icons.grid_on_outlined), title: Text('Exporter en Excel (XLSX)'))),
    ]));
    if (choice == null) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final headers = const ['Recu','Date','Eleve','Matricule','Classe','Libelle','Du','Paye','Reste','Mode','Etat'];
    final data = rows.map((r) => <String?>[
          r.receipt,
          r.date?.toIso8601String(),
          r.studentName,
          r.matricule,
          r.classLabel,
          r.feeLabel,
          '${r.due}',
          '${r.paid}',
          '${r.balance}',
          r.method,
          r.closeStatus,
        ]).toList();
    final f = choice == 'xlsx'
        ? await XlsxExport.export(filename: 'paiements_export_$ts.xlsx', sheetName: 'Paiements', headers: headers, rows: data)
        : await CsvExport.export(filename: 'paiements_export_$ts.csv', headers: headers, rows: data);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export ${choice.toUpperCase()} : ${f.path}')));
  }

  Future<void> _printReceipt(PaymentRow r) async {
    final bytes = await ReceiptService().generateReceipt(
      ReceiptData(
        receiptNumber: r.receipt,
        date: r.date,
        studentName: r.studentName,
        matricule: r.matricule,
        classLabel: r.classLabel,
        feeLabel: r.feeLabel,
        amountDue: r.due,
        amountPaid: r.paid,
        balance: r.balance,
        paymentMethod: r.method,
        cashier: null,
      ),
      establishmentName: 'Établissement',
    );
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'recu_${r.receipt}.pdf');
  }

  Future<void> _printReceiptFromTemplate(PaymentRow r) async {
    try {
      final auth = ref.read(authControllerProvider);
      final docRepo = ref.read(documentRepositoryProvider);
      final tpl = await docRepo.defaultTemplate('recu', actorUserId: auth.userId);
      if (tpl == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun modèle "reçu" actif trouvé dans Document Studio.')));
        return;
      }
      final content = jsonDecode(tpl.contentJson as String) as Map<String, dynamic>;
      final pdf = DocumentStudioPdfService();
      final d = r.date ?? DateTime.now();
      final ctx = <String, dynamic>{
        'etablissement': {'nom': 'Établissement scolaire', 'adresse': ''},
        'eleve': {'nom': r.studentName, 'matricule': r.matricule, 'classe': r.classLabel ?? ''},
        'annee': {'libelle': '2026-2027'},
        'date': {'jour': '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}'},
        'recu': {
          'numero': r.receipt,
          'date': '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}',
          'libelle': r.feeLabel,
          'du': '${r.due}',
          'paye': '${r.paid}',
          'reste': '${r.balance}',
          'mode': r.method ?? '',
          'montant': '${r.paid}',
        },
      };
      final bytes = await pdf.renderTemplate(templateContent: content, context: ctx, pageFormat: tpl.pageFormat);
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'recu_modele_${r.receipt}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur reçu (modèle): $e')));
    }
  }

  Future<void> _showClosuresAndReport() async {
    final auth = ref.read(authControllerProvider);
    final repo = ref.read(financeRepositoryProvider);
    final closures = await repo.listClosures(actorUserId: auth.userId);
    final report = await repo.report(actorUserId: auth.userId);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clôtures de caisse & rapport financier'),
        content: SizedBox(
          width: 820,
          height: 520,
          child: DefaultTabController(
            length: 2,
            child: Column(children: [
              const TabBar(tabs: [Tab(text: 'Rapport / cohérence'), Tab(text: 'Historique clôtures (Z)')]),
              Expanded(child: TabBarView(children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      AppStatCard(icon: Icons.receipt_long, label: 'Transactions', value: '${report.paymentsCount}', tone: AppTone.info),
                      AppStatCard(icon: Icons.payments, label: 'Total dû', value: formatMga(report.totalDue), tone: AppTone.neutral),
                      AppStatCard(icon: Icons.savings, label: 'Total encaissé', value: formatMga(report.totalPaid), tone: AppTone.success),
                      AppStatCard(icon: Icons.warning_amber, label: 'Reste à recouvrer', value: formatMga(report.totalBalance), tone: report.totalBalance > 0 ? AppTone.danger : AppTone.success),
                      AppStatCard(icon: Icons.event_busy, label: 'Échéances dues/retard', value: '${report.dueSchedules}', tone: report.dueSchedules > 0 ? AppTone.warning : AppTone.success),
                      AppStatCard(icon: Icons.notification_important, label: 'En retard', value: '${report.overdueSchedules}', tone: report.overdueSchedules > 0 ? AppTone.danger : AppTone.success),
                    ]),
                    const SizedBox(height: 16),
                    const Text('Encaissements par mode', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (report.paidByMethod.isEmpty) const Text('Aucune donnée.')
                    else ...report.paidByMethod.entries.map((e) => ListTile(dense: true, title: Text(e.key), trailing: Text(formatMga(e.value), style: const TextStyle(fontWeight: FontWeight.w600)))),
                  ]),
                ),
                closures.isEmpty
                    ? const Center(child: Text('Aucune clôture enregistrée.'))
                    : ListView(children: closures.map((c) => ListTile(
                          leading: const Icon(Icons.lock_clock),
                          title: Text('${c.closureDate.year}-${c.closureDate.month.toString().padLeft(2, '0')}-${c.closureDate.day.toString().padLeft(2, '0')} • ${c.status}'),
                          subtitle: Text('Espèces ${formatMga(c.totalCash)} • MM ${formatMga(c.totalMobileMoney)} • Chèque ${formatMga(c.totalCheck)} • Virement ${formatMga(c.totalTransfer)}'),
                          trailing: Text(formatMga(c.totalCash + c.totalMobileMoney + c.totalCheck + c.totalTransfer), style: const TextStyle(fontWeight: FontWeight.w700)),
                        )).toList()),
              ])),
            ]),
          ),
        ),
        actions: [
          OutlinedButton.icon(onPressed: () async {
            try {
              final fmt = await showDialog<String>(context: context, builder: (c)=>SimpleDialog(title: const Text('Exporter le rapport & clôtures'), children: [
                SimpleDialogOption(onPressed: ()=>Navigator.pop(c,'csv'), child: const ListTile(leading: Icon(Icons.description_outlined), title: Text('CSV'))),
                SimpleDialogOption(onPressed: ()=>Navigator.pop(c,'xlsx'), child: const ListTile(leading: Icon(Icons.grid_on_outlined), title: Text('Excel (XLSX)'))),
              ]));
              if (fmt == null) return;
              final ts = DateTime.now().millisecondsSinceEpoch;
              final headers = const ['Type','Date/Clé','Libellé','Montant/Info'];
              final rows = <List<String?>>[
                ['Rapport','transactions','Nombre de transactions','${report.paymentsCount}'],
                ['Rapport','total_du','Total dû','${report.totalDue}'],
                ['Rapport','total_paye','Total encaissé','${report.totalPaid}'],
                ['Rapport','reste','Reste à recouvrer','${report.totalBalance}'],
                ['Rapport','echeances_dues','Échéances dues/retard','${report.dueSchedules}'],
                ['Rapport','en_retard','En retard','${report.overdueSchedules}'],
                ...report.paidByMethod.entries.map((e)=>['Par mode', e.key, 'Encaissements', '${e.value}']),
                ...closures.map((c)=>['Clôture','${c.closureDate.year}-${c.closureDate.month.toString().padLeft(2,'0')}-${c.closureDate.day.toString().padLeft(2,'0')}','Espèces/MM/Chèque/Virement','${c.totalCash}/${c.totalMobileMoney}/${c.totalCheck}/${c.totalTransfer}']),
              ];
              final file = fmt == 'xlsx'
                  ? await XlsxExport.export(filename: 'rapport_finance_$ts.xlsx', sheetName: 'Rapport', headers: headers, rows: rows)
                  : await CsvExport.export(filename: 'rapport_finance_$ts.csv', headers: headers, rows: rows);
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export ${fmt.toUpperCase()} : ${file.path}')));
            } catch (e) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur export rapport : $e')));
            }
          }, icon: const Icon(Icons.download_outlined, size: 16), label: const Text('Exporter')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalsAsync = ref.watch(financeTotalsProvider);
    final listAsync = ref.watch(paymentsProvider(_query));
    final perms = ref.watch(currentPermissionsProvider).valueOrNull ?? const <String>{};
    final canCreate = perms.contains('finance.create');
    final canClose = perms.contains('finance.close_cash_desk');
    final canExport = perms.contains('finance.export');

    return Scaffold(
      backgroundColor:
          theme.brightness == Brightness.dark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Finances & Caisse'),
        actions: [
          OutlinedButton.icon(
            onPressed: () => context.go('/finance/schedules'),
            icon: const Icon(Icons.event_note_outlined, size: 16),
            label: const Text('Échéanciers'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _showClosuresAndReport,
            icon: const Icon(Icons.assessment_outlined, size: 16),
            label: const Text('Rapport / Clôtures'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: canClose ? _closeCashDesk : null,
            icon: const Icon(Icons.lock_clock, size: 16),
            label: const Text('Clôture Z'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: canCreate ? _newPayment : null,
            icon: const Icon(Icons.add_card, size: 16),
            label: const Text('Encaissement'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          totalsAsync.when(
            data: (t) {
              final due = t['due'] ?? 0;
              final paid = t['paid'] ?? 0;
              final balance = t['balance'] ?? 0;
              final rate = due == 0 ? 0 : ((paid / due) * 100).clamp(0, 100);
              return Wrap(spacing: 12, runSpacing: 12, children: [
                AppStatCard(
                  icon: Icons.receipt_long_outlined,
                  label: 'Transactions',
                  value: '${t['count'] ?? 0}',
                  hint: 'Reçus enregistrés',
                  tone: AppTone.info,
                ),
                AppStatCard(
                  icon: Icons.savings_outlined,
                  label: 'Total encaissé',
                  value: formatMga(paid),
                  tone: AppTone.success,
                ),
                AppStatCard(
                  icon: Icons.pending_actions_outlined,
                  label: 'Reste à recouvrer',
                  value: formatMga(balance),
                  tone: balance > 0 ? AppTone.danger : AppTone.success,
                ),
                AppStatCard(
                  icon: Icons.donut_large_outlined,
                  label: 'Taux de recouvrement',
                  value: '${rate.toStringAsFixed(1)} %',
                  hint: 'Payé / dû',
                  tone: rate >= 70 ? AppTone.success : AppTone.warning,
                ),
              ]);
            },
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Erreur totaux : $e'),
          ),
          const SizedBox(height: 12),
          listAsync.maybeWhen(
            data: (rows) => _journalCard(rows),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Rechercher (reçu, élève, matricule)...',
                ),
                onSubmitted: (v) =>
                    setState(() => _query = v.trim().isEmpty ? null : v.trim()),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                initialValue: _method,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Mode'),
                items: const ['Tous', 'Espèces', 'Mobile Money', 'Chèque', 'Virement']
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() => _method = v ?? 'Tous'),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Aujourd\'hui'),
              selected: _todayOnly,
              onSelected: (v) => setState(() => _todayOnly = v),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => setState(
                  () => _query = _search.text.trim().isEmpty ? null : _search.text.trim()),
              child: const Text('Filtrer'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: canExport
                  ? listAsync.maybeWhen(
                      data: (rows) => rows.isEmpty ? null : () => _export(rows),
                      orElse: () => null,
                    )
                  : null,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Export CSV'),
            ),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: listAsync.when(
              data: (rows) {
                final filtered = _applyFilters(rows);
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: filtered.isEmpty
                      ? AppEmptyState(
                          icon: Icons.payments_outlined,
                          title: rows.isEmpty
                              ? 'Aucun paiement enregistré'
                              : 'Aucun paiement dans ce filtre',
                          message: rows.isEmpty
                              ? 'Importez les données de test ou enregistrez un encaissement.'
                              : null,
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('N° reçu')),
                                DataColumn(label: Text('Date')),
                                DataColumn(label: Text('Élève')),
                                DataColumn(label: Text('Libellé')),
                                DataColumn(label: Text('Dû')),
                                DataColumn(label: Text('Payé')),
                                DataColumn(label: Text('Reste')),
                                DataColumn(label: Text('Mode')),
                                DataColumn(label: Text('État caisse')),
                                DataColumn(label: Text('PDF')),
                              ],
                              rows: filtered.map((r) {
                                final closed = (r.closeStatus ?? '').toLowerCase().contains('clôt') ||
                                    (r.closeStatus ?? '').toLowerCase().contains('clot');
                                return DataRow(cells: [
                                  DataCell(Text(r.receipt,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontFamily: 'monospace',
                                          color: theme.colorScheme.primary))),
                                  DataCell(Text(formatDateIso(r.date))),
                                  DataCell(Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(r.studentName,
                                          style: const TextStyle(fontWeight: FontWeight.w600)),
                                      Text(
                                          '${r.matricule}${r.classLabel == null ? '' : ' • ${r.classLabel}'}',
                                          style: const TextStyle(fontSize: 10)),
                                    ],
                                  )),
                                  DataCell(Text(r.feeLabel)),
                                  DataCell(Text(formatNumber(r.due))),
                                  DataCell(Text(formatNumber(r.paid),
                                      style: const TextStyle(fontWeight: FontWeight.w600))),
                                  DataCell(AppBadge(
                                    r.balance <= 0 ? 'Soldé' : formatMga(r.balance),
                                    tone: r.balance <= 0 ? AppTone.success : AppTone.danger,
                                  )),
                                  DataCell(AppBadge(
                                    r.method ?? '-',
                                    tone: switch (r.method) {
                                      'Espèces' => AppTone.info,
                                      'Mobile Money' => AppTone.success,
                                      'Chèque' => AppTone.warning,
                                      'Virement' => AppTone.neutral,
                                      _ => AppTone.neutral,
                                    },
                                  )),
                                  DataCell(AppBadge(
                                    r.closeStatus ?? r.scheduleStatus ?? 'Ouverte',
                                    tone: closed ? AppTone.success : AppTone.warning,
                                    icon: closed
                                        ? Icons.lock_outline
                                        : Icons.lock_open_outlined,
                                  )),
                                  DataCell(Wrap(spacing: 0, children: [
                                    IconButton(
                                      tooltip: 'Reçu (standard)',
                                      icon: const Icon(Icons.print_outlined, size: 18),
                                      onPressed: () => _printReceipt(r),
                                    ),
                                    IconButton(
                                      tooltip: 'Reçu (modèle Document Studio)',
                                      icon: const Icon(Icons.description_outlined, size: 18),
                                      onPressed: () => _printReceiptFromTemplate(r),
                                    ),
                                  ])),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Text(
                      'Erreur chargement paiements : $e\n(Vérifiez la permission finance.read)')),
            ),
          ),
        ]),
      ),
    );
  }

  List<PaymentRow> _applyFilters(List<PaymentRow> rows) {
    final now = DateTime.now();
    return rows.where((r) {
      if (_method != 'Tous' && r.method != _method) return false;
      if (_todayOnly) {
        final d = r.date;
        if (d == null) return false;
        if (d.year != now.year || d.month != now.month || d.day != now.day) return false;
      }
      return true;
    }).toList();
  }

  Widget _journalCard(List<PaymentRow> rows) {
    // Journée de caisse : aujourd'hui, sinon la dernière date présente.
    final dates = rows
        .map((r) => r.date)
        .whereType<DateTime>()
        .map((d) => DateTime(d.year, d.month, d.day))
        .toList()
      ..sort((a, b) => b.compareTo(a));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = dates.contains(today) ? today : (dates.isEmpty ? today : dates.first);
    final dayRows = rows.where((r) {
      final d = r.date;
      return d != null && d.year == day.year && d.month == day.month && d.day == day.day;
    }).toList();
    final total = dayRows.fold<int>(0, (sum, r) => sum + r.paid);
    final byMethod = <String, int>{};
    for (final r in dayRows) {
      final m = r.method ?? 'Autre';
      byMethod[m] = (byMethod[m] ?? 0) + r.paid;
    }

    return AppSectionCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      title: 'Journal de caisse — ${formatDateFr(day)}',
      subtitle: '${dayRows.length} reçu(s) • Total encaissé : ${formatMga(total)}',
      trailing: AppBadge(
        dayRows.isEmpty ? 'Aucun mouvement' : '${formatMga(total)}',
        tone: dayRows.isEmpty ? AppTone.neutral : AppTone.success,
        icon: Icons.point_of_sale_outlined,
      ),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final entry in byMethod.entries)
          AppBadge('${entry.key} : ${formatMga(entry.value)}', tone: AppTone.info),
        if (byMethod.isEmpty)
          Text('Aucun encaissement sur la journée sélectionnée.',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}
