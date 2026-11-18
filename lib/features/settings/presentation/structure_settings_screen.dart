import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_providers.dart';
import 'package:fianarana/core/services/establishment_service.dart';
import 'package:fianarana/core/utils/csv_export.dart';
import 'package:fianarana/core/widgets/app_ui.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/settings/application/structure_providers.dart';

T? _firstOrNull<T>(Iterable<T> values) => values.isEmpty ? null : values.first;

/// Paramétrage de l'établissement et du référentiel pédagogique :
/// fiche établissement, années & périodes, niveaux (cycle/filière),
/// classes et matières avec coefficients.
class StructureSettingsScreen extends ConsumerStatefulWidget {
  const StructureSettingsScreen({super.key});

  @override
  ConsumerState<StructureSettingsScreen> createState() => _StructureSettingsScreenState();
}

class _StructureSettingsScreenState extends ConsumerState<StructureSettingsScreen> {
  String? _selectedYearId;

  ({String? id, String? username}) get _actor {
    final auth = ref.read(authControllerProvider);
    return (id: auth.userId, username: auth.username);
  }

  bool get _canEdit {
    final perms = ref.watch(currentPermissionsProvider).valueOrNull ?? const <String>{};
    return perms.contains('settings.update');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(schoolYearsProvider);
      ref.invalidate(periodsProvider);
      ref.invalidate(levelsProvider);
      ref.invalidate(classesStructureProvider);
      ref.invalidate(subjectsProvider);
      ref.invalidate(currentEstablishmentProvider);
    } catch (e) {
      _toast('Erreur : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = ref.watch(schoolYearsProvider);
    final yearList = years.valueOrNull ?? const <SchoolYear>[];
    final activeYearId = _selectedYearId ??
        (_firstOrNull(yearList.where((y) => y.status == 'En cours'))?.id ??
            _firstOrNull(yearList)?.id);

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Établissement & structure pédagogique'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(icon: Icon(Icons.apartment_outlined, size: 18), text: 'Établissement'),
            Tab(icon: Icon(Icons.event_available_outlined, size: 18), text: 'Années & périodes'),
            Tab(icon: Icon(Icons.stairs_outlined, size: 18), text: 'Niveaux'),
            Tab(icon: Icon(Icons.school_outlined, size: 18), text: 'Classes'),
            Tab(icon: Icon(Icons.menu_book_outlined, size: 18), text: 'Matières'),
          ]),
        ),
        body: TabBarView(children: [
          _EstablishmentTab(canEdit: _canEdit, onSaved: () => _guard(() async {})),
          _YearsTab(
            canEdit: _canEdit,
            selectedYearId: activeYearId,
            onSelectYear: (id) => setState(() => _selectedYearId = id),
            run: _guard,
            actor: _actor,
          ),
          _LevelsTab(canEdit: _canEdit, run: _guard, actor: _actor),
          _ClassesTab(canEdit: _canEdit, yearId: activeYearId, run: _guard, actor: _actor),
          _SubjectsTab(canEdit: _canEdit, run: _guard, actor: _actor),
        ]),
      ),
    );
  }
}

/// Affiche un dialogue de confirmation simple.
Future<bool> _confirm(BuildContext context, String title, String message) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmer')),
      ],
    ),
  );
  return ok == true;
}

class _EstablishmentTab extends ConsumerWidget {
  final bool canEdit;
  final VoidCallback onSaved;
  const _EstablishmentTab({required this.canEdit, required this.onSaved});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(currentEstablishmentProvider);
    return info.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur établissement : $e')),
      data: (data) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const AppPageHeader(
            title: 'Fiche de l\'établissement',
            subtitle: 'Ces informations alimentent l\'en-tête des reçus, bulletins, certificats et modèles de documents.',
          ),
          const SizedBox(height: 12),
          AppSectionCard(
            title: data.name,
            subtitle: 'Code ${data.code.isEmpty ? "-" : data.code} • Devise ${data.currency}',
            trailing: AppBadge(canEdit ? 'Modifiable' : 'Lecture seule',
                tone: canEdit ? AppTone.success : AppTone.warning),
            padding: const EdgeInsets.all(16),
            child: _EstablishmentForm(
              key: ValueKey('${data.id}-${data.name}-${data.code}'),
              info: data,
              canEdit: canEdit,
              onSaved: onSaved,
            ),
          ),
        ]),
      ),
    );
  }
}

