import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/audit_service.dart';

/// Sauvegarde/restauration locale intègre : archive .zip de la base SQLite active
/// (+ journaux WAL/SHM si présents) et du dossier médias, avec manifeste, somme
/// de contrôle et traçabilité. La restauration requiert un redémarrage.
class BackupService {
  final AppDatabase db;
  late final AuditService _audit = AuditService(db);
  BackupService(this.db);

  Future<Directory> _appDataDir() async {
    final dir = await getApplicationSupportDirectory();
    final root = Directory(p.join(dir.path, 'fianarana'));
    if (!root.existsSync()) root.createSync(recursive: true);
    return root;
  }

  Future<bool> _isSandbox(Directory dataDir) async =>
      sandboxMarkerFile(dataDir).existsSync();

  Future<String> _activeDbName(Directory dataDir) async =>
      (await _isSandbox(dataDir)) ? 'fianarana_sandbox.sqlite' : 'fianarana.sqlite';

  Future<void> _checkpointBestEffort() async {
    try {
      // Cohérence lecture : checkpoint WAL avant copie (si mode WAL).
      await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE);');
    } catch (_) {
      // Meilleur effort : la copie reste tentée.
    }
  }

  Future<File> createBackup({
    String type = 'manuel',
    String? actorUserId,
    String? actorUsername,
  }) async {
    final dataDir = await _appDataDir();
    final backupsDir = Directory(p.join(dataDir.path, 'backups'));
    if (!backupsDir.existsSync()) backupsDir.createSync(recursive: true);
    final ts = DateTime.now();
    final stamp = '${ts.year}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}_'
        '${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}${ts.second.toString().padLeft(2, '0')}';
    final name = 'backup_$stamp.zip';
    final outFile = File(p.join(backupsDir.path, name));

    try {
      await _checkpointBestEffort();
      final activeDb = await _activeDbName(dataDir);
      final sandbox = await _isSandbox(dataDir);

      final encoder = ZipFileEncoder()..create(outFile.path);

      // Base active + fichiers journaux associés
      for (final suffix in const ['', '-wal', '-shm', '-journal']) {
        final f = File(p.join(dataDir.path, '$activeDb$suffix'));
        if (f.existsSync()) {
          encoder.addFile(f, '$activeDb$suffix');
        }
      }
      // Médias
      final mediaDir = Directory(p.join(dataDir.path, 'media'));
      if (mediaDir.existsSync()) {
        encoder.addDirectory(mediaDir, includeDirName: true);
      }

      final manifest = <String, dynamic>{
        'format': 'fianarana-backup-v1',
        'createdAt': ts.toIso8601String(),
        'type': type,
        'database': activeDb,
        'sandbox': sandbox,
        'schemaVersion': db.schemaVersion,
        'includes': {
          'database': File(p.join(dataDir.path, activeDb)).existsSync(),
          'media': mediaDir.existsSync(),
        },
      };
      final manifestFile = File(p.join(backupsDir.path, 'manifest_$stamp.json'));
      await manifestFile.writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
      encoder.addFile(manifestFile, 'manifest.json');
      encoder.close();
      try { if (manifestFile.existsSync()) manifestFile.deleteSync(); } catch (_) {}

      final bytes = await outFile.readAsBytes();
      final checksum = sha256.convert(bytes).toString();
      await db.into(db.backupRecords).insert(BackupRecordsCompanion.insert(
        id: Value(newUuid()),
        filePath: outFile.path,
        createdAtBackup: ts,
        type: Value(type),
        checksum: Value(checksum),
        status: const Value('ok'),
      ));
      await _audit.log(
        userId: actorUserId,
        username: actorUsername,
        module: 'Sauvegarde',
        targetObject: outFile.path,
        description: 'Sauvegarde locale créée ($type, base: $activeDb)',
        result: 'Succès',
      );
      return outFile;
    } catch (e) {
      // Robustesse : enregistrer l'échec et tracer l'audit
      try {
        await db.into(db.backupRecords).insert(BackupRecordsCompanion.insert(
          id: Value(newUuid()),
          filePath: outFile.path,
          createdAtBackup: ts,
          type: Value(type),
          checksum: const Value.absent(),
          status: Value('échec: $e'),
        ));
      } catch (_) {}
      try {
        await _audit.log(
          userId: actorUserId,
          username: actorUsername,
          module: 'Sauvegarde',
          targetObject: outFile.path,
          description: 'Échec sauvegarde ($type)',
          result: 'Échec',
          metadata: {'error': e.toString()},
        );
      } catch (_) {}
      rethrow;
    }
  }

  /// Restauration contrôlée : extrait la base/médias de l'archive dans le dossier
  /// de données. Un redémarrage de l'application est requis pour recharger la base.
  Future<void> restoreFrom(
    String zipPath, {
    String? actorUserId,
    String? actorUsername,
  }) async {
    final zipFile = File(zipPath);
    if (!zipFile.existsSync()) {
      throw StateError('Archive de sauvegarde introuvable.');
    }
    try {
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      if (archive.isEmpty) throw StateError('Archive vide ou invalide.');

      // Lecture manifeste (si présent) pour cibler la bonne base
      String? targetDb;
      for (final f in archive.files) {
        if (f.isFile && p.basename(f.name) == 'manifest.json') {
          try {
            final m = jsonDecode(utf8.decode(f.content as List<int>)) as Map<String, dynamic>;
            targetDb = (m['database'] as String?)?.trim();
          } catch (_) {}
          break;
        }
      }
      targetDb ??= archive.files.any((f) => f.name.endsWith('fianarana_sandbox.sqlite') || f.name.contains('fianarana_sandbox.sqlite'))
          ? 'fianarana_sandbox.sqlite'
          : 'fianarana.sqlite';

      final dataDir = await _appDataDir();
      // Nettoyage préventif des journaux de la base cible pour éviter incohérences
      for (final suffix in const ['-wal', '-shm', '-journal']) {
        final jf = File(p.join(dataDir.path, '$targetDb$suffix'));
        if (jf.existsSync()) {
          try { jf.deleteSync(); } catch (_) {}
        }
      }

      for (final file in archive.files) {
        final name = file.name.replaceAll('\\', '/');
        if (name == 'manifest.json' || name.endsWith('/manifest.json')) continue;
        // Sécurité chemin
        final normalized = p.normalize(p.join(dataDir.path, name));
        if (!p.isWithin(dataDir.path, normalized) && normalized != p.join(dataDir.path, name)) {
          continue;
        }
        final outPath = p.join(dataDir.path, name);
        if (file.isFile) {
          final out = File(outPath)..createSync(recursive: true);
          await out.writeAsBytes(file.content as List<int>);
        } else {
          Directory(outPath).createSync(recursive: true);
        }
      }

      await _audit.log(
        userId: actorUserId,
        username: actorUsername,
        module: 'Sauvegarde',
        targetObject: zipPath,
        description: 'Restauration effectuée (base: $targetDb, redémarrage requis)',
        result: 'Succès',
      );
    } catch (e) {
      try {
        await _audit.log(
          userId: actorUserId,
          username: actorUsername,
          module: 'Sauvegarde',
          targetObject: zipPath,
          description: 'Échec restauration',
          result: 'Échec',
          metadata: {'error': e.toString()},
        );
      } catch (_) {}
      rethrow;
    }
  }

  Future<List<BackupRecord>> listBackups() {
    return (db.select(db.backupRecords)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAtBackup)]))
        .get();
  }
}
