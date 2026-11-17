import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/core/database/seed_importer.dart';
import 'package:fianarana/core/services/backup_service.dart';
import 'package:fianarana/core/services/recycle_bin_service.dart';
import 'package:fianarana/core/services/year_closure_service.dart';
import 'package:fianarana/core/settings/app_config.dart';
import 'package:fianarana/core/settings/ui_settings.dart';
import 'package:fianarana/core/utils/csv_export.dart';
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
    final auth = ref.read(authControllerProvider);
    final adminRow = await (db.select(db.roles).join([
      innerJoin(db.userRoles, db.userRoles.roleId.equalsExp(db.roles.id)),
    ])
          ..where(db.userRoles.userId.equals(auth.userId ?? '') &
              db.roles.name.equals('Administrateur')))
        .getSingleOrNull();
    if (adminRow == null) {
      _setMessage('Accès refusé : la corbeille est réservée aux administrateurs.');
      return;
    }
    final svc = RecycleBinService(db);
    String filter = 'Tous';
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: const Text('Corbeille (suppression logique, admin)'),
          content: SizedBox(
            width: 760,
            height: 480,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('Filtrer par type : '),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: filter,
                    items: ['Tous', ...RecycleBinService.allEntityTypes]
                        .map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setD(() => filter = v ?? 'Tous'),
                  ),
                ),
                IconButton(
                  tooltip: 'Actualiser',
                  onPressed: () => setD(() {}),
                  icon: const Icon(Icons.refresh),
                ),
              ]),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<DeletedEntry>>(
                  future: svc.listDeleted(entityFilter: filter == 'Tous' ? null : filter),
                  builder: (ctx, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final items = snap.data ?? const <DeletedEntry>[];
                    if (items.isEmpty) return const Center(child: Text('Corbeille vide pour ce filtre'));
                    return ListView(
                      children: items
                          .map((e) => ListTile(
                                dense: true,
                                title: Text('${e.entity} — ${e.label}'),
                                subtitle: Text('Supprimé : ${e.deletedAt ?? "-"}'),
                                trailing: TextButton.icon(
                                  onPressed: () async {
                                    await svc.restore(e.entity, e.id,
                                        actorUserId: auth.userId,
                                        actorUsername: auth.username);
                                    setD(() {});
                                    _setMessage('Élément restauré : ${e.label}');
                                  },
                                  icon: const Icon(Icons.restore, size: 16),
                                  label: const Text('Restaurer'),
                                ),
                              ))
                          .toList(),
                    );
                  },
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))
          ],
        );
      }),
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

  Future<void> _exportAudit({required bool asJson}) async {
    DateTime from = DateTime.now().subtract(const Duration(days: 30));
    DateTime to = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        String fmt(DateTime d) =>
            '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
        return AlertDialog(
          title: Text('Exporter l\'audit (${asJson ? 'JSON' : 'CSV'})'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'Sélectionnez la période à exporter (empreinte SHA-256 du fichier fournie).'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: ctx,
                        initialDate: from,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100));
                    if (d != null) setD(() => from = d);
                  },
                  child: Text('Du ${fmt(from)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: ctx,
                        initialDate: to,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100));
                    if (d != null) {
                      setD(() => to = DateTime(d.year, d.month, d.day, 23, 59, 59));
                    }
                  },
                  child: Text('Au ${fmt(to)}'),
                ),
              ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Exporter')),
          ],
        );
      }),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final db = ref.read(appDatabaseProvider);
      final q = db.select(db.auditLogs)
        ..where((t) => t.timestampUtc.isBetweenValues(from.toUtc(), to.toUtc()))
        ..orderBy([(t) => OrderingTerm.desc(t.timestampUtc)]);
      final logs = await q.get();
      final dir = await getApplicationDocumentsDirectory();
      final outDir = Directory(p.join(dir.path, 'fianarana_exports'));
      if (!outDir.existsSync()) outDir.createSync(recursive: true);
      final ts = DateTime.now();
      final stamp =
          '${ts.year}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}_${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}';
      late String content;
      late String ext;
      if (asJson) {
        ext = 'json';
        content = const JsonEncoder.withIndent('  ').convert({
          'period': {'from': from.toUtc().toIso8601String(), 'to': to.toUtc().toIso8601String()},
          'count': logs.length,
          'entries': logs
              .map((l) => {
                    'id': l.id,
                    'timestampUtc': l.timestampUtc.toIso8601String(),
                    'userId': l.userId,
                    'username': l.username,
                    'module': l.module,
                    'targetObject': l.targetObject,
                    'description': l.description,
                    'result': l.result,
                    'hashSha256_entree': l.hashSha256,
                  })
              .toList(),
        });
      } else {
        ext = 'csv';
        final sb = StringBuffer();
        String esc(String? v) => '"${(v ?? '').replaceAll('"', '""')}"';
        sb.writeln(['id', 'timestampUtc', 'userId', 'username', 'module', 'targetObject', 'description', 'result', 'hashSha256_entree']
            .map(esc)
            .join(','));
        for (final l in logs) {
          sb.writeln([l.id, l.timestampUtc.toIso8601String(), l.userId, l.username, l.module, l.targetObject, l.description, l.result, l.hashSha256]
              .map(esc)
              .join(','));
        }
        content = sb.toString();
      }
      final bytes = utf8.encode(content);
      final fileHash = sha256.convert(bytes).toString();
      final file = File(p.join(outDir.path, 'audit_export_$stamp.$ext'));
      await file.writeAsBytes(bytes);
      final hashFile = File('${file.path}.sha256');
      await hashFile.writeAsString('$fileHash  ${p.basename(file.path)}\n');
      _setMessage(
          'Export audit ${ext.toUpperCase()} (${logs.length} entrées) : ${file.path}\nEmpreinte SHA-256 (intégrité fichier) : ${hashFile.path}');
    } catch (e) {
      _setMessage('Erreur export audit : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportTemplates() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final files = <File>[];
      files.add(await CsvExport.export(
        filename: 'modele_import_eleves.csv',
        headers: const ['Matricule', 'Nom', 'Prenom', 'Sexe', 'Date_Naissance', 'Lieu_Naissance', 'Classe', 'Statut'],
        rows: const [
          ['ELV-EX-0001', 'RAKOTO', 'Jean', 'M', '2012-05-10', 'Antananarivo', '3ème 1', 'Actif'],
        ],
      ));
      files.add(await CsvExport.export(
        filename: 'modele_import_personnel.csv',
        headers: const ['Matricule_Personnel', 'Nom', 'Prenom', 'Sexe', 'Fonction', 'Departement_Matiere', 'Telephone', 'Statut'],
        rows: const [
          ['PER-EX-001', 'RASOA', 'Marie', 'F', 'Enseignante', 'Mathématiques', '0340000000', 'Actif'],
        ],
      ));
      files.add(await CsvExport.export(
        filename: 'modele_import_notes.csv',
        headers: const ['Matricule_Eleve', 'Matiere', 'Periode', 'Libelle_Evaluation', 'Note', 'Bareme', 'Coefficient', 'Dispense', 'Niveau_Maitrise', 'Observation'],
        rows: const [
          ['ELV-2026-0001', 'Mathématiques', 'Trimestre 1', 'Devoir 1', '14.5', '20', '1', 'false', 'Acquis', ''],
        ],
      ));
      _setMessage('Modèles d\'import générés :\n${files.map((f) => f.path).join('\n')}');
    } catch (e) {
      _setMessage('Erreur génération modèles : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeSchoolYear() async {
    final db = ref.read(appDatabaseProvider);
    final years = await (db.select(db.schoolYears)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.startDate)]))
        .get();
    if (!mounted) return;
    if (years.isEmpty) {
      _setMessage('Aucune année scolaire trouvée.');
      return;
    }
    String selected = years.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
            title: const Text('Clôture annuelle & archivage légal'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Génère une archive scellée (JSON + empreinte SHA-256) en lecture seule pour l\'année sélectionnée et marque l\'année comme clôturée.'),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selected,
                    decoration: const InputDecoration(labelText: 'Année scolaire'),
                    items: years
                        .map((y) => DropdownMenuItem(
                            value: y.id, child: Text('${y.label} (${y.status})')))
                        .toList(),
                    onChanged: (v) => setD(() => selected = v ?? selected),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clôturer & archiver')),
            ],
          )),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final auth = ref.read(authControllerProvider);
      final f = await YearClosureService(db).closeSchoolYear(
          schoolYearId: selected,
          actorUserId: auth.userId,
          actorUsername: auth.username);
      _setMessage('Clôture annuelle effectuée. Archive scellée: ${f.path} (+ .sha256)');
    } catch (e) {
      _setMessage('Erreur clôture annuelle: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
          const AppBadge('v1.1 • schéma v6',
              tone: AppTone.info, icon: Icons.storage_outlined),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
            AppAlertBanner(tone: AppTone.info, icon: Icons.info_outline, title: _msg!),
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
                  const SizedBox(height: 12),
                  _importExportCard(),
                  const SizedBox(height: 12),
                  _yearClosureCard(),
                ],
              );
              final right = ListView(
                padding: const EdgeInsets.only(left: 6),
                children: [
                  _auditCard(),
                  const SizedBox(height: 12),
                  _securityCard(),
                  const SizedBox(height: 12),
                  _advancedAdminCard(),
                  const SizedBox(height: 12),
                  _displayCard(),
                  const SizedBox(height: 12),
                  _aboutCard(),
                ],
              );
              if (constraints.maxWidth >= 980) {
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                _importExportCard(),
                const SizedBox(height: 12),
                _yearClosureCard(),
                const SizedBox(height: 12),
                _auditCard(),
                const SizedBox(height: 12),
                _securityCard(),
                const SizedBox(height: 12),
                _advancedAdminCard(),
                const SizedBox(height: 12),
                _displayCard(),
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
    final cfg = ref.watch(appConfigProvider).valueOrNull ?? AppConfig.defaults;
    return AppSectionCard(
      title: 'Sauvegarde locale',
      subtitle: 'Archive .zip intègre (base SQLite active + médias + manifeste), restauration contrôlée.',
      trailing: FilledButton.icon(
        onPressed: _busy ? null : _backup,
        icon: const Icon(Icons.backup_outlined, size: 16),
        label: const Text('Sauvegarder'),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Sauvegarde planifiée automatique', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Text('Sauvegarde périodique (utilisateur connecté) et à la mise en arrière-plan/fermeture. Prise en compte au redémarrage.',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
            Switch(
              value: cfg.autoBackupEnabled,
              onChanged: _busy ? null : (v) async {
                await saveAppSetting(ref, kAutoBackupEnabledKey, v ? '1' : '0');
                _setMessage(v ? 'Sauvegarde planifiée activée (effectif au redémarrage).' : 'Sauvegarde planifiée désactivée (effectif au redémarrage).');
              },
            ),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: cfg.autoBackupIntervalHours,
              onChanged: (!cfg.autoBackupEnabled || _busy) ? null : (v) async {
                if (v == null) return;
                await saveAppSetting(ref, kAutoBackupIntervalHoursKey, '');
                _setMessage('Intervalle de sauvegarde enregistré (h, effectif au redémarrage).');
              },
              items: const [1, 6, 12, 24, 48, 72, 168]
                  .map((h) => DropdownMenuItem(value: h, child: Text('Toutes les h')))
                  .toList(),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        backups.when(
          data: (rows) => rows.isEmpty
              ? Text('Aucune sauvegarde enregistrée.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))
              : Column(children: [
                  for (final b in rows.take(4))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(b.status == 'ok' ? Icons.archive_outlined : Icons.error_outline, size: 18, color: b.status == 'ok' ? null : Theme.of(context).colorScheme.error),
                      title: Text(b.filePath.split(RegExp(r'[\\/]')).last,
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                      subtitle: Text(' •  • ',
                          style: const TextStyle(fontSize: 10)),
                      trailing: IconButton(
                        tooltip: 'Restaurer',
                        icon: const Icon(Icons.restore, size: 18),
                        onPressed: _busy ? null : () => _restore(b),
                      ),
                    ),
                ]),
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Erreur sauvegardes : '),
        ),
      ]),
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
                ? '${counts?['Élèves'] ?? 0} élèves • ${counts?['Notes'] ?? 0} notes • ${counts?['Séances/sem.'] ?? 0} séances • ${counts?['Événements'] ?? 0} événements.'
                : 'Importez les données depuis le bouton ci-contre pour tester tous les modules.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
      title: 'Corbeille (admin)',
      subtitle: 'Suppression logique exhaustive, rétention configurable, restauration en un clic (réservé administrateur).',
      trailing: OutlinedButton.icon(
        onPressed: _showRecycleBin,
        icon: const Icon(Icons.delete_outline, size: 16),
        label: const Text('Ouvrir'),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Text(
        'Tous les types d\'éléments supprimés (élèves, notes, finances, personnel, planning, documents, etc.) sont listés, filtrables et restaurables avant purge automatique selon la rétention.',
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _auditCard() {
    final logs = ref.watch(_auditLogsProvider);
    return AppSectionCard(
      title: 'Journal d\'audit',
      subtitle:
          'Traçabilité UTC horodatée et empreinte SHA-256. Export JSON/CSV par période accompagné d\'un fichier .sha256.',
      trailing: Wrap(spacing: 6, runSpacing: 6, children: [
        OutlinedButton.icon(onPressed: _showAudit, icon: const Icon(Icons.visibility_outlined, size: 14), label: const Text('Consulter')),
        OutlinedButton.icon(onPressed: _busy ? null : () => _exportAudit(asJson: false), icon: const Icon(Icons.table_view_outlined, size: 14), label: const Text('Export CSV')),
        FilledButton.icon(onPressed: _busy ? null : () => _exportAudit(asJson: true), icon: const Icon(Icons.data_object, size: 14), label: const Text('Export JSON')),
      ]),
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
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          AppBadge(auth.scopeType ?? 'Session', tone: AppTone.info),
        ]),
        const SizedBox(height: 8),
        const _ShortcutLine('Ctrl+F', 'Recherche globale'),
        const _ShortcutLine('Ctrl+L', 'Verrouiller la session'),
        const _ShortcutLine('Ctrl+W', 'Fermer la fenêtre / l\'onglet'),
        const _ShortcutLine('Ctrl+N', 'Nouvel enregistrement (module actif)'),
        const _ShortcutLine('Ctrl+S', 'Enregistrer (raccourci global)'),
      ]),
    );
  }

  Widget _importExportCard() {
    return AppSectionCard(
      title: 'Import / Export & modèles',
      subtitle: 'Modèles CSV guidés pour import (élèves, personnel, notes) et exports de données.',
      trailing: FilledButton.icon(
        onPressed: _busy ? null : _exportTemplates,
        icon: const Icon(Icons.description_outlined, size: 16),
        label: const Text('Générer modèles CSV'),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Text(
        'Modèles générés dans Documents/fianarana_exports. Exports disponibles : listes/paiements (CSV), audit JSON/CSV signé (.sha256), sauvegardes .zip. Import élèves CSV/XLSX avec prévisualisation et doublons depuis le module Élèves.',
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  Future<void> _showClosureHistory() async {
    final db = ref.read(appDatabaseProvider);
    final closures = await YearClosureService(db).listClosures();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Historique des clôtures / archives'),
        content: SizedBox(
          width: 720,
          height: 420,
          child: closures.isEmpty
              ? const Center(child: Text('Aucune clôture archivée.'))
              : ListView(
                  children: closures.map((c) => ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(c.status),
                        subtitle: Text('Date: ${formatDateFr(c.closedAt)}\nArchive: ${c.archivePath ?? "-"}\nSHA-256: ${c.archiveHash ?? "-"}', style: const TextStyle(fontSize: 11)),
                        isThreeLine: true,
                      )).toList(),
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
      ),
    );
  }

  Widget _yearClosureCard() {
    return AppSectionCard(
      title: 'Clôture annuelle & archivage légal',
      subtitle: 'Archive scellée (JSON + SHA-256) en lecture seule de l\'année scolaire (coffre-fort légal).',
      trailing: Wrap(spacing: 8, children: [
        OutlinedButton.icon(onPressed: _busy ? null : _showClosureHistory, icon: const Icon(Icons.history, size: 16), label: const Text('Historique')),
        FilledButton.icon(onPressed: _busy ? null : _closeSchoolYear, icon: const Icon(Icons.inventory_2_outlined, size: 16), label: const Text('Clôturer')),
      ]),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Text(
          'Conserve une synthèse figée (périodes, effectifs, notes, finances, présences) pour archivage et préparation de la rentrée suivante.',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }

  Widget _displayCard() {
    final scaleAsync = ref.watch(uiScaleProvider);
    return AppSectionCard(
      title: 'Affichage & accessibilité',
      subtitle: 'Ajustez la taille du texte et des éléments de l\'interface.',
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: scaleAsync.when(
        data: (scale) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Échelle UI', style: TextStyle(fontSize: 12)),
            const Spacer(),
            AppBadge('${(scale * 100).round()}%', tone: AppTone.info),
          ]),
          Slider(
            value: scale,
            min: 0.85,
            max: 1.25,
            divisions: 8,
            label: '${(scale * 100).round()}%',
            onChanged: (v) async {
              await saveUiScale(ref, v);
            },
          ),
        ]),
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Erreur réglage affichage : $e'),
      ),
    );
  }

  Future<void> _saveCivilStatusConfig() async {
    final current = ref.read(appConfigProvider).valueOrNull?.civilStatusConfig ??
        AppConfig.defaults.civilStatusConfig;
    final ctrl = TextEditingController(
        text: const JsonEncoder.withIndent('  ').convert(current));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configuration état civil / champs régionaux'),
        content: SizedBox(
            width: 640,
            height: 360,
            child: TextField(
                controller: ctrl,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                    labelText: 'JSON (champs, libellés, requis, formats)',
                    alignLabelWithHint: true))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok == true) {
      await saveAppSetting(ref, kCivilStatusConfigKey, ctrl.text);
      _setMessage('Configuration état civil enregistrée.');
    }
  }

  Future<void> _saveMasteryLevels() async {
    final current = ref.read(appConfigProvider).valueOrNull?.masteryLevels ?? AppConfig.defaults.masteryLevels;
    final ctrl = TextEditingController(text: current.join('\n'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Référentiel de maîtrise (compétences)'),
        content: SizedBox(
          width: 520,
          height: 320,
          child: TextField(
            controller: ctrl,
            maxLines: null,
            expands: true,
            decoration: const InputDecoration(
              labelText: 'Niveaux de maîtrise (un par ligne)',
              hintText: 'Non acquis\nEn cours\nAcquis\nExpert',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok == true) {
      final levels = ctrl.text.split(RegExp(r'[\r\n]+')).map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList();
      await saveAppSetting(ref, kMasteryLevelsKey, jsonEncode(levels.isEmpty ? AppConfig.defaults.masteryLevels : levels));
      _setMessage('Niveaux de maîtrise enregistrés.');
    }
  }

  Future<void> _saveCompetencyCodes() async {
    final current = ref.read(appConfigProvider).valueOrNull?.competencyCodes ?? AppConfig.defaults.competencyCodes;
    final ctrl = TextEditingController(text: current.join('\n'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Référentiel de compétences (codes)'),
        content: SizedBox(
          width: 520,
          height: 320,
          child: TextField(
            controller: ctrl,
            maxLines: null,
            expands: true,
            decoration: const InputDecoration(
              labelText: 'Codes de compétences (un par ligne)',
              hintText: 'C1 - Compréhension\nC2 - Expression\nC3 - Raisonnement',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok == true) {
      final codes = ctrl.text.split(RegExp(r'[\r\n]+')).map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList();
      await saveAppSetting(ref, kCompetencyCodesKey, jsonEncode(codes));
      _setMessage('Référentiel de compétences enregistré.');
    }
  }

  Future<void> _checkUpdate() async {
    _setMessage(
        'Mise à jour logique: version 1.1 (schéma v6). Vérification distante non configurée en local; les migrations Drift s\'appliquent automatiquement au redémarrage.');
  }

  Future<void> _setSandbox(bool v) async {
    await saveAppSetting(ref, kSandboxModeKey, v ? '1' : '0');
    try {
      final dir = await getApplicationSupportDirectory();
      final folder = Directory(p.join(dir.path, 'fianarana'));
      if (!folder.existsSync()) folder.createSync(recursive: true);
      final marker = File(p.join(folder.path, 'use_sandbox.flag'));
      if (v) {
        if (!marker.existsSync()) await marker.writeAsString('sandbox');
      } else {
        if (marker.existsSync()) await marker.delete();
      }
    } catch (_) {}
    _setMessage(v
        ? 'Mode démonstration/bac à sable activé. Redémarrez l\'application pour ouvrir la base bac à sable isolée (données de test séparées).'
        : 'Mode démonstration désactivé. Redémarrez l\'application pour revenir à la base de production.');
  }

  Widget _advancedAdminCard() {
    final cfgAsync = ref.watch(appConfigProvider);
    return AppSectionCard(
      title: 'Administration avancée & conformité',
      subtitle:
          'Utilisateurs/rôles, bac à sable, mises à jour, sécurité session, corbeille et état civil.',
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: cfgAsync.when(
        data: (cfg) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
                onPressed: () => context.go('/settings/users'),
                icon: const Icon(Icons.manage_accounts_outlined, size: 16),
                label: const Text('Utilisateurs & rôles')),
            OutlinedButton.icon(
                onPressed: _checkUpdate,
                icon: const Icon(Icons.system_update_alt, size: 16),
                label: const Text('Vérifier mise à jour')),
            OutlinedButton.icon(
                onPressed: _saveCivilStatusConfig,
                icon: const Icon(Icons.badge_outlined, size: 16),
                label: const Text('Champs état civil')),
            OutlinedButton.icon(
                onPressed: _saveMasteryLevels,
                icon: const Icon(Icons.school_outlined, size: 16),
                label: const Text('Niveaux de maîtrise')),
            OutlinedButton.icon(
                onPressed: _saveCompetencyCodes,
                icon: const Icon(Icons.list_alt_outlined, size: 16),
                label: const Text('Codes compétences')),
          ]),
          const SizedBox(height: 10),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: cfg.sandboxMode,
              onChanged: _setSandbox,
              title: const Text('Mode démonstration / bac à sable'),
              subtitle: const Text('Formation avec données fictives (bascule logique, réimport guidé).')),
          Row(children: [
            const Expanded(child: Text('Inactivité avant verrouillage (min)')),
            DropdownButton<int>(
                value: cfg.inactivityMinutes,
                items: const [1, 2, 5, 10, 15, 30]
                    .map((m) => DropdownMenuItem(value: m, child: Text('$m')))
                    .toList(),
                onChanged: (v) async {
                  if (v != null) {
                    await saveAppSetting(ref, kInactivityMinutesKey, '$v');
                    _setMessage('Délai d\'inactivité enregistré (appliqué au prochain lancement/session).');
                  }
                })
          ]),
          Row(children: [
            const Expanded(child: Text('Rétention corbeille (jours, purge auto)')),
            DropdownButton<int>(
                value: cfg.recycleRetentionDays,
                items: const [7, 30, 60, 90, 365]
                    .map((d) => DropdownMenuItem(value: d, child: Text('$d')))
                    .toList(),
                onChanged: (v) async {
                  if (v != null) {
                    await saveAppSetting(ref, kRecycleRetentionDaysKey, '$v');
                    _setMessage('Rétention corbeille enregistrée.');
                  }
                })
          ]),
          const SizedBox(height: 4),
          Text(
              'Portées RBAC (Globale/Affectations/Caisse), audit exportable par période (JSON/CSV + SHA-256), sauvegardes .zip, migrations Drift automatiques.',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Erreur config: $e'),
      ),
    );
  }

  Widget _aboutCard() {
    return AppSectionCard(
      title: 'À propos',
      subtitle: 'Fianarana — application Desktop de gestion scolaire.',
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _InfoLine('Version', '1.1 • MVP Desktop'),
        const _InfoLine('Base de données', 'SQLite 3 (Drift) locale, clés UUID'),
        const _InfoLine('Schéma', 'v6 — studio, absences, clôture, compétences, état civil'),
        const _InfoLine('Année scolaire', '2026-2027'),
        const _InfoLine('Devise', 'Ariary malgache (MGA)'),
        const SizedBox(height: 8),
        Text(
          'Données stockées localement, sans dépendance réseau. Sauvegardes .zip et journal d\'audit SHA-256.',
          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
              style: const TextStyle(fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))),
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
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
      ]),
    );
  }
}
