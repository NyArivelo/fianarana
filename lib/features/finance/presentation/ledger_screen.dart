import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/security/permission_providers.dart';
import 'package:fianarana/core/utils/csv_export.dart';
import 'package:fianarana/core/widgets/app_ui.dart';
import 'package:fianarana/features/finance/application/finance_providers.dart';
import 'package:fianarana/features/finance/data/finance_repository.dart';
import 'package:fianarana/features/students/application/students_providers.dart';

/// Grand livre comptable : écritures élève détaillées (brut dû, remises,
/// bourse, avoir, net dû, encaissé, solde) avec filtres et export.
class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  final _search = TextEditingController();
  String? _query;
  DateTime? _from;
  DateTime? _to;
  String? _classId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ({DateTime? from, DateTime? to, String? query, String? classId}) get _args =>
      (from: _from, to: _to, query: _query, classId: _classId);

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = (isFrom ? _from : _to) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: isFrom ? 'Début de période' : 'Fin de période',
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to != null && _to!.isBefore(picked)) _to = picked;
      } else {
        _to = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        if (_from != null && _from!.isAfter(picked)) _from = picked;
      }
    });
  }

  Future<void> _export(List<LedgerRow> rows) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    const headers = [
      'Recu',
      'Date',
      'Eleve',
      'Matricule',
      'Classe',
      'Libelle',
      'Brut du',
      'Remise',
      'Bourse',
      'Avoir',
      'Net du',
      'Paye',
      'Solde',
    ];
    final data = rows
        .map((r) => <String?>[
              r.receipt,
              formatDateIso(r.date),
              r.studentName,
              r.matricule,
              r.classLabel,
              r.feeLabel,
              '${r.grossDue}',
              '${r.discount}',
              '${r.scholarship}',
              '${r.creditNote}',
              '${r.netDue}',
              '${r.paid}',
              '${r.balance}',
            ])
        .toList();
    final file = await CsvExport.export(filename: 'grand_livre_$ts.csv', headers: headers, rows: data);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export CSV : ${file.path}')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final classes = ref.watch(classesProvider).valueOrNull ?? const <ClassesData>[];
    final rowsAsync = ref.watch(ledgerProvider(_args));
    final perms = ref.watch(currentPermissionsProvider).valueOrNull ?? const <String>{};
    final canExport = perms.contains('finance.export');

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Grand livre comptable'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => ref.invalidate(ledgerProvider),
            icon: const Icon(Icons.refresh_outlined),
          ),
          IconButton(
            tooltip: 'Exporter en CSV',
            onPressed: canExport
                ? rowsAsync.maybeWhen(
                    data: (rows) => rows.isEmpty ? null : () => _export(rows),
                    orElse: () => null,
                  )
                : null,
            icon: const Icon(Icons.download_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const AppPageHeader(
            title: 'Écritures de compte élève',
            subtitle: 'Brut dû, remises/bourses/avoirs, net dû, encaissements et soldes sur la période.',
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 300,
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_outlined, size: 18),
                  hintText: 'Reçu, élève, matricule ou libellé',
                ),
                onSubmitted: (v) => setState(() => _query = v.trim().isEmpty ? null : v.trim()),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                initialValue: _classId,
                isExpanded: true,
                decoration: const InputDecoration(isDense: true, labelText: 'Classe'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Toutes les classes')),
                  ...classes.map((c) =>
                      DropdownMenuItem<String?>(value: c.id, child: Text(c.label, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() => _classId = v),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _pickDate(isFrom: true),
              icon: const Icon(Icons.event_outlined, size: 16),
              label: Text(_from == null ? 'Du : toutes' : 'Du : ${formatDateIso(_from)}'),
            ),
            OutlinedButton.icon(
              onPressed: () => _pickDate(isFrom: false),
              icon: const Icon(Icons.event_available_outlined, size: 16),
              label: Text(_to == null ? 'Au : toutes' : 'Au : ${formatDateIso(_to)}'),
            ),
            FilledButton(
              onPressed: () => setState(() => _query = _search.text.trim().isEmpty ? null : _search.text.trim()),
              child: const Text('Filtrer'),
            ),
            TextButton.icon(
              onPressed: (_from == null && _to == null && _classId == null && _query == null)
                  ? null
                  : () => setState(() {
                        _from = null;
                        _to = null;
                        _classId = null;
                        _query = null;
                        _search.clear();
                      }),
              icon: const Icon(Icons.clear_all_outlined, size: 16),
              label: const Text('Réinitialiser'),
            ),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: rowsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erreur : $e')),
              data: (rows) {
                final gross = rows.fold<int>(0, (s, r) => s + r.grossDue);
                final reductions = rows.fold<int>(0, (s, r) => s + r.reductions);
                final net = rows.fold<int>(0, (s, r) => s + r.netDue);
                final paid = rows.fold<int>(0, (s, r) => s + r.paid);
                final balance = rows.fold<int>(0, (s, r) => s + r.balance);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    AppStatCard(
                      icon: Icons.receipt_long_outlined,
                      label: 'Brut dû',
                      value: formatMga(gross),
                      hint: '${rows.length} écriture(s)',
                      tone: AppTone.info,
                    ),
                    AppStatCard(
                      icon: Icons.percent_outlined,
                      label: 'Réductions',
                      value: formatMga(reductions),
                      hint: 'Remises + bourses + avoirs',
                      tone: AppTone.warning,
                    ),
                    AppStatCard(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Net dû',
                      value: formatMga(net),
                      hint: 'Après réductions',
                      tone: AppTone.neutral,
                    ),
                    AppStatCard(
                      icon: Icons.savings_outlined,
                      label: 'Encaissé',
                      value: formatMga(paid),
                      tone: AppTone.success,
                    ),
                    AppStatCard(
                      icon: Icons.pending_actions_outlined,
                      label: 'Solde restant',
                      value: formatMga(balance),
                      tone: balance > 0 ? AppTone.danger : AppTone.success,
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: rows.isEmpty
                          ? const AppEmptyState(
                              icon: Icons.menu_book_outlined,
                              title: 'Aucune écriture sur la période',
                              message: 'Ajustez les filtres ou enregistrez des encaissements.',
                            )
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SingleChildScrollView(
                                child: DataTable(
                                  columnSpacing: 18,
                                  columns: const [
                                    DataColumn(label: Text('N° reçu')),
                                    DataColumn(label: Text('Date')),
                                    DataColumn(label: Text('Élève')),
                                    DataColumn(label: Text('Classe')),
                                    DataColumn(label: Text('Libellé')),
                                    DataColumn(label: Text('Brut dû'), numeric: true),
                                    DataColumn(label: Text('Remise'), numeric: true),
                                    DataColumn(label: Text('Bourse'), numeric: true),
                                    DataColumn(label: Text('Avoir'), numeric: true),
                                    DataColumn(label: Text('Net dû'), numeric: true),
                                    DataColumn(label: Text('Payé'), numeric: true),
                                    DataColumn(label: Text('Solde'), numeric: true),
                                  ],
                                  rows: [
                                    ...rows.map((r) => DataRow(cells: [
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
                                              Text(r.studentName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                              Text(r.matricule, style: const TextStyle(fontSize: 10)),
                                            ],
                                          )),
                                          DataCell(Text(r.classLabel ?? '-')),
                                          DataCell(Text(r.feeLabel)),
                                          DataCell(Text(formatNumber(r.grossDue))),
                                          DataCell(Text(formatNumber(r.discount))),
                                          DataCell(Text(formatNumber(r.scholarship))),
                                          DataCell(Text(formatNumber(r.creditNote))),
                                          DataCell(Text(formatNumber(r.netDue),
                                              style: const TextStyle(fontWeight: FontWeight.w600))),
                                          DataCell(Text(formatNumber(r.paid),
                                              style: const TextStyle(fontWeight: FontWeight.w600))),
                                          DataCell(AppBadge(
                                            r.balance <= 0 ? 'Soldé' : formatMga(r.balance),
                                            tone: r.balance <= 0 ? AppTone.success : AppTone.danger,
                                          )),
                                        ])),
                                    DataRow(
                                      color: WidgetStatePropertyAll(theme.colorScheme.primary.withValues(alpha: 0.06)),
                                      cells: [
                                        const DataCell(Text('TOTAUX', style: TextStyle(fontWeight: FontWeight.w800))),
                                        const DataCell(Text('')),
                                        const DataCell(Text('')),
                                        const DataCell(Text('')),
                                        const DataCell(Text('')),
                                        DataCell(Text(formatNumber(gross),
                                            style: const TextStyle(fontWeight: FontWeight.w800))),
                                        DataCell(Text(formatNumber(reductions),
                                            style: const TextStyle(fontWeight: FontWeight.w800))),
                                        const DataCell(Text('')),
                                        const DataCell(Text('')),
                                        DataCell(Text(formatNumber(net),
                                            style: const TextStyle(fontWeight: FontWeight.w800))),
                                        DataCell(Text(formatNumber(paid),
                                            style: const TextStyle(fontWeight: FontWeight.w800))),
                                        DataCell(Text(formatNumber(balance),
                                            style: const TextStyle(fontWeight: FontWeight.w800))),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}