class _EstablishmentForm extends ConsumerStatefulWidget {
  final EstablishmentInfo info;
  final bool canEdit;
  final VoidCallback onSaved;
  const _EstablishmentForm({super.key, required this.info, required this.canEdit, required this.onSaved});

  @override
  ConsumerState<_EstablishmentForm> createState() => _EstablishmentFormState();
}

class _EstablishmentFormState extends ConsumerState<_EstablishmentForm> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _motto;
  late final TextEditingController _currency;
  late final TextEditingController _legal;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final i = widget.info;
    _name = TextEditingController(text: i.name);
    _code = TextEditingController(text: i.code);
    _address = TextEditingController(text: i.address ?? '');
    _phone = TextEditingController(text: i.phone ?? '');
    _email = TextEditingController(text: i.email ?? '');
    _motto = TextEditingController(text: i.motto ?? '');
    _currency = TextEditingController(text: i.currency);
    _legal = TextEditingController(text: i.legalMentions ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name, _code, _address, _phone, _email, _motto, _currency, _legal]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Le nom de l\'établissement est obligatoire.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final auth = ref.read(authControllerProvider);
      await EstablishmentService(ref.read(appDatabaseProvider)).save(
        id: widget.info.id,
        name: _name.text,
        code: _code.text,
        address: _address.text,
        phone: _phone.text,
        email: _email.text,
        motto: _motto.text,
        currency: _currency.text,
        legalMentions: _legal.text,
      );
      await AuditServiceLocator.log(ref, auth.userId, auth.username,
          'Mise à jour de la fiche établissement : ${_name.text.trim()}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Établissement enregistré.')));
      widget.onSaved();
      ref.invalidate(currentEstablishmentProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: [
        Expanded(child: _field(_name, 'Nom de l\'établissement *')),
        const SizedBox(width: 8),
        SizedBox(width: 160, child: _field(_code, 'Code')),
        const SizedBox(width: 8),
        SizedBox(width: 110, child: _field(_currency, 'Devise')),
      ]),
      const SizedBox(height: 8),
      _field(_address, 'Adresse'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _field(_phone, 'Téléphone')),
        const SizedBox(width: 8),
        Expanded(child: _field(_email, 'E-mail')),
      ]),
      const SizedBox(height: 8),
      _field(_motto, 'Devise / slogan'),
      const SizedBox(height: 8),
      _field(_legal, 'Mentions légales', maxLines: 3),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: !widget.canEdit || _saving ? null : _save,
          icon: const Icon(Icons.save_outlined, size: 16),
          label: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
        ),
      ),
    ]);
  }

  Widget _field(TextEditingController c, String label, {int maxLines = 1}) {
    return TextField(
      controller: c,
      enabled: widget.canEdit && !_saving,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
    );
  }
}

/// Petit utilitaire d'audit pour les écrans de paramétrage.
class AuditServiceLocator {
  static Future<void> log(WidgetRef ref, String? userId, String? username, String description) async {
    // L'audit est déjà journalisé par StructureRepository pour le référentiel.
    // Pour la fiche établissement, on écrit une entrée dédiée.
    final db = ref.read(appDatabaseProvider);
    await AuditService(db).log(
      userId: userId,
      username: username,
      module: 'Structure',
      targetObject: 'Établissement',
      description: description,
      result: 'Succès',
    );
  }
}

class _YearsTab extends ConsumerWidget {
  final bool canEdit;
  final String? selectedYearId;
  final ValueChanged<String?> onSelectYear;
  final Future<void> Function(Future<void> Function()) run;
  final ({String? id, String? username}) actor;

