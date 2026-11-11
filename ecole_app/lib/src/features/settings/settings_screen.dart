import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../../core/security/current_user_scope.dart';
import '../academics/academics_structure_screen.dart';
import '../admin/admin_screen.dart';
import 'backup_tab.dart';
import 'settings_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(currentUserScopeProvider).valueOrNull?.scope ?? 'global';
    final isGlobal = scope == 'global';
    final tabs = <Tab>[
      const Tab(text: 'Établissement'),
      const Tab(text: 'Années scolaires & Périodes'),
      const Tab(text: 'Structure pédagogique'),
      if (isGlobal) const Tab(text: 'Sécurité & Administration'),
      if (isGlobal) const Tab(text: 'Sauvegarde & Restauration'),
    ];
    final views = <Widget>[
      const _SchoolSettingsTab(),
      const _AcademicYearsTab(),
      const AcademicsStructureTab(),
      if (isGlobal) const AdminSecurityTab(),
      if (isGlobal) const BackupRestoreTab(),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(isScrollable: true, tabs: tabs),
          ),
          Expanded(child: TabBarView(children: views)),
        ],
      ),
    );
  }
}

class _SchoolSettingsTab extends ConsumerStatefulWidget {
  const _SchoolSettingsTab();

  @override
  ConsumerState<_SchoolSettingsTab> createState() => _SchoolSettingsTabState();
}

class _SchoolSettingsTabState extends ConsumerState<_SchoolSettingsTab> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _motto = TextEditingController();
  final _timezone = TextEditingController(text: 'UTC');
  final _dateFormat = TextEditingController(text: 'dd/MM/yyyy');
  final _timeFormat = TextEditingController(text: 'HH:mm');
  final _legal = TextEditingController();
  String? _id;
  bool _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _email.dispose();
    _motto.dispose();
    _timezone.dispose();
    _dateFormat.dispose();
    _timeFormat.dispose();
    _legal.dispose();
    super.dispose();
  }

  void _fill(SchoolSetting? s) {
    if (_loaded) return;
    if (s != null) {
      _id = s.id;
      _name.text = s.name;
      _address.text = s.address ?? '';
      _phone.text = s.phone ?? '';
      _email.text = s.email ?? '';
      _motto.text = s.motto ?? '';
      _timezone.text = s.timezone;
      _dateFormat.text = s.dateFormat;
      _timeFormat.text = s.timeFormat;
      _legal.text = s.legalMentions ?? '';
    }
    _loaded = true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(settingsRepositoryProvider).saveSchoolSetting(
          id: _id,
          name: _name.text.trim(),
          address: _address.text.trim().isEmpty ? null : _address.text.trim(),
          phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          motto: _motto.text.trim().isEmpty ? null : _motto.text.trim(),
          timezone: _timezone.text.trim(),
          dateFormat: _dateFormat.text.trim(),
          timeFormat: _timeFormat.text.trim(),
          legalMentions: _legal.text.trim().isEmpty ? null : _legal.text.trim(),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paramètres de l\'établissement enregistrés')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingAsync = ref.watch(schoolSettingProvider);
    return settingAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e')),
      data: (setting) {
        _fill(setting);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fiche de l\'établissement',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _field(_name, 'Nom de l\'établissement *', width: 420,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Requis'
                              : null),
                      _field(_motto, 'Devise', width: 420),
                      _field(_address, 'Adresse', width: 420),
                      _field(_phone, 'Téléphone', width: 200),
                      _field(_email, 'Courriel', width: 240),
                      _field(_timezone, 'Fuseau horaire', width: 200),
                      _field(_dateFormat, 'Format de date', width: 200),
                      _field(_timeFormat, 'Format d\'heure', width: 200),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _legal,
                    decoration: const InputDecoration(
                      labelText: 'Mentions légales (documents)',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Enregistrer'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _field(TextEditingController c, String label,
      {double width = 300, String? Function(String?)? validator}) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: c,
        decoration: InputDecoration(labelText: label),
        validator: validator,
      ),
    );
  }
}

