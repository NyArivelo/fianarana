import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../auth/auth_controller.dart';
import '../students/students_providers.dart';
import 'finance_providers.dart';
import 'finance_repository.dart';

class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 7,
      child: Column(
        children: [
          const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Encaissements / Journal'),
            Tab(text: 'Nouveau paiement'),
            Tab(text: 'Échéanciers'),
            Tab(text: 'Remises / Avoirs / Bourses'),
            Tab(text: 'Impayés & soldes'),
            Tab(text: 'Clôture de caisse'),
            Tab(text: 'Types de frais'),
          ]),
          const Expanded(
            child: TabBarView(children: [
              _PaymentsJournalTab(),
              _NewPaymentTab(),
              _InstallmentsTab(),
              _AdjustmentsTab(),
              _ArrearsTab(),
              _CashClosureTab(),
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
  String? _installmentId;
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
    try {
      await ref.read(financeRepositoryProvider).addPayment(
        studentId: _studentId!, feeTypeId: _feeTypeId, installmentId: _installmentId, amount: amt, method: _method,
        cashierUserId: user?.id, note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      _amount.clear(); _note.clear(); setState(() => _installmentId = null);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paiement enregistré (reçu généré).')));
    } on CashDayClosedException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
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
        if (_studentId != null) ...[
          const SizedBox(height: 12),
          _InstallmentPicker(studentId: _studentId!, value: _installmentId, onChanged: (id, suggested) {
            setState(() { _installmentId = id; if (suggested != null && _amount.text.isEmpty) _amount.text = suggested.toStringAsFixed(0); });
          }),
        ],
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

class _InstallmentPicker extends ConsumerWidget {
  final String studentId; final String? value; final void Function(String? id, double? suggestedAmount) onChanged;
  const _InstallmentPicker({required this.studentId, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(paymentPlansProvider(studentId)).valueOrNull ?? [];
    // collect installments from all plans
    final items = <({PaymentInstallment inst, String planName})>[];
    for (final p in plans) {
      final insts = ref.watch(installmentsProvider(p.id)).valueOrNull ?? [];
      for (final i in insts) {
        if (i.status != 'paid') items.add((inst: i, planName: p.name));
      }
    }
    items.sort((a,b)=>a.inst.dueDate.compareTo(b.inst.dueDate));
    final fmt = DateFormat('dd/MM/yyyy');
    final money = NumberFormat('#,##0.00', 'fr');
    return DropdownButtonFormField<String?>(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Échéance (optionnel)'),
      items: [const DropdownMenuItem(value: null, child: Text('(Aucune - paiement libre)')),
        for (final it in items) DropdownMenuItem(value: it.inst.id, child: Text('${it.planName} #${it.inst.sequence} ${fmt.format(it.inst.dueDate)} reste ${money.format(it.inst.amount - it.inst.paidAmount)}'))],
      onChanged: (v) {
        final sel = items.firstWhereOrNull((x)=>x.inst.id==v);
        onChanged(v, sel == null ? null : (sel.inst.amount - sel.inst.paidAmount));
      },
    );
  }
}

class _InstallmentsTab extends ConsumerStatefulWidget {
  const _InstallmentsTab();
  @override
  ConsumerState<_InstallmentsTab> createState() => _InstallmentsTabState();
}

class _InstallmentsTabState extends ConsumerState<_InstallmentsTab> {
  String? _studentId;
  @override
  Widget build(BuildContext context) {
    final students = ref.watch(studentsProvider).valueOrNull ?? [];
    final allInst = ref.watch(allInstallmentsProvider).valueOrNull ?? [];
    final plans = _studentId == null ? <PaymentPlan>[] : (ref.watch(paymentPlansProvider(_studentId!)).valueOrNull ?? []);
    final money = NumberFormat('#,##0.00', 'fr');
    final fmt = DateFormat('dd/MM/yyyy');
    final overdue = allInst.where((i) => i.status == 'overdue').length;
    final dueSoon = allInst.where((i) => i.status == 'pending' && i.dueDate.isBefore(DateTime.now().add(const Duration(days: 7)))).length;

    return Padding(padding: const EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 420, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Échéanciers & plans de paiement', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          Chip(label: Text('En retard: $overdue')),
          Chip(label: Text('À venir (7j): $dueSoon')),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _studentId,
          decoration: const InputDecoration(labelText: 'Élève'),
          items: [for (final s in students) DropdownMenuItem(value: s.id, child: Text('${s.lastName} ${s.firstName}'))],
          onChanged: (v) => setState(() => _studentId = v),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: _studentId == null ? null : () => _createPlan(context, ref, _studentId!), icon: const Icon(Icons.add), label: const Text('Nouveau plan')),
        const SizedBox(height: 12),
        if (_studentId != null)
          Expanded(child: plans.isEmpty ? const Text('Aucun plan pour cet élève.') : ListView.builder(itemCount: plans.length, itemBuilder: (context, i) {
            final p = plans[i];
            final inst = ref.watch(installmentsProvider(p.id)).valueOrNull ?? [];
            return Card(child: ExpansionTile(
              title: Text(p.name),
              subtitle: Text('Total: ${money.format(p.totalAmount)} • ${p.status}'),
              children: [for (final e in inst) ListTile(
                dense: true,
                leading: Icon(e.status == 'paid' ? Icons.check_circle : e.status == 'overdue' ? Icons.warning : Icons.schedule, color: e.status == 'paid' ? Colors.green : e.status == 'overdue' ? Colors.red : null),
                title: Text('Échéance ${e.sequence} - ${fmt.format(e.dueDate)}'),
                subtitle: Text('${money.format(e.paidAmount)} / ${money.format(e.amount)} • ${e.status}'),
              )],
            ));
          })),
      ])),
      const VerticalDivider(width: 24),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Alertes / échéances (toutes)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Expanded(child: allInst.isEmpty ? const Text('Aucune échéance.') : ListView.builder(itemCount: allInst.length, itemBuilder: (context, i) {
          final e = allInst[i];
          return ListTile(
            leading: Icon(e.status == 'paid' ? Icons.check_circle : e.status == 'overdue' ? Icons.error : Icons.schedule, color: e.status == 'overdue' ? Colors.red : e.status == 'paid' ? Colors.green : Colors.orange),
            title: Text('Échéance ${e.sequence} • ${fmt.format(e.dueDate)} • ${money.format(e.amount)}'),
            subtitle: Text('Statut: ${e.status} • Payé: ${money.format(e.paidAmount)} • Plan: ${e.planId.substring(0, 8)}'),
          );
        })),
      ])),
    ]));
  }

  static Future<void> _createPlan(BuildContext context, WidgetRef ref, String studentId) async {
    final name = TextEditingController(text: 'Plan de paiement');
    final total = TextEditingController();
    final count = TextEditingController(text: '3');
    DateTime first = DateTime.now().add(const Duration(days: 30));
    final fmt = DateFormat('dd/MM/yyyy');
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setState) => AlertDialog(
      title: const Text('Nouveau plan de paiement'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Libellé')),
        TextField(controller: total, decoration: const InputDecoration(labelText: 'Montant total'), keyboardType: TextInputType.number),
        TextField(controller: count, decoration: const InputDecoration(labelText: 'Nombre d\'échéances'), keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () async {
          final d = await showDatePicker(context: ctx, initialDate: first, firstDate: DateTime(2020), lastDate: DateTime(2100));
          if (d != null) setState(() => first = d);
        }, child: Text('1ère échéance: ${fmt.format(first)}')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () async {
          final amt = double.tryParse(total.text.replaceAll(',', '.'));
          final n = int.tryParse(count.text) ?? 1;
          if (amt == null || amt <= 0 || n < 1) return;
          await ref.read(financeRepositoryProvider).createPaymentPlan(studentId: studentId, name: name.text.trim(), totalAmount: amt, installmentsCount: n, firstDueDate: first);
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Créer')),
      ],
    )));
  }
}

