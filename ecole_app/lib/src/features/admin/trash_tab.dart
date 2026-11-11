import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/database_provider.dart';
import 'trash_repository.dart';

final trashRepositoryProvider = Provider<TrashRepository>((ref) => TrashRepository(ref.watch(appDatabaseProvider)));

class TrashTab extends ConsumerStatefulWidget {
  const TrashTab({super.key});
  @override
  ConsumerState<TrashTab> createState() => _TrashTabState();
}

class _TrashTabState extends ConsumerState<TrashTab> {
  late Future<List<TrashItem>> _future;
  int _retentionDays = 30;

  @override
  void initState() { super.initState(); _reload(); }
  void _reload() { _future = ref.read(trashRepositoryProvider).listAll(); }

  String _typeLabel(String t) => const {
    'student':'Élève','guardian':'Responsable','enrollment':'Inscription','class':'Classe','subject':'Matière','level':'Niveau','educationType':'Type enseignement','room':'Salle','feeType':'Type de frais','session':'Séance','evaluation':'Évaluation','payment':'Paiement','paymentPlan':'Plan de paiement','teacherAssignment':'Affectation','academicYear':'Année scolaire','period':'Période','staffMember':'Personnel','disciplinaryIncident':'Incident disciplinaire','disciplinaryAction':'Action disciplinaire','libraryItem':'Ouvrage','libraryCopy':'Exemplaire','libraryLoan':'Prêt','documentTemplate':'Modèle de document','financialAdjustment':'Ajustement financier','equipmentItem':'Équipement','roomReservation':'Réservation de salle'
  }[t] ?? t;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Corbeille administrative', style: Theme.of(context).textTheme.titleLarge),
        const Spacer(),
        IconButton(icon: const Icon(Icons.refresh), tooltip: 'Actualiser', onPressed: ()=>setState(_reload)),
      ]),
      const SizedBox(height: 4),
      const Text('Éléments supprimés logiquement (restaurables). La purge définitive est irréversible. Accès réservé aux administrateurs (portée globale).'),
      const SizedBox(height: 8),
      Row(children: [
        const Text('Rétention (jours): '),
        SizedBox(width: 80, child: TextFormField(initialValue: '$_retentionDays', keyboardType: TextInputType.number, onChanged: (v)=>_retentionDays = int.tryParse(v) ?? 30)),
        const SizedBox(width: 12),
        FilledButton.tonalIcon(onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final n = await ref.read(trashRepositoryProvider).purgeOlderThanDays(_retentionDays);
          if (!mounted) return;
          messenger.showSnackBar(SnackBar(content: Text('$n élément(s) purgé(s) (> $_retentionDays j).')));
          setState(_reload);
        }, icon: const Icon(Icons.auto_delete_outlined), label: const Text('Purger les éléments expirés')),
      ]),
      const SizedBox(height: 12),
      Expanded(child: FutureBuilder<List<TrashItem>>(future: _future, builder: (context, snap){
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        if (items.isEmpty) return const Center(child: Text('Corbeille vide.'));
        return ListView.separated(itemCount: items.length, separatorBuilder: (_, __)=>const Divider(height:1), itemBuilder: (context,i){
          final it = items[i];
          final age = it.deletedAt == null ? null : DateTime.now().difference(it.deletedAt!).inDays;
          final expired = age != null && age >= _retentionDays;
          return ListTile(
            leading: Icon(expired ? Icons.delete_forever : Icons.delete_outline, color: expired ? Colors.red : null),
            title: Text(it.label),
            subtitle: Text('${_typeLabel(it.entityType)} • supprimé: ${it.deletedAt != null ? fmt.format(it.deletedAt!) : '-'}${age != null ? ' • $age j' : ''}${expired ? ' • expiré' : ''}${it.extra != null ? ' • ${it.extra}' : ''}'),
            trailing: Wrap(spacing: 4, children: [
              TextButton.icon(onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ref.read(trashRepositoryProvider).restore(it);
                  if (!mounted) return;
                  messenger.showSnackBar(const SnackBar(content: Text('Élément restauré.')));
                  setState(_reload);
                } catch(e){
                  if (!mounted) return;
                  messenger.showSnackBar(SnackBar(content: Text('Restauration impossible: $e')));
                }
              }, icon: const Icon(Icons.restore), label: const Text('Restaurer')),
              IconButton(tooltip: 'Purger définitivement', onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final ok = await showDialog<bool>(context: context, builder: (ctx)=>AlertDialog(title: const Text('Purge définitive'), content: Text('Supprimer définitivement "${it.label}" ? Cette action est irréversible.'), actions:[TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('Annuler')), FilledButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('Purger'))]));
                if (ok != true) return;
                try {
                  await ref.read(trashRepositoryProvider).purge(it);
                  if (!mounted) return;
                  messenger.showSnackBar(const SnackBar(content: Text('Élément purgé.')));
                  setState(_reload);
                } catch(e){
                  if (!mounted) return;
                  messenger.showSnackBar(SnackBar(content: Text('Purge impossible (références?): $e')));
                }
              }, icon: const Icon(Icons.delete_forever, color: Colors.red)),
            ]),
          );
        });
      })),
    ]));
  }
}
