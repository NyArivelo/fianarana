import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import 'package:fianarana/core/utils/csv_export.dart';
import 'package:fianarana/core/widgets/app_ui.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/core/security/permission_providers.dart';
import 'package:fianarana/features/documents/application/document_providers.dart';
import 'package:fianarana/features/documents/services/document_studio_pdf_service.dart';
import 'package:fianarana/features/library/application/library_providers.dart';
import 'package:fianarana/features/library/data/library_repository.dart';
import 'package:fianarana/features/students/application/students_providers.dart';

/// Module Bibliothèque & Quitus.
///
/// Trois onglets : catalogue des ouvrages, prêts (retards en évidence) et
/// contrôle des quitus par élève (solde d'écolage + livres non restitués).
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _loanFilter = 'Tous';
  bool _includeAllStudents = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(libraryCatalogueProvider);
    ref.invalidate(libraryLoansProvider);
    ref.invalidate(libraryStatsProvider);
    ref.invalidate(libraryQuitusProvider);
  }

  bool _matches(String? haystack) {
    if (_query.isEmpty) return true;
    return (haystack ?? '').toLowerCase().contains(_query);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _generateStudentDoc(LibraryQuitusRow r, String docType, String label) async {
    final auth = ref.read(authControllerProvider);
    try {
      final tpl = await ref.read(documentRepositoryProvider).defaultTemplate(docType, actorUserId: auth.userId);
      if (tpl == null) { _snack('Aucun modèle "$docType" actif dans Document Studio.'); return; }
      final content = jsonDecode(tpl.contentJson as String) as Map<String, dynamic>;
      final pdf = DocumentStudioPdfService();
      final now = DateTime.now();
      final ctx = <String, dynamic>{
        'etablissement': {'nom': 'Établissement scolaire', 'adresse': ''},
        'eleve': {
          'nom': r.fullName,
          'matricule': r.matricule,
          'classe': r.classLabel ?? '-',
        },
        'annee': {'libelle': '2026-2027'},
        'date': {'jour': '${now.day.toString().padLeft(2,'0')}/${now.month.toString().padLeft(2,'0')}/${now.year}'},
        'sortie': {'date': '${now.day.toString().padLeft(2,'0')}/${now.month.toString().padLeft(2,'0')}/${now.year}', 'motif': '', 'quitus_finance': r.financeOk ? 'Oui' : 'Non', 'quitus_bibliotheque': r.libraryOk ? 'Oui' : 'Non'},
      };
      final bytes = await pdf.renderTemplate(templateContent: content, context: ctx, pageFormat: tpl.pageFormat);
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: '${label}_${r.matricule}.pdf');
    } catch (e) { _snack('Erreur génération document : $e'); }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _returnLoan(LibraryLoanRow loan) =>
      _returnLoanByIds(loan.loan.id, loan.loan.itemId, loan.itemTitle);

  Future<void> _returnLoanByIds(String loanId, String itemId, String itemTitle) async {
    final auth = ref.read(authControllerProvider);
    try {
      await ref.read(libraryRepositoryProvider).returnLoan(
            loanId: loanId,
            itemId: itemId,
            actorUserId: auth.userId,
            actorUsername: auth.username,
          );
      _refresh();
      _snack('Retour enregistré : « $itemTitle » — quitus bibliothèque mis à jour.');
    } catch (e) {
      _snack('Erreur retour : $e');
    }
  }

  Future<void> _newLoan() async {
    final catalogue = await ref.read(libraryCatalogueProvider.future);
    final available = catalogue.where((c) => !c.isBorrowed).toList();
    if (available.isEmpty) {
      _snack('Aucun exemplaire disponible : enregistrez d\'abord un retour.');
      return;
    }
    final auth = ref.read(authControllerProvider);
    final students = await ref
        .read(studentsRepositoryProvider)
        .list(actorUserId: auth.userId, limit: 500);
    if (!mounted) return;

    String? itemId = available.first.item.id;
    String? studentId = students.isNotEmpty ? students.first.id : null;
    DateTime dueDate = DateTime.now().add(const Duration(days: 14));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nouveau prêt'),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: itemId,
                decoration: const InputDecoration(labelText: 'Ouvrage disponible'),
                isExpanded: true,
                items: available
                    .map((c) => DropdownMenuItem(
                          value: c.item.id,
                          child: Text(
                            '${c.item.title}${c.item.copyCode == null ? '' : ' • ${c.item.copyCode}'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setDialogState(() => itemId = v),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: studentId,
                decoration: const InputDecoration(labelText: 'Élève emprunteur'),
                isExpanded: true,
                items: students
                    .map((s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(
                            '${s.matricule} — ${s.fullName}${s.classLabel == null ? '' : ' (${s.classLabel})'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setDialogState(() => studentId = v),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Text('Échéance : ${formatDateFr(dueDate)}',
                      style: const TextStyle(fontSize: 12)),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: dueDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setDialogState(() => dueDate = picked);
                  },
                  icon: const Icon(Icons.event_outlined, size: 16),
                  label: const Text('Choisir'),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer le prêt')),
          ],
        ),
      ),
    );
    if (ok != true || itemId == null || studentId == null) return;
    try {
      await ref.read(libraryRepositoryProvider).createLoan(
            itemId: itemId!,
            studentId: studentId!,
            dueDate: dueDate,
            actorUserId: auth.userId,
            actorUsername: auth.username,
          );
      _refresh();
      _snack('Prêt enregistré. Échéance : ${formatDateFr(dueDate)}.');
    } catch (e) {
      _snack('Erreur prêt : $e');
    }
  }

  Future<void> _newItem() async {
    final auth = ref.read(authControllerProvider);
    final titleCtrl = TextEditingController();
    final isbnCtrl = TextEditingController();
    final authorCtrl = TextEditingController();
    final copyCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvel ouvrage'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Titre *')),
            const SizedBox(height: 8),
            TextField(
                controller: isbnCtrl,
                decoration: const InputDecoration(labelText: 'Code / ISBN')),
            const SizedBox(height: 8),
            TextField(
                controller: authorCtrl,
                decoration: const InputDecoration(labelText: 'Auteur / catégorie')),
            const SizedBox(height: 8),
            TextField(
                controller: copyCtrl,
                decoration: const InputDecoration(labelText: 'Code exemplaire (ex: EX-101)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ajouter')),
        ],
      ),
    );
    if (ok != true) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) {
      _snack('Le titre est obligatoire.');
      return;
    }
    try {
      await ref.read(libraryRepositoryProvider).addItem(
            title: title,
            codeOrIsbn: isbnCtrl.text.trim().isEmpty ? null : isbnCtrl.text.trim(),
            authorOrCategory:
                authorCtrl.text.trim().isEmpty ? null : authorCtrl.text.trim(),
            copyCode: copyCtrl.text.trim().isEmpty ? null : copyCtrl.text.trim(),
            actorUserId: auth.userId,
            actorUsername: auth.username,
          );
      _refresh();
      _snack('Ouvrage ajouté au catalogue.');
    } catch (e) {
      _snack('Erreur ajout : $e');
    }
  }


  Future<void> _exportCatalogue(List<LibraryCatalogueRow> rows) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final f = await CsvExport.export(
      filename: 'bibliotheque_catalogue_$ts.csv',
      headers: const ['Titre','Auteur/Categorie','Code exemplaire','ISBN/Code','Statut','Emprunteur','Matricule','Echeance'],
      rows: rows.map((r)=>[
        r.item.title,
        r.item.authorOrCategory,
        r.item.copyCode,
        r.item.codeOrIsbn,
        r.statusLabel,
        r.borrowerName,
        r.borrowerMatricule,
        r.dueDate?.toIso8601String(),
      ]).toList(),
    );
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export catalogue: ${f.path}')));
  }

  Future<void> _exportLoans(List<LibraryLoanRow> rows) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final f = await CsvExport.export(
      filename: 'bibliotheque_prets_$ts.csv',
      headers: const ['Ouvrage','Exemplaire','Emprunteur','Matricule','Classe','Date pret','Echeance','Date retour','Retard'],
      rows: rows.map((r)=>[
        r.itemTitle,
        r.copyCode,
        r.borrowerName,
        r.borrowerMatricule,
        r.classLabel,
        r.loan.loanDate.toIso8601String(),
        r.loan.dueDate?.toIso8601String(),
        r.loan.returnDate?.toIso8601String(),
        r.overdue ? 'Oui' : 'Non',
      ]).toList(),
    );
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export prêts: ${f.path}')));
  }

  Future<void> _exportQuitus(List<LibraryQuitusRow> rows) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final f = await CsvExport.export(
      filename: 'bibliotheque_quitus_$ts.csv',
      headers: const ['Matricule','Eleve','Classe','Solde_MGA','Prets_actifs','Prets_en_retard','Prochaine_echeance','Quitus'],
      rows: rows.map((r)=>[
        r.matricule,
        r.fullName,
        r.classLabel,
        '${r.balanceMga}',
        '${r.activeLoans}',
        '${r.overdueLoans}',
        r.nextDueDate?.toIso8601String(),
        (r.balanceMga <= 0 && r.overdueLoans == 0 && r.activeLoans == 0) ? 'OK' : 'Non conforme',
      ]).toList(),
    );
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export quitus: ${f.path}')));
  }

  Future<void> _exportCurrentTab() async {
    try {
      final idx = _tabs.index;
      if (idx == 0) {
        final rows = ref.read(libraryCatalogueProvider).valueOrNull ?? const <LibraryCatalogueRow>[];
        final filtered = rows.where((r) => _matches(r.item.title) || _matches(r.item.authorOrCategory) || _matches(r.item.copyCode) || _matches(r.item.codeOrIsbn) || _matches(r.borrowerName) || _matches(r.borrowerMatricule)).toList();
        await _exportCatalogue(filtered);
      } else if (idx == 1) {
        final rows = ref.read(libraryLoansProvider).valueOrNull ?? const <LibraryLoanRow>[];
        final filtered = rows.where((l) {
          final okFilter = switch (_loanFilter) {
            'En cours' => !l.isReturned && !l.overdue,
            'En retard' => l.overdue,
            'Retournés' => l.isReturned,
            _ => true,
          };
          if (!okFilter) return false;
          return _matches(l.itemTitle) || _matches(l.borrowerName) || _matches(l.borrowerMatricule) || _matches(l.classLabel);
        }).toList();
        await _exportLoans(filtered);
      } else {
        final rows = ref.read(libraryQuitusProvider(_includeAllStudents)).valueOrNull ?? const <LibraryQuitusRow>[];
        final filtered = rows.where((r) => _matches(r.fullName) || _matches(r.matricule) || _matches(r.classLabel)).toList();
        await _exportQuitus(filtered);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur export: $e')));
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(currentPermissionsProvider).valueOrNull ?? const <String>{};
    final canEdit = perms.contains('library.create') || perms.contains('library.update');
    final canExport = perms.contains('library.read');
    final theme = Theme.of(context);
    final stats = ref.watch(libraryStatsProvider).valueOrNull ?? LibraryStats.empty();
    final overdueBanner = stats.overdue > 0;

    return Scaffold(
      backgroundColor:
          theme.brightness == Brightness.dark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Bibliothèque & Quitus'),
        actions: [
          OutlinedButton.icon(
            onPressed: canEdit ? _newItem : null,
            icon: const Icon(Icons.library_add_outlined, size: 16),
            label: const Text('Nouvel ouvrage'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: canEdit ? _newLoan : null,
            icon: const Icon(Icons.swap_horiz, size: 16),
            label: const Text('Nouveau prêt'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            AppStatCard(
              icon: Icons.menu_book_outlined,
              label: 'Ouvrages',
              value: '${stats.totalItems}',
              hint: 'Catalogue actif',
              tone: AppTone.info,
            ),
            AppStatCard(
              icon: Icons.check_circle_outline,
              label: 'Disponibles',
              value: '${stats.available}',
              tone: AppTone.success,
            ),
            AppStatCard(
              icon: Icons.outbox_outlined,
              label: 'Empruntés',
              value: '${stats.borrowed}',
              hint: 'Prêts en cours',
              tone: AppTone.neutral,
            ),
            AppStatCard(
              icon: Icons.report_gmailerrorred_outlined,
              label: 'Retards',
              value: '${stats.overdue}',
              hint: 'Quitus bibliothèque bloqués',
              tone: stats.overdue > 0 ? AppTone.danger : AppTone.success,
            ),
          ]),
          if (overdueBanner) ...[
            const SizedBox(height: 12),
            AppAlertBanner(
              title: '${stats.overdue} prêt(s) en retard — quitus bibliothèque bloqué',
              message:
                  'Tout emprunt non restitué bloque la délivrance du certificat de radiation. Enregistrez le retour depuis l\'onglet Prêts.',
              tone: AppTone.warning,
              action: TextButton(
                onPressed: () {
                  _tabs.animateTo(1);
                  setState(() => _loanFilter = 'En retard');
                },
                child: const Text('Voir les retards'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(
              width: 360,
              height: 38,
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: _tabs.index == 2
                      ? 'Rechercher un élève, matricule...'
                      : 'Rechercher un ouvrage, un élève, un ISBN...',
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(onPressed: canExport ? _exportCurrentTab : null, icon: const Icon(Icons.download_outlined, size: 16), label: const Text('Exporter CSV')),
            const SizedBox(width: 8),
            AppBadge(
              _tabs.index == 0
                  ? 'Catalogue'
                  : _tabs.index == 1
                      ? '${stats.activeLoans} prêt(s) en cours'
                      : 'Contrôle des quitus',
              tone: AppTone.info,
              icon: Icons.verified_user_outlined,
            ),
          ]),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(icon: Icon(Icons.menu_book_outlined, size: 17), text: 'Catalogue'),
              Tab(icon: Icon(Icons.swap_horiz, size: 17), text: 'Prêts & retards'),
              Tab(icon: Icon(Icons.fact_check_outlined, size: 17), text: 'Quitus élèves'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _catalogueTab(),
                _loansTab(),
                _quitusTab(),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Onglet 1 : catalogue
  // ---------------------------------------------------------------------------

  Widget _catalogueTab() {
    final async = ref.watch(libraryCatalogueProvider);
    return async.when(
      data: (rows) {
        final filtered = rows.where((r) {
          return _matches(r.item.title) ||
              _matches(r.item.codeOrIsbn) ||
              _matches(r.item.authorOrCategory) ||
              _matches(r.item.copyCode) ||
              _matches(r.borrowerName) ||
              _matches(r.borrowerMatricule);
        }).toList();
        if (filtered.isEmpty) {
          return AppEmptyState(
            icon: Icons.menu_book_outlined,
            title: rows.isEmpty ? 'Catalogue vide' : 'Aucun ouvrage ne correspond à la recherche',
            message: rows.isEmpty
                ? 'Importez les données de test (Paramètres → Données de test) ou ajoutez un ouvrage.'
                : null,
            action: rows.isEmpty
                ? FilledButton(onPressed: _newItem, child: const Text('Ajouter un ouvrage'))
                : null,
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(children: [
                  Text('${filtered.length} ouvrage(s)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  AppBadge('${filtered.where((r) => !r.isBorrowed).length} disponible(s)',
                      tone: AppTone.success,
                      icon: Icons.check_circle_outline),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      showCheckboxColumn: false,
                      columns: const [
                        DataColumn(label: Text('Ouvrage')),
                        DataColumn(label: Text('Auteur / catégorie')),
                        DataColumn(label: Text('Exemplaire')),
                        DataColumn(label: Text('État')),
                        DataColumn(label: Text('Emprunteur')),
                        DataColumn(label: Text('Action')),
                      ],
                      rows: filtered.map((r) {
                        final item = r.item;
                        return DataRow(cells: [
                          DataCell(Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(item.title,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (item.codeOrIsbn != null)
                                Text(item.codeOrIsbn!,
                                    style: const TextStyle(
                                        fontSize: 10, fontFamily: 'monospace')),
                            ],
                          )),
                          DataCell(Text(item.authorOrCategory ?? '-')),
                          DataCell(Text(item.copyCode ?? '-')),
                          DataCell(AppBadge(
                            r.statusLabel,
                            tone: !r.isBorrowed
                                ? AppTone.success
                                : (r.overdue ? AppTone.danger : AppTone.warning),
                            icon: !r.isBorrowed
                                ? Icons.check_circle_outline
                                : (r.overdue ? Icons.error_outline : Icons.schedule),
                          )),
                          DataCell(r.isBorrowed
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(r.borrowerName ?? '—',
                                        style: const TextStyle(fontSize: 12)),
                                    Text(
                                      '${r.borrowerMatricule ?? ''} • échéance ${formatDateIso(r.dueDate)}',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: r.overdue
                                              ? const Color(0xFFDC2626)
                                              : null),
                                    ),
                                  ],
                                )
                              : const Text('—')),
                          DataCell(r.isBorrowed
                              ? OutlinedButton.icon(
                                  onPressed: () => _returnLoanByIds(
                                      r.loanId!, r.item.id, r.item.title),
                                  icon: const Icon(Icons.assignment_return_outlined, size: 15),
                                  label: const Text('Retour'),
                                )
                              : TextButton.icon(
                                  onPressed: _newLoan,
                                  icon: const Icon(Icons.swap_horiz, size: 15),
                                  label: const Text('Prêter'),
                                )),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Erreur chargement catalogue : $e\n(Vérifiez la permission library.read)')),
    );
  }

  // ---------------------------------------------------------------------------
  // Onglet 2 : prêts
  // ---------------------------------------------------------------------------

  Widget _loansTab() {
    final async = ref.watch(libraryLoansProvider);
    return async.when(
      data: (rows) {
        final counts = <String, int>{
          'Tous': rows.length,
          'En cours': rows.where((l) => !l.isReturned && !l.overdue).length,
          'En retard': rows.where((l) => l.overdue).length,
          'Retournés': rows.where((l) => l.isReturned).length,
        };
        final filtered = rows.where((l) {
          final okFilter = switch (_loanFilter) {
            'En cours' => !l.isReturned && !l.overdue,
            'En retard' => l.overdue,
            'Retournés' => l.isReturned,
            _ => true,
          };
          if (!okFilter) return false;
          return _matches(l.itemTitle) ||
              _matches(l.borrowerName) ||
              _matches(l.borrowerMatricule) ||
              _matches(l.classLabel);
        }).toList();

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final entry in counts.entries)
                ChoiceChip(
                  label: Text('${entry.key} (${entry.value})'),
                  selected: _loanFilter == entry.key,
                  onSelected: (_) => setState(() => _loanFilter = entry.key),
                ),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: filtered.isEmpty
                    ? AppEmptyState(
                        icon: Icons.library_books_outlined,
                        title: rows.isEmpty ? 'Aucun prêt enregistré' : 'Aucun prêt dans ce filtre',
                        message: rows.isEmpty
                            ? 'Importez les données de test ou créez un prêt depuis le catalogue.'
                            : null,
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Ouvrage')),
                              DataColumn(label: Text('Élève')),
                              DataColumn(label: Text('Classe')),
                              DataColumn(label: Text('Début')),
                              DataColumn(label: Text('Échéance')),
                              DataColumn(label: Text('Statut')),
                              DataColumn(label: Text('Action')),
                            ],
                            rows: filtered.map((l) {
                              final status = l.isReturned
                                  ? 'Retourné'
                                  : (l.overdue ? 'En retard' : 'En cours');
                              final tone = l.isReturned
                                  ? AppTone.neutral
                                  : (l.overdue ? AppTone.danger : AppTone.warning);
                              return DataRow(cells: [
                                DataCell(Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(l.itemTitle,
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                    if (l.copyCode != null)
                                      Text(l.copyCode!,
                                          style: const TextStyle(
                                              fontSize: 10, fontFamily: 'monospace')),
                                  ],
                                )),
                                DataCell(Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(l.borrowerName ?? '-'),
                                    if (l.borrowerMatricule != null)
                                      Text(l.borrowerMatricule!,
                                          style: const TextStyle(
                                              fontSize: 10, fontFamily: 'monospace')),
                                  ],
                                )),
                                DataCell(Text(l.classLabel ?? '-')),
                                DataCell(Text(formatDateIso(l.loan.startDate))),
                                DataCell(Text(formatDateIso(l.loan.dueDate),
                                    style: TextStyle(
                                        color: l.overdue ? const Color(0xFFDC2626) : null,
                                        fontWeight:
                                            l.overdue ? FontWeight.w700 : FontWeight.normal))),
                                DataCell(AppBadge(
                                  status,
                                  tone: tone,
                                  icon: l.isReturned
                                      ? Icons.assignment_turned_in_outlined
                                      : (l.overdue ? Icons.error_outline : Icons.schedule),
                                )),
                                DataCell(l.isReturned
                                    ? Text(formatDateIso(l.loan.returnDate),
                                        style: const TextStyle(fontSize: 11))
                                    : TextButton.icon(
                                        onPressed: () => _returnLoan(l),
                                        icon: const Icon(Icons.assignment_return_outlined,
                                            size: 15),
                                        label: const Text('Retour'),
                                      )),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
              ),
            ),
          ]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Erreur chargement prêts : $e\n(Vérifiez la permission library.read)')),
    );
  }

  // ---------------------------------------------------------------------------
  // Onglet 3 : quitus
  // ---------------------------------------------------------------------------

  Widget _quitusTab() {
    final async = ref.watch(libraryQuitusProvider(_includeAllStudents));
    return async.when(
      data: (rows) {
        final filtered = rows.where((r) {
          if (_query.isEmpty) return true;
          return _matches(r.fullName) || _matches(r.matricule) || _matches(r.classLabel);
        }).toList();
        final blocked = filtered.where((r) => !r.certificateReady).length;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              AppBadge('${filtered.length} élève(s)', tone: AppTone.info),
              const SizedBox(width: 8),
              AppBadge('$blocked certificat(s) bloqué(s)',
                  tone: blocked > 0 ? AppTone.danger : AppTone.success,
                  icon: blocked > 0 ? Icons.block : Icons.verified),
              const Spacer(),
              const Text('Afficher tous les élèves', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              Switch(
                value: _includeAllStudents,
                onChanged: (v) => setState(() => _includeAllStudents = v),
              ),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: filtered.isEmpty
                    ? AppEmptyState(
                        icon: Icons.verified_user_outlined,
                        title: rows.isEmpty
                            ? 'Aucun élève avec un prêt actif'
                            : 'Aucun élève ne correspond à la recherche',
                        message: rows.isEmpty
                            ? 'Activez « Afficher tous les élèves » pour contrôler les quitus de toute la scolarité.'
                            : null,
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Élève')),
                              DataColumn(label: Text('Classe')),
                              DataColumn(label: Text('Solde écolage')),
                              DataColumn(label: Text('Prêts')),
                              DataColumn(label: Text('Retards')),
                              DataColumn(label: Text('Quitus financier')),
                              DataColumn(label: Text('Quitus bibliothèque')),
                              DataColumn(label: Text('Certificat')),
                              DataColumn(label: Text('Documents')),
                            ],
                            rows: filtered.map((r) {
                              return DataRow(cells: [
                                DataCell(Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(r.fullName,
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text(r.matricule,
                                        style: const TextStyle(
                                            fontSize: 10, fontFamily: 'monospace')),
                                  ],
                                )),
                                DataCell(Text(r.classLabel ?? '-')),
                                DataCell(Text(
                                  formatMga(r.balanceMga),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: r.financeOk
                                          ? null
                                          : const Color(0xFFDC2626)),
                                )),
                                DataCell(Text('${r.activeLoans}')),
                                DataCell(Text('${r.overdueLoans}',
                                    style: TextStyle(
                                        fontWeight:
                                            r.overdueLoans > 0 ? FontWeight.w700 : null,
                                        color: r.overdueLoans > 0
                                            ? const Color(0xFFDC2626)
                                            : null))),
                                DataCell(AppBadge(
                                  r.financeOk ? 'Validé' : 'Impayé',
                                  tone: r.financeOk ? AppTone.success : AppTone.danger,
                                  icon: r.financeOk
                                      ? Icons.check_circle_outline
                                      : Icons.payments_outlined,
                                )),
                                DataCell(AppBadge(
                                  r.overdueLoans > 0
                                      ? 'Bloqué (retard)'
                                      : (r.activeLoans > 0 ? 'Prêt en cours' : 'OK'),
                                  tone: r.libraryOk ? AppTone.success : AppTone.danger,
                                  icon: r.libraryOk
                                      ? Icons.check_circle_outline
                                      : Icons.book_outlined,
                                )),
                                DataCell(AppBadge(
                                  r.certificateReady ? 'Délivrable' : 'Bloqué',
                                  tone: r.certificateReady ? AppTone.success : AppTone.warning,
                                  icon: r.certificateReady
                                      ? Icons.verified_outlined
                                      : Icons.block,
                                )),
                                DataCell(Wrap(spacing: 4, children: [
                                  IconButton(tooltip: 'Attestation', icon: const Icon(Icons.description_outlined, size: 18), onPressed: () => _generateStudentDoc(r, 'attestation', 'attestation')),
                                  IconButton(tooltip: 'Certificat', icon: const Icon(Icons.verified_outlined, size: 18), onPressed: () => _generateStudentDoc(r, 'certificat', 'certificat')),
                                ])),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
              ),
            ),
          ]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Erreur chargement quitus : $e\n(Vérifiez la permission students.read)')),
    );
  }
}