  const _YearsTab({
    required this.canEdit,
    required this.selectedYearId,
    required this.onSelectYear,
    required this.run,
    required this.actor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final years = ref.watch(schoolYearsProvider);
    final periods = ref.watch(periodsProvider(selectedYearId));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppPageHeader(
          title: 'Années scolaires & périodes',
          subtitle: 'Ouverture, clôture des périodes et calendrier annuel.',
          actions: [
            FilledButton.icon(
              onPressed: !canEdit ? null : () => _editYear(context, ref, null),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nouvelle année'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: years.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Erreur : $e')),
            data: (list) {
              if (list.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'Aucune année scolaire',
                  message: 'Créez une année scolaire pour ouvrir les périodes et les classes.',
                );
              }
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  flex: 2,
                  child: ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final y = list[i];
                      final selected = y.id == selectedYearId;
                      return Card(
                        color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
                        child: ListTile(
                          leading: const Icon(Icons.event_note_outlined),
                          title: Text(y.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${y.code} • ${_date(y.startDate)} → ${_date(y.endDate)}'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            AppBadge(y.status, tone: y.status == 'En cours' ? AppTone.success : AppTone.neutral),
                            IconButton(
                              tooltip: 'Modifier',
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: !canEdit ? null : () => _editYear(context, ref, y),
                            ),
                            IconButton(
                              tooltip: 'Archiver',
                              icon: const Icon(Icons.archive_outlined, size: 18),
                              onPressed: !canEdit ? null : () async {
                                if (!await _confirm(context, 'Archiver l\'année ?', y.label)) return;
                                await run(() => ref.read(structureRepositoryProvider).archive(
                                  entity: 'school_year', id: y.id,
                                  actorUserId: actor.id, actorUsername: actor.username));
                              },
                            ),
                          ]),
                          onTap: () => onSelectYear(y.id),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: AppSectionCard(
                    title: 'Périodes${selectedYearId == null ? '' : ' de l\'année sélectionnée'}',
                    subtitle: 'Trimestres / semestres, dates et état de clôture.',
                    trailing: FilledButton.icon(
                      onPressed: (!canEdit || selectedYearId == null)
                          ? null
                          : () => _editPeriod(context, ref, null),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Nouvelle période'),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: periods.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Erreur : $e'),
                      data: (list) => list.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('Aucune période définie pour cette année.'),
                            )
                          : Column(children: [
                              for (final p in list)
                                ListTile(
                                  dense: true,
                                  leading: CircleAvatar(radius: 14, child: Text('${p.sequence}')),
                                  title: Text(p.name),
                                  subtitle: Text('${_date(p.startDate)} → ${_date(p.endDate)}'),
                                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                    AppBadge(p.isClosed ? 'Clôturée' : 'Ouverte',
                                        tone: p.isClosed ? AppTone.warning : AppTone.success),
                                    IconButton(
                                      tooltip: 'Modifier',
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      onPressed: !canEdit ? null : () => _editPeriod(context, ref, p),
                                    ),
                                    IconButton(
                                      tooltip: p.isClosed ? 'Réouvrir' : 'Clôturer',
                                      icon: Icon(p.isClosed ? Icons.lock_open_outlined : Icons.lock_outline, size: 18),
                                      onPressed: !canEdit ? null : () async {
                                        if (!await _confirm(context,
                                            p.isClosed ? 'Réouvrir la période ?' : 'Clôturer la période ?',
                                            '${p.name} — les notes resteront consultables.')) return;
                                        await run(() => ref.read(structureRepositoryProvider).togglePeriodClosed(
                                          id: p.id, isClosed: !p.isClosed,
                                          actorUserId: actor.id, actorUsername: actor.username));
                                      },
                                    ),
                                  ]),
                                ),
                            ]),
                    ),
                  ),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _editYear(BuildContext context, WidgetRef ref, SchoolYear? year) async {
    final code = TextEditingController(text: year?.code ?? '');
    final label = TextEditingController(text: year?.label ?? '');
    var start = year?.startDate ?? DateTime(DateTime.now().year, 9, 1);
    var end = year?.endDate ?? DateTime(DateTime.now().year + 1, 6, 30);
    var status = year?.status ?? 'En cours';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        String d(DateTime x) => '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}/${x.year}';
        return AlertDialog(
          title: Text(year == null ? 'Nouvelle année scolaire' : 'Modifier l\'année'),
          content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: code, decoration: const InputDecoration(labelText: 'Code (ex: 2026-2027) *')),
            const SizedBox(height: 8),
            TextField(controller: label, decoration: const InputDecoration(labelText: 'Libellé *')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () async {
                final p = await showDatePicker(context: ctx, initialDate: start, firstDate: DateTime(2015), lastDate: DateTime(2100));
                if (p != null) setD(() => start = p);
              }, child: Text('Début : ${d(start)}'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: () async {
                final p = await showDatePicker(context: ctx, initialDate: end, firstDate: DateTime(2015), lastDate: DateTime(2100));
                if (p != null) setD(() => end = p);
              }, child: Text('Fin : ${d(end)}'))),
            ]),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Statut'),
              items: const ['En cours', 'Planifiée', 'Clôturée']
                  .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setD(() => status = v ?? status),
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        );
      }),
    );
    if (ok != true) return;
    await run(() => ref.read(structureRepositoryProvider).saveYear(
      id: year?.id, code: code.text, label: label.text, startDate: start, endDate: end,
      status: status, actorUserId: actor.id, actorUsername: actor.username));
  }

  Future<void> _editPeriod(BuildContext context, WidgetRef ref, Period? period) async {
    final name = TextEditingController(text: period?.name ?? '');
    final sequence = TextEditingController(text: '${period?.sequence ?? 1}');
    var start = period?.startDate;
    var end = period?.endDate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        String d(DateTime? x) => x == null ? 'Non définie' : '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}/${x.year}';
        return AlertDialog(
          title: Text(period == null ? 'Nouvelle période' : 'Modifier la période'),
          content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Libellé (ex: Trimestre 1) *')),
            const SizedBox(height: 8),
            TextField(controller: sequence, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Ordre')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () async {
                final p = await showDatePicker(context: ctx, initialDate: start ?? DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(2100));
                if (p != null) setD(() => start = p);
              }, child: Text('Début : ${d(start)}'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: () async {
                final p = await showDatePicker(context: ctx, initialDate: end ?? DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(2100));
                if (p != null) setD(() => end = p);
              }, child: Text('Fin : ${d(end)}'))),
            ]),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        );
      }),
    );
    if (ok != true || selectedYearId == null) return;
    await run(() => ref.read(structureRepositoryProvider).savePeriod(
      id: period?.id, schoolYearId: selectedYearId!, name: name.text,
      sequence: int.tryParse(sequence.text) ?? 1, startDate: start, endDate: end,
      actorUserId: actor.id, actorUsername: actor.username));
  }
}

