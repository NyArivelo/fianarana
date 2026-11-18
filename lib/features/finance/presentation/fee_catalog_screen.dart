import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/security/permission_providers.dart';
import 'package:fianarana/core/utils/csv_export.dart';
import 'package:fianarana/core/widgets/app_ui.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/finance/application/fee_providers.dart';
import 'package:fianarana/features/settings/application/structure_providers.dart';
import 'package:fianarana/features/students/application/students_providers.dart';
import 'package:fianarana/features/students/data/students_repository.dart';

/// Catalogue des frais, grilles tarifaires, bourses/remises et notes de crédit.
class FeeCatalogScreen extends ConsumerStatefulWidget {
  const FeeCatalogScreen({super.key});

  @override
  ConsumerState<FeeCatalogScreen> createState() => _FeeCatalogScreenState();
}

class _FeeCatalogScreenState extends ConsumerState<FeeCatalogScreen> {
  String? _yearId;

  ({String? id, String? username}) get _actor {
    final auth = ref.read(authControllerProvider);
    return (id: auth.userId, username: auth.username);
  }

  Set<String> get _perms => ref.watch(currentPermissionsProvider).valueOrNull ?? const <String>{};
  bool get _canCreate => _perms.contains('fees.create');
  bool get _canUpdate => _perms.contains('fees.update');
  bool get _canDelete => _perms.contains('fees.delete');