class _CashClosureTab extends ConsumerWidget {
  const _CashClosureTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final closures = ref.watch(cashClosuresProvider);
    final totalToday = ref.watch(totalPaidTodayProvider).valueOrNull ?? 0.0;
    final money = NumberFormat('#,##0.00', 'fr');
    final fmt = DateFormat('dd/MM/yyyy');
    final user = ref.watch(authControllerProvider).currentUser;
    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Clôture de caisse (Z)', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        FilledButton.icon(onPressed: user == null ? null : () => _closeDay(context, ref, user, totalToday), icon: const Icon(Icons.lock), label: const Text('Clôturer la journée')),
      ]),
      const SizedBox(height: 8),
      Text('Encaissements du jour (attendu): ${money.format(totalToday)}'),
      const SizedBox(height: 12),
      Expanded(child: closures.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) => list.isEmpty ? const Text('Aucune clôture enregistrée.') : SingleChildScrollView(child: DataTable(columns: const [
          DataColumn(label: Text('Date')), DataColumn(label: Text('Attendu')), DataColumn(label: Text('Compté')), DataColumn(label: Text('Écart')), DataColumn(label: Text('Note')),
        ], rows: [for (final c in list) DataRow(cells: [
          DataCell(Text(fmt.format(c.closureDate))),
          DataCell(Text(money.format(c.expectedAmount))),
          DataCell(Text(money.format(c.countedAmount))),
          DataCell(Text(money.format(c.difference))),
          DataCell(Text(c.note ?? '')),
        ])])),
      )),
    ]));
  }

  static Future<void> _closeDay(BuildContext context, WidgetRef ref, User user, double expected) async {
    final counted = TextEditingController(text: expected.toStringAsFixed(2));
    final note = TextEditingController();
    final money = NumberFormat('#,##0.00', 'fr');
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Clôturer la caisse du jour'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Caissier: ${user.displayName}'),
        Text('Montant attendu (système): ${money.format(expected)}'),
        const SizedBox(height: 8),
        TextField(controller: counted, decoration: const InputDecoration(labelText: 'Montant compté (espèces/total)'), keyboardType: TextInputType.number),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
        const SizedBox(height: 8),
        const Text('Cette clôture enregistre le Z de caisse pour la journée.'),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () async {
          final amt = double.tryParse(counted.text.replaceAll(',', '.')) ?? 0;
          await ref.read(financeRepositoryProvider).createCashClosure(cashierUserId: user.id, date: DateTime.now(), countedAmount: amt, note: note.text.trim().isEmpty ? null : note.text.trim());
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Valider la clôture')),
      ],
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


