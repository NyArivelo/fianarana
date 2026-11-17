import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/widgets/app_ui.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/core/security/permission_providers.dart';
import 'package:fianarana/features/facilities/application/facilities_providers.dart';
import 'package:fianarana/features/facilities/data/facilities_repository.dart';

/// Locaux & équipements : inventaire, capacité et occupation du planning.
class FacilitiesScreen extends ConsumerStatefulWidget {
  const FacilitiesScreen({super.key});

  @override
  ConsumerState<FacilitiesScreen> createState() => _FacilitiesScreenState();
}

class _FacilitiesScreenState extends ConsumerState<FacilitiesScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _kind = 'Tous';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _edit([FacilityRow? row]) async {
    final auth = ref.read(authControllerProvider);
    final nameCtrl = TextEditingController(text: row?.facility.name ?? '');
    final codeCtrl = TextEditingController(text: row?.facility.code ?? '');
    final categoryCtrl =
        TextEditingController(text: row?.facility.category ?? '');
    final capacityCtrl = TextEditingController(
        text:
            row?.facility.capacity == null ? '' : '${row!.facility.capacity}');
    var domain = row?.facility.domain ?? 'Locaux';
    var status = row?.facility.status ?? 'Disponible';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
              row == null ? 'Nouveau local / équipement' : 'Modifier le local'),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Désignation *'),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: codeCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Code (ex: SAL-B201)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: capacityCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Capacité (places)'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: categoryCtrl,
                decoration: const InputDecoration(
                    labelText:
                        'Catégorie / affectation (ex: Salle affectée (3ème 1))'),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: domain,
                    decoration: const InputDecoration(labelText: 'Domaine'),
                    items: const [
                      'Locaux',
                      'Laboratoires',
                      'Équipements',
                      'Bibliothèque'
                    ]
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => domain = v ?? 'Locaux'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Statut'),
                    items: const [
                      'Opérationnelle',
                      'Disponible',
                      'Occupé',
                      'En maintenance'
                    ]
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => status = v ?? 'Disponible'),
                  ),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La désignation est obligatoire.')));
      return;
    }
    try {
      await ref.read(facilitiesRepositoryProvider).save(
            id: row?.facility.id,
            domain: domain,
            name: name,
            code: codeCtrl.text.trim().isEmpty ? null : codeCtrl.text.trim(),
            category: categoryCtrl.text.trim().isEmpty
                ? null
                : categoryCtrl.text.trim(),
            capacity: int.tryParse(capacityCtrl.text.trim()),
            status: status,
            actorUserId: auth.userId,
            actorUsername: auth.username,
          );
      ref.invalidate(facilitiesListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(row == null ? 'Local ajouté.' : 'Local mis à jour.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur enregistrement : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(currentPermissionsProvider).valueOrNull ?? const <String>{};
    final canEdit = perms.contains('facilities.create') || perms.contains('facilities.update');
    final theme = Theme.of(context);
    final async = ref.watch(facilitiesListProvider);
    final rows = async.valueOrNull ?? const <FacilityRow>[];
    final stats = ref.read(facilitiesRepositoryProvider).stats(rows);

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF020617)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Locaux & équipements'),
        actions: [
          FilledButton.icon(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add_business_outlined, size: 16),
            label: const Text('Nouveau local'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            AppStatCard(
              icon: Icons.meeting_room_outlined,
              label: 'Locaux & équipements',
              value: '${stats.total}',
              tone: AppTone.info,
            ),
            AppStatCard(
              icon: Icons.groups_2_outlined,
              label: 'Capacité cumulée',
              value: '${formatNumber(stats.totalCapacity)} places',
              tone: AppTone.neutral,
            ),
            AppStatCard(
              icon: Icons.build_circle_outlined,
              label: 'Opérationnels',
              value: '${stats.functional}/${stats.total}',
              tone: stats.functional == stats.total
                  ? AppTone.success
                  : AppTone.warning,
            ),
            AppStatCard(
              icon: Icons.calendar_view_week_outlined,
              label: 'Séances hebdomadaires',
              value: '${stats.weeklySessions}',
              hint: 'Salles utilisées au planning',
              tone: AppTone.info,
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(
              width: 300,
              height: 38,
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: 'Rechercher un local, un code, une affectation...',
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
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final kind in const [
                    'Tous',
                    'Salles',
                    'Laboratoires',
                    'Équipements'
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(kind),
                        selected: _kind == kind,
                        onSelected: (_) => setState(() => _kind = kind),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            AppBadge('${rows.length} fiche(s)', tone: AppTone.neutral),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: async.when(
              data: (_) {
                final filtered = rows.where((r) {
                  final okKind = _kind == 'Tous' || r.kind == _kind;
                  if (!okKind) return false;
                  if (_query.isEmpty) return true;
                  return r.facility.name.toLowerCase().contains(_query) ||
                      (r.facility.code ?? '').toLowerCase().contains(_query) ||
                      (r.facility.category ?? '')
                          .toLowerCase()
                          .contains(_query);
                }).toList();
                if (filtered.isEmpty) {
                  return AppEmptyState(
                    icon: Icons.meeting_room_outlined,
                    title: rows.isEmpty
                        ? 'Aucun local enregistré'
                        : 'Aucun local dans ce filtre',
                    message: rows.isEmpty
                        ? 'Importez les données de test (Paramètres → Données de test) ou ajoutez un local.'
                        : null,
                    action: rows.isEmpty
                        ? FilledButton(
                            onPressed: () => _edit(),
                            child: const Text('Ajouter un local'))
                        : null,
                  );
                }
                return LayoutBuilder(builder: (context, constraints) {
                  const spacing = 12.0;
                  final columns =
                      (constraints.maxWidth / 300).floor().clamp(1, 5);
                  final width =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                          columns;
                  return SingleChildScrollView(
                    child: Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        for (final row in filtered)
                          SizedBox(width: width, child: _facilityCard(row)),
                      ],
                    ),
                  );
                });
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Text(
                      'Erreur chargement locaux : $e\n(Vérifiez la permission library.read)')),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _facilityCard(FacilityRow row) {
    final theme = Theme.of(context);
    final facility = row.facility;
    final maintenance = facility.status.toLowerCase().contains('maintenance');
    final occupied = facility.status.toLowerCase().contains('occup');
    final tone = maintenance
        ? AppTone.danger
        : (occupied ? AppTone.warning : AppTone.success);
    final icon = row.kind == 'Salles'
        ? Icons.meeting_room_outlined
        : row.kind == 'Laboratoires'
            ? Icons.science_outlined
            : Icons.sports_soccer_outlined;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _edit(row),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: appToneColors(context, AppTone.info).background,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon,
                    size: 18,
                    color: appToneColors(context, AppTone.info).foreground),
              ),
              const Spacer(),
              AppBadge(
                facility.status,
                tone: tone,
                icon: maintenance
                    ? Icons.build_outlined
                    : (occupied
                        ? Icons.event_busy_outlined
                        : Icons.check_circle_outline),
              ),
            ]),
            const SizedBox(height: 10),
            if (facility.code != null)
              Text(facility.code!,
                  style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary)),
            Text(facility.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(facility.category ?? '—',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            Divider(height: 1, color: theme.dividerColor),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Row(children: [
                  Icon(Icons.groups_outlined,
                      size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text('${facility.capacity ?? 0} places',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ),
                ]),
              ),
              Expanded(
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Icon(Icons.calendar_view_week_outlined,
                      size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text('${row.weeklySessions} séance(s)/sem.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ),
                ]),
              ),
            ]),
            if (row.assignedClass != null) ...[
              const SizedBox(height: 8),
              AppBadge('Classe : ${row.assignedClass}',
                  tone: AppTone.info, icon: Icons.school_outlined),
            ],
          ]),
        ),
      ),
    );
  }
}
