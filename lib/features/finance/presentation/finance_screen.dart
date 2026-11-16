import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/features/finance/application/finance_providers.dart';

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

  @override
  Widget build(BuildContext context) {
    final totalsAsync = ref.watch(financeTotalsProvider);
    final listAsync = ref.watch(paymentsProvider(_query));
    return Scaffold(
      appBar: AppBar(title: const Text('Finances & Caisse')),
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
