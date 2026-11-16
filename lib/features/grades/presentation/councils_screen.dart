import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/grades/application/council_providers.dart';
import 'package:fianarana/features/grades/application/grades_providers.dart';
import 'package:fianarana/features/students/application/students_providers.dart';

class CouncilsScreen extends ConsumerStatefulWidget {
  const CouncilsScreen({super.key});

  @override
  ConsumerState<CouncilsScreen> createState() => _CouncilsScreenState();
}

class _CouncilsScreenState extends ConsumerState<CouncilsScreen> {
  String? _classId;
  String? _periodId;

  Future<void> _createCouncil() async {
    if (_classId == null || _periodId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sélectionnez une classe et une période')));
      return;
    }
    final auth = ref.read(authControllerProvider);
    try {
      await ref.read(gradesRepositoryProvider).upsertCouncil(
        classId: _classId!,
        periodId: _periodId!,
        councilDate: DateTime.now(),
        status: 'Préparation',
        actorUserId: auth.userId,
        actorUsername: auth.username,
      );
      ref.invalidate(councilsProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Conseil de classe créé')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _lockPeriod() async {
    if (_periodId == null) return;
    final auth = ref.read(authControllerProvider);
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Verrouiller la période'),
      content: const Text('Après délibération, les notes et moyennes de la période seront gelées. Continuer ?'),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('Annuler')),
        FilledButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('Verrouiller')),
      ],
    ));
    if (ok != true) return;
    try {
      await ref.read(gradesRepositoryProvider).lockPeriod(periodId: _periodId!, actorUserId: auth.userId, actorUsername: auth.username);
      ref.invalidate(periodsProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Période verrouillée')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _unlockPeriod() async {
    if (_periodId == null) return;
    final auth = ref.read(authControllerProvider);
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Déverrouillage exceptionnel'),
      content: TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Motif (obligatoire, audité)')),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('Annuler')),
        FilledButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('Déverrouiller')),
      ],
    ));
    if (ok != true || reasonCtrl.text.trim().isEmpty) return;
    try {
      await ref.read(gradesRepositoryProvider).unlockPeriod(periodId: _periodId!, reason: reasonCtrl.text.trim(), actorUserId: auth.userId, actorUsername: auth.username);
      ref.invalidate(periodsProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Période déverrouillée (audité)')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classesProvider);
    final periodsAsync = ref.watch(periodsProvider);
    final councilsAsync = ref.watch(councilsProvider((classId: _classId, periodId: _periodId)));

    return Scaffold(
      appBar: AppBar(title: const Text('Conseils de classe & périodes')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 240, child: classesAsync.when(
              data: (c) => DropdownButtonFormField<String?>(value: _classId, decoration: const InputDecoration(labelText: 'Classe'), items: [
                const DropdownMenuItem(value: null, child: Text('Toutes')),
                ...c.map((x)=>DropdownMenuItem(value: x.id, child: Text(x.label))),
              ], onChanged: (v)=>setState(()=>_classId=v)),
              loading: ()=>const LinearProgressIndicator(), error: (e,_)=>Text('$e'),
            )),
            SizedBox(width: 240, child: periodsAsync.when(
              data: (p) => DropdownButtonFormField<String?>(value: _periodId, decoration: const InputDecoration(labelText: 'Période'), items: [
                const DropdownMenuItem(value: null, child: Text('Toutes')),
                ...p.map((x)=>DropdownMenuItem(value: x.id, child: Text('${x.name}${x.isClosed ? " (verrouillée)" : ""}'))),
              ], onChanged: (v)=>setState(()=>_periodId=v)),
              loading: ()=>const LinearProgressIndicator(), error: (e,_)=>Text('$e'),
            )),
            FilledButton.icon(onPressed: _createCouncil, icon: const Icon(Icons.add), label: const Text('Nouveau conseil')),
            OutlinedButton.icon(onPressed: _lockPeriod, icon: const Icon(Icons.lock), label: const Text('Verrouiller période')),
            OutlinedButton.icon(onPressed: _unlockPeriod, icon: const Icon(Icons.lock_open), label: const Text('Déverrouiller (exception)')),
          ]),
          const SizedBox(height: 12),
          Expanded(child: councilsAsync.when(
            data: (list) => Card(child: list.isEmpty ? const Center(child: Text('Aucun conseil (données de test: conseils_classe importables).')) : ListView(
              children: list.map((c) => ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: Text('Conseil ${c.status}'),
                subtitle: Text('Classe: ${c.classId}\nPériode: ${c.periodId}\nAppréciation: ${c.globalAppreciation ?? "-"}'),
                isThreeLine: true,
              )).toList(),
            )),
            loading: ()=>const Center(child: CircularProgressIndicator()),
            error: (e,_)=>Center(child: Text('Erreur: $e')),
          )),
        ]),
      ),
    );
  }
}
