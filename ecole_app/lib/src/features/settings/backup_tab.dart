import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/auto_backup_service.dart';
import '../../core/services/backup_service.dart';

final backupServiceProvider = Provider<BackupService>((ref) => BackupService());
final autoBackupServiceProvider = Provider<AutoBackupService>((ref) => AutoBackupService(ref.watch(backupServiceProvider)));

class BackupRestoreTab extends ConsumerStatefulWidget {
  const BackupRestoreTab({super.key});
  @override
  ConsumerState<BackupRestoreTab> createState() => _BackupRestoreTabState();
}

class _BackupRestoreTabState extends ConsumerState<BackupRestoreTab> {
  bool _busy = false;
  String? _message;
  Map<String, dynamic>? _autoConfig;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final c = await ref.read(autoBackupServiceProvider).loadConfig();
    if (mounted) setState(() => _autoConfig = c);
  }

  Future<void> _saveAutoConfig() async {
    if (_autoConfig == null) return;
    await ref.read(autoBackupServiceProvider).saveConfig(_autoConfig!);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configuration sauvegarde automatique enregistrée.')));
  }

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
    final cfg = _autoConfig;
    return Padding(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: ListView(children: [
      Text('Sauvegarde & Restauration', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('Sauvegarde manuelle et automatique de la base SQLite et du dossier des pièces jointes (archive .zip, manifeste d\'intégrité SHA-256).'),
      const SizedBox(height: 20),
      Wrap(spacing: 12, runSpacing: 12, children: [
        FilledButton.icon(onPressed: _busy ? null : _backup, icon: const Icon(Icons.backup), label: const Text('Créer une sauvegarde (.zip)')),
        OutlinedButton.icon(onPressed: _busy ? null : _restore, icon: const Icon(Icons.restore), label: const Text('Restaurer depuis .zip')),
      ]),
      if (_busy) ...[const SizedBox(height: 12), const LinearProgressIndicator()],
      if (_message != null) ...[const SizedBox(height: 12), Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_message!)))],
      const Divider(height: 32),
      Text('Sauvegarde automatique', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (cfg == null) const CircularProgressIndicator() else Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Activer la sauvegarde automatique'), subtitle: const Text('Vérification au démarrage de l\'application (si l\'intervalle est dépassé).'), value: cfg['enabled'] == true, onChanged: (v) => setState(() => _autoConfig = {...cfg, 'enabled': v})),
        Row(children: [
          const Text('Intervalle (heures): '),
          SizedBox(width: 100, child: TextFormField(initialValue: '${cfg['intervalHours'] ?? 24}', keyboardType: TextInputType.number, onChanged: (v) => _autoConfig = {...?_autoConfig, 'intervalHours': int.tryParse(v) ?? 24})),
          const SizedBox(width: 16),
          Expanded(child: Text('Dernière sauvegarde auto: ${cfg['lastBackupAt'] ?? 'jamais'}')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('Dossier: ${cfg['directory'] ?? '(par défaut: dossier de données app/backups)'}')),
          TextButton(onPressed: () async { final d = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Dossier des sauvegardes automatiques'); if (d != null) setState(() => _autoConfig = {...?_autoConfig, 'directory': d}); }, child: const Text('Choisir')),
        ]),
        const SizedBox(height: 8),
        FilledButton.tonal(onPressed: _saveAutoConfig, child: const Text('Enregistrer la configuration auto')),
      ]),
      const SizedBox(height: 16),
      const Text('Après restauration, redémarrer l\'application est recommandé.'),
    ])));
  }
}