  void _refresh() {
    ref.invalidate(feeStructuresProvider);
    ref.invalidate(allDiscountsProvider);
    ref.invalidate(allCreditNotesProvider);
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    try {
      await action();
      _refresh();
      if (success != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = ref.watch(schoolYearsProvider).valueOrNull ?? const <SchoolYear>[];
    String? activeYear = _yearId;
    if (activeYear == null && years.isNotEmpty) {
      activeYear = years.where((y) => y.status == 'En cours').isEmpty
          ? years.first.id
          : years.firstWhere((y) => y.status == 'En cours').id;
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Catalogue de frais & remises'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.price_change_outlined, size: 18), text: 'Grille tarifaire'),
            Tab(icon: Icon(Icons.volunteer_activism_outlined, size: 18), text: 'Bourses & remises'),
            Tab(icon: Icon(Icons.receipt_long_outlined, size: 18), text: 'Notes de crédit'),
          ]),
        ),
        body: TabBarView(children: [
          _feesTab(activeYear),
          _discountsTab(),
          _creditNotesTab(),
        ]),
      ),
    );
  }

  Widget _feesTab(String? yearId) {
    final fees = ref.watch(feeStructuresProvider(yearId));
    final levels = ref.watch(levelsProvider).valueOrNull ?? const <Level>[];
    final levelNames = {for (final l in levels) l.id: l.name};
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppPageHeader(
          title: 'Grille tarifaire',
          subtitle: 'Frais par année et niveau : scolarité, inscription, examens, assurance…',
          actions: [
            OutlinedButton.icon(
              onPressed: () => CsvExport.export(
                filename: 'grille_tarifaire.csv',
                headers: const ['Code', 'Libellé', 'Catégorie', 'Montant MGA', 'Échéances', 'Obligatoire', 'Statut'],
                rows: (fees.valueOrNull ?? const <FeeStructure>[])
                    .map((f) => [f.code, f.label, f.category, '${f.amountMga}', '${f.installmentCount}',
                      f.isMandatory ? 'Oui' : 'Non', f.status]).toList(),
              ),
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Exporter'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _canCreate ? () => _editFee(null, yearId) : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nouveau frais'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(child: fees.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur : $e')),
          data: (list) => list.isEmpty
              ? const AppEmptyState(
                  icon: Icons.price_change_outlined,
                  title: 'Aucun frais paramétré',
                  message: 'Créez la grille tarifaire pour sécuriser la saisie des encaissements.',
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final f = list[i];
                    return Card(child: ListTile(
                      leading: AppBadge(f.code, tone: AppTone.info),
                      title: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${f.category} • ${levelNames[f.levelId] ?? 'Tous niveaux'} • '
                          '${f.isMandatory ? 'Obligatoire' : 'Facultatif'} • '
                          '${f.installmentCount} échéance(s)'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(width: 130, child: Text('${formatNumber(f.amountMga)} MGA',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w700))),
                        const SizedBox(width: 8),
                        AppBadge(f.status, tone: f.status == 'Actif' ? AppTone.success : AppTone.neutral),
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: _canUpdate ? () => _editFee(f, yearId) : null),
                        IconButton(icon: const Icon(Icons.archive_outlined, size: 18),
                            onPressed: !_canDelete ? null : () async {
                              await _run(() => ref.read(feeRepositoryProvider).archiveFee(
                                id: f.id, actorUserId: _actor.id, actorUsername: _actor.username),
                                success: 'Frais archivé.');
                            }),
                      ]),
                    ));
                  },
                ),
        )),
      ]),
    );
  }

  Future<void> _editFee(FeeStructure? fee, String? yearId) async {
    final levels = ref.read(levelsProvider).valueOrNull ?? const <Level>[];
    final code = TextEditingController(text: fee?.code ?? '');
    final label = TextEditingController(text: fee?.label ?? '');
    final amount = TextEditingController(text: '${fee?.amountMga ?? 0}');
    final installments = TextEditingController(text: '${fee?.installmentCount ?? 1}');
    var category = fee?.category ?? 'Scolarité';
    var levelId = fee?.levelId;
    var due = fee?.dueDate;
    var mandatory = fee?.isMandatory ?? true;
    var status = fee?.status ?? 'Actif';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: Text(fee == null ? 'Nouveau frais' : 'Modifier le frais'),
        content: SizedBox(width: 640, height: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            SizedBox(width: 140, child: TextField(controller: code, decoration: const InputDecoration(labelText: 'Code *'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: label, decoration: const InputDecoration(labelText: 'Libellé *'))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              items: const ['Scolarité', 'Inscription', 'Examens', 'Assurance', 'Transport', 'Cantine', 'Activités', 'Autre']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setD(() => category = v ?? category),
            )),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonFormField<String?>(
              initialValue: levelId,
              decoration: const InputDecoration(labelText: 'Niveau'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Tous niveaux')),
                ...levels.map((l) => DropdownMenuItem<String?>(value: l.id, child: Text(l.name))),
              ],
              onChanged: (v) => setD(() => levelId = v),
            )),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: amount, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Montant (MGA) *'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: installments, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Nombre d\'échéances'))),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () async {
                final p = await showDatePicker(context: ctx, initialDate: due ?? DateTime.now(),
                    firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (p != null) setD(() => due = p);
              },
              icon: const Icon(Icons.event_outlined, size: 16),
              label: Text(due == null ? 'Échéance (optionnelle)' : 'Échéance : ${formatDateFr(due)}'),
            ),
            FilterChip(
              label: const Text('Obligatoire'),
              selected: mandatory,
              onSelected: (v) => setD(() => mandatory = v),
            ),
            DropdownButton<String>(
              value: status,
              items: const ['Actif', 'Inactif'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setD(() => status = v ?? status),
            ),
          ]),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      )),
    );
    if (ok != true || label.text.trim().isEmpty || code.text.trim().isEmpty) return;
    await _run(() => ref.read(feeRepositoryProvider).saveFee(
          id: fee?.id,
          schoolYearId: yearId,
          levelId: levelId,
          code: code.text,
          label: label.text,
          category: category,
          amountMga: int.tryParse(amount.text) ?? 0,
          installmentCount: int.tryParse(installments.text) ?? 1,
          dueDate: due,
          isMandatory: mandatory,
          status: status,
          actorUserId: _actor.id,
          actorUsername: _actor.username,
        ), success: fee == null ? 'Frais créé.' : 'Frais mis à jour.');
  }

  Widget _discountsTab() {
    final discounts = ref.watch(allDiscountsProvider);
    final students = ref.watch(studentsListProvider((query: null, classId: null, status: null))).valueOrNull ??
        const <StudentListItem>[];
    final names = {for (final s in students) s.id: '${s.fullName} (${s.matricule})'};
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppPageHeader(
          title: 'Bourses, remises et exonérations',
          subtitle: 'Réductions accordées par élève, avec motif et période de validité.',
          actions: [
            FilledButton.icon(
              onPressed: _canCreate ? () => _editDiscount(null) : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nouvelle remise'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(child: discounts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur : $e')),
          data: (list) => list.isEmpty
              ? const AppEmptyState(
                  icon: Icons.volunteer_activism_outlined,
                  title: 'Aucune remise accordée',
                  message: 'Les bourses et remises réduisent automatiquement le net à payer.',
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final d = list[i];
                    return Card(child: ListTile(
                      leading: AppBadge(d.type, tone: d.type == 'Bourse' ? AppTone.success : AppTone.info),
                      title: Text(d.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${names[d.studentId] ?? d.studentId} • '
                          '${d.amountMga > 0 ? '${formatNumber(d.amountMga)} MGA' : '${d.percent}%'} • '
                          '${d.reason ?? "Sans motif"}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        AppBadge(d.status, tone: d.status == 'Actif' ? AppTone.success : AppTone.neutral),
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: _canUpdate ? () => _editDiscount(d) : null),
                        IconButton(icon: const Icon(Icons.archive_outlined, size: 18),
                            onPressed: !_canDelete ? null : () async {
                              await _run(() => ref.read(feeRepositoryProvider).archiveDiscount(
                                id: d.id, actorUserId: _actor.id, actorUsername: _actor.username),
                                success: 'Remise archivée.');
                            }),
                      ]),
                    ));
                  },
                ),
        )),
      ]),
    );
  }

  Future<void> _editDiscount(StudentDiscount? existing) async {
    final students = await ref.read(studentsListProvider((query: null, classId: null, status: 'Actif')).future);
    if (students.isEmpty || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun élève actif disponible.')));
      return;
    }
    String? studentId = existing?.studentId ?? students.first.id;
    final label = TextEditingController(text: existing?.label ?? '');
    final amount = TextEditingController(text: '${existing?.amountMga ?? 0}');
    final percent = TextEditingController(text: '${existing?.percent ?? 0}');
    final reason = TextEditingController(text: existing?.reason ?? '');
    var type = existing?.type ?? 'Bourse';
    var status = existing?.status ?? 'Actif';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: Text(existing == null ? 'Nouvelle bourse / remise' : 'Modifier la remise'),
        content: SizedBox(width: 560, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: studentId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Élève *'),
            items: students.map((s) => DropdownMenuItem(
              value: s.id,
              child: Text('${s.fullName} — ${s.matricule}', overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (v) => setD(() => studentId = v),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const ['Bourse', 'Remise', 'Exonération', 'Fratrie', 'Personnel']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setD(() => type = v ?? type),
            )),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Statut'),
              items: const ['Actif', 'Suspendu', 'Expiré']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setD(() => status = v ?? status),
            )),
          ]),
          const SizedBox(height: 8),
          TextField(controller: label, decoration: const InputDecoration(labelText: 'Libellé *')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: amount, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Montant fixe (MGA)'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: percent, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'ou Pourcentage (%)'))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: reason, maxLines: 2, decoration: const InputDecoration(labelText: 'Motif')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      )),
    );
    if (ok != true || studentId == null || label.text.trim().isEmpty) return;
    await _run(() => ref.read(feeRepositoryProvider).saveDiscount(
          id: existing?.id,
          studentId: studentId!,
          label: label.text,
          type: type,
          amountMga: int.tryParse(amount.text) ?? 0,
          percent: double.tryParse(percent.text.replaceAll(',', '.')) ?? 0,
          reason: reason.text.isEmpty ? null : reason.text,
          status: status,
          actorUserId: _actor.id,
          actorUsername: _actor.username,
        ), success: 'Remise enregistrée.');
  }

  Widget _creditNotesTab() {
    final notes = ref.watch(allCreditNotesProvider);
    final students = ref.watch(studentsListProvider((query: null, classId: null, status: null))).valueOrNull ??
        const <StudentListItem>[];
    final names = {for (final s in students) s.id: '${s.fullName} (${s.matricule})'};
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppPageHeader(
          title: 'Notes de crédit (avoirs)',
          subtitle: 'Trop-perçus, annulations et reports utilisables sur un prochain encaissement.',
          actions: [
            FilledButton.icon(
              onPressed: _canCreate ? () => _issueCreditNote() : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Émettre un avoir'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(child: notes.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur : $e')),
          data: (list) => list.isEmpty
              ? const AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Aucune note de crédit',
                  message: 'Émettez un avoir pour un trop-perçu ou une annulation de paiement.',
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final n = list[i];
                    return Card(child: ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text('${formatNumber(n.amountMga)} MGA — ${n.reason}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${names[n.studentId] ?? n.studentId} • Émise le ${formatDateFr(n.issuedDate)}'
                          '${n.receiptNumber == null ? '' : ' • Reçu ${n.receiptNumber}'}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        AppBadge(n.status, tone: n.status == 'Annulée' ? AppTone.danger : AppTone.success),
                        if (n.status != 'Annulée')
                          IconButton(
                            tooltip: 'Annuler l\'avoir',
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            onPressed: _canUpdate
                                ? () => _run(() => ref.read(feeRepositoryProvider).cancelCreditNote(
                                      id: n.id, actorUserId: _actor.id, actorUsername: _actor.username),
                                      success: 'Avoir annulé.')
                                : null,
                          ),
                      ]),
                    ));
                  },
                ),
        )),
      ]),
    );
  }

  Future<void> _issueCreditNote() async {
    final students = await ref.read(studentsListProvider((query: null, classId: null, status: 'Actif')).future);
    if (students.isEmpty || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun élève actif disponible.')));
      return;
    }
    String? studentId = students.first.id;
    final amount = TextEditingController(text: '0');
    final reason = TextEditingController();
    final receipt = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: const Text('Émettre une note de crédit'),
        content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: studentId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Élève *'),
            items: students.map((s) => DropdownMenuItem(
              value: s.id,
              child: Text('${s.fullName} — ${s.matricule}', overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (v) => setD(() => studentId = v),
          ),
          const SizedBox(height: 8),
          TextField(controller: amount, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Montant (MGA) *')),
          const SizedBox(height: 8),
          TextField(controller: receipt, decoration: const InputDecoration(labelText: 'Reçu concerné (optionnel)')),
          const SizedBox(height: 8),
          TextField(controller: reason, maxLines: 2, decoration: const InputDecoration(labelText: 'Motif *')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Émettre')),
        ],
      )),
    );
    if (ok != true || studentId == null || reason.text.trim().isEmpty) return;
    await _run(() => ref.read(feeRepositoryProvider).issueCreditNote(
          studentId: studentId!,
          amountMga: int.tryParse(amount.text) ?? 0,
          reason: reason.text,
          receiptNumber: receipt.text.isEmpty ? null : receipt.text,
          actorUserId: _actor.id,
          actorUsername: _actor.username,
        ), success: 'Note de crédit émise.');
  }
}
