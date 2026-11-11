import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../auth/auth_controller.dart';
import '../students/students_providers.dart';
import 'finance_providers.dart';

class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(tabs: [
            Tab(text: 'Encaissements / Journal'),
            Tab(text: 'Nouveau paiement'),
            Tab(text: 'Types de frais'),
          ]),
          const Expanded(
            child: TabBarView(children: [
              _PaymentsJournalTab(),
              _NewPaymentTab(),
              _FeeTypesTab(),
            ]),
          ),
        ],
      ),
    );
  }
}

class _PaymentsJournalTab extends ConsumerWidget {
  const _PaymentsJournalTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(paymentsProvider);
    final totalToday = ref.watch(totalPaidTodayProvider).valueOrNull ?? 0.0;
    final students = {for (final s in (ref.watch(studentsProvider).valueOrNull ?? <Student>[])) s.id: s};
    final fees = {for (final f in (ref.watch(feeTypesProvider).valueOrNull ?? <FeeType>[])) f.id: f};
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final money = NumberFormat('#,##0.00', 'fr');
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Total encaissé aujourd\'hui: ${money.format(totalToday)}', style: Theme.of(context).textTheme.titleMedium))),
        const SizedBox(height: 12),
        Expanded(child: payments.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur: $e')),
          data: (list) {
            if (list.isEmpty) return const Center(child: Text('Aucun paiement enregistré.'));
            return SingleChildScrollView(child: DataTable(columns: const [
              DataColumn(label: Text('Reçu')), DataColumn(label: Text('Date')), DataColumn(label: Text('Élève')),
              DataColumn(label: Text('Frais')), DataColumn(label: Text('Montant')), DataColumn(label: Text('Mode')), DataColumn(label: Text('Statut')),
            ], rows: [for (final p in list) DataRow(cells: [
              DataCell(Text(p.receiptNumber)),
              DataCell(Text(fmt.format(p.paidAt))),
              DataCell(Text(() { final s = students[p.studentId]; return s == null ? p.studentId : '${s.lastName} ${s.firstName}'; }())),
              DataCell(Text(fees[p.feeTypeId]?.name ?? '-')),
              DataCell(Text(money.format(p.amount))),
              DataCell(Text(p.method)),
              DataCell(Text(p.status)),
            ])]));
          },
        )),
      ]),
    );
  }
}

class _NewPaymentTab extends ConsumerStatefulWidget {
  const _NewPaymentTab();
  @override
  ConsumerState<_NewPaymentTab> createState() => _NewPaymentTabState();
}

class _NewPaymentTabState extends ConsumerState<_NewPaymentTab> {
  String? _studentId;
  String? _feeTypeId;
  String _method = 'cash';
  final _amount = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() { _amount.dispose(); _note.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final amt = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (_studentId == null || amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sélectionnez un élève et un montant valide.')));
      return;
    }
    final user = ref.read(authControllerProvider).currentUser;
    await ref.read(financeRepositoryProvider).addPayment(
      studentId: _studentId!, feeTypeId: _feeTypeId, amount: amt, method: _method,
      cashierUserId: user?.id, note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    _amount.clear(); _note.clear();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paiement enregistré (reçu généré).')));
  }

  @override
  Widget build(BuildContext context) {
    final students = ref.watch(studentsProvider).valueOrNull ?? [];
    final fees = ref.watch(feeTypesProvider).valueOrNull ?? [];
    return SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Enregistrer un paiement', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _studentId,
          decoration: const InputDecoration(labelText: 'Élève *'),
          items: [for (final s in students) DropdownMenuItem(value: s.id, child: Text('${s.lastName} ${s.firstName} (${s.matricule})'))],
          onChanged: (v) => setState(() => _studentId = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _feeTypeId,
          decoration: const InputDecoration(labelText: 'Type de frais'),
          items: [const DropdownMenuItem(value: null, child: Text('(Autre / non spécifié)')),
            for (final f in fees) DropdownMenuItem(value: f.id, child: Text('${f.name} (${f.defaultAmount})'))],
          onChanged: (v) {
            setState(() => _feeTypeId = v);
            if (v != null) {
              final f = fees.where((x) => x.id == v).firstOrNull;
              if (f != null && _amount.text.isEmpty) _amount.text = f.defaultAmount.toStringAsFixed(0);
            }
          },
        ),
        const SizedBox(height: 12),
        TextField(controller: _amount, decoration: const InputDecoration(labelText: 'Montant *'), keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _method,
          decoration: const InputDecoration(labelText: 'Mode de paiement'),
          items: const [
            DropdownMenuItem(value: 'cash', child: Text('Espèces')),
            DropdownMenuItem(value: 'cheque', child: Text('Chèque')),
            DropdownMenuItem(value: 'virement', child: Text('Virement')),
            DropdownMenuItem(value: 'mobile', child: Text('Mobile money')),
          ],
          onChanged: (v) => setState(() => _method = v ?? 'cash'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note'), maxLines: 2),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.save), label: const Text('Enregistrer et générer le reçu')),
      ]),
    ));
  }
}

class _FeeTypesTab extends ConsumerWidget {
  const _FeeTypesTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fees = ref.watch(feeTypesProvider);
    final money = NumberFormat('#,##0.00', 'fr');
    return Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      Row(children: [
        Text('Types de frais', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        FilledButton.icon(onPressed: () => _editFee(context, ref), icon: const Icon(Icons.add), label: const Text('Ajouter')),
      ]),
      const SizedBox(height: 12),
      Expanded(child: fees.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) => list.isEmpty ? const Center(child: Text('Aucun type de frais.')) : ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) {
            final f = list[i];
            return ListTile(
              title: Text(f.name),
              subtitle: Text(f.description ?? ''),
              trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(money.format(f.defaultAmount)),
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editFee(context, ref, f)),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => ref.read(financeRepositoryProvider).deleteFeeType(f.id)),
              ]),
            );
          },
        ),
      )),
    ]));
  }

  static Future<void> _editFee(BuildContext context, WidgetRef ref, [FeeType? f]) async {
    final name = TextEditingController(text: f?.name ?? '');
    final desc = TextEditingController(text: f?.description ?? '');
    final amt = TextEditingController(text: (f?.defaultAmount ?? 0).toString());
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(f == null ? 'Nouveau type de frais' : 'Modifier le type'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom')),
        const SizedBox(height: 8),
        TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description')),
        const SizedBox(height: 8),
        TextField(controller: amt, decoration: const InputDecoration(labelText: 'Montant par défaut'), keyboardType: TextInputType.number),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () async {
          if (name.text.trim().isEmpty) return;
          await ref.read(financeRepositoryProvider).upsertFeeType(
            id: f?.id, name: name.text.trim(), description: desc.text.trim().isEmpty ? null : desc.text.trim(),
            amount: double.tryParse(amt.text.replaceAll(',', '.')) ?? 0);
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Enregistrer')),
      ],
    ));
  }
}
