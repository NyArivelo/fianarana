import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/backup_service.dart';

final backupServiceProvider = Provider<BackupService>((ref) => BackupService());

class BackupRestoreTab extends ConsumerStatefulWidget {
  const BackupRestoreTab({super.key});
  @override
  ConsumerState<BackupRestoreTab> createState() => _BackupRestoreTabState();
}

class _BackupRestoreTabState extends ConsumerState<BackupRestoreTab> {
  bool _busy = false;
  String? _message;

  Future<void> _backup() async {
    final path = await FilePicker.platform.saveFile(dialogTitle: 'Enregistrer la sauvegarde', fileName: 'ecole_backup.zip', type: FileType.custom, allowedExtensions: ['zip']);
    if (path == null) return;
    setState(() { _busy = true; _message = null; });
    try {
      await ref.read(backupServiceProvider).createBackup(path);
      setState(() => _message = 'Sauvegarde créée: $path');
    } catch (e) {
      setState(() => _message = 'Erreur sauvegarde: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Restaurer une sauvegarde'),
      content: const Text('La restauration remplacera la base de données locale (et les pièces jointes). Redémarrez l\'application après restauration. Continuer ?'),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('Annuler')), FilledButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('Continuer'))],
    ));
    if (confirm != true) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
    if (result == null || result.files.single.path == null) return;
    setState(() { _busy = true; _message = null; });
    try {
      await ref.read(backupServiceProvider).restoreBackup(result.files.single.path!);
      setState(() => _message = 'Restauration terminée avec contrôle d\'intégrité. Veuillez redémarrer l\'application.');
    } catch (e) {
      setState(() => _message = 'Erreur restauration: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 700), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Sauvegarde & Restauration', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('Sauvegarde manuelle de la base SQLite et du dossier des pièces jointes dans une archive .zip (avec manifeste de contrôle d\'intégrité). La restauration vérifie l\'intégrité avant remplacement.'),
      const SizedBox(height: 24),
      Wrap(spacing: 12, runSpacing: 12, children: [
        FilledButton.icon(onPressed: _busy ? null : _backup, icon: const Icon(Icons.backup), label: const Text('Créer une sauvegarde (.zip)')),
        OutlinedButton.icon(onPressed: _busy ? null : _restore, icon: const Icon(Icons.restore), label: const Text('Restaurer depuis .zip')),
      ]),
      const SizedBox(height: 16),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null) ...[const SizedBox(height: 12), Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_message!)))],
      const SizedBox(height: 24),
      const Text('Remarque: la sauvegarde automatique programmée (horodatée, au démarrage/fermeture ou fréquence) peut être ajoutée comme évolution ultérieure. Après restauration, redémarrer l\'application est recommandé.'),
    ])));
  }
}