class _AcademicYearsTab extends ConsumerWidget {
  const _AcademicYearsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yearsAsync = ref.watch(academicYearsProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Années scolaires',
                  style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _showYearDialog(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Nouvelle année'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: yearsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erreur: $e')),
              data: (years) {
                if (years.isEmpty) {
                  return const Center(
                      child: Text('Aucune année scolaire. Créez-en une.'));
                }
                return ListView.separated(
                  itemCount: years.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _YearCard(year: years[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _showYearDialog(BuildContext context, WidgetRef ref,
      {AcademicYear? year}) async {
    final label = TextEditingController(text: year?.label ?? '');
    DateTime start = year?.startDate ?? DateTime(DateTime.now().year, 9, 1);
    DateTime end = year?.endDate ?? DateTime(DateTime.now().year + 1, 7, 31);
    bool isCurrent = year?.isCurrent ?? false;
    final fmt = DateFormat('dd/MM/yyyy');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(year == null ? 'Nouvelle année scolaire' : 'Modifier l\'année'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  decoration:
                      const InputDecoration(labelText: 'Libellé (ex: 2025-2026)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: start,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) setState(() => start = d);
                        },
                        child: Text('Début: ${fmt.format(start)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: end,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) setState(() => end = d);
                        },
                        child: Text('Fin: ${fmt.format(end)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: isCurrent,
                  onChanged: (v) => setState(() => isCurrent = v ?? false),
                  title: const Text('Année en cours'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                if (label.text.trim().isEmpty) return;
                await ref.read(settingsRepositoryProvider).upsertAcademicYear(
                      id: year?.id,
                      label: label.text.trim(),
                      startDate: start,
                      endDate: end,
                      isCurrent: isCurrent,
                    );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _YearCard extends ConsumerWidget {
  final AcademicYear year;
  const _YearCard({required this.year});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('dd/MM/yyyy');
    final periodsAsync = ref.watch(periodsProvider(year.id));
    return Card(
      child: ExpansionTile(
        title: Row(
          children: [
            Text(year.label, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (year.isCurrent) ...[
              const SizedBox(width: 8),
              const Chip(label: Text('En cours'), visualDensity: VisualDensity.compact),
            ],
            if (year.isClosed) ...[
              const SizedBox(width: 8),
              const Chip(label: Text('Clôturée'), visualDensity: VisualDensity.compact),
            ],
          ],
        ),
        subtitle: Text('${fmt.format(year.startDate)} → ${fmt.format(year.endDate)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Modifier',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _AcademicYearsTab._showYearDialog(context, ref, year: year),
            ),
            if (!year.isCurrent)
              IconButton(
                tooltip: 'Définir comme année en cours',
                icon: const Icon(Icons.star_outline),
                onPressed: () => ref.read(settingsRepositoryProvider).setCurrentYear(year.id),
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Périodes', style: TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _showPeriodDialog(context, ref, year.id),
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter une période'),
                    ),
                  ],
                ),
                periodsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Erreur: $e'),
                  data: (periods) {
                    if (periods.isEmpty) {
                      return const Text('Aucune période définie.');
                    }
                    return Column(
                      children: [
                        for (final p in periods)
                          ListTile(
                            dense: true,
                            leading: CircleAvatar(radius: 14, child: Text('${p.orderIndex}')),
                            title: Text(p.name),
                            subtitle: Text(p.isClosed ? 'Clôturée' : 'Ouverte'),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  tooltip: p.isClosed ? 'Rouvrir' : 'Clôturer',
                                  icon: Icon(p.isClosed ? Icons.lock_open : Icons.lock_outline),
                                  onPressed: () => ref
                                      .read(settingsRepositoryProvider)
                                      .setPeriodClosed(p.id, !p.isClosed),
                                ),
                                IconButton(
                                  tooltip: 'Supprimer',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => ref
                                      .read(settingsRepositoryProvider)
                                      .deletePeriod(p.id),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _showPeriodDialog(
      BuildContext context, WidgetRef ref, String academicYearId,
      {Period? period}) async {
    final name = TextEditingController(text: period?.name ?? '');
    final order = TextEditingController(text: '${period?.orderIndex ?? 1}');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(period == null ? 'Nouvelle période' : 'Modifier la période'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: 'Nom (ex: Trimestre 1, Semestre 1)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: order,
                decoration: const InputDecoration(labelText: 'Ordre'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await ref.read(settingsRepositoryProvider).upsertPeriod(
                    id: period?.id,
                    academicYearId: academicYearId,
                    name: name.text.trim(),
                    orderIndex: int.tryParse(order.text) ?? 1,
                  );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}
