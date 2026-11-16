import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/core/services/backup_service.dart';
import 'package:fianarana/core/services/recycle_bin_service.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _msg;
  bool _busy = false;

  Future<void> _backup() async {
    setState(() { _busy = true; _msg = null; });
    try {
      final db = ref.read(appDatabaseProvider);
      final auth = ref.read(authControllerProvider);
      final f = await BackupService(db).createBackup(type: 'manuel', actorUserId: auth.userId, actorUsername: auth.username);
      setState(() => _msg = 'Sauvegarde créée: ${f.path}');
    } catch (e) {
      setState(() => _msg = 'Erreur sauvegarde: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _showRecycleBin() async {
    final db = ref.read(appDatabaseProvider);
    final svc = RecycleBinService(db);
    final items = await svc.listDeleted();
    if (!mounted) return;
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Corbeille (suppression logique)'),
      content: SizedBox(width: 600, height: 400, child: items.isEmpty
        ? const Center(child: Text('Corbeille vide'))
        : ListView(children: items.map((e) => ListTile(
            title: Text('${e.entity} • ${e.label}'),
            subtitle: Text('Supprimé: ${e.deletedAt ?? "-"}'),
            trailing: TextButton(onPressed: () async {
              final auth = ref.read(authControllerProvider);
              await svc.restore(e.entity, e.id, actorUserId: auth.userId, actorUsername: auth.username);
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() => _msg = 'Élément restauré: ${e.label}');
            }, child: const Text('Restaurer')),
          )).toList())),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres & administration')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Sauvegarde locale'),
            subtitle: const Text('Créer une archive .zip (base SQLite + médias). Restauration contrôlée disponible via service.'),
            trailing: FilledButton(onPressed: _busy ? null : _backup, child: const Text('Sauvegarder')),
          )),
          Card(child: ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Corbeille'),
            subtitle: const Text('Suppression logique, rétention configurable (30j par défaut), restauration en un clic.'),
            trailing: OutlinedButton(onPressed: _showRecycleBin, child: const Text('Ouvrir')),
          )),
          const Card(child: ListTile(
            leading: Icon(Icons.keyboard_outlined),
            title: Text('Raccourcis clavier (fondations)'),
            subtitle: Text('Ctrl+L verrouillage, Ctrl+F recherche (à lier), Ctrl+N nouveau, Ctrl+S sauvegarder, Ctrl+W fermer onglet, Échap fermer modale. Saisie grille au clavier à généraliser.'),
          )),
          const Card(child: ListTile(
            leading: Icon(Icons.tab_outlined),
            title: Text('Interface multi-onglets (MDI)'),
            subtitle: Text('Fondation à étendre: état par onglet, ouverture simultanée de modules/dossiers, fermeture rapide.'),
          )),
          const Card(child: ListTile(
            leading: Icon(Icons.lock_person_outlined),
            title: Text('Session & sécurité poste partagé'),
            subtitle: Text('Verrouillage rapide (Ctrl+L) implémenté côté session; déverrouillage par mot de passe. PIN rapide et changement d’utilisateur à compléter.'),
          )),
          if (_msg != null) Padding(padding: const EdgeInsets.all(8), child: Text(_msg!)),
        ],
      ),
    );
  }
}
