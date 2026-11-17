import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/core/database/seed_importer.dart';
import 'package:fianarana/core/services/backup_service.dart';
import 'package:fianarana/core/services/recycle_bin_service.dart';
import 'package:fianarana/core/widgets/app_ui.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';

final _settingsStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  Future<int> count(String table) async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM $table WHERE is_deleted = 0')
        .getSingle();
    return row.read<int>('c');
  }

  return {
    'Élèves': await count('students'),
    'Personnel': await count('staff_members'),
    'Classes': await count('classes'),
    'Notes': await count('evaluations'),
    'Séances/sem.': await count('timetable_sessions'),
    'Événements': await count('calendar_events'),
  };
});

final _backupsProvider = FutureProvider<List<BackupRecord>>((ref) {
  return BackupService(ref.watch(appDatabaseProvider)).listBackups();
});

final _auditLogsProvider = FutureProvider<List<AuditLog>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.auditLogs)
        ..orderBy([(t) => OrderingTerm.desc(t.timestampUtc)])
        ..limit(80))
      .get();
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _msg;
  bool _busy = false;

  void _setMessage(String message) {
    if (!mounted) return;
    setState(() => _msg = message);
  }

  Future<void> _backup() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final db = ref.read(appDatabaseProvider);
      final auth = ref.read(authControllerProvider);
      final f = await BackupService(db).createBackup(
          type: 'manuel',
          actorUserId: auth.userId,
          actorUsername: auth.username);
      ref.invalidate(_backupsProvider);
      _setMessage('Sauvegarde créée : ${f.path}');
    } catch (e) {
      _setMessage('Erreur sauvegarde : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(BackupRecord record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurer cette sauvegarde ?'),
        content: Text('Archive : ${record.filePath}\n\n'
            'La base et les médias seront remplacés par le contenu de l\'archive. '
            'L\'application doit être redémarrée après la restauration.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restaurer')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final auth = ref.read(authControllerProvider);
      await BackupService(ref.read(appDatabaseProvider)).restoreFrom(
        record.filePath,
        actorUserId: auth.userId,
        actorUsername: auth.username,
      );
      _setMessage(
          'Restauration effectuée. Redémarrez l\'application pour recharger la base.');
    } catch (e) {
      _setMessage('Erreur restauration : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reimportSeeds() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Réimporter les données de test ?'),
        content: const Text(
            'Cette action met à jour les données de démonstration (élèves, personnel, affectations, '
            'emploi du temps, calendrier, bibliothèque, locaux). '
            'Les enregistrements existants portant les mêmes UUID seront écrasés. '
            'Les saisies de production ne sont pas supprimées.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Réimporter')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final db = ref.read(appDatabaseProvider);
      final result = await SeedImporter(db).importAll();
      ref.invalidate(_settingsStatsProvider);
      _setMessage('Import terminé : $result');
    } catch (e) {
      _setMessage('Erreur import : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showRecycleBin() async {
    final db = ref.read(appDatabaseProvider);
    final svc = RecycleBinService(db);
    final items = await svc.listDeleted();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Corbeille (suppression logique)'),
        content: SizedBox(
          width: 640,
          height: 420,
          child: items.isEmpty
              ? const Center(child: Text('Corbeille vide'))
              : ListView(
                  children: items
                      .map((e) => ListTile(
                            title: Text('${e.entity} • ${e.label}'),
                            subtitle: Text('Supprimé : ${e.deletedAt ?? "-"}'),
                            trailing: TextButton(
                              onPressed: () async {
                                final auth = ref.read(authControllerProvider);
                                await svc.restore(e.entity, e.id,
                                    actorUserId: auth.userId,
                                    actorUsername: auth.username);
                                if (ctx.mounted) Navigator.pop(ctx);
                                _setMessage('Élément restauré : ${e.label}');
                              },
                              child: const Text('Restaurer'),
                            ),
                          ))
                      .toList()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))
        ],
      ),
    );
  }

  Future<void> _showAudit() async {
    final logs = await ref.read(_auditLogsProvider.future);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Journal d\'audit (traçabilité SHA-256)'),
        content: SizedBox(
          width: 760,
          height: 460,
          child: logs.isEmpty
              ? const Center(child: Text('Aucune entrée d\'audit'))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Horodatage UTC')),
                        DataColumn(label: Text('Agent')),
                        DataColumn(label: Text('Module')),
                        DataColumn(label: Text('Description')),
                        DataColumn(label: Text('Empreinte')),
                      ],
                      rows: logs.map((l) {
                        final ts = l.timestampUtc;
                        final stamp =
                            '${formatDateIso(ts)} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
                        return DataRow(cells: [
                          DataCell(Text(stamp,
                              style: const TextStyle(
                                  fontSize: 11, fontFamily: 'monospace'))),
                          DataCell(Text(l.username ?? l.userId ?? 'système')),
                          DataCell(AppBadge(l.module, tone: AppTone.info)),
                          DataCell(SizedBox(
                            width: 280,
                            child: Text(l.description,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                          )),
                          DataCell(Text(
                            (l.hashSha256 ?? '-').substring(
                                0, (l.hashSha256 ?? '-').length.clamp(0, 16)),
                            style: const TextStyle(
                                fontSize: 10, fontFamily: 'monospace'),
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = ref.watch(_settingsStatsProvider);

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF020617)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Paramètres & administration'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          AppBadge('v1.1 • schéma v5',
              tone: AppTone.info, icon: Icons.storage_outlined),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          stats.maybeWhen(
            data: (counts) => Wrap(spacing: 12, runSpacing: 12, children: [
              for (final entry in counts.entries)
                AppStatCard(
                  icon: switch (entry.key) {
                    'Élèves' => Icons.people_outline,
                    'Personnel' => Icons.badge_outlined,
                    'Classes' => Icons.school_outlined,
                    'Notes' => Icons.grading_outlined,
                    'Séances/sem.' => Icons.calendar_view_week_outlined,
                    _ => Icons.event_note_outlined,
                  },
                  label: entry.key,
                  value: formatNumber(entry.value),
                  tone: entry.value == 0 ? AppTone.warning : AppTone.info,
                  width: 178,
                ),
            ]),
            orElse: () => const SizedBox(height: 64),
          ),
          const SizedBox(height: 12),
          if (_msg != null) ...[
            AppAlertBanner(
              tone: AppTone.info,
              icon: Icons.info_outline,
              title: _msg!,
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final left = ListView(
                padding: const EdgeInsets.only(right: 6),
                children: [
                  _backupCard(),
                  const SizedBox(height: 12),
                  _seedCard(stats.valueOrNull),
                  const SizedBox(height: 12),
                  _recycleCard(),
                ],
              );
              final right = ListView(
                padding: const EdgeInsets.only(left: 6),
                children: [
                  _auditCard(),
                  const SizedBox(height: 12),
                  _securityCard(),
                  const SizedBox(height: 12),
                  _aboutCard(),
                ],
              );
              if (constraints.maxWidth >= 980) {
                return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: left),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: right),
                    ]);
              }
              return ListView(children: [
                _backupCard(),
                const SizedBox(height: 12),
                _seedCard(stats.valueOrNull),
                const SizedBox(height: 12),
                _recycleCard(),
                const SizedBox(height: 12),
                _auditCard(),
                const SizedBox(height: 12),
                _securityCard(),
                const SizedBox(height: 12),
                _aboutCard(),
              ]);
            }),
          ),
        ]),
      ),
    );
  }

  Widget _backupCard() {
    final backups = ref.watch(_backupsProvider);
    return AppSectionCard(
      title: 'Sauvegarde locale',
      subtitle: 'Archive .zip (base SQLite + médias), restauration contrôlée.',
      trailing: FilledButton.icon(
        onPressed: _busy ? null : _backup,
        icon: const Icon(Icons.backup_outlined, size: 16),
        label: const Text('Sauvegarder'),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: backups.when(
        data: (rows) => rows.isEmpty
            ? Text('Aucune sauvegarde enregistrée.',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant))
            : Column(children: [
                for (final b in rows.take(4))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.archive_outlined, size: 18),
                    title: Text(b.filePath.split(RegExp(r'[\\/]')).last,
                        style: const TextStyle(
                            fontSize: 12, fontFamily: 'monospace')),
                    subtitle: Text(
                        '${formatDateFr(b.createdAtBackup)} • ${b.type} • ${b.status}',
                        style: const TextStyle(fontSize: 10)),
                    trailing: IconButton(
                      tooltip: 'Restaurer',
                      icon: const Icon(Icons.restore, size: 18),
                      onPressed: _busy ? null : () => _restore(b),
                    ),
                  ),
              ]),
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Erreur sauvegardes : $e'),
      ),
    );
  }

  Widget _seedCard(Map<String, int>? counts) {
    final loaded = (counts?['Élèves'] ?? 0) > 0;
    return AppSectionCard(
      title: 'Données de test',
      subtitle:
          'Jeu de démonstration : élèves, personnel, affectations, planning, calendrier, bibliothèque et locaux.',
      trailing: AppBadge(
        loaded ? 'Chargées' : 'Non chargées',
        tone: loaded ? AppTone.success : AppTone.warning,
        icon: loaded ? Icons.check_circle_outline : Icons.dataset_outlined,
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [
        Expanded(
          child: Text(
            loaded
                ? '${counts?['Élèves'] ?? 0} élèves • ${counts?['Notes'] ?? 0} notes • '
                    '${counts?['Séances/sem.'] ?? 0} séances • ${counts?['Événements'] ?? 0} événements.'
                : 'Importez les données depuis le bouton ci-contre pour tester tous les modules.',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _reimportSeeds,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Réimporter'),
        ),
      ]),
    );
  }

  Widget _recycleCard() {
    return AppSectionCard(
      title: 'Corbeille',
      subtitle:
          'Suppression logique, rétention 30 jours, restauration en un clic.',
      trailing: OutlinedButton.icon(
        onPressed: _showRecycleBin,
        icon: const Icon(Icons.delete_outline, size: 16),
        label: const Text('Ouvrir'),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Text(
        'Les éléments supprimés restent consultables et restaurables avant purge définitive.',
        style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _auditCard() {
    final logs = ref.watch(_auditLogsProvider);
    return AppSectionCard(
      title: 'Journal d\'audit',
      subtitle:
          'Traçabilité UTC horodatée et empreinte SHA-256 des opérations sensibles.',
      trailing: OutlinedButton.icon(
        onPressed: _showAudit,
        icon: const Icon(Icons.receipt_long_outlined, size: 16),
        label: const Text('Consulter'),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: logs.when(
        data: (rows) => Row(children: [
          AppBadge('${rows.length} entrée(s) récente(s)', tone: AppTone.info),
          const SizedBox(width: 8),
          if (rows.isNotEmpty)
            Expanded(
              child: Text(rows.first.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
        ]),
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Erreur audit : $e'),
      ),
    );
  }

  Widget _securityCard() {
    final auth = ref.watch(authControllerProvider);
    return AppSectionCard(
      title: 'Session & sécurité',
      subtitle: 'Poste partagé : rôles, permissions et verrouillage rapide.',
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.person_outline, size: 16),
          const SizedBox(width: 6),
          Expanded(
              child: Text(auth.fullName ?? auth.username ?? 'Utilisateur',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600))),
          AppBadge(auth.scopeType ?? 'Session', tone: AppTone.info),
        ]),
        const SizedBox(height: 8),
        const _ShortcutLine('Ctrl+F', 'Recherche globale'),
        const _ShortcutLine('Ctrl+L', 'Verrouiller la session'),
        const _ShortcutLine('Ctrl+W', 'Fermer la fenêtre / l\'onglet'),
        const _ShortcutLine('Ctrl+N', 'Nouvel enregistrement du module actif'),
        const _ShortcutLine('Ctrl+S', 'Enregistrer le formulaire actif'),
      ]),
    );
  }

  Widget _aboutCard() {
    return AppSectionCard(
      title: 'À propos',
      subtitle: 'Fianarana — application Desktop de gestion scolaire.',
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _InfoLine('Version', '1.1 • MVP Desktop'),
        const _InfoLine(
            'Base de données', 'SQLite 3 (Drift) locale, clés UUID'),
        const _InfoLine('Schéma', 'v5 — calendrier & éphéméride'),
        const _InfoLine('Année scolaire', '2026-2027'),
        const _InfoLine('Devise', 'Ariary malgache (MGA)'),
        const SizedBox(height: 8),
        Text(
          'Données stockées localement, sans dépendance réseau. Sauvegardes .zip et journal d\'audit SHA-256.',
          style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ]),
    );
  }
}

class _ShortcutLine extends StatelessWidget {
  final String keys;
  final String label;
  const _ShortcutLine(this.keys, this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(keys,
              style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant))),
      ]),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  const _InfoLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
      ]),
    );
  }
}