class _AdjustmentsTab extends ConsumerWidget {
  const _AdjustmentsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adjustments = ref.watch(adjustmentsProvider);
    final students = {for (final s in (ref.watch(studentsProvider).valueOrNull ?? <Student>[])) s.id: s};
    final fees = {for (final f in (ref.watch(feeTypesProvider).valueOrNull ?? <FeeType>[])) f.id: f};
    final money = NumberFormat('#,##0.00', 'fr');
    final fmt = DateFormat('dd/MM/yyyy');
    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Remises, avoirs et bourses', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        FilledButton.icon(onPressed: () => _edit(context, ref), icon: const Icon(Icons.add), label: const Text('Ajouter')),
      ]),
      const SizedBox(height: 8),
      const Text('Les ajustements actifs réduisent le solde dû (total planifié - ajustements - paiements).'),
      const SizedBox(height: 12),
      Expanded(child: adjustments.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) {
          if (list.isEmpty) return const Center(child: Text('Aucun ajustement enregistré.'));
          return ListView.builder(itemCount: list.length, itemBuilder: (context, i) {
            final a = list[i];
            final st = students[a.studentId];
            return Card(child: ListTile(
              leading: Icon(a.type == 'bourse' ? Icons.school : a.type == 'avoir' ? Icons.account_balance_wallet : Icons.discount, color: a.status == 'active' ? Colors.green : Colors.grey),
              title: Text('${a.type.toUpperCase()} — ${money.format(a.amount)} • ${st != null ? '${st.lastName} ${st.firstName}' : a.studentId}'),
              subtitle: Text('${fmt.format(a.date)} • ${a.status}${a.reason != null && a.reason!.isNotEmpty ? ' • ${a.reason}' : ''}${a.feeTypeId != null && fees[a.feeTypeId] != null ? ' • ${fees[a.feeTypeId]!.name}' : ''}'),
              isThreeLine: true,
              trailing: Wrap(spacing: 4, children: [
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(context, ref, a)),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => ref.read(financeRepositoryProvider).deleteAdjustment(a.id)),
              ]),
            ));
          });
        },
      )),
    ]));
  }

  static Future<void> _edit(BuildContext context, WidgetRef ref, [FinancialAdjustment? a]) async {
    final students = ref.read(studentsProvider).valueOrNull ?? [];
    if (students.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun élève disponible.'))); return; }
    final fees = ref.read(feeTypesProvider).valueOrNull ?? [];
    String studentId = a?.studentId ?? students.first.id;
    String type = a?.type ?? 'remise';
    String status = a?.status ?? 'active';
    String? feeTypeId = a?.feeTypeId;
    final amount = TextEditingController(text: a != null ? a.amount.toStringAsFixed(0) : '');
    final reason = TextEditingController(text: a?.reason ?? '');
    final note = TextEditingController(text: a?.note ?? '');
    DateTime date = a?.date ?? DateTime.now();
    final fmt = DateFormat('dd/MM/yyyy');
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setState) => AlertDialog(
      title: Text(a == null ? 'Nouvel ajustement' : 'Modifier l\'ajustement'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: studentId, decoration: const InputDecoration(labelText: 'Élève'), items: [for (final s in students) DropdownMenuItem(value: s.id, child: Text('${s.lastName} ${s.firstName} (${s.matricule})'))], onChanged: a==null ? (v)=>setState(()=>studentId=v??studentId) : null),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'Type'), items: const [
          DropdownMenuItem(value: 'remise', child: Text('Remise')),
          DropdownMenuItem(value: 'avoir', child: Text('Avoir')),
          DropdownMenuItem(value: 'bourse', child: Text('Bourse')),
          DropdownMenuItem(value: 'reduction', child: Text('Réduction')),
        ], onChanged: (v)=>setState(()=>type=v??'remise')),
        const SizedBox(height: 8),
        TextField(controller: amount, decoration: const InputDecoration(labelText: 'Montant *'), keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () async { final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100)); if (d!=null) setState(()=>date=d); }, child: Text('Date: ${fmt.format(date)}')),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(initialValue: feeTypeId, decoration: const InputDecoration(labelText: 'Frais concerné (optionnel)'), items: [const DropdownMenuItem(value: null, child: Text('(Aucun)')), for (final f in fees) DropdownMenuItem(value: f.id, child: Text(f.name))], onChanged: (v)=>setState(()=>feeTypeId=v)),
        const SizedBox(height: 8),
        TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motif')),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
        DropdownButtonFormField<String>(initialValue: status, decoration: const InputDecoration(labelText: 'Statut'), items: const [DropdownMenuItem(value: 'active', child: Text('Actif')), DropdownMenuItem(value: 'cancelled', child: Text('Annulé'))], onChanged: (v)=>setState(()=>status=v??'active')),
      ]))),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () async {
          final amt = double.tryParse(amount.text.replaceAll(',', '.'));
          if (amt == null || amt <= 0) return;
          await ref.read(financeRepositoryProvider).upsertAdjustment(id: a?.id, studentId: studentId, feeTypeId: feeTypeId, type: type, amount: amt, reason: reason.text.trim().isEmpty?null:reason.text.trim(), date: date, status: status, note: note.text.trim().isEmpty?null:note.text.trim());
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Enregistrer')),
      ],
    )));
  }
}