String _date(DateTime? d) =>
    d == null ? '-' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class _LevelsTab extends ConsumerWidget {
  final bool canEdit;
  final Future<void> Function(Future<void> Function()) run;
  final ({String? id, String? username}) actor;
  const _LevelsTab({required this.canEdit, required this.run, required this.actor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levels = ref.watch(levelsProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppPageHeader(
          title: 'Niveaux, cycles et filières',
          subtitle: 'Secondaire 2 / 3, tronc commun, séries — base du calcul des coefficients.',
          actions: [
            OutlinedButton.icon(
              onPressed: () => CsvExport.export(
                filename: 'niveaux.csv',
                headers: const ['Nom', 'Cycle', 'Filière', 'Ordre'],
                rows: (levels.valueOrNull ?? const <Level>[])
                    .map((l) => [l.name, l.cycle ?? '', l.track ?? '', '${l.sequence}']).toList(),
              ),
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Exporter'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: !canEdit ? null : () => _edit(context, ref, null),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nouveau niveau'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(child: levels.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur : $e')),
          data: (list) => list.isEmpty
              ? const AppEmptyState(icon: Icons.stairs_outlined, title: 'Aucun niveau', message: 'Ajoutez les niveaux de l\'établissement.')
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final l = list[i];
                    return Card(child: ListTile(
                      leading: CircleAvatar(radius: 16, child: Text('${l.sequence}')),
                      title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Cycle : ${l.cycle ?? "-"} • Filière : ${l.track ?? "-"}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: !canEdit ? null : () => _edit(context, ref, l)),
                        IconButton(icon: const Icon(Icons.archive_outlined, size: 18),
                            onPressed: !canEdit ? null : () async {
                              if (!await _confirm(context, 'Archiver le niveau ?', l.name)) return;
                              await run(() => ref.read(structureRepositoryProvider).archive(
                                entity: 'level', id: l.id, actorUserId: actor.id, actorUsername: actor.username));
                            }),
                      ]),
                    ));
                  },
                ),
        )),
      ]),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Level? level) async {
    final name = TextEditingController(text: level?.name ?? '');
    final cycle = TextEditingController(text: level?.cycle ?? '');
    final track = TextEditingController(text: level?.track ?? '');
    final sequence = TextEditingController(text: '${level?.sequence ?? 0}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(level == null ? 'Nouveau niveau' : 'Modifier le niveau'),
        content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom (ex: 3ème) *')),
          const SizedBox(height: 8),
          TextField(controller: cycle, decoration: const InputDecoration(labelText: 'Cycle (ex: Secondaire 2)')),
          const SizedBox(height: 8),
          TextField(controller: track, decoration: const InputDecoration(labelText: 'Filière / série (ex: Tronc commun)')),
          const SizedBox(height: 8),
          TextField(controller: sequence, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Ordre d\'affichage')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isEmpty) return;
    await run(() => ref.read(structureRepositoryProvider).saveLevel(
      id: level?.id, name: name.text, cycle: cycle.text.isEmpty ? null : cycle.text,
      track: track.text.isEmpty ? null : track.text, sequence: int.tryParse(sequence.text) ?? 0,
      actorUserId: actor.id, actorUsername: actor.username));
  }
}

