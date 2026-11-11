import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class BackupService {
  Future<Directory> _appDataDir() async {
    final dir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(dir.path, 'ecole_app'));
    if (!await dbDir.exists()) await dbDir.create(recursive: true);
    return dbDir;
  }

  Future<String> createBackup(String targetZipPath) async {
    final dataDir = await _appDataDir();
    final encoder = ZipFileEncoder();
    encoder.create(targetZipPath);

    final manifest = <String, dynamic>{'createdAt': DateTime.now().toUtc().toIso8601String(), 'files': <String, String>{}};

    Future<void> addFileIfExists(String name) async {
      final f = File(p.join(dataDir.path, name));
      if (await f.exists()) {
        encoder.addFile(f, name);
        final bytes = await f.readAsBytes();
        (manifest['files'] as Map<String, String>)[name] = sha256.convert(bytes).toString();
      }
    }

    await addFileIfExists('ecole.sqlite');
    await addFileIfExists('ecole.sqlite-wal');
    await addFileIfExists('ecole.sqlite-shm');

    final attachDir = Directory(p.join(dataDir.path, 'attachments'));
    if (await attachDir.exists()) {
      await for (final ent in attachDir.list(recursive: true, followLinks: false)) {
        if (ent is File) {
          final rel = p.join('attachments', p.relative(ent.path, from: attachDir.path)).replaceAll('\\', '/');
          encoder.addFile(ent, rel);
          final bytes = await ent.readAsBytes();
          (manifest['files'] as Map<String, String>)[rel] = sha256.convert(bytes).toString();
        }
      }
    }

    // write manifest into zip
    final manifestJson = const JsonEncoder.withIndent('  ').convert(manifest);
    final tmpManifest = File(p.join(dataDir.path, 'backup_manifest.json'));
    await tmpManifest.writeAsString(manifestJson);
    encoder.addFile(tmpManifest, 'backup_manifest.json');
    encoder.close();
    if (await tmpManifest.exists()) await tmpManifest.delete();

    return targetZipPath;
  }

  Future<void> restoreBackup(String zipPath) async {
    final dataDir = await _appDataDir();
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // verify manifest
    final manifestFile = archive.findFile('backup_manifest.json');
    if (manifestFile == null) throw Exception('Archive invalide: manifest manquant.');
    final manifest = jsonDecode(utf8.decode(manifestFile.content as List<int>)) as Map<String, dynamic>;
    final files = (manifest['files'] as Map).cast<String, String>();
    for (final entry in files.entries) {
      final f = archive.findFile(entry.key);
      if (f == null) throw Exception('Fichier manquant dans l\'archive: ${entry.key}');
      final hash = sha256.convert(f.content as List<int>).toString();
      if (hash != entry.value) throw Exception('Intégrité invalide pour ${entry.key} (hash différent).');
    }

    // extract to temp then replace
    final tempDir = Directory(p.join(dataDir.path, '_restore_tmp'));
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await tempDir.create(recursive: true);
    for (final file in archive) {
      if (file.isFile) {
        final outPath = p.join(tempDir.path, file.name);
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      }
    }

    // replace db and attachments
    for (final name in ['ecole.sqlite', 'ecole.sqlite-wal', 'ecole.sqlite-shm']) {
      final src = File(p.join(tempDir.path, name));
      final dst = File(p.join(dataDir.path, name));
      if (await src.exists()) {
        await src.copy(dst.path);
      } else if (await dst.exists() && name != 'ecole.sqlite') {
        // remove stale wal/shm if not in backup
        await dst.delete();
      }
    }
    final srcAttach = Directory(p.join(tempDir.path, 'attachments'));
    final dstAttach = Directory(p.join(dataDir.path, 'attachments'));
    if (await dstAttach.exists()) await dstAttach.delete(recursive: true);
    if (await srcAttach.exists()) {
      await _copyDir(srcAttach, dstAttach);
    }

    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  }

  Future<void> _copyDir(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final ent in src.list(recursive: false, followLinks: false)) {
      final newPath = p.join(dst.path, p.basename(ent.path));
      if (ent is File) {
        await ent.copy(newPath);
      } else if (ent is Directory) {
        await _copyDir(ent, Directory(newPath));
      }
    }
  }
}
