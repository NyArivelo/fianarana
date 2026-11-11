import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../../core/security/current_user_scope.dart';
import 'facilities_providers.dart';

class FacilitiesScreen extends ConsumerWidget {
  const FacilitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(currentUserScopeProvider).valueOrNull?.scope ?? 'global';
    if (scope != 'global') {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Accès restreint : le module Locaux & équipements est réservé aux utilisateurs de portée globale.')));
    }
    return DefaultTabController(
      length: 3,
      child: Column(children: const [
        TabBar(isScrollable: true, tabs: [Tab(text: 'Salles / Locaux'), Tab(text: 'Équipements'), Tab(text: 'Réservations')]),
        Expanded(child: TabBarView(children: [_RoomsTab(), _EquipmentTab(), _ReservationsTab()])),
      ]),
    );
  }
}

class _RoomsTab extends ConsumerWidget {
  const _RoomsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(facilitiesRoomsProvider);
    return Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      Row(children: [
        Text('Salles et locaux', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        FilledButton.icon(onPressed: () => _editRoom(context, ref), icon: const Icon(Icons.add), label: const Text('Ajouter une salle')),
      ]),
      const SizedBox(height: 12),
      Expanded(child: rooms.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) => list.isEmpty ? const Center(child: Text('Aucune salle enregistrée.')) : ListView.builder(itemCount: list.length, itemBuilder: (context,i){
          final r = list[i];
          return Card(child: ListTile(
            leading: const Icon(Icons.meeting_room_outlined),
            title: Text(r.name),
            subtitle: Text([r.location, r.capacity != null ? 'Capacité: ${r.capacity}' : null].whereType<String>().where((s)=>s.isNotEmpty).join(' • ')),
            trailing: Wrap(spacing: 4, children: [
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editRoom(context, ref, r)),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => ref.read(facilitiesRepositoryProvider).deleteRoom(r.id)),
            ]),
          ));
        }),
      )),
    ]));
  }

  static Future<void> _editRoom(BuildContext context, WidgetRef ref, [Room? r]) async {
    final name = TextEditingController(text: r?.name ?? '');
    final loc = TextEditingController(text: r?.location ?? '');
    final cap = TextEditingController(text: r?.capacity?.toString() ?? '');
    await showDialog(context: context, builder: (ctx)=>AlertDialog(
      title: Text(r==null?'Nouvelle salle':'Modifier la salle'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom *')),
        TextField(controller: loc, decoration: const InputDecoration(labelText: 'Localisation / bâtiment')),
        TextField(controller: cap, decoration: const InputDecoration(labelText: 'Capacité'), keyboardType: TextInputType.number),
      ])),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: () async {
        if (name.text.trim().isEmpty) return;
        await ref.read(facilitiesRepositoryProvider).upsertRoom(id: r?.id, name: name.text.trim(), location: loc.text.trim().isEmpty?null:loc.text.trim(), capacity: int.tryParse(cap.text.trim()));
        if (ctx.mounted) Navigator.pop(ctx);
      }, child: const Text('Enregistrer'))],
    ));
  }
}