class _ArrearsTab extends ConsumerWidget {
  const _ArrearsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(studentFinanceSummaryProvider);
    final allInst = ref.watch(allInstallmentsProvider).valueOrNull ?? [];
    final money = NumberFormat('#,##0.00', 'fr');
    final fmt = DateFormat('dd/MM/yyyy');
    final overdueInst = allInst.where((i)=>i.status=='overdue').toList();
    return Padding(padding: const EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Impayés & soldes par élève', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Solde = (total planifié - remises/avoirs/bourses actifs) - paiements validés. Un solde positif indique un reste à payer.'),
        const SizedBox(height: 12),
        Expanded(child: summary.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur: $e')),
          data: (rows) {
            final withDue = rows.where((r)=>r.balance > 0.01 || r.overdueCount > 0).toList();
            if (withDue.isEmpty) return const Center(child: Text('Aucun impayé détecté (selon plans/ajustements/paiements).'));
            return SingleChildScrollView(child: DataTable(columns: const [
              DataColumn(label: Text('Élève')), DataColumn(label: Text('Planifié')), DataColumn(label: Text('Ajustements')), DataColumn(label: Text('Payé')), DataColumn(label: Text('Solde')), DataColumn(label: Text('Échéances en retard')),
            ], rows: [for (final r in withDue) DataRow(cells: [
              DataCell(Text('${r.student.lastName} ${r.student.firstName} (${r.student.matricule})')),
              DataCell(Text(money.format(r.planned))),
              DataCell(Text(money.format(r.adjustments))),
              DataCell(Text(money.format(r.paid))),
              DataCell(Text(money.format(r.balance), style: TextStyle(color: r.balance > 0.01 ? Colors.red : Colors.green, fontWeight: FontWeight.w600))),
              DataCell(Text(r.overdueCount.toString())),
            ])]));
          },
        )),
      ])),
      const VerticalDivider(width: 24),
      Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Alertes échéances en retard', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Expanded(child: overdueInst.isEmpty ? const Text('Aucune échéance en retard.') : ListView.builder(itemCount: overdueInst.length, itemBuilder: (context,i){
          final e = overdueInst[i];
          final reste = (e.amount - e.paidAmount);
          return Card(color: Colors.red.withValues(alpha: 0.05), child: ListTile(
            leading: const Icon(Icons.warning, color: Colors.red),
            title: Text('Échéance ${e.sequence} • ${fmt.format(e.dueDate)}'),
            subtitle: Text('Reste: ${money.format(reste)} / ${money.format(e.amount)} • Plan: ${e.planId.substring(0,8)}'),
          ));
        })),
      ])),
    ]));
  }
}
