import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import 'package:fianarana/features/auth/application/auth_controller.dart';
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _newPayment() async {
    final auth = ref.read(authControllerProvider);
    final students = await ref.read(studentsRepositoryProvider).list(actorUserId: auth.userId, limit: 500);
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
              items: students.map((s) => DropdownMenuItem(value: s.id, child: Text('${s.matricule} - ${s.fullName}'))).toList(),
              onChanged: (v) => studentIdCtrl.value = v,
            ),
            const SizedBox(height: 8),
            TextField(controller: feeCtrl, decoration: const InputDecoration(labelText: 'Libellé des frais')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: dueCtrl, decoration: const InputDecoration(labelText: 'Montant dû (MGA)'), keyboardType: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: paidCtrl, decoration: const InputDecoration(labelText: 'Montant payé (MGA)'), keyboardType: TextInputType.number)),
            ]),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: method,
              decoration: const InputDecoration(labelText: 'Mode de paiement'),
              items: const ['Espèces','Mobile Money','Chèque','Virement'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (v) => method = v ?? 'Espèces',
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer & générer reçu')),
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Paiement enregistré. Reçu: $receipt')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur encaissement: $e')));
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
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: cashCtrl, decoration: const InputDecoration(labelText: 'Total espèces (MGA)'), keyboardType: TextInputType.number),
          TextField(controller: mmCtrl, decoration: const InputDecoration(labelText: 'Total Mobile Money (MGA)'), keyboardType: TextInputType.number),
          TextField(controller: chkCtrl, decoration: const InputDecoration(labelText: 'Total chèques (MGA)'), keyboardType: TextInputType.number),
          TextField(controller: trCtrl, decoration: const InputDecoration(labelText: 'Total virements (MGA)'), keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          const Text('Les paiements ouverts du jour seront marqués clôturés.'),
        ])),
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Caisse clôturée (Z)')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur clôture: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalsAsync = ref.watch(financeTotalsProvider);
    final listAsync = ref.watch(paymentsProvider(_query));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finances & Caisse'),
        actions: [
          OutlinedButton.icon(onPressed: () => context.go('/finance/schedules'), icon: const Icon(Icons.event_note_outlined), label: const Text('Échéanciers')),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _closeCashDesk, icon: const Icon(Icons.lock_clock), label: const Text('Clôture Z')),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: _newPayment, icon: const Icon(Icons.add_card), label: const Text('Encaissement')),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            totalsAsync.when(
              data: (t) => Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _KpiCard(label: 'Transactions', value: '${t['count'] ?? 0}'),
                  _KpiCard(label: 'Total dû (MGA)', value: '${t['due'] ?? 0}'),
                  _KpiCard(label: 'Total payé (MGA)', value: '${t['paid'] ?? 0}'),
                  _KpiCard(label: 'Reste à payer (MGA)', value: '${t['balance'] ?? 0}'),
                ],
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Erreur totaux: $e'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher (reçu, élève, matricule)...'),
                    onSubmitted: (v) => setState(() => _query = v.trim().isEmpty ? null : v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: () => setState(() => _query = _search.text.trim().isEmpty ? null : _search.text.trim()), child: const Text('Filtrer')),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: listAsync.when(
                data: (rows) => Card(
                  child: rows.isEmpty
                      ? const Center(child: Text('Aucun paiement (importez les données de test depuis l’assistant).'))
                      : SingleChildScrollView(
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Reçu')),
                              DataColumn(label: Text('Date')),
                              DataColumn(label: Text('Élève')),
                              DataColumn(label: Text('Classe')),
                              DataColumn(label: Text('Libellé')),
                              DataColumn(label: Text('Dû')),
                              DataColumn(label: Text('Payé')),
                              DataColumn(label: Text('Reste')),
                              DataColumn(label: Text('Mode')),
                              DataColumn(label: Text('État caisse')),
                              DataColumn(label: Text('Action')),
                            ],
                            rows: rows.map((r) => DataRow(cells: [
                              DataCell(Text(r.receipt)),
                              DataCell(Text(r.date == null ? '-' : '${r.date!.year}-${r.date!.month.toString().padLeft(2,'0')}-${r.date!.day.toString().padLeft(2,'0')}')),
                              DataCell(Text('${r.studentName} (${r.matricule})')),
                              DataCell(Text(r.classLabel ?? '-')),
                              DataCell(Text(r.feeLabel)),
                              DataCell(Text('${r.due}')),
                              DataCell(Text('${r.paid}')),
                              DataCell(Text('${r.balance}')),
                              DataCell(Text(r.method ?? '-')),
                              DataCell(Text(r.closeStatus ?? r.scheduleStatus ?? '-')),
                              DataCell(IconButton(
                                tooltip: 'Imprimer le reçu PDF',
                                icon: const Icon(Icons.print_outlined),
                                onPressed: () async {
                                  final bytes = await ReceiptService().generateReceipt(ReceiptData(
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
                                  ), establishmentName: 'Établissement');
                                  await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'recu_${r.receipt}.pdf');
                                },
                              )),
                            ])).toList(),
                          ),
                        ),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Erreur: $e\n(Vérifiez permission finance.read)')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  const _KpiCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ]),
        ),
      ),
    );
  }
}
