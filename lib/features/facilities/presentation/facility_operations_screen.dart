import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/security/permission_providers.dart';
import 'package:fianarana/core/widgets/app_ui.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/facilities/application/facilities_providers.dart';
import 'package:fianarana/features/facilities/data/facilities_repository.dart';

/// Réservations de locaux et fiches de maintenance.
class FacilityOperationsScreen extends ConsumerStatefulWidget {
  const FacilityOperationsScreen({super.key});

  @override
  ConsumerState<FacilityOperationsScreen> createState() => _FacilityOperationsScreenState();
}

class _FacilityOperationsScreenState extends ConsumerState<FacilityOperationsScreen> {
  ({String? id, String? username}) get _actor {
    final auth = ref.read(authControllerProvider);
    return (id: auth.userId, username: auth.username);
  }

  Set<String> get _perms => ref.watch(currentPermissionsProvider).valueOrNull ?? const <String>{};
  bool get _canCreate => _perms.contains('facilities.create');
  bool get _canUpdate => _perms.contains('facilities.update');

  void _refresh() {
    ref.invalidate(facilityReservationsProvider);
    ref.invalidate(facilityMaintenanceProvider);
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Réservations & maintenance'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.event_available_outlined, size: 18), text: 'Réservations'),
            Tab(icon: Icon(Icons.build_outlined, size: 18), text: 'Maintenance'),
          ]),
        ),
        body: TabBarView(children: [
          _reservationsTab(),
          _maintenanceTab(),
        ]),
      ),
    );
  }

  Future<List<Facility>> _facilities() async {
    final rows = await ref.read(facilitiesListProvider.future);
    return rows.map((r) => r.facility).toList();
  }

  Widget _reservationsTab() {
    final reservations = ref.watch(facilityReservationsProvider);
    final facilities = ref.watch(facilitiesListProvider).valueOrNull ?? const <FacilityRow>[];
    final names = {for (final f in facilities) f.facility.id: f.facility.name};
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppPageHeader(
          title: 'Réservations de locaux et équipements',
          subtitle: 'Créneaux datés, validation et contrôle automatique des conflits.',
          actions: [
            FilledButton.icon(
              onPressed: _canCreate ? () => _editReservation(null, names.keys.toList()) : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nouvelle réservation'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(child: reservations.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur : $e')),
          data: (list) => list.isEmpty
              ? const AppEmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'Aucune réservation',
                  message: 'Réservez une salle, un laboratoire ou du matériel pour un événement.',
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final r = list[i];
                    final tone = r.status == 'Validée'
                        ? AppTone.success
                        : r.status == 'Refusée' || r.status == 'Annulée'
                            ? AppTone.danger
                            : AppTone.warning;
                    return Card(child: ListTile(
                      leading: const Icon(Icons.meeting_room_outlined),
                      title: Text('${r.title} — ${names[r.facilityId] ?? 'Local'}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${formatDateFr(r.startDate)} ${_hm(r.startDate)} → '
                          '${formatDateFr(r.endDate)} ${_hm(r.endDate)}'
                          '${r.purpose == null ? '' : '\n${r.purpose}'}'),
                      isThreeLine: r.purpose != null,
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        AppBadge(r.status, tone: tone),
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: _canUpdate ? () => _editReservation(r, names.keys.toList()) : null),
                        if (r.status != 'Annulée')
                          IconButton(
                            tooltip: 'Annuler',
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            onPressed: _canUpdate
                                ? () => _run(() => ref.read(facilitiesRepositoryProvider).cancelReservation(
                                      id: r.id, actorUserId: _actor.id, actorUsername: _actor.username),
                                      success: 'Réservation annulée.')
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

  Future<void> _editReservation(FacilityReservation? existing, List<String> facilityIds) async {
    final facilities = await _facilities();
    if (facilities.isEmpty || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun local ou équipement enregistré.')));
      return;
    }
    String? facilityId = existing?.facilityId ?? facilities.first.id;
    final title = TextEditingController(text: existing?.title ?? '');
    final purpose = TextEditingController(text: existing?.purpose ?? '');
    var start = existing?.startDate ?? DateTime.now().add(const Duration(hours: 1));
    var end = existing?.endDate ?? DateTime.now().add(const Duration(hours: 2));
    var status = existing?.status ?? 'Demandée';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: Text(existing == null ? 'Nouvelle réservation' : 'Modifier la réservation'),
        content: SizedBox(width: 620, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: facilityId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Local / équipement *'),
            items: facilities.map((f) => DropdownMenuItem(
              value: f.id, child: Text('${f.name}${f.code == null ? '' : ' (${f.code})'}', overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (v) => setD(() => facilityId = v),
          ),
          const SizedBox(height: 8),
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Objet *')),
          const SizedBox(height: 8),
          TextField(controller: purpose, maxLines: 2, decoration: const InputDecoration(labelText: 'Usage prévu')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(context: ctx, initialDate: start, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d == null) return;
                final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(start));
                if (t == null) return;
                setD(() => start = DateTime(d.year, d.month, d.day, t.hour, t.minute));
              },
              icon: const Icon(Icons.play_arrow_outlined, size: 16),
              label: Text('Début : ${formatDateFr(start)} ${_hm(start)}'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(context: ctx, initialDate: end, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d == null) return;
                final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(end));
                if (t == null) return;
                setD(() => end = DateTime(d.year, d.month, d.day, t.hour, t.minute));
              },
              icon: const Icon(Icons.stop_outlined, size: 16),
              label: Text('Fin : ${formatDateFr(end)} ${_hm(end)}'),
            ),
            DropdownButton<String>(
              value: status,
              items: const ['Demandée', 'Validée', 'Refusée', 'Annulée', 'Terminée']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setD(() => status = v ?? status),
            ),
          ]),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      )),
    );
    if (ok != true || facilityId == null || title.text.trim().isEmpty) return;
    await _run(() => ref.read(facilitiesRepositoryProvider).saveReservation(
          id: existing?.id,
          facilityId: facilityId!,
          title: title.text,
          purpose: purpose.text.isEmpty ? null : purpose.text,
          startDate: start,
          endDate: end,
          status: status,
          actorUserId: _actor.id,
          actorUsername: _actor.username,
        ), success: 'Réservation enregistrée.');
  }

  Widget _maintenanceTab() {
    final maintenance = ref.watch(facilityMaintenanceProvider);
    final facilities = ref.watch(facilitiesListProvider).valueOrNull ?? const <FacilityRow>[];
    final names = {for (final f in facilities) f.facility.id: f.facility.name};
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppPageHeader(
          title: 'Maintenance des locaux & équipements',
          subtitle: 'Interventions préventives et correctives, coûts et prestataires.',
          actions: [
            FilledButton.icon(
              onPressed: _canCreate ? () => _editMaintenance(null) : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nouvelle intervention'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(child: maintenance.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur : $e')),
          data: (list) => list.isEmpty
              ? const AppEmptyState(
                  icon: Icons.build_outlined,
                  title: 'Aucune intervention',
                  message: 'Planifiez la maintenance préventive et suivez les réparations.',
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final m = list[i];
                    final tone = m.status == 'Terminée'
                        ? AppTone.success
                        : m.status == 'En cours'
                            ? AppTone.warning
                            : AppTone.info;
                    return Card(child: ListTile(
                      leading: Icon(m.type == 'Préventive' ? Icons.event_repeat_outlined : Icons.handyman_outlined),
                      title: Text('${m.description} — ${names[m.facilityId] ?? 'Local'}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${m.type} • ${formatDateFr(m.startDate)}'
                          '${m.endDate == null ? '' : ' → ${formatDateFr(m.endDate)}'}'
                          '${m.provider == null ? '' : ' • ${m.provider}'} • ${formatNumber(m.costMga)} MGA'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        AppBadge(m.status, tone: tone),
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: _canUpdate ? () => _editMaintenance(m) : null),
                        if (m.status != 'Terminée' && m.status != 'Annulée')
                          IconButton(
                            tooltip: 'Marquer terminée',
                            icon: const Icon(Icons.check_circle_outline, size: 18),
                            onPressed: _canUpdate
                                ? () => _run(() => ref.read(facilitiesRepositoryProvider).completeMaintenance(
                                      id: m.id, actorUserId: _actor.id, actorUsername: _actor.username),
                                      success: 'Intervention terminée.')
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

  Future<void> _editMaintenance(FacilityMaintenanceData? existing) async {
    final facilities = await _facilities();
    if (facilities.isEmpty || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun local ou équipement enregistré.')));
      return;
    }
    String? facilityId = existing?.facilityId ?? facilities.first.id;
    final description = TextEditingController(text: existing?.description ?? '');
    final provider = TextEditingController(text: existing?.provider ?? '');
    final cost = TextEditingController(text: '${existing?.costMga ?? 0}');
    var type = existing?.type ?? 'Corrective';
    var start = existing?.startDate ?? DateTime.now();
    var end = existing?.endDate;
    var status = existing?.status ?? 'Planifiée';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: Text(existing == null ? 'Nouvelle intervention' : 'Modifier l\'intervention'),
        content: SizedBox(width: 620, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: facilityId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Local / équipement *'),
            items: facilities.map((f) => DropdownMenuItem(
              value: f.id, child: Text('${f.name}${f.code == null ? '' : ' (${f.code})'}', overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (v) => setD(() => facilityId = v),
          ),
          const SizedBox(height: 8),
          TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Description des travaux *')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const ['Préventive', 'Corrective'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setD(() => type = v ?? type),
            )),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Statut'),
              items: const ['Planifiée', 'En cours', 'Terminée', 'Annulée']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setD(() => status = v ?? status),
            )),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: provider, decoration: const InputDecoration(labelText: 'Prestataire'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: cost, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Coût (MGA)'))),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(context: ctx, initialDate: start, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) setD(() => start = d);
              },
              icon: const Icon(Icons.play_arrow_outlined, size: 16),
              label: Text('Début : ${formatDateFr(start)}'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(context: ctx, initialDate: end ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) setD(() => end = d);
              },
              icon: const Icon(Icons.stop_outlined, size: 16),
              label: Text(end == null ? 'Fin' : 'Fin : ${formatDateFr(end)}'),
            ),
          ]),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      )),
    );
    if (ok != true || facilityId == null || description.text.trim().isEmpty) return;
    await _run(() => ref.read(facilitiesRepositoryProvider).saveMaintenance(
          id: existing?.id,
          facilityId: facilityId!,
          type: type,
          description: description.text,
          startDate: start,
          endDate: end,
          costMga: int.tryParse(cost.text) ?? 0,
          provider: provider.text.isEmpty ? null : provider.text,
          status: status,
          actorUserId: _actor.id,
          actorUsername: _actor.username,
        ), success: 'Intervention enregistrée.');
  }
}

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
