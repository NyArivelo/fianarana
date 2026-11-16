import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/features/finance/application/finance_providers.dart';

class SchedulesScreen extends ConsumerStatefulWidget {
  const SchedulesScreen({super.key});

  @override
  ConsumerState<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends ConsumerState<SchedulesScreen> {
  bool _overdueOnly = false;

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(schedulesProvider(_overdueOnly));
    return Scaffold(
      appBar: AppBar(title: const Text('Échéanciers & relances')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SwitchListTile(
              value: _overdueOnly,
              onChanged: (v) => setState(() => _overdueOnly = v),
              title: const Text('Afficher uniquement les impayés/en retard (alertes de relance)'),
            ),
            Expanded(
              child: listAsync.when(
                data: (rows) => Card(
                  child: rows.isEmpty
                      ? const Center(child: Text('Aucun échéancier (données de test: echeanciers_paiement).'))
                      : SingleChildScrollView(
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Élève')),
                              DataColumn(label: Text('Libellé')),
                              DataColumn(label: Text('Échéance')),
                              DataColumn(label: Text('Dû (MGA)')),
                              DataColumn(label: Text('Payé (MGA)')),
                              DataColumn(label: Text('Statut')),
                            ],
                            rows: rows.map((r) => DataRow(cells: [
                              DataCell(Text(r.studentId)),
                              DataCell(Text(r.label)),
                              DataCell(Text(r.dueDate == null ? '-' : '${r.dueDate!.year}-${r.dueDate!.month.toString().padLeft(2,'0')}-${r.dueDate!.day.toString().padLeft(2,'0')}')),
                              DataCell(Text('${r.amountDueMga}')),
                              DataCell(Text('${r.amountPaidMga}')),
                              DataCell(Text(r.status, style: TextStyle(color: r.status == 'En retard' ? Colors.red : null))),
                            ])).toList(),
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
