import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/audit_service.dart';

/// Sauvegarde/restauration locale: archive .zip de la base SQLite + dossier médias.
/// (Fondation; la copie à chaud SQLite peut être renforcée avec VACUUM INTO/backup API.)
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

  Future<File> createBackup({String type = 'manuel', String? actorUserId, String? actorUsername}) async {
    final dataDir = await _appDataDir();
    final backupsDir = Directory(p.join(dataDir.path, 'backups'));
    if (!backupsDir.existsSync()) backupsDir.createSync(recursive: true);
    final ts = DateTime.now();
    final name = 'backup_${ts.year}${ts.month.toString().padLeft(2,'0')}${ts.day.toString().padLeft(2,'0')}_${ts.hour.toString().padLeft(2,'0')}${ts.minute.toString().padLeft(2,'0')}${ts.second.toString().padLeft(2,'0')}.zip';
    final outFile = File(p.join(backupsDir.path, name));

    final encoder = ZipFileEncoder()..create(outFile.path);
    final dbFile = File(p.join(dataDir.path, 'fianarana.sqlite'));
    if (dbFile.existsSync()) {
      encoder.addFile(dbFile, 'fianarana.sqlite');
    }
    final mediaDir = Directory(p.join(dataDir.path, 'media'));
    if (mediaDir.existsSync()) {
      encoder.addDirectory(mediaDir, includeDirName: true);
    }
    encoder.close();

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
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Sauvegarde', targetObject: outFile.path, description: 'Sauvegarde locale créée ($type)', result: 'Succès');
    return outFile;
  }

  /// Restauration contrôlée (fondation): vérifie l'existence et l'intégrité basique.
  /// L'application doit être redémarrée après restauration complète.
  Future<void> restoreFrom(String zipPath, {String? actorUserId, String? actorUsername}) async {
    final zipFile = File(zipPath);
    if (!zipFile.existsSync()) throw StateError('Archive introuvable');
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    if (archive.isEmpty) throw StateError('Archive vide ou invalide');
    final dataDir = await _appDataDir();
    for (final file in archive) {
      final outPath = p.join(dataDir.path, file.name);
      if (file.isFile) {
        final out = File(outPath)..createSync(recursive: true);
        await out.writeAsBytes(file.content as List<int>);
      } else {
        Directory(outPath).createSync(recursive: true);
      }
    }
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Sauvegarde', targetObject: zipPath, description: 'Restauration effectuée (redémarrage recommandé)', result: 'Succès');
  }

  Future<List<BackupRecord>> listBackups() {
    return (db.select(db.backupRecords)..where((t)=>t.isDeleted.equals(false))..orderBy([(t)=>OrderingTerm.desc(t.createdAtBackup)])).get();
  }
}