class _ClassesTab extends ConsumerWidget {
  final bool canEdit;
  final String? yearId;
  final Future<void> Function(Future<void> Function()) run;
  final ({String? id, String? username}) actor;
  const _ClassesTab({required this.canEdit, required this.yearId, required this.run, required this.actor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(classesStructureProvider(yearId));
    final levels = ref.watch(levelsProvider).valueOrNull ?? const <Level>[];
    Map<String, String> levelNames = {for (final l in levels) l.id: l.name};
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppPageHeader(
          title: 'Classes',
          subtitle: yearId == null
              ? 'Sélectionnez une année scolaire dans l\'onglet « Années & périodes ».'
              : 'Classes de l\'année sélectionnée, effectif et salle de référence.',
          actions: [
            FilledButton.icon(
              onPressed: (!canEdit || yearId == null) ? null : () => _edit(context, ref, null),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nouvelle classe'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(child: classes.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur : $e')),
          data: (list) => list.isEmpty
              ? const AppEmptyState(icon: Icons.school_outlined, title: 'Aucune classe', message: 'Créez les classes de l\'année scolaire.')
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final c = list[i];
                    return Card(child: ListTile(
                      leading: const Icon(Icons.class_outlined),
                      title: Text(c.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Code : ${c.code ?? "-"} • Niveau : ${levelNames[c.levelId] ?? "-"} • '
                          'Capacité : ${c.capacity ?? "-"} • Salle : ${c.room ?? "-"}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: !canEdit ? null : () => _edit(context, ref, c)),
                        IconButton(icon: const Icon(Icons.archive_outlined, size: 18),
                            onPressed: !canEdit ? null : () async {
                              if (!await _confirm(context, 'Archiver la classe ?', c.label)) return;
                              await run(() => ref.read(structureRepositoryProvider).archive(
                                entity: 'class', id: c.id, actorUserId: actor.id, actorUsername: actor.username));
                            }),
                      ]),
                    ));
                  },
                ),
        )),
      ]),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, ClassesData? clazz) async {
    final cachedLevels = ref.read(levelsProvider).valueOrNull;
    final List<Level> levels = cachedLevels ?? await ref.read(levelsProvider.future);
    final label = TextEditingController(text: clazz?.label ?? '');
    final code = TextEditingController(text: clazz?.code ?? '');
    final capacity = TextEditingController(text: clazz?.capacity?.toString() ?? '');
    final room = TextEditingController(text: clazz?.room ?? '');
    String? levelId = clazz?.levelId ?? _firstOrNull(levels)?.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: Text(clazz == null ? 'Nouvelle classe' : 'Modifier la classe'),
        content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: label, decoration: const InputDecoration(labelText: 'Libellé (ex: 3ème 1) *')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: code, decoration: const InputDecoration(labelText: 'Code'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: capacity, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Capacité'))),
          ]),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: levelId,
            decoration: const InputDecoration(labelText: 'Niveau'),
            items: levels.map((l) => DropdownMenuItem(value: l.id, child: Text(l.name))).toList(),
            onChanged: (v) => setD(() => levelId = v),
          ),
          const SizedBox(height: 8),
          TextField(controller: room, decoration: const InputDecoration(labelText: 'Salle')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      )),
    );
    if (ok != true || label.text.trim().isEmpty || yearId == null) return;
    await run(() => ref.read(structureRepositoryProvider).saveClass(
      id: clazz?.id, schoolYearId: yearId, levelId: levelId, code: code.text,
      label: label.text, capacity: int.tryParse(capacity.text), room: room.text,
      actorUserId: actor.id, actorUsername: actor.username));
  }
}