class _EquipmentTab extends ConsumerWidget {
  const _EquipmentTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equipment = ref.watch(equipmentProvider);
    final rooms = {for (final r in (ref.watch(facilitiesRoomsProvider).valueOrNull ?? <Room>[])) r.id: r};
    return Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      Row(children: [
        Text('Équipements & inventaire', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        FilledButton.icon(onPressed: () => _edit(context, ref), icon: const Icon(Icons.add), label: const Text('Ajouter')),
      ]),
      const SizedBox(height: 12),
      Expanded(child: equipment.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) => list.isEmpty ? const Center(child: Text('Aucun équipement enregistré.')) : ListView.builder(itemCount: list.length, itemBuilder: (context,i){
          final e = list[i];
          final room = e.roomId != null ? rooms[e.roomId] : null;
          return Card(child: ListTile(
            leading: Icon(Icons.inventory_2_outlined, color: e.status=='ok'?Colors.green:(e.status=='maintenance'?Colors.orange:Colors.red)),
            title: Text('${e.name} ${e.quantity > 1 ? '(x${e.quantity})' : ''}'),
            subtitle: Text([
              if (e.category!=null && e.category!.isNotEmpty) e.category!,
              'Statut: ${e.status}',
              if (room!=null) 'Salle: ${room.name}',
              if (e.serialNumber!=null && e.serialNumber!.isNotEmpty) 'N°: ${e.serialNumber}',
            ].join(' • ')),
            isThreeLine: true,
            trailing: Wrap(spacing: 4, children: [
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(context, ref, e)),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => ref.read(facilitiesRepositoryProvider).deleteEquipment(e.id)),
            ]),
          ));
        }),
      )),
    ]));
  }

  static Future<void> _edit(BuildContext context, WidgetRef ref, [EquipmentItem? e]) async {
    final rooms = ref.read(facilitiesRoomsProvider).valueOrNull ?? [];
    final name = TextEditingController(text: e?.name ?? '');
    final category = TextEditingController(text: e?.category ?? '');
    final serial = TextEditingController(text: e?.serialNumber ?? '');
    final qty = TextEditingController(text: (e?.quantity ?? 1).toString());
    final notes = TextEditingController(text: e?.notes ?? '');
    String status = e?.status ?? 'ok';
    String? roomId = e?.roomId;
    DateTime? purchase = e?.purchaseDate;
    final fmt = DateFormat('dd/MM/yyyy');
    await showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder:(ctx,setState)=>AlertDialog(
      title: Text(e==null?'Nouvel équipement':'Modifier l\'équipement'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom *')),
        TextField(controller: category, decoration: const InputDecoration(labelText: 'Catégorie (mobilier, informatique, labo, sport...)')),
        TextField(controller: serial, decoration: const InputDecoration(labelText: 'Numéro de série / inventaire')),
        TextField(controller: qty, decoration: const InputDecoration(labelText: 'Quantité'), keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(initialValue: status, decoration: const InputDecoration(labelText: 'État'), items: const [
          DropdownMenuItem(value: 'ok', child: Text('OK / opérationnel')),
          DropdownMenuItem(value: 'maintenance', child: Text('En maintenance')),
          DropdownMenuItem(value: 'broken', child: Text('Hors service')),
          DropdownMenuItem(value: 'retired', child: Text('Réformé')),
        ], onChanged: (v)=>setState(()=>status=v??'ok')),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(initialValue: roomId, decoration: const InputDecoration(labelText: 'Salle / local (optionnel)'), items: [const DropdownMenuItem(value: null, child: Text('(Non affecté)')), for (final r in rooms) DropdownMenuItem(value: r.id, child: Text(r.name))], onChanged: (v)=>setState(()=>roomId=v)),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () async { final d = await showDatePicker(context: ctx, initialDate: purchase ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100)); if (d!=null) setState(()=>purchase=d); }, child: Text(purchase==null?'Date d\'acquisition (optionnelle)':'Acquisition: ${fmt.format(purchase!)}')),
        TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),
      ]))),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: () async {
        if (name.text.trim().isEmpty) return;
        await ref.read(facilitiesRepositoryProvider).upsertEquipment(id: e?.id, name: name.text.trim(), category: category.text.trim().isEmpty?null:category.text.trim(), serialNumber: serial.text.trim().isEmpty?null:serial.text.trim(), roomId: roomId, status: status, quantity: int.tryParse(qty.text.trim()) ?? 1, purchaseDate: purchase, notes: notes.text.trim().isEmpty?null:notes.text.trim());
        if (ctx.mounted) Navigator.pop(ctx);
      }, child: const Text('Enregistrer'))],
    )));
  }
}