class _SubjectsTab extends ConsumerWidget {
  final bool canEdit;
  final Future<void> Function(Future<void> Function()) run;
  final ({String? id, String? username}) actor;
  const _SubjectsTab({required this.canEdit, required this.run, required this.actor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(subjectsProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppPageHeader(
          title: 'Matières & coefficients',
          subtitle: 'Coefficients par cycle (secondaire 2 et 3), domaine disciplinaire.',
          actions: [
            OutlinedButton.icon(
              onPressed: () => CsvExport.export(
                filename: 'matieres.csv',
                headers: const ['Code', 'Matière', 'Coef. Sec2', 'Coef. Sec3', 'Domaine'],
                rows: (subjects.valueOrNull ?? const <Subject>[])
                    .map((s) => [s.code, s.name, '${s.coefficientSec2}', '${s.coefficientSec3}', s.domain ?? '']).toList(),
              ),
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Exporter'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: !canEdit ? null : () => _edit(context, ref, null),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nouvelle matière'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(child: subjects.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur : $e')),
          data: (list) => list.isEmpty
              ? const AppEmptyState(icon: Icons.menu_book_outlined, title: 'Aucune matière', message: 'Ajoutez les matières et leurs coefficients.')
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final s = list[i];
                    return Card(child: ListTile(
                      leading: AppBadge(s.code, tone: AppTone.info),
                      title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Sec2 ×${s.coefficientSec2} • Sec3 ×${s.coefficientSec3} • ${s.domain ?? "Général"}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: !canEdit ? null : () => _edit(context, ref, s)),
                        IconButton(icon: const Icon(Icons.archive_outlined, size: 18),
                            onPressed: !canEdit ? null : () async {
                              if (!await _confirm(context, 'Archiver la matière ?', s.name)) return;
                              await run(() => ref.read(structureRepositoryProvider).archive(
                                entity: 'subject', id: s.id, actorUserId: actor.id, actorUsername: actor.username));
                            }),
                      ]),
                    ));
                  },
                ),
        )),
      ]),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Subject? subject) async {
    final code = TextEditingController(text: subject?.code ?? '');
    final name = TextEditingController(text: subject?.name ?? '');
    final c2 = TextEditingController(text: '${subject?.coefficientSec2 ?? 1}');
    final c3 = TextEditingController(text: '${subject?.coefficientSec3 ?? 1}');
    final domain = TextEditingController(text: subject?.domain ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(subject == null ? 'Nouvelle matière' : 'Modifier la matière'),
        content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            SizedBox(width: 120, child: TextField(controller: code, decoration: const InputDecoration(labelText: 'Code *'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom *'))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: c2, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Coef. Secondaire 2'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: c3, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Coef. Secondaire 3'))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: domain, decoration: const InputDecoration(labelText: 'Domaine')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok != true || code.text.trim().isEmpty || name.text.trim().isEmpty) return;
    await run(() => ref.read(structureRepositoryProvider).saveSubject(
      id: subject?.id, code: code.text, name: name.text,
      coefficientSec2: double.tryParse(c2.text.replaceAll(',', '.')) ?? 1,
      coefficientSec3: double.tryParse(c3.text.replaceAll(',', '.')) ?? 1,
      domain: domain.text.isEmpty ? null : domain.text,
      actorUserId: actor.id, actorUsername: actor.username));
  }
}