class _ReservationsTab extends ConsumerWidget {
  const _ReservationsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservations = ref.watch(reservationsProvider);
    final rooms = {for (final r in (ref.watch(facilitiesRoomsProvider).valueOrNull ?? <Room>[])) r.id: r};
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      Row(children: [
        Text('Réservations de salles', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        FilledButton.icon(onPressed: () => _edit(context, ref), icon: const Icon(Icons.add), label: const Text('Nouvelle réservation')),
      ]),
      const SizedBox(height: 12),
      Expanded(child: reservations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) => list.isEmpty ? const Center(child: Text('Aucune réservation.')) : ListView.builder(itemCount: list.length, itemBuilder: (context,i){
          final r = list[i];
          final room = rooms[r.roomId];
          return Card(child: ListTile(
            leading: Icon(r.status=='cancelled'?Icons.event_busy:Icons.event_available, color: r.status=='cancelled'?Colors.grey:Colors.blue),
            title: Text('${r.title} — ${room?.name ?? r.roomId}'),
            subtitle: Text('${fmt.format(r.startAt)} → ${fmt.format(r.endAt)} • ${r.status}${r.reservedFor!=null && r.reservedFor!.isNotEmpty ? ' • ${r.reservedFor}' : ''}'),
            trailing: Wrap(spacing: 4, children: [
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(context, ref, r)),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => ref.read(facilitiesRepositoryProvider).deleteReservation(r.id)),
            ]),
          ));
        }),
      )),
    ]));
  }

  static Future<void> _edit(BuildContext context, WidgetRef ref, [RoomReservation? res]) async {
    final rooms = ref.read(facilitiesRoomsProvider).valueOrNull ?? [];
    if (rooms.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Créez d\'abord au moins une salle.'))); return; }
    String roomId = res?.roomId ?? rooms.first.id;
    final title = TextEditingController(text: res?.title ?? '');
    final reservedFor = TextEditingController(text: res?.reservedFor ?? '');
    final notes = TextEditingController(text: res?.notes ?? '');
    DateTime start = res?.startAt ?? DateTime.now();
    DateTime end = res?.endAt ?? DateTime.now().add(const Duration(hours: 1));
    String status = res?.status ?? 'reserved';
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    Future<void> pick(BuildContext ctx, bool isStart, void Function(void Function()) setState) async {
      final base = isStart ? start : end;
      final d = await showDatePicker(context: ctx, initialDate: base, firstDate: DateTime(2020), lastDate: DateTime(2100));
      if (d == null) return;
      final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(base));
      if (t == null) return;
      setState(() {
        final v = DateTime(d.year, d.month, d.day, t.hour, t.minute);
        if (isStart) { start = v; if (!end.isAfter(start)) end = start.add(const Duration(hours: 1)); } else { end = v; }
      });
    }
    await showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder:(ctx,setState)=>AlertDialog(
      title: Text(res==null?'Nouvelle réservation':'Modifier la réservation'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: roomId, decoration: const InputDecoration(labelText: 'Salle *'), items: [for (final r in rooms) DropdownMenuItem(value: r.id, child: Text(r.name))], onChanged: (v)=>setState(()=>roomId=v??roomId)),
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Intitulé / motif *')),
        TextField(controller: reservedFor, decoration: const InputDecoration(labelText: 'Réservé pour (classe, enseignant, événement)')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: ()=>pick(ctx,true,setState), child: Text('Début: ${fmt.format(start)}')),
        OutlinedButton(onPressed: ()=>pick(ctx,false,setState), child: Text('Fin: ${fmt.format(end)}')),
        DropdownButtonFormField<String>(initialValue: status, decoration: const InputDecoration(labelText: 'Statut'), items: const [DropdownMenuItem(value: 'reserved', child: Text('Réservée')), DropdownMenuItem(value: 'done', child: Text('Terminée')), DropdownMenuItem(value: 'cancelled', child: Text('Annulée'))], onChanged: (v)=>setState(()=>status=v??'reserved')),
        TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
      ]))),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: () async {
        if (title.text.trim().isEmpty) return;
        final messenger = ScaffoldMessenger.of(ctx);
        final navigator = Navigator.of(ctx);
        final err = await ref.read(facilitiesRepositoryProvider).upsertReservation(id: res?.id, roomId: roomId, title: title.text.trim(), reservedFor: reservedFor.text.trim().isEmpty?null:reservedFor.text.trim(), startAt: start, endAt: end, status: status, notes: notes.text.trim().isEmpty?null:notes.text.trim());
        if (!ctx.mounted) return;
        if (err != null) { messenger.showSnackBar(SnackBar(content: Text(err))); return; }
        navigator.pop();
      }, child: const Text('Enregistrer'))],
    )));
  }
}
